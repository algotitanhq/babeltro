// fx: the nine scenes. Every one of them writes pixels straight into the
// framebuffer on the CPU; there is no shader anywhere in this demo.
//
// Each scene is a module with its state in file-scope statics (there is only
// ever one of each) and two entry points: start, which allocates and seeds
// everything for a w x h frame, and render, which draws one frame. Nothing is
// allocated per frame.
//
// A note on integer widths: Go's int is 64-bit, C's int is 32-bit on wasm32.
// Every int below holds a pixel coordinate, an index into a w*h buffer or a
// small count, all far below 2^31, so int is the honest type for them.
#ifndef BABELTRO_FX_H
#define BABELTRO_FX_H

#include <stdint.h>
#include <stdlib.h>

#include "canvas.h"
#include "fmath.h"
#include "palette.h"

// What an effect knows about time (see spec/ABI.md: a fixed 60 Hz step).
typedef struct {
    double t;       // seconds since the demo started
    double beat;    // seconds since this scene started
    double dt;      // seconds since the previous frame
    uint64_t frame; // frame counter
} fx_state;

typedef struct {
    const char *name;
    void (*start)(int w, int h);
    void (*render)(canvas *fb, const fx_state *s);
    // set_step picks a rung of the scene's optimisation ladder, for the
    // scenes that have one (NULL otherwise). 0 is the optimised default and
    // start resets to it; steps 1..n are the rungs, n being that same
    // default.
    void (*set_step)(int n);
} effect;

extern const effect fx_starfield, fx_tunnel, fx_plasma, fx_rotozoom,
    fx_metaballs, fx_grid, fx_fire, fx_mandelbrot, fx_finale;

// fx_resize resizes a heap buffer of n elements of *p, keeping nothing: the
// caller refills it. Running out of memory in a demo is fatal.
#define fx_resize(p, n) ((p) = fx_realloc((p), (size_t)(n) * sizeof *(p)))

static inline void *fx_realloc(void *p, size_t bytes)
{
    p = realloc(p, bytes);
    if (!p && bytes)
        abort();
    return p;
}

#endif
