// canvas: the software framebuffer every effect draws into, and the 5x7 font
// the finale writes with.
//
// Pixels are packed as 0xAABBGGRR in a uint32_t, which in little-endian
// memory is R, G, B, A: exactly the bytes of a browser ImageData, so the host
// copies a frame without converting it.
#ifndef BABELTRO_CANVAS_H
#define BABELTRO_CANVAS_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int w, h;
    uint32_t *pix; // w*h pixels, row-major, top row first
} canvas;

// rgb packs a colour into the framebuffer layout, alpha opaque.
static inline uint32_t rgb(uint32_t r, uint32_t g, uint32_t b)
{
    return 0xFF000000u | b << 16 | g << 8 | r;
}

// unit_to_byte maps [0,1] to 0..255, rounding and clamping.
static inline uint32_t unit_to_byte(double v)
{
    if (v <= 0)
        return 0;
    if (v >= 1)
        return 255;
    return (uint32_t)(v * 255 + 0.5);
}

// rgb_from_float packs normalised channels, clamping each to [0,1].
static inline uint32_t rgb_from_float(double r, double g, double b)
{
    return rgb(unit_to_byte(r), unit_to_byte(g), unit_to_byte(b));
}

static inline double clamp01(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

// canvas_additive adds colour c scaled by intensity/255 to pixel i,
// saturating each channel.
void canvas_additive(canvas *fb, int i, uint32_t c, uint8_t intensity);

// canvas_hline draws a 1px horizontal line, clipped to the frame.
void canvas_hline(canvas *fb, int x, int y, int w, uint32_t c);

// --- text, 5x7 font (font.c) ---

enum { FONT_W = 5, FONT_H = 7, FONT_GAP = 1 };

// Glyph rows for the printable ASCII range ' '..'~'. Each row holds 5 bits,
// the most significant one being the leftmost pixel.
extern const uint8_t font[95][FONT_H];

static inline int text_width(int len, int scale)
{
    return len > 0 ? (len * (FONT_W + FONT_GAP) - FONT_GAP) * scale : 0;
}

static inline int text_height(int scale) { return FONT_H * scale; }

// draw_text draws s with its top-left corner at (x, y) in a solid colour.
void draw_text(canvas *fb, int x, int y, const char *s, int scale, uint32_t c);

// draw_text_outline draws s offset by one pixel in the four cardinal
// directions, a hard edge that keeps a logo readable over a busy background.
// offs holds one baseline offset per letter, or is NULL.
void draw_text_outline(canvas *fb, int x, int y, const char *s, int scale,
                       uint32_t c, const int *offs);

// draw_text_gradient draws s with a three-stop vertical ramp (top, mid,
// bottom), the chrome look of the finale logo. With scan set every fourth row
// is darkened, the CRT look.
void draw_text_gradient(canvas *fb, int x, int y, const char *s, int scale,
                        uint32_t top, uint32_t mid, uint32_t bottom,
                        const int *offs, bool scan);

// draw_text_reflect adds a vertically mirrored copy of s below line y, fading
// out over depth rows like light on a polished floor.
void draw_text_reflect(canvas *fb, int x, int y, const char *s, int scale,
                       uint32_t top, uint32_t bottom, const int *offs,
                       uint8_t strength, int depth);

#endif
