//! Metaballs: summed radial fields with shaded iso-contours. Every pixel
//! evaluates sum(r^2 / d^2) with one division per ball and no square root,
//! and the contour band gets a hot rim so the blobs read as liquid rather
//! than as a flat gradient.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const palette = @import("palette.zig");
const State = @import("fx.zig").State;

const n_balls = 6;

const Metaballs = @This();

pub fn start(_: *Metaballs, _: std.mem.Allocator, _: usize, _: usize) !void {}

pub fn render(_: *Metaballs, fb: canvas.FB, st: State) void {
    const fw: f32 = @floatFromInt(fb.w);
    const fh: f32 = @floatFromInt(fb.h);
    // x is scaled by width/height so a circle in field space is a circle on
    // screen, whatever the aspect ratio
    const asp = fw / fh;
    const t: f32 = @floatCast(st.beat);

    // Each ball orbits on its own ellipse and breathes. Go stores the centre
    // and computes (centre - 0.5) * asp again for every pixel; the offsets
    // are computed once here instead, with the same roundings, so the
    // values (and the pixels) are identical.
    var bx: [n_balls]f32 = undefined;
    var by: [n_balls]f32 = undefined;
    var rad2: [n_balls]f32 = undefined; // the field is about 1 on a ball's surface
    for (0..n_balls) |i| {
        const fi: f32 = @floatFromInt(i);
        const a = t * (0.35 + fi * 0.07) + fi * 2.1;
        const cx = 0.5 + 0.20 * fmath.cos(a) * (1 + 0.3 * fmath.sin(t * 0.5 + fi));
        const cy = 0.5 + 0.20 * fmath.sin(a * 1.3 + fi) * (1 + 0.3 * fmath.cos(t * 0.4 + fi * 2));
        const r = 0.105 + 0.025 * fmath.sin(t * 1.1 + fi * 1.7);
        bx[i] = (cx - 0.5) * asp;
        by[i] = cy - 0.5;
        rad2[i] = r * r;
    }
    const pal = &palette.sunset;

    // @excerpt METABALLS
    for (0..fb.h) |y| {
        const fy = @as(f32, @floatFromInt(y)) / fh - 0.5;
        for (fb.row(y), 0..) |*px, x| {
            const fx = (@as(f32, @floatFromInt(x)) / fw - 0.5) * asp;
            var field: f32 = 0;
            // inline for unrolls the six balls at compile time
            inline for (bx, by, rad2) |cx, cy, r2| {
                const dx = fx - cx;
                const dy = fy - cy;
                field += r2 / (dx * dx + dy * dy + 1e-5);
            }
            // field is about 1 at the surface of a ball and explodes inside;
            // v/(1+v) compresses that into a usable 0..1 ramp without a log
            const v = field / (1.6 + field);
            var idx: u8 = @intFromFloat(@min(v * 255, 255));
            // rim: the iso-surface where the balls meet flares white
            if (field > 1.0 and field < 1.09) idx = 255;
            px.* = pal[idx];
        }
    }
    // @end
}
