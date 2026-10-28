// Rotozoom: build a texture once, then every frame rotate and zoom the
// sampling grid over it. Cost per pixel: a few multiplies and one lookup.
#pragma once

#include <cmath>
#include <numbers>
#include <span>
#include <vector>

#include "fmath.hpp"
#include "fx.hpp"
#include "palette.hpp"

namespace bb {

class Rotozoom {
public:
    Rotozoom(int, int) {}

    void render(Canvas& fb, const Frame& f)
    {
        const auto t = float(f.beat);
        const float ang = t * 0.45f;
        const float cos_a = fmath::cos(ang), sin_a = fmath::sin(ang);
        // breathing zoom: 0.7 .. 1.6
        const float breath = 0.55f + 0.45f * fmath::sin(t * 0.7f) + 0.35f;
        const float offx = fmath::sin(t * 0.31f) * 180 + t * 26;
        const float offy = fmath::cos(t * 0.27f) * 180 + t * 19;

        const int w = fb.w;
        const float cx = float(w) * 0.5f, cy = float(fb.h) * 0.5f;
        const float zoom = breath / float(w) * 6.5f;
        const auto tex = tex_;
        // @excerpt ROTOZOOM
        for (int y = 0; y < fb.h; ++y) {
            const float dy = float(y) - cy;
            const auto row = fb.row(y);
            for (int x = 0; x < w; ++x) {
                const float dx = float(x) - cx;
                const float tx = (dx * cos_a - dy * sin_a) * zoom * 34;
                const float ty = (dx * sin_a + dy * cos_a) * zoom * 34;
                const int ix = int(tx + offx) & mask;
                const int iy = int(ty + offy) & mask;
                row[x] = tex[std::size_t(iy * size + ix)];
            }
        }
        // @end
    }

private:
    static constexpr int size = 512;
    static constexpr int mask = size - 1;

    // The texture is built on the first ROTOZOOM start and kept for the
    // life of the module: a function-local static, initialised once.
    std::span<const uint32_t> tex_ = texture();

    static std::span<const uint32_t> texture()
    {
        static const std::vector<uint32_t> tex = build_texture();
        return tex;
    }

    // build_texture makes a tileable rainbow plasma. It costs a few hundred
    // thousand sine calls; doing that per frame would cost the whole budget,
    // which is the point of the scene.
    static std::vector<uint32_t> build_texture()
    {
        constexpr double two_pi = 2 * std::numbers::pi;
        std::vector<uint32_t> tex(size * size);
        auto out = tex.begin();
        for (int y = 0; y < size; ++y) {
            // Go rounds the coordinates to float32 before the double maths
            const double fy = float(y) / size;
            for (int x = 0; x < size; ++x) {
                const double fx = float(x) / size;
                // every frequency is a whole number of cycles per tile
                double v = std::sin(fx * two_pi * 3 + fy * two_pi * 2) * 0.5 +
                           std::sin(fy * two_pi * 5 - fx * two_pi * 4) * 0.3 +
                           std::sin((fx + fy) * two_pi * 7) * 0.2;
                // concentric rings, also periodic in the tile
                const double dx = double(x) - size / 2;
                const double dy = double(y) - size / 2;
                const double rr = std::sqrt(dx * dx + dy * dy) / size * 12;
                v += std::sin(rr * two_pi) * 0.35;

                double hue = std::fmod(v * 0.55 + 0.5, 1);
                if (hue < 0)
                    hue += 1;
                auto [r, g, b] = hsl_to_rgb(hue, 0.70, 0.48 + 0.14 * v);

                // a dark grid over the colour: without a straight edge the
                // motion reads as random shimmer
                if (x % (size / 8) < 3 || y % (size / 8) < 3)
                    r *= 0.28, g *= 0.28, b *= 0.28;
                *out++ = from_float(r, g, b);
            }
        }
        return tex;
    }
};

} // namespace bb
