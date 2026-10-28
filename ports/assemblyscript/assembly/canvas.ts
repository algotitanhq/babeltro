// The framebuffer, colour packing and the 5×7 font.
//
// Pixels are 0xAABBGGRR u32s; in little-endian memory that is R, G, B, A,
// which the host copies straight into an ImageData.

import { f2b } from './palette';

export class FB {
  pix: StaticArray<u32>;
  constructor(public w: i32, public h: i32) {
    this.pix = new StaticArray<u32>(w * h);
  }
}

/** Normalised floats to a colour, clamping to [0,1], in f64 like Go. */
export function fromFloat(r: f64, g: f64, b: f64): u32 {
  return 0xff000000 | (<u32>f2b(b) << 16) | (<u32>f2b(g) << 8) | <u32>f2b(r);
}

/** Adds a colour scaled by intensity/255, saturating. */
export function additive(fb: FB, i: i32, c: u32, intensity: u8): void {
  if (intensity == 0) return;
  const k = <u32>intensity;
  const p = fb.pix[i];
  let r = (p & 0xff) + ((c & 0xff) * k) / 255;
  let g = ((p >> 8) & 0xff) + (((c >> 8) & 0xff) * k) / 255;
  let b = ((p >> 16) & 0xff) + (((c >> 16) & 0xff) * k) / 255;
  if (r > 255) r = 255;
  if (g > 255) g = 255;
  if (b > 255) b = 255;
  fb.pix[i] = 0xff000000 | (b << 16) | (g << 8) | r;
}

/** A 1px horizontal line. */
export function hline(fb: FB, x: i32, y: i32, w: i32, c: u32): void {
  if (y < 0 || y >= fb.h) return;
  const row = y * fb.w;
  for (let xx = x; xx < x + w; xx++) {
    if (xx >= 0 && xx < fb.w) fb.pix[row + xx] = c;
  }
}

