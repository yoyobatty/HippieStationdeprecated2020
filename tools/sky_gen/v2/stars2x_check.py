"""Checks the star layers, the galaxy band and the twinkles at resolution scale 2 against scale 1.

    python tools/sky_gen/v2/stars2x_check.py

Builds stars.build_layers(scale) and twinkle.build_twinkles(scale) at scale 1 and 2 and turns every state into its sheet
image as build_v2.py does (sg.additive_image, the same dither seeds). Each scale-2 image is scaled down by 2 (the mean of
each 2 x 2) and compared with scale 1, per state:

  mean|d|  mean absolute difference, 0..255 over every pixel and channel (the number to keep small)
  p99.9    the 99.9th percentile of it (where the stars are: a star's light lands a little differently at scale 2)
  floor    mean|d| of scale 1's own art blown up 2x, dithered again and scaled back: the dither alone
  light    scale 2's mean brightness over scale 1's (1.000: the same light)
  seam     the step across the tile's wrap over the mean step between neighbours, columns / rows, at scale 1 and 2
           (about 1: seamless; a star tile's few stars at its edge move it about, the same at both scales)
  lone px  the largest single-pixel contrast, a pixel less the mean of its 8 neighbours (0..255, any channel), at
           scale 1 / scale 2: a hard single pixel flickers as the sky turns under the game's smooth sampling
  hard     the largest such contrast over the pixel's own value, among pixels of 24+: 1.00 is a lone pixel on black,
           about 0.67 a star drawn as stars.SOFT_SIGMA's soft dot (scale 1 / scale 2)

The band also gets a reference: scale 1's own band upsampled smoothly to 2x (stars.upsample) and scaled back the same
way. The 2 x 2 mean softens detail at the pixel's size, so any 2x band that keeps scale 1's detail differs by about that.

Then each twinkle group's centre is checked against the scale-2 near star under it (exit 1 if any is off by more than
half a pixel), and data/previews/sky2x/stars_check.png is written: per state, scale 1 | scale 2 scaled down | the
busiest 240 px of scale 1 blown up 2x (nearest, as the game shows it today) | the same place at scale 2, full size.
The twinkle row is the near layer with all three groups at full alpha.
"""
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import sky_gen as sg  # noqa: E402
import stars  # noqa: E402
import twinkle  # noqa: E402

OUT = os.path.join(sg.ROOT, 'data', 'previews', 'sky2x', 'stars_check.png')
SEEDS = {'stars_deep': 801, 'stars_far': 802, 'stars_mid': 803, 'stars_near': 804, 'band': 805}  # build_v2.py
PANEL = 480  # scale-1 px a sheet panel shows
CROP = 240   # scale-1 px of the busy crop (480 px at scale 2)


def sheet_image(state, rgb):
    """The state's sheet colours, float 0..255 RGB, as build_v2.py makes them."""
    img = twinkle.as_image(rgb, int(state[-1])) if state.startswith('twinkle') else sg.additive_image(rgb, SEEDS[state])
    return np.asarray(img, float)[..., :3]


def down2(a):
    return 0.25 * (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2])


def seam(a):
    """Step across the wrap over the mean neighbour step: (columns, rows)."""
    lum = a.mean(axis=-1)
    cols = np.abs(lum[:, 0] - lum[:, -1]).mean() / max(np.abs(np.diff(lum, axis=1)).mean(), 1e-12)
    rows = np.abs(lum[0] - lum[-1]).mean() / max(np.abs(np.diff(lum, axis=0)).mean(), 1e-12)
    return cols, rows


def lone_pixel(img):
    """Largest (pixel - mean of its 8 neighbours) over the image and its channels, wrapping."""
    around = sum(np.roll(img, (dy, dx), axis=(0, 1)) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx) / 8.0
    return float((img - around).max())


def hardness(img, least=24.0):
    """Largest (pixel - mean of its 8 neighbours) / pixel among pixels of `least` or more (0..255), any channel."""
    around = sum(np.roll(img, (dy, dx), axis=(0, 1)) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx) / 8.0
    bright = img >= least
    return float(((img - around)[bright] / img[bright]).max()) if bright.any() else 0.0


def busiest(img, size, within=None, step=8):
    """(y, x) of the size x size window (wrapping) with the most fine detail, optionally inside the window `within`
    (y, x, size)."""
    lum = img.mean(axis=-1)
    n = lum.shape[0]
    detail = np.abs(lum - sg.blur(lum, 1.5))
    if within is not None:
        wy, wx, ws = within
        detail = np.roll(detail, (-wy, -wx), axis=(0, 1))[:ws, :ws]
        n = ws
        tiled = detail
        span = range(0, n - size + 1, step)
    else:
        tiled = np.tile(detail, (2, 2))
        span = range(0, n, step)
    c = np.pad(tiled.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    best, where = -1.0, (0, 0)
    for y in span:
        for x in span:
            s = c[y + size, x + size] - c[y, x + size] - c[y + size, x] + c[y, x]
            if s > best:
                best, where = s, (y, x)
    if within is not None:
        where = ((where[0] + within[0]) % lum.shape[0], (where[1] + within[1]) % lum.shape[0])
    return where


def window(img, y, x, size):
    n = img.shape[0]
    return img[np.ix_(np.arange(y, y + size) % n, np.arange(x, x + size) % n)]


def to_pil(a):
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), 'RGB')


