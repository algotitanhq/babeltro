// Plasma: four summed sine fields, the oldest trick in the demoscene book.
// Done naively it is four sin() calls per pixel; here three of the four terms
// are 1D tables rebuilt once per frame, leaving a single lookup per pixel.
#include <math.h>

#include "fx.h"

static struct {
    float *rad;            // distance to the centre, per pixel (built once)
    float *sx, *sy, *sxy;  // per-column, per-row and per-diagonal sines
    float phase;
    // the ladder: 1 calls sinf() four times per pixel, 2 reads the sine
    // table four times per pixel, 3 (the default) moves three of the four
    // lookups into per-frame 1D tables
    int step;
} P;

static void set_step(int n) { P.step = n; }

static void start(int w, int h)
{
    P.step = 0;
    fx_resize(P.rad, w * h);
    fx_resize(P.sx, w);
    fx_resize(P.sy, h);
    fx_resize(P.sxy, w + h);

    float cx = (float)w * 0.5f, cy = (float)h * 0.5f;
    float k = 44.0f / (float)(w + h);
    float *r = P.rad;
    for (int y = 0; y < h; y++) {
        float dy = (float)y - cy;
        for (int x = 0; x < w; x++) {
            float dx = (float)x - cx;
            *r++ = sqrtf(dx * dx + dy * dy) * k;
        }
    }
}

// tables rebuilds the 1D sine terms for this frame.
static void tables(const fx_state *s, int w, int h)
{
    float t = (float)s->beat;
    float kx = 26.0f / (float)w;
    float ky = 26.0f / (float)h;
    for (int x = 0; x < w; x++)
        P.sx[x] = fm_sin((float)x * kx + t * 1.3f);
    for (int y = 0; y < h; y++)
        P.sy[y] = fm_sin((float)y * ky * 1.35f - t * 1.1f);
    for (int i = 0; i < w + h; i++)
        P.sxy[i] = fm_sin((float)i * kx * 0.85f + t * 0.8f);
    P.phase = t * 2.6f;
}

// render_sin is the plasma as you would first write it: every term, every
// pixel, straight from the maths library. Slow, and the reference for what
// the table approximates.
static void render_sin(canvas *fb, const fx_state *s)
{
    int w = fb->w, h = fb->h;
    float t = (float)s->beat;
    float kx = 26.0f / (float)w, ky = 26.0f / (float)h;
    float kr = 44.0f / (float)(w + h);
    float cx = (float)w * 0.5f, cy = (float)h * 0.5f;
    float phase = t * 2.6f;

    // @excerpt PLASMA/1
    for (int y = 0; y < h; y++) {
        float dy = (float)y - cy;
        for (int x = 0; x < w; x++) {
            float dx = (float)x - cx;
            float rad = sqrtf(dx * dx + dy * dy) * kr;
            float v = sinf((float)x * kx + t * 1.3f) +
                      sinf((float)y * ky * 1.35f - t * 1.1f) +
                      sinf((float)(x + y) * kx * 0.85f + t * 0.8f) +
                      sinf(rad + phase);
            int i = (int)(v * 36 + 127.5f);
            if (i < 0)
                i = 0;
            else if (i > 255)
                i = 255;
            fb->pix[y * w + x] = pal_sunset[i];
        }
    }
    // @end
}

// render_table keeps the per-pixel structure of render_sin but reads the
// sine table instead of calling sinf(). Same arguments, so the same pixels
// as the optimised version; the only change is the table's precision.
static void render_table(canvas *fb, const fx_state *s)
{
    int w = fb->w, h = fb->h;
    float t = (float)s->beat;
    float kx = 26.0f / (float)w, ky = 26.0f / (float)h;
    float kr = 44.0f / (float)(w + h);
    float cx = (float)w * 0.5f, cy = (float)h * 0.5f;
    float phase = t * 2.6f;

    // @excerpt PLASMA/2
    for (int y = 0; y < h; y++) {
        float dy = (float)y - cy;
        for (int x = 0; x < w; x++) {
            float dx = (float)x - cx;
            float rad = sqrtf(dx * dx + dy * dy) * kr;
            float v = fm_sin((float)x * kx + t * 1.3f) +
                      fm_sin((float)y * ky * 1.35f - t * 1.1f) +
                      fm_sin((float)(x + y) * kx * 0.85f + t * 0.8f) +
                      fm_sin(rad + phase);
            int i = (int)(v * 36 + 127.5f);
            if (i < 0)
                i = 0;
            else if (i > 255)
                i = 255;
            fb->pix[y * w + x] = pal_sunset[i];
        }
    }
    // @end
}

static void render(canvas *fb, const fx_state *s)
{
    switch (P.step) {
    case 1:
        render_sin(fb, s);
        return;
    case 2:
        render_table(fb, s);
        return;
    }
    int w = fb->w, h = fb->h;
    tables(s, w, h);
    const float *restrict sx = P.sx;
    float phase = P.phase;

    // @excerpt PLASMA
    for (int y = 0; y < h; y++) {
        // row pointers: the diagonal term for pixel x of row y is sxy[x + y]
        float sy = P.sy[y];
        const float *restrict rad = P.rad + y * w;
        const float *restrict sxy = P.sxy + y;
        uint32_t *restrict row = fb->pix + y * w;
        for (int x = 0; x < w; x++) {
            float v = sx[x] + sy + sxy[x] + fm_sin(rad[x] + phase);
            int i = (int)(v * 36 + 127.5f);
            if (i < 0)
                i = 0;
            else if (i > 255)
                i = 255;
            row[x] = pal_sunset[i];
        }
    }
    // @end
}

const effect fx_plasma = {"PLASMA", start, render, set_step};
