// Fire: the Doom fire algorithm. A heat buffer is seeded at the bottom row
// and diffused upward with a little random sideways drift. It is integer
// only, one byte per pixel, and reads beautifully through a palette ramp.
#include <string.h>

#include "fx.h"

static struct {
    uint8_t *heat; // one byte per pixel, carried from frame to frame
    uint32_t rng;
} F;

static void start(int w, int h)
{
    fx_resize(F.heat, w * h);
    memset(F.heat, 0, (size_t)w * h);
    F.rng = 0x9E3779B9;
}

// xorshift32, inlined: vastly cheaper than rand() in a per-pixel loop, and
// the same sequence in every language.
static inline uint32_t next(void)
{
    uint32_t x = F.rng;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return F.rng = x;
}

static void render(canvas *fb, const fx_state *s)
{
    int w = fb->w, h = fb->h;
    uint8_t *restrict heat = F.heat;
    uint32_t *restrict pix = fb->pix;
    const uint32_t *pal = pal_ember;

    // seed the hottest row: a slow horizontal wave gives the fire its uneven
    // base, the random term keeps the tongues from looking periodic
    uint8_t *last = heat + (h - 1) * w;
    float t = (float)s->frame * 0.05f;
    for (int x = 0; x < w; x++) {
        float fx = (float)x / (float)w;
        float wave = 0.5f + 0.5f * fm_sin(fx * 11 + t) * 0.6f +
                     0.5f * fm_sin(fx * 23 - t * 1.7f) * 0.4f;
        float v = 150 + wave * 90 + (float)(next() & 31) - 16;
        if (v > 255)
            v = 255;
        else if (v < 90)
            v = 90;
        last[x] = (uint8_t)v;
    }
    for (int x = 0; x < w; x++)
        pix[(h - 1) * w + x] = pal[last[x]];

    // diffuse upward: every destination pixel takes one value from the row
    // below, offset sideways by a random -1/0/+1. Gather, not scatter, so each
    // pixel is written exactly once: no holes, no salt-and-pepper noise.
    // Each row goes through the palette as soon as it is complete, so the
    // buffer is walked once per frame instead of twice.
    // @excerpt FIRE
    for (int y = h - 1; y > 0; y--) {
        const uint8_t *src = heat + y * w;
        uint8_t *dst = heat + (y - 1) * w;
        for (int x = 0; x < w; x++) {
            if (src[x] == 0) { // cold below: no random draw, stay cold
                dst[x] = 0;
                continue;
            }
            uint32_t r = next();
            int sx = x + (int)(r % 3) - 1; // -1, 0 or +1, no average drift
            if (sx < 0)
                sx = 0;
            else if (sx >= w)
                sx = w - 1;
            uint8_t v = src[sx];
            uint8_t decay = r >> 16 & 1;
            dst[x] = v > decay ? v - decay : 0;
        }
        uint32_t *prow = pix + (y - 1) * w;
        for (int x = 0; x < w; x++)
            prow[x] = pal[dst[x]];
    }
    // @end
}

const effect fx_fire = {"FIRE", start, render, NULL};
