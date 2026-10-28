// canvas: the framebuffer every effect draws into, the colour packing, and
// the 5x7 bitmap font the finale writes with.
//
// Pixels are 0xAABBGGRR in a uint32_t: R, G, B, A in little-endian memory,
// exactly an ImageData buffer, so the host copies them without converting.
#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>
#include <vector>

namespace bb {

using std::int32_t;
using std::uint32_t;
using std::uint64_t;
using std::uint8_t;

// rgb packs a colour with alpha 0xFF.
constexpr uint32_t rgb(uint32_t r, uint32_t g, uint32_t b)
{
    return 0xFF000000u | b << 16 | g << 8 | r;
}

constexpr double clamp01(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

// to_byte maps [0,1] to 0..255 with rounding, clamping outside.
constexpr uint8_t to_byte(double v)
{
    if (v <= 0)
        return 0;
    if (v >= 1)
        return 255;
    return uint8_t(v * 255 + 0.5);
}

// from_float packs normalised channels. It takes doubles, as Go's does: a
// float argument widens exactly, so callers never round twice.
constexpr uint32_t from_float(double r, double g, double b)
{
    return rgb(to_byte(r), to_byte(g), to_byte(b));
}

// Text metrics: glyphs are 5 pixels wide plus a 1 pixel gap, 7 tall.
constexpr int text_width(std::string_view s, int scale)
{
    return s.empty() ? 0 : (int(s.size()) * 6 - 1) * scale;
}
constexpr int text_height(int scale) { return 7 * scale; }

// Canvas owns the pixels. It is resized only by bb_init, so its storage, and
// the address the host reads from, never moves while scenes run.
struct Canvas {
    int w = 0, h = 0;
    std::vector<uint32_t> pix;

    void resize(int width, int height)
    {
        w = width;
        h = height;
        pix.assign(std::size_t(w) * std::size_t(h), 0);
    }

    // row is one line of pixels: Go's fb.Pix[y*w : (y+1)*w].
    std::span<uint32_t> row(int y) { return std::span(pix).subspan(std::size_t(y) * w, w); }

    // additive adds c scaled by intensity/255, saturating per channel.
    void additive(int i, uint32_t c, uint8_t intensity);
    void hline(int x, int y, int len, uint32_t c);

    void draw_text(int x, int y, std::string_view s, int scale, uint32_t c);
    // draw_text_gradient draws s with a three-stop vertical ramp, each glyph
    // at its own baseline offset; scan darkens every fourth row.
    void draw_text_gradient(int x, int y, std::string_view s, int scale, uint32_t top,
                            uint32_t mid, uint32_t bottom, std::span<const int> offs, bool scan);
    // draw_text_outline draws s shifted one pixel in each cardinal direction.
    void draw_text_outline(int x, int y, std::string_view s, int scale, uint32_t c,
                           std::span<const int> offs);
    // draw_text_reflect adds a mirrored copy of s below the line y, fading
    // out over depth rows.
    void draw_text_reflect(int x, int y, std::string_view s, int scale, uint32_t top,
                           uint32_t bottom, std::span<const int> offs, uint8_t strength, int depth);
};

} // namespace bb
