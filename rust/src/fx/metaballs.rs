//! Metaballs sum radial fields and shade the iso-contours. The cheap trick:
//! every pixel evaluates sum(r² / d²) with one division per ball, no square
//! roots, and the contour band gets a hot rim so the blobs read as liquid
//! rather than as a flat gradient.

use super::{Effect, State};
use crate::canvas::Frame;
use crate::fmath;
use crate::palette::{Palette, SUNSET};

const BALLS: usize = 6;

#[derive(Clone, Copy, Default)]
struct Ball {
    /// centre in normalised space, [0, 1] on both axes
    x: f32,
    y: f32,
    radius: f32,
}

pub struct Metaballs {
    balls: [Ball; BALLS],
    pal: &'static Palette,
}

impl Metaballs {
    pub fn new() -> Self {
        Metaballs {
            balls: [Ball::default(); BALLS],
            pal: &SUNSET,
        }
    }
}

impl Effect for Metaballs {
    fn resize(&mut self, _w: usize, _h: usize) {}

    fn prepare(&mut self, s: &State) {
        let sine = fmath::table();
        let t = s.beat as f32;
        for (i, b) in self.balls.iter_mut().enumerate() {
            let fi = i as f32;
            // each ball orbits on its own ellipse and breathes
            let a = t * (0.35 + fi * 0.07) + fi * 2.1;
            b.x = 0.5 + 0.20 * sine.cos(a) * (1.0 + 0.3 * sine.sin(t * 0.5 + fi));
            b.y = 0.5 + 0.20 * sine.sin(a * 1.3 + fi) * (1.0 + 0.3 * sine.cos(t * 0.4 + fi * 2.0));
            b.radius = 0.105 + 0.025 * sine.sin(t * 1.1 + fi * 1.7);
        }
    }

    fn draw(&mut self, fb: &mut Frame) {
        let (w, h) = (fb.w as f32, fb.h as f32);
        let pal = self.pal;
        // x is scaled by width/height so a circle in field space is a circle
        // on screen, whatever the aspect ratio
        let asp = w / h;
        // per ball: centre in screen-shaped field space and r², the field
        // being about 1 on a ball's own surface
        let balls = self
            .balls
            .map(|b| ((b.x - 0.5) * asp, b.y - 0.5, b.radius * b.radius));

        // @excerpt METABALLS
        for (y, row) in fb.pix.chunks_exact_mut(fb.w).enumerate() {
            let fy = y as f32 / h - 0.5;
            for (x, px) in row.iter_mut().enumerate() {
                let fx = (x as f32 / w - 0.5) * asp;
                // six balls in a fixed-size array: a loop of known length
                let field: f32 = balls
                    .iter()
                    .map(|&(bx, by, r2)| {
                        let (dx, dy) = (fx - bx, fy - by);
                        r2 / (dx * dx + dy * dy + 1e-5)
                    })
                    .sum();
                // field is about 1 at the surface of a ball and explodes
                // inside; v/(1+v) compresses that into a usable 0..1 ramp
                let v = field / (1.6 + field);
                // rim: the iso-surface where the balls meet flares white
                let idx = if field > 1.0 && field < 1.09 {
                    255
                } else {
                    ((v * 255.0) as usize).min(255)
                };
                *px = pal[idx];
            }
        }
        // @end
    }
}
