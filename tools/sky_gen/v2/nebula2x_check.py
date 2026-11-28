#!/usr/bin/env python3
"""nebula2x_check.py: are nebula.py's 2x clouds the 1x clouds without the blocks?

    python tools/sky_gen/v2/nebula2x_check.py [STATE...]

Builds the theme states (billow1-6, veil1-2, haze, or the ones named) at scale 1 (480x480, which the game draws at 2x) and
scale 2 (960x960, drawn at 1x), both through 8 bit as the .dmi holds them, and prints per state:
    mean    scale 1's mean level (0-255, all channels), for scale
    diff    mean absolute difference (0-255) between scale 2 averaged down by 2 and scale 1
    broad   the same after blurring both by 2 scale-1 px: the big shapes, colours and density, without the fine detail
    seam    each 2x tile's step across the wrap (last row to first, last column to first) over the steps either side of
            it, the worse axis, then the largest such ratio anywhere inside the tile on that axis, and scale 1's wrap ratio:
            about 1 wraps cleanly; a bright edge lying along the wrap raises it (and scale 1's) without being a seam. The
            run fails if the wrap stands above both 1.5 and 1.2 x the inside's largest.
    speck   the largest single-pixel contrast at scale 2: max over pixels of |pixel - mean of its 8 neighbours| on
            luminance (0.299 R + 0.587 G + 0.114 B, 0-255), with its 99.9th percentile, the max over single channels, and
            scale 1's own max for reference (one 2x pixel is ~2.85 screen pixels in game; 1-px detail shimmers as the sky turns)
and writes data/previews/sky2x/nebula_check.png: a row per state through its first theme's tones (alpha 255): scale 1
drawn at 2x as the game does | scale 2 at 1x | a 160 px crop round the brightest part of each, at 3x (about screen size),
scale 1 above, scale 2 below.

Single process, about a minute (the scale-2 build is most of it). Nothing is installed into hippiestation/icons.
"""
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import nebula  # noqa: E402
import sky_gen as sg  # noqa: E402  (nebula.py puts it on the path)

OUT_DIR = os.path.join(nebula.ROOT, 'data', 'previews', 'sky2x')
LUMA = np.array([0.299, 0.587, 0.114])
CROP = 160  # game pixels
ZOOM = 3  # one game pixel is about 2.85 screen pixels


def as_array(image):
    """A built state's image as floats 0-255 (RGB)."""
    return np.asarray(image.convert('RGB'), dtype=float)


def down(arr, k=2):
    n = arr.shape[0] // k
    return arr.reshape(n, k, n, k, -1).mean(axis=(1, 3))


def blur_rgb(arr, sigma):
    return np.stack([sg.blur(arr[..., c], sigma) for c in range(arr.shape[2])], axis=2)


def seam_ratio(arr):
    """The step across the wrap (first row against last, first column against last) over the mean of the steps either
    side of it (rows -2|-1 and 0|1, likewise columns), on the worse axis; and the same ratio's largest value at every other
    row or column of that axis. Seamless: the wrap's ratio is about 1 and no bigger than the inside's (a bright edge lying
    along the wrap raises both); a seam stands well above."""
    worst = (0.0, 0.0)
    for axis in (0, 1):
        a = np.moveaxis(arr, axis, 0)
        step = np.mean(np.abs(np.roll(a, -1, axis=0) - a), axis=tuple(range(1, a.ndim)))  # step[i]: row i to row i + 1
        ratio = step / np.maximum(0.5 * (np.roll(step, 1) + np.roll(step, -1)), 1e-9)
        edge, inside = ratio[-1], ratio[:-1].max()  # step[-1] is the last row to the first: the wrap
        worst = max(worst, (edge, inside))
    return worst


def speck(field):
    """|pixel - mean of its 8 neighbours| per pixel (wrapping: the tiles repeat)."""
    around = sum(np.roll(field, (dy, dx), axis=(0, 1)) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx) / 8.0
    return np.abs(field - around)


def tones_for(state):
    for entries in nebula.THEMES.values():
        for name, tones, *_ in entries:
            if name == state:
                return tones
    return ('#c0301c', '#30d0c0', '#ffffff')


def tinted(arr, state):
    return np.clip(nebula.tint(arr / 255.0, tones_for(state), 255), 0, 1)


