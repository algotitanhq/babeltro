package fx

import (
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
	sxy2        []float32
	phase       float32
	pal         *palette.Palette
}

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
	p.sxy2 = make([]float32, w+h)
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
		p.sxy2[i] = fmath.Sin(float32(i)*kx*1.31 - t*0.6)
	}
	p.phase = t * 2.6
}

// @excerpt PLASMA
func (p *Plasma) Draw(fb *canvas.FB, y0, y1 int) {
	w := fb.W
	pix := fb.Pix
	pal := p.pal
	phase := p.phase
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
}

// @end
