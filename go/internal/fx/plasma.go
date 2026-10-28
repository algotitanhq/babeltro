package fx

import (
	"math"

	"babeltro/internal/canvas"
	"babeltro/internal/fmath"
	"babeltro/internal/palette"
)

// Plasma is four summed sine fields, the oldest trick in the demoscene book.
// Done naively it is four sin() calls per pixel; here three of the four terms
// are 1D tables rebuilt once per frame, leaving a single lookup per pixel.
type Plasma struct {
	w, h        int
	rad         []float32
	sx, sy, sxy []float32
	phase       float32
	pal         *palette.Palette

	// the ladder: 1 calls sin() four times per pixel, 2 reads the sine table
	// four times per pixel, 3 (the default) moves three of the four lookups
	// into per-frame 1D tables
	step       int
	t, kx, ky  float32
	cx, cy, kr float32
}

func (p *Plasma) SetStep(n int) { p.step = n }

func NewPlasma() *Plasma { return &Plasma{pal: palette.Sunset} }

func (p *Plasma) Name() string   { return "PLASMA" }
func (p *Plasma) Parallel() bool { return true }

func (p *Plasma) Resize(w, h int) {
	if w == p.w && h == p.h {
		return
	}
	p.w, p.h = w, h
	p.rad = make([]float32, w*h)
	cx, cy := float32(w)*0.5, float32(h)*0.5
	k := 44.0 / float32(w+h)
	for y := 0; y < h; y++ {
		dy := float32(y) - cy
		base := y * w
		for x := 0; x < w; x++ {
			dx := float32(x) - cx
			p.rad[base+x] = fmath.Sqrt(dx*dx+dy*dy) * k
		}
	}
	p.sx = make([]float32, w)
	p.sy = make([]float32, h)
	p.sxy = make([]float32, w+h)
}

func (p *Plasma) Prepare(s State, w, h int) {
	if w != p.w || h != p.h {
		p.Resize(w, h)
	}
	t := float32(s.Beat)
	kx := 26.0 / float32(w)
	ky := 26.0 / float32(h)
	for x := 0; x < w; x++ {
		p.sx[x] = fmath.Sin(float32(x)*kx + t*1.3)
	}
	for y := 0; y < h; y++ {
		p.sy[y] = fmath.Sin(float32(y)*ky*1.35 - t*1.1)
	}
	for i := 0; i < w+h; i++ {
		p.sxy[i] = fmath.Sin(float32(i)*kx*0.85 + t*0.8)
	}
	p.phase = t * 2.6
	p.t, p.kx, p.ky = t, kx, ky
	p.cx, p.cy = float32(w)*0.5, float32(h)*0.5
	p.kr = 44.0 / float32(w+h)
}

func (p *Plasma) Draw(fb *canvas.FB, y0, y1 int) {
	switch p.step {
	case 1:
		p.drawSin(fb, y0, y1)
		return
	case 2:
		p.drawTable(fb, y0, y1)
		return
	}
	w := fb.W
	pix := fb.Pix
	pal := p.pal
	phase := p.phase
	// @excerpt PLASMA
	for y := y0; y < y1; y++ {
		sy := p.sy[y]
		row := y * w
		rad := p.rad[row : row+w]
		sxy := p.sxy[y : y+w]
		for x := 0; x < w; x++ {
			v := p.sx[x] + sy + sxy[x] + fmath.Sin(rad[x]+phase)
			i := int(v*36 + 127.5)
			if i < 0 {
				i = 0
			} else if i > 255 {
				i = 255
			}
			pix[row+x] = pal[i]
		}
	}
	// @end
}

// sin32 is the maths library's sine, rounded to float32 like the table.
func sin32(a float32) float32 { return float32(math.Sin(float64(a))) }

// drawSin is the plasma as you would first write it: every term, every
// pixel, straight from the maths library. Slow, and the reference for what
// the table approximates.
func (p *Plasma) drawSin(fb *canvas.FB, y0, y1 int) {
	w := fb.W
	pix := fb.Pix
	t, kx, ky, kr := p.t, p.kx, p.ky, p.kr
	// @excerpt PLASMA/1
	for y := y0; y < y1; y++ {
		dy := float32(y) - p.cy
		for x := 0; x < w; x++ {
			dx := float32(x) - p.cx
			rad := float32(math.Sqrt(float64(dx*dx+dy*dy))) * kr
			v := sin32(float32(x)*kx+t*1.3) +
				sin32(float32(y)*ky*1.35-t*1.1) +
				sin32(float32(x+y)*kx*0.85+t*0.8) +
				sin32(rad+p.phase)
			i := int(v*36 + 127.5)
			if i < 0 {
				i = 0
			} else if i > 255 {
				i = 255
			}
			pix[y*w+x] = p.pal[i]
		}
	}
	// @end
}

// drawTable keeps the per-pixel structure of drawSin but reads the sine
// table instead of calling sin(). Same arguments, so the same pixels as the
// optimised version; the only change from drawSin is the table's precision.
func (p *Plasma) drawTable(fb *canvas.FB, y0, y1 int) {
	w := fb.W
	pix := fb.Pix
	t, kx, ky, kr := p.t, p.kx, p.ky, p.kr
	// @excerpt PLASMA/2
	for y := y0; y < y1; y++ {
		dy := float32(y) - p.cy
		for x := 0; x < w; x++ {
			dx := float32(x) - p.cx
			rad := fmath.Sqrt(dx*dx+dy*dy) * kr
			v := fmath.Sin(float32(x)*kx+t*1.3) +
				fmath.Sin(float32(y)*ky*1.35-t*1.1) +
				fmath.Sin(float32(x+y)*kx*0.85+t*0.8) +
				fmath.Sin(rad+p.phase)
			i := int(v*36 + 127.5)
			if i < 0 {
				i = 0
			} else if i > 255 {
				i = 255
			}
			pix[y*w+x] = p.pal[i]
		}
	}
	// @end
}
