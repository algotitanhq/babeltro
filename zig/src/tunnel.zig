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

const Tunnel = @This();

pub fn start(t: *Tunnel, arena: std.mem.Allocator, w: usize, h: usize) !void {
    t.depth = try arena.alloc(f32, w * h);
    t.angle = try arena.alloc(f32, w * h);
    // scale with the diagonal so the rings look the same at any resolution
    const diag: f32 = @floatFromInt(w + h);
    fmath.distInvTable(t.depth, w, h, diag * 2.2, diag * 0.02);
    fmath.atan2Table(t.angle, w, h);
}

pub fn render(t: *Tunnel, fb: canvas.FB, st: State) void {
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
