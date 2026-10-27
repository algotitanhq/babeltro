package fx

import (
	"babeltro/internal/canvas"
	"babeltro/internal/fmath"
)

// Grid is the synthwave staple: an infinite checker floor rushing at the
// camera under a banded sun. The floor is a per-pixel perspective divide, and
// the lines come from the fractional part of the world coordinates.
type Grid struct {
	w, h    int
	t       float32
	horizon float32
	asp     float32
}

func NewGrid() *Grid { return &Grid{} }

func (g *Grid) Name() string   { return "GRID" }
func (g *Grid) Parallel() bool { return true }

func (g *Grid) Resize(w, h int) {
	g.w, g.h = w, h
	g.horizon = float32(h) * 0.52
	g.asp = float32(h) / float32(w)
}

func (g *Grid) Prepare(s State, w, h int) {
	if w != g.w || h != g.h {
		g.Resize(w, h)
	}
	g.t = float32(s.Beat)
}

func (g *Grid) Draw(fb *canvas.FB, y0, y1 int) {
	w, h := fb.W, fb.H
	pix := fb.Pix
	horizon := g.horizon
	cx := float32(w) * 0.5
	t := g.t
	asp := g.asp

	// sun parameters
	sunY := horizon - float32(h)*0.13
	sunR := float32(h) * 0.16
	sunX := cx

	for y := y0; y < y1; y++ {
		row := y * w
		fy := float32(y)

		// everything that depends only on the row is hoisted out of the
		// pixel loop; on the floor that is most of the arithmetic
		sky := canvas.Clamp01(float64(fy / horizon))
		skyR := float32(0.03 + 0.18*sky*sky)
		skyG := float32(0.01 + 0.05*sky)
		skyB := float32(0.08 + 0.22*sky)

		onFloor := fy > horizon
		var floorR, floorG, floorB float32
		var kx float32 // world x per screen pixel on this row
		var dz float32 // distance below the horizon, in pixels
		var lineZ, fadeX, lwX float32
		if onFloor {
			dz = fy - horizon
			z := (float32(h) * 0.55) / dz
			wz := z*2.5 + t*5.5
			kx = z / (float32(w) * 0.5) * asp * 2.0
			// same aliasing guard as below, but across the row
			fadeX = float32(canvas.Clamp01(float64((1/kx - 1.5) / 2)))
			lwX = 0.022

			// A line narrower than a pixel lands on only every few pixels and
			// reads as a row of bright dots. Widen it to a full pixel and dim
			// it by the area it actually covers: the same light, spread out,
			// which is what the eye integrates anyway.
			period := dz * dz / (1.375 * float32(h)) // pixels per unit of wz
			lwZ := 0.014 + 0.024/z
			ampZ := float32(1)
			if minW := 0.5 / period; lwZ < minW {
				ampZ = lwZ / minW
				lwZ = minW
			}
			lineZ = lineGlow(mathMod2(wz), lwZ) * ampZ
			// fade lines that have shrunk below a couple of pixels per
			// period, otherwise the horizon boils with aliasing
			lineZ *= float32(canvas.Clamp01(float64((period - 1.5) / 2)))

			fog := float32(canvas.Clamp01(float64(1.0 / (1 + z*z*0.004))))
			lineZ *= fog

			floorR = 0.02
			floorG = 0.01
			floorB = 0.06
			haze := canvas.Clamp01(float64(dz / (float32(h) * 0.12)))
			if haze < 1 {
				floorR += float32(0.25 * (1 - haze))
				floorG += float32(0.05 * (1 - haze))
				floorB += float32(0.35 * (1 - haze))
				// the haze itself is the glow near the horizon
				floorR += 0.55 * float32(lineZ)
				floorG += 0.35 * float32(lineZ)
				floorB += 0.75 * float32(lineZ)
			} else {
				floorR += 0.55 * lineZ
				floorG += 0.35 * lineZ
				floorB += 0.75 * lineZ
			}
		}

		// sun: bounding box test first, then the expensive circle only there
		dyc := fy - sunY
		sunRow := dyc > -sunR && dyc < sunR && fy < horizon+2
		stripe := false
		var sr, sg, sb float32
		if sunRow {
			stripe = fy > sunY-sunR*0.45 && int(fy)%9 < 4
			u := canvas.Clamp01(float64((fy - (sunY - sunR)) / (2 * sunR)))
			sr = 1.0
			sg = float32(0.95 - 0.7*u)
			sb = float32(0.25 + 0.55*u)
		}

		for x := 0; x < w; x++ {
			r, gg, b := skyR, skyG, skyB

			if sunRow && !stripe {
				dx := float32(x) - sunX
				if dx > -sunR && dx < sunR {
					d := fmath.Sqrt(dx*dx + dyc*dyc)
					if d < sunR {
						edge := float32(canvas.Clamp01(float64((sunR - d) / (sunR * 0.025))))
						r = mix(r, sr, edge)
						gg = mix(gg, sg, edge)
						b = mix(b, sb, edge)
					}
				}
			}

			if onFloor {
				// How far this ray slides sideways between one row and the
				// next, in pixels: x = (k-0.37)/kx + cx, so dx/dy = |x-cx|/dz.
				// The line must be at least that wide, and dimmed by the same
				// ratio, or each row shows a handful of isolated bright dots
				// instead of a line.
				off := absf(float32(x) - cx)
				wPx := 2 * lwX / kx
				if slide := off / dz; slide > wPx {
					wPx = slide
				}
				if wPx < 1 {
					wPx = 1
				}
				lineX := lineGlow(mathMod2((float32(x)-cx)*kx+0.37), wPx*kx*0.5) *
					(2 * lwX / kx / wPx) * fadeX
				line := lineX
				if lineZ > line {
					line = lineZ
				}
				r = floorR - 0.55*lineZ + 0.55*line
				gg = floorG - 0.35*lineZ + 0.35*line
				b = floorB - 0.75*lineZ + 0.75*line
			}

			pix[row+x] = canvas.FromFloat(float64(r), float64(gg), float64(b))
		}
	}
}

// mathMod returns v mod 2 in [0,2), working for negatives.
func mathMod(v, period float32) float32 {
	if period == 0 {
		return 0
	}
	m := v - float32(int(v/period))*period
	if m < 0 {
		m += period
	}
	return m
}

// mathMod2 wraps a world coordinate into [0,1).
func mathMod2(v float32) float32 {
	m := v - float32(int(v))
	if m < 0 {
		m += 1
	}
	return m
}

// lineGlow returns 1 on the grid line, falling to 0 over width w.
func lineGlow(f, w float32) float32 {
	d := f
	if d > 0.5 {
		d = 1 - d
	}
	if d < w {
		return 1 - d/w
	}
	return 0
}

func mix(a, b, t float32) float32 { return a + (b-a)*t }

func absf(v float32) float32 {
	if v < 0 {
		return -v
	}
	return v
}
