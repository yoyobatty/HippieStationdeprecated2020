#!/usr/bin/env python3
"""Art for two more of the rare big events (flyby.py builds them into the sheets):

  prism: a stream of ice crystals drifting between the station and the sun. Faceted shards of every size tumble past, their
         faces flaring as they turn, their edges split into colour; the ones that catch the sun throw a fan of spectrum, and
         the sun wears a halo while the stream is thick.
  giant: a ringed giant rising over the station, painted rather than photographed: soft banded clouds, broad rings with a
         dark gap, the planet's shadow across the rings behind it and the rings' shadow across its face, a moon crossing.

Sprites in sky_events.dmi (EV, additive, pointing east) and the giant in sky_events_big.dmi (BIG, straight alpha, drawn over
the sky rather than added to it, so its night side hides the stars).
"""
import numpy as np
from PIL import Image, ImageDraw

from flyby import EV, C, grid, col, edge, round_edge
from sky_gen import spectral, sample_wrap, smoothstep, blur, blur_plain

BIG = 512


def wavelength_rgb(nm):
    """Visible light to linear RGB (Bruton's fit), 380..700 nm."""
    nm = np.asarray(nm, dtype=float)
    r = np.select([nm < 440, nm < 490, nm < 510, nm < 580, nm < 645], [-(nm - 440) / 60, 0 * nm, 0 * nm, (nm - 510) / 70, 1 + 0 * nm], 1 + 0 * nm)
    g = np.select([nm < 440, nm < 490, nm < 510, nm < 580, nm < 645], [0 * nm, (nm - 440) / 50, 1 + 0 * nm, 1 + 0 * nm, -(nm - 645) / 65], 0 * nm)
    b = np.select([nm < 440, nm < 490, nm < 510], [1 + 0 * nm, 1 + 0 * nm, -(nm - 510) / 20], 0 * nm)
    fall = np.select([nm < 420, nm > 645], [0.3 + 0.7 * (nm - 380) / 40, 0.3 + 0.7 * (700 - nm) / 55], 1 + 0 * nm)
    return np.clip(np.stack([r, g, b], -1) * fall[..., None], 0, 1)


def soft_spectrum(t, white=0.35):
    """t 0..1 red..violet, washed toward white so no colour reads as a pure screen primary."""
    rgb = wavelength_rgb(680 - np.asarray(t) * 260)
    return rgb * (1 - white) + white


# ---------------------------------------------------------------- prism: the crystals

SHARD_FRAMES = 8
SHARDS = {  # name: (length, width, back point, seed, frame delays) - a long needle, a stubby column, a broken plate
    'prism_shard': (200.0, 40.0, 0.55, 1101, [4, 3, 3, 2, 3, 4, 4, 3]),
    'prism_shard2': (150.0, 54.0, 0.25, 1102, [3, 4, 3, 3, 2, 3, 4, 4]),
    'prism_shard3': (120.0, 70.0, 0.0, 1103, [5, 3, 2, 3, 4, 3, 3, 4]),
}


def _poly_mask(points, ss):
    im = Image.new('F', (EV * ss, EV * ss), 0.0)
    ImageDraw.Draw(im).polygon([(x * ss, y * ss) for x, y in points], fill=1.0)
    return im


def _down(im, ss):
    return np.asarray(im.resize((EV, EV), Image.BOX), dtype=float)


def _lines(segments, ss, width):
    im = Image.new('F', (EV * ss, EV * ss), 0.0)
    d = ImageDraw.Draw(im)
    for (a, b), power in segments:
        d.line([(a[0] * ss, a[1] * ss), (b[0] * ss, b[1] * ss)], fill=float(power), width=max(1, int(width * ss)))
    return im


