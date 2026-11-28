#!/usr/bin/env python3
"""Sky v2 star layers and the galaxy band.

Follows Last Light's night sky (native/shaders/r2/starsky.hlsli there): real magnitude counts (x2.8 per magnitude),
a compressed brightness curve that steepens past mag 5.5, blackbody colours against a 6000 K white point, faint stars
desaturated, a few bright leaders with a wider core and a small glow, open clusters, and a galaxy band with a
cream-gold bulge, blue-white arms and a long dark rift down its middle.

    python tools/sky_gen/v2/stars.py preview    writes data/previews/sky2_stars*.png

A star tile is 480 px and stands for about 60 degrees of sky (8 px a degree). The band tile is BAND px square, drawn
unscaled: the band runs along x (so it wraps) and the game turns the layer to the theme's angle.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sky_gen as sg  # noqa: E402

TILE = sg.TILE
BAND = 960
ROOT = sg.ROOT
SKY_FRACTION = 1 / 11.0
EXPOSURE = 5.0  # display gain over Last Light's flux curve: bold showpiece, faint stars still read on 8 bit  # how much of the whole sky one 480 px tile is

# (lowest mag, highest mag, stars on the whole sky) - Last Light's layers
MAG_BANDS = [(-1.4, 1.5, 20), (1.5, 2.8, 90), (2.8, 3.9, 350), (3.9, 5.0, 1200), (5.0, 6.1, 4000), (6.1, 7.2, 12000),
             (7.2, 8.4, 34000)]

# which magnitudes each parallax layer holds, near to far
LAYERS = {
    'stars_near': (-1.4, 2.8),
    'stars_mid': (2.8, 5.0),
    'stars_far': (5.0, 6.1),
    'stars_deep': (6.1, 8.4),
}

# (share, low K, high K): B A F G K M, white point 6000 K
TEMPS = [(0.16, 10000, 25000), (0.20, 7500, 10000), (0.20, 6000, 7500), (0.25, 5200, 6000), (0.17, 3900, 5200),
         (0.02, 2600, 3900)]


# ---------------------------------------------------------------- colour and brightness

def planck(lam_um, t):
    return 1.0 / (lam_um ** 5 * (np.exp(14388.0 / (lam_um * t)) - 1.0))


LAMBDAS = np.array([0.610, 0.550, 0.465])
WHITE = planck(LAMBDAS, 6000.0)


def blackbody(t):
    """RGB of a temperature (array of K), relative to a 6000 K white, brightest channel 1."""
    rgb = planck(LAMBDAS[None, :], np.asarray(t, float)[:, None]) / WHITE[None, :]
    return rgb / rgb.max(axis=1, keepdims=True)


def temperatures(rng, count, bright_share):
    """Star temperatures; bright_share 0..1 raises the share of hot B stars, as among the naked-eye bright ones."""
    shares = np.array([s for s, _, _ in TEMPS])
    shares[0] *= 1.0 + 0.6 * float(np.mean(bright_share))
    shares /= shares.sum()
    pick = rng.choice(len(TEMPS), size=count, p=shares)
    lo = np.array([TEMPS[i][1] for i in pick], float)
    hi = np.array([TEMPS[i][2] for i in pick], float)
    return np.exp(np.log(lo) + (np.log(hi) - np.log(lo)) * rng.uniform(0, 1, count))


def saturate(rgb, amount):
    grey = rgb.mean(axis=-1, keepdims=True)
    return np.clip(grey + (rgb - grey) * amount[..., None], 0, None)


def flux(m):
    """Shown brightness of a magnitude: x1.77 a magnitude, steeper past 5.5 so the faint ones fall away, not pepper."""
    f = 10 ** (-0.4 * 0.62 * (m - 1.0))
    return f * np.where(m > 5.5, 2.0 ** (-0.6 * (m - 5.5)), 1.0)


def magnitudes(rng, m0, m1, count):
    u = rng.uniform(0, 1, count)
    a, b = 10 ** (0.45 * m0), 10 ** (0.45 * m1)
    return np.log10(a + (b - a) * u) / 0.45


def count_between(m0, m1, area):
    total = 0.0
    for lo, hi, n in MAG_BANDS:
        overlap = max(0.0, min(hi, m1) - max(lo, m0))
        total += n * overlap / (hi - lo)
    return int(round(total * area))


# ---------------------------------------------------------------- drawing

def draw_star(canvas, x, y, rgb, f):
    """A star of flux f: 1 px when faint, a wider core and a small exp glow (6% of flux, ~3 px) when bright."""
    n = canvas.shape[0]
    if f < 0.9:
        canvas[int(y) % n, int(x) % n] += rgb * f
        return
    sigma = 0.45 * (1.0 + 0.5 * np.log2(f))
    reach = int(np.ceil(max(3 * sigma, 9 + 2 * np.log2(f))))
    d = np.arange(-reach, reach + 1)
    dy, dx = np.meshgrid(d, d, indexing='ij')
    r = np.hypot(dx, dy)
    core = np.exp(-r * r / (2 * sigma * sigma))
    core *= f / core.sum() * 1.6  # the core carries most of the light
    glow = np.exp(-r / 3.0)
    glow *= 0.06 * f / glow.sum() * 9.0
    patch = core + glow
    if f > 4:  # the very brightest get faint diffraction spikes, kept short
        spike = 0.025 * np.log2(f) * (np.exp(-np.abs(dx) / 5.0) * (dy == 0) + np.exp(-np.abs(dy) / 5.0) * (dx == 0))
        patch = patch + spike
    rows = (int(y) + dy) % n
    cols = (int(x) + dx) % n
    np.add.at(canvas, (rows, cols), patch[..., None] * rgb[None, None, :])


def place(rng, count, density, n):
    xs, ys = [], []
    got = 0
    while got < count:
        cx = rng.uniform(0, n, count * 3)
        cy = rng.uniform(0, n, count * 3)
        ok = rng.uniform(0, 1, count * 3) < density[cy.astype(int) % n, cx.astype(int) % n] / density.max()
        xs.append(cx[ok])
        ys.append(cy[ok])
        got += ok.sum()
    return np.concatenate(xs)[:count], np.concatenate(ys)[:count]


def roll_off(rgb, knee=0.75):
    """Rolls the brightest off by the max channel, keeping hue: no cream clipping."""
    peak = rgb.max(axis=-1, keepdims=True)
    over = np.maximum(peak - knee, 0)
    target = np.where(peak > knee, knee + (1 - knee) * (1 - np.exp(-over / (1 - knee))), peak)
    return rgb * np.where(peak > 1e-6, target / np.maximum(peak, 1e-6), 1)


def star_field(seed, m0, m1, n=TILE, density=None, gain=2.2, area=None):
    """Every star between two magnitudes on an n x n tile, following a density field (None = gentle clumps)."""
    rng = np.random.default_rng(seed)
    area = SKY_FRACTION * (n / TILE) ** 2 if area is None else area
    count = count_between(m0, m1, area)
    if density is None:
        clump = sg.spectral(n, 3.0, seed + 500, 1, 8)
        density = 0.75 + 0.25 * clump
    xs, ys = place(rng, count, density, n)
    mags = magnitudes(rng, m0, m1, count)
    f = flux(mags) * gain * EXPOSURE
    rgb = blackbody(temperatures(rng, count, np.clip((3.0 - mags) / 4, 0, 1)))
    # bright stars 1.4x saturated, fading to white for the faint ones
    sat = np.interp(mags, [1.0, 4.0, 6.5], [1.15, 0.8, 0.25])
    rgb = saturate(rgb, sat)
    canvas = np.zeros((n, n, 3))
    for x, y, c, fl in zip(xs, ys, rgb, f):
        draw_star(canvas, x, y, c, fl)
    return canvas, list(zip(xs, ys, mags))


def open_cluster(canvas, rng, cx, cy, radius, members, n):
    """A tight knot of young blue-white stars, mag 2.6..6.2 squeezed, as a Pleiades."""
    m = np.sort(magnitudes(rng, 3.4, 7.2, members))
    for mag in m:
        r = abs(rng.normal(0, radius * 0.55))
        a = rng.uniform(0, 2 * np.pi)
        t = rng.uniform(9000, 22000)
        rgb = saturate(blackbody([t]), np.array([1.2]))[0]
        draw_star(canvas, cx + r * np.cos(a), cy + r * np.sin(a), rgb, flux(mag) * EXPOSURE)
    # unresolved members as a faint haze
    yy, xx = np.mgrid[0:n, 0:n]
    dx = (xx - cx + n / 2) % n - n / 2
    dy = (yy - cy + n / 2) % n - n / 2
    canvas += np.exp(-(dx * dx + dy * dy) / (2 * (radius * 0.8) ** 2))[..., None] * np.array([0.55, 0.68, 1.0]) * 0.035


# ---------------------------------------------------------------- the galaxy band

def band_shape(n=BAND, seed=301):
    """Fields across the band tile: (glow, across, bulge, rift). The band runs along x and wraps."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    along = xx / n
    # the band's middle wanders a little, and it swells at the bulge
    wander = np.zeros(n)
    rng = np.random.default_rng(seed)
    for k, amp in ((1, 0.018), (2, 0.008), (3, 0.004), (5, 0.002)):
        wander += amp * np.sin(2 * np.pi * (k * np.arange(n) / n + rng.uniform()))
    centre = 0.5 + wander[None, :]
    bulge = np.exp(-(((along - 0.42 + 0.5) % 1.0 - 0.5) / 0.15) ** 2)  # one bulge per repeat
    width = 0.085 + 0.055 * bulge
    across = (yy / n - centre) / width  # 0 at the middle, 1 at the half-width
    # the outer halo, faded to nothing at the tile's top and bottom: the tile repeats across the band too, so no seam
    edge = np.cos(np.pi * (yy / n - 0.5)) ** 2
    glow = np.exp(-across ** 2) * (0.55 + 0.45 * bulge) + 0.22 * np.exp(-(across / 1.8) ** 2) * edge
    # star clouds: the band is lumpy, brighter knots strung along it
    lumps = 0.6 * sg.spectral(n, 2.4, seed + 1, 3, 90) + 0.4 * sg.spectral(n, 1.6, seed + 5, 30, 240)
    lumps = sg.warp(lumps, seed + 2, n * 0.012, hi=14)
    glow = glow * (0.45 + 0.85 * lumps ** 1.4)
    # the rift: a long dark lane down the middle, broken into fingers and pillars by thresholded smooth noise
    rift_centre = 0.10 * np.sin(2 * np.pi * (along + 0.3)) + 0.04 * np.sin(2 * np.pi * (along * 3 + 0.7))
    lane = np.exp(-((across - rift_centre) / (0.30 + 0.12 * bulge)) ** 2)
    ragged = 0.7 * sg.spectral(n, 3.0, seed + 3, 2, 60) + 0.3 * sg.spectral(n, 2.0, seed + 6, 40, 300)
    ragged = sg.warp(ragged, seed + 4, n * 0.010, hi=10)
    fingers = sg.smoothstep(0.38, 0.62, ragged) * np.exp(-(across / 1.3) ** 2)
    rift = np.clip(lane * sg.smoothstep(0.25, 0.55, ragged) + 0.55 * fingers * (1 - lane), 0, 1)
    rift = sg.blur(rift, 0.8)
    return glow, across, bulge, rift