def centred_crop(img, cy, cx, size):
    """A size x size crop of a wrapping picture round (cy, cx)."""
    rolled = np.roll(img, (size // 2 - cy, size // 2 - cx), axis=(0, 1))
    return rolled[:size, :size]


def row_picture(state, one, two):
    """scale 1 at 2x (blocks) | scale 2 | crops round the brightest part at ZOOM, scale 1 over scale 2."""
    a = np.repeat(np.repeat(tinted(one, state), 2, axis=0), 2, axis=1)
    b = tinted(two, state)
    glow = sg.blur((b * LUMA).sum(axis=2), 6.0)
    cy, cx = np.unravel_index(np.argmax(glow), glow.shape)
    crops = [np.repeat(np.repeat(centred_crop(p, cy, cx, CROP), ZOOM, axis=0), ZOOM, axis=1) for p in (a, b)]
    gap = 8
    h = a.shape[0]
    side = CROP * ZOOM
    canvas = np.zeros((max(h, 2 * side + gap), h * 2 + side + gap * 2, 3))
    canvas[:h, :h] = a
    canvas[:h, h + gap:2 * h + gap] = b
    canvas[:side, 2 * (h + gap):] = crops[0]
    canvas[side + gap:2 * side + gap, 2 * (h + gap):] = crops[1]
    return canvas


def main():
    names = sys.argv[1:] or list(nebula.THEME_STATES)
    unknown = [s for s in names if s not in nebula.THEME_STATES]
    if unknown:
        print('not a theme state: %s (states: %s)' % (', '.join(unknown), ', '.join(nebula.THEME_STATES)))
        sys.exit(2)
    t = time.time()
    one = nebula.build_images(nebula.build_states(scale=1, only=names))
    t1 = time.time() - t
    t = time.time()
    two = nebula.build_images(nebula.build_states(scale=2, only=names))
    t2 = time.time() - t
    print('built %d states: scale 1 in %.1f s, scale 2 in %.1f s' % (len(names), t1, t2))
    print('%-8s %9s %6s %6s %6s | %-18s | %s' % ('state', 'size', 'mean', 'diff', 'broad', 'seam: wrap in 1x',
                                                'speck 2x: max p99.9 chan | 1x max'))
    rows, worst = [], []
    for s in names:
        a, b = as_array(one[s]), as_array(two[s])
        assert a.shape == (nebula.N, nebula.N, 3) and b.shape == (2 * nebula.N, 2 * nebula.N, 3), (s, a.shape, b.shape)
        small = down(b)
        diff = np.mean(np.abs(small - a))
        broad = np.mean(np.abs(blur_rgb(small, 2.0) - blur_rgb(a, 2.0)))
        seam, inside = seam_ratio(b)
        seam1, _ = seam_ratio(a)
        sp2 = speck((b * LUMA).sum(axis=2))
        sp1 = speck((a * LUMA).sum(axis=2))
        chan = max(speck(b[..., c]).max() for c in range(3))
        print('%-8s %4dx%-4d %6.1f %6.2f %6.2f | %5.2f %5.2f %5.2f | %6.1f %6.1f %6.1f | %6.1f' % (
            s, b.shape[1], b.shape[0], a.mean(), diff, broad, seam, inside, seam1, sp2.max(), np.percentile(sp2, 99.9),
            chan, sp1.max()))
        if seam > max(1.5, 1.2 * inside):
            worst.append('%s seam %.2f (inside up to %.2f)' % (s, seam, inside))
        rows.append(row_picture(s, a, b))
    os.makedirs(OUT_DIR, exist_ok=True)
    gap = 8
    sheet = np.zeros((sum(r.shape[0] for r in rows) + gap * (len(rows) - 1), max(r.shape[1] for r in rows), 3))
    y = 0
    for r in rows:
        sheet[y:y + r.shape[0], :r.shape[1]] = r
        y += r.shape[0] + gap
    im = Image.fromarray((np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')
    draw = ImageDraw.Draw(im)
    y = 0
    for s, r in zip(names, rows):
        draw.text((6, y + 4), '%s  scale 1 at 2x (as the game draws it)' % s, fill=(255, 255, 255))
        draw.text((r.shape[0] + gap + 6, y + 4), 'scale 2 at 1x', fill=(255, 255, 255))
        draw.text((2 * (r.shape[0] + gap) + 6, y + 4), 'crop at %dx: scale 1 / scale 2' % ZOOM, fill=(255, 255, 255))
        y += r.shape[0] + gap
    path = os.path.join(OUT_DIR, 'nebula_check.png')
    im.save(path, optimize=False, compress_level=6)
    print(os.path.relpath(path, nebula.ROOT))
    if worst:
        print('SEAM: ' + '; '.join(worst))
        sys.exit(1)


if __name__ == '__main__':
    main()