def prism_shard(frame, length, width, back, seed):
    """An ice crystal side on, pointing east: a hexagonal column seen as three long faces with a pointed end (and a point or a
    break at the back). Glassy: faint inside, its edges lit and split into colour. As it tumbles the light moves from face to
    face, and once a turn one face flares."""
    ss = 3
    rng = np.random.default_rng(seed)
    half_l, half_w = length / 2, width / 2
    tip = half_w * 0.95
    x0, x1 = C - half_l, C + half_l
    ys = [C - half_w, C - half_w / 3, C + half_w / 3, C + half_w]  # the three faces' long edges
    jag = rng.uniform(-0.25, 0.25, 4) * half_w
    back_x = [x0 + tip * back + j for j in jag]  # the back end: pointed, or broken off unevenly
    front = (x1, C + rng.uniform(-0.1, 0.1) * half_w)
    faces = []
    for k in range(3):
        a, b = ys[k], ys[k + 1]
        faces.append([(back_x[k], a), (x1 - tip, a), (x1 - tip, b), (back_x[k + 1], b)])
    caps = [[(x1 - tip, ys[k]), front, (x1 - tip, ys[k + 1])] for k in range(3)]
    if back > 0.3:
        back_tip = (x0, C)
        caps += [[(back_x[k], ys[k]), back_tip, (back_x[k + 1], ys[k + 1])] for k in range(3)]
    turn = frame / SHARD_FRAMES * 2 * np.pi
    body = np.zeros((EV, EV))
    xx, yy = grid()
    # glass isn't flat-shaded: light pools toward one end of a face and thins at the other, with soft streaks along it
    pool = 0.55 + 0.45 * np.cos((xx - C) / length * np.pi * 1.3 + turn)
    streaks = 0.75 + 0.5 * sample_wrap(spectral(EV, 2.0, seed, 2, 24), xx * 0.25, yy * 2.5)
    for k, face in enumerate(faces + caps):
        normal = (k % 3) * 2 * np.pi / 3 + (0.5 if k >= 3 else 0.0)
        lit = 0.07 + 0.20 * max(0.0, np.cos(turn - normal)) + 0.90 * max(0.0, np.cos(turn - normal)) ** 14
        body += _down(_poly_mask(face, ss), ss) * lit
    body *= pool * streaks
    # facet edges: the outline bright, the inner ridges fainter
    outline = [((back_x[0], ys[0]), (x1 - tip, ys[0])), ((x1 - tip, ys[0]), front), (front, (x1 - tip, ys[3])),
               ((x1 - tip, ys[3]), (back_x[3], ys[3]))]
    if back > 0.3:
        outline += [((back_x[0], ys[0]), (x0, C)), ((x0, C), (back_x[3], ys[3]))]
    else:
        outline += [((back_x[k], ys[k]), (back_x[k + 1], ys[k + 1])) for k in range(3)]
    ridges = [((back_x[k], ys[k]), (x1 - tip, ys[k])) for k in (1, 2)] + [((x1 - tip, ys[0]), (x1 - tip, ys[3]))]
    # an edge is bright where it faces the light as the crystal turns, and all but gone where it doesn't
    segs = [(seg, 0.30 + 0.70 * max(0.0, np.cos(turn - i * 1.1)) ** 2) for i, seg in enumerate(outline)]
    segs += [(seg, 0.18 + 0.35 * max(0.0, np.cos(turn - 2.0 - i * 2.1)) ** 2) for i, seg in enumerate(ridges)]
    lines = _down(_lines(segs, ss, 1.0), ss)
    # light inside the glass: two faint caustic streaks across it
    caust = []
    for _ in range(2):
        cx = rng.uniform(x0 + length * 0.2, x1 - length * 0.3)
        caust.append((((cx, ys[0] + 2), (cx + rng.uniform(-0.6, 0.6) * width, ys[3] - 2)), 0.35))
    inner = _down(_lines(caust, ss, 0.8), ss) * (0.6 + 0.4 * np.cos(turn * 2))
    # colour split at the edges: red pushed one way, violet the other (a prism does this to light)
    fringe = np.zeros((EV, EV, 3))
    for t, shift in ((0.0, -1.6), (0.25, -0.8), (0.5, 0.0), (0.75, 0.8), (1.0, 1.6)):
        moved = np.roll(blur(lines, 0.9), int(round(shift)), axis=0)
        fringe += moved[..., None] * soft_spectrum(t, 0.15) * 0.30
    glass = (0.82, 0.92, 1.0)
    img = col(body * 0.80, glass) + col(lines * 0.55, (1.0, 1.0, 1.0)) + fringe + col(inner, (0.85, 0.95, 1.0))
    img += col(blur(lines + body * 0.6, 5.0) * 0.30, (0.70, 0.82, 1.0))
    return blur_plain(img, 0.35) * edge(xx, yy, 8)[..., None]


