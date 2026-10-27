// Package hud draws the on-screen instrumentation. It is the other half of
// the piece: the effects are the show, and this panel is the argument — every
// number here is measured live, not typed in.
//
// The layout is written against a 720-line screen and scaled to the
// framebuffer. On a Retina Mac a 1280x720 window is a 2560x1440 framebuffer,
// so a HUD drawn at one fixed font scale would come out half the intended
// physical size — unreadable from a sofa. The font is drawn at an integer
// scale that follows the framebuffer height, and every geometry length below
// is a reference unit multiplied by the same fractional factor.
package hud

import (
	"strconv"
	"unsafe"

	"babeltro/internal/brand"
	"babeltro/internal/canvas"
)

var (
	cyan  = canvas.RGB(0x6E, 0xE2, 0xFF)
	white = canvas.RGB(0xE8, 0xF4, 0xFF)
	dim   = canvas.RGB(0x6C, 0x84, 0x99)
	green = canvas.RGB(0x5C, 0xF2, 0x9A)
	amber = canvas.RGB(0xFF, 0xC2, 0x4A)
	red   = canvas.RGB(0xFF, 0x5C, 0x5C)
	panel = canvas.RGB(0x05, 0x08, 0x0C)
)

// Stats is one frame's worth of measurements, filled by the engine.
type Stats struct {
	FPS        float64
	FrameMS    float64
	CPUMs      float64
	BudgetMS   float64
	Pixels     float64
	Mpxs       float64
	Workers    int
	AllocBytes uint64
	Allocs     uint64
	GCRuns     uint32
	Scene      string
	SceneIndex int
	SceneCount int
	SceneTime  float64
	SceneDur   float64
}

// Layout, in reference units at a 720-line screen. Only the parts that are
// genuinely a matter of taste are fixed here; every width that has to hold
// text is measured from the font at draw time, because the font is drawn at an
// integer scale while the panel scales fractionally — at 1080 lines a fixed
// column width collides with the text it was meant to hold.
const (
	refH     = 720
	textBase = 3  // font scale at 720 lines: 2x felt small on a Retina screen
	pad      = 14 // inner margin, in reference units
	graphH   = 52 // frame-time graph height, reference units
	// histCap bounds the frame-time history. The graph spends one sample per
	// pixel of its width, so this must exceed the widest panel a display can
	// ask for; it is clamped at draw time.
	histCap = 2048
	// maxLineChars is the character count of the widest line the panel draws
	// ("8 WORKERS   8739 B/FRAME   0 ALLOCS"), used to bound the font scale by
	// the frame width.
	maxLineChars = 31
)

// HUD keeps the rolling history for the frame-time graph.
type HUD struct {
	scratch [512]byte
	hist    [histCap]float64
	histPos int
	Visible bool

	// f scales every reference dimension to the framebuffer height. It is
	// fractional on purpose: an integer factor would leave the panel at 720p
	// size on a 1080-line screen.
	f  float64
	ts int // font scale
}

func New() *HUD { return &HUD{Visible: true} }

// scaleFor returns the factor that keeps the HUD at its designed proportion
// of the screen.
func scaleFor(h int) float64 {
	f := float64(h) / refH
	if f < 1 {
		f = 1
	}
	return f
}

// px converts a reference length to framebuffer pixels.
func (h *HUD) px(v float64) int { return int(v*h.f + 0.5) }

// panelGeom returns the metrics that define the panel's extent, from the
// framebuffer size alone. Draw and PanelBottom both go through it, so the
// number a scene composes against is by construction the number drawn.
//
// The font only exists in integer scales, so it is chosen from two bounds: the
// framebuffer height (that is what makes the panel readable on Retina) and the
// framebuffer width, because on a narrow window a height-derived scale makes a
// panel that eats most of the frame.
func panelGeom(fbW, fbH int) (ts, textH, lineGap, padPx, barH, gh, hintGap, ph int) {
	f := scaleFor(fbH)
	h := &HUD{f: f}

	ts = h.px(textBase)
	if wCap := canvas.TextWidthN(maxLineChars, 1); wCap > 0 {
		// the panel may take 62% of the frame width at most
		if lim := fbW * 62 / 100 / wCap; lim < ts {
			ts = lim
		}
	}
	if ts < 1 {
		ts = 1
	}

	textH = canvas.TextHeight(ts)
	lineGap = h.px(5)
	if lineGap < 3 {
		lineGap = 3
	}
	padPx = h.px(pad)
	barH = h.px(6)
	if barH < 3 {
		barH = 3
	}
	gh = h.px(graphH)
	hintGap = h.px(7)
	ph = padPx*2 + 6*textH + 5*lineGap + h.px(11) + barH + h.px(4) + gh + hintGap + textH
	return
}

