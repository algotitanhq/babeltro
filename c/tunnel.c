// Tunnel: every pixel is mapped to polar coordinates once, at start. After
// that the per-pixel work is a couple of table lookups and a palette read:
// the geometry is free, which is why it can afford to look this good.
#include "fx.h"

static struct {
    float *depth; // falls off as 1/r: large at the centre, small at the edge
    float *angle; // atan2 as a fraction of a turn, [0,1)
} T;

static void start(int w, int h)
{
    fx_resize(T.depth, w * h);
    fx_resize(T.angle, w * h);
    // scale with the diagonal so the rings look the same at any resolution
    fm_dist_inv_table(T.depth, w, h, (float)(w + h) * 2.2f, (float)(w + h) * 0.02f);
    fm_atan2_table(T.angle, w, h);
}

static void render(canvas *fb, const fx_state *s)
{
    int n = fb->w * fb->h;
    uint32_t *restrict pix = fb->pix;
    const float *restrict depth = T.depth, *restrict angle = T.angle;
    float tm = (float)s->beat;
    float adv = tm * 3.0f;
    float spin = tm * 0.25f;

    // The tables are laid out like the framebuffer, so one flat index walks
    // all three.
    // @excerpt TUNNEL
    for (int i = 0; i < n; i++) {
        float u = depth[i] + adv; // scroll towards the viewer
        float v = angle[i];

        // rings along the depth axis
        float ring = fm_sin01(u * 0.16f);
        // spokes that twist as they recede
        float twist = v * 12 + u * 0.09f + spin;
        float spoke = fm_sin01(twist);

        float val = ring * 0.55f + spoke * 0.45f;
        // brick checker gives the walls their structure
        if (((int)(u * 0.32f) + (int)twist) & 1)
            val = -val * 0.7f;

        float fog = 1 / (1 + u * 0.02f);
        float lum = (val * 0.5f + 0.5f) * fog;
        int idx = (int)(lum * 300);
        if (idx > 255)
            idx = 255;
        if (idx < 0)
            idx = 0;
        pix[i] = pal_ice[idx];
    }
    // @end
}

const effect fx_tunnel = {"TUNNEL", start, render};
