"""Sky v2 asteroid field: generated rocks for /obj/screen/parallax_layer/random/asteroids (the gold and quiet themes).

    python tools/sky_gen/v2/asteroids.py preview    -> data/previews/sky2_body_asteroids_*.png

build_asteroids() returns {state: PIL RGBA 480x480}, one tiling field per sun heading:
    asteroids_0 .. asteroids_15   lit from heading 22.5 * i degrees (counter-clockwise from screen east, y up)
The layer tiles, so it cannot be turned like a body: DM picks the state nearest the round's sun,
    icon_state = "asteroids_[round(sun_bearing / 22.5) % 16]"
Every heading is the same field (same rocks, places and spins); only the light moves.

The rocks: star-convex lumps (an ellipsoid with a noisy radius, dented by craters), ray-marched, shaded in linear light with a
soft terminator, a faint rim on the sun side and almost nothing on the night side. Mostly small: a power law of sizes with
few big ones, so the field reads as distant rubble with depth, not a wall of dark blobs.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bodies as b  # noqa: E402

TILE = b.TILE
HEADINGS = 16
SUN_Z = 0.30          # the sun a little in front of the field: lit sides a bit more than half


def rock_geometry(seed, R, ss=3):
    """Hit depth, normals, albedo and coverage for one rock of radius about R output pixels, on a supersampled grid."""
    rng = np.random.default_rng(seed)
    half = int(np.ceil(R * 1.45)) + 2
    size = half * 2 * ss
    yy, xx = np.mgrid[0:size, 0:size].astype(float) + 0.5
    X = (xx - size / 2) / (R * ss)
    Y = -(yy - size / 2) / (R * ss)
    axes = np.array([1.0, rng.uniform(0.55, 0.9), rng.uniform(0.45, 0.8)])
    frame = b.rot(*rng.uniform(0, 360, 3))
    lumpy = rng.uniform(0.18, 0.34)
    kind = rng.uniform()
    # crater sites on the rock (its own frame)
    nc = int(rng.integers(3, 9))
    cdir = rng.normal(size=(3, nc))
    cdir /= np.linalg.norm(cdir, axis=0)
    csize = rng.uniform(0.18, 0.5, nc)

    def radius(q):
        n = q / np.maximum(np.linalg.norm(q, axis=0), 1e-9)
        r = 1 + lumpy * b.fbm(n, seed, 1.1, 3) + 0.06 * b.fbm(n, seed + 1, 4.0, 3)
        ang = np.arccos(np.clip(cdir.T @ n, -1, 1))               # (craters, points)
        t = ang / csize[:, None]
        bowl = np.where(t < 1, (t * t - 1) * 0.07, 0.025 * np.exp(-((t - 1.15) / 0.18) ** 2))   # dish and a low rim
        return r + (bowl * csize[:, None] * 3).sum(0)

    def to_rock(px, py, pz):
        p = np.stack([px, py, pz])
        return (frame @ p) / axes[:, None]

    r2 = X * X + Y * Y
    cand = r2 < 1.45 ** 2
    xs, ys = X[cand], Y[cand]
    steps = 44
    zs = np.linspace(1.45, -1.45, steps)
    hit = np.full(xs.size, np.nan)
    prev_in = np.zeros(xs.size, bool)
    prev_z = np.full(xs.size, zs[0])
    for z in zs:
        todo = np.isnan(hit)
        if not todo.any():
            break
        q = to_rock(xs[todo], ys[todo], np.full(todo.sum(), z))
        inside = np.linalg.norm(q, axis=0) < radius(q)
        idx = np.flatnonzero(todo)[inside]
        # refine between the last outside step and this one
        lo = prev_z[idx]
        hi = np.full(idx.size, z)
        for _ in range(9):
            mid = (lo + hi) / 2
            qm = to_rock(xs[idx], ys[idx], mid)
            ins = np.linalg.norm(qm, axis=0) < radius(qm)
            hi = np.where(ins, mid, hi)
            lo = np.where(ins, lo, mid)
        hit[idx] = (lo + hi) / 2
        prev_z[todo] = z
    depth = np.full((size, size), np.nan)
    depth[cand] = hit
    cover = ~np.isnan(depth)
    # normals from the depth's slope; edge pixels borrow their neighbours' depth so the slope stays sane
    d = np.where(cover, depth, np.nan)
    filled = d.copy()
    for _ in range(2):
        nb = np.nanmean(np.stack([np.roll(filled, s, a) for s in (1, -1) for a in (0, 1)]), axis=0)
        filled = np.where(np.isnan(filled), nb, filled)
    filled = np.where(np.isnan(filled), -1.5, filled)
    filled = b.gauss_blur(filled[..., None], 0.7 * ss)[..., 0]    # march steps leave a fine grain: smooth it out
    gy, gx = np.gradient(filled)
    k = R * ss
    nx, ny = -gx * k, gy * k
    nrm = np.stack([nx, ny, np.ones_like(nx)])
    nrm /= np.linalg.norm(nrm, axis=0)
    # albedo: carbon-dark, stony or grey-metal rocks, mottled, darker in crater floors
    q = to_rock(X[cover], Y[cover], depth[cover])
    if kind < 0.55:
        base = b.lin((74, 68, 62))
    elif kind < 0.88:
        base = b.lin((112, 98, 84))
    else:
        base = b.lin((128, 126, 124))
    mott = 1 + 0.25 * b.fbm(q, seed + 2, 3.0, 4) + 0.12 * b.fbm(q, seed + 3, 9.0, 3)
    alb = np.zeros((size, size, 3))
    alb[cover] = base * mott[:, None]
    return dict(R=R, ss=ss, size=size, cover=cover, nrm=nrm, alb=alb, Z=np.where(cover, 1.0, 0.0))


def shade(g, heading):
    """One rock lit from `heading` degrees on screen: premultiplied linear RGBA at output size."""
    th = np.radians(heading)
    L = np.array([np.cos(th), np.sin(th), SUN_Z])
    L /= np.linalg.norm(L)
    nrm, cover = g['nrm'], g['cover']
    dg = np.tensordot(L, nrm, axes=1)
    lam = np.clip(dg, 0, None) * b.smoothstep(-0.05, 0.25, dg)
    # rim: the sun-side silhouette catches light skimming the surface; soft, warm-white
    edge = (1 - np.clip(nrm[2], 0, 1)) ** 2.5
    rim = edge * np.clip(nrm[0] * L[0] + nrm[1] * L[1], 0, None) * 0.35
    col = g['alb'] * (lam * 3.6 + 0.006)[..., None] + (rim[..., None] * np.array([1.0, 0.92, 0.82]) * g['alb'] * 4)
    col = b.rolloff(col, knee=0.6)
    a = cover.astype(float)
    pre = np.concatenate([col * a[..., None], a[..., None]], axis=-1)
    ss = g['ss']
    n = g['size'] // ss
    return pre.reshape(n, ss, n, ss, 4).mean(axis=(1, 3))


def field_plan(seed=7):
    """Where the rocks sit and how big: a power law of sizes, far fewer big ones, loosely clustered, nothing piled up."""
    rng = np.random.default_rng(seed)
    sizes = []
    sizes += list(rng.uniform(1.2, 2.6, 42))     # specks
    sizes += list(rng.uniform(2.8, 5.5, 22))     # small
    sizes += list(rng.uniform(6.0, 10.0, 9))     # medium
    sizes += list(rng.uniform(12.0, 18.0, 3))    # the few big ones
    sizes.sort(reverse=True)
    # loose clusters: a few drift centres, rocks scattered round them (wrapping), a share scattered anywhere
    centres = rng.uniform(0, TILE, (4, 2))
    placed = []
    for R in sizes:
        for _ in range(200):
            if rng.uniform() < 0.6:
                c = centres[rng.integers(len(centres))]
                x, y = (c + rng.normal(0, 70, 2)) % TILE
            else:
                x, y = rng.uniform(0, TILE, 2)
            ok = True
            for (px, py, pr) in placed:
                dx = min(abs(x - px), TILE - abs(x - px))
                dy = min(abs(y - py), TILE - abs(y - py))
                if np.hypot(dx, dy) < (R + pr) * 1.6 + 4:
                    ok = False
                    break
            if ok:
                placed.append((x, y, R))
                break
    return placed


def build_asteroids(headings=HEADINGS, seed=7):
    plan = field_plan(seed)
    geos = [rock_geometry(1000 + i, R, ss=4 if R < 4 else 3) for i, (_, _, R) in enumerate(plan)]
    out = {}
    for h in range(headings):
        heading = 360.0 * h / headings
        acc = np.zeros((TILE, TILE, 4))
        for (x, y, R), g in zip(plan, geos):
            spr = shade(g, heading)
            n = spr.shape[0]
            x0, y0 = int(round(x)) - n // 2, int(round(y)) - n // 2
            ys = (np.arange(n) + y0) % TILE
            xs = (np.arange(n) + x0) % TILE
            region = acc[np.ix_(ys, xs)]
            acc[np.ix_(ys, xs)] = spr + region * (1 - spr[..., 3:4])     # premultiplied over (wraps at the tile edge)
        a = np.clip(acc[..., 3:4], 0, 1)
        rgb = b.srgb(np.clip(acc[..., :3] / np.maximum(a, 1e-6), 0, 1))
        a8 = np.clip(np.floor(a * 255 + 0.5), 0, 255)
        rgb8 = np.clip(np.floor(rgb * 255 + 0.5), 0, 255)
        rgb8[a8[..., 0] == 0] = 0
        out['asteroids_%d' % h] = Image.fromarray(np.concatenate([rgb8, a8], axis=-1).astype(np.uint8), 'RGBA')
    return out


def preview():
    os.makedirs(b.PREVIEW, exist_ok=True)
    states = build_asteroids()
    bg = b.star_background()
    W, H = bg.shape[1], bg.shape[0]
    # one heading over stars at game scale, tiled as the layer tiles
    for h in (0, 4, 10):
        im = states['asteroids_%d' % h]
        big = Image.new('RGBA', (TILE * 3, TILE * 3))
        for i in range(3):
            for j in range(3):
                big.paste(im, (i * TILE, j * TILE))
        tiled = Image.fromarray((bg * 255 + 0.5).astype(np.uint8), 'RGB').convert('RGBA')
        tiled.alpha_composite(big.crop((70, 30, 70 + W, 30 + H)))
        path = os.path.join(b.PREVIEW, 'sky2_body_asteroids_h%d.png' % h)
        tiled.convert('RGB').save(path)
        print(os.path.relpath(path, b.sg.ROOT))
    # the old field next to the new one, same view
    tg = b.Dmi.from_file(os.path.join(b.sg.ROOT, 'icons', 'effects', 'parallax.dmi'))
    old = tg.get_state('asteroids').frames[0].convert('RGBA')
    pair = Image.new('RGB', (TILE * 2, TILE))
    for i, im in enumerate((old, states['asteroids_0'])):
        v = Image.fromarray((bg[:TILE, :TILE] * 255 + 0.5).astype(np.uint8), 'RGB').convert('RGBA')
        v.alpha_composite(im)
        pair.paste(v.convert('RGB'), (i * TILE, 0))
    d = ImageDraw.Draw(pair)
    d.text((6, 4), 'old asteroids', fill=(220, 220, 220))
    d.text((TILE + 6, 4), 'v2 asteroids_0 (sun east)', fill=(220, 220, 220))
    path = os.path.join(b.PREVIEW, 'sky2_body_asteroids_compare.png')
    pair.save(path)
    print(os.path.relpath(path, b.sg.ROOT))
    # zoom of the biggest rocks under four headings
    plan = field_plan()
    g = rock_geometry(1000, plan[0][2])
    row = [Image.fromarray(np.clip(b.srgb(np.clip(shade(g, h)[..., :3] / np.maximum(shade(g, h)[..., 3:4], 1e-6), 0, 1)) * shade(g, h)[..., 3:4] * 255, 0, 255).astype(np.uint8), 'RGB')
           for h in (0, 90, 180, 270)]
    z = Image.new('RGB', (sum(r.width * 6 for r in row), row[0].height * 6), (4, 5, 9))
    for i, r in enumerate(row):
        z.paste(r.resize((r.width * 6, r.height * 6), Image.NEAREST), (i * r.width * 6, 0))
    path = os.path.join(b.PREVIEW, 'sky2_body_asteroids_rock_zoom.png')
    z.save(path)
    print(os.path.relpath(path, b.sg.ROOT))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'preview':
        preview()
    else:
        print(__doc__)
