r"""Colour packing and the 5x7 bitmap font, drawn block by block into an
(h, w) uint32 framebuffer. Each lit font cell is a scale×scale block, so a
glyph is a few dozen NumPy slice assignments rather than a pixel loop.
"""

import numpy as np

from fmath import F32


def from_float(r, g, b):
    """Normalised float64 colours (arrays) to packed pixels, clamping to [0, 1]."""

    def byte(v):
        # Go: 0 if v <= 0, 255 if v >= 1, else uint8(v*255 + 0.5). Clipping
        # v*255 + 0.5 to [0, 255] before truncating gives the same bytes.
        return np.clip(v * 255 + 0.5, 0, 255).astype(np.uint32)

    return 0xFF000000 | byte(b) << 16 | byte(g) << 8 | byte(r)


def unpack(p):
    """Packed pixels to int64 r, g, b channels (int64, so sums cannot wrap)."""
    p = p.astype(np.int64)
    return p & 0xFF, p >> 8 & 0xFF, p >> 16 & 0xFF


def pack(r, g, b):
    return (0xFF000000 | b << 16 | g << 8 | r).astype(np.uint32)


def additive(fb, y, x, c, intensity):
    """Adds colour c scaled by intensity/255 to one pixel, saturating."""
    if intensity == 0:
        return
    p = int(fb[y, x])
    r = min((p & 0xFF) + (c & 0xFF) * intensity // 255, 255)
    g = min((p >> 8 & 0xFF) + (c >> 8 & 0xFF) * intensity // 255, 255)
    b = min((p >> 16 & 0xFF) + (c >> 16 & 0xFF) * intensity // 255, 255)
    fb[y, x] = 0xFF000000 | b << 16 | g << 8 | r


def hline(fb, x, y, w, c):
    h, fw = fb.shape
    if 0 <= y < h:
        fb[y, max(x, 0):max(min(x + w, fw), 0)] = c


FONT_SRC = r"""
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
"""

# FONT[ch] is the list of lit (row, col) cells of the glyph
FONT = {}
for _line in FONT_SRC.strip().splitlines():
    _name, *_rows = _line.split()
    FONT[" " if _name == "SPACE" else _name] = [
        (r, c) for r, bits in enumerate(_rows) for c, bit in enumerate(bits) if bit == "1"
    ]

ADVANCE = 6  # five columns and a gap


def glyph(ch):
    return FONT.get(ch.upper())


def text_width(s, scale):
    return (len(s) * ADVANCE - 1) * scale if s else 0


def text_height(scale):
    return 7 * scale


def _blocks(fb, x, y, cells, scale):
    """The visible part of each scale×scale block, as slices of fb."""
    h, w = fb.shape
    for r, c in cells:
        px, py = x + c * scale, y + r * scale
        y0, y1, x0, x1 = max(py, 0), min(py + scale, h), max(px, 0), min(px + scale, w)
        if y0 < y1 and x0 < x1:
            yield y0, y1, x0, x1


def draw_text(fb, x, y, s, scale, c):
    for i, ch in enumerate(s):
        for y0, y1, x0, x1 in _blocks(fb, x + i * ADVANCE * scale, y, glyph(ch) or (), scale):
            fb[y0:y1, x0:x1] = c


def draw_text_outline(fb, x, y, s, scale, c, offs):
    """s offset by one pixel in the four cardinal directions: a hard edge."""
    for i, ch in enumerate(s):
        gx, gy = x + i * ADVANCE * scale, y + offs[i]
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            draw_text(fb, gx + dx, gy + dy, ch, scale, c)


def _channels(c):
    return np.array([c & 0xFF, c >> 8 & 0xFF, c >> 16 & 0xFF], dtype=F32)


def draw_text_gradient(fb, x, y, s, scale, top, mid, bottom, offs, scan):
    """s with a three-stop vertical ramp. The colour depends only on the
    screen row, so it is one column of colours, computed once."""
    top, mid, bottom = _channels(top), _channels(mid), _channels(bottom)
    rows = np.arange(fb.shape[0])
    f = np.clip((rows - y).astype(F32) / F32(7 * scale), F32(0), F32(1))[:, None]
    upper = top + (mid - top) * (f * F32(2))
    lower = mid + (bottom - mid) * ((f - F32(0.5)) * F32(2))
    rgb = np.where(f < F32(0.5), upper, lower).astype(np.uint32)  # truncates, like uint32()
    if scan:
        rgb[rows & 3 == 0] = rgb[rows & 3 == 0] * 3 // 4
    col = pack(rgb[:, 0], rgb[:, 1], rgb[:, 2])[:, None]
    for i, ch in enumerate(s):
        for y0, y1, x0, x1 in _blocks(fb, x + i * ADVANCE * scale, y + offs[i], glyph(ch) or (), scale):
            fb[y0:y1, x0:x1] = col[y0:y1]


def draw_text_reflect(fb, x, y, s, scale, top, bottom, offs, strength, depth):
    """A mirrored copy of s below row y, fading over depth rows and added to
    the framebuffer: light on a polished floor."""
    depth = max(depth, 1)
    top, bottom = _channels(top), _channels(bottom)
    rows = np.arange(fb.shape[0])
    d = (rows - y).astype(F32) / F32(depth)
    a = F32(1) - d
    inten = (F32(strength) * (a * a)).astype(np.int64)
    inten[d > 1] = 0
    rgb = (top + (bottom - top) * d[:, None]).astype(np.int64)
    # what Additive adds per row: channel * intensity / 255, in integers
    add = (rgb * inten[:, None] // 255)[:, None, :]
    for i, ch in enumerate(s):
        # glyph row 0 sits at the far end, and a lifted letter's reflection
        # is pushed down by as much
        cells = [(6 - r, c) for r, c in glyph(ch) or ()]
        for y0, y1, x0, x1 in _blocks(fb, x + i * ADVANCE * scale, y - offs[i], cells, scale):
            block = fb[y0:y1, x0:x1]
            r, g, b = unpack(block)
            ad = add[y0:y1]
            block[:] = pack(np.minimum(r + ad[..., 0], 255), np.minimum(g + ad[..., 1], 255),
                            np.minimum(b + ad[..., 2], 255))
