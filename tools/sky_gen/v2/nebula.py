#!/usr/bin/env python3
"""v2 nebulae: billowing emission clouds, veils and haze for the sky themes.

    python tools/sky_gen/v2/nebula.py preview    writes data/previews/sky2_nebula_<theme>.png (608x480, the theme's nebulae over
                                                 black with the star layers of the committed sky.dmi) and
                                                 data/previews/sky2_nebula_<theme>_ab.png (old preview | new, side by side)
    python tools/sky_gen/v2/nebula.py dm         prints the DM nebula lists for sky_themes.dm

Every state is 480x480 (drawn at twice that in game) and wraps on both axes. build_images(scale=2) makes the same clouds at
960x960 with twice the detail, for the game to draw at 1x (see "scale" below; nebula2x_check.py compares the two).

Colour split: each state is an RGB picture with three greyscale fields packed into its channels, and the game tints it with a
colour matrix, so one layer carries three tones:
    R  body   the cloud's broad glow and its faint outer halo
    G  crest  the dense billow tops and the lit rims on billow and dust edges
    B  core   the hot middles, small
The matrix's rows are the three tones: color = list(body r,g,b, crest r,g,b, core r,g,b). The sky adds layers, so a pixel's
colour is body*R + crest*G + core*B, times alpha. Veils pack two strand sets (R, G) and the sheet glow (B); haze packs two
broad washes (R, G) and nothing in B.

Look rules (Last Light's advice): billows are Worley fBm (5 octaves, cell sizes 2.5x apart), cut with smoothstep(0.37, 0.64)
so their edges are crisp; a small domain warp (0.3 of the big cells) keeps them from looking like marble; rims are a narrow
band of the density just inside the edge, brighter on the side facing the light; dust is smooth noise cut into lanes and
pillars; hot cores are small.

Scale: the state functions take n (the picture's size) and scale (how many of its pixels make one pixel of the 480 tile).
Every size in pixels below is a size at scale 1 and is multiplied by scale. The random fields keep their big shapes at any
scale: noise() and spectral_aniso() give the scale-1 field's own spectrum on the finer grid (FFT zero-padding: the same
shapes, smoothly interpolated) plus a little new random detail at the frequencies the 480 tile can't hold; slopes are
measured per scale-1 pixel, so the thresholds on them hold. Nothing finer than about 2 px at scale 2 (band_limit() on each
state's channels): in game a 960 cloud pixel is ~2.85 screen pixels and the sky turns, so single-pixel detail would
shimmer. A scale-2 state averaged down by 2 looks like the scale-1 one, without the blocks. Only the theme states (billow,
veil, haze) have a scale: sky_gen.py's old states stay 480.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SKY_GEN = os.path.normpath(os.path.join(HERE, '..'))
sys.path.insert(0, SKY_GEN)
sys.path.insert(0, HERE)
import sky_gen as sg  # noqa: E402  (read-only use of its helpers)
import stars  # noqa: E402  (the v2 galaxy band: nebulae lie along it)
from sky_gen import spectral, sample_wrap, blur, shoulder, smoothstep, additive_image, streaks  # noqa: E402

ROOT = sg.ROOT
N = sg.NEBULA_SIZE  # 480, drawn at 2x
PREVIEW_DIR = os.path.join(ROOT, 'data', 'previews')


# ---------------------------------------------------------------- noise

def fine_taper(n):
    """Per frequency of an n tile: 1 for periods of 6 px and up, rolling off (raised cosine) to 0 at 3 px. Detail finer than
    about 2 px shimmers in game: a 960 cloud pixel is ~2.85 screen pixels, resampled smoothly as the sky turns."""
    f = np.fft.fftfreq(n) * n
    k = np.hypot(f[:, None], f[None, :])
    t = np.clip((k - n / 6.0) / (n / 6.0), 0, 1)
    return 0.5 * (1 + np.cos(np.pi * t))


def band_limit(rgb, scale):
    """A scale > 1 state (n, n, 3) with its detail finer than about 2 px taken out (fine_taper()), clipped to 0..1; scale 1
    is left as it is. The clouds' smoothsteps, powers, products and tone curves make edges sharper than the fields they
    cut, so this goes last, on what the .dmi holds. Wraps."""
    if scale == 1:
        return rgb
    taper = fine_taper(rgb.shape[0])
    out = [np.fft.ifft2(np.fft.fft2(rgb[..., c]) * taper).real for c in range(rgb.shape[2])]
    return np.clip(np.stack(out, axis=2), 0, 1)


def scaled_noise(n, seed, amp_of, scale=1):
    """Periodic noise, n x n, 0..1, from random phases under the amplitudes amp_of(fy, fx) (frequencies in cycles per tile).

    At scale 1 this is sky_gen.spectral's recipe. At a bigger scale the n // scale tile's spectrum (the same random phases)
    is put on its own frequencies of the n tile (FFT zero-padding: the same shapes, smoothly interpolated), moved so each
    scale-1 pixel's centre lands in the middle of its scale x scale block; the frequencies the small tile can't hold get new
    random phases under the same amplitudes, rolled off by fine_taper() (new detail, nothing finer than about 2 px). Levels
    come from the scale-1 field's percentiles, so a threshold on the field cuts it in the same places."""
    if n % scale:
        raise ValueError('scaled_noise: %d px is not a whole number of scale-%d pixels' % (n, scale))
    n1 = n // scale
    rng = np.random.default_rng(seed)
    f1 = np.fft.fftfreq(n1) * n1
    spec1 = amp_of(f1[:, None], f1[None, :]) * np.exp(1j * rng.uniform(0, 2 * np.pi, (n1, n1)))
    field = np.fft.ifft2(spec1).real
    a, b = np.percentile(field, [0.5, 99.5])
    if scale > 1:
        f = np.fft.fftfreq(n) * n
        fine = np.random.default_rng([seed, scale])  # a stream no int seed gives
        spec = amp_of(f[:, None], f[None, :]) * fine_taper(n) * np.exp(1j * fine.uniform(0, 2 * np.pi, (n, n)))
        shift = np.exp(-2j * np.pi * f1 * ((scale - 1) / 2.0) / n)
        idx = f1.astype(int) % n
        spec[np.ix_(idx, idx)] = spec1 * shift[:, None] * shift[None, :]
        field = np.fft.ifft2(spec).real * scale ** 2  # ifft2 divides by the pixel count: scale^2 more of them
    return np.clip((field - a) / (b - a), 0, 1)


