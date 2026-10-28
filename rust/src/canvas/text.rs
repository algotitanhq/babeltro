//! A 5×7 bitmap font and the text routines the finale draws with. Everything
//! the demo prints is drawn from these dots by the CPU: no text-rendering
//! library anywhere.

use std::ops::Range;

use super::{Frame, channels, pack};

/// The font, written out as text so it stays readable in source. Each line
/// is "CHAR row0 row1 ... row6", one character per pixel, MSB first.
const FONT_SRC: &str = r##"
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
"##;

/// One character's 7 rows of 5-bit pixels.
type Glyph = [u8; 7];

const FONT_W: i32 = 5;
const FONT_GAP: i32 = 1;
const ADVANCE: i32 = FONT_W + FONT_GAP;

/// Printable ASCII, from ' ' to '~'. A `const fn` parses `FONT_SRC` while
/// the crate compiles, so the module ships the finished bitmaps and does no
/// work at start-up (Go parses the same text in an `init` function).
static FONT: [Glyph; 95] = parse_font(FONT_SRC);

const fn parse_font(src: &str) -> [Glyph; 95] {
    let b = src.as_bytes();
    let mut font = [[0; 7]; 95];
    let mut i = 0;
    // `for` and iterators are not available in const fn yet: plain loops
    while i < b.len() {
        // split one line into up to 8 space-separated fields
        let mut start = [0; 8];
        let mut n = 0;
        while i < b.len() && b[i] != b'\n' {
            if b[i] == b' ' {
                i += 1;
                continue;
            }
            if n < 8 {
                start[n] = i;
            }
            n += 1;
            while i < b.len() && b[i] != b' ' && b[i] != b'\n' {
                i += 1;
            }
        }
        i += 1;
        if n != 8 {
            continue;
        }
        // "SPACE" is the only field 0 longer than one byte
        let ch = if b[start[0] + 1] != b' ' {
            b' '
        } else {
            b[start[0]]
        };
        let mut row = 0;
        while row < 7 {
            let mut bits = 0;
            let mut col = 0;
            while col < 5 {
                if b[start[row + 1] + col] == b'1' {
                    bits |= 1 << (4 - col);
                }
                col += 1;
            }
            font[(ch - b' ') as usize][row] = bits;
            row += 1;
        }
    }
    font
}

/// The glyph for `ch`, folding lowercase to uppercase.
fn glyph(ch: char) -> Option<&'static Glyph> {
    (ch.to_ascii_uppercase() as usize)
        .checked_sub(32)
        .and_then(|i| FONT.get(i))
}

/// The lit dots of a glyph as (row, column) pairs, top to bottom.
fn dots(g: &Glyph) -> impl Iterator<Item = (i32, i32)> + '_ {
    (0..7).flat_map(move |row| {
        let bits = g[row as usize];
        (0..FONT_W)
            .filter(move |col| bits & (1 << (4 - col)) != 0)
            .map(move |col| (row, col))
    })
}

/// The pixel width of `s` at the given integer scale.
pub fn text_width(s: &str, scale: i32) -> i32 {
    match s.chars().count() as i32 {
        0 => 0,
        n => (n * ADVANCE - FONT_GAP) * scale,
    }
}

fn lerp_channel(a: u32, b: u32, u: f32) -> u32 {
    (a as f32 + (b as f32 - a as f32) * u) as u32
}

impl Frame {
    /// The visible part of a scale×scale glyph block at (px, py), as row and
    /// column ranges. Clipping once per block and then filling straight runs
    /// is much cheaper than testing bounds per pixel.
    fn clip_block(&self, px: i32, py: i32, scale: i32) -> Option<(Range<usize>, Range<usize>)> {
        let ys = py.max(0)..(py + scale).min(self.h as i32);
        let xs = px.max(0)..(px + scale).min(self.w as i32);
        (!ys.is_empty() && !xs.is_empty()).then_some((
            ys.start as usize..ys.end as usize,
            xs.start as usize..xs.end as usize,
        ))
    }

    /// Row `y`, columns `xs`, as a slice.
    fn span(&mut self, y: usize, xs: Range<usize>) -> &mut [u32] {
        let row = y * self.w;
        &mut self.pix[row + xs.start..row + xs.end]
    }

    fn draw_glyph(&mut self, x: i32, y: i32, g: &Glyph, scale: i32, c: u32) {
        for (row, col) in dots(g) {
            if let Some((ys, xs)) = self.clip_block(x + col * scale, y + row * scale, scale) {
                for yy in ys {
                    self.span(yy, xs.clone()).fill(c);
                }
            }
        }
    }

    /// Draws `s` in a solid colour with its top-left corner at (x, y).
    pub fn draw_text(&mut self, x: i32, y: i32, s: &str, scale: i32, c: u32) {
        let scale = scale.max(1);
        let mut cx = x;
        for ch in s.chars() {
            let Some(g) = glyph(ch) else {
                cx += FONT_W * scale;
                continue;
            };
            self.draw_glyph(cx, y, g, scale, c);
            cx += ADVANCE * scale;
        }
    }