def twinkle_offsets(near2, tw2, picks):
    """Max distance (scale-2 px) between each twinkling star's group centroid and the near star's, in a small window."""
    near = twinkle.near_stars()
    worst = 0.0
    r = 5
    d = np.arange(-r, r + 1)
    for i, g in picks:
        cy, cx = int(near[i][1] * 2), int(near[i][0] * 2)
        rows, cols = (cy + d) % near2.shape[0], (cx + d) % near2.shape[0]
        for img in (near2, tw2['twinkle%d' % g]):
            w = img[np.ix_(rows, cols)].mean(axis=-1)
            w = w * (w > 0.5 * w.max())  # the star's own core, not a neighbour's glow
            oy, ox = (w * d[:, None]).sum() / w.sum(), (w * d[None, :]).sum() / w.sum()
            worst = max(worst, float(np.hypot(oy, ox)))
    return worst


def main():
    t0 = time.time()
    lay1 = stars.build_layers(1)
    tw1, picks1 = twinkle.build_twinkles(scale=1)
    t1 = time.time()
    lay2 = stars.build_layers(2)
    t2 = time.time()
    tw2, picks2 = twinkle.build_twinkles(scale=2)
    t3 = time.time()
    print('build: scale 1 %.1f s, scale 2 %.1f s (layers %.1f s, twinkles %.1f s)' % (t1 - t0, t3 - t1, t2 - t1, t3 - t2))
    if picks1 != picks2:
        print('FAIL: twinkle picks differ between scales')
        sys.exit(1)

    all1 = dict(lay1, **tw1)
    all2 = dict(lay2, **tw2)
    images = {}
    print('%-11s %-10s %7s %6s %6s %6s %10s %10s %8s %10s' % ('state', 'scale 2', 'mean|d|', 'p99.9', 'floor',
                                                               'light', 'seam s1', 'seam s2', 'lone px', 'hard'))
    for state in list(lay1) + list(tw1):
        a, b = all1[state], all2[state]
        img1, img2 = sheet_image(state, a), sheet_image(state, b)
        diff = np.abs(down2(img2) - img1)
        floor = np.abs(down2(sheet_image(state, np.repeat(np.repeat(a, 2, 0), 2, 1))) - img1).mean()
        light = img2.mean() / max(img1.mean(), 1e-12)
        print('%-11s %-10s %7.3f %6.1f %6.3f %6.3f %10s %10s %8s %10s' % (
            state, '%dx%d' % b.shape[:2], diff.mean(), np.percentile(diff, 99.9), floor, light,
            '%.2f/%.2f' % seam(a), '%.2f/%.2f' % seam(b), '%.0f/%.0f' % (lone_pixel(img1), lone_pixel(img2)),
            '%.2f/%.2f' % (hardness(img1), hardness(img2))))
        images[state] = (img1, img2, diff.mean())

    smooth = np.stack([stars.upsample(lay1['band'][..., c], 2) for c in range(3)], axis=-1)
    print('band reference, scale 1 upsampled smoothly and scaled back: mean|d| %.3f' % np.abs(
        down2(sheet_image('band', smooth)) - images['band'][0]).mean())
    worst = twinkle_offsets(lay2['stars_near'], tw2, picks2)
    print('twinkle groups on the scale-2 near stars: worst centre offset %.2f px (%d stars)' % (worst, len(picks2)))

    # the sheet
    near_tw = []
    for k, (lay, tw) in enumerate(((lay1, tw1), (lay2, tw2))):
        base = sheet_image('stars_near', lay['stars_near'])
        near_tw.append(np.clip(base + sum(sheet_image(s, tw[s]) for s in sorted(tw)), 0, 255))
    rows = [(s, images[s][0], images[s][1], 'mean|d| %.3f' % images[s][2]) for s in ('stars_deep', 'stars_far',
                                                                                    'stars_mid', 'stars_near', 'band')]
    tw_d = np.mean([images[s][2] for s in sorted(tw1)])
    rows.append(('near + twinkles', near_tw[0], near_tw[1], 'twinkle mean|d| %.3f' % tw_d))
    font = ImageFont.load_default()
    head = 16
    titles = ['scale 1', 'scale 2 scaled down', 'scale 1 crop, 2x nearest', 'scale 2 crop, full size']
    sheet = Image.new('RGB', (4 * PANEL + 3 * 4, len(rows) * (PANEL + head) + head), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for c, title in enumerate(titles):
        draw.text((c * (PANEL + 4) + 4, 2), title, fill=(230, 230, 230), font=font)
    for r, (name, img1, img2, note) in enumerate(rows):
        top = head + r * (PANEL + head)
        n1 = img1.shape[0]
        # the panel: whole star tiles; the band's busiest 480 px
        wy, wx = (0, 0) if n1 == PANEL else busiest(img1, PANEL, step=16)
        cy, cx = busiest(img1, CROP, within=(wy, wx, PANEL))
        down = down2(img2)
        panels = [window(img1, wy, wx, PANEL), window(down, wy, wx, PANEL),
                  np.repeat(np.repeat(window(img1, cy, cx, CROP), 2, 0), 2, 1), window(img2, 2 * cy, 2 * cx, 2 * CROP)]
        draw.text((4, top + 2), '%s   %s   crop at (%d, %d) scale-1 px' % (name, note, cx, cy), fill=(230, 230, 230),
                  font=font)
        for c, p in enumerate(panels):
            sheet.paste(to_pil(p), (c * (PANEL + 4), top + head))
        # where the crop is, on the first two panels
        for c in (0, 1):
            x0 = c * (PANEL + 4) + (cx - wx) % n1
            y0 = top + head + (cy - wy) % n1
            draw.rectangle((x0, y0, x0 + CROP - 1, y0 + CROP - 1), outline=(90, 90, 160))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print(OUT)
    if worst > 0.5:
        print('FAIL: a twinkle group is off its near star')
        sys.exit(1)


if __name__ == '__main__':
    main()
