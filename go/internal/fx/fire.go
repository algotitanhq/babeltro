package fx

import (
	"rosette/internal/canvas"
	"rosette/internal/fmath"
	"rosette/internal/palette"
)

// Fire is the Doom fire algorithm: a heat buffer that is seeded at the bottom
// row and diffused upward with a little random sideways drift. It is integer
// only, one byte per pixel, and reads beautifully through a palette ramp.
type Fire struct {
	w, h  int
	buf   []uint8
	pal   *palette.Palette
	rng   uint32
	frame uint64
}

func NewFire() *Fire { return &Fire{pal: palette.Ember, rng: 0x9E3779B9} }

func (f *Fire) Name() string   { return "FIRE" }
func (f *Fire) Parallel() bool { return false }

func (f *Fire) Resize(w, h int) {
	if w == f.w && h == f.h {
		return
	}
	f.w, f.h = w, h
	f.buf = make([]uint8, w*h)
}

// rand is a xorshift32: vastly cheaper than math/rand in a per-pixel loop.
func (f *Fire) rand() uint32 {
	x := f.rng
	x ^= x << 13
	x ^= x >> 17
	x ^= x << 5
	f.rng = x
	return x
}

func (f *Fire) Prepare(s State, w, h int) {
	if w != f.w || h != f.h || f.buf == nil {
		f.Resize(w, h)
	}
	f.frame = s.Frame
}

func (f *Fire) Draw(fb *canvas.FB, y0, y1 int) {
	w, h := fb.W, fb.H
	if f.buf == nil || f.w != w || f.h != h {
		f.Resize(w, h)
	}
	buf := f.buf

	// seed the hottest row: a slow horizontal wave gives the fire its uneven
	// base, the random term keeps the tongues from looking periodic
	last := (h - 1) * w
	t := float32(f.frame) * 0.05
	for x := 0; x < w; x++ {
		fx := float32(x) / float32(w)
		wv := 0.5 + 0.5*fmath.Sin(fx*11+t)*0.6 + 0.5*fmath.Sin(fx*23-t*1.7)*0.4
		v := 150 + wv*90 + float32(f.rand()&31) - 16
		if v > 255 {
			v = 255
		} else if v < 90 {
			v = 90
		}
		buf[last+x] = uint8(v)
	}

	// diffuse upward: every destination pixel takes one value from the row
	// below, offset sideways by a random -1/0/+1. Gather, not scatter, so each
	// pixel is written exactly once: no holes, no salt-and-pepper noise.
	//
	// The palette lookup for a row happens as soon as that row is complete, so
	// the buffer is touched once per frame instead of twice.
	pal := f.pal
	pix := fb.Pix
	lastRow := (h - 1) * w
	for x := 0; x < w; x++ {
		pix[lastRow+x] = pal[buf[lastRow+x]]
	}
	for y := h - 1; y > 0; y-- {
		src := y * w
		dst := (y - 1) * w
		for x := 0; x < w; x++ {
			if buf[src+x] == 0 {
				if buf[dst+x] != 0 {
					buf[dst+x] = 0
				}
				continue
			}
			r := f.rand()
			sx := x + int(r%3) - 1 // -1, 0 or +1, with no sideways drift
			if sx < 0 {
				sx = 0
			} else if sx >= w {
				sx = w - 1
			}
			v := buf[src+sx]
			if decay := uint8(r >> 16 & 1); v > decay {
				buf[dst+x] = v - decay
			} else {
				buf[dst+x] = 0
			}
		}
		prow := pix[dst : dst+w]
		brow := buf[dst : dst+w]
		for x := range prow {
			prow[x] = pal[brow[x]]
		}
	}
}
