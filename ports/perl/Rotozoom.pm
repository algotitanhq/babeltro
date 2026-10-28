# Rotozoom: a texture built once, then every frame a rotated and zoomed
# sampling grid over it. A translation of go/internal/fx/rotozoom.go.

package Rotozoom;
use strict;
use warnings;
use FMath;

use constant { TEX => 512, TEX_MASK => 511 };
use constant { K0_45 => f32(0.45), K0_7 => f32(0.7), K0_55 => f32(0.55), K0_35 => f32(0.35),
               K0_31 => f32(0.31), K0_27 => f32(0.27), K6_5 => f32(6.5) };

# The texture: a tileable rainbow plasma under a dark grid, 262,144 pixels
# of float64 maths. It depends on nothing, so it is built once per
# interpreter rather than once per scene start: a few seconds of Perl.
my @TEX;

sub texture {
    my $two_pi = 2 * PI;
    for my $y (0 .. TEX - 1) {
        my $fy = $y / TEX;
        for my $x (0 .. TEX - 1) {
            my $fx = $x / TEX;
            # every frequency is a whole number of cycles per tile
            my $v = sin($fx * $two_pi * 3 + $fy * $two_pi * 2) * 0.5
                  + sin($fy * $two_pi * 5 - $fx * $two_pi * 4) * 0.3
                  + sin(($fx + $fy) * $two_pi * 7) * 0.2;
            # concentric rings, also periodic in the tile
            my ($dx, $dy) = ($x - TEX / 2, $y - TEX / 2);
            my $rr = sqrt($dx * $dx + $dy * $dy) / TEX * 12;
            $v += sin($rr * $two_pi) * 0.35;
            # math.Mod(a, 1) is a - int(a), exactly, for any a this big
            my $hue = $v * 0.55 + 0.5;
            $hue -= int $hue;
            $hue += 1 if $hue < 0;
            my @c = hsl2rgb($hue, 0.70, 0.48 + 0.14 * $v);
            # a dark grid: without a straight edge the motion reads as shimmer
            @c = map { $_ * 0.28 } @c if $x % (TEX / 8) < 3 || $y % (TEX / 8) < 3;
            push @TEX, from_float(@c);
        }
    }
}

sub hsl2rgb {
    my ($h, $s, $l) = @_;
    return ($l, $l, $l) if $s == 0;
    my $q = $l < 0.5 ? $l * (1 + $s) : $l + $s - $l * $s;
    my $p = 2 * $l - $q;
    return map {
        my $t = $_;
        $t += 1 if $t < 0;
        $t -= 1 if $t > 1;
          $t < 1 / 6 ? $p + ($q - $p) * 6 * $t
        : $t < 1 / 2 ? $q
        : $t < 2 / 3 ? $p + ($q - $p) * (2 / 3 - $t) * 6
        :              $p;
    } $h + 1 / 3, $h, $h - 1 / 3;
}

sub new {
    my ($class, $w, $h) = @_;
    texture() unless @TEX;
    return bless { w => $w, h => $h }, $class;
}

sub step { }

sub render {
    my ($self, $n) = @_;
    my ($w, $h) = @$self{qw(w h)};
    my $t = f32($n / 60);
    my $ang = f32($t * K0_45);
    my ($cos_a) = tcos($ang);
    my ($sin_a) = tsin($ang);
    # breathing zoom: 0.7 .. 1.6
    my ($s07) = tsin(f32($t * K0_7));
    my $zoom = f32(f32(K0_55 + f32(K0_45 * $s07)) + K0_35);
    my ($s31) = tsin(f32($t * K0_31));
    my ($c27) = tcos(f32($t * K0_27));
    my $offx = f32(f32($s31 * 180) + f32($t * 26));
    my $offy = f32(f32($c27 * 180) + f32($t * 19));
    my ($cx, $cy) = f32($w * 0.5, $h * 0.5);
    $zoom = f32(f32($zoom / $w) * K6_5);
    my @dx = f32(map { $_ - $cx } 0 .. $w - 1);
    my @dxc = f32(map { $_ * $cos_a } @dx);
    my @dxs = f32(map { $_ * $sin_a } @dx);
    my @X = 0 .. $w - 1;
    my @pix;

    # @excerpt ROTOZOOM
    for my $y (0 .. $h - 1) {
        my $dy = f32($y - $cy);
        my ($dys, $dyc) = f32($dy * $sin_a, $dy * $cos_a);
        # (dx*cosA - dy*sinA) * zoom * 34, and its twin, one row at a time
        my @tx = f32(map { $_ * 34 } f32(map { $_ * $zoom } f32(map { $_ - $dys } @dxc)));
        my @ty = f32(map { $_ * 34 } f32(map { $_ * $zoom } f32(map { $_ + $dyc } @dxs)));
        my @ix = map { int($_) & TEX_MASK } f32(map { $_ + $offx } @tx);
        my @iy = map { int($_) & TEX_MASK } f32(map { $_ + $offy } @ty);
        push @pix, @TEX[map { $iy[$_] * TEX + $ix[$_] } @X];
    }
    # @end
    return \@pix;
}

1;
