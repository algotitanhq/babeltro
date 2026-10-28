// Rotozoom: build a texture once, then every frame rotate and zoom the
// sampling grid over it. A few multiplies and one lookup per pixel.

import { FB, fromFloat } from '../canvas';
import { cos, sin } from '../fmath';
import { hsl2rgb, outB, outG, outR } from '../palette';
import { Effect } from './effect';

const TEX_SIZE: i32 = 512;
const TEX_MASK: i32 = TEX_SIZE - 1;

// Built on first use and kept for the life of the module (Go rebuilds it
// with every new Rotozoom): it depends on nothing, so the pixels are the same.
let texture: StaticArray<u32> | null = null;

// A tileable rainbow plasma under a dark grid, in f64 like Go.
function buildTexture(): StaticArray<u32> {
  const twoPi: f64 = 2 * Math.PI;
  const tex = new StaticArray<u32>(TEX_SIZE * TEX_SIZE);
  for (let y = 0; y < TEX_SIZE; y++) {
    const fy: f64 = <f64>(<f32>y / <f32>TEX_SIZE);
    for (let x = 0; x < TEX_SIZE; x++) {
      const fx: f64 = <f64>(<f32>x / <f32>TEX_SIZE);
      // every frequency is a whole number of cycles per tile
      let v: f64 =
        Math.sin(fx * twoPi * 3 + fy * twoPi * 2) * 0.5 +
        Math.sin(fy * twoPi * 5 - fx * twoPi * 4) * 0.3 +
        Math.sin((fx + fy) * twoPi * 7) * 0.2;
      // concentric rings, also periodic in the tile
      const dx: f64 = <f64>x - <f64>(TEX_SIZE / 2);
      const dy: f64 = <f64>y - <f64>(TEX_SIZE / 2);
      const rr: f64 = (Math.sqrt(dx * dx + dy * dy) / <f64>TEX_SIZE) * 12;
      v += Math.sin(rr * twoPi) * 0.35;

      // % on floats is fmod: the sign of the dividend, like Go's math.Mod
      let hue: f64 = (v * 0.55 + 0.5) % 1;
      if (hue < 0) hue += 1;
      hsl2rgb(hue, 0.7, 0.48 + 0.14 * v);
      let cr = outR, cg = outG, cb = outB;

      // a dark grid over the colour, so the motion reads as motion
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

export class Rotozoom extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  tex: StaticArray<u32>;
  cosA: f32 = 0;
  sinA: f32 = 0;
  zoom: f32 = 0;
  offx: f32 = 0;
  offy: f32 = 0;

  constructor() {
    super();
    let tex = texture;
    if (tex === null) texture = tex = buildTexture();
    this.tex = tex;
  }

  resize(w: i32, h: i32): void {
    this.w = w;
    this.h = h;
  }

  prepare(beat: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    const t = <f32>beat;
    const ang: f32 = t * 0.45;
    this.cosA = cos(ang);
    this.sinA = sin(ang);
    // breathing zoom: 0.7 .. 1.6
    this.zoom = 0.55 + 0.45 * sin(t * 0.7) + 0.35;
    this.offx = sin(t * 0.31) * 180 + t * 26;
    this.offy = cos(t * 0.27) * 180 + t * 19;
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w;
    const pix = fb.pix;
    const cx: f32 = <f32>w * 0.5;
    const cy: f32 = <f32>fb.h * 0.5;
    const cosA = this.cosA, sinA = this.sinA;
    const zoom: f32 = (this.zoom / <f32>w) * 6.5;
    const offx = this.offx, offy = this.offy;
    const tex = this.tex;

    // @excerpt ROTOZOOM
    // ix and iy are masked to 0..511, so the texture read cannot be out of
    // range: unchecked() removes its bounds check.
    for (let y = y0; y < y1; y++) {
      const dy: f32 = <f32>y - cy;
      const row = y * w;
      for (let x = 0; x < w; x++) {
        const dx: f32 = <f32>x - cx;
        // two multiplies, as in Go: folding zoom * 34 would round differently
        const tx: f32 = (dx * cosA - dy * sinA) * zoom * 34;
        const ty: f32 = (dx * sinA + dy * cosA) * zoom * 34;
        const ix = <i32>(tx + offx) & TEX_MASK;
        const iy = <i32>(ty + offy) & TEX_MASK;
        unchecked((pix[row + x] = tex[iy * TEX_SIZE + ix]));
      }
    }
    // @end
  }
}
