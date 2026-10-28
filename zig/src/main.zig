//! The wasm exports every port provides (see spec/ABI.md): bb_init allocates
//! the framebuffer, bb_start begins a scene from a clean state, bb_render
//! draws one frame of it.
//!
//! Memory is handled with two allocators, each chosen for its lifetime:
//!
//!  - the framebuffer comes from std.heap.wasm_allocator, which grows linear
//!    memory with memory.grow and lives as long as the module;
//!  - everything a scene builds at start (the tunnel's tables, the fire's
//!    heat buffer, ...) comes from an ArenaAllocator on top of it. The next
//!    bb_start resets the arena: the old scene's tables are released in one
//!    call, with no per-table free, and the pages are kept for the next one.
//!
//! No frame allocates.

const std = @import("std");
const canvas = @import("canvas.zig");
const fx = @import("fx.zig");

// wasm32-freestanding has nowhere to print a message, so a failed safety
// check (Debug, ReleaseSafe) traps; the host sees a RuntimeError with the
// stack. ReleaseFast compiles the checks out altogether.
pub const panic = std.debug.no_panic;

var fb: canvas.FB = .{ .w = 0, .h = 0, .pix = &.{} };
var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
var effect: fx.Effect = undefined;

/// Allocates a w x h framebuffer and returns its address in linear memory.
/// The host reads the pixels from there after every bb_render.
export fn bb_init(w: i32, h: i32) i32 {
    std.heap.wasm_allocator.free(fb.pix);
    const uw: usize = @intCast(w);
    const uh: usize = @intCast(h);
    const pix = std.heap.wasm_allocator.alloc(u32, uw * uh) catch @panic("out of memory");
    @memset(pix, 0); // as Go's make: transparent black until the first frame
    fb = .{ .w = uw, .h = uh, .pix = pix };
    return @intCast(@intFromPtr(pix.ptr));
}

/// Begins scene from a fresh state, so stateful scenes (the fire, the
/// starfield) replay the same history in every language. Unknown numbers
/// play the finale, as in Go.
export fn bb_start(scene: i32) void {
    _ = arena.reset(.retain_capacity);
    const last = @backingInt(fx.Effect.Tag.finale);
    const tag: fx.Effect.Tag = if (scene >= 0 and scene < last) @fromBackingInt(@intCast(scene)) else .finale;
    effect.begin(tag, arena.allocator(), fb.w, fb.h) catch @panic("out of memory");
}

/// Draws frame n (n >= 1) of the current scene.
export fn bb_render(n: i32) void {
    effect.render(fb, fx.State.at(@intCast(n)));
}
