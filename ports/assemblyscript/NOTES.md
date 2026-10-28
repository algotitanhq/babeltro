# AssemblyScript port: notes

TypeScript syntax, compiled straight to wasm by `asc`. There is no JS glue
and the module imports nothing. Unlike JavaScript, it has Go's number types:
`f32` and `f64` are separate, and an `f32` expression runs on wasm's `f32`
instructions, so there is no `Math.fround` anywhere. Literals take their type
from context: in `x * 0.5`, with `x` an `f32`, `0.5` is an `f32` constant, as
in Go. The trap is a literal that comes first with no `f32` context. It is
then an `f64` and the whole expression is computed in `f64`, so every float
local here has its type written out. The runtime is `minimal`: TLSF
allocation, and a collector that runs only when `bb_start` calls
`__collect()` between scenes (see `build.sh`).

## How AssemblyScript differs, scene by scene

- **STARFIELD**: the stars are parallel `StaticArray<f32>`s, flat runs of
  numbers with no object per star. `<i32>x` truncates toward zero like Go's
  `int32()`. The three random draws are separate statements, in Go's order.
- **TUNNEL**: the depth and angle tables have the framebuffer's length. The
  loop reads them with `unchecked()`, which drops a bounds check that could
  never fail. `Mathf.sqrt` is the correctly rounded `f32.sqrt`, so it equals
  Go's `float32(math.Sqrt(float64(v)))`.
- **PLASMA**: the table `sin()` is an `@inline` function, so calling it in
  the pixel loop costs nothing. The JS port had to inline the table read by
  hand. All the table reads are `unchecked()`. Built with
  `--uncheckedBehavior never`, which puts the checks back, the loop takes
  0.92 ms instead of 0.49 ms at 640x360 (TUNNEL: 1.52 ms against 0.88 ms).
- **PLASMA/1**: `<f32>Math.sin(<f64>a)` is Go's `float32(math.Sin(...))`
  word for word, with no `Math.fround`. Here `Math` is AssemblyScript's own
  f64 library compiled into the module, not V8's: software, like Go's, yet
  it ran in a third of Go's time (27.6 ms against 83 ms, same run).
- **ROTOZOOM**: the texture index is masked to 0..511, so the read is
  `unchecked()`. `%` on an `f64` is fmod, which keeps the dividend's sign as
  `math.Mod` does. The texture is built once per module, not once per
  scene start.
- **METABALLS**: `1e-5` and `1.09` are typed `f32` by their context, which is
  the rounding Go applies. The JS port needs `f32()` on each constant.
- **GRID**: Go's `v - float32(int(v))` becomes `v - Mathf.trunc(v)`, the same
  value with no float→int round trip. Each `f64` step has its own `f64`
  local, because inside `<f32>(0.03 + …)` the leading literal would become an
  `f32`.
- **FIRE**: `r % 3` on a `u32` is the unsigned remainder, and `u8`
  arithmetic does not wrap below zero because `v > decay` is tested first.
  The xorshift is an `@inline` method.
- **MANDELBROT**: Go passes the escape function as a func value.
  AssemblyScript could do the same, but every call would be a
  `call_indirect`. A flag tested once per block lets both loops inline.
- **FINALE**: the font is a `StaticArray<u8>` literal, laid out in a data
  segment: no code runs to build it. Go parses it from text at init.
  `ASSEMBLYSCRIPT` (14 letters) is spelt out. The 45% width limit gives it
  scale 3 at 640x360, still readable, and the subtitle fits with its rules.

## Pixel differences

None outside the language name. All eight non-text scenes are byte-identical
to Go at 640x360 (frames 1, 2, 60, 300), 1280x720 (1, 600), 1920x1080 (1,
900) and 333x187 (1, 7, 1000). So is every rung of the PLASMA, TUNNEL and
MANDELBROT ladders at 640x360. AssemblyScript's own `sin`, `cos`, `atan2`
and `exp` cost no pixel.

FINALE differs over most of the card. `ASSEMBLYSCRIPT` is 83 font columns
wide against 11 for `GO`, so the logo is smaller and everything below it
moves up. A scratch build with `LANG = 'GO'` matches the C reference exactly (0 differing
pixels) at 640x360, 1280x720, 1920x1080, 320x200 and 333x187, frames 1, 2,
60, 300 and 601.
