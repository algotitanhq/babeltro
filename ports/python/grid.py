"""The synthwave floor under a banded sun.

Go hoists everything that depends only on the row out of the pixel loop.
NumPy makes that the natural shape: every per-row quantity is a column
(an (n, 1) array), every per-pixel one is (n, w), and broadcasting does
the hoisting. Go mixes float32 and float64 here more than anywhere else;
each `float64(...)` in Go is an .astype(np.float64) here, and back.
"""

import numpy as np

import canvas
from fmath import F32

F64 = np.float64


def clamp01(v):
    return np.clip(v, 0, 1)


def mod1(v):
    """v wrapped into [0, 1): v minus its truncation, like Go's mathMod2."""
    m = v - v.astype(np.int32).astype(F32)
    return np.where(m < 0, m + F32(1), m)


def line_glow(f, w):
    """1 on the grid line, falling to 0 over width w."""
    d = np.where(f > F32(0.5), F32(1) - f, f)
    return np.where(d < w, F32(1) - d / w, F32(0))


class Grid:
    def __init__(self):
        self.w = self.h = 0

    def resize(self, w, h):
        self.w, self.h = w, h
        self.horizon = F32(h) * F32(0.52)
        self.asp = F32(h) / F32(w)

    def prepare(self, s):
        self.t = F32(s.beat)

    def draw(self, fb):
        w, h, t, asp, horizon = self.w, self.h, self.t, self.asp, self.horizon
        cx = F32(w) * F32(0.5)
        fy = np.arange(h, dtype=F32)[:, None]  # one column: the row's y
        xs = np.arange(w, dtype=F32)

        # the sky, one colour per row
        sky = clamp01((fy / horizon).astype(F64))
        r, g, b = (np.repeat(c.astype(F32), w, axis=1)
                   for c in (0.03 + 0.18 * sky * sky, 0.01 + 0.05 * sky, 0.08 + 0.22 * sky))

        # the sun: only on its rows, only off the stripes, only in its circle
        sun_y = horizon - F32(h) * F32(0.13)
        sun_r = F32(h) * F32(0.16)
        dyc = fy - sun_y
        sun_row = (dyc > -sun_r) & (dyc < sun_r) & (fy < horizon + F32(2))
        stripe = (fy > sun_y - sun_r * F32(0.45)) & (fy.astype(np.int32) % 9 < 4)
        rows = np.flatnonzero(sun_row[:, 0])
        dx = xs - cx
        cols = np.flatnonzero((dx > -sun_r) & (dx < sun_r))
        if rows.size and cols.size:
            box = np.s_[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]  # rows and columns are runs
            dyc, dx = dyc[box[0]], dx[box[1]]
            u = clamp01(((fy[box[0]] - (sun_y - sun_r)) / (F32(2) * sun_r)).astype(F64))
            sun = F32(1), (0.95 - 0.7 * u).astype(F32), (0.25 + 0.55 * u).astype(F32)
            d = np.sqrt(dx * dx + dyc * dyc)
            disc = ~stripe[box[0]] & (d < sun_r)
            edge = clamp01(((sun_r - d) / (sun_r * F32(0.025))).astype(F64)).astype(F32)
            for c, sc in zip((r, g, b), sun):
                c = c[box]
                np.copyto(c, c + (sc - c) * edge, where=disc)  # mix(c, sun, edge)

        # @excerpt GRID
        # the floor: rows below the horizon, each one depth
        y0 = int(np.argmax(fy[:, 0] > horizon)) if fy[-1, 0] > horizon else h
        fy = fy[y0:]
        dz = fy - horizon  # distance below the horizon, in pixels
        z = (F32(h) * F32(0.55)) / dz
        wz = z * F32(2.5) + t * F32(5.5)
        kx = z / (F32(w) * F32(0.5)) * asp * F32(2.0)  # world x per pixel
        fade_x = clamp01(((F32(1) / kx - F32(1.5)) / F32(2)).astype(F64)).astype(F32)
        lw_x = F32(0.022)
        # a line narrower than a pixel is widened to one and dimmed to match
        period = dz * dz / (F32(1.375) * F32(h))  # pixels per unit of wz
        lw_z = F32(0.014) + F32(0.024) / z
        min_w = F32(0.5) / period
        amp_z = np.where(lw_z < min_w, lw_z / min_w, F32(1))
        lw_z = np.maximum(lw_z, min_w)
        line_z = line_glow(mod1(wz), lw_z) * amp_z
        line_z *= clamp01(((period - F32(1.5)) / F32(2)).astype(F64)).astype(F32)
        line_z *= clamp01((F32(1.0) / (F32(1) + z * z * F32(0.004))).astype(F64)).astype(F32)
        haze = 1 - clamp01((dz / (F32(h) * F32(0.12))).astype(F64))  # the glow near the horizon
        floor = [F32(base) + (k * haze).astype(F32) + F32(gain) * line_z
                 for base, k, gain in ((0.02, 0.25, 0.55), (0.01, 0.05, 0.35), (0.06, 0.35, 0.75))]

        # per pixel: the lines across, widened to the ray's sideways slide
        xc = xs - cx
        w_px0 = F32(2) * lw_x / kx
        w_px = np.maximum(np.maximum(w_px0, np.abs(xc) / dz), F32(1))
        line_x = line_glow(mod1(xc * kx + F32(0.37)), w_px * kx * F32(0.5)) * (w_px0 / w_px) * fade_x
        line = np.maximum(line_x, line_z)
        for c, fl, gain in zip((r, g, b), floor, (F32(0.55), F32(0.35), F32(0.75))):
            c[y0:] = fl - gain * line_z + gain * line
        # @end

        fb[:] = canvas.from_float(r.astype(F64), g.astype(F64), b.astype(F64))
