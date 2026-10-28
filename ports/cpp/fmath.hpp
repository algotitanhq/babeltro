// fmath: the numeric shortcuts every effect leans on. Calling sin() a million
// times per frame is the difference between 20 ms and 1 ms, so the hot loops
// read a sine table instead, and every random number comes from xorshift32.
#pragma once

#include <array>
#include <cmath>
#include <cstdint>
#include <numbers>
#include <span>

namespace bb::fmath {

inline constexpr int tab_bits = 13;
inline constexpr int tab_size = 1 << tab_bits;
inline constexpr int tab_mask = tab_size - 1;
// Radians to table steps. Go folds TabSize/(2*Pi) exactly and rounds once to
// float32; rounding the double quotient instead gives the same float.
inline constexpr float inv2pi = float(tab_size / (2 * std::numbers::pi));

// One extra entry so a full period wraps exactly.
using Table = std::array<float, tab_size + 1>;

// The tables are not constexpr: libc++'s std::sin is not usable in constant
// evaluation, and a hand-written constexpr series would be our own maths
// library, not the language's. So they are built once, when the host calls
// _initialize, which runs the module's static initialisers.
inline Table make_table(double (*f)(double))
{
    Table tab{};
    for (int i = 0; i <= tab_size; ++i)
        tab[i] = float(f(2 * std::numbers::pi * i / tab_size));
    tab[tab_size] = tab[0]; // guarantee a full period overflows exactly
    return tab;
}
inline const Table sin_tab = make_table([](double a) { return std::sin(a); });
inline const Table cos_tab = make_table([](double a) { return std::cos(a); });

// The lookups truncate toward zero, like Go's int(), and then wrap with the
// mask, which on two's complement also handles negative angles. Every angle
// the effects pass stays far inside int range, where the conversion is
// defined.

// sin returns sin(a) from the table, a in radians.
inline float sin(float a) { return sin_tab[int(a * inv2pi) & tab_mask]; }

// cos returns cos(a) from the table, a in radians.
inline float cos(float a) { return cos_tab[int(a * inv2pi) & tab_mask]; }

// sin01 returns sin(2*pi*t) for t in turns.
inline float sin01(float t) { return sin_tab[int(t * tab_size) & tab_mask]; }

// atan2_turns returns atan2(y, x) as a fraction of a full turn, in [0,1).
inline float atan2_turns(float y, float x)
{
    const float a = float(std::atan2(double(y), double(x)));
    return a / float(2 * std::numbers::pi) + 0.5f;
}

// atan2_table fills tab (w*h, row-major) with the turn fraction of every
// pixel around the centre of the grid.
inline void atan2_table(std::span<float> tab, int w, int h)
{
    const float cx = float(w) / 2, cy = float(h) / 2;
    auto out = tab.begin();
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            *out++ = atan2_turns(float(y) - cy, float(x) - cx);
}

// dist_inv_table fills tab with scale/(r+softness), r being the distance to
// the centre. The softness term tames the singularity there. std::sqrt on a
// float is correctly rounded, so it equals Go's float32(math.Sqrt(...)).
inline void dist_inv_table(std::span<float> tab, int w, int h, float scale, float softness)
{
    const float cx = float(w) / 2, cy = float(h) / 2;
    auto out = tab.begin();
    for (int y = 0; y < h; ++y) {
        const float dy = float(y) - cy;
        for (int x = 0; x < w; ++x) {
            const float dx = float(x) - cx;
            *out++ = scale / (std::sqrt(dx * dx + dy * dy) + softness);
        }
    }
}

// Rng is xorshift32: three shifts and three xors give the same sequence in
// every language, which no standard library generator promises. The state
// must never be zero.
class Rng {
public:
    constexpr explicit Rng(std::uint32_t seed) : state_{seed} {}

    constexpr std::uint32_t next()
    {
        std::uint32_t x = state_;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        return state_ = x;
    }

    // unit returns a number in [0,1) built from the top 24 bits, so the
    // conversion to float is exact.
    constexpr float unit() { return float(next() >> 8) * 0x1p-24f; }

private:
    std::uint32_t state_;
};

} // namespace bb::fmath
