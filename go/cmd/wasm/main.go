//go:build wasip1

// Command wasm builds the effects as a WebAssembly reactor for the browser
// lab. It exports the three functions every port exports (see spec/ABI.md):
// bb_init allocates the framebuffer, bb_start begins a scene from a clean
// state, bb_render draws one frame of it. There is no HUD, no scroller and
// no worker pool here: one thread, the effect's pixels and nothing else.
//
//	GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o go.wasm ./cmd/wasm
package main

import (
	"unsafe"

	"babeltro/internal/canvas"
	"babeltro/internal/fx"
)

var (
	fb  *canvas.FB
	eff fx.Effect
)

func main() {}

// bb_init allocates a w×h framebuffer and returns its address in linear
// memory. The host reads the pixels from there after every bb_render.
//
//go:wasmexport bb_init
func bbInit(w, h int32) int32 {
	fx.PanelBottom = nil // no HUD in the frame: the finale uses the full height
	fx.FinaleTag = "ONE THREAD - NO GPU - NO SHADER"
	fb = canvas.New(int(w), int(h))
	return int32(uintptr(unsafe.Pointer(&fb.Pix[0])))
}

// bb_start begins scene from a fresh effect, so stateful scenes (the fire,
// the starfield) replay the same history in every language.
//
//go:wasmexport bb_start
func bbStart(scene int32) {
	eff = newEffect(scene)
	eff.Resize(fb.W, fb.H)
}

// bb_render draws frame n (n ≥ 1) of the current scene. Time is derived
// from n at a fixed 60 Hz step, never from a clock, so a frame number names
// the same image everywhere.
//
//go:wasmexport bb_render
func bbRender(n int32) {
	t := float64(n) / 60
	s := fx.State{T: t, Beat: t, DT: 1.0 / 60, Frame: uint64(n)}
	eff.Prepare(s, fb.W, fb.H)
	eff.Draw(fb, 0, fb.H)
}

func newEffect(scene int32) fx.Effect {
	switch scene {
	case 0:
		return fx.NewStarfield()
	case 1:
		return fx.NewTunnel()
	case 2:
		return fx.NewPlasma()
	case 3:
		return fx.NewRotozoom()
	case 4:
		return fx.NewMetaballs()
	case 5:
		return fx.NewGrid()
	case 6:
		return fx.NewFire()
	case 7:
		return fx.NewMandelbrot()
	default:
		return fx.NewFinale()
	}
}
