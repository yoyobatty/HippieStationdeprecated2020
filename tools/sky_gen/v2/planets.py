"""Draws Lavaland and the six other worlds for sky_bodies.dmi: backlit planets with airglow, a rock belt and a moon. LOCAL ONLY.

Usage:
  python tools/sky_gen/v2/planets.py hippiestation/icons/effects/sky_bodies.dmi [--preview data/previews/sky_planets.png]

Written for the Paradise port of the sky (Paradise tools/perf_bench/sky_v2/gen_planets.py, 2026-11-27) and brought back here.
planet_lava: Lavaland (bodies.py's surface) with a sparse tilted belt of lumpy, pitted rocks (sun rim, planetshine) and a moon on
the belt in front of the lower right edge, subtle light-led airglow (a limb line, a soft halo, a thin band above the limb).
Baked backlit from the upper left (PLANET_BAKE_ANGLE 135, light_at(BACKLIT_Z)): the game turns it by 135 less the sun's bearing
(parallax.dm face_sun(SKY_PLANET_BAKE_ANGLE)) and turns the ion storm's aurora back by 135 (sky.dm start_aurora()).
The six worlds (WORLD_LOOKS): crisp terminators, near-zero ambient, airglow on those with air, small moons (jungle, ocean, a
lumpy one for redrock), banded rings with a gap for the gas giant. Baked lit from the east (face_sun(0)).
planet_plasma and planet_chasm are Paradise's Lavaland themes: rebuilt only in a sheet that already has them.
--preview draws the sheet's states before (as they were in the sheet) above after. Seeded: a rebuild gives the same pixels.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bodies as b  # noqa: E402  (puts tools/sky_gen, and through it tools/mapmerge2, on the path)
import sky_gen as sg  # noqa: E402
from dmi import Dmi  # noqa: E402


PLASMA_AIR = dict(b.LAVA_AIR, colour=b.lin((225, 150, 255)), twilight=b.lin((190, 80, 255)))
CHASM_AIR = dict(b.LAVA_AIR, colour=b.lin((200, 196, 192)), twilight=b.lin((150, 142, 138)), density=0.9)


# Where the light comes from in the baked planets, degrees counter-clockwise from screen east: upper left, like Paradise's
# sprites. The planet layer turns them by the sun's bearing less this.
PLANET_BAKE_ANGLE = 135
# The sun is behind the planets and a little up-left, as in Paradise's sprites: a bright rim, the face mostly in shadow
BACKLIT_Z = -0.45


def spots(p, seed, count, smallest, largest, power=2):
    """Round spots on the sphere: the strongest at each point, 0..1 (power 2 soft, 4+ flat-bottomed)."""
    rng = np.random.default_rng(seed)
    centres = rng.normal(size=(3, count))
    centres /= np.linalg.norm(centres, axis=0)
    size = rng.uniform(smallest, largest, count)[:, None]
    return np.exp(-(np.arccos(np.clip(centres.T @ p, -1, 1)) / size) ** power).max(axis=0)


def plasma_surface(p):
    """Dark violet basalt split by branching plasma veins, with glowing crystal vents and pale plasma frost."""
    s = b.Surface()
    w = b.warped(p, 111, 1.5, 0.42)
    base = b.stretch(b.fbm(w, 112, 2.2, 7, gain=0.52))
    albedo = b.mix(b.lin((34, 29, 40)), b.lin((86, 78, 94)), b.smoothstep(0.3, 0.85, base) * 0.8)
    albedo *= (1 + 0.12 * b.fbm(p, 113, 10.0, 4))[:, None]
    region = b.stretch(b.fbm(p, 115, 1.2, 3))
    # veins: the crests of ridged noise, thin and forking like frost on glass, only where the ground is active
    crest = b.stretch(b.ridged(b.warped(p, 114, 2.4, 0.22), 116, 2.6, 5))
    veins = b.smoothstep(0.86, 0.96, crest) * b.smoothstep(0.25, 0.6, region)
    vents = spots(p, 117, 240, 0.003, 0.010) * b.smoothstep(0.35, 0.7, region)
    flicker = 0.5 + 0.5 * b.stretch(b.fbm(p, 118, 6.0, 3))
    heat = np.clip(np.maximum(veins * 0.85, vents), 0, 1) * flicker
    s.emission = b.ramp(heat, [(0.0, (0, 0, 0)), (0.12, (0.04, 0.0, 0.05)), (0.35, (0.45, 0.03, 0.40)),
                               (0.6, (1.2, 0.15, 1.1)), (0.85, (2.0, 0.55, 2.2)), (1.0, (2.6, 1.3, 3.0))])
    albedo = b.mix(albedo, b.lin((22, 12, 26)), np.clip(heat * 1.4, 0, 1))
    frost = b.smoothstep(0.6, 0.9, b.stretch(b.fbm(p, 119, 5.0, 3))) * (1 - np.clip(heat * 2, 0, 1))
    s.albedo = b.mix(albedo, b.lin((168, 140, 190)), frost * 0.35)
    mountains = b.ridged(b.warped(p, 120, 1.8, 0.25), 121, 2.2, 6)
    ch, _ = b.craters(p, 122, 60, 0.02, 0.14, 0.05, fresh=0.0)
    s.height = (base - 0.5) * 0.010 + (mountains - 0.5) * 0.016 - veins * 0.004 + ch * 0.8
    return s


def chasm_surface(p):
    """Grey basalt and pale ash, torn by wide black canyons with bright rims, and pocked with deep sinkholes. No glow."""
    s = b.Surface()
    w = b.warped(p, 211, 1.2, 0.35)
    base = b.stretch(b.fbm(w, 212, 2.0, 7, gain=0.5))
    albedo = b.mix(b.lin((58, 57, 60)), b.lin((132, 128, 126)), b.smoothstep(0.25, 0.85, base) * 0.9)
    albedo *= (1 + 0.15 * b.fbm(p, 213, 10.0, 4))[:, None]
    river = 1 - np.abs(b.fbm(b.warped(p, 214, 1.0, 0.4, octaves=3), 215, 1.4, 3, gain=0.45))
    eps = 0.03 + 0.05 * b.smoothstep(0.3, 0.9, b.stretch(b.fbm(p, 216, 2.0, 2)))
    canyon = b.smoothstep(1 - eps, 1 - eps * 0.3, river)
    rim = b.smoothstep(1 - eps * 2.4, 1 - eps, river) * (1 - canyon)
    pits = spots(p, 217, 70, 0.015, 0.05, power=4)
    albedo = b.mix(albedo, b.lin((170, 166, 160)), np.clip(rim + b.smoothstep(0.2, 0.5, pits) * (1 - pits), 0, 1) * 0.45)
    s.albedo = b.mix(albedo, b.lin((4, 4, 6)), np.clip(np.maximum(canyon, b.smoothstep(0.55, 0.85, pits)), 0, 1))
    s.emission = np.zeros_like(s.albedo)
    ch, _ = b.craters(p, 218, 80, 0.015, 0.12, 0.05, fresh=0.0)
    s.height = (base - 0.5) * 0.012 - canyon * 0.02 - pits * 0.02 + ch * 0.8
    return s


def planet_lava(R=128):
    return b.render(R, b.lava_surface, ss=2, frame=b.rot(20, 160, 8), bump=1.6, atmosphere=b.LAVA_AIR, exposure=1.6,
                    light=b.light_at(BACKLIT_Z), bloom=[(1.2, 0.6), (4, 0.3), (10, 0.06)], night_glow=b.lin((255, 80, 30)) * 0.1,
                    night_emission=0.14, ambient=(0.0001, 0.0001, 0.00015), limb=0.2, terminator=(-0.01, 0.05))


def planet_plasma(R=128):
    return b.render(R, plasma_surface, ss=2, frame=b.rot(-30, 60, 12), bump=1.6, atmosphere=PLASMA_AIR, exposure=1.6,
                    light=b.light_at(BACKLIT_Z), bloom=[(1.2, 0.6), (4, 0.3), (10, 0.06)], night_glow=b.lin((230, 70, 255)) * 0.1,
                    night_emission=0.14, ambient=(0.0001, 0.0001, 0.00015), limb=0.2, terminator=(-0.01, 0.05))


def planet_chasm(R=128):
    # no glow of its own: its moon's light and the airglow show the dark face a little
    return b.render(R, chasm_surface, ss=2, frame=b.rot(15, 250, -6), bump=1.8, atmosphere=CHASM_AIR, exposure=1.5,
                    light=b.light_at(BACKLIT_Z), night_emission=0.0, ambient=(0.0012, 0.0012, 0.0015), limb=0.2, terminator=(-0.01, 0.05))


# Airglow colours per planet: list(limb line, soft halo, the thin band above the limb), 0-255
AIRGLOW = {
    'planet_lava': ((255, 136, 70), (240, 70, 24), (255, 106, 58)),
    'planet_plasma': ((255, 150, 255), (176, 56, 255), (130, 210, 255)),
    'planet_chasm': ((205, 214, 228), (110, 130, 165), (120, 235, 170)),
}
# The light planets throw on their moon's dark side (planetshine), 0-1 linear-ish
PLANETSHINE = {'planet_lava': (1.0, 0.42, 0.14), 'planet_plasma': (0.8, 0.3, 1.0), 'planet_chasm': (0.35, 0.38, 0.45)}


def airglow(n, R, colours, light_deg, scale=1.0, strength=0.55, night=0.06, band_strength=0.15):
    """Premultiplied RGB and alpha arrays (n x n) for a planet's airglow: a thin bright line at the limb, a soft halo past
    it, and a thin separate band a few pixels up, as airglow looks from orbit. Strongest on the side toward the light."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float) + 0.5
    dx, dy = xx - n / 2, n / 2 - yy
    d = np.hypot(dx, dy) - R
    ang = np.arctan2(dy, dx)
    toward = (np.cos(ang - np.radians(light_deg)) + 1) / 2
    side = (night + (1 - night) * toward ** 2.4) * strength
    shimmer = 1 + 0.12 * np.sin(7 * ang + 1.3) * np.sin(3 * ang + 0.4)
    w = max(scale, 0.45)
    limb = np.exp(-((d - 1.0 * w) / (2.8 * w)) ** 2) * 0.62 * side * shimmer
    halo = np.exp(-np.clip(d, 0, None) / (15.0 * w)) * np.clip((d + 3 * w) / (4 * w), 0, 1) * 0.42 * side
    band = np.exp(-((d - 7.5 * w) / (2.6 * w)) ** 2) * band_strength * side * shimmer
    cols = [np.array(c) / 255 for c in colours]
    rgb = limb[..., None] * cols[0] + halo[..., None] * cols[1] + band[..., None] * cols[2]
    alpha = 1 - (1 - np.clip(limb, 0, 1)) * (1 - np.clip(halo, 0, 1)) * (1 - np.clip(band, 0, 1))
    return rgb, alpha, d


