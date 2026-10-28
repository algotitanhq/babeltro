//! The numeric shortcuts every effect leans on. Calling @sin a million times
//! per frame is the difference between 20 ms and 1 ms, so the hot loops read a
//! sine table instead, and every random number comes from xorshift32.

const std = @import("std");
const pi = std.math.pi;

pub const tab_bits = 13;
pub const tab_size = 1 << tab_bits;
pub const tab_mask = tab_size - 1;

/// Radians to table steps. The quotient is folded at compile time (in
/// comptime_float, wider than f64) and rounded once to f32, as Go does.
const inv2pi: f32 = @as(comptime_float, tab_size) / (2 * pi);

/// One table entry per step of a full turn, plus one so a full period wraps
/// exactly. Both tables are computed by the compiler: they are constants in
/// the module's data section, and nothing runs at startup to fill them.
pub const sin_tab: [tab_size + 1]f32 = table(.sin);
pub const cos_tab: [tab_size + 1]f32 = table(.cos);

fn table(comptime which: enum { sin, cos }) [tab_size + 1]f32 {
    // comptime evaluation counts backward branches; 8193 sines need more
    // than the default budget of 1000
    @setEvalBranchQuota(100_000);
    var t: [tab_size + 1]f32 = undefined;
    for (t[0..tab_size], 0..) |*v, i| {
        const a = 2 * pi * @as(f64, @floatFromInt(i)) / tab_size;
        v.* = @floatCast(if (which == .sin) @sin(a) else @cos(a));
    }
    t[tab_size] = t[0];
    return t;
}

/// The lookups truncate toward zero, like Go's int(), then wrap with the mask;
/// on a two's-complement i32 that also handles negative angles. @intFromFloat
/// is checked in Debug and ReleaseSafe and undefined beyond i32 in
/// ReleaseFast, so it is only ever handed angles the effects keep small.
inline fn index(steps: f32) usize {
    const i: i32 = @intFromFloat(steps);
    return @intCast(i & tab_mask);
}

/// sin(a) from the table, a in radians.
pub inline fn sin(a: f32) f32 {
    return sin_tab[index(a * inv2pi)];
}

/// cos(a) from the table, a in radians.
pub inline fn cos(a: f32) f32 {
    return cos_tab[index(a * inv2pi)];
}

/// sin(2*pi*t) for t in turns.
pub inline fn sin01(t: f32) f32 {
    return sin_tab[index(t * tab_size)];
}

/// sqrt in f32. Go goes through float64 and rounds back; for a square root
/// that double rounding provably gives the correctly rounded f32 result, so
/// the f32 instruction is the same function.
pub inline fn sqrt(x: f32) f32 {
    return @sqrt(x);
}

/// atan2(y, x) as a fraction of a full turn, in [0,1). The angle itself is
/// computed in f64, as in Go, by Zig's own std.math.atan2.
pub fn atan2Turns(y: f32, x: f32) f32 {
    const a: f32 = @floatCast(std.math.atan2(@as(f64, y), @as(f64, x)));
    return a / (2 * pi) + 0.5;
}

/// Fills tab (w*h entries) with the turn fraction of every pixel around the
/// centre of the grid. The tunnel reads it instead of calling atan2.
pub fn atan2Table(tab: []f32, w: usize, h: usize) void {
    const cx = @as(f32, @floatFromInt(w)) / 2;
    const cy = @as(f32, @floatFromInt(h)) / 2;
    for (0..h) |y| {
        const dy = @as(f32, @floatFromInt(y)) - cy;
        for (tab[y * w ..][0..w], 0..) |*v, x| {
            v.* = atan2Turns(dy, @as(f32, @floatFromInt(x)) - cx);
        }
    }
}

/// Fills tab (w*h entries) with scale/(r+softness), r being the distance to
/// the centre. The softness term tames the singularity there, which would
/// otherwise turn into aliasing noise.
pub fn distInvTable(tab: []f32, w: usize, h: usize, scale: f32, softness: f32) void {
    const cx = @as(f32, @floatFromInt(w)) / 2;
    const cy = @as(f32, @floatFromInt(h)) / 2;
    for (0..h) |y| {
        const dy = @as(f32, @floatFromInt(y)) - cy;
        for (tab[y * w ..][0..w], 0..) |*v, x| {
            const dx = @as(f32, @floatFromInt(x)) - cx;
            v.* = scale / (sqrt(dx * dx + dy * dy) + softness);
        }
    }
}

/// xorshift32: three shifts and three xors give the same sequence in every
/// language, which no library generator promises. The state must never be
/// zero. `<<` on a u32 simply drops the bits shifted out; @shlExact would be
/// the checked variant.
pub const Rng = struct {
    state: u32,

    pub fn next(r: *Rng) u32 {
        var x = r.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        r.state = x;
        return x;
    }

    /// A number in [0,1) from the top 24 bits, so the conversion to f32 is
    /// exact.
    pub fn float(r: *Rng) f32 {
        return @as(f32, @floatFromInt(r.next() >> 8)) * (1.0 / 16777216.0);
    }
};
