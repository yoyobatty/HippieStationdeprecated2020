"""How sharp the sky looks on screen: pixelation, stair-stepping and shimmer, measured from real-client pictures.

DreamSeeker stretches the 480 game px tall map to the window (about 2.85 screen px a game pixel on a 1369 px pane). Three ways
the sky can look rough there, each measured here:

  grid      Something drawn at the game's pixels and then stretched shows a block grid lined up with the screen, one game
            pixel apart. Measured as the share of fine-detail energy sitting at that grid's frequency (and its first
            harmonic) in the rows' and columns' spectra, against the energy around it. ~1 is no grid; 3+ is clear blocks.
  rotated   Art drawn nearest-neighbour while the sky is turned shows its own pixel grid turned with the sky: the strongest
            peak of the 2D spectrum away from the screen axes, with its angle (compare with the sky's turn) and period.
  blocks    Art drawn bigger than its pixels and point-sampled (PIXEL_SCALE, or the map's Point Sampling mode) comes in hard
            2x2 game-pixel blocks: the share of the steps between game pixels on one phase of every two, 0 smooth, 1 blocks.
            Read it with the sky held at 0 degrees (sky_shots.dm `scaling`): turned blocks don't line up with the screen.
  shimmer   Lines that crawl as the sky turns: given pictures a fraction of a degree apart (sky_shots.dm `sharpness`), each
            is turned back by its own angle, and what's left in the fine detail between neighbours is what moved on its own.
            Mean fine-detail change (0-255) and a heat map of where it is.

  python tools/sky_gen/v2/sky_sharpness.py PICTURE [PICTURE...] [--crop x0,y0,x1,y1] [--view-px 480]
  python tools/sky_gen/v2/sky_sharpness.py --shimmer A.png:ANGLE B.png:ANGLE [C.png:ANGLE ...] [--out heat.png]

--crop     the map's part of a window picture (default: the map pane of a maximized 2576x1408 DreamSeeker grab)
--view-px  the view's height in game pixels (480 for 15 tiles): sets the game pixel's size on screen
Pictures from tools/keybind_check/sky_shots.dm with data/sky_shots_which = sharpness: data/previews/sky_sharp_*.png.
"""
import argparse
import os

import numpy as np
from PIL import Image

DEFAULT_CROP = (10, 35, 1740, 1395)


def load(path, crop):
    im = Image.open(path).convert('RGB')
    if crop:
        im = im.crop(crop)
    return np.asarray(im, dtype=np.float64) @ np.array([0.299, 0.587, 0.114])


def box_blur(a, r):
    out = a
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r, r)
        p = np.pad(out, pad, mode='edge')
        c = np.cumsum(p, axis=axis)
        c = np.concatenate([np.zeros_like(c.take([0], axis=axis)), c], axis=axis)
        k = 2 * r + 1
        out = (c.take(range(k, c.shape[axis]), axis=axis) - c.take(range(0, c.shape[axis] - k), axis=axis)) / k
    return out


def detail(lum):
    return lum - box_blur(lum, 4)


def grid_score(lum, game_px):
    """Energy of the fine detail at the game pixel's frequency against the energy just around it, rows and columns averaged."""
    d = detail(lum)
    scores = []
    for axis in (0, 1):
        diff = np.abs(np.diff(d, axis=axis))  # block edges are where it steps
        line = diff - diff.mean(axis=axis, keepdims=True)
        spec = np.abs(np.fft.rfft(line, axis=axis)).mean(axis=1 - axis)
        n = line.shape[axis]
        freqs = np.fft.rfftfreq(n)
        ratios = []
        for harmonic in (1, 2):
            f0 = harmonic / game_px
            if f0 >= 0.5:
                continue
            at = (np.abs(freqs - f0) < 0.006)
            around = (np.abs(freqs - f0) > 0.015) & (np.abs(freqs - f0) < 0.05)
            if at.any() and around.any():
                ratios.append(spec[at].max() / max(np.median(spec[around]), 1e-9))
        scores.append(max(ratios) if ratios else 0)
    return float(np.mean(scores))


def game_pixels(lum, game_px):
    """The picture taken back to one sample a game pixel, at the pixels' middles (the offset that gives the sharpest steps: a
    crop that doesn't start on a game pixel's edge still lines up)"""
    best = None
    for off in np.linspace(0, game_px, 7)[:-1]:
        ys = (np.arange(int((lum.shape[0] - off) / game_px)) * game_px + off + game_px / 2).astype(int)
        xs = (np.arange(int((lum.shape[1] - off) / game_px)) * game_px + off + game_px / 2).astype(int)
        g = lum[np.ix_(ys[ys < lum.shape[0]], xs[xs < lum.shape[1]])]
        energy = np.abs(np.diff(g, axis=0)).sum() + np.abs(np.diff(g, axis=1)).sum()
        if best is None or energy > best[0]:
            best = (energy, g)
    return best[1]


