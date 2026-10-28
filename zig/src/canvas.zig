//! The software framebuffer every effect draws into, and the 5x7 font the
//! finale writes with.
//!
//! Pixels are packed as 0xAABBGGRR in a u32, which in little-endian memory is
//! R, G, B, A: exactly the bytes of a browser ImageData, so the host copies a
//! frame without converting it.

const std = @import("std");

pub const FB = struct {
    w: usize,
    h: usize,
    pix: []u32, // w*h pixels, row-major, top row first

    /// Row y as a slice: the bounds check happens once here, not per pixel.
    pub inline fn row(fb: FB, y: usize) []u32 {
        return fb.pix[y * fb.w ..][0..fb.w];
    }

    /// Adds colour c scaled by intensity/255 to pixel i, saturating.
    pub fn additive(fb: FB, i: usize, c: u32, intensity: u8) void {
        if (intensity == 0) return;
        const p = fb.pix[i];
        const k: u32 = intensity;
        const r = @min((p & 0xFF) + (c & 0xFF) * k / 255, 255);
        const g = @min((p >> 8 & 0xFF) + (c >> 8 & 0xFF) * k / 255, 255);
        const b = @min((p >> 16 & 0xFF) + (c >> 16 & 0xFF) * k / 255, 255);
        fb.pix[i] = rgb(r, g, b);
    }

    /// A 1px horizontal line, clipped to the frame.
    pub fn hline(fb: FB, x: i32, y: i32, len: i32, c: u32) void {
        if (y < 0 or y >= fb.h) return;
        const x0: usize = @intCast(std.math.clamp(x, 0, @as(i32, @intCast(fb.w))));
        const x1: usize = @intCast(std.math.clamp(x + len, 0, @as(i32, @intCast(fb.w))));
        if (x0 < x1) @memset(fb.row(@intCast(y))[x0..x1], c);
    }

    /// The visible part of a scale x scale glyph block at (px, py), or null if
    /// none of it is. Clipping once per block and then writing straight runs
    /// is much cheaper than testing bounds per pixel.
    fn clipBlock(fb: FB, px: i32, py: i32, scale: i32) ?Block {
        const w: i32 = @intCast(fb.w);
        const h: i32 = @intCast(fb.h);
        const b: Block = .{
            .y0 = @max(py, 0),
            .y1 = @min(py + scale, h),
            .x0 = @intCast(@max(px, 0)),
            .x1 = @intCast(@max(@min(px + scale, w), 0)),
        };
        return if (b.y0 < b.y1 and b.x0 < b.x1) b else null;
    }

    /// Draws s with its top-left corner at (x, y) in solid colour c.
    pub fn drawText(fb: FB, x: i32, y: i32, s: []const u8, scale_in: i32, c: u32) void {
        const scale = @max(scale_in, 1);
        var cx = x;
        for (s) |ch| {
            const g = glyph(ch) orelse {
                // as in Go, an unknown character advances without the gap
                cx += font_width * scale;
                continue;
            };
            for (g, 0..) |bits, row_i| {
                if (bits == 0) continue;
                const py = y + @as(i32, @intCast(row_i)) * scale;
                for (0..5) |col| {
                    if ((bits & bit(col)) == 0) continue;
                    const px = cx + @as(i32, @intCast(col)) * scale;
                    const b = fb.clipBlock(px, py, scale) orelse continue;
                    for (@as(usize, @intCast(b.y0))..@as(usize, @intCast(b.y1))) |yy| @memset(fb.row(yy)[b.x0..b.x1], c);
                }
            }
            cx += (font_width + font_gap) * scale;
        }
    }

    /// Draws s with a three-stop vertical colour ramp (top, mid, bottom),
    /// which is how the finale logo gets its chrome look. Each glyph sits at
    /// its own baseline offset offs[i], so callers can wave the letters
    /// without giving up the gradient. With scan set, every fourth row is
    /// darkened: the CRT look, which also hides the banding of a seven-row
    /// glyph at large scales.
    pub fn drawTextGradient(fb: FB, x: i32, y: i32, s: []const u8, scale_in: i32, top: u32, mid: u32, bottom: u32, offs: []const i32, scan: bool) void {
        const scale = @max(scale_in, 1);
        const t = channels(top);
        const m = channels(mid);
        const b3 = channels(bottom);
        const total_h: f32 = @floatFromInt(7 * scale);

        var cx = x;
        for (s, 0..) |ch, i| {
            const dy = if (i < offs.len) offs[i] else 0;
            if (glyph(ch)) |g| {
                for (g, 0..) |bits, row_i| {
                    if (bits == 0) continue;
                    const py = y + @as(i32, @intCast(row_i)) * scale + dy;
                    for (0..5) |col| {
                        if ((bits & bit(col)) == 0) continue;
                        const px = cx + @as(i32, @intCast(col)) * scale;
                        const blk = fb.clipBlock(px, py, scale) orelse continue;
                        var yy = blk.y0;
                        while (yy < blk.y1) : (yy += 1) {
                            const f = std.math.clamp(@as(f32, @floatFromInt(yy - y)) / total_h, 0, 1);
                            var c = if (f < 0.5) lerp3(t, m, f * 2) else lerp3(m, b3, (f - 0.5) * 2);
                            if (scan and (yy & 3) == 0) {
                                for (&c) |*v| v.* = v.* * 3 / 4;
                            }
                            @memset(fb.row(@intCast(yy))[blk.x0..blk.x1], rgb(c[0], c[1], c[2]));
                        }
                    }
                }
            }
            cx += (font_width + font_gap) * scale;
        }
    }

    /// Draws s offset by one pixel in the four cardinal directions in colour
    /// c, producing a hard edge that keeps the logo readable over a busy
    /// background. offs are the same per-glyph offsets as drawTextGradient's.
    pub fn drawTextOutline(fb: FB, x: i32, y: i32, s: []const u8, scale: i32, c: u32, offs: []const i32) void {
        for (s, 0..) |_, i| {
            const dy = if (i < offs.len) offs[i] else 0;
            const gx = x + @as(i32, @intCast(i)) * (font_width + font_gap) * scale;
            for ([4][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |d| {
                fb.drawText(gx + d[0], y + dy + d[1], s[i..][0..1], scale, c);
            }
        }
    }

    /// Draws a vertically mirrored copy of s starting at y, the line the
    /// reflection sits on. The copy fades out over depth rows and is added to
    /// the framebuffer rather than drawn over it, so it looks like light on a
    /// polished floor.
    pub fn drawTextReflect(fb: FB, x: i32, y: i32, s: []const u8, scale_in: i32, top: u32, bottom: u32, offs: []const i32, strength: u8, depth_in: i32) void {
        const scale = @max(scale_in, 1);
        const depth: f32 = @floatFromInt(@max(depth_in, 1));
        const t = channels(top);
        const b3 = channels(bottom);

        var cx = x;
        for (s, 0..) |ch, i| {
            const dy = if (i < offs.len) offs[i] else 0;
            if (glyph(ch)) |g| {
                for (g, 0..) |bits, row_i| {
                    if (bits == 0) continue;
                    // mirrored: glyph row 0 sits at the far end, and a letter
                    // lifted by dy has its reflection pushed down by as much
                    const py = y + (6 - @as(i32, @intCast(row_i))) * scale - dy;
                    for (0..5) |col| {
                        if ((bits & bit(col)) == 0) continue;
                        const px = cx + @as(i32, @intCast(col)) * scale;
                        const blk = fb.clipBlock(px, py, scale) orelse continue;
                        var yy = blk.y0;
                        while (yy < blk.y1) : (yy += 1) {
                            const d = @as(f32, @floatFromInt(yy - y)) / depth;
                            if (d > 1) continue;
                            const a = (1 - d) * (1 - d);
                            const inten: u8 = @intFromFloat(@as(f32, @floatFromInt(strength)) * a);
                            if (inten == 0) continue;
                            const c = lerp3(t, b3, d);
                            const base = @as(usize, @intCast(yy)) * fb.w;
                            for (blk.x0..blk.x1) |xx| fb.additive(base + xx, rgb(c[0], c[1], c[2]), inten);
                        }
                    }
                }
            }
            cx += (font_width + font_gap) * scale;
        }
    }
};

const Block = struct { y0: i32, y1: i32, x0: usize, x1: usize };

/// Packs a colour into the framebuffer layout, alpha opaque.
pub inline fn rgb(r: u32, g: u32, b: u32) u32 {
    return 0xFF000000 | b << 16 | g << 8 | r;
}

/// Maps [0,1] to 0..255, rounding and clamping. The clamp comes first because
/// @intFromFloat on a value that does not fit a u8 is illegal behaviour.
pub inline fn unitToByte(v: f64) u32 {
    if (v <= 0) return 0;
    if (v >= 1) return 255;
    const b: u8 = @intFromFloat(v * 255 + 0.5);
    return b;
}

/// Packs normalised channels, clamping each to [0,1].
pub inline fn fromFloat(r: f64, g: f64, b: f64) u32 {
    return rgb(unitToByte(r), unitToByte(g), unitToByte(b));
}

pub inline fn clamp01(v: f64) f64 {
    return if (v < 0) 0 else if (v > 1) 1 else v;
}

/// A colour's R, G, B channels as f32, for the text gradients.
fn channels(c: u32) [3]f32 {
    return .{ @floatFromInt(c & 0xFF), @floatFromInt(c >> 8 & 0xFF), @floatFromInt(c >> 16 & 0xFF) };
}

/// a + (b-a)*u per channel, truncated toward zero as Go's uint32() does.
fn lerp3(a: [3]f32, b: [3]f32, u: f32) [3]u32 {
    var out: [3]u32 = undefined;
    for (&out, a, b) |*o, ca, cb| o.* = @intFromFloat(ca + (cb - ca) * u);
    return out;
}

// --- the font ---

pub const font_width = 5;
pub const font_gap = 1;

/// Pixel width of a string of n characters at the given integer scale.
pub fn textWidth(n: usize, scale: i32) i32 {
    if (n == 0) return 0;
    return (@as(i32, @intCast(n)) * (font_width + font_gap) - font_gap) * scale;
}

/// Pixel height of one line at the given scale.
pub fn textHeight(scale: i32) i32 {
    return 7 * scale;
}

/// One character's 7 rows of 5-bit pixels, MSB on the left.
const Glyph = [7]u8;

inline fn bit(col: usize) u8 {
    return @as(u8, 1) << @intCast(4 - col);
}

/// Maps a character to its glyph, folding lowercase to uppercase.
fn glyph(ch: u8) ?*const Glyph {
    const c = std.ascii.toUpper(ch);
    if (c < 32 or c - 32 >= font.len) return null;
    return &font[c - 32];
}

/// The 5x7 font, written out as text so it stays readable in source. Each
/// line is "CHAR row0 row1 ... row6", one character per pixel. The parser
/// below runs inside the compiler: the module only ships the 665 bytes of
/// bitmaps, never this text.
const font_src =
    \\SPACE 00000 00000 00000 00000 00000 00000 00000
    \\! 00100 00100 00100 00100 00100 00000 00100
    \\" 01010 01010 01010 00000 00000 00000 00000
    \\# 01010 01010 11111 01010 11111 01010 01010
    \\$ 00100 01111 10100 01110 00101 11110 00100
    \\% 11001 11010 00010 00100 01000 01011 10011
    \\& 01100 10010 10100 01000 10101 10010 01101
    \\' 00100 00100 01000 00000 00000 00000 00000
    \\( 00010 00100 01000 01000 01000 00100 00010
    \\) 01000 00100 00010 00010 00010 00100 01000
    \\* 00000 10101 01110 11111 01110 10101 00000
    \\+ 00000 00100 00100 11111 00100 00100 00000
    \\, 00000 00000 00000 00000 01100 01100 11000
    \\- 00000 00000 00000 11111 00000 00000 00000
    \\. 00000 00000 00000 00000 00000 01100 01100
    \\/ 00001 00010 00010 00100 01000 01000 10000
    \\0 01110 10001 10011 10101 11001 10001 01110
    \\1 00100 01100 00100 00100 00100 00100 01110
    \\2 01110 10001 00001 00110 01000 10000 11111
    \\3 11111 00010 00100 00010 00001 10001 01110
    \\4 00010 00110 01010 10010 11111 00010 00010
    \\5 11111 10000 11110 00001 00001 10001 01110
    \\6 00110 01000 10000 11110 10001 10001 01110
    \\7 11111 00001 00010 00100 01000 01000 01000
    \\8 01110 10001 10001 01110 10001 10001 01110
    \\9 01110 10001 10001 01111 00001 00010 01100
    \\: 00000 01100 01100 00000 01100 01100 00000
    \\; 00000 01100 01100 00000 01100 00100 01000
    \\< 00010 00100 01000 10000 01000 00100 00010
    \\= 00000 00000 11111 00000 11111 00000 00000
    \\> 01000 00100 00010 00001 00010 00100 01000
    \\? 01110 10001 00001 00110 00100 00000 00100
    \\@ 01110 10001 10111 10101 10111 10000 01110
    \\A 01110 10001 10001 11111 10001 10001 10001
    \\B 11110 10001 10001 11110 10001 10001 11110
    \\C 01110 10001 10000 10000 10000 10001 01110
    \\D 11110 10001 10001 10001 10001 10001 11110
    \\E 11111 10000 10000 11110 10000 10000 11111
    \\F 11111 10000 10000 11110 10000 10000 10000
    \\G 01110 10001 10000 10111 10001 10001 01111
    \\H 10001 10001 10001 11111 10001 10001 10001
    \\I 11111 00100 00100 00100 00100 00100 11111
    \\J 00111 00010 00010 00010 00010 10010 01100
    \\K 10001 10010 10100 11000 10100 10010 10001
    \\L 10000 10000 10000 10000 10000 10000 11111
    \\M 10001 11011 10101 10101 10001 10001 10001
    \\N 10001 11001 10101 10011 10001 10001 10001
    \\O 01110 10001 10001 10001 10001 10001 01110
    \\P 11110 10001 10001 11110 10000 10000 10000
    \\Q 01110 10001 10001 10001 10101 10010 01101
    \\R 11110 10001 10001 11110 10100 10010 10001
    \\S 01111 10000 10000 01110 00001 00001 11110
    \\T 11111 00100 00100 00100 00100 00100 00100
    \\U 10001 10001 10001 10001 10001 10001 01110
    \\V 10001 10001 10001 10001 10001 01010 00100
    \\W 10001 10001 10001 10101 10101 10101 01010
    \\X 10001 10001 01010 00100 01010 10001 10001
    \\Y 10001 10001 01010 00100 00100 00100 00100
    \\Z 11111 00001 00010 00100 01000 10000 11111
    \\[ 01110 01000 01000 01000 01000 01000 01110
    \\\ 10000 01000 01000 00100 00010 00010 00001
    \\] 01110 00010 00010 00010 00010 00010 01110
    \\^ 00100 01010 10001 00000 00000 00000 00000
    \\_ 00000 00000 00000 00000 00000 00000 11111
    \\{ 00110 00100 01000 01000 01000 00100 00110
    \\| 00100 00100 00100 00100 00100 00100 00100
    \\} 01100 00100 00010 00010 00010 00100 01100
    \\~ 00000 00000 01000 10101 00010 00000 00000
;

const font: [95]Glyph = parse: {
    @setEvalBranchQuota(50_000);
    var f = std.mem.zeroes([95]Glyph);
    var lines = std.mem.tokenizeScalar(u8, font_src, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        const name = fields.next().?;
        const ch: u8 = if (std.mem.eql(u8, name, "SPACE")) ' ' else name[0];
        for (&f[ch - 32]) |*row_bits| {
            const dots = fields.next().?;
            if (dots.len != 5) @compileError("font: bad row for '" ++ name ++ "'");
            for (dots) |d| row_bits.* = row_bits.* << 1 | @intFromBool(d == '1');
        }
    }
    break :parse f;
};
