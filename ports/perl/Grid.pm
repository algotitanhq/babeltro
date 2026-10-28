# Grid: the synthwave floor under a banded sun. A translation of
# go/internal/fx/grid.go. Go hoists everything that depends only on the row
# out of the pixel loop; here the pixel loop is a list of maps per row, with
# the per-pixel branches (max, min, the line's width) as ternaries.

package Grid;
use strict;
use warnings;
use FMath;

use constant { K0_52 => f32(0.52), K0_13 => f32(0.13), K0_16 => f32(0.16), K0_55 => f32(0.55),
               K2_5 => f32(2.5), K5_5 => f32(5.5), K0_022 => f32(0.022), K0_014 => f32(0.014),
               K0_024 => f32(0.024), K0_004 => f32(0.004), K0_02 => f32(0.02), K0_01 => f32(0.01),
               K0_06 => f32(0.06), K0_12 => f32(0.12), K0_35 => f32(0.35), K0_75 => f32(0.75),
               K0_45 => f32(0.45), K0_025 => f32(0.025), K0_37 => f32(0.37) };

sub new {
    my ($class, $w, $h) = @_;
    return bless { w => $w, h => $h, horizon => f32($h * K0_52), asp => f32($h / $w) }, $class;
}

sub step { }

# mod1 wraps a world coordinate into [0,1) (Go's mathMod2)
sub mod1 { my $m = f32($_[0] - int $_[0]); $m < 0 ? f32($m + 1) : $m }

# glow F, W is 1 on a grid line, falling to 0 over width w (Go's lineGlow)
sub glow { my ($d, $w) = @_; $d = f32(1 - $d) if $d > 0.5; $d < $w ? f32(1 - f32($d / $w)) : 0 }

sub render {
    my ($self, $n) = @_;
    my ($w, $h, $horizon, $asp) = @$self{qw(w h horizon asp)};
    my $t = f32($n / 60);
    my $cx = f32($w * 0.5);
    # the sun
    my $sun_y = f32($horizon - f32($h * K0_13));
    my $sun_r = f32($h * K0_16);
    my @X = 0 .. $w - 1;
    my @xc = f32(map { $_ - $cx } @X);    # x - cx, which is also x - sunX
    my $lw_x = K0_022;
    my @pix;

    for my $y (0 .. $h - 1) {
        # the sky: one colour per row (float64, then float32)
        my $sky = clamp01(f32($y / $horizon));
        my @r = (f32(0.03 + 0.18 * $sky * $sky)) x $w;
        my @g = (f32(0.01 + 0.05 * $sky)) x $w;
        my @b = (f32(0.08 + 0.22 * $sky)) x $w;

        # sun: rows in its box, then pixels in its box, then the circle
        my $dyc = f32($y - $sun_y);
        if ($dyc > -$sun_r && $dyc < $sun_r && $y < f32($horizon + 2)
            && !($y > f32($sun_y - f32($sun_r * K0_45)) && $y % 9 < 4)) {
            my $u = clamp01(f32(f32($y - f32($sun_y - $sun_r)) / f32(2 * $sun_r)));
            my @sun = (1, f32(0.95 - 0.7 * $u), f32(0.25 + 0.55 * $u));
            my $dyc2 = f32($dyc * $dyc);
            my @in = grep { $xc[$_] > -$sun_r && $xc[$_] < $sun_r } @X;
            my @d = f32(map { sqrt } f32(map { $_ + $dyc2 } f32(map { $_ * $_ } @xc[@in])));
            my @k = grep { $d[$_] < $sun_r } 0 .. $#in;
            my @px = @in[@k];
            my $soft = f32($sun_r * K0_025);
            my @edge = map { clamp01($_) } f32(map { $_ / $soft } f32(map { $sun_r - $_ } @d[@k]));
            for ([\@r, $sun[0]], [\@g, $sun[1]], [\@b, $sun[2]]) {
                my ($c, $s) = @$_;
                # mix: c + (sun - c) * edge
                my @v = @$c[@px];
                my @dv = f32(map { f32($s - $v[$_]) * $edge[$_] } 0 .. $#px);
                @$c[@px] = f32(map { $v[$_] + $dv[$_] } 0 .. $#px);
            }
        }

        if ($y > $horizon) {
            # GRID: the floor
            my $dz = f32($y - $horizon);
            my $z = f32(f32($h * K0_55) / $dz);
            my $wz = f32(f32($z * K2_5) + f32($t * K5_5));
            my $kx = f32(f32(f32($z / f32($w * 0.5)) * $asp) * 2);
            my $fade_x = f32(clamp01(f32(f32(f32(1 / $kx) - 1.5) / 2)));
            # a line narrower than a pixel is widened to one and dimmed by
            # the area it actually covers
            my $period = f32(f32($dz * $dz) / f32(1.375 * $h));
            my $lw_z = f32(K0_014 + f32(K0_024 / $z));
            my $amp_z = 1;
            my $min_w = f32(0.5 / $period);
            ($amp_z, $lw_z) = (f32($lw_z / $min_w), $min_w) if $lw_z < $min_w;
            my $line_z = f32(glow(mod1($wz), $lw_z) * $amp_z);
            $line_z = f32($line_z * f32(clamp01(f32(f32($period - 1.5) / 2))));
            my $fog = f32(clamp01(f32(1 / f32(1 + f32(f32($z * $z) * K0_004)))));
            $line_z = f32($line_z * $fog);
            my ($fr, $fg, $fb) = (K0_02, K0_01, K0_06);
            my $haze = clamp01(f32($dz / f32($h * K0_12)));
            if ($haze < 1) {
                $fr = f32($fr + f32(0.25 * (1 - $haze)));
                $fg = f32($fg + f32(0.05 * (1 - $haze)));
                $fb = f32($fb + f32(0.35 * (1 - $haze)));
            }
            $fr = f32($fr + f32(K0_55 * $line_z));
            $fg = f32($fg + f32(K0_35 * $line_z));
            $fb = f32($fb + f32(K0_75 * $line_z));

            # @excerpt GRID
            # how far each ray slides sideways between rows: the line must be
            # at least that wide, and dimmed by the same ratio
            my $w_min = f32(f32(2 * $lw_x) / $kx);
            my @slide = f32(map { abs($_) / $dz } @xc);
            my @w_px = map { my $v = $_ > $w_min ? $_ : $w_min; $v < 1 ? 1 : $v } @slide;
            my @f = map { mod1($_) } f32(map { $_ + K0_37 } f32(map { $_ * $kx } @xc));
            my @lw = f32(map { $_ * 0.5 } f32(map { $_ * $kx } @w_px));
            my @dim = f32(map { $w_min / $_ } @w_px);
            my @line = f32(map { $_ * $fade_x } f32(map { glow($f[$_], $lw[$_]) * $dim[$_] } @X));
            @line = map { $line_z > $_ ? $line_z : $_ } @line;
            # the floor colour, its row glow swapped for the brighter line
            for ([\@r, $fr, K0_55], [\@g, $fg, K0_35], [\@b, $fb, K0_75]) {
                my ($c, $base, $k) = @$_;
                my $row = f32($base - f32($k * $line_z));
                @$c = f32(map { $row + $_ } f32(map { $k * $_ } @line));
            }
            # @end
        }
        push @pix, map { from_float($r[$_], $g[$_], $b[$_]) } @X;
    }
    return \@pix;
}

1;
