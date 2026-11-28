"""How the sky moves on screen, frame by frame, in a clip of the game window (tools/keybind_check/record.ps1: a folder of
frame_NNNN.png with times.txt; a video file works too): the wobble, the judder and the darting a screenshot can't show.

Each frame's sky is matched against the clip's first frame by phase correlation (sub-pixel), in four boxes clear of the
middle of the view (the mob the camera follows) and of the HUD along the bottom, and the boxes' shifts averaged. The far
sky barely moves as the eye flies (0.06 px a tile), so with only the far layers on (sky_shots.dm `walk`, sky_walk_far.mkv)
anything beyond a pixel or so, and above all any back-and-forth, is a wobble.

  python tools/sky_gen/v2/sky_motion.py data/previews/sky_walk_far [--crop x0,y0,x1,y1] [--csv out.csv] [--plot out.png]

Prints the shift's range in x and y, how many times it turns back on itself by more than half a pixel (a wobble), and the
biggest single-frame jump; --csv writes frame, time, dx, dy for every frame, --plot draws them.
"""
import argparse
import os
import subprocess
import sys

import numpy as np

FFMPEG_CANDIDATES = [r'C:\Program Files\ShareX\ffmpeg.exe', 'ffmpeg']
DEFAULT_CROP = (10, 35, 1740, 1395)  # the map pane of a maximized 2576x1408 DreamSeeker grab, as sky_sharpness.py


def ffmpeg():
    for c in FFMPEG_CANDIDATES:
        try:
            subprocess.run([c, '-version'], capture_output=True, check=True)
            return c
        except Exception:
            continue
    sys.exit('sky_motion: no ffmpeg')


def probe(path, ff):
    out = subprocess.run([ff, '-i', path], capture_output=True, text=True).stderr
    import re
    m = re.search(r'(\d{3,5})x(\d{3,5})', out)
    fps = re.search(r'(\d+(?:\.\d+)?) fps', out)
    return int(m.group(1)), int(m.group(2)), float(fps.group(1)) if fps else 60.0


def folder_frames(path, crop):
    """A record.ps1 clip: frame_NNNN.png in order, each with its time from times.txt"""
    from PIL import Image
    times = {}
    tfile = os.path.join(path, 'times.txt')
    if os.path.exists(tfile):
        for line in open(tfile):
            parts = line.split()
            if len(parts) == 2:
                times[int(parts[0])] = float(parts[1]) / 1000
    names = sorted(n for n in os.listdir(path) if n.startswith('frame_') and n.endswith('.png'))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(path, n)).convert('L')
        if crop:
            im = im.crop(crop)
        yield times.get(i, i / 30.0), np.asarray(im, dtype=np.float64)


def frames(path, crop):
    """(seconds, picture) for each frame of a clip"""
    if os.path.isdir(path):
        yield from folder_frames(path, crop)
        return
    for i, (fps, f) in enumerate(video_frames(path, crop or DEFAULT_CROP)):
        yield i / fps, f


def video_frames(path, crop):
    ff = ffmpeg()
    w, h, fps = probe(path, ff)
    x0, y0, x1, y1 = crop
    x1 = min(x1, w)
    y1 = min(y1, h)
    cw, ch = x1 - x0, y1 - y0
    proc = subprocess.Popen([ff, '-loglevel', 'error', '-i', path, '-vf', 'crop=%d:%d:%d:%d' % (cw, ch, x0, y0),
                             '-f', 'rawvideo', '-pix_fmt', 'gray', '-'], stdout=subprocess.PIPE)
    size = cw * ch
    while True:
        buf = proc.stdout.read(size)
        if len(buf) < size:
            break
        yield fps, np.frombuffer(buf, dtype=np.uint8).reshape(ch, cw).astype(np.float64)


