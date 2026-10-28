// Plasma: four summed sine fields. Done naively it is four sin() calls per
// pixel; here three of the four terms are 1D tables rebuilt once per frame,
// leaving a single table lookup per pixel.

import { FB } from '../canvas';
import { sin } from '../fmath';
import { SUNSET } from '../palette';
import { Effect } from './effect';

export class Plasma extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  rad: StaticArray<f32> = new StaticArray<f32>(0); // distance from the centre, per pixel
  sx: StaticArray<f32> = new StaticArray<f32>(0); // sin(x) term, per column
  sy: StaticArray<f32> = new StaticArray<f32>(0); // sin(y) term, per row
  sxy: StaticArray<f32> = new StaticArray<f32>(0); // sin(x + y) term, indexed by x + y
  phase: f32 = 0;
  // the ladder: 1 calls sin() four times per pixel, 2 reads the sine table
  // four times per pixel, 3 (the default) moves three of the four lookups
  // into per-frame 1D tables
  step: i32 = 0;
  t: f32 = 0;
  kx: f32 = 0;
  ky: f32 = 0;
  cx: f32 = 0;
  cy: f32 = 0;
  kr: f32 = 0;

  setStep(n: i32): void {
    this.step = n;
  }

  resize(w: i32, h: i32): void {
    if (w == this.w && h == this.h) return;
    this.w = w;
    this.h = h;
    const rad = (this.rad = new StaticArray<f32>(w * h));
    const cx: f32 = <f32>w * 0.5, cy: f32 = <f32>h * 0.5;
    const k: f32 = 44.0 / <f32>(w + h);
    for (let y = 0; y < h; y++) {
      const dy: f32 = <f32>y - cy;
      for (let x = 0; x < w; x++) {
        const dx: f32 = <f32>x - cx;
        unchecked((rad[y * w + x] = Mathf.sqrt(dx * dx + dy * dy) * k));
      }
    }
    this.sx = new StaticArray<f32>(w);
    this.sy = new StaticArray<f32>(h);
    this.sxy = new StaticArray<f32>(w + h);
  }

  prepare(beat: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    const t = <f32>beat;
    const kx: f32 = 26.0 / <f32>w;
    const ky: f32 = 26.0 / <f32>h;
    const sx = this.sx, sy = this.sy, sxy = this.sxy;
    for (let x = 0; x < w; x++) unchecked((sx[x] = sin(<f32>x * kx + t * 1.3)));
    for (let y = 0; y < h; y++) unchecked((sy[y] = sin(<f32>y * ky * 1.35 - t * 1.1)));
    for (let i = 0; i < w + h; i++) unchecked((sxy[i] = sin(<f32>i * kx * 0.85 + t * 0.8)));
    this.phase = t * 2.6;
    this.t = t;
    this.kx = kx;
    this.ky = ky;
    this.cx = <f32>w * 0.5;
    this.cy = <f32>h * 0.5;
    this.kr = 44.0 / <f32>(w + h);
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    if (this.step == 1) {
      this.drawSin(fb, y0, y1);
      return;
    }
    if (this.step == 2) {
      this.drawTable(fb, y0, y1);
      return;
    }
    const w = fb.w;
    const pix = fb.pix;
    const pal = SUNSET;
    const phase = this.phase;
    const rad = this.rad, sx = this.sx, sxyTab = this.sxy;
    // @excerpt PLASMA
    // Every index below is in range by construction (x < w, y < h, and the
    // tables were sized from w and h), so unchecked() drops the bounds
    // check. The palette index is clamped first.
    for (let y = y0; y < y1; y++) {
      const sy = unchecked(this.sy[y]);
      const row = y * w;
      for (let x = 0; x < w; x++) {
        const v: f32 =
          unchecked(sx[x]) + sy + unchecked(sxyTab[y + x]) + sin(unchecked(rad[row + x]) + phase);
        const i = min(max(<i32>(v * 36 + 127.5), 0), 255);
        unchecked((pix[row + x] = pal[i]));
      }
    }
    // @end
  }

  // The plasma as you would first write it: every term, every pixel,
  // straight from the maths library.
  drawSin(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w;
    const pix = fb.pix;
    const pal = SUNSET;
    const t = this.t, kx = this.kx, ky = this.ky, kr = this.kr, phase = this.phase;
    const cx = this.cx, cy = this.cy;
    // @excerpt PLASMA/1
    for (let y = y0; y < y1; y++) {
      const dy: f32 = <f32>y - cy;
      for (let x = 0; x < w; x++) {
        const dx: f32 = <f32>x - cx;
        const rad: f32 = Mathf.sqrt(dx * dx + dy * dy) * kr;
        // Math.sin is the f64 sine, as Go's math.Sin; Mathf.sin would be
        // the f32 one. Either is compiled into the module.
        const v: f32 =
          <f32>Math.sin(<f64>(<f32>x * kx + t * 1.3)) +
          <f32>Math.sin(<f64>(<f32>y * ky * 1.35 - t * 1.1)) +
          <f32>Math.sin(<f64>(<f32>(x + y) * kx * 0.85 + t * 0.8)) +
          <f32>Math.sin(<f64>(rad + phase));
        const i = min(max(<i32>(v * 36 + 127.5), 0), 255);
        pix[y * w + x] = pal[i];
      }
    }
    // @end
  }

  // The same structure as drawSin, reading the sine table instead.
  drawTable(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w;
    const pix = fb.pix;
    const pal = SUNSET;
    const t = this.t, kx = this.kx, ky = this.ky, kr = this.kr, phase = this.phase;
    const cx = this.cx, cy = this.cy;
    // @excerpt PLASMA/2
    for (let y = y0; y < y1; y++) {
      const dy: f32 = <f32>y - cy;
      for (let x = 0; x < w; x++) {
        const dx: f32 = <f32>x - cx;
        const rad: f32 = Mathf.sqrt(dx * dx + dy * dy) * kr;
        const v: f32 =
          sin(<f32>x * kx + t * 1.3) +
          sin(<f32>y * ky * 1.35 - t * 1.1) +
          sin(<f32>(x + y) * kx * 0.85 + t * 0.8) +
          sin(rad + phase);
        const i = min(max(<i32>(v * 36 + 127.5), 0), 255);
        pix[y * w + x] = pal[i];
      }
    }
    // @end
  }
}