def prism_flare():
    """A shard catching the sun: a hard white star with long thin spikes, and a fan of spectrum thrown east out of it, red at
    one side, violet at the other, soft and wide rather than a rainbow sticker."""
    xx, yy = grid()
    sx, sy = 60.0, C  # the star sits west of the middle; the fan opens east from it (the game points it away from the sun)
    dx, dy = xx - sx, yy - sy
    r = np.hypot(dx, dy) + 1e-6
    core = np.exp(-(r / 2.2) ** 2) * 1.6 + np.exp(-(r / 9.0) ** 2) * 0.35
    spikes = (np.exp(-(dy / 0.9) ** 2) * np.exp(-np.abs(dx) / 55) + np.exp(-(dx / 0.9) ** 2) * np.exp(-np.abs(dy) / 30)) * 0.9
    diag = (np.exp(-((dx - dy) / 1.3) ** 2) + np.exp(-((dx + dy) / 1.3) ** 2)) * np.exp(-r / 16) * 0.35
    star = core + spikes + diag
    angle = np.arctan2(dy, dx)
    spread = 0.30  # half-width of the fan, radians
    t = np.clip((angle + spread) / (2 * spread), 0, 1)
    inside = smoothstep(spread, spread * 0.75, np.abs(angle)) * (dx > 0)
    along = smoothstep(6, 26, r) * np.exp(-r / 120) * smoothstep(EV - sx - 4, EV - sx - 40, r)
    fan = inside * along * 0.55
    img = col(np.clip(star, 0, 2), (1.0, 1.0, 1.0)) + fan[..., None] * soft_spectrum(t, 0.30)
    return img * edge(xx, yy, 6)[..., None]


def prism_halo():
    """The sun's halo while the crystals are thick: a thin ring, reddish on its inside edge and fading out through white to
    blue, with the brighter arcs where it's crossed by the tangent arcs above and below, and a soft ring further out."""
    xx, yy = grid()
    dx, dy = xx - C, yy - C
    r = np.hypot(dx, dy) / (EV / 2)
    angle = np.arctan2(dy, dx)
    rad = 0.84
    inside = r - rad
    band = np.where(inside < 0, np.exp(-(inside / 0.02) ** 2), np.exp(-(inside / 0.10) ** 2))
    t = np.clip(inside / 0.12 + 0.15, 0, 1)
    colour = soft_spectrum(t * 0.85, 0.45)
    arcs = 1 + 0.9 * np.exp(-((np.abs(np.sin(angle)) - 1) / 0.12) ** 2) * np.exp(-(inside / 0.04) ** 2)
    sundogs = np.exp(-((np.abs(np.cos(angle)) - 1) / 0.03) ** 2) * np.exp(-((r - rad - 0.02) / 0.05) ** 2) * 1.2
    wash = np.exp(-((r - 0.5) / 0.35) ** 2) * 0.05 * (r < rad)  # the sky inside the ring a little lighter than out
    img = (band * arcs * 0.30 + sundogs * 0.5)[..., None] * colour + col(wash, (0.85, 0.9, 1.0))
    return blur_plain(img, 0.6) * round_edge(xx, yy, 4)[..., None]


# ---------------------------------------------------------------- giant: a ringed planet rising, painted

