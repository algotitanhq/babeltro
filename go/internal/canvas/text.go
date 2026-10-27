package canvas

import "strings"

// A 5x7 bitmap font, written out as text so it stays readable in source.
// Each line is "CHAR row0 row1 ... row6", one character per pixel, MSB first.
// Everything the demo prints — HUD, scroller, titles — is drawn from these
// dots by the CPU, so the piece never touches a text-rendering library.
const fontSrc = `
SPACE 00000 00000 00000 00000 00000 00000 00000
! 00100 00100 00100 00100 00100 00000 00100
" 01010 01010 01010 00000 00000 00000 00000
# 01010 01010 11111 01010 11111 01010 01010
$ 00100 01111 10100 01110 00101 11110 00100
% 11001 11010 00010 00100 01000 01011 10011
& 01100 10010 10100 01000 10101 10010 01101
' 00100 00100 01000 00000 00000 00000 00000
( 00010 00100 01000 01000 01000 00100 00010
) 01000 00100 00010 00010 00010 00100 01000
* 00000 10101 01110 11111 01110 10101 00000
+ 00000 00100 00100 11111 00100 00100 00000
, 00000 00000 00000 00000 01100 01100 11000
- 00000 00000 00000 11111 00000 00000 00000
. 00000 00000 00000 00000 00000 01100 01100
/ 00001 00010 00010 00100 01000 01000 10000
0 01110 10001 10011 10101 11001 10001 01110
1 00100 01100 00100 00100 00100 00100 01110
2 01110 10001 00001 00110 01000 10000 11111
3 11111 00010 00100 00010 00001 10001 01110
4 00010 00110 01010 10010 11111 00010 00010
5 11111 10000 11110 00001 00001 10001 01110
6 00110 01000 10000 11110 10001 10001 01110
7 11111 00001 00010 00100 01000 01000 01000
8 01110 10001 10001 01110 10001 10001 01110
9 01110 10001 10001 01111 00001 00010 01100
: 00000 01100 01100 00000 01100 01100 00000
; 00000 01100 01100 00000 01100 00100 01000
< 00010 00100 01000 10000 01000 00100 00010
= 00000 00000 11111 00000 11111 00000 00000
> 01000 00100 00010 00001 00010 00100 01000
? 01110 10001 00001 00110 00100 00000 00100
@ 01110 10001 10111 10101 10111 10000 01110
A 01110 10001 10001 11111 10001 10001 10001
B 11110 10001 10001 11110 10001 10001 11110
C 01110 10001 10000 10000 10000 10001 01110
D 11110 10001 10001 10001 10001 10001 11110
E 11111 10000 10000 11110 10000 10000 11111
F 11111 10000 10000 11110 10000 10000 10000
G 01110 10001 10000 10111 10001 10001 01111
H 10001 10001 10001 11111 10001 10001 10001
I 11111 00100 00100 00100 00100 00100 11111
J 00111 00010 00010 00010 00010 10010 01100
K 10001 10010 10100 11000 10100 10010 10001
L 10000 10000 10000 10000 10000 10000 11111
M 10001 11011 10101 10101 10001 10001 10001
N 10001 11001 10101 10011 10001 10001 10001
O 01110 10001 10001 10001 10001 10001 01110
P 11110 10001 10001 11110 10000 10000 10000
Q 01110 10001 10001 10001 10101 10010 01101
R 11110 10001 10001 11110 10100 10010 10001
S 01111 10000 10000 01110 00001 00001 11110
T 11111 00100 00100 00100 00100 00100 00100
U 10001 10001 10001 10001 10001 10001 01110
V 10001 10001 10001 10001 10001 01010 00100
W 10001 10001 10001 10101 10101 10101 01010
X 10001 10001 01010 00100 01010 10001 10001
Y 10001 10001 01010 00100 00100 00100 00100
Z 11111 00001 00010 00100 01000 10000 11111
[ 01110 01000 01000 01000 01000 01000 01110
\ 10000 01000 01000 00100 00010 00010 00001
] 01110 00010 00010 00010 00010 00010 01110
^ 00100 01010 10001 00000 00000 00000 00000
_ 00000 00000 00000 00000 00000 00000 11111
{ 00110 00100 01000 01000 01000 00100 00110
| 00100 00100 00100 00100 00100 00100 00100
} 01100 00100 00010 00010 00010 00100 01100
~ 00000 00000 01000 10101 00010 00000 00000
`

