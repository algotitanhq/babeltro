# Mandelbrot: a dive into the seahorse valley. All float64, which is the one
# number Perl has, so this is the scene with no f32 anywhere. A translation
# of go/internal/fx/mandelbrot.go, ladder included:
#   step 1  the escape-time loop for every pixel, nothing else
#   step 2  plus the closed-form test for the cardioid and the bulb
#   step 3  (and 0, the default) plus blocks of 2x2 pixels

package Mandelbrot;
use strict;
use warnings;
use FMath;

sub new {
    my ($class, $w, $h) = @_;
    # keep the block size constant in screen terms as the window grows
    return bless { w => $w, h => $h, pal => $ICE, step => 0, block => $w > 1600 ? 3 : 2 }, $class;
}

sub step { $_[0]{step} = $_[1] }

# @excerpt MANDELBROT/1
sub iter_plain {
    my ($cx, $cy, $max) = @_;
    my ($zx, $zy, $zx2, $zy2) = (0, 0, 0, 0);
    for my $i (0 .. $max - 1) {
        $zy = 2 * $zx * $zy + $cy;
        $zx = $zx2 - $zy2 + $cx;
        ($zx2, $zy2) = ($zx * $zx, $zy * $zy);
        return $i if $zx2 + $zy2 > 4;
    }
    return $max;
}
# @end

# @excerpt MANDELBROT/2
sub iter {
    my ($cx, $cy, $max) = @_;
    # cheap escape test for the main cardioid and the period-2 bulb
    my $x = $cx - 0.25;
    my $y2 = $cy * $cy;
    my $q = $x * $x + $y2;
    return $max if $q * ($q + $x) <= 0.25 * $y2;
    return $max if ($cx + 1) * ($cx + 1) + $y2 <= 0.0625;
    my ($zx, $zy, $zx2, $zy2) = (0, 0, 0, 0);
    for my $i (0 .. $max - 1) {
        $zy = 2 * $zx * $zy + $cy;
        $zx = $zx2 - $zy2 + $cx;
        ($zx2, $zy2) = ($zx * $zx, $zy * $zy);
        return $i if $zx2 + $zy2 > 4;
    }
    return $max;
}
# @end

sub render {
    my ($self, $n) = @_;
    my ($w, $h, $pal) = @$self{qw(w h pal)};
    my $t = $n / 60;
    $t = 14 if $t > 14;
    my $u = $t / 12;
    # slide onto the target quickly, then let the exponential dive work
    my $k = 1 - exp(-8 * $u);
    my $span = 2.9 * exp(-$u * $u * 3.6);
    my $max = 64 + int(128 * $u);
    my $mx = -0.5 + (-0.743643887037151 + 0.5) * $k;
    my $my = 0.0 + 0.131825904205330 * $k;

    my ($step, $iter) = ($self->{block}, \&iter);
    ($step, $iter) = (1, \&iter_plain) if $self->{step} == 1;
    $step = 1 if $self->{step} == 2;
    my $x0 = $mx - $span * 0.5;
    my $y0 = $my - $span * 0.5 * ($h / $w);
    my $d = $span / $w;    # units per pixel
    my @pix;

    # @excerpt MANDELBROT
    for (my $by = 0; $by < $h; $by += $step) {
        my $cy = $y0 + $by * $d;
        # one row of blocks: a colour per block, each repeated step times
        my @row = map {
            my $it = $iter->($x0 + $_ * $d, $cy, $max);
            my $c = 0xFF0A0812;
            if ($it < $max) {
                # the ramp is anchored to 40 iterations, not to the budget
                my $v = sqrt($it / 40);
                $v = 1 if $v > 1;
                my $i = int(($v * 0.92 + 0.04) * 255);
                $c = $pal->[$i < 0 ? 0 : $i > 255 ? 255 : $i];
            }
            ($c) x $step;
        } grep { $_ % $step == 0 } 0 .. $w - 1;
        $#row = $w - 1;    # the last block may stick out on the right
        push @pix, (@row) x ($by + $step > $h ? $h - $by : $step);
    }
    # @end
    return \@pix;
}

1;
