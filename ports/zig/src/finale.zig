//! Finale: the closing card. The logo, its reflection, the subtitle and the
//! numbers that make the point, over a glowing backdrop with a few
//! twinkling stars. The browser lab draws no HUD in the frame, so the card
//! composes over the full height.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const State = @import("fx.zig").State;

/// The language this port is written in, and the only words that differ
/// from the other ports. It comes from build.zig (`-Dlang=...`, "ZIG" by
/// default) as a comptime string, so the subtitle below is joined by the
/// compiler and the offsets array has the name's length in its type.
const lang: []const u8 = @import("config").lang;
const sub = "EVERY PIXEL IS " ++ lang;
const tag = "ONE THREAD - NO GPU - NO SHADER";
const lines = [3][]const u8{ "0 GPU SHADERS", "0 EXTERNAL MODULES", "0 ASSETS ON DISK" };

const n_stars = 260;

/// A fixed background star in normalised coordinates: the finale only needs
/// twinkle, not motion.
const BgStar = struct { x: f32, y: f32, b: f32 };

stars: [n_stars]BgStar,

logo_scale: i32,
logo_x: i32,
logo_y: i32,
text_h: i32,
refl_h: i32, // rows the reflection fades over, below the floor line
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

offs: [lang.len]i32, // per-letter wave offsets

glow_x: f32,
glow_y: f32,
glow_r: f32,
// per-column squared distance to the glow centre, in glow radii, and the
// rectangle the glow can possibly reach
dx2: []f32,
box_x0: i32,
box_x1: i32,
box_y0: i32,
box_y1: i32,

const Finale = @This();

pub fn start(f: *Finale, arena: std.mem.Allocator, w_u: usize, h_u: usize) !void {
    const w: i32 = @intCast(w_u);
    const h: i32 = @intCast(h_u);

    var rng: fmath.Rng = .{ .state = 0xF1A1E };
    for (&f.stars) |*s| {
        // three draws, in this order
        const x = rng.float();
        const y = rng.float();
        const b = 0.15 + rng.float() * 0.85;
        s.* = .{ .x = x, .y = y, .b = b };
    }

    f.sub_scale = @max(@divTrunc(w, 300), 1);
    const sub_h = canvas.textHeight(f.sub_scale);
    f.stats_scale = @max(@divTrunc(w, 440), 1);
    f.stat_gap = @divTrunc(canvas.textHeight(f.stats_scale) * 3, 2);
    f.tag_scale = f.stats_scale + 1;
    const tag_h = canvas.textHeight(f.tag_scale);

    const gap = @divTrunc(h, 48);
    const top = @divTrunc(h, 40);
    const bottom: i32 = @intFromFloat(@as(f32, @floatFromInt(h)) * 0.90);
    const fixed = sub_h + 3 * f.stat_gap + tag_h + 4 * gap; // all but the wordmark
    // The wordmark's scale comes from the room it has rather than from its
    // length. Height: the glyph is 7 blocks and its reflection fades over
    // half of that, so it needs 10.5 blocks. Width: never more than 45% of
    // the frame, which only binds for long names.
    const lim = @divTrunc(@divTrunc(w * 9, 20), canvas.textWidth(lang.len, 1));
    f.logo_scale = @max(@min(@divTrunc((bottom - top - fixed) * 2, 21), lim), 3);
    const logo_w = canvas.textWidth(lang.len, f.logo_scale);
    f.text_h = canvas.textHeight(f.logo_scale);
    f.refl_h = @divTrunc(f.text_h, 2);
    f.logo_x = @divTrunc(w - logo_w, 2);

    const block_h = f.text_h + f.refl_h + fixed;
    f.logo_y = top + @divTrunc(bottom - top - block_h, 2);
    f.floor_y = f.logo_y + f.text_h;
    f.sub_y = f.floor_y + f.refl_h + gap;
    f.stats_y = f.sub_y + sub_h + gap;
    f.tag_y = f.stats_y + 3 * f.stat_gap + gap;
    f.sub_x = @divTrunc(w - canvas.textWidth(sub.len, f.sub_scale), 2);
    f.tag_x = @divTrunc(w - canvas.textWidth(tag.len, f.tag_scale), 2);

    const fw: f32 = @floatFromInt(w);
    f.glow_x = fw * 0.5;
    f.glow_y = @as(f32, @floatFromInt(f.logo_y)) + @as(f32, @floatFromInt(f.text_h)) * 0.55;
    f.glow_r = fw * 0.34;

    // the glow is an ellipse about 1.6x wider than it is tall
    f.dx2 = try arena.alloc(f32, w_u);
    for (f.dx2, 0..) |*v, x| {
        const d = (@as(f32, @floatFromInt(x)) - f.glow_x) / f.glow_r * 1.6;
        v.* = d * d;
    }
    const span_x: i32 = @intFromFloat(f.glow_r / 1.6);
    const span_y: i32 = @intFromFloat(f.glow_r);
    const gx: i32 = @intFromFloat(f.glow_x);
    const gy: i32 = @intFromFloat(f.glow_y);
    f.box_x0 = gx - span_x;
    f.box_x1 = gx + span_x;
    f.box_y0 = gy - span_y;
    f.box_y1 = gy + span_y;
}