// PanelBottom returns the last row occupied by the panel, whether or not the
// HUD is visible. Scenes that compose around the panel need the real number:
// the panel is taller than a fixed fraction of the frame, and a scene that
// guesses clips under it.
func PanelBottom(fbW, fbH int) int {
	h := &HUD{f: scaleFor(fbH)}
	_, _, _, _, _, _, _, ph := panelGeom(fbW, fbH)
	return h.px(16) + ph
}

func (h *HUD) text(fb *canvas.FB, x, y int, s string, c uint32) {
	fb.DrawText(x, y, s, h.ts, c)
}

func (h *HUD) textB(fb *canvas.FB, x, y int, b []byte, c uint32) {
	if len(b) == 0 {
		return
	}
	fb.DrawText(x, y, unsafe.String(&b[0], len(b)), h.ts, c)
}

// rightB draws b right-aligned inside a column ending at xRight.
func (h *HUD) rightB(fb *canvas.FB, xRight, y int, b []byte, c uint32) {
	h.textB(fb, xRight-canvas.TextWidthN(len(b), h.ts), y, b, c)
}

func (h *HUD) right(fb *canvas.FB, xRight, y int, s string, c uint32) {
	h.text(fb, xRight-canvas.TextWidth(s, h.ts), y, s, c)
}

