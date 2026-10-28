#include "canvas.hpp"

#include <algorithm>
#include <array>
#include <optional>

namespace bb {
namespace {

// The 5x7 font, written out as text exactly as in Go: "CHAR row0 ... row6",
// one character per pixel, MSB first. Go parses it in init(); here a
// consteval function parses it while compiling, and only the 665 bytes of
// glyphs reach the module.
constexpr std::string_view font_src = R"font(
SPACE 00000 00000 00000 00000 00000 00000 00000
! 00100 00100 00100 00100 00100 00000 00100
" 01010 01010 01010 00000 00000 00000 00000
# 01010 01010 11111 01010 11111 01010 01010
$ 00100 01111 10100 01110 00101 11110 00100
% 11001 11010 00010 00100 01000 01011 10011
& 01100 10010 10100 01000 10101 10010 01101
' 00100 00100 01000 00000 00000 00000 00000
( 00010 00100 01000 01000 01000 00100 00010
) 01000 00100 00010 00010 00010 00100 01000
* 00000 10101 01110 11111 01110 10101 00000
+ 00000 00100 00100 11111 00100 00100 00000
, 00000 00000 00000 00000 01100 01100 11000
- 00000 00000 00000 11111 00000 00000 00000
. 00000 00000 00000 00000 00000 01100 01100
/ 00001 00010 00010 00100 01000 01000 10000
0 01110 10001 10011 10101 11001 10001 01110
1 00100 01100 00100 00100 00100 00100 01110
2 01110 10001 00001 00110 01000 10000 11111
3 11111 00010 00100 00010 00001 10001 01110
4 00010 00110 01010 10010 11111 00010 00010
5 11111 10000 11110 00001 00001 10001 01110
6 00110 01000 10000 11110 10001 10001 01110
7 11111 00001 00010 00100 01000 01000 01000
8 01110 10001 10001 01110 10001 10001 01110
9 01110 10001 10001 01111 00001 00010 01100
: 00000 01100 01100 00000 01100 01100 00000
; 00000 01100 01100 00000 01100 00100 01000
< 00010 00100 01000 10000 01000 00100 00010
= 00000 00000 11111 00000 11111 00000 00000
> 01000 00100 00010 00001 00010 00100 01000
? 01110 10001 00001 00110 00100 00000 00100
@ 01110 10001 10111 10101 10111 10000 01110
A 01110 10001 10001 11111 10001 10001 10001
B 11110 10001 10001 11110 10001 10001 11110
C 01110 10001 10000 10000 10000 10001 01110
D 11110 10001 10001 10001 10001 10001 11110
E 11111 10000 10000 11110 10000 10000 11111
F 11111 10000 10000 11110 10000 10000 10000
G 01110 10001 10000 10111 10001 10001 01111
H 10001 10001 10001 11111 10001 10001 10001
I 11111 00100 00100 00100 00100 00100 11111
J 00111 00010 00010 00010 00010 10010 01100
K 10001 10010 10100 11000 10100 10010 10001
L 10000 10000 10000 10000 10000 10000 11111
M 10001 11011 10101 10101 10001 10001 10001
N 10001 11001 10101 10011 10001 10001 10001
O 01110 10001 10001 10001 10001 10001 01110
P 11110 10001 10001 11110 10000 10000 10000
Q 01110 10001 10001 10001 10101 10010 01101
R 11110 10001 10001 11110 10100 10010 10001
S 01111 10000 10000 01110 00001 00001 11110
T 11111 00100 00100 00100 00100 00100 00100
U 10001 10001 10001 10001 10001 10001 01110
V 10001 10001 10001 10001 10001 01010 00100
W 10001 10001 10001 10101 10101 10101 01010
X 10001 10001 01010 00100 01010 10001 10001
Y 10001 10001 01010 00100 00100 00100 00100
Z 11111 00001 00010 00100 01000 10000 11111
[ 01110 01000 01000 01000 01000 01000 01110
\ 10000 01000 01000 00100 00010 00010 00001
] 01110 00010 00010 00010 00010 00010 01110
^ 00100 01010 10001 00000 00000 00000 00000
_ 00000 00000 00000 00000 00000 00000 11111
{ 00110 00100 01000 01000 01000 00100 00110
| 00100 00100 00100 00100 00100 00100 00100
} 01100 00100 00010 00010 00010 00100 01100
~ 00000 00000 01000 10101 00010 00000 00000
)font";

using Glyph = std::array<uint8_t, 7>;
using Font = std::array<Glyph, 95>; // ' ' to '~'

consteval Font parse_font(std::string_view src)
{
    Font font{};
    while (!src.empty()) {
        const auto eol = std::min(src.find('\n'), src.size());
        std::string_view line = src.substr(0, eol);
        src.remove_prefix(std::min(eol + 1, src.size()));

        std::array<std::string_view, 8> fields{};
        std::size_t n = 0;
        while (!line.empty()) {
            const auto start = line.find_first_not_of(' ');
            if (start == line.npos)
                break;
            line.remove_prefix(start);
            const auto len = std::min(line.find(' '), line.size());
            if (n < fields.size())
                fields[n] = line.substr(0, len);
            ++n;
            line.remove_prefix(len);
        }
        if (n != fields.size())
            continue;

        const char ch = fields[0] == "SPACE" ? ' ' : fields[0][0];
        Glyph& g = font[std::size_t(ch - ' ')];
        for (std::size_t r = 0; r < 7; ++r)
            for (std::size_t c = 0; c < 5; ++c)
                if (fields[r + 1][c] == '1')
                    g[r] |= uint8_t(1 << (4 - c));
    }
    return font;
}

constexpr Font font = parse_font(font_src);
constexpr int glyph_w = 5;
constexpr int glyph_gap = 1;

// glyph returns the font entry for ch, folding lowercase to uppercase.
constexpr const Glyph* glyph(char ch)
{
    if (ch >= 'a' && ch <= 'z')
        ch = char(ch - 'a' + 'A');
    const int idx = ch - ' ';
    return idx >= 0 && idx < int(font.size()) ? &font[std::size_t(idx)] : nullptr;
}

constexpr bool lit(uint8_t bits, int col) { return bits & (1 << (4 - col)); }

// Block is the visible part of one scale x scale font dot: rows [y0, y1),
// columns [x0, x1).
struct Block {
    int y0, y1, x0, x1;
};

// clip clips a dot once, so the loops after it write straight runs instead
// of testing bounds per pixel.
std::optional<Block> clip(const Canvas& fb, int px, int py, int scale)
{
    const Block b{std::max(py, 0), std::min(py + scale, fb.h), std::max(px, 0),
                  std::min(px + scale, fb.w)};
    if (b.y0 < b.y1 && b.x0 < b.x1)
        return b;
    return std::nullopt;
}

struct Channels {
    uint32_t r, g, b;
    explicit constexpr Channels(uint32_t c) : r{c & 0xFF}, g{c >> 8 & 0xFF}, b{c >> 16 & 0xFF} {}
};

// lerp goes from a to b in float, as Go's text code does, and truncates.
constexpr uint32_t lerp(uint32_t a, uint32_t b, float u)
{
    return uint32_t(float(a) + (float(b) - float(a)) * u);
}

int offset(std::span<const int> offs, std::size_t i) { return i < offs.size() ? offs[i] : 0; }

} // namespace

