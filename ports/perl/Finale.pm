# Finale: the closing card. The logo with its gradient, outline and
# reflection, the subtitle and the numbers. A translation of
# go/internal/fx/finale.go as the browser lab builds it: no HUD panel
# (PanelBottom nil) and the one-thread tag.

package Finale;
use strict;
use warnings;
use FMath;
use Canvas;

our $LANG = 'PERL';
our $TAG = 'ONE THREAD - NO GPU - NO SHADER';
my @LINES = ('0 GPU SHADERS', '0 EXTERNAL MODULES', '0 ASSETS ON DISK');

use constant { K0_15 => f32(0.15), K0_85 => f32(0.85), K0_90 => f32(0.90), K0_55 => f32(0.55),
               K0_34 => f32(0.34), K1_6 => f32(1.6), K0_32 => f32(0.32), K0_45 => f32(0.45),
               K0_02 => f32(0.02), K0_09 => f32(0.09), K0_01 => f32(0.01), K0_06 => f32(0.06),
               K0_14 => f32(0.14), K0_88 => f32(0.88), K0_12 => f32(0.12), K0_52 => f32(0.52),
               K0_9 => f32(0.9) };

sub new {
    my ($class, $w, $h) = @_;
    my $f = bless { w => $w, h => $h }, $class;
    my $rng = 0xF1A1E;
    for (1 .. 260) {
        my ($x, $y, $b) = (rng_f32(\$rng), rng_f32(\$rng), rng_f32(\$rng));
        push @{ $f->{stars} }, [$x, $y, f32(K0_15 + f32($b * K0_85))];
    }

    # the layout: Go's integer arithmetic, int() where Go divides
    $f->{sub} = "EVERY PIXEL IS $LANG";
    $f->{sub_scale} = int($w / 300) || 1;
    my $sub_h = Canvas::text_height($f->{sub_scale});
    $f->{stats_scale} = int($w / 440) || 1;
    $f->{stat_gap} = int(Canvas::text_height($f->{stats_scale}) * 3 / 2);
    $f->{tag_scale} = $f->{stats_scale} + 1;
    my $tag_h = Canvas::text_height($f->{tag_scale});
    my $gap = int($h / 48);
    my $top = int($h / 40);
    my $bottom = int f32($h * K0_90);
    my $fixed = $sub_h + 3 * $f->{stat_gap} + $tag_h + 4 * $gap;
    # the wordmark needs 10.5 blocks of height, and at most 45% of the width
    my $scale = int(($bottom - $top - $fixed) * 2 / 21);
    my $lim = int(int($w * 9 / 20) / Canvas::text_width($LANG, 1));
    $scale = $lim if $scale > $lim;
    $scale = 3 if $scale < 3;
    $f->{logo_scale} = $scale;
    my $logo_w = Canvas::text_width($LANG, $scale);
    $f->{text_h} = Canvas::text_height($scale);
    $f->{refl_h} = int($f->{text_h} / 2);
    $f->{logo_x} = int(($w - $logo_w) / 2);
    my $block_h = $f->{text_h} + $f->{refl_h} + $fixed;
    $f->{logo_y} = $top + int(($bottom - $top - $block_h) / 2);
    $f->{floor_y} = $f->{logo_y} + $f->{text_h};
    $f->{sub_y} = $f->{floor_y} + $f->{refl_h} + $gap;
    $f->{stats_y} = $f->{sub_y} + $sub_h + $gap;
    $f->{tag_y} = $f->{stats_y} + 3 * $f->{stat_gap} + $gap;
    $f->{sub_x} = int(($w - Canvas::text_width($f->{sub}, $f->{sub_scale})) / 2);
    $f->{tag_x} = int(($w - Canvas::text_width($TAG, $f->{tag_scale})) / 2);

    # the pool of light: an ellipse about 1.6x wider than tall
    my $gx = $f->{glow_x} = f32($w * 0.5);
    my $gy = $f->{glow_y} = f32($f->{logo_y} + f32($f->{text_h} * K0_55));
    my $gr = $f->{glow_r} = f32($w * K0_34);
    $f->{dx2} = [ f32(map { $_ * $_ } f32(map { $_ * K1_6 } f32(map { $_ / $gr } f32(map { $_ - $gx } 0 .. $w - 1)))) ];
    my ($span_x, $span_y) = (int f32($gr / K1_6), int $gr);
    @$f{qw(box_x0 box_x1 box_y0 box_y1)} = (int($gx) - $span_x, int($gx) + $span_x, int($gy) - $span_y, int($gy) + $span_y);
    return $f;
}

sub step { }

