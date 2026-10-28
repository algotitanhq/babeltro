// The WebAssembly entry points every port exports (see spec/ABI.md):
// bb_init allocates the framebuffer, bb_start begins a scene from a clean
// state, bb_step optionally picks a rung of its optimisation ladder,
// bb_render draws one frame of it. One thread, no HUD, no scroller: the
// effect's pixels and nothing else.
#include <cstdint>
#include <variant>

#include "finale.hpp"
#include "fire.hpp"
#include "grid.hpp"
#include "mandelbrot.hpp"
#include "metaballs.hpp"
#include "plasma.hpp"
#include "rotozoom.hpp"
#include "starfield.hpp"
#include "tunnel.hpp"

namespace {

using namespace bb;

// The current scene, by value. std::monostate means "none yet". Emplacing a
// new scene destroys the old one first, so its buffers are freed before the
// next scene's are allocated: bb_start is the only place memory changes.
using Scene = std::variant<std::monostate, Starfield, Tunnel, Plasma, Rotozoom, Metaballs, Grid,
                           Fire, Mandelbrot, Finale>;

// every alternative but the first must be an Effect
template <class... E>
constexpr bool all_effects(std::variant<std::monostate, E...>*) { return (Effect<E> && ...); }
static_assert(all_effects(static_cast<Scene*>(nullptr)));

Canvas fb;
Scene scene;

} // namespace

#define EXPORT(name) __attribute__((export_name(name)))

// bb_init allocates a w x h framebuffer and returns its address in linear
// memory. The host reads the pixels from there after every bb_render.
EXPORT("bb_init") std::int32_t bb_init(std::int32_t w, std::int32_t h)
{
    scene = std::monostate{}; // a scene sized for the old frame must not draw into the new one
    fb.resize(w, h);
    return std::int32_t(reinterpret_cast<std::uintptr_t>(fb.pix.data()));
}

// bb_start begins scene n from a fresh state, so stateful scenes (the fire,
// the starfield) replay the same history in every language. Any number past
// the last scene selects the finale, as in the Go reference.
EXPORT("bb_start") void bb_start(std::int32_t n)
{
    const int w = fb.w, h = fb.h;
    switch (n) {
    case 0: scene.emplace<Starfield>(w, h); break;
    case 1: scene.emplace<Tunnel>(w, h); break;
    case 2: scene.emplace<Plasma>(w, h); break;
    case 3: scene.emplace<Rotozoom>(w, h); break;
    case 4: scene.emplace<Metaballs>(w, h); break;
    case 5: scene.emplace<Grid>(w, h); break;
    case 6: scene.emplace<Fire>(w, h); break;
    case 7: scene.emplace<Mandelbrot>(w, h); break;
    default: scene.emplace<Finale>(w, h); break;
    }
}

// bb_step picks a rung of the scene's optimisation ladder, for the scenes
// that have one; 0 is the optimised default. Called after bb_start, before
// the first frame. A scene without a ladder ignores it, decided at compile
// time.
EXPORT("bb_step") void bb_step(std::int32_t k)
{
    std::visit(
        [k](auto& e) {
            if constexpr (Laddered<std::decay_t<decltype(e)>>)
                e.set_step(k);
        },
        scene);
}

// bb_render draws frame n (n >= 1) of the current scene. Time is derived from
// n at a fixed 60 Hz step, never from a clock, so a frame number names the
// same image everywhere.
EXPORT("bb_render") void bb_render(std::int32_t n)
{
    const double t = double(n) / 60;
    const Frame f{.t = t, .beat = t, .dt = 1.0 / 60, .n = std::uint64_t(n)};
    std::visit(
        [&f](auto& e) {
            if constexpr (Effect<std::decay_t<decltype(e)>>)
                e.render(fb, f);
        },
        scene);
}
