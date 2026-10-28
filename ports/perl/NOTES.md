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
  frame. Perl's `atan2` matches Go's after float32 rounding.
- **FIRE**: integers only, and each random number depends on the last,
  so this one stays a plain pixel loop. Perl's integers are 64-bit, so
  xorshift32 masks its left shifts with `& 0xFFFFFFFF`. The heat buffer
  becomes colours in one array slice: `@pal[@heat]`.

## Pixel differences

None. TUNNEL, PLASMA and FIRE match Go byte for byte at 160x90
(frames 1, 2, 60, 300), 320x180, 333x187 and 640x360, and so does every rung
of the PLASMA and TUNNEL ladders. That holds in Node and in a browser worker.
Perl is about 100 (FIRE) to 350 (TUNNEL) times slower than Go's wasm: an
interpreter inside wasm, rounding every float by packing it.
