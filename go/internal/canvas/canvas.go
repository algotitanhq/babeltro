// Package canvas holds the software framebuffer every effect draws into.
//
// Pixels are packed as 0xAABBGGRR in a uint32, which in little-endian memory
// is exactly the byte order OpenGL's GL_RGBA/GL_UNSIGNED_BYTE upload expects.
// So a frame can go from the CPU loop to the screen without a single copy.
package canvas

import "math"

// RGB packs a colour into the framebuffer's uint32 layout.
func RGB(r, g, b uint8) uint32 {
	return 0xFF000000 | uint32(b)<<16 | uint32(g)<<8 | uint32(r)
}

// RGBA packs a colour with alpha.
func RGBA(r, g, b, a uint8) uint32 {
	return uint32(a)<<24 | uint32(b)<<16 | uint32(g)<<8 | uint32(r)
}

// FromFloat packs normalised floats to a colour, clamping to [0,1].
func FromFloat(r, g, b float64) uint32 {
	return RGB(f2b(r), f2b(g), f2b(b))
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

// FB is a linear RGBA framebuffer.
type FB struct {
	W, H int
	Pix  []uint32
}

func New(w, h int) *FB {
	return &FB{W: w, H: h, Pix: make([]uint32, w*h)}
}

// Resize reallocates only when the dimensions actually changed, so a resize
// does not cost an allocation every frame.
func (fb *FB) Resize(w, h int) {
	if fb.W == w && fb.H == h {
		return
	}
	fb.W, fb.H = w, h
	fb.Pix = make([]uint32, w*h)
}

func (fb *FB) Fill(c uint32) {
	for i := range fb.Pix {
		fb.Pix[i] = c
	}
}

// FadeTo darkens every pixel towards black by amount (0..1), used by
// transitions. It is branch-free inside the loop.
func (fb *FB) FadeTo(amount float64) {
	if amount <= 0 {
		return
	}
	if amount >= 1 {
		for i := range fb.Pix {
			fb.Pix[i] = 0xFF000000
		}
		return
	}
	// Integer multiplier avoids a float multiply per pixel.
	m := uint32((1 - amount) * 256)
	for i, p := range fb.Pix {
		r := (p & 0xFF) * m >> 8
		g := (p >> 8 & 0xFF) * m >> 8
		b := (p >> 16 & 0xFF) * m >> 8
		fb.Pix[i] = 0xFF000000 | b<<16 | g<<8 | r
	}
}

// Additive adds a colour scaled by intensity/255, saturating.
func (fb *FB) Additive(i int, c uint32, intensity uint8) {
	if intensity == 0 {
		return
	}
	p := fb.Pix[i]
	r := uint32(p&0xFF) + uint32(c&0xFF)*uint32(intensity)/255
	g := uint32(p>>8&0xFF) + uint32(c>>8&0xFF)*uint32(intensity)/255
	b := uint32(p>>16&0xFF) + uint32(c>>16&0xFF)*uint32(intensity)/255
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

// FillRect blends a colour over a rectangle. alpha < 255 tints instead of
// replacing, which is how the HUD panel stays readable over bright scenes.
func (fb *FB) FillRect(x, y, w, h int, c uint32, alpha uint8) {
	if x < 0 {
		w += x
		x = 0
	}
	if y < 0 {
		h += y
		y = 0
	}
	if x+w > fb.W {
		w = fb.W - x
	}
	if y+h > fb.H {
		h = fb.H - y
	}
	if w <= 0 || h <= 0 {
		return
	}
	if alpha == 255 {
		for yy := y; yy < y+h; yy++ {
			row := yy * fb.W
			for xx := x; xx < x+w; xx++ {
				fb.Pix[row+xx] = c
			}
		}
		return
	}
	a := uint32(alpha)
	ia := 255 - a
	for yy := y; yy < y+h; yy++ {
		row := yy * fb.W
		for xx := x; xx < x+w; xx++ {
			i := row + xx
			p := fb.Pix[i]
			r := (uint32(p&0xFF)*ia + uint32(c&0xFF)*a) / 255
			g := (uint32(p>>8&0xFF)*ia + uint32(c>>8&0xFF)*a) / 255
			b := (uint32(p>>16&0xFF)*ia + uint32(c>>16&0xFF)*a) / 255
			fb.Pix[i] = 0xFF000000 | b<<16 | g<<8 | r
		}
	}
}

// HLine draws a 1px horizontal line, used by the HUD graphs.
func (fb *FB) HLine(x, y, w int, c uint32) {
	if y < 0 || y >= fb.H {
		return
	}
	row := y * fb.W
	for xx := x; xx < x+w; xx++ {
		if xx >= 0 && xx < fb.W {
			fb.Pix[row+xx] = c
		}
	}
}

// VLine draws a 1px vertical line.
func (fb *FB) VLine(x, y, h int, c uint32) {
	if x < 0 || x >= fb.W {
		return
	}
	lo, hi := y, y+h
	if lo < 0 {
		lo = 0
	}
	if hi > fb.H {
		hi = fb.H
	}
	for yy := lo; yy < hi; yy++ {
		fb.Pix[yy*fb.W+x] = c
	}
}

// Sine returns a sine table lookup, kept here so effects share one source.
func Sine(phase float64) float64 { return math.Sin(phase) }

// Clamp01 clamps a float to [0,1].
func Clamp01(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}
