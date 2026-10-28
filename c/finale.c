// Finale: the closing card. The logo, its reflection, the subtitle and the
// numbers that make the point, over a glowing backdrop with a few twinkling
// stars.
//
// The browser lab draws no HUD in the frame, so unlike the native Go demo the
// card composes over the full height.
#include <math.h>
#include <string.h>

#include "fx.h"

// The language this port is written in: the only words that differ from the
// other ports.
#define LANG "C"
#define LANG_LEN ((int)sizeof LANG - 1)

static const char sub[] = "EVERY PIXEL IS " LANG;
static const char tag[] = "ONE THREAD - NO GPU - NO SHADER";
static const char *const lines[3] = {"0 GPU SHADERS", "0 EXTERNAL MODULES", "0 ASSETS ON DISK"};

enum { BG_STARS = 260 };

// A fixed background star in normalised coordinates: the finale only needs
// twinkle, not motion.
typedef struct {
    float x, y, b;
} bg_star;

static struct {
    bg_star stars[BG_STARS];

    int logo_scale, logo_x, logo_y, text_h;
    int refl_h; // rows the reflection fades over, below the floor line
    int floor_y;
    int sub_scale, sub_x, sub_y;
    int stats_scale, stats_y, stat_gap;
    int tag_scale, tag_x, tag_y;

    int offs[LANG_LEN]; // per-letter wave offsets

    float glow_x, glow_y, glow_r;
    // per-column squared distance to the glow centre, in glow radii, and the
    // rectangle the glow can possibly reach
    float *dx2;
    int box_x0, box_x1, box_y0, box_y1;
} F;

static void start(int w, int h)
{
    fm_rng rng = {0xF1A1E};
    for (int i = 0; i < BG_STARS; i++) {
        bg_star *s = &F.stars[i]; // three draws, in this order
        s->x = fm_rng_float(&rng);
        s->y = fm_rng_float(&rng);
        s->b = 0.15f + fm_rng_float(&rng) * 0.85f;
    }

    F.sub_scale = w / 300 < 1 ? 1 : w / 300;
    int sub_h = text_height(F.sub_scale);
    F.stats_scale = w / 440 < 1 ? 1 : w / 440;
    F.stat_gap = text_height(F.stats_scale) * 3 / 2;
    F.tag_scale = F.stats_scale + 1;
    int tag_h = text_height(F.tag_scale);

    int gap = h / 48;
    int top = h / 40;
    int bottom = (int)((float)h * 0.90f);
    int fixed = sub_h + 3 * F.stat_gap + tag_h + 4 * gap; // all but the wordmark
    // The wordmark's scale comes from the room it has rather than from its
    // length. Height: the glyph is 7 blocks and its reflection fades over
    // half of that, so it needs 10.5 blocks. Width: never more than 45% of
    // the frame, which only binds for long names.
    F.logo_scale = (bottom - top - fixed) * 2 / 21;
    int lim = w * 9 / 20 / text_width(LANG_LEN, 1);
    if (F.logo_scale > lim)
        F.logo_scale = lim;
    if (F.logo_scale < 3)
        F.logo_scale = 3;
    int logo_w = text_width(LANG_LEN, F.logo_scale);
    F.text_h = text_height(F.logo_scale);
    F.refl_h = F.text_h / 2;
    F.logo_x = (w - logo_w) / 2;

    int block_h = F.text_h + F.refl_h + fixed;
    F.logo_y = top + (bottom - top - block_h) / 2;
    F.floor_y = F.logo_y + F.text_h;
    F.sub_y = F.floor_y + F.refl_h + gap;
    F.stats_y = F.sub_y + sub_h + gap;
    F.tag_y = F.stats_y + 3 * F.stat_gap + gap;
    F.sub_x = (w - text_width((int)strlen(sub), F.sub_scale)) / 2;
    F.tag_x = (w - text_width((int)strlen(tag), F.tag_scale)) / 2;

    F.glow_x = (float)w * 0.5f;
    F.glow_y = (float)F.logo_y + (float)F.text_h * 0.55f;
    F.glow_r = (float)w * 0.34f;

    // the glow is an ellipse about 1.6x wider than it is tall
    fx_resize(F.dx2, w);
    for (int x = 0; x < w; x++) {
        float d = ((float)x - F.glow_x) / F.glow_r * 1.6f;
        F.dx2[x] = d * d;
    }
    int span_x = (int)(F.glow_r / 1.6f);
    int span_y = (int)F.glow_r;
    F.box_x0 = (int)F.glow_x - span_x;
    F.box_x1 = (int)F.glow_x + span_x;
    F.box_y0 = (int)F.glow_y - span_y;
    F.box_y1 = (int)F.glow_y + span_y;
}

static inline int32_t min255(int32_t v) { return v > 255 ? 255 : v; }
static inline float min255f(float v) { return v > 255 ? 255 : v; }

