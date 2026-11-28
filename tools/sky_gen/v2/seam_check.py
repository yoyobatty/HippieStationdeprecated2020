"""Straight lines in pictures of the sky: seams where repeats or quarters of a sprite meet.

A seam is a line the whole way across the sky's art, turned with the sky. This turns a picture back by the sky's angle so
any seam runs straight up or across, takes out everything but fine detail (the picture less a blur of itself), and looks
along every column and row for a steady brightening or darkening. Stars and rocks are bright dots, so a column's median
ignores them; a seam shifts the whole column. Each line found is printed with its strength (robust z-score) and place, and
a picture of the turned-back detail with the lines marked is written beside the input.

  python tools/sky_gen/v2/seam_check.py PICTURE [PICTURE...] --angle DEG [--crop x0,y0,x1,y1] [--z 8]

--angle  the sky's turn when the picture was taken, degrees clockwise (sky_turn_angle(); sky_shots.dm `seams` logs it)
--crop   the map's part of the window picture (default: the map pane of a maximized 2576x1408 DreamSeeker shot)
--z      how far past the usual a column or row must be to count as a line (default 8)

Pictures from tools/keybind_check/sky_shots.dm with data/sky_shots_which = seams: data/previews/sky_seams_*.png.
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageDraw


def blur(a, radius):
    """Three box blurs each way (close to a Gaussian), edges held."""
    out = a
    k = 2 * radius + 1
    for axis in (0, 1):
        for _ in range(3):
            pad = [(0, 0), (0, 0)]
            pad[axis] = (radius, radius)
            p = np.pad(out, pad, mode='edge')
            c = np.cumsum(p, axis=axis, dtype=np.float64)
            c = np.concatenate([np.zeros_like(c.take([0], axis=axis)), c], axis=axis)
            hi = c.take(range(k, c.shape[axis]), axis=axis)
            lo = c.take(range(0, c.shape[axis] - k), axis=axis)
            out = (hi - lo) / k
    return out


def robust_z(profile):
    m = np.median(profile)
    mad = np.median(np.abs(profile - m)) * 1.4826 + 1e-9
    return (profile - m) / mad


def lines_in(values, z_min):
    """Runs of columns (or rows) past z_min: (start, end, peak z, signed level) each."""
    z = robust_z(np.abs(values))
    found = []
    i = 0
    while i < len(z):
        if z[i] >= z_min:
            j = i
            while j + 1 < len(z) and z[j + 1] >= z_min:
                j += 1
            peak = i + int(np.argmax(z[i:j + 1]))
            found.append((i, j, float(z[peak]), float(values[peak])))
            i = j + 1
        else:
            i += 1
    return found


def check(path, angle, crop, z_min):
    im = Image.open(path).convert('RGB')
    if crop:
        im = im.crop(crop)
    # Turn back: BYOND turned the sky clockwise by `angle`; PIL turns counter-clockwise for a positive angle
    turned = im.rotate(angle, resample=Image.BILINEAR, expand=False)
    w, h = turned.size
    # Keep the middle that the turn left filled
    s, c = abs(np.sin(np.radians(angle))), abs(np.cos(np.radians(angle)))
    mx = int(np.ceil((w * (1 - c) + h * s) / 2)) + 4
    my = int(np.ceil((h * (1 - c) + w * s) / 2)) + 4
    if mx * 2 >= w or my * 2 >= h:
        mx, my = w // 4, h // 4
    region = turned.crop((mx, my, w - mx, h - my))
    lum = np.asarray(region, dtype=np.float64) @ np.array([0.299, 0.587, 0.114])
    detail = lum - blur(lum, 6)
    cols = np.median(detail, axis=0)
    rows = np.median(detail, axis=1)
    col_lines = lines_in(cols, z_min)
    row_lines = lines_in(rows, z_min)
    name = os.path.basename(path)
    print('%s (turned back %g deg, %dx%d checked): %d up-down, %d across' % (name, angle, region.width, region.height,
                                                                              len(col_lines), len(row_lines)))
    for kind, found in (('up-down x', col_lines), ('across y', row_lines)):
        for a, b, zpk, level in found:
            print('  %s %d-%d  z %.1f  %s %.2f' % (kind, a, b, zpk, 'brighter' if level > 0 else 'darker', abs(level)))
    pic = Image.fromarray(np.clip(detail * 6 + 128, 0, 255).astype(np.uint8)).convert('RGB')
    draw = ImageDraw.Draw(pic)
    for a, b, _, _ in col_lines:
        draw.rectangle((a - 1, 0, b + 1, 6), fill=(255, 40, 40))
        draw.rectangle((a - 1, pic.height - 7, b + 1, pic.height - 1), fill=(255, 40, 40))
    for a, b, _, _ in row_lines:
        draw.rectangle((0, a - 1, 6, b + 1), fill=(255, 40, 40))
        draw.rectangle((pic.width - 7, a - 1, pic.width - 1, b + 1), fill=(255, 40, 40))
    out = os.path.splitext(path)[0] + '_seams.png'
    pic.save(out)
    return len(col_lines) + len(row_lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('pictures', nargs='+')
    ap.add_argument('--angle', type=float, required=True)
    ap.add_argument('--crop', default='10,35,1740,1395')
    ap.add_argument('--z', type=float, default=8)
    args = ap.parse_args()
    crop = tuple(int(v) for v in args.crop.split(',')) if args.crop else None
    total = 0
    for path in args.pictures:
        total += check(path, args.angle, crop, args.z)
    print('lines found: %d' % total)


if __name__ == '__main__':
    main()
