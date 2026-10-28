//! A warp-speed star tunnel: stars live in 3D, get projected in perspective
//! and dragged into short streaks. The streak is what sells the speed, so
//! each star draws from its previous depth to its current one.

use super::{Effect, State};
use crate::canvas::{Frame, channels, from_float, pack};
use crate::fmath::Rng;

const STARS: usize = 1600;

#[derive(Clone, Copy, Default)]
struct Star {
    x: f32,
    y: f32,
    z: f32,
}

/// A star projected to the screen: a streak from its tail to its head.
#[derive(Clone, Copy, Default)]
struct Streak {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,
    c: u32,
}

pub struct Starfield {
    w: usize,
    h: usize,
    stars: Vec<Star>,
    streaks: Vec<Streak>,
    /// precomputed backdrop: it never changes, so build it once
    backdrop: Vec<u32>,
    rng: Rng,
}

impl Starfield {
    pub fn new() -> Self {
        let mut rng = Rng::new(0x6005E);
        let stars = (0..STARS)
            .map(|_| {
                // one statement per draw: the order of the random calls is
                // part of the image
                let x = (rng.next_f32() * 2.0 - 1.0) * 1.6;
                let y = (rng.next_f32() * 2.0 - 1.0) * 1.6;
                let z = rng.next_f32() * 40.0 + 0.2;
                Star { x, y, z }
            })
            .collect();
        Starfield {
            w: 0,
            h: 0,
            stars,
            streaks: vec![Streak::default(); STARS],
            backdrop: Vec::new(),
            rng,
        }
    }
}

impl Effect for Starfield {
    /// Paints the deep-navy vignette once per size change. Copying a ready
    /// frame is two orders of magnitude cheaper than evaluating it per pixel
    /// per frame, and this is the trick the rest of the demo leans on too.
    fn resize(&mut self, w: usize, h: usize) {
        (self.w, self.h) = (w, h);
        self.backdrop.resize(w * h, 0);
        for (y, row) in self.backdrop.chunks_exact_mut(w).enumerate() {
            let dy = y as f64 / h as f64 - 0.5;
            for (x, px) in row.iter_mut().enumerate() {
                let dx = x as f64 / w as f64 - 0.5;
                let v = dx * dx + dy * dy;
                // from_float clamps the negatives of the far corners to 0
                *px = from_float(0.02 - v * 0.03, 0.02 - v * 0.025, 0.05 - v * 0.03);
            }
        }
    }

    fn prepare(&mut self, s: &State) {
        let (cx, cy) = (self.w as f32 * 0.5, self.h as f32 * 0.5);
        let zoom = self.w as f32 * 0.78;
        // accelerate over the scene so the entry has a kick
        let speed = (2.5 + s.beat.min(3.0) * 4.0) as f32;
        let dz = speed * (s.dt as f32).min(0.1);

        // @excerpt STARFIELD
        for (p, out) in self.stars.iter_mut().zip(&mut self.streaks) {
            p.z -= dz;
            if p.z < 0.8 {
                p.z += 40.0;
                p.x = (self.rng.next_f32() * 2.0 - 1.0) * 1.1;
                p.y = (self.rng.next_f32() * 2.0 - 1.0) * 1.1;
            }
            let f = 1.0 / p.z;
            let f2 = 1.0 / (p.z + dz * 2.4);

            // brighter and bluer as the star gets close
            let near = 1.0 - p.z / 40.0;
            let b = near * near;
            let r = (120.0 * b + 40.0) as u32;
            let g = (190.0 * b + 40.0) as u32;
            let bl = (255.0 * (0.25 + 0.75 * b)) as u32;
            // z ≥ 0.8 keeps every coordinate well inside i32, where `as`
            // truncates exactly like Go's int32()
            *out = Streak {
                x0: (cx + p.x * f * zoom) as i32,
                y0: (cy + p.y * f * zoom) as i32,
                x1: (cx + p.x * f2 * zoom) as i32,
                y1: (cy + p.y * f2 * zoom) as i32,
                c: pack(r, g, bl),
            };
        }
        // @end
    }

    fn draw(&mut self, fb: &mut Frame) {
        fb.pix.copy_from_slice(&self.backdrop);
        let (w, h) = (fb.w as i32, fb.h as i32);
        for p in &self.streaks {
            // additive line from the trailing point to the head
            draw_line_add(fb, (p.x0, p.y0), (p.x1, p.y1), p.c);
            // bright head pixel
            if (0..w).contains(&p.x1) && (0..h).contains(&p.y1) {
                fb.pix[(p.y1 * w + p.x1) as usize] = 0xFFCC_EEFF;
            }
        }
    }
}

/// Draws a Bresenham line adding colour, so overlapping stars accumulate
/// brightness instead of replacing each other.
fn draw_line_add(fb: &mut Frame, (mut x0, mut y0): (i32, i32), (x1, y1): (i32, i32), c: u32) {
    let (w, h) = (fb.w as i32, fb.h as i32);
    let dx = (x1 - x0).abs();
    let dy = -(y1 - y0).abs();
    let sx = if x0 < x1 { 1 } else { -1 };
    let sy = if y0 < y1 { 1 } else { -1 };
    let (cr, cg, cb) = channels(c);
    let mut err = dx + dy;
    loop {
        if (0..w).contains(&x0) && (0..h).contains(&y0) {
            let px = &mut fb.pix[(y0 * w + x0) as usize];
            let (r, g, b) = channels(*px);
            *px = pack((r + cr).min(255), (g + cg).min(255), (b + cb).min(255));
        }
        if x0 == x1 && y0 == y1 {
            break;
        }
        let e2 = 2 * err;
        if e2 >= dy {
            err += dy;
            x0 += sx;
        }
        if e2 <= dx {
            err += dx;
            y0 += sy;
        }
    }
}
