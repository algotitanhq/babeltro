// Starfield: a warp-speed star tunnel. Stars live in 3D, are projected in
// perspective and dragged into short streaks from their previous depth.

import { FB, fromFloat } from '../canvas';
import { Rng } from '../fmath';
import { Effect } from './effect';

const N: i32 = 1600;

export class Starfield extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  // Go keeps an array of structs; here each field is its own StaticArray,
  // a flat run of numbers with no per-star object
  sx: StaticArray<f32> = new StaticArray<f32>(N);
  sy: StaticArray<f32> = new StaticArray<f32>(N);
  sz: StaticArray<f32> = new StaticArray<f32>(N);
  px0: StaticArray<i32> = new StaticArray<i32>(N);
  py0: StaticArray<i32> = new StaticArray<i32>(N);
  px1: StaticArray<i32> = new StaticArray<i32>(N);
  py1: StaticArray<i32> = new StaticArray<i32>(N);
  pc: StaticArray<u32> = new StaticArray<u32>(N);
  bg: StaticArray<u32> = new StaticArray<u32>(0);
  rng: Rng = new Rng(0x6005e);
  seeded: bool = false;

  resize(w: i32, h: i32): void {
    if (w == this.w && h == this.h) return;
    this.w = w;
    this.h = h;
    if (!this.seeded) {
      const rng = this.rng;
      for (let i = 0; i < N; i++) {
        // one statement per draw: x, then y, then z, as Go's struct literal
        this.sx[i] = (rng.float32() * 2 - 1) * 1.6;
        this.sy[i] = (rng.float32() * 2 - 1) * 1.6;
        this.sz[i] = rng.float32() * 40 + 0.2;
      }
      this.seeded = true;
    }
    this.buildBackdrop();
  }

  // the deep-navy vignette, once per size change
  buildBackdrop(): void {
    const w = this.w, h = this.h;
    if (this.bg.length != w * h) this.bg = new StaticArray<u32>(w * h);
    const bg = this.bg;
    for (let y = 0; y < h; y++) {
      const dy: f64 = <f64>y / <f64>h - 0.5;
      for (let x = 0; x < w; x++) {
        const dx: f64 = <f64>x / <f64>w - 0.5;
        const v: f64 = dx * dx + dy * dy;
        const r: f64 = max(0.02 - v * 0.03, 0);
        const g: f64 = max(0.02 - v * 0.025, 0);
        const b: f64 = max(0.05 - v * 0.03, 0);
        unchecked((bg[y * w + x] = fromFloat(r, g, b)));
      }
    }
  }

  prepare(t: f64, dtf: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    const cx: f32 = <f32>w * 0.5, cy: f32 = <f32>h * 0.5;
    // accelerate over the scene so the entry has a kick
    const speed = <f32>(2.5 + Math.min(t, 3) * 4);
    let dt = <f32>dtf;
    if (dt > 0.1) dt = 0.1;
    const dz: f32 = speed * dt;
    const sx = this.sx, sy = this.sy, sz = this.sz, rng = this.rng;

    // @excerpt STARFIELD
    for (let i = 0; i < N; i++) {
      let z: f32 = unchecked(sz[i]) - dz;
      if (z < 0.8) {
        z += 40;
        unchecked((sx[i] = (rng.float32() * 2 - 1) * 1.1));
        unchecked((sy[i] = (rng.float32() * 2 - 1) * 1.1));
      }
      unchecked((sz[i] = z));
      const x = unchecked(sx[i]), y = unchecked(sy[i]);
      const f: f32 = 1.0 / z;
      const zoom: f32 = <f32>w * 0.78;
      const x0: f32 = cx + x * f * zoom;
      const y0: f32 = cy + y * f * zoom;
      const f2: f32 = 1.0 / (z + dz * 2.4);
      const x1: f32 = cx + x * f2 * zoom;
      const y1: f32 = cy + y * f2 * zoom;

      // brighter and bluer as the star gets close
      const near: f32 = 1 - z / 40;
      const b: f32 = near * near;
      const r = <u32>(b * 120 + 40);
      const g = <u32>(b * 190 + 40);
      const bl = <u32>((b * 0.75 + 0.25) * 255);
      // f32 to i32 truncates toward zero, like Go's int32(); z >= 0.8 keeps
      // every coordinate small, so the range never matters
      unchecked((this.px0[i] = <i32>x0));
      unchecked((this.py0[i] = <i32>y0));
      unchecked((this.px1[i] = <i32>x1));
      unchecked((this.py1[i] = <i32>y1));
      unchecked((this.pc[i] = 0xff000000 | (bl << 16) | (g << 8) | r));
    }
    // @end
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w, h = fb.h;
    if (this.bg.length == w * h) {
      memory.copy(
        changetype<usize>(fb.pix) + ((<usize>(y0 * w)) << 2),
        changetype<usize>(this.bg) + ((<usize>(y0 * w)) << 2),
        (<usize>((y1 - y0) * w)) << 2,
      );
    } else {
      fb.pix.fill(0xff050405);
    }
    for (let i = 0; i < N; i++) {
      const x1 = this.px1[i], yy1 = this.py1[i];
      // additive line from the trailing point to the head
      drawLineAdd(fb, this.px0[i], this.py0[i], x1, yy1, this.pc[i]);
      // bright head pixel
      if (x1 >= 0 && x1 < w && yy1 >= 0 && yy1 < h) fb.pix[yy1 * w + x1] = 0xffcceeff;
    }
  }
}

// A Bresenham line adding colour, so overlapping stars accumulate.
function drawLineAdd(fb: FB, x0: i32, y0: i32, x1: i32, y1: i32, c: u32): void {
  const dx = abs(x1 - x0);
  const dy = -abs(y1 - y0);
  const sx = x0 < x1 ? 1 : -1;
  const sy = y0 < y1 ? 1 : -1;
  let err = dx + dy;
  while (true) {
    if (x0 >= 0 && x0 < fb.w && y0 >= 0 && y0 < fb.h) {
      const i = y0 * fb.w + x0;
      const p = unchecked(fb.pix[i]);
      // TypeScript's & binds looser than +, unlike Go's: parenthesised
      let r = (p & 0xff) + (c & 0xff);
      let g = ((p >> 8) & 0xff) + ((c >> 8) & 0xff);
      let b = ((p >> 16) & 0xff) + ((c >> 16) & 0xff);
      if (r > 255) r = 255;
      if (g > 255) g = 255;
      if (b > 255) b = 255;
      unchecked((fb.pix[i] = 0xff000000 | (b << 16) | (g << 8) | r));
    }
    if (x0 == x1 && y0 == y1) break;
    const e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x0 += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y0 += sy;
    }
  }
}
