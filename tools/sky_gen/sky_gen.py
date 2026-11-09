#!/usr/bin/env python3
"""Builds the generated sky art: star fields, twinkle groups, nebula clouds, dust, sun glare, comet and gas giants.

    python tools/sky_gen/sky_gen.py build      writes hippiestation/icons/effects/sky.dmi, sky_nebula.dmi and sky_bodies.dmi
    python tools/sky_gen/sky_gen.py preview    writes data/previews/sky_<theme>.png, one composite per sky theme
    python tools/sky_gen/sky_gen.py check      fails if the committed sheets differ from what this script builds

Everything is seeded, so a rebuild gives the same pixels. Every tile wraps on both axes: the noise is made in frequency space
(periodic by construction) and stars are drawn with wrap-around. Nebula clouds are greyscale and drawn additively, so the game
tints each one with a theme colour (hippiestation/code/_onclick/hud/sky_themes.dm, which the previews read their colours from).
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'mapmerge2'))
from dmi import Dmi  # noqa: E402

TILE = 480  # a parallax tile, the same as tg's
OUT_DIR = os.path.join(ROOT, 'hippiestation', 'icons', 'effects')


# ---------------------------------------------------------------- noise

def spectral(n, beta, seed, lo=1.0, hi=None):
    """Periodic fractal noise, n x n, 0..1. Power falls as k^-beta; lo/hi cut the band of feature sizes."""
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(n) * n
    k = np.hypot(f[:, None], f[None, :])
    amp = np.zeros_like(k)
    keep = k >= lo
    if hi is not None:
        keep &= k <= hi
    amp[keep] = k[keep] ** (-beta / 2.0)
    phase = rng.uniform(0, 2 * np.pi, (n, n))
    field = np.fft.ifft2(amp * np.exp(1j * phase)).real
    a, b = np.percentile(field, [0.5, 99.5])
    return np.clip((field - a) / (b - a), 0, 1)


def sample_wrap(field, x, y):
    """Bilinear sample of a periodic field at float coordinates."""
    n = field.shape[0]
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    x0 %= n
    y0 %= n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    return (field[y0, x0] * (1 - fx) * (1 - fy) + field[y0, x1] * fx * (1 - fy)
            + field[y1, x0] * (1 - fx) * fy + field[y1, x1] * fx * fy)


def warp(field, seed, strength, beta=3.2, lo=1.0, hi=12):
    """Pushes a field around by two other noise fields: turns blobs into drawn-out wisps."""
    n = field.shape[0]
    u = spectral(n, beta, seed, lo, hi) - 0.5
    v = spectral(n, beta, seed + 1, lo, hi) - 0.5
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    return sample_wrap(field, xx + u * strength, yy + v * strength)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- stars

# (weight, colour) by star class, hot to cool. Slightly more saturated than the real thing so the colours read at one pixel.
STAR_CLASSES = [
    (0.07, (150, 175, 255)),
    (0.13, (190, 208, 255)),
    (0.22, (240, 242, 255)),
    (0.22, (255, 244, 226)),
    (0.20, (255, 214, 160)),
    (0.16, (255, 172, 120)),
]


def star_colours(rng, count):
    weights = np.array([c[0] for c in STAR_CLASSES])
    picks = rng.choice(len(STAR_CLASSES), size=count, p=weights / weights.sum())
    cols = np.array([c[1] for c in STAR_CLASSES], dtype=float)[picks] / 255.0
    return cols * rng.uniform(0.92, 1.0, (count, 1))


def splat(canvas, x, y, colour, core, halo=0.0, halo_size=0.0, spike=0.0, spike_len=0):
    """One star at an integer pixel, drawn with wrap-around. core is the centre pixel's brightness."""
    n = canvas.shape[0]
    radius = int(max(1, np.ceil(halo_size * 3), spike_len))
    ys = np.arange(-radius, radius + 1)
    dy, dx = np.meshgrid(ys, ys, indexing='ij')
    d2 = dx * dx + dy * dy
    # a tight core: the centre pixel and a faint cross of neighbours for the brighter ones
    patch = core * np.exp(-d2 / (2 * 0.42 ** 2)) if core > 0.45 else core * (d2 == 0)
    if halo > 0:
        patch = patch + halo * np.exp(-d2 / (2 * halo_size ** 2))
    if spike > 0 and spike_len:
        fall = np.exp(-np.abs(dx) / (spike_len / 3.0)) * (dy == 0) + np.exp(-np.abs(dy) / (spike_len / 3.0)) * (dx == 0)
        patch = patch + spike * fall
    rows = (y + dy) % n
    cols = (x + dx) % n
    np.add.at(canvas, (rows, cols), patch[..., None] * colour[None, None, :])


