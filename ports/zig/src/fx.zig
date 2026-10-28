//! The nine scenes behind one type. Every scene is a struct with the same two
//! functions:
//!
//!     start(self, arena, w, h) !void   build the tables, from a fresh state
//!     render(self, fb, state) void     draw one whole frame
//!
//! The scenes with an optimisation ladder also have setStep(self, n).
//!
//! Effect is a tagged union of them, and `inline else` turns a call on the
//! union into a switch over the nine concrete calls at compile time: no
//! vtable, no function pointer, and a scene missing either function is a
//! compile error, not a crash.

const std = @import("std");
const canvas = @import("canvas.zig");

/// What a scene knows about time. Frame n is at a fixed 60 Hz step, never a
/// clock, so a frame number names the same image in every language.
pub const State = struct {
    t: f64, // seconds since the demo started
    beat: f64, // seconds since this scene started
    dt: f64, // seconds since the previous frame
    frame: u64,

    pub fn at(n: u32) State {
        const t = @as(f64, @floatFromInt(n)) / 60;
        return .{ .t = t, .beat = t, .dt = 1.0 / 60.0, .frame = n };
    }
};

/// The scenes in playback order: the tag values are the scene numbers of
/// spec/ABI.md.
pub const Effect = union(enum(u8)) {
    starfield: @import("starfield.zig"),
    tunnel: @import("tunnel.zig"),
    plasma: @import("plasma.zig"),
    rotozoom: @import("rotozoom.zig"),
    metaballs: @import("metaballs.zig"),
    grid: @import("grid.zig"),
    fire: @import("fire.zig"),
    mandelbrot: @import("mandelbrot.zig"),
    finale: @import("finale.zig"),

    pub const Tag = std.meta.Tag(Effect);

    /// Makes `tag` the active scene, in place, and starts it.
    pub fn begin(e: *Effect, tag: Tag, arena: std.mem.Allocator, w: usize, h: usize) !void {
        switch (tag) {
            inline else => |t| {
                // start sets every field that render reads before writing it
                e.* = @unionInit(Effect, @tagName(t), undefined);
                try @field(e, @tagName(t)).start(arena, w, h);
            },
        }
    }

    /// Picks a rung of the scene's optimisation ladder, 0 being the default.
    /// Go asks at run time whether the effect implements fx.Stepped; here
    /// @hasDecl asks at compile time, so the scenes without a ladder compile
    /// to nothing.
    pub fn setStep(e: *Effect, n: i32) void {
        switch (e.*) {
            inline else => |*scene| if (@hasDecl(@TypeOf(scene.*), "setStep")) scene.setStep(n),
        }
    }

    pub fn render(e: *Effect, fb: canvas.FB, s: State) void {
        switch (e.*) {
            inline else => |*scene| scene.render(fb, s),
        }
    }
};
