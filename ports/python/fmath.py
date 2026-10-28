"""The numeric shortcuts every effect leans on: Go's sine table and xorshift32.

Go's float32 maths is reproduced with NumPy's float32: arrays of dtype
float32 and np.float32 scalars both round after every operation, exactly
like Go. NumPy 2 (NEP 50) keeps it that way: a Python float or int meeting a
float32 is converted to float32 first, as Go converts an untyped constant.
The trap is the other direction: a float64 *array or scalar* (np.float64,
the result of math.sin, anything from np.arange without a dtype) silently
promotes the whole expression to float64. So every constant that matters is
spelled F32(...) and every array is born float32.
"""

import numpy as np

F32 = np.float32

TAB_BITS = 13
TAB_SIZE = 1 << TAB_BITS
TAB_MASK = TAB_SIZE - 1

# Go multiplies a float32 by the untyped constant TabSize/(2*Pi), which the
# compiler rounds to float32 first.
INV_2PI = F32(TAB_SIZE / (2 * np.pi))
TWO_PI = F32(2 * np.pi)

_angles = 2 * np.pi * np.arange(TAB_SIZE + 1, dtype=np.float64) / TAB_SIZE
SIN_TAB = np.sin(_angles).astype(F32)
COS_TAB = np.cos(_angles).astype(F32)
# guarantee a full period overflows exactly
SIN_TAB[TAB_SIZE] = SIN_TAB[0]
COS_TAB[TAB_SIZE] = COS_TAB[0]

# The same tables as lists of np.float32 scalars, for plain-Python loops:
# indexing a list is several times cheaper than indexing an array, and the
# items stay float32, so the arithmetic on them does too.
SIN_LIST = list(SIN_TAB)
COS_LIST = list(COS_TAB)


def _index(a, scale):
    # astype truncates toward zero, like Go's int(); `&` wraps negative
    # indices the way two's complement does in Go.
    return (a * scale).astype(np.intp) & TAB_MASK


# Vectorised: a is a float32 array (or a 0-d one).
def sin(a):
    """sin(a) from the table, a in radians."""
    return SIN_TAB[_index(a, INV_2PI)]


def cos(a):
    return COS_TAB[_index(a, INV_2PI)]


def sin01(t):
    """sin(2*pi*t) for t in turns."""
    return SIN_TAB[_index(t, TAB_SIZE)]


def cos01(t):
    return COS_TAB[_index(t, TAB_SIZE)]


# Scalar: a is one np.float32. int() on it truncates like Go.
def sin1(a):
    return SIN_LIST[int(a * INV_2PI) & TAB_MASK]


def cos1(a):
    return COS_LIST[int(a * INV_2PI) & TAB_MASK]


def sin01_1(t):
    return SIN_LIST[int(t * TAB_SIZE) & TAB_MASK]


def atan2_turns(y, x):
    """atan2 as a float32 fraction of a turn, in [0, 1); arrays.

    Go computes math.Atan2 in float64 and rounds; np.arctan2 on float32
    arrays would call atan2f instead and give different last bits.
    """
    a = np.arctan2(y.astype(np.float64), x.astype(np.float64)).astype(F32)
    return a / TWO_PI + F32(0.5)


class Rng:
    """xorshift32, the only randomness that shapes the image.

    Python ints never overflow, so the left shifts are masked back to 32
    bits by hand; the right shift is the logical one Go uses on a uint32.
    """

    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFF  # must never be zero

    def next(self):
        x = self.state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self.state = x
        return x

    def float32(self):
        # 24 bits times 2**-24 is exact in a double, and so in a float32
        return F32((self.next() >> 8) * (1.0 / 16777216))

    def floats(self, n):
        """The next n float32() values, as an array."""
        return np.array([self.next() >> 8 for _ in range(n)], dtype=F32) * F32(1.0 / 16777216)
