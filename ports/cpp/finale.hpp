// Finale: the closing card. The logo, its reflection, the subtitle and the
// numbers that make the point, over a glowing backdrop with a few twinkling
// stars. The browser lab draws no HUD in the frame, so the card composes over
// the full height.
#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <string_view>
#include <vector>

#include "fmath.hpp"
#include "fx.hpp"

namespace bb {

// The language this port is written in: the only words that differ from the
// other ports.
inline constexpr char lang[] = "C++";

// join concatenates two string literals at compile time into a char array,
// terminator included: "EVERY PIXEL IS " + lang with no runtime string.
template <std::size_t A, std::size_t B>
consteval std::array<char, A + B - 1> join(const char (&a)[A], const char (&b)[B])
{
    std::array<char, A + B - 1> out{};
    std::copy_n(a, A - 1, out.begin());
    std::copy_n(b, B, out.begin() + (A - 1));
    return out;
}

class Finale {
public:
    Finale(int w, int h) : dx2_(std::size_t(w))
    {
        fmath::Rng rng{0xF1A1E};
        // braced initialisers evaluate left to right: x, y, then b
        for (BgStar& s : stars_)
            s = BgStar{rng.unit(), rng.unit(), 0.15f + rng.unit() * 0.85f};
        layout(w, h);
    }

    void render(Canvas& fb, const Frame& f)
    {
        const double t = f.t;
        backdrop(fb, t);
        const int w = fb.w;

        // @excerpt FINALE
        // --- logo ---
        const int scale = logo_scale_;
        // the letters bounce off the floor line: offsets run from -scale/3
        // (up) to 0 (resting on it), never below, so no letter sinks into
        // its own reflection
        for (std::size_t i = 0; i < offs_.size(); ++i)
            offs_[i] = int((std::sin(t * 2.4 + double(i) * 0.75) - 1) * double(scale) / 6);

        constexpr uint32_t top = 0xFFFFF6E8; // pale cream
        constexpr uint32_t mid = 0xFF7C9CFF; // hot rose
        constexpr uint32_t bot = 0xFF582080; // deep violet

        // reflection first, so the wordmark sits on top of its own light
        fb.draw_text_reflect(logo_x_, floor_y_, lang, scale, top, bot, offs_, 125, refl_h_);
        // a one-pixel dark edge keeps the letters off the background
        fb.draw_text_outline(logo_x_, logo_y_, lang, scale, 0xFF200A18, offs_);
        fb.draw_text_gradient(logo_x_, logo_y_, lang, scale, top, mid, bot, offs_, true);
        // @end

        // --- subtitle with rules either side ---
        const int sub_w = text_width(sub, sub_scale_);
        const int rule = sub_w / 3;
        const int ly = sub_y_ + text_height(sub_scale_) / 2;
        fb.hline(sub_x_ - rule - 14, ly, rule, 0xFF9050A0);
        fb.hline(sub_x_ + sub_w + 14, ly, rule, 0xFF9050A0);
        fb.draw_text(sub_x_, sub_y_, sub, sub_scale_, 0xFFF0E0FF);

        // --- closing numbers ---
        for (int i = 0; const std::string_view l : lines) {
            const int lw = text_width(l, stats_scale_);
            fb.draw_text((w - lw) / 2, stats_y_ + i++ * stat_gap_, l, stats_scale_, 0xFFC0B0E0);
        }

        // the punchline
        fb.draw_text(tag_x_, tag_y_, tag, tag_scale_, 0xFFB0E0FF);
    }

private:
    static constexpr auto sub_chars = join("EVERY PIXEL IS ", lang);
    static constexpr std::string_view sub{sub_chars.data(), sub_chars.size() - 1};
    static constexpr std::string_view tag = "ONE THREAD - NO GPU - NO SHADER";
    static constexpr std::array<std::string_view, 3> lines = {"0 GPU SHADERS", "0 EXTERNAL MODULES",
                                                              "0 ASSETS ON DISK"};

    // a fixed background star in normalised coordinates: the finale only
    // needs twinkle, not motion
    struct BgStar {
        float x, y, b;
    };
    std::array<BgStar, 260> stars_{};
    std::array<int, sizeof lang - 1> offs_{}; // per-letter wave offsets

    int logo_scale_ = 0, logo_x_ = 0, logo_y_ = 0, text_h_ = 0;
    int refl_h_ = 0; // rows the reflection fades over, below the floor line
    int floor_y_ = 0;
    int sub_scale_ = 0, sub_x_ = 0, sub_y_ = 0;
    int stats_scale_ = 0, stats_y_ = 0, stat_gap_ = 0;
    int tag_scale_ = 0, tag_x_ = 0, tag_y_ = 0;

    float glow_x_ = 0, glow_y_ = 0, glow_r_ = 0;
    // per-column squared distance to the glow centre, in glow radii, and the
    // rectangle the glow can possibly reach
    std::vector<float> dx2_;
    int box_x0_ = 0, box_x1_ = 0, box_y0_ = 0, box_y1_ = 0;

