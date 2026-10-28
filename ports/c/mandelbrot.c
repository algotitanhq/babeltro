// Mandelbrot: a dive into the boundary that never ends. It is the most
// expensive scene in the demo, so it renders on a coarse grid of square
// blocks: at 60 fps in motion nobody can tell, and the speed budget stays
// honest. The maths is double precision throughout, as in Go.
#include <math.h>

#include "fx.h"

static struct {
    int step; // block size in pixels
    // the ladder: 1 iterates every pixel with no shortcut, 2 adds the closed
    // form test for the cardioid and the bulb, 3 (the default) also renders
    // on blocks of step x step pixels
    int rung;
} M;

static void set_step(int n) { M.rung = n; }

static void start(int w, int h)
{
    (void)h;
    M.rung = 0;
    // keep the block size constant in screen terms as the window grows
    M.step = w > 1600 ? 3 : 2;
}

// @excerpt MANDELBROT/2
// iterations returns how many steps of z = z^2 + c it takes |z| to pass 2,
// or max if it never does.
static int iterations(double cx, double cy, int max)
{
    // cheap escape test for the main cardioid and the period-2 bulb
    double x = cx - 0.25;
    double y2 = cy * cy;
    double q = x * x + y2;
    if (q * (q + x) <= 0.25 * y2)
        return max;
    if ((cx + 1) * (cx + 1) + y2 <= 0.0625)
        return max;

    // keep the squares around: each one is needed twice
    double zx = 0, zy = 0, zx2 = 0, zy2 = 0;
    for (int i = 0; i < max; i++) {
        zy = 2 * zx * zy + cy;
        zx = zx2 - zy2 + cx;
        zx2 = zx * zx;
        zy2 = zy * zy;
        if (zx2 + zy2 > 4)
            return i;
    }
    return max;
}
// @end

// @excerpt MANDELBROT/1
// iterations_plain is the escape-time loop and nothing else: every point
// inside the set runs the full budget before it gives up.
static int iterations_plain(double cx, double cy, int max)
{
    double zx = 0, zy = 0, zx2 = 0, zy2 = 0;
    for (int i = 0; i < max; i++) {
        zy = 2 * zx * zy + cy;
        zx = zx2 - zy2 + cx;
        zx2 = zx * zx;
        zy2 = zy * zy;
        if (zx2 + zy2 > 4)
            return i;
    }
    return max;
}
// @end

static void render(canvas *fb, const fx_state *s)
{
    int w = fb->w, h = fb->h, step = M.step;
    int (*iter)(double, double, int) = iterations;
    switch (M.rung) {
    case 1:
        step = 1, iter = iterations_plain;
        break;
    case 2:
        step = 1;
        break;
    }

    // the camera
    double u = fmin(s->beat, 14) / 12;
    // the centre slides onto the target quickly, then the exponential dive
    // does the work; drifting it linearly with the zoom would spend most of
    // the scene looking at empty plane
    double k = 1 - exp(-8 * u);
    // tested target: the seahorse valley, where the boundary never opens into
    // a flat interior, so the whole frame stays fractal at any depth
    double span = 2.9 * exp(-u * u * 3.6);
    // the deep frames need the iteration budget; the wide ones do not
    int max_iter = 64 + (int)(128 * u);
    double ccx = -0.5 + (-0.743643887037151 + 0.5) * k;
    double ccy = 0.0 + 0.131825904205330 * k;

    double asp = (double)h / w;
    double x0 = ccx - span * 0.5;
    double y0 = ccy - span * 0.5 * asp;
    double d = span / w; // plane units per pixel

    // @excerpt MANDELBROT
    for (int by = 0; by < h; by += step) {
        double cy = y0 + by * d;
        int y_end = by + step < h ? by + step : h;
        for (int bx = 0; bx < w; bx += step) {
            int it = iter(x0 + bx * d, cy, max_iter);
            uint32_t c = 0xFF0A0812; // inside the set
            if (it < max_iter) {
                // the ramp is anchored to a fixed iteration count, not to
                // max_iter, so raising the budget for a deep zoom does not
                // darken the whole picture
                double v = fmin(sqrt(it / 40.0), 1);
                c = pal_at(pal_ice, v * 0.92 + 0.04);
            }
            int x_end = bx + step < w ? bx + step : w;
            for (int yy = by; yy < y_end; yy++)
                for (int xx = bx; xx < x_end; xx++)
                    fb->pix[yy * w + xx] = c;
        }
    }
    // @end
}

const effect fx_mandelbrot = {"MANDELBROT", start, render, set_step};
