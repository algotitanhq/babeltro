# C port: notes

Layout: `fmath`, `palette` and `canvas` (with `font.c`) are the shared helpers,
one `.c` file per scene, `fx.h` for the scene interface, `main.c` for the wasm
exports. Each scene keeps its state in file-scope statics, since there is only
ever one of each. Build: `scripts/build-c.sh`.

## How C differs, scene by scene

- **STARFIELD**: the 1600 stars and their streaks are fixed-size static
  arrays, so nothing is allocated at all. Each star's three random draws are
  separate statements, because C leaves the evaluation order of an
  initialiser list unspecified. `1.0f / z` needs its suffix: a bare `1.0`
  would quietly turn the projection into double arithmetic.
- **TUNNEL**: the depth and angle tables have the same layout as the
  framebuffer, so the loop walks all three with one flat index. `restrict`
  tells the compiler the three never alias, which Go cannot express.
- **TUNNEL/1**: `sqrtf` is correctly rounded, so it is Go's
  `float32(math.Sqrt(...))` without the round trip through double.
- **PLASMA**: Go's `sxy[y : y+w]` slice becomes the pointer `P.sxy + y`.
- **PLASMA/1**: C has a float sine, `sinf`, so the naive version calls it
  directly; Go has only `math.Sin` and rounds its double result to float32.
  wasi-libc's `sinf` is not guaranteed correctly rounded, yet it changed no
  pixel against the reference's rung (640x360, 1280x720, 1920x1080, 333x211).
- **ROTOZOOM**: the 1 MiB texture lives in static storage and is built once
  per module, not once per scene start. `math.Mod` is `fmod`. Go rounds the
  texture coordinates to float32 before using them in double maths; the
  `(float)` casts keep that.
- **METABALLS**: the ball offsets `(ball - 0.5) * asp` are computed once per
  frame. Go computes them again for every pixel. The values are the same, so
  the pixels are too.
- **GRID**: this scene mixes float32 and float64 the most. In Go every
  conversion is written out. In C promotion happens implicitly, so the
  risk runs the other way: one unsuffixed literal would turn a float32
  expression into a double one. Every float32 constant has an `f` suffix,
  and `clampf` marks the places where Go clamps in double.
- **FIRE**: the same code as Go. `uint8_t` values promote to `int` in
  arithmetic, so `v - decay` cannot wrap.
- **MANDELBROT**: double is C's default floating type, so this is the most
  literal port of the nine.
- **FINALE**: `"EVERY PIXEL IS " LANG` is joined at compile time, and
  `sizeof` gives the logo's length. The font is a table built with
  designated initialisers (`['A' - 32] = {...}`), not text parsed at startup.

## Pixel differences

None outside the language name. Every scene other than FINALE matches the C reference
exactly (0 differing pixels) at 640x360 on frames 1, 2, 60 and 300, at
1280x720 on frames 1 and 600, at 1920x1080 on frames 1 and 900, and at
333x211 on frames 1, 7 and 1000. In FINALE the logo and subtitle spell `C`
instead of `GO`. To check that this is the only cause, a scratch build with
`LANG` set to `"GO"` was tested: it matches the Go finale exactly at 640x360,
1280x720 and 1920x1080.

The maths library (wasi-libc's `sin`, `cos`, `atan2`, `exp` and `fmod`,
instead of Go's own) changed no pixel on any frame tested. Last-bit
differences may still exist, but none of them reached a pixel.
