//! The closing card: the logo, its reflection, the subtitle and the numbers
//! that make the point.

use super::{Effect, State};
use crate::canvas::{Frame, channels, from_float, pack, text_width};
use crate::fmath::Rng;

/// The language this port is written in: the only words that differ from
/// one port's image to the next.
const LANG: &str = "RUST";
const SUBTITLE: &str = "EVERY PIXEL IS RUST";
/// The punchline under the closing numbers, the same words in every port.
const TAG: &str = "ONE THREAD - NO GPU - NO SHADER";
const LINES: [&str; 3] = ["0 GPU SHADERS", "0 EXTERNAL MODULES", "0 ASSETS ON DISK"];

const TOP_COL: u32 = 0xFFFF_F6E8; // pale cream
const MID_COL: u32 = 0xFF7C_9CFF; // hot rose
const BOT_COL: u32 = 0xFF58_2080; // deep violet

const fn text_height(scale: i32) -> i32 {
    7 * scale
}

/// A fixed background star in normalised coordinates; the finale only needs
/// twinkle, not motion.
struct BgStar {
    x: f32,
    y: f32,
    b: f32,
}

/// Where everything goes, worked out once per frame size.
#[derive(Default)]
struct Layout {
    logo_scale: i32,
    logo_x: i32,
    logo_y: i32,
    text_h: i32,
    /// rows the reflection fades over, below the floor line
    refl_h: i32,
    floor_y: i32,
    sub_scale: i32,
    sub_x: i32,
    sub_y: i32,
    stats_scale: i32,
    stats_y: i32,
    stat_gap: i32,
    tag_scale: i32,
    tag_x: i32,
    tag_y: i32,
    glow_y: f32,
    glow_r: f32,
    /// the rectangle the glow can possibly reach
    box_x: (i32, i32),
    box_y: (i32, i32),
}

pub struct Finale {
    t: f64,
    stars: Vec<BgStar>,
    layout: Layout,
    /// per-column squared distance to the glow centre, in glow radii
    dx2: Vec<f32>,
    /// per-letter wave offsets, reused so a frame allocates nothing
    offs: [i32; LANG.len()],
}

impl Finale {
    pub fn new() -> Self {
        let mut rng = Rng::new(0xF1A1E);
        let stars = (0..260)
            .map(|_| {
                let x = rng.next_f32();
                let y = rng.next_f32();
                let b = 0.15 + rng.next_f32() * 0.85;
                BgStar { x, y, b }
            })
            .collect();
        Finale {
            t: 0.0,
            stars,
            layout: Layout::default(),
            dx2: Vec::new(),
            offs: [0; LANG.len()],
        }
    }
}

impl Effect for Finale {
    fn resize(&mut self, w: usize, h: usize) {
        let (w, h) = (w as i32, h as i32);
        let mut l = Layout {
            sub_scale: (w / 300).max(1),
            stats_scale: (w / 440).max(1),
            ..Layout::default()
        };
        let sub_h = text_height(l.sub_scale);
        l.stat_gap = text_height(l.stats_scale) * 3 / 2;
        l.tag_scale = l.stats_scale + 1;
        let tag_h = text_height(l.tag_scale);

        // No HUD in the lab's frame, so the card has the whole height.
        let gap = h / 48;
        let top = h / 40;
        let bottom = (h as f32 * 0.90) as i32;
        let fixed = sub_h + 3 * l.stat_gap + tag_h + 4 * gap; // all but the wordmark
        // The wordmark is the language's name, from "C" to "JAVASCRIPT", so
        // its scale comes from the room it has rather than from its length.
        // Height: 7 blocks plus a reflection over half of that, 10.5 blocks.
        // Width: never more than 45% of the frame.
        let lim = w * 9 / 20 / text_width(LANG, 1);
        l.logo_scale = ((bottom - top - fixed) * 2 / 21).min(lim).max(3);
        l.text_h = text_height(l.logo_scale);
        l.refl_h = l.text_h / 2;
        l.logo_x = (w - text_width(LANG, l.logo_scale)) / 2;

        let block_h = l.text_h + l.refl_h + fixed;
        l.logo_y = top + (bottom - top - block_h) / 2;
        l.floor_y = l.logo_y + l.text_h;
        l.sub_y = l.floor_y + l.refl_h + gap;
        l.stats_y = l.sub_y + sub_h + gap;
        l.tag_y = l.stats_y + 3 * l.stat_gap + gap;
        l.sub_x = (w - text_width(SUBTITLE, l.sub_scale)) / 2;
        l.tag_x = (w - text_width(TAG, l.tag_scale)) / 2;

        let glow_x = w as f32 * 0.5;
        l.glow_y = l.logo_y as f32 + l.text_h as f32 * 0.55;
        l.glow_r = w as f32 * 0.34;

        // the glow is an ellipse about 1.6x wider than it is tall
        self.dx2 = (0..w)
            .map(|x| {
                let d = (x as f32 - glow_x) / l.glow_r * 1.6;
                d * d
            })
            .collect();
        let span_x = (l.glow_r / 1.6) as i32;
        let span_y = l.glow_r as i32;
        l.box_x = (glow_x as i32 - span_x, glow_x as i32 + span_x);
        l.box_y = (l.glow_y as i32 - span_y, l.glow_y as i32 + span_y);
        self.layout = l;
    }

    fn prepare(&mut self, s: &State) {
        self.t = s.t;
    }

