// Fire: the Doom fire. A heat buffer seeded at the bottom row and diffused
// upward with a little random sideways drift; integers only, one byte per
// pixel, read through a palette.

import { FB } from '../canvas';
import { sin } from '../fmath';
import { EMBER } from '../palette';
import { Effect } from './effect';

export class Fire extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  buf: StaticArray<u8> = new StaticArray<u8>(0);
  rng: u32 = 0x9e3779b9;
  frame: i32 = 0;

  resize(w: i32, h: i32): void {
    if (w == this.w && h == this.h) return;
    this.w = w;
    this.h = h;
    this.buf = new StaticArray<u8>(w * h); // zeroed
  }

  // xorshift32, inlined into the loop
  // @ts-ignore: decorator
  @inline rand(): u32 {
    let x = this.rng;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    this.rng = x;
    return x;
  }

  prepare(t: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    this.frame = frame;
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w, h = fb.h;
    if (this.w != w || this.h != h) this.resize(w, h);
    const buf = this.buf;

    // seed the hottest row: a slow wave for the uneven base, a random term
    // so the tongues do not look periodic
    const last = (h - 1) * w;
    const t: f32 = <f32>this.frame * 0.05;
    for (let x = 0; x < w; x++) {
      const fx: f32 = <f32>x / <f32>w;
      const wv: f32 = 0.5 + 0.5 * sin(fx * 11 + t) * 0.6 + 0.5 * sin(fx * 23 - t * 1.7) * 0.4;
      let v: f32 = 150 + wv * 90 + <f32>(this.rand() & 31) - 16;
      if (v > 255) v = 255;
      else if (v < 90) v = 90;
      buf[last + x] = <u8>v;
    }

    const pal = EMBER;
    const pix = fb.pix;
    for (let x = 0; x < w; x++) pix[last + x] = pal[buf[last + x]];
    // @excerpt FIRE
    // Every index is in [0, w*h) and a u8 cannot exceed the palette's 255,
    // so the whole loop runs unchecked.
    for (let y = h - 1; y > 0; y--) {
      const src = y * w;
      const dst = (y - 1) * w;
      for (let x = 0; x < w; x++) {
        if (unchecked(buf[src + x]) == 0) {
          if (unchecked(buf[dst + x]) != 0) unchecked((buf[dst + x] = 0));
          continue;
        }
        const r = this.rand();
        // -1, 0 or +1: r % 3 on a u32 is the unsigned remainder
        const sx = min(max(x + <i32>(r % 3) - 1, 0), w - 1);
        const v = unchecked(buf[src + sx]);
        const decay = <u8>((r >> 16) & 1);
        unchecked((buf[dst + x] = v > decay ? v - decay : 0));
      }
      for (let x = 0; x < w; x++) unchecked((pix[dst + x] = pal[buf[dst + x]]));
    }
    // @end
  }
}
