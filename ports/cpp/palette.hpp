// palette: 256-colour ramps interpolated from a handful of stops. Effects
// index these instead of doing colour maths per pixel: pay once, then look up.
//
// The ramps need nothing but arithmetic, so in C++ they are consteval: the
// compiler builds them, and the module carries 1 KiB of finished table per ramp
// instead of the code that makes them. Constant evaluation follows IEEE
// double rounding, so the colours are the ones Go computes at startup.
#pragma once

#include <array>
#include <cstddef>

#include "canvas.hpp"

namespace bb {

using Palette = std::array<uint32_t, 256>;

// Stop is one colour anchor at position pos in [0,1].
struct Stop {
    double pos, r, g, b;
};

// ramp takes the stops as a braced list; N is deduced from its length.
template <std::size_t N>
consteval Palette ramp(const Stop (&stops)[N])
{
    Palette p{};
    for (int i = 0; i < 256; ++i) {
        const double t = double(i) / 255;
        // find the segment containing t
        Stop a = stops[0], b = stops[N - 1];
        for (std::size_t k = 0; k + 1 < N; ++k) {
            if (t >= stops[k].pos && t <= stops[k + 1].pos) {
                a = stops[k];
                b = stops[k + 1];
                break;
            }
        }
        double u = b.pos > a.pos ? (t - a.pos) / (b.pos - a.pos) : 0;
        u = clamp01(u);
        u = u * u * (3 - 2 * u); // smoothstep keeps gradients from banding
        p[i] = from_float(a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u);
    }
    return p;
}

// at returns the colour at t in [0,1], clamped.
constexpr uint32_t at(const Palette& p, double t)
{
    const int i = int(t * 255);
    return p[i < 0 ? 0 : i > 255 ? 255 : i];
}

// Sunset: the demo's signature ramp. Deep violet to hot orange to cream.
inline constexpr Palette sunset = ramp({
    {0.00, 0.02, 0.00, 0.06},
    {0.18, 0.25, 0.02, 0.38},
    {0.38, 0.72, 0.05, 0.45},
    {0.56, 0.98, 0.25, 0.22},
    {0.74, 1.00, 0.62, 0.15},
    {0.88, 1.00, 0.93, 0.55},
    {1.00, 1.00, 1.00, 0.96},
});

// Ice: cold counterpart used by the tunnel and the mandelbrot.
inline constexpr Palette ice = ramp({
    {0.00, 0.00, 0.00, 0.03},
    {0.25, 0.00, 0.10, 0.30},
    {0.50, 0.00, 0.55, 0.85},
    {0.72, 0.35, 0.90, 1.00},
    {0.90, 0.80, 1.00, 1.00},
    {1.00, 1.00, 1.00, 1.00},
});

// Ember: fire ramp.
inline constexpr Palette ember = ramp({
    {0.00, 0.00, 0.00, 0.00},
    {0.20, 0.25, 0.00, 0.00},
    {0.45, 0.80, 0.10, 0.00},
    {0.68, 1.00, 0.45, 0.00},
    {0.85, 1.00, 0.80, 0.15},
    {1.00, 1.00, 1.00, 0.85},
});

struct Rgb {
    double r, g, b;
};

// hsl_to_rgb converts hue, saturation and lightness (all 0..1) to RGB.
constexpr Rgb hsl_to_rgb(double h, double s, double l)
{
    if (s == 0)
        return {l, l, l};
    const double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const double p = 2 * l - q;
    auto hue = [p, q](double t) {
        if (t < 0)
            t += 1;
        if (t > 1)
            t -= 1;
        if (t < 1.0 / 6)
            return p + (q - p) * 6 * t;
        if (t < 1.0 / 2)
            return q;
        if (t < 2.0 / 3)
            return p + (q - p) * (2.0 / 3 - t) * 6;
        return p;
    };
    return {hue(h + 1.0 / 3), hue(h), hue(h - 1.0 / 3)};
}

} // namespace bb
