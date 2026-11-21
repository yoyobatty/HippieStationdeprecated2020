#!/usr/bin/env python3
"""Sky bodies, v2: every single thing in the sky generated here - lit planets, far galaxies, a sun glare that stays a point.

    python tools/sky_gen/v2/bodies.py preview   writes data/previews/sky2_body_<state>.png (each body over the current star
                                                sheets, at game size) and data/previews/sky2_body_strip.png (old | new per state)

build_bodies() gives {state: PIL RGBA 480x480}, the same shape sky_gen.ported_bodies() gives, plus 'sun' (an opaque additive
image like sky_gen's, white: the game tints it), an extra 'world_gas', and galaxy/galaxy2/galaxy3/galaxy4 (glow with alpha by
brightness, replacing tg's icons/effects/parallax.dmi art: the galaxy layer has to point at sky_bodies.dmi to use them).

How a planet is made. Every surface is 3D noise read on the sphere itself (no map, so no seams and no pinched poles). Light is
worked in linear values from one sun direction (composed under LIGHT, baked turned so the sun is east: build_bodies(light_angle)),
then rolled off by the brightest
channel so a bright patch keeps its hue instead of clipping to cream, then encoded to sRGB.
  - Surface: albedo, a height field (bump-shaded, so craters and ridges catch the light), clouds that cast shadows, ocean glint.
  - Air: marched along each line of sight through an exponential shell; sunlit air scatters (the rim, the soft terminator),
    and the surface behind it is dimmed by the same air (limb darkening). Airless bodies get Lambert's own darkening only.
  - Lavaland: lava rivers (zero lines of smooth noise) and crust-plate cracks (Voronoi borders) emit light of their own, hotter
    down the middle; the emission is strongest on the night side, blooms a little, and lights the ash haze from below.
  - Each world may be lit from a different height (light_at): the angle on screen is always LIGHT's, so one DM turn fits all.
Galaxies: a bulge, a disc with patchy logarithmic arms and spurs, star-forming knots, dust lanes, a bar or a mid-plane lane.
Everything is seeded, so a rebuild gives the same pixels.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sky_gen as sg  # noqa: E402  (read-only: helpers and the old bodies for the before/after)
from dmi import Dmi  # noqa: E402  (sky_gen put tools/mapmerge2 on the path)

TILE = sg.TILE


def unit(*v):
    v = np.array(v, dtype=float)
    return v / np.linalg.norm(v)


# The sun's direction, seen from the screen: x right, y up, z toward the viewer. The game puts the sun at a random bearing, so
# the DM side can turn a body to face it (see the report at the bottom of preview).
LIGHT = unit(-0.80, 0.42, 0.40)
# The bodies were composed under LIGHT (from 152 degrees: counter-clockwise from screen east, y up). They are baked turned so the
# sun comes from BAKE_ANGLE instead: the whole picture turns (surface, glow, haze), so nothing about the look changes but its
# heading. Default east (0): the game turns each body toward its round's sun (see build_bodies).
AUTHOR_ANGLE = float(np.degrees(np.arctan2(LIGHT[1], LIGHT[0])))
BAKE_ANGLE = 0.0


# ---------------------------------------------------------------- colour

def lin(rgb):
    """sRGB 0..255 to linear."""
    c = np.asarray(rgb, dtype=float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def rolloff(rgb, knee=0.55):
    """Linear up to the knee, then eases toward 1 by the brightest channel, the others scaled with it: hue kept, nothing clips."""
    m = rgb.max(axis=-1, keepdims=True)
    over = np.clip(m - knee, 0, None)
    m2 = np.where(m > knee, knee + (1 - knee) * (1 - np.exp(-over / (1 - knee))), m)
    return rgb * (m2 / np.maximum(m, 1e-9))


def ramp(t, stops):
    """Piecewise-linear colour ramp: stops = [(t, (r, g, b) linear), ...]."""
    ts = [s[0] for s in stops]
    return np.stack([np.interp(t, ts, [s[1][ch] for s in stops]) for ch in range(3)], axis=-1)


def mix(a, b, t):
    """Blends colours by a per-point weight (the weight gets the colour axis)."""
    t = np.asarray(t, dtype=float)
    if t.ndim:
        t = t[..., None]
    return a * (1 - t) + b * t


smoothstep = sg.smoothstep


# ---------------------------------------------------------------- 3D noise on the sphere

_GRAD = np.array([[1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0], [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
                  [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1]], dtype=float)


def _hash(ix, iy, iz, seed):
    m = 0xFFFFFFFF
    h = ((ix * 0x8DA6B343) ^ (iy * 0xD8163841) ^ (iz * 0xCB1AB31F) ^ (seed * 0x165667B1)) & m
    h ^= h >> 15
    h = (h * 0x2C1B3C6D) & m
    h ^= h >> 12
    h = (h * 0x297A2D39) & m
    h ^= h >> 15
    return h


def perlin(p, seed):
    """Gradient noise at points p (3, n). Roughly -1..1."""
    x, y, z = p
    xi, yi, zi = np.floor(x), np.floor(y), np.floor(z)
    fx, fy, fz = x - xi, y - yi, z - zi
    xi, yi, zi = xi.astype(np.int64), yi.astype(np.int64), zi.astype(np.int64)
    u, v, w = [t * t * t * (t * (t * 6 - 15) + 10) for t in (fx, fy, fz)]
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                g = _GRAD[_hash(xi + dx, yi + dy, zi + dz, seed) % 12]
                d = g[:, 0] * (fx - dx) + g[:, 1] * (fy - dy) + g[:, 2] * (fz - dz)
                wt = (u if dx else 1 - u) * (v if dy else 1 - v) * (w if dz else 1 - w)
                out = out + d * wt
    return out


def fbm(p, seed, freq, octaves, gain=0.5, lac=2.07):
    """Fractal noise, roughly -1..1."""
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * perlin(p * freq, seed * 31 + o)
        norm += amp
        amp *= gain
        freq *= lac
    return total / norm * 1.6


def ridged(p, seed, freq, octaves, gain=0.5, lac=2.07):
    """Ridged fractal noise, 0..1: sharp crests where the noise crosses zero."""
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * (1 - np.abs(perlin(p * freq, seed * 37 + o))) ** 2
        norm += amp
        amp *= gain
        freq *= lac
    return total / norm


def warped(p, seed, freq, strength, octaves=4):
    """Points pushed around by three noise fields: features drawn out into flows instead of round blobs."""
    q = np.stack([fbm(p, seed + k, freq, octaves) for k in range(3)])
    return p + q * strength


def stretch(f, lo=1.0, hi=99.0):
    """Rescales a field to 0..1 by its percentiles, so a threshold means the same share of surface whatever the seed."""
    a, b = np.percentile(f, [lo, hi])
    return np.clip((f - a) / (b - a), 0, 1)


def swirl(p, centre, size, turns):
    """Turns points round an axis through `centre`, more near it: a cyclone, for cloud fields."""
    c = unit(*centre)
    d = np.clip(c @ p, -1, 1)
    ang = np.arccos(d)
    theta = turns * 2 * np.pi * np.exp(-(ang / size) ** 2)
    cos_t, sin_t = np.cos(theta), np.sin(theta)
    cx = np.cross(c[:, None].T, p.T).T
    return p * cos_t + cx * sin_t + c[:, None] * d * (1 - cos_t)


def cell_edges(p, seed, count):
    """Distance (radians, roughly) to the nearest border between Voronoi cells of `count` random sites on the sphere."""
    rng = np.random.default_rng(seed)
    # sites kept apart (dart throwing): two sites close together would make a sliver cell that fills in solid
    spacing = np.sqrt(4 * np.pi / count) * 0.55
    sites = []
    while len(sites) < count:
        c = rng.normal(size=3)
        c /= np.linalg.norm(c)
        if not sites or (np.asarray(sites) @ c).max() < np.cos(spacing):
            sites.append(c)
    sites = np.asarray(sites)
    q = p / np.linalg.norm(p, axis=0)
    b1 = np.full(q.shape[1], -2.0)
    b2 = np.full(q.shape[1], -2.0)
    for chunk in range(0, count, 64):
        d = sites[chunk:chunk + 64] @ q                 # cosines, bigger is nearer
        for row in d:
            better = row > b1
            b2 = np.where(better, b1, np.maximum(b2, row))
            b1 = np.where(better, row, b1)
    a1 = np.arccos(np.clip(b1, -1, 1))
    a2 = np.arccos(np.clip(b2, -1, 1))
    return (a2 - a1) * 0.5


def great_arcs(p, seed, count, wmin, wmax):
    """Long cracks along pieces of great circles (Europa's lineae): (dark band, bright centre ridge), 0..1 each."""
    rng = np.random.default_rng(seed)
    band = np.zeros(p.shape[1])
    ridge = np.zeros(p.shape[1])
    q = p / np.linalg.norm(p, axis=0)
    for _ in range(count):
        a = rng.normal(size=3)
        a /= np.linalg.norm(a)
        c = np.cross(a, rng.normal(size=3))
        c /= np.linalg.norm(c)
        b = np.cross(a, c)
        dist = np.abs(np.arcsin(np.clip(a @ q, -1, 1)))
        along = np.arctan2(b @ q, c @ q)
        half = rng.uniform(0.5, 1.6)
        w = np.maximum((wmin + (wmax - wmin) * rng.uniform() ** 2) * smoothstep(half, half * 0.6, np.abs(along)), 1e-6)
        on = smoothstep(w, w * 0.45, dist) * (w > 1e-5)
        band = np.maximum(band, on * rng.uniform(0.6, 1.0))
        if w.max() > wmax * 0.6:
            ridge = np.maximum(ridge, smoothstep(w * 0.28, w * 0.05, dist) * (w > 1e-5))
    return band, ridge


def craters(p, seed, count, rmin, rmax, depth, slope=2.2, fresh=0.25):
    """Impact craters on the unit sphere: (height, albedo boost). Radii (radians) by a power law, so most are small."""
    rng = np.random.default_rng(seed)
    h = np.zeros(p.shape[1])
    bright = np.zeros(p.shape[1])
    for _ in range(count):
        c = rng.normal(size=3)
        c /= np.linalg.norm(c)
        u = rng.uniform()
        rad = (rmin ** (1 - slope) + u * (rmax ** (1 - slope) - rmin ** (1 - slope))) ** (1 / (1 - slope))
        d = c @ p
        near = d > np.cos(min(rad * 2.6, np.pi))
        if not near.any():
            continue
        t = np.arccos(np.clip(d[near], -1, 1)) / rad
        dep = depth * rad ** 0.85 * rng.uniform(0.6, 1.2)
        bowl = np.where(t < 1, (t * t - 1) * 0.9, 0) + 0.32 * np.exp(-((t - 1) / 0.2) ** 2) + 0.06 * np.exp(-((t - 1.3) / 0.6) ** 2)
        if rad > rmax * 0.45:  # big ones get a central peak and a flat floor
            bowl = np.where(t < 1, np.maximum(bowl, -0.55) + 0.25 * np.exp(-(t / 0.15) ** 2), bowl)
        h[near] += dep * bowl
        if rng.uniform() < fresh:
            bright[near] += np.exp(-((t - 1.05) / 0.5) ** 2) * (t < 2.6) * rng.uniform(0.4, 1.0)
    return h, bright


# ---------------------------------------------------------------- image helpers

def gauss_blur(img, sigma):
    """Gaussian blur of an (h, w[, c]) array with zero padding (FFT)."""
    pad = int(3 * sigma) + 1
    a = np.pad(img, ((pad, pad), (pad, pad)) + ((0, 0),) * (img.ndim - 2))
    fy = np.fft.fftfreq(a.shape[0])
    fx = np.fft.rfftfreq(a.shape[1])
    k = np.exp(-2 * (np.pi * sigma) ** 2 * (fy[:, None] ** 2 + fx[None, :] ** 2))
    if a.ndim == 3:
        k = k[..., None]
    out = np.fft.irfft2(np.fft.rfft2(a, axes=(0, 1)) * k, s=a.shape[:2], axes=(0, 1))
    return out[pad:-pad, pad:-pad]


def rot(ax, ay, az):
    """Rotation matrix: about x, then y, then z (degrees)."""
    ax, ay, az = np.radians([ax, ay, az])
    rx = np.array([[1, 0, 0], [0, np.cos(ax), -np.sin(ax)], [0, np.sin(ax), np.cos(ax)]])
    ry = np.array([[np.cos(ay), 0, np.sin(ay)], [0, 1, 0], [-np.sin(ay), 0, np.cos(ay)]])
    rz = np.array([[np.cos(az), -np.sin(az), 0], [np.sin(az), np.cos(az), 0], [0, 0, 1]])
    return rz @ ry @ rx


# ---------------------------------------------------------------- the renderer

class Surface:
    """What a body is made of, at points p (3, n) on the unit sphere in its own frame. Each field over those points."""
    albedo = None      # (n, 3) linear
    height = None      # (n,) in planet radii, for bump shading
    emission = None    # (n, 3) linear light of its own (lava)
    ocean = None       # (n,) 0..1 where water glints
    cloud = None       # (n,) 0..1 cover
    cloud_fn = None    # p -> cover, for cloud shadows


def render(R, surface_fn, *, ss=3, light=LIGHT, frame=None, bump=1.0, atmosphere=None, exposure=1.0,
           bloom=None, ambient=(0.0006, 0.0007, 0.0010), pad=1.22, night_glow=None, night_emission=0.3, limb=0.0, terminator=(-0.02, 0.10)):
    """Draws a body of radius R pixels lit from `light`. Returns a straight-alpha RGBA PIL image (size about 2*R*pad).

    atmosphere: dict(colour=linear rgb, scale_height (radii), top (radii above surface), density, extinction=rgb,
                     twilight=linear rgb, sunset=0..1)
    """
    frame = np.eye(3) if frame is None else frame
    # turn the whole scene on screen so the light comes from BAKE_ANGLE: the body's frame turns with it
    turn = np.radians(AUTHOR_ANGLE - BAKE_ANGLE)
    rz = np.array([[np.cos(turn), -np.sin(turn), 0], [np.sin(turn), np.cos(turn), 0], [0, 0, 1]])
    frame = frame @ rz
    light = rz.T @ np.asarray(light, dtype=float)
    half = int(np.ceil(R * pad))
    size = half * 2 * ss
    c = size / 2.0
    yy, xx = np.mgrid[0:size, 0:size].astype(float) + 0.5
    X = (xx - c) / (R * ss)
    Y = -(yy - c) / (R * ss)
    r2 = X * X + Y * Y
    inside = r2 < 1.0
    Z = np.sqrt(np.clip(1 - r2, 0, 1))
    L = np.asarray(light, dtype=float)

    n_scr = np.stack([X[inside], Y[inside], Z[inside]])           # normals on screen
    p = frame @ n_scr                                              # the same points in the body's frame
    s = surface_fn(p)
    npts = p.shape[1]

    # bump: the height field's slope on screen, laid into the tangent plane
    nrm = n_scr.copy()
    if s.height is not None and bump:
        hg = np.zeros((size, size))
        hg[inside] = s.height
        gy, gx = np.gradient(hg)
        k = R * ss * bump
        gxi, gyi = gx[inside] * k, -gy[inside] * k
        zf = np.clip(Z[inside], 0, 1) ** 0.5                    # foreshortened at the limb: keep the bumps from shouting there
        g = np.stack([gxi, gyi, np.zeros(npts)]) * zf
        g -= (g * nrm).sum(0) * nrm
        nrm = nrm - g
        nrm /= np.linalg.norm(nrm, axis=0)

    dg = L @ n_scr                       # the sphere's own facing: the terminator
    d = np.clip(L @ nrm, 0, None)
    lit = d * smoothstep(terminator[0], terminator[1], dg)   # the bumped light, cut at the terminator (soft on deep air)
    albedo = s.albedo if s.albedo is not None else np.full((npts, 3), 0.2)

    col = albedo * lit[:, None]
    # clouds: shadow on the ground first, then the cloud lit on top
    if s.cloud is not None:
        Lb = frame @ L
        if s.cloud_fn is not None:
            shadow = s.cloud_fn(p + Lb[:, None] * 0.018)
            col *= (1 - 0.55 * shadow)[:, None]
        cl = s.cloud[:, None]
        cloud_lit = np.clip(dg, 0, None) * 0.92 + 0.0
        col = col * (1 - cl) + cl * np.array([0.78, 0.80, 0.82]) * cloud_lit[:, None]
    # water glint
    if s.ocean is not None:
        Hv = unit(*(L + np.array([0, 0, 1.0])))
        nh = np.clip(Hv @ nrm, 0, 1)
        fres = 0.03 + 0.25 * (1 - np.clip(n_scr[2], 0, 1)) ** 5
        glint = (nh ** 60 * 0.22 + nh ** 18 * 0.006) * (1 - (s.cloud if s.cloud is not None else 0)) * s.ocean * (1 + fres * 4)
        col += glint[:, None] * smoothstep(0.0, 0.15, dg)[:, None] * np.array([1.0, 0.95, 0.88])
    col += np.asarray(ambient) * np.sqrt(albedo / 0.2)   # faint fill on the night side; bright ice must not glow grey
    if limb:  # deep atmospheres (gas giants) darken toward the edge on their own
        col *= (np.clip(n_scr[2], 0, 1) ** limb)[:, None]

    night = smoothstep(0.18, -0.12, dg)
    emis = np.zeros((npts, 3))
    if s.emission is not None:
        emis = s.emission * (night_emission + (1 - night_emission) * night)[:, None]
        if s.cloud is not None:
            emis *= (1 - 0.6 * s.cloud)[:, None]

    # the air: marched along each line of sight, front of the shell to the ground (or out the back)
    surf_grid = np.zeros((size, size, 3))
    emis_grid = np.zeros((size, size, 3))
    inscatter = np.zeros((size, size, 3))
    trans_grid = np.ones((size, size, 3))
    if atmosphere:
        a = atmosphere
        top = 1 + a['top']
        H = a['scale_height']
        ext = np.asarray(a.get('extinction', (1, 1, 1)), dtype=float)
        shell = r2 < top * top
        zf = np.sqrt(np.clip(top * top - r2, 0, None))
        zb = np.where(inside, Z, -zf)
        steps = 40
        ds = (zf - zb) / steps
        tau = np.zeros((size, size))
        acc = np.zeros((size, size, 3))
        twilight = np.asarray(a.get('twilight', a['colour']), dtype=float)
        for i in range(steps):
            z = zf - (i + 0.5) * ds
            rr = np.sqrt(r2 + z * z)
            dens = np.exp(-np.clip(rr - 1, 0, None) / H) * shell
            cosl = (X * L[0] + Y * L[1] + z * L[2]) / np.maximum(rr, 1e-6)
            # the shell's own day and night: soft across the terminator (the twilight band), but air deeper in the planet's
            # shadow cylinder stays dark, so the night side carries no false glow
            qdl = cosl * rr
            perp = np.sqrt(np.clip(rr * rr - qdl * qdl, 0, None))
            core = (qdl < 0) * smoothstep(0.9995, 0.975, perp)
            sun = smoothstep(a.get('penumbra', -0.14), 0.22, cosl) * (1 - core)
            dusk = np.exp(-((cosl - 0.02) / 0.13) ** 2)            # light that skimmed a long way through the air: reddened
            tint = mix(np.asarray(a['colour'], float), twilight, dusk * a.get('sunset', 0.6))
            seen = np.exp(-tau)[..., None] * np.exp(-tau[..., None] * (ext - 1) * 0.5)
            step_light = (dens * ds)[..., None] * sun[..., None] * tint * seen
            if night_glow is not None:  # lava light from below, on the night side
                step_light += (dens * ds)[..., None] * (1 - sun)[..., None] * np.asarray(night_glow) * seen
            acc += step_light
            tau += dens * ds * a['density']
        inscatter = acc * a['density'] * a.get('brightness', 1.0)
        trans_grid = np.exp(-tau[..., None] * ext * a.get('veil', 0.6))

    surf_grid[inside] = col
    emis_grid[inside] = emis
    if bloom:
        glow = np.zeros_like(emis_grid)
        for sigma, amount in bloom:
            glow += gauss_blur(emis_grid, sigma * ss) * amount
        emis_total = emis_grid + glow
    else:
        emis_total = emis_grid
    light_out = (surf_grid + emis_grid) * trans_grid + inscatter + (emis_total - emis_grid)
    light_out = rolloff(light_out * exposure)

    # alpha: the disc is opaque; outside it, the glow stands in for its own light over a dark sky
    m = light_out.max(axis=-1)
    # the disc's own edge is feathered over about one output pixel, so it never reads as a cut-out with a pixel outline
    edge = np.clip((1 - np.sqrt(r2)) * R / 0.9 + 0.15, 0, 1)
    alpha = np.where(inside, np.maximum(edge, np.clip(m, 0, 1)), np.clip(m, 0, 1))
    straight = np.where(inside[..., None], light_out, light_out / np.maximum(alpha[..., None], 1e-6))
    # downsample in linear, premultiplied
    pre = np.concatenate([straight * alpha[..., None], alpha[..., None]], axis=-1)
    n = size // ss
    pre = pre.reshape(n, ss, n, ss, 4).mean(axis=(1, 3))
    a_out = pre[..., 3:4]
    rgb = srgb(np.clip(pre[..., :3] / np.maximum(a_out, 1e-6), 0, 1))
    rng = np.random.default_rng(int(R * 1000) % 9973)
    noise = rng.uniform(-0.5, 0.5, rgb.shape[:2])[..., None]
    rgb8 = np.clip(np.floor(rgb * 255 + 0.5 + noise), 0, 255)
    a8 = np.clip(np.floor(a_out * 255 + 0.5 + noise), 0, 255)
    a8[a8 < 2] = 0
    rgb8[a8[..., 0] == 0] = 0
    return Image.fromarray(np.concatenate([rgb8, a8], axis=-1).astype(np.uint8), 'RGBA')


# ---------------------------------------------------------------- Lavaland

def lava_surface(p):
    s = Surface()
    w = warped(p, 11, 1.3, 0.38)
    base = stretch(fbm(w, 12, 2.0, 7, gain=0.52))
    mott = fbm(p, 13, 9.0, 4)
    region = stretch(fbm(p, 14, 1.1, 3))                     # where the volcanism is: some faces quieter
    # basalt and ash: dark, uneven, low contrast; a rusty tinge on the ash plains
    basalt = lin((40, 35, 33))
    ash = lin((92, 82, 74))
    rust = lin((96, 66, 50))
    albedo = mix(basalt, ash, smoothstep(0.25, 0.85, base) * 0.85)
    albedo = mix(albedo, rust, (smoothstep(0.55, 0.9, stretch(fbm(w, 15, 1.7, 4))) * 0.45))
    # old basalt flows: dark lobes with crisp edges, and fine grit, so the day side has detail of its own
    flows = smoothstep(0.58, 0.64, stretch(fbm(warped(p, 16, 3.0, 0.12), 17, 3.2, 6, gain=0.55)))
    albedo = mix(albedo, lin((30, 27, 27)), flows * 0.55)
    albedo *= (1 + 0.12 * mott + 0.08 * fbm(p, 18, 24.0, 3))[:, None]
    # the lava. Rivers: the zero line of a smooth, warped field (few octaves, so they bend instead of wiggling), wide only
    # where the ground is active. Cracks: the borders of crust plates (Voronoi cells on the sphere), big plates over the active
    # faces, small ones in the hottest parts. Widths are angles: one pixel at the disc's centre is about 1/R.
    w2 = warped(p, 21, 1.1, 0.35, octaves=3)
    river = 1 - np.abs(fbm(w2, 22, 1.3, 3, gain=0.45))
    eps = (0.004 + 0.030 * smoothstep(0.35, 0.95, region)) * (0.6 + 0.8 * stretch(fbm(p, 29, 3.0, 2)))
    rivers = smoothstep(1 - eps, 1 - eps * 0.2, river) * smoothstep(0.08, 0.4, region)
    e1 = cell_edges(warped(warped(p, 23, 3.0, 0.045), 27, 14.0, 0.006, octaves=2), 24, 140)
    # plate cracks taper and break: width wanders along a crack and some stretches are shut, so they never close into a
    # drawn net of polygons
    taper = 0.35 + 1.0 * stretch(fbm(p, 34, 5.0, 3))
    open_ = smoothstep(0.32, 0.5, stretch(fbm(warped(p, 35, 2.0, 0.1), 36, 3.5, 3)))
    plates = smoothstep(0.0075 * taper, 0.0012 * taper, e1) * smoothstep(0.30, 0.62, region) * open_
    # seen from far off, the small crust cells are a fine hot mesh, not a net of drawn lines: thin, dimmer, broken up
    e2 = cell_edges(warped(p, 25, 6.0, 0.02), 26, 900)
    small = smoothstep(0.0045, 0.0016, e2) * smoothstep(0.65, 0.92, region) * 0.45 * smoothstep(0.3, 0.6, stretch(fbm(p, 30, 5.0, 3)))
    flicker = 0.45 + 0.55 * stretch(fbm(p, 28, 6.0, 3))   # hotter and cooler stretches along a channel
    heat = np.clip(np.maximum(rivers * 0.85, np.maximum(plates * 0.7, small)), 0, 1) * flicker
    # the middle of a wide channel and of a fresh crack runs hotter: yellow, nearly white where both are widest and hottest
    core = smoothstep(1 - eps * 0.4, 1 - eps * 0.04, river) * smoothstep(0.012, 0.03, eps) * smoothstep(0.08, 0.4, region)
    core = np.maximum(core, smoothstep(0.0035, 0.0006, e1) * smoothstep(0.5, 0.8, region) * 0.6)
    heat = np.clip(heat + core * 0.45 * flicker, 0, 1)
    # vents and lava lakes: hot points scattered over the active faces, the night side's equivalent of city lights
    rng = np.random.default_rng(37)
    vents = rng.normal(size=(3, 90))
    vents /= np.linalg.norm(vents, axis=0)
    dots = vents.T @ p                                            # (vents, points): cosine of the angle to each vent
    size = rng.uniform(0.004, 0.012, 90)[:, None]
    blob = np.exp(-(np.arccos(np.clip(dots, -1, 1)) / size) ** 2).max(axis=0)
    heat = np.clip(np.maximum(heat, blob * smoothstep(0.4, 0.75, region) * 0.95), 0, 1)
    # crust: cooled lava next to a channel is darker and a little red
    crust = smoothstep(1 - eps * 4, 1 - eps, river) * smoothstep(0.08, 0.4, region) + smoothstep(0.03, 0.008, e1) * 0.5 * smoothstep(0.28, 0.6, region)
    albedo = mix(albedo, lin((34, 22, 20)), np.clip(crust, 0, 1) * 0.7)
    albedo = mix(albedo, lin((20, 12, 10)), np.clip(heat * 1.4, 0, 1))
    # by day the active faces show fresh black flows spreading from the channels, and pale sulphur and red-oxide fallout
    # round the vents; the quiet faces stay grey ash. Seen from far off this is what tells an active world from a dead moon
    spread = smoothstep(0.55, 0.85, stretch(fbm(warped(p, 38, 2.5, 0.15), 39, 4.0, 4))) * smoothstep(0.45, 0.8, region)
    albedo = mix(albedo, lin((22, 20, 21)), spread * 0.6)
    fallout = smoothstep(0.62, 0.9, stretch(fbm(p, 41, 7.0, 3))) * smoothstep(0.5, 0.85, region) * (1 - spread)
    albedo = mix(albedo, lin((150, 126, 72)), fallout * 0.35)
    oxide = smoothstep(0.6, 0.9, stretch(fbm(w, 42, 2.4, 4))) * (1 - spread)
    albedo = mix(albedo, lin((120, 58, 36)), oxide * 0.4)
    s.albedo = albedo
    s.emission = ramp(heat, [(0.0, (0, 0, 0)), (0.12, (0.05, 0.004, 0.0)), (0.35, (0.55, 0.07, 0.008)),
                             (0.6, (1.4, 0.30, 0.03)), (0.85, (2.4, 0.85, 0.12)), (1.0, (3.2, 1.6, 0.45))])
    # height: ash plains low, basalt ridges up, a scatter of old craters
    mountains = ridged(warped(p, 31, 1.8, 0.25), 32, 2.2, 6)
    ch, cb = craters(p, 33, 70, 0.02, 0.16, 0.05, fresh=0.1)
    s.height = (base - 0.5) * 0.010 + (mountains - 0.5) * 0.016 + flows * 0.002 - rivers * 0.004 - plates * 0.002 + ch * 0.8
    s.albedo = s.albedo * (1 + 0.25 * cb)[:, None]
    return s


LAVA_AIR = dict(colour=lin((255, 170, 120)) * 1.0, twilight=lin((255, 110, 60)), scale_height=0.014, top=0.09, density=1.25,
                extinction=(0.8, 1.0, 1.25), sunset=0.7, brightness=1.0, veil=0.12)


def planet_lava(R=128):
    # side-lit (sun nearly square to the line of sight): about half the disc is night, so the lava reads as lava at game
    # scale, not a brown ball with a glowing rim
    return render(R, lava_surface, ss=2, frame=rot(20, 160, 8), bump=1.6, atmosphere=LAVA_AIR, exposure=1.6, light=light_at(0.0),
                  bloom=[(1.2, 0.6), (4, 0.3), (10, 0.06)], night_glow=lin((255, 80, 30)) * 0.1, night_emission=0.14,
                  ambient=(0.0005, 0.0006, 0.0009), limb=0.2)


# ---------------------------------------------------------------- the other worlds

def ice_surface(p):
    s = Surface()
    w = warped(p, 41, 1.4, 0.30)
    base = stretch(fbm(w, 42, 2.2, 6))
    s.albedo = mix(lin((178, 190, 200)), lin((228, 234, 240)), smoothstep(0.2, 0.8, base))
    s.albedo = mix(s.albedo, lin((150, 170, 192)), smoothstep(0.6, 0.95, stretch(fbm(p, 43, 1.5, 4))) * 0.5)
    # lineae: long cracks stained a rusty brown, Europa-style, in two scales
    band, ridge = great_arcs(warped(p, 44, 2.0, 0.04), 45, 34, 0.006, 0.026)
    band2, _ = great_arcs(warped(p, 46, 1.6, 0.22), 47, 60, 0.003, 0.009)   # bent hard: the curved (cycloid) cracks
    lineae = np.clip(band + 0.6 * band2, 0, 1)
    stain = mix(lin((150, 108, 84)), lin((120, 74, 52)), stretch(fbm(p, 50, 3.0, 3)))
    s.albedo = mix(s.albedo, lin((176, 146, 126)), smoothstep(0.55, 0.85, stretch(fbm(warped(p, 51, 2.0, 0.2), 52, 2.4, 6))) * 0.4)
    s.albedo = mix(s.albedo, stain, lineae * 0.8)
    s.albedo = mix(s.albedo, lin((222, 222, 226)), ridge * 0.7)   # the bright double ridge down the middle of a wide one
    chaos = smoothstep(0.75, 0.9, stretch(fbm(p, 48, 3.0, 5)))
    s.albedo = mix(s.albedo, lin((140, 120, 110)), chaos * 0.45)
    ch, cb = craters(p, 49, 25, 0.02, 0.09, 0.02, fresh=0.6)
    s.height = (base - 0.5) * 0.004 + ridge * 0.002 - band * 0.001 + ch * 0.6
    s.albedo *= (1 + 0.15 * cb)[:, None]
    return s


ICE_AIR = dict(colour=lin((170, 200, 255)), twilight=lin((200, 210, 255)), scale_height=0.02, top=0.07, density=0.4,
               extinction=(0.7, 0.85, 1.0), sunset=0.2, brightness=1.0, veil=0.2)


def earthlike(p, seed, land_share, land, highland, coast, ice_cap, cloud_cover, cyclones):
    s = Surface()
    w = warped(p, seed, 1.2, 0.45, octaves=5)
    elev = stretch(fbm(w, seed + 1, 1.6, 8, gain=0.55))
    sea = np.quantile(elev, 1 - land_share)
    landm = smoothstep(sea - 0.004, sea + 0.004, elev)
    up = np.clip((elev - sea) / (1 - sea), 0, 1)
    lat = np.abs(p[1])
    tone = stretch(fbm(p, seed + 2, 4.0, 5))
    lnd = mix(land[0], land[1], smoothstep(0.3, 0.8, tone))
    lnd = mix(lnd, highland, smoothstep(0.35, 0.8, up) * 0.8)
    lnd = mix(lnd, coast, smoothstep(0.08, 0.0, up) * 0.5)
    deep = np.clip((sea - elev) / max(sea, 1e-6), 0, 1)
    water = mix(lin((24, 60, 92)), lin((6, 18, 44)), smoothstep(0.0, 0.25, deep))
    water = mix(water, lin((40, 112, 128)), smoothstep(0.05, 0.0, deep) * 0.55)   # shallows round the coasts
    s.albedo = mix(water, lnd, landm)
    cap = smoothstep(ice_cap - 0.04, ice_cap + 0.02, lat + 0.06 * fbm(p, seed + 3, 3.0, 4))
    s.albedo = mix(s.albedo, lin((232, 238, 244)), cap)
    s.ocean = (1 - landm) * (1 - cap)
    s.height = landm * (1 - cap) * (up * 0.012 + (ridged(w, seed + 4, 3.0, 5) - 0.5) * 0.008 * up)

    def cloud_fn(q):
        for centre, size, turns in cyclones:
            q = swirl(q, centre, size, turns)
        qq = q * np.array([1.0, 1.8, 1.0])[:, None]          # stretched along the latitudes, like weather
        f = fbm(warped(qq, seed + 5, 1.5, 0.35), seed + 6, 2.2, 7, gain=0.55)
        g = 0.5 + 0.5 * f
        cut = 1 - cloud_cover
        big = smoothstep(cut - 0.02, cut + 0.28, g) * (0.75 + 0.25 * smoothstep(0.4, 0.9, g))
        # fair-weather cumulus: small puffs in rows, thin, everywhere the big systems aren't
        puffs = smoothstep(0.62, 0.8, 0.5 + 0.5 * fbm(warped(qq, seed + 7, 4.0, 0.05), seed + 8, 10.0, 3)) * 0.45
        return np.maximum(big, puffs * smoothstep(0.85, 0.4, np.abs(q[1])))
    s.cloud_fn = cloud_fn
    s.cloud = cloud_fn(p)
    return s


def jungle_surface(p):
    return earthlike(p, 61, 0.48, (lin((36, 66, 26)), lin((58, 84, 34))), lin((96, 92, 64)), lin((120, 128, 80)),
                     0.93, 0.56, [((0.4, 0.3, 0.86), 0.22, 0.55), ((-0.6, -0.45, 0.6), 0.16, -0.45)])


def ocean_surface(p):
    return earthlike(p, 71, 0.07, (lin((48, 82, 36)), lin((76, 100, 50))), lin((120, 116, 90)), lin((150, 150, 110)),
                     0.88, 0.50, [((0.25, 0.45, 0.85), 0.20, 0.42), ((-0.5, -0.2, 0.85), 0.15, -0.35), ((0.7, -0.5, 0.5), 0.12, -0.3)])


EARTH_AIR = dict(colour=lin((120, 165, 255)), twilight=lin((255, 160, 110)), scale_height=0.02, top=0.1, density=1.15,
                 extinction=(0.45, 0.7, 1.0), sunset=0.15, brightness=1.0, veil=0.30)


def ray_systems(p, seed, centres, reaches):
    """Bright rays thrown out from young craters (centres in the body's frame, placed where they're seen): streaks along
    great circles from each, broken up along their length, fading with distance."""
    rng = np.random.default_rng(seed)
    out = np.zeros(p.shape[1])
    for _, (centre, reach) in enumerate(zip(centres, reaches)):
        c = unit(*centre)
        a = np.cross(c, rng.normal(size=3))
        a /= np.linalg.norm(a)
        b = np.cross(c, a)
        ang = np.arccos(np.clip(c @ p, -1, 1))
        az = np.arctan2(b @ p, a @ p)
        # many thin rays of different lengths: noise round the crater, sharpened, each ray with its own reach
        k = rng.integers(22, 34)
        streaks = np.zeros(p.shape[1])
        for r in range(k):
            th = rng.uniform(-np.pi, np.pi)
            wid = rng.uniform(0.015, 0.05)
            dth = np.angle(np.exp(1j * (az - th)))
            ln = reach * rng.uniform(0.4, 1.0)
            streaks = np.maximum(streaks, np.exp(-(dth / wid) ** 2) * smoothstep(ln, ln * 0.3, ang) * rng.uniform(0.4, 1.0))
        streaks *= smoothstep(0.25, 0.65, 0.5 + 0.5 * fbm(p, seed * 7 + _, 9.0, 3))   # broken up along their length
        halo = np.exp(-(ang / (reach * 0.07)) ** 2) * 0.8
        out = np.maximum(out, np.maximum(streaks * smoothstep(0.02, 0.06, ang), halo) * rng.uniform(0.6, 1.0))
    return out


def rock_surface(p):
    """An airless moon: bright cratered highlands, a few dark smooth maria with crisp shores, ray craters."""
    s = Surface()
    w = warped(p, 81, 1.3, 0.3)
    base = stretch(fbm(w, 82, 2.0, 7))
    mfield = stretch(fbm(warped(p, 83, 1.0, 0.4), 84, 1.3, 6, gain=0.55))
    maria = smoothstep(0.64, 0.68, mfield)
    s.albedo = mix(lin((124, 120, 114)), lin((168, 164, 156)), smoothstep(0.2, 0.9, base))
    s.albedo = mix(s.albedo, mix(lin((62, 62, 64)), lin((84, 80, 76)), stretch(fbm(p, 88, 5.0, 4))), maria * 0.85)
    ch, cb = craters(p, 185, 520, 0.012, 0.22, 0.06, fresh=0.25)
    ch2, cb2 = craters(p, 86, 1600, 0.008, 0.035, 0.05, fresh=0.15)
    rays = ray_systems(p, 92, [(0.656, 0.358, 0.664), (0.698, -0.688, 0.201)], [0.8, 0.45])
    s.height = (base - 0.5) * 0.006 * (1 - maria) + ch * (1 - 0.6 * maria) + ch2 * (1 - 0.5 * maria) + maria * -0.002
    s.albedo *= (1 + 0.25 * (cb + 0.6 * cb2) + 0.07 * fbm(p, 87, 12, 3))[:, None]
    s.albedo = mix(s.albedo, lin((226, 224, 220)), np.clip(rays * 1.1, 0, 1) * 0.75)
    return s


def redrock_surface(p):
    s = Surface()
    w = warped(p, 91, 1.2, 0.4)
    base = stretch(fbm(w, 92, 1.8, 7))
    dark = smoothstep(0.5, 0.85, stretch(fbm(warped(p, 93, 1.4, 0.45), 94, 1.6, 7, gain=0.58)))
    dark *= 0.7 + 0.3 * stretch(fbm(warped(p, 89, 6.0, 0.03), 88, 6.0, 4))   # wind-streaked, not a flat cut-out
    s.albedo = mix(lin((176, 98, 58)), lin((206, 132, 84)), smoothstep(0.2, 0.85, base))
    s.albedo = mix(s.albedo, lin((86, 52, 36)), dark * 0.85)
    # one great canyon system, not a net: the zero line of smooth noise, only where a second field allows it
    # a rift system: a few straight troughs along great circles, ragged walls
    # wide enough to read as a trough with a lit wall from far off, not a scratched line
    canyon, _ = great_arcs(warped(p, 95, 4.0, 0.02), 96, 3, 0.016, 0.034)
    canyon *= smoothstep(0.3, 0.7, stretch(fbm(p, 90, 1.0, 2)))
    s.albedo = mix(s.albedo, lin((128, 72, 48)), canyon * 0.35)
    cap = smoothstep(0.945, 0.965, p[1] + 0.025 * fbm(p, 97, 5.0, 4)) * 0.92
    s.albedo = mix(s.albedo, lin((236, 228, 222)), cap)
    ch, cb = craters(p, 98, 160, 0.012, 0.13, 0.04, fresh=0.1)
    s.height = (base - 0.5) * 0.010 + ch * 0.8 - canyon * 0.010 + (ridged(w, 99, 3.0, 4) - 0.5) * 0.004
    return s


MARS_AIR = dict(colour=lin((240, 190, 160)), twilight=lin((140, 170, 230)), scale_height=0.022, top=0.08, density=0.6,
                extinction=(0.75, 0.85, 1.0), sunset=0.4, brightness=1.0, veil=0.25)


def gas_surface(p):
    """Belts and zones of uneven width with wavy, sheared edges, fine streaks drawn out along the latitudes, eddies at the
    band edges, a chain of white ovals, a big red oval with a pale collar, and mottled poles."""
    s = Surface()
    rng = np.random.default_rng(116)
    # zonal flow: everything is drawn out east-west, so noise is read on points squeezed along the latitudes
    flat = p * np.array([1.0, 7.0, 1.0])[:, None]
    eddy_sites = [(rng.uniform(-1, 1), rng.uniform(-0.7, 0.7), rng.uniform(-0.2, 1)) for _ in range(40)]
    q = p
    for c in eddy_sites:
        q = swirl(q, c, rng.uniform(0.025, 0.06), rng.choice([-1, 1]) * rng.uniform(0.12, 0.4))
    # and many small ones of every size, so the hooks along a band edge never repeat
    erng = np.random.default_rng(130)
    for _ in range(70):
        c = (erng.uniform(-1, 1), erng.uniform(-0.8, 0.8), erng.uniform(-0.2, 1))
        q = swirl(q, c, erng.uniform(0.008, 0.03), erng.choice([-1, 1]) * erng.uniform(0.1, 0.9))
    lat = q[1] + 0.03 * fbm(flat, 117, 1.6, 5) + 0.006 * fbm(q * np.array([1.0, 4.0, 1.0])[:, None], 118, 10.0, 3)
    # band edges in sin(latitude), uneven: a belt here and there, zones between
    widths = rng.gamma(2.2, 1.0, 14)
    widths[7] *= 2.2                                    # a broad zone at the equator
    edges = np.concatenate([[-1.0], -0.93 + 1.86 * np.cumsum(widths)[:-1] / widths.sum(), [1.0]])
    zones = [lin(c) for c in ((236, 226, 206), (228, 214, 190), (232, 222, 204))]
    belts = [lin(c) for c in ((206, 172, 138), (192, 150, 116), (218, 190, 156), (196, 180, 166), (212, 166, 126), (200, 160, 128))]
    albedo = np.zeros((p.shape[1], 3))
    weight = np.zeros(p.shape[1])
    for k in range(len(edges) - 1):
        lo, hi = edges[k], edges[k + 1]
        soft = 0.014 + 0.018 * rng.uniform()             # soft edges: belts shade into zones, never clip-art fills
        inband = smoothstep(lo - soft, lo + soft, lat) * smoothstep(hi + soft, hi - soft, lat)
        colour = belts[rng.integers(len(belts))] if k % 2 else zones[rng.integers(len(zones))] * rng.uniform(0.96, 1.02)
        albedo += inband[:, None] * colour
        weight += inband
    albedo /= np.maximum(weight, 1e-6)[:, None]
    # streaks and festoons: ridged noise drawn out along the flow, strongest near the band edges
    edge_near = np.zeros(p.shape[1])
    for e in edges[1:-1]:
        edge_near = np.maximum(edge_near, np.exp(-((lat - e) / 0.03) ** 2))
    streak = ridged(warped(q * np.array([1.0, 9.0, 1.0])[:, None], 119, 1.2, 0.25), 120, 2.4, 5)
    fine = fbm(warped(q * np.array([1.0, 16.0, 1.0])[:, None], 127, 2.0, 0.2), 128, 6.0, 4)   # thin threads inside every band
    albedo *= (1 + (0.16 + 0.22 * edge_near) * (streak - 0.5) + 0.10 * fbm(flat, 121, 3.0, 5) + 0.05 * fbm(p, 126, 2.0, 2)
               + 0.12 * fine - 0.05 * edge_near)[:, None]
    festoon = smoothstep(0.62, 0.8, ridged(warped(flat, 122, 2.0, 0.4), 123, 3.0, 3)) * edge_near
    albedo = mix(albedo, lin((120, 132, 150)), festoon * 0.25)
    # white ovals in a chain along one southern belt edge
    chain = edges[np.argmin(np.abs(edges + 0.45))]
    for k in range(5):
        lon = -0.9 + 0.45 * k + rng.uniform(-0.1, 0.1)
        c = unit(np.sin(lon), chain, np.cos(lon))
        d = np.arccos(np.clip(c @ p, -1, 1))
        albedo = mix(albedo, lin((240, 236, 228)), smoothstep(0.045, 0.02, d) * 0.85)
    # the big oval: a pale collar, a red body, turning inside
    spot_c = unit(-0.32, -0.30, 0.90)
    qs = swirl(p, spot_c, 0.16, 0.6)
    d = np.sqrt(np.arccos(np.clip(spot_c @ p, -1, 1)) ** 2 * 0.35 + ((p[1] - spot_c[1]) / 0.55) ** 2 * 0.65 * 2.6)
    inner = 0.8 + 0.3 * fbm(qs * np.array([1.0, 2.0, 1.0])[:, None], 124, 10.0, 4)
    albedo = mix(albedo, lin((244, 232, 214)), smoothstep(0.19, 0.12, d) * 0.6)
    albedo = mix(albedo, lin((196, 104, 70)) * inner[:, None], smoothstep(0.125, 0.06, d) * 0.85)
    # poles: no bands left, a darker blue-grey mottle
    pole = smoothstep(0.78, 0.92, np.abs(p[1]))
    albedo = mix(albedo, lin((150, 146, 142)) * (1 + 0.15 * fbm(p, 125, 8.0, 4))[:, None], pole * 0.7)
    s.albedo = albedo
    return s


GAS_AIR = dict(penumbra=-0.04, colour=lin((220, 200, 175)), twilight=lin((255, 170, 120)), scale_height=0.03, top=0.08, density=0.7,
               extinction=(0.7, 0.85, 1.0), sunset=0.4, brightness=0.8, veil=0.45)


WORLD_R = 58


def light_at(z):
    """LIGHT's direction on screen with a different height out of the screen: a body further round toward the sun's side is
    seen more side-lit (thinner lit part, longer shadows). The angle on screen stays the same, so one DM turn fits all."""
    xy = LIGHT[:2] / np.linalg.norm(LIGHT[:2]) * np.sqrt(1 - z * z)
    return np.array([xy[0], xy[1], z])


WORLDS = {
    'world_ice': lambda R: render(R, ice_surface, frame=rot(30, 40, 10), bump=1.0, atmosphere=ICE_AIR, exposure=1.05),
    'world_jungle': lambda R: render(R, jungle_surface, frame=rot(18, 200, -12), bump=1.0, atmosphere=EARTH_AIR, exposure=1.25),
    'world_rock': lambda R: render(R, rock_surface, frame=rot(10, 70, 0), bump=2.0, atmosphere=None, exposure=1.35, light=light_at(0.22)),
    'world_redrock': lambda R: render(R, redrock_surface, frame=rot(-25, 120, 6), bump=1.1, atmosphere=MARS_AIR, exposure=1.2),
    'world_ocean': lambda R: render(R, ocean_surface, frame=rot(-15, 30, 14), bump=1.0, atmosphere=EARTH_AIR, exposure=1.25),
    'world_gas': lambda R: render(int(R * 1.35), gas_surface, frame=rot(0, 0, -12), bump=0, atmosphere=GAS_AIR, exposure=1.2, limb=0.35, terminator=(-0.10, 0.32)),
}


def build_worlds_only(state, R=WORLD_R):
    """One world, for looking at while tuning."""
    return WORLDS[state](R)


def build_worlds(R=WORLD_R):
    return {state: make(R) for state, make in WORLDS.items()}


# ---------------------------------------------------------------- galaxies

def galaxy(seed, radius, incl, pa, arms=2, pitch=14, bar=0.0, bulge=0.12, arm_strength=1.0, dust=1.0, arm_dust=1.0, knots=60,
           n=TILE, ss=2, exposure=1.0):
    """A galaxy seen from far off: a warm bulge, a disc with logarithmic spiral arms (blue-white, knotted with pink star-forming
    regions), dust lanes on the arms' inner edges, an optional bar. incl/pa in degrees; radius in pixels.
    Returns (h, w, 3) linear light; the alpha comes from the light itself, as for the haze round a planet."""
    rng = np.random.default_rng(seed)
    size = n * ss
    yy, xx = np.mgrid[0:size, 0:size].astype(float) + 0.5
    x = (xx - size / 2) / (radius * ss)
    y = -(yy - size / 2) / (radius * ss)
    c, s_ = np.cos(np.radians(pa)), np.sin(np.radians(pa))
    xr, yr = x * c + y * s_, -x * s_ + y * c                 # along the major axis, across it
    ci = np.cos(np.radians(incl))
    u, v = xr, yr / max(ci, 0.16)                            # in the disc's own plane (a disc has thickness: edge-on isn't a line)
    r = np.hypot(u, v)
    th = np.arctan2(v, u)
    pts = np.stack([u.ravel(), v.ravel(), np.zeros(u.size)])
    noise = fbm(pts * 1.0, seed, 2.5, 5).reshape(u.shape)
    fine = fbm(pts, seed + 1, 22.0, 3).reshape(u.shape)
    tight = 1 / np.tan(np.radians(pitch))
    phase = th - np.log(r + 0.04) * tight + noise * 0.9
    patchy = smoothstep(-0.3, 0.6, fbm(pts, seed + 2, 5.0, 4).reshape(u.shape))
    arm = (0.5 + 0.5 * np.cos(arms * phase)) ** 2.4 * (0.45 + 0.75 * patchy)
    spurs = (0.5 + 0.5 * np.cos(2 * arms * phase + noise * 2.5)) ** 4 * 0.35 * patchy   # feathers between the main arms
    arm = np.clip(arm + spurs, 0, 1.2)
    lane = (0.5 + 0.5 * np.cos(arms * phase - 0.55)) ** 12 * (0.5 + 0.5 * patchy)       # dust just inside each arm
    disc = np.exp(-r / 0.26) * smoothstep(1.15, 0.7, r)
    arm_zone = smoothstep(0.08 + bar * 0.9, 0.28 + bar * 0.9, r)   # arms start where the bulge or bar ends
    # bulge: a round-ish spheroid on screen, a hot little nucleus
    rb = np.hypot(xr, yr / (0.75 + 0.25 * ci))
    bul = np.exp(-(rb / bulge) ** 0.8 * 2.2) + 2.5 * np.exp(-(rb / (bulge * 0.12)) ** 2)
    warm = np.array([1.0, 0.80, 0.56])
    cool = np.array([0.70, 0.80, 1.0])
    light = bul[..., None] * warm * 1.1
    armed = arm * arm_zone * arm_strength
    grain = 0.75 + 0.5 * np.clip(0.5 + 0.5 * fine, 0, 1)    # resolved star clouds: the arms are grainy, not smooth
    light += (disc * (0.35 + 1.6 * armed * grain))[..., None] * mix(warm * 0.9, cool, np.clip(armed * 1.4, 0, 1))
    if bar:
        bar_l = np.exp(-(np.abs(u) / bar) ** 2.5 - (v / (bar * 0.28)) ** 2)
        light += (bar_l * 0.55)[..., None] * warm
    # star-forming knots strung along the arms
    flat = (disc * armed).ravel()
    if knots and flat.sum() > 0:
        pick = rng.choice(flat.size, size=knots, p=flat / flat.sum())
        ky, kx = np.unravel_index(pick, u.shape)
        for py, px in zip(ky, kx):
            sz = rng.uniform(0.6, 1.6) * ss
            y0, y1 = max(0, py - 6 * ss), min(size, py + 6 * ss)
            x0, x1 = max(0, px - 6 * ss), min(size, px + 6 * ss)
            g = np.exp(-((yy[y0:y1, x0:x1] - py - 0.5) ** 2 + (xx[y0:y1, x0:x1] - px - 0.5) ** 2) / (2 * sz * sz))
            tint = np.array([1.0, 0.55, 0.75]) if rng.uniform() < 0.6 else np.array([0.75, 0.85, 1.0])
            light[y0:y1, x0:x1] += g[..., None] * tint * rng.uniform(0.2, 0.6) * disc[py, px] ** 0.3
    # dust: lanes inside the arms, and across the near side of a tilted disc a lane along the major axis
    tau = dust * arm_dust * (lane * arm_zone * disc * 2.2 + np.clip(0.5 + 0.5 * noise, 0, 1) * disc * 0.4)
    if incl > 70:
        thick = 0.022 + 0.012 * (1 + noise) * 0.5
        tau += dust * 3.0 * np.exp(-((yr + 0.02) / thick) ** 2) * smoothstep(1.0, 0.5, np.abs(xr)) * (0.6 + 0.4 * (0.5 + 0.5 * noise))
    light *= np.exp(-tau)[..., None] * np.array([1.0, 0.95, 0.85]) ** (tau[..., None] * 0.5)  # dust reddens what it dims
    light = rolloff(light * exposure, knee=0.45)
    light *= smoothstep(n * ss / 2, n * ss / 2 - 30 * ss, np.hypot(xx - size / 2, yy - size / 2))[..., None]
    return light.reshape(n, ss, n, ss, 3).mean(axis=(1, 3))


def glow_image(light, seed):
    """Light over a dark sky as a straight-alpha image: alpha by the brightest channel (black stays clear)."""
    a = np.clip(light.max(axis=-1, keepdims=True), 0, 1)
    rgb = srgb(np.clip(light / np.maximum(a, 1e-6), 0, 1))
    rng = np.random.default_rng(seed)
    noise = rng.uniform(-0.5, 0.5, a.shape)
    a8 = np.clip(np.floor(srgb(a) * 255 + 0.5 + noise), 0, 255)  # alpha in sRGB steps too: faint outskirts don't band
    a_lin = lin(a8)
    rgb = srgb(np.clip(light / np.maximum(a_lin, 1e-6), 0, 1))
    rgb8 = np.clip(np.floor(rgb * 255 + 0.5 + noise), 0, 255)
    rgb8[a8[..., 0] == 0] = 0
    return Image.fromarray(np.concatenate([rgb8, a8], axis=-1).astype(np.uint8), 'RGBA')


def build_galaxies():
    """The far galaxy a theme can show (state names as the old tg ones, so themes keep working)."""
    return {
        'galaxy': glow_image(galaxy(301, 150, 28, 20, arms=2, pitch=15, bulge=0.10, exposure=0.8), 301),
        'galaxy2': glow_image(galaxy(302, 140, 50, -35, arms=2, pitch=18, bar=0.32, bulge=0.08, exposure=0.85), 302),
        'galaxy3': glow_image(galaxy(303, 175, 66, 32, arms=2, pitch=16, bulge=0.11, arm_dust=0.7, exposure=0.85), 303),
        'galaxy4': glow_image(galaxy(304, 185, 88, -14, arms=3, pitch=16, bulge=0.17, dust=1.4, arm_dust=0.15, arm_strength=0.3, knots=20, exposure=1.0), 304),
    }


# ---------------------------------------------------------------- the sun

def sun_glare_v2(n=TILE):
    """A nearby star seen without a lens burning: a tiny hot core, a halo that falls off as a power law, thin faint rays.
    The core alone reaches full white, and only within a few pixels: tinted by the game it reads as a point, not a cream disc."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    dx = xx - n / 2 + 0.5
    dy = yy - n / 2 + 0.5
    r = np.hypot(dx, dy)
    core = 2.5 * np.exp(-(r / 2.6) ** 2)
    halo = 0.75 / (1 + (r / 5.0) ** 2) ** 1.1 + 0.24 / (1 + (r / 30.0) ** 2) + 0.05 * np.exp(-r / 120.0)
    taper = 1 / (1 + (r / 10.0) ** 2) ** 0.2
    rays = (np.exp(-(dy / 0.9) ** 2) * np.exp(-np.abs(dx) / 90.0) + np.exp(-(dx / 0.9) ** 2) * np.exp(-np.abs(dy) / 90.0)) * 0.30 * taper
    rays += (np.exp(-((dx - dy) / 1.2) ** 2) + np.exp(-((dx + dy) / 1.2) ** 2)) * np.exp(-r / 30.0) * 0.10 * taper
    total = core + halo + rays
    total *= smoothstep(n / 2.0, n / 2.0 - 50, r)
    # roll off near white (a slightly warm halo, a white core: the game's tint does the colour)
    rgb = np.stack([total * 1.0, total * 0.985, total * 0.96], axis=-1)
    return rolloff(rgb, knee=0.5)


# ---------------------------------------------------------------- the set

def build_bodies(light_angle=0.0):
    """light_angle: where the sun is, degrees counter-clockwise from screen east (y up). 0 bakes every body lit from the east;
    the game then turns each one to its sun: transform = matrix().Turn(-sun_angle) (BYOND turns clockwise)."""
    global BAKE_ANGLE
    old_angle, BAKE_ANGLE = BAKE_ANGLE, float(light_angle)
    try:
        return _build_bodies()
    finally:
        BAKE_ANGLE = old_angle


def _build_bodies():
    """{state: PIL RGBA 480x480}: planet_lava, world_ice/jungle/rock/redrock/ocean (+ world_gas), galaxy/galaxy2-4, sun."""
    out = {'planet_lava': sg.centred(planet_lava())}
    for state, image in build_worlds().items():
        out[state] = sg.centred(image)
    out.update(build_galaxies())
    out['sun'] = sg.additive_image(sun_glare_v2(), 31)
    return out


# ---------------------------------------------------------------- previews

PREVIEW = os.path.join(sg.ROOT, 'data', 'previews')
VIEW_W, VIEW_H = 608, 480


def star_background(seed=3):
    d = Dmi.from_file(os.path.join(sg.OUT_DIR, 'sky.dmi'))
    rng = np.random.default_rng(seed)
    out = np.zeros((VIEW_H, VIEW_W, 3)) + np.array([0.008, 0.010, 0.018])
    for state in ('stars_deep', 'stars_far', 'stars_mid', 'stars_near'):
        ox, oy = rng.integers(0, TILE, 2)
        out += sg.tile_to(sg.as_float(d.get_state(state).frames[0]), VIEW_W, VIEW_H, ox, oy)
    return np.clip(out, 0, 1)


def over(bg, image, state, tint='#ffd2a8'):
    """A body on the view as the game draws it: alpha over, or added (the sun, tinted)."""
    out = bg.copy()
    arr = np.asarray(image.convert('RGBA'), dtype=float) / 255.0
    left, top = (VIEW_W - TILE) // 2, (VIEW_H - TILE) // 2
    view = out[top:top + TILE, left:left + TILE]
    if state == 'sun':
        view += arr[..., :3] * sg.hex_rgb(tint)
    else:
        a = arr[..., 3:4]
        view[:] = view * (1 - a) + arr[..., :3] * a
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')


def preview():
    os.makedirs(PREVIEW, exist_ok=True)
    new = build_bodies()
    old = sg.ported_bodies()
    old['sun'] = sg.additive_image(sg.sun_glare(), 31)
    tg = Dmi.from_file(os.path.join(sg.ROOT, 'icons', 'effects', 'parallax.dmi'))
    for state in ('galaxy', 'galaxy2', 'galaxy3', 'galaxy4'):
        old[state] = tg.get_state(state).frames[0].convert('RGBA')
    bg = star_background()
    for state, image in new.items():
        path = os.path.join(PREVIEW, 'sky2_body_%s.png' % state)
        over(bg, image, state).save(path)
        print(os.path.relpath(path, sg.ROOT))
    states = list(new)
    strip = Image.new('RGB', (VIEW_W * 2, VIEW_H * len(states)), (0, 0, 0))
    draw = ImageDraw.Draw(strip)
    for i, state in enumerate(states):
        strip.paste(over(bg, old[state], state) if state in old else Image.fromarray((bg * 255 + 0.5).astype(np.uint8), 'RGB'),
                    (0, i * VIEW_H))
        strip.paste(over(bg, new[state], state), (VIEW_W, i * VIEW_H))
        draw.text((8, i * VIEW_H + 6), ('%s  old' % state if state in old else '%s  (no old state)' % state), fill=(200, 200, 200))
        draw.text((VIEW_W + 8, i * VIEW_H + 6), '%s  v2' % state, fill=(200, 200, 200))
    path = os.path.join(PREVIEW, 'sky2_body_strip.png')
    strip.save(path)
    print(os.path.relpath(path, sg.ROOT))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'preview':
        preview()
    else:
        print(__doc__)
