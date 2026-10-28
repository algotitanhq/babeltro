# Tunnel: every pixel mapped to polar coordinates once, at resize time; per
# frame, a few table lookups and a palette read. A translation of
# go/internal/fx/tunnel.go, ladder included:
#   step 1  distance and angle computed for every pixel, every frame
#   step 2  (and 0, the default) both read from tables built at resize
#
# Rows are lists; f32 rounds a list after each float32 operation.

package Tunnel;
use strict;
use warnings;
use FMath;

use constant { K2_2 => f32(2.2), K0_02 => f32(0.02), K2PI => f32(2 * PI),
               K0_16 => f32(0.16), K0_09 => f32(0.09), K0_32 => f32(0.32),
               K0_55 => f32(0.55), K0_45 => f32(0.45), K0_7 => f32(0.7) };

sub new {
    my ($class, $w, $h) = @_;
    my $self = bless { w => $w, h => $h, step => 0, pal => $ICE }, $class;
    # scale with the diagonal so the rings look the same at any resolution
    @$self{qw(scale soft)} = f32(($w + $h) * K2_2, ($w + $h) * K0_02);
    @$self{qw(cx cy)} = ($w / 2, $h / 2);
    # the tables: one list of depths and one of angles per row
    for my $y (0 .. $h - 1) {
        my ($depth, $angle) = $self->polar($y);
        push @{ $self->{depth} }, $depth;
        push @{ $self->{angle} }, $angle;
    }
    return $self;
}

sub step { $_[0]{step} = $_[1] }

# polar Y returns row y's depth (falls off as 1/r: large at the centre,
# small at the edge) and angle (atan2 as a fraction of a turn, [0,1)), as
# two list references: one row of fmath.DistInvTab and fmath.Atan2Tab.
sub polar {
    my ($self, $y) = @_;
    my ($cx, $scale, $soft) = @$self{qw(cx scale soft)};
    # @excerpt TUNNEL/1
    # step 1 calls this for every row of every frame: a square root, a
    # division and an atan2 per pixel, for values that never change
    my $dy = f32($y - $self->{cy});
    my $dy2 = f32($dy * $dy);
    my @dx = f32(map { $_ - $cx } 0 .. $self->{w} - 1);
    my @r = f32(map { $_ + $soft } f32(map { sqrt } f32(map { $_ + $dy2 } f32(map { $_ * $_ } @dx))));
    my @depth = f32(map { $scale / $_ } @r);
    my @angle = f32(map { $_ + 0.5 } f32(map { $_ / K2PI } f32(map { atan2 $dy, $_ } @dx)));
    # @end
    return (\@depth, \@angle);
}

sub render {
    my ($self, $n) = @_;
    my ($w, $h, $pal) = @$self{qw(w h pal)};
    my $t = f32($n / 60);
    my ($adv, $spin) = f32($t * 3, $t * 0.25);
    my @X = 0 .. $w - 1;
    my @pix;
    for my $y (0 .. $h - 1) {
        my ($depth, $angle) = $self->{step} == 1
            ? $self->polar($y)
            : ($self->{depth}[$y], $self->{angle}[$y]);
        # @excerpt TUNNEL
        my @u = f32(map { $_ + $adv } @$depth);    # scroll towards the viewer
        # rings along the depth axis
        my @ring = tsin01(f32(map { $_ * K0_16 } @u));
        # spokes that twist as they recede: v*12 + u*0.09 + spin
        my @v12 = f32(map { $_ * 12 } @$angle);
        my @u09 = f32(map { $_ * K0_09 } @u);
        my @twist = f32(map { $_ + $spin } f32(map { $v12[$_] + $u09[$_] } @X));
        my @spoke = tsin01(@twist);
        my @r55 = f32(map { $_ * K0_55 } @ring);
        my @s45 = f32(map { $_ * K0_45 } @spoke);
        my @val = f32(map { $r55[$_] + $s45[$_] } @X);
        # brick checker gives the walls their structure
        my @u32 = f32(map { $_ * K0_32 } @u);
        for (grep { (int($u32[$_]) + int($twist[$_])) & 1 } @X) {
            $val[$_] = f32(-$val[$_] * K0_7);
        }
        my @fog = f32(map { 1 / $_ } f32(map { 1 + $_ } f32(map { $_ * K0_02 } @u)));
        my @lum = f32(map { $_ + 0.5 } f32(map { $_ * 0.5 } @val));
        @lum = f32(map { $lum[$_] * $fog[$_] } @X);
        # a cold rim on the brightest ridges
        push @pix, map { my $i = int; $pal->[$i > 255 ? 255 : $i < 0 ? 0 : $i] } f32(map { $_ * 300 } @lum);
        # @end
    }
    return \@pix;
}

1;
