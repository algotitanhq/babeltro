"""The closing card: the language's name in a chrome 5x7 font, its
reflection, a pool of light and the numbers that make the point.
"""

import math

import numpy as np

import canvas
import fmath
from fmath import F32

TAG = "ONE THREAD - NO GPU - NO SHADER"
LINES = ("0 GPU SHADERS", "0 EXTERNAL MODULES", "0 ASSETS ON DISK")
TOP, MID, BOT = 0xFFFFF6E8, 0xFF7C9CFF, 0xFF582080  # cream, rose, violet


def idiv(a, b):
    """Go's integer division, which truncates toward zero; // floors."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


class Finale:
    def __init__(self, lang):
        self.lang = lang
        self.w = self.h = 0
        rng = fmath.Rng(0xF1A1E)
        # fixed background stars: x, y, brightness
        self.stars = [(rng.float32(), rng.float32(), F32(0.15) + rng.float32() * F32(0.85)) for _ in range(260)]

    def resize(self, w, h):
        if (w, h) == (self.w, self.h):
            return
        self.w, self.h = w, h
        th, tw = canvas.text_height, canvas.text_width
        self.sub = "EVERY PIXEL IS " + self.lang
        self.sub_scale = max(w // 300, 1)
        self.stats_scale = max(w // 440, 1)
        self.stat_gap = th(self.stats_scale) * 3 // 2
        self.tag_scale = self.stats_scale + 1
        sub_h, tag_h = th(self.sub_scale), th(self.tag_scale)

        # no HUD in the lab's frame: the card has the whole height
        gap, top = h // 48, h // 40
        bottom = int(F32(h) * F32(0.90))
        fixed = sub_h + 3 * self.stat_gap + tag_h + 4 * gap  # everything but the wordmark
        # the wordmark needs 10.5 blocks of height (7 and half a reflection),
        # and never more than 45% of the width
        scale = idiv((bottom - top - fixed) * 2, 21)
        scale = min(scale, w * 9 // 20 // tw(self.lang, 1))
        self.logo_scale = scale = max(scale, 3)
        self.logo_w, self.text_h = tw(self.lang, scale), th(scale)
        self.refl_h = self.text_h // 2
        self.logo_x = idiv(w - self.logo_w, 2)

        y0 = top + idiv(bottom - top - (self.text_h + self.refl_h + fixed), 2)
        self.logo_y = y0
        self.floor_y = y0 + self.text_h
        self.sub_y = self.floor_y + self.refl_h + gap
        self.stats_y = self.sub_y + sub_h + gap
        self.tag_y = self.stats_y + 3 * self.stat_gap + gap
        self.sub_x = idiv(w - tw(self.sub, self.sub_scale), 2)
        self.tag_x = idiv(w - tw(TAG, self.tag_scale), 2)

        # the glow: an ellipse 1.6x wider than tall, and the box it can reach
        self.glow_x = F32(w) * F32(0.5)
        self.glow_y = F32(self.logo_y) + F32(self.text_h) * F32(0.55)
        self.glow_r = F32(w) * F32(0.34)
        d = (np.arange(w, dtype=F32) - self.glow_x) / self.glow_r * F32(1.6)
        self.dx2 = d * d
        span_x, span_y = int(self.glow_r / F32(1.6)), int(self.glow_r)
        self.box = (max(int(self.glow_y) - span_y, 0), min(int(self.glow_y) + span_y, h),
                    max(int(self.glow_x) - span_x, 0), min(int(self.glow_x) + span_x, w))

        # the background ramp, one colour per row
        ys = np.arange(h, dtype=F32)
        u = ys * (F32(1) / F32(h))
        cy = F32(h) * F32(0.5)
        ny = (ys - cy) / cy
        vig = np.maximum(F32(1) - F32(0.32) * ny * ny, F32(0.45))
        self.ramp = canvas.from_float(((F32(0.02) + F32(0.09) * u * u) * vig).astype(np.float64),
                                      ((F32(0.01) + F32(0.02) * u) * vig).astype(np.float64),
                                      ((F32(0.06) + F32(0.14) * u) * vig).astype(np.float64))[:, None]
        # the floor line's glow, brightest in the middle
        fade = F32(1) - np.abs(np.arange(w, dtype=F32) - self.glow_x) / (F32(w) * F32(0.52))
        self.floor_x = np.flatnonzero(fade > 0)
        fade = fade[self.floor_x]
        glow = fade * fade * F32(0.9)
        self.floor_add = [F32(k) * glow for k in (210, 110, 230)]

    def prepare(self, s):
        self.t = s.t

    def draw(self, fb):
        w, h, t = self.w, self.h, self.t
        fb[:] = self.ramp

        # the pool of light, only where it reaches
        by0, by1, bx0, bx1 = self.box
        pulse = F32(0.88) + F32(0.12) * F32(math.sin(t * 2.2))
        dy = (np.arange(by0, by1, dtype=F32) - self.glow_y) / self.glow_r
        d2 = self.dx2[bx0:bx1] + (dy * dy)[:, None]
        g = F32(1) - d2
        g *= g * pulse
        box = fb[by0:by1, bx0:bx1]
        r, gg, b = canvas.unpack(box)
        lit = pack_clamped(r + (g * F32(120)).astype(np.int32), gg + (g * F32(22)).astype(np.int32),
                           b + (g * F32(100)).astype(np.int32))
        np.copyto(box, lit, where=d2 < 1)

        # stars, twinkling slowly
        for i, (sx, sy, sb) in enumerate(self.stars):
            x, y = int(sx * F32(w)), int(sy * F32(h))
            if 0 <= y < h and 0 <= x < w:
                tw = F32(0.55) + F32(0.45) * F32(math.sin(t * 1.7 + i * 0.7))
                canvas.additive(fb, y, x, 0xFF40306A, int(F32(70) * sb * tw))

        # the polished floor line the reflection lands on
        if 0 <= self.floor_y < h:
            row = fb[self.floor_y]
            # float32 sums, as in Go: an int64 channel plus a float32 would be float64
            r, gg, b = (ch.astype(F32) + add for ch, add in zip(canvas.unpack(row[self.floor_x]), self.floor_add))
            row[self.floor_x] = pack_clamped(r.astype(np.int64), gg.astype(np.int64), b.astype(np.int64))

        # @excerpt FINALE
        scale, lang = self.logo_scale, self.lang
        # the letters bounce off the floor line, never below it
        offs = [int((math.sin(t * 2.4 + i * 0.75) - 1) * scale / 6) for i in range(len(lang))]
        # reflection first, so the wordmark sits on top of its own light
        canvas.draw_text_reflect(fb, self.logo_x, self.floor_y, lang, scale, TOP, BOT, offs, 125, self.refl_h)
        # a one-pixel dark edge keeps the letters off the background
        canvas.draw_text_outline(fb, self.logo_x, self.logo_y, lang, scale, 0xFF200A18, offs)
        canvas.draw_text_gradient(fb, self.logo_x, self.logo_y, lang, scale, TOP, MID, BOT, offs, True)
        # @end

        # subtitle with rules either side
        sub_w = canvas.text_width(self.sub, self.sub_scale)
        ly = self.sub_y + canvas.text_height(self.sub_scale) // 2
        canvas.hline(fb, self.sub_x - sub_w // 3 - 14, ly, sub_w // 3, 0xFF9050A0)
        canvas.hline(fb, self.sub_x + sub_w + 14, ly, sub_w // 3, 0xFF9050A0)
        canvas.draw_text(fb, self.sub_x, self.sub_y, self.sub, self.sub_scale, 0xFFF0E0FF)

        # the closing numbers, and the punchline
        for i, line in enumerate(LINES):
            lw = canvas.text_width(line, self.stats_scale)
            canvas.draw_text(fb, idiv(w - lw, 2), self.stats_y + i * self.stat_gap, line, self.stats_scale, 0xFFC0B0E0)
        canvas.draw_text(fb, self.tag_x, self.tag_y, TAG, self.tag_scale, 0xFFB0E0FF)


def pack_clamped(r, g, b):
    return canvas.pack(np.minimum(r, 255), np.minimum(g, 255), np.minimum(b, 255))
