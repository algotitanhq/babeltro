// Metaballs: summed radial fields sum(r² / d²), one division per ball per
// pixel and no square root, with a hot rim on the iso-contour.

import { FB } from '../canvas';
import { cos, sin } from '../fmath';
import { SUNSET } from '../palette';
import { Effect } from './effect';

const N: i32 = 6;

export class Metaballs extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  bx: StaticArray<f32> = new StaticArray<f32>(N); // centres, normalised
  by: StaticArray<f32> = new StaticArray<f32>(N);
  rad: StaticArray<f32> = new StaticArray<f32>(N);
  // per-frame: each ball's offset in field space and its radius squared
  ox: StaticArray<f32> = new StaticArray<f32>(N);
  oy: StaticArray<f32> = new StaticArray<f32>(N);
  rad2: StaticArray<f32> = new StaticArray<f32>(N);

  resize(w: i32, h: i32): void {
    this.w = w;
    this.h = h;
  }

  prepare(beat: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    this.w = w;
    this.h = h;
    const t = <f32>beat;
    for (let i = 0; i < N; i++) {
      const fi = <f32>i;
      // each ball orbits on its own ellipse and breathes
      const a: f32 = t * (0.35 + fi * 0.07) + fi * 2.1;
      this.bx[i] = 0.5 + 0.2 * cos(a) * (1 + 0.3 * sin(t * 0.5 + fi));
      this.by[i] = 0.5 + 0.2 * sin(a * 1.3 + fi) * (1 + 0.3 * cos(t * 0.4 + fi * 2));
      this.rad[i] = 0.105 + 0.025 * sin(t * 1.1 + fi * 1.7);
    }
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w, h = fb.h;
    const pix = fb.pix;
    const pal = SUNSET;
    // x is scaled by width/height so a circle in field space is round
    const asp: f32 = <f32>w / <f32>h;
    const ox = this.ox, oy = this.oy, rad2 = this.rad2;
    // Go recomputes these for every pixel; the values are the same
    for (let i = 0; i < N; i++) {
      ox[i] = (this.bx[i] - 0.5) * asp;
      oy[i] = this.by[i] - 0.5;
      rad2[i] = this.rad[i] * this.rad[i];
    }
    // @excerpt METABALLS
    for (let y = y0; y < y1; y++) {
      const fy: f32 = <f32>y / <f32>h - 0.5;
      const row = y * w;
      for (let x = 0; x < w; x++) {
        const fx: f32 = (<f32>x / <f32>w - 0.5) * asp;
        let field: f32 = 0;
        // N is a compile-time constant and the arrays have length N
        for (let i = 0; i < N; i++) {
          const dx: f32 = fx - unchecked(ox[i]);
          const dy: f32 = fy - unchecked(oy[i]);
          // 1e-5 and 1.09 below are f32 constants, as in Go: the f32
          // context types the literal, no Math.fround needed
          const d2: f32 = dx * dx + dy * dy + 1e-5;
          field += unchecked(rad2[i]) / d2;
        }
        // field is about 1 on a ball's surface and explodes inside;
        // v/(1+v) compresses that into a usable 0..1 ramp
        const v: f32 = field / (1.6 + field);
        let idx = min(<i32>(v * 255), 255);
        // rim: the iso-surface where the balls meet flares white
        if (field > 1.0 && field < 1.09) idx = 255;
        unchecked((pix[row + x] = pal[idx]));
      }
    }
    // @end
  }
}
