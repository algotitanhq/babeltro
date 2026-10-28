//! Four summed sine fields, the oldest trick in the demoscene book. Done
//! naively it is four sin() calls per pixel; here three of the four terms are
//! 1D tables rebuilt once per frame, leaving a single lookup per pixel.

use super::{Effect, State};
use crate::canvas::Frame;
use crate::fmath;
use crate::palette::{Palette, SUNSET};

pub struct Plasma {
    w: usize,
    h: usize,
    /// distance to the centre, per pixel, scaled to the ring frequency
    rad: Vec<f32>,
    /// one sine per column, per row, and per diagonal (x + y)
    sx: Vec<f32>,
    sy: Vec<f32>,
    sxy: Vec<f32>,
    phase: f32,
    pal: &'static Palette,
}

impl Plasma {
    pub fn new() -> Self {
        Plasma {
            w: 0,
            h: 0,
            rad: Vec::new(),
            sx: Vec::new(),
            sy: Vec::new(),
            sxy: Vec::new(),
            phase: 0.0,
            pal: &SUNSET,
        }
    }
}

impl Effect for Plasma {
    fn resize(&mut self, w: usize, h: usize) {
        (self.w, self.h) = (w, h);
        let (cx, cy) = (w as f32 * 0.5, h as f32 * 0.5);
        let k = 44.0 / (w + h) as f32;
        self.rad = (0..h)
            .flat_map(|y| {
                let dy = y as f32 - cy;
                (0..w).map(move |x| {
                    let dx = x as f32 - cx;
                    (dx * dx + dy * dy).sqrt() * k
                })
            })
            .collect();
        self.sx = vec![0.0; w];
        self.sy = vec![0.0; h];
        self.sxy = vec![0.0; w + h];
    }

    fn prepare(&mut self, s: &State) {
        let sine = fmath::table();
        let t = s.beat as f32;
        let kx = 26.0 / self.w as f32;
        let ky = 26.0 / self.h as f32;
        for (x, v) in self.sx.iter_mut().enumerate() {
            *v = sine.sin(x as f32 * kx + t * 1.3);
        }
        for (y, v) in self.sy.iter_mut().enumerate() {
            *v = sine.sin(y as f32 * ky * 1.35 - t * 1.1);
        }
        for (i, v) in self.sxy.iter_mut().enumerate() {
            *v = sine.sin(i as f32 * kx * 0.85 + t * 0.8);
        }
        self.phase = t * 2.6;
    }

    fn draw(&mut self, fb: &mut Frame) {
        let sine = fmath::table();
        let (w, pal, phase) = (fb.w, self.pal, self.phase);

        // @excerpt PLASMA
        // chunks_exact_mut hands out one row at a time; zipping the row with
        // slices of the same length lets the compiler drop every bounds check
        // in the pixel loop.
        let rows = fb.pix.chunks_exact_mut(w).zip(self.rad.chunks_exact(w));
        for (y, (row, rad)) in rows.enumerate() {
            let sy = self.sy[y];
            // the diagonal term for pixel x of row y is sxy[x + y]
            let sxy = &self.sxy[y..y + w];
            let cols = row.iter_mut().zip(rad).zip(&self.sx).zip(sxy);
            for (((px, &rad), &sx), &sxy) in cols {
                let v = sx + sy + sxy + sine.sin(rad + phase);
                *px = pal[((v * 36.0 + 127.5) as i32).clamp(0, 255) as usize];
            }
        }
        // @end
    }
}
