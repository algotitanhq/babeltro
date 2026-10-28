// Grid: the synthwave staple, an infinite checker floor rushing at the camera
// under a banded sun. The floor is a per-pixel perspective divide, and the
// lines come from the fractional part of the world coordinates.
//
// This scene mixes float and double the most: Go clamps in double. C++
// promotes implicitly, so the danger runs the other way from Go's: a single
// unsuffixed literal turns a float expression into a double one. Every float
// constant carries its f, and every narrowing back is a visible float(...).
#pragma once

#include <algorithm>
#include <cmath>

#include "fx.hpp"

namespace bb {

class Grid {
public:
    Grid(int, int) {}

    void render(Canvas& fb, const Frame& f)
    {
        const int w = fb.w, h = fb.h;
        const float horizon = float(h) * 0.52f;
        const float asp = float(h) / float(w);
        const float cx = float(w) * 0.5f;
        const auto t = float(f.beat);
        constexpr float lw_x = 0.022f;

        // sun parameters
        const float sun_y = horizon - float(h) * 0.13f;
        const float sun_r = float(h) * 0.16f;
        const float sun_x = cx;

        for (int y = 0; y < h; ++y) {
            const auto row = fb.row(y);
            const auto fy = float(y);

            // everything that depends only on the row is hoisted out of the
            // pixel loop; on the floor that is most of the arithmetic
            const double sky = clamp01(fy / horizon);
            const auto sky_r = float(0.03 + 0.18 * sky * sky);
            const auto sky_g = float(0.01 + 0.05 * sky);
            const auto sky_b = float(0.08 + 0.22 * sky);

            const bool on_floor = fy > horizon;
            float floor_r = 0, floor_g = 0, floor_b = 0;
            float kx = 0;     // world x per screen pixel on this row
            float dz = 0;     // distance below the horizon, in pixels
            float line_z = 0; // brightness of the cross line on this row
            float fade_x = 0; // aliasing fade of the receding lines
            if (on_floor) {
                dz = fy - horizon;
                const float z = (float(h) * 0.55f) / dz;
                const float wz = z * 2.5f + t * 5.5f;
                kx = z / (float(w) * 0.5f) * asp * 2.0f;
                // same aliasing guard as below, but across the row
                fade_x = float(clamp01((1 / kx - 1.5f) / 2));

                // A line narrower than a pixel lands on only every few pixels
                // and reads as a row of bright dots. Widen it to a full pixel
                // and dim it by the area it actually covers.
                const float period = dz * dz / (1.375f * float(h)); // pixels per unit of wz
                float lw_z = 0.014f + 0.024f / z;
                float amp_z = 1;
                if (const float min_w = 0.5f / period; lw_z < min_w) {
                    amp_z = lw_z / min_w;
                    lw_z = min_w;
                }
                line_z = glow(frac(wz), lw_z) * amp_z;
                // fade lines that have shrunk below a couple of pixels per
                // period, otherwise the horizon boils with aliasing
                line_z *= float(clamp01((period - 1.5f) / 2));
                line_z *= float(clamp01(1.0f / (1 + z * z * 0.004f))); // fog

                floor_r = 0.02f, floor_g = 0.01f, floor_b = 0.06f;
                // the haze near the horizon is computed in double, as in Go
                if (const double haze = clamp01(dz / (float(h) * 0.12f)); haze < 1) {
                    floor_r += float(0.25 * (1 - haze));
                    floor_g += float(0.05 * (1 - haze));
                    floor_b += float(0.35 * (1 - haze));
                }
                floor_r += 0.55f * line_z;
                floor_g += 0.35f * line_z;
                floor_b += 0.75f * line_z;
            }

            // sun: bounding box test first, then the circle only there
            const float dyc = fy - sun_y;
            const bool sun_row = dyc > -sun_r && dyc < sun_r && fy < horizon + 2;
            bool stripe = false;
            float sr = 0, sg = 0, sb = 0;
            if (sun_row) {
                stripe = fy > sun_y - sun_r * 0.45f && int(fy) % 9 < 4;
                const double u = clamp01((fy - (sun_y - sun_r)) / (2 * sun_r));
                sr = 1.0f;
                sg = float(0.95 - 0.7 * u);
                sb = float(0.25 + 0.55 * u);
            }

            // @excerpt GRID
            for (int x = 0; x < w; ++x) {
                float r = sky_r, g = sky_g, b = sky_b;

                if (sun_row && !stripe) {
                    const float dx = float(x) - sun_x;
                    if (dx > -sun_r && dx < sun_r) {
                        const float d = std::sqrt(dx * dx + dyc * dyc);
                        if (d < sun_r) {
                            const auto edge = float(clamp01((sun_r - d) / (sun_r * 0.025f)));
                            r = mix(r, sr, edge);
                            g = mix(g, sg, edge);
                            b = mix(b, sb, edge);
                        }
                    }
                }

                if (on_floor) {
                    // How far this ray slides sideways between one row and
                    // the next, in pixels: x = (k-0.37)/kx + cx, so dx/dy =
                    // |x-cx|/dz. The line must be at least that wide, and
                    // dimmed by the same ratio, or each row shows isolated
                    // bright dots instead of a line.
                    const float off = std::abs(float(x) - cx);
                    const float w_px = std::max({2 * lw_x / kx, off / dz, 1.0f});
                    const float line_x = glow(frac((float(x) - cx) * kx + 0.37f), w_px * kx * 0.5f) *
                                         (2 * lw_x / kx / w_px) * fade_x;
                    const float line = std::max(line_x, line_z);
                    r = floor_r - 0.55f * line_z + 0.55f * line;
                    g = floor_g - 0.35f * line_z + 0.35f * line;
                    b = floor_b - 0.75f * line_z + 0.75f * line;
                }

                row[x] = from_float(r, g, b);
            }
            // @end
        }
    }

private:
    // mix is Go's a + (b-a)*t. Not std::lerp: that one guarantees exact end
    // points and monotonicity, and pays for them with a different formula.
    static float mix(float a, float b, float t) { return a + (b - a) * t; }

    // frac wraps a world coordinate into [0,1), negatives included.
    static float frac(float v)
    {
        const float m = v - float(int(v));
        return m < 0 ? m + 1 : m;
    }

    // glow returns 1 on a grid line, falling to 0 over width w.
    static float glow(float f, float w)
    {
        const float d = f > 0.5f ? 1 - f : f;
        return d < w ? 1 - d / w : 0;
    }
};

} // namespace bb
