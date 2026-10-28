//! 256-entry colour ramps built from a handful of stops. Effects index these
//! ramps instead of doing per-pixel colour maths, which is the classic
//! demoscene trade: pay once at load, then look up.

use std::ops::Index;
use std::sync::LazyLock;

use crate::canvas::{rgb, unit_to_byte};

/// One colour anchor in a ramp, at position `pos` in [0, 1].
#[derive(Clone, Copy)]
pub struct Stop {
    pos: f64,
    r: f64,
    g: f64,
    b: f64,
}

const fn s(pos: f64, r: f64, g: f64, b: f64) -> Stop {
    Stop { pos, r, g, b }
}

/// A ready-to-index 256-colour ramp.
pub struct Palette([u32; 256]);

impl Palette {
    /// Interpolates the stops into a palette.
    pub fn new(stops: &[Stop]) -> Self {
        let (Some(&first), Some(&last)) = (stops.first(), stops.last()) else {
            return Palette([0; 256]);
        };
        Palette(std::array::from_fn(|i| {
            let t = i as f64 / 255.0;
            // the segment containing t
            let (a, b) = stops
                .windows(2)
                .find(|seg| t >= seg[0].pos && t <= seg[1].pos)
                .map_or((first, last), |seg| (seg[0], seg[1]));
            let u = if b.pos > a.pos {
                (t - a.pos) / (b.pos - a.pos)
            } else {
                0.0
            };
            let u = u.clamp(0.0, 1.0);
            // smoothstep keeps gradients from banding
            let u = u * u * (3.0 - 2.0 * u);
            rgb(
                unit_to_byte(a.r + (b.r - a.r) * u),
                unit_to_byte(a.g + (b.g - a.g) * u),
                unit_to_byte(a.b + (b.b - a.b) * u),
            )
        }))
    }

    /// The colour at position t in [0, 1], clamped.
    pub fn at(&self, t: f64) -> u32 {
        self.0[((t * 255.0) as i32).clamp(0, 255) as usize]
    }
}

impl Index<usize> for Palette {
    type Output = u32;

    fn index(&self, i: usize) -> &u32 {
        &self.0[i]
    }
}

/// HSL (all 0..1) to RGB components 0..1.
pub fn hsl_to_rgb(h: f64, s: f64, l: f64) -> (f64, f64, f64) {
    if s == 0.0 {
        return (l, l, l);
    }
    let q = if l < 0.5 {
        l * (1.0 + s)
    } else {
        l + s - l * s
    };
    let p = 2.0 * l - q;
    (
        hue_to_rgb(p, q, h + 1.0 / 3.0),
        hue_to_rgb(p, q, h),
        hue_to_rgb(p, q, h - 1.0 / 3.0),
    )
}

fn hue_to_rgb(p: f64, q: f64, mut t: f64) -> f64 {
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 1.0 / 6.0 {
        p + (q - p) * 6.0 * t
    } else if t < 1.0 / 2.0 {
        q
    } else if t < 2.0 / 3.0 {
        p + (q - p) * (2.0 / 3.0 - t) * 6.0
    } else {
        p
    }
}

/// Sunset: the demo's signature ramp. Deep violet to hot orange to cream.
pub static SUNSET: LazyLock<Palette> = LazyLock::new(|| {
    Palette::new(&[
        s(0.00, 0.02, 0.00, 0.06),
        s(0.18, 0.25, 0.02, 0.38),
        s(0.38, 0.72, 0.05, 0.45),
        s(0.56, 0.98, 0.25, 0.22),
        s(0.74, 1.00, 0.62, 0.15),
        s(0.88, 1.00, 0.93, 0.55),
        s(1.00, 1.00, 1.00, 0.96),
    ])
});

/// Ice: cold counterpart used by the tunnel and the mandelbrot.
pub static ICE: LazyLock<Palette> = LazyLock::new(|| {
    Palette::new(&[
        s(0.00, 0.00, 0.00, 0.03),
        s(0.25, 0.00, 0.10, 0.30),
        s(0.50, 0.00, 0.55, 0.85),
        s(0.72, 0.35, 0.90, 1.00),
        s(0.90, 0.80, 1.00, 1.00),
        s(1.00, 1.00, 1.00, 1.00),
    ])
});

/// Ember: fire ramp.
pub static EMBER: LazyLock<Palette> = LazyLock::new(|| {
    Palette::new(&[
        s(0.00, 0.00, 0.00, 0.00),
        s(0.20, 0.25, 0.00, 0.00),
        s(0.45, 0.80, 0.10, 0.00),
        s(0.68, 1.00, 0.45, 0.00),
        s(0.85, 1.00, 0.80, 0.15),
        s(1.00, 1.00, 1.00, 0.85),
    ])
});
