// Mandelbrot: a dive into the boundary. It is the most expensive scene, so
// it renders on a coarse grid of step×step blocks: at 60 fps in motion nobody
// can tell. Go does this in float64, which is exactly a JS number.

import { ICE, paletteAt } from '../lib/palette.js';

const INSIDE = 0xff0a0812;

export class Mandelbrot {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.cx = 0;
    this.cy = 0;
    this.scale = 0;
    this.maxIter = 192;
    this.step = 2;
  }

  resize(w, h) {
    this.w = w;
    this.h = h;
    // keep the block size constant in screen terms as the window grows
    this.step = w > 1600 ? 3 : 2;
  }

  prepare(s) {
    const u = Math.min(s.beat, 14) / 12;
    // the camera slides onto the target quickly, then the exponential dive
    // does the work
    const k = 1 - Math.exp(-8 * u);
    // the target is the seahorse valley, where the boundary never opens into
    // a flat interior, so the whole frame stays fractal at any depth
    this.scale = 2.9 * Math.exp(-u * u * 3.6);
    // deep frames need the iteration budget; wide ones do not
    this.maxIter = 64 + ((128 * u) | 0);
    this.cx = -0.5 + (-0.743643887037151 + 0.5) * k;
    this.cy = 0.0 + 0.131825904205330 * k;
  }

  draw(fb) {
    const { w, h, pix } = fb;
    const { step, maxIter, scale } = this;
    const asp = h / w;
    const x0 = this.cx - scale * 0.5;
    const y0 = this.cy - scale * 0.5 * asp;
    const d = scale / w; // plane units per pixel

    for (let by = 0; by < h; by += step) {
      const ci = y0 + by * d;
      const yEnd = Math.min(by + step, h);
      for (let bx = 0; bx < w; bx += step) {
        const it = mandelIter(x0 + bx * d, ci, maxIter);
        // the ramp is anchored to a fixed iteration count, not to maxIter,
        // so raising the budget for a deep zoom does not darken the picture
        const c = it >= maxIter ? INSIDE : paletteAt(ICE, Math.min(Math.sqrt(it / 40), 1) * 0.92 + 0.04);
        const xEnd = Math.min(bx + step, w);
        for (let yy = by; yy < yEnd; yy++) pix.fill(c, yy * w + bx, yy * w + xEnd);
      }
    }
  }
}

// @excerpt MANDELBROT
function mandelIter(cx, cy, max) {
  // cheap escape test for the main cardioid and the period-2 bulb
  const x = cx - 0.25;
  const y2 = cy * cy;
  const q = x * x + y2;
  if (q * (q + x) <= 0.25 * y2) return max;
  if ((cx + 1) * (cx + 1) + y2 <= 0.0625) return max;

  // z = z² + c, keeping the squares for the escape test
  let zx = 0, zy = 0, zx2 = 0, zy2 = 0;
  for (let i = 0; i < max; i++) {
    zy = 2 * zx * zy + cy;
    zx = zx2 - zy2 + cx;
    zx2 = zx * zx;
    zy2 = zy * zy;
    if (zx2 + zy2 > 4) return i;
  }
  return max;
}
// @end
