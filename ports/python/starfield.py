"""The warp-speed starfield: 1600 stars projected in perspective and
dragged into streaks.

The projection is one array expression over all the stars. The streaks
are Bresenham lines, the most loop-shaped algorithm there is; see lines()
for how they come out of NumPy without one.
"""

import numpy as np

import canvas
import fmath
from fmath import F32

N = 1600
HEAD = 0xFFCCEEFF


class Starfield:
    def __init__(self):
        self.w = self.h = 0
        self.rng = fmath.Rng(0x6005E)
        x, y, z = self.rng.floats(3 * N).reshape(N, 3).T
        self.x = (x * F32(2) - F32(1)) * F32(1.6)
        self.y = (y * F32(2) - F32(1)) * F32(1.6)
        self.z = z * F32(40) + F32(0.2)

    def resize(self, w, h):
        if (w, h) == (self.w, self.h):
            return
        self.w, self.h = w, h
        # the deep-navy vignette never changes: build it once per size
        dx = np.arange(w) / w - 0.5
        dy = (np.arange(h) / h - 0.5)[:, None]
        v = dx * dx + dy * dy
        self.bg = canvas.from_float(np.maximum(0.02 - v * 0.03, 0), np.maximum(0.02 - v * 0.025, 0),
                                    np.maximum(0.05 - v * 0.03, 0))

    def prepare(self, s):
        w, h = self.w, self.h
        cx, cy = F32(w) * F32(0.5), F32(h) * F32(0.5)
        # accelerate over the scene so the entry has a kick
        speed = F32(2.5 + min(s.beat, 3) * 4)
        dz = speed * min(F32(s.dt), F32(0.1))
        # @excerpt STARFIELD
        self.z -= dz
        # stars that pass the camera respawn far away, in star order: two
        # random numbers each, x then y
        gone = np.flatnonzero(self.z < F32(0.8))
        self.z[gone] += F32(40)
        xy = self.rng.floats(2 * gone.size)
        self.x[gone] = (xy[0::2] * F32(2) - F32(1)) * F32(1.1)
        self.y[gone] = (xy[1::2] * F32(2) - F32(1)) * F32(1.1)

        zoom = F32(w) * F32(0.78)
        f = F32(1.0) / self.z
        f2 = F32(1.0) / (self.z + dz * F32(2.4))
        # streaks run from the trailing point (1) to the head (0)
        self.x0 = (cx + self.x * f * zoom).astype(np.int32)
        self.y0 = (cy + self.y * f * zoom).astype(np.int32)
        self.x1 = (cx + self.x * f2 * zoom).astype(np.int32)
        self.y1 = (cy + self.y * f2 * zoom).astype(np.int32)
        # brighter and bluer as the star gets close
        near = F32(1) - self.z / F32(40)
        b = near * near
        self.rgb = np.stack([F32(120) * b + F32(40), F32(190) * b + F32(40),
                             F32(255) * (F32(0.25) + F32(0.75) * b)]).astype(np.int64)
        # @end

    def draw(self, fb):
        w, h = self.w, self.h
        pix = fb.reshape(-1)
        pix[:] = self.bg.reshape(-1)
        idx, star = lines(self.x0, self.y0, self.x1, self.y1, w, h)

        # Go draws star by star: its additive line, then its head pixel on
        # top. Saturating additions commute, so only the heads need care: a
        # head erases what came before it, and later stars add over it.
        heads = (self.x1 >= 0) & (self.x1 < w) & (self.y1 >= 0) & (self.y1 < h)
        head_at = self.y1[heads].astype(np.intp) * w + self.x1[heads]
        last_head = np.full(w * h, -1)
        np.maximum.at(last_head, head_at, np.flatnonzero(heads))
        pix[head_at] = HEAD
        keep = star > last_head[idx]
        idx, star = idx[keep], star[keep]

        # sum each touched pixel's contributions, then saturate once
        touched, slot = np.unique(idx, return_inverse=True)
        r, g, b = canvas.unpack(pix[touched])
        add = [np.bincount(slot, weights=ch[star], minlength=touched.size).astype(np.int64) for ch in self.rgb]
        pix[touched] = canvas.pack(np.minimum(r + add[0], 255), np.minimum(g + add[1], 255),
                                   np.minimum(b + add[2], 255))


def lines(x0, y0, x1, y1, w, h):
    """Every on-screen pixel of every Bresenham line from (x0, y0) to (x1, y1),
    as flat pixel indices and the number of the line each belongs to.

    Go's Bresenham steps the major axis every iteration and the minor one
    when the error term says so. Solving that recurrence gives the minor
    offset of step k in closed form, floor((2·minor·k + major) / (2·major)),
    so all the lines' pixels come out at once with no loop at all. (Checked
    against the loop on 300 000 random lines, ties included.)
    """
    x0, y0, x1, y1 = (v.astype(np.intp) for v in (x0, y0, x1, y1))
    a, b = np.abs(x1 - x0), np.abs(y1 - y0)
    major, minor = np.maximum(a, b), np.minimum(a, b)
    n = major + 1  # pixels per line
    line = np.repeat(np.arange(n.size), n)
    k = np.arange(line.size) - np.repeat(np.cumsum(n) - n, n)  # step along each line
    mj, mn = np.maximum(major, 1)[line], minor[line]
    m = (2 * mn * k + mj) // (2 * mj)
    x_major = (a >= b)[line]
    x = x0[line] + np.where(x0 < x1, 1, -1)[line] * np.where(x_major, k, m)
    y = y0[line] + np.where(y0 < y1, 1, -1)[line] * np.where(x_major, m, k)
    on = (x >= 0) & (x < w) & (y >= 0) & (y < h)
    return (y * w + x)[on], line[on]
