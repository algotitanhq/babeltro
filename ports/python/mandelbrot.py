"""The Mandelbrot dive. All float64, which is what both Python floats and
NumPy's default are, so the arithmetic is Go's without any care.

Vectorising an escape-time loop is the classic NumPy exercise: iterate every
point at once, and drop the ones that escape so the arrays shrink as the
iteration count grows. The two loop rungs are Go's per-point functions,
called once per pixel from plain Python.
"""

import math

import numpy as np

import palette

INSIDE = 0xFF0A0812


class Mandelbrot:
    def __init__(self):
        self.pal = palette.ICE
        self.w = self.h = 0
        self.block = 2
        # 1 iterates every pixel with no shortcut, 2 adds the closed-form
        # test for the cardioid and the bulb, 3 (the default) is vectorised
        # and renders on blocks of block×block pixels
        self.rung = 0

    def set_step(self, n):
        self.rung = n

    def resize(self, w, h):
        self.w, self.h = w, h
        # keep the block size constant in screen terms as the window grows
        self.block = 3 if w > 1600 else 2

    def prepare(self, s):
        u = min(s.beat, 14) / 12
        k = 1 - math.exp(-8 * u)
        self.scale = 2.9 * math.exp(-u * u * 3.6)
        self.max_iter = 64 + int(128 * u)
        self.cx = -0.5 + (-0.743643887037151 + 0.5) * k
        self.cy = 0.0 + 0.131825904205330 * k
        # one colour per iteration count, instead of a palette lookup per pixel
        lut = [palette.at(self.pal, min(math.sqrt(i / 40), 1) * 0.92 + 0.04) for i in range(self.max_iter)]
        self.lut = np.array(lut + [INSIDE], dtype=np.uint32)

    def draw(self, fb):
        w, h = self.w, self.h
        span = self.scale
        x0 = self.cx - span * 0.5
        y0 = self.cy - span * 0.5 * (h / w)
        d = span / w  # units per pixel
        if self.rung in (1, 2):
            return self.draw_points(fb, x0, y0, d, mandel_iter_plain if self.rung == 1 else mandel_iter)
        b = self.block
        # one point per block: an (h/b, w/b) grid of c values
        cx = x0 + np.arange(0, w, b, dtype=np.float64) * d
        cy = y0 + np.arange(0, h, b, dtype=np.float64)[:, None] * d
        it = escape_time(*np.broadcast_arrays(cx, cy), self.max_iter)
        # each block's colour, stretched back to b×b pixels
        fb[:] = self.lut[it].repeat(b, axis=0).repeat(b, axis=1)[:h, :w]

    def draw_points(self, fb, x0, y0, d, iterate):
        w, h, max_iter, lut = self.w, self.h, self.max_iter, self.lut.tolist()
        pix = memoryview(fb).cast("B").cast("I")
        for y in range(h):
            cy = y0 + y * d
            for x in range(w):
                pix[y * w + x] = lut[iterate(x0 + x * d, cy, max_iter)]


# @excerpt MANDELBROT
def escape_time(cx, cy, max_iter):
    """Iteration counts for a whole grid of points at once."""
    it = np.full(cx.shape, max_iter, dtype=np.intp)
    # cheap escape test for the main cardioid and the period-2 bulb
    x, y2 = cx - 0.25, cy * cy
    q = x * x + y2
    inside = (q * (q + x) <= 0.25 * y2) | ((cx + 1) * (cx + 1) + y2 <= 0.0625)
    live = np.flatnonzero(~inside)  # flat indices of the points still iterating
    c_x, c_y = cx.ravel()[live], cy.ravel()[live]
    zx = np.zeros_like(c_x)
    zy, zx2, zy2 = zx.copy(), zx.copy(), zx.copy()
    out = it.ravel()
    for i in range(max_iter):
        zy = 2 * zx * zy + c_y
        zx = zx2 - zy2 + c_x
        zx2 = zx * zx
        zy2 = zy * zy
        escaped = zx2 + zy2 > 4
        if escaped.any():
            out[live[escaped]] = i
            keep = ~escaped
            live, c_x, c_y, zx, zy, zx2, zy2 = (a[keep] for a in (live, c_x, c_y, zx, zy, zx2, zy2))
            if not live.size:
                break
    return it
# @end


# @excerpt MANDELBROT/2
def mandel_iter(cx, cy, max_iter):
    # cheap escape test for the main cardioid and the period-2 bulb
    x = cx - 0.25
    y2 = cy * cy
    q = x * x + y2
    if q * (q + x) <= 0.25 * y2:
        return max_iter
    if (cx + 1) * (cx + 1) + y2 <= 0.0625:
        return max_iter
    zx = zy = zx2 = zy2 = 0.0
    for i in range(max_iter):
        zy = 2 * zx * zy + cy
        zx = zx2 - zy2 + cx
        zx2 = zx * zx
        zy2 = zy * zy
        if zx2 + zy2 > 4:
            return i
    return max_iter
# @end


# @excerpt MANDELBROT/1
def mandel_iter_plain(cx, cy, max_iter):
    zx = zy = zx2 = zy2 = 0.0
    for i in range(max_iter):
        zy = 2 * zx * zy + cy
        zx = zx2 - zy2 + cx
        zx2 = zx * zx
        zy2 = zy * zy
        if zx2 + zy2 > 4:
            return i
    return max_iter
# @end
