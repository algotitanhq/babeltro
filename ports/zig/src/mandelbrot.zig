//! Mandelbrot: a dive into the boundary. It is the most expensive scene, so
//! it renders on a coarse grid of step x step blocks and stretches the
//! result: at 60 fps in motion nobody can tell, and the budget stays honest.

const std = @import("std");
const canvas = @import("canvas.zig");
const palette = @import("palette.zig");
const State = @import("fx.zig").State;

step: usize,
// the ladder: 1 iterates every pixel with no shortcut, 2 adds the closed-form
// test for the cardioid and the bulb, 3 and 0 (the default) also render on
// blocks of step x step pixels
rung: i32,

const Mandelbrot = @This();

pub fn start(m: *Mandelbrot, _: std.mem.Allocator, w: usize, _: usize) !void {
    // keep the block size constant in screen terms as the window grows
    m.step = if (w > 1600) 3 else 2;
    m.rung = 0;
}

pub fn setStep(m: *Mandelbrot, n: i32) void {
    m.rung = n;
}

/// The iteration function is a comptime parameter, not a run-time function
/// value: each rung gets its own copy of the block loop with its function
/// called directly (and inlined), where Go and C call through a pointer.
const IterFn = fn (cx: f64, cy: f64, max: u32) u32;

pub fn render(m: *Mandelbrot, fb: canvas.FB, st: State) void {
    switch (m.rung) {
        1 => drawBlocks(iteratePlain, fb, st, 1),
        2 => drawBlocks(iterate, fb, st, 1),
        else => drawBlocks(iterate, fb, st, m.step),
    }
}

fn drawBlocks(comptime iter: IterFn, fb: canvas.FB, st: State, step: usize) void {
    const w = fb.w;
    const h = fb.h;

    const t = @min(st.beat, 14);
    const u = t / 12;
    // the camera slides onto the target point quickly, then the exponential
    // dive does the work; drifting the centre linearly with the zoom would
    // spend most of the scene looking at empty plane
    const k = 1 - @exp(-8 * u);
    // tested target: the seahorse valley, where the boundary never opens into
    // a flat interior, so the whole frame stays fractal at any depth
    const span = 2.9 * @exp(-u * u * 3.6);
    // the deep frames need the iteration budget; the wide ones do not
    const max_iter: u32 = 64 + @as(u32, @intFromFloat(128 * u));
    const centre_x = -0.5 + (-0.743643887037151 + 0.5) * k;
    const centre_y = 0.0 + 0.131825904205330 * k;

    const asp = @as(f64, @floatFromInt(h)) / @as(f64, @floatFromInt(w));
    const x0 = centre_x - span * 0.5;
    const y0 = centre_y - span * 0.5 * asp;
    // units per pixel: a block is step pixels wide, and the loop advances by
    // whole blocks, so this must not be divided by step as well
    const d = span / @as(f64, @floatFromInt(w));
    const pal = &palette.ice;

    // @excerpt MANDELBROT
    var y: usize = 0;
    while (y < h) : (y += step) {
        const cy = y0 + @as(f64, @floatFromInt(y)) * d;
        const y_end = @min(y + step, h);
        var x: usize = 0;
        while (x < w) : (x += step) {
            const cx = x0 + @as(f64, @floatFromInt(x)) * d;
            const it = iter(cx, cy, max_iter);
            const c: u32 = if (it >= max_iter) 0xFF0A0812 else c: {
                // the ramp is anchored to a fixed iteration count, not to
                // max_iter, so raising the budget for a deep zoom does not
                // darken the whole picture
                const v = @min(@sqrt(@as(f64, @floatFromInt(it)) / 40), 1);
                break :c palette.at(pal, v * 0.92 + 0.04);
            };
            const x_end = @min(x + step, w);
            for (y..y_end) |yy| @memset(fb.row(yy)[x..x_end], c);
        }
    }
    // @end
}

/// The escape-time loop and nothing else: every point inside the set runs
/// the full budget before it gives up.
// @excerpt MANDELBROT/1
fn iteratePlain(cx: f64, cy: f64, max: u32) u32 {
    var zx: f64 = 0;
    var zy: f64 = 0;
    var zx2: f64 = 0;
    var zy2: f64 = 0;
    for (0..max) |i| {
        zy = 2 * zx * zy + cy;
        zx = zx2 - zy2 + cx;
        zx2 = zx * zx;
        zy2 = zy * zy;
        if (zx2 + zy2 > 4) return @intCast(i);
    }
    return max;
}
// @end

/// The escape time of c = cx + i*cy, or max if it never escapes.
// @excerpt MANDELBROT/2
fn iterate(cx: f64, cy: f64, max: u32) u32 {
    // cheap escape test for the main cardioid and the period-2 bulb
    const x = cx - 0.25;
    const y2 = cy * cy;
    const q = x * x + y2;
    if (q * (q + x) <= 0.25 * y2) return max;
    if ((cx + 1) * (cx + 1) + y2 <= 0.0625) return max;

    var zx: f64 = 0;
    var zy: f64 = 0;
    var zx2: f64 = 0;
    var zy2: f64 = 0;
    for (0..max) |i| {
        zy = 2 * zx * zy + cy;
        zx = zx2 - zy2 + cx;
        zx2 = zx * zx;
        zy2 = zy * zy;
        if (zx2 + zy2 > 4) return @intCast(i);
    }
    return max;
}
// @end
