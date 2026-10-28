// Everything the lab says in words. Kept short on purpose: the effect on
// screen and the code under it do the explaining.

export const EFFECTS = [
  {
    name: 'STARFIELD',
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Perspective divide · additive lines',
    text: 'Stars live in 3D and land on screen at x/z, y/z. Each draws a streak from where it was to where it is: that is what sells the speed.',
  },
  {
    name: 'TUNNEL',
    seconds: 11, // the scene loops after this, as in the demo
    trick: 'Polar lookup tables',
    text: 'Every pixel knows its distance and angle from the centre, computed once per screen size. Scrolling the distance flies you forward.',
  },
  {
    name: 'PLASMA',
    seconds: 10, // the scene loops after this, as in the demo
    trick: 'Summed sines · palette',
    text: 'Four sine waves summed per pixel and read through a palette. Three depend only on x, y or x+y, so they are 1D tables rebuilt each frame.',
  },
  {
    name: 'ROTOZOOM',
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Inverse mapping · power-of-two wrap',
    text: 'Each screen pixel is rotated and scaled back into a 512×512 texture. The texture wraps with a bit mask: two multiplies per axis, one lookup.',
  },
  {
    name: 'METABALLS',
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Implicit surfaces',
    text: 'Six balls each add r²/d² to a field; where the sum crosses 1 is the surface. The blobs merge because the fields add up.',
  },
  {
    name: 'GRID',
    seconds: 10, // the scene loops after this, as in the demo
    trick: 'One division per row',
    text: 'Below the horizon each row is one depth, found once per row. The lines are where the floor coordinate crosses a whole number.',
  },
  {
    name: 'FIRE',
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Cellular automaton · palette',
    text: 'Heat is seeded on the bottom row; every pixel copies the one below, shifted by −1, 0 or +1 and cooled a little. One byte per pixel.',
  },
  {
    name: 'MANDELBROT',
    seconds: 12, // the scene loops after this, as in the demo
    trick: 'Escape time · early out',
    text: 'Iterate z = z² + c until it escapes. A closed-form test skips the main cardioid, where points never escape, and the budget grows with the zoom.',
  },
  {
    name: 'FINALE',
    seconds: 14, // the scene loops after this, as in the demo
    trick: 'Bitmap font · gradient · reflection',
    text: 'A 5×7 font scaled up block by block, a three-stop gradient, an additive reflection. Its name is the only thing that differs between languages.',
  },
];

// The order here is the order of the pickers and of the number keys.
export const LANGS = [
  {
    id: 'go',
    name: 'Go',
    color: '#4fc3e8',
    hl: 'go',
    how: 'Go → wasm (wasip1). The module carries Go’s runtime and garbage collector.',
  },
  {
    id: 'c',
    name: 'C',
    color: '#8ea3ff',
    hl: 'c',
    how: 'C → wasm with clang and wasi-libc. No runtime: the libm it links is the only baggage.',
  },
  {
    id: 'rust',
    name: 'Rust',
    color: '#ff8a4c',
    hl: 'rust',
    how: 'Rust → wasm32-unknown-unknown. No runtime; bounds checks stay unless iterators prove them away.',
  },
  {
    id: 'js',
    name: 'JavaScript',
    color: '#f2d64b',
    hl: 'javascript',
    how: 'Plain JavaScript, no wasm. Every float32 operation needs Math.fround to match.',
  },
];