// Draw lays the panel out. Everything is drawn with the demo's own bitmap
// font, so the instrumentation costs the same as any other effect.
//
// The lines are built before anything is drawn, because the panel is sized to
// its content. The font only exists in integer scales while the panel follows
// the framebuffer fractionally, so a fixed panel width that is comfortable at
// 720 lines runs out of room at 1080 — text then overlaps its neighbour. Sizing
// from the measured lines removes that whole class of bug.
func (h *HUD) Draw(fb *canvas.FB, s Stats) {
	h.hist[h.histPos%histCap] = s.CPUMs
	h.histPos++

	if !h.Visible {
		return
	}

	h.f = scaleFor(fb.H)
	// the font scale follows the frame height, capped by the frame width
	ts, textH, lineGap, padPx, barH, gh, hintGap, ph := panelGeom(fb.W, fb.H)
	h.ts = ts
	linePx := textH + lineGap
	tw := func(str string) int { return canvas.TextWidth(str, h.ts) }
	bw := func(b []byte) int { return canvas.TextWidthN(len(b), h.ts) }
	// minimum breathing room before a right-aligned value
	gap := tw("  ")
	lblW := tw("SCENE  ") // label column: the longest label plus a gap

	// --- build every line first ---------------------------------------------
	var bufs [5][128]byte

	fps := append(bufs[0][:0], "FPS "...)
	fps = strconv.AppendFloat(fps, s.FPS, 'f', 1, 64)
	fps = append(fps, "   FRAME "...)
	fps = strconv.AppendFloat(fps, s.FrameMS, 'f', 2, 64)
	fps = append(fps, " MS"...)

	cpu := append(bufs[1][:0], "CPU "...)
	cpu = strconv.AppendFloat(cpu, s.CPUMs, 'f', 2, 64)
	cpu = append(cpu, " MS   BUDGET "...)
	cpu = strconv.AppendFloat(cpu, s.BudgetMS, 'f', 2, 64)

	head := s.BudgetMS / maxf(s.CPUMs, 0.001)
	headB := append(bufs[2][:0], ' ')
	headB = strconv.AppendFloat(headB, head, 'f', 1, 64)
	headB = append(headB, 'X')

	col := green
	if head < 2 {
		col = red
	} else if head < 4 {
		col = amber
	}

	pix := bufs[3][:0]
	pix = strconv.AppendFloat(pix, s.Pixels/1000, 'f', 1, 64)
	pix = append(pix, " KPX  ->  "...)
	pix = strconv.AppendFloat(pix, s.Mpxs, 'f', 0, 64)
	pix = append(pix, " MPIX/S"...)

	work := bufs[4][:0]
	work = strconv.AppendInt(work, int64(s.Workers), 10)
	work = append(work, " WORKERS   "...)
	work = strconv.AppendUint(work, s.AllocBytes, 10)
	work = append(work, " B/FRAME   "...)
	work = strconv.AppendUint(work, s.Allocs, 10)
	work = append(work, " ALLOCS"...)

	timeB := h.scratch[:0]
	timeB = strconv.AppendInt(timeB, int64(s.SceneIndex+1), 10)
	timeB = append(timeB, '/')
	timeB = strconv.AppendInt(timeB, int64(s.SceneCount), 10)
	timeB = append(timeB, "  "...)
	timeB = strconv.AppendFloat(timeB, s.SceneTime, 'f', 1, 64)
	timeB = append(timeB, 's')

	const (
		title = brand.Project
		sub   = "// SOFTWARE RENDERER"
		mark  = "PURE " + brand.Lang
		hint  = "ESC QUIT  H HUD  S NEXT  F FULL"
	)

	// --- size the panel to the widest line ----------------------------------
	need := tw(title) + tw(" ") + tw(sub) + gap + tw(mark)
	need = maxi(need, lblW+tw(s.Scene)+gap+bw(timeB))
	need = maxi(need, bw(fps))
	need = maxi(need, bw(cpu)+gap+bw(headB))
	need = maxi(need, bw(pix))
	need = maxi(need, bw(work))
	need = maxi(need, tw(hint))
	mw := need

	gapG := h.px(11)
	pw := mw + padPx*2

	x0 := h.px(18)
	y0 := h.px(16)
	x := x0 + padPx
	y := y0 + padPx
	xr := x0 + pw - padPx

	fb.FillRect(x0, y0, pw, ph, panel, 200)
	fb.FillRect(x0, y0, pw, h.px(1), cyan, 90)
	fb.FillRect(x0, y0+ph-h.px(1), pw, h.px(1), cyan, 45)

	h.text(fb, x, y, title, cyan)
	h.text(fb, x+tw(title+" "), y, sub, dim)
	h.right(fb, xr, y, mark, dim)

	y += linePx
	h.text(fb, x, y, "SCENE", dim)
	h.text(fb, x+lblW, y, s.Scene, white)
	h.rightB(fb, xr, y, timeB, dim)

	y += linePx
	h.textB(fb, x, y, fps, white)

	y += linePx
	h.textB(fb, x, y, cpu, white)
	h.rightB(fb, xr, y, headB[1:], col)

	y += linePx
	h.textB(fb, x, y, pix, cyan)

	y += linePx
	h.textB(fb, x, y, work, dim)

	y += textH + gapG
	fb.FillRect(x, y, mw, barH, canvas.RGB(0x12, 0x1A, 0x22), 255)
	frac := s.CPUMs / maxf(s.BudgetMS, 0.001)
	if frac > 1 {
		frac = 1
	}
	if frac < 0 {
		frac = 0
	}
	c := green
	switch {
	case frac > 0.75:
		c = red
	case frac > 0.5:
		c = amber
	}
	fb.FillRect(x, y, int(frac*float64(mw)), barH, c, 255)
	fb.FillRect(x+mw-h.px(1), y, h.px(1), barH, red, 255)

	y += barH + h.px(4)
	fb.FillRect(x, y, mw, gh, canvas.RGB(0x08, 0x0D, 0x12), 220)
	scaleMax := maxf(s.BudgetMS, 0.001)
	// one sample per pixel column: the graph is as wide as the panel, so its
	// resolution follows the framebuffer instead of a fixed sample count
	start := h.histPos - mw
	if start < 0 {
		start = 0
	}
	for i := 0; i < mw; i++ {
		idx := start + i
		if idx < 0 {
			continue
		}
		v := h.hist[idx%histCap]
		if v > scaleMax {
			v = scaleMax
		}
		bh := int(v / scaleMax * float64(gh-1))
		if bh <= 0 {
			continue
		}
		cc := green
		if v > s.BudgetMS*0.75 {
			cc = red
		} else if v > s.BudgetMS*0.5 {
			cc = amber
		}
		fb.FillRect(x+i, y+gh-bh, h.px(1), bh, cc, 255)
	}
	fb.HLine(x, y, mw, canvas.RGB(0x4A, 0x1E, 0x1E))

	h.text(fb, x, y+gh+hintGap, hint, canvas.RGB(0x3E, 0x4E, 0x5C))
}

func maxf(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func maxi(a, b int) int {
	if a > b {
		return a
	}
	return b
}
