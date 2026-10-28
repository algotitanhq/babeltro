"""Metaballs: six radial fields summed per pixel, the iso-contour shaded.

The field of one ball over the whole screen is an outer sum of a row of
x terms and a column of y terms: broadcasting builds it without a loop.
"""

import numpy as np

import fmath
import palette
from fmath import F32

N = 6


class Metaballs:
    def __init__(self):
        self.pal = palette.SUNSET
        self.w = self.h = 0

    def resize(self, w, h):
        self.w, self.h = w, h
        # x is scaled by width/height so a circle in field space is a circle on screen
        self.asp = F32(w) / F32(h)
        self.fx = (np.arange(w, dtype=F32) / F32(w) - F32(0.5)) * self.asp
        self.fy = (np.arange(h, dtype=F32) / F32(h) - F32(0.5))[:, None]

    def prepare(self, s):
        t = F32(s.beat)
        self.balls = []
        for i in range(N):
            fi = F32(i)
            # each ball orbits on its own ellipse and breathes
            a = t * (F32(0.35) + fi * F32(0.07)) + fi * F32(2.1)
            bx = F32(0.5) + F32(0.20) * fmath.cos1(a) * (F32(1) + F32(0.3) * fmath.sin1(t * F32(0.5) + fi))
            by = F32(0.5) + F32(0.20) * fmath.sin1(a * F32(1.3) + fi) * (
                F32(1) + F32(0.3) * fmath.cos1(t * F32(0.4) + fi * F32(2)))
            r = F32(0.105) + F32(0.025) * fmath.sin1(t * F32(1.1) + fi * F32(1.7))
            self.balls.append((bx, by, r * r))

    def draw(self, fb):
        asp = self.asp
        # @excerpt METABALLS
        field = np.zeros(fb.shape, dtype=F32)
        for bx, by, r2 in self.balls:
            dx = self.fx - (bx - F32(0.5)) * asp  # a row
            dy = self.fy - (by - F32(0.5))  # a column
            field += r2 / (dx * dx + dy * dy + F32(1e-5))  # the (h, w) field
        # about 1 on a ball's surface; v/(1+v) compresses it into 0..1
        v = field / (F32(1.6) + field)
        idx = np.minimum((v * F32(255)).astype(np.intp), 255)
        # rim: the iso-surface where the balls meet flares white
        idx[(field > F32(1.0)) & (field < F32(1.09))] = 255
        np.take(self.pal, idx, out=fb)
        # @end
