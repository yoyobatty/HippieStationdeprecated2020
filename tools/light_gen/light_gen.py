#!/usr/bin/env python3
"""Draws two small sheets of effect art, both white so the game can colour them:
  hippiestation/icons/effects/light_glow.dmi   the soft pool of light that fires, alarms and the supermatter pulse (light_glow.dm)
  hippiestation/icons/effects/particle_fx.dmi  the shapes particles are made of (particle_fx.dm)

    python tools/light_gen/light_gen.py          writes the sheets
    python tools/light_gen/light_gen.py check    fails if a committed sheet differs
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


PARTICLE = 16  # the particle sprites' sheet: small white shapes the particle sets colour and scale (particle_fx.dm)
PARTICLE_OUT = os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'particle_fx.dmi')


def blob(radius, hard=False):
    yy, xx = np.mgrid[0:PARTICLE, 0:PARTICLE].astype(float)
    r = np.hypot(xx - PARTICLE / 2 + 0.5, yy - PARTICLE / 2 + 0.5)
    alpha = (r <= radius).astype(float) if hard else np.exp(-(r / radius) ** 2)
    alpha = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([np.full_like(alpha, 255)] * 3 + [alpha]), 'RGBA')


def build_particles(path):
    dmi = Dmi(PARTICLE, PARTICLE)
    dmi.state('dot').frame(blob(1.3))     # an ember, a spark, a mote
    dmi.state('puff').frame(blob(5.0))    # steam, breath, dust
    dmi.state('chip').frame(blob(1.6, hard=True))  # debris, a drop of blood
    dmi.to_file(path)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'check':
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            build(os.path.join(tmp, 'light_glow.dmi'))
            build_particles(os.path.join(tmp, 'particle_fx.dmi'))
            for name, out in (('light_glow.dmi', OUT), ('particle_fx.dmi', PARTICLE_OUT)):
                if open(os.path.join(tmp, name), 'rb').read() != open(out, 'rb').read():
                    print('stale %s (run tools/light_gen/light_gen.py)' % name)
                    sys.exit(1)
        print('light_glow.dmi and particle_fx.dmi match the generator')
    else:
        build(OUT)
        build_particles(PARTICLE_OUT)
        for out in (OUT, PARTICLE_OUT):
            print('%s  %d KB' % (os.path.relpath(out, ROOT), max(1, os.path.getsize(out) // 1024)))