def noise(n, beta, seed, lo=1.0, hi=None, scale=1):
    """sky_gen.spectral() at any scale (scaled_noise()): power falls as k^-beta, lo/hi in cycles per tile."""
    if scale == 1:
        return spectral(n, beta, seed, lo, hi)

    def amp_of(fy, fx):
        k = np.hypot(fy, fx)
        amp = np.zeros_like(k)
        keep = k >= lo
        if hi is not None:
            keep &= k <= hi
        amp[keep] = k[keep] ** (-beta / 2.0)
        return amp
    return scaled_noise(n, seed, amp_of, scale)


def spectral_aniso(n, beta, seed, lo, hi, angle, stretch, scale=1):
    """spectral() with features drawn out along `angle` (radians) by `stretch`. Periodic: shaped in frequency space."""
    def amp_of(fy, fx):
        c, s = np.cos(angle), np.sin(angle)
        along = fx * c + fy * s
        across = -fx * s + fy * c
        k = np.hypot(along * stretch, across)
        amp = np.zeros(k.shape)
        keep = (k >= lo) & (k <= hi)
        amp[keep] = k[keep] ** (-beta / 2.0)
        return amp
    return scaled_noise(n, seed, amp_of, scale)


def region_mask(n, seed, cover, scale=1):
    """sky_gen.region_mask() at any scale: very broad noise cut so about `cover` of the tile has cloud."""
    base = noise(n, 3.4, seed, 1, 4, scale)
    cut = np.quantile(base, 1 - cover)
    return smoothstep(cut - 0.14, cut + 0.30, base)


def warp_coords(n, seed, strength, hi=8, scale=1):
    """Pixel coordinates pushed about by smooth periodic noise (domain warp), `strength` pixels (of this n) at most-ish."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    u = (noise(n, 3.4, seed, 1, hi, scale) - 0.5) * 2
    v = (noise(n, 3.4, seed + 1, 1, hi, scale) - 0.5) * 2
    return xx + u * strength, yy + v * strength


def puffs(x, y, n, cells, seed):
    """One octave of billows: a jittered point per cell, each a dome of its own size and brightness; the brightest dome wins.
    Periodic because the cell count divides the tile and the neighbours wrap."""
    rng = np.random.default_rng(seed)
    px = rng.uniform(0.1, 0.9, (cells, cells))
    py = rng.uniform(0.1, 0.9, (cells, cells))
    rad = rng.uniform(0.75, 1.25, (cells, cells))
    lum = rng.uniform(0.45, 1.0, (cells, cells))
    gx = x / n * cells
    gy = y / n * cells
    cx = np.floor(gx).astype(int)
    cy = np.floor(gy).astype(int)
    fx = gx - cx
    fy = gy - cy
    # a soft maximum of the domes (sum of 4th powers): neighbouring puffs merge without the creases a hard max leaves
    acc = np.zeros(x.shape)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ix = (cx + dx) % cells
            iy = (cy + dy) % cells
            d2 = (fx - dx - px[iy, ix]) ** 2 + (fy - dy - py[iy, ix]) ** 2
            dome = np.clip(1 - d2 / rad[iy, ix] ** 2, 0, None) ** 0.75 * lum[iy, ix]
            acc += dome ** 4
    return acc ** 0.25


OCTAVES = (4, 10, 24, 60, 160)  # cells across the tile: 120, 48, 20, 8, 3 pixels a cell, about 2.5x apart


def billow_fbm(n, seed, warp=0.3, gain=0.5, scale=1):
    """Worley fBm of domes, 0..1, warped by `warp` of the biggest cell. The same octaves at any scale: the next one (400
    cells) would be 2.4 px cells at 960, finer than the 2x clouds may go."""
    # the warp is as smooth as the biggest cells, so it bends them without folding the small ones into streaks
    x, y = warp_coords(n, seed + 500, warp * n / OCTAVES[0], hi=3, scale=scale)
    if scale > 1:
        # the domes sit at fractions of the tile: pixel centres where the scale-1 tile's are
        x, y = x - (scale - 1) / 2.0, y - (scale - 1) / 2.0
    total = np.zeros((n, n))
    amp, norm = 1.0, 0.0
    for i, cells in enumerate(OCTAVES):
        total += amp * puffs(x, y, n, cells, seed + 17 * i)
        norm += amp
        amp *= gain
    total /= norm
    a, b = np.percentile(total, [0.5, 99.7])
    return np.clip((total - a) / (b - a), 0, 1)


def gradient(field, scale=1):
    """Central-difference slope, per scale-1 pixel (so thresholds on it hold at any scale)."""
    gx = (np.roll(field, -1, 1) - np.roll(field, 1, 1)) * 0.5
    gy = (np.roll(field, -1, 0) - np.roll(field, 1, 0)) * 0.5
    if scale != 1:
        gx, gy = gx * scale, gy * scale
    return gx, gy


def norm01(field, lo=0.5, hi=99.5):
    a, b = np.percentile(field, [lo, hi])
    return np.clip((field - a) / max(b - a, 1e-9), 0, 1)


# ---------------------------------------------------------------- the galaxy band

_BAND = {}


def fold_across(across, round_off=0.04):
    """band_shape's `across` made to wrap across the band. It runs straight from about -6 at the tile's top to +6 at its
    bottom, so gas spread wider than the band (haze to 3.2 half-widths) is still there at the wrap and steps across it.
    Folded the short way round the tile, with its top rounded off over the last `round_off` of a tile (smooth slope, no
    crease). Only its square is right: the sign flips where the fold is (every use here squares it)."""
    n = across.shape[0]
    width = 1.0 / (n * (across[1] - across[0]))  # band_shape's across is linear down each column: its slope gives the width
    u = across * width  # tiles from the middle line
    t = np.abs((u + 0.5) % 1.0 - 0.5)
    t = np.where(t > 0.5 - round_off, 0.5 - round_off / 2 - (0.5 - t) ** 2 / (2 * round_off), t)
    return np.sign(u) * t / width


def band_fields(n=N, scale=1):
    """The v2 galaxy band (stars.band_shape, a 960 px tile drawn 1x) at nebula scale: this n tile drawn 2x is the same 960
    game pixels, so with the same origin and turn the gas sits on the band. Returns (across, rift, bulge): across is 0 on
    the band's middle line and 1 at its half width; rift is its dark lane. n = 960 (scale 2) is the band's own pixels.
    At scale 2 across is folded (fold_across()) so the 960 tiles wrap top to bottom; the 480 ones keep the old field and
    its faint seam there."""
    if stars.BAND % n:
        raise ValueError('band_fields: the nebula tile (%d) must divide the band tile (%d)' % (n, stars.BAND))
    key = (n, scale > 1)
    if key not in _BAND:
        glow, across, bulge, rift = stars.band_shape(stars.BAND, 301)
        if scale > 1:
            across = fold_across(across)
        k = stars.BAND // n
        _BAND[key] = (across[::k, ::k].copy(), blur(rift, k * 1.6)[::k, ::k].copy(), bulge[::k, ::k].copy())
    return _BAND[key]


def band_mask(n, seed, cover, spread=2.4, scale=1):
    """Where gas can be: patches strung along the galaxy band, thinning away from its middle line. Gas spreads wider than
    the band's starlight (spread x its half width) and gathers where the band bulges."""
    across, rift, bulge = band_fields(n, scale)
    strip = np.exp(-(across / spread) ** 2) * (0.75 + 0.25 * bulge)
    return np.clip(strip * (0.12 + 1.0 * region_mask(n, seed, cover, scale)), 0, 1)


