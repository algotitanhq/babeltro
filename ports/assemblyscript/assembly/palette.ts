// 256-entry colour ramps built from a handful of stops, in f64 like Go.

/** Stops are flat: pos, r, g, b, pos, r, g, b, … */
function ramp(s: StaticArray<f64>): StaticArray<u32> {
  const n = s.length >> 2;
  const p = new StaticArray<u32>(256);
  for (let i = 0; i < 256; i++) {
    const t: f64 = <f64>i / 255;
    // find the segment containing t
    let a = 0;
    let b = n - 1;
    for (let k = 0; k < n - 1; k++) {
      if (t >= s[k << 2] && t <= s[(k + 1) << 2]) {
        a = k;
        b = k + 1;
        break;
      }
    }
    const ap = s[a << 2];
    const bp = s[b << 2];
    let u: f64 = 0;
    if (bp > ap) u = (t - ap) / (bp - ap);
    u = clamp01(u);
    // smoothstep keeps gradients from banding
    u = u * u * (3.0 - 2.0 * u);
    const r: f64 = s[(a << 2) + 1] + (s[(b << 2) + 1] - s[(a << 2) + 1]) * u;
    const g: f64 = s[(a << 2) + 2] + (s[(b << 2) + 2] - s[(a << 2) + 2]) * u;
    const bl: f64 = s[(a << 2) + 3] + (s[(b << 2) + 3] - s[(a << 2) + 3]) * u;
    p[i] = 0xff000000 | (<u32>f2b(bl) << 16) | (<u32>f2b(g) << 8) | <u32>f2b(r);
  }
  return p;
}

export function clamp01(v: f64): f64 {
  if (v < 0) return 0;
  if (v > 1) return 1;
  return v;
}

export function f2b(v: f64): u8 {
  if (v <= 0) return 0;
  if (v >= 1) return 255;
  return <u8>(v * 255 + 0.5);
}

/** The colour at t in [0,1], clamped. */
export function at(p: StaticArray<u32>, t: f64): u32 {
  let i = <i32>(t * 255);
  if (i < 0) i = 0;
  else if (i > 255) i = 255;
  return unchecked(p[i]);
}

// Sunset: deep violet to hot orange to cream.
export const SUNSET = ramp([
  0.00, 0.02, 0.00, 0.06,
  0.18, 0.25, 0.02, 0.38,
  0.38, 0.72, 0.05, 0.45,
  0.56, 0.98, 0.25, 0.22,
  0.74, 1.00, 0.62, 0.15,
  0.88, 1.00, 0.93, 0.55,
  1.00, 1.00, 1.00, 0.96,
]);

// Ice: the tunnel and the mandelbrot.
export const ICE = ramp([
  0.00, 0.00, 0.00, 0.03,
  0.25, 0.00, 0.10, 0.30,
  0.50, 0.00, 0.55, 0.85,
  0.72, 0.35, 0.90, 1.00,
  0.90, 0.80, 1.00, 1.00,
  1.00, 1.00, 1.00, 1.00,
]);

// Ember: the fire.
export const EMBER = ramp([
  0.00, 0.00, 0.00, 0.00,
  0.20, 0.25, 0.00, 0.00,
  0.45, 0.80, 0.10, 0.00,
  0.68, 1.00, 0.45, 0.00,
  0.85, 1.00, 0.80, 0.15,
  1.00, 1.00, 1.00, 0.85,
]);

// HSL2RGB has three results; AssemblyScript has no tuples, so they land in
// these globals (a multi-value return would need a struct on the heap).
export let outR: f64 = 0;
export let outG: f64 = 0;
export let outB: f64 = 0;

/** hue/sat/light (all 0..1) to RGB components 0..1, in outR/outG/outB. */
export function hsl2rgb(h: f64, s: f64, l: f64): void {
  if (s == 0) {
    outR = l;
    outG = l;
    outB = l;
    return;
  }
  const q: f64 = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p: f64 = 2 * l - q;
  outR = hue2rgb(p, q, h + 1.0 / 3);
  outG = hue2rgb(p, q, h);
  outB = hue2rgb(p, q, h - 1.0 / 3);
}

function hue2rgb(p: f64, q: f64, t: f64): f64 {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1.0 / 6) return p + (q - p) * 6 * t;
  if (t < 1.0 / 2) return q;
  if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
  return p;
}
