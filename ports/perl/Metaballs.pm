# Metaballs: six radial fields summed, sum(r^2 / d^2), and the iso-contour
# given a hot rim. A translation of go/internal/fx/metaballs.go.

package Metaballs;
use strict;
use warnings;
use FMath;

use constant { K0_35 => f32(0.35), K0_07 => f32(0.07), K2_1 => f32(2.1), K0_2 => f32(0.2),
               K0_3 => f32(0.3), K1_3 => f32(1.3), K0_4 => f32(0.4), K0_105 => f32(0.105),
               K0_025 => f32(0.025), K1_1 => f32(1.1), K1_7 => f32(1.7), K1E_5 => f32(1e-5),
               K1_6 => f32(1.6), K1_09 => f32(1.09) };

sub new {
    my ($class, $w, $h) = @_;
    return bless { w => $w, h => $h, pal => $SUNSET }, $class;
}

sub step { }

sub render {
    my ($self, $n) = @_;
    my ($w, $h, $pal) = @$self{qw(w h pal)};
    my $t = f32($n / 60);
    my (@bx, @by, @rad2);
    for my $i (0 .. 5) {
        # each ball orbits on its own ellipse and breathes
        my $a = f32(f32($t * f32(K0_35 + f32($i * K0_07))) + f32($i * K2_1));
        my ($ca) = tcos($a);
        my ($s1) = tsin(f32(f32($t * 0.5) + $i));
        my $x = f32(0.5 + f32(f32(K0_2 * $ca) * f32(1 + f32(K0_3 * $s1))));
        my ($sa) = tsin(f32(f32($a * K1_3) + $i));
        my ($c1) = tcos(f32(f32($t * K0_4) + f32($i * 2)));
        my $y = f32(0.5 + f32(f32(K0_2 * $sa) * f32(1 + f32(K0_3 * $c1))));
        my ($s2) = tsin(f32(f32($t * K1_1) + f32($i * K1_7)));
        my $r = f32(K0_105 + f32(K0_025 * $s2));
        push @rad2, f32($r * $r);
        push @bx, $x;
        push @by, $y;
    }
    # x is scaled by width/height so a circle stays a circle on screen
    my $asp = f32($w / $h);
    # the balls' centres in screen-shaped field space (Go recomputes these per
    # pixel; they are the same numbers)
    my @cx = f32(map { $_ * $asp } f32(map { $_ - 0.5 } @bx));
    my @cy = f32(map { $_ - 0.5 } @by);
    my @fx = f32(map { $_ * $asp } f32(map { $_ - 0.5 } f32(map { $_ / $w } 0 .. $w - 1)));
    my @pix;

    # @excerpt METABALLS
    for my $y (0 .. $h - 1) {
        my $fy = f32(f32($y / $h) - 0.5);
        my @field = (0) x $w;
        for my $i (0 .. 5) {
            my $dy = f32($fy - $cy[$i]);
            my $dy2 = f32($dy * $dy);
            # d2 = dx*dx + dy*dy + 1e-5, then field += r^2 / d2
            my @d2 = f32(map { $_ + K1E_5 } f32(map { $_ + $dy2 } f32(map { $_ * $_ } f32(map { $_ - $cx[$i] } @fx))));
            my @q = f32(map { $rad2[$i] / $_ } @d2);
            @field = f32(map { $field[$_] + $q[$_] } 0 .. $w - 1);
        }
        # v/(1+v) compresses the field into a usable 0..1 ramp; the rim, where
        # the balls meet, flares white
        my @den = f32(map { K1_6 + $_ } @field);
        my @idx = map { int } f32(map { $_ * 255 } f32(map { $field[$_] / $den[$_] } 0 .. $w - 1));
        push @pix, map {
            my $f = $field[$_];
            $pal->[$f > 1 && $f < K1_09 || $idx[$_] > 255 ? 255 : $idx[$_]];
        } 0 .. $w - 1;
    }
    # @end
    return \@pix;
}

1;
