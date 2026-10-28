// Starfield: a warp-speed star tunnel. Stars live in 3D, get projected in
// perspective and dragged into short streaks; the streak is what sells the
// speed, so each star draws from its previous depth to its current one.
//
// The stars are stored as parallel typed arrays ("structure of arrays")
// rather than an array of objects: Float32Array gives float32 storage for
// free, and the projected segments go into an Int32Array.

import { f32, Rng } from '../lib/fmath.js';
import { fromFloat } from '../lib/canvas.js';

const COUNT = 1600;
const NEAR = f32(0.8);
const DT_MAX = f32(0.1);
const ZOOM_K = f32(0.78);
const STREAK = f32(2.4);
const SPREAD = f32(1.6);
const RESPAWN = f32(1.1);
const Z_MIN = f32(0.2);
const B_BIAS = f32(0.25);
const B_GAIN = f32(0.75);

export class Starfield {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.rng = new Rng(0x6005e);
    this.x = new Float32Array(COUNT);
    this.y = new Float32Array(COUNT);
    this.z = new Float32Array(COUNT);
    for (let i = 0; i < COUNT; i++) {
      // three separate statements: the order of the calls is the sequence
      this.x[i] = f32(f32(this.rng.float32() * 2) - 1) * SPREAD;
      this.y[i] = f32(f32(this.rng.float32() * 2) - 1) * SPREAD;
      this.z[i] = f32(this.rng.float32() * 40) + Z_MIN;
    }
    // projected segment per star: x0, y0, x1, y1, and its colour
    this.seg = new Int32Array(COUNT * 4);
    this.col = new Uint32Array(COUNT);
    this.bg = null;
  }

  resize(w, h) {
    if (w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    this.buildBackdrop();
  }

  // The deep-navy vignette never changes, so it is painted once per size and
  // copied every frame: far cheaper than evaluating it per pixel.
  buildBackdrop() {
    const { w, h } = this;
    const bg = (this.bg = new Uint32Array(w * h));
    for (let y = 0; y < h; y++) {
      const dy = y / h - 0.5;
      for (let x = 0; x < w; x++) {
        const dx = x / w - 0.5;
        const v = dx * dx + dy * dy;
        bg[y * w + x] = fromFloat(
          Math.max(0.02 - v * 0.03, 0),
          Math.max(0.02 - v * 0.025, 0),
          Math.max(0.05 - v * 0.03, 0),
        );
      }
    }
  }

  prepare(s) {
    const { w, h, x: xs, y: ys, z: zs, seg, col, rng } = this;
    const cx = f32(w * 0.5);
    const cy = f32(h * 0.5);
    const zoom = f32(w * ZOOM_K);
    // accelerate over the scene so the entry has a kick
    const speed = f32(2.5 + Math.min(s.beat, 3) * 4);
    let dt = f32(s.dt);
    if (dt > DT_MAX) dt = DT_MAX;
    const dz = f32(speed * dt);
    const trail = f32(dz * STREAK);

    // @excerpt STARFIELD
    for (let i = 0; i < COUNT; i++) {
      let z = f32(zs[i] - dz);
      if (z < NEAR) {
        z = f32(z + 40);
        xs[i] = f32(f32(rng.float32() * 2) - 1) * RESPAWN;
        ys[i] = f32(f32(rng.float32() * 2) - 1) * RESPAWN;
      }
      zs[i] = z;
      // perspective: divide by depth, now and a little further back
      const px = xs[i], py = ys[i];
      const f = f32(1 / z);
      const f2 = f32(1 / f32(z + trail));
      const k = i * 4;
      seg[k] = f32(cx + f32(f32(px * f) * zoom)); // Int32Array store truncates
      seg[k + 1] = f32(cy + f32(f32(py * f) * zoom));
      seg[k + 2] = f32(cx + f32(f32(px * f2) * zoom));
      seg[k + 3] = f32(cy + f32(f32(py * f2) * zoom));

      // brighter and bluer as the star gets close
      const near = f32(1 - f32(z / 40));
      const b = f32(near * near);
      const r = f32(f32(120 * b) + 40) | 0;
      const g = f32(f32(190 * b) + 40) | 0;
      const bl = f32(255 * f32(B_BIAS + f32(B_GAIN * b))) | 0;
      col[i] = 0xff000000 | (bl << 16) | (g << 8) | r;
    }
    // @end
  }

  draw(fb) {
    const { w, h, pix } = fb;
    const { seg, col } = this;
    pix.set(this.bg);
    for (let i = 0; i < COUNT; i++) {
      const k = i * 4;
      const x1 = seg[k + 2], y1 = seg[k + 3];
      // additive line from the trailing point to the head
      drawLineAdd(fb, seg[k], seg[k + 1], x1, y1, col[i]);
      // bright head pixel
      if (x1 >= 0 && x1 < w && y1 >= 0 && y1 < h) pix[y1 * w + x1] = 0xffcceeff;
    }
  }
}

// A Bresenham line that adds its colour, so overlapping stars accumulate
// brightness instead of replacing each other.
function drawLineAdd(fb, x0, y0, x1, y1, c) {
  const { w, h, pix } = fb;
  const dx = Math.abs(x1 - x0);
  const dy = -Math.abs(y1 - y0);
  const sx = x0 < x1 ? 1 : -1;
  const sy = y0 < y1 ? 1 : -1;
  const cr = c & 0xff, cg = (c >>> 8) & 0xff, cb = (c >>> 16) & 0xff;
  let err = dx + dy;
  for (;;) {
    if (x0 >= 0 && x0 < w && y0 >= 0 && y0 < h) {
      const i = y0 * w + x0;
      const p = pix[i];
      const r = Math.min((p & 0xff) + cr, 255);
      const g = Math.min(((p >>> 8) & 0xff) + cg, 255);
      const b = Math.min(((p >>> 16) & 0xff) + cb, 255);
      pix[i] = 0xff000000 | (b << 16) | (g << 8) | r;
    }
    if (x0 === x1 && y0 === y1) break;
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
