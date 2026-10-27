// Package engine drives the demo: it owns the clock, the scene list, the
// worker pool and the instrumentation. Everything it reports is measured.
package engine

import (
	"runtime"
	"time"

	"babeltro/internal/brand"
	"babeltro/internal/canvas"
	"babeltro/internal/fx"
	"babeltro/internal/hud"
)

// Scene is one entry in the timeline.
type Scene struct {
	Name string
	Eff  fx.Effect // nil means the scene is drawn by the engine (finale)
	Dur  float64   // seconds
}

// Engine renders the demo into a framebuffer.
type Engine struct {
	FB       *canvas.FB
	Scenes   []Scene
	HUD      *hud.HUD
	Scroller *Scroller

	idx   int
	start float64
	t     float64

	pool *bandPool

	frameNo  uint64
	cpuMs    float64
	renderMs float64
	frameMs  float64
	fps      float64
	budget   float64

	// allocation accounting, sampled rather than read every frame: reading
	// MemStats stops the world, so doing it per frame would distort exactly
	// the number it is meant to report
	lastAllocT     float64
	lastTotalAlloc uint64
	lastAllocCount uint64
	framesSince    uint64
	allocPerFrm    uint64
	allocsPerFrm   uint64
	gcCount        uint32
	sampled        bool
}

// New builds an engine. budget is the frame budget in ms (1000/refresh).
func New(fb *canvas.FB, scenes []Scene, workers int, budget float64) *Engine {
	e := &Engine{
		FB:     fb,
		Scenes: scenes,
		HUD:    hud.New(),
		pool:   newBandPool(workers),
		budget: budget,
	}
	e.Scroller = NewScroller(scrollerText)
	return e
}

// Resize forwards the new size to every effect.
func (e *Engine) Resize(w, h int) {
	e.FB.Resize(w, h)
	for i := range e.Scenes {
		if e.Scenes[i].Eff != nil {
			e.Scenes[i].Eff.Resize(w, h)
		}
	}
}

// Workers reports the pool size.
func (e *Engine) Workers() int { return e.pool.n }

// Next jumps to the next scene, restarting its clock at t.
func (e *Engine) Next(t float64) {
	e.start = t
	e.idx = (e.idx + 1) % len(e.Scenes)
	if e.Scenes[e.idx].Eff != nil {
		e.Scenes[e.idx].Eff.Resize(e.FB.W, e.FB.H)
	}
}

// Jump switches to a specific scene index now.
func (e *Engine) Jump(t float64, idx int) {
	if idx < 0 || idx >= len(e.Scenes) {
		return
	}
	e.start = t - 0.0001
	e.idx = idx
	if e.Scenes[idx].Eff != nil {
		e.Scenes[idx].Eff.Resize(e.FB.W, e.FB.H)
	}
}

// Step advances the demo clock and renders one frame.
func (e *Engine) Step(t, dt float64) {
	e.t = t
	e.frameNo++
	if dt > 0 {
		e.fps = 1 / dt
	}
	e.frameMs = dt * 1000

	// --- timeline ---
	local := t - e.start
	for local >= e.Scenes[e.idx].Dur {
		e.start += e.Scenes[e.idx].Dur
		e.idx = (e.idx + 1) % len(e.Scenes)
		local = t - e.start
	}
	sc := &e.Scenes[e.idx]

	t0 := time.Now()

	// --- scene ---
	if sc.Eff != nil {
		st := fx.State{T: t, Beat: local, DT: dt, Frame: e.frameNo}
		sc.Eff.Prepare(st, e.FB.W, e.FB.H)
		e.pool.Run(sc.Eff, e.FB)
	}
	e.renderMs = float64(time.Since(t0).Nanoseconds()) / 1e6

	// --- transitions ---
	fade := transition(local, sc.Dur)

	// --- scene title ---
	titleA := sceneTitleAlpha(local)
	if titleA > 0 {
		drawSceneTitle(e.FB, sc.Name, e.idx, len(e.Scenes), titleA)
	}

	// --- scroller ---
	if scrollerAlpha(t) > 0 {
		e.Scroller.Draw(e.FB, t, uint8(scrollerAlpha(t)*255))
	}

	// --- fade to black between scenes ---
	if fade < 1 {
		e.FB.FadeTo(1 - fade)
	}

	// --- HUD ---
	e.HUD.Draw(e.FB, e.stats(local, sc.Dur))

	inst := float64(time.Since(t0).Nanoseconds()) / 1e6
	// a rolling average: a single frame can be long for reasons that have
	// nothing to do with the effect (scheduler, GC), and the HUD is making a
	// claim about the steady state
	if e.frameNo < 10 {
		e.cpuMs = inst
	} else {
		e.cpuMs = e.cpuMs*0.85 + inst*0.15
	}
	e.sampleAllocs(t)
}

