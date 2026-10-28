# Rust port: notes

Same pixels as the C reference, written as Rust. Global state is a
`thread_local!` `RefCell` (see `src/lib.rs`): safe, and on single-threaded
wasm it is a plain static plus one borrow-flag check per call.

## Effect by effect

- **STARFIELD**: `as i32` saturates out of range, and Go's `int32()` is
  implementation-defined there, so the two agree only in range. Here z ≥ 0.8
  keeps every projected coordinate small.
  The random draws are separate `let`s so their order is visible.
- **TUNNEL**: one iterator zips the framebuffer with the depth and angle
  tables, so there is no index and nothing to bounds-check.
- **PLASMA**: `chunks_exact_mut(w)` plus `zip` with equal-length slices
  removes every bounds check from the pixel loop.
- **PLASMA/1**: the sines are `f64::sin` rounded to f32, as in Go. Rust's
  libm and Go's `math` differ in the last f64 bit for some angles, but no
  difference survives the rounding: 0 differing pixels at 640×360 and
  1280×720. The more natural `f32::sin` (libm's `sinf`) also gave 0
  differing pixels at 640×360, and ran in 5.8 ms instead of 8.6 ms.
- **PLASMA/2**: the `fb.pix[y * w + x]` index keeps one bounds check per
  pixel; the palette index needs none, as the clamp to 0..=255 proves it in
  range for a `[u32; 256]`. Iterating rows with `chunks_exact_mut` instead
  took 3.55 ms down to about 3.2 ms at 1280×720: the check costs about 10%,
  far less than the sines.
- **ROTOZOOM**: the texture is a `Box<[u32; 512*512]>`, not a `Vec`, so its
  length is a compile-time fact and the masked index needs no check.
  `* zoom * 34` stays two multiplies, as in Go, because folding them would
  change the rounding.
- **METABALLS**: `Iterator::sum` on floats starts from -0.0, not 0.0; that
  does not change a sum of positive terms.
- **GRID**: Go's `v - float32(int(v))` becomes `f32::fract`, which is defined
  as `v - v.trunc()`: the same bits with no float→int→float round trip. The
  per-row floor constants are an `Option<FloorRow>`, not zero-initialised
  locals that are only valid on the floor.
- **FIRE**: the source and destination rows are both in one buffer, which the
  borrow checker allows only after `split_at_mut` proves they do not overlap.
  `saturating_sub` replaces Go's `if v > decay` branch.
- **MANDELBROT**: `chunks_mut(w * step)` gives one band of blocks at a time.
  The first row is computed and then `copy_from_slice`d down the band, so
  there is no clamped block loop. Go folds `-0.743643887037151+0.5` exactly
  at compile time, while Rust rounds the literal first; I checked that both
  give the same f64.
- **MANDELBROT/1**: Go passes the escape function as a func value; here
  `draw_blocks` takes `impl Fn`, so every rung gets its own monomorphised
  copy of the loop and calls the iteration directly rather than through a
  pointer.
- **FINALE**: the font is parsed at compile time by a `const fn`, where Go
  does it in `init`. Clippy's suggestion for `g *= g * pulse` is
  `g = g * g * pulse`, which rounds differently, so the code writes
  `g * (g * pulse)` explicitly.

## Pixel differences

- **FINALE only, all of it from the name.** The wordmark's scale comes from
  the name's width (scale 21 for `GO`, 12 for `RUST` at 640×360). That moves
  the logo, its reflection, the floor line, the glow centred on the logo and
  the subtitle, so the differing box covers most of the frame. To check this,
  I built the port with `GO` / `EVERY PIXEL IS GO`: it then matched Go
  exactly (0 differing pixels) at 640×360 (frames 1, 2, 60, 300, 601),
  1280×720 (1, 600), 1920×1080 and 200×150.
- **Maths library: no effect on pixels.** Inside wasm, Rust's libm and Go's
  `math` disagree in the last bit of f64 `sin`/`cos` for 1858 and 2184 of the
  8192 sine-table angles. All of them agree once rounded to f32. No
  difference from `sin`, `cos`, `atan2` or `exp` reached a pixel at 640×360,
  1280×720, 1920×1080 or 333×197.
