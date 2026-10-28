// The JavaScript port of babeltro: the nine effects in plain JavaScript, no
// WebAssembly, no dependencies, no build step. It implements the contract in
// spec/ABI.md as an ES module:
//
//   init(w, h)    allocate the framebuffer and return it (a Uint32Array)
//   start(scene)  begin a scene from a fresh state
//   render(n)     draw frame n of the current scene
//
// Every effect is a class with the same three methods, the shape of Go's
// fx.Effect: resize(w, h) builds the tables tied to resolution, prepare(s)
// does the per-frame set-up, draw(fb) writes every pixel.

import { Framebuffer } from './lib/canvas.js';
import { Starfield } from './fx/starfield.js';
import { Tunnel } from './fx/tunnel.js';
import { Plasma } from './fx/plasma.js';
import { Rotozoom } from './fx/rotozoom.js';
import { Metaballs } from './fx/metaballs.js';
import { Grid } from './fx/grid.js';
import { Fire } from './fx/fire.js';
import { Mandelbrot } from './fx/mandelbrot.js';
import { Finale } from './fx/finale.js';

export const LANG = 'JAVASCRIPT';

const SCENES = [
  () => new Starfield(),
  () => new Tunnel(),
  () => new Plasma(),
  () => new Rotozoom(),
  () => new Metaballs(),
  () => new Grid(),
  () => new Fire(),
  () => new Mandelbrot(),
  () => new Finale(LANG),
];

let fb = null;
let effect = null;
// what an effect knows about time; one object, updated in place every frame
const state = { t: 0, beat: 0, dt: 1 / 60, frame: 0 };

/** Allocates a w×h framebuffer and returns it. */
export function init(w, h) {
  fb = new Framebuffer(w, h);
  if (effect) effect.resize(w, h);
  return fb.pix;
}

/** Begins scene from a fresh effect, so stateful scenes replay the same history. */
export function start(scene) {
  effect = (SCENES[scene] ?? SCENES[SCENES.length - 1])();
  effect.resize(fb.w, fb.h);
}

/** Draws frame n (n ≥ 1). Time comes from n at a fixed 60 Hz step, never a clock. */
export function render(n) {
  state.t = state.beat = n / 60;
  state.frame = n;
  effect.prepare(state);
  effect.draw(fb);
}
