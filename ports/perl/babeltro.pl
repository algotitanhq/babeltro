# babeltro.pl: the port's entry points, the contract of spec/ABI.md spelt
# in Perl. port.js boots the interpreter, puts this file and the modules in
# its virtual filesystem, adds their directory to @INC and calls these subs.

use strict;
use warnings;
use Starfield;
use Tunnel;
use Plasma;
use Rotozoom;
use Metaballs;
use Grid;
use Fire;
use Mandelbrot;
use Finale;

my @SCENES = qw(Starfield Tunnel Plasma Rotozoom Metaballs Grid Fire Mandelbrot Finale);
my ($W, $H, $fx);

sub bb_init  { ($W, $H) = @_; return }
sub bb_start { my $class = $SCENES[ $_[0] ] or die "no scene $_[0] in Perl\n"; $fx = $class->new($W, $H); return }
sub bb_step  { $fx->step($_[0]); return }

# bb_render packs the frame into $FB, one string of w*h little-endian u32
# (the bytes of an ImageData), and returns the address of that string's
# bytes: pack 'p' is Perl's address-of, and on wasm32 an address is an
# offset into the linear memory port.js can read. $FB is global so the
# bytes stay put until the next frame.
our $FB;
sub bb_render { $FB = pack 'V*', @{ $fx->render($_[0]) }; unpack 'L', pack 'p', $FB }

1;