    fn draw(&mut self, fb: &mut Frame) {
        let (w, h) = (fb.w, fb.h);
        let l = &self.layout;
        let t = self.t;

        // --- background, pass 1: a plain vertical ramp, one colour per row ---
        let cy = h as f32 * 0.5;
        let inv_h = 1.0 / h as f32;
        for (y, row) in fb.pix.chunks_exact_mut(w).enumerate() {
            let u = y as f32 * inv_h;
            let ny = (y as f32 - cy) / cy;
            let vig = (1.0 - 0.32 * ny * ny).max(0.45);
            let r = (0.02 + 0.09 * u * u) * vig;
            let g = (0.01 + 0.02 * u) * vig;
            let b = (0.06 + 0.14 * u) * vig;
            row.fill(from_float(f64::from(r), f64::from(g), f64::from(b)));
        }

        // --- background, pass 2: the pool of light, only where it reaches ---
        let ys = l.box_y.0.max(0) as usize..l.box_y.1.min(h as i32).max(0) as usize;
        let xs = l.box_x.0.max(0) as usize..l.box_x.1.min(w as i32).max(0) as usize;
        let pulse = 0.88 + 0.12 * (t * 2.2).sin() as f32;
        for y in ys {
            let dy = (y as f32 - l.glow_y) / l.glow_r;
            let dy2 = dy * dy;
            if dy2 >= 1.0 {
                continue;
            }
            let row = &mut fb.pix[y * w..][xs.clone()];
            for (px, &dx2) in row.iter_mut().zip(&self.dx2[xs.clone()]) {
                let d2 = dx2 + dy2;
                if d2 >= 1.0 {
                    continue;
                }
                let g = 1.0 - d2;
                // g·(g·pulse), Go's `g *= g * pulse`: floats are not
                // associative, so (g·g)·pulse could round differently
                let g = g * (g * pulse);
                // g is in [0, 1): every product below is in range for `as`
                let (r, gg, b) = channels(*px);
                *px = pack(
                    (r + (g * 120.0) as u32).min(255),
                    (gg + (g * 22.0) as u32).min(255),
                    (b + (g * 100.0) as u32).min(255),
                );
            }
        }

        // stars, twinkling slowly
        for (i, s) in self.stars.iter().enumerate() {
            let sx = (s.x * w as f32) as usize;
            let sy = (s.y * h as f32) as usize;
            if sx < w && sy < h {
                let tw = 0.55 + 0.45 * (t * 1.7 + i as f64 * 0.7).sin() as f32;
                fb.additive(sy * w + sx, 0xFF40_306A, (70.0 * s.b * tw) as u8);
            }
        }

        // --- the polished floor line the reflection lands on ---
        if (0..h as i32).contains(&l.floor_y) {
            let cx = w as f32 * 0.5;
            let row = &mut fb.pix[l.floor_y as usize * w..][..w];
            for (x, px) in row.iter_mut().enumerate() {
                let fade = 1.0 - (x as f32 - cx).abs() / (w as f32 * 0.52);
                if fade <= 0.0 {
                    continue;
                }
                let glow = fade * fade * 0.9;
                let (r, g, b) = channels(*px);
                let add = |c: u32, k: f32| (c as f32 + k * glow).min(255.0) as u32;
                *px = pack(add(r, 210.0), add(g, 110.0), add(b, 230.0));
            }
        }

        // @excerpt FINALE
        // --- logo ---
        let scale = l.logo_scale;
        // the letters bounce off the floor line: offsets run from -scale/3
        // (up) to 0 (resting on it), never below, so no letter sinks into
        // its own reflection
        for (i, off) in self.offs.iter_mut().enumerate() {
            *off = (((t * 2.4 + i as f64 * 0.75).sin() - 1.0) * f64::from(scale) / 6.0) as i32;
        }
        let offs = &self.offs;

        // reflection first, so the wordmark sits on top of its own light
        fb.draw_text_reflect(
            l.logo_x,
            l.floor_y,
            LANG,
            scale,
            [TOP_COL, BOT_COL],
            offs,
            125,
            l.refl_h,
        );
        // a one-pixel dark edge keeps the letters off the background
        fb.draw_text_outline(l.logo_x, l.logo_y, LANG, scale, 0xFF20_0A18, offs);
        fb.draw_text_gradient(
            l.logo_x,
            l.logo_y,
            LANG,
            scale,
            [TOP_COL, MID_COL, BOT_COL],
            offs,
            true,
        );
        // @end

        // --- subtitle with rules either side ---
        let sub_w = text_width(SUBTITLE, l.sub_scale);
        let rule = sub_w / 3;
        let ly = l.sub_y + text_height(l.sub_scale) / 2;
        fb.hline(l.sub_x - rule - 14, ly, rule, 0xFF90_50A0);
        fb.hline(l.sub_x + sub_w + 14, ly, rule, 0xFF90_50A0);
        fb.draw_text(l.sub_x, l.sub_y, SUBTITLE, l.sub_scale, 0xFFF0_E0FF);

        // --- closing numbers ---
        let w = w as i32;
        for (i, line) in (0..).zip(LINES) {
            let lw = text_width(line, l.stats_scale);
            fb.draw_text(
                (w - lw) / 2,
                l.stats_y + i * l.stat_gap,
                line,
                l.stats_scale,
                0xFFC0_B0E0,
            );
        }

        // the punchline
        fb.draw_text(l.tag_x, l.tag_y, TAG, l.tag_scale, 0xFFB0_E0FF);
    }
}
