// Starfield: a warp-speed star tunnel. Stars live in 3D, get projected in
// perspective and dragged into short streaks: each star draws from its
// previous depth to its current one, and the streak is what sells the speed.
#pragma once

#include <algorithm>
#include <array>
#include <cstdlib>
#include <ranges>
#include <vector>

#include "fmath.hpp"
#include "fx.hpp"

namespace bb {

class Starfield {
public:
    Starfield(int w, int h) : bg_(std::size_t(w) * std::size_t(h))
    {
        // A braced initialiser evaluates left to right in C++ (unlike C), so
        // the three draws happen in Go's order: x, y, then z.
        for (Star& s : stars_)
            s = Star{(rng_.unit() * 2 - 1) * 1.6f, (rng_.unit() * 2 - 1) * 1.6f, rng_.unit() * 40 + 0.2f};
        build_backdrop(w, h);
    }

    void render(Canvas& fb, const Frame& f)
    {
        fly(f, fb.w, fb.h);
        draw(fb);
    }

private:
    struct Star {
        float x, y, z;
    };
    struct Streak {
        int32_t x0, y0, x1, y1;
        uint32_t c;
    };
    static constexpr std::size_t count = 1600;

    fmath::Rng rng_{0x6005E};
    std::array<Star, count> stars_;
    std::array<Streak, count> streaks_{};
    std::vector<uint32_t> bg_; // the backdrop never changes, so build it once

    // build_backdrop paints the deep-navy vignette. Copying a ready buffer is
    // two orders of magnitude cheaper than evaluating it per pixel per frame.
    void build_backdrop(int w, int h)
    {
        auto out = bg_.begin();
        for (int y = 0; y < h; ++y) {
            const double dy = double(y) / double(h) - 0.5;
            for (int x = 0; x < w; ++x) {
                const double dx = double(x) / double(w) - 0.5;
                const double v = dx * dx + dy * dy;
                *out++ = from_float(std::max(0.02 - v * 0.03, 0.0), std::max(0.02 - v * 0.025, 0.0),
                                    std::max(0.05 - v * 0.03, 0.0));
            }
        }
    }

    void fly(const Frame& f, int w, int h)
    {
        const float cx = float(w) * 0.5f, cy = float(h) * 0.5f;
        // accelerate over the scene so the entry has a kick
        const auto speed = float(2.5 + std::min(f.beat, 3.0) * 4);
        const float dt = std::min(float(f.dt), 0.1f);
        const float dz = speed * dt;
        // @excerpt STARFIELD
        for (auto [p, out] : std::views::zip(stars_, streaks_)) {
            p.z -= dz;
            if (p.z < 0.8f) {
                p.z += 40;
                p.x = (rng_.unit() * 2 - 1) * 1.1f;
                p.y = (rng_.unit() * 2 - 1) * 1.1f;
            }
            const float f0 = 1.0f / p.z;
            const float zoom = float(w) * 0.78f;
            const float x0 = cx + p.x * f0 * zoom;
            const float y0 = cy + p.y * f0 * zoom;
            const float f1 = 1.0f / (p.z + dz * 2.4f);
            const float x1 = cx + p.x * f1 * zoom;
            const float y1 = cy + p.y * f1 * zoom;

            // brighter and bluer as the star gets close
            const float near = 1 - p.z / 40;
            const float b = near * near;
            const auto r = uint32_t(120 * b + 40);
            const auto g = uint32_t(190 * b + 40);
            const auto bl = uint32_t(255 * (0.25f + 0.75f * b));
            out = {int32_t(x0), int32_t(y0), int32_t(x1), int32_t(y1), rgb(r, g, bl)};
        }
        // @end
    }

    void draw(Canvas& fb) const
    {
        std::ranges::copy(bg_, fb.pix.begin());
        for (const Streak& s : streaks_) {
            // additive line from the trailing point to the head
            line_add(fb, s.x0, s.y0, s.x1, s.y1, s.c);
            // bright head pixel
            if (s.x1 >= 0 && s.x1 < fb.w && s.y1 >= 0 && s.y1 < fb.h)
                fb.pix[std::size_t(s.y1 * fb.w + s.x1)] = 0xFFCCEEFF;
        }
    }

    // line_add draws a Bresenham line adding colour, so overlapping stars
    // accumulate brightness instead of replacing each other.
    static void line_add(Canvas& fb, int x0, int y0, int x1, int y1, uint32_t c)
    {
        const int dx = std::abs(x1 - x0), dy = -std::abs(y1 - y0);
        const int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
        int err = dx + dy;
        for (;;) {
            if (x0 >= 0 && x0 < fb.w && y0 >= 0 && y0 < fb.h) {
                uint32_t& p = fb.pix[std::size_t(y0 * fb.w + x0)];
                const uint32_t r = std::min((p & 0xFF) + (c & 0xFF), 255u);
                const uint32_t g = std::min((p >> 8 & 0xFF) + (c >> 8 & 0xFF), 255u);
                const uint32_t b = std::min((p >> 16 & 0xFF) + (c >> 16 & 0xFF), 255u);
                p = rgb(r, g, b);
            }
            if (x0 == x1 && y0 == y1)
                break;
            const int e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }
        }
    }
};

} // namespace bb
