package fx

import (
	"math"

	"babeltro/internal/canvas"
	"babeltro/internal/fmath"
	"babeltro/internal/palette"
)

// Rotozoom is the purest demoscene move: build a texture once, then every
// frame rotate and zoom the sampling grid over it. Cost per pixel is a few
// multiplies and one lookup.
type Rotozoom struct {
	w, h  int
	tex   []uint32
	cosA  float32
	sinA  float32
	zoom  float32
	offx  float32
	offy  float32
	lastW int
	lastH int
}

const texSize = 512
const texMask = texSize - 1

func NewRotozoom() *Rotozoom { return &Rotozoom{} }

func (r *Rotozoom) Name() string   { return "ROTOZOOM" }
func (r *Rotozoom) Parallel() bool { return true }

func (r *Rotozoom) Resize(w, h int) {
	r.w, r.h = w, h
	if r.tex == nil {
		r.buildTexture()
	}
}

// buildTexture makes a tileable rainbow plasma once, at startup. Building it
// costs a few hundred thousand sine calls; doing the same work per frame would
// cost the whole budget, which is the point of the scene.
func (r *Rotozoom) buildTexture() {
	twoPi := 2 * math.Pi
	r.tex = make([]uint32, texSize*texSize)
	for y := 0; y < texSize; y++ {
		fy := float32(y) / texSize
		for x := 0; x < texSize; x++ {
			fx := float32(x) / texSize
			// the pattern has to wrap every 512 pixels, so every frequency is
			// a whole number of cycles per tile
			v := math.Sin(float64(fx)*twoPi*3+float64(fy)*twoPi*2)*0.5 +
				math.Sin(float64(fy)*twoPi*5-float64(fx)*twoPi*4)*0.3 +
				math.Sin((float64(fx)+float64(fy))*twoPi*7)*0.2
			// concentric rings, also periodic in the tile
			dx := float64(x) - texSize/2
			dy := float64(y) - texSize/2
			rr := math.Sqrt(dx*dx+dy*dy) / texSize * 12
			v += math.Sin(rr*twoPi) * 0.35

			hue := math.Mod(v*0.55+0.5, 1)
			if hue < 0 {
				hue += 1
			}
			cr, cg, cb := palette.HSL2RGB(hue, 0.70, 0.48+0.14*v)

			// a dark grid over the colour: without a straight edge the
			// rotation and the zoom read as random shimmer instead of motion
			gx := x%(texSize/8) < 3
			gy := y%(texSize/8) < 3
			if gx || gy {
				cr *= 0.28
				cg *= 0.28
				cb *= 0.28
			}
			r.tex[y*texSize+x] = canvas.FromFloat(cr, cg, cb)
		}
	}
}

func (r *Rotozoom) Prepare(s State, w, h int) {
	if w != r.w || h != r.h {
		r.Resize(w, h)
	}
	if r.tex == nil {
		r.buildTexture()
	}
	t := float32(s.Beat)
	ang := t * 0.45
	r.cosA = fmath.Cos(ang)
	r.sinA = fmath.Sin(ang)
	// breathing zoom: 0.7 .. 1.6
	r.zoom = 0.55 + 0.45*fmath.Sin(t*0.7) + 0.35
	r.offx = fmath.Sin(t*0.31)*180 + t*26
	r.offy = fmath.Cos(t*0.27)*180 + t*19
}

func (r *Rotozoom) Draw(fb *canvas.FB, y0, y1 int) {
	w := fb.W
	pix := fb.Pix
	cx := float32(w) * 0.5
	cy := float32(fb.H) * 0.5
	cosA, sinA := r.cosA, r.sinA
	zoom := r.zoom / float32(w) * 6.5
	offx, offy := r.offx, r.offy
	tex := r.tex

	for y := y0; y < y1; y++ {
		dy := float32(y) - cy
		row := y * w
		for x := 0; x < w; x++ {
			dx := float32(x) - cx
			tx := (dx*cosA - dy*sinA) * zoom * 34
			ty := (dx*sinA + dy*cosA) * zoom * 34
			ix := int(tx+offx) & texMask
			iy := int(ty+offy) & texMask
			pix[row+x] = tex[iy*texSize+ix]
		}
	}
}
