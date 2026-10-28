// Everything the lab says in words. Kept short on purpose: the effect on
// screen and the code under it do the explaining.

export const EFFECTS = [
  {
    name: 'STARFIELD',
    native: 0.054, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Perspective divide · additive lines',
    text: 'Stars live in 3D and land on screen at x/z, y/z. Each draws a streak from where it was to where it is: that is what sells the speed.',
  },
  {
    name: 'TUNNEL',
    native: 0.93, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 11, // the scene loops after this, as in the demo
    trick: 'Polar lookup tables',
    text: 'Every pixel knows its distance and angle from the centre, computed once per screen size. Scrolling the distance flies you forward.',
    steps: [
      { name: 'atan2 + sqrt per pixel', text: 'Distance and angle from the centre, computed for every pixel, every frame — for values that never change.' },
      { name: 'Polar tables', text: 'The same two numbers, computed once per screen size and read back. Not a single pixel changes.' },
    ],
  },
  {
    name: 'PLASMA',
    native: 0.41, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 10, // the scene loops after this, as in the demo
    trick: 'Summed sines · palette',
    text: 'Four sine waves summed per pixel and read through a palette. Three depend only on x, y or x+y, so they are 1D tables rebuilt each frame.',
    steps: [
      { name: 'sin() per pixel', text: 'The first version anyone writes: four calls to the maths library for every pixel.' },
      { name: 'Sine table', text: 'The same loop, reading an 8192-entry table instead of calling sin(). A few pixels shift by the table’s precision.' },
      { name: '1D tables', text: 'Three of the four terms depend only on x, y or x+y, so they are computed once per frame, not once per pixel.' },
    ],
  },
  {
    name: 'ROTOZOOM',
    native: 0.3, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Inverse mapping · power-of-two wrap',
    text: 'Each screen pixel is rotated and scaled back into a 512×512 texture. The texture wraps with a bit mask: two multiplies per axis, one lookup.',
  },
  {
    name: 'METABALLS',
    native: 1.74, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Implicit surfaces',
    text: 'Six balls each add r²/d² to a field; where the sum crosses 1 is the surface. The blobs merge because the fields add up.',
  },
  {
    name: 'GRID',
    native: 1.76, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 10, // the scene loops after this, as in the demo
    trick: 'One division per row',
    text: 'Below the horizon each row is one depth, found once per row. The lines are where the floor coordinate crosses a whole number.',
  },
  {
    name: 'FIRE',
    native: 1.08, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 9, // the scene loops after this, as in the demo
    trick: 'Cellular automaton · palette',
    text: 'Heat is seeded on the bottom row; every pixel copies the one below, shifted by −1, 0 or +1 and cooled a little. One byte per pixel.',
  },
  {
    name: 'MANDELBROT',
    native: 1.75, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 12, // the scene loops after this, as in the demo
    trick: 'Escape time · early out',
    text: 'Iterate z = z² + c until it escapes. A closed-form test skips the main cardioid, where points never escape, and the budget grows with the zoom.',
    steps: [
      { name: 'Plain escape time', text: 'Iterate every pixel until it escapes. Points inside the set run the whole budget for nothing.' },
      { name: 'Cardioid test', text: 'A closed-form test spots the main cardioid and bulb, where points never escape, and skips them. Same pixels.' },
      { name: '2×2 blocks', text: 'Compute one point per block of four pixels. The honest trade-off: in motion nobody sees it.' },
    ],
  },
  {
    name: 'FINALE',
    native: 0.28, // ms: native Go, one thread, best of 240 frames at 640×360 on an M1
    seconds: 14, // the scene loops after this, as in the demo
    trick: 'Bitmap font · gradient · reflection',
    text: 'A 5×7 font scaled up block by block, a three-stop gradient, an additive reflection. Only the name differs between languages, but the layout follows its width.',
  },
];

// The order here is the order of the pickers and of the number keys.
// `how` is one line on how the language gets into the browser.
export const LANGS = [
  {
    id: 'go',
    name: 'Go',
    color: '#4fc3e8',
    hl: 'go',
    how: 'Go → wasm (wasip1). The module carries Go’s runtime and garbage collector.',
  },
  {
    id: 'tinygo',
    name: 'TinyGo',
    color: '#7fe0d0',
    hl: 'go',
    how: 'The same Go sources, compiled by TinyGo through LLVM instead of Go’s own backend.',
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
    color: '#ef6a45',
    hl: 'rust',
    how: 'Rust → wasm32-unknown-unknown. No runtime; bounds checks stay unless iterators prove them away.',
  },
  {
    id: 'zig',
    name: 'Zig',
    color: '#f7a41d',
    hl: 'zig',
    how: 'Zig → wasm, freestanding. Tables built at compile time, its own maths library.',
  },
  // the entries below appear once their port is built
  {
    id: 'cpp',
    name: 'C++',
    color: '#5be0a0',
    hl: 'cpp',
    how: 'C++23 → wasm with clang and libc++. Palettes and font are built at compile time.',
  },
  {
    id: 'assemblyscript',
    name: 'AssemblyScript',
    color: '#9b6dff',
    hl: 'typescript',
    how: 'TypeScript syntax compiled to wasm by asc. Real f32 and f64 types, so no Math.fround.',
  },
  {
    id: 'wat',
    name: 'Hand-written wasm',
    color: '#b48cff',
    hl: 'wasm',
    how: 'WebAssembly text, written by hand: no compiler at all.',
    scenes: [2, 6],
  },
  {
    id: 'js',
    name: 'JavaScript',
    color: '#f2d64b',
    hl: 'javascript',
    how: 'Plain JavaScript, no wasm. Every float32 operation needs Math.fround to match.',
  },
  {
    id: 'python',
    name: 'Python',
    color: '#5a9fd4',
    hl: 'python',
    how: 'CPython and NumPy compiled to wasm (Pyodide), running in the worker.',
    scenes: [1, 2, 7],
  },
  {
    id: 'perl',
    name: 'Perl',
    color: '#d06bd4',
    hl: 'perl',
    how: 'Perl 5.42 (zeroperl) compiled to wasm; float32 rounded via pack \'f\'.',
    scenes: [1, 2, 6],
  },
  {
    id: 'sql',
    name: 'SQL',
    color: '#c9cfd8',
    hl: 'sql',
    how: 'SQLite compiled to wasm: every pixel is a row of a query.',
    scenes: [2],
  },
];

export const HOME = {
  question: 'How do you make this effect',
  intro: 'Nine classic demoscene effects, each written in several languages, all running live in your browser and drawing the same pixels. Pick one to see how each language does it.',
};

// Said wherever the lab shows a time, because it is the first thing a reader
// will get wrong.
export const TIMING_NOTE =
  'These are WebAssembly times in this browser: they measure each compiler’s wasm backend as much as the language. ' +
  'The same Go code runs 1.5–3× faster built by TinyGo, and native Go is faster still.';