void Canvas::additive(int i, uint32_t c, uint8_t intensity)
{
    if (intensity == 0)
        return;
    const Channels p{pix[std::size_t(i)]}, k{c};
    const uint32_t r = p.r + k.r * intensity / 255;
    const uint32_t g = p.g + k.g * intensity / 255;
    const uint32_t b = p.b + k.b * intensity / 255;
    pix[std::size_t(i)] = rgb(std::min(r, 255u), std::min(g, 255u), std::min(b, 255u));
}

void Canvas::hline(int x, int y, int len, uint32_t c)
{
    if (y < 0 || y >= h)
        return;
    auto line = row(y);
    for (int xx = std::max(x, 0); xx < std::min(x + len, w); ++xx)
        line[std::size_t(xx)] = c;
}

void Canvas::draw_text(int x, int y, std::string_view s, int scale, uint32_t c)
{
    scale = std::max(scale, 1);
    int cx = x;
    for (const char ch : s) {
        const Glyph* g = glyph(ch);
        if (!g) {
            cx += glyph_w * scale;
            continue;
        }
        for (int r = 0; r < 7; ++r) {
            for (int col = 0; col < 5; ++col) {
                if (!lit((*g)[std::size_t(r)], col))
                    continue;
                if (const auto b = clip(*this, cx + col * scale, y + r * scale, scale))
                    for (int yy = b->y0; yy < b->y1; ++yy)
                        std::ranges::fill(row(yy).subspan(std::size_t(b->x0), std::size_t(b->x1 - b->x0)), c);
            }
        }
        cx += (glyph_w + glyph_gap) * scale;
    }
}

