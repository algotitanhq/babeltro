"""The Doom fire: heat seeded on the bottom row, diffused upward with a
random sideways drift.

The catch for NumPy is the random generator. Go draws one xorshift32 value
per burning pixel, in order, and a generator is sequential by nature: value
n+1 needs value n. But xorshift is *linear* over GF(2): each step is a
32×32 bit matrix T, so jumping m values ahead is the matrix T^m, applied
with four table lookups (one per byte of the state). Doubling the jump
gives the start of 2, 4, 8 … lanes in a few array operations; then every
lane steps at once, and a frame's worth of the stream comes out of a few
dozen NumPy calls instead of 100 000 Python ones. Same values, same order.
"""

import numpy as np

import fmath
import palette
from fmath import F32

LANE = 16  # values per lane


def _xorshift(x):
    x ^= (x << 13) & 0xFFFFFFFF
    x ^= x >> 17
    x ^= (x << 5) & 0xFFFFFFFF
    return x


def _tables(cols):
    """A linear map, given by the images of the 32 single bits, as four
    256-entry tables: by linearity, the image of a state is the xor of the
    images of its four bytes."""
    tables = []
    for byte in range(4):
        tab = [0] * 256
        for v in range(1, 256):
            low = v & -v  # each entry is a smaller one plus one bit
            tab[v] = tab[v ^ low] ^ cols[8 * byte + low.bit_length() - 1]
        tables.append(np.array(tab, dtype=np.uint32))
    return tables


def _apply(tables, x):
    t0, t1, t2, t3 = tables
    return t0[x & 255] ^ t1[x >> 8 & 255] ^ t2[x >> 16 & 255] ^ t3[x >> 24]


def _jumps(levels):
    """T^(LANE·2^k) for k = 0, 1, 2 …: each one is the previous one squared."""
    cols = [1 << k for k in range(32)]
    for _ in range(LANE):
        cols = [_xorshift(c) for c in cols]
    out = []
    for _ in range(levels):
        out.append(_tables(cols))
        cols = _apply(out[-1], np.array(cols, dtype=np.uint32)).tolist()
    return out


_JUMPS = _jumps(20)


class XorShiftStream:
    """The xorshift32 sequence of a seed, generated in bulk."""

    def __init__(self, seed):
        self.state = seed
        self.buf = np.zeros(0, dtype=np.uint32)

    def peek(self, n):
        """The next n values, without consuming them."""
        if self.buf.size < n:
            self._extend(max(n - self.buf.size, 1 << 17))
        return self.buf[:n]

    def advance(self, n):
        self.buf = self.buf[n:]

    def _extend(self, n):
        # the starts of 2^k lanes, LANE values apart
        x = np.array([self.state], dtype=np.uint32)
        for jump in _JUMPS:
            if x.size * LANE >= n:
                break
            x = np.concatenate((x, _apply(jump, x)))
        out = np.empty((LANE, x.size), dtype=np.uint32)
        for j in range(LANE):  # every lane steps at once; uint32 shifts wrap like Go's
            x ^= x << 13
            x ^= x >> 17
            x ^= x << 5
            out[j] = x
        fresh = out.T.ravel()  # lane after lane: the sequence in order
        self.state = int(fresh[-1])
        self.buf = np.concatenate((self.buf, fresh))


class Fire:
    def __init__(self):
        self.pal = palette.EMBER
        self.rng = XorShiftStream(0x9E3779B9)
        self.w = self.h = 0

    def resize(self, w, h):
        if (w, h) == (self.w, self.h):
            return
        self.w, self.h = w, h
        # one byte of heat per pixel, plus a copy of each edge pixel either
        # side, so a sideways step off the edge reads the edge (Go clamps)
        self.heat = np.zeros((h, w + 2), dtype=np.uint8)
        self.fx = np.arange(w, dtype=F32) / F32(w)

    def prepare(self, s):
        self.frame = s.frame

    def draw(self, fb):
        w, h, heat = self.w, self.h, self.heat
        # seed the hottest row: a slow wave for an uneven base, noise on top
        t = F32(self.frame) * F32(0.05)
        fx = self.fx
        wave = (F32(0.5) + F32(0.5) * fmath.sin(fx * F32(11) + t) * F32(0.6)
                + F32(0.5) * fmath.sin(fx * F32(23) - t * F32(1.7)) * F32(0.4))
        noise = (self.rng.peek(w) & 31).astype(F32)
        self.rng.advance(w)
        v = F32(150) + wave * F32(90) + noise - F32(16)
        heat[h - 1, 1:-1] = np.clip(v, F32(90), F32(255)).astype(np.uint8)
        heat[h - 1, 0], heat[h - 1, -1] = heat[h - 1, 1], heat[h - 1, -2]

        # at most one random number per pixel; draw them all up front
        r = self.rng.peek(w * h)
        drift = (r % 3).astype(np.intp)  # 0, 1, 2: left, same, right, in padded columns
        decay = (r >> 16 & 1).astype(np.uint8)
        used = 0
        # @excerpt FIRE
        # each row is gathered from the one below, so rows go in order; the
        # pixels of a row are independent, so each row is a few array ops
        for y in range(h - 1, 0, -1):
            src, dst = heat[y], heat[y - 1]
            hot = src[1:-1].nonzero()[0]  # cold pixels draw no random number
            n = hot.size
            v = src[hot + drift[used:used + n]]
            cooled = v - np.minimum(v, decay[used:used + n])  # v - decay, never below 0
            used += n
            dst.fill(0)
            dst[1:-1][hot] = cooled
            dst[0], dst[-1] = dst[1], dst[-2]
        self.rng.advance(used)
        np.take(self.pal, heat[:, 1:-1], out=fb)
        # @end