def place_stars(rng, count, density, n=TILE):
    """Star positions following a density field (0..1): clusters and thin patches instead of an even scatter."""
    xs = np.empty(0, dtype=int)
    ys = np.empty(0, dtype=int)
    while len(xs) < count:
        cx = rng.integers(0, n, count * 2)
        cy = rng.integers(0, n, count * 2)
        ok = rng.uniform(0, 1, count * 2) < density[cy, cx]
        xs = np.concatenate([xs, cx[ok]])
        ys = np.concatenate([ys, cy[ok]])
    return xs[:count], ys[:count]


def star_layer(seed, count, faint, bright, slope, density_seed, glow_above=2.0, n=TILE):
    """A field of stars. Returns (canvas, stars): stars is a list of (x, y, colour, brightness) for the twinkle picks."""
    rng = np.random.default_rng(seed)
    density = 0.25 + 0.75 * spectral(n, 2.6, density_seed, 1, 10) ** 1.6
    xs, ys = place_stars(rng, count, density, n)
    cols = star_colours(rng, count)
    # many faint, few bright: a power law between faint and bright
    u = rng.uniform(0, 1, count)
    brightness = faint + (bright - faint) * u ** slope
    canvas = np.zeros((n, n, 3))
    stars = []
    for x, y, c, b in zip(xs, ys, cols, brightness):
        if b >= glow_above:
            continue
        splat(canvas, x, y, c, b)
        stars.append((x, y, c, b))
    return canvas, stars


def bright_stars(seed, count, density_seed, n=TILE):
    """The few near stars with a soft halo, and short spikes on the brightest. Returned apart so some can twinkle."""
    rng = np.random.default_rng(seed)
    density = 0.4 + 0.6 * spectral(n, 2.6, density_seed, 1, 8)
    xs, ys = place_stars(rng, count, density, n)
    cols = star_colours(rng, count)
    mags = rng.uniform(0, 1, count) ** 2.2  # mostly modest, a couple of showpieces
    return [(int(x), int(y), c, float(m)) for x, y, c, m in zip(xs, ys, cols, mags)]


def draw_bright(stars, scale=1.0, n=TILE):
    canvas = np.zeros((n, n, 3))
    for x, y, c, m in stars:
        core = (0.75 + 0.5 * m) * scale
        halo = (0.10 + 0.22 * m) * scale
        size = 1.1 + 1.7 * m
        spike = (0.30 * scale) if m > 0.55 else 0.0
        splat(canvas, x, y, c, core, halo, size, spike, int(4 + 7 * m))
    return canvas


# ---------------------------------------------------------------- nebula

def blur(field, sigma):
    """Gaussian blur that wraps at the edges (done in frequency space, so a tile stays a tile)."""
    n = field.shape[0]
    f = np.fft.fftfreq(n)
    k2 = f[:, None] ** 2 + f[None, :] ** 2
    return np.fft.ifft2(np.fft.fft2(field) * np.exp(-2 * (np.pi * sigma) ** 2 * k2)).real


def shoulder(field, gain):
    """Brightens with a soft roll-off, so the bright parts of a cloud keep their shape instead of going flat white."""
    return (1 - np.exp(-np.clip(field, 0, None) * gain)) / (1 - np.exp(-gain))


def region_mask(n, seed, cover):
    """Where a nebula is: very broad noise cut so about `cover` of the tile has cloud, the rest stays black sky."""
    base = spectral(n, 3.4, seed, 1, 4)
    cut = np.quantile(base, 1 - cover)
    return smoothstep(cut - 0.14, cut + 0.30, base)


def cloud_field(n, seed, cover=0.45):
    """Billowing emission cloud: big soft shapes, finer puffs inside them, thin dark dust veins, a glow round the bright parts."""
    big = warp(spectral(n, 3.4, seed, 1, 10), seed + 10, n * 0.10, hi=6)
    mid = warp(spectral(n, 2.8, seed + 20, 4, 64), seed + 30, n * 0.05, hi=10)
    fine = spectral(n, 2.2, seed + 35, 16, None)
    density = big * 0.58 + mid * 0.32 + fine * 0.10
    # dust thins the cloud along veins before it's lit, so a vein has soft sides and whatever was behind it still shows a little
    veins = warp(spectral(n, 3.0, seed + 60, 3, 40), seed + 70, n * 0.08, hi=8)
    density = density - 0.20 * (1 - np.abs(2 * veins - 1)) ** 5
    body = smoothstep(0.34, 0.96, density) ** 1.7
    lit = body + blur(body, n / 80.0) * 0.5 + blur(body, n / 22.0) * 0.35
    return shoulder(lit * region_mask(n, seed + 40, cover), 1.3) * 0.95


