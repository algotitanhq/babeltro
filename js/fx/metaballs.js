// Metaballs: sum radial fields and shade the iso-contours. Every pixel
// evaluates sum(r^2 / d^2) with one division per ball and no square root,
// and the contour band gets a hot rim so the blobs read as liquid.

import { f32, sin, cos } from '../lib/fmath.js';
import { SUNSET } from '../lib/palette.js';

const N = 6;
const EPS = f32(1e-5);
const KNEE = f32(1.6);
const RIM_HI = f32(1.09);

export class Metaballs {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.bx = new Float32Array(N); // centres, in normalised space
    this.by = new Float32Array(N);
    this.rad = new Float32Array(N);
    // per-frame, per-ball terms hoisted out of the pixel loop
    this.ox = new Float32Array(N);
    this.oy = new Float32Array(N);
    this.rad2 = new Float32Array(N);
  }

  resize(w, h) {
    this.w = w;
    this.h = h;
  }

  prepare(s) {
    const t = f32(s.beat);
    for (let i = 0; i < N; i++) {
      // each ball orbits on its own ellipse and breathes
      const a = f32(f32(t * f32(f32(0.35) + f32(i * f32(0.07)))) + f32(i * f32(2.1)));
      const wx = f32(1 + f32(f32(0.3) * sin(f32(f32(t * 0.5) + i))));
      const wy = f32(1 + f32(f32(0.3) * cos(f32(f32(t * f32(0.4)) + i * 2))));
      this.bx[i] = 0.5 + f32(f32(f32(0.2) * cos(a)) * wx);
      this.by[i] = 0.5 + f32(f32(f32(0.2) * sin(f32(f32(a * f32(1.3)) + i))) * wy);
      this.rad[i] = f32(0.105) + f32(f32(0.025) * sin(f32(f32(t * f32(1.1)) + f32(i * f32(1.7)))));
    }
  }

  draw(fb) {
    const { w, h, pix } = fb;
    const { bx, by, rad, ox, oy, rad2 } = this;
    const pal = SUNSET;
    // x is scaled by width/height so a circle in field space is a circle on
    // screen, whatever the aspect ratio
    const asp = f32(w / h);
    for (let i = 0; i < N; i++) {
      ox[i] = f32(bx[i] - 0.5) * asp;
      oy[i] = by[i] - 0.5;
      rad2[i] = rad[i] * rad[i]; // the field is about 1 on a ball's surface
    }

    // @excerpt METABALLS
    for (let y = 0; y < h; y++) {
      const fy = f32(f32(y / h) - 0.5);
      const row = y * w;
      for (let x = 0; x < w; x++) {
        const fx = f32(f32(f32(x / w) - 0.5) * asp);
        let field = 0;
        for (let i = 0; i < N; i++) {
          const dx = f32(fx - ox[i]);
          const dy = f32(fy - oy[i]);
          const d2 = f32(f32(f32(dx * dx) + f32(dy * dy)) + EPS);
          field = f32(field + f32(rad2[i] / d2));
        }
        // the field explodes inside a ball; v/(k+v) squeezes it into 0..1
        const v = f32(field / f32(KNEE + field));
        let idx = f32(v * 255) | 0;
        if (idx > 255) idx = 255;
        // rim: the iso-surface where the balls meet flares white
        if (field > 1 && field < RIM_HI) idx = 255;
        pix[row + x] = pal[idx];
      }
    }
    // @end
  }
}
