// Finale: the closing card. The logo, its reflection, the subtitle and the
// numbers that make the point.

import {
  FB, additive, drawText, drawTextGradient, drawTextOutline, drawTextReflect,
  hline, fromFloat, textHeight, textWidth,
} from '../canvas';
import { Rng } from '../fmath';
import { Effect } from './effect';

// The only words that differ between ports.
export const LANG = 'ASSEMBLYSCRIPT';
// the browser lab has no HUD and one thread, and says so in every port
const TAG = 'ONE THREAD - NO GPU - NO SHADER';
const NSTARS: i32 = 260;

export class Finale extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  t: f64 = 0;

  starX: StaticArray<f32> = new StaticArray<f32>(NSTARS);
  starY: StaticArray<f32> = new StaticArray<f32>(NSTARS);
  starB: StaticArray<f32> = new StaticArray<f32>(NSTARS);
  seeded: bool = false;

  logoScale: i32 = 0;
  logoX: i32 = 0;
  logoY: i32 = 0;
  logoW: i32 = 0;
  textH: i32 = 0;
  reflH: i32 = 0; // rows the reflection fades over, below the floor line
  floorY: i32 = 0;

  sub: string = 'EVERY PIXEL IS ' + LANG;
  subScale: i32 = 0;
  subX: i32 = 0;
  subY: i32 = 0;

  statsScale: i32 = 0;
  statsY: i32 = 0;
  statGap: i32 = 0;

  tagScale: i32 = 0;
  tagX: i32 = 0;
  tagY: i32 = 0;

  lines: StaticArray<string> = ['0 GPU SHADERS', '0 EXTERNAL MODULES', '0 ASSETS ON DISK'];
  // per-letter wave offsets, reused so a frame allocates nothing
  offs: StaticArray<i32> = new StaticArray<i32>(LANG.length);

  glowX: f32 = 0;
  glowY: f32 = 0;
  glowR: f32 = 0;
  // per-column squared distance to the glow centre, and the box it reaches
  dx2: StaticArray<f32> = new StaticArray<f32>(0);
  boxX0: i32 = 0;
  boxX1: i32 = 0;
  boxY0: i32 = 0;
  boxY1: i32 = 0;

  resize(w: i32, h: i32): void {
    if (w == this.w && h == this.h) return;
    this.w = w;
    this.h = h;

    if (!this.seeded) {
      const rng = new Rng(0xf1a1e);
      for (let i = 0; i < NSTARS; i++) {
        this.starX[i] = rng.float32();
        this.starY[i] = rng.float32();
        this.starB[i] = 0.15 + rng.float32() * 0.85;
      }
      this.seeded = true;
    }

    // i32 division truncates toward zero, like Go's int division
    this.subScale = max(w / 300, 1);
    const subH = textHeight(this.subScale);
    this.statsScale = max(w / 440, 1);
    this.statGap = (textHeight(this.statsScale) * 3) / 2;
    this.tagScale = this.statsScale + 1;
    const tagH = textHeight(this.tagScale);

    // no HUD here: the card uses the whole height
    const gap = h / 48;
    const top = h / 40;
    const bottom = <i32>(<f32>h * 0.9);
    const fixed = subH + 3 * this.statGap + tagH + 4 * gap; // all but the wordmark
    // the wordmark needs 10.5 blocks of height and at most 45% of the width
    let logoScale = ((bottom - top - fixed) * 2) / 21;
    const lim = (w * 9) / 20 / textWidth(LANG, 1);
    if (logoScale > lim) logoScale = lim;
    if (logoScale < 3) logoScale = 3;
    this.logoScale = logoScale;
    this.logoW = textWidth(LANG, logoScale);
    this.textH = textHeight(logoScale);
    this.reflH = this.textH / 2;
    this.logoX = (w - this.logoW) / 2;

    const blockH = this.textH + this.reflH + fixed;
    const y0 = top + (bottom - top - blockH) / 2;
    this.logoY = y0;
    this.floorY = this.logoY + this.textH;
    this.subY = this.floorY + this.reflH + gap;
    this.statsY = this.subY + subH + gap;
    this.tagY = this.statsY + 3 * this.statGap + gap;
    this.subX = (w - textWidth(this.sub, this.subScale)) / 2;
    this.tagX = (w - textWidth(TAG, this.tagScale)) / 2;

    this.glowX = <f32>w * 0.5;
    this.glowY = <f32>this.logoY + <f32>this.textH * 0.55;
    this.glowR = <f32>w * 0.34;

    // the glow is an ellipse about 1.6x wider than it is tall
    if (this.dx2.length != w) this.dx2 = new StaticArray<f32>(w);
    for (let x = 0; x < w; x++) {
      const d: f32 = ((<f32>x - this.glowX) / this.glowR) * 1.6;
      this.dx2[x] = d * d;
    }
    const spanX = <i32>(this.glowR / 1.6);
    const spanY = <i32>this.glowR;
    this.boxX0 = <i32>this.glowX - spanX;
    this.boxX1 = <i32>this.glowX + spanX;
    this.boxY0 = <i32>this.glowY - spanY;
    this.boxY1 = <i32>this.glowY + spanY;
  }

  prepare(t: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    this.t = t;
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w, h = fb.h;
    const pix = fb.pix;
    const cx: f32 = <f32>w * 0.5;
    const cy: f32 = <f32>h * 0.5;

    // --- background, pass 1: a vertical ramp, one colour per row ---
    const invH: f32 = 1 / <f32>h;
    for (let y = y0; y < y1; y++) {
      const u: f32 = <f32>y * invH;
      const ny: f32 = (<f32>y - cy) / cy;
      let vig: f32 = 1 - 0.32 * ny * ny;
      if (vig < 0.45) vig = 0.45;
      const r: f32 = (0.02 + 0.09 * u * u) * vig;
      const g: f32 = (0.01 + 0.02 * u) * vig;
      const b: f32 = (0.06 + 0.14 * u) * vig;
      const c = fromFloat(<f64>r, <f64>g, <f64>b);
      const row = y * w;
      for (let x = 0; x < w; x++) unchecked((pix[row + x] = c));
    }

    // --- background, pass 2: the pool of light, only where it reaches ---
    const by0 = max(this.boxY0, y0), by1 = min(this.boxY1, y1);
    const bx0 = max(this.boxX0, 0), bx1 = min(this.boxX1, w);
    const pulse: f32 = 0.88 + 0.12 * <f32>Math.sin(this.t * 2.2);
    const dx2 = this.dx2;
    for (let y = by0; y < by1; y++) {
      const dy: f32 = (<f32>y - this.glowY) / this.glowR;
      const dy2: f32 = dy * dy;
      if (dy2 >= 1) continue;
      const row = y * w;
      for (let x = bx0; x < bx1; x++) {
        const d2: f32 = unchecked(dx2[x]) + dy2;
        if (d2 >= 1) continue;
        let g: f32 = 1 - d2;
        g *= g * pulse;
        const p = unchecked(pix[row + x]);
        const r = min(<i32>(p & 0xff) + <i32>(g * 120), 255);
        const gg = min(<i32>((p >> 8) & 0xff) + <i32>(g * 22), 255);
        const b = min(<i32>((p >> 16) & 0xff) + <i32>(g * 100), 255);
        unchecked((pix[row + x] = 0xff000000 | (<u32>b << 16) | (<u32>gg << 8) | <u32>r));
      }
    }

    // stars, twinkling slowly
    for (let i = 0; i < NSTARS; i++) {
      const sx = <i32>(this.starX[i] * <f32>w);
      const sy = <i32>(this.starY[i] * <f32>h);
      if (sy < y0 || sy >= y1 || sx < 0 || sx >= w) continue;
      const tw: f32 = 0.55 + 0.45 * <f32>Math.sin(this.t * 1.7 + <f64>i * 0.7);
      const k: f32 = 70 * this.starB[i] * tw;
      additive(fb, sy * w + sx, 0xff40306a, <u8>k);
    }

    // --- the polished floor line the reflection lands on ---
    if (this.floorY >= y0 && this.floorY < y1) {
      const base = this.floorY * w;
      for (let x = 0; x < w; x++) {
        const d: f32 = <f32>x - cx;
        const fade: f32 = 1 - Mathf.abs(d) / (<f32>w * 0.52);
        if (fade <= 0) continue;
        const glow: f32 = fade * fade * 0.9;
        const p = pix[base + x];
        const r = min<f32>(<f32>(p & 0xff) + 210 * glow, 255);
        const g = min<f32>(<f32>((p >> 8) & 0xff) + 110 * glow, 255);
        const b = min<f32>(<f32>((p >> 16) & 0xff) + 230 * glow, 255);
        pix[base + x] = 0xff000000 | (<u32>b << 16) | (<u32>g << 8) | <u32>r;
      }
    }

    // @excerpt FINALE
    // --- logo ---
    const scale = this.logoScale;
    const offs = this.offs;
    // the letters bounce off the floor line: offsets run from -scale/3 (up)
    // to 0 (resting on it), never below
    for (let i = 0; i < offs.length; i++) {
      const o: f64 = ((Math.sin(this.t * 2.4 + <f64>i * 0.75) - 1) * <f64>scale) / 6;
      offs[i] = <i32>o;
    }

    const topCol: u32 = 0xfffff6e8; // pale cream
    const midCol: u32 = 0xff7c9cff; // hot rose
    const botCol: u32 = 0xff582080; // deep violet

    // reflection first, so the wordmark sits on top of its own light
    drawTextReflect(fb, this.logoX, this.floorY, LANG, scale, topCol, botCol, offs, 125, this.reflH);
    // a one-pixel dark edge keeps the letters off the background
    drawTextOutline(fb, this.logoX, this.logoY, LANG, scale, 0xff200a18, offs);
    drawTextGradient(fb, this.logoX, this.logoY, LANG, scale, topCol, midCol, botCol, offs, true);
    // @end

    // --- subtitle with rules either side ---
    const subW = textWidth(this.sub, this.subScale);
    const lineLen = subW / 3;
    const ly = this.subY + textHeight(this.subScale) / 2;
    hline(fb, this.subX - lineLen - 14, ly, lineLen, 0xff9050a0);
    hline(fb, this.subX + subW + 14, ly, lineLen, 0xff9050a0);
    drawText(fb, this.subX, this.subY, this.sub, this.subScale, 0xfff0e0ff);

    // --- closing numbers ---
    for (let i = 0; i < this.lines.length; i++) {
      const l = this.lines[i];
      const y = this.statsY + i * this.statGap;
      const lw = textWidth(l, this.statsScale);
      drawText(fb, (w - lw) / 2, y, l, this.statsScale, 0xffc0b0e0);
    }

    // the punchline
    drawText(fb, this.tagX, this.tagY, TAG, this.tagScale, 0xffb0e0ff);
  }
}
