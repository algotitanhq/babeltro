// Tunnel: every pixel is mapped to polar coordinates once, in the
// constructor. After that the per-pixel work is a couple of table lookups and
// a palette read: the geometry is free.
#pragma once

#include <algorithm>
#include <cmath>
#include <vector>

#include "fmath.hpp"
#include "fx.hpp"
#include "palette.hpp"

namespace bb {

class Tunnel {
public:
    // scale and softness grow with the diagonal, so the rings look the same
    // at any resolution
    Tunnel(int w, int h)
        : scale_{float(w + h) * 2.2f}, soft_{float(w + h) * 0.02f},
          depth_(std::size_t(w) * std::size_t(h)), angle_(depth_.size())
    {
        fmath::dist_inv_table(depth_, w, h, scale_, soft_);
        fmath::atan2_table(angle_, w, h);
    }

    // the ladder: 1 computes the distance and the angle for every pixel,
    // every frame; 2 (the default) reads them from the tables
    void set_step(int k) { step_ = k; }

    void render(Canvas& fb, const Frame& f)
    {
        const auto t = float(f.beat);
        if (step_ == 1)
            draw_direct(fb, t);
        else
            draw_tables(fb, t);
    }

private:
    float scale_, soft_;
    std::vector<float> depth_; // falls off as 1/r: large at the centre
    std::vector<float> angle_; // atan2 as a fraction of a turn, [0,1)
    int step_ = 0;

    void draw_tables(Canvas& fb, float tm) const
    {
        const Palette& pal = ice;
        const float adv = tm * 3.0f;
        const float spin = tm * 0.25f;
        // the depth and angle tables have the framebuffer's layout, so one
        // flat index walks all three
        // @excerpt TUNNEL
        for (std::size_t i = 0; i < fb.pix.size(); ++i) {
            const float u = depth_[i] + adv; // scroll towards the viewer
            const float v = angle_[i];

            // rings along the depth axis
            const float ring = fmath::sin01(u * 0.16f);
            // spokes that twist as they recede
            const float twist = v * 12 + u * 0.09f + spin;
            const float spoke = fmath::sin01(twist);

            float val = ring * 0.55f + spoke * 0.45f;
            // brick checker gives the walls their structure
            if (((int(u * 0.32f) + int(twist)) & 1) == 1)
                val = -val * 0.7f;

            const float fog = 1 / (1 + u * 0.02f);
            const float lum = (val * 0.5f + 0.5f) * fog;
            fb.pix[i] = pal[std::clamp(int(lum * 300), 0, 255)];
        }
        // @end
    }

    // draw_direct is the tunnel without its tables: a square root, a
    // division and an atan2 per pixel, every frame, for values that never
    // change. Same formulas, so the same pixels; only the time differs.
    void draw_direct(Canvas& fb, float tm) const
    {
        const Palette& pal = ice;
        const float adv = tm * 3.0f;
        const float spin = tm * 0.25f;
        const float cx = float(fb.w) / 2, cy = float(fb.h) / 2;
        // @excerpt TUNNEL/1
        for (int y = 0; y < fb.h; ++y) {
            const float dy = float(y) - cy;
            auto row = fb.row(y);
            for (int x = 0; x < fb.w; ++x) {
                const float dx = float(x) - cx;
                const float depth = scale_ / (std::sqrt(dx * dx + dy * dy) + soft_);
                const float u = depth + adv;
                const float v = fmath::atan2_turns(dy, dx);

                const float ring = fmath::sin01(u * 0.16f);
                const float twist = v * 12 + u * 0.09f + spin;
                const float spoke = fmath::sin01(twist);
                float val = ring * 0.55f + spoke * 0.45f;
                if (((int(u * 0.32f) + int(twist)) & 1) == 1)
                    val = -val * 0.7f;
                const float fog = 1 / (1 + u * 0.02f);
                const float lum = (val * 0.5f + 0.5f) * fog;
                row[x] = pal[std::clamp(int(lum * 300), 0, 255)];
            }
        }
        // @end
    }
};

} // namespace bb
