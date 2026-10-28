//! Starfield: a warp-speed star tunnel. Stars live in 3D, get projected in
//! perspective and dragged into short streaks. The streak is what sells the
//! speed, so each star draws from its previous depth to its current one.

const std = @import("std");
const canvas = @import("canvas.zig");
const fmath = @import("fmath.zig");
const State = @import("fx.zig").State;

const n_stars = 1600;

const Star = struct { x: f32, y: f32, z: f32 };

const Proj = struct {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,
    c: u32,
};

// The stars are a fixed-size array inside the struct: their number never
// changes, so there is nothing to allocate.
stars: [n_stars]Star,
proj: [n_stars]Proj,
bg: []u32, // the backdrop never changes, so it is built once per start
rng: fmath.Rng,

const Starfield = @This();

pub fn start(s: *Starfield, arena: std.mem.Allocator, w: usize, h: usize) !void {
    s.rng = .{ .state = 0x6005E };
    for (&s.stars) |*p| {
        // three draws in a fixed order: statements, not one initialiser
        const x = (s.rng.float() * 2 - 1) * 1.6;
        const y = (s.rng.float() * 2 - 1) * 1.6;
        const z = s.rng.float() * 40 + 0.2;
        p.* = .{ .x = x, .y = y, .z = z };
    }
    s.bg = try arena.alloc(u32, w * h);
    buildBackdrop(s.bg, w, h);
}

/// Paints the deep-navy vignette. Copying a ready buffer is two orders of
/// magnitude cheaper than evaluating it per pixel per frame, and this is the
/// trick the rest of the demo leans on too.
fn buildBackdrop(bg: []u32, w: usize, h: usize) void {
    const fw: f64 = @floatFromInt(w);
    const fh: f64 = @floatFromInt(h);
    for (0..h) |y| {
        const dy = @as(f64, @floatFromInt(y)) / fh - 0.5;
        for (bg[y * w ..][0..w], 0..) |*px, x| {
            const dx = @as(f64, @floatFromInt(x)) / fw - 0.5;
            const v = dx * dx + dy * dy;
            px.* = canvas.fromFloat(@max(0.02 - v * 0.03, 0), @max(0.02 - v * 0.025, 0), @max(0.05 - v * 0.03, 0));
        }
    }
}

pub fn render(s: *Starfield, fb: canvas.FB, st: State) void {
    s.project(st, fb.w, fb.h);
    @memcpy(fb.pix, s.bg);
    const w: i32 = @intCast(fb.w);
    const h: i32 = @intCast(fb.h);
    for (&s.proj) |p| {
        // additive line from the trailing point to the head
        drawLineAdd(fb, p.x0, p.y0, p.x1, p.y1, p.c);
        // bright head pixel
        if (p.x1 >= 0 and p.x1 < w and p.y1 >= 0 and p.y1 < h) {
            fb.pix[@intCast(p.y1 * w + p.x1)] = 0xFFCCEEFF;
        }
    }
}

/// Moves every star and projects its streak.
fn project(s: *Starfield, st: State, w: usize, h: usize) void {
    const cx = @as(f32, @floatFromInt(w)) * 0.5;
    const cy = @as(f32, @floatFromInt(h)) * 0.5;
    // accelerate over the scene so the entry has a kick
    const speed: f32 = @floatCast(2.5 + @min(st.beat, 3) * 4);
    const dt = @min(@as(f32, @floatCast(st.dt)), 0.1);
    const dz = speed * dt;
    const zoom = @as(f32, @floatFromInt(w)) * 0.78;

    // @excerpt STARFIELD
    for (&s.stars, &s.proj) |*p, *out| {
        p.z -= dz;
        if (p.z < 0.8) {
            p.z += 40;
            p.x = (s.rng.float() * 2 - 1) * 1.1;
            p.y = (s.rng.float() * 2 - 1) * 1.1;
        }
        // 1.0 meets an f32 and becomes one: the whole projection stays f32
        const f = 1.0 / p.z;
        const x0 = cx + p.x * f * zoom;
        const y0 = cy + p.y * f * zoom;
        const f2 = 1.0 / (p.z + dz * 2.4);
        const x1 = cx + p.x * f2 * zoom;
        const y1 = cy + p.y * f2 * zoom;

        // brighter and bluer as the star gets close
        const near = 1 - p.z / 40;
        const b = near * near;
        const r: u32 = @intFromFloat(120 * b + 40);
        const g: u32 = @intFromFloat(190 * b + 40);
        const bl: u32 = @intFromFloat(255 * (0.25 + 0.75 * b));
        out.* = .{
            .x0 = @intFromFloat(x0),
            .y0 = @intFromFloat(y0),
            .x1 = @intFromFloat(x1),
            .y1 = @intFromFloat(y1),
            .c = canvas.rgb(r, g, bl),
        };
    }
    // @end
}

/// A Bresenham line that adds its colour, so overlapping stars accumulate
/// brightness instead of replacing each other.
fn drawLineAdd(fb: canvas.FB, x0_in: i32, y0_in: i32, x1: i32, y1: i32, c: u32) void {
    const w: i32 = @intCast(fb.w);
    const h: i32 = @intCast(fb.h);
    var x0 = x0_in;
    var y0 = y0_in;
    const dx: i32 = @intCast(@abs(x1 - x0));
    const dy = -@as(i32, @intCast(@abs(y1 - y0)));
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;
    while (true) {
        if (x0 >= 0 and x0 < w and y0 >= 0 and y0 < h) {
            const i: usize = @intCast(y0 * w + x0);
            const p = fb.pix[i];
            const r = @min((p & 0xFF) + (c & 0xFF), 255);
            const g = @min((p >> 8 & 0xFF) + (c >> 8 & 0xFF), 255);
            const b = @min((p >> 16 & 0xFF) + (c >> 16 & 0xFF), 255);
            fb.pix[i] = canvas.rgb(r, g, b);
        }
        if (x0 == x1 and y0 == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}
