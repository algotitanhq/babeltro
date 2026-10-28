//! Builds the Zig port as a WebAssembly module for the lab:
//!
//!     zig build --release=fast            zig-out/bin/babeltro.wasm
//!     zig build --release=fast -Dlang=GO  the same, spelling GO
//!     zig build -Doptimize=safe           with every safety check
//!
//! The target is wasm32-freestanding: the effects read no file, no clock and
//! no environment, so they need nothing from WASI, and the module imports
//! nothing at all.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });

    // The name the finale spells. Changing it is how a scratch build proves
    // that the name is the finale's only difference from Go.
    const options = b.addOptions();
    options.addOption([]const u8, "lang", b.option([]const u8, "lang", "language name on the finale card") orelse "ZIG");

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // DWARF would be nine tenths of a release module
        .strip = optimize != .debug,
    });
    root.addOptions("config", options);

    const wasm = b.addExecutable(.{ .name = "babeltro", .root_module = root });
    wasm.entry = .disabled; // a reactor: no main, the host calls the exports
    // export exactly the ABI; memory is exported by default
    root.export_symbol_names = &.{ "bb_init", "bb_start", "bb_render" };
    b.installArtifact(wasm);
}
