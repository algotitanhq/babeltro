#include "fmath.h"

#include <math.h>

float fm_sin_tab[TAB_SIZE + 1];
float fm_cos_tab[TAB_SIZE + 1];

void fmath_init(void)
{
    for (int i = 0; i <= TAB_SIZE; i++) {
        double a = 2 * FM_PI * i / TAB_SIZE;
        fm_sin_tab[i] = (float)sin(a);
        fm_cos_tab[i] = (float)cos(a);
    }
    // guarantee a full period overflows exactly
    fm_sin_tab[TAB_SIZE] = fm_sin_tab[0];
    fm_cos_tab[TAB_SIZE] = fm_cos_tab[0];
}

float fm_atan2_turns(float y, float x)
{
    float a = (float)atan2(y, x);
    return a / (float)(2 * FM_PI) + 0.5f;
}

void fm_atan2_table(float *tab, int w, int h)
{
    float cx = (float)w / 2, cy = (float)h / 2;
    for (int y = 0; y < h; y++) {
        float dy = (float)y - cy;
        for (int x = 0; x < w; x++)
            *tab++ = fm_atan2_turns(dy, (float)x - cx);
    }
}

void fm_dist_inv_table(float *tab, int w, int h, float scale, float softness)
{
    float cx = (float)w / 2, cy = (float)h / 2;
    for (int y = 0; y < h; y++) {
        float dy = (float)y - cy;
        for (int x = 0; x < w; x++) {
            float dx = (float)x - cx;
            // sqrtf is correctly rounded, so it equals Go's float32(math.Sqrt)
            float r = sqrtf(dx * dx + dy * dy) + softness;
            *tab++ = scale / r;
        }
    }
}