def band_layer(seed=301, n=BAND, strength=1.0):
    """The galaxy band at full colour: glow, its own grain of unresolved stars, clusters, the rift."""
    glow, across, bulge, rift = band_shape(n, seed)
    cream = np.array([1.00, 0.84, 0.60])
    arms = np.array([0.72, 0.82, 1.00])
    colour = cream[None, None, :] * bulge[..., None] + arms[None, None, :] * (1 - bulge[..., None])
    # bulge creamier near the middle line only
    core = np.exp(-across ** 2 * 2)[..., None]
    colour = colour * (0.75 + 0.25 * core) + (1 - core) * 0.25 * arms
    light = sg.blur(glow, 1.0)[..., None] * colour * 1.1  # bold: the band reads through a theme's nebulae
    # grain: very faint stars, dense along the band
    density = 0.3 + 1.6 * np.clip(glow / glow.max(), 0, 1)
    grain, _ = star_field(seed + 10, 7.0, 9.2, n, density, gain=2.2, area=SKY_FRACTION * (n / TILE) ** 2 * 1.4)
    # pink HII knots strung along the arms
    rng = np.random.default_rng(seed + 20)
    for _ in range(9):
        x = rng.uniform(0, n)
        y = n * (0.5 + rng.normal(0, 0.04))
        r = rng.uniform(4, 10)
        yy, xx = np.mgrid[0:n, 0:n]
        d2 = ((xx - x + n / 2) % n - n / 2) ** 2 + ((yy - y + n / 2) % n - n / 2) ** 2
        light += np.exp(-d2 / (2 * r * r))[..., None] * np.array([1.0, 0.30, 0.45]) * rng.uniform(0.04, 0.09)
    clusters = np.zeros((n, n, 3))
    for _ in range(3):
        open_cluster(clusters, rng, rng.uniform(0, n), n * (0.5 + rng.normal(0, 0.08)), rng.uniform(10, 16),
                     int(rng.integers(14, 24)), n)
    dark = 1.0 - 0.88 * rift[..., None]
    # Unresolved stars read as soft light through the rift's dust. Clusters also dim behind it.
    grain = np.stack([sg.blur(channel, 0.6) for channel in grain.transpose(2, 0, 1)], axis=-1)
    grain *= 1 - 0.75 * rift[..., None]
    out = (light + grain) * dark * strength + clusters * (1 - 0.60 * rift[..., None])
    return roll_off(out)