// A 5×7 bitmap font for the codes 32..126, seven rows per glyph, MSB first.
// Go parses the same dots from text at init; here they are a literal
// StaticArray<u8>, which the compiler lays out in a data segment: no code
// runs to build it.
const FONT: StaticArray<u8> = [
  0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, // space
  0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100, // !
  0b01010, 0b01010, 0b01010, 0b00000, 0b00000, 0b00000, 0b00000, // "
  0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010, // #
  0b00100, 0b01111, 0b10100, 0b01110, 0b00101, 0b11110, 0b00100, // $
  0b11001, 0b11010, 0b00010, 0b00100, 0b01000, 0b01011, 0b10011, // %
  0b01100, 0b10010, 0b10100, 0b01000, 0b10101, 0b10010, 0b01101, // &
  0b00100, 0b00100, 0b01000, 0b00000, 0b00000, 0b00000, 0b00000, // '
  0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010, // (
  0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000, // )
  0b00000, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0b00000, // *
  0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000, // +
  0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100, 0b11000, // ,
  0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000, // -
  0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100, // .
  0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000, // /
  0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110, // 0
  0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110, // 1
  0b01110, 0b10001, 0b00001, 0b00110, 0b01000, 0b10000, 0b11111, // 2
  0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110, // 3
  0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010, // 4
  0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110, // 5
  0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110, // 6
  0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000, // 7
  0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110, // 8
  0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100, // 9
  0b00000, 0b01100, 0b01100, 0b00000, 0b01100, 0b01100, 0b00000, // :
  0b00000, 0b01100, 0b01100, 0b00000, 0b01100, 0b00100, 0b01000, // ;
  0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010, // <
  0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000, // =
  0b01000, 0b00100, 0b00010, 0b00001, 0b00010, 0b00100, 0b01000, // >
  0b01110, 0b10001, 0b00001, 0b00110, 0b00100, 0b00000, 0b00100, // ?
  0b01110, 0b10001, 0b10111, 0b10101, 0b10111, 0b10000, 0b01110, // @
  0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001, // A
  0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110, // B
  0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110, // C
  0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110, // D
  0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111, // E
  0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000, // F
  0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111, // G
  0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001, // H
  0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111, // I
  0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100, // J
  0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001, // K
  0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111, // L
  0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001, // M
  0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001, // N
  0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110, // O
  0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000, // P
  0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101, // Q
  0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001, // R
  0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110, // S
  0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, // T
  0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110, // U
  0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100, // V
  0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010, // W
  0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001, // X
  0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100, // Y
  0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111, // Z
  0b01110, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110, // [
  0b10000, 0b01000, 0b01000, 0b00100, 0b00010, 0b00010, 0b00001, // \
  0b01110, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110, // ]
  0b00100, 0b01010, 0b10001, 0b00000, 0b00000, 0b00000, 0b00000, // ^
  0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111, // _
  0, 0, 0, 0, 0, 0, 0, // `: no glyph
  0, 0, 0, 0, 0, 0, 0, // a: no glyph
  0, 0, 0, 0, 0, 0, 0, // b: no glyph
  0, 0, 0, 0, 0, 0, 0, // c: no glyph
  0, 0, 0, 0, 0, 0, 0, // d: no glyph
  0, 0, 0, 0, 0, 0, 0, // e: no glyph
  0, 0, 0, 0, 0, 0, 0, // f: no glyph
  0, 0, 0, 0, 0, 0, 0, // g: no glyph
  0, 0, 0, 0, 0, 0, 0, // h: no glyph
  0, 0, 0, 0, 0, 0, 0, // i: no glyph
  0, 0, 0, 0, 0, 0, 0, // j: no glyph
  0, 0, 0, 0, 0, 0, 0, // k: no glyph
  0, 0, 0, 0, 0, 0, 0, // l: no glyph
  0, 0, 0, 0, 0, 0, 0, // m: no glyph
  0, 0, 0, 0, 0, 0, 0, // n: no glyph
  0, 0, 0, 0, 0, 0, 0, // o: no glyph
  0, 0, 0, 0, 0, 0, 0, // p: no glyph
  0, 0, 0, 0, 0, 0, 0, // q: no glyph
  0, 0, 0, 0, 0, 0, 0, // r: no glyph
  0, 0, 0, 0, 0, 0, 0, // s: no glyph
  0, 0, 0, 0, 0, 0, 0, // t: no glyph
  0, 0, 0, 0, 0, 0, 0, // u: no glyph
  0, 0, 0, 0, 0, 0, 0, // v: no glyph
  0, 0, 0, 0, 0, 0, 0, // w: no glyph
  0, 0, 0, 0, 0, 0, 0, // x: no glyph
  0, 0, 0, 0, 0, 0, 0, // y: no glyph
  0, 0, 0, 0, 0, 0, 0, // z: no glyph
  0b00110, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00110, // {
  0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, // |
  0b01100, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01100, // }
  0b00000, 0b00000, 0b01000, 0b10101, 0b00010, 0b00000, 0b00000, // ~
];
const FONT_WIDTH: i32 = 5;
const FONT_GAP: i32 = 1;

/** The font index of a character code, folding lower case; -1 if none. */
function glyphIndex(ch: i32): i32 {
  if (ch >= 0x61 && ch <= 0x7a) ch -= 0x20;
  const idx = ch - 32;
  return idx < 0 || idx >= 95 ? -1 : idx;
}

export function textWidth(s: string, scale: i32): i32 {
  if (s.length == 0) return 0;
  return (s.length * (FONT_WIDTH + FONT_GAP) - FONT_GAP) * scale;
}

export function textHeight(scale: i32): i32 {
  return 7 * scale;
}

