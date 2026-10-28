//! Fire: the Doom fire algorithm. A heat buffer is seeded at the bottom row
//! and diffused upward with a little random sideways drift. It is integer
//! only, one byte per pixel, and reads beautifully through a palette ramp.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const palette = @import("palette.zig");
const State = @import("fx.zig").State;

buf: []u8, // heat, one byte per pixel; it carries over from frame to frame
rng: fmath.Rng, // the same xorshift32 as everywhere, with the fire's own seed

const Fire = @This();

pub fn start(f: *Fire, arena: std.mem.Allocator, w: usize, h: usize) !void {
    f.buf = try arena.alloc(u8, w * h);
    @memset(f.buf, 0);
    f.rng = .{ .state = 0x9E3779B9 };
}

pub fn render(f: *Fire, fb: canvas.FB, st: State) void {
    const w = fb.w;
    const h = fb.h;
    const buf = f.buf;
    const pal = &palette.ember;

    // seed the hottest row: a slow horizontal wave gives the fire its uneven
    // base, the random term keeps the tongues from looking periodic
    const last = buf[(h - 1) * w ..][0..w];
    const t = @as(f32, @floatFromInt(st.frame)) * 0.05;
    const fw: f32 = @floatFromInt(w);
    for (last, 0..) |*heat, x| {
        const fx = @as(f32, @floatFromInt(x)) / fw;
        const wv = 0.5 + 0.5 * fmath.sin(fx * 11 + t) * 0.6 + 0.5 * fmath.sin(fx * 23 - t * 1.7) * 0.4;
        const v = 150 + wv * 90 + @as(f32, @floatFromInt(f.rng.next() & 31)) - 16;
        heat.* = @intFromFloat(std.math.clamp(v, 90, 255));
    }
    for (fb.row(h - 1), last) |*px, heat| px.* = pal[heat];

    // diffuse upward: every destination pixel takes one value from the row
    // below, offset sideways by a random -1/0/+1. Gather, not scatter, so
    // each pixel is written exactly once: no holes, no salt-and-pepper noise.
    // The palette lookup for a row happens as soon as that row is complete,
    // so the buffer is touched once per frame instead of twice.
    // @excerpt FIRE
    var y = h - 1;
    while (y > 0) : (y -= 1) {
        const src = buf[y * w ..][0..w];
        const dst = buf[(y - 1) * w ..][0..w];
        for (dst, src, 0..) |*d, s, x| {
            if (s == 0) {
                d.* = 0;
                continue;
            }
            const r = f.rng.next();
            // -1, 0 or +1 with no sideways bias, clamped to the row
            const sx = std.math.clamp(@as(isize, @intCast(x + r % 3)) - 1, 0, @as(isize, @intCast(w - 1)));
            // -| is saturating subtraction: heat never wraps below zero
            d.* = src[@intCast(sx)] -| @as(u8, @intCast(r >> 16 & 1));
        }
        for (fb.row(y - 1), dst) |*px, heat| px.* = pal[heat];
    }
    // @end
}
