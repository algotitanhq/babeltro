# x86 assembly port: notes

The demoscene's own language. The effects are 32-bit x86 assembly (NASM
syntax, flat protected mode), assembled by `nasm -f bin` into a 3.5 KB raw
image. A browser cannot run that, so `cpu.c` is a small 386+SSE interpreter
compiled to wasm: it decodes only the instructions the program uses and
stops with a message on anything else. The emulated machine's 32 MiB live
inside wasm memory, so the lab reads the framebuffer the x86 code wrote,
with no copy. The memory map is at the top of `main.asm`. Two scenes,
PLASMA (with its ladder) and FIRE; the rest draw nothing.

## How x86 assembly differs, scene by scene

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
- **FIRE**: the scene x86 was born for: bytes, shifts and `movzx`. The
  xorshift32 lives in `ebx` all frame, `r % 3` is a real `div`, the edge
  clamps are `cmov`s, and the buffer is cleared by a single `rep stosb`.

## Pixel differences

None. PLASMA (all three rungs) and FIRE match C exactly (0 differing
pixels) at 640x360 on frames 1, 60 and 300, at 160x90 on 1, 2, 60 and 300,
and at 1280x720 on 1 and 600. The emulator retires about 5.1 million x86
instructions per PLASMA frame and 8.1 million per FIRE frame at 640x360,
some 125 emulated MIPS: a 486 would have been proud.