sub render {
    my ($f, $n) = @_;
    my ($w, $h) = @$f{qw(w h)};
    my $t = $n / 60;
    my $fb = Canvas->new($w, $h);
    my $pix = $fb->{pix};
    my ($cx, $cy) = f32($w * 0.5, $h * 0.5);

    # background, pass 1: a vertical ramp, one colour per row
    my $inv_h = f32(1 / $h);
    for my $y (0 .. $h - 1) {
        my $u = f32($y * $inv_h);
        my $ny = f32(f32($y - $cy) / $cy);
        my $vig = f32(1 - f32(f32(K0_32 * $ny) * $ny));
        $vig = K0_45 if $vig < K0_45;
        my $r = f32(f32(K0_02 + f32(f32(K0_09 * $u) * $u)) * $vig);
        my $g = f32(f32(K0_01 + f32(K0_02 * $u)) * $vig);
        my $b = f32(f32(K0_06 + f32(K0_14 * $u)) * $vig);
        push @$pix, (from_float($r, $g, $b)) x $w;
    }

    # background, pass 2: the pool of light, only where it reaches
    my ($by0, $by1, $bx0, $bx1) = @$f{qw(box_y0 box_y1 box_x0 box_x1)};
    $by0 = 0 if $by0 < 0;
    $by1 = $h if $by1 > $h;
    $bx0 = 0 if $bx0 < 0;
    $bx1 = $w if $bx1 > $w;
    my $pulse = f32(K0_88 + f32(K0_12 * f32(sin($t * 2.2))));
    for my $y ($by0 .. $by1 - 1) {
        my $dy = f32(f32($y - $f->{glow_y}) / $f->{glow_r});
        my $dy2 = f32($dy * $dy);
        next if $dy2 >= 1;
        my @x = grep { f32($f->{dx2}[$_] + $dy2) < 1 } $bx0 .. $bx1 - 1;
        my @g = f32(map { 1 - $_ } f32(map { $f->{dx2}[$_] + $dy2 } @x));
        @g = f32(map { $_ * f32($_ * $pulse) } @g);
        for my $k (0 .. $#x) {
            my $i = $y * $w + $x[$k];
            my $p = $pix->[$i];
            my @c = map { int f32($g[$k] * $_) } 120, 22, 100;
            my @s = map { my $v = ($p >> 8 * $_ & 0xFF) + $c[$_]; $v > 255 ? 255 : $v } 0 .. 2;
            $pix->[$i] = Canvas::rgb(@s);
        }
    }

    # stars, twinkling slowly
    my $i = 0;
    for my $s (@{ $f->{stars} }) {
        my ($sx, $sy) = (int f32($s->[0] * $w), int f32($s->[1] * $h));
        my $tw = f32(K0_55 + f32(K0_45 * f32(sin($t * 1.7 + $i++ * 0.7))));
        $fb->additive($sy * $w + $sx, 0xFF40306A, int f32(f32(70 * $s->[2]) * $tw))
            if $sy >= 0 && $sy < $h && $sx >= 0 && $sx < $w;
    }

    # the polished floor line the reflection lands on
    my $fy = $f->{floor_y};
    if ($fy >= 0 && $fy < $h) {
        my $half = f32($w * K0_52);
        for my $x (0 .. $w - 1) {
            my $fade = f32(1 - f32(abs(f32($x - $cx)) / $half));
            next if $fade <= 0;
            my $glow = f32(f32($fade * $fade) * K0_9);
            my $p = $pix->[$fy * $w + $x];
            my @s = map { my $v = f32(($p >> 8 * $_ & 0xFF) + f32((210, 110, 230)[$_] * $glow)); $v > 255 ? 255 : int $v } 0 .. 2;
            $pix->[$fy * $w + $x] = Canvas::rgb(@s);
        }
    }

    # @excerpt FINALE
    # the logo: the letters bounce off the floor line, never below it
    my $scale = $f->{logo_scale};
    my @offs = map { int((sin($t * 2.4 + $_ * 0.75) - 1) * $scale / 6) } 0 .. length($LANG) - 1;
    my ($top, $mid, $bot) = (0xFFFFF6E8, 0xFF7C9CFF, 0xFF582080);    # cream, rose, violet
    # reflection first, so the wordmark sits on top of its own light
    $fb->draw_text_reflect($f->{logo_x}, $fy, $LANG, $scale, $top, $bot, \@offs, 125, $f->{refl_h});
    # a one-pixel dark edge keeps the letters off the background
    $fb->draw_text_outline($f->{logo_x}, $f->{logo_y}, $LANG, $scale, 0xFF200A18, \@offs);
    $fb->draw_text_gradient($f->{logo_x}, $f->{logo_y}, $LANG, $scale, $top, $mid, $bot, \@offs, 1);
    # @end

    # subtitle with rules either side
    my $sub_w = Canvas::text_width($f->{sub}, $f->{sub_scale});
    my $len = int($sub_w / 3);
    my $ly = $f->{sub_y} + int(Canvas::text_height($f->{sub_scale}) / 2);
    $fb->hline($f->{sub_x} - $len - 14, $ly, $len, 0xFF9050A0);
    $fb->hline($f->{sub_x} + $sub_w + 14, $ly, $len, 0xFF9050A0);
    $fb->draw_text($f->{sub_x}, $f->{sub_y}, $f->{sub}, $f->{sub_scale}, 0xFFF0E0FF);

    # the closing numbers, and the punchline
    for my $k (0 .. $#LINES) {
        my $lw = Canvas::text_width($LINES[$k], $f->{stats_scale});
        $fb->draw_text(int(($w - $lw) / 2), $f->{stats_y} + $k * $f->{stat_gap}, $LINES[$k], $f->{stats_scale}, 0xFFC0B0E0);
    }
    $fb->draw_text($f->{tag_x}, $f->{tag_y}, $TAG, $f->{tag_scale}, 0xFFB0E0FF);
    return $pix;
}

1;
