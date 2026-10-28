# Canvas: a framebuffer (a plain list of packed pixels) and the 5x7 font
# everything on the closing card is drawn with. A translation of the parts
# of go/internal/canvas the finale uses.

package Canvas;
use strict;
use warnings;
use FMath;

use constant { FONT_W => 5, FONT_GAP => 1 };

# The font, as text: "CHAR row0 … row6", one character per pixel. Each
# glyph becomes seven 5-bit numbers, which is all oct('0b…') takes.
my %FONT;
for (split /\n/, <<'END') {
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
END
    my ($ch, @rows) = split ' ';
    next unless @rows == 7;
    $FONT{ $ch eq 'SPACE' ? ' ' : $ch } = [ map { oct "0b$_" } @rows ];
}

sub new {
    my ($class, $w, $h) = @_;
    return bless { w => $w, h => $h, pix => [] }, $class;
}

sub text_width  { my ($s, $scale) = @_; length $s ? (length($s) * (FONT_W + FONT_GAP) - FONT_GAP) * $scale : 0 }
sub text_height { 7 * $_[0] }

# glyph CH yields the font rows of a character, lowercase folded to upper
sub glyph { $FONT{ uc $_[0] } }

# blocks X, Y, CH, SCALE, DY: the visible part of every lit scale×scale
# block of a glyph, as [y0, y1, x0, x1] (half-open), clipped to the frame.
# MIRROR draws the rows upside down below y, for the reflection.
sub blocks {
    my ($self, $x, $y, $ch, $scale, $dy, $mirror) = @_;
    my $g = glyph($ch) or return;
    my @out;
    for my $row (0 .. 6) {
        my $bits = $g->[$row] or next;
        my $py = $mirror ? $y + (6 - $row) * $scale - $dy : $y + $row * $scale + $dy;
        for my $col (0 .. 4) {
            next unless $bits & 1 << (4 - $col);
            my $px = $x + $col * $scale;
            my ($y0, $y1, $x0, $x1) = ($py, $py + $scale, $px, $px + $scale);
            $y0 = 0 if $y0 < 0;
            $y1 = $self->{h} if $y1 > $self->{h};
            $x0 = 0 if $x0 < 0;
            $x1 = $self->{w} if $x1 > $self->{w};
            push @out, [$y0, $y1, $x0, $x1] if $y0 < $y1 && $x0 < $x1;
        }
    }
    return @out;
}

# fill Y, X0, X1, C writes a run of one colour
sub fill { my ($self, $y, $x0, $x1, $c) = @_; @{ $self->{pix} }[$y * $self->{w} + $x0 .. $y * $self->{w} + $x1 - 1] = ($c) x ($x1 - $x0) }

# additive I, C, INTENSITY adds c scaled by intensity/255, saturating
sub additive {
    my ($self, $i, $c, $k) = @_;
    return unless $k;
    my $p = $self->{pix}[$i];
    my @s = map { my $v = ($p >> $_ & 0xFF) + int(($c >> $_ & 0xFF) * $k / 255); $v > 255 ? 255 : $v } 0, 8, 16;
    $self->{pix}[$i] = 0xFF000000 | $s[2] << 16 | $s[1] << 8 | $s[0];
}

sub hline {
    my ($self, $x, $y, $len, $c) = @_;
    return if $y < 0 || $y >= $self->{h};
    $self->{pix}[$y * $self->{w} + $_] = $c for grep { $_ >= 0 && $_ < $self->{w} } $x .. $x + $len - 1;
}

# draw_text X, Y, S, SCALE, C: solid text, top-left corner at (x, y)
sub draw_text {
    my ($self, $x, $y, $s, $scale, $c) = @_;
    for my $ch (split //, $s) {
        for my $b ($self->blocks($x, $y, $ch, $scale, 0)) {
            $self->fill($_, $b->[2], $b->[3], $c) for $b->[0] .. $b->[1] - 1;
        }
        $x += (FONT_W + FONT_GAP) * $scale;
    }
}

# draw_text_outline: the text offset one pixel in the four cardinal
# directions, each glyph lifted by its own wave offset
sub draw_text_outline {
    my ($self, $x, $y, $s, $scale, $c, $offs) = @_;
    my $i = 0;
    for my $ch (split //, $s) {
        my $gx = $x + $i * (FONT_W + FONT_GAP) * $scale;
        $self->draw_text($gx + $_->[0], $y + $offs->[$i] + $_->[1], $ch, $scale, $c) for [-1, 0], [1, 0], [0, -1], [0, 1];
        $i++;
    }
}

# channels C splits a packed colour into r, g, b
sub channels { map { $_[0] >> $_ & 0xFF } 0, 8, 16 }
sub rgb { 0xFF000000 | $_[2] << 16 | $_[1] << 8 | $_[0] }

# draw_text_gradient: text under a three-stop vertical ramp (the chrome),
# every fourth row darkened when SCAN is set (the CRT look)
sub draw_text_gradient {
    my ($self, $x, $y, $s, $scale, $top, $mid, $bot, $offs, $scan) = @_;
    my @t = channels($top);
    my @m = channels($mid);
    my @b = channels($bot);
    my $total = 7 * $scale;
    my $i = 0;
    for my $ch (split //, $s) {
        for my $blk ($self->blocks($x, $y, $ch, $scale, $offs->[$i])) {
            for my $yy ($blk->[0] .. $blk->[1] - 1) {
                my $f = f32(($yy - $y) / $total);
                $f = $f < 0 ? 0 : $f > 1 ? 1 : $f;
                my ($from, $to, $u) = $f < 0.5 ? (\@t, \@m, f32($f * 2)) : (\@m, \@b, f32(f32($f - 0.5) * 2));
                my @c = map { int f32($from->[$_] + f32(($to->[$_] - $from->[$_]) * $u)) } 0 .. 2;
                @c = map { int($_ * 3 / 4) } @c if $scan && ($yy & 3) == 0;
                $self->fill($yy, $blk->[2], $blk->[3], rgb(@c));
            }
        }
        $x += (FONT_W + FONT_GAP) * $scale;
        $i++;
    }
}

# draw_text_reflect: the text mirrored below the line y, fading out over
# DEPTH rows and added to the frame: light on a polished floor
sub draw_text_reflect {
    my ($self, $x, $y, $s, $scale, $top, $bot, $offs, $strength, $depth) = @_;
    my @t = channels($top);
    my @b = channels($bot);
    my $i = 0;
    for my $ch (split //, $s) {
        for my $blk ($self->blocks($x, $y, $ch, $scale, $offs->[$i], 1)) {
            for my $yy ($blk->[0] .. $blk->[1] - 1) {
                my $d = f32(($yy - $y) / $depth);
                next if $d > 1;
                my $a = f32(1 - $d);
                my $k = int f32($strength * f32($a * $a));
                next unless $k;
                my $c = rgb(map { int f32($t[$_] + f32(($b[$_] - $t[$_]) * $d)) } 0 .. 2);
                $self->additive($yy * $self->{w} + $_, $c, $k) for $blk->[2] .. $blk->[3] - 1;
            }
        }
        $x += (FONT_W + FONT_GAP) * $scale;
        $i++;
    }
}

1;
