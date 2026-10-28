"""256-entry colour ramps built from a handful of stops.

All of this is float64 in Go, which is what a Python float is, so it is a
line-for-line transcription. Each palette ends up as a uint32 array that the
effects index with a whole image of indices at once.
"""

import numpy as np


def clamp01(v):
    return 0.0 if v < 0 else 1.0 if v > 1 else v


def f2b(v):
    """A float in [0, 1] to a byte, rounded; int() truncates like uint8()."""
    if v <= 0:
        return 0
    if v >= 1:
        return 255
    return int(v * 255 + 0.5)


def make(*stops):
    """Interpolates (pos, r, g, b) stops into a ready-to-index ramp."""
    pal = np.zeros(256, dtype=np.uint32)
    for i in range(256):
        t = i / 255
        # find the segment containing t
        a, b = stops[0], stops[-1]
        for lo, hi in zip(stops, stops[1:]):
            if lo[0] <= t <= hi[0]:
                a, b = lo, hi
                break
        u = (t - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 0.0
        u = clamp01(u)
        # smoothstep keeps gradients from banding
        u = u * u * (3 - 2 * u)
        r, g, bl = (f2b(a[k] + (b[k] - a[k]) * u) for k in (1, 2, 3))
        pal[i] = 0xFF000000 | bl << 16 | g << 8 | r
    return pal


def at(pal, t):
    """The colour at t in [0, 1], clamped."""
    return pal[min(max(int(t * 255), 0), 255)]


def hsl2rgb(h, s, l):
    """Hue/saturation/lightness to r, g, b, all 0..1. Works on arrays too."""
    q = np.where(l < 0.5, l * (1 + s), l + s - l * s)
    p = 2 * l - q
    return _hue2rgb(p, q, h + 1 / 3), _hue2rgb(p, q, h), _hue2rgb(p, q, h - 1 / 3)


def _hue2rgb(p, q, t):
    t = np.where(t < 0, t + 1, t)
    t = np.where(t > 1, t - 1, t)
    return np.select(
        [t < 1 / 6, t < 1 / 2, t < 2 / 3],
        [p + (q - p) * 6 * t, q, p + (q - p) * (2 / 3 - t) * 6],
        p,
    )


# Sunset: the demo's signature ramp. Deep violet to hot orange to cream.
SUNSET = make(
    (0.00, 0.02, 0.00, 0.06),
    (0.18, 0.25, 0.02, 0.38),
    (0.38, 0.72, 0.05, 0.45),
    (0.56, 0.98, 0.25, 0.22),
    (0.74, 1.00, 0.62, 0.15),
    (0.88, 1.00, 0.93, 0.55),
    (1.00, 1.00, 1.00, 0.96),
)

# Ice: cold counterpart used by the tunnel and the mandelbrot.
ICE = make(
    (0.00, 0.00, 0.00, 0.03),
    (0.25, 0.00, 0.10, 0.30),
    (0.50, 0.00, 0.55, 0.85),
    (0.72, 0.35, 0.90, 1.00),
    (0.90, 0.80, 1.00, 1.00),
    (1.00, 1.00, 1.00, 1.00),
)

# Ember: fire ramp.
EMBER = make(
    (0.00, 0.00, 0.00, 0.00),
    (0.20, 0.25, 0.00, 0.00),
    (0.45, 0.80, 0.10, 0.00),
    (0.68, 1.00, 0.45, 0.00),
    (0.85, 1.00, 0.80, 0.15),
    (1.00, 1.00, 1.00, 0.85),
)
