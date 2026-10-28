// Grid: the synthwave staple, an infinite checker floor rushing at the
// camera under a banded sun. The floor is a per-pixel perspective divide and
// the lines come from the fractional part of the world coordinates.
//
// This scene mixes f32 and f64 the most. Go writes every conversion out, and
// so does this port: each f64 step has its own f64 local, because a literal
// that opens an expression inside <f32>(…) or <f64>(…) would take that type.

import { FB, fromFloat } from '../canvas';
import { clamp01 } from '../palette';
import { Effect } from './effect';

export class Grid extends Effect {
  w: i32 = 0;
  h: i32 = 0;
  t: f32 = 0;
  horizon: f32 = 0;
  asp: f32 = 0;

  resize(w: i32, h: i32): void {
    this.w = w;
    this.h = h;
    this.horizon = <f32>h * 0.52;
    this.asp = <f32>h / <f32>w;
  }

  prepare(beat: f64, dt: f64, frame: i32, w: i32, h: i32): void {
    if (w != this.w || h != this.h) this.resize(w, h);
    this.t = <f32>beat;
  }

  draw(fb: FB, y0: i32, y1: i32): void {
    const w = fb.w, h = fb.h;
    const pix = fb.pix;
    const horizon = this.horizon;
    const cx: f32 = <f32>w * 0.5;
    const t = this.t;
    const asp = this.asp;

    // sun parameters
    const sunY: f32 = horizon - <f32>h * 0.13;
    const sunR: f32 = <f32>h * 0.16;
    const sunX = cx;

    for (let y = y0; y < y1; y++) {
      const row = y * w;
      const fy = <f32>y;

      // everything that depends only on the row is hoisted out of the
      // pixel loop; on the floor that is most of the arithmetic
      const sky: f64 = clamp01(<f64>(fy / horizon));
      const skyR64: f64 = 0.03 + 0.18 * sky * sky;
      const skyG64: f64 = 0.01 + 0.05 * sky;
      const skyB64: f64 = 0.08 + 0.22 * sky;
      const skyR = <f32>skyR64, skyG = <f32>skyG64, skyB = <f32>skyB64;

      const onFloor = fy > horizon;
      let floorR: f32 = 0, floorG: f32 = 0, floorB: f32 = 0;
      let kx: f32 = 0; // world x per screen pixel on this row
      let dz: f32 = 0; // distance below the horizon, in pixels
      let lineZ: f32 = 0, fadeX: f32 = 0, lwX: f32 = 0;
      if (onFloor) {
        dz = fy - horizon;
        const z: f32 = (<f32>h * 0.55) / dz;
        const wz: f32 = z * 2.5 + t * 5.5;
        kx = (z / (<f32>w * 0.5)) * asp * 2.0;
        // same aliasing guard as below, but across the row (clamping an f32
        // in f64 and back is exact, so the clamp is done in f32)
        const fx: f32 = (1 / kx - 1.5) / 2;
        fadeX = clampf(fx);
        lwX = 0.022;

        // A line narrower than a pixel lands on only every few pixels and
        // reads as a row of bright dots. Widen it to a full pixel and dim
        // it by the area it actually covers.
        const period: f32 = (dz * dz) / (1.375 * <f32>h); // pixels per unit of wz
        let lwZ: f32 = 0.014 + 0.024 / z;
        let ampZ: f32 = 1;
        const minW: f32 = 0.5 / period;
        if (lwZ < minW) {
          ampZ = lwZ / minW;
          lwZ = minW;
        }
        lineZ = lineGlow(mod1(wz), lwZ) * ampZ;
        // fade lines that have shrunk below a couple of pixels per period
        lineZ *= clampf((period - 1.5) / 2);

        const fog: f32 = 1.0 / (1 + z * z * 0.004);
        lineZ *= clampf(fog);

        floorR = 0.02;
        floorG = 0.01;
        floorB = 0.06;
        const haze: f64 = clamp01(<f64>(dz / (<f32>h * 0.12)));
        if (haze < 1) {
          const hr: f64 = 0.25 * (1 - haze);
          const hg: f64 = 0.05 * (1 - haze);
          const hb: f64 = 0.35 * (1 - haze);
          floorR += <f32>hr;
          floorG += <f32>hg;
          floorB += <f32>hb;
        }
        // the haze itself is the glow near the horizon; both Go branches add it
        floorR += 0.55 * lineZ;
        floorG += 0.35 * lineZ;
        floorB += 0.75 * lineZ;
      }

      // sun: bounding box test first, then the circle only there
      const dyc: f32 = fy - sunY;
      const sunRow = dyc > -sunR && dyc < sunR && fy < horizon + 2;
      let stripe = false;
      let sr: f32 = 0, sg: f32 = 0, sb: f32 = 0;
      if (sunRow) {
        stripe = fy > sunY - sunR * 0.45 && <i32>fy % 9 < 4;
        const uf: f32 = (fy - (sunY - sunR)) / (2 * sunR);
        const u: f64 = clamp01(<f64>uf);
        const sg64: f64 = 0.95 - 0.7 * u;
        const sb64: f64 = 0.25 + 0.55 * u;
        sr = 1.0;
        sg = <f32>sg64;
        sb = <f32>sb64;
      }
      // Go subtracts the row's line glow again for every pixel; the
      // difference is per row, with the same roundings
      const baseR: f32 = floorR - 0.55 * lineZ;
      const baseG: f32 = floorG - 0.35 * lineZ;
      const baseB: f32 = floorB - 0.75 * lineZ;

      // @excerpt GRID
      for (let x = 0; x < w; x++) {
        let r = skyR, gg = skyG, b = skyB;

        if (sunRow && !stripe) {
          const dx: f32 = <f32>x - sunX;
          if (dx > -sunR && dx < sunR) {
            const d = Mathf.sqrt(dx * dx + dyc * dyc);
            if (d < sunR) {
              const edge = clampf((sunR - d) / (sunR * 0.025));
              r = mix(r, sr, edge);
              gg = mix(gg, sg, edge);
              b = mix(b, sb, edge);
            }
          }
        }

        if (onFloor) {
          // How far this ray slides sideways between one row and the next:
          // the line must be at least that wide, and dimmed by the same
          // ratio, or each row shows isolated bright dots.
          const off = Mathf.abs(<f32>x - cx);
          let wPx: f32 = (2 * lwX) / kx;
          const slide: f32 = off / dz;
          if (slide > wPx) wPx = slide;
          if (wPx < 1) wPx = 1;
          const lineX: f32 =
            lineGlow(mod1((<f32>x - cx) * kx + 0.37), wPx * kx * 0.5) *
            ((2 * lwX) / kx / wPx) * fadeX;
          const line = lineZ > lineX ? lineZ : lineX;
          r = baseR + 0.55 * line;
          gg = baseG + 0.35 * line;
          b = baseB + 0.75 * line;
        }

        unchecked((pix[row + x] = fromFloat(<f64>r, <f64>gg, <f64>b)));
      }
      // @end
    }
  }
}

// @ts-ignore: decorator
@inline function clampf(v: f32): f32 {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}

// Go's v - float32(int(v)) wraps into [0,1). Mathf.trunc is the f32.trunc
// instruction: the same value with no float→int→float round trip.
// @ts-ignore: decorator
@inline function mod1(v: f32): f32 {
  let m: f32 = v - Mathf.trunc(v);
  if (m < 0) m += 1;
  return m;
}

// 1 on the grid line, falling to 0 over width w.
// @ts-ignore: decorator
@inline function lineGlow(f: f32, w: f32): f32 {
  const d: f32 = f > 0.5 ? 1 - f : f;
  return d < w ? 1 - d / w : 0;
}

// @ts-ignore: decorator
@inline function mix(a: f32, b: f32, t: f32): f32 {
  return a + (b - a) * t;
}