GIANT_R = 112.0  # the disc's radius in its 512 sprite
RING_IN, RING_OUT = 1.32, 2.18  # the rings' inner and outer edge, in disc radii
RING_ANGLE = np.radians(32)  # the rings' long axis, from east (the sun's side when the game turns it)
RING_TIP = -1  # which way they're tipped: the sun's well up over their face toward the viewer, so it's lit
RING_OPEN = 0.32  # how open they are: minor over major axis
LIGHT = np.array([0.80, 0.18, 0.57])  # from the east, a little up and a little toward the viewer: a gibbous giant


def _unit(v):
    return v / np.linalg.norm(v)


def ring_profile(rr, seed=1201):
    """How thick the rings are at rr disc radii: a faint inner ring, a broad bright one, a dark gap, a middling outer one cut by
    a thin gap, ringlets running through all of it (smooth bands, no grain)."""
    noise = sample_wrap(spectral(BIG, 2.2, seed, 6, 120), (rr - RING_IN) / (RING_OUT - RING_IN) * BIG, 0 * rr + 7.0)
    c_ring = smoothstep(RING_IN, RING_IN + 0.06, rr) * smoothstep(1.62, 1.55, rr) * 0.28
    b_ring = smoothstep(1.55, 1.63, rr) * smoothstep(1.93, 1.90, rr) * (0.75 + 0.25 * (rr - 1.55) / 0.38)
    gap = 1 - smoothstep(1.93, 1.94, rr) * smoothstep(1.995, 1.985, rr)
    a_ring = smoothstep(1.985, 2.0, rr) * smoothstep(RING_OUT, RING_OUT - 0.03, rr) * 0.62
    thin = 1 - 0.75 * np.exp(-((rr - 2.12) / 0.006) ** 2)
    return np.clip((c_ring + b_ring + a_ring) * gap * thin * (0.72 + 0.5 * noise), 0, 1)


