# SQL port: notes

Every pixel is computed by a query: SQLite 3.49, compiled to WebAssembly by
[sql.js](https://sql.js.org) 1.14.2. `port.js` binds the frame number, runs
the scene's prepared statements and copies out the one value the last one
returns: the whole frame as a blob, `unhex(group_concat(hex, ''))` over the
pixels in framebuffer order, each pixel's `hex` read from a 768-row palette
table. One row, one column, 921,600 bytes at 640x360, one `Uint8Array.set`.
No JavaScript function is registered with SQLite. `sin`, `atan2`, `exp` and
`sqrt` are the C ones sql.js compiles in (`extension-functions.c`, its libm).

sql.js's wasm is found with `locateFile`: `port.js` points it at
`new URL('./node_modules/sql.js/dist/sql-wasm.wasm', import.meta.url)`, a
path under Node, and in the lab's worker the URL of the asset Vite emits for
that same expression. The `.sql` files are found the same way. The
`browser` build sql.js ships looks for `sql-wasm-browser.wasm`, which is
byte-identical.

SQLite has one float type, a 64-bit REAL, and Go's effects compute in
float32. It can be emulated, in pure SQL: `v * 536870913.0 - (v * 536870913.0 - v)`
(Veltkamp's split, S = 2^29 + 1) rounds a double to the nearest float32, ties
to even, for any value in float32's normal range. It needs `v` three times
and SQL has no variables, so a value is computed in one subquery and
rounded in the next, each subquery marked `LIMIT -1`, which limits nothing
but stops SQLite inlining it (inlined, a rounding costs three evaluations of
everything below it, compounding). Each subquery then runs as a co-routine,
one row in flight. Wherever Go has a float32 operation, there is a rounding.

## How SQL differs, scene by scene

- **STARFIELD**: 1600 stars in a table, moved by one `REPLACE INTO` per
  frame. A star that passes the camera respawns with two fresh random
  numbers, and "the k-th star reborn this frame takes calls 2k-1 and 2k" is
  a window function again. The streaks are Bresenham lines, all 1600 walked
  at once by one recursive CTE (a row is a star at one point of its line,
  with its error term). Additive drawing has no order in SQL, so the frame is
  what painting in order would leave: per pixel, the last head pixel written
  there, plus the sum of the lines drawn after it, saturated once (saturating
  adds of non-negative values commute).
- **TUNNEL**: the float32 emulation done the plain way: 17 roundings per
  pixel, in nine stacked co-routines. It costs about 2.5x the same query in
  plain double (`--step 3`, not a Go rung), which differs from Go on about 5
  pixels per frame (see below). Go's `if odd { val = -val * 0.7 }` is a
  `CASE`, and `(int(u*0.32) + int(twist)) & 1` survives as is.
- **TUNNEL/1**: the geometry is a VIEW, `tunnel_geometry`, and the default
  rung stores it once in a table. Both rungs run the same frame query over a
  view `tunnel_src`: switching rung is a `CREATE VIEW`. A VIEW is a
  function call, a TABLE is a cache: the oldest optimisation in databases.
- **PLASMA**: the three 1D sine tables are real tables rewritten every frame
  (`REPLACE INTO`), so each pixel finds its terms by INTEGER PRIMARY KEY:
  three B-tree seeks, plus one into the sine table and one into the palette.
  The pixel query is computed in plain double, and only where the double
  falls within a proven rounding distance of an integer does a `CASE` replay
  Go's float32 steps (Ziv's strategy, the one correctly rounded maths
  libraries use). The four sines are float32, so their double sum is exact,
  and Go's five roundings move `v*36 + 127.5` by less than 3.4e-5: any value
  further than 1e-4 from an integer truncates the same way. At 640x360 about 45
  pixels per frame replay the palette index and 1,200 (0.5%) the radial
  index; the query costs 1.35x the plain double one and matches the C reference everywhere.
- **PLASMA/1**: four `sin()` per pixel and every argument rounded: nine
  stacked subqueries. SQLite's `sin` is a C call, cheaper than the B-tree
  seek that replaces it on the next rung (246 ms against 317 at 320x180).
- **PLASMA/2**: the same per-pixel arithmetic with four joins on the sine
  table instead of four `sin()`. In SQL a table lookup is a B-tree seek, not
  an array index, which is why this rung is slower than the previous one.
- **ROTOZOOM**: the 512x512 texture is float64 maths, built once into a
  table (its HSL ramp is a CASE per channel; `math.Mod(v, 1)` is
  `v - CAST(v AS INTEGER)`, which is exact). Per frame, `dx*cosA`, `dx*sinA`
  and their `dy` twins go into a column table and a row table, so each pixel
  does four float32 roundings per axis and one seek into the texture.
- **METABALLS**: the squared distances to the six balls split into a column
  term and a row term, each a six-column table rebuilt every frame. Per
  pixel stay the 24 roundings of the six divisions and the running float32
  sum, in ball order, across ten stacked subqueries.
- **GRID**: the scene where Go mixes float32 and float64 the most, every
  conversion written out (Clamp01 in float64, colours in float32). All the
  per-row work Go hoists lands in a per-frame row table; per pixel remain
  the sun's disk, behind an `iif` on the row's kind so the square root runs
  only on sun rows, and the floor's cross lines.
- **FIRE**: the one scene that is not a set. Each pixel draws a random number
  only if the pixel below still burns, so which number it gets depends on
  every pixel computed before it. The loop over rows is a trigger: inserting
  h-1 … 1 into `fire_job` runs one row update each, in that order. Within a
  row it is a set again: the k-th burning pixel takes the k-th number, and
  k-th is `sum(v > 0) OVER (ORDER BY id)`. The xorshift32 numbers are
  generated ahead by a recursive CTE, with XOR written `(a | b) - (a & b)`
  (SQLite has `&`, `|`, `<<`, `>>`, no `^`) and left shifts masked to 32 bits.
- **MANDELBROT**: float64 in Go, REAL in SQLite, so no rounding tricks at
  all. The escape-time loop is a recursive CTE over every block of the frame
  at once: a row is a point after i iterations, and a point stops making rows
  when it escapes. SQLite runs it as a queue, so the result comes out in
  escape order, and goes through an INTEGER PRIMARY KEY table to meet the
  pixels again.
- **MANDELBROT/1**: the same query with one point per pixel and no cardioid
  test: a configuration row, not new code.
- **MANDELBROT/2**: the cardioid and bulb test is a `WHERE NOT skip` on the
  CTE's seed: the points inside the set never enter the queue.
- **FINALE**: painting in layers becomes "which layer is on top of this
  pixel": every overwriting layer (outline, chrome gradient, rules,
  subtitle, numbers, tag) is a set of `(id, layer, colour)` rows, and
  `max(layer)` with SQLite's bare-column rule picks the colour. Under it, the
  additive layers (glow, stars, the reflection) are sums, saturated, and the
  floor line is the one float32 step in between. The 5x7 font is a table of
  lit dots, and text is a join: characters × dots × scale² blocks.