    /// Draws `s` with a three-stop vertical colour ramp (top, mid, bottom),
    /// which is how the finale logo gets its chrome look. Each glyph sits at
    /// its own baseline offset from `offs`, so the letters can wave without
    /// giving up the gradient. With `scan` set every fourth row is darkened:
    /// the CRT look, which also hides the banding of a seven-row glyph.
    #[allow(clippy::too_many_arguments)]
    pub fn draw_text_gradient(
        &mut self,
        x: i32,
        y: i32,
        s: &str,
        scale: i32,
        [top, mid, bottom]: [u32; 3],
        offs: &[i32],
        scan: bool,
    ) {
        let scale = scale.max(1);
        let (tr, tg, tb) = channels(top);
        let (mr, mg, mb) = channels(mid);
        let (br, bg, bb) = channels(bottom);
        let total_h = (7 * scale) as f32;

        for (i, ch) in s.chars().enumerate() {
            let cx = x + i as i32 * ADVANCE * scale;
            let dy = offs.get(i).copied().unwrap_or(0);
            let Some(g) = glyph(ch) else { continue };
            for (row, col) in dots(g) {
                let Some((ys, xs)) = self.clip_block(cx + col * scale, y + row * scale + dy, scale)
                else {
                    continue;
                };
                for yy in ys {
                    let f = ((yy as i32 - y) as f32 / total_h).clamp(0.0, 1.0);
                    let (mut r, mut gg, mut bl) = if f < 0.5 {
                        let u = f * 2.0;
                        (
                            lerp_channel(tr, mr, u),
                            lerp_channel(tg, mg, u),
                            lerp_channel(tb, mb, u),
                        )
                    } else {
                        let u = (f - 0.5) * 2.0;
                        (
                            lerp_channel(mr, br, u),
                            lerp_channel(mg, bg, u),
                            lerp_channel(mb, bb, u),
                        )
                    };
                    if scan && yy & 3 == 0 {
                        r = r * 3 / 4;
                        gg = gg * 3 / 4;
                        bl = bl * 3 / 4;
                    }
                    self.span(yy, xs.clone()).fill(pack(r, gg, bl));
                }
            }
        }
    }

    /// Draws `s` offset by one pixel in the four cardinal directions, a hard
    /// edge that keeps the logo readable over a busy background. `offs` are
    /// the same per-glyph offsets as `draw_text_gradient`'s.
    pub fn draw_text_outline(&mut self, x: i32, y: i32, s: &str, scale: i32, c: u32, offs: &[i32]) {
        for (i, ch) in s.chars().enumerate() {
            let dy = offs.get(i).copied().unwrap_or(0);
            let gx = x + i as i32 * ADVANCE * scale;
            let Some(g) = glyph(ch) else { continue };
            for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                self.draw_glyph(gx + ox, y + dy + oy, g, scale.max(1), c);
            }
        }
    }

    /// Draws a vertically mirrored copy of `s` hanging from row `y`, the line
    /// the reflection sits on. The copy fades out over `depth` rows and is
    /// added to the frame rather than drawn over it, like light on a polished
    /// floor.
    #[allow(clippy::too_many_arguments)]
    pub fn draw_text_reflect(
        &mut self,
        x: i32,
        y: i32,
        s: &str,
        scale: i32,
        [top, bottom]: [u32; 2],
        offs: &[i32],
        strength: u8,
        depth: i32,
    ) {
        let scale = scale.max(1);
        let depth = depth.max(1) as f32;
        let (tr, tg, tb) = channels(top);
        let (br, bg, bb) = channels(bottom);

        for (i, ch) in s.chars().enumerate() {
            let cx = x + i as i32 * ADVANCE * scale;
            let dy = offs.get(i).copied().unwrap_or(0);
            let Some(g) = glyph(ch) else { continue };
            for (row, col) in dots(g) {
                // mirrored: glyph row 0 sits at the far end, and a letter
                // lifted by dy has its reflection pushed down by as much
                let py = y + (6 - row) * scale - dy;
                let Some((ys, xs)) = self.clip_block(cx + col * scale, py, scale) else {
                    continue;
                };
                for yy in ys {
                    let d = (yy as i32 - y) as f32 / depth;
                    if d > 1.0 {
                        continue;
                    }
                    let a = (1.0 - d) * (1.0 - d);
                    let intensity = (f32::from(strength) * a) as u8;
                    if intensity == 0 {
                        continue;
                    }
                    let c = pack(
                        lerp_channel(tr, br, d),
                        lerp_channel(tg, bg, d),
                        lerp_channel(tb, bb, d),
                    );
                    let base = yy * self.w;
                    for xx in xs.clone() {
                        self.additive(base + xx, c, intensity);
                    }
                }
            }
        }
    }
}
