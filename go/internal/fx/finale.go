package fx

import (
	"math"

	"babeltro/internal/brand"
	"babeltro/internal/canvas"
	"babeltro/internal/fmath"
	"babeltro/internal/hud"
)

// PanelBottom reports the last row the HUD panel covers, so the finale can
// compose below it. A host that draws no HUD in the frame (the browser lab)
// sets it to nil and the card uses the whole height.
var PanelBottom = hud.PanelBottom

// FinaleTag is the punchline under the closing numbers. The native demo
// boasts about its workers; the browser lab runs on one thread, so it says
// that instead, in words that are the same in every port.
var FinaleTag = "60 FPS - ONE CPU - 8 " + brand.Workers

// starBg is a fixed background star in normalised coordinates; the finale
// only needs twinkle, not motion.
type starBg struct {
	x, y, b float32
}

// Finale is the closing card: the logo, its reflection, the subtitle and the
// numbers that make the point. It draws on the calling goroutine (Parallel is
// false) because the text pass must not race with the background pass over the
// same pixels.
type Finale struct {
	w, h int

	t float64

	stars []starBg

	logoScale int
	logoX     int
	logoY     int
	logoW     int
	textH     int
	reflH     int // rows the reflection fades over, below the floor line

	floorY int

	sub      string
	subScale int
	subX     int
	subY     int

	statsScale int
	statsY     int
	statGap    int

	tag      string
	tagScale int
	tagX     int
	tagY     int

	lines [3]string
	offs  []int // per-letter wave offsets, reused so a frame allocates nothing

	glowX, glowY, glowR float32
	// per-column squared distance to the glow centre, in glow radii, and the
	// rectangle the glow can possibly reach
	dx2          []float32
	boxX0, boxX1 int
	boxY0, boxY1 int
}

func NewFinale() *Finale {
	f := &Finale{offs: make([]int, len(brand.Lang))}
	f.lines = [3]string{"0 GPU SHADERS", "0 EXTERNAL MODULES", "0 ASSETS ON DISK"}
	return f
}

func (f *Finale) Name() string   { return "FINALE" }
func (f *Finale) Parallel() bool { return false }

