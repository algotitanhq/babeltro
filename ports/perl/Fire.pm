# Fire: the Doom fire. A heat buffer seeded at the bottom row and diffused
# upward with a little random sideways drift; integers only, one byte of
# heat per pixel, read through a palette. A translation of
# go/internal/fx/fire.go.

package Fire;
use strict;
use warnings;
use FMath;

use constant { K0_05 => f32(0.05), K1_7 => f32(1.7), K0_6 => f32(0.6), K0_4 => f32(0.4) };

sub new {
    my ($class, $w, $h) = @_;
    return bless { w => $w, h => $h, pal => $EMBER, rng => 0x9E3779B9, heat => [ (0) x ($w * $h) ] }, $class;
}

sub step { }    # no ladder

sub render {
    my ($self, $frame) = @_;
    my ($w, $h, $heat) = @$self{qw(w h heat)};
    my $rng = $self->{rng};

    # seed the hottest row: a slow horizontal wave gives the fire its uneven
    # base, the random term keeps the tongues from looking periodic
    my $t = f32($frame * K0_05);
    my @fx = f32(map { $_ / $w } 0 .. $w - 1);
    my @s1 = tsin(f32(map { $_ + $t } f32(map { $_ * 11 } @fx)));
    my $t17 = f32($t * K1_7);
    my @s2 = tsin(f32(map { $_ - $t17 } f32(map { $_ * 23 } @fx)));
    my $last = ($h - 1) * $w;
    for my $x (0 .. $w - 1) {
        # wv = 0.5 + 0.5*s1*0.6 + 0.5*s2*0.4, rounded like Go's float32
        my $wv = f32(0.5 + f32(f32(0.5 * $s1[$x]) * K0_6));
        $wv = f32($wv + f32(f32(0.5 * $s2[$x]) * K0_4));
        $rng ^= $rng << 13 & 0xFFFFFFFF; $rng ^= $rng >> 17; $rng ^= $rng << 5 & 0xFFFFFFFF;
        my $v = f32(f32(f32(150 + f32($wv * 90)) + ($rng & 31)) - 16);
        $heat->[$last + $x] = $v > 255 ? 255 : $v < 90 ? 90 : int $v;
    }

    # diffuse upward: every destination pixel takes one value from the row
    # below, offset sideways by a random -1/0/+1. Gather, not scatter.
    # @excerpt FIRE
    for my $y (reverse 1 .. $h - 1) {
        my ($src, $dst) = ($y * $w, ($y - 1) * $w);
        for my $x (0 .. $w - 1) {
            unless ($heat->[$src + $x]) { $heat->[$dst + $x] = 0; next }
            # xorshift32, kept in 32 bits by hand: Perl's integers are 64-bit
            $rng ^= $rng << 13 & 0xFFFFFFFF; $rng ^= $rng >> 17; $rng ^= $rng << 5 & 0xFFFFFFFF;
            my $sx = $x + $rng % 3 - 1;    # -1, 0 or +1
            $sx = $sx < 0 ? 0 : $sx >= $w ? $w - 1 : $sx;
            my $v = $heat->[$src + $sx];
            my $decay = $rng >> 16 & 1;
            $heat->[$dst + $x] = $v > $decay ? $v - $decay : 0;
        }
    }
    # the whole buffer through the palette, in one slice
    my @pix = @{ $self->{pal} }[@$heat];
    # @end
    $self->{rng} = $rng;
    return \@pix;
}

1;