    void layout(int w, int h)
    {
        sub_scale_ = std::max(w / 300, 1);
        const int sub_h = text_height(sub_scale_);
        stats_scale_ = std::max(w / 440, 1);
        stat_gap_ = text_height(stats_scale_) * 3 / 2;
        tag_scale_ = stats_scale_ + 1;
        const int tag_h = text_height(tag_scale_);

        const int gap = h / 48;
        const int top = h / 40;
        const int bottom = int(float(h) * 0.90f);
        const int fixed = sub_h + 3 * stat_gap_ + tag_h + 4 * gap; // all but the wordmark
        // The wordmark's scale comes from the room it has, not from its
        // length. Height: the glyph is 7 blocks and its reflection fades over
        // half of that, so it needs 10.5 blocks. Width: never more than 45%
        // of the frame, which only binds for long names.
        logo_scale_ = std::max(std::min((bottom - top - fixed) * 2 / 21, w * 9 / 20 / text_width(lang, 1)), 3);
        const int logo_w = text_width(lang, logo_scale_);
        text_h_ = text_height(logo_scale_);
        refl_h_ = text_h_ / 2;
        logo_x_ = (w - logo_w) / 2;

        const int block_h = text_h_ + refl_h_ + fixed;
        logo_y_ = top + (bottom - top - block_h) / 2;
        floor_y_ = logo_y_ + text_h_;
        sub_y_ = floor_y_ + refl_h_ + gap;
        stats_y_ = sub_y_ + sub_h + gap;
        tag_y_ = stats_y_ + 3 * stat_gap_ + gap;
        sub_x_ = (w - text_width(sub, sub_scale_)) / 2;
        tag_x_ = (w - text_width(tag, tag_scale_)) / 2;

        glow_x_ = float(w) * 0.5f;
        glow_y_ = float(logo_y_) + float(text_h_) * 0.55f;
        glow_r_ = float(w) * 0.34f;

        // the glow is an ellipse about 1.6x wider than it is tall
        for (int x = 0; x < w; ++x) {
            const float d = (float(x) - glow_x_) / glow_r_ * 1.6f;
            dx2_[x] = d * d;
        }
        const int span_x = int(glow_r_ / 1.6f);
        const int span_y = int(glow_r_);
        box_x0_ = int(glow_x_) - span_x;
        box_x1_ = int(glow_x_) + span_x;
        box_y0_ = int(glow_y_) - span_y;
        box_y1_ = int(glow_y_) + span_y;
    }

    void backdrop(Canvas& fb, double t) const
    {
        const int w = fb.w, h = fb.h;

        // pass 1: a plain vertical ramp, one colour per row
        const float cy = float(h) * 0.5f;
        const float inv_h = 1 / float(h);
        for (int y = 0; y < h; ++y) {
            const float u = float(y) * inv_h;
            const float ny = (float(y) - cy) / cy;
            const float vig = std::max(1 - 0.32f * ny * ny, 0.45f);
            std::ranges::fill(fb.row(y), from_float((0.02f + 0.09f * u * u) * vig, (0.01f + 0.02f * u) * vig,
                                                    (0.06f + 0.14f * u) * vig));
        }

        // pass 2: the pool of light, only where it can reach
        const int by0 = std::max(box_y0_, 0), by1 = std::min(box_y1_, h);
        const int bx0 = std::max(box_x0_, 0), bx1 = std::min(box_x1_, w);
        const float pulse = 0.88f + 0.12f * float(std::sin(t * 2.2));
        for (int y = by0; y < by1; ++y) {
            const float dy = (float(y) - glow_y_) / glow_r_;
            const float dy2 = dy * dy;
            if (dy2 >= 1)
                continue;
            const auto row = fb.row(y);
            for (int x = bx0; x < bx1; ++x) {
                const float d2 = dx2_[x] + dy2;
                if (d2 >= 1)
                    continue;
                float g = 1 - d2;
                g *= g * pulse;
                const uint32_t p = row[x];
                const int32_t r = std::min(int32_t(p & 0xFF) + int32_t(g * 120), 255);
                const int32_t gg = std::min(int32_t(p >> 8 & 0xFF) + int32_t(g * 22), 255);
                const int32_t b = std::min(int32_t(p >> 16 & 0xFF) + int32_t(g * 100), 255);
                row[x] = rgb(uint32_t(r), uint32_t(gg), uint32_t(b));
            }
        }

        // stars, twinkling slowly
        for (int i = 0; const BgStar& s : stars_) {
            const int sx = int(s.x * float(w));
            const int sy = int(s.y * float(h));
            const float tw = 0.55f + 0.45f * float(std::sin(t * 1.7 + double(i++) * 0.7));
            if (sy < 0 || sy >= h || sx < 0 || sx >= w)
                continue;
            fb.additive(sy * w + sx, 0xFF40306A, uint8_t(70 * s.b * tw));
        }

        // the polished floor line the reflection lands on
        if (floor_y_ >= 0 && floor_y_ < h) {
            const auto row = fb.row(floor_y_);
            const float cx = float(w) * 0.5f;
            for (int x = 0; x < w; ++x) {
                const float fade = 1 - std::abs(float(x) - cx) / (float(w) * 0.52f);
                if (fade <= 0)
                    continue;
                const float glow = fade * fade * 0.9f;
                const uint32_t p = row[x];
                const float r = std::min(float(p & 0xFF) + 210 * glow, 255.0f);
                const float g = std::min(float(p >> 8 & 0xFF) + 110 * glow, 255.0f);
                const float b = std::min(float(p >> 16 & 0xFF) + 230 * glow, 255.0f);
                row[x] = rgb(uint32_t(r), uint32_t(g), uint32_t(b));
            }
        }
    }
};

} // namespace bb
