# C++ port: notes

C++23, one header per scene plus `canvas.cpp` and `main.cpp`. A scene is a
plain class: the constructor builds its tables, `render` draws a frame,
the destructor frees it all. `main.cpp` keeps the current scene by value in
a `std::variant` and dispatches with `std::visit`. There is no virtual base:
the nine scenes are a closed set, only one is alive at a time, and
`bb_start` is just `emplace`. The concepts `Effect` and `Laddered` stand in
for the interface, checked at compile time, and `if constexpr` asks whether
a scene has a ladder (`-fno-rtti` rules out `dynamic_cast` anyway).

Palettes and the font are `consteval`. The compiler builds them and the
module carries only the finished tables. The sine tables are not, because
libc++'s `std::sin` cannot run at compile time, and a hand-written series
would be our own maths library, not the language's. They are built by
`_initialize`, which runs the static initialisers. Build: `ports/cpp/build.sh`.
The wasi-runtimes sysroot only has libc++, so libc comes from wasi-libc.

## How C++ differs, scene by scene

- **STARFIELD**: the stars and their streaks are `std::array` members of
  the scene, so a new scene is one value and a frame allocates nothing. C
  leaves the evaluation order of an initialiser list unspecified, but a C++
  braced initialiser runs left to right. So `Star{rng.unit(), rng.unit(), ...}`
  keeps Go's draw order on one line. `std::views::zip` walks each star with
  its streak.
- **TUNNEL**: the depth and angle tables have the framebuffer's layout, so
  one flat index walks all three `std::vector`s.
- **TUNNEL/1**: `std::sqrt` on a `float` picks the float overload, which is
  correctly rounded. It equals Go's `float32(math.Sqrt(...))` without the
  trip through double.
- **PLASMA**: Go's slices `rad[row : row+w]` become `std::span` views from
  `subspan`. They are not copies and have no bounds check, since libc++
  hardening is off.
- **PLASMA/1**: `std::sin` is overloaded, so float in gives float out
  (libc's `sinf`). Go only has the double version and rounds its result.
  No pixel changed against Go's rung (640x360, 1280x720, 333x211).
- **ROTOZOOM**: the 1 MiB texture is a function-local `static const
  std::vector`, built on the first start and kept for the module's life.
  Each scene holds a `std::span` on it. `hsl_to_rgb` is `constexpr`, but the
  texture needs `std::sin`, so it is built at run time.
- **METABALLS**: the balls are stored the way the pixel loop reads them:
  offset and aspect-scaled once per frame, with the radius already squared.
  Go recomputes the offsets for every pixel. The values are the same, so
  the pixels are too.
- **GRID**: `std::lerp` would be the obvious `mix`, but it is not Go's
  formula. It guarantees exact end points and monotonicity, so its rounding
  is different. The port keeps `a + (b - a) * t`. Every float constant
  has an `f` suffix: one bare literal would promote the whole expression to
  double.
- **FIRE**: the fire's xorshift is the same `fmath::Rng` class with its own
  seed. Each finished row goes through the palette with
  `std::ranges::transform`.
- **MANDELBROT**: the escape test is a template argument (`draw<escape>`),
  not a function variable as in Go. Each rung gets its own copy of the
  loop with the test inlined, and no indirect call per block.
- **FINALE**: `"EVERY PIXEL IS " + lang` is joined at compile time by a
  `consteval` function into a `std::array<char>`. The letter offsets are an
  array sized from the literal. The font is Go's text table, parsed by a
  `consteval` function, so only its 665 bytes of glyphs reach the module.

## Pixel differences

None outside the language name. Every scene other than FINALE matches Go
exactly (0 differing pixels) at 640x360 on frames 1, 2, 60 and 300, at
1280x720 on frames 1 and 600, at 1920x1080 on frames 1 and 900, and at
333x211 on frames 1, 7 and 1000. So do the ladder rungs at 640x360. In
FINALE the logo and subtitle spell `C++` instead of `GO`, and the wider
wordmark moves the layout and the glow. A scratch build with `lang` set to
`"GO"` matches the Go finale exactly at 640x360, 1280x720 and 1920x1080, so
the name is the only cause.

The maths library (wasi-libc's `sin`, `sinf`, `cos`, `atan2`, `exp` and
`fmod`, instead of Go's own) changed no pixel on any frame tested.
