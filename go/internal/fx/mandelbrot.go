package fx

import (
	"math"

	"babeltro/internal/canvas"
	"babeltro/internal/palette"
)

// Mandelbrot dives into the boundary forever. It is the most expensive scene
// in the demo, so it renders on a coarse grid and stretches the result: at
// 60 fps in motion nobody can tell, and the speed budget stays honest.
type Mandelbrot struct {
	w, h    int
	pal     *palette.Palette
	cx, cy  float64
	scale   float64
	maxIter int
	step    int
}

func NewMandelbrot() *Mandelbrot {
	return &Mandelbrot{pal: palette.Ice, maxIter: 192, step: 2}
}

func (m *Mandelbrot) Name() string   { return "MANDELBROT" }
func (m *Mandelbrot) Parallel() bool { return true }

func (m *Mandelbrot) Resize(w, h int) {
	m.w, m.h = w, h
	// keep the block size constant in screen terms as the window grows
	m.step = 2
	if w > 1600 {
		m.step = 3
	}
}

func (m *Mandelbrot) Prepare(s State, w, h int) {
	if w != m.w || h != m.h {
		m.Resize(w, h)
	}
	t := s.Beat
	if t > 14 {
		t = 14
	}
	u := t / 12
	// the camera slides onto the target point quickly, then the exponential
	// dive does the work; drifting the centre linearly with the zoom would
	// spend most of the scene looking at empty plane
	k := 1 - math.Exp(-8*u)
	// tested target: the seahorse valley, where the boundary never opens into
	// a flat interior, so the whole frame stays fractal at any depth
	m.scale = 2.9 * math.Exp(-u*u*3.6)
	// the deep frames need the iteration budget; the wide ones do not, and
	// spending it there would cost the whole frame for nothing
	m.maxIter = 64 + int(128*u)
	m.cx = -0.5 + (-0.743643887037151+0.5)*k
	m.cy = 0.0 + 0.131825904205330*k
}

func (m *Mandelbrot) Draw(fb *canvas.FB, y0, y1 int) {
	w, h := fb.W, fb.H
	step := m.step
	asp := float64(h) / float64(w)
	span := m.scale
	x0 := m.cx - span*0.5
	y0w := m.cy - span*0.5*asp
	// units per pixel: a block is step pixels wide, and the loop below advances
	// by whole blocks, so this must not be divided by step as well
	d := span / float64(w)

	maxIter := m.maxIter
	pal := m.pal

	// iterate over blocks, not rows: each block is computed exactly once, by
	// the band that owns its first row
	sy := (y0 + step - 1) / step
	for ; sy*step < y1; sy++ {
		cy := y0w + float64(sy*step)*d
		yStart := sy * step
		yEnd := yStart + step
		if yEnd > h {
			yEnd = h
		}
		for x := 0; x < w; x += step {
			sx := x / step
			cx := x0 + float64(sx*step)*d
			it := mandelIter(cx, cy, maxIter)
			var c uint32
			if it >= maxIter {
				c = 0xFF0A0812
			} else {
				// the ramp is anchored to a fixed iteration count, not to
				// maxIter, so raising the iteration budget to survive a deep
				// zoom does not darken the whole picture
				v := math.Sqrt(float64(it) / 40)
				if v > 1 {
					v = 1
				}
				c = pal.At(v*0.92 + 0.04)
			}
			xEnd := x + step
			if xEnd > w {
				xEnd = w
			}
			for yy := yStart; yy < yEnd; yy++ {
				row := yy * w
				for xx := x; xx < xEnd; xx++ {
					fb.Pix[row+xx] = c
				}
			}
		}
	}
}

// @excerpt MANDELBROT
func mandelIter(cx, cy float64, max int) int {
	// cheap escape test for the main cardioid and the period-2 bulb
	x := cx - 0.25
	y2 := cy * cy
	q := x*x + y2
	if q*(q+x) <= 0.25*y2 {
		return max
	}
	if (cx+1)*(cx+1)+y2 <= 0.0625 {
		return max
	}
	zx, zy := 0.0, 0.0
	zx2, zy2 := 0.0, 0.0
	for i := 0; i < max; i++ {
		zy = 2*zx*zy + cy
		zx = zx2 - zy2 + cx
		zx2 = zx * zx
		zy2 = zy * zy
		if zx2+zy2 > 4 {
			return i
		}
	}
	return max
}

// @end
