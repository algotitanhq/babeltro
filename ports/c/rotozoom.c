// Rotozoom: the purest demoscene move. Build a texture once, then every frame
// rotate and zoom the sampling grid over it. Cost per pixel is a few
// multiplies and one lookup.
#include <math.h>

#include "fx.h"

enum { TEX_SIZE = 512, TEX_MASK = TEX_SIZE - 1 };

// The texture depends on nothing, so it is built on the first start and
// kept: 1 MiB of static storage instead of a heap allocation.
static uint32_t tex[TEX_SIZE * TEX_SIZE];
static bool tex_ready;

// build_texture makes a tileable rainbow plasma. It costs a few hundred
// thousand sine calls; doing the same work per frame would cost the whole
// budget, which is the point of the scene.
static void build_texture(void)
{
    const double two_pi = 2 * FM_PI;
    for (int y = 0; y < TEX_SIZE; y++) {
        double fy = (float)y / TEX_SIZE; // Go rounds the coordinates to float32
        for (int x = 0; x < TEX_SIZE; x++) {
            double fx = (float)x / TEX_SIZE;
            // the pattern has to wrap every 512 pixels, so every frequency is
            // a whole number of cycles per tile
            double v = sin(fx * two_pi * 3 + fy * two_pi * 2) * 0.5 +
                       sin(fy * two_pi * 5 - fx * two_pi * 4) * 0.3 +
                       sin((fx + fy) * two_pi * 7) * 0.2;
            // concentric rings, also periodic in the tile
            double dx = x - TEX_SIZE / 2, dy = y - TEX_SIZE / 2;
            double rr = sqrt(dx * dx + dy * dy) / TEX_SIZE * 12;
            v += sin(rr * two_pi) * 0.35;

            double hue = fmod(v * 0.55 + 0.5, 1);
            if (hue < 0)
                hue += 1;
            double r, g, b;
            hsl_to_rgb(hue, 0.70, 0.48 + 0.14 * v, &r, &g, &b);

            // a dark grid over the colour: without a straight edge the
            // rotation and the zoom read as random shimmer instead of motion
            if (x % (TEX_SIZE / 8) < 3 || y % (TEX_SIZE / 8) < 3) {
                r *= 0.28;
                g *= 0.28;
                b *= 0.28;
            }
            tex[y * TEX_SIZE + x] = rgb_from_float(r, g, b);
        }
    }
    tex_ready = true;
}

static void start(int w, int h)
{
    (void)w, (void)h;
    if (!tex_ready)
        build_texture();
}

static void render(canvas *fb, const fx_state *s)
{
    float t = (float)s->beat;
    float ang = t * 0.45f;
    float cos_a = fm_cos(ang), sin_a = fm_sin(ang);
    // breathing zoom, 0.45 .. 1.35, folded with the per-pixel scale
    float zoom = (0.55f + 0.45f * fm_sin(t * 0.7f) + 0.35f) / (float)fb->w * 6.5f;
    float offx = fm_sin(t * 0.31f) * 180 + t * 26;
    float offy = fm_cos(t * 0.27f) * 180 + t * 19;

    int w = fb->w, h = fb->h;
    float cx = (float)w * 0.5f, cy = (float)h * 0.5f;

    // @excerpt ROTOZOOM
    for (int y = 0; y < h; y++) {
        float dy = (float)y - cy;
        uint32_t *restrict row = fb->pix + y * w;
        for (int x = 0; x < w; x++) {
            float dx = (float)x - cx;
            // rotate the screen offset, scale it, then wrap into the tile
            float tx = (dx * cos_a - dy * sin_a) * zoom * 34;
            float ty = (dx * sin_a + dy * cos_a) * zoom * 34;
            int ix = (int)(tx + offx) & TEX_MASK;
            int iy = (int)(ty + offy) & TEX_MASK;
            row[x] = tex[iy * TEX_SIZE + ix];
        }
    }
    // @end
}

const effect fx_rotozoom = {"ROTOZOOM", start, render, NULL};
