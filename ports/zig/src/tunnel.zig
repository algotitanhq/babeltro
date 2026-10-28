//! Tunnel: every pixel is mapped to polar coordinates once, at start. After
//! that the per-pixel work is a couple of table lookups and a palette read:
//! the geometry is free, which is why it can afford to look this good.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const palette = @import("palette.zig");
const State = @import("fx.zig").State;

depth: []f32, // falls off as 1/r: large at the centre, small at the edge
angle: []f32, // atan2 as a fraction of a turn, [0,1)
step: i32, // the ladder: 1 computes the geometry per pixel, 2 and 0 read the tables

const Tunnel = @This();

pub fn start(t: *Tunnel, arena: std.mem.Allocator, w: usize, h: usize) !void {
    t.step = 0;
    t.depth = try arena.alloc(f32, w * h);
    t.angle = try arena.alloc(f32, w * h);
    // scale with the diagonal so the rings look the same at any resolution
    const diag: f32 = @floatFromInt(w + h);
    fmath.distInvTable(t.depth, w, h, diag * 2.2, diag * 0.02);
    fmath.atan2Table(t.angle, w, h);
}

pub fn setStep(t: *Tunnel, n: i32) void {
    t.step = n;
}

pub fn render(t: *Tunnel, fb: canvas.FB, st: State) void {
    if (t.step == 1) return drawDirect(fb, st);
    const pal = &palette.ice;
    const tm: f32 = @floatCast(st.beat);
    const adv = tm * 3.0;
    const spin = tm * 0.25;

    // @excerpt TUNNEL
    // The tables have the framebuffer's layout, so one multi-object for loop
    // walks all three in step: equal lengths are asserted once, up front,
    // instead of a bounds check per pixel.
    for (fb.pix, t.depth, t.angle) |*px, depth, v| {
        const u = depth + adv; // scroll towards the viewer

        // rings along the depth axis
        const ring = fmath.sin01(u * 0.16);
        // spokes that twist as they recede
        const twist = v * 12 + u * 0.09 + spin;
        const spoke = fmath.sin01(twist);

        var val = ring * 0.55 + spoke * 0.45;
        // brick checker gives the walls their structure
        const brick = @as(i32, @intFromFloat(u * 0.32)) + @as(i32, @intFromFloat(twist));
        if (brick & 1 == 1) val = -val * 0.7;

        const fog = 1 / (1 + u * 0.02);
        const lum = (val * 0.5 + 0.5) * fog;
        // clamp in float, then convert: the conversion is always in range
        const idx: u8 = @intFromFloat(std.math.clamp(lum * 300, 0, 255));
        px.* = pal[idx];
    }
    // @end
}

/// The tunnel without its tables: a square root, a division and an atan2 per
/// pixel, every frame, for values that never change. The formulas are the
/// ones the tables are built from, so the pixels are the same; only the time
/// differs.
fn drawDirect(fb: canvas.FB, st: State) void {
    const pal = &palette.ice;
    const tm: f32 = @floatCast(st.beat);
    const adv = tm * 3.0;
    const spin = tm * 0.25;
    const cx = @as(f32, @floatFromInt(fb.w)) / 2;
    const cy = @as(f32, @floatFromInt(fb.h)) / 2;
    const diag: f32 = @floatFromInt(fb.w + fb.h);
    const scale = diag * 2.2;
    const soft = diag * 0.02;

    // @excerpt TUNNEL/1
    for (0..fb.h) |y| {
        const dy = @as(f32, @floatFromInt(y)) - cy;
        for (fb.row(y), 0..) |*px, x| {
            const dx = @as(f32, @floatFromInt(x)) - cx;
            const depth = scale / (fmath.sqrt(dx * dx + dy * dy) + soft);
            const u = depth + adv;
            const v = fmath.atan2Turns(dy, dx);

            const ring = fmath.sin01(u * 0.16);
            const twist = v * 12 + u * 0.09 + spin;
            const spoke = fmath.sin01(twist);
            var val = ring * 0.55 + spoke * 0.45;
            const brick = @as(i32, @intFromFloat(u * 0.32)) + @as(i32, @intFromFloat(twist));
            if (brick & 1 == 1) val = -val * 0.7;
            const fog = 1 / (1 + u * 0.02);
            const lum = (val * 0.5 + 0.5) * fog;
            const idx: u8 = @intFromFloat(std.math.clamp(lum * 300, 0, 255));
            px.* = pal[idx];
        }
    }
    // @end
}
