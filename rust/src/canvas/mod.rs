//! The software framebuffer every effect draws into.
//!
//! Pixels are packed as `0xAABBGGRR` in a `u32`, which in little-endian
//! memory is R, G, B, A: exactly an `ImageData` buffer, so the host copies a
//! frame to the screen without converting it.

mod text;

pub use text::text_width;

/// Packs an opaque colour into the framebuffer's `u32` layout.
pub const fn rgb(r: u8, g: u8, b: u8) -> u32 {
    0xFF00_0000 | (b as u32) << 16 | (g as u32) << 8 | r as u32
}

/// Splits a packed colour into its red, green and blue channels.
pub const fn channels(c: u32) -> (u32, u32, u32) {
    (c & 0xFF, c >> 8 & 0xFF, c >> 16 & 0xFF)
}

/// Packs channels already known to be in 0..=255.
pub const fn pack(r: u32, g: u32, b: u32) -> u32 {
    0xFF00_0000 | b << 16 | g << 8 | r
}

/// Packs normalised floats into a colour, clamping to [0, 1].
pub fn from_float(r: f64, g: f64, b: f64) -> u32 {
    rgb(unit_to_byte(r), unit_to_byte(g), unit_to_byte(b))
}

/// Maps [0, 1] to 0..=255, rounding to nearest. The comparisons come first:
/// in range, `as u8` truncates exactly like Go's `uint8()`.
pub fn unit_to_byte(v: f64) -> u8 {
    if v <= 0.0 {
        0
    } else if v >= 1.0 {
        255
    } else {
        (v * 255.0 + 0.5) as u8
    }
}

/// Clamps a float to [0, 1] (NaN passes through, as in Go's `Clamp01`).
pub fn clamp01(v: f64) -> f64 {
    v.clamp(0.0, 1.0)
}

/// A linear RGBA framebuffer, row-major, top row first.
pub struct Frame {
    pub w: usize,
    pub h: usize,
    pub pix: Vec<u32>,
}

impl Frame {
    pub fn new(w: usize, h: usize) -> Self {
        Frame {
            w,
            h,
            pix: vec![0; w * h],
        }
    }

    /// Adds `c` scaled by intensity/255 to pixel `i`, saturating.
    pub fn additive(&mut self, i: usize, c: u32, intensity: u8) {
        if intensity == 0 {
            return;
        }
        let k = u32::from(intensity);
        let (pr, pg, pb) = channels(self.pix[i]);
        let (cr, cg, cb) = channels(c);
        self.pix[i] = pack(
            (pr + cr * k / 255).min(255),
            (pg + cg * k / 255).min(255),
            (pb + cb * k / 255).min(255),
        );
    }

    /// Draws a 1px horizontal line, clipped to the frame.
    pub fn hline(&mut self, x: i32, y: i32, len: i32, c: u32) {
        if y < 0 || y >= self.h as i32 {
            return;
        }
        let x0 = x.max(0);
        let x1 = (x + len).min(self.w as i32);
        if x0 < x1 {
            let row = y as usize * self.w;
            self.pix[row + x0 as usize..row + x1 as usize].fill(c);
        }
    }
}
