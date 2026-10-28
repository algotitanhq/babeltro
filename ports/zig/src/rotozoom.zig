//! Rotozoom: the purest demoscene move. Build a texture once, then every
//! frame rotate and zoom the sampling grid over it. Cost per pixel is a few
//! multiplies and one lookup.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const palette = @import("palette.zig");
const State = @import("fx.zig").State;

const tex_size = 512;
const tex_mask = tex_size - 1;

/// The 1 MiB texture lives in static memory, outside any allocator, and is
/// built the first time the scene starts: it depends on nothing, so every
/// later start reuses it. Its length is part of its type, so the masked index
/// below can never be out of bounds.
var tex: [tex_size * tex_size]u32 = undefined;
var tex_ready = false;

const Rotozoom = @This();

pub fn start(_: *Rotozoom, _: std.mem.Allocator, _: usize, _: usize) !void {
    if (!tex_ready) buildTexture();
    tex_ready = true;
}

/// A tileable rainbow plasma. Building it costs a million sine calls; doing
/// the same work per frame would cost the whole budget, which is the point of
/// the scene. It is not built at comptime: the compiler's interpreter would
/// take minutes over it, and the module would carry the whole megabyte.
fn buildTexture() void {
    const two_pi: f64 = 2 * std.math.pi;
    for (0..tex_size) |y| {
        const fy: f64 = @as(f32, @floatFromInt(y)) / tex_size;
        for (0..tex_size) |x| {
            // Go rounds the coordinates to f32 first, then widens them to f64
            const fx: f64 = @as(f32, @floatFromInt(x)) / tex_size;
            // the pattern has to wrap every 512 pixels, so every frequency is
            // a whole number of cycles per tile
            var v = @sin(fx * two_pi * 3 + fy * two_pi * 2) * 0.5 +
                @sin(fy * two_pi * 5 - fx * two_pi * 4) * 0.3 +
                @sin((fx + fy) * two_pi * 7) * 0.2;
            // concentric rings, also periodic in the tile
            const dx = @as(f64, @floatFromInt(x)) - tex_size / 2;
            const dy = @as(f64, @floatFromInt(y)) - tex_size / 2;
            const rr = @sqrt(dx * dx + dy * dy) / tex_size * 12;
            v += @sin(rr * two_pi) * 0.35;

            // @rem is the truncating remainder, Go's math.Mod
            var hue = @rem(v * 0.55 + 0.5, 1);
            if (hue < 0) hue += 1;
            var c = palette.hslToRgb(hue, 0.70, 0.48 + 0.14 * v);

            // a dark grid over the colour: without a straight edge the
            // rotation and the zoom read as random shimmer instead of motion
            if (x % (tex_size / 8) < 3 or y % (tex_size / 8) < 3) {
                for (&c) |*ch| ch.* *= 0.28;
            }
            tex[y * tex_size + x] = canvas.fromFloat(c[0], c[1], c[2]);
        }
    }
}

pub fn render(_: *Rotozoom, fb: canvas.FB, st: State) void {
    const t: f32 = @floatCast(st.beat);
    const ang = t * 0.45;
    const cos_a = fmath.cos(ang);
    const sin_a = fmath.sin(ang);
    // breathing zoom: 0.7 .. 1.6
    const breath = 0.55 + 0.45 * fmath.sin(t * 0.7) + 0.35;
    const offx = fmath.sin(t * 0.31) * 180 + t * 26;
    const offy = fmath.cos(t * 0.27) * 180 + t * 19;

    const w: f32 = @floatFromInt(fb.w);
    const cx = w * 0.5;
    const cy = @as(f32, @floatFromInt(fb.h)) * 0.5;
    const zoom = breath / w * 6.5;

    // @excerpt ROTOZOOM
    for (0..fb.h) |y| {
        const dy = @as(f32, @floatFromInt(y)) - cy;
        for (fb.row(y), 0..) |*px, x| {
            const dx = @as(f32, @floatFromInt(x)) - cx;
            // `* zoom * 34` stays two multiplies, as in Go: folding them
            // into one constant would round differently
            const tx = (dx * cos_a - dy * sin_a) * zoom * 34;
            const ty = (dx * sin_a + dy * cos_a) * zoom * 34;
            // truncate toward zero first, then wrap: the mask on an i32
            // handles negative coordinates too
            const ix = @as(i32, @intFromFloat(tx + offx)) & tex_mask;
            const iy = @as(i32, @intFromFloat(ty + offy)) & tex_mask;
            px.* = tex[@intCast(iy * tex_size + ix)];
        }
    }
    // @end
}
