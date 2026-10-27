# babeltro — the Go port (reference)

A demoscene intro computed entirely on the CPU, written in Go.

Every pixel of every scene comes out of a Go loop. The graphics card does one
thing only: show the finished frame as a single textured quad. No shader, no
game engine, no external Go dependency — just the standard library, two
hand-written cgo bindings (GLFW and OpenGL 2.1), and a `[]uint32`
framebuffer.

The instrumentation on screen at all times is not decoration: it is the
demo's thesis. It measures, frame by frame, the real CPU time against the
16.67 ms budget of a 60 Hz display.

## Running

```sh
go build -o babeltro ./cmd/babeltro
./babeltro                # 1280x720, 8 goroutines
./babeltro -fs            # fullscreen
./babeltro -w 1920 -h 1080
```

`go run ./cmd/babeltro` works too, but a compiled binary starts faster.

| Key | Action |
| --- | --- |
| `Esc` | quit |
| `H` | hide/show the instrumentation |
| `S` | next scene |
| `→` / `←` | next / previous scene |
| `F` | fullscreen |
| `F1` | (re)start from the beginning |

Other modes:

```sh
./babeltro -list                        # scenes and their durations
./babeltro -bench -w 1280 -h 720        # measured cost of each effect
./babeltro -dump /tmp/shots -at 5       # render PNGs without a window (visual iteration)
./babeltro -scene 4                     # start at a given scene
./babeltro -stats                       # live measurements on stdout, once a second
./babeltro -stats -dur 30               # same, and quit after 30 s
```

On a Retina display, the 1280×720 window covers 2560×1440 physical pixels:
that is the resolution the demo computes.

## The scenes

| # | Scene | What the CPU does |
| --- | --- | --- |
| 1 | STARFIELD | 2400 stars projected in perspective, additive Bresenham trails |
| 2 | TUNNEL | tabulated polar coordinates, procedural texture, fog |
| 3 | PLASMA | four sine fields in tables, one tabulated sine per pixel |
| 4 | ROTOZOOM | a 512×512 texture generated at startup, sampled while rotating |
| 5 | METABALLS | six `r²/d²` fields per pixel, iso-surface and rim |
| 6 | GRID | synthwave floor by perspective division, striped sun |
| 7 | FIRE | propagation automaton, `uint8` buffer, palette |
| 8 | MANDELBROT | a dive into the seahorse valley, 2×2 blocks, adaptive iterations |
| 9 | FINALE | gradient logo, reflection, text — all pixels |

## Why it is fast

A few principles, all visible in the code:

**Look up rather than compute.** `internal/fmath` holds an 8192-entry sine
table; the effects read it instead of calling `math.Sin`. The tunnel
precomputes `1/r` and `atan2` once per screen size, not once per pixel.

**Precompute what does not move.** The starfield background is painted once
into a buffer, then copied with `copy` every frame: 0.15 ms instead of
2.8 ms. Palettes are 256-colour ramps built at load time, then indexed by an
`int`.

**Hoist invariants out of loops.** In the grid, everything that depends only
on the row (perspective division, fog, line period) is computed once per row;
the pixel loop keeps a single multiplication and two lookups.

**Parallelise without allocating.** `internal/engine/pool.go` starts N
persistent goroutines that share the frame as horizontal bands. No goroutine
or closure is created per frame: the pool is built at startup and reused.

**Zero allocations per frame.** The HUD formats its numbers into a reused
`[512]byte`. Effects own their buffers and resize them only when the window
changes. The instrumentation shows the result: `0 B/FRAME`.

**Accept the honest trade-off.** The Mandelbrot is rendered on a stretched
2×2-pixel grid, and its iteration budget follows the zoom: 64 when the view is
wide, 192 when the boundary has to hold. In motion nobody sees the grid, and
the cost stays within budget. The demo does not cheat on what it measures: it
chooses what it computes.

## The numbers

Measured by `./babeltro -bench` (240 frames per effect, the first 24
discarded), on an 8-core M1:

**1280×720 (0.92 Mpx)**

| Scene | median | best | Mpx/s |
| --- | ---: | ---: | ---: |
| STARFIELD | 0.19 ms | 0.15 ms | 4,742 |
| TUNNEL | 0.86 ms | 0.82 ms | 1,076 |
| PLASMA | 0.46 ms | 0.41 ms | 1,987 |
| ROTOZOOM | 0.35 ms | 0.31 ms | 2,612 |
| METABALLS | 1.63 ms | 1.57 ms | 565 |
| GRID | 1.85 ms | 1.53 ms | 500 |
| FIRE | 2.79 ms | 2.67 ms | 330 |
| MANDELBROT | 1.65 ms | 1.38 ms | 560 |
| FINALE | 1.22 ms | 1.21 ms | 757 |

The 60 Hz budget is 16.67 ms. The heaviest effect uses 2.8 of it: six times
under budget, for 0.92 million pixels computed by hand.

**2560×1440 (3.69 Mpx, the real window size on Retina)**

| Scene | median | best | Mpx/s |
| --- | ---: | ---: | ---: |
| STARFIELD | 0.62 ms | 0.52 ms | 5,939 |
| TUNNEL | 3.16 ms | 3.05 ms | 1,168 |
| PLASMA | 1.52 ms | 1.45 ms | 2,433 |
| ROTOZOOM | 1.13 ms | 1.08 ms | 3,260 |
| METABALLS | 6.26 ms | 6.16 ms | 589 |
| GRID | 7.08 ms | 6.01 ms | 521 |
| FIRE | 7.82 ms | 7.65 ms | 471 |
| MANDELBROT | 3.21 ms | 2.61 ms | 1,150 |
| FINALE | 4.76 ms | 4.72 ms | 775 |

Four times the pixels: the heaviest effect goes from 2.8 to 7.8 ms and still
holds 60 Hz at full Retina resolution, with no GPU, computing every pixel in
a goroutine.

## Layout

```
cmd/babeltro/       main: window, loop, flags, -dump mode, -bench mode
internal/brand/     the words on screen that change from one port to another
internal/glfwc/     GLFW binding + app activation (Objective-C)
internal/glc/       OpenGL 2.1 binding: a single textured quad
internal/canvas/    framebuffer, primitives, 5×7 bitmap font
internal/palette/   256-colour ramps
internal/fmath/     trigonometric and polar tables
internal/fx/        the nine effects, one common interface
internal/engine/    clock, timeline, band pool, measurement
internal/hud/       the hand-drawn instrumentation
```

An effect implements four methods: `Name`, `Resize`, `Prepare` (once per
frame, single-threaded, builds that frame's tables) and `Draw(fb, y0, y1)`
(one band, called in parallel). That is the whole contract.

## What it shows

That everyday Go — no explicit SIMD, no `unsafe` in the hot loops, no
compiler tricks — holds a million pixels per frame at 60 Hz when written the
way Go is written: clear, tabulated, parallel where it counts, and measured
honestly.
