// Numeric shortcuts every effect leans on: a sine table, the float32 helpers
// Go gets for free from its type system, and the xorshift32 generator.
//
// JavaScript has a single number type, a float64. Go's float32 arithmetic is
// reproduced by rounding every result with Math.fround: for +, -, *, / and
// sqrt, computing in float64 and rounding once gives exactly the float32
// result, so f32(a * b) below *is* a float32 multiply.

export const f32 = Math.fround;

export const TAB_BITS = 13;
export const TAB_SIZE = 1 << TAB_BITS;
export const TAB_MASK = TAB_SIZE - 1;

// Go multiplies a float32 by the untyped constant TabSize/(2*Pi), which the
// compiler rounds to float32 first; so do we.
export const INV_2PI = f32(TAB_SIZE / (2 * Math.PI));
const TWO_PI_F32 = f32(2 * Math.PI);

// The tables hold float32 values: a Float32Array rounds on store.
export const SIN_TAB = new Float32Array(TAB_SIZE + 1);
export const COS_TAB = new Float32Array(TAB_SIZE + 1);
for (let i = 0; i <= TAB_SIZE; i++) {
  const a = (2 * Math.PI * i) / TAB_SIZE;
  SIN_TAB[i] = Math.sin(a);
  COS_TAB[i] = Math.cos(a);
}
// guarantee a full period overflows exactly
SIN_TAB[TAB_SIZE] = SIN_TAB[0];
COS_TAB[TAB_SIZE] = COS_TAB[0];

// `| 0` truncates toward zero like Go's int(x), and `& TAB_MASK` wraps
// negative indices the same way two's complement does in Go. Every argument
// the effects pass stays far inside the int32 range `| 0` can represent.

/** sin(a) from the table; a is a float32 in radians. */
export function sin(a) {
  return SIN_TAB[(f32(a * INV_2PI) | 0) & TAB_MASK];
}

/** cos(a) from the table. */
export function cos(a) {
  return COS_TAB[(f32(a * INV_2PI) | 0) & TAB_MASK];
}

/** sin(2*pi*t) for t in turns. Multiplying by 8192 is exact: no rounding. */
export function sin01(t) {
  return SIN_TAB[((t * TAB_SIZE) | 0) & TAB_MASK];
}

/** cos(2*pi*t) for t in turns. */
export function cos01(t) {
  return COS_TAB[((t * TAB_SIZE) | 0) & TAB_MASK];
}

/** float32 square root. */
export function sqrt32(x) {
  return f32(Math.sqrt(x));
}

/** atan2(y, x) as a float32 fraction of a full turn, in [0,1). */
export function atan2Turns(y, x) {
  const a = f32(Math.atan2(y, x));
  return f32(f32(a / TWO_PI_F32) + 0.5);
}

/**
 * The turn fraction of atan2 for every pixel of a w×h grid, used by the
 * tunnel. Only recomputed when the framebuffer is resized.
 */
export function atan2Tab(w, h) {
  const cx = f32(w / 2);
  const cy = f32(h / 2);
  const tab = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    const dy = f32(y - cy);
    for (let x = 0; x < w; x++) {
      tab[y * w + x] = atan2Turns(dy, f32(x - cx));
    }
  }
  return tab;
}

/**
 * scale/(r+softness) for every pixel of a w×h grid, used by the tunnel. The
 * softness term tames the singularity at the centre, which would otherwise
 * turn into aliasing noise.
 */
export function distInvTab(w, h, scale, softness) {
  const cx = f32(w / 2);
  const cy = f32(h / 2);
  const tab = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    const dy = f32(y - cy);
    for (let x = 0; x < w; x++) {
      const dx = f32(x - cx);
      const r = f32(sqrt32(f32(f32(dx * dx) + f32(dy * dy))) + softness);
      tab[y * w + x] = scale / r; // rounded to float32 by the store
    }
  }
  return tab;
}

/**
 * Rng is a xorshift32 generator, the only source of randomness that shapes
 * the image, because every port must reproduce the same sequence bit for bit.
 *
 * JS bitwise operators work on int32: `<<` wraps exactly like a uint32 shift,
 * `>>>` is the unsigned (logical) right shift Go uses on a uint32, and the
 * final `>>> 0` reads the bits back as an unsigned number.
 */
export class Rng {
  constructor(seed) {
    this.state = seed >>> 0; // must never be zero
  }

  /** Advances the generator and returns the new state, a uint32. */
  next() {
    let x = this.state;
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    this.state = x >>> 0;
    return this.state;
  }

  /** A float32 in [0, 1) from the top 24 bits: the product is exact. */
  float32() {
    return (this.next() >>> 8) * (1 / 16777216);
  }
}
