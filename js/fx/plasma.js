// Plasma: four summed sine fields, the oldest trick in the demoscene book.
// Done naively it is four sin() calls per pixel; here three of the four terms
// are 1D tables rebuilt once per frame, leaving a single lookup per pixel.

import { f32, sin, sqrt32, SIN_TAB, TAB_MASK, INV_2PI } from '../lib/fmath.js';
import { SUNSET } from '../lib/palette.js';

const F_X = f32(1.3);
const F_Y = f32(1.35);
const F_YT = f32(1.1);
const F_D = f32(0.85);
const F_DT = f32(0.8);
const F_PHASE = f32(2.6);

export class Plasma {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.rad = null; // distance from the centre, per pixel
    this.sx = null; // sin(x) term, per column
    this.sy = null; // sin(y) term, per row
    this.sxy = null; // sin(x + y) term, indexed by x + y
    this.phase = 0;
  }

  resize(w, h) {
    if (w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    const rad = (this.rad = new Float32Array(w * h));
    const cx = f32(w * 0.5);
    const cy = f32(h * 0.5);
    const k = f32(44 / (w + h));
    for (let y = 0; y < h; y++) {
      const dy = f32(y - cy);
      for (let x = 0; x < w; x++) {
        const dx = f32(x - cx);
        rad[y * w + x] = sqrt32(f32(f32(dx * dx) + f32(dy * dy))) * k;
      }
    }
    this.sx = new Float32Array(w);
    this.sy = new Float32Array(h);
    this.sxy = new Float32Array(w + h);
  }

  prepare(s) {
    const { w, h, sx, sy, sxy } = this;
    const t = f32(s.beat);
    const kx = f32(26 / w);
    const ky = f32(26 / h);
    const tx = f32(t * F_X);
    const ty = f32(t * F_YT);
    const td = f32(t * F_DT);
    for (let x = 0; x < w; x++) sx[x] = sin(f32(f32(x * kx) + tx));
    for (let y = 0; y < h; y++) sy[y] = sin(f32(f32(f32(y * ky) * F_Y) - ty));
    for (let i = 0; i < w + h; i++) sxy[i] = sin(f32(f32(f32(i * kx) * F_D) + td));
    this.phase = f32(t * F_PHASE);
  }

  draw(fb) {
    const { w, h, pix } = fb;
    const { rad, sx, sy, sxy, phase } = this;
    const pal = SUNSET;

    // @excerpt PLASMA
    for (let y = 0; y < h; y++) {
      const syv = sy[y];
      const row = y * w;
      for (let x = 0; x < w; x++) {
        // three 1D tables, and the fourth field: sin(radius + phase), read
        // from the sine table inline (see the tunnel for why not sin())
        const a = f32(rad[row + x] + phase);
        const sr = SIN_TAB[(f32(a * INV_2PI) | 0) & TAB_MASK];
        const v = f32(f32(f32(sx[x] + syv) + sxy[y + x]) + sr);
        let i = f32(f32(v * 36) + 127.5) | 0;
        if (i < 0) i = 0;
        else if (i > 255) i = 255;
        pix[row + x] = pal[i];
      }
    }
    // @end
  }
}
