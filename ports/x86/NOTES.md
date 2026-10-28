# x86 assembly port: notes

The demoscene's own language. The effects are 32-bit x86 assembly (NASM
syntax, flat protected mode), assembled by `nasm -f bin` into a 17 KB raw
image. A browser cannot run that, so `cpu.c` is a small 386+SSE interpreter
compiled to wasm: it decodes only the instructions the program uses and
stops with a message on anything else. The emulated machine's 32 MiB live
inside wasm memory, so the lab reads the framebuffer the x86 code wrote,
with no copy. The memory map is at the top of `main.asm`. All nine scenes.

## How x86 assembly differs, scene by scene

- **STARFIELD**: the backdrop is copied with one `rep movsd`, and the
  streaks are a Bresenham loop with `neg` and `cmov` for the absolute
  values. The star generator is the xorshift32 macro FIRE uses.
- **TUNNEL**: one index register walks the depth table, the angle table and
  the framebuffer with scaled addressing, `[esi+ecx*4]`. There is no `atan2`
  either: it is an octant fold plus a 21-term atan series whose coefficients
  are computed once into memory, the sign bits tested as integers.
- **TUNNEL/1**: `sqrtss`, `divss` and a `call atan2_turns` per pixel, every
  frame, for values that never change.
- **PLASMA**: floats are SSE scalar (`movss`, `addss`, `mulss`,
  `cvttss2si`), never the x87. The x87 keeps 80-bit intermediates and
  rounds only when it stores, so `a*b+c` there is not Go's `a*b+c`; every
  SSE instruction rounds to its own width, once. There is no libm either:
  `fmath.asm` builds the sine table with a Cody-Waite reduction and a Taylor
  series in f64 (`cvtsd2si` rounds to nearest), equal to Go's bit for bit.
  The hot loop is 22 instructions a pixel, the index clamp two `cmov`s.
- **PLASMA/1**: every sine is a `call` into that f64 series, four a pixel:
  73 million instructions a frame at 640x360, against 5 for the default.
- **PLASMA/2**: the same loop with each call replaced by the four-instruction
  table lookup, `mulss`, `cvttss2si`, `and 8191`, `movss`.
- **ROTOZOOM**: the 1 MiB texture sits at a fixed address and is built on
  first use with a million f64 sine calls; `math.Mod(x, 1)` is
  `x - trunc(x)`, `cvttsd2si` then `cvtsi2sd`. The pixel loop wraps with
  `and 511` and finds the texel with a shift and an add.
- **METABALLS**: the six balls' centres and radii go to a fixed table once
  per frame, and the pixel loop walks it with a pointer, `[edx]`, `[edx+4]`.
- **GRID**: Go mixes float32 and float64 here; `ss` and `sd` instructions
  follow it op by op, with `cvtss2sd` where Go widens. The f32 clamp is two
  `comiss`, not `maxss`, so a -0 stays -0 as in Go.
- **FIRE**: the scene x86 was born for: bytes, shifts and `movzx`. The
  xorshift32 lives in `ebx` all frame, `r % 3` is a real `div`, the edge
  clamps are `cmov`s, and the buffer is cleared by a single `rep stosb`.
- **MANDELBROT**: f64 throughout (`mulsd`, `addsd`, `comisd`); `exp` is
  written from scratch (reduction by ln2, Taylor series, 2^k built from its exponent
  bits). Each block is filled with `rep stosd`, and the rung picks the
  iteration routine through a `call [M_FN]`.
- **MANDELBROT/1**: the plain escape loop, z and its squares held in four
  xmm registers.
- **MANDELBROT/2**: the cardioid and bulb tests, then a `jmp` into the plain
  loop.
- **FINALE**: the 5x7 font is the one table shipped as data (`font.asm`,
  `db` rows). One walker visits a glyph's lit dots and calls a block
  handler through `call [T_FN]`: solid, gradient with scanlines, or the
  additive reflection, whose rows run upward by giving the walker a negative
  row step. Signed layout maths uses `cdq`/`idiv`, and `/2` is the classic
  `cdq; sub eax, edx; sar eax, 1`. The name is a NASM `%define`.

## Pixel differences

Only the name. Every scene and rung matches C exactly (0 differing pixels)
at 640x360 on frames 1, 60 and 300, and every scene but the finale at
160x90 on 1, 2, 60 and 300 and at 1280x720 on 1 and 600. FINALE differs
only inside the wordmark and its reflection, which spell `X86`; a scratch
build spelling `C` (`X86_LANG=C OUT=... ports/x86/build.sh`) matches the C
finale exactly at 640x360 and 160x90. Instructions retired per frame at
640x360 (frame 300): STARFIELD 0.5 M, TUNNEL 11.1 M (rung 1: 42.7 M),
PLASMA 5.1 M (73.3 M, 12.0 M), ROTOZOOM 5.5 M, METABALLS 24.5 M, GRID
19.8 M, FIRE 8.1 M, MANDELBROT 12.7 M (357.6 M, 48.7 M), FINALE 4.0 M. The
emulator runs some 125 emulated MIPS: a 486 would have been proud.
