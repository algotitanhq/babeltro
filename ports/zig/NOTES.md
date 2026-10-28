# Zig port: notes

Layout: `fmath`, `palette` and `canvas` are the shared helpers, one file per
scene, `fx.zig` for the scene union and `main.zig` for the exports. Build:
`scripts/build-zig.sh` (`zig build --release=fast`). The target is
wasm32-freestanding: nothing here reads a file or a clock, so WASI would bring
nothing, and the module imports nothing. The sine tables, the palettes and
the font are computed by the compiler and ship as data. The framebuffer comes
from `std.heap.wasm_allocator`. Each scene's tables come from an
`ArenaAllocator` that the next `bb_start` resets in one call. No frame
allocates. `bb_step` reaches only the scenes that declare `setStep`. Go asks
that with a type assertion at run time; here `@hasDecl` asks it at compile
time.

## How Zig differs, scene by scene

- **STARFIELD**: the stars and their streaks are fixed-size arrays inside the
  scene struct. A float literal takes the type of the other operand, so
  `1.0 / p.z` stays f32 with no suffix to forget.
- **TUNNEL**: one `for (fb.pix, t.depth, t.angle)` loop walks the three
  buffers in step. The lengths are checked once, so there is no index and no
  per-pixel bounds check.
- **PLASMA/1**: Go has only a float64 `math.Sin`, so its rung rounds each
  sine back to float32, and this port does the same. Zig's `@sin` also takes
  an f32 directly. A scratch build using it gave 0 differing pixels at four
  sizes and ran about 12% faster.
- **PLASMA**: Go's `sxy[y : y+w]` is `sxy[y..][0..w]`, and the pixel loop runs
  over four slices at once.
- **ROTOZOOM**: the 1 MiB texture is a static `[512*512]u32`, built the first
  time the scene starts. It is not built at comptime: that would take minutes
  and add a megabyte to the module. `math.Mod` is `@rem`.
- **METABALLS**: the ball offsets are computed once per frame instead of once
  per pixel. The values are the same, so the pixels are too. `inline for`
  unrolls the six balls at compile time.
- **GRID**: Zig widens f32 to f64 implicitly but never narrows, so every
  `float32(...)` in Go is an explicit `@floatCast` here. The floor constants
  are an optional `?FloorRow`. `v - float32(int(v))` becomes `v - @trunc(v)`,
  which gives the same bits.
- **FIRE**: `-|` (saturating subtraction) replaces Go's `if v > decay`
  branch.
- **MANDELBROT**: a literal port. Each block row is one `@memset`.
- **MANDELBROT/1**: the iteration function is a `comptime` parameter of the
  block loop. Each rung gets its own compiled copy that calls its function
  directly, where Go assigns a func value and C calls through a pointer.
- **FINALE**: the name comes from a build option (`-Dlang`, default `ZIG`).
  `"EVERY PIXEL IS " ++ lang` is joined at compile time, and the wave offsets
  are a `[lang.len]i32`. The compiler parses the font from the same text as
  Go's, so only the bitmaps ship.

## Pixel differences

None outside the language name. Every scene other than FINALE matches Go
exactly (0 differing pixels) at 640x360 on frames 1, 2, 60 and 300, at
1280x720 on frames 1 and 600, at 1920x1080 on frames 1 and 900, and at
333x211 on frames 1, 7 and 1000. Every rung of the PLASMA, TUNNEL and
MANDELBROT ladders matches Go's rung exactly at 640x360 and 1280x720. The
FINALE logo and subtitle spell `ZIG`. A scratch build with `-Dlang=GO` matches Go's finale exactly at all four
sizes. Debug and ReleaseSafe builds give the same pixels, and no safety check
fires (overflow, bounds or `@intFromFloat` range).

The maths library changed no pixel. Here that means `@sin`, `@cos`, `@exp`
and `@rem`, which Zig's own compiler_rt implements, and `std.math.atan2`. The
comptime sine and cosine tables match Go's bit for bit in all 8193 entries,
and so do the same tables computed at run time in wasm.
