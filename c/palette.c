#include "palette.h"

#include <stddef.h>

#include "canvas.h"

// One colour anchor of a ramp, at position pos in [0,1].
typedef struct {
    double pos, r, g, b;
} stop;

palette pal_sunset, pal_ice, pal_ember;


static void build(palette p, const stop *stops, size_t n)
{
    for (int i = 0; i < 256; i++) {
        double t = (double)i / 255;
        // find the segment containing t
        stop a = stops[0], b = stops[n - 1];
        for (size_t k = 0; k + 1 < n; k++) {
            if (t >= stops[k].pos && t <= stops[k + 1].pos) {
                a = stops[k];
                b = stops[k + 1];
                break;
            }
        }
        double u = 0;
        if (b.pos > a.pos)
            u = (t - a.pos) / (b.pos - a.pos);
        u = clamp01(u);
        // smoothstep keeps gradients from banding
        u = u * u * (3 - 2 * u);
        p[i] = rgb_from_float(a.r + (b.r - a.r) * u,
                              a.g + (b.g - a.g) * u,
                              a.b + (b.b - a.b) * u);
    }
}

#define LEN(a) (sizeof(a) / sizeof((a)[0]))

static const stop sunset[] = {
    {0.00, 0.02, 0.00, 0.06}, {0.18, 0.25, 0.02, 0.38}, {0.38, 0.72, 0.05, 0.45},
    {0.56, 0.98, 0.25, 0.22}, {0.74, 1.00, 0.62, 0.15}, {0.88, 1.00, 0.93, 0.55},
    {1.00, 1.00, 1.00, 0.96},
};
static const stop ice[] = {
    {0.00, 0.00, 0.00, 0.03}, {0.25, 0.00, 0.10, 0.30}, {0.50, 0.00, 0.55, 0.85},
    {0.72, 0.35, 0.90, 1.00}, {0.90, 0.80, 1.00, 1.00}, {1.00, 1.00, 1.00, 1.00},
};
static const stop ember[] = {
    {0.00, 0.00, 0.00, 0.00}, {0.20, 0.25, 0.00, 0.00}, {0.45, 0.80, 0.10, 0.00},
    {0.68, 1.00, 0.45, 0.00}, {0.85, 1.00, 0.80, 0.15}, {1.00, 1.00, 1.00, 0.85},
};

void palette_init(void)
{
    build(pal_sunset, sunset, LEN(sunset));
    build(pal_ice, ice, LEN(ice));
    build(pal_ember, ember, LEN(ember));
}

static double hue_to_rgb(double p, double q, double t)
{
    if (t < 0)
        t += 1;
    if (t > 1)
        t -= 1;
    if (t < 1.0 / 6)
        return p + (q - p) * 6 * t;
    if (t < 1.0 / 2)
        return q;
    if (t < 2.0 / 3)
        return p + (q - p) * (2.0 / 3 - t) * 6;
    return p;
}

void hsl_to_rgb(double h, double s, double l, double *r, double *g, double *b)
{
    if (s == 0) {
        *r = *g = *b = l;
        return;
    }
    double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    double p = 2 * l - q;
    *r = hue_to_rgb(p, q, h + 1.0 / 3);
    *g = hue_to_rgb(p, q, h);
    *b = hue_to_rgb(p, q, h - 1.0 / 3);
}
