// 256-entry colour ramps built from a handful of stops. Effects index these
// ramps instead of doing per-pixel colour maths: pay once at load, then look
// up. All of this is float64 in Go, which is plain JS number arithmetic.

/** One colour anchor at position pos in [0,1]. */
export const S = (pos, r, g, b) => ({ pos, r, g, b });

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

/** A float in [0,1] to a byte, rounded; `| 0` is Go's uint8() truncation. */
export function f2b(v) {
  if (v <= 0) return 0;
  if (v >= 1) return 255;
  return (v * 255 + 0.5) | 0;
}

/** Interpolates the stops into a ready-to-index Uint32Array(256). */
export function makePalette(...stops) {
  const p = new Uint32Array(256);
  if (stops.length === 0) return p;
  for (let i = 0; i < 256; i++) {
    const t = i / 255;
    // find the segment containing t
    let a = stops[0];
    let b = stops[stops.length - 1];
    for (let k = 0; k < stops.length - 1; k++) {
      if (t >= stops[k].pos && t <= stops[k + 1].pos) {
        a = stops[k];
        b = stops[k + 1];
        break;
      }
    }
    let u = 0;
    if (b.pos > a.pos) u = (t - a.pos) / (b.pos - a.pos);
    u = clamp01(u);
    // smoothstep keeps gradients from banding
    u = u * u * (3 - 2 * u);
    const r = a.r + (b.r - a.r) * u;
    const g = a.g + (b.g - a.g) * u;
    const bl = a.b + (b.b - a.b) * u;
    p[i] = 0xff000000 | (f2b(bl) << 16) | (f2b(g) << 8) | f2b(r);
  }
  return p;
}

/** The colour at t in [0,1], clamped. */
export function paletteAt(p, t) {
  let i = (t * 255) | 0;
  if (i < 0) i = 0;
  else if (i > 255) i = 255;
  return p[i];
}

/** Hue/saturation/lightness (all 0..1) to an [r, g, b] triple, 0..1. */
export function hsl2rgb(h, s, l) {
  if (s === 0) return [l, l, l];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  return [hue2rgb(p, q, h + 1 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1 / 3)];
}

function hue2rgb(p, q, t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 1 / 2) return q;
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}

// Sunset: the demo's signature ramp. Deep violet to hot orange to cream.
export const SUNSET = makePalette(
  S(0.0, 0.02, 0.0, 0.06),
  S(0.18, 0.25, 0.02, 0.38),
  S(0.38, 0.72, 0.05, 0.45),
  S(0.56, 0.98, 0.25, 0.22),
  S(0.74, 1.0, 0.62, 0.15),
  S(0.88, 1.0, 0.93, 0.55),
  S(1.0, 1.0, 1.0, 0.96),
);

// Ice: cold counterpart used by the tunnel and the mandelbrot.
export const ICE = makePalette(
  S(0.0, 0.0, 0.0, 0.03),
  S(0.25, 0.0, 0.1, 0.3),
  S(0.5, 0.0, 0.55, 0.85),
  S(0.72, 0.35, 0.9, 1.0),
  S(0.9, 0.8, 1.0, 1.0),
  S(1.0, 1.0, 1.0, 1.0),
);

// Ember: fire ramp.
export const EMBER = makePalette(
  S(0.0, 0.0, 0.0, 0.0),
  S(0.2, 0.25, 0.0, 0.0),
  S(0.45, 0.8, 0.1, 0.0),
  S(0.68, 1.0, 0.45, 0.0),
  S(0.85, 1.0, 0.8, 0.15),
  S(1.0, 1.0, 1.0, 0.85),
);
