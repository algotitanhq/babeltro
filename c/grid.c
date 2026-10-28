// Grid: the synthwave staple, an infinite checker floor rushing at the camera
// under a banded sun. The floor is a per-pixel perspective divide, and the
// lines come from the fractional part of the world coordinates.
//
// The Go reference mixes float32 and float64 here (its clamp works in
// float64); the casts below keep every operation at the width Go uses.
#include <math.h>

#include "fx.h"

static void start(int w, int h) { (void)w, (void)h; }

// frac wraps a world coordinate into [0,1), negatives included.
static inline float frac(float v)
{
    float m = v - (float)(int)v;
    return m < 0 ? m + 1 : m;
}

// line_glow returns 1 on a grid line, falling to 0 over width w.
static inline float line_glow(float f, float w)
{
    float d = f > 0.5f ? 1 - f : f;
    return d < w ? 1 - d / w : 0;
}

static inline float mix(float a, float b, float t) { return a + (b - a) * t; }

// clampf clamps in double, like Go's canvas.Clamp01, and rounds back.
static inline float clampf(float v) { return (float)clamp01(v); }

static void render(canvas *fb, const fx_state *s)
{
    int w = fb->w, h = fb->h;
    float horizon = (float)h * 0.52f;
    float asp = (float)h / (float)w;
    float cx = (float)w * 0.5f;
    float t = (float)s->beat;

    // sun parameters
    float sun_y = horizon - (float)h * 0.13f;
    float sun_r = (float)h * 0.16f;
    float sun_x = cx;

    for (int y = 0; y < h; y++) {
        uint32_t *restrict row = fb->pix + y * w;
        float fy = (float)y;

        // everything that depends only on the row is hoisted out of the
        // pixel loop; on the floor that is most of the arithmetic
        double sky = clamp01(fy / horizon);
        float sky_r = (float)(0.03 + 0.18 * sky * sky);
        float sky_g = (float)(0.01 + 0.05 * sky);
        float sky_b = (float)(0.08 + 0.22 * sky);

        bool on_floor = fy > horizon;
        float floor_r = 0, floor_g = 0, floor_b = 0;
        float kx = 0;      // world x per screen pixel on this row
        float dz = 0;      // distance below the horizon, in pixels
        float line_z = 0;  // brightness of the cross line on this row
        float fade_x = 0;  // aliasing fade of the receding lines
        const float lw_x = 0.022f;
        if (on_floor) {
            dz = fy - horizon;
            float z = ((float)h * 0.55f) / dz;
            float wz = z * 2.5f + t * 5.5f;
            kx = z / ((float)w * 0.5f) * asp * 2.0f;
            // same aliasing guard as below, but across the row
            fade_x = clampf((1 / kx - 1.5f) / 2);

            // A line narrower than a pixel lands on only every few pixels and
            // reads as a row of bright dots. Widen it to a full pixel and dim
            // it by the area it actually covers: the same light, spread out,
            // which is what the eye integrates anyway.
            float period = dz * dz / (1.375f * (float)h); // pixels per unit of wz
            float lw_z = 0.014f + 0.024f / z;
            float amp_z = 1;
            float min_w = 0.5f / period;
            if (lw_z < min_w) {
                amp_z = lw_z / min_w;
                lw_z = min_w;
            }
            line_z = line_glow(frac(wz), lw_z) * amp_z;
            // fade lines that have shrunk below a couple of pixels per
            // period, otherwise the horizon boils with aliasing
            line_z *= clampf((period - 1.5f) / 2);
            line_z *= clampf(1.0f / (1 + z * z * 0.004f)); // fog

            floor_r = 0.02f;
            floor_g = 0.01f;
            floor_b = 0.06f;
            // the haze near the horizon is computed in double, as in Go
            double haze = clamp01(dz / ((float)h * 0.12f));
            if (haze < 1) {
                floor_r += (float)(0.25 * (1 - haze));
                floor_g += (float)(0.05 * (1 - haze));
                floor_b += (float)(0.35 * (1 - haze));
            }
            floor_r += 0.55f * line_z;
            floor_g += 0.35f * line_z;
            floor_b += 0.75f * line_z;
        }

        // sun: bounding box test first, then the expensive circle only there
        float dyc = fy - sun_y;
        bool sun_row = dyc > -sun_r && dyc < sun_r && fy < horizon + 2;
        bool stripe = false;
        float sr = 0, sg = 0, sb = 0;
        if (sun_row) {
            stripe = fy > sun_y - sun_r * 0.45f && (int)fy % 9 < 4;
            double u = clamp01((fy - (sun_y - sun_r)) / (2 * sun_r));
            sr = 1.0f;
            sg = (float)(0.95 - 0.7 * u);
            sb = (float)(0.25 + 0.55 * u);
        }

        // @excerpt GRID
        for (int x = 0; x < w; x++) {
            float r = sky_r, g = sky_g, b = sky_b;

            if (sun_row && !stripe) {
                float dx = (float)x - sun_x;
                if (dx > -sun_r && dx < sun_r) {
                    float d = sqrtf(dx * dx + dyc * dyc);
                    if (d < sun_r) {
                        float edge = clampf((sun_r - d) / (sun_r * 0.025f));
                        r = mix(r, sr, edge);
                        g = mix(g, sg, edge);
                        b = mix(b, sb, edge);
                    }
                }
            }

            if (on_floor) {
                // How far this ray slides sideways between one row and the
                // next, in pixels: x = (k-0.37)/kx + cx, so dx/dy = |x-cx|/dz.
                // The line must be at least that wide, and dimmed by the same
                // ratio, or each row shows a handful of isolated bright dots
                // instead of a line.
                float off = fabsf((float)x - cx);
                float w_px = 2 * lw_x / kx;
                float slide = off / dz;
                if (slide > w_px)
                    w_px = slide;
                if (w_px < 1)
                    w_px = 1;
                float line_x = line_glow(frac(((float)x - cx) * kx + 0.37f), w_px * kx * 0.5f) *
                               (2 * lw_x / kx / w_px) * fade_x;
                float line = line_x > line_z ? line_x : line_z;
                r = floor_r - 0.55f * line_z + 0.55f * line;
                g = floor_g - 0.35f * line_z + 0.35f * line;
                b = floor_b - 0.75f * line_z + 0.75f * line;
            }

            row[x] = rgb_from_float(r, g, b);
        }
        // @end
    }
}

const effect fx_grid = {"GRID", start, render};
