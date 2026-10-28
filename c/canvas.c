#include "canvas.h"

#include <stddef.h>

static inline uint32_t min255(uint32_t v) { return v > 255 ? 255 : v; }

void canvas_additive(canvas *fb, int i, uint32_t c, uint8_t intensity)
{
    if (intensity == 0)
        return;
    uint32_t p = fb->pix[i];
    uint32_t r = (p & 0xFF) + (c & 0xFF) * intensity / 255;
    uint32_t g = (p >> 8 & 0xFF) + (c >> 8 & 0xFF) * intensity / 255;
    uint32_t b = (p >> 16 & 0xFF) + (c >> 16 & 0xFF) * intensity / 255;
    fb->pix[i] = rgb(min255(r), min255(g), min255(b));
}

void canvas_hline(canvas *fb, int x, int y, int w, uint32_t c)
{
    if (y < 0 || y >= fb->h)
        return;
    uint32_t *row = fb->pix + (size_t)y * fb->w;
    for (int xx = x; xx < x + w; xx++)
        if (xx >= 0 && xx < fb->w)
            row[xx] = c;
}

// glyph returns the rows of ch, folding lowercase to uppercase, or NULL when
// the font has no such character.
static const uint8_t *glyph(unsigned char ch)
{
    if (ch >= 'a' && ch <= 'z')
        ch = ch - 'a' + 'A';
    int idx = ch - 32;
    return idx >= 0 && idx < 95 ? font[idx] : NULL;
}

// A clipped rectangle: rows [y0, y1), columns [x0, x1).
typedef struct {
    int y0, y1, x0, x1;
} span;

// clip_block returns the visible part of the scale x scale block at (px, py).
// Clipping once per block and then writing straight runs is much cheaper than
// testing bounds per pixel.
static bool clip_block(const canvas *fb, int px, int py, int scale, span *s)
{
    s->y0 = py < 0 ? 0 : py;
    s->y1 = py + scale > fb->h ? fb->h : py + scale;
    s->x0 = px < 0 ? 0 : px;
    s->x1 = px + scale > fb->w ? fb->w : px + scale;
    return s->y0 < s->y1 && s->x0 < s->x1;
}

static inline bool lit(uint8_t bits, int col) { return bits & (1 << (4 - col)); }

void draw_text(canvas *fb, int x, int y, const char *s, int scale, uint32_t c)
{
    if (scale < 1)
        scale = 1;
    for (int cx = x; *s; s++) {
        const uint8_t *g = glyph((unsigned char)*s);
        if (!g) {
            cx += FONT_W * scale; // an unknown character leaves no gap
            continue;
        }
        for (int row = 0; row < FONT_H; row++) {
            for (int col = 0; col < FONT_W; col++) {
                span b;
                if (lit(g[row], col) &&
                    clip_block(fb, cx + col * scale, y + row * scale, scale, &b))
                    for (int yy = b.y0; yy < b.y1; yy++)
                        for (int xx = b.x0; xx < b.x1; xx++)
                            fb->pix[(size_t)yy * fb->w + xx] = c;
            }
        }
        cx += (FONT_W + FONT_GAP) * scale;
    }
}

void draw_text_outline(canvas *fb, int x, int y, const char *s, int scale,
                       uint32_t c, const int *offs)
{
    static const int dirs[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
    for (int i = 0; s[i]; i++) {
        int dy = offs ? offs[i] : 0;
        char one[2] = {s[i], '\0'};
        int gx = x + i * (FONT_W + FONT_GAP) * scale;
        for (int d = 0; d < 4; d++)
            draw_text(fb, gx + dirs[d][0], y + dy + dirs[d][1], one, scale, c);
    }
}

// Channel n (0 = red, 1 = green, 2 = blue) of a packed colour, as a float.
static inline float chan(uint32_t c, int n) { return (float)(c >> (8 * n) & 0xFF); }

// lerp_rgb mixes colours a and b by u in [0,1], channel by channel, in float
// arithmetic truncated to integers (as the Go reference does).
static inline uint32_t lerp_rgb(uint32_t a, uint32_t b, float u)
{
    uint32_t out[3];
    for (int n = 0; n < 3; n++)
        out[n] = (uint32_t)(chan(a, n) + (chan(b, n) - chan(a, n)) * u);
    return rgb(out[0], out[1], out[2]);
}

void draw_text_gradient(canvas *fb, int x, int y, const char *s, int scale,
                        uint32_t top, uint32_t mid, uint32_t bottom,
                        const int *offs, bool scan)
{
    if (scale < 1)
        scale = 1;
    int total_h = FONT_H * scale;
    for (int i = 0, cx = x; s[i]; i++, cx += (FONT_W + FONT_GAP) * scale) {
        const uint8_t *g = glyph((unsigned char)s[i]);
        if (!g)
            continue;
        int dy = offs ? offs[i] : 0;
        for (int row = 0; row < FONT_H; row++) {
            for (int col = 0; col < FONT_W; col++) {
                span b;
                if (!lit(g[row], col) ||
                    !clip_block(fb, cx + col * scale, y + row * scale + dy, scale, &b))
                    continue;
                for (int yy = b.y0; yy < b.y1; yy++) {
                    float f = (float)(yy - y) / (float)total_h;
                    f = f < 0 ? 0 : f > 1 ? 1 : f;
                    uint32_t c = f < 0.5f ? lerp_rgb(top, mid, f * 2)
                                          : lerp_rgb(mid, bottom, (f - 0.5f) * 2);
                    if (scan && (yy & 3) == 0) {
                        uint32_t r = c & 0xFF, gg = c >> 8 & 0xFF, bl = c >> 16 & 0xFF;
                        c = rgb(r * 3 / 4, gg * 3 / 4, bl * 3 / 4);
                    }
                    uint32_t *p = fb->pix + (size_t)yy * fb->w;
                    for (int xx = b.x0; xx < b.x1; xx++)
                        p[xx] = c;
                }
            }
        }
    }
}

void draw_text_reflect(canvas *fb, int x, int y, const char *s, int scale,
                       uint32_t top, uint32_t bottom, const int *offs,
                       uint8_t strength, int depth)
{
    if (scale < 1)
        scale = 1;
    if (depth < 1)
        depth = 1;
    for (int i = 0, cx = x; s[i]; i++, cx += (FONT_W + FONT_GAP) * scale) {
        const uint8_t *g = glyph((unsigned char)s[i]);
        if (!g)
            continue;
        int dy = offs ? offs[i] : 0;
        for (int row = 0; row < FONT_H; row++) {
            // mirrored: glyph row 0 sits at the far end, and a letter lifted
            // by dy has its reflection pushed down by as much
            int py = y + (FONT_H - 1 - row) * scale - dy;
            for (int col = 0; col < FONT_W; col++) {
                span b;
                if (!lit(g[row], col) || !clip_block(fb, cx + col * scale, py, scale, &b))
                    continue;
                for (int yy = b.y0; yy < b.y1; yy++) {
                    float d = (float)(yy - y) / (float)depth;
                    if (d > 1)
                        continue;
                    float a = 1 - d;
                    a *= a;
                    uint8_t inten = (uint8_t)((float)strength * a);
                    if (inten == 0)
                        continue;
                    uint32_t c = lerp_rgb(top, bottom, d);
                    int base = yy * fb->w;
                    for (int xx = b.x0; xx < b.x1; xx++)
                        canvas_additive(fb, base + xx, c, inten);
                }
            }
        }
    }
}
