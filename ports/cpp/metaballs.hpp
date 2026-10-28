// Metaballs: radial fields summed, the iso-contours shaded. Every pixel
// evaluates sum(r^2 / d^2) with one division per ball and no square root,
// and the contour band gets a hot rim so the blobs read as liquid.
#pragma once

#include <algorithm>
#include <array>

#include "fmath.hpp"
#include "fx.hpp"
#include "palette.hpp"

namespace bb {

class Metaballs {
public:
    Metaballs(int, int) {}

    void render(Canvas& fb, const Frame& f)
    {
        const int w = fb.w, h = fb.h;
        // x is scaled by width/height so a circle in field space is a circle
        // on screen, whatever the aspect ratio
        const float asp = float(w) / float(h);
        move(float(f.beat), asp);
        // @excerpt METABALLS
        for (int y = 0; y < h; ++y) {
            const float fy = float(y) / float(h) - 0.5f;
            const auto row = fb.row(y);
            for (int x = 0; x < w; ++x) {
                const float fx = (float(x) / float(w) - 0.5f) * asp;
                float field = 0;
                for (const Ball& b : balls_) {
                    const float dx = fx - b.x;
                    const float dy = fy - b.y;
                    field += b.r2 / (dx * dx + dy * dy + 1e-5f);
                }
                // about 1 at a ball's surface and exploding inside: v/(1+v)
                // compresses that into a usable 0..1 ramp without a log
                const float v = field / (1.6f + field);
                int idx = std::min(int(v * 255), 255);
                // rim: the iso-surface where the balls meet flares white
                if (field > 1.0f && field < 1.09f)
                    idx = 255;
                row[x] = sunset[idx];
            }
        }
        // @end
    }

private:
    // A ball is kept the way the pixel loop reads it: its centre relative to
    // the middle of the screen, x already scaled by the aspect ratio, and its
    // squared radius. Go recomputes the offsets for every pixel; the values,
    // and so the pixels, are the same.
    struct Ball {
        float x, y, r2;
    };
    std::array<Ball, 6> balls_{};

    void move(float t, float asp)
    {
        for (std::size_t i = 0; i < balls_.size(); ++i) {
            const auto fi = float(i);
            // each ball orbits on its own ellipse and breathes
            const float a = t * (0.35f + fi * 0.07f) + fi * 2.1f;
            const float x = 0.5f + 0.20f * fmath::cos(a) * (1 + 0.3f * fmath::sin(t * 0.5f + fi));
            const float y = 0.5f + 0.20f * fmath::sin(a * 1.3f + fi) * (1 + 0.3f * fmath::cos(t * 0.4f + fi * 2));
            const float r = 0.105f + 0.025f * fmath::sin(t * 1.1f + fi * 1.7f);
            balls_[i] = {(x - 0.5f) * asp, y - 0.5f, r * r};
        }
    }
};

} // namespace bb