static void backdrop(canvas *fb, double t)
{
    int w = fb->w, h = fb->h;
    uint32_t *pix = fb->pix;

    // pass 1: a plain vertical ramp, one colour per row
    float cy = (float)h * 0.5f;
    float inv_h = 1 / (float)h;
    for (int y = 0; y < h; y++) {
        float u = (float)y * inv_h;
        float ny = ((float)y - cy) / cy;
        float vig = 1 - 0.32f * ny * ny;
        if (vig < 0.45f)
            vig = 0.45f;
        uint32_t c = rgb_from_float((0.02f + 0.09f * u * u) * vig,
                                    (0.01f + 0.02f * u) * vig,
                                    (0.06f + 0.14f * u) * vig);
        uint32_t *row = pix + y * w;
        for (int x = 0; x < w; x++)
            row[x] = c;
    }

    // pass 2: the pool of light, only where it can reach
    int by0 = F.box_y0 < 0 ? 0 : F.box_y0, by1 = F.box_y1 > h ? h : F.box_y1;
    int bx0 = F.box_x0 < 0 ? 0 : F.box_x0, bx1 = F.box_x1 > w ? w : F.box_x1;
    float pulse = 0.88f + 0.12f * (float)sin(t * 2.2);
    for (int y = by0; y < by1; y++) {
        float dy = ((float)y - F.glow_y) / F.glow_r;
        float dy2 = dy * dy;
        if (dy2 >= 1)
            continue;
        uint32_t *row = pix + y * w;
        for (int x = bx0; x < bx1; x++) {
            float d2 = F.dx2[x] + dy2;
            if (d2 >= 1)
                continue;
            float g = 1 - d2;
            g *= g * pulse;
            uint32_t p = row[x];
            row[x] = rgb((uint32_t)min255((int32_t)(p & 0xFF) + (int32_t)(g * 120)),
                         (uint32_t)min255((int32_t)(p >> 8 & 0xFF) + (int32_t)(g * 22)),
                         (uint32_t)min255((int32_t)(p >> 16 & 0xFF) + (int32_t)(g * 100)));
        }
    }

    // stars, twinkling slowly
    for (int i = 0; i < BG_STARS; i++) {
        const bg_star *s = &F.stars[i];
        int sx = (int)(s->x * (float)w);
        int sy = (int)(s->y * (float)h);
        if (sy < 0 || sy >= h || sx < 0 || sx >= w)
            continue;
        float tw = 0.55f + 0.45f * (float)sin(t * 1.7 + i * 0.7);
        canvas_additive(fb, sy * w + sx, 0xFF40306A, (uint8_t)(70 * s->b * tw));
    }

    // the polished floor line the reflection lands on
    if (F.floor_y >= 0 && F.floor_y < h) {
        uint32_t *row = pix + F.floor_y * w;
        float cx = (float)w * 0.5f;
        for (int x = 0; x < w; x++) {
            float fade = 1 - fabsf((float)x - cx) / ((float)w * 0.52f);
            if (fade <= 0)
                continue;
            float glow = fade * fade * 0.9f;
            uint32_t p = row[x];
            row[x] = rgb((uint32_t)min255f((float)(p & 0xFF) + 210 * glow),
                         (uint32_t)min255f((float)(p >> 8 & 0xFF) + 110 * glow),
                         (uint32_t)min255f((float)(p >> 16 & 0xFF) + 230 * glow));
        }
    }
}

static void render(canvas *fb, const fx_state *s)
{
    int w = fb->w;
    double t = s->t;
    backdrop(fb, t);

    // @excerpt FINALE
    // --- logo ---
    int scale = F.logo_scale;
    // the letters bounce off the floor line: offsets run from -scale/3 (up)
    // to 0 (resting on it), never below, so no letter sinks into its own
    // reflection
    for (int i = 0; i < LANG_LEN; i++)
        F.offs[i] = (int)((sin(t * 2.4 + i * 0.75) - 1) * scale / 6);

    const uint32_t top = 0xFFFFF6E8; // pale cream
    const uint32_t mid = 0xFF7C9CFF; // hot rose
    const uint32_t bot = 0xFF582080; // deep violet

    // reflection first, so the wordmark sits on top of its own light
    draw_text_reflect(fb, F.logo_x, F.floor_y, LANG, scale, top, bot, F.offs, 125, F.refl_h);
    // a one-pixel dark edge keeps the letters off the background
    draw_text_outline(fb, F.logo_x, F.logo_y, LANG, scale, 0xFF200A18, F.offs);
    draw_text_gradient(fb, F.logo_x, F.logo_y, LANG, scale, top, mid, bot, F.offs, true);

    // --- subtitle with rules either side ---
    int sub_w = text_width((int)strlen(sub), F.sub_scale);
    int rule = sub_w / 3;
    int ly = F.sub_y + text_height(F.sub_scale) / 2;
    canvas_hline(fb, F.sub_x - rule - 14, ly, rule, 0xFF9050A0);
    canvas_hline(fb, F.sub_x + sub_w + 14, ly, rule, 0xFF9050A0);
    draw_text(fb, F.sub_x, F.sub_y, sub, F.sub_scale, 0xFFF0E0FF);

    // --- closing numbers ---
    for (int i = 0; i < 3; i++) {
        int lw = text_width((int)strlen(lines[i]), F.stats_scale);
        draw_text(fb, (w - lw) / 2, F.stats_y + i * F.stat_gap, lines[i], F.stats_scale, 0xFFC0B0E0);
    }

    // the punchline
    draw_text(fb, F.tag_x, F.tag_y, tag, F.tag_scale, 0xFFB0E0FF);
    // @end
}

const effect fx_finale = {"FINALE", start, render};
