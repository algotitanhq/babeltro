//! 256-entry colour ramps built from a handful of stops. Effects index these
//! ramps instead of doing per-pixel colour maths, the classic demoscene
//! trade: pay once, then look up. Here "once" is at compile time: every
//! ramp below is a constant array the compiler computed.

const canvas = @import("canvas.zig");

/// One colour anchor in a ramp, at position pos in [0,1].
pub const Stop = struct { pos: f64, r: f64, g: f64, b: f64 };

/// A ready-to-index 256-colour ramp.
pub const Palette = [256]u32;

/// Interpolates the stops into a palette, with a smoothstep between each
/// pair so gradients do not band.
pub fn build(comptime stops: []const Stop) Palette {
    @setEvalBranchQuota(20_000);
    var p: Palette = undefined;
    for (&p, 0..) |*c, i| {
        const t = @as(f64, @floatFromInt(i)) / 255;
        // find the segment containing t
        var a = stops[0];
        var b = stops[stops.len - 1];
        for (stops[0 .. stops.len - 1], stops[1..]) |lo, hi| {
            if (t >= lo.pos and t <= hi.pos) {
                a = lo;
                b = hi;
                break;
            }
        }
        var u: f64 = if (b.pos > a.pos) (t - a.pos) / (b.pos - a.pos) else 0;
        u = canvas.clamp01(u);
        u = u * u * (3 - 2 * u);
        c.* = canvas.fromFloat(a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u);
    }
    return p;
}

/// The colour at position t in [0,1], clamped to the ends of the ramp.
pub fn at(p: *const Palette, t: f64) u32 {
    // clamp in float before converting: an out-of-range @intFromFloat is
    // illegal behaviour in Zig, where Go would merely produce some number
    const i: usize = @intFromFloat(@min(@max(t * 255, 0), 255));
    return p[i];
}

fn s(pos: f64, r: f64, g: f64, b: f64) Stop {
    return .{ .pos = pos, .r = r, .g = g, .b = b };
}

/// Sunset: the demo's signature ramp. Deep violet to hot orange to cream.
pub const sunset = build(&.{
    s(0.00, 0.02, 0.00, 0.06),
    s(0.18, 0.25, 0.02, 0.38),
    s(0.38, 0.72, 0.05, 0.45),
    s(0.56, 0.98, 0.25, 0.22),
    s(0.74, 1.00, 0.62, 0.15),
    s(0.88, 1.00, 0.93, 0.55),
    s(1.00, 1.00, 1.00, 0.96),
});

/// Ice: cold counterpart used by the tunnel and the mandelbrot.
pub const ice = build(&.{
    s(0.00, 0.00, 0.00, 0.03),
    s(0.25, 0.00, 0.10, 0.30),
    s(0.50, 0.00, 0.55, 0.85),
    s(0.72, 0.35, 0.90, 1.00),
    s(0.90, 0.80, 1.00, 1.00),
    s(1.00, 1.00, 1.00, 1.00),
});

/// Ember: fire ramp.
pub const ember = build(&.{
    s(0.00, 0.00, 0.00, 0.00),
    s(0.20, 0.25, 0.00, 0.00),
    s(0.45, 0.80, 0.10, 0.00),
    s(0.68, 1.00, 0.45, 0.00),
    s(0.85, 1.00, 0.80, 0.15),
    s(1.00, 1.00, 1.00, 0.85),
});

/// HSL (all 0..1) to RGB components 0..1. The rotozoom's texture calls it
/// at run time, a quarter of a million times.
pub fn hslToRgb(h: f64, sat: f64, l: f64) [3]f64 {
    if (sat == 0) return .{ l, l, l };
    const q = if (l < 0.5) l * (1 + sat) else l + sat - l * sat;
    const p = 2 * l - q;
    return .{ hueToRgb(p, q, h + 1.0 / 3.0), hueToRgb(p, q, h), hueToRgb(p, q, h - 1.0 / 3.0) };
}

fn hueToRgb(p: f64, q: f64, t0: f64) f64 {
    var t = t0;
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1.0 / 6.0) return p + (q - p) * 6 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6;
    return p;
}