def add_light(canvas, rgb, alpha, where):
    """Adds premultiplied light onto an RGBA image where `where` is true."""
    arr = np.asarray(canvas).astype(float) / 255
    a = arr[..., 3:4]
    prem = arr[..., :3] * a + rgb * where[..., None]
    a2 = np.clip(a[..., 0] + alpha * where * (1 - a[..., 0]), 0, 1)
    out = np.zeros_like(arr)
    out[..., :3] = np.clip(prem / np.maximum(a2, 1e-6)[..., None], 0, 1)
    out[..., 3] = a2
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def lit_moon(state):
    """The moon: crisp sunlight from behind and up-left, and its dark side faintly lit by the planet's own glow."""
    sun = b.render(42, b.rock_surface, frame=b.rot(25, 300, 5), atmosphere=None, exposure=1.35, light=b.light_at(BACKLIT_Z),
                   ambient=(0.0, 0.0, 0.0), terminator=(-0.005, 0.03))
    old = b.BAKE_ANGLE
    b.BAKE_ANGLE = 156 # toward the planet, seen from the moon
    try:
        fill = b.render(42, b.rock_surface, frame=b.rot(25, 300, 5), atmosphere=None, exposure=0.55, light=b.light_at(-0.3),
                        ambient=(0.0, 0.0, 0.0), terminator=(-0.05, 0.25))
    finally:
        b.BAKE_ANGLE = old
    s = np.asarray(sun).astype(float) / 255
    f = np.asarray(fill).astype(float) / 255
    out = s.copy()
    out[..., :3] = np.clip(s[..., :3] + f[..., :3] * np.array(PLANETSHINE[state]) * 0.6, 0, 1)
    out[..., 3] = np.maximum(s[..., 3], f[..., 3])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def rock_sprite(rng, r, tint, shine, toward_planet, sun=(-0.55, 0.5, -0.45)):
    """One small lumpy asteroid, r pixels across its middle: an irregular outline, pitted, lit from behind and up-left
    (a bright rim, a dark face) with the planet's glow faint on its other side. Straight-alpha RGBA."""
    size = int(np.ceil(r * 2.6)) + 3
    c = size / 2
    yy, xx = np.mgrid[0:size, 0:size].astype(float) + 0.5
    dx, dy = (xx - c), (c - yy)
    ang = np.arctan2(dy, dx)
    lump = np.ones_like(ang)
    for k in (2, 3, 5):
        lump += rng.uniform(0.06, 0.2) * np.sin(k * ang + rng.uniform(0, 2 * np.pi))
    edge = r * lump
    dist = np.hypot(dx, dy)
    cover = np.clip(edge - dist + 0.5, 0, 1)
    u = np.clip(dist / np.maximum(edge, 0.1), 0, 1)
    nx, ny = dx / np.maximum(edge, 0.1), dy / np.maximum(edge, 0.1)
    nz = np.sqrt(np.clip(1 - u * u, 0, 1))
    # pits: a few dark round dents
    pits = np.zeros_like(dist)
    for _ in range(int(2 + r)):
        px, py, pr = rng.uniform(-r * 0.6, r * 0.6), rng.uniform(-r * 0.6, r * 0.6), rng.uniform(0.6, max(0.8, r * 0.35))
        pits = np.maximum(pits, np.exp(-((dx - px) ** 2 + (dy - py) ** 2) / (pr * pr)))
    sun = np.array(sun, dtype=float)
    sun /= np.linalg.norm(sun)
    fill = np.array([toward_planet[0], toward_planet[1], 0.15])
    fill /= np.linalg.norm(fill)
    lit = np.clip(nx * sun[0] + ny * sun[1] + nz * sun[2], 0, None) * 1.7
    glow = np.clip(nx * fill[0] + ny * fill[1] + nz * fill[2], 0, None)
    albedo = rng.uniform(0.75, 1.05) * (1 - 0.45 * pits) * (0.9 + 0.2 * rng.uniform(size=dist.shape))
    base = np.array([150, 144, 138]) * np.asarray(tint) / 255
    col = base * (albedo * lit)[..., None] + np.asarray(shine) * (0.32 * albedo * glow)[..., None] + 0.02
    out = np.zeros((size, size, 4))
    out[..., :3] = np.clip(col, 0, 1)
    out[..., 3] = cover
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def ring_and_moon(planet, R, seed, tint, state):
    """The planet on a 480 px canvas with a belt of small rocks round it (the far half behind it, rocks in its shadow dimmed)
    and a cratered moon to the lower right, lit from screen east like the planet: the look of Paradise's planet sprites."""
    rng = np.random.default_rng(seed)
    n = sg.TILE
    cx = cy = n / 2
    # sloping down to the right like Paradise's belt (screen y down), sparse and scattered
    a, bb, tilt = 1.75 * R, 0.28 * R, np.radians(15)
    count = 330
    theta = rng.uniform(0, 2 * np.pi, count)
    rho = np.where(rng.uniform(size=count) < 0.6, 1 + rng.normal(0, 0.08, count), 1 + rng.normal(0, 0.22, count))
    x = rho * a * np.cos(theta)
    y = rho * bb * np.sin(theta) + rng.normal(0, 5, count)
    sx = x * np.cos(tilt) - y * np.sin(tilt)
    sy = x * np.sin(tilt) + y * np.cos(tilt)
    # toward the light (upper left on screen, y down) brighter; the far stretch right behind the planet is in its shadow
    lx, ly = -np.cos(np.radians(45)), -np.sin(np.radians(45))
    toward = (sx * lx + sy * ly) / a
    lum = 0.62 + 0.38 * np.clip((toward + 1) / 2, 0, 1)
    across = np.abs(sx * ly - sy * lx)
    lum = np.where((toward < 0) & (toward > -1.6 * R / a) & (across < R) & (np.sin(theta) < 0), lum * 0.45, lum)
    kind = rng.uniform(size=count)
    base = np.array([145, 140, 134]) * np.asarray(tint)
    back = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    front = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    from PIL import ImageDraw
    draw_back, draw_front = ImageDraw.Draw(back), ImageDraw.Draw(front)
    for i in range(count):
        draw = draw_front if np.sin(theta[i]) > 0 else draw_back
        c = tuple(int(v) for v in np.clip(base * lum[i] * rng.uniform(0.75, 1.15), 0, 255))
        px, py = cx + sx[i], cy + sy[i]
        if kind[i] < 0.45:
            draw.point((px, py), fill=c + (255,))
        elif kind[i] < 0.75:
            draw.rectangle((px, py, px + 1, py + 1), fill=c + (255,))
        else:
            r = rng.uniform(2.2, 4.0) if rng.uniform() < 0.8 else rng.uniform(4.5, 7.0)
            to_planet = np.array([cx - px, py - cy]) / max(np.hypot(cx - px, py - cy), 1)
            rock = rock_sprite(rng, r, tint, PLANETSHINE[state], to_planet)
            (front if np.sin(theta[i]) > 0 else back).alpha_composite(rock, (int(px - rock.width / 2), int(py - rock.height / 2)))
    moon = lit_moon(state)
    glow_rgb, glow_a, d = airglow(n, R, AIRGLOW[state], PLANET_BAKE_ANGLE)
    canvas = add_light(back, glow_rgb, glow_a, d > 0.8)
    canvas.alpha_composite(planet, (int((n - planet.width) // 2), int((n - planet.height) // 2)))
    canvas = add_light(canvas, glow_rgb, glow_a, d <= 0.8)
    canvas.alpha_composite(front)
    # the moon rides the belt's near side, just in front of the planet's lower right edge
    mt = np.radians(45)
    mx, my = a * np.cos(mt), bb * np.sin(mt)
    moon_x = cx + mx * np.cos(tilt) - my * np.sin(tilt)
    moon_y = cy + mx * np.sin(tilt) + my * np.cos(tilt)
    canvas.alpha_composite(moon, (int(moon_x - moon.width / 2), int(moon_y - moon.height / 2)))
    return canvas


# The other worlds of a system: lit from screen east (the game turns them to the sun), crisp day/night edges, airglow for
# those with air, a moon for some, rings for the gas giant. (make, radius, airglow colours or None, moon, rings)
CRISP = (-0.01, 0.05)
DARK = (0.0001, 0.0001, 0.00015)
WORLD_R = b.WORLD_R
WORLD_LOOKS = {
    'world_ice': (lambda R: b.render(R, b.ice_surface, frame=b.rot(30, 40, 10), bump=1.0, atmosphere=b.ICE_AIR, exposure=1.1,
                                     ambient=DARK, terminator=CRISP), WORLD_R, ((190, 225, 255), (90, 150, 255), (150, 255, 210)), None, False),
    'world_jungle': (lambda R: b.render(R, b.jungle_surface, frame=b.rot(18, 200, -12), bump=1.0, atmosphere=b.EARTH_AIR,
                                        exposure=1.3, ambient=DARK, terminator=CRISP), WORLD_R, ((170, 215, 255), (70, 130, 255), (120, 255, 160)), 'moon', False),
    'world_rock': (lambda R: b.render(R, b.rock_surface, frame=b.rot(10, 70, 0), bump=2.0, atmosphere=None, exposure=1.4,
                                      light=b.light_at(0.22), ambient=DARK, terminator=(-0.005, 0.03)), WORLD_R, None, None, False),
    'world_redrock': (lambda R: b.render(R, b.redrock_surface, frame=b.rot(-25, 120, 6), bump=1.1, atmosphere=b.MARS_AIR,
                                         exposure=1.25, ambient=DARK, terminator=CRISP), WORLD_R, ((255, 190, 150), (220, 110, 70), (255, 160, 120)), 'rock', False),
    'world_ocean': (lambda R: b.render(R, b.ocean_surface, frame=b.rot(-15, 30, 14), bump=1.0, atmosphere=b.EARTH_AIR,
                                       exposure=1.3, ambient=DARK, terminator=CRISP), WORLD_R, ((170, 215, 255), (70, 130, 255), (120, 255, 160)), 'moon', False),
    'world_gas': (lambda R: b.render(R, b.gas_surface, frame=gas_frame(), bump=0, atmosphere=b.GAS_AIR, exposure=1.25,
                                     limb=0.35, ambient=DARK, terminator=(-0.06, 0.2)), int(WORLD_R * 1.35), ((255, 228, 190), (230, 160, 100), (255, 196, 140)), None, True),
}


# The gas giant's rings on screen: the slope of their long axis (degrees counter-clockwise from east, so -18 runs down to the
# right) and how open they are (minor over major axis). The near half is below the planet, so the north pole leans toward us.
GAS_RING_TILT = -18
GAS_RING_FLAT = 0.24


def gas_frame():
    """The gas giant's frame for b.render(): its equator in the rings' plane, so the bands run along the rings (user,
    2026-11-27: the rings were tilted against its axis). The rings are a circle seen from asin(GAS_RING_FLAT) above their
    plane; the pole is square to their long axis on screen and leans toward the viewer by that much."""
    t = np.radians(GAS_RING_TILT)
    lean = np.arcsin(GAS_RING_FLAT)
    east = np.array([np.cos(t), np.sin(t), 0.0])  # the rings' long axis: in the equator plane, across the view
    pole = np.array([-np.sin(t) * np.cos(lean), np.cos(t) * np.cos(lean), np.sin(lean)])
    body = np.stack([east, pole, np.cross(east, pole)])  # rows: the body's x (on the equator), y (the pole), z, on screen
    # render() turns its frame by the authored light's angle less BAKE_ANGLE (0 for the worlds): undo that here
    turn = np.radians(b.AUTHOR_ANGLE - b.BAKE_ANGLE)
    rz = np.array([[np.cos(turn), -np.sin(turn), 0], [np.sin(turn), np.cos(turn), 0], [0, 0, 1]])
    return body @ rz.T


def gas_rings(n, R, rng):
    """A gas giant's rings as (back, front) RGBA layers: banded, with a dark gap, fine ringlets, tilted, lit from the east, the
    planet's shadow across the far side."""
    yy, xx = np.mgrid[0:n, 0:n].astype(float) + 0.5
    x, y = xx - n / 2, n / 2 - yy
    tilt = np.radians(GAS_RING_TILT)
    u = x * np.cos(tilt) + y * np.sin(tilt)
    v = -x * np.sin(tilt) + y * np.cos(tilt)
    flat = GAS_RING_FLAT
    rho = np.hypot(u, v / flat) / R
    dens = (b.smoothstep(1.3, 1.36, rho) * (1 - b.smoothstep(2.05, 2.15, rho)))
    dens *= 0.55 + 0.45 * np.sin(rho * 41 + 0.7) ** 2 * (0.6 + 0.4 * np.sin(rho * 13))
    dens *= 1 - 0.9 * np.exp(-((rho - 1.74) / 0.035) ** 2)  # the dark gap
    dens *= np.where(rho < 1.55, 0.55, 1.0)  # the faint inner ring
    shadow = (u < 0) & (np.abs(v) < R) & (v > 0)  # far side, west of the planet: in its shadow
    lit = np.where(shadow, 0.18, 0.85 + 0.15 * np.clip(u / (2.1 * R), -1, 1))
    col = np.array([0.86, 0.78, 0.66])
    a = np.clip(dens * 0.8, 0, 1)
    img = np.zeros((n, n, 4))
    img[..., :3] = np.clip(col * lit[..., None], 0, 1)
    img[..., 3] = a
    front = img.copy()
    back = img.copy()
    front[..., 3] = np.where(v < 0, a, 0)  # the near half is below the middle on screen
    back[..., 3] = np.where(v >= 0, a, 0)
    to = lambda arr: Image.fromarray((arr * 255 + 0.5).astype(np.uint8), 'RGBA')
    return to(back), to(front)


def build_world(state, seed):
    make, R, glow, moon_kind, rings = WORLD_LOOKS[state]
    rng = np.random.default_rng(seed)
    n = sg.TILE
    old = b.BAKE_ANGLE
    b.BAKE_ANGLE = 0.0
    try:
        planet = make(R)
        moon = None
        if moon_kind == 'moon':
            moon = b.render(max(12, int(R * 0.27)), b.rock_surface, frame=b.rot(40, 120, 5), atmosphere=None, exposure=1.35,
                            light=b.light_at(0.3), ambient=DARK, terminator=(-0.005, 0.03))
    finally:
        b.BAKE_ANGLE = old
    if moon_kind == 'rock':  # a small lumpy moon, like Phobos
        moon = rock_sprite(rng, R * 0.17, (1.05, 0.95, 0.88), (0.6, 0.35, 0.25), (-1, 0), sun=(0.8, 0.15, 0.55))
    canvas = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    front_rings = None
    if rings:
        back_rings, front_rings = gas_rings(n, R, rng)
        canvas.alpha_composite(back_rings)
    if glow:
        glow_rgb, glow_a, d = airglow(n, R, glow, 0, R / 128, strength=0.5, night=0.05, band_strength=0)
        canvas = add_light(canvas, glow_rgb, glow_a, d > 0.8 * max(R / 128, 0.45))
    canvas.alpha_composite(planet, (int((n - planet.width) // 2), int((n - planet.height) // 2)))
    if glow:
        canvas = add_light(canvas, glow_rgb, glow_a, d <= 0.8 * max(R / 128, 0.45))
    if front_rings:
        canvas.alpha_composite(front_rings)
    if moon:
        canvas.alpha_composite(moon, (int(n / 2 + R * 1.55 - moon.width / 2), int(n / 2 + R * 0.55 - moon.height / 2)))
    return canvas


def load_states(path):
    d = Dmi.from_file(path)
    return d, {s.name: s for s in d.states}


def preview(before, after, out):
    """The sheet's planets and worlds as they were (top row) and as built (bottom row), on a dark sky."""
    names = [name for name in after if name in before] or list(after)
    pic = Image.new('RGBA', (480 * len(names), 960), (4, 5, 10, 255))
    for i, name in enumerate(names):
        for row, states in enumerate((before, after)):
            if name in states:
                pic.alpha_composite(states[name], (i * 480, row * 480))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    pic.resize((240 * len(names), 480), Image.LANCZOS).save(out)
    print('preview:', out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sheet')
    ap.add_argument('--preview')
    args = ap.parse_args()
    d, states = load_states(args.sheet)
    before = {name: state.get_frame().convert('RGBA') for name, state in states.items()}
    made = {state: build_world(state, 400 + i) for i, state in enumerate(WORLD_LOOKS)}
    b.BAKE_ANGLE = PLANET_BAKE_ANGLE
    made['planet_lava'] = ring_and_moon(planet_lava(), 128, 301, (1.05, 0.95, 0.88), 'planet_lava')
    if 'planet_plasma' in states:  # Paradise's Lavaland themes
        made['planet_plasma'] = ring_and_moon(planet_plasma(), 128, 302, (0.95, 0.9, 1.08), 'planet_plasma')
    if 'planet_chasm' in states:
        made['planet_chasm'] = ring_and_moon(planet_chasm(), 128, 303, (1.0, 1.0, 1.0), 'planet_chasm')
    order = [state.name for state in d.states]
    d.states = [state for state in d.states if state.name not in made]
    for name in [name for name in order if name in made] + [name for name in made if name not in order]:
        d.state(name).frame(made[name])
    d.to_file(args.sheet)
    print(args.sheet, [state.name for state in d.states])
    if args.preview:
        preview(before, made, args.preview)


if __name__ == '__main__':
    sys.exit(main())
