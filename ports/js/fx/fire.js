// Fire: the Doom fire algorithm. A heat buffer is seeded at the bottom row
// and diffused upward with a little random sideways drift. Integer only, one
// byte per pixel (a Uint8Array), read through a palette ramp.

import { f32, sin } from '../lib/fmath.js';
import { EMBER } from '../lib/palette.js';

const K_T = f32(0.05);
const K_T2 = f32(1.7);
const W1 = f32(0.6);
const W2 = f32(0.4);

export class Fire {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.buf = null;
    this.rng = 0x9e3779b9; // the fire's own xorshift32 state, a uint32
    this.frame = 0;
  }

  resize(w, h) {
    if (w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    this.buf = new Uint8Array(w * h);
  }

  prepare(s) {
    this.frame = s.frame;
  }

  draw(fb) {
    const { w, h, pix } = fb;
    const { buf } = this;
    const pal = EMBER;
    // The generator is inlined: its state lives in a local, which the JIT
    // keeps in a register, and is written back once at the end. `x >>> 0`
    // reads the int32 bits as the uint32 Go has.
    let x32 = this.rng;

    // seed the hottest row: a slow horizontal wave gives the fire its uneven
    // base, the random term keeps the tongues from looking periodic
    const last = (h - 1) * w;
    const t = f32(this.frame * K_T);
    const t2 = f32(t * K_T2);
    for (let x = 0; x < w; x++) {
      const fx = f32(x / w);
      const s1 = f32(f32(0.5 * sin(f32(f32(fx * 11) + t))) * W1);
      const s2 = f32(f32(0.5 * sin(f32(f32(fx * 23) - t2))) * W2);
      const wv = f32(f32(0.5 + s1) + s2);
      x32 ^= x32 << 13;
      x32 ^= x32 >>> 17;
      x32 ^= x32 << 5;
      let v = f32(f32(f32(150 + f32(wv * 90)) + (x32 & 31)) - 16);
      if (v > 255) v = 255;
      else if (v < 90) v = 90;
      buf[last + x] = v | 0;
    }

    // The bottom row is complete: colour it now.
    for (let x = 0; x < w; x++) pix[last + x] = pal[buf[last + x]];

    // @excerpt FIRE
    // Diffuse upward: every destination pixel takes one value from the row
    // below, offset sideways by a random -1/0/+1 (gather, not scatter, so
    // each pixel is written exactly once). Each row is coloured as soon as
    // it is complete, so the buffer is touched once per frame.
    for (let y = h - 1; y > 0; y--) {
      const src = y * w;
      const dst = src - w;
      for (let x = 0; x < w; x++) {
        if (buf[src + x] === 0) {
          buf[dst + x] = 0;
          continue;
        }
        x32 ^= x32 << 13;
        x32 ^= x32 >>> 17;
        x32 ^= x32 << 5;
        const r = x32 >>> 0;
        let sx = x + (r % 3) - 1; // -1, 0 or +1: no sideways drift on average
        if (sx < 0) sx = 0;
        else if (sx >= w) sx = w - 1;
        const v = buf[src + sx];
        const decay = (r >>> 16) & 1;
        buf[dst + x] = v > decay ? v - decay : 0;
      }
      for (let x = dst; x < src; x++) pix[x] = pal[buf[x]];
    }
    // @end

    this.rng = x32 >>> 0;
  }
}
