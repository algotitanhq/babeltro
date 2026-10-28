// Rotozoom: the purest demoscene move. Build a texture once, then every
// frame rotate and zoom the sampling grid over it. Cost per pixel is a few
// multiplies and one lookup.

import { f32, sin, cos } from '../lib/fmath.js';
import { hsl2rgb } from '../lib/palette.js';
import { fromFloat } from '../lib/canvas.js';

const TEX_SIZE = 512;
const TEX_MASK = TEX_SIZE - 1;

export class Rotozoom {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.tex = null;
    this.cosA = 0;
    this.sinA = 0;
    this.zoom = 0;
    this.offx = 0;
    this.offy = 0;
  }

  resize(w, h) {
    this.w = w;
    this.h = h;
    if (this.tex === null) this.tex = buildTexture();
  }

  prepare(s) {
    const t = f32(s.beat);
    const ang = f32(t * f32(0.45));
    this.cosA = cos(ang);
    this.sinA = sin(ang);
    // breathing zoom: 0.7 .. 1.6
    this.zoom = f32(f32(f32(0.55) + f32(f32(0.45) * sin(f32(t * f32(0.7))))) + f32(0.35));
    this.offx = f32(f32(sin(f32(t * f32(0.31))) * 180) + f32(t * 26));
    this.offy = f32(f32(cos(f32(t * f32(0.27))) * 180) + f32(t * 19));
  }

  draw(fb) {
    const { w, h, pix } = fb;
    const { cosA, sinA, offx, offy, tex } = this;
    const cx = f32(w * 0.5);
    const cy = f32(h * 0.5);
    const zoom = f32(f32(this.zoom / w) * f32(6.5));

    // @excerpt ROTOZOOM
    for (let y = 0; y < h; y++) {
      const dy = f32(y - cy);
      // the row's share of the rotation does not depend on x
      const dySin = f32(dy * sinA);
      const dyCos = f32(dy * cosA);
      const row = y * w;
      for (let x = 0; x < w; x++) {
        const dx = f32(x - cx);
        // rotate, then scale: (dx, dy) in screen space to (tx, ty) in texels
        const tx = f32(f32(f32(f32(dx * cosA) - dySin) * zoom) * 34);
        const ty = f32(f32(f32(f32(dx * sinA) + dyCos) * zoom) * 34);
        // `| 0` truncates toward zero like Go's int(); the mask wraps the tile
        const ix = (f32(tx + offx) | 0) & TEX_MASK;
        const iy = (f32(ty + offy) | 0) & TEX_MASK;
        pix[row + x] = tex[iy * TEX_SIZE + ix];
      }
    }
    // @end
  }
}

// A tileable rainbow plasma with a dark grid, built once. It costs a few
// hundred thousand sine calls; doing that per frame would cost the whole
// budget, which is the point of the scene. All of it is float64.
function buildTexture() {
  const twoPi = 2 * Math.PI;
  const tex = new Uint32Array(TEX_SIZE * TEX_SIZE);
  for (let y = 0; y < TEX_SIZE; y++) {
    const fy = y / TEX_SIZE; // exact in float32 and float64 alike
    for (let x = 0; x < TEX_SIZE; x++) {
      const fx = x / TEX_SIZE;
      // the pattern has to wrap every 512 pixels, so every frequency is a
      // whole number of cycles per tile
      let v =
        Math.sin(fx * twoPi * 3 + fy * twoPi * 2) * 0.5 +
        Math.sin(fy * twoPi * 5 - fx * twoPi * 4) * 0.3 +
        Math.sin((fx + fy) * twoPi * 7) * 0.2;
      // concentric rings, also periodic in the tile
      const dx = x - TEX_SIZE / 2;
      const dy = y - TEX_SIZE / 2;
      const rr = (Math.sqrt(dx * dx + dy * dy) / TEX_SIZE) * 12;
      v += Math.sin(rr * twoPi) * 0.35;

      let hue = (v * 0.55 + 0.5) % 1; // JS % is Go's math.Mod: sign of the dividend
      if (hue < 0) hue += 1;
      let [cr, cg, cb] = hsl2rgb(hue, 0.7, 0.48 + 0.14 * v);

      // a dark grid over the colour: without a straight edge the rotation
      // and the zoom read as random shimmer instead of motion
      if (x % (TEX_SIZE / 8) < 3 || y % (TEX_SIZE / 8) < 3) {
        cr *= 0.28;
        cg *= 0.28;
        cb *= 0.28;
      }
      tex[y * TEX_SIZE + x] = fromFloat(cr, cg, cb);
    }
  }
  return tex;
}
