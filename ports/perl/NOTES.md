# Perl port: notes

Perl 5.42 compiled to wasm ([zeroperl](https://github.com/6over3/zeroperl-ts),
fetched by `fetch.sh`), booted in the worker with a virtual filesystem that
holds the `.pm` modules. Perl has doubles and 64-bit integers, nothing else.
Go's float32 comes from the only rounding tool Perl has: `unpack 'f', pack 'f', $x`,
which stores the number as a C float and reads it back. Both take lists,
so the effects compute a whole row as a list and round it in one go
(`f32 map { … } @row`). In wasm at 320x180 that is 3x faster than rounding
pixel by pixel (124 ms against 380 ms for the plasma loop).
The frame leaves Perl as `pack 'V*'`, an ImageData's bytes, and JS
copies it out of the interpreter's memory at the address `pack 'p'` gives.
Yes, Perl has an address-of operator.

## How Perl differs, scene by scene

- **STARFIELD**: the 1600 stars are three parallel lists, so each float32
  operation is one `map` over all of them. The respawn loop runs over
  `grep { $z[$_] < 0.8 }`, in index order, so the generator is called in
  the same order as in Go. The streaks are a plain Bresenham sub that adds
  colour one pixel at a time.
- **PLASMA**: each row is seven list operations: one `map` per float32
  operation, each followed by `f32`. Go's three per-frame tables become three
  lists built the same way. The rounding is about 40% of the frame. Without it,
  4 pixels in 57,600 change at 320x180, but this port aims for zero.
- **PLASMA/1**: Perl's `sin` (wasi-libc's) gives Go's pixels exactly, once
  rounded to float32. It is also faster than the next rung: in Perl, `sin` is
  one op written in C, while a table lookup is a multiply, a rounding, an
  `int` and an index.
- **PLASMA/2**: the sine table makes Perl slower, not faster: 90 ms against
  77 ms at 160x90. Tables pay off only once the next rung moves the lookups
  out of the pixel loop.
- **TUNNEL**: the shading is seventeen float32 operations per pixel, so
  seventeen `map`s per row. The brick checker flips its pixels in a `for`
  over `grep`, which is about as Perl as a tunnel gets.
- **TUNNEL/1**: the per-pixel `sqrt`, division and `atan2` are in the
  `polar` sub that builds the tables. Step 1 calls it for every row of every
  frame. Perl's `atan2` matches C's after float32 rounding.
- **ROTOZOOM**: the 512x512 texture is 262,144 pixels of float64 maths,
  about 1.8 s of Perl. It depends on nothing, so it is built once per
  interpreter and kept in a file-scoped `my @TEX`; later starts reuse it.
  `math.Mod(v, 1)` is `$v - int $v`, which is exact. The pixel loop finishes
  with a slice, `@TEX[map { $iy[$_] * 512 + $ix[$_] } @X]`.
- **METABALLS**: six balls times six float32 operations per pixel makes
  about forty `map`s per row, the slowest scene here. Go recomputes each
  ball's centre for every pixel, and Perl hoists it: the values are the same.
- **GRID**: the floor's per-pixel branches (`max`, `min`, the line width)
  become ternaries inside `map`s. The sun goes through `grep`, first on the
  pixels inside its box, then on the pixels inside its circle. Go's
  float64-then-float32 sky terms come out as `f32(0.03 + 0.18 * $sky * $sky)`.
- **FIRE**: integers only, and each random number depends on the last,
  so this one stays a plain pixel loop. Perl's integers are 64-bit, so
  xorshift32 masks its left shifts with `& 0xFFFFFFFF`. The heat buffer
  becomes colours in one array slice: `@pal[@heat]`.
- **MANDELBROT**: all float64, Perl's only kind of float, so there is not
  a single `f32`. Each row of blocks is one `map` that returns every colour
  `($c) x $step` times. The row is then repeated with `(@row) x $step`, since
  Perl's `x` repeats lists as well as strings.
- **MANDELBROT/1**: the escape-time loop and nothing else. The
  `($zx2, $zy2) = ($zx * $zx, $zy * $zy)` list assignment is the idiom, and
  the loop costs about 10x the default rung.
- **MANDELBROT/2**: the cardioid and bulb test skips the interior, which
  is most of the cost: 81 ms against 216 ms at 160x90.
- **FINALE**: the 5x7 font is the same text table in a heredoc, and each
  row becomes a number with `oct "0b$row"`. The glyph blocks come from one
  `blocks` sub, mirrored for the reflection. The logo then takes three
  passes: the additive reflection, a one-pixel outline drawn four times, and
  the gradient with every fourth row darkened.

## Pixel differences

None outside the language name. The eight scenes without text match the
reference byte for byte at 160x90 and 320x180, and so does every rung of the
PLASMA, TUNNEL and MANDELBROT ladders. TUNNEL, PLASMA and FIRE were also
checked at 333x187 and 640x360, and in a browser worker. The stateful scenes
were run out to frame 300.

FINALE differs over most of the card. `PERL` is 23 font columns wide against
5 for `C`, so the logo, the pool of light behind it and every line below it
move. To check, the same `Finale.pm` with `$LANG = 'C'` matches the C
reference on frames 1, 2, 30 and 300 at 160x90, 320x180 and 640x360.

Perl is roughly 200 (MANDELBROT) to 1,400 (METABALLS) times slower than the
C reference at 160x90: an interpreter inside wasm, rounding every float by packing it.