// Glyph is one character's 7 rows of 5-bit pixels.
type Glyph [7]uint8

var (
	font      [95]Glyph
	fontWidth = 5
	fontGap   = 1
)

func init() {
	for _, line := range strings.Split(fontSrc, "\n") {
		fields := strings.Fields(line)
		if len(fields) != 8 {
			continue
		}
		var ch rune
		if fields[0] == "SPACE" {
			ch = ' '
		} else {
			ch = []rune(fields[0])[0]
		}
		idx := int(ch) - 32
		if idx < 0 || idx >= len(font) {
			continue
		}
		for r := 0; r < 7; r++ {
			var v uint8
			for c := 0; c < 5; c++ {
				if fields[r+1][c] == '1' {
					v |= 1 << (4 - c)
				}
			}
			font[idx][r] = v
		}
	}
}

// TextWidth returns the pixel width of s at the given integer scale.
func TextWidth(s string, scale int) int {
	if len(s) == 0 {
		return 0
	}
	return (len(s)*(fontWidth+fontGap) - fontGap) * scale
}

// TextHeight returns the pixel height of one line at the given scale.
func TextHeight(scale int) int { return 7 * scale }

// TextWidthN is TextWidth for a byte count, so callers formatting into a
// reusable buffer can measure without converting it to a string.
func TextWidthN(n int, scale int) int {
	if n <= 0 {
		return 0
	}
	return (n*(fontWidth+fontGap) - fontGap) * scale
}

// DrawText draws s with its top-left corner at (x, y). Colour is applied per
// pixel; pass an alpha < 255 for translucency.
func (fb *FB) DrawText(x, y int, s string, scale int, c uint32) {
	fb.DrawTextAlpha(x, y, s, scale, c, 255)
}

// DrawTextAlpha draws text blended against the framebuffer with a global
// alpha (0 = invisible, 255 = solid).
func (fb *FB) DrawTextAlpha(x, y int, s string, scale int, c uint32, alpha uint8) {
	if scale < 1 {
		scale = 1
	}
	ar := (c & 0xFF) * uint32(alpha) / 255
	ag := (c >> 8 & 0xFF) * uint32(alpha) / 255
	ab := (c >> 16 & 0xFF) * uint32(alpha) / 255

	cx := x
	for _, ch := range s {
		idx := int(ch) - 32
		if ch >= 'a' && ch <= 'z' {
			idx = int(ch-'a') + int('A') - 32
		}
		if idx < 0 || idx >= len(font) {
			cx += fontWidth * scale
			continue
		}
		g := &font[idx]
		for row := 0; row < 7; row++ {
			bits := g[row]
			if bits == 0 {
				continue
			}
			for col := 0; col < 5; col++ {
				if bits&(1<<(4-col)) == 0 {
					continue
				}
				px := cx + col*scale
				py := y + row*scale
				for sy := 0; sy < scale; sy++ {
					yy := py + sy
					if yy < 0 || yy >= fb.H {
						continue
					}
					base := yy * fb.W
					for sx := 0; sx < scale; sx++ {
						xx := px + sx
						if xx < 0 || xx >= fb.W {
							continue
						}
						i := base + xx
						if alpha == 255 {
							fb.Pix[i] = c
						} else {
							fb.blend(i, ar, ag, ab)
						}
					}
				}
			}
		}
		cx += (fontWidth + fontGap) * scale
	}
}

func (fb *FB) blend(i int, r, g, b uint32) {
	p := fb.Pix[i]
	pr := p & 0xFF
	pg := p >> 8 & 0xFF
	pb := p >> 16 & 0xFF
	// add-with-saturation gives text a light, luminous feel over dark art.
	nr := pr + r
	ng := pg + g
	nb := pb + b
	if nr > 255 {
		nr = 255
	}
	if ng > 255 {
		ng = 255
	}
	if nb > 255 {
		nb = 255
	}
	fb.Pix[i] = 0xFF000000 | nb<<16 | ng<<8 | nr
}
