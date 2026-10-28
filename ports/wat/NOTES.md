# Hand-written WebAssembly port: notes

No compiler: the effects are written directly in the WebAssembly text format,
one file per scene, and `build.sh` wraps them in one `(module ...)` for
`wat2wasm`. Only multi-value and bulk memory are enabled. The memory map is at
the top of `memory.wat`. Six scenes; STARFIELD, GRID and FINALE are not ported.

## How hand-written WebAssembly differs, scene by scene

- **PLASMA**: no `sin` instruction exists, so `fmath.wat` builds the 8193-entry
  tables at instantiation (the `start` function) with a hand-written Taylor
  series behind a Cody-Waite range reduction. That costs a few hundred bytes
  where a data segment would cost 64 KiB, and all 8193 sin and 8193 cos
  entries equal Go's float32 tables bit for bit. The hot loop walks four
  pointers side by side; Go's slice `sxy[y : y+w]` is just `sxy + 4*y`.
- **PLASMA/1**: the "maths library" sine is our own `$sin64`, rounded with
  `f32.demote_f64` as Go rounds `math.Sin`.
- **PLASMA/2**: the same loop reading the table: the index is `i32.trunc_f32_s`
  (truncates toward zero like Go's `int()`, traps out of range) and `& 8191`.
- **TUNNEL**: one flat byte offset addresses the framebuffer and both tables.
  `atan2` does not exist either: it is an octant fold plus a 21-term atan
  series whose coefficients are computed once into memory.
- **TUNNEL/1**: the square root is the `f32.sqrt` instruction, correctly
  rounded; the atan2 is the hand-written one, per pixel.
- **ROTOZOOM**: the 1 MiB texture lives at a fixed address and is built on
  first use with about a million `$sin64` calls; `math.Mod(x, 1)` is
  `x - f64.trunc(x)`, and `hsl2rgb` returns three values on the stack.
- **METABALLS**: the per-ball offsets are computed once per frame into memory;
  the pixel loop reads them with `offset=` immediates.
- **FIRE**: the heat buffer is cleared with one `memory.fill`. Unsigned maths
  is spelled out: `i32.shr_u`, `i32.rem_u`, `i32.load8_u`.
- **MANDELBROT**: `exp` is hand-written too (range reduction by ln2, Taylor
  series, 2^k assembled from its exponent bits). Each block's first row is
  drawn and the rows under it are `memory.copy`'d.
- **MANDELBROT/1**: the plain escape loop, a `block`/`loop` pair with `br_if`.
- **MANDELBROT/2**: the cardioid and bulb tests, then a call to the plain loop.

## Pixel differences

None. Every ported scene and rung matches Go exactly (0 differing pixels) at
640x360 on frames 1, 2, 60 and 300, at 1280x720 on 1 and 600, at 1920x1080 on
1 and 900, and at 333x211 on 1, 7 and 1000. The hand-written `exp` differs
from Go's `math.Exp` by one ulp in 78 of the 2000 calls of frames 1..1000;
none of the frames checked shows a pixel difference.
