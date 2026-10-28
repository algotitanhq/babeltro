//! The tunnel maps every pixel to polar coordinates once, at resize time.
//! After that the per-pixel work is a couple of table lookups and a palette
//! read: the geometry is free, which is why it can afford to look this good.

use super::{Effect, State};
use crate::canvas::Frame;
use crate::fmath;
use crate::palette::{ICE, Palette};

pub struct Tunnel {
    /// falls off as 1/r: large at the centre, small at the edge
    depth: Vec<f32>,
    /// atan2 as a fraction of a turn, [0, 1)
    angle: Vec<f32>,
    t: f32,
    pal: &'static Palette,
}

impl Tunnel {
    pub fn new() -> Self {
        Tunnel {
            depth: Vec::new(),
            angle: Vec::new(),
            t: 0.0,
            pal: &ICE,
        }
    }
}

impl Effect for Tunnel {
    fn resize(&mut self, w: usize, h: usize) {
        // scale with the diagonal so the rings look the same at any resolution
        let diag = (w + h) as f32;
        self.depth = fmath::dist_inv_table(w, h, diag * 2.2, diag * 0.02);
        self.angle = fmath::atan2_table(w, h);
    }

    fn prepare(&mut self, s: &State) {
        self.t = s.beat as f32;
    }

    fn draw(&mut self, fb: &mut Frame) {
        let sine = fmath::table();
        let pal = self.pal;
        let adv = self.t * 3.0;
        let spin = self.t * 0.25;

        // @excerpt TUNNEL
        // The three buffers have the same length, so one zipped iterator
        // walks them in step with no index and no bounds check at all.
        let pixels = fb.pix.iter_mut().zip(&self.depth).zip(&self.angle);
        for ((px, &depth), &angle) in pixels {
            let u = depth + adv; // scroll towards the viewer

            // rings along the depth axis
            let ring = sine.sin01(u * 0.16);
            // spokes that twist as they recede
            let twist = angle * 12.0 + u * 0.09 + spin;
            let spoke = sine.sin01(twist);

            let mut val = ring * 0.55 + spoke * 0.45;
            // brick checker gives the walls their structure; u and twist are
            // positive and small, so `as` truncates exactly like Go's int()
            if ((u * 0.32) as i32 + twist as i32) & 1 == 1 {
                val = -val * 0.7;
            }

            let fog = 1.0 / (1.0 + u * 0.02);
            let lum = (val * 0.5 + 0.5) * fog;
            // a cold rim on the brightest ridges
            *px = pal[((lum * 300.0) as i32).clamp(0, 255) as usize];
        }
        // @end
    }
}
