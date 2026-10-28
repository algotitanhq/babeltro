// fx: what every scene shares. A scene is a plain class: its constructor
// takes the frame size and builds every table and buffer the scene needs,
// render(fb, frame) draws one frame, and nothing is allocated after the
// constructor. Its destructor (the vectors' own) frees it all.
//
// There is no base class. The nine scenes are a closed set and only one is
// alive at a time, so main.cpp holds the current one in a std::variant and
// dispatches with std::visit. The concepts below are the interface: checked
// at compile time, with no vtable, no heap allocation for the scene object
// and no dynamic_cast (which -fno-rtti forbids anyway) to ask whether a scene
// has an optimisation ladder.
//
// On integer widths: Go's int is 64-bit, int is 32-bit on wasm32. Every int
// here holds a pixel coordinate, an index into a w*h buffer or a small count,
// all far below 2^31, so int is the honest type for them.
#pragma once

#include <concepts>

#include "canvas.hpp"

namespace bb {

// Frame is what a scene knows about time (spec/ABI.md: a fixed 60 Hz step).
struct Frame {
    double t;    // seconds since the demo started
    double beat; // seconds since this scene started
    double dt;   // seconds since the previous frame
    uint64_t n;  // frame counter
};

template <class E>
concept Effect = std::constructible_from<E, int, int> &&
                 requires(E& e, Canvas& fb, const Frame& f) { e.render(fb, f); };

// A Laddered scene can be drawn by its naive rungs too: set_step(k) picks
// rung k, and 0 (the default) is the optimised version.
template <class E>
concept Laddered = Effect<E> && requires(E& e, int k) { e.set_step(k); };

} // namespace bb
