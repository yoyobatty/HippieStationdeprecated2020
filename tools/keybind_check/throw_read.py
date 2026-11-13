#!/usr/bin/env python3
"""Reads throw_shots.dm's grabs (data/throw_capture/): where the magenta wrench is in each, and how evenly it moved.

For each phase: the grabs taken while it was in the air, its speed between each grab and the next (pixels a millisecond), how much
that speed varies (a stuttering throw jumps then sits, so it varies a lot), how many grabs caught it standing still mid-flight, and
how high it rose above the line from where it started to where it landed. Writes a strip of the in-flight grabs per phase to
data/previews/throw_<phase>_strip.png.
Usage: python tools/keybind_check/throw_read.py
"""
import csv
import os
from collections import OrderedDict

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
DATA = os.path.join(ROOT, 'data', 'throw_capture')
OUT = os.path.join(ROOT, 'data', 'previews')
MAP_RIGHT = 1016  # the map pane's right edge in the grab; the panels are to the right of it


def find(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(int)[:, :MAP_RIGHT]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hit = (r > 90) & (b > 90) & (g < 0.45 * np.minimum(r, b)) & (np.abs(r - b) < 70)
    ys, xs = np.nonzero(hit)
    if len(xs) < 6:
        return None
    return float(xs.mean()), float(ys.mean()), float(ys.min())


def main():
    rows = list(csv.DictReader(open(os.path.join(DATA, 'grabs.csv'))))
    phases = OrderedDict()
    for row in rows:
        phases.setdefault(row['phase'], []).append((int(row['n']), int(row['ms'])))
    os.makedirs(OUT, exist_ok=True)
    for phase, grabs in phases.items():
        seen = []
        for n, ms in grabs:
            path = os.path.join(DATA, f'{phase}_{n}.png')
            if not os.path.exists(path):
                continue
            spot = find(path)
            if spot:
                seen.append((n, ms, *spot))
        if len(seen) < 3:
            print(f'{phase}: the wrench was found in {len(seen)} grabs')
            continue
        # in the air: from the last grab before it first moves to the first grab after it last moves
        xs = [s[2] for s in seen]
        start_x, end_x = xs[0], xs[-1]
        moving = [i for i in range(1, len(seen)) if abs(seen[i][2] - seen[i - 1][2]) > 0.5]
        if not moving:
            print(f'{phase}: it never moved ({len(seen)} grabs)')
            continue
        first, last = moving[0] - 1, moving[-1]
        flight = seen[first:last + 1]
        speeds = []
        stills = 0
        for a, b in zip(flight, flight[1:]):
            dt = b[1] - a[1]
            dx = b[2] - a[2]
            if dt <= 0:
                continue
            speeds.append(dx / dt)
            if abs(dx) <= 0.5:
                stills += 1
        speeds = np.array(speeds)
        mean = speeds.mean()
        spread = speeds.std() / abs(mean) if mean else float('nan')
        # rise above the straight line between where it started and where it came down
        x0, y0 = flight[0][2], flight[0][4]
        x1, y1 = flight[-1][2], flight[-1][4]
        rise = 0
        for f in flight:
            t = (f[2] - x0) / (x1 - x0) if x1 != x0 else 0
            line_y = y0 + (y1 - y0) * t
            rise = max(rise, line_y - f[4])
        took = flight[-1][1] - flight[0][1]
        # how far off a steady glide each grab is: a straight line through place against time, over the grabs in the air
        t = np.array([f[1] for f in flight], dtype=float)
        x = np.array([f[2] for f in flight], dtype=float)
        fit = np.polyfit(t, x, 1)
        off = x - np.polyval(fit, t)
        rms, worst = float(np.sqrt((off ** 2).mean())), float(np.abs(off).max())
        print(f'{phase}: {len(grabs)} grabs, {len(flight)} with it in the air over {took} ms; moved {end_x - start_x:.0f} px; '
              f'speed {mean * 1000:.0f} px/s, varying {spread * 100:.0f}% grab to grab; {stills} grabs caught it still mid-air; '
              f'rose {rise:.0f} px; off a steady glide by {rms:.1f} px on average, {worst:.1f} at most')
        # a strip of the in-flight grabs, cropped round the throw
        top = int(min(f[4] for f in flight)) - 60
        bottom = int(max(f[3] for f in flight)) + 60
        left = int(min(f[2] for f in flight)) - 70
        right = int(max(f[2] for f in flight)) + 70
        tiles = []
        for f in flight:
            im = Image.open(os.path.join(DATA, f'{phase}_{f[0]}.png')).convert('RGB').crop((left, max(top, 0), right, bottom))
            d = ImageDraw.Draw(im)
            d.text((4, 4), f'{f[1] - flight[0][1]} ms', fill=(255, 255, 255))
            tiles.append(im)
        w, h = tiles[0].size
        sheet = Image.new('RGB', (w, h * len(tiles)), (0, 0, 0))
        for i, t in enumerate(tiles):
            sheet.paste(t, (0, i * h))
        sheet.save(os.path.join(OUT, f'throw_{phase}_strip.png'))


if __name__ == '__main__':
    main()
