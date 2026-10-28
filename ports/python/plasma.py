"""Four summed sine fields, the oldest trick in the demoscene book.

Go's ladder is about the maths: sin() per pixel, then a sine table, then
1D tables. In Python the ladder that matters is the loop itself. Rungs 1 and
2 are Go's per-pixel loops, written as plain Python; the default is the
whole frame as a handful of NumPy array operations.
"""

import math

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

import fmath
import palette
from fmath import F32


class Plasma:
    def __init__(self):
        self.pal = palette.SUNSET
        self.w = self.h = 0
        # 1 calls sin() four times per pixel, 2 reads the sine table four
        # times per pixel, 3 (the default) is the vectorised version
        self.step = 0

    def set_step(self, n):
        self.step = n

    def resize(self, w, h):
        if (w, h) == (self.w, self.h):
            return
        self.w, self.h = w, h
        dx = np.arange(w, dtype=F32) - F32(w) * F32(0.5)
        dy = np.arange(h, dtype=F32)[:, None] - F32(h) * F32(0.5)
        # np.sqrt on float32 is a correctly rounded sqrtf: the same value as
        # Go's float32(math.Sqrt(float64(v)))
        self.rad = np.sqrt(dx * dx + dy * dy) * (F32(44) / F32(w + h))
        self.xs = np.arange(w, dtype=F32)
        self.ys = np.arange(h, dtype=F32)
        self.ds = np.arange(w + h, dtype=F32)

    def prepare(self, s):
        w, h = self.w, self.h
        t = F32(s.beat)
        self.t = t
        self.kx = F32(26) / F32(w)
        self.ky = F32(26) / F32(h)
        self.kr = F32(44) / F32(w + h)
        self.cx, self.cy = F32(w) * F32(0.5), F32(h) * F32(0.5)
        self.phase = t * F32(2.6)

    def draw(self, fb):
        if self.step == 1:
            return self.draw_sin(fb)
        if self.step == 2:
            return self.draw_table(fb)
        t, kx, ky, h, w = self.t, self.kx, self.ky, self.h, self.w
        # @excerpt PLASMA
        sx = fmath.sin(self.xs * kx + t * F32(1.3))  # one row: depends on x only
        sy = fmath.sin(self.ys * ky * F32(1.35) - t * F32(1.1))[:, None]  # one column
        sxy = fmath.sin(self.ds * kx * F32(0.85) + t * F32(0.8))  # depends on x+y
        # row y reads sxy[y : y+w]: an (h, w) strided view, no copy
        diag = sliding_window_view(sxy, w)[:h]
        v = sx + sy + diag + fmath.sin(self.rad + self.phase)
        # astype truncates toward zero, like Go's int()
        i = np.clip((v * F32(36) + F32(127.5)).astype(np.intp), 0, 255)
        np.take(self.pal, i, out=fb)
        # @end

    def draw_sin(self, fb):
        # The plasma as you would first write it. The floats are np.float32
        # scalars, so the arithmetic rounds like Go's; math.sin is float64,
        # rounded back like Go's sin32.
        f32, sin, sqrt = F32, math.sin, math.sqrt
        w, h, t, kx, ky, kr = self.w, self.h, self.t, self.kx, self.ky, self.kr
        cx, cy, phase = self.cx, self.cy, self.phase
        pal = self.pal.tolist()
        pix = memoryview(fb).cast("B").cast("I")
        # @excerpt PLASMA/1
        for y in range(h):
            dy = f32(y) - cy
            for x in range(w):
                dx = f32(x) - cx
                rad = f32(sqrt(dx * dx + dy * dy)) * kr
                v = (f32(sin(f32(x) * kx + t * 1.3))
                     + f32(sin(f32(y) * ky * 1.35 - t * 1.1))
                     + f32(sin(f32(x + y) * kx * 0.85 + t * 0.8))
                     + f32(sin(rad + phase)))
                i = int(v * 36 + 127.5)
                if i < 0:
                    i = 0
                elif i > 255:
                    i = 255
                pix[y * w + x] = pal[i]
        # @end

    def draw_table(self, fb):
        f32, sin, sqrt = F32, fmath.sin1, math.sqrt
        w, h, t, kx, ky, kr = self.w, self.h, self.t, self.kx, self.ky, self.kr
        cx, cy, phase = self.cx, self.cy, self.phase
        pal = self.pal.tolist()
        pix = memoryview(fb).cast("B").cast("I")
        # @excerpt PLASMA/2
        for y in range(h):
            dy = f32(y) - cy
            for x in range(w):
                dx = f32(x) - cx
                rad = f32(sqrt(dx * dx + dy * dy)) * kr
                v = (sin(f32(x) * kx + t * 1.3)
                     + sin(f32(y) * ky * 1.35 - t * 1.1)
                     + sin(f32(x + y) * kx * 0.85 + t * 0.8)
                     + sin(rad + phase))
                i = int(v * 36 + 127.5)
                if i < 0:
                    i = 0
                elif i > 255:
                    i = 255
                pix[y * w + x] = pal[i]
        # @end