def giant(seed=1210):
    """{RGBA} straight-alpha picture of the ringed giant. Bands in cream, butterscotch and dusty teal, brushed along the
    latitudes with a few soft storms; limb darkening and a hazy rim on the lit side; the terminator soft; the rings lit by the
    sun with the planet's shadow across them behind and their shadow across its face."""
    n = BIG
    c = n / 2 - 0.5
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    x, y = (xx - c) / GIANT_R, -(yy - c) / GIANT_R  # disc radii, y up
    light = _unit(LIGHT)
    # the ring plane: its long axis at RING_ANGLE, tipped toward the viewer so it's RING_OPEN open
    major = np.array([np.cos(RING_ANGLE), np.sin(RING_ANGLE), 0.0])
    minor_screen = RING_TIP * np.array([-np.sin(RING_ANGLE), np.cos(RING_ANGLE), 0.0])
    tip = np.arcsin(RING_OPEN)
    normal = _unit(np.cos(tip) * minor_screen + np.sin(tip) * np.array([0, 0, 1.0]))
    if normal[2] < 0:
        normal = -normal
    # the planet
    rho2 = x * x + y * y
    on_disc = rho2 < 1
    z = np.sqrt(np.clip(1 - rho2, 0, 1))
    pts = np.stack([x, y, z], -1)
    lat = np.arcsin(np.clip(pts @ normal, -1, 1))
    east = _unit(np.cross(normal, major))
    lon = np.arctan2(pts @ east, pts @ major)
    # bands brushed along the latitudes: the latitude wobbled by long, low swirls, then a palette by latitude
    sw1 = sample_wrap(spectral(n, 3.0, seed, 1, 10), (lon / (2 * np.pi)) * n * 2, (lat / np.pi + 0.5) * n * 0.35)
    sw2 = sample_wrap(spectral(n, 2.4, seed + 1, 3, 40), (lon / (2 * np.pi)) * n * 3, (lat / np.pi + 0.5) * n * 1.3)
    wob = lat + (sw1 - 0.5) * 0.10 + (sw2 - 0.5) * 0.035
    s = np.sin(wob)
    stops = [(-1.0, (0.50, 0.62, 0.66)), (-0.78, (0.62, 0.68, 0.64)), (-0.55, (0.86, 0.76, 0.56)),
             (-0.38, (0.93, 0.85, 0.66)), (-0.22, (0.78, 0.58, 0.38)), (-0.10, (0.96, 0.90, 0.74)),
             (0.04, (0.90, 0.80, 0.60)), (0.16, (0.74, 0.52, 0.34)), (0.30, (0.95, 0.88, 0.70)),
             (0.48, (0.82, 0.70, 0.50)), (0.66, (0.70, 0.70, 0.60)), (0.82, (0.56, 0.64, 0.66)), (1.0, (0.48, 0.58, 0.64))]
    sp = np.array([p for p, _ in stops])
    cols = np.array([q for _, q in stops])
    base = np.stack([np.interp(s, sp, cols[:, k]) for k in range(3)], -1)
    streak = sample_wrap(spectral(n, 2.2, seed + 2, 8, 60), (lon / (2 * np.pi)) * n * 4, (wob / np.pi + 0.5) * n * 3)
    base *= (0.93 + 0.12 * streak)[..., None]  # brushwork along the bands
    for slat, slon, size, tone in ((-0.30, 1.1, 0.10, (0.98, 0.94, 0.86)), (0.22, -0.4, 0.06, (0.80, 0.54, 0.40)),
                                   (-0.05, 2.2, 0.045, (0.99, 0.97, 0.90))):  # a few storms
        d = np.hypot((lat - slat) / size, np.angle(np.exp(1j * (lon - slon))) * np.cos(slat) / (size * 1.8))
        spot = np.exp(-d ** 2)
        base = base * (1 - spot[..., None] * 0.8) + spot[..., None] * np.array(tone) * 0.8
    lam = np.clip(pts @ light, -1, 1)
    day = smoothstep(-0.10, 0.30, lam) * (0.35 + 0.65 * np.clip(lam, 0, 1) ** 0.8)
    limb = 0.55 + 0.45 * z ** 0.5
    # the rings' shadow on the face: from each point toward the sun, where does the ray cross the ring plane?
    t = -(pts @ normal) / (light @ normal)
    hit = pts + t[..., None] * light
    hit_r = np.linalg.norm(hit, axis=-1)
    ring_shadow = 1 - 0.75 * ring_profile(hit_r) * (t > 0)
    planet = base * (day * limb * ring_shadow)[..., None]
    night_glow = smoothstep(0.0, -0.4, lam) * 0.04  # light off the rings on the night side, barely
    planet += night_glow[..., None] * np.array([0.7, 0.66, 0.6])
    rim = np.exp(-((1 - np.sqrt(np.clip(rho2, 0, 4))) / 0.035) ** 2) * smoothstep(-0.2, 0.5, (pts @ light))
    planet += rim[..., None] * np.array([0.70, 0.80, 0.85]) * 0.35
    edge_alpha = smoothstep(1.0 + 1.2 / GIANT_R, 1.0 - 1.2 / GIANT_R, np.sqrt(rho2))
    # the rings: where the line of sight crosses the ring plane, and is that in front of the planet or behind it?
    zr = -(x * normal[0] + y * normal[1]) / normal[2]
    rpts = np.stack([x, y, zr], -1)
    rr = np.linalg.norm(rpts, axis=-1)
    dens = ring_profile(rr)
    # lit side of the rings: the sun is on the viewer's side of the plane here; the planet's shadow across them
    to_sun = rpts @ light
    perp = rpts - to_sun[..., None] * light
    shadowed = (np.linalg.norm(perp, axis=-1) < 1.0) & (to_sun < 0)
    lit_face = 0.55 + 0.45 * abs(light @ normal)
    ring_tone = np.array([0.88, 0.82, 0.70]) * (0.85 + 0.15 * sample_wrap(spectral(n, 2.0, seed + 3, 10, 100), rr * 90, 0 * rr + 3))[..., None]
    ring_rgb = ring_tone * (lit_face * np.where(shadowed, 0.08, 1.0))[..., None]
    ring_a = np.clip(dens * 1.15, 0, 0.97)
    in_front = zr > np.where(on_disc, z, -9)
    # compose: back ring, then the planet, then the front ring
    rgb = np.zeros((n, n, 3))
    a = np.zeros((n, n))
    back = ring_a * ~in_front
    rgb = ring_rgb * back[..., None]
    a = back
    rgb = rgb * (1 - edge_alpha[..., None]) + planet * edge_alpha[..., None]
    a = a * (1 - edge_alpha) + edge_alpha
    front = ring_a * in_front
    rgb = rgb * (1 - front[..., None]) + ring_rgb * front[..., None]
    a = a * (1 - front) + front
    # painted, not photographed: soften a touch, and keep a faint haze so the edge isn't a cut-out
    rgb = blur_plain(rgb, 0.6)
    a = blur(a, 0.5)
    halo = blur(edge_alpha, 6.0) * (1 - edge_alpha) * smoothstep(-0.3, 0.6, (np.stack([x, y, 0 * x], -1) @ light) / (np.sqrt(rho2) + 1e-6)) * 0.25
    rgb = rgb + halo[..., None] * np.array([0.6, 0.72, 0.8])
    a = np.clip(a + halo, 0, 1)
    straight = np.where(a[..., None] > 1e-3, rgb / np.maximum(a[..., None], 1e-3), 0)
    out = np.concatenate([np.clip(straight, 0, 1), a[..., None]], -1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def moon(seed=1250, tone=(0.80, 0.78, 0.74)):
    """A moon of the giant, small: grey, lit from the east like it, a few soft maria. Straight alpha, so it hides what's behind."""
    xx, yy = grid()
    r_px = 13.0
    x, y = (xx - C) / r_px, -(yy - C) / r_px
    rho2 = x * x + y * y
    z = np.sqrt(np.clip(1 - rho2, 0, 1))
    lam = np.clip(x * LIGHT[0] + y * LIGHT[1] + z * LIGHT[2], -1, 1) / np.linalg.norm(LIGHT)
    maria = sample_wrap(spectral(EV, 3.0, seed, 2, 12), (x / (1 + z)) * 40 + 30, (y / (1 + z)) * 40 + 30)
    surf = np.array(tone) * (0.75 + 0.35 * maria)[..., None]
    day = smoothstep(-0.05, 0.25, lam) * (0.25 + 0.75 * np.clip(lam, 0, 1))
    rgb = surf * day[..., None]
    a = smoothstep(1.0 + 1 / r_px, 1.0 - 1 / r_px, np.sqrt(rho2))
    out = np.concatenate([np.clip(rgb, 0, 1), a[..., None]], -1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def ring_shine():
    """Faint sunlight scattered off the giant's rings, a soft glow along them (additive, laid under the giant)."""
    xx, yy = grid()
    x, y = (xx - C) / (EV / 2) * 2.4, -(yy - C) / (EV / 2) * 2.4  # disc radii across the 256 sprite (drawn at 2x the giant)
    u = x * np.cos(RING_ANGLE) + y * np.sin(RING_ANGLE)
    v = -x * np.sin(RING_ANGLE) + y * np.cos(RING_ANGLE)
    rr = np.hypot(u, v / RING_OPEN)
    glow_ = np.exp(-((rr - 1.8) / 0.55) ** 2) * 0.10 + np.exp(-(np.hypot(x, y) / 1.6) ** 2) * 0.05
    return col(blur(glow_, 3.0), (0.95, 0.88, 0.74)) * round_edge(xx, yy, 20)[..., None]


def build_tiles(additive_image):
    out = {}
    for name, (length, width, back, seed, _) in SHARDS.items():
        out[name] = [additive_image(prism_shard(f, length, width, back, seed), seed + f) for f in range(SHARD_FRAMES)]
    out['prism_flare'] = additive_image(prism_flare(), 1120)
    out['prism_halo'] = additive_image(prism_halo(), 1121)
    out['moon'] = moon()
    out['ring_shine'] = additive_image(ring_shine(), 1260)
    return out


DELAYS = {name: delays for name, (_, _, _, _, delays) in SHARDS.items()}


def build_big():
    return {'giant': giant()}
