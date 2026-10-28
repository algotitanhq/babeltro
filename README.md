# babeltro

Nine classic demoscene effects — starfield, tunnel, plasma, rotozoom,
metaballs, synthwave grid, fire, Mandelbrot, a logo card — written in several
languages and run side by side in the browser. Babel for the languages,
"-tro" for the intro.

The point is not which language wins. It is to see how each one approaches
the same effect, and what it takes to make it produce **the same pixels**:
float widths, fused multiply-adds, float-to-int conversion, bounds checks,
evaluation order, the maths library.

## The lab

```sh
cd web
npm install
../scripts/build-all.sh   # builds every wasm port into web/public/wasm
npm run dev
```

One screen: pick an effect, a language, and a second language to compare
with. The lab counts the differing pixels every frame and can paint them in
magenta; under the canvases, each language's hot loop and a note on how that
language does it differently. Every pane runs in its own worker.

Keys: `Space` pause, `←`/`→` effect, `.` one frame, `R` restart, `D`
differences, `1`–`4` compare with a language, `Shift`+`1`–`4` main language.

## Ports

| Directory | Language | How it runs in the browser | Pixels vs Go |
| --- | --- | --- | --- |
| `go/` | Go | wasm (`GOOS=wasip1`, reactor) — the reference | — |
| `ports/c/` | C17 | wasm via clang + wasi-libc | identical ¹ |
| `ports/rust/` | Rust | wasm32-unknown-unknown, no dependencies | identical ¹ |
| `zig/` | Zig | wasm32-freestanding, comptime tables | identical ¹ |
| `ports/js/` | JavaScript | plain ES modules, no wasm | identical ¹ |
| `goose/` | Goose | test bench, PLASMA only, native (see `goose/RESULTS.md`) | — |

¹ Every scene at every size tested, except the finale, which spells the
language's name: the logo's size follows the name's width, and the card is
laid out around it.

Each port has a `NOTES.md` with what it does differently, scene by scene.
The contract every port follows, and how to add a language, is
`spec/ABI.md`. `go/` also still builds the original native demo (window,
HUD, worker pool): see `go/README.md`.

## Checking a port

```sh
node tools/check.mjs c rust js                  # every scene against Go
node tools/check.mjs --scene 2 --at 1,600 c     # one scene, chosen frames
node tools/check.mjs --png /tmp/diff rust       # also write ref/port/diff PNGs
```
