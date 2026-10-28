//! The synthwave staple: an infinite checker floor rushing at the camera
//! under a banded sun. The floor is a per-pixel perspective divide, and the
//! lines come from the fractional part of the world coordinates.

use super::{Effect, State};
use crate::canvas::{Frame, clamp01, from_float};

pub struct Grid {
    t: f32,
    horizon: f32,
    asp: f32,
}

impl Grid {
    pub fn new() -> Self {
        Grid {
            t: 0.0,
            horizon: 0.0,
            asp: 1.0,
        }
    }
}

/// Everything about a floor row that does not depend on x.
struct FloorRow {
    /// world x per screen pixel on this row
    kx: f32,
    /// distance below the horizon, in pixels
    dz: f32,
    /// glow of the line running across the row, and the row's base colour
    line_z: f32,
    fade_x: f32,
    base: (f32, f32, f32),
}

/// The half-width of a line running into the distance, in world units.
const LINE_W_X: f32 = 0.022;

impl Effect for Grid {
    fn resize(&mut self, w: usize, h: usize) {
        self.horizon = h as f32 * 0.52;
        self.asp = h as f32 / w as f32;
    }

    fn prepare(&mut self, s: &State) {
        self.t = s.beat as f32;
    }

    fn draw(&mut self, fb: &mut Frame) {
        let (w, h) = (fb.w as f32, fb.h as f32);
        let horizon = self.horizon;
        let cx = w * 0.5;

        // sun parameters
        let sun_y = horizon - h * 0.13;
        let sun_r = h * 0.16;
        let sun_x = cx;

        for (y, row) in fb.pix.chunks_exact_mut(fb.w).enumerate() {
            let fy = y as f32;

            // everything that depends only on the row is hoisted out of the
            // pixel loop; on the floor that is most of the arithmetic
            let sky = clamp01(f64::from(fy / horizon));
            let sky = (
                (0.03 + 0.18 * sky * sky) as f32,
                (0.01 + 0.05 * sky) as f32,
                (0.08 + 0.22 * sky) as f32,
            );
            let floor = (fy > horizon).then(|| self.floor_row(fy - horizon, h, w));

            // sun: bounding box test first, then the circle only there
            let dyc = fy - sun_y;
            let sun_row = dyc > -sun_r && dyc < sun_r && fy < horizon + 2.0;
            let stripe = sun_row && fy > sun_y - sun_r * 0.45 && (fy as i32) % 9 < 4;
            let u = clamp01(f64::from((fy - (sun_y - sun_r)) / (2.0 * sun_r)));
            let sun = (1.0, (0.95 - 0.7 * u) as f32, (0.25 + 0.55 * u) as f32);

            // @excerpt GRID
            for (x, px) in row.iter_mut().enumerate() {
                let fx = x as f32;
                let (mut r, mut g, mut b) = sky;

                if sun_row && !stripe {
                    let dx = fx - sun_x;
                    if dx > -sun_r && dx < sun_r {
                        let d = (dx * dx + dyc * dyc).sqrt();
                        if d < sun_r {
                            let edge = clamp01(f64::from((sun_r - d) / (sun_r * 0.025))) as f32;
                            r = mix(r, sun.0, edge);
                            g = mix(g, sun.1, edge);
                            b = mix(b, sun.2, edge);
                        }
                    }
                }

                if let Some(f) = &floor {
                    // How far this ray slides sideways between one row and
                    // the next, in pixels: x = (k-0.37)/kx + cx, so
                    // dx/dy = |x-cx|/dz. The line must be at least that wide,
                    // and dimmed by the same ratio, or each row shows a
                    // handful of isolated bright dots instead of a line.
                    let slide = (fx - cx).abs() / f.dz;
                    let w_px = (2.0 * LINE_W_X / f.kx).max(slide).max(1.0);
                    let line_x = line_glow(wrap01((fx - cx) * f.kx + 0.37), w_px * f.kx * 0.5)
                        * (2.0 * LINE_W_X / f.kx / w_px)
                        * f.fade_x;
                    let line = line_x.max(f.line_z);
                    r = f.base.0 - 0.55 * f.line_z + 0.55 * line;
                    g = f.base.1 - 0.35 * f.line_z + 0.35 * line;
                    b = f.base.2 - 0.75 * f.line_z + 0.75 * line;
                }

                *px = from_float(f64::from(r), f64::from(g), f64::from(b));
            }
            // @end
        }
    }
}

impl Grid {
    /// The row constants of a floor row `dz` pixels below the horizon.
    fn floor_row(&self, dz: f32, h: f32, w: f32) -> FloorRow {
        let z = (h * 0.55) / dz;
        let wz = z * 2.5 + self.t * 5.5;
        let kx = z / (w * 0.5) * self.asp * 2.0;
        // same aliasing guard as below, but across the row
        let fade_x = clamp01(f64::from((1.0 / kx - 1.5) / 2.0)) as f32;

        // A line narrower than a pixel lands on only every few pixels and
        // reads as a row of bright dots. Widen it to a full pixel and dim it
        // by the area it actually covers: the same light, spread out, which
        // is what the eye integrates anyway.
        let period = dz * dz / (1.375 * h); // pixels per unit of wz
        let mut lw_z = 0.014 + 0.024 / z;
        let mut amp_z = 1.0;
        let min_w = 0.5 / period;
        if lw_z < min_w {
            amp_z = lw_z / min_w;
            lw_z = min_w;
        }
        let mut line_z = line_glow(wrap01(wz), lw_z) * amp_z;
        // fade lines that have shrunk below a couple of pixels per period,
        // otherwise the horizon boils with aliasing
        line_z *= clamp01(f64::from((period - 1.5) / 2.0)) as f32;
        line_z *= clamp01(f64::from(1.0 / (1.0 + z * z * 0.004))) as f32;

        let (mut r, mut g, mut b) = (0.02, 0.01, 0.06);
        let haze = clamp01(f64::from(dz / (h * 0.12)));
        if haze < 1.0 {
            // the haze itself is the glow near the horizon
            r += (0.25 * (1.0 - haze)) as f32;
            g += (0.05 * (1.0 - haze)) as f32;
            b += (0.35 * (1.0 - haze)) as f32;
        }
        r += 0.55 * line_z;
        g += 0.35 * line_z;
        b += 0.75 * line_z;

        FloorRow {
            kx,
            dz,
            line_z,
            fade_x,
            base: (r, g, b),
        }
    }
}

/// Wraps a world coordinate into [0, 1). `fract` keeps the sign of v, as
/// Go's `v - float32(int(v))` does, and needs no float-to-int round trip.
fn wrap01(v: f32) -> f32 {
    let m = v.fract();
    if m < 0.0 { m + 1.0 } else { m }
}

/// 1 on the grid line, falling to 0 over width w.
fn line_glow(f: f32, w: f32) -> f32 {
    let d = if f > 0.5 { 1.0 - f } else { f };
    if d < w { 1.0 - d / w } else { 0.0 }
}

fn mix(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}
