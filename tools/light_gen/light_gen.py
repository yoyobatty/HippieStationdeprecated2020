#!/usr/bin/env python3
"""Draws hippiestation/icons/effects/light_glow.dmi: the soft pool of light that fires, alarms and the supermatter pulse
(hippiestation/code/modules/lighting/light_glow.dm). White with a smooth fall-off in its alpha; the game colours it.

    python tools/light_gen/light_gen.py          writes the sheet
    python tools/light_gen/light_gen.py check    fails if the committed sheet differs
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'mapmerge2'))
from dmi import Dmi  # noqa: E402

SIZE = 224  # seven tiles across. LIGHT_GLOW_SIZE in the .dm centres it by this
OUT = os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'light_glow.dmi')


def soft():
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    r = np.hypot(xx - SIZE / 2 + 0.5, yy - SIZE / 2 + 0.5) / (SIZE / 2)
    # bright in the middle, most of it gone by half way out, nothing at the edge
    fall = np.exp(-(r / 0.42) ** 2) * np.clip(1 - r, 0, 1) ** 0.5
    rng = np.random.default_rng(7)
    alpha = np.clip(np.floor(fall * 255 + 0.5 + rng.uniform(-0.5, 0.5, fall.shape)), 0, 255).astype(np.uint8)
    rgba = np.dstack([np.full_like(alpha, 255)] * 3 + [alpha])
    return Image.fromarray(rgba, 'RGBA')


def build(path):
    dmi = Dmi(SIZE, SIZE)
    dmi.state('soft').frame(soft())
    dmi.to_file(path)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'check':
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            build(os.path.join(tmp, 'light_glow.dmi'))
            if open(os.path.join(tmp, 'light_glow.dmi'), 'rb').read() != open(OUT, 'rb').read():
                print('stale light_glow.dmi (run tools/light_gen/light_gen.py)')
                sys.exit(1)
        print('light_glow.dmi matches the generator')
    else:
        build(OUT)
        print('%s  %d KB' % (os.path.relpath(OUT, ROOT), os.path.getsize(OUT) // 1024))
