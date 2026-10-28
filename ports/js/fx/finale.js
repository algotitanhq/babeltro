// Finale: the closing card. The logo (the language's name), its reflection,
// the subtitle and the numbers that make the point, over a lit backdrop.
// The browser lab has no HUD panel, so the card uses the whole height.

import { f32, Rng } from '../lib/fmath.js';
import { fromFloat } from '../lib/canvas.js';
import {
  textWidth, textHeight, drawText, drawTextGradient, drawTextOutline, drawTextReflect,
} from '../lib/text.js';

const TAG = 'ONE THREAD - NO GPU - NO SHADER';
const LINES = ['0 GPU SHADERS', '0 EXTERNAL MODULES', '0 ASSETS ON DISK'];
const STARS = 260;

const TOP_COL = 0xfffff6e8; // pale cream
const MID_COL = 0xff7c9cff; // hot rose
const BOT_COL = 0xff582080; // deep violet

// Go's integer division truncates toward zero; so does `| 0` on the quotient.
const idiv = (a, b) => (a / b) | 0;

export class Finale {
  constructor(lang) {
    this.lang = lang;
    this.w = 0;
    this.h = 0;
    this.t = 0;
    this.offs = new Int32Array(lang.length); // per-letter wave, reused each frame
    // fixed background stars in normalised coordinates: twinkle, no motion
    const rng = new Rng(0xf1a1e);
    this.sx = new Float32Array(STARS);
    this.sy = new Float32Array(STARS);
    this.sb = new Float32Array(STARS);
    for (let i = 0; i < STARS; i++) {
      this.sx[i] = rng.float32();
      this.sy[i] = rng.float32();
      this.sb[i] = f32(0.15) + f32(rng.float32() * f32(0.85));
    }
    this.sub = `EVERY PIXEL IS ${lang}`;
    this.dx2 = null;
  }

