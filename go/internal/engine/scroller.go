package engine

import (
	"math"

	"babeltro/internal/canvas"
)

// Scroller is the sine-wave text banner that runs along the bottom. It exists
// because a demo without a scroller is not a demo.
type Scroller struct {
	Text  string
	Scale int
	Speed float64 // pixels per second, in reference units
	YFrac float64 // vertical position, fraction of the screen height
	Bold  bool
}

// refH is the height the scroller is designed at. At a Retina 720p window
// the framebuffer is 1440 lines, so the banner and its bob are doubled to
// keep the same apparent size.
const refH = 720

func NewScroller(text string) *Scroller {
	// YFrac is the banner's top row, so it has to leave a full text height
	// below itself: 0.93 at scale 4 put the glyphs' last row on the frame edge.
	return &Scroller{Text: text, Scale: 4, Speed: 190, YFrac: 0.90}
}

// Draw advances the banner by time t and paints it with the given alpha.
func (s *Scroller) Draw(fb *canvas.FB, t float64, alpha uint8) {
	if alpha == 0 {
		return
	}
	// proportional to the framebuffer, rounded: integer division would leave
	// a 1080-line screen at 720p size
	f := float64(fb.H) / refH
	if f < 1 {
		f = 1
	}
	sc := int(f + 0.5)
	scale := s.Scale * sc
	adv := 6 * scale
	w := fb.W
	textW := canvas.TextWidth(s.Text, scale)
	total := float64(textW + w)

	shift := int(math.Mod(t*s.Speed*float64(sc), total))
	baseX := w - shift
	bob := 10.0 * float64(sc)

	for i, ch := range s.Text {
		x := baseX + i*adv
		if x > w || x+adv < 0 {
			continue
		}
		// each glyph bobs on a slow sine, giving the line its wave
		phase := float64(i)*0.32 + t*2.2
		y := int(float64(fb.H)*s.YFrac + bob*math.Sin(phase))
		c := waveColour(i, t)
		glyph := string(ch)
		fb.DrawTextAlpha(x, y+sc, glyph, scale, 0x000000, uint8(int(alpha)*2/5))
		fb.DrawTextAlpha(x, y, glyph, scale, c, alpha)
	}
}

// waveColour cycles the scroller through cyan and amber so it reads as one
// moving object rather than a wall of text.
func waveColour(i int, t float64) uint32 {
	if math.Sin(float64(i)*0.25+t*1.5) > 0 {
		return canvas.RGB(0x9A, 0xEC, 0xFF)
	}
	return canvas.RGB(0xFF, 0xD5, 0x7A)
}