def streaks(n, seed, heading, length=44):
    """Fine noise smeared along a flow (line integral convolution): silky strands that run the same way locally.
    The flow is a steady heading bent by swirls. The heading has to win, or strands close into rings round each swirl's middle."""
    swirl = spectral(n, 3.5, seed, 1, 5)
    cx = np.roll(swirl, -1, 0) - np.roll(swirl, 1, 0)
    cy = -(np.roll(swirl, -1, 1) - np.roll(swirl, 1, 1))
    bend = 0.75 / np.mean(np.hypot(cx, cy))
    vx = np.cos(heading) + cx * bend
    vy = np.sin(heading) + cy * bend
    mag = np.hypot(vx, vy) + 1e-9
    vx, vy = vx / mag, vy / mag
    grain = spectral(n, 0.8, seed + 1, 14, None)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    total = grain.copy()
    weight = 1.0
    for sign in (1.0, -1.0):
        px, py = xx.copy(), yy.copy()
        for step in range(1, length + 1):
            px = px + sign * sample_wrap(vx, px, py)
            py = py + sign * sample_wrap(vy, px, py)
            w = 0.5 + 0.5 * np.cos(np.pi * step / (length + 1))
            total += sample_wrap(grain, px, py) * w
            weight += w
    total /= weight
    a, b = np.percentile(total, [1, 99])
    return np.clip((total - a) / (b - a), 0, 1)


def wisp_field(n, seed, heading, cover=0.5):
    """Fibrous sheets, like a supernova's veil: fine strands that follow a flow, there where a faint cloud is and gone where it isn't."""
    strand = smoothstep(0.50, 0.95, streaks(n, seed, heading)) ** 1.8
    sheet = warp(spectral(n, 3.1, seed + 50, 2, 24), seed + 60, n * 0.08, hi=6)
    sheet = smoothstep(0.40, 0.88, sheet)
    lit = strand * sheet
    lit = blur(lit, 0.8) * 0.75 + blur(lit, n / 110.0) * 0.7 + blur(lit, n / 30.0) * 0.7 + sheet ** 2 * 0.07
    return shoulder(lit * region_mask(n, seed + 40, cover), 1.4) * 0.80


def haze_field(n, seed):
    """A broad faint glow with no hard features, to give the black a little colour."""
    base = spectral(n, 3.8, seed, 1, 5)
    return smoothstep(0.30, 1.0, base) ** 1.6 * 0.42


def band_field(n, seed):
    """A galactic band crossing the tile on the diagonal (x + y wraps, so it tiles), with dark dust veins along its middle."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    bend = (spectral(n, 3.4, seed, 1, 5) - 0.5) * n * 0.30
    across = ((xx + yy + bend) % n) / n  # 0..1 across the band's repeat
    dist = np.abs(across - 0.5)
    core = np.exp(-(dist / 0.075) ** 2)
    skirt = np.exp(-(dist / 0.20) ** 2) * 0.30
    mottle = 0.50 + 0.50 * warp(spectral(n, 2.6, seed + 5, 3, None), seed + 6, n * 0.05, hi=10)
    veins = warp(spectral(n, 2.9, seed + 9, 3, 50), seed + 12, n * 0.10, hi=8)
    dust = smoothstep(0.45, 0.80, veins) * np.exp(-(dist / 0.11) ** 2)
    lit = np.clip((core * 0.70 + skirt) * mottle - dust * 0.55, 0, None)
    return shoulder(blur(lit, 0.7), 1.4) * 0.80


def dust_motes(seed, count, n=TILE):
    """Sparse near dust: a few soft specks that slide past quickly and give walking in space a sense of speed."""
    rng = np.random.default_rng(seed)
    canvas = np.zeros((n, n, 3))
    for _ in range(count):
        x, y = rng.integers(0, n, 2)
        b = rng.uniform(0.10, 0.34)
        size = rng.uniform(0.6, 1.3)
        splat(canvas, int(x), int(y), np.array([0.82, 0.88, 1.0]), 0.0, b, size)
    return canvas


# ---------------------------------------------------------------- single things in the sky

def sun_glare(n=TILE):
    """A nearby star: a hard core, two halos and four long thin rays. White; the game tints it."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    dx = xx - n / 2 + 0.5
    dy = yy - n / 2 + 0.5
    r = np.hypot(dx, dy)
    glow = 1.7 * np.exp(-(r / 5.0) ** 2) + 0.60 * np.exp(-r / 20.0) + 0.16 * np.exp(-r / 85.0)
    rays = (np.exp(-np.abs(dy) / 1.3) * np.exp(-np.abs(dx) / 42.0) + np.exp(-np.abs(dx) / 1.3) * np.exp(-np.abs(dy) / 42.0)) * 0.42
    diag = (np.exp(-np.abs(dx - dy) / 1.4) + np.exp(-np.abs(dx + dy) / 1.4)) * np.exp(-r / 20.0) * 0.18
    edge = smoothstep(n / 2.0, n / 2.0 - 40, r)  # nothing left by the edge of the sheet
    return np.repeat(((glow + rays + diag) * edge)[..., None], 3, axis=2)