void Canvas::draw_text_gradient(int x, int y, std::string_view s, int scale, uint32_t top,
                                uint32_t mid, uint32_t bottom, std::span<const int> offs, bool scan)
{
    scale = std::max(scale, 1);
    const Channels t{top}, m{mid}, b{bottom};
    const int total_h = 7 * scale;
    int cx = x;
    for (std::size_t i = 0; i < s.size(); ++i, cx += (glyph_w + glyph_gap) * scale) {
        const Glyph* g = glyph(s[i]);
        if (!g)
            continue;
        const int dy = offset(offs, i);
        for (int r = 0; r < 7; ++r) {
            for (int col = 0; col < 5; ++col) {
                if (!lit((*g)[std::size_t(r)], col))
                    continue;
                const auto blk = clip(*this, cx + col * scale, y + r * scale + dy, scale);
                if (!blk)
                    continue;
                for (int yy = blk->y0; yy < blk->y1; ++yy) {
                    const float f = std::clamp(float(yy - y) / float(total_h), 0.0f, 1.0f);
                    uint32_t cr, cg, cb;
                    if (f < 0.5f) {
                        const float u = f * 2;
                        cr = lerp(t.r, m.r, u), cg = lerp(t.g, m.g, u), cb = lerp(t.b, m.b, u);
                    } else {
                        const float u = (f - 0.5f) * 2;
                        cr = lerp(m.r, b.r, u), cg = lerp(m.g, b.g, u), cb = lerp(m.b, b.b, u);
                    }
                    if (scan && (yy & 3) == 0)
                        cr = cr * 3 / 4, cg = cg * 3 / 4, cb = cb * 3 / 4;
                    std::ranges::fill(row(yy).subspan(std::size_t(blk->x0), std::size_t(blk->x1 - blk->x0)),
                                      rgb(cr, cg, cb));
                }
            }
        }
    }
}

void Canvas::draw_text_outline(int x, int y, std::string_view s, int scale, uint32_t c,
                               std::span<const int> offs)
{
    constexpr int dirs[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
    for (std::size_t i = 0; i < s.size(); ++i) {
        const int gx = x + int(i) * (glyph_w + glyph_gap) * scale;
        const int gy = y + offset(offs, i);
        for (const auto& d : dirs)
            draw_text(gx + d[0], gy + d[1], s.substr(i, 1), scale, c);
    }
}

void Canvas::draw_text_reflect(int x, int y, std::string_view s, int scale, uint32_t top,
                               uint32_t bottom, std::span<const int> offs, uint8_t strength, int depth)
{
    scale = std::max(scale, 1);
    depth = std::max(depth, 1);
    const Channels t{top}, b{bottom};
    int cx = x;
    for (std::size_t i = 0; i < s.size(); ++i, cx += (glyph_w + glyph_gap) * scale) {
        const Glyph* g = glyph(s[i]);
        if (!g)
            continue;
        const int dy = offset(offs, i);
        for (int r = 0; r < 7; ++r) {
            // mirrored: glyph row 0 sits at the far end, and a letter lifted
            // by dy has its reflection pushed down by as much
            const int py = y + (6 - r) * scale - dy;
            for (int col = 0; col < 5; ++col) {
                if (!lit((*g)[std::size_t(r)], col))
                    continue;
                const auto blk = clip(*this, cx + col * scale, py, scale);
                if (!blk)
                    continue;
                for (int yy = blk->y0; yy < blk->y1; ++yy) {
                    const float d = float(yy - y) / float(depth);
                    if (d > 1)
                        continue;
                    float a = 1 - d;
                    a *= a;
                    const auto inten = uint8_t(float(strength) * a);
                    if (inten == 0)
                        continue;
                    const uint32_t c = rgb(lerp(t.r, b.r, d), lerp(t.g, b.g, d), lerp(t.b, b.b, d));
                    const int base = yy * w;
                    for (int xx = blk->x0; xx < blk->x1; ++xx)
                        additive(base + xx, c, inten);
                }
            }
        }
    }
}

} // namespace bb
