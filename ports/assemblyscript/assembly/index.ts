// The wasm exports the lab drives (spec/ABI.md): bb_init allocates the
// framebuffer, bb_start begins a scene from a fresh state, bb_step picks a
// rung of its optimisation ladder, bb_render draws one frame.

import { FB } from './canvas';
import { Effect } from './fx/effect';
import { Starfield } from './fx/starfield';
import { Tunnel } from './fx/tunnel';
import { Plasma } from './fx/plasma';
import { Rotozoom } from './fx/rotozoom';
import { Metaballs } from './fx/metaballs';
import { Grid } from './fx/grid';
import { Fire } from './fx/fire';
import { Mandelbrot } from './fx/mandelbrot';
import { Finale } from './fx/finale';

let fb: FB | null = null;
let eff: Effect | null = null;

/** Allocates a w×h framebuffer and returns its address in linear memory. */
export function bb_init(w: i32, h: i32): i32 {
  const f = new FB(w, h);
  fb = f;
  // the GC never moves an object, so this address holds for the module's life
  return <i32>changetype<usize>(f.pix);
}

/** Begins scene from a fresh effect, as Go does. */
export function bb_start(scene: i32): void {
  // The minimal runtime collects only when asked. Here, between scenes, the
  // previous effect and its tables are unreachable and no reference is live
  // on the wasm stack: the one safe point, and the one place it is needed.
  eff = null;
  __collect();
  const e = newEffect(scene);
  const f = fb!;
  e.resize(f.w, f.h);
  eff = e;
}

/** The rung of the scene's optimisation ladder, called after bb_start. */
export function bb_step(n: i32): void {
  eff!.setStep(n);
}

/** Draws frame n of the current scene, at a fixed 60 Hz step. */
export function bb_render(n: i32): void {
  const f = fb!;
  const t: f64 = <f64>n / 60;
  eff!.prepare(t, 1.0 / 60, n, f.w, f.h);
  eff!.draw(f, 0, f.h);
}

function newEffect(scene: i32): Effect {
  switch (scene) {
    case 0: return new Starfield();
    case 1: return new Tunnel();
    case 2: return new Plasma();
    case 3: return new Rotozoom();
    case 4: return new Metaballs();
    case 5: return new Grid();
    case 6: return new Fire();
    case 7: return new Mandelbrot();
    default: return new Finale();
  }
}