# ---------------------------------------------------------------- the layers as the game will draw them

def build_layers():
    """{state: float RGB array} for the four star layers and the band."""
    out = {}
    for i, (state, (m0, m1)) in enumerate(LAYERS.items()):
        canvas, _ = star_field(401 + i, m0, m1)
        if state == 'stars_mid':  # one open cluster in a nearer layer, off the band
            rng = np.random.default_rng(77)
            open_cluster(canvas, rng, 330, 140, 14, 18, TILE)
        out[state] = roll_off(canvas)
    out['band'] = band_layer()
    return out


def as_image(rgb, seed):
    return sg.additive_image(np.clip(rgb, 0, 1), seed)


def compose(layers, w=608, h=480, angle=28.0, seed=3, extra=None):
    """Everything added over black at the theme's band angle, as one client view."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w, 3))
    band = layers['band']
    if angle:
        img = Image.fromarray((np.clip(np.tile(np.roll(band, BAND // 2, axis=0), (2, 2, 1)), 0, 1) * 255).astype(np.uint8))
        img = img.rotate(angle, resample=Image.BICUBIC)
        big = np.asarray(img, float) / 255.0
        c = big.shape[0] // 2
        out += big[c - h // 2:c - h // 2 + h, c - w // 2:c - w // 2 + w]
    else:
        out += sg.tile_to(band, w, h, 0, BAND // 2 - h // 2)
    for state in ('stars_deep', 'stars_far', 'stars_mid', 'stars_near'):
        ox, oy = rng.integers(0, TILE, 2)
        out += sg.tile_to(layers[state], w, h, ox, oy)
    if extra is not None:
        out += extra
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGB')


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    if mode != 'preview':
        print(__doc__)
        sys.exit(2)
    out = os.path.join(ROOT, 'data', 'previews')
    os.makedirs(out, exist_ok=True)
    layers = build_layers()
    compose(layers).save(os.path.join(out, 'sky2_stars.png'))
    compose(layers, angle=0, seed=9).save(os.path.join(out, 'sky2_stars_flat.png'))
    for state, rgb in layers.items():
        as_image(rgb, 1).convert('RGB').save(os.path.join(out, 'sky2_layer_%s.png' % state))
    for k, (_, (m0, m1)) in enumerate(LAYERS.items()):
        print(list(LAYERS)[k], count_between(m0, m1, SKY_FRACTION))
    print('data/previews/sky2_stars.png')


if __name__ == '__main__':
    main()
