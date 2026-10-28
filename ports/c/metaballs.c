// Metaballs: sum radial fields and shade the iso-contours. Every pixel
// evaluates sum(r^2 / d^2) with one division per ball and no square root,
// and the contour band gets a hot rim so the blobs read as liquid rather than
// as a flat gradient.
#include "fx.h"

enum { BALLS = 6 };

static void start(int w, int h) { (void)w, (void)h; }

static void render(canvas *fb, const fx_state *s)
{
    int w = fb->w, h = fb->h;
    float t = (float)s->beat;
    // x is scaled by width/height so a circle in field space is a circle on
    // screen, whatever the aspect ratio
    float asp = (float)w / (float)h;

    // Ball centres relative to the screen centre, in the same units as the
    // pixel coordinates below, and the squared radii: the field is about 1
    // on a ball's own surface.
    float bx[BALLS], by[BALLS], rad2[BALLS];
    for (int i = 0; i < BALLS; i++) {
        float fi = (float)i;
        // each ball orbits on its own ellipse and breathes
        float a = t * (0.35f + fi * 0.07f) + fi * 2.1f;
        float x = 0.5f + 0.20f * fm_cos(a) * (1 + 0.3f * fm_sin(t * 0.5f + fi));
        float y = 0.5f + 0.20f * fm_sin(a * 1.3f + fi) * (1 + 0.3f * fm_cos(t * 0.4f + fi * 2));
        float r = 0.105f + 0.025f * fm_sin(t * 1.1f + fi * 1.7f);
        bx[i] = (x - 0.5f) * asp;
        by[i] = y - 0.5f;
        rad2[i] = r * r;
    }

    // @excerpt METABALLS
    for (int y = 0; y < h; y++) {
        float fy = (float)y / (float)h - 0.5f;
        uint32_t *restrict row = fb->pix + y * w;
        for (int x = 0; x < w; x++) {
            float fx = ((float)x / (float)w - 0.5f) * asp;
            float field = 0;
            for (int i = 0; i < BALLS; i++) {
                float dx = fx - bx[i];
                float dy = fy - by[i];
                field += rad2[i] / (dx * dx + dy * dy + 1e-5f);
            }
            // field is about 1 at the surface of a ball and explodes inside;
            // v/(1.6+v) compresses that into a usable 0..1 ramp without a log
            float v = field / (1.6f + field);
            int idx = (int)(v * 255);
            if (idx > 255)
                idx = 255;
            // rim: the iso-surface where the balls meet flares white
            if (field > 1.0f && field < 1.09f)
                idx = 255;
            row[x] = pal_sunset[idx];
        }
    }
    // @end
}

const effect fx_metaballs = {"METABALLS", start, render, NULL};
