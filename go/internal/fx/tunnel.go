package fx

import (
	"babeltro/internal/canvas"
	"babeltro/internal/fmath"
	"babeltro/internal/palette"
)

// Tunnel maps every pixel to polar coordinates once, at resize time. After
// that the per-pixel work is a couple of table lookups and a palette read —
// the geometry is free, which is why it can afford to look this good.
type Tunnel struct {
	w, h  int
	depth []float32 // falls off as 1/r: large at the centre, small at the edge
	angle []float32 // atan2 fraction of a turn, [0,1)
	t     float32
	pal   *palette.Palette

	// the ladder: 1 computes the distance and the angle for every pixel,
	// every frame; 2 (the default) reads them from tables built at resize
	step int
}

func (t *Tunnel) SetStep(n int) { t.step = n }

func NewTunnel() *Tunnel { return &Tunnel{pal: palette.Ice} }

func (t *Tunnel) Name() string   { return "TUNNEL" }
func (t *Tunnel) Parallel() bool { return true }

func (t *Tunnel) Resize(w, h int) {
	if w == t.w && h == t.h {
		return
	}
	t.w, t.h = w, h
	// scale with the diagonal so the rings look the same at any resolution
	scale := float32(w+h) * 2.2
	t.depth = fmath.DistInvTab(w, h, scale, float32(w+h)*0.02)
	t.angle = fmath.Atan2Tab(w, h)
}

func (t *Tunnel) Prepare(s State, w, h int) {
	if w != t.w || h != t.h {
		t.Resize(w, h)
	}
	t.t = float32(s.Beat)
}

func (t *Tunnel) Draw(fb *canvas.FB, y0, y1 int) {
	if t.step == 1 {
		t.drawDirect(fb, y0, y1)
		return
	}
	w := fb.W
	pix := fb.Pix
	pal := t.pal
	tm := t.t
	adv := tm * 3.0
	spin := tm * 0.25

	// @excerpt TUNNEL
	for y := y0; y < y1; y++ {
		row := y * w
		for x := 0; x < w; x++ {
			i := row + x
			u := t.depth[i] + adv // scroll towards the viewer
			v := t.angle[i]

			// rings along the depth axis
			ring := fmath.Sin01(u * 0.16)
			// spokes that twist as they recede
			twist := v*12 + u*0.09 + spin
			spoke := fmath.Sin01(twist)

			val := ring*0.55 + spoke*0.45
			// brick checker gives the walls their structure
			if (int(u*0.32)+int(twist))&1 == 1 {
				val = -val * 0.7
			}

			fog := 1 / (1 + u*0.02)
			lum := (val*0.5 + 0.5) * fog
			// a cold rim on the brightest ridges
			idx := int(lum * 300)
			if idx > 255 {
				idx = 255
			}
			if idx < 0 {
				idx = 0
			}
			pix[i] = pal[idx]
		}
	}
	// @end
}

// drawDirect is the tunnel without its tables: a square root, a division and
// an atan2 per pixel, every frame, for values that never change. The
// formulas are the ones the tables are built from, so the pixels are the
// same; only the time differs.
func (t *Tunnel) drawDirect(fb *canvas.FB, y0, y1 int) {
	w, h := fb.W, fb.H
	pix := fb.Pix
	pal := t.pal
	tm := t.t
	adv := tm * 3.0
	spin := tm * 0.25
	cx, cy := float32(w)/2, float32(h)/2
	scale := float32(w+h) * 2.2
	soft := float32(w+h) * 0.02

	// @excerpt TUNNEL/1
	for y := y0; y < y1; y++ {
		dy := float32(y) - cy
		for x := 0; x < w; x++ {
			dx := float32(x) - cx
			depth := scale / (fmath.Sqrt(dx*dx+dy*dy) + soft)
			u := depth + adv
			v := fmath.Atan2(dy, dx)

			ring := fmath.Sin01(u * 0.16)
			twist := v*12 + u*0.09 + spin
			spoke := fmath.Sin01(twist)
			val := ring*0.55 + spoke*0.45
			if (int(u*0.32)+int(twist))&1 == 1 {
				val = -val * 0.7
			}
			fog := 1 / (1 + u*0.02)
			lum := (val*0.5 + 0.5) * fog
			idx := int(lum * 300)
			if idx > 255 {
				idx = 255
			}
			if idx < 0 {
				idx = 0
			}
			pix[y*w+x] = pal[idx]
		}
	}
	// @end
}
