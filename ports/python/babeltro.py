"""The Python port of babeltro, driven from port.js (see spec/ABI.md).

Every effect is a class with Go's fx.Effect shape: resize(w, h) builds the
tables tied to resolution, prepare(state) does the per-frame set-up,
draw(fb) writes every pixel of fb, an (h, w) uint32 array.
"""

from typing import NamedTuple

import numpy as np

from finale import Finale
from fire import Fire
from grid import Grid
from mandelbrot import Mandelbrot
from metaballs import Metaballs
from plasma import Plasma
from rotozoom import Rotozoom
from starfield import Starfield
from tunnel import Tunnel

LANG = "PYTHON"

SCENES = {
    0: Starfield,
    1: Tunnel,
    2: Plasma,
    3: Rotozoom,
    4: Metaballs,
    5: Grid,
    6: Fire,
    7: Mandelbrot,
    8: lambda: Finale(LANG),
}


class State(NamedTuple):
    t: float  # seconds since the demo started
    beat: float  # seconds since this scene started
    dt: float  # seconds since the previous frame
    frame: int


fb = np.zeros((0, 0), dtype=np.uint32)
effect = None


def init(w, h):
    """Allocates the w×h framebuffer; port.js reads it in place."""
    global fb
    fb = np.zeros((h, w), dtype=np.uint32)
    return fb


def start(scene):
    """Begins scene from a fresh effect, so stateful scenes replay the same history."""
    global effect
    effect = SCENES[scene]()
    effect.resize(fb.shape[1], fb.shape[0])


def step(n):
    """Picks rung n of the scene's optimisation ladder; 0 is the default."""
    if hasattr(effect, "set_step"):
        effect.set_step(n)


def render(n):
    """Draws frame n. Time comes from n at a fixed 60 Hz step, never a clock."""
    t = n / 60
    effect.prepare(State(t, t, 1 / 60, n))
    effect.draw(fb)
