// Starfield: a warp-speed star tunnel. Stars live in 3D, get projected in
// perspective and dragged into short streaks. The streak is what sells the
// speed, so each star draws from its previous depth to its current one.
#include <math.h>
#include <string.h>

#include "fx.h"

enum { STARS = 1600 };

typedef struct {
    float x, y, z;
} star;

typedef struct {
    int32_t x0, y0, x1, y1; // the streak drawn from (x0,y0) to (x1,y1)
    uint32_t c;
} streak;

static struct {
    int w, h;
    star stars[STARS];
    streak proj[STARS];
    uint32_t *bg; // the backdrop never changes, so it is built once
    fm_rng rng;
} S;

// build_backdrop paints the deep-navy vignette once per size. Copying a ready
// buffer is two orders of magnitude cheaper than evaluating it per pixel per
// frame, and this is the trick the rest of the demo leans on too.
static void build_backdrop(void)
{
    int w = S.w, h = S.h;
    fx_resize(S.bg, w * h);
    uint32_t *p = S.bg;
    for (int y = 0; y < h; y++) {
        double dy = (double)y / h - 0.5;
        for (int x = 0; x < w; x++) {
            double dx = (double)x / w - 0.5;
            double v = dx * dx + dy * dy;
            *p++ = rgb_from_float(fmax(0.02 - v * 0.03, 0),
                                  fmax(0.02 - v * 0.025, 0),
                                  fmax(0.05 - v * 0.03, 0));
        }
    }
}

static void start(int w, int h)
{
    S.w = w;
    S.h = h;
    S.rng.s = 0x6005E;
    for (int i = 0; i < STARS; i++) {
        // one statement per draw: C leaves the evaluation order of the
        // members of an initialiser list unspecified, Go does not
        star *p = &S.stars[i];
        p->x = (fm_rng_float(&S.rng) * 2 - 1) * 1.6f;
        p->y = (fm_rng_float(&S.rng) * 2 - 1) * 1.6f;
        p->z = fm_rng_float(&S.rng) * 40 + 0.2f;
    }
    build_backdrop();
}

// move advances every star and projects its streak for this frame.
static void move(const fx_state *st)
{
    int w = S.w;
    float cx = (float)w * 0.5f, cy = (float)S.h * 0.5f;
    // accelerate over the scene so the entry has a kick
    float speed = (float)(2.5 + fmin(st->beat, 3) * 4);
    float dt = (float)st->dt;
    if (dt > 0.1f)
        dt = 0.1f;
    float dz = speed * dt;
    float zoom = (float)w * 0.78f;

    // @excerpt STARFIELD
    for (int i = 0; i < STARS; i++) {
        star *p = &S.stars[i];
        p->z -= dz;
        if (p->z < 0.8f) { // passed the camera: respawn far away
            p->z += 40;
            p->x = (fm_rng_float(&S.rng) * 2 - 1) * 1.1f;
            p->y = (fm_rng_float(&S.rng) * 2 - 1) * 1.1f;
        }
        // project now, and a little deeper: the streak between the two
        float f = 1.0f / p->z;
        float x0 = cx + p->x * f * zoom;
        float y0 = cy + p->y * f * zoom;
        float f2 = 1.0f / (p->z + dz * 2.4f);
        float x1 = cx + p->x * f2 * zoom;
        float y1 = cy + p->y * f2 * zoom;

        // brighter and bluer as the star gets close
        float near = 1 - p->z / 40;
        float b = near * near;
        uint32_t r = (uint32_t)(120 * b + 40);
        uint32_t g = (uint32_t)(190 * b + 40);
        uint32_t bl = (uint32_t)(255 * (0.25f + 0.75f * b));
        S.proj[i] = (streak){(int32_t)x0, (int32_t)y0, (int32_t)x1, (int32_t)y1,
                             rgb(r, g, bl)};
    }
    // @end
}

static inline uint32_t min255(uint32_t v) { return v > 255 ? 255 : v; }

// line_add draws a Bresenham line adding colour, so overlapping stars
// accumulate brightness instead of replacing each other.
static void line_add(canvas *fb, int x0, int y0, int x1, int y1, uint32_t c)
{
    int dx = abs(x1 - x0), dy = -abs(y1 - y0);
    int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    for (;;) {
        if (x0 >= 0 && x0 < fb->w && y0 >= 0 && y0 < fb->h) {
            uint32_t *q = &fb->pix[y0 * fb->w + x0];
            uint32_t p = *q;
            *q = rgb(min255((p & 0xFF) + (c & 0xFF)),
                     min255((p >> 8 & 0xFF) + (c >> 8 & 0xFF)),
                     min255((p >> 16 & 0xFF) + (c >> 16 & 0xFF)));
        }
        if (x0 == x1 && y0 == y1)
            break;
        int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

static void render(canvas *fb, const fx_state *st)
{
    move(st);
    int w = fb->w, h = fb->h;
    memcpy(fb->pix, S.bg, (size_t)w * h * sizeof *fb->pix);
    for (int i = 0; i < STARS; i++) {
        const streak *p = &S.proj[i];
        line_add(fb, p->x0, p->y0, p->x1, p->y1, p->c);
        // bright head pixel
        if (p->x1 >= 0 && p->x1 < w && p->y1 >= 0 && p->y1 < h)
            fb->pix[p->y1 * w + p->x1] = 0xFFCCEEFF;
    }
}

const effect fx_starfield = {"STARFIELD", start, render};