FLYBY = 160  # fly-by sprites point east: the game turns them to their heading


def meteor():
    """A shooting star: a short bright streak with a hot head."""
    n = FLYBY
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    head_x, mid = 125.0, n / 2 - 0.5
    behind = head_x - xx
    along = np.where(behind >= 0, np.exp(-behind / 26.0), np.exp(-(behind / 1.5) ** 2))
    across = np.exp(-((yy - mid) / 0.75) ** 2)
    streak = along * across + 0.9 * np.exp(-((xx - head_x) ** 2 + (yy - mid) ** 2) / 3.0)
    return streak[..., None] * np.array([0.85, 0.93, 1.0])


def comet():
    """A comet: a soft head and a tail that widens and fades behind it."""
    n = FLYBY
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    head_x, mid = 128.0, n / 2 - 0.5
    behind = np.clip(head_x - xx, 0, None)
    width = 1.2 + behind * 0.085
    tail = np.where(xx <= head_x, np.exp(-behind / 38.0) * np.exp(-((yy - mid) / width) ** 2) / (0.6 + width * 0.35), 0.0)
    head = 1.3 * np.exp(-((xx - head_x) ** 2 + (yy - mid) ** 2) / 4.5) + 0.35 * np.exp(-np.hypot(xx - head_x, yy - mid) / 5.0)
    return (tail * 0.9)[..., None] * np.array([0.55, 0.80, 1.0]) + head[..., None] * np.array([0.90, 0.97, 1.0])


def ship(blink):
    """A ship far off: a white running light, a red one that blinks, a faint blue burn behind. Only a few pixels."""
    n = FLYBY
    canvas = np.zeros((n, n, 3))
    mid = n // 2
    splat(canvas, mid + 2, mid, np.array([1.0, 1.0, 0.95]), 0.85, 0.10, 1.0)
    if blink:
        splat(canvas, mid - 1, mid, np.array([1.0, 0.25, 0.2]), 0.9, 0.16, 1.1)
    for i in range(1, 6):
        splat(canvas, mid - 2 - i, mid, np.array([0.35, 0.6, 1.0]), 0.34 * (1 - i / 6.0))
    return canvas


