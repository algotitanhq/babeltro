# Goose test bench — the plasma

A single effect ported from `go/internal/fx/plasma.go` to Goose, to find out
whether the tooling holds up before committing to a full port. The port is
faithful: at the same instant, the two renders differ by **2 pixels out of
921,600** (maximum difference 5/255, from f32/f64 rounding in the sine
table). The comparison is therefore about the same work.

Machine: M1, 8 cores, macOS 27. Goose built with the official compiler
(`goose build`), Go 1.27.2. 1280×720, 240 frames measured after 20 of warm-up.

## The numbers

| | median | Mpx/s |
| --- | ---: | ---: |
| Go, 1 worker | 1.53 ms | 600 |
| **Goose, 1 thread** | **1.48 ms** | **623** |
| Go, 8 workers (the demo's `bandPool`) | **0.46 ms** | **1,995** |
| **Goose, 8 threads** | **0.75 ms** | **1,230** |

At 2560×1440 the conclusion does not move: Goose serial 5.88 ms against Go
serial 6.09 ms.

## What it says

**Serially, Goose matches Go, or even beats it.** 1.48 ms against 1.53 ms,
with a gap that is stable run after run. This was not a given: a first
version, written with dynamic arrays (`u32[>..]`), ran in 2.02 ms — 36%
slower — because every index cost a bounds check and every float conversion
a call to `GS_F2I`. Switching to fixed arrays lets the compiler elide 62 of
79 checks and removes the calls.

**In parallel, Goose loses 63%.** And the cause is not the speed of the
generated code, it is the memory model. Goose forbids any memory shared
between threads (spec §11.2): a worker is a program instance with its own
copy of every global, and only *flat* values — no references, no slices —
cross a thread boundary. Concrete consequences:

- `Draw(fb, y0, y1)` writing its band of the shared framebuffer does not
  exist. A band has to be computed into a `u32[1280][90]`, sent back through
  the queue, then copied by `main`. Measured: **0.136 ms/frame** of pure
  copying.
- A typed queue (`qget<T>`) is a **shared work queue**, not a mailbox per
  worker. Post eight jobs and the first worker to arrive takes three, another
  none. So the job must name its band and `main` must reassemble by that
  field. This is what produced the 85,000 wrong pixels of the first attempt,
  fixed by reassembling by `y0`.
- Every worker keeps its own copy of the distance field: **8 × 3.7 MB**.

## The control that matters

To check that the parallel gap really follows from the model and not from my
code, I rewrote the same plasma **in Go**, but constrained to Goose's model:
persistent workers, private tables, band computed into a buffer and sent back
over a channel, `main` doing the copy.

| | median |
| --- | ---: |
| Native Go (the current `bandPool`) | 0.46 ms |
| Go constrained to the Goose model | **0.64 ms** |
| Goose, under the same model | **0.75 ms** |

Under the same model, Goose pays only a **17%** slowdown, and what remains is
the loop itself. The dominant overhead — 0.46 → 0.64 ms — is the price of the
model, not of the language.

## Verdict

The tooling holds: a compiler that builds itself, clear errors, FFI, readable
generated C, `bytes_of`/`write_file`, no crash in 240 frames. The language
keeps its promise of serial speed.

What it does not allow is writing the demo the way it is written today. The
`bandPool` — N goroutines, one shared framebuffer, zero copies — is the heart
of the demo's parallel argument, and Goose forbids it by construction. A full
port would be possible, but it would mean either accepting the copies through
the queue (and the demo would show a less flattering number), or rewriting
every effect to produce self-contained bands.

## Build and run

```sh
goose build plasma.goose -o plasma
./plasma
```

Prints both regimes, checks that the two renders are identical byte for byte,
and writes `plasma_goose.ppm` for comparison with the Go render.
