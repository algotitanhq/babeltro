# Plasma: four summed sine fields, the oldest trick in the demoscene book.
# A translation of go/internal/fx/plasma.go, ladder included:
#   step 1  sin() four times per pixel
#   step 2  the sine table four times per pixel
#   step 3  (and 0, the default) three of the four terms in 1D tables
#           rebuilt once per frame, one table lookup left per pixel
#
# Every rung works on a whole row at once, as lists: map does the
# arithmetic, f32 rounds the list to float32 after each operation, the way
# Go's float32 code rounds after each operation.

package Plasma;
use strict;
use warnings;
use FMath;

# Go's float32 constants: an untyped constant meeting a float32 becomes one
use constant { K1_3 => f32(1.3), K1_1 => f32(1.1), K0_8 => f32(0.8),
               K1_35 => f32(1.35), K0_85 => f32(0.85), K2_6 => f32(2.6) };

sub new {
    my ($class, $w, $h) = @_;
    my $self = bless { w => $w, h => $h, step => 0, pal => $SUNSET }, $class;
    # the radial term's distance, once per resolution
    my ($cx, $cy) = ($w * 0.5, $h * 0.5);
    my $k = f32(44 / ($w + $h));
    my @dx2 = f32(map { $_ * $_ } f32(map { $_ - $cx } 0 .. $w - 1));
    $self->{rad} = [ map {
        my $dy = f32($_ - $cy);
        my $dy2 = f32($dy * $dy);
        [ f32(map { $_ * $k } f32(map { sqrt } f32(map { $_ + $dy2 } @dx2))) ];
    } 0 .. $h - 1 ];
    return $self;
}

sub step { $_[0]{step} = $_[1] }

# render returns the frame's pixels, a list of 0xAABBGGRR numbers
sub render {
    my ($self, $n) = @_;
    my ($w, $h, $pal) = @$self{qw(w h pal)};
    my $t  = f32($n / 60);    # Go: float32(s.Beat)
    my $kx = f32(26 / $w);
    my $ky = f32(26 / $h);
    my @X  = 0 .. $w - 1;
    my $phase = f32($t * K2_6);
    my ($t13, $t11, $t08) = f32($t * K1_3, $t * K1_1, $t * K0_8);
    my @pix;

    if ($self->{step} == 1 || $self->{step} == 2) {
        my ($cx, $cy) = ($w * 0.5, $h * 0.5);
        my $kr = f32(44 / ($w + $h));
        if ($self->{step} == 1) {
            # @excerpt PLASMA/1
            for my $y (0 .. $h - 1) {
                my $dy = f32($y - $cy);
                my $dy2 = f32($dy * $dy);
                my @rad = f32(map { $_ * $kr } f32(map { sqrt }
                          f32(map { $_ + $dy2 } f32(map { $_ * $_ } f32(map { $_ - $cx } @X)))));
                # the four terms, every pixel, straight from the maths library
                my @a = f32(map { sin } f32(map { $_ + $t13 } f32(map { $_ * $kx } @X)));
                my @b = f32(map { sin } f32(map { $_ - $t11 } f32(map { $_ * K1_35 } f32(map { $y * $ky } @X))));
                my @c = f32(map { sin } f32(map { $_ + $t08 } f32(map { $_ * K0_85 } f32(map { ($_ + $y) * $kx } @X))));
                my @d = f32(map { sin } f32(map { $_ + $phase } @rad));
                # v = a + b + c + d, left to right, rounded after each addition
                my @v = f32(map { $a[$_] + $b[$_] } @X);
                @v = f32(map { $v[$_] + $c[$_] } @X);
                @v = f32(map { $v[$_] + $d[$_] } @X);
                push @pix, map { my $i = int; $pal->[$i < 0 ? 0 : $i > 255 ? 255 : $i] }
                           f32(map { $_ + 127.5 } f32(map { $_ * 36 } @v));
            }
            # @end
        } else {
            # @excerpt PLASMA/2
            for my $y (0 .. $h - 1) {
                my $dy = f32($y - $cy);
                my $dy2 = f32($dy * $dy);
                my @rad = f32(map { $_ * $kr } f32(map { sqrt }
                          f32(map { $_ + $dy2 } f32(map { $_ * $_ } f32(map { $_ - $cx } @X)))));
                # the same four terms, read from the sine table instead
                my @a = tsin(f32(map { $_ + $t13 } f32(map { $_ * $kx } @X)));
                my @b = tsin(f32(map { $_ - $t11 } f32(map { $_ * K1_35 } f32(map { $y * $ky } @X))));
                my @c = tsin(f32(map { $_ + $t08 } f32(map { $_ * K0_85 } f32(map { ($_ + $y) * $kx } @X))));
                my @d = tsin(f32(map { $_ + $phase } @rad));
                my @v = f32(map { $a[$_] + $b[$_] } @X);
                @v = f32(map { $v[$_] + $c[$_] } @X);
                @v = f32(map { $v[$_] + $d[$_] } @X);
                push @pix, map { my $i = int; $pal->[$i < 0 ? 0 : $i > 255 ? 255 : $i] }
                           f32(map { $_ + 127.5 } f32(map { $_ * 36 } @v));
            }
            # @end
        }
        return \@pix;
    }

    # the 1D tables, once per frame: three of the four terms
    my @sx  = tsin(f32(map { $_ + $t13 } f32(map { $_ * $kx } @X)));
    my @sy  = tsin(f32(map { $_ - $t11 } f32(map { $_ * K1_35 } f32(map { $_ * $ky } 0 .. $h - 1))));
    my @sxy = tsin(f32(map { $_ + $t08 } f32(map { $_ * K0_85 } f32(map { $_ * $kx } 0 .. $w + $h - 1))));
    my $rad = $self->{rad};

    # @excerpt PLASMA
    for my $y (0 .. $h - 1) {
        my $sy = $sy[$y];
        my @sxy_row = @sxy[$y .. $y + $w - 1];       # the diagonal term, shifted by y
        my @d = tsin(f32(map { $_ + $phase } @{ $rad->[$y] }));    # the one lookup left
        # v = sx + sy + sxy + d, left to right, rounded after each addition
        my @v = f32(map { $_ + $sy } @sx);
        @v = f32(map { $v[$_] + $sxy_row[$_] } @X);
        @v = f32(map { $v[$_] + $d[$_] } @X);
        # to a palette index: int() truncates like Go's, then clamp
        push @pix, map { my $i = int; $pal->[$i < 0 ? 0 : $i > 255 ? 255 : $i] }
                   f32(map { $_ + 127.5 } f32(map { $_ * 36 } @v));
    }
    # @end
    return \@pix;
}

1;
