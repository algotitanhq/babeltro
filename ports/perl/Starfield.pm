# Starfield: warp-speed stars in 3D, projected in perspective and drawn as
# short additive streaks. A translation of go/internal/fx/starfield.go.
#
# The 1600 stars are kept as parallel lists (x, y, z), so every float32
# operation is one map and one f32 over all of them.

package Starfield;
use strict;
use warnings;
use FMath;

use constant { K1_6 => f32(1.6), K1_1 => f32(1.1), K0_2 => f32(0.2),
               K0_8 => f32(0.8), K0_78 => f32(0.78), K2_4 => f32(2.4), DT => f32(1 / 60) };

sub new {
    my ($class, $w, $h) = @_;
    my $self = bless { w => $w, h => $h, rng => 0x6005E }, $class;
    my $rng = \$self->{rng};
    for (1 .. 1600) {
        # x, y, z in that order: Go evaluates the struct literal left to right
        push @{ $self->{x} }, f32(f32(f32(rng_f32($rng) * 2) - 1) * K1_6);
        push @{ $self->{y} }, f32(f32(f32(rng_f32($rng) * 2) - 1) * K1_6);
        push @{ $self->{z} }, f32(f32(rng_f32($rng) * 40) + K0_2);
    }
    # the deep-navy vignette, once: float64 maths, as in Go
    for my $y (0 .. $h - 1) {
        my $dy = $y / $h - 0.5;
        push @{ $self->{bg} }, map {
            my $dx = $_ / $w - 0.5;
            my $v = $dx * $dx + $dy * $dy;
            from_float(map { $_ < 0 ? 0 : $_ } 0.02 - $v * 0.03, 0.02 - $v * 0.025, 0.05 - $v * 0.03);
        } 0 .. $w - 1;
    }
    return $self;
}

sub step { }

sub render {
    my ($self, $n) = @_;
    my ($w, $h, $sx, $sy, $sz) = @$self{qw(w h x y z)};
    my $rng = \$self->{rng};
    my ($cx, $cy) = f32($w * 0.5, $h * 0.5);
    # accelerate over the scene so the entry has a kick
    my $beat = $n / 60;
    my $speed = f32(2.5 + ($beat < 3 ? $beat : 3) * 4);
    my $dz = f32($speed * DT);
    my $zoom = f32($w * K0_78);
    my $dz24 = f32($dz * K2_4);

    # @excerpt STARFIELD
    @$sz = f32(map { $_ - $dz } @$sz);
    # the stars that passed the camera go back to the far end, in order,
    # since each one draws two numbers from the generator
    for my $i (grep { $sz->[$_] < K0_8 } 0 .. $#$sz) {
        $sz->[$i] = f32($sz->[$i] + 40);
        $sx->[$i] = f32(f32(f32(rng_f32($rng) * 2) - 1) * K1_1);
        $sy->[$i] = f32(f32(f32(rng_f32($rng) * 2) - 1) * K1_1);
    }
    my @I = 0 .. $#$sz;
    my @f  = f32(map { 1 / $_ } @$sz);
    my @f2 = f32(map { 1 / $_ } f32(map { $_ + $dz24 } @$sz));
    # head (x0, y0) at the current depth, tail (x1, y1) a little further
    my @x0 = map { int } f32(map { $cx + $_ } f32(map { $_ * $zoom } f32(map { $sx->[$_] * $f[$_] } @I)));
    my @y0 = map { int } f32(map { $cy + $_ } f32(map { $_ * $zoom } f32(map { $sy->[$_] * $f[$_] } @I)));
    my @x1 = map { int } f32(map { $cx + $_ } f32(map { $_ * $zoom } f32(map { $sx->[$_] * $f2[$_] } @I)));
    my @y1 = map { int } f32(map { $cy + $_ } f32(map { $_ * $zoom } f32(map { $sy->[$_] * $f2[$_] } @I)));
    # brighter and bluer as the star gets close
    my @b = f32(map { $_ * $_ } f32(map { 1 - $_ } f32(map { $_ / 40 } @$sz)));
    my @c = map {
        my $b = $_;
        my $r = int f32(f32(120 * $b) + 40);
        my $g = int f32(f32(190 * $b) + 40);
        my $bl = int f32(255 * f32(0.25 + f32(0.75 * $b)));
        0xFF000000 | $bl << 16 | $g << 8 | $r;
    } @b;
    # @end

    my @pix = @{ $self->{bg} };
    for my $i (@I) {
        line_add(\@pix, $w, $h, $x0[$i], $y0[$i], $x1[$i], $y1[$i], $c[$i]);
        # bright head pixel
        $pix[$y1[$i] * $w + $x1[$i]] = 0xFFCCEEFF
            if $x1[$i] >= 0 && $x1[$i] < $w && $y1[$i] >= 0 && $y1[$i] < $h;
    }
    return \@pix;
}

# line_add draws a Bresenham line adding colour, so overlapping stars
# accumulate brightness instead of replacing each other
sub line_add {
    my ($pix, $w, $h, $x0, $y0, $x1, $y1, $c) = @_;
    my ($dx, $dy) = (abs($x1 - $x0), -abs($y1 - $y0));
    my ($stx, $sty) = ($x0 < $x1 ? 1 : -1, $y0 < $y1 ? 1 : -1);
    my $err = $dx + $dy;
    while (1) {
        if ($x0 >= 0 && $x0 < $w && $y0 >= 0 && $y0 < $h) {
            my $p = $pix->[$y0 * $w + $x0];
            my @s = map { my $v = ($p >> $_ & 0xFF) + ($c >> $_ & 0xFF); $v > 255 ? 255 : $v } 0, 8, 16;
            $pix->[$y0 * $w + $x0] = 0xFF000000 | $s[2] << 16 | $s[1] << 8 | $s[0];
        }
        last if $x0 == $x1 && $y0 == $y1;
        my $e2 = 2 * $err;
        if ($e2 >= $dy) { $err += $dy; $x0 += $stx }
        if ($e2 <= $dx) { $err += $dx; $y0 += $sty }
    }
}

1;
