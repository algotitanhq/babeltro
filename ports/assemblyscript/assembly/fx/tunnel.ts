// Tunnel: every pixel is mapped to polar coordinates once, at resize time.
// After that the per-pixel work is two table reads and a palette read.

import { FB } from '../canvas';
import { atan2Tab, atan2Turns, distInvTab, sin01 } from '../fmath';
import { ICE } from '../palette';
import { Effect } from './effect';

export class Tunnel extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  depth: StaticArray<f32> = new StaticArray<f32>(0); // 1/r: large at the centre
  angle: StaticArray<f32> = new StaticArray<f32>(0); // atan2 in turns, [0,1)
  t: f32 = 0;
  // the ladder: 1 computes the distance and the angle for every pixel, every
  // frame; 2 (the default) reads them from tables built at resize
  step: i32 = 0;

  setStep(n: i32): void {
    this.step = n;
  }

  resize(w: i32, h: i32): void {
    if (w == this.w && h == this.h) return;
    this.w = w;
    this.h = h;
    // scale with the diagonal so the rings look the same at any resolution
    const scale: f32 = <f32>(w + h) * 2.2;
    this.depth = distInvTab(w, h, scale, <f32>(w + h) * 0.02);
    this.angle = atan2Tab(w, h);
  }

  prepare(t: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    this.t = <f32>t;
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    if (this.step == 1) {
      this.drawDirect(fb, y0, y1);
      return;
    }
    const w = fb.w;
    const pix = fb.pix;
    const depth = this.depth, angle = this.angle;
    const pal = ICE;
    const adv: f32 = this.t * 3.0;
    const spin: f32 = this.t * 0.25;

    // @excerpt TUNNEL
    // The tables have the framebuffer's length and i < w*h, so unchecked()
    // only removes checks that could not fail. The palette index is
    // clamped to 0..255 first.
    for (let y = y0; y < y1; y++) {
      const row = y * w;
      for (let x = 0; x < w; x++) {
        const i = row + x;
        const u: f32 = unchecked(depth[i]) + adv; // scroll towards the viewer
        const v: f32 = unchecked(angle[i]);

        // rings along the depth axis
        const ring = sin01(u * 0.16);
        // spokes that twist as they recede
        const twist: f32 = v * 12 + u * 0.09 + spin;
        const spoke = sin01(twist);

        let val: f32 = ring * 0.55 + spoke * 0.45;
        // brick checker gives the walls their structure
        if (((<i32>(u * 0.32) + <i32>twist) & 1) == 1) val = -val * 0.7;

        const fog: f32 = 1 / (1 + u * 0.02);
        const lum: f32 = (val * 0.5 + 0.5) * fog;
        // a cold rim on the brightest ridges
        const idx = min(max(<i32>(lum * 300), 0), 255);
        unchecked((pix[i] = pal[idx]));
      }
    }
    // @end
  }

  // The tunnel without its tables: a square root, a division and an atan2
  // per pixel, every frame, for values that never change.
  drawDirect(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w, h = fb.h;
    const pix = fb.pix;
    const pal = ICE;
    const adv: f32 = this.t * 3.0;
    const spin: f32 = this.t * 0.25;
    const cx: f32 = <f32>w / 2, cy: f32 = <f32>h / 2;
    const scale: f32 = <f32>(w + h) * 2.2;
    const soft: f32 = <f32>(w + h) * 0.02;

    // @excerpt TUNNEL/1
    for (let y = y0; y < y1; y++) {
      const dy: f32 = <f32>y - cy;
      for (let x = 0; x < w; x++) {
        const dx: f32 = <f32>x - cx;
        const depth: f32 = scale / (Mathf.sqrt(dx * dx + dy * dy) + soft);
        const u: f32 = depth + adv;
        const v = atan2Turns(dy, dx);

        const ring = sin01(u * 0.16);
        const twist: f32 = v * 12 + u * 0.09 + spin;
        const spoke = sin01(twist);
        let val: f32 = ring * 0.55 + spoke * 0.45;
        if (((<i32>(u * 0.32) + <i32>twist) & 1) == 1) val = -val * 0.7;
        const fog: f32 = 1 / (1 + u * 0.02);
        const lum: f32 = (val * 0.5 + 0.5) * fog;
        const idx = min(max(<i32>(lum * 300), 0), 255);
        unchecked((pix[y * w + x] = pal[idx]));
      }
    }
    // @end
  }
}
