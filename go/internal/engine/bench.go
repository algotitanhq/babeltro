package engine

import (
	"sort"
	"time"

	"babeltro/internal/fx"
)

// BenchResult is one effect's measured cost per frame.
type BenchResult struct {
	Name    string
	Frames  int
	Median  float64 // ms per frame, median
	Min     float64 // ms per frame, fastest observed
	Mpixels float64 // megapixels per second at the median
}

// Bench renders every scene in the timeline back to back and reports the cost
// of a whole frame: Prepare plus the parallel draw, with no transitions and no
// HUD. The first frames of each scene are discarded so one-off setup (texture
// generation, fire seeding) does not show up as steady-state cost.
func (e *Engine) Bench(frames int) []BenchResult {
	const warm = 24
	dt := 1.0 / 60
	px := float64(e.FB.W * e.FB.H)

	out := make([]BenchResult, 0, len(e.Scenes))
	samples := make([]float64, 0, frames)
	for i := range e.Scenes {
		sc := &e.Scenes[i]
		if sc.Eff == nil {
			continue
		}
		sc.Eff.Resize(e.FB.W, e.FB.H)
		samples = samples[:0]
		for n := 0; n < frames+warm; n++ {
			t := float64(n) * dt
			st := fx.State{T: t, Beat: t, DT: dt, Frame: uint64(n)}

			t0 := time.Now()
			sc.Eff.Prepare(st, e.FB.W, e.FB.H)
			e.pool.Run(sc.Eff, e.FB)
			d := float64(time.Since(t0).Nanoseconds()) / 1e6

			if n >= warm {
				samples = append(samples, d)
			}
		}
		sorted := append([]float64(nil), samples...)
		sort.Float64s(sorted)
		med := sorted[len(sorted)/2]
		out = append(out, BenchResult{
			Name:    sc.Name,
			Frames:  len(sorted),
			Median:  med,
			Min:     sorted[0],
			Mpixels: px / med / 1000,
		})
	}
	return out
}