## Pixel differences

None outside the language name. Eight scenes match the reference byte for
byte at 160x90 and 320x180 (frames 1, 2, 30); TUNNEL, PLASMA, FIRE and
MANDELBROT also at 640x360, and every rung of the PLASMA and TUNNEL ladders at 160x90.
FINALE differs only where it spells `SQL`: the logo, its outline and
reflection, and the subtitle. The same finale.sql with the name set to `C`
matches the C reference at 160x90 and 320x180, and with `GO` it matches Go.
At 640x360 the fire has thousands of dead pixels per frame, so the
data-dependent random draws are exercised too.

That is the float32 emulation at work. Without it, plain double SQL differs
from Go on a few pixels per frame, by one palette step:

- **PLASMA** (`--step 4`): 236 pixels over 60 frames at 320x180, 0 to 26
  per frame, largest channel difference 5. About 85% come from the 1D sine
  tables: the index `int(a * 8192/2π)` lands on the other side of an integer
  when `a` is not rounded to float32, and the neighbouring sine differs by
  up to 7.7e-4, which moves a whole column, row or diagonal of `v` a little;
  the pixels already close to a palette boundary step over it. The rest are
  the radial term's index (5%) and `int(v*36 + 127.5)` itself (10%).
- **TUNNEL** (`--step 3`): 325 pixels over 60 frames at 320x180, at most 12
  per frame, largest channel difference 4, and one pixel at 16. Same
  mechanism: an unrounded value truncates across an integer (a table index,
  the checker parity or the palette index).

The maths library never mattered: sql.js's `sin` and `atan2` give exactly
Go's float32 tables, and its `exp` gives Go's float64 camera path.
