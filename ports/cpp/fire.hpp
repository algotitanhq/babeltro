// Fire: the Doom fire algorithm. A heat buffer is seeded at the bottom row
// and diffused upward with a little random sideways drift. Integer only, one
// byte per pixel, read through a palette ramp.
#pragma once

#include <algorithm>
#include <span>
#include <vector>

#include "fmath.hpp"
#include "fx.hpp"
#include "palette.hpp"

namespace bb {

class Fire {
public:
    Fire(int w, int h) : heat_(std::size_t(w) * std::size_t(h)) {}

    void render(Canvas& fb, const Frame& f)
    {
        seed(fb.w, fb.h, f.n);
        spread(fb);
    }

private:
    std::vector<uint8_t> heat_;
    fmath::Rng rng_{0x9E3779B9}; // Go's own xorshift32 for the fire: the same generator

    // seed fills the hottest row: a slow horizontal wave gives the fire its
    // uneven base, the random term keeps the tongues from looking periodic
    void seed(int w, int h, uint64_t frame)
    {
        const std::size_t last = std::size_t(h - 1) * w;
        const float t = float(frame) * 0.05f;
        for (int x = 0; x < w; ++x) {
            const float fx = float(x) / float(w);
            const float wv = 0.5f + 0.5f * fmath::sin(fx * 11 + t) * 0.6f +
                             0.5f * fmath::sin(fx * 23 - t * 1.7f) * 0.4f;
            float v = 150 + wv * 90 + float(rng_.next() & 31) - 16;
            v = v > 255 ? 255 : v < 90 ? 90 : v;
            heat_[last + x] = uint8_t(v);
        }
    }

    // spread diffuses upward: every destination pixel takes one value from
    // the row below, offset sideways by a random -1, 0 or +1. Gather, not
    // scatter, so each pixel is written exactly once. A row goes through the
    // palette as soon as it is complete, so the buffer is read once a frame.
    void spread(Canvas& fb)
    {
        const int w = fb.w, h = fb.h;
        auto& buf = heat_;
        auto paint = [&](int y) {
            const auto heat = std::span(buf).subspan(std::size_t(y) * w, w);
            std::ranges::transform(heat, fb.row(y).begin(), [](uint8_t v) { return ember[v]; });
        };
        paint(h - 1);
        // @excerpt FIRE
        for (int y = h - 1; y > 0; --y) {
            const int src = y * w;
            const int dst = (y - 1) * w;
            for (int x = 0; x < w; ++x) {
                if (buf[src + x] == 0) {
                    buf[dst + x] = 0;
                    continue;
                }
                const uint32_t r = rng_.next();
                const int sx = std::clamp(x + int(r % 3) - 1, 0, w - 1);
                const uint8_t v = buf[src + sx];
                const auto decay = uint8_t(r >> 16 & 1);
                buf[dst + x] = v > decay ? uint8_t(v - decay) : 0;
            }
            paint(y - 1);
        }
        // @end
    }
};

} // namespace bb