def premultiplied_resize(image, scale):
    """Resizes an RGBA image without the dark fringe a straight resize leaves round soft edges."""
    arr = np.asarray(image.convert('RGBA'), dtype=float) / 255.0
    arr[..., :3] *= arr[..., 3:4]
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    chans = [np.asarray(Image.fromarray((arr[..., i] * 255).astype(np.uint8), 'L').resize(size, Image.LANCZOS), dtype=float) / 255.0 for i in range(4)]
    out = np.stack(chans, axis=2)
    alpha = np.clip(out[..., 3:4], 1e-6, 1)
    out[..., :3] = np.clip(out[..., :3] / alpha, 0, 1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def centred(image, n=TILE):
    canvas = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    canvas.alpha_composite(image, ((n - image.width) // 2, (n - image.height) // 2))
    return canvas


# Hand-drawn bodies from other SS13 codebases (CC BY-SA 3.0, see ported/README.md): (our state, source sheet, its state, scale)
PORTED = [
    ('planet_lava', 'paradise_parallax.dmi', 'planet_lava', 0.55),
    ('world_ice', 'tgmc_parallax.dmi', 'ice', 0.26),
    ('world_jungle', 'tgmc_parallax.dmi', 'jungle', 0.26),
    ('world_rock', 'tgmc_parallax.dmi', 'rock', 0.26),
    ('world_redrock', 'tgmc_parallax.dmi', 'redrock', 0.26),
    ('world_ocean', 'tgmc_parallax.dmi', 'Palmaria', 0.27),
]


def ported_bodies():
    out = {}
    sheets = {}
    for state, sheet, source, scale in PORTED:
        if sheet not in sheets:
            sheets[sheet] = Dmi.from_file(os.path.join(HERE, 'ported', sheet))
        image = sheets[sheet].get_state(source).frames[0].convert('RGBA')
        box = image.getbbox()
        out[state] = centred(premultiplied_resize(image.crop(box), scale))
    return out


# ---------------------------------------------------------------- output helpers

def dither(arr, seed):
    """Float 0..1 to 8 bit with half a step of noise, so slow gradients in the dark don't band."""
    rng = np.random.default_rng(seed)
    noise = rng.uniform(-0.5, 0.5, arr.shape[:2])
    if arr.ndim == 3:
        noise = noise[..., None]
    return np.clip(np.floor(arr * 255.0 + 0.5 + noise), 0, 255).astype(np.uint8)


def additive_image(rgb, seed):
    """An opaque image for an additive layer: black adds nothing."""
    data = dither(np.clip(rgb, 0, 1), seed)
    alpha = np.full(data.shape[:2] + (1,), 255, dtype=np.uint8)
    return Image.fromarray(np.concatenate([data, alpha], axis=2), 'RGBA')


def grey_image(field, seed):
    return additive_image(np.repeat(np.clip(field, 0, 1)[..., None], 3, axis=2), seed)


# ---------------------------------------------------------------- the set

NEBULA_SIZE = 480  # drawn at twice this on screen (see /obj/screen/parallax_layer/nebula): clouds are soft, the pixels aren't missed
TWINKLE_GROUPS = 3


def build_tiles():
    """Every generated tile, as {sheet: {state: PIL image}}."""
    sky = {}
    # Far to near. Counts and brightness were tuned by eye in the previews.
    deep, _ = star_layer(101, 2600, 0.035, 0.26, 3.0, 901)
    sky['stars_deep'] = additive_image(deep, 1)
    far, _ = star_layer(102, 900, 0.10, 0.62, 3.2, 902)
    sky['stars_far'] = additive_image(far, 2)
    mid, _ = star_layer(103, 330, 0.18, 1.0, 3.0, 903)
    sky['stars_mid'] = additive_image(mid, 3)

    near = bright_stars(104, 46, 904)
    rng = np.random.default_rng(55)
    groups = rng.integers(0, TWINKLE_GROUPS + 1, len(near))  # group 0 never twinkles
    # A twinkling star keeps 55% of its light in the steady layer; the rest is in its group's layer, which fades in and out
    steady = [(x, y, c, m) for (x, y, c, m), g in zip(near, groups) if g == 0]
    base = draw_bright(steady)
    for g in range(1, TWINKLE_GROUPS + 1):
        mine = [s for s, sg in zip(near, groups) if sg == g]
        base += draw_bright(mine, 0.55)
        sky['twinkle%d' % g] = additive_image(draw_bright(mine, 0.60), 10 + g)
    sky['stars_near'] = additive_image(base, 4)
    sky['dust'] = additive_image(dust_motes(105, 70), 5)

    nebula = {}
    n = NEBULA_SIZE
    nebula['cloud1'] = grey_image(cloud_field(n, 201), 21)
    nebula['cloud2'] = grey_image(cloud_field(n, 211, 0.38), 22)
    nebula['cloud3'] = grey_image(cloud_field(n, 221, 0.55), 23)
    nebula['wisp1'] = grey_image(wisp_field(n, 231, 0.45), 24)
    nebula['wisp2'] = grey_image(wisp_field(n, 241, -0.95, 0.6), 25)
    nebula['haze1'] = grey_image(haze_field(n, 251), 26)
    nebula['haze2'] = grey_image(haze_field(n, 261), 27)
    nebula['band'] = grey_image(band_field(n, 271), 28)

    bodies = ported_bodies()
    bodies['sun'] = additive_image(sun_glare(), 31)

    flyby = {
        'meteor': additive_image(meteor(), 41),
        'comet': additive_image(comet(), 42),
        'ship': [additive_image(ship(False), 43), additive_image(ship(True), 44)],
    }
    return {'sky': sky, 'sky_nebula': nebula, 'sky_bodies': bodies, 'sky_flyby': flyby}


def write_sheets(tiles, out_dir):
    for sheet, states in tiles.items():
        first = next(iter(states.values()))
        size = (first[0] if isinstance(first, list) else first).size
        dmi = Dmi(size[0], size[1])
        for name, image in states.items():
            state = dmi.state(name)
            if isinstance(image, list):  # an animated state: the ship's light blinks
                for frame in image:
                    state.frame(frame, delay=6)
            else:
                state.frame(image)
        dmi.to_file(os.path.join(out_dir, sheet + '.dmi'))


# ---------------------------------------------------------------- previews

def hex_rgb(text):
    text = text.lstrip('#')
    return np.array([int(text[i:i + 2], 16) for i in (0, 2, 4)], dtype=float) / 255.0


def tile_to(arr, w, h, ox=0, oy=0):
    """Tiles an image array over a w x h view, shifted by an offset."""
    n = arr.shape[0]
    ys = (np.arange(h) + oy) % n
    xs = (np.arange(w) + ox) % n
    return arr[np.ix_(ys, xs)]


def upscale2(arr):
    """Twice the size with bilinear filtering, wrapping at the edges (how the client draws a scaled tile)."""
    n = arr.shape[0]
    yy, xx = np.mgrid[0:n * 2, 0:n * 2].astype(float)
    out = np.empty((n * 2, n * 2, arr.shape[2]))
    for ch in range(arr.shape[2]):
        out[..., ch] = sample_wrap(arr[..., ch], (xx - 0.5) / 2, (yy - 0.5) / 2)
    return out


def as_float(image):
    return np.asarray(image.convert('RGB'), dtype=float) / 255.0


def compose(tiles, theme, w=608, h=480, seed=0):
    """What a client would see of a theme with nothing in the way: every layer added up over black."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w, 3))
    for state, colour, strength in theme['nebula']:
        field = upscale2(as_float(tiles['sky_nebula'][state]))
        ox, oy = rng.integers(0, field.shape[0], 2)
        out += tile_to(field, w, h, ox, oy) * hex_rgb(colour) * strength
    tint = hex_rgb(theme.get('star_tint', '#ffffff'))
    for state in ('stars_deep', 'stars_far', 'stars_mid', 'stars_near', 'twinkle1', 'twinkle2', 'twinkle3', 'dust'):
        ox, oy = rng.integers(0, TILE, 2)
        out += tile_to(as_float(tiles['sky'][state]), w, h, ox, oy) * tint
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGB')


THEME_FILE = os.path.join(ROOT, 'hippiestation', 'code', '_onclick', 'hud', 'sky_themes.dm')


def read_themes():
    """The nebula lists out of sky_themes.dm, so the previews show what the game will: {theme: {'nebula': [(state, colour, strength)]}}."""
    import re
    themes = {}
    current = None
    for line in open(THEME_FILE, encoding='utf-8'):
        head = re.match(r'/datum/sky_theme/(\w+)\s*$', line)
        if head:
            current = head.group(1)
            themes[current] = {'nebula': []}
            continue
        entry = re.search(r'list\("(\w+)",\s*"(#[0-9a-fA-F]{6})",\s*(\d+)', line)
        if entry and current:
            themes[current]['nebula'].append((entry.group(1), entry.group(2), int(entry.group(3)) / 255.0))
    return themes


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'build'
    tiles = build_tiles()
    if mode == 'build':
        write_sheets(tiles, OUT_DIR)
        for sheet in tiles:
            path = os.path.join(OUT_DIR, sheet + '.dmi')
            print('%s  %d states  %d KB' % (os.path.relpath(path, ROOT), len(tiles[sheet]), os.path.getsize(path) // 1024))
    elif mode == 'preview':
        out = os.path.join(ROOT, 'data', 'previews')
        os.makedirs(out, exist_ok=True)
        for name, theme in read_themes().items():
            compose(tiles, theme, seed=sum(map(ord, name))).save(os.path.join(out, 'sky_%s.png' % name))
            print('data/previews/sky_%s.png' % name)
    elif mode == 'check':
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            write_sheets(tiles, tmp)
            bad = [s for s in tiles if open(os.path.join(tmp, s + '.dmi'), 'rb').read() != open(os.path.join(OUT_DIR, s + '.dmi'), 'rb').read()]
        if bad:
            print('stale generated sky sheets: %s (run tools/sky_gen/sky_gen.py build)' % ', '.join(bad))
            sys.exit(1)
        print('sky sheets match the generator')
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == '__main__':
    main()
