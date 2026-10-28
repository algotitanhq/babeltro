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

// the ladder: 1 calls the maths library's sine four times per pixel, 2 reads
// the sine table four times per pixel, 3 and 0 (the default) move three of
// the four lookups into per-frame 1D tables
step: i32,

const Plasma = @This();

pub fn start(p: *Plasma, arena: std.mem.Allocator, w: usize, h: usize) !void {
    p.step = 0;
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

pub fn setStep(p: *Plasma, n: i32) void {
    p.step = n;
}

/// What every rung needs to know about the frame.
const Frame = struct {
    t: f32,
    kx: f32,
    ky: f32,
    phase: f32,

    fn of(fb: canvas.FB, st: State) Frame {
        const t: f32 = @floatCast(st.beat);
        return .{
            .t = t,
            .kx = 26.0 / @as(f32, @floatFromInt(fb.w)),
            .ky = 26.0 / @as(f32, @floatFromInt(fb.h)),
            .phase = t * 2.6,
        };
    }
};

pub fn render(p: *Plasma, fb: canvas.FB, st: State) void {
    const f = Frame.of(fb, st);
    switch (p.step) {
        1 => drawSin(fb, f),
        2 => drawTable(fb, f),
        else => p.drawRows(fb, f),
    }
}

/// The default: three of the four sines come from 1D tables rebuilt once per
/// frame, and the distance to the centre from a table built at start.
fn drawRows(p: *Plasma, fb: canvas.FB, f: Frame) void {
    const w = fb.w;
    const t = f.t;
    const kx = f.kx;
    const ky = f.ky;
    for (p.sx, 0..) |*v, x| v.* = fmath.sin(@as(f32, @floatFromInt(x)) * kx + t * 1.3);
    for (p.sy, 0..) |*v, y| v.* = fmath.sin(@as(f32, @floatFromInt(y)) * ky * 1.35 - t * 1.1);
    for (p.sxy, 0..) |*v, i| v.* = fmath.sin(@as(f32, @floatFromInt(i)) * kx * 0.85 + t * 0.8);
    const phase = f.phase;
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

/// The maths library's sine, rounded to f32 like the table. Go has only a
/// float64 math.Sin, so this is what its rung computes; Zig's @sin would also
/// take an f32 directly (sinf), a different function with its own roundings.
inline fn sin32(a: f32) f32 {
    return @floatCast(@sin(@as(f64, a)));
}

/// The plasma as you would first write it: every term, every pixel, straight
/// from the maths library. Slow, and the reference for what the table
/// approximates.
fn drawSin(fb: canvas.FB, f: Frame) void {
    const cx = @as(f32, @floatFromInt(fb.w)) * 0.5;
    const cy = @as(f32, @floatFromInt(fb.h)) * 0.5;
    const kr = 44.0 / @as(f32, @floatFromInt(fb.w + fb.h));
    const pal = &palette.sunset;
    // @excerpt PLASMA/1
    for (0..fb.h) |y| {
        const fy: f32 = @floatFromInt(y);
        const dy = fy - cy;
        for (fb.row(y), 0..) |*px, x| {
            const fx: f32 = @floatFromInt(x);
            const dx = fx - cx;
            // an f32 @sqrt is correctly rounded: the same bits as Go's
            // round trip through float64
            const rad = @sqrt(dx * dx + dy * dy) * kr;
            const v = sin32(fx * f.kx + f.t * 1.3) +
                sin32(fy * f.ky * 1.35 - f.t * 1.1) +
                sin32(@as(f32, @floatFromInt(x + y)) * f.kx * 0.85 + f.t * 0.8) +
                sin32(rad + f.phase);
            const i: u8 = @intFromFloat(std.math.clamp(v * 36 + 127.5, 0, 255));
            px.* = pal[i];
        }
    }
    // @end
}

/// The same per-pixel structure, reading the sine table instead of calling
/// the library. Same arguments as the default, so the same pixels; the only
/// change from drawSin is the table's precision.
fn drawTable(fb: canvas.FB, f: Frame) void {
    const cx = @as(f32, @floatFromInt(fb.w)) * 0.5;
    const cy = @as(f32, @floatFromInt(fb.h)) * 0.5;
    const kr = 44.0 / @as(f32, @floatFromInt(fb.w + fb.h));
    const pal = &palette.sunset;
    // @excerpt PLASMA/2
    for (0..fb.h) |y| {
        const fy: f32 = @floatFromInt(y);
        const dy = fy - cy;
        for (fb.row(y), 0..) |*px, x| {
            const fx: f32 = @floatFromInt(x);
            const dx = fx - cx;
            const rad = fmath.sqrt(dx * dx + dy * dy) * kr;
            const v = fmath.sin(fx * f.kx + f.t * 1.3) +
                fmath.sin(fy * f.ky * 1.35 - f.t * 1.1) +
                fmath.sin(@as(f32, @floatFromInt(x + y)) * f.kx * 0.85 + f.t * 0.8) +
                fmath.sin(rad + f.phase);
            const i: u8 = @intFromFloat(std.math.clamp(v * 36 + 127.5, 0, 255));
            px.* = pal[i];
        }
    }
    // @end
}
