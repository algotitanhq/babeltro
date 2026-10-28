// Grid: the synthwave staple. An infinite checker floor rushes at the camera
// under a banded sun. The floor is a per-pixel perspective divide, and the
// lines come from the fractional part of the world coordinates.

import { f32, sqrt32 } from '../lib/fmath.js';
import { fromFloat, clamp01 } from '../lib/canvas.js';

// float32 constants, rounded once
const C = {
  horizon: f32(0.52), sunUp: f32(0.13), sunR: f32(0.16), sunCut: f32(0.45),
  sunEdge: f32(0.025), floorK: f32(0.55), depthK: f32(2.5), speed: f32(5.5),
  lwX: f32(0.022), lwZ0: f32(0.014), lwZ1: f32(0.024), fog: f32(0.004),
  haze: f32(0.12), offX: f32(0.37), fade: f32(1.5),
  glowR: f32(0.55), glowG: f32(0.35), glowB: f32(0.75),
  floorR: f32(0.02), floorG: f32(0.01), floorB: f32(0.06),
};

export class Grid {
  constructor() {
    this.w = 0;
    this.h = 0;
    this.t = 0;
    this.horizon = 0;
    this.asp = 0;
  }

  resize(w, h) {
    this.w = w;
    this.h = h;
    this.horizon = f32(h * C.horizon);
    this.asp = f32(h / w);
  }

  prepare(s) {
    this.t = f32(s.beat);
  }

