// Package palette builds 256-entry colour ramps from a handful of stops.
// Effects index these ramps instead of doing expensive per-pixel colour maths,
// which is the classic demoscene trade: pay once at load, then look up.
package palette

import "math"

// Stop is one colour anchor in a ramp, at position Pos in [0,1].
type Stop struct {
	Pos     float64
	R, G, B float64
}

// Palette is a ready-to-index 256-colour ramp.
type Palette [256]uint32

// New interpolates the stops into a palette.
func New(stops ...Stop) *Palette {
	var p Palette
	if len(stops) == 0 {
		return &p
	}
	for i := 0; i < 256; i++ {
		t := float64(i) / 255
		// find the segment containing t
		a := stops[0]
		b := stops[len(stops)-1]
		for k := 0; k < len(stops)-1; k++ {
			if t >= stops[k].Pos && t <= stops[k+1].Pos {
				a, b = stops[k], stops[k+1]
				break
			}
		}
		var u float64
		if b.Pos > a.Pos {
			u = (t - a.Pos) / (b.Pos - a.Pos)
		}
		u = clamp01(u)
		// smoothstep keeps gradients from banding
		u = u * u * (3 - 2*u)
		r := a.R + (b.R-a.R)*u
		g := a.G + (b.G-a.G)*u
		bl := a.B + (b.B-a.B)*u
		p[i] = 0xFF000000 | uint32(f2b(bl))<<16 | uint32(f2b(g))<<8 | uint32(f2b(r))
	}
	return &p
}

func clamp01(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

func f2b(v float64) uint8 {
	if v <= 0 {
		return 0
	}
	if v >= 1 {
		return 255
	}
	return uint8(v*255 + 0.5)
}

func S(pos, r, g, b float64) Stop { return Stop{pos, r, g, b} }

// At returns the colour at position t in [0,1], wrapping.
func (p *Palette) At(t float64) uint32 {
	i := int(t * 255)
	if i < 0 {
		i = 0
	} else if i > 255 {
		i = 255
	}
	return p[i]
}

// AtWrap returns the colour at t, wrapping fractional values around the ramp.
func (p *Palette) AtWrap(t float64) uint32 {
	t -= math.Floor(t)
	i := int(t * 256)
	if i > 255 {
		i = 255
	}
	return p[i]
}

var (
	// Sunset: the demo's signature ramp. Deep violet to hot orange to cream.
	Sunset = New(
		S(0.00, 0.02, 0.00, 0.06),
		S(0.18, 0.25, 0.02, 0.38),
		S(0.38, 0.72, 0.05, 0.45),
		S(0.56, 0.98, 0.25, 0.22),
		S(0.74, 1.00, 0.62, 0.15),
		S(0.88, 1.00, 0.93, 0.55),
		S(1.00, 1.00, 1.00, 0.96),
	)

	// Ice: cold counterpart used by the tunnel and the mandelbrot.
	Ice = New(
		S(0.00, 0.00, 0.00, 0.03),
		S(0.25, 0.00, 0.10, 0.30),
		S(0.50, 0.00, 0.55, 0.85),
		S(0.72, 0.35, 0.90, 1.00),
		S(0.90, 0.80, 1.00, 1.00),
		S(1.00, 1.00, 1.00, 1.00),
	)

	// Ember: fire ramp.
	Ember = New(
		S(0.00, 0.00, 0.00, 0.00),
		S(0.20, 0.25, 0.00, 0.00),
		S(0.45, 0.80, 0.10, 0.00),
		S(0.68, 1.00, 0.45, 0.00),
		S(0.85, 1.00, 0.80, 0.15),
		S(1.00, 1.00, 1.00, 0.85),
	)

	// Acid: green/yellow, used by the grid.
	Acid = New(
		S(0.00, 0.00, 0.02, 0.02),
		S(0.30, 0.00, 0.25, 0.10),
		S(0.55, 0.10, 0.85, 0.45),
		S(0.78, 0.75, 1.00, 0.55),
		S(1.00, 1.00, 1.00, 0.90),
	)

	// Gold: bronze to cream, gives the rotozoom its own identity against the
	// magenta/sunset scenes on either side of it.
	Gold = New(
		S(0.00, 0.03, 0.02, 0.01),
		S(0.30, 0.30, 0.16, 0.03),
		S(0.55, 0.78, 0.50, 0.08),
		S(0.76, 1.00, 0.84, 0.30),
		S(0.90, 1.00, 0.96, 0.70),
		S(1.00, 1.00, 1.00, 0.96),
	)

	// Mono: white-on-black, for the HUD and the credits.
	Mono = New(
		S(0.00, 0.10, 0.10, 0.12),
		S(1.00, 0.92, 0.95, 1.00),
	)
)

// NGon returns a palette from n arbitrary hue stops, evenly spaced.
func NGon(hues ...float64) *Palette {
	stops := make([]Stop, 0, len(hues))
	for i, h := range hues {
		r, g, b := HSL2RGB(h, 0.75, 0.55)
		stops = append(stops, S(float64(i)/float64(len(hues)), r, g, b))
	}
	stops = append(stops, S(1, stops[0].R, stops[0].G, stops[0].B))
	return New(stops...)
}

// HSL2RGB converts hue/sat/light (all 0..1) to RGB components 0..1.
func HSL2RGB(h, s, l float64) (float64, float64, float64) {
	if s == 0 {
		return l, l, l
	}
	var q float64
	if l < 0.5 {
		q = l * (1 + s)
	} else {
		q = l + s - l*s
	}
	p := 2*l - q
	return hue2rgb(p, q, h+1.0/3), hue2rgb(p, q, h), hue2rgb(p, q, h-1.0/3)
}

func hue2rgb(p, q, t float64) float64 {
	if t < 0 {
		t += 1
	}
	if t > 1 {
		t -= 1
	}
	switch {
	case t < 1.0/6:
		return p + (q-p)*6*t
	case t < 1.0/2:
		return q
	case t < 2.0/3:
		return p + (q-p)*(2.0/3-t)*6
	}
	return p
}
