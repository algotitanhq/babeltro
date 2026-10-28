# Python port: notes

CPython 3.14 and NumPy 2.4, compiled to wasm by Pyodide 314.0.7 and run in
the lab's worker. `port.js` loads them (from the npm package in Node, and
from the jsdelivr CDN build of the same version in the browser), writes the
`.py` files into Pyodide's file system and calls `babeltro.render(n)` once
per frame. The pixels never cross into JavaScript: the framebuffer is a
NumPy `uint32` array, and the host reads it through a `Uint32Array` view of
Pyodide's wasm memory.

The default rung of every scene is NumPy: whole-image array expressions, no
per-pixel Python. The ladders' early rungs are the same per-pixel loops Go
runs, written as plain Python, so the lab shows what the interpreter costs.
Go's float32 is NumPy's `float32`, which rounds after every operation just
as Go does. NumPy 2's promotion rules (NEP 50) do the rest: a Python float
meeting a `float32` becomes a `float32` first, as Go converts an untyped
constant. The trap is `float64` arrays and scalars, which promote quietly.
That is why every array here is created with `dtype=F32`, and every
`float64(...)` in Go is an `.astype(np.float64)` here.

## How Python differs, scene by scene

- **STARFIELD**: the projection of all 1600 stars is one array expression.
  The streaks are Bresenham lines, which look like they need a loop. But the
  recurrence Go's version follows has a closed form: the minor-axis offset
  at step k is `(2·minor·k + major) // (2·major)`. So every pixel of every
  line comes out of `np.repeat` at once, with no loop. It was checked
  against the loop on 300 000 random lines. The head pixels are the one
  ordering problem, because a head erases the light drawn before it:
  `np.maximum.at` finds the last head on each pixel. Saturating additions
  commute, so the rest is one `bincount` per channel.
- **TUNNEL**: the polar tables come from broadcasting a row of x against a
  column of y. The angle uses `np.arctan2` on `float64` copies, then rounds:
  on `float32` arrays NumPy would call `atan2f`, which is not Go's maths.
- **TUNNEL/1**: `math.sqrt` and `math.atan2` per pixel, every frame, with
  `np.float32` scalars: 74 ms a frame at 160x90 (0.6 ms for NumPy, 0.6 ms for
  Go's rung). That is about 5 µs per pixel, so a 640x360 frame takes a second.
- **PLASMA**: the `x+y` table read at `sxy[y : y+w]` for row y is
  `sliding_window_view(sxy, w)`: an (h, w) array with no copy and no loop.
- **PLASMA/1**: the floats are `np.float32` scalars, so each operation
  rounds like Go's, and `math.sin` is rounded back the way Go's `sin32`
  does it. Constants are left as bare Python floats: NEP 50 makes
  `t * 1.3` a float32 multiply. Writing `np.float32(1.3)` in the loop would
  cost twice as much, since each one builds an object per pixel.
  At 160x90 it takes 115 ms a frame: Go's rung takes 2.0 ms and the NumPy one
  0.45 ms. Two hundred and fifty times slower than the array version, and
  that is the whole point of the lab.
- **PLASMA/2**: the table lookup reads a list of `np.float32`, which is
  several times faster to index than the array. The items must stay
  `float32`: a list of Python floats would make the four-term sum
  `float64` and change the pixels. 81 ms at 160x90,
  against 0.12 ms for Go's: the table saves the calls, not the interpreter.
- **ROTOZOOM**: the texture is built in `float64` with whole-tile arrays
  (`np.fmod` takes the dividend's sign, like `math.Mod`). Each frame is two
  rotated coordinate planes, a `& 511` and one `np.take`.
- **METABALLS**: each ball's field is a row of `dx²` plus a column of `dy²`.
  Broadcasting turns that into the (h, w) image, six times per frame.
- **GRID**: everything Go hoists out of the pixel loop becomes an (n, 1)
  column, and broadcasting does the hoisting. The sun is computed only
  over its bounding box. Go's `if` chains become `np.where` and
  `np.maximum`, and its `float64` detours become explicit `astype` round
  trips.
- **FIRE**: the hard one. Go draws one xorshift32 number per burning pixel,
  in order, and a generator is sequential. But xorshift is linear over
  GF(2), so jumping ahead is a 32×32 bit matrix, applied with four byte
  tables. Squaring that jump gives the starts of 2, 4, 8… lanes, and then
  every lane steps at once. A frame's random numbers take under a hundred NumPy
  calls instead of 200 000 Python ones. The rows stay sequential, a few
  array operations each. The heat buffer has an edge pixel copied on either
  side, so the sideways step needs no clamping.
- **MANDELBROT**: escape time for every point at once. Points that escape
  are dropped, so the arrays shrink as the iterations grow. Colours come
  from one lookup table per iteration count, and the 2×2 blocks are two
  `repeat`s. Python floats and NumPy's default are both `float64`, so Go's
  arithmetic carries over unchanged.
- **MANDELBROT/1**: plain Python floats are already `float64`, so the escape
  loop is Go's word for word: 71 ms a frame at 160x90 over frames 1 to 30.
  Go's rung takes 1.6 ms.
- **MANDELBROT/2**: the cardioid test brings it to 23 ms (Go: 0.7 ms). The
  vectorised rung takes 1.9 ms: here NumPy gains less than elsewhere,
  because the shrinking set of live points means one small array operation
  per iteration.
- **FINALE**: the font is a dict mapping each character to its lit cells.
  Each cell is a `scale×scale` slice assignment. The gradient depends only
  on the screen row, so it is computed once as a column of colours. Go's
  integer `/` truncates and Python's `//` floors, so the layout uses a
  small `idiv` wherever the operand could be negative.

## Pixel differences

None outside the language name. All eight non-text scenes match Go exactly
(0 differing pixels) at 640x360 and 320x180 on frames 1, 2, 60 and 300.
Spot checks at other sizes also match: STARFIELD at 1280x720 and 333x187,
GRID at 1280x720, 333x187 and 100x80, FIRE at 333x187 up to frame 500.
Every ladder rung matches too: PLASMA 1 and 2,
TUNNEL 1 and MANDELBROT 1 and 2, at 160x90 on frames 1, 2 and 30. Pyodide's
libm (musl's `sin`, `cos`, `atan2`, `exp`) changed no pixel. Neither did
NumPy's own `float64` `sin` in the texture and the sine table.

FINALE differs over most of the card, because `PYTHON` is 35 font columns
wide against 11 for `GO`. That changes the logo's scale and moves
everything under it. Rebuilt with the name `GO`, the same code matches the
Go finale exactly at 640x360 (frames 1 to 600), 1280x720 and 100x80. The
same pixels come out in Chrome, in the lab's kind of module worker, as in
Node.
