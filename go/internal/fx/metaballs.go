package fx

import (
	"babeltro/internal/canvas"
	"babeltro/internal/fmath"
	"babeltro/internal/palette"
)

// Metaballs sums radial fields and shades the iso-contours. The cheap trick:
// every pixel evaluates sum(r^2 / d^2) with one reciprocal, no square roots,
// and the contour band gets a hot rim so the blobs read as liquid rather than
// as a flat gradient.
type Metaballs struct {
	w, h int
	pal  *palette.Palette
	t    float32
	ball [6][2]float32 // centre x,y in normalised space
	rad  [6]float32
	n    int
}

func NewMetaballs() *Metaballs { return &Metaballs{pal: palette.Sunset, n: 6} }

func (m *Metaballs) Name() string   { return "METABALLS" }
func (m *Metaballs) Parallel() bool { return true }

func (m *Metaballs) Resize(w, h int) { m.w, m.h = w, h }

func (m *Metaballs) Prepare(s State, w, h int) {
	m.w, m.h = w, h
	t := float32(s.Beat)
	m.t = t
	for i := 0; i < m.n; i++ {
		fi := float32(i)
		// each ball orbits on its own ellipse and breathes
		a := t*(0.35+fi*0.07) + fi*2.1
		m.ball[i][0] = 0.5 + 0.20*fmath.Cos(a)*float32(1+0.3*fmath.Sin(t*0.5+fi))
		m.ball[i][1] = 0.5 + 0.20*fmath.Sin(a*1.3+fi)*float32(1+0.3*fmath.Cos(t*0.4+fi*2))
		m.rad[i] = 0.105 + 0.025*fmath.Sin(t*1.1+fi*1.7)
	}
}

func (m *Metaballs) Draw(fb *canvas.FB, y0, y1 int) {
	w, h := fb.W, fb.H
	pix := fb.Pix
	pal := m.pal
	// x is scaled by width/height so a circle in field space is a circle on
	// screen, whatever the aspect ratio
	asp := float32(w) / float32(h)
	// the field is sum(r^2 / d^2): about 1 on a ball's own surface
	rad2 := [6]float32{}
	for i := 0; i < m.n; i++ {
		rad2[i] = m.rad[i] * m.rad[i]
	}
	// @excerpt METABALLS
	for y := y0; y < y1; y++ {
		fy := float32(y)/float32(h) - 0.5
		row := y * w
		for x := 0; x < w; x++ {
			fx := (float32(x)/float32(w) - 0.5) * asp
			var field float32
			for i := 0; i < m.n; i++ {
				dx := fx - (m.ball[i][0]-0.5)*asp
				dy := fy - (m.ball[i][1] - 0.5)
				d2 := dx*dx + dy*dy + 1e-5
				field += rad2[i] / d2
			}
			// field is about 1 at the surface of a ball and explodes inside;
			// v/(1+v) compresses that into a usable 0..1 ramp without a log.
			v := field / (1.6 + field)
			idx := int(v * 255)
			if idx > 255 {
				idx = 255
			}
			// rim: the iso-surface where the balls meet flares white
			if field > 1.0 && field < 1.09 {
				idx = 255
			}
			pix[row+x] = pal[idx]
		}
	}
	// @end
}