  draw(fb) {
    const { w, h, pix } = fb;
    const { horizon, t, asp } = this;
    const cx = f32(w * 0.5);

    // sun parameters
    const sunY = f32(horizon - f32(h * C.sunUp));
    const sunR = f32(h * C.sunR);
    const sunX = cx;
    const sunTop = f32(sunY - sunR);
    const sunCut = f32(sunY - f32(sunR * C.sunCut));
    const sunEdge = f32(sunR * C.sunEdge);
    const sunBottom = f32(horizon + 2);

    for (let y = 0; y < h; y++) {
      const row = y * w;
      const fy = y;

      // everything that depends only on the row is hoisted out of the pixel
      // loop; on the floor that is most of the arithmetic
      const sky = clamp01(f32(fy / horizon)); // float64 from here, as in Go
      const skyR = f32(0.03 + 0.18 * sky * sky);
      const skyG = f32(0.01 + 0.05 * sky);
      const skyB = f32(0.08 + 0.22 * sky);

      const onFloor = fy > horizon;
      let floorR = 0, floorG = 0, floorB = 0;
      let baseR = 0, baseG = 0, baseB = 0;
      let kx = 0; // world x per screen pixel on this row
      let dz = 0; // distance below the horizon, in pixels
      let lineZ = 0, fadeX = 0, linePx = 0; // linePx: line width in pixels
      if (onFloor) {
        dz = f32(fy - horizon);
        const z = f32(f32(h * C.floorK) / dz);
        const wz = f32(f32(z * C.depthK) + f32(t * C.speed));
        kx = f32(f32(f32(z / f32(w * 0.5)) * asp) * 2);
        // same aliasing guard as below, but across the row
        fadeX = f32(clamp01(f32(f32(f32(1 / kx) - C.fade) / 2)));
        linePx = f32(f32(2 * C.lwX) / kx);

        // A line narrower than a pixel lands on only every few pixels and
        // reads as a row of bright dots. Widen it to a full pixel and dim it
        // by the area it actually covers: the same light, spread out.
        const period = f32(f32(dz * dz) / f32(1.375 * h)); // pixels per unit of wz
        let lwZ = f32(C.lwZ0 + f32(C.lwZ1 / z));
        let ampZ = 1;
        const minW = f32(0.5 / period);
        if (lwZ < minW) {
          ampZ = f32(lwZ / minW);
          lwZ = minW;
        }
        lineZ = f32(lineGlow(mod1(wz), lwZ) * ampZ);
        // fade lines that have shrunk below a couple of pixels per period,
        // otherwise the horizon boils with aliasing
        lineZ = f32(lineZ * f32(clamp01(f32(f32(period - C.fade) / 2))));
        const fog = f32(clamp01(f32(1 / f32(1 + f32(f32(z * z) * C.fog)))));
        lineZ = f32(lineZ * fog);

        floorR = C.floorR;
        floorG = C.floorG;
        floorB = C.floorB;
        const haze = clamp01(f32(dz / f32(h * C.haze)));
        if (haze < 1) {
          // the haze itself is the glow near the horizon
          floorR = f32(floorR + f32(0.25 * (1 - haze)));
          floorG = f32(floorG + f32(0.05 * (1 - haze)));
          floorB = f32(floorB + f32(0.35 * (1 - haze)));
        }
        floorR = f32(floorR + f32(C.glowR * lineZ));
        floorG = f32(floorG + f32(C.glowG * lineZ));
        floorB = f32(floorB + f32(C.glowB * lineZ));
        // Each pixel swaps the row's glow for max(row line, column line).
        // Taking the row's glow back out is row-invariant, so it is done once
        // here, with the same float32 roundings as Go's per-pixel version.
        baseR = f32(floorR - f32(C.glowR * lineZ));
        baseG = f32(floorG - f32(C.glowG * lineZ));
        baseB = f32(floorB - f32(C.glowB * lineZ));
      }

      // sun: bounding box test first, then the expensive circle only there
      const dyc = f32(fy - sunY);
      const sunRow = dyc > -sunR && dyc < sunR && fy < sunBottom;
      let stripe = false;
      let sr = 0, sg = 0, sb = 0;
      if (sunRow) {
        stripe = fy > sunCut && y % 9 < 4;
        const u = clamp01(f32(f32(fy - sunTop) / f32(2 * sunR)));
        sr = 1;
        sg = f32(0.95 - 0.7 * u);
        sb = f32(0.25 + 0.55 * u);
      }
      const dyc2 = f32(dyc * dyc);

      // @excerpt GRID
      for (let x = 0; x < w; x++) {
        let r = skyR, g = skyG, b = skyB;

        if (sunRow && !stripe) {
          const dx = f32(x - sunX);
          if (dx > -sunR && dx < sunR) {
            const d = sqrt32(f32(f32(dx * dx) + dyc2));
            if (d < sunR) {
              const edge = f32(clamp01(f32(f32(sunR - d) / sunEdge)));
              r = mix(r, sr, edge);
              g = mix(g, sg, edge);
              b = mix(b, sb, edge);
            }
          }
        }

        if (onFloor) {
          // How far this ray slides sideways from one row to the next, in
          // pixels: the line must be at least that wide, and dimmed by the
          // same ratio, or each row shows isolated bright dots.
          const off = Math.abs(f32(x - cx));
          let wPx = linePx;
          const slide = f32(off / dz);
          if (slide > wPx) wPx = slide;
          if (wPx < 1) wPx = 1;
          const gx = mod1(f32(f32(f32(x - cx) * kx) + C.offX));
          const lineX = f32(f32(lineGlow(gx, f32(f32(wPx * kx) * 0.5)) * f32(linePx / wPx)) * fadeX);
          const line = lineZ > lineX ? lineZ : lineX;
          r = f32(baseR + f32(C.glowR * line));
          g = f32(baseG + f32(C.glowG * line));
          b = f32(baseB + f32(C.glowB * line));
        }

        pix[row + x] = fromFloat(r, g, b);
      }
      // @end
    }
  }
}

// mod1 wraps a world coordinate into [0,1). Math.trunc is Go's int()
// conversion without the int32 range limit of `| 0`.
function mod1(v) {
  let m = f32(v - Math.trunc(v));
  if (m < 0) m = f32(m + 1);
  return m;
}

// lineGlow is 1 on the grid line, falling to 0 over width w.
function lineGlow(f, w) {
  const d = f > 0.5 ? f32(1 - f) : f;
  return d < w ? f32(1 - f32(d / w)) : 0;
}

function mix(a, b, t) {
  return f32(a + f32(f32(b - a) * t));
}
