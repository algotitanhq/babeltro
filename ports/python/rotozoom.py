"""Rotozoom: build a texture once, then every frame rotate and zoom the
sampling grid over it. Cost per pixel: a few multiplies and one lookup,
which in NumPy is a few whole-image multiplies and one np.take.
"""

import numpy as np

import canvas
import fmath
import palette
from fmath import F32

TEX_SIZE = 512
TEX_MASK = TEX_SIZE - 1

_texture = None


def texture():
    """A tileable rainbow plasma with a dark grid, built once per module.

    It is float64 throughout, like Go's, except that Go divides the
    coordinates in float32 first; dividing by 512 is exact either way.
    """
    global _texture
    if _texture is not None:
        return _texture
    two_pi = 2 * np.pi
    i = np.arange(TEX_SIZE, dtype=np.float64)
    fx, fy = i / TEX_SIZE, i[:, None] / TEX_SIZE
    # every frequency is a whole number of cycles per tile, so it wraps
    v = (np.sin(fx * two_pi * 3 + fy * two_pi * 2) * 0.5
         + np.sin(fy * two_pi * 5 - fx * two_pi * 4) * 0.3
         + np.sin((fx + fy) * two_pi * 7) * 0.2)
    # concentric rings, also periodic in the tile
    dx, dy = i - TEX_SIZE / 2, i[:, None] - TEX_SIZE / 2
    rr = np.sqrt(dx * dx + dy * dy) / TEX_SIZE * 12
    v = v + np.sin(rr * two_pi) * 0.35

    hue = np.fmod(v * 0.55 + 0.5, 1)  # fmod, like Go's math.Mod, keeps the sign
    hue = np.where(hue < 0, hue + 1, hue)
    r, g, b = palette.hsl2rgb(hue, 0.70, 0.48 + 0.14 * v)
    # a dark grid over the colour, or the motion reads as shimmer
    line = (np.arange(TEX_SIZE) % (TEX_SIZE // 8) < 3)
    dark = np.where(line | line[:, None], 0.28, 1.0)
    _texture = canvas.from_float(r * dark, g * dark, b * dark).ravel()
    return _texture


class Rotozoom:
    def __init__(self):
        self.w = self.h = 0

    def resize(self, w, h):
        self.w, self.h = w, h
        self.tex = texture()
        self.dx = np.arange(w, dtype=F32) - F32(w) * F32(0.5)
        self.dy = np.arange(h, dtype=F32)[:, None] - F32(h) * F32(0.5)

    def prepare(self, s):
        t = F32(s.beat)
        ang = t * F32(0.45)
        self.cos_a, self.sin_a = fmath.cos1(ang), fmath.sin1(ang)
        # breathing zoom: 0.7 .. 1.6
        self.zoom = F32(0.55) + F32(0.45) * fmath.sin1(t * F32(0.7)) + F32(0.35)
        self.offx = fmath.sin1(t * F32(0.31)) * F32(180) + t * F32(26)
        self.offy = fmath.cos1(t * F32(0.27)) * F32(180) + t * F32(19)

    def draw(self, fb):
        dx, dy, cos_a, sin_a = self.dx, self.dy, self.cos_a, self.sin_a
        zoom = self.zoom / F32(self.w) * F32(6.5)
        # @excerpt ROTOZOOM
        tx = (dx * cos_a - dy * sin_a) * zoom * F32(34)
        ty = (dx * sin_a + dy * cos_a) * zoom * F32(34)
        ix = (tx + self.offx).astype(np.int32) & TEX_MASK  # the wrap is a bit mask
        iy = (ty + self.offy).astype(np.int32) & TEX_MASK
        np.take(self.tex, iy * TEX_SIZE + ix, out=fb)
        # @end
