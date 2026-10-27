package canvas

// clipBlock returns the visible part of a scale×scale glyph block at (px, py)
// as a row range and a half-open column range. Clipping once per block and
// then writing straight runs is much cheaper than testing bounds per pixel.
func (fb *FB) clipBlock(px, py, scale int) (y0, y1, x0, x1 int, ok bool) {
	y0, y1 = py, py+scale
	if y0 < 0 {
		y0 = 0
	}
	if y1 > fb.H {
		y1 = fb.H
	}
	x0, x1 = px, px+scale
	if x0 < 0 {
		x0 = 0
	}
	if x1 > fb.W {
		x1 = fb.W
	}
	return y0, y1, x0, x1, y0 < y1 && x0 < x1
}

// DrawTextGradient draws s with a three-stop vertical colour ramp (top, mid,
// bottom) which is how the finale logo gets its chrome look. Each glyph is
// placed at its own baseline offset from offs (one entry per rune, or nil for
// none), so callers can wave the letters without giving up the gradient.
// With scan set, every third row is darkened: the CRT look, and it also hides
// the banding you get from a seven-row glyph at large scales.
func (fb *FB) DrawTextGradient(x, y int, s string, scale int, top, mid, bottom uint32, offs []int, scan bool) {
	if scale < 1 {
		scale = 1
	}
	tr, tg, tb := top&0xFF, top>>8&0xFF, top>>16&0xFF
	mr, mg, mb := mid&0xFF, mid>>8&0xFF, mid>>16&0xFF
	br, bg, bb := bottom&0xFF, bottom>>8&0xFF, bottom>>16&0xFF
	totalH := 7 * scale

	pix := fb.Pix
	cx := x
	i := 0
	for _, ch := range s {
		dy := 0
		if i < len(offs) {
			dy = offs[i]
		}
		if idx := glyphIndex(ch); idx >= 0 {
			g := &font[idx]
			for row := 0; row < 7; row++ {
				bits := g[row]
				if bits == 0 {
					continue
				}
				py := y + row*scale + dy
				for col := 0; col < 5; col++ {
					if bits&(1<<(4-col)) == 0 {
						continue
					}
					px := cx + col*scale
					cy0, cy1, cx0, cx1, ok := fb.clipBlock(px, py, scale)
					if !ok {
						continue
					}
					for yy := cy0; yy < cy1; yy++ {
						f := float32(yy-y) / float32(totalH)
						if f < 0 {
							f = 0
						} else if f > 1 {
							f = 1
						}
						var r, gg, bl uint32
						if f < 0.5 {
							u := f * 2
							r = uint32(float32(tr) + (float32(mr)-float32(tr))*u)
							gg = uint32(float32(tg) + (float32(mg)-float32(tg))*u)
							bl = uint32(float32(tb) + (float32(mb)-float32(tb))*u)
						} else {
							u := (f - 0.5) * 2
							r = uint32(float32(mr) + (float32(br)-float32(mr))*u)
							gg = uint32(float32(mg) + (float32(bg)-float32(mg))*u)
							bl = uint32(float32(mb) + (float32(bb)-float32(mb))*u)
						}
						if scan && yy&3 == 0 {
							r = r * 3 / 4
							gg = gg * 3 / 4
							bl = bl * 3 / 4
						}
						c := 0xFF000000 | bl<<16 | gg<<8 | r
						base := yy * fb.W
						for xx := cx0; xx < cx1; xx++ {
							pix[base+xx] = c
						}
					}
				}
			}
		}
		cx += (fontWidth + fontGap) * scale
		i++
	}
}

// DrawTextOutline draws s offset by one pixel in the four cardinal directions
// in the given colour, producing a hard edge. Used to keep the logo readable
// over a busy background.
func (fb *FB) DrawTextOutline(x, y int, s string, scale int, c uint32) {
	for _, d := range [4][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}} {
		fb.DrawText(x+d[0], y+d[1], s, scale, c)
	}
}

// DrawTextReflect draws a vertically mirrored copy of s starting at y, which
// is meant to be the line the reflection sits on. The copy fades out over
// depth rows from that line and is added to the framebuffer rather than drawn
// over it, so it looks like light on a polished floor. A depth shorter than
// the glyph height cuts the reflection off where it has faded.
func (fb *FB) DrawTextReflect(x, y int, s string, scale int, top, bottom uint32, offs []int, strength uint8, depth int) {
	if scale < 1 {
		scale = 1
	}
	if depth < 1 {
		depth = 1
	}
	tr, tg, tb := top&0xFF, top>>8&0xFF, top>>16&0xFF
	br, bg, bb := bottom&0xFF, bottom>>8&0xFF, bottom>>16&0xFF

	cx := x
	i := 0
	for _, ch := range s {
		dy := 0
		if i < len(offs) {
			dy = offs[i]
		}
		if idx := glyphIndex(ch); idx >= 0 {
			g := &font[idx]
			for row := 0; row < 7; row++ {
				bits := g[row]
				if bits == 0 {
					continue
				}
				// mirrored: glyph row 0 sits at the far end
				py := y + (6-row)*scale + dy
				for col := 0; col < 5; col++ {
					if bits&(1<<(4-col)) == 0 {
						continue
					}
					px := cx + col*scale
					cy0, cy1, cx0, cx1, ok := fb.clipBlock(px, py, scale)
					if !ok {
						continue
					}
					for yy := cy0; yy < cy1; yy++ {
						d := float32(yy-y) / float32(depth)
						if d > 1 {
							continue
						}
						a := 1 - d
						a *= a
						inten := uint8(float32(strength) * a)
						if inten == 0 {
							continue
						}
						f := d
						r := uint32(float32(tr) + (float32(br)-float32(tr))*f)
						gg := uint32(float32(tg) + (float32(bg)-float32(tg))*f)
						bl := uint32(float32(tb) + (float32(bb)-float32(tb))*f)
						c := 0xFF000000 | bl<<16 | gg<<8 | r
						base := yy * fb.W
						for xx := cx0; xx < cx1; xx++ {
							fb.Additive(base+xx, c, inten)
						}
					}
				}
			}
		}
		cx += (fontWidth + fontGap) * scale
		i++
	}
}

// glyphIndex maps a rune to the font table, folding lowercase to uppercase.
func glyphIndex(ch rune) int {
	if ch >= 'a' && ch <= 'z' {
		ch = ch - 'a' + 'A'
	}
	idx := int(ch) - 32
	if idx < 0 || idx >= len(font) {
		return -1
	}
	return idx
}
