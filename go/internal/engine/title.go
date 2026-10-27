package engine

import (
	"strconv"

	"rosette/internal/canvas"
	"rosette/internal/hud"
)

// drawSceneTitle puts the scene name on screen for the first few seconds,
// centred, with a hard shadow so it survives whatever is behind it. The
// scale follows the framebuffer height, so the title keeps its weight on a
// Retina screen instead of shrinking to a third of the frame width.
func drawSceneTitle(fb *canvas.FB, name string, idx, n int, a float64) {
	// proportional to the framebuffer, rounded: 5 at 720 lines, 8 at 1080,
	// 10 at 1440 — integer division would leave 1080p at 720p size
	f := float64(fb.H) / 720
	if f < 1 {
		f = 1
	}
	sc := int(f + 0.5)
	scale := 5 * sc
	if fb.W < 1000*sc {
		scale = 3 * sc
	}
	// keep a long name inside the frame
	for scale > sc && canvas.TextWidth(name, scale) > fb.W*9/10 {
		scale -= sc
	}
	tw := canvas.TextWidth(name, scale)
	x := (fb.W - tw) / 2
	y := fb.H/2 - canvas.TextHeight(scale)
	// On a small window the HUD panel can reach past the centre of the frame
	// and swallow the title. Centring is right whenever it is visible; when it
	// is not, drop it into the clear band below the panel.
	if need := hud.PanelBottom(fb.W, fb.H) + canvas.TextHeight(scale); y < need {
		y = need
	}

	al := uint8(a * 255)
	if al > 255 {
		al = 255
	}
	white := canvas.RGB(0xF2, 0xF8, 0xFF)
	accent := canvas.RGB(0x6E, 0xE2, 0xFF)

	fb.DrawTextAlpha(x+2*sc, y+3*sc, name, scale, 0x000000, uint8(a*180))
	fb.DrawTextAlpha(x, y, name, scale, white, al)

	// "SCENE 03 / 08" under the title
	var buf [16]byte
	b := buf[:0]
	b = append(b, "SCENE "...)
	if idx+1 < 10 {
		b = append(b, '0')
	}
	b = strconv.AppendInt(b, int64(idx+1), 10)
	b = append(b, '/')
	if n < 10 {
		b = append(b, '0')
	}
	b = strconv.AppendInt(b, int64(n), 10)

	hs := sc
	hy := y + canvas.TextHeight(scale) + 10*sc
	bw := canvas.TextWidthN(len(b), hs)
	bx := (fb.W - bw) / 2
	txt := string(b)
	fb.DrawTextAlpha(bx, hy, txt, hs, canvas.RGB(0x00, 0x00, 0x00), uint8(a*160))
	fb.DrawTextAlpha(bx, hy-sc, txt, hs, accent, uint8(a*220))
}
