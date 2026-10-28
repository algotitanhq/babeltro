//! The Mandelbrot set, diving into the boundary forever. It is the most
//! expensive scene in the demo, so it renders on a coarse grid and stretches
//! the result: at 60 fps in motion nobody can tell.

use super::{Effect, State};
use crate::canvas::Frame;
use crate::palette::{ICE, Palette};

pub struct Mandelbrot {
    pal: &'static Palette,
    cx: f64,
    cy: f64,
    scale: f64,
    max_iter: u32,
    /// block size in pixels
    step: usize,
}

impl Mandelbrot {
    pub fn new() -> Self {
        Mandelbrot {
            pal: &ICE,
            cx: 0.0,
            cy: 0.0,
            scale: 1.0,
            max_iter: 192,
            step: 2,
        }
    }
}

impl Effect for Mandelbrot {
    fn resize(&mut self, w: usize, _h: usize) {
        // keep the block size constant in screen terms as the window grows
        self.step = if w > 1600 { 3 } else { 2 };
    }

    fn prepare(&mut self, s: &State) {
        let u = s.beat.min(14.0) / 12.0;
        // the camera slides onto the target point quickly, then the
        // exponential dive does the work
        let k = 1.0 - (-8.0 * u).exp();
        // the seahorse valley, where the boundary never opens into a flat
        // interior, so the whole frame stays fractal at any depth
        self.scale = 2.9 * (-u * u * 3.6).exp();
        // the deep frames need the iteration budget; the wide ones do not
        self.max_iter = 64 + (128.0 * u) as u32;
        // Go folds -0.743643887037151+0.5 exactly at compile time, Rust
        // rounds the literal first: both give the same f64 for this value
        self.cx = -0.5 + (-0.743643887037151 + 0.5) * k;
        self.cy = 0.0 + 0.131825904205330 * k;
    }

    fn draw(&mut self, fb: &mut Frame) {
        let (w, step) = (fb.w, self.step);
        let asp = fb.h as f64 / w as f64;
        let span = self.scale;
        let x0 = self.cx - span * 0.5;
        let y0 = self.cy - span * 0.5 * asp;
        // units per pixel
        let d = span / w as f64;
        let (max_iter, pal) = (self.max_iter, self.pal);

        // @excerpt MANDELBROT
        // A band is one row of blocks. Compute its first pixel row block by
        // block, then copy that row down over the rest of the band.
        for (by, band) in fb.pix.chunks_mut(w * step).enumerate() {
            let cy = y0 + (by * step) as f64 * d;
            let (first, rest) = band.split_at_mut(w);
            for (bx, block) in first.chunks_mut(step).enumerate() {
                let cx = x0 + (bx * step) as f64 * d;
                let it = mandel_iter(cx, cy, max_iter);
                block.fill(if it >= max_iter {
                    0xFF0A_0812
                } else {
                    // the ramp is anchored to a fixed iteration count, so a
                    // bigger budget for the deep zoom does not darken it all
                    let v = (f64::from(it) / 40.0).sqrt().min(1.0);
                    pal.at(v * 0.92 + 0.04)
                });
            }
            for row in rest.chunks_exact_mut(w) {
                row.copy_from_slice(first);
            }
        }
        // @end
    }
}

/// The escape iteration of c = cx + i·cy, or `max` if it never escapes.
fn mandel_iter(cx: f64, cy: f64, max: u32) -> u32 {
    // cheap escape test for the main cardioid and the period-2 bulb
    let x = cx - 0.25;
    let y2 = cy * cy;
    let q = x * x + y2;
    if q * (q + x) <= 0.25 * y2 || (cx + 1.0) * (cx + 1.0) + y2 <= 0.0625 {
        return max;
    }
    let (mut zx, mut zy) = (0.0, 0.0);
    let (mut zx2, mut zy2) = (0.0, 0.0);
    for i in 0..max {
        zy = 2.0 * zx * zy + cy;
        zx = zx2 - zy2 + cx;
        zx2 = zx * zx;
        zy2 = zy * zy;
        if zx2 + zy2 > 4.0 {
            return i;
        }
    }
    max
}