/** Draws one glyph with its top-left corner at (x, y), solid. */
function drawGlyph(fb: FB, x: i32, y: i32, idx: i32, scale: i32, c: u32): void {
  for (let row = 0; row < 7; row++) {
    const bits = <i32>FONT[idx * 7 + row];
    if (bits == 0) continue;
    for (let col = 0; col < 5; col++) {
      if ((bits & (1 << (4 - col))) == 0) continue;
      const px = x + col * scale;
      const py = y + row * scale;
      for (let sy = 0; sy < scale; sy++) {
        const yy = py + sy;
        if (yy < 0 || yy >= fb.h) continue;
        const base = yy * fb.w;
        for (let sx = 0; sx < scale; sx++) {
          const xx = px + sx;
          if (xx < 0 || xx >= fb.w) continue;
          fb.pix[base + xx] = c;
        }
      }
    }
  }
}

/** Draws s with its top-left corner at (x, y). */
export function drawText(fb: FB, x: i32, y: i32, s: string, scale: i32, c: u32): void {
  if (scale < 1) scale = 1;
  let cx = x;
  for (let i = 0; i < s.length; i++) {
    const idx = glyphIndex(s.charCodeAt(i));
    if (idx < 0) {
      cx += FONT_WIDTH * scale;
      continue;
    }
    drawGlyph(fb, cx, y, idx, scale, c);
    cx += (FONT_WIDTH + FONT_GAP) * scale;
  }
}

// clipBlock leaves the visible part of a scale×scale block in these four
// globals and reports whether anything is left (no tuples, as above).
let clipY0: i32 = 0;
let clipY1: i32 = 0;
let clipX0: i32 = 0;
let clipX1: i32 = 0;

function clipBlock(fb: FB, px: i32, py: i32, scale: i32): bool {
  clipY0 = max(py, 0);
  clipY1 = min(py + scale, fb.h);
  clipX0 = max(px, 0);
  clipX1 = min(px + scale, fb.w);
  return clipY0 < clipY1 && clipX0 < clipX1;
}

/**
 * Draws s with a three-stop vertical colour ramp (top, mid, bottom), each
 * glyph lifted by its entry in offs. With scan set, every fourth row is
 * darkened: the CRT look.
 */
export function drawTextGradient(
  fb: FB, x: i32, y: i32, s: string, scale: i32,
  top: u32, mid: u32, bottom: u32, offs: StaticArray<i32>, scan: bool,
): void {
  if (scale < 1) scale = 1;
  const tr = <f32>(top & 0xff), tg = <f32>((top >> 8) & 0xff), tb = <f32>((top >> 16) & 0xff);
  const mr = <f32>(mid & 0xff), mg = <f32>((mid >> 8) & 0xff), mb = <f32>((mid >> 16) & 0xff);
  const br = <f32>(bottom & 0xff), bg = <f32>((bottom >> 8) & 0xff), bb = <f32>((bottom >> 16) & 0xff);
  const totalH = 7 * scale;
  const w = fb.w;
  const pix = fb.pix;

  let cx = x;
  for (let i = 0; i < s.length; i++) {
    const dy = i < offs.length ? offs[i] : 0;
    const idx = glyphIndex(s.charCodeAt(i));
    if (idx >= 0) {
      for (let row = 0; row < 7; row++) {
        const bits = <i32>FONT[idx * 7 + row];
        if (bits == 0) continue;
        const py = y + row * scale + dy;
        for (let col = 0; col < 5; col++) {
          if ((bits & (1 << (4 - col))) == 0) continue;
          if (!clipBlock(fb, cx + col * scale, py, scale)) continue;
          for (let yy = clipY0; yy < clipY1; yy++) {
            let f: f32 = <f32>(yy - y) / <f32>totalH;
            if (f < 0) f = 0;
            else if (f > 1) f = 1;
            let r: u32, gg: u32, bl: u32;
            if (f < 0.5) {
              const u: f32 = f * 2;
              r = <u32>(tr + (mr - tr) * u);
              gg = <u32>(tg + (mg - tg) * u);
              bl = <u32>(tb + (mb - tb) * u);
            } else {
              const u: f32 = (f - 0.5) * 2;
              r = <u32>(mr + (br - mr) * u);
              gg = <u32>(mg + (bg - mg) * u);
              bl = <u32>(mb + (bb - mb) * u);
            }
            if (scan && (yy & 3) == 0) {
              r = (r * 3) / 4;
              gg = (gg * 3) / 4;
              bl = (bl * 3) / 4;
            }
            const c = 0xff000000 | (bl << 16) | (gg << 8) | r;
            const base = yy * w;
            // the block is clipped, so every index is inside the frame
            for (let xx = clipX0; xx < clipX1; xx++) unchecked((pix[base + xx] = c));
          }
        }
      }
    }
    cx += (FONT_WIDTH + FONT_GAP) * scale;
  }
}

