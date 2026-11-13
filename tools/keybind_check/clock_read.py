#!/usr/bin/env python3
"""Reads trip_clock.dm's grabs (data/clock/): per phase, how many grabs a second the client allowed and how many showed a new frame.

A grab (PrintWindow) waits for the client to draw, so grabs a second follow the client's frame rate up to about 31, the grabber's
own limit: a phase that drops below that is one the client can't keep up with (measured: the tunnel's masked copies held it to 6).
"""
import csv
import os
from collections import OrderedDict

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
DATA = os.path.join(ROOT, 'data', 'clock')
SCREEN_PER_VIEW = 1369 / 480.0


def marker_x(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(int)
    hit = (a[..., 0] > 200) & (a[..., 1] < 60) & (a[..., 2] > 200)
    xs = np.nonzero(hit.any(0))[0]
    if not len(xs):
        return None
    return xs.min() / SCREEN_PER_VIEW  # view pixels from the left edge


def main():
    rows = list(csv.DictReader(open(os.path.join(DATA, 'grabs.csv'))))
    phases = OrderedDict()
    for r in rows:
        phases.setdefault(r['phase'], []).append((int(r['n']), float(r['ms'])))
    print('%-20s %8s %8s' % ('phase', 'grabs/s', 'new%'))
    for phase, grabs in phases.items():
        xs = [marker_x(os.path.join(DATA, '%s_%d.png' % (phase, n))) for n, ms in grabs]
        xs = [x for x in xs if x is not None]
        span = (grabs[-1][1] - grabs[0][1]) / 1000.0
        new = np.mean(np.abs(np.diff(xs)) > 0.5) * 100 if len(xs) > 2 else 0
        print('%-20s %8.1f %7.0f%%' % (phase, len(grabs) / max(span, 0.001), new))

if __name__ == '__main__':
    main()
