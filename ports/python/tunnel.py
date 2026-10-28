"""The tunnel: every pixel mapped to polar coordinates once, at resize time.

After that a frame is a dozen whole-image array operations. The ladder's
first rung recomputes the distance and the angle for every pixel, every
frame, in a plain Python loop.
"""

import math

import numpy as np

import fmath
import palette
from fmath import F32


class Tunnel:
    def __init__(self):
        self.pal = palette.ICE
        self.w = self.h = 0
        # 1 computes distance and angle per pixel, every frame; 2 (the
        # default) reads them from tables built at resize
        self.step = 0

    def set_step(self, n):
        self.step = n

    def resize(self, w, h):
        if (w, h) == (self.w, self.h):
            return
        self.w, self.h = w, h
        # scale with the diagonal so the rings look the same at any size
        self.scale = F32(w + h) * F32(2.2)
        self.soft = F32(w + h) * F32(0.02)
        self.cx, self.cy = F32(w) / F32(2), F32(h) / F32(2)
        dx = np.arange(w, dtype=F32) - self.cx
        dy = np.arange(h, dtype=F32)[:, None] - self.cy
        self.depth = self.scale / (np.sqrt(dx * dx + dy * dy) + self.soft)
        self.angle = fmath.atan2_turns(*np.broadcast_arrays(dy, dx))

    def prepare(self, s):
        self.t = F32(s.beat)

    def draw(self, fb):
        if self.step == 1:
            return self.draw_direct(fb)
        adv = self.t * F32(3.0)
        spin = self.t * F32(0.25)
        # @excerpt TUNNEL
        u = self.depth + adv  # scroll towards the viewer
        ring = fmath.sin01(u * F32(0.16))  # rings along the depth axis
        twist = self.angle * F32(12) + u * F32(0.09) + spin
        spoke = fmath.sin01(twist)  # spokes that twist as they recede
        val = ring * F32(0.55) + spoke * F32(0.45)
        # brick checker gives the walls their structure
        odd = ((u * F32(0.32)).astype(np.int32) + twist.astype(np.int32)) & 1 == 1
        val = np.where(odd, -val * F32(0.7), val)
        fog = F32(1) / (F32(1) + u * F32(0.02))
        lum = (val * F32(0.5) + F32(0.5)) * fog
        idx = np.clip((lum * F32(300)).astype(np.intp), 0, 255)
        np.take(self.pal, idx, out=fb)
        # @end

    def draw_direct(self, fb):
        f32, sqrt, atan2, sin01 = F32, math.sqrt, math.atan2, fmath.sin01_1
        w, h, cx, cy = self.w, self.h, self.cx, self.cy
        scale, soft, two_pi = self.scale, self.soft, fmath.TWO_PI
        adv = self.t * 3.0
        spin = self.t * 0.25
        pal = self.pal.tolist()
        pix = memoryview(fb).cast("B").cast("I")
        # @excerpt TUNNEL/1
        for y in range(h):
            dy = f32(y) - cy
            for x in range(w):
                dx = f32(x) - cx
                depth = scale / (f32(sqrt(dx * dx + dy * dy)) + soft)
                u = depth + adv
                v = f32(atan2(dy, dx)) / two_pi + 0.5

                ring = sin01(u * 0.16)
                twist = v * 12 + u * 0.09 + spin
                spoke = sin01(twist)
                val = ring * 0.55 + spoke * 0.45
                if (int(u * 0.32) + int(twist)) & 1:
                    val = -val * 0.7
                fog = 1 / (1 + u * 0.02)
                lum = (val * 0.5 + 0.5) * fog
                idx = int(lum * 300)
                if idx > 255:
                    idx = 255
                elif idx < 0:
                    idx = 0
                pix[y * w + x] = pal[idx]
        # @end
