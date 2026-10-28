//! The Doom fire algorithm: a heat buffer seeded at the bottom row and
//! diffused upward with a little random sideways drift. It is integer only,
//! one byte per pixel, and reads beautifully through a palette ramp.

use super::{Effect, State};
use crate::canvas::Frame;
use crate::fmath::{self, Rng};
use crate::palette::{EMBER, Palette};

pub struct Fire {
    w: usize,
    /// heat, one byte per pixel, carried from frame to frame
    heat: Vec<u8>,
    pal: &'static Palette,
    rng: Rng,
    frame: u64,
}

impl Fire {
    pub fn new() -> Self {
        Fire {
            w: 0,
            heat: Vec::new(),
            pal: &EMBER,
            rng: Rng::new(0x9E37_79B9),
            frame: 0,
        }
    }
}

impl Effect for Fire {
    fn resize(&mut self, w: usize, h: usize) {
        self.w = w;
        self.heat = vec![0; w * h];
    }

    fn prepare(&mut self, s: &State) {
        self.frame = s.frame;
    }

    fn draw(&mut self, fb: &mut Frame) {
        let (w, pal) = (self.w, self.pal);
        let t = self.frame as f32 * 0.05;
        let sine = fmath::table();
        // the loops hold the heat buffer and advance the generator together:
        // two disjoint field borrows, which the borrow checker accepts
        let Fire { heat, rng, .. } = self;

        // seed the hottest row: a slow horizontal wave gives the fire its
        // uneven base, the random term keeps the tongues from looking periodic
        let bottom = heat.len() - w;
        for (x, cell) in heat[bottom..].iter_mut().enumerate() {
            let fx = x as f32 / w as f32;
            let wv = 0.5
                + 0.5 * sine.sin(fx * 11.0 + t) * 0.6
                + 0.5 * sine.sin(fx * 23.0 - t * 1.7) * 0.4;
            let v = 150.0 + wv * 90.0 + (rng.next_u32() & 31) as f32 - 16.0;
            *cell = v.clamp(90.0, 255.0) as u8;
        }

        let paint = |pix: &mut [u32], heat: &[u8]| {
            for (px, &v) in pix.iter_mut().zip(heat) {
                *px = pal[usize::from(v)];
            }
        };
        paint(&mut fb.pix[bottom..], &heat[bottom..]);

        // @excerpt FIRE
        // Diffuse upward: every destination pixel takes one value from the
        // row below, offset sideways by a random -1/0/+1. Gather, not
        // scatter, so each pixel is written exactly once.
        //
        // The borrow checker will not hand out a mutable row and a shared row
        // of the same Vec by index; split_at_mut cuts the buffer in two at
        // the source row, which proves they never overlap.
        for y in (1..fb.h).rev() {
            let (above, below) = heat.split_at_mut(y * w);
            let src = &below[..w];
            let dst = &mut above[(y - 1) * w..];
            for (x, d) in dst.iter_mut().enumerate() {
                if src[x] == 0 {
                    *d = 0; // a cold cell costs no random number
                    continue;
                }
                let r = rng.next_u32();
                // x-1, x or x+1, clamped to the row
                let sx = (x + (r % 3) as usize).saturating_sub(1).min(w - 1);
                let decay = (r >> 16 & 1) as u8;
                *d = src[sx].saturating_sub(decay);
            }
            // the row is complete: colour it while it is still in cache
            paint(&mut fb.pix[(y - 1) * w..y * w], dst);
        }
        // @end
    }
}
