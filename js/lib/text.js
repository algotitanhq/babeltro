// A 5x7 bitmap font and the text renderers the finale uses. Everything the
// demo prints is drawn from these dots by the CPU: no canvas fillText, no
// font loading.

import { f32 } from './fmath.js';

// Each line is "CHAR row0 … row6", one character per pixel, MSB first.
// String.raw keeps the backslash glyph's backslash.
const FONT_SRC = String.raw`
SPACE 00000 00000 00000 00000 00000 00000 00000
! 00100 00100 00100 00100 00100 00000 00100
" 01010 01010 01010 00000 00000 00000 00000
# 01010 01010 11111 01010 11111 01010 01010
$ 00100 01111 10100 01110 00101 11110 00100
% 11001 11010 00010 00100 01000 01011 10011
& 01100 10010 10100 01000 10101 10010 01101
' 00100 00100 01000 00000 00000 00000 00000
( 00010 00100 01000 01000 01000 00100 00010
) 01000 00100 00010 00010 00010 00100 01000
* 00000 10101 01110 11111 01110 10101 00000
+ 00000 00100 00100 11111 00100 00100 00000
, 00000 00000 00000 00000 01100 01100 11000
- 00000 00000 00000 11111 00000 00000 00000
. 00000 00000 00000 00000 00000 01100 01100
/ 00001 00010 00010 00100 01000 01000 10000
0 01110 10001 10011 10101 11001 10001 01110
1 00100 01100 00100 00100 00100 00100 01110
2 01110 10001 00001 00110 01000 10000 11111
3 11111 00010 00100 00010 00001 10001 01110
4 00010 00110 01010 10010 11111 00010 00010
5 11111 10000 11110 00001 00001 10001 01110
6 00110 01000 10000 11110 10001 10001 01110
7 11111 00001 00010 00100 01000 01000 01000
8 01110 10001 10001 01110 10001 10001 01110
9 01110 10001 10001 01111 00001 00010 01100
: 00000 01100 01100 00000 01100 01100 00000
; 00000 01100 01100 00000 01100 00100 01000
< 00010 00100 01000 10000 01000 00100 00010
= 00000 00000 11111 00000 11111 00000 00000
> 01000 00100 00010 00001 00010 00100 01000
? 01110 10001 00001 00110 00100 00000 00100
@ 01110 10001 10111 10101 10111 10000 01110
A 01110 10001 10001 11111 10001 10001 10001
B 11110 10001 10001 11110 10001 10001 11110
C 01110 10001 10000 10000 10000 10001 01110
D 11110 10001 10001 10001 10001 10001 11110
E 11111 10000 10000 11110 10000 10000 11111
F 11111 10000 10000 11110 10000 10000 10000
G 01110 10001 10000 10111 10001 10001 01111
H 10001 10001 10001 11111 10001 10001 10001
I 11111 00100 00100 00100 00100 00100 11111
J 00111 00010 00010 00010 00010 10010 01100
K 10001 10010 10100 11000 10100 10010 10001
L 10000 10000 10000 10000 10000 10000 11111
M 10001 11011 10101 10101 10001 10001 10001
N 10001 11001 10101 10011 10001 10001 10001
O 01110 10001 10001 10001 10001 10001 01110
P 11110 10001 10001 11110 10000 10000 10000
Q 01110 10001 10001 10001 10101 10010 01101
R 11110 10001 10001 11110 10100 10010 10001
S 01111 10000 10000 01110 00001 00001 11110
T 11111 00100 00100 00100 00100 00100 00100
U 10001 10001 10001 10001 10001 10001 01110
V 10001 10001 10001 10001 10001 01010 00100
W 10001 10001 10001 10101 10101 10101 01010
X 10001 10001 01010 00100 01010 10001 10001
Y 10001 10001 01010 00100 00100 00100 00100
Z 11111 00001 00010 00100 01000 10000 11111
[ 01110 01000 01000 01000 01000 01000 01110
\ 10000 01000 01000 00100 00010 00010 00001
] 01110 00010 00010 00010 00010 00010 01110
^ 00100 01010 10001 00000 00000 00000 00000
_ 00000 00000 00000 00000 00000 00000 11111
{ 00110 00100 01000 01000 01000 00100 00110
| 00100 00100 00100 00100 00100 00100 00100
} 01100 00100 00010 00010 00010 00100 01100
~ 00000 00000 01000 10101 00010 00000 00000
`;

