"""Checks the 2x sky bodies sheet against the 1x one: the same picture in twice the pixels, and no hard single pixels.

    python tools/sky_gen/v2/bodies2x_check.py [--keep DIR] [--from DIR]

Builds sky_bodies.dmi's states twice, as build_v2.py does (bodies.build_bodies(0.0, scale) with planets.repaint_states over
it), at scale 1 (480 px) and scale 2 (960 px), and prints per state:
  diff      the mean absolute difference (0-255) between the scale-1 state and the scale-2 one averaged down 2x2 (in linear
            light, premultiplied; the additive sun in its own values), over premultiplied RGB and alpha. Under ~3 means
            the 2x art scaled down by 2 looks like today's art.
  hard1/2   the largest single-pixel contrast, max over pixels of |Y - mean of its 8 neighbours| on luminance (Y of the
            colour over black, 0-255), at scale 1 and at scale 2; p999 is the 99.9th percentile at scale 2. A hard one-pixel
            speck or step scores high; in game a 2x pixel lands on about 1.4 screen pixels, and one-pixel detail flickers
            as the sky turns.
Writes data/previews/sky2x/bodies_check.png: per state, scale 1 | scale 2 averaged down | a 480 px crop of scale 2 at full
size (an edge: Lavaland's limb, belt and moon, the gas giant's limb and ring, each world whole; the galaxies' and the sun's
middle), each over a dark sky. Takes a few minutes (the build times are printed).
  --keep DIR   also save every built state as DIR/s1_<state>.png and DIR/s2_<state>.png
  --from DIR   load those instead of building (to look again without the wait)
"""
import argparse
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bodies  # noqa: E402
import planets  # noqa: E402
import sky_gen as sg  # noqa: E402

OUT = os.path.join(sg.ROOT, 'data', 'previews', 'sky2x')
SKY = (4, 5, 10)
CROP_CENTRE = {'planet_lava': (660, 600), 'world_gas': (640, 530)}  # scale-2 pixels; the rest: the middle


def build(scale):
    t = time.time()
    states = planets.repaint_states(bodies.build_bodies(0.0, scale=scale), scale=scale)
    return states, time.time() - t


def as_float(image):
    return np.asarray(image.convert('RGBA'), dtype=float) / 255


def down2(arr, additive):
    """A scale-2 state averaged 2x2 to scale 1: in linear light and premultiplied (as render() averages its samples), or the
    plain values for the additive sun. Straight-alpha float RGBA back."""
    h, w = arr.shape[0] // 2, arr.shape[1] // 2
    box = lambda x: x.reshape(h, 2, w, 2, x.shape[-1]).mean(axis=(1, 3))
    if additive:
        return box(arr)
    a = arr[..., 3:4]
    pre = box(np.concatenate([bodies.lin(arr[..., :3] * 255) * a, a], axis=-1))
    a2 = pre[..., 3:4]
    rgb = bodies.srgb(np.clip(pre[..., :3] / np.maximum(a2, 1e-9), 0, 1))
    return np.concatenate([np.where(a2 > 0, rgb, 0), a2], axis=-1)


def premul(arr):
    return np.concatenate([arr[..., :3] * arr[..., 3:4], arr[..., 3:4]], axis=-1)


def hard_pixels(arr):
    """|Y - mean of the 8 neighbours| per pixel, Y the luminance of the colour over black, 0-255."""
    y = (arr[..., :3] * arr[..., 3:4]) @ np.array([0.2126, 0.7152, 0.0722]) * 255
    p = np.pad(y, 1, mode='edge')
    h, w = y.shape
    around = sum(p[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx) / 8
    return np.abs(y - around)


def on_sky(arr, additive):
    bg = np.array(SKY, dtype=float) / 255
    if additive:
        out = np.clip(bg + arr[..., :3], 0, 1)
    else:
        out = bg * (1 - arr[..., 3:4]) + arr[..., :3] * arr[..., 3:4]
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGB')


def load(path_dir, tag):
    states = {}
    for f in sorted(os.listdir(path_dir)):
        if f.startswith(tag + '_') and f.endswith('.png'):
            states[f[len(tag) + 1:-4]] = Image.open(os.path.join(path_dir, f)).convert('RGBA')
    return states


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--keep')
    ap.add_argument('--from', dest='src')
    args = ap.parse_args()
    if args.src:
        s1, s2 = load(args.src, 's1'), load(args.src, 's2')
        print('loaded from', args.src)
    else:
        s1, t1 = build(1)
        print('scale 1 built in %.0f s' % t1)
        s2, t2 = build(2)
        print('scale 2 built in %.0f s' % t2)
        if args.keep:
            os.makedirs(args.keep, exist_ok=True)
            for tag, states in (('s1', s1), ('s2', s2)):
                for name, image in states.items():
                    image.save(os.path.join(args.keep, '%s_%s.png' % (tag, name)))
    names = [name for name in s1 if name in s2]
    os.makedirs(OUT, exist_ok=True)
    panel = sg.TILE
    sheet = Image.new('RGB', (panel * 3, panel * len(names)), SKY)
    draw = ImageDraw.Draw(sheet)
    print('%-14s %9s %6s %6s %6s %6s' % ('state', 'size 2x', 'diff', 'hard1', 'hard2', 'p999'))
    worst = []
    for i, name in enumerate(names):
        additive = name == 'sun'
        a1, a2 = as_float(s1[name]), as_float(s2[name])
        if a2.shape[0] != 2 * a1.shape[0] or a2.shape[1] != 2 * a1.shape[1]:
            print('%-14s size %s vs %s: not 2x' % (name, s2[name].size, s1[name].size))
            continue
        d2 = down2(a2, additive)
        diff = np.abs(premul(d2) - premul(a1)).mean() * 255
        h1, h2 = hard_pixels(a1), hard_pixels(a2)
        print('%-14s %4dx%-4d %6.2f %6.1f %6.1f %6.1f' % (name, a2.shape[1], a2.shape[0], diff, h1.max(), h2.max(),
                                                        np.percentile(h2, 99.9)))
        worst.append((diff, name))
        cx, cy = CROP_CENTRE.get(name, (a2.shape[1] // 2, a2.shape[0] // 2))
        x0 = int(np.clip(cx - panel // 2, 0, a2.shape[1] - panel))
        y0 = int(np.clip(cy - panel // 2, 0, a2.shape[0] - panel))
        crop = a2[y0:y0 + panel, x0:x0 + panel]
        for col, (arr, label) in enumerate(((a1, 'scale 1'), (d2, 'scale 2 down 2x  diff %.2f' % diff),
                                            (crop, 'scale 2 crop at %d,%d  hard %.0f' % (x0, y0, h2.max())))):
            sheet.paste(on_sky(arr, additive), (col * panel, i * panel))
            draw.text((col * panel + 6, i * panel + 4), '%s  %s' % (name, label), fill=(210, 210, 210))
    path = os.path.join(OUT, 'bodies_check.png')
    sheet.save(path, optimize=True)
    print(os.path.relpath(path, sg.ROOT))
    over = [name for diff, name in worst if diff > 3]
    print('over 3: %s' % (', '.join(over) if over else 'none'))


if __name__ == '__main__':
    main()
