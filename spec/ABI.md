# The port contract

Every language port is a module the browser lab drives through the same
three calls. The C port (`ports/c`) is the reference: a port is correct
when, for every scene and every frame, its framebuffer is byte-identical to
C's — except where the image spells the language's name.

## Exports

A WebAssembly port exports:

| Export | Signature | Meaning |
| --- | --- | --- |
| `memory` | memory | linear memory holding the framebuffer |
| `_initialize` | `() -> ()` | optional; called once by the host before anything else |
| `bb_init` | `(w: i32, h: i32) -> i32` | allocate a `w×h` framebuffer, return its byte address |
| `bb_start` | `(scene: i32) -> ()` | begin `scene` from a fresh state |
| `bb_render` | `(n: i32) -> ()` | draw frame `n` of the current scene into the framebuffer |

A port may also export `bb_step(n: i32)`: the rung of the scene's
optimisation ladder, called after `bb_start` (0, the default, is the
optimised version). A port may import the `wasi_snapshot_preview1` functions the host shim
provides (`web/src/host/wasi.js`). None of them may influence the pixels.

A port that runs as JavaScript — the JavaScript port itself, or any
language that brings its own interpreter compiled to wasm (Python, Perl,
SQL…) — is instead an ES module at `ports/<lang>/port.js` exporting:

| Export | Meaning |
| --- | --- |
| `load()` | optional, async: fetch and start the interpreter |
| `scenes` | optional: the scene numbers the port implements (default: all) |
| `init(w, h)` | allocate the framebuffer and return it, a `Uint32Array` |
| `start(scene)`, `step(n)`, `render(n)` | as above; `render` may return a promise |
| `framebuffer()` | optional: the current framebuffer, if it can change |

## Layout of a port

`ports/<lang>/` holds the sources, a `NOTES.md` (one bullet per scene,
`- **SCENE**: text`, which the lab shows above the code) and either a
`build.sh` writing `web/public/wasm/<lang>.wasm` or a `port.js`. Each effect
marks its hot loop between `@excerpt SCENE` and `@end` comments (rungs of
a ladder: `@excerpt SCENE/k`). The lab also needs an entry in
`web/src/content.js` (`LANGS`): name, colour, highlighter grammar, one
line on how it reaches the browser, and `scenes` for a partial port.

## Pixels

`w*h` little-endian `u32` values, row-major, top row first, packed as
`0xAABBGGRR` with alpha always `0xFF`. In memory that is R, G, B, A bytes:
exactly an `ImageData` buffer, so the host copies without converting.

## Time

The host calls `bb_start(scene)`, then `bb_render(1)`, `bb_render(2)`, … with
no gaps: the fire and the starfield carry state from frame to frame. Frame
`n` is at a fixed 60 Hz step, never a clock:

```
T = Beat = n / 60      (float64)
DT       = 1 / 60      (float64)
Frame    = n
```

## Scenes

| # | Scene | Reference |
| --- | --- | --- |
| 0 | STARFIELD | `go/internal/fx/starfield.go` |
| 1 | TUNNEL | `go/internal/fx/tunnel.go` |
| 2 | PLASMA | `go/internal/fx/plasma.go` |
| 3 | ROTOZOOM | `go/internal/fx/rotozoom.go` |
| 4 | METABALLS | `go/internal/fx/metaballs.go` |
| 5 | GRID | `go/internal/fx/grid.go` |
| 6 | FIRE | `go/internal/fx/fire.go` |
| 7 | MANDELBROT | `go/internal/fx/mandelbrot.go` |
| 8 | FINALE | `go/internal/fx/finale.go` |

Shared helpers live in `go/internal/fmath` (sine table, xorshift32),
`go/internal/palette` (256-colour ramps) and `go/internal/canvas`
(framebuffer, 5×7 font, logo text). In the wasm build the finale has no HUD
to avoid (`fx.PanelBottom = nil`) and its tag reads
`ONE THREAD - NO GPU - NO SHADER`.

## What "the same image" takes

These are the places where languages silently disagree. A port follows the
Go code on each of them; when it cannot, the difference is reported, not
hidden.

- **Float widths.** Every `float32` in Go is a 32-bit float in the port and
  every `float64` a 64-bit one, including intermediate results. In JS that
  means `Math.fround` after every `float32` operation.
- **No fused multiply-add.** wasm never fuses `a*b+c` on its own; a port must
  not ask for it either (C: `-ffp-contract=off`).
- **Float to int.** Go truncates toward zero. Values the Go code does not
  clamp first are out of range nowhere in the reference; a port must not
  rely on its own language's behaviour there (C: undefined; Rust:
  saturating; JS: `| 0` wraps).
- **Integers.** Go's `int` is 64-bit on wasm. Unsigned arithmetic wraps
  (Rust: `wrapping_*`). Shifts follow Go: `x >> s` on a signed value is
  arithmetic.
- **Evaluation order.** Go evaluates operands and struct fields left to
  right. Where an expression calls the random generator more than once, the
  port sequences the calls explicitly (C leaves initialiser order unspecified).
- **Random numbers.** Only `fmath.Rng` (xorshift32, `Float32` from the top
  24 bits) and the fire's own xorshift32. Same seeds, same call order.
- **Maths library.** `sin`, `cos`, `atan2`, `exp`, `sqrt`, `floor`, `mod`
  come from each language's own library. `sqrt` and `floor` are exact
  everywhere; the others may differ in the last bit. A port uses its
  language's library rather than copying Go's, and the lab reports what that
  costs in pixels.

## Language name

The finale spells the language's name, in capitals: `GO`, `C`, `RUST`,
`JAVASCRIPT`. Those pixels are the only intended difference.