const GLYPHS = 95; // printable ASCII, from ' ' to '~'
const FONT_W = 5;
const FONT_GAP = 1;
const ADVANCE = FONT_W + FONT_GAP;

// FONT[g * 7 + row] holds the 5 bits of one glyph row.
const FONT = new Uint8Array(GLYPHS * 7);
for (const line of FONT_SRC.split('\n')) {
  const fields = line.trim().split(/\s+/);
  if (fields.length !== 8) continue;
  const ch = fields[0] === 'SPACE' ? ' ' : fields[0];
  const idx = ch.charCodeAt(0) - 32;
  if (idx < 0 || idx >= GLYPHS) continue;
  for (let r = 0; r < 7; r++) FONT[idx * 7 + r] = parseInt(fields[r + 1], 2);
}

/** Maps a character code to its glyph, folding lowercase; -1 if none. */
function glyphIndex(code) {
  if (code >= 97 && code <= 122) code -= 32;
  const idx = code - 32;
  return idx >= 0 && idx < GLYPHS ? idx : -1;
}

/** Pixel width of s at an integer scale. */
export function textWidth(s, scale) {
  return s.length === 0 ? 0 : (s.length * ADVANCE - FONT_GAP) * scale;
}

/** Pixel height of one line at an integer scale. */
export function textHeight(scale) {
  return 7 * scale;
}

/** Draws s in a solid colour with its top-left corner at (x, y). */
export function drawText(fb, x, y, s, scale, c) {
  if (scale < 1) scale = 1;
  const { w, h, pix } = fb;
  let cx = x;
  for (let k = 0; k < s.length; k++) {
    const idx = glyphIndex(s.charCodeAt(k));
    if (idx < 0) {
      cx += FONT_W * scale;
      continue;
    }
    for (let row = 0; row < 7; row++) {
      const bits = FONT[idx * 7 + row];
      if (bits === 0) continue;
      for (let col = 0; col < 5; col++) {
        if ((bits & (1 << (4 - col))) === 0) continue;
        const px = cx + col * scale;
        const py = y + row * scale;
        for (let yy = py; yy < py + scale; yy++) {
          if (yy < 0 || yy >= h) continue;
          const base = yy * w;
          for (let xx = px; xx < px + scale; xx++) {
            if (xx >= 0 && xx < w) pix[base + xx] = c;
          }
        }
      }
    }
    cx += ADVANCE * scale;
  }
}

/**
 * Draws s with a three-stop vertical colour ramp (top, mid, bottom): the
 * finale logo's chrome look. Glyph k is shifted down by offs[k], so the
 * letters can wave without giving up the gradient. With scan set every
 * fourth row is darkened, the CRT look.
 */
