// Mandelbrot: dives into the seahorse valley forever. The most expensive
// scene, so by default it renders on blocks of step×step pixels.

import { FB } from '../canvas';
import { ICE, at } from '../palette';
import { Effect } from './effect';

export class Mandelbrot extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  cx: f64 = 0;
  cy: f64 = 0;
  scale: f64 = 0;
  maxIter: i32 = 192;
  step: i32 = 2;
  // the ladder: 1 iterates every pixel with no shortcut, 2 adds the closed
  // form test for the cardioid and the bulb, 3 (the default) also renders on
  // blocks of step×step pixels
  rung: i32 = 0;

  setStep(n: i32): void {
    this.rung = n;
  }

  resize(w: i32, h: i32): void {
    this.w = w;
    this.h = h;
    // keep the block size constant in screen terms as the window grows
    this.step = w > 1600 ? 3 : 2;
  }

  prepare(beat: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    const t = min(beat, 14);
    const u: f64 = t / 12;
    // slide onto the target quickly, then let the exponential dive work
    const k: f64 = 1 - Math.exp(-8 * u);
    this.scale = 2.9 * Math.exp(-u * u * 3.6);
    this.maxIter = 64 + <i32>(u * 128);
    this.cx = -0.5 + (-0.743643887037151 + 0.5) * k;
    this.cy = 0.0 + 0.131825904205330 * k;
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w, h = fb.h;
    const pix = fb.pix;
    let step = this.step;
    // Go passes the escape function as a func value. AssemblyScript has
    // first-class functions too, but each call would be a call_indirect the
    // optimiser cannot inline; a flag tested once per block lets both
    // loops inline.
    const plain = this.rung == 1;
    if (this.rung == 1 || this.rung == 2) step = 1;
    const asp: f64 = <f64>h / <f64>w;
    const span = this.scale;
    const x0: f64 = this.cx - span * 0.5;
    const y0w: f64 = this.cy - span * 0.5 * asp;
    // units per pixel: the loop advances by whole blocks
    const d: f64 = span / <f64>w;
    const maxIter = this.maxIter;
    const pal = ICE;

    let sy = (y0 + step - 1) / step;
    // @excerpt MANDELBROT
    for (; sy * step < y1; sy++) {
      const cy: f64 = y0w + <f64>(sy * step) * d;
      const yStart = sy * step;
      const yEnd = min(yStart + step, h);
      for (let x = 0; x < w; x += step) {
        const sx = x / step;
        const cx: f64 = x0 + <f64>(sx * step) * d;
        const it = plain ? mandelIterPlain(cx, cy, maxIter) : mandelIter(cx, cy, maxIter);
        let c: u32;
        if (it >= maxIter) {
          c = 0xff0a0812;
        } else {
          // the ramp is anchored to a fixed iteration count, not to maxIter
          const v = min(Math.sqrt(<f64>it / 40), 1);
          c = at(pal, v * 0.92 + 0.04);
        }
        const xEnd = min(x + step, w);
        // the block is clipped to the frame, so its stores are unchecked
        for (let yy = yStart; yy < yEnd; yy++) {
          const row = yy * w;
          for (let xx = x; xx < xEnd; xx++) unchecked((pix[row + xx] = c));
        }
      }
    }
    // @end
  }
}

// @excerpt MANDELBROT/2
// @ts-ignore: decorator
@inline function mandelIter(cx: f64, cy: f64, maxIter: i32): i32 {
  // cheap escape test for the main cardioid and the period-2 bulb
  const x: f64 = cx - 0.25;
  const y2: f64 = cy * cy;
  const q: f64 = x * x + y2;
  if (q * (q + x) <= 0.25 * y2) return maxIter;
  if ((cx + 1) * (cx + 1) + y2 <= 0.0625) return maxIter;
  let zx: f64 = 0, zy: f64 = 0;
  let zx2: f64 = 0, zy2: f64 = 0;
  for (let i = 0; i < maxIter; i++) {
    zy = 2 * zx * zy + cy;
    zx = zx2 - zy2 + cx;
    zx2 = zx * zx;
    zy2 = zy * zy;
    if (zx2 + zy2 > 4) return i;
  }
  return maxIter;
}
// @end

// The escape-time loop and nothing else: every point inside the set runs
// the full budget before it gives up.
// @excerpt MANDELBROT/1
// @ts-ignore: decorator
@inline function mandelIterPlain(cx: f64, cy: f64, maxIter: i32): i32 {
  let zx: f64 = 0, zy: f64 = 0;
  let zx2: f64 = 0, zy2: f64 = 0;
  for (let i = 0; i < maxIter; i++) {
    zy = 2 * zx * zy + cy;
    zx = zx2 - zy2 + cx;
    zx2 = zx * zx;
    zy2 = zy * zy;
    if (zx2 + zy2 > 4) return i;
  }
  return maxIter;
}
// @end
