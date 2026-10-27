// Package fx contains the effects. Every one of them writes pixels straight
// into the framebuffer on the CPU; there is no shader anywhere in this demo.
//
// An effect first gets Prepare (once per frame, single-threaded, where it can
// build per-frame lookup tables) and then Draw for each horizontal band, so the
// engine can hand independent strips to different goroutines. Effects that need
// the previous frame (fire, feedback) report Parallel() == false and are run
// whole.
package fx

import "rosette/internal/canvas"

// State is what an effect knows about time.
type State struct {
	T     float64 // seconds since the demo started
	Beat  float64 // seconds since this scene started
	DT    float64 // seconds since the previous frame
	Frame uint64  // frame counter
}

// Effect is one scene.
type Effect interface {
	Name() string
	// Resize lets the effect rebuild any tables tied to resolution.
	Resize(w, h int)
	// Prepare runs once per frame before the parallel draw, and is where
	// per-frame lookup tables belong.
	Prepare(s State, w, h int)
	// Draw renders rows [y0, y1) of fb.
	Draw(fb *canvas.FB, y0, y1 int)
	// Parallel reports whether Draw can be called concurrently on different
	// bands. False means the engine calls it once with the full height.
	Parallel() bool
}

// All returns the effects in playback order.
func All() []Effect {
	return []Effect{
		&Starfield{},
		&Tunnel{},
		&Plasma{},
		&Rotozoom{},
		&Metaballs{},
		&Grid{},
		&Fire{},
		&Mandelbrot{},
	}
}
