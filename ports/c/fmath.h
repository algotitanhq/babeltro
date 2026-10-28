// fmath: the numeric shortcuts every effect leans on. Calling sin() a million
// times per frame is the difference between 20 ms and 1 ms, so the hot loops
// read a sine table instead, and every random number comes from xorshift32.
#ifndef BABELTRO_FMATH_H
#define BABELTRO_FMATH_H

#include <stdint.h>

#define FM_PI 3.14159265358979323846

enum {
    TAB_BITS = 13,
    TAB_SIZE = 1 << TAB_BITS,
    TAB_MASK = TAB_SIZE - 1,
};

// Radians to table steps. Go folds TabSize/(2*Pi) exactly and rounds once to
// float32; rounding the double quotient instead gives the same float here.
#define FM_INV2PI ((float)(TAB_SIZE / (2 * FM_PI)))

// One extra entry so a full period wraps exactly.
extern float fm_sin_tab[TAB_SIZE + 1];
extern float fm_cos_tab[TAB_SIZE + 1];

// fmath_init fills the tables; call it once before any lookup.
void fmath_init(void);

// The lookups truncate toward zero, like Go's int(), and then wrap with the
// mask: on a two's-complement int that also handles negative angles. The
// angles the effects pass stay far inside int range, where the cast is
// defined.

// fm_sin returns sin(a) from the table, a in radians.
static inline float fm_sin(float a) { return fm_sin_tab[(int)(a * FM_INV2PI) & TAB_MASK]; }

// fm_cos returns cos(a) from the table, a in radians.
static inline float fm_cos(float a) { return fm_cos_tab[(int)(a * FM_INV2PI) & TAB_MASK]; }

// fm_sin01 returns sin(2*pi*t) for t in turns.
static inline float fm_sin01(float t) { return fm_sin_tab[(int)(t * TAB_SIZE) & TAB_MASK]; }

// fm_atan2_turns returns atan2(y, x) as a fraction of a full turn, in [0,1).
float fm_atan2_turns(float y, float x);

// fm_atan2_table fills tab[w*h] with the turn fraction of every pixel around
// the centre of a w x h grid.
void fm_atan2_table(float *tab, int w, int h);

// fm_dist_inv_table fills tab[w*h] with scale/(r+softness), r being the
// distance to the centre. The softness term tames the singularity there.
void fm_dist_inv_table(float *tab, int w, int h, float scale, float softness);

// xorshift32: three shifts and three xors give the same sequence in every
// language, which no standard library rand() promises. The state must never
// be zero.
typedef struct { uint32_t s; } fm_rng;

static inline uint32_t fm_rng_next(fm_rng *r)
{
    uint32_t x = r->s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return r->s = x;
}

// fm_rng_float returns a number in [0,1) from the top 24 bits, so the
// conversion to float is exact.
static inline float fm_rng_float(fm_rng *r)
{
    return (float)(fm_rng_next(r) >> 8) * 0x1p-24f;
}

#endif