/**
 * Draws s offset by one pixel in the four cardinal directions, a hard edge
 * that follows the same per-glyph offsets as drawTextGradient.
 */
export function drawTextOutline(fb: FB, x: i32, y: i32, s: string, scale: i32, c: u32, offs: StaticArray<i32>): void {
  for (let i = 0; i < s.length; i++) {
    const dy = i < offs.length ? offs[i] : 0;
    const idx = glyphIndex(s.charCodeAt(i));
    if (idx < 0) continue;
    const gx = x + i * (FONT_WIDTH + FONT_GAP) * scale;
    drawGlyph(fb, gx - 1, y + dy, idx, scale, c);
    drawGlyph(fb, gx + 1, y + dy, idx, scale, c);
    drawGlyph(fb, gx, y + dy - 1, idx, scale, c);
    drawGlyph(fb, gx, y + dy + 1, idx, scale, c);
  }
}

/**
 * Draws a vertically mirrored copy of s from the line y down, fading out
 * over depth rows and added to the framebuffer: light on a polished floor.
 */
export function drawTextReflect(
  fb: FB, x: i32, y: i32, s: string, scale: i32,
  top: u32, bottom: u32, offs: StaticArray<i32>, strength: u8, depth: i32,
): void {
  if (scale < 1) scale = 1;
  if (depth < 1) depth = 1;
  const tr = <f32>(top & 0xff), tg = <f32>((top >> 8) & 0xff), tb = <f32>((top >> 16) & 0xff);
  const br = <f32>(bottom & 0xff), bg = <f32>((bottom >> 8) & 0xff), bb = <f32>((bottom >> 16) & 0xff);
  const w = fb.w;

  let cx = x;
  for (let i = 0; i < s.length; i++) {
    const dy = i < offs.length ? offs[i] : 0;
    const idx = glyphIndex(s.charCodeAt(i));
    if (idx >= 0) {
      for (let row = 0; row < 7; row++) {
        const bits = <i32>FONT[idx * 7 + row];
        if (bits == 0) continue;
        // mirrored: glyph row 0 sits at the far end, and a letter lifted by
        // dy has its reflection pushed down by as much
        const py = y + (6 - row) * scale - dy;
        for (let col = 0; col < 5; col++) {
          if ((bits & (1 << (4 - col))) == 0) continue;
          if (!clipBlock(fb, cx + col * scale, py, scale)) continue;
          for (let yy = clipY0; yy < clipY1; yy++) {
            const d: f32 = <f32>(yy - y) / <f32>depth;
            if (d > 1) continue;
            let a: f32 = 1 - d;
            a *= a;
            const inten = <u8>(<f32>strength * a);
            if (inten == 0) continue;
            const r = <u32>(tr + (br - tr) * d);
            const gg = <u32>(tg + (bg - tg) * d);
            const bl = <u32>(tb + (bb - tb) * d);
            const c = 0xff000000 | (bl << 16) | (gg << 8) | r;
            const base = yy * w;
            for (let xx = clipX0; xx < clipX1; xx++) additive(fb, base + xx, c, inten);
          }
        }
      }
    }
    cx += (FONT_WIDTH + FONT_GAP) * scale;
  }
}
