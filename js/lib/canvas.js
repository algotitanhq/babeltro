// The software framebuffer every effect draws into.
//
// Pixels are packed as 0xAABBGGRR in a Uint32Array, which on a little-endian
// machine is R, G, B, A in memory: exactly an ImageData buffer.
//
// A note on colours in JS: `0xff000000 | b << 16 | …` is an int32, so it is
// negative whenever alpha is set. That does not matter: storing it into a
// Uint32Array keeps the same 32 bits.

import { f2b } from './palette.js';

export class Framebuffer {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.pix = new Uint32Array(w * h);
  }

  /** Adds colour c scaled by intensity/255 at index i, saturating. */
  additive(i, c, intensity) {
    if (intensity === 0) return;
    const p = this.pix[i];
    // integer division: Go's uint32 `/` truncates, JS needs the `| 0`
    let r = (p & 0xff) + (((c & 0xff) * intensity) / 255 | 0);
    let g = ((p >>> 8) & 0xff) + ((((c >>> 8) & 0xff) * intensity) / 255 | 0);
    let b = ((p >>> 16) & 0xff) + ((((c >>> 16) & 0xff) * intensity) / 255 | 0);
    if (r > 255) r = 255;
    if (g > 255) g = 255;
    if (b > 255) b = 255;
    this.pix[i] = 0xff000000 | (b << 16) | (g << 8) | r;
  }

  /** A 1px horizontal line. */
  hline(x, y, w, c) {
    if (y < 0 || y >= this.h) return;
    const row = y * this.w;
    for (let xx = x; xx < x + w; xx++) {
      if (xx >= 0 && xx < this.w) this.pix[row + xx] = c;
    }
  }
}

/** Normalised float64 channels to a packed colour, clamping to [0,1]. */
export function fromFloat(r, g, b) {
  return 0xff000000 | (f2b(b) << 16) | (f2b(g) << 8) | f2b(r);
}

/** Clamps a float64 to [0,1]. */
export function clamp01(v) {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}