def roll_packed(rgb, knee=0.72):
    """Rolls the brightest off by the sum of the packed channels, keeping their mix. Each tone is at most 1 a channel, so
    the tinted sum never clips: the hot parts stay their colour instead of flattening to cream."""
    total = rgb.sum(axis=-1, keepdims=True)
    over = np.maximum(total - knee, 0)
    target = np.where(total > knee, knee + (1 - knee) * (1 - np.exp(-over / (1 - knee))), total)
    return rgb * np.where(total > 1e-6, target / np.maximum(total, 1e-6), 1)


def crisp(field, amount=0.6, radius=1.4):
    """Unsharp mask: the game draws the art at 2x, so small detail needs its edges pushed. radius in this field's pixels."""
    return np.clip(field + amount * (field - blur(field, radius)), 0, None)


# ---------------------------------------------------------------- dust

def dust_field(n, seed, lanes=1.0, scale=1):
    """Dark dust, 0..1: a few winding lanes of varying width (a ridge of smooth noise) and broad soft rifts."""
    lx, ly = warp_coords(n, seed, n * 0.05, hi=6, scale=scale)
    s = sample_wrap(noise(n, 3.3, seed + 2, 2, 14, scale), lx, ly)
    ridge = 1 - np.abs(2 * s - 1)
    width = noise(n, 3.0, seed + 6, 1, 8, scale)
    lane = smoothstep(0.72 + 0.18 * width, 0.99, ridge)
    # lanes come and go along their length, so there are a few, not a net; and dust is turbulent itself, so a lane frays
    lane *= smoothstep(0.62, 0.88, noise(n, 3.2, seed + 3, 1, 5, scale)) * lanes
    lane *= 0.45 + 0.55 * noise(n, 2.2, seed + 8, 6, None, scale)
    rift = smoothstep(0.60, 0.90, noise(n, 3.6, seed + 7, 1, 6, scale)) * 0.55 * lanes
    return np.clip(blur(np.maximum(lane * 0.75, rift), 1.8 * scale), 0, 1)


# ---------------------------------------------------------------- the clouds

def wrapped_offset(n, sx, sy):
    """Each pixel's offset from (sx, sy) the short way round the tile."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    return (xx - sx + n / 2) % n - n / 2, (yy - sy + n / 2) % n - n / 2


def pillar_field(n, seed, sx, sy, light, count=3, reach=110.0, scale=1):
    """Dust pillars: tapering columns standing on the side `light` points away from, their heads toward the cluster at
    (sx, sy). Each bends a little, its edges are torn at two scales, its body is lumpy, and its base melts into the cloud.
    0..1 (how much dust). (sx, sy) are this n's pixels; reach is in scale-1 pixels."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    ax, ay = warp_coords(n, seed + 1, 9.0 * scale, hi=18, scale=scale)
    bx, by = warp_coords(n, seed + 3, 3.2 * scale, hi=70, scale=scale)
    knobs = noise(n, 2.2, seed + 4, 12, 90, scale) - 0.5  # globules and bites along the edges
    jx, jy = ax - xx + bx - xx, ay - yy + by - yy
    reach = reach * scale
    out = np.zeros((n, n))
    for i in range(count):
        main = i == count // 2
        ang = light + rng.uniform(-0.3, 0.3) + (i - (count - 1) / 2) * 0.38
        head_d = reach * rng.uniform(0.50, 0.70) * (0.9 if main else 1.0)
        length = reach * rng.uniform(0.60, 0.95) * (1.3 if main else 1.0)
        width = rng.uniform(7.0, 10.0) * (1.4 if main else 1.0) * scale
        bend = rng.uniform(-0.25, 0.25) * width  # sideways drift per unit of length squared
        hx, hy = sx - np.cos(ang) * head_d, sy - np.sin(ang) * head_d
        ux, uy = np.cos(ang), np.sin(ang)  # base to head
        ox, oy = wrapped_offset(n, hx, hy)
        ox, oy = ox + jx, oy + jy
        t = np.clip(-(ox * ux + oy * uy), 0, length)  # how far back from the head
        side = (t / length) ** 2 * bend * 6
        cx, cy = ox + t * ux - side * uy, oy + t * uy + side * ux
        dcap = np.hypot(cx, cy)
        radius = width * (0.7 + 0.8 * (t / length) ** 1.3) * (1 + 0.9 * knobs)  # thicker toward the base, knobbly
        col = smoothstep(radius + 2.0 * scale, radius - 1.0 * scale, dcap) * smoothstep(length, length * 0.45, t)
        out = np.maximum(out, col)
    lumps = 0.55 + 0.45 * noise(n, 1.8, seed + 2, 8, None, scale)
    return np.clip(blur(out * lumps, 0.8 * scale), 0, 1)


