//! The purest demoscene move: build a texture once, then every frame rotate
//! and zoom the sampling grid over it. Cost per pixel is a few multiplies and
//! one lookup.

use std::f64::consts::TAU;

use super::{Effect, State};
use crate::canvas::{Frame, from_float};
use crate::fmath;
use crate::palette::hsl_to_rgb;

const TEX_SIZE: usize = 512;
const TEX_MASK: i32 = TEX_SIZE as i32 - 1;

/// A fixed-size array rather than a `Vec`: the compiler then knows its
/// length, and a masked index provably fits, so the lookup needs no check.
type Texture = Box<[u32; TEX_SIZE * TEX_SIZE]>;

pub struct Rotozoom {
    tex: Texture,
    cos_a: f32,
    sin_a: f32,
    zoom: f32,
    offx: f32,
    offy: f32,
}

impl Rotozoom {
    pub fn new() -> Self {
        Rotozoom {
            tex: build_texture(),
            cos_a: 1.0,
            sin_a: 0.0,
            zoom: 1.0,
            offx: 0.0,
            offy: 0.0,
        }
    }
}

/// A tileable rainbow plasma, built once. It costs a few hundred thousand
/// sine calls; doing the same work per frame would cost the whole budget,
/// which is the point of the scene.
fn build_texture() -> Texture {
    let n = TEX_SIZE as f64;
    let mut tex: Texture = vec![0; TEX_SIZE * TEX_SIZE]
        .try_into()
        .expect("texture size");
    for (y, row) in tex.as_chunks_mut::<TEX_SIZE>().0.iter_mut().enumerate() {
        // x/512 is exact in f32, and Go goes through float32 here too
        let fy = f64::from(y as f32 / TEX_SIZE as f32);
        for (x, px) in row.iter_mut().enumerate() {
            let fx = f64::from(x as f32 / TEX_SIZE as f32);
            // the pattern has to wrap every 512 pixels, so every frequency
            // is a whole number of cycles per tile
            let mut v = (fx * TAU * 3.0 + fy * TAU * 2.0).sin() * 0.5
                + (fy * TAU * 5.0 - fx * TAU * 4.0).sin() * 0.3
                + ((fx + fy) * TAU * 7.0).sin() * 0.2;
            // concentric rings, also periodic in the tile
            let dx = x as f64 - n / 2.0;
            let dy = y as f64 - n / 2.0;
            let rr = (dx * dx + dy * dy).sqrt() / n * 12.0;
            v += (rr * TAU).sin() * 0.35;

            // `%` on floats is fmod, like Go's math.Mod: the sign follows v
            let mut hue = (v * 0.55 + 0.5) % 1.0;
            if hue < 0.0 {
                hue += 1.0;
            }
            let (mut r, mut g, mut b) = hsl_to_rgb(hue, 0.70, 0.48 + 0.14 * v);

            // a dark grid over the colour: without a straight edge the
            // rotation and the zoom read as random shimmer instead of motion
            if x % (TEX_SIZE / 8) < 3 || y % (TEX_SIZE / 8) < 3 {
                r *= 0.28;
                g *= 0.28;
                b *= 0.28;
            }
            *px = from_float(r, g, b);
        }
    }
    tex
}

impl Effect for Rotozoom {
    fn resize(&mut self, _w: usize, _h: usize) {}

    fn prepare(&mut self, s: &State) {
        let sine = fmath::table();
        let t = s.beat as f32;
        let ang = t * 0.45;
        self.cos_a = sine.cos(ang);
        self.sin_a = sine.sin(ang);
        // breathing zoom: 0.7 .. 1.6
        self.zoom = 0.55 + 0.45 * sine.sin(t * 0.7) + 0.35;
        self.offx = sine.sin(t * 0.31) * 180.0 + t * 26.0;
        self.offy = sine.cos(t * 0.27) * 180.0 + t * 19.0;
    }

    fn draw(&mut self, fb: &mut Frame) {
        let cx = fb.w as f32 * 0.5;
        let cy = fb.h as f32 * 0.5;
        let (cos_a, sin_a) = (self.cos_a, self.sin_a);
        let zoom = self.zoom / fb.w as f32 * 6.5;
        let (offx, offy) = (self.offx, self.offy);
        let tex = &*self.tex;

        // @excerpt ROTOZOOM
        for (y, row) in fb.pix.chunks_exact_mut(fb.w).enumerate() {
            let dy = y as f32 - cy;
            // the row's share of the rotation, hoisted: the same products
            // the pixel loop would compute, so the same bits
            let (dy_sin, dy_cos) = (dy * sin_a, dy * cos_a);
            for (x, px) in row.iter_mut().enumerate() {
                let dx = x as f32 - cx;
                // not `zoom * 34.0` folded into one constant: floats are not
                // associative, and the Go code multiplies twice
                let tx = (dx * cos_a - dy_sin) * zoom * 34.0;
                let ty = (dx * sin_a + dy_cos) * zoom * 34.0;
                // truncate toward zero, then wrap into the tile with a mask
                let ix = (tx + offx) as i32 & TEX_MASK;
                let iy = (ty + offy) as i32 & TEX_MASK;
                *px = tex[iy as usize * TEX_SIZE + ix as usize];
            }
        }
        // @end
    }
}
