"""The near dust, second pass: sparse lit grit (the user's ruling). A few dull specks close by, and a handful catching the sun,
which the game tints in the sky's colour (SSparallax.dust_art() in hippiestation/code/_onclick/hud/sky.dm). Both slide fast
(speed 5); each speck is drawn a touch drawn out along one drift, and the lit ones glint now and then as they tumble.

build_tiles() returns {state: PIL RGBA or [frames]}, 480 square tiles that wrap, for sky_events_dust.dmi (flyby.py build).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from sky_gen import TILE, splat, additive_image  # noqa: E402

DRIFT = np.radians(-28.0)  # the way the grit is drawn out (y down): all of it roughly one way, as if drifting past together
LIT_FRAMES = 8
# ~6.5 s a loop, kept to 8 frames (each is a whole 480 tile in the client's memory): three short glint frames between long
# still ones, each glinting speck on one of them, so nothing blinks on a beat
LIT_DELAYS = [13, 2, 11, 9, 2, 14, 2, 12]
GLINT_FRAMES = [1, 4, 6]


def smear(canvas, x, y, colour, core, length, angle):
    """A speck drawn out over a few pixels: bright at its head, thinning behind."""
    steps = max(1, int(length * 1.5))
    for s in range(1, steps):
        t = s / steps
        px = x - np.cos(angle) * length * t
        py = y - np.sin(angle) * length * t
        splat(canvas, int(round(px)) % TILE, int(round(py)) % TILE, colour, core * 0.5 * (1 - t) ** 1.5)
    splat(canvas, int(x) % TILE, int(y) % TILE, colour, core)


def grit(seed=1105, count=40):
    """The dull grit: one-pixel specks, faint and brownish grey, a few bigger and drawn out."""
    rng = np.random.default_rng(seed)
    canvas = np.zeros((TILE, TILE, 3))
    for k in range(count):
        x, y = rng.integers(0, TILE, 2)
        tone = np.array([0.86, 0.82, 0.76]) * rng.uniform(0.85, 1.05, 3)
        if k < 9:
            smear(canvas, x, y, tone, rng.uniform(0.22, 0.34), rng.uniform(2.0, 3.5), DRIFT + rng.normal(0, 0.25))
            splat(canvas, int(x), int(y), tone, 0.0, 0.04, 1.0)
        else:
            splat(canvas, int(x), int(y), tone, rng.uniform(0.12, 0.24))
    return canvas


def lit_specks(seed=1106, count=9):
    """Where the lit flakes are, how bright, and which frame each glints on (-1: never)."""
    rng = np.random.default_rng(seed)
    specks = []
    for k in range(count):
        x, y = rng.integers(0, TILE, 2)
        glint = GLINT_FRAMES[k // 2 % 3] if k % 2 == 0 else -1
        specks.append((int(x), int(y), rng.uniform(0.75, 1.0), rng.uniform(3.5, 6.5), DRIFT + rng.normal(0, 0.15), glint))
    return specks


def lit_frame(frame, specks):
    """One frame of the lit specks, white (tinted in game): each a bright head and a short drawn-out tail, the glinting one
    flaring with a tiny cross."""
    canvas = np.zeros((TILE, TILE, 3))
    white = np.array([1.0, 1.0, 1.0])
    for x, y, bright, length, angle, glint in specks:
        b = bright
        if frame == glint:
            b *= 1.6
            splat(canvas, x, y, white, 0.0, 0.25, 1.4, 0.7, 4)
        smear(canvas, x, y, white, b, length, angle)
        splat(canvas, x, y, white, 0.0, 0.22 * b, 0.9)
        for ox, oy, part in ((1, 0, 0.55), (0, 1, 0.45), (1, 1, 0.3)):  # a flake, not a point: nearer than any star
            splat(canvas, (x + ox) % TILE, (y + oy) % TILE, white, b * part)
    return canvas


def build_tiles():
    specks = lit_specks()
    return {
        'dust': additive_image(grit(), 1107),
        'dust_lit': [additive_image(lit_frame(f, specks), 1110 + f) for f in range(LIT_FRAMES)],
    }


DELAYS = {'dust_lit': LIT_DELAYS}
