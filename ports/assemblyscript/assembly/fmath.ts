// Numeric shortcuts every effect leans on: a sine table and xorshift32.
//
// AssemblyScript has Go's number types: f32 and f64 are distinct, and an f32
// expression is computed in f32 by the wasm instructions themselves. What it
// adds is contextual typing of literals: in `x * 0.5` with x an f32, 0.5 is an
// f32 constant, exactly like Go's untyped constants. The trap is the other
// way round: a literal written first, with no f32 context, is an f64 and
// drags the expression into f64. So every float local here has its type.

export const TAB_BITS: i32 = 13;
export const TAB_SIZE: i32 = 1 << TAB_BITS;
export const TAB_MASK: i32 = TAB_SIZE - 1;
// Go rounds the untyped constant TabSize/(2*Pi) to float32
const INV_2PI: f32 = <f32>(<f64>TAB_SIZE / (2.0 * Math.PI));
const TWO_PI_F32: f32 = <f32>(2.0 * Math.PI);

// StaticArray: a fixed length known to the type, laid out as a plain run of
// f32s. Indexing it still checks the bounds; unchecked() drops the check.
export const SIN_TAB = new StaticArray<f32>(TAB_SIZE + 1);
export const COS_TAB = new StaticArray<f32>(TAB_SIZE + 1);
for (let i = 0; i <= TAB_SIZE; i++) {
  const a: f64 = (2.0 * Math.PI * <f64>i) / <f64>TAB_SIZE;
  SIN_TAB[i] = <f32>Math.sin(a);
  COS_TAB[i] = <f32>Math.cos(a);
}
// guarantee a full period overflows exactly
SIN_TAB[TAB_SIZE] = SIN_TAB[0];
COS_TAB[TAB_SIZE] = COS_TAB[0];

// The index is masked into [0, TAB_SIZE), so the check can never fire:
// unchecked() is safe by construction.

/** sin(a) from the table; a in radians. */
// @ts-ignore: decorator
@inline export function sin(a: f32): f32 {
  return unchecked(SIN_TAB[<i32>(a * INV_2PI) & TAB_MASK]);
}

/** cos(a) from the table. */
// @ts-ignore: decorator
@inline export function cos(a: f32): f32 {
  return unchecked(COS_TAB[<i32>(a * INV_2PI) & TAB_MASK]);
}

/** sin(2*pi*t) for t in turns. */
// @ts-ignore: decorator
@inline export function sin01(t: f32): f32 {
  return unchecked(SIN_TAB[<i32>(t * <f32>TAB_SIZE) & TAB_MASK]);
}

/** atan2(y, x) as a fraction of a full turn, in [0,1). */
export function atan2Turns(y: f32, x: f32): f32 {
  const a = <f32>Math.atan2(<f64>y, <f64>x);
  return a / TWO_PI_F32 + 0.5;
}

/** The turn fraction of atan2 for every pixel of a w×h grid (the tunnel). */
export function atan2Tab(w: i32, h: i32): StaticArray<f32> {
  const cx = <f32>w / 2;
  const cy = <f32>h / 2;
  const tab = new StaticArray<f32>(w * h);
  for (let y = 0; y < h; y++) {
    const dy = <f32>y - cy;
    for (let x = 0; x < w; x++) {
      unchecked((tab[y * w + x] = atan2Turns(dy, <f32>x - cx)));
    }
  }
  return tab;
}

/**
 * scale/(r+softness) for every pixel of a w×h grid (the tunnel). The
 * softness term tames the singularity at the centre.
 */
export function distInvTab(w: i32, h: i32, scale: f32, softness: f32): StaticArray<f32> {
  const cx = <f32>w / 2;
  const cy = <f32>h / 2;
  const tab = new StaticArray<f32>(w * h);
  for (let y = 0; y < h; y++) {
    const dy = <f32>y - cy;
    for (let x = 0; x < w; x++) {
      const dx = <f32>x - cx;
      // f32.sqrt is correctly rounded: Go's float32(math.Sqrt(float64(v)))
      const r: f32 = Mathf.sqrt(dx * dx + dy * dy) + softness;
      unchecked((tab[y * w + x] = scale / r));
    }
  }
  return tab;
}

/**
 * xorshift32, the only source of randomness that shapes the image. u32
 * arithmetic wraps and `>>` on a u32 is the logical shift, as in Go.
 */
export class Rng {
  constructor(public state: u32) {}

  next(): u32 {
    let x = this.state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    this.state = x;
    return x;
  }

  /** A float in [0, 1) from the top 24 bits: the conversion is exact. */
  float32(): f32 {
    return <f32>(this.next() >> 8) * (1.0 / 16777216);
  }
}
