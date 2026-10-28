//! Plasma: four summed sine fields, the oldest trick in the demoscene book.
//! Done naively it is four sines per pixel; here three of the four terms are
//! 1D tables rebuilt once per frame, leaving a single lookup per pixel.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const palette = @import("palette.zig");
const State = @import("fx.zig").State;

rad: []f32, // distance to the centre, per pixel, built once
sx: []f32, // one entry per column
sy: []f32, // one entry per row
sxy: []f32, // the diagonal term, indexed by x + y

const Plasma = @This();

pub fn start(p: *Plasma, arena: std.mem.Allocator, w: usize, h: usize) !void {
    p.rad = try arena.alloc(f32, w * h);
    p.sx = try arena.alloc(f32, w);
    p.sy = try arena.alloc(f32, h);
    p.sxy = try arena.alloc(f32, w + h);
    const cx = @as(f32, @floatFromInt(w)) * 0.5;
    const cy = @as(f32, @floatFromInt(h)) * 0.5;
    const k = 44.0 / @as(f32, @floatFromInt(w + h));
    for (0..h) |y| {
        const dy = @as(f32, @floatFromInt(y)) - cy;
        for (p.rad[y * w ..][0..w], 0..) |*r, x| {
            const dx = @as(f32, @floatFromInt(x)) - cx;
            r.* = fmath.sqrt(dx * dx + dy * dy) * k;
        }
    }
}

pub fn render(p: *Plasma, fb: canvas.FB, st: State) void {
    const w = fb.w;
    const t: f32 = @floatCast(st.beat);
    const kx = 26.0 / @as(f32, @floatFromInt(w));
    const ky = 26.0 / @as(f32, @floatFromInt(fb.h));
    for (p.sx, 0..) |*v, x| v.* = fmath.sin(@as(f32, @floatFromInt(x)) * kx + t * 1.3);
    for (p.sy, 0..) |*v, y| v.* = fmath.sin(@as(f32, @floatFromInt(y)) * ky * 1.35 - t * 1.1);
    for (p.sxy, 0..) |*v, i| v.* = fmath.sin(@as(f32, @floatFromInt(i)) * kx * 0.85 + t * 0.8);
    const phase = t * 2.6;
    const pal = &palette.sunset;

    // @excerpt PLASMA
    for (p.sy, 0..) |sy, y| {
        // Go's sxy[y : y+w] is sxy[y..][0..w] here. The for loop over four
        // slices checks once that their lengths agree, then needs no
        // per-pixel bounds check
        const row = fb.row(y);
        const rad = p.rad[y * w ..][0..w];
        const sxy = p.sxy[y..][0..w];
        for (row, p.sx, rad, sxy) |*px, sx, r, sd| {
            const v = sx + sy + sd + fmath.sin(r + phase);
            const i: u8 = @intFromFloat(std.math.clamp(v * 36 + 127.5, 0, 255));
            px.* = pal[i];
        }
    }
    // @end
}
