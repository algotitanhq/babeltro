// Tunnel: every pixel is mapped to polar coordinates once, at resize time.
// After that the per-pixel work is a couple of table lookups and a palette
// read: the geometry is free.

import { f32, sin01, sqrt32, atan2Turns, SIN_TAB, TAB_SIZE, TAB_MASK, atan2Tab, distInvTab } from '../lib/fmath.js';
import { ICE } from '../lib/palette.js';

// float32 constants, rounded once here instead of in the loop
const K_RING = f32(0.16);
const K_TWIST = f32(0.09);
const K_CHECK = f32(0.32);
const K_FOG = f32(0.02);
const W_RING = f32(0.55);
const W_SPOKE = f32(0.45);
const DARK = f32(0.7);

export class Tunnel {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.depth = null; // falls off as 1/r: large at the centre, small at the edge
    this.angle = null; // atan2 as a fraction of a turn, [0,1)
    this.t = 0;
    // the ladder: 1 computes the distance and the angle for every pixel,
    // every frame; 2 (the default) reads them from tables built at resize
    this.step = 0;
  }

  setStep(n) {
    this.step = n;
  }

  resize(w, h) {
    if (w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    // scale with the diagonal so the rings look the same at any resolution
    const scale = f32(f32(w + h) * f32(2.2));
    this.depth = distInvTab(w, h, scale, f32(f32(w + h) * f32(0.02)));
    this.angle = atan2Tab(w, h);
  }

  prepare(s) {
    this.t = f32(s.beat);
  }

  // The table reads are written out instead of calling fmath's sin01. V8
  // does inline the call, yet measured on Node 23 the loop ran 2.5x slower
  // with it, so the hot loops of this port index SIN_TAB directly.
  draw(fb) {
    if (this.step === 1) return this.drawDirect(fb);
    const { pix } = fb;
    const { depth, angle } = this;
    const pal = ICE;
    const adv = f32(this.t * 3);
    const spin = f32(this.t * 0.25);
    const n = pix.length;

    // @excerpt TUNNEL
    for (let i = 0; i < n; i++) {
      const u = f32(depth[i] + adv); // scroll towards the viewer
      const v = angle[i];

      // rings along the depth axis, spokes that twist as they recede; both
      // are sin01(turns): one table read each
      const ring = SIN_TAB[((f32(u * K_RING) * TAB_SIZE) | 0) & TAB_MASK];
      const twist = f32(f32(f32(v * 12) + f32(u * K_TWIST)) + spin);
      const spoke = SIN_TAB[((twist * TAB_SIZE) | 0) & TAB_MASK];

      let val = f32(f32(ring * W_RING) + f32(spoke * W_SPOKE));
      // brick checker gives the walls their structure
      if ((((f32(u * K_CHECK) | 0) + (twist | 0)) & 1) === 1) {
        val = f32(-val * DARK);
      }

      const fog = f32(1 / f32(1 + f32(u * K_FOG)));
      const lum = f32(f32(f32(val * 0.5) + 0.5) * fog);
      let idx = f32(lum * 300) | 0;
      if (idx > 255) idx = 255;
      if (idx < 0) idx = 0;
      pix[i] = pal[idx];
    }
    // @end
  }

  // drawDirect is the tunnel without its tables: a square root, a division
  // and an atan2 per pixel, every frame, for values that never change. The
  // formulas are the ones the tables are built from, so the pixels are the
  // same; only the time differs.
  drawDirect(fb) {
    const { w, h, pix } = fb;
    const pal = ICE;
    const adv = f32(this.t * 3);
    const spin = f32(this.t * 0.25);
    const cx = f32(w / 2);
    const cy = f32(h / 2);
    const scale = f32(f32(w + h) * f32(2.2));
    const soft = f32(f32(w + h) * f32(0.02));

    // @excerpt TUNNEL/1
    for (let y = 0; y < h; y++) {
      const dy = f32(y - cy);
      for (let x = 0; x < w; x++) {
        const dx = f32(x - cx);
        const depth = f32(scale / f32(sqrt32(f32(f32(dx * dx) + f32(dy * dy))) + soft));
        const u = f32(depth + adv);
        const v = atan2Turns(dy, dx);

        const ring = sin01(f32(u * K_RING));
        const twist = f32(f32(f32(v * 12) + f32(u * K_TWIST)) + spin);
        const spoke = sin01(twist);
        let val = f32(f32(ring * W_RING) + f32(spoke * W_SPOKE));
        if ((((f32(u * K_CHECK) | 0) + (twist | 0)) & 1) === 1) {
          val = f32(-val * DARK);
        }
        const fog = f32(1 / f32(1 + f32(u * K_FOG)));
        const lum = f32(f32(f32(val * 0.5) + 0.5) * fog);
        let idx = f32(lum * 300) | 0;
        if (idx > 255) idx = 255;
        if (idx < 0) idx = 0;
        pix[y * w + x] = pal[idx];
      }
    }
    // @end
  }
}
