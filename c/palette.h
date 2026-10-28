// palette: 256-entry colour ramps built from a handful of stops. Effects index
// these instead of doing per-pixel colour maths, the classic demoscene trade:
// pay once at load, then look up.
#ifndef BABELTRO_PALETTE_H
#define BABELTRO_PALETTE_H

#include <stdint.h>

typedef uint32_t palette[256];

extern palette pal_sunset; // deep violet to hot orange to cream
extern palette pal_ice;    // cold counterpart: tunnel and mandelbrot
extern palette pal_ember;  // fire

// palette_init builds the ramps; call it once at startup.
void palette_init(void);

// pal_at returns the colour at t in [0,1], clamped to the ends.
static inline uint32_t pal_at(const palette p, double t)
{
    int i = (int)(t * 255);
    if (i < 0)
        i = 0;
    else if (i > 255)
        i = 255;
    return p[i];
}

// hsl_to_rgb converts hue/saturation/lightness (all 0..1) to RGB in 0..1.
void hsl_to_rgb(double h, double s, double l, double *r, double *g, double *b);

#endif
