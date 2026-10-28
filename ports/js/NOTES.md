# JavaScript port: notes

Plain ES modules, no WebAssembly, no dependencies. JS has one number type,
float64. That makes Go's `float64` code a direct transcription. Every `float32`
operation is wrapped in `Math.fround` (aliased `f32`), and float32 state lives
in `Float32Array`s, which round when a value is stored. For `+ - * /` and
`sqrt`, computing in float64 and rounding once gives exactly the float32
result. Go's `int(x)` becomes `x | 0`: it truncates toward zero, and every
value the effects convert is far inside the int32 range. It is also
measurably faster in V8 than `Math.trunc`.

**What the browser does not give you: float32 arithmetic.** Every
`Math.fround` is a float64→float32→float64 conversion pair, and the pairs add
up along dependent chains. Removing them from the tunnel (which gives wrong
pixels) makes it about 2x faster. This is why ROTOZOOM, almost pure float32
arithmetic, is the one scene clearly slower than Go's wasm.

## Effects

- **STARFIELD**: the stars are parallel `Float32Array`s rather than an array
  of objects. Storing a float into an `Int32Array` truncates like Go's
  `int32()`. xorshift32 uses `<<` (wraps like uint32), `>>>` (Go's logical
  shift on uint32) and a final `>>> 0`.
- **TUNNEL**: the hot loop indexes `SIN_TAB` directly instead of calling
  `sin01()`. V8 inlines the call, but the loop still ran about 2.5x slower with
  it (measured, Node 23).
- **PLASMA**: the pixel loop reads `SIN_TAB` inline rather than through
  `sin()`: the helper call, though inlined by V8, made the loop about 2.8x
  slower (2.5 ms against 0.9 ms).
- **PLASMA/1**: `Math.sin` on a float32 argument, each result wrapped in
  `f32` like Go's `sin32`. It matches Go pixel for pixel at 640x360,
  1280x720, 1920x1080 and 333x187: whatever V8's and Go's sines differ by does
  not survive the float32 rounding and the 256-level quantisation. It is about
  2x faster than Go's wasm (10 ms against 22 ms at 640x360): wasm has no sine
  instruction, so Go's `math.Sin` is software, while V8's is native code.
- **PLASMA/2**: calling the table `sin()` helper four times per pixel costs
  5.7 ms, against Go's 1.7 ms: the helper-call cost described above, paid
  four times per pixel.
- **ROTOZOOM**: the row terms `dy*sinA` and `dy*cosA` are hoisted. The values
  are the same, so the pixels are too. The texture's `math.Mod` is JS `%`,
  which also takes the sign of the dividend.
- **METABALLS**: the per-ball offsets are hoisted into `Float32Array`s. The
  comparison constants (`1.09`, `1e-5`) are rounded with `f32` once, because
  comparing a float32 with the double `1.09` gives a different answer.
- **GRID**: Go subtracts the row's line glow from each pixel. That term
  depends only on the row, so it is computed once per row with the same
  float32 roundings. `mod1` uses `Math.trunc`, which has no int32 limit.
- **FIRE**: the generator is inlined, and its state is kept in a local
  `x32` (int32 bits) for the whole frame. `r % 3` and `(r >>> 16) & 1` are
  computed on `x32 >>> 0`, the uint32 value. Go's `uint64` frame counter is a
  plain number: no `BigInt`.
- **MANDELBROT**: all float64, so this is a line-for-line transcription.
  `(-0.743643887037151 + 0.5)` is folded exactly by Go's constant arithmetic
  and rounded by JS. It was checked to give the same double.
- **FINALE**: the font is parsed from the same text table with `String.raw`,
  which keeps the `\` glyph intact. Integer divisions are written
  `(a / b) | 0`. The per-letter wave offsets go into a reused `Int32Array`,
  whose stores truncate.

## Pixel differences

None outside the language name. All eight non-text scenes are byte-identical to
Go at 640x360 (frames 1, 2, 60, 300), 1280x720 (1, 600), 1920x1080 (1, 900)
and 333x187, and so is every rung of the PLASMA, TUNNEL and MANDELBROT
ladders at 640x360. V8's `Math.sin`, `Math.cos`, `Math.atan2` and `Math.exp`
caused no difference: wherever their results feed the image they are rounded to float32
or quantised to a byte first.

FINALE differs from Go over most of the card, not just the wordmark. The logo
scale is limited to 45% of the frame width, and `JAVASCRIPT` is 59 font
columns wide against 11 for `GO`. So the logo is smaller, and the subtitle,
numbers and tag all move up. As a check, the same `Finale` class built with
the name `GO` matches Go on all 600 frames at 640x360, 1280x720, 1920x1080,
320x200 and 100x80.