  resize(w, h) {
    if (w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    const lang = this.lang;

    this.subScale = Math.max(idiv(w, 300), 1);
    const subH = textHeight(this.subScale);
    this.statsScale = Math.max(idiv(w, 440), 1);
    this.statGap = idiv(textHeight(this.statsScale) * 3, 2);
    this.tagScale = this.statsScale + 1;
    const tagH = textHeight(this.tagScale);

    const gap = idiv(h, 48);
    const top = idiv(h, 40);
    const bottom = f32(h * f32(0.9)) | 0;
    const fixed = subH + 3 * this.statGap + tagH + 4 * gap; // all but the wordmark
    // The wordmark's scale comes from the room it has, not from its length:
    // 7 blocks of glyph plus half of that of reflection is 10.5 blocks high,
    // and it never takes more than 45% of the width (which binds for long
    // names, JAVASCRIPT among them).
    let scale = idiv((bottom - top - fixed) * 2, 21);
    const lim = idiv(idiv(w * 9, 20), textWidth(lang, 1));
    if (scale > lim) scale = lim;
    if (scale < 3) scale = 3;
    this.logoScale = scale;
    this.logoW = textWidth(lang, scale);
    this.textH = textHeight(scale);
    this.reflH = idiv(this.textH, 2);
    this.logoX = idiv(w - this.logoW, 2);

    const blockH = this.textH + this.reflH + fixed;
    this.logoY = top + idiv(bottom - top - blockH, 2);
    this.floorY = this.logoY + this.textH;
    this.subY = this.floorY + this.reflH + gap;
    this.statsY = this.subY + subH + gap;
    this.tagY = this.statsY + 3 * this.statGap + gap;
    this.subX = idiv(w - textWidth(this.sub, this.subScale), 2);
    this.tagX = idiv(w - textWidth(TAG, this.tagScale), 2);

    this.glowX = f32(w * 0.5);
    this.glowY = f32(this.logoY + f32(this.textH * f32(0.55)));
    this.glowR = f32(w * f32(0.34));

    // per-column squared distance to the glow centre, in glow radii: the
    // glow is an ellipse about 1.6x wider than it is tall
    const dx2 = (this.dx2 = new Float32Array(w));
    for (let x = 0; x < w; x++) {
      const d = f32(f32(f32(x - this.glowX) / this.glowR) * f32(1.6));
      dx2[x] = d * d;
    }
    // the rectangle the glow can possibly reach
    const spanX = f32(this.glowR / f32(1.6)) | 0;
    const spanY = this.glowR | 0;
    this.boxX0 = (this.glowX | 0) - spanX;
    this.boxX1 = (this.glowX | 0) + spanX;
    this.boxY0 = (this.glowY | 0) - spanY;
    this.boxY1 = (this.glowY | 0) + spanY;
  }

  prepare(s) {
    this.t = s.t;
  }

  draw(fb) {
    this.drawBackdrop(fb);
    this.drawCard(fb);
  }

  drawBackdrop(fb) {
    const { w, h, pix } = fb;
    const { t, dx2, glowY, glowR } = this;
    const cy = f32(h * 0.5);

    // pass 1: a plain vertical ramp, one colour per row
    const invH = f32(1 / h);
    for (let y = 0; y < h; y++) {
      const u = f32(y * invH);
      const ny = f32(f32(y - cy) / cy);
      let vig = f32(1 - f32(f32(f32(0.32) * ny) * ny));
      if (vig < f32(0.45)) vig = f32(0.45);
      const r = f32(f32(f32(0.02) + f32(f32(f32(0.09) * u) * u)) * vig);
      const g = f32(f32(f32(0.01) + f32(f32(0.02) * u)) * vig);
      const b = f32(f32(f32(0.06) + f32(f32(0.14) * u)) * vig);
      pix.fill(fromFloat(r, g, b), y * w, (y + 1) * w);
    }

    // pass 2: the pool of light, only inside the box it can reach
    const by0 = Math.max(this.boxY0, 0), by1 = Math.min(this.boxY1, h);
    const bx0 = Math.max(this.boxX0, 0), bx1 = Math.min(this.boxX1, w);
    const pulse = f32(f32(0.88) + f32(f32(0.12) * f32(Math.sin(t * 2.2))));
    for (let y = by0; y < by1; y++) {
      const dy = f32(f32(y - glowY) / glowR);
      const dy2 = f32(dy * dy);
      if (dy2 >= 1) continue;
      const row = y * w;
      for (let x = bx0; x < bx1; x++) {
        const d2 = f32(dx2[x] + dy2);
        if (d2 >= 1) continue;
        let g = f32(1 - d2);
        g = f32(g * f32(g * pulse));
        // add the glow to the ramp, saturating each channel
        const p = pix[row + x];
        const r = Math.min((p & 0xff) + (f32(g * 120) | 0), 255);
        const gg = Math.min(((p >>> 8) & 0xff) + (f32(g * 22) | 0), 255);
        const b = Math.min(((p >>> 16) & 0xff) + (f32(g * 100) | 0), 255);
        pix[row + x] = 0xff000000 | (b << 16) | (gg << 8) | r;
      }
    }

    // stars, twinkling slowly
    const { sx, sy, sb } = this;
    const fw = f32(w), fh = f32(h);
    for (let i = 0; i < STARS; i++) {
      const x = f32(sx[i] * fw) | 0;
      const y = f32(sy[i] * fh) | 0;
      if (y < 0 || y >= h || x < 0 || x >= w) continue;
      const tw = f32(f32(0.55) + f32(f32(0.45) * f32(Math.sin(t * 1.7 + i * 0.7))));
      fb.additive(y * w + x, 0xff40306a, f32(f32(70 * sb[i]) * tw) | 0);
    }
  }

  drawCard(fb) {
    const { w, pix } = fb;
    const { t, lang, offs, logoScale: scale } = this;
    const cx = f32(w * 0.5);

    // the polished floor line the reflection lands on
    if (this.floorY >= 0 && this.floorY < fb.h) {
      const base = this.floorY * w;
      const reach = f32(w * f32(0.52));
      for (let x = 0; x < w; x++) {
        const fade = f32(1 - f32(Math.abs(f32(x - cx)) / reach));
        if (fade <= 0) continue;
        const glow = f32(f32(fade * fade) * f32(0.9));
        const p = pix[base + x];
        const r = Math.min(f32((p & 0xff) + f32(210 * glow)), 255) | 0;
        const g = Math.min(f32(((p >>> 8) & 0xff) + f32(110 * glow)), 255) | 0;
        const b = Math.min(f32(((p >>> 16) & 0xff) + f32(230 * glow)), 255) | 0;
        pix[base + x] = 0xff000000 | (b << 16) | (g << 8) | r;
      }
    }

    // @excerpt FINALE
    // the letters bounce off the floor line: offsets run from -scale/3 (up)
    // to 0 (resting on it), never below
    for (let i = 0; i < offs.length; i++) {
      offs[i] = ((Math.sin(t * 2.4 + i * 0.75) - 1) * scale) / 6; // Int32Array truncates
    }

    // reflection first, so the wordmark sits on top of its own light; then a
    // one-pixel dark edge keeps the letters off the background
    drawTextReflect(fb, this.logoX, this.floorY, lang, scale, TOP_COL, BOT_COL, offs, 125, this.reflH);
    drawTextOutline(fb, this.logoX, this.logoY, lang, scale, 0xff200a18, offs);
    drawTextGradient(fb, this.logoX, this.logoY, lang, scale, TOP_COL, MID_COL, BOT_COL, offs, true);
    // @end

    // subtitle with rules either side
    const subW = textWidth(this.sub, this.subScale);
    const lineLen = idiv(subW, 3);
    const ly = this.subY + idiv(textHeight(this.subScale), 2);
    fb.hline(this.subX - lineLen - 14, ly, lineLen, 0xff9050a0);
    fb.hline(this.subX + subW + 14, ly, lineLen, 0xff9050a0);
    drawText(fb, this.subX, this.subY, this.sub, this.subScale, 0xfff0e0ff);

    // closing numbers, then the punchline
    for (let i = 0; i < LINES.length; i++) {
      const lw = textWidth(LINES[i], this.statsScale);
      drawText(fb, idiv(w - lw, 2), this.statsY + i * this.statGap, LINES[i], this.statsScale, 0xffc0b0e0);
    }
    drawText(fb, this.tagX, this.tagY, TAG, this.tagScale, 0xffb0e0ff);
  }
}
