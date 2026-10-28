# FMath: what every effect leans on. A Perl translation of
# go/internal/fmath and go/internal/palette.
#
# Perl has one kind of number that matters here, the double. Go's effects
# compute in float32, so every float32 operation is followed by a rounding
# to float32. Perl's only way to do that is to store the number as a C
# float and read it back: unpack 'f', pack 'f', $x. Both take lists, so a
# whole row rounds in one pack and one unpack. That is why the effects
# work a row at a time, as lists, rather than a pixel at a time.

package FMath;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT = qw(f32 tsin tsin01 PI TAB_SIZE TAB_MASK INV2PI @SIN @COS $SUNSET $ICE $EMBER);

# f32 LIST rounds each number to the nearest float32 (in scalar context,
# the first one). For + - * / and sqrt, computing in double and rounding
# once gives exactly the float32 result, so this is all it takes.
sub f32 { unpack 'f*', pack 'f*', @_ }

use constant PI       => 4 * atan2(1, 1);
use constant TAB_SIZE => 1 << 13;
use constant TAB_MASK => TAB_SIZE - 1;
use constant INV2PI   => f32(TAB_SIZE / (2 * PI));    # Go: untyped, made float32

# the sine and cosine tables, float32 like Go's, with the full period
# wrapping exactly
our @SIN = f32(map { sin(2 * PI * $_ / TAB_SIZE) } 0 .. TAB_SIZE);
our @COS = f32(map { cos(2 * PI * $_ / TAB_SIZE) } 0 .. TAB_SIZE);
$SIN[TAB_SIZE] = $SIN[0];
$COS[TAB_SIZE] = $COS[0];

# tsin LIST is fmath.Sin on each angle (radians, already float32): one
# rounding for the product, then int() truncates toward zero like Go's int().
# On a negative int, & works on its two's-complement bits, again like Go.
sub tsin { map { $SIN[int($_) & TAB_MASK] } f32(map { $_ * INV2PI } @_) }

# tsin01 LIST is fmath.Sin01, for angles in turns. Multiplying a float32 by
# 8192 is exact, so there is nothing to round.
sub tsin01 { map { $SIN[int($_ * TAB_SIZE) & TAB_MASK] } @_ }

# palette STOPS builds a 256-colour ramp (float64 maths, as in Go) from
# [pos, r, g, b] stops, packed 0xAABBGGRR: R, G, B, A bytes in memory.
sub palette {
    my @stops = @_;
    my $byte = sub { my $v = shift; $v <= 0 ? 0 : $v >= 1 ? 255 : int($v * 255 + 0.5) };
    return [ map {
        my $t = $_ / 255;
        my ($lo, $hi) = @stops[0, -1];
        for my $k (0 .. $#stops - 1) {
            if ($t >= $stops[$k][0] && $t <= $stops[$k + 1][0]) {
                ($lo, $hi) = @stops[$k, $k + 1];
                last;
            }
        }
        my $u = $hi->[0] > $lo->[0] ? ($t - $lo->[0]) / ($hi->[0] - $lo->[0]) : 0;
        $u = $u < 0 ? 0 : $u > 1 ? 1 : $u;
        $u = $u * $u * (3 - 2 * $u);    # smoothstep keeps gradients from banding
        my ($r, $g, $bl) = map { $lo->[$_] + ($hi->[$_] - $lo->[$_]) * $u } 1 .. 3;
        0xFF000000 | $byte->($bl) << 16 | $byte->($g) << 8 | $byte->($r);
    } 0 .. 255 ];
}

our $SUNSET = palette(
    [0.00, 0.02, 0.00, 0.06], [0.18, 0.25, 0.02, 0.38], [0.38, 0.72, 0.05, 0.45],
    [0.56, 0.98, 0.25, 0.22], [0.74, 1.00, 0.62, 0.15], [0.88, 1.00, 0.93, 0.55],
    [1.00, 1.00, 1.00, 0.96],
);
our $ICE = palette(
    [0.00, 0.00, 0.00, 0.03], [0.25, 0.00, 0.10, 0.30], [0.50, 0.00, 0.55, 0.85],
    [0.72, 0.35, 0.90, 1.00], [0.90, 0.80, 1.00, 1.00], [1.00, 1.00, 1.00, 1.00],
);
our $EMBER = palette(
    [0.00, 0.00, 0.00, 0.00], [0.20, 0.25, 0.00, 0.00], [0.45, 0.80, 0.10, 0.00],
    [0.68, 1.00, 0.45, 0.00], [0.85, 1.00, 0.80, 0.15], [1.00, 1.00, 1.00, 0.85],
);

1;
