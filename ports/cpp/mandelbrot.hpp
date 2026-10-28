// Mandelbrot: a dive into the boundary. It is the most expensive scene, so
// it renders on a coarse grid of blocks and stretches the result: at 60 fps
// in motion nobody can tell.
#pragma once

#include <algorithm>
#include <cmath>

#include "fx.hpp"
#include "palette.hpp"

namespace bb {

// @excerpt MANDELBROT/2
constexpr int escape(double cx, double cy, int max)
{
    // cheap escape test for the main cardioid and the period-2 bulb
    const double x = cx - 0.25;
    const double y2 = cy * cy;
    const double q = x * x + y2;
    if (q * (q + x) <= 0.25 * y2)
        return max;
    if ((cx + 1) * (cx + 1) + y2 <= 0.0625)
        return max;
    double zx = 0, zy = 0, zx2 = 0, zy2 = 0;
    for (int i = 0; i < max; ++i) {
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

// escape_plain is the escape-time loop and nothing else: every point inside
// the set runs the full budget before it gives up.
//
// @excerpt MANDELBROT/1
constexpr int escape_plain(double cx, double cy, int max)
{
    double zx = 0, zy = 0, zx2 = 0, zy2 = 0;
    for (int i = 0; i < max; ++i) {
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

class Mandelbrot {
public:
    // keep the block size constant in screen terms as the window grows
    Mandelbrot(int w, int) : block_{w > 1600 ? 3 : 2} {}

    // the ladder: 1 iterates every pixel with no shortcut, 2 adds the closed
    // form test for the cardioid and the bulb, 3 (the default) also renders
    // on blocks of block x block pixels
    void set_step(int k) { rung_ = k; }

    void render(Canvas& fb, const Frame& f)
    {
        aim(f.beat);
        // The escape test is a template argument, not a function pointer as
        // in Go: each rung gets its own copy of the loop with the test
        // inlined, and no indirect call per block.
        switch (rung_) {
        case 1:
            draw<escape_plain>(fb, 1);
            break;
        case 2:
            draw<escape>(fb, 1);
            break;
        default:
            draw<escape>(fb, block_);
        }
    }

private:
    int block_;
    int rung_ = 0;
    double cx_ = 0, cy_ = 0, scale_ = 0;
    int max_iter_ = 192;

    void aim(double beat)
    {
        const double t = std::min(beat, 14.0);
        const double u = t / 12;
        // the camera slides onto the target quickly, then the exponential
        // dive does the work
        const double k = 1 - std::exp(-8 * u);
        // the seahorse valley: the boundary never opens into a flat interior
        scale_ = 2.9 * std::exp(-u * u * 3.6);
        // the deep frames need the iteration budget; the wide ones do not
        max_iter_ = 64 + int(128 * u);
        cx_ = -0.5 + (-0.743643887037151 + 0.5) * k;
        cy_ = 0.0 + 0.131825904205330 * k;
    }

    template <auto Escape>
    void draw(Canvas& fb, int step) const
    {
        const int w = fb.w, h = fb.h;
        const double asp = double(h) / double(w);
        const double span = scale_;
        const double x0 = cx_ - span * 0.5;
        const double y0 = cy_ - span * 0.5 * asp;
        // units per pixel: the loop below advances by whole blocks, so this
        // must not be divided by step as well
        const double d = span / double(w);
        const int max_iter = max_iter_;
        // @excerpt MANDELBROT
        for (int by = 0; by * step < h; ++by) {
            const double cy = y0 + double(by * step) * d;
            const int y_start = by * step;
            const int y_end = std::min(y_start + step, h);
            for (int x = 0; x < w; x += step) {
                const double cx = x0 + double(x) * d;
                const int it = Escape(cx, cy, max_iter);
                uint32_t c = 0xFF0A0812;
                if (it < max_iter) {
                    // the ramp is anchored to a fixed iteration count, not to
                    // max_iter, so a deeper budget does not darken the picture
                    const double v = std::min(std::sqrt(double(it) / 40), 1.0);
                    c = at(ice, v * 0.92 + 0.04);
                }
                const int x_end = std::min(x + step, w);
                for (int yy = y_start; yy < y_end; ++yy)
                    std::ranges::fill(fb.row(yy).subspan(x, x_end - x), c);
            }
        }
        // @end
    }
};

} // namespace bb
