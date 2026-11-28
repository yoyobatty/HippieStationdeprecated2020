"""Draws the sky's weather art into sky_weather.dmi (hippiestation/code/_onclick/hud/sky_weather.dm). LOCAL ONLY.

Usage:
  python tools/sky_gen/v2/weather.py hippiestation/icons/effects/sky_weather.dmi [--preview data/previews/sky_weather.png]

Written for the Paradise port of the sky (Paradise tools/perf_bench/sky_v2/gen_weather.py, 2026-11-27) and brought back here.

ash_veil    480 px: a patchy dark ash haze over Lavaland's disc (R 128, centred like the planet sprites)
ash_swirl   192 px: an ash cyclone, spiral arms round a dark eye, circular so it can turn in place inside the disc
aurora1/2   256 px: aurora curtains, rays rising from a wavy green hem through cyan to a violet top (drawn additively)
rad_veil    480 px: seamless soft green noise that tiles, for the radiation storm's shimmer
--preview draws them over a dark sky and Lavaland (the sky_bodies.dmi next to the sheet). numpy, Pillow. Seeded.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bodies as b  # noqa: E402  (puts tools/sky_gen, and through it tools/mapmerge2, on the path)
from dmi import Dmi  # noqa: E402


def tile_noise(n, seed, freq, octaves=4):
    """Seamless 2D fractal noise on an n x n tile, roughly 0..1: noise read on a torus in 4D folded into 3D samples."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    a, c = xx / n * 2 * np.pi, yy / n * 2 * np.pi
    # two circles: (cos a, sin a) and (cos c, sin c), squeezed into 3D points with a twist so it doesn't repeat inside the tile
    p = np.stack([np.cos(a) + 0.5 * np.cos(c), np.sin(a) + 0.5 * np.sin(c), np.sin(c) * 0.9]).reshape(3, -1)
    v = b.fbm(p, seed, freq, octaves)
    return b.stretch(v).reshape(n, n)


def to_image(rgb, alpha):
    out = np.zeros(alpha.shape + (4,))
    out[..., :3] = np.clip(rgb, 0, 1)
    out[..., 3] = np.clip(alpha, 0, 1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def ash_veil(n=480, R=128):
    yy, xx = np.mgrid[0:n, 0:n].astype(float) + 0.5
    dx, dy = xx - n / 2, n / 2 - yy
    r = np.hypot(dx, dy) / R
    inside = np.clip((1 - r) * R / 2, 0, 1)
    p = np.stack([dx / R, dy / R, np.sqrt(np.clip(1 - r * r, 0, 1))]).reshape(3, -1)
    streaks = b.stretch(b.fbm(p * np.array([[1.0], [3.5], [1.0]]), 501, 2.2, 5)).reshape(n, n)
    puffs = b.stretch(b.fbm(p, 502, 4.0, 4)).reshape(n, n)
    dens = np.clip(0.35 + 0.5 * streaks * puffs, 0, 1) * inside
    col = np.zeros((n, n, 3)) + np.array([0.20, 0.16, 0.13])
    col *= (0.8 + 0.4 * puffs)[..., None]
    return to_image(col, dens * 0.75)


def ash_swirl(n=192):
    yy, xx = np.mgrid[0:n, 0:n].astype(float) + 0.5
    dx, dy = xx - n / 2, n / 2 - yy
    rr = np.hypot(dx, dy) / (n / 2)
    ang = np.arctan2(dy, dx)
    arms = 0.5 + 0.5 * np.sin(3 * ang + 9 * rr)  # three spiral arms winding in
    p = np.stack([dx / n * 3, dy / n * 3, np.zeros_like(dx)]).reshape(3, -1)
    grain = b.stretch(b.fbm(p, 503, 3.0, 4)).reshape(n, n)
    dens = arms * (0.6 + 0.4 * grain)
    dens *= np.clip((1 - rr) * 4, 0, 1) * np.clip(rr * 6, 0.25, 1)  # soft edge, a thinner eye
    col = np.zeros((n, n, 3)) + np.array([0.42, 0.35, 0.29])
    col *= (0.7 + 0.5 * grain * arms)[..., None]
    return to_image(col, dens * 0.85)


def aurora(seed, n=256):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(float) + 0.5
    u = xx / n
    hem = 0.62 + 0.08 * np.sin(u * 2 * np.pi * rng.uniform(1.2, 1.8) + rng.uniform(0, 6)) + 0.03 * np.sin(u * 2 * np.pi * 4.3)
    h = (hem * n - yy) / n  # height above the hem, in sprite heights
    rays = b.stretch(b.fbm(np.stack([u * 40, np.zeros_like(u), np.zeros_like(u)]).reshape(3, -1), seed, 1.0, 3)).reshape(n, n)
    rise = np.where(h > 0, np.exp(-h / (0.18 + 0.2 * rays)), np.exp(h / 0.015))
    side = np.clip(np.sin(u * np.pi) * 1.4, 0, 1)
    top = np.clip(yy / n / 0.2, 0, 1) ** 1.5  # rays fade out before the sprite's top edge
    glow = rise * (0.35 + 0.65 * rays) * side * top
    green = np.array([0.45, 1.0, 0.55])
    cyan = np.array([0.35, 0.95, 0.95])
    violet = np.array([0.7, 0.4, 1.0])
    t = np.clip(h / 0.35, 0, 1)[..., None]
    col = np.where(t < 0.5, green * (1 - t * 2) + cyan * (t * 2), cyan * (2 - t * 2) + violet * (t * 2 - 1))
    return to_image(col, np.clip(glow * 1.2, 0, 1))


def rad_veil(n=480):
    noise = tile_noise(n, 504, 1.6, 4)
    fine = tile_noise(n, 505, 4.0, 3)
    dens = np.clip((noise - 0.35) * 1.6, 0, 1) * (0.7 + 0.3 * fine)
    col = np.zeros((n, n, 3)) + np.array([0.45, 1.0, 0.35])
    return to_image(col, dens * 0.55)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sheet')
    ap.add_argument('--preview')
    args = ap.parse_args()
    states = {'ash_veil': ash_veil(), 'ash_swirl': ash_swirl(), 'aurora1': aurora(611), 'aurora2': aurora(612), 'rad_veil': rad_veil()}
    # one sheet needs one sprite size: everything goes on 480 px, smaller art centred
    d = Dmi(480, 480)
    for name, image in states.items():
        canvas = Image.new('RGBA', (480, 480), (0, 0, 0, 0))
        canvas.alpha_composite(image, ((480 - image.width) // 2, (480 - image.height) // 2))
        d.state(name).frame(canvas)
    d.to_file(args.sheet)
    print(args.sheet, list(states))
    if args.preview:
        pic = Image.new('RGBA', (480 * 3, 480), (6, 7, 14, 255))
        planet = [s for s in Dmi.from_file(os.path.join(os.path.dirname(args.sheet), 'sky_bodies.dmi')).states if s.name == 'planet_lava'][0]
        pic.alpha_composite(planet.get_frame().convert('RGBA'), (0, 0))
        pic.alpha_composite(states['ash_veil'], (0, 0))
        pic.alpha_composite(states['ash_swirl'], (240 - 96 - 40, 240 - 96 + 30))
        for i, name in enumerate(['aurora1', 'aurora2']):
            big = states[name].resize((480, 480))
            pic.alpha_composite(big, (480, 0) if i == 0 else (480, 120))
        pic.alpha_composite(states['rad_veil'], (960, 0))
        pic.save(args.preview)
        print('preview:', args.preview)


if __name__ == '__main__':
    sys.exit(main())