pub fn render(f: *Finale, fb: canvas.FB, st: State) void {
    const t = st.t;
    const w: i32 = @intCast(fb.w);
    const h: i32 = @intCast(fb.h);
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    const cx = fw * 0.5;
    const cy = fh * 0.5;

    // --- background, pass 1: a plain vertical ramp, one colour per row ---
    const inv_h = 1 / fh;
    for (0..fb.h) |y| {
        const fy: f32 = @floatFromInt(y);
        const u = fy * inv_h;
        const ny = (fy - cy) / cy;
        const vig = @max(1 - 0.32 * ny * ny, 0.45);
        const r = (0.02 + 0.09 * u * u) * vig;
        const g = (0.01 + 0.02 * u) * vig;
        const b = (0.06 + 0.14 * u) * vig;
        @memset(fb.row(y), canvas.fromFloat(r, g, b));
    }

    // --- background, pass 2: the pool of light, only where it reaches ---
    const by0: usize = @intCast(@max(f.box_y0, 0));
    const by1: usize = @intCast(@max(@min(f.box_y1, h), 0));
    const bx0: usize = @intCast(@max(f.box_x0, 0));
    const bx1: usize = @intCast(@max(@min(f.box_x1, w), 0));
    const pulse = 0.88 + 0.12 * @as(f32, @floatCast(@sin(t * 2.2)));
    for (by0..by1) |y| {
        const dy = (@as(f32, @floatFromInt(y)) - f.glow_y) / f.glow_r;
        const dy2 = dy * dy;
        if (dy2 >= 1) continue;
        const row = fb.row(y);
        for (bx0..bx1) |x| {
            const d2 = f.dx2[x] + dy2;
            if (d2 >= 1) continue;
            var g = 1 - d2;
            g *= g * pulse;
            const p = row[x];
            const r = @min((p & 0xFF) + @as(u32, @intFromFloat(g * 120)), 255);
            const gg = @min((p >> 8 & 0xFF) + @as(u32, @intFromFloat(g * 22)), 255);
            const b = @min((p >> 16 & 0xFF) + @as(u32, @intFromFloat(g * 100)), 255);
            row[x] = canvas.rgb(r, gg, b);
        }
    }

    // stars, twinkling slowly
    for (&f.stars, 0..) |s, i| {
        const sx: i32 = @intFromFloat(s.x * fw);
        const sy: i32 = @intFromFloat(s.y * fh);
        if (sy < 0 or sy >= h or sx < 0 or sx >= w) continue;
        const tw = 0.55 + 0.45 * @as(f32, @floatCast(@sin(t * 1.7 + @as(f64, @floatFromInt(i)) * 0.7)));
        fb.additive(@intCast(sy * w + sx), 0xFF40306A, @intFromFloat(70 * s.b * tw));
    }

    // --- the polished floor line the reflection lands on ---
    if (f.floor_y >= 0 and f.floor_y < h) {
        for (fb.row(@intCast(f.floor_y)), 0..) |*px, x| {
            const fade = 1 - @abs(@as(f32, @floatFromInt(x)) - cx) / (fw * 0.52);
            if (fade <= 0) continue;
            const glow = fade * fade * 0.9;
            const p = px.*;
            const r = @min(@as(f32, @floatFromInt(p & 0xFF)) + 210 * glow, 255);
            const g = @min(@as(f32, @floatFromInt(p >> 8 & 0xFF)) + 110 * glow, 255);
            const b = @min(@as(f32, @floatFromInt(p >> 16 & 0xFF)) + 230 * glow, 255);
            px.* = canvas.rgb(@intFromFloat(r), @intFromFloat(g), @intFromFloat(b));
        }
    }

    // @excerpt FINALE
    // --- logo ---
    const scale = f.logo_scale;
    // the letters bounce off the floor line: offsets run from -scale/3 (up)
    // to 0 (resting on it), never below, so no letter sinks into its own
    // reflection
    for (&f.offs, 0..) |*o, i| {
        const wave = @sin(t * 2.4 + @as(f64, @floatFromInt(i)) * 0.75) - 1;
        o.* = @intFromFloat(wave * @as(f64, @floatFromInt(scale)) / 6);
    }

    const top_col: u32 = 0xFFFFF6E8; // pale cream
    const mid_col: u32 = 0xFF7C9CFF; // hot rose
    const bot_col: u32 = 0xFF582080; // deep violet

    // reflection first, so the wordmark sits on top of its own light
    fb.drawTextReflect(f.logo_x, f.floor_y, lang, scale, top_col, bot_col, &f.offs, 125, f.refl_h);
    // a one-pixel dark edge keeps the letters off the background
    fb.drawTextOutline(f.logo_x, f.logo_y, lang, scale, 0xFF200A18, &f.offs);
    fb.drawTextGradient(f.logo_x, f.logo_y, lang, scale, top_col, mid_col, bot_col, &f.offs, true);
    // @end

    // --- subtitle with rules either side ---
    const sub_w = canvas.textWidth(sub.len, f.sub_scale);
    const line_len = @divTrunc(sub_w, 3);
    const ly = f.sub_y + @divTrunc(canvas.textHeight(f.sub_scale), 2);
    fb.hline(f.sub_x - line_len - 14, ly, line_len, 0xFF9050A0);
    fb.hline(f.sub_x + sub_w + 14, ly, line_len, 0xFF9050A0);
    fb.drawText(f.sub_x, f.sub_y, sub, f.sub_scale, 0xFFF0E0FF);

    // --- closing numbers ---
    for (lines, 0..) |l, i| {
        const y = f.stats_y + @as(i32, @intCast(i)) * f.stat_gap;
        const lw = canvas.textWidth(l.len, f.stats_scale);
        fb.drawText(@divTrunc(w - lw, 2), y, l, f.stats_scale, 0xFFC0B0E0);
    }

    // the punchline
    fb.drawText(f.tag_x, f.tag_y, tag, f.tag_scale, 0xFFB0E0FF);
}