def cluster_stars(n, seed, sx, sy, count=16, spread=13.0, scale=1):
    """A young cluster: a few bright stars and more faint ones, packed round (sx, sy). Wraps. spread in scale-1 pixels."""
    rng = np.random.default_rng(seed)
    canvas = np.zeros((n, n))
    reach = int(np.ceil(3 * scale))
    yy, xx = np.mgrid[-reach:reach + 1, -reach:reach + 1]
    spread, size = spread * scale, 0.55 * scale
    for i in range(count):
        r = spread * np.sqrt(-2 * np.log(rng.uniform(0.02, 1)))  # Gaussian-ish radius, a few strays
        a = rng.uniform(0, 2 * np.pi)
        x, y = sx + r * np.cos(a), sy + r * np.sin(a)
        b = 0.25 + 0.75 * rng.uniform(0, 1) ** 3 if i else 1.0
        ix, iy = int(np.floor(x)), int(np.floor(y))
        fx, fy = x - ix, y - iy
        dot = b * np.exp(-((xx - fx) ** 2 + (yy - fy) ** 2) / (2 * size ** 2))
        np.add.at(canvas, ((iy + yy) % n, (ix + xx) % n), dot)
    return canvas


def billow_state(n, seed, cover=0.5, light=0.7, dust=1.0, pillars=1.0, core=1.0, reach=110.0, hole=58.0, blister=0.0,
                 octave_gain=0.5, scale=1):
    """An emission cloud lit by a young cluster inside it. Returns an (n, n, 3) float array: R body, G crest + rims, B core.

    The cluster sits in the thickest part of the cloud and has blown a cavity round itself. Gas is brightest near it (falling
    off over `reach` pixels), the billow sides facing it are rimmed, and the gas close to it is hotter (more crest colour).
    Dust pillars stand on the side `light` points from, their heads toward the cluster. `hole` is the cavity's size;
    `blister` (0..1) draws the cavity out to one side, so it breaks out of the cloud like a blister instead of a ring.
    reach and hole are in scale-1 pixels; n is this picture's size (480 * scale for the game's tile)."""
    f = billow_fbm(n, seed, gain=octave_gain, scale=scale)
    region = band_mask(n, seed + 40, cover, scale=scale)
    dens_raw = norm01(f * (0.35 + 0.65 * region), 1, 99.8)

    # the cluster: where the cloud is thickest on a broad scale
    broad = blur(dens_raw * region, 28.0 * scale)
    if scale > 1:
        # found on the scale-1 grid (the blocks' means), so it lands where it does at scale 1, in its block's middle
        broad = broad.reshape(n // scale, scale, n // scale, scale).mean(axis=(1, 3))
    sy, sx = np.unravel_index(np.argmax(broad), broad.shape)
    if scale > 1:
        sx, sy = sx * scale + (scale - 1) / 2.0, sy * scale + (scale - 1) / 2.0
    pillar_reach = reach  # pillar_field() takes scale-1 pixels
    reach, hole = reach * scale, hole * scale
    # its light summed over the neighbouring copies of the tile, so the field (and which way is "toward it") is smooth
    # everywhere, with no seam where the short way round flips
    # (summed round the short-way offset, so copies either side of the far point pair up and the tile still wraps)
    near = np.zeros((n, n))
    wx, wy = wrapped_offset(n, sx, sy)
    dist = np.hypot(wx, wy)
    for ky in (-1, 0, 1):
        for kx in (-1, 0, 1):
            near += (1 + ((wx - kx * n) ** 2 + (wy - ky * n) ** 2) / reach ** 2) ** -1.5
    near = (near - near.min()) / (near.max() - near.min())
    ngx, ngy = gradient(near, scale)
    gm = np.hypot(ngx, ngy)
    ux, uy = ngx / (gm + 2e-4), ngy / (gm + 2e-4)  # toward the cluster, fading out where the pull of two copies cancels
    # the cavity is ragged, not a ring
    rag = 0.65 + 0.7 * noise(n, 2.6, seed + 95, 3, 30, scale)
    if blister:
        # distance to a segment running out from the cluster, across from the pillars
        bx, by = np.cos(light + np.pi * 0.8), np.sin(light + np.pi * 0.8)
        span = blister * hole * 2.2
        along = np.clip(-(wx * bx + wy * by), 0, span)  # wx, wy run from the cluster to the pixel, so minus
        cdist = np.hypot(wx + along * bx, wy + along * by)
        cdist = cdist * (1 + 0.6 * along / max(span, 1))  # widens as it opens out
    else:
        cdist = dist
    cavity = smoothstep(hole * 0.25, hole, cdist * rag)
    dens_raw = dens_raw * (0.45 + 0.55 * cavity)
    body = smoothstep(0.37, 0.64, dens_raw)
    # a faint envelope beyond the cut, textured (not a blur), so the edge isn't a sticker on black
    envelope = smoothstep(0.18, 0.42, dens_raw) * (1 - body) * 0.13 * smoothstep(0.1, 0.6, region)

    # lit sides: the density as a height field lit from the cluster. Slopes facing it light up most: a rim brightest on
    # the edge and falling off inward, not a drawn outline
    gx, gy = gradient(blur(dens_raw, 2.5 * scale), scale)
    lit = np.clip(-(gx * ux + gy * uy) / 0.03, 0, 1) ** 1.6 * smoothstep(0.33, 0.45, dens_raw)
    bgx, bgy = gradient(blur(dens_raw, 7.0 * scale), scale)
    side = np.clip(-(bgx * ux + bgy * uy) / 0.012, 0, 1) * body
    # and the bright rim itself: a thin band just inside the cut, strongest facing the cluster, broken by the fine octaves
    tgx, tgy = gradient(blur(dens_raw, 1.0 * scale), scale)
    facing = np.clip(-(tgx * ux + tgy * uy) / 0.025, 0, 1)
    edge = smoothstep(0.37, 0.47, dens_raw) * smoothstep(0.60, 0.47, dens_raw)
    edge = edge * (0.25 + 0.75 * facing) * (0.55 + 0.45 * noise(n, 2.0, seed + 91, 20, None, scale))
    rim = (lit + side * 0.25 + edge * 1.25) * (0.35 + 0.65 * near ** 0.7)

    crest = smoothstep(0.62, 0.97, dens_raw) ** 1.8 * near
    # crests carry the billows' own small octaves, so a big lit crest is cauliflower, not a flat glowing blob
    crest = crest * (0.45 + 0.55 * smoothstep(0.35, 0.85, f))

    # dust: lanes and rifts anywhere, the band's own rift where the band runs; pillars on one side of the cluster
    d = dust_field(n, seed + 70, lanes=dust, scale=scale) if dust else np.zeros((n, n))
    _, band_rift, _ = band_fields(n, scale)
    d = np.maximum(d, smoothstep(0.30, 0.80, band_rift) * 0.80 * min(dust, 1.0))
    # lanes are lit on the side facing the cluster too: a bright lip on the dark
    lgx, lgy = gradient(blur(d, 1.6 * scale), scale)
    l_edge = np.clip(-(lgx * ux + lgy * uy) / 0.05, 0, 1) ** 1.4 * (1 - d) * body * near ** 0.5
    pil = (pillar_field(n, seed + 80, sx, sy, light, reach=pillar_reach, scale=scale) * pillars if pillars
           else np.zeros((n, n)))
    # the dust's side facing the cluster glows where gas is being burnt off it (the bright edge on a pillar's head)
    dgx, dgy = gradient(blur(pil, 2.2 * scale), scale)
    d_edge = np.clip(-(dgx * ux + dgy * uy) / 0.06, 0, 1) ** 1.5 * (1 - 0.6 * pil) * body
    d_edge = d_edge * (0.5 + 0.5 * noise(n, 2.0, seed + 85, 12, None, scale))  # torn, not a clean crescent
    # pillars are seen against glowing gas behind them: a bright sheet round where they stand, lumpy like the rest
    back = blur(pil, 34.0 * scale)
    back = back / max(back.max(), 1e-6)
    back = smoothstep(0.08, 0.7, back) * smoothstep(0.25, 0.75, f)
    seen = 1 - 0.92 * d
    seen = seen * (1 - 0.80 * pil)

    # the cluster's light: a soft glow on the gas round it (the stars themselves come from the star layers)
    hot = np.exp(-(dist / (11.0 * scale)) ** 2) * 0.75 + np.exp(-dist / (32.0 * scale)) * 0.22
    hot = hot * (0.40 + 0.60 * smoothstep(0.2, 0.6, dens_raw)) * core
    # and the cluster itself: a dozen young stars packed round the middle, drawn into the core so they ride with the cloud
    hot = hot + cluster_stars(n, seed + 99, sx, sy, scale=scale) * core

    halo = blur(body * near, n / 60.0) * 0.22 + blur(body * near, n / 18.0) * 0.05
    level = 0.55 + 0.45 * near
    r = (body * (0.10 + 0.55 * smoothstep(0.37, 1.0, dens_raw) ** 1.2) * level + envelope + halo) * seen
    r = r + back * 0.42 * (1 - 0.85 * pil) + pil * 0.06  # the glow behind, and a pillar's own faint light
    g = (crest * 0.45 + rim * 1.0 + l_edge * 0.35) * seen + (d_edge * 0.55 + back * 0.10) * (1 - 0.85 * pil)
    b = hot * (1 - 0.6 * np.maximum(d, pil))
    r, g = crisp(r, 0.7, 1.4 * scale), crisp(g, 0.9, 1.0 * scale)
    out = np.stack([shoulder(r, 1.2) * 0.85, shoulder(g, 1.3) * 0.95, shoulder(b, 1.4)], axis=2)
    return roll_packed(band_limit(out, scale))  # roll_packed is smooth: it makes no fine detail of its own


def filaments(n, seed, heading, x, y, scale=1):
    """Long thin filaments running along `heading`: ridges of noise drawn out 7x along it, sampled through the warped
    coordinates x, y so they bend gently. Only some ridges are lit, and each brightens and fades along its length, so they
    read as separate threads rather than a satin sheen."""
    out = np.zeros((n, n))
    for i, (hi, stretch, sharp, amp) in enumerate(((30, 7.0, 14, 1.0), (70, 9.0, 24, 0.7))):
        f = spectral_aniso(n, 2.6, seed + i, 2, hi, heading, stretch, scale)
        ridge = (1 - np.abs(2 * f - 1)) ** sharp
        lit = smoothstep(0.58, 0.90, noise(n, 3.0, seed + 20 + i, 2, 16, scale))  # which threads glow, and where
        out += amp * sample_wrap(ridge * lit, x, y)
    return out


def fibre_veil_state(n, seed, heading, cover=0.5, scale=1):
    """Fibrous veil: two filament sets braided together (R, G) on a faint sheet glow (B). The filaments bunch where a broad
    sheet is (a shock front seen edge-on is where a veil is brightest)."""
    x, y = warp_coords(n, seed + 30, n * 0.10, hi=3, scale=scale)  # big gentle bends: shock fronts are arcs
    sheet = smoothstep(0.45, 0.90, sample_wrap(spectral_aniso(n, 3.3, seed + 50, 1, 10, heading, 2.5, scale), x, y))
    where = band_mask(n, seed + 40, cover, spread=3.0, scale=scale) * sheet
    a = filaments(n, seed, heading, x, y, scale)
    # the second set bends its own way, so the two cross and braid
    x2, y2 = warp_coords(n, seed + 33, n * 0.03, hi=6, scale=scale)
    b = filaments(n, seed + 11, heading + 0.15, x + (x2 - np.mgrid[0:n, 0:n][1]), y + (y2 - np.mgrid[0:n, 0:n][0]), scale)
    a = (blur(a, 0.8 * scale) * 1.05 + blur(a, 3.0 * scale) * 0.35) * where
    b = (blur(b, 0.8 * scale) * 1.05 + blur(b, 3.0 * scale) * 0.35) * where
    glow = blur(where, n / 60.0) * 0.18 + blur(where, n / 20.0) * 0.14
    return band_limit(np.stack([shoulder(a, 1.5) * 0.9, shoulder(b, 1.5) * 0.9, shoulder(glow, 1.4) * 0.8], axis=2), scale)


def shock_strands(n, seed, phi, gpx, fronts, count, spacing, width=0.9, scale=1):
    """Bundles of thin strands along a few level lines of the smooth field phi (shock fronts: a handful of big arcs, not a
    lattice). Each strand is the front nudged by its own fine noise, so a bundle splits, crosses and rejoins. Measured in
    pixels (the level offset over the slope), so lines keep one width wherever the field is steep or flat. Returns
    (strands, glow): glow is the soft light trailing behind each front, on one side only. gpx is the slope per scale-1
    pixel (gradient(phi, scale)), so width and the glow's lengths are scale-1 pixels at any scale."""
    strands = np.zeros((n, n))
    glow = np.zeros((n, n))
    for f, level in enumerate(fronts):
        for k in range(count):
            nudge = (noise(n, 2.4, seed + 100 * f + k, 4, 40, scale) - 0.5) * spacing * 3.0
            d = (phi - level - (k - count / 2) * spacing + nudge) / gpx  # pixels from this strand, + is behind it
            bright = smoothstep(0.42, 0.82, noise(n, 3.2, seed + 100 * f + 50, 1, 5, scale))  # the front is lit along one long stretch
            bright = bright * (0.5 + 0.5 * smoothstep(0.3, 0.8, noise(n, 2.6, seed + 100 * f + k + 60, 3, 16, scale)))
            strands += np.exp(-(d / width) ** 2) * bright * (0.6 + 0.4 * (k % 2))
            glow += np.exp(-np.abs(d) / np.where(d > 0, 14.0, 2.0)) * bright / count
    return strands, glow


def veil_state(n, seed, heading, cover=0.5, scale=1):
    """Veil: shock-front arcs drawn as bundles of fine strands (R one set, G a second set just behind it, so the fronts
    are two-toned like a supernova remnant's), and the soft light trailing behind the fronts (B). Lies along the band."""
    phi = spectral_aniso(n, 3.8, seed, 1, 5, heading, 1.8, scale)  # big gentle arcs, longer along the band
    phi = blur(phi, 2.0 * scale)
    gx, gy = gradient(phi, scale)
    gpx = np.hypot(gx, gy) + 2e-4
    where = band_mask(n, seed + 40, cover, spread=2.2, scale=scale)
    a, ga = shock_strands(n, seed, phi, gpx, (0.62,), 6, 0.014, 0.7, scale)
    b, gb = shock_strands(n, seed, phi + 0.010, gpx, (0.62,), 4, 0.018, 0.9, scale)
    flat = smoothstep(0.0006, 0.0025, gpx - 2e-4)  # where the field is flat the "front" would be a smear: drop it
    a = (a * 0.6 + blur(a, 2.5 * scale) * 0.12) * where * flat
    b = (b * 0.6 + blur(b, 2.5 * scale) * 0.12) * where * flat
    glow = (ga + gb) * 0.35 * where * flat
    return band_limit(np.stack([shoulder(a, 1.4) * 0.85, shoulder(b, 1.4) * 0.75, shoulder(glow, 1.3) * 0.9], axis=2), scale)


def haze_state(n, seed, scale=1):
    """A faint broad wash in two tones (R, G) lying along the galaxy band, with the band's rift cut out of it; B is a thin
    brighter seam on the band's middle line, broken into knots."""
    across, rift, bulge = band_fields(n, scale)
    lie = np.exp(-(across / 3.2) ** 2)
    a = smoothstep(0.15, 1.0, noise(n, 3.8, seed, 1, 5, scale)) ** 1.3 * lie
    b = smoothstep(0.20, 1.0, noise(n, 3.6, seed + 1, 1, 7, scale)) ** 1.5 * np.exp(-(across / 2.0) ** 2)
    seam = (np.exp(-(across / 0.9) ** 2) * smoothstep(0.35, 0.85, noise(n, 2.6, seed + 2, 3, 40, scale))
            * (0.5 + 0.5 * bulge))
    clear = 1 - 0.75 * smoothstep(0.2, 0.7, rift)
    # the band's rift is drawn at 960: at scale 2 its fine edges are the only sharp thing here
    return band_limit(np.stack([a * 0.60 * clear, b * 0.50 * clear, seam * 0.35 * clear], axis=2), scale)


THEME_STATES = ('billow1', 'billow2', 'billow3', 'billow4', 'billow5', 'billow6', 'veil1', 'veil2', 'haze')


def build_states(n=N, scale=1, only=None):
    """Every v2 nebula state: {state: (n * scale, n * scale, 3) float array in 0..1}. n is the scale-1 tile (480); scale 2
    is the same clouds at 960 with twice the detail, for the game to draw at 1x. `only`: a list of state names to build."""
    m = n * scale
    recipes = {
        'billow1': lambda: billow_state(m, 401, cover=0.55, light=0.6, blister=0.8, scale=scale),
        'billow2': lambda: billow_state(m, 411, cover=0.45, light=2.4, pillars=1.4, hole=50, scale=scale),
        'billow3': lambda: billow_state(m, 421, cover=0.70, light=-0.9, dust=1.5, pillars=0, core=0.3, hole=22, reach=115,
                                        scale=scale),  # a wall of gas, no blown cavity
        'billow4': lambda: billow_state(m, 461, cover=0.55, light=1.9, hole=46, blister=1.0, reach=125, scale=scale),
        'billow5': lambda: billow_state(m, 471, cover=0.50, light=-2.3, pillars=0, dust=1.2, hole=40, reach=95, scale=scale),
        'billow6': lambda: billow_state(m, 481, cover=0.60, light=-0.4, dust=1.4, pillars=1.2, hole=52, blister=0.6,
                                        scale=scale),
        'veil1': lambda: veil_state(m, 431, 0.22, 0.5, scale=scale),  # filaments run near the band's line, as shock fronts in a disc do
        'veil2': lambda: veil_state(m, 441, -0.30, 0.6, scale=scale),
        'haze': lambda: haze_state(m, 451, scale=scale),
    }
    return {name: make() for name, make in recipes.items() if only is None or name in only}


def build_images(states=None, scale=1):
    """The states as PIL images for a .dmi (opaque RGB: black adds nothing). With no states given, builds them at `scale`
    (1: 480x480, drawn at 2x in game; 2: 960x960, drawn at 1x). Each keeps its dither seed whatever else is built."""
    states = states or build_states(scale=scale)
    seeds = {name: 700 + i for i, name in enumerate(sorted(THEME_STATES))}
    return {name: additive_image(arr, seeds.get(name, 700 + i)) for i, (name, arr) in enumerate(sorted(states.items()))}


# ---------------------------------------------------------------- palettes

# Per theme, 1-3 entries: state, the three tones (body, crest, core) as hex, alpha 0-255, speed, minutes per repeat, heading.
# First entry is the theme's main cloud (the Medium parallax preference shows only it).
THEMES = {
    'ember': [
        ('billow1', ('#8a180c', '#ffa848', '#fff4dc'), 235, 0.45, 40, (1, 0)),
        ('veil1', ('#ff5a24', '#ffb45a', '#3a0c10'), 78, 0.55, 55, (1, 0)),
        ('haze', ('#2c0a34', '#3a1008', '#ff6a30'), 78, 0.35, 0, (0, 0)),
    ],
    'glacier': [
        ('billow2', ('#0d3a8c', '#5ee0ff', '#d8f8ff'), 240, 0.45, 45, (-1, 0)),
        ('veil2', ('#7fe6ff', '#6a7aff', '#0a1e40'), 110, 0.55, 60, (-1, 0)),
        ('haze', ('#0c2440', '#08304a', '#4a90c8'), 160, 0.35, 0, (0, 0)),
    ],
    'violet': [
        ('billow3', ('#4a0c90', '#ff3a9a', '#ffe8f6'), 230, 0.42, 50, (1, 0)),
        ('veil1', ('#6ab8ff', '#9a8aff', '#200a38'), 62, 0.58, 60, (-1, 0)),
        ('haze', ('#1c0838', '#300a28', '#a060ff'), 78, 0.35, 0, (0, 0)),
    ],
    'verdant': [
        ('billow4', ('#08604a', '#30f2a8', '#fff2a0'), 205, 0.45, 45, (1, 0)),
        ('veil1', ('#d8ff8a', '#ffc860', '#062a24'), 49, 0.55, 55, (1, 0)),
        ('haze', ('#062a3a', '#08301c', '#40d0a0'), 62, 0.35, 0, (0, 0)),
    ],
    'gold': [
        ('billow6', ('#7a440c', '#ffd070', '#fff6dc'), 205, 0.40, 60, (1, 0)),
        ('veil2', ('#4a8ad8', '#70c0ff', '#0a1a30'), 110, 0.48, 70, (-1, 0)),
        ('haze', ('#2a1c0c', '#0c1a2a', '#c09050'), 150, 0.35, 0, (0, 0)),
    ],
    'rose': [
        ('billow5', ('#a01c64', '#ff7ac0', '#fff0f8'), 225, 0.42, 45, (1, 0)),
        ('billow3', ('#1a3cb0', '#60b0ff', '#e8f4ff'), 165, 0.52, 36, (-1, 0)),
        ('veil2', ('#ffd0e8', '#ff8ac8', '#30102a'), 80, 0.58, 60, (1, 0)),
    ],
    'quiet': [
        ('haze', ('#101a38', '#0c1428', '#5a6a9a'), 170, 0.35, 0, (0, 0)),
        ('veil2', ('#3a4a78', '#2a3460', '#0c1020'), 95, 0.40, 0, (0, 0)),
    ],
}


def hex_rgb(text):
    return sg.hex_rgb(text)


def tone_matrix(tones):
    """The 3x3 matrix taking a state's packed (R, G, B) to a colour: rows are the body, crest and core tones."""
    return np.array([hex_rgb(t) for t in tones])


def dm_matrix(tones, alpha=255):
    """A BYOND colour matrix (9 numbers, rows = what the R, G and B channels become), with alpha folded in: on an opaque
    BLEND_ADD layer, scaling the colour does what alpha would, without depending on how alpha mixes with a matrix colour."""
    m = tone_matrix(tones) * (alpha / 255.0)
    return 'list(%s)' % ', '.join('%.3g' % v for v in m.ravel())


def dm_lists():
    """The nebula lists in sky_themes.dm syntax: a colour matrix where the colour went, alpha folded into it (so 255)."""
    out = []
    for name, entries in THEMES.items():
        # the game's clouds no longer drift (2026-11-27): THEMES' minutes and heading aren't printed any more
        lines = ['\tlist("%s", %s, 255, %.2f)' % (s, dm_matrix(t, a), sp)
                 for s, t, a, sp, mins, h in entries]
        out.append('/datum/sky_theme/%s\n\tnebula = list(\n%s)' % (name, ',\n'.join('\t' + l for l in lines)))
    return '\n\n'.join(out)


# ---------------------------------------------------------------- previews

def tint(arr, tones, alpha):
    """What the game draws for one entry: the packed channels through the colour matrix, times alpha. Not clamped (the sky adds)."""
    return np.einsum('hwc,cd->hwd', arr, tone_matrix(tones)) * (alpha / 255.0)


def star_layers():
    from dmi import Dmi
    sheet = Dmi.from_file(os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'sky.dmi'))
    names = ('stars_deep', 'stars_far', 'stars_mid', 'stars_near', 'twinkle1', 'twinkle2', 'twinkle3', 'dust')
    return {s: sg.as_float(sheet.get_state(s).frames[0]) for s in names}