func (f *Finale) Resize(w, h int) {
	if w == f.w && h == f.h {
		return
	}
	f.w, f.h = w, h

	if f.stars == nil {
		rng := fmath.Rng(0xF1A1E)
		f.stars = make([]starBg, 260)
		for i := range f.stars {
			f.stars[i] = starBg{
				x: rng.Float32(),
				y: rng.Float32(),
				b: 0.15 + rng.Float32()*0.85,
			}
		}
	}

	f.sub = "EVERY PIXEL IS " + brand.Lang
	f.subScale = w / 300
	if f.subScale < 1 {
		f.subScale = 1
	}
	subH := canvas.TextHeight(f.subScale)

	f.statsScale = w / 440
	if f.statsScale < 1 {
		f.statsScale = 1
	}
	f.statGap = canvas.TextHeight(f.statsScale) * 3 / 2

	f.tag = FinaleTag
	f.tagScale = f.statsScale + 1
	tagH := canvas.TextHeight(f.tagScale)

	// The HUD panel owns the top-left corner and is taller than any fixed
	// fraction of the frame; a scene that guesses where it ends clips under it.
	// hud.PanelBottom reports the row it actually reaches, so the card composes
	// in the band below it and sizes the wordmark to the room that is left.
	gap := h / 48
	top := h / 40
	if PanelBottom != nil {
		top += PanelBottom(w, h)
	}
	bottom := int(float32(h) * 0.90)
	fixed := subH + 3*f.statGap + tagH + 4*gap // everything but the wordmark
	// The wordmark is the language's name, from "C" to "JAVASCRIPT", so its
	// scale comes from the room it has rather than from its length. Height:
	// the glyph is 7 blocks and its reflection fades over half of that, so
	// the wordmark needs 10.5 blocks. Width: never more than 45% of the frame,
	// which only binds for long names.
	f.logoScale = (bottom - top - fixed) * 2 / 21
	if lim := w * 9 / 20 / canvas.TextWidth(brand.Lang, 1); f.logoScale > lim {
		f.logoScale = lim
	}
	if f.logoScale < 3 {
		f.logoScale = 3
	}
	f.logoW = canvas.TextWidth(brand.Lang, f.logoScale)
	f.textH = canvas.TextHeight(f.logoScale)
	f.reflH = f.textH / 2
	f.logoX = (w - f.logoW) / 2

	blockH := f.textH + f.reflH + fixed
	y0 := top + (bottom-top-blockH)/2

	f.logoY = y0
	f.floorY = f.logoY + f.textH
	f.subY = f.floorY + f.reflH + gap
	f.statsY = f.subY + subH + gap
	f.tagY = f.statsY + 3*f.statGap + gap
	f.subX = (w - canvas.TextWidth(f.sub, f.subScale)) / 2
	f.tagX = (w - canvas.TextWidth(f.tag, f.tagScale)) / 2

	f.glowX = float32(w) * 0.5
	f.glowY = float32(f.logoY) + float32(f.textH)*0.55
	f.glowR = float32(w) * 0.34

	// the glow is an ellipse about 1.6x wider than it is tall
	if cap(f.dx2) < w {
		f.dx2 = make([]float32, w)
	} else {
		f.dx2 = f.dx2[:w]
	}
	for x := range f.dx2 {
		d := (float32(x) - f.glowX) / f.glowR * 1.6
		f.dx2[x] = d * d
	}
	spanX := int(f.glowR / 1.6)
	spanY := int(f.glowR)
	f.boxX0 = int(f.glowX) - spanX
	f.boxX1 = int(f.glowX) + spanX
	f.boxY0 = int(f.glowY) - spanY
	f.boxY1 = int(f.glowY) + spanY
}

func (f *Finale) Prepare(s State, w, h int) {
	if w != f.w || h != f.h {
		f.Resize(w, h)
	}
	f.t = s.T
}

