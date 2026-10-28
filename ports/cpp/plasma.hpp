// Plasma: four summed sine fields, the oldest trick in the demoscene book.
// Done naively it is four sin() calls per pixel; here three of the four terms
// are 1D tables rebuilt once per frame, leaving a single lookup per pixel.
#pragma once

#include <algorithm>
#include <cmath>
#include <span>
#include <vector>

#include "fmath.hpp"
#include "fx.hpp"
#include "palette.hpp"

namespace bb {

class Plasma {
public:
    Plasma(int w, int h)
        : rad_(std::size_t(w) * std::size_t(h)), sx_(std::size_t(w)), sy_(std::size_t(h)),
          sxy_(std::size_t(w + h))
    {
        const float cx = float(w) * 0.5f, cy = float(h) * 0.5f;
        const float k = 44.0f / float(w + h);
        auto out = rad_.begin();
        for (int y = 0; y < h; ++y) {
            const float dy = float(y) - cy;
            for (int x = 0; x < w; ++x) {
                const float dx = float(x) - cx;
                *out++ = std::sqrt(dx * dx + dy * dy) * k;
            }
        }
    }

    // the ladder: 1 calls sin() four times per pixel, 2 reads the sine table
    // four times per pixel, 3 (the default) moves three of the four lookups
    // into per-frame 1D tables
    void set_step(int k) { step_ = k; }

    void render(Canvas& fb, const Frame& f)
    {
        prepare(f, fb.w, fb.h);
        switch (step_) {
        case 1:
            draw_sin(fb);
            break;
        case 2:
            draw_table(fb);
            break;
        default:
            draw(fb);
        }
    }

private:
    std::vector<float> rad_;           // distance to the centre, per pixel
    std::vector<float> sx_, sy_, sxy_; // the three 1D terms of this frame
    float t_ = 0, kx_ = 0, ky_ = 0, kr_ = 0, cx_ = 0, cy_ = 0, phase_ = 0;
    int step_ = 0;

    void prepare(const Frame& f, int w, int h)
    {
        const auto t = float(f.beat);
        const float kx = 26.0f / float(w);
        const float ky = 26.0f / float(h);
        for (int x = 0; x < w; ++x)
            sx_[x] = fmath::sin(float(x) * kx + t * 1.3f);
        for (int y = 0; y < h; ++y)
            sy_[y] = fmath::sin(float(y) * ky * 1.35f - t * 1.1f);
        for (int i = 0; i < w + h; ++i)
            sxy_[i] = fmath::sin(float(i) * kx * 0.85f + t * 0.8f);
        phase_ = t * 2.6f;
        t_ = t, kx_ = kx, ky_ = ky;
        cx_ = float(w) * 0.5f, cy_ = float(h) * 0.5f;
        kr_ = 44.0f / float(w + h);
    }

    void draw(Canvas& fb) const
    {
        const int w = fb.w;
        const Palette& pal = sunset;
        const float phase = phase_;
        // @excerpt PLASMA
        for (int y = 0; y < fb.h; ++y) {
            const float sy = sy_[y];
            const auto row = fb.row(y);
            const auto rad = std::span(rad_).subspan(std::size_t(y) * w, w);
            const auto sxy = std::span(sxy_).subspan(y, w);
            for (int x = 0; x < w; ++x) {
                const float v = sx_[x] + sy + sxy[x] + fmath::sin(rad[x] + phase);
                row[x] = pal[std::clamp(int(v * 36 + 127.5f), 0, 255)];
            }
        }
        // @end
    }

    // draw_sin is the plasma as you would first write it: every term, every
    // pixel, straight from the maths library. std::sin has a float overload
    // (libc's sinf), so unlike Go there is no round trip through double.
    void draw_sin(Canvas& fb) const
    {
        const float t = t_, kx = kx_, ky = ky_, kr = kr_;
        // @excerpt PLASMA/1
        for (int y = 0; y < fb.h; ++y) {
            const float dy = float(y) - cy_;
            const auto row = fb.row(y);
            for (int x = 0; x < fb.w; ++x) {
                const float dx = float(x) - cx_;
                const float rad = std::sqrt(dx * dx + dy * dy) * kr;
                const float v = std::sin(float(x) * kx + t * 1.3f) +
                                std::sin(float(y) * ky * 1.35f - t * 1.1f) +
                                std::sin(float(x + y) * kx * 0.85f + t * 0.8f) +
                                std::sin(rad + phase_);
                row[x] = sunset[std::clamp(int(v * 36 + 127.5f), 0, 255)];
            }
        }
        // @end
    }

    // draw_table keeps the per-pixel structure of draw_sin but reads the
    // sine table instead: same arguments, so the same pixels as the
    // optimised version.
    void draw_table(Canvas& fb) const
    {
        const float t = t_, kx = kx_, ky = ky_, kr = kr_;
        // @excerpt PLASMA/2
        for (int y = 0; y < fb.h; ++y) {
            const float dy = float(y) - cy_;
            const auto row = fb.row(y);
            for (int x = 0; x < fb.w; ++x) {
                const float dx = float(x) - cx_;
                const float rad = std::sqrt(dx * dx + dy * dy) * kr;
                const float v = fmath::sin(float(x) * kx + t * 1.3f) +
                                fmath::sin(float(y) * ky * 1.35f - t * 1.1f) +
                                fmath::sin(float(x + y) * kx * 0.85f + t * 0.8f) +
                                fmath::sin(rad + phase_);
                row[x] = sunset[std::clamp(int(v * 36 + 127.5f), 0, 255)];
            }
        }
        // @end
    }
};

} // namespace bb