export function drawTextGradient(fb, x, y, s, scale, top, mid, bottom, offs, scan) {
  if (scale < 1) scale = 1;
  const tr = top & 0xff, tg = (top >>> 8) & 0xff, tb = (top >>> 16) & 0xff;
  const mr = mid & 0xff, mg = (mid >>> 8) & 0xff, mb = (mid >>> 16) & 0xff;
  const br = bottom & 0xff, bg = (bottom >>> 8) & 0xff, bb = (bottom >>> 16) & 0xff;
  const totalH = 7 * scale;
  const { w, h, pix } = fb;
  let cx = x;
  for (let k = 0; k < s.length; k++) {
    const dy = k < offs.length ? offs[k] : 0;
    const idx = glyphIndex(s.charCodeAt(k));
    for (let row = 0; idx >= 0 && row < 7; row++) {
      const bits = FONT[idx * 7 + row];
      if (bits === 0) continue;
      // clip the scale×scale block once, then write straight runs
      const py = y + row * scale + dy;
      const y0 = Math.max(py, 0), y1 = Math.min(py + scale, h);
      for (let col = 0; col < 5; col++) {
        if ((bits & (1 << (4 - col))) === 0) continue;
        const px = cx + col * scale;
        const x0 = Math.max(px, 0), x1 = Math.min(px + scale, w);
        if (y0 >= y1 || x0 >= x1) continue;
        for (let yy = y0; yy < y1; yy++) {
          let f = f32((yy - y) / totalH);
          if (f < 0) f = 0;
          else if (f > 1) f = 1;
          // the channel bytes are small integers, exact as float32 already
          let r, g, b;
          if (f < 0.5) {
            const u = f32(f * 2);
            r = f32(tr + f32((mr - tr) * u)) | 0;
            g = f32(tg + f32((mg - tg) * u)) | 0;
            b = f32(tb + f32((mb - tb) * u)) | 0;
          } else {
            const u = f32(f32(f - 0.5) * 2);
            r = f32(mr + f32((br - mr) * u)) | 0;
            g = f32(mg + f32((bg - mg) * u)) | 0;
            b = f32(mb + f32((bb - mb) * u)) | 0;
          }
          if (scan && (yy & 3) === 0) {
            r = (r * 3) >>> 2;
            g = (g * 3) >>> 2;
            b = (b * 3) >>> 2;
          }
          pix.fill(0xff000000 | (b << 16) | (g << 8) | r, yy * w + x0, yy * w + x1);
        }
      }
    }
    cx += ADVANCE * scale;
  }
}

/**
 * Draws s offset by one pixel in the four cardinal directions in colour c:
 * a hard edge that keeps the logo readable over a busy background.
 */
export function drawTextOutline(fb, x, y, s, scale, c, offs) {
  for (let k = 0; k < s.length; k++) {
    const dy = k < offs.length ? offs[k] : 0;
    const g = s[k];
    const gx = x + k * ADVANCE * scale;
    drawText(fb, gx - 1, y + dy, g, scale, c);
    drawText(fb, gx + 1, y + dy, g, scale, c);
    drawText(fb, gx, y + dy - 1, g, scale, c);
    drawText(fb, gx, y + dy + 1, g, scale, c);
  }
}

/**
 * Draws a vertically mirrored copy of s below the line y, fading out over
 * depth rows and added to the framebuffer: light on a polished floor. A
 * letter lifted by offs[k] has its reflection pushed down by as much.
 */
export function drawTextReflect(fb, x, y, s, scale, top, bottom, offs, strength, depth) {
  if (scale < 1) scale = 1;
  if (depth < 1) depth = 1;
  const tr = top & 0xff, tg = (top >>> 8) & 0xff, tb = (top >>> 16) & 0xff;
  const br = bottom & 0xff, bg = (bottom >>> 8) & 0xff, bb = (bottom >>> 16) & 0xff;
  const { w, h } = fb;
  let cx = x;
  for (let k = 0; k < s.length; k++) {
    const dy = k < offs.length ? offs[k] : 0;
    const idx = glyphIndex(s.charCodeAt(k));
    for (let row = 0; idx >= 0 && row < 7; row++) {
      const bits = FONT[idx * 7 + row];
      if (bits === 0) continue;
      // mirrored: glyph row 0 sits at the far end
      const py = y + (6 - row) * scale - dy;
      const y0 = Math.max(py, 0), y1 = Math.min(py + scale, h);
      for (let col = 0; col < 5; col++) {
        if ((bits & (1 << (4 - col))) === 0) continue;
        const px = cx + col * scale;
        const x0 = Math.max(px, 0), x1 = Math.min(px + scale, w);
        if (y0 >= y1 || x0 >= x1) continue;
        for (let yy = y0; yy < y1; yy++) {
          const d = f32((yy - y) / depth);
          if (d > 1) continue;
          let a = f32(1 - d);
          a = f32(a * a);
          const inten = f32(strength * a) | 0;
          if (inten === 0) continue;
          const r = f32(tr + f32((br - tr) * d)) | 0;
          const g = f32(tg + f32((bg - tg) * d)) | 0;
          const b = f32(tb + f32((bb - tb) * d)) | 0;
          const c = 0xff000000 | (b << 16) | (g << 8) | r;
          const base = yy * w;
          for (let xx = x0; xx < x1; xx++) fb.additive(base + xx, c, inten);
        }
      }
    }
    cx += ADVANCE * scale;
  }
}