// transition returns a 0..1 brightness multiplier that fades in and out.
func transition(local, dur float64) float64 {
	const in, out = 0.45, 0.40
	a := 1.0
	if local < in {
		a = local / in
	}
	if local > dur-out {
		a = (dur - local) / out
	}
	if a < 0 {
		a = 0
	}
	if a > 1 {
		a = 1
	}
	return a
}

func sceneTitleAlpha(local float64) float64 {
	if local < 0.5 || local > 3.2 {
		return 0
	}
	if local < 1.1 {
		return (local - 0.5) / 0.6
	}
	if local > 2.4 {
		return (3.2 - local) / 0.8
	}
	return 1
}

func scrollerAlpha(t float64) float64 {
	const start = 11.0
	if t < start {
		return 0
	}
	if t < start+1.5 {
		return (t - start) / 1.5
	}
	return 1
}

func (e *Engine) stats(local, dur float64) hud.Stats {
	return hud.Stats{
		FPS:        e.fps,
		FrameMS:    e.frameMs,
		CPUMs:      e.cpuMs,
		BudgetMS:   e.budget,
		Pixels:     float64(e.FB.W * e.FB.H),
		Mpxs:       float64(e.FB.W*e.FB.H) / (e.cpuMs * 1000),
		Workers:    e.pool.n,
		AllocBytes: e.allocPerFrm,
		Allocs:     e.allocsPerFrm,
		GCRuns:     e.gcCount,
		Scene:      e.Scenes[e.idx].Name,
		SceneIndex: e.idx,
		SceneCount: len(e.Scenes),
		SceneTime:  local,
		SceneDur:   dur,
	}
}

func (e *Engine) sampleAllocs(t float64) {
	e.framesSince++
	if t-e.lastAllocT < 2 {
		return
	}
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)
	if e.sampled && e.framesSince > 0 {
		e.allocPerFrm = (ms.TotalAlloc - e.lastTotalAlloc) / e.framesSince
		e.allocsPerFrm = (ms.Mallocs - e.lastAllocCount) / e.framesSince
		e.gcCount = ms.NumGC
	}
	e.lastTotalAlloc = ms.TotalAlloc
	e.lastAllocCount = ms.Mallocs
	e.framesSince = 0
	e.lastAllocT = t
	e.sampled = true
}

const scrollerText = brand.Project + " PRESENTS ... EVERY PIXEL IS " + brand.Lang + " ... NO SHADERS, NO GAME ENGINE, " +
	"NO GPU WORK BEYOND THE FINAL BLIT ... 921,600 PIXELS PER FRAME COMPUTED ON THE CPU " +
	"AND HANDED TO EIGHT " + brand.Workers + " ... GREETINGS TO EVERYONE WHO EVER WROTE A PLASMA " +
	"IN A LANGUAGE THAT DID NOT NEED A VIRTUAL MACHINE ... THIS IS " + brand.Lang + " AT FULL SPEED ... "

// FPS reports the last frame's rate.
func (e *Engine) FPS() float64 { return e.fps }

// CPUMs reports the smoothed cost of one frame, the number the HUD shows.
func (e *Engine) CPUMs() float64 { return e.cpuMs }

// SceneName reports the scene currently on screen.
func (e *Engine) SceneName() string { return e.Scenes[e.idx].Name }
