package fx

import (
	"math"
	"math/rand"

	"babeltro/internal/canvas"
)

// Starfield is a warp-speed star tunnel: stars live in 3D, get projected in
// perspective and dragged into short streaks. The streak is what sells the
// speed, so each star draws from its previous depth to its current one.
type Starfield struct {
	w, h   int
	stars  []star3
	proj   []starProj
	bg     []uint32 // precomputed backdrop: it never changes, so build it once
	seeded bool
}

type star3 struct {
	x, y, z float32
	h       float32 // hue: 0 cool blue, 1 warm white
}

type starProj struct {
	x0, y0, x1, y1 int32
	c              uint32
}

func NewStarfield() *Starfield { return &Starfield{} }

func (s *Starfield) Name() string   { return "STARFIELD" }
func (s *Starfield) Parallel() bool { return false }

func (s *Starfield) Resize(w, h int) {
	if w == s.w && h == s.h {
		return
	}
	s.w, s.h = w, h
	if !s.seeded {
		rng := rand.New(rand.NewSource(0x6005E))
		s.stars = make([]star3, 1600)
		for i := range s.stars {
			s.stars[i] = star3{
				x: (rng.Float32()*2 - 1) * 1.6,
				y: (rng.Float32()*2 - 1) * 1.6,
				z: rng.Float32()*40 + 0.2,
			}
		}
		s.proj = make([]starProj, len(s.stars))
		s.seeded = true
	}
	s.buildBackdrop()
}

// buildBackdrop paints the deep-navy vignette once per size change. Copying a
// ready row is two orders of magnitude cheaper than evaluating it per pixel
// per frame, and this is the trick the rest of the demo leans on too.
func (s *Starfield) buildBackdrop() {
	w, h := s.w, s.h
	if cap(s.bg) < w*h {
		s.bg = make([]uint32, w*h)
	}
	s.bg = s.bg[:w*h]
	for y := 0; y < h; y++ {
		dy := float64(y)/float64(h) - 0.5
		row := s.bg[y*w : (y+1)*w]
		for x := 0; x < w; x++ {
			dx := float64(x)/float64(w) - 0.5
			v := dx*dx + dy*dy
			r := 0.02 - v*0.03
			g := 0.02 - v*0.025
			b := 0.05 - v*0.03
			if r < 0 {
				r = 0
			}
			if g < 0 {
				g = 0
			}
			if b < 0 {
				b = 0
			}
			row[x] = canvas.FromFloat(r, g, b)
		}
	}
}

func (s *Starfield) Prepare(st State, w, h int) {
	if w != s.w || h != s.h {
		s.Resize(w, h)
	}
	cx, cy := float32(w)*0.5, float32(h)*0.5
	// accelerate over the scene so the entry has a kick
	speed := float32(2.5 + math.Min(st.Beat, 3)*4)
	dt := float32(st.DT)
	if dt > 0.1 {
		dt = 0.1
	}

	dz := speed * dt
	for i := range s.stars {
		p := &s.stars[i]
		p.z -= dz
		if p.z < 0.8 {
			p.z += 40
			p.x = (rand.Float32()*2 - 1) * 1.1
			p.y = (rand.Float32()*2 - 1) * 1.1
		}
		f := 1.0 / p.z
		zoom := float32(w) * 0.78
		x0 := cx + p.x*f*zoom
		y0 := cy + p.y*f*zoom
		f2 := 1.0 / (p.z + dz*2.4)
		x1 := cx + p.x*f2*zoom
		y1 := cy + p.y*f2*zoom

		// brighter and bluer as the star gets close
		near := 1 - p.z/40
		b := near * near
		r := uint32(120*b + 40)
		g := uint32(190*b + 40)
		bl := uint32(255 * (0.25 + 0.75*b))
		s.proj[i] = starProj{
			x0: int32(x0), y0: int32(y0),
			x1: int32(x1), y1: int32(y1),
			c: 0xFF000000 | bl<<16 | g<<8 | r,
		}
	}
}

func (s *Starfield) Draw(fb *canvas.FB, y0, y1 int) {
	w, h := fb.W, fb.H
	if len(s.bg) == w*h {
		copy(fb.Pix[y0*w:y1*w], s.bg[y0*w:y1*w])
	} else {
		fb.Fill(0xFF050405)
	}
	for i := range s.proj {
		p := &s.proj[i]
		// additive line from the trailing point to the head
		drawLineAdd(fb, int(p.x0), int(p.y0), int(p.x1), int(p.y1), p.c)
		// bright head pixel
		if p.x1 >= 0 && p.x1 < int32(w) && p.y1 >= 0 && p.y1 < int32(h) {
			fb.Pix[int(p.y1)*w+int(p.x1)] = 0xFFCCEEFF
		}
	}
}

// drawLineAdd draws a Bresenham line adding colour, so overlapping stars
// accumulate brightness instead of replacing each other.
func drawLineAdd(fb *canvas.FB, x0, y0, x1, y1 int, c uint32) {
	dx := abs(x1 - x0)
	dy := -abs(y1 - y0)
	sx, sy := -1, -1
	if x0 < x1 {
		sx = 1
	}
	if y0 < y1 {
		sy = 1
	}
	err := dx + dy
	for {
		if x0 >= 0 && x0 < fb.W && y0 >= 0 && y0 < fb.H {
			i := y0*fb.W + x0
			p := fb.Pix[i]
			r := uint32(p&0xFF) + c&0xFF
			g := uint32(p>>8&0xFF) + c>>8&0xFF
			b := uint32(p>>16&0xFF) + c>>16&0xFF
			if r > 255 {
				r = 255
			}
			if g > 255 {
				g = 255
			}
			if b > 255 {
				b = 255
			}
			fb.Pix[i] = 0xFF000000 | b<<16 | g<<8 | r
		}
		if x0 == x1 && y0 == y1 {
			break
		}
		e2 := 2 * err
		if e2 >= dy {
			err += dy
			x0 += sx
		}
		if e2 <= dx {
			err += dx
			y0 += sy
		}
	}
}

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