def art_blocks(lum, game_px, size=2, tile=24):
    """Art drawn `size` times bigger nearest-neighbour (PIXEL_SCALE, or anything else that point-samples it): its game pixels
    come in equal size x size blocks, so the steps between neighbouring game pixels all fall on one phase of every `size`.
    Per tile of the picture, the share of the step energy on its strongest phase, 0 for art at the game's pixels or filtered
    (smooth), 1 for hard blocks; the tiles are weighted by their detail. Only for art at the screen's angle (sky held at 0)."""
    g = game_pixels(lum, game_px)
    shares = []
    weights = []
    for y in range(0, g.shape[0] - tile + 1, tile):
        for x in range(0, g.shape[1] - tile + 1, tile):
            t = g[y:y + tile, x:x + tile]
            for axis in (0, 1):
                steps = np.abs(np.diff(t, axis=axis))
                along = steps.sum(axis=1 - axis)
                phases = np.array([along[k::size].sum() for k in range(size)])
                total = phases.sum()
                if total < 1e-6:
                    continue
                shares.append((phases.max() / total - 1 / size) / (1 - 1 / size))
                weights.append(total)
    if not weights:
        return 0.0
    return float(np.average(shares, weights=weights))


def rotated_peak(lum, game_px):
    """The strongest fine-grid peak of the 2D spectrum off the screen's axes: (strength against the median, angle deg, period px)"""
    d = detail(lum)
    h, w = d.shape
    s = min(h, w)
    d = d[(h - s) // 2:(h - s) // 2 + s, (w - s) // 2:(w - s) // 2 + s] * np.outer(np.hanning(s), np.hanning(s))
    spec = np.abs(np.fft.fftshift(np.fft.fft2(d)))
    fy, fx = np.meshgrid(np.fft.fftshift(np.fft.fftfreq(s)), np.fft.fftshift(np.fft.fftfreq(s)), indexing='ij')
    r = np.hypot(fx, fy)
    ang = np.degrees(np.arctan2(fy, fx)) % 180
    off_axis = (np.minimum(np.abs(ang - 90), np.minimum(ang, 180 - ang)) > 4)
    band = (r > 0.6 / game_px) & (r < 0.48) & off_axis
    if not band.any():
        return 0.0, 0.0, 0.0
    vals = spec[band]
    i = np.argmax(vals)
    peak = vals[i] / max(np.median(vals), 1e-9)
    return float(peak), float(ang[band][i]), float(1 / r[band][i])


def shimmer(entries, crop, out):
    """entries: [(path, angle)], each turned back by its angle; the fine detail's change between neighbours"""
    frames = []
    for path, angle in entries:
        im = Image.open(path).convert('RGB')
        if crop:
            im = im.crop(crop)
        turned = im.rotate(angle, resample=Image.BICUBIC)
        frames.append(detail(np.asarray(turned, dtype=np.float64) @ np.array([0.299, 0.587, 0.114])))
    h, w = frames[0].shape
    m = int(min(h, w) * 0.22)
    changes = []
    heat = np.zeros((h - 2 * m, w - 2 * m))
    for a, b in zip(frames, frames[1:]):
        diff = np.abs(a - b)[m:h - m, m:w - m]
        changes.append(diff.mean())
        heat = np.maximum(heat, diff)
    if out:
        Image.fromarray(np.clip(heat * 6, 0, 255).astype(np.uint8)).save(out)
    return changes


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('pictures', nargs='*')
    ap.add_argument('--crop', default=','.join(map(str, DEFAULT_CROP)))
    ap.add_argument('--view-px', type=float, default=480)
    ap.add_argument('--shimmer', nargs='*')
    ap.add_argument('--out')
    args = ap.parse_args()
    crop = tuple(int(v) for v in args.crop.split(',')) if args.crop else None
    for path in args.pictures:
        lum = load(path, crop)
        game_px = lum.shape[0] / args.view_px
        g = grid_score(lum, game_px)
        peak, ang, period = rotated_peak(lum, game_px)
        blocks = art_blocks(lum, game_px)
        print('%-42s grid %5.2f  blocks %4.2f  turned-grid peak %5.1f at %5.1f deg, %4.1f px  (game px %.2f screen px)' %
              (os.path.basename(path), g, blocks, peak, ang, period, game_px))
    if args.shimmer:
        entries = []
        for item in args.shimmer:
            path, angle = item.rsplit(':', 1)
            entries.append((path, float(angle)))
        changes = shimmer(entries, crop, args.out)
        print('shimmer (mean fine-detail change between neighbours): %s' % ', '.join('%.2f' % c for c in changes))
        if args.out:
            print(args.out)


if __name__ == '__main__':
    main()