def band_tint(theme):
    """The theme's band colour times its alpha, read from sky_themes.dm (`band = list("#hex", alpha)`), so the preview
    shows the band as the game tints it. White at 220 if the theme doesn't set one."""
    import re
    path = os.path.join(ROOT, 'hippiestation', 'code', '_onclick', 'hud', 'sky_themes.dm')
    text = open(path, encoding='utf-8', errors='replace').read()
    block = re.search(r'/datum/sky_theme/%s\r?\n(.*?)(?:\n/datum|\Z)' % theme, text, re.S)
    m = block and re.search(r'band = list\("(#[0-9a-fA-F]{6})", (\d+)\)', block.group(1))
    colour, alpha = (m.group(1), int(m.group(2))) if m else ('#ffffff', 220)
    return np.array(hex_rgb(colour)) * alpha / 255.0


BAND_ANGLE = {'ember': 28, 'glacier': -18, 'violet': 40, 'verdant': -32, 'gold': 12, 'rose': -45, 'quiet': 22}


def compose(states, layers, theme, w=608, h=480, angle=None, band=True):
    """One client view: the v2 band and the theme's nebulae on one 960 px repeat (same origin, so the gas sits on the band),
    turned to the theme's band angle, then the star layers; added over black and clipped per channel as the client does."""
    rng = np.random.default_rng(sum(map(ord, theme)))
    angle = BAND_ANGLE.get(theme, 0) if angle is None else angle
    rep = stars.BAND
    sky = layers['band'] * band_tint(theme) if band else np.zeros((rep, rep, 3))
    main = THEMES[theme][0][0]
    for state, tones, alpha, *_ in THEMES[theme]:
        sky += sg.upscale2(tint(states[state], tones, alpha))
    # look at the main cloud's cluster (or the band's middle): it ends up a third of the way in
    if states[main][..., 2].max() > 0.2 and main.startswith('billow'):
        cy, cx = np.unravel_index(np.argmax(states[main][..., 2]), states[main].shape[:2])
        cx, cy = cx * 2, cy * 2
    else:
        cx, cy = rep // 3, rep // 2
    sky = np.roll(sky, (rep // 2 - cy, rep // 2 - cx), axis=(0, 1))
    big = np.tile(sky, (3, 3, 1))
    chans = []  # PIL turns a float picture one channel at a time
    for c in range(3):
        im = Image.fromarray(big[..., c].astype(np.float32), 'F').rotate(angle, resample=Image.BICUBIC)
        chans.append(np.asarray(im))
    turned = np.clip(np.stack(chans, axis=2), 0, None)
    mid = turned.shape[0] // 2
    x0 = mid - w // 3
    out = turned[mid - h // 2:mid - h // 2 + h, x0:x0 + w].copy()
    for s in ('stars_deep', 'stars_far', 'stars_mid', 'stars_near'):
        ox, oy = rng.integers(0, sg.TILE, 2)
        out += sg.tile_to(layers[s], w, h, ox, oy)
    return np.clip(out, 0, 1)


def to_image(arr):
    return Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')


def seam_report(states):
    """How much bigger the step across each tile edge is than a typical step inside: about 1 means it wraps cleanly."""
    for name, arr in sorted(states.items()):
        inner = np.mean(np.abs(np.diff(arr, axis=0))) + np.mean(np.abs(np.diff(arr, axis=1)))
        edge = np.mean(np.abs(arr[0] - arr[-1])) + np.mean(np.abs(arr[:, 0] - arr[:, -1]))
        print('  %-8s edge/inside step %.2f' % (name, edge / max(inner, 1e-9)))


def preview(only=None):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    # the states go through 8-bit like the .dmi does, so the previews show the banding the game would
    states = {k: sg.as_float(v) for k, v in build_images().items()}
    seam_report(states)
    layers = stars.build_layers()  # the v2 star layers and band, as the band session made them
    for theme in THEMES:
        if only and theme not in only:
            continue
        new = to_image(compose(states, layers, theme))
        path = os.path.join(PREVIEW_DIR, 'sky2_nebula_%s.png' % theme)
        new.save(path)
        old_path = os.path.join(PREVIEW_DIR, 'sky_%s.png' % theme)
        if os.path.exists(old_path):
            old = Image.open(old_path).convert('RGB')
            strip = Image.new('RGB', (old.width + 8 + new.width, max(old.height, new.height)))
            strip.paste(old, (0, 0))
            strip.paste(new, (old.width + 8, 0))
            strip.save(os.path.join(PREVIEW_DIR, 'sky2_nebula_%s_ab.png' % theme))
        print(os.path.relpath(path, ROOT))
    # every state whole at 1x through one test palette (body red, crest teal, core white), to judge the art itself
    test = ('#c0301c', '#30d0c0', '#ffffff')
    row = np.concatenate([np.clip(tint(states[s], test, 255), 0, 1) for s in sorted(states)], axis=1)
    to_image(row).save(os.path.join(PREVIEW_DIR, 'sky2_nebula_states_rgb.png'))
    # the bare states, each through a plain white matrix per channel, for checking the fields themselves
    sheet = np.concatenate([np.concatenate([states[s][..., c] for c in range(3)], axis=1) for s in sorted(states)], axis=0)
    to_image(np.repeat(sheet[..., None], 3, axis=2)).resize((sheet.shape[1] // 2, sheet.shape[0] // 2), Image.LANCZOS).save(
        os.path.join(PREVIEW_DIR, 'sky2_nebula_states.png'))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    if mode == 'preview':
        preview(sys.argv[2:] or None)
    elif mode == 'dm':
        print(dm_lists())
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == '__main__':
    main()