func (f *Finale) Draw(fb *canvas.FB, y0, y1 int) {
	w, h := fb.W, fb.H
	pix := fb.Pix

	cx := float32(w) * 0.5
	cy := float32(h) * 0.5

	// --- background, pass 1: a plain vertical ramp, one colour per row ---
	invH := 1 / float32(h)
	for y := y0; y < y1; y++ {
		u := float32(y) * invH
		ny := (float32(y) - cy) / cy
		vig := 1 - 0.32*ny*ny
		if vig < 0.45 {
			vig = 0.45
		}
		r := (0.02 + 0.09*u*u) * vig
		g := (0.01 + 0.02*u) * vig
		b := (0.06 + 0.14*u) * vig
		c := canvas.FromFloat(float64(r), float64(g), float64(b))
		row := pix[y*w : (y+1)*w]
		for i := range row {
			row[i] = c
		}
	}

	// --- background, pass 2: the pool of light, only where it reaches ---
	by0, by1 := f.boxY0, f.boxY1
	if by0 < y0 {
		by0 = y0
	}
	if by1 > y1 {
		by1 = y1
	}
	bx0, bx1 := f.boxX0, f.boxX1
	if bx0 < 0 {
		bx0 = 0
	}
	if bx1 > w {
		bx1 = w
	}
	pulse := 0.88 + 0.12*float32(math.Sin(f.t*2.2))
	for y := by0; y < by1; y++ {
		dy := (float32(y) - f.glowY) / f.glowR
		dy2 := dy * dy
		if dy2 >= 1 {
			continue
		}
		row := y * w
		for x := bx0; x < bx1; x++ {
			d2 := f.dx2[x] + dy2
			if d2 >= 1 {
				continue
			}
			g := 1 - d2
			g *= g * pulse

			p := pix[row+x]
			r := int32(p&0xFF) + int32(g*120)
			gg := int32(p>>8&0xFF) + int32(g*22)
			b := int32(p>>16&0xFF) + int32(g*100)
			if r > 255 {
				r = 255
			}
			if gg > 255 {
				gg = 255
			}
			if b > 255 {
				b = 255
			}
			pix[row+x] = 0xFF000000 | uint32(b)<<16 | uint32(gg)<<8 | uint32(r)
		}
	}

	// stars, twinkling slowly
	for i := range f.stars {
		s := &f.stars[i]
		sx := int(s.x * float32(w))
		sy := int(s.y * float32(h))
		if sy < y0 || sy >= y1 || sx < 0 || sx >= w {
			continue
		}
		tw := 0.55 + 0.45*float32(math.Sin(f.t*1.7+float64(i)*0.7))
		fb.Additive(sy*w+sx, 0xFF40306A, uint8(70*s.b*tw))
	}

	// --- the polished floor line the reflection lands on ---
	if f.floorY >= y0 && f.floorY < y1 {
		base := f.floorY * w
		for x := 0; x < w; x++ {
			d := float32(x) - cx
			fade := 1 - float32(math.Abs(float64(d)))/(float32(w)*0.52)
			if fade <= 0 {
				continue
			}
			glow := fade * fade * 0.9
			p := fb.Pix[base+x]
			r := float32(p&0xFF) + 210*glow
			g := float32(p>>8&0xFF) + 110*glow
			b := float32(p>>16&0xFF) + 230*glow
			if r > 255 {
				r = 255
			}
			if g > 255 {
				g = 255
			}
			if b > 255 {
				b = 255
			}
			fb.Pix[base+x] = 0xFF000000 | uint32(b)<<16 | uint32(g)<<8 | uint32(r)
		}
	}

	// --- logo ---
	scale := f.logoScale
	offs := f.offs
	// the letters bounce off the floor line: offsets run from -scale/3 (up)
	// to 0 (resting on it), never below, so no letter sinks into its own
	// reflection
	for i := range offs {
		offs[i] = int((math.Sin(f.t*2.4+float64(i)*0.75) - 1) * float64(scale) / 6)
	}

	const (
		topCol = uint32(0xFFFFF6E8) // pale cream
		midCol = uint32(0xFF7C9CFF) // hot rose
		botCol = uint32(0xFF582080) // deep violet
	)

	// reflection first, so the wordmark sits on top of its own light
	fb.DrawTextReflect(f.logoX, f.floorY, brand.Lang, scale, topCol, botCol, offs, 125, f.reflH)

	// a one-pixel dark edge keeps the letters off the background
	fb.DrawTextOutline(f.logoX, f.logoY, brand.Lang, scale, 0xFF200A18, offs)
	fb.DrawTextGradient(f.logoX, f.logoY, brand.Lang, scale, topCol, midCol, botCol, offs, true)

	// --- subtitle with rules either side ---
	subW := canvas.TextWidth(f.sub, f.subScale)
	lineLen := subW / 3
	ly := f.subY + canvas.TextHeight(f.subScale)/2
	fb.HLine(f.subX-lineLen-14, ly, lineLen, 0xFF9050A0)
	fb.HLine(f.subX+subW+14, ly, lineLen, 0xFF9050A0)
	fb.DrawText(f.subX, f.subY, f.sub, f.subScale, 0xFFF0E0FF)

	// --- closing numbers ---
	for i, l := range f.lines {
		y := f.statsY + i*f.statGap
		lw := canvas.TextWidth(l, f.statsScale)
		fb.DrawText((w-lw)/2, y, l, f.statsScale, 0xFFC0B0E0)
	}

	// the punchline
	fb.DrawText(f.tagX, f.tagY, f.tag, f.tagScale, 0xFFB0E0FF)
}
