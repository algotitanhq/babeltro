// The WebAssembly entry points every port exports (see spec/ABI.md):
// bb_init allocates the framebuffer, bb_start begins a scene from a clean
// state, bb_render draws one frame of it. There is no HUD, no scroller and no
// threads here: one thread, the effect's pixels and nothing else.
#include <stdint.h>
#include <stdlib.h>

#include "fx.h"

#define EXPORT(name) __attribute__((export_name(name)))

static const effect *const scenes[] = {
    &fx_starfield, &fx_tunnel, &fx_plasma, &fx_rotozoom, &fx_metaballs,
    &fx_grid, &fx_fire, &fx_mandelbrot, &fx_finale,
};
enum { SCENE_COUNT = sizeof scenes / sizeof scenes[0] };

static canvas fb;
static const effect *current;

// bb_init allocates a w x h framebuffer and returns its address in linear
// memory. The host reads the pixels from there after every bb_render.
EXPORT("bb_init") int32_t bb_init(int32_t w, int32_t h)
{
    static bool tables_ready;
    if (!tables_ready) {
        fmath_init();
        palette_init();
        tables_ready = true;
    }
    fb.w = w;
    fb.h = h;
    fx_resize(fb.pix, (size_t)w * h);
    return (int32_t)(uintptr_t)fb.pix;
}

// bb_start begins scene from a fresh state, so stateful scenes (the fire,
// the starfield) replay the same history in every language. Any number past
// the last scene selects the finale, as in the Go reference.
EXPORT("bb_start") void bb_start(int32_t scene)
{
    current = scenes[scene >= 0 && scene < SCENE_COUNT ? scene : SCENE_COUNT - 1];
    current->start(fb.w, fb.h);
}

// bb_render draws frame n (n >= 1) of the current scene. Time is derived from
// n at a fixed 60 Hz step, never from a clock, so a frame number names the
// same image everywhere.
EXPORT("bb_render") void bb_render(int32_t n)
{
    double t = (double)n / 60;
    fx_state s = {.t = t, .beat = t, .dt = 1.0 / 60, .frame = (uint64_t)n};
    current->render(&fb, &s);
}
