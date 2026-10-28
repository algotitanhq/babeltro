//! Grid: the synthwave staple, an infinite checker floor rushing at the
//! camera under a banded sun. The floor is a per-pixel perspective divide,
//! and the lines come from the fractional part of the world coordinates.
//!
//! This scene mixes f32 and f64 the most. Zig never converts between them
//! implicitly in arithmetic, so every @floatCast below is a place where Go
//! writes float32(...) or float64(...) too.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const State = @import("fx.zig").State;

const Grid = @This();

pub fn start(_: *Grid, _: std.mem.Allocator, _: usize, _: usize) !void {}

/// Clamps an f32 in f64, as Go's canvas.Clamp01(float64(v)), and rounds back.
inline fn clamp01(v: f32) f32 {
    return @floatCast(canvas.clamp01(v));
}

/// Everything about a floor row that does not depend on x.
const FloorRow = struct {
    dz: f32, // distance below the horizon, in pixels
    kx: f32, // world x per screen pixel on this row
    line_z: f32, // brightness of the line running across the row
    fade_x: f32,
    r: f32,
    g: f32,
    b: f32,
};

fn floorRow(fy: f32, horizon: f32, fh: f32, fw: f32, asp: f32, t: f32) FloorRow {
    const dz = fy - horizon;
    const z = (fh * 0.55) / dz;
    const wz = z * 2.5 + t * 5.5;
    const kx = z / (fw * 0.5) * asp * 2.0;

    // A line narrower than a pixel lands on only every few pixels and reads
    // as a row of bright dots. Widen it to a full pixel and dim it by the
    // area it actually covers: the same light, spread out, which is what the
    // eye integrates anyway.
    const period = dz * dz / (1.375 * fh); // pixels per unit of wz
    var lw_z = 0.014 + 0.024 / z;
    var amp_z: f32 = 1;
    const min_w = 0.5 / period;
    if (lw_z < min_w) {
        amp_z = lw_z / min_w;
        lw_z = min_w;
    }
    var line_z = lineGlow(fract(wz), lw_z) * amp_z;
    // fade lines that have shrunk below a couple of pixels per period,
    // otherwise the horizon boils with aliasing
    line_z *= clamp01((period - 1.5) / 2);
    line_z *= clamp01(1.0 / (1 + z * z * 0.004)); // fog

    var row: FloorRow = .{
        .dz = dz,
        .kx = kx,
        .line_z = line_z,
        // same aliasing guard as above, but across the row
        .fade_x = clamp01((1 / kx - 1.5) / 2),
        .r = 0.02,
        .g = 0.01,
        .b = 0.06,
    };
    // the haze near the horizon is computed in f64, as in Go
    const haze = canvas.clamp01(dz / (fh * 0.12));
    if (haze < 1) {
        row.r += @floatCast(0.25 * (1 - haze));
        row.g += @floatCast(0.05 * (1 - haze));
        row.b += @floatCast(0.35 * (1 - haze));
    }
    row.r += 0.55 * line_z;
    row.g += 0.35 * line_z;
    row.b += 0.75 * line_z;
    return row;
}

pub fn render(_: *Grid, fb: canvas.FB, st: State) void {
    const fw: f32 = @floatFromInt(fb.w);
    const fh: f32 = @floatFromInt(fb.h);
    const horizon = fh * 0.52;
    const asp = fh / fw;
    const cx = fw * 0.5;
    const t: f32 = @floatCast(st.beat);
    const lw_x: f32 = 0.022;

    // sun parameters
    const sun_y = horizon - fh * 0.13;
    const sun_r = fh * 0.16;
    const sun_x = cx;

    for (0..fb.h) |y| {
        const fy: f32 = @floatFromInt(y);

        // everything that depends only on the row is hoisted out of the
        // pixel loop; on the floor that is most of the arithmetic
        const sky = canvas.clamp01(fy / horizon);
        const sky_r: f32 = @floatCast(0.03 + 0.18 * sky * sky);
        const sky_g: f32 = @floatCast(0.01 + 0.05 * sky);
        const sky_b: f32 = @floatCast(0.08 + 0.22 * sky);

        // an optional: the floor constants exist only on floor rows
        const floor: ?FloorRow = if (fy > horizon) floorRow(fy, horizon, fh, fw, asp, t) else null;

        // sun: bounding box test first, then the expensive circle only there
        const dyc = fy - sun_y;
        const sun_row = dyc > -sun_r and dyc < sun_r and fy < horizon + 2;
        const stripe = sun_row and fy > sun_y - sun_r * 0.45 and y % 9 < 4;
        const u = canvas.clamp01((fy - (sun_y - sun_r)) / (2 * sun_r));
        const sr: f32 = 1.0;
        const sg: f32 = @floatCast(0.95 - 0.7 * u);
        const sb: f32 = @floatCast(0.25 + 0.55 * u);

        // @excerpt GRID
        for (fb.row(y), 0..) |*px, x| {
            const fx: f32 = @floatFromInt(x);
            var r = sky_r;
            var g = sky_g;
            var b = sky_b;

            if (sun_row and !stripe) {
                const dx = fx - sun_x;
                if (dx > -sun_r and dx < sun_r) {
                    const d = fmath.sqrt(dx * dx + dyc * dyc);
                    if (d < sun_r) {
                        const edge = clamp01((sun_r - d) / (sun_r * 0.025));
                        r = mix(r, sr, edge);
                        g = mix(g, sg, edge);
                        b = mix(b, sb, edge);
                    }
                }
            }

            if (floor) |f| {
                // How far this ray slides sideways between one row and the
                // next, in pixels: x = (k-0.37)/kx + cx, so dx/dy = |x-cx|/dz.
                // The line must be at least that wide, and dimmed by the same
                // ratio, or each row shows a handful of isolated bright dots
                // instead of a line.
                const off = @abs(fx - cx);
                const w_px = @max(2 * lw_x / f.kx, off / f.dz, 1);
                const line_x = lineGlow(fract((fx - cx) * f.kx + 0.37), w_px * f.kx * 0.5) *
                    (2 * lw_x / f.kx / w_px) * f.fade_x;
                const line = @max(line_x, f.line_z);
                r = f.r - 0.55 * f.line_z + 0.55 * line;
                g = f.g - 0.35 * f.line_z + 0.35 * line;
                b = f.b - 0.75 * f.line_z + 0.75 * line;
            }

            px.* = canvas.fromFloat(r, g, b);
        }
        // @end
    }
}

/// Wraps a world coordinate into [0,1). Go writes v - float32(int(v)); @trunc
/// gives the same bits without the round trip through an integer, and
/// without its range limit.
inline fn fract(v: f32) f32 {
    const m = v - @trunc(v);
    return if (m < 0) m + 1 else m;
}

/// 1 on the grid line, falling to 0 over width w.
inline fn lineGlow(f: f32, w: f32) f32 {
    const d = if (f > 0.5) 1 - f else f;
    return if (d < w) 1 - d / w else 0;
}

inline fn mix(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