def boxes(h, w):
    """Boxes of sky to match: three across a strip (a record.ps1 clip is a strip already clear of the mob and the HUD), or four
    clear of the middle and of the bottom's HUD in a whole map pane"""
    if w > 2 * h:
        bw, bh = w // 3 - 8, h - 8
        return [(4, 4), (4, w // 3 + 4), (4, 2 * w // 3 + 4)], bh, bw
    bw, bh = w // 4, h // 4
    return [(h // 10, w // 10), (h // 10, w - w // 10 - bw), (h // 2 - bh // 2, w // 12), (h // 2 - bh // 2, w - w // 12 - bw)], bh, bw


def phase_shift(a, b):
    """Shift of b against a, sub-pixel (parabola on the correlation peak)"""
    win = np.outer(np.hanning(a.shape[0]), np.hanning(a.shape[1]))
    fa = np.fft.fft2((a - a.mean()) * win)
    fb = np.fft.fft2((b - b.mean()) * win)
    r = fb * np.conj(fa)
    r /= np.abs(r) + 1e-9
    c = np.real(np.fft.ifft2(r))
    py, px = np.unravel_index(np.argmax(c), c.shape)

    def sub(c, p, axis):
        n = c.shape[axis]
        idx = [py, px]
        idx[axis] = (p - 1) % n
        l = c[tuple(idx)]
        idx[axis] = (p + 1) % n
        r_ = c[tuple(idx)]
        m = c[py, px]
        d = l - 2 * m + r_
        return p + (0.5 * (l - r_) / d if d != 0 else 0)

    sy = sub(c, py, 0)
    sx = sub(c, px, 1)
    if sy > a.shape[0] / 2:
        sy -= a.shape[0]
    if sx > a.shape[1] / 2:
        sx -= a.shape[1]
    return sx, sy


def reversals(series, threshold=0.5):
    """How many times a series turns back on itself by more than threshold (a wobble), ignoring smaller dither"""
    count = 0
    direction = 0
    extreme = series[0]
    for v in series[1:]:
        if direction >= 0:
            if v > extreme:
                extreme = v
                direction = 1 if direction == 1 or v - series[0] > threshold else direction
            elif extreme - v > threshold:
                if direction == 1:
                    count += 1
                direction = -1
                extreme = v
        else:
            if v < extreme:
                extreme = v
            elif v - extreme > threshold:
                count += 1
                direction = 1
                extreme = v
    return count


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('clip')
    ap.add_argument('--crop', help='x0,y0,x1,y1 of each frame (a video defaults to a maximized map pane)')
    ap.add_argument('--csv')
    ap.add_argument('--plot')
    args = ap.parse_args()
    crop = tuple(int(v) for v in args.crop.split(',')) if args.crop else None
    ref = None
    rows = []
    for i, (t, f) in enumerate(frames(args.clip, crop)):
        if ref is None:
            ref = f
            places, bh, bw = boxes(*f.shape)
        shifts = [phase_shift(ref[y:y + bh, x:x + bw], f[y:y + bh, x:x + bw]) for y, x in places]
        dx = float(np.median([s[0] for s in shifts]))
        dy = float(np.median([s[1] for s in shifts]))
        rows.append((i, t, dx, dy))
    if not rows:
        sys.exit('sky_motion: no frames')
    xs = np.array([r[2] for r in rows])
    ys = np.array([r[3] for r in rows])
    jump = max(np.max(np.abs(np.diff(xs))) if len(xs) > 1 else 0, np.max(np.abs(np.diff(ys))) if len(ys) > 1 else 0)
    span = rows[-1][1] - rows[0][1]
    fps = (len(rows) - 1) / span if span > 0 else 0
    print('%s: %d frames at %.0f fps; x %.2f..%.2f px, y %.2f..%.2f px; turns back >0.5 px: x %d, y %d; biggest frame jump %.2f px'
          % (os.path.basename(os.path.normpath(args.clip)), len(rows), fps, xs.min(), xs.max(), ys.min(), ys.max(), reversals(list(xs)),
             reversals(list(ys)), jump))
    if args.csv:
        with open(args.csv, 'w') as f:
            f.write('frame,seconds,dx,dy\n')
            for r in rows:
                f.write('%d,%.4f,%.3f,%.3f\n' % r)
    if args.plot:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        t = [r[1] for r in rows]
        fig, ax = plt.subplots(figsize=(10, 3.2))
        ax.plot(t, xs, label='sky x (px)')
        ax.plot(t, ys, label='sky y (px)')
        ax.set_xlabel('seconds')
        ax.legend()
        ax.grid(alpha=0.3)
        fig.tight_layout()
        fig.savefig(args.plot, dpi=110)


if __name__ == '__main__':
    main()
