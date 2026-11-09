#!/usr/bin/env python3
"""Cuts the map out of the sky_shots.dm window pictures and lays them out for comparing.

    python tools/sky_gen/sheet.py                 one sheet per kind of shot: data/previews/sky_sheet_<kind>.png
    python tools/sky_gen/sheet.py pair a b out    two shots side by side: data/previews/<out>.png
    python tools/sky_gen/sheet.py diff a b        how many map pixels differ between two shots (twinkle, drift)

The map is found by its black letterbox: the biggest square that fits the window's left pane.
"""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
PREVIEWS = os.path.join(ROOT, 'data', 'previews')
ORDER = ['before', 'ember', 'glacier', 'violet', 'verdant', 'gold', 'rose', 'quiet']


def map_of(path):
    """The game map cut out of a window picture."""
    image = Image.open(path).convert('RGB')
    arr = np.asarray(image).astype(int)
    height = arr.shape[0]
    # the stat panel's flat dark grey starts where the map pane ends
    row = arr[height // 2]
    right = next((x for x in range(200, row.shape[0] - 8) if all(tuple(row[x + i]) == (23, 23, 23) for i in range(8))), row.shape[0])
    top = 31  # under the title bar
    bottom = height - 8
    side = min(right - 8, bottom - top)
    left = 8 + (right - 8 - side) // 2
    return image.crop((left, top, left + side, top + side))


def shot(name):
    return os.path.join(PREVIEWS, name if name.endswith('.png') else name + '.png')


def labelled(image, text, size):
    image = image.resize((size, size), Image.LANCZOS)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 8 + 7 * len(text), 18), fill=(0, 0, 0))
    draw.text((4, 3), text, fill=(255, 255, 255))
    return image


def sheet(kind, size=560, columns=4):
    found = []
    for tag in ORDER:
        hits = glob.glob(os.path.join(PREVIEWS, 'sky_%s_%s.png' % (tag, kind)))
        if hits:
            found.append((tag, hits[0]))
    if not found:
        return
    rows = (len(found) + columns - 1) // columns
    out = Image.new('RGB', (size * columns, size * rows))
    for i, (tag, path) in enumerate(found):
        out.paste(labelled(map_of(path), tag, size), ((i % columns) * size, (i // columns) * size))
    target = os.path.join(PREVIEWS, 'sky_sheet_%s.png' % kind)
    out.save(target)
    print(os.path.relpath(target, ROOT))


def main():
    args = sys.argv[1:]
    if not args:
        for kind in ('1_space', '2_window', '3_dark'):
            sheet(kind)
    elif args[0] == 'pair':
        a, b = map_of(shot(args[1])), map_of(shot(args[2]))
        size = 900
        out = Image.new('RGB', (size * 2, size))
        out.paste(labelled(a, args[1], size), (0, 0))
        out.paste(labelled(b, args[2], size), (size, 0))
        target = os.path.join(PREVIEWS, args[3] + '.png')
        out.save(target)
        print(os.path.relpath(target, ROOT))
    elif args[0] == 'diff':
        a = np.asarray(map_of(shot(args[1]))).astype(int)
        b = np.asarray(map_of(shot(args[2]))).astype(int)
        changed = np.abs(a - b).max(axis=2)
        print('%d of %d map pixels differ by more than 12 (%.2f%%), biggest change %d' % ((changed > 12).sum(), changed.size, 100.0 * (changed > 12).mean(), changed.max()))
    elif args[0] == 'one':
        size = int(args[2]) if len(args) > 2 else 900
        target = os.path.join(PREVIEWS, args[1] + '_map.png')
        map_of(shot(args[1])).resize((size, size), Image.LANCZOS).save(target)
        print(os.path.relpath(target, ROOT))
    else:
        print(__doc__)


if __name__ == '__main__':
    main()
