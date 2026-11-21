#!/usr/bin/env python3
"""The sky's moving things, second pass: shooting stars, comets, ships, and the art of the rare big events.

    python tools/sky_gen/v2/flyby.py build      writes hippiestation/icons/effects/sky_events.dmi (+ _dust.dmi, _big.dmi)
    python tools/sky_gen/v2/flyby.py preview    writes data/previews/sky2_flyby_*.png and sky2_event_*.png, and sky2_dust.png

build_tiles() returns {state: PIL RGBA or [frames]} like sky_gen.build_tiles()['sky_flyby']. Every sprite is additive (black
adds nothing) and points east: the game turns it to its heading (hippiestation/code/_onclick/hud/sky.dm). Sheet size EV.

The previews run the same timelines the game does (sky.dm) and draw key frames side by side over a theme's sky from sky_gen.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sky_gen as sg  # noqa: E402  (read only: helpers and the current sky for previews)
from sky_gen import spectral, sample_wrap, smoothstep, shoulder, blur, blur_plain, splat, additive_image  # noqa: E402

EV = 256  # the event sheet's sprites
C = EV / 2 - 0.5
OUT_DIR = sg.OUT_DIR
ROOT = sg.ROOT

# The aurora is drawn round a disc this big in the middle of its sprite; the game sizes it to Lavaland's disc and moves it to
# the disc's middle (SKY_LAVALAND_RADIUS and _SHIFT in sky.dm: in sky_bodies.dmi's planet_lava now, r 52 at 241.5, 238.5)
AURORA_R = 64.0
PLANET_X, PLANET_Y, PLANET_R = 241.5, 238.5, 52.0  # for the previews


def grid(n=EV):
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    return xx, yy


def col(field, rgb):
    return field[..., None] * np.asarray(rgb, dtype=float)


def edge(xx, yy, margin=14, n=EV):
    """Nothing by the sheet's edge, so a turned sprite shows no box."""
    d = np.minimum(np.minimum(xx, n - 1 - xx), np.minimum(yy, n - 1 - yy))
    return smoothstep(0, margin, d)


def round_edge(xx, yy, margin=24, n=EV):
    r = np.hypot(xx - (n / 2 - 0.5), yy - (n / 2 - 0.5))
    return smoothstep(n / 2.0, n / 2.0 - margin, r)


# ---------------------------------------------------------------- shooting stars

HEAD_X = EV - 44  # where a streak's head sits: ahead of the middle, so the turn swings the train round behind it


def meteor(seed, head_rgb, train_rgb, length=46.0, width=0.55, glow=0.16, sparks=14, fragments=0):
    """A shooting star: a hot head (green-white, oxygen and magnesium) and a train that cools to orange as it fades,
    a few sparks shed along it. fragments: pieces breaking off the side with short trains of their own (a fireball)."""
    rng = np.random.default_rng(seed)
    xx, yy = grid()
    hx, cy = HEAD_X, C
    b = hx - xx
    bb = np.clip(b, 0, None)
    ahead = b < 0
    along = np.where(ahead, np.exp(-(b / 1.1) ** 2), np.exp(-bb / length) * smoothstep(-1, 3, bb + 1))
    w = width + 0.006 * bb
    core = along * np.exp(-((yy - cy) / w) ** 2)
    halo = np.where(ahead, np.exp(-(b / 2.5) ** 2), np.exp(-bb / (length * 0.55))) * np.exp(-((yy - cy) / (2.0 + 0.02 * bb)) ** 2)
    t = smoothstep(0, length * 1.4, bb)[..., None]
    train = np.asarray(head_rgb) * (1 - t) + np.asarray(train_rgb) * t
    r = np.hypot(xx - hx, yy - cy)
    head = 1.3 * np.exp(-r ** 2 / 1.6) + 0.30 * np.exp(-r / 3.2)
    img = core[..., None] * train + col(halo, train_rgb) * glow + col(head, head_rgb)
    canvas = np.zeros((EV, EV, 3))
    for _ in range(sparks):
        back = rng.exponential(length * 0.9)
        if back > hx - 8:
            continue
        splat(canvas, int(hx - back), int(round(cy + rng.normal(0, 0.7))), np.asarray(train_rgb), 0.55 * np.exp(-back / (length * 1.6)) * rng.uniform(0.4, 1))
    for k in range(fragments):
        off = rng.uniform(1.8, 4.0) * (1 if k % 2 else -1)
        start = rng.uniform(6, 22)
        fx = hx - start
        fb = np.clip(fx - xx, 0, None)
        fa = np.where(xx > fx, np.exp(-((xx - fx) / 1.0) ** 2), np.exp(-fb / (length * 0.35)))
        fy = cy + off * (1 + fb * 0.02)
        img += col(fa * np.exp(-((yy - fy) / 0.6) ** 2), train_rgb) * 0.55
        img += col(np.exp(-((xx - fx) ** 2 + (yy - cy - off) ** 2) / 1.2), head_rgb) * 0.7
    return (img + canvas) * edge(xx, yy)[..., None]


METEORS = {
    #           head (hot)           train (cooling)      length width glow sparks fragments
    'meteor':   ((0.86, 1.00, 0.88), (1.00, 0.62, 0.30), 44.0, 0.55, 0.16, 12, 0),
    'meteor_o': ((1.00, 0.92, 0.72), (1.00, 0.42, 0.16), 38.0, 0.55, 0.18, 10, 0),
    'meteor_b': ((0.86, 0.92, 1.00), (0.55, 0.62, 1.00), 52.0, 0.50, 0.14, 8, 0),
    'bolide':   ((1.00, 1.00, 0.90), (1.00, 0.55, 0.22), 92.0, 0.95, 0.28, 34, 3),
}


# ---------------------------------------------------------------- comets

COMET_FRAMES = 8
COMET_DELAY = 3


def comet(phase, seed=71, scale=1.0, ion_power=1.0):
    """A comet as a telescope would show it, its tails pointing away from the sun (the game turns it so): a green coma round a
    white point, a straight blue ion tail combed into streamers with knots running out along them (phase 0..1 of one knot
    spacing), and a broad curved dust tail, cream, swept back toward where the comet has been (+y here: the game flips it)."""
    xx, yy = grid()
    hx, cy = EV - 34 - (1 - scale) * 70, C
    b = hx - xx
    bb = np.clip(b, 0, None)
    r = np.hypot(xx - hx, yy - cy)
    s = scale
    coma = 1.25 * np.exp(-(r / (1.0 * s)) ** 2) + 0.55 * np.exp(-r / (3.0 * s)) + 0.20 * np.exp(-r / (9.0 * s)) + 0.06 * np.exp(-r / (26.0 * s))
    # the ion tail: straight back, streamers fanned a couple of degrees, knots running outward
    rng = np.random.default_rng(seed)
    uneven = spectral(EV, 2.0, seed, 3, 40)
    ion = np.zeros_like(xx)
    start = smoothstep(2, 10 * s, bb)
    for angle, power in ((-2.3, 0.35), (-1.1, 0.7), (0.0, 1.0), (0.9, 0.6), (2.0, 0.4), (3.1, 0.22)):
        ys = cy + np.tan(np.radians(angle)) * bb
        width = 0.55 + 0.010 * bb
        spacing = rng.uniform(26, 38) * s
        knots = 0.55 + 0.45 * (0.5 + 0.5 * np.cos(2 * np.pi * (bb / spacing - phase - rng.uniform(0, 1)))) ** 2
        steady = 0.5 + 0.8 * sample_wrap(uneven, np.full(xx.shape, angle * 31.0 + 50), bb * 1.3)
        ion += power * np.exp(-((yy - ys) / width) ** 2) * knots * steady
    ion *= np.exp(-bb / (150.0 * s)) * start * (b > 0) * 0.42 * ion_power
    ion += np.exp(-((yy - cy) / (1.6 + 0.07 * bb)) ** 2) * np.exp(-bb / (110.0 * s)) * start * (b > 0) * 0.10 * ion_power
    # the dust tail: curved, wide, its outer (leading) edge sharper than the inner
    yc = cy + 0.0030 / s * bb ** 2
    width = 1.6 * s + 0.21 * bb
    d = (yy - yc) / width
    profile = np.where(d > 0, np.exp(-d ** 2 * 1.8), np.exp(-(d / 1.5) ** 2))
    fan = np.arctan2(yy - cy, bb + 1)
    bands = 0.78 + 0.22 * np.cos(fan * 46 + 0.5) * smoothstep(20, 70, bb)
    dust = profile * np.exp(-bb / (78.0 * s)) * (b > 0) * smoothstep(0, 6 * s, bb) * bands * (1.6 / (1 + 0.06 * bb / s))
    img = (col(coma, (0.62, 1.00, 0.80)) + col(np.exp(-(r / (0.9 * s)) ** 2) * 0.9, (1, 1, 1)) + col(ion, (0.36, 0.62, 1.00))
           + col(dust, (1.00, 0.90, 0.72)) * 1.35)
    return shoulder(blur_plain(img, 0.45), 1.25) * edge(xx, yy, 24)[..., None]


# ---------------------------------------------------------------- ships

SHIP_FRAMES = 8
SHIP_DELAYS = [2, 1, 2, 2, 3, 2, 2, 2]  # 16 ticks a loop; the strobe flashes on 0 and 2


def ship_into(canvas, x, y, frame, seed, strobe_at=(0, 2), size=1.0):
    """One ship far off: a sliver of hull lit on its sun side, red and green running lights, a white strobe, and a blue-white
    drive flame that wavers, with a faint wake behind. x, y is the hull's middle (it points east)."""
    rng = np.random.default_rng(seed * 100 + frame)
    xx, yy = grid()
    hull = np.exp(-(((xx - x) / (3.2 * size)) ** 2 + ((yy - y) / (0.9 * size)) ** 2) * 1.0)
    lit = hull * (0.55 + 0.45 * np.clip((y - yy) / 1.2, -1, 1))
    canvas += col(lit, (0.62, 0.64, 0.70)) * 0.55
    splat(canvas, int(x + 3 * size), int(y), np.array([1.0, 0.98, 0.92]), 0.55)  # the bridge's windows
    splat(canvas, int(x - 1), int(y - 2 * size), np.array([1.0, 0.18, 0.12]), 0.85, 0.12, 1.0)  # port, red
    splat(canvas, int(x - 1), int(y + 2 * size), np.array([0.15, 1.0, 0.35]), 0.80, 0.10, 1.0)  # starboard, green
    if frame in strobe_at:
        splat(canvas, int(x + 1), int(y), np.array([1.0, 1.0, 1.0]), 1.2, 0.55, 2.2, 0.35, 6)
    flame = rng.uniform(7, 13) * size
    tail = x - 4 * size
    bb = np.clip(tail - xx, 0, None)
    plume = np.exp(-bb / flame) * np.exp(-((yy - y) / (0.6 + 0.05 * bb)) ** 2) * (xx <= tail + 0.5)
    canvas += col(plume, (0.50, 0.75, 1.00)) * rng.uniform(0.8, 1.0)
    canvas += col(np.exp(-((xx - tail) ** 2 + (yy - y) ** 2) / 1.5), (0.85, 0.93, 1.0)) * 0.9
    wake = np.exp(-bb / 70.0) * np.exp(-((yy - y) / (0.8 + 0.03 * bb)) ** 2) * (xx <= tail)
    canvas += col(wake, (0.40, 0.55, 1.00)) * 0.10
    return canvas


def ship(frame):
    xx, yy = grid()
    return ship_into(np.zeros((EV, EV, 3)), C + 6, C, frame, 81) * edge(xx, yy)[..., None]


def convoy(frame):
    """Three in an echelon: a freighter leading, two escorts, each strobe on its own beat."""
    xx, yy = grid()
    canvas = np.zeros((EV, EV, 3))
    ship_into(canvas, C + 22, C, frame, 91, (0, 2), 1.3)
    ship_into(canvas, C + 4, C - 9, frame, 92, (4, 6), 0.9)
    ship_into(canvas, C - 12, C + 8, frame, 93, (3,), 0.9)
    return canvas * edge(xx, yy)[..., None]


# ---------------------------------------------------------------- light: flashes, glows, rings

def flash(spike_len=120.0, tint=(0.92, 0.96, 1.0)):
    """A blinding point: a core, two halos and long spikes, square on like the sun's, with faint ones on the diagonals."""
    xx, yy = grid()
    dx, dy = xx - C, yy - C
    r = np.hypot(dx, dy)
    glow = 2.2 * np.exp(-(r / 2.6) ** 2) + 0.75 * np.exp(-r / 7.0) + 0.22 * np.exp(-r / 30.0)
    rays = (np.exp(-np.abs(dy) / 0.9) * np.exp(-np.abs(dx) / (spike_len * 0.33)) + np.exp(-np.abs(dx) / 0.9) * np.exp(-np.abs(dy) / (spike_len * 0.33))) * 0.65
    diag = (np.exp(-np.abs(dx - dy) / 1.0) + np.exp(-np.abs(dx + dy) / 1.0)) * np.exp(-r / (spike_len * 0.16)) * 0.22
    return col(glow + rays + diag, tint) * round_edge(xx, yy, 30)[..., None]


def glow():
    """A wide soft glow, drawn big and faint: the whole sky lit by something brilliant."""
    xx, yy = grid()
    r = np.hypot(xx - C, yy - C)
    return col(0.85 * np.exp(-(r / 52.0) ** 2) + 0.30 * np.exp(-r / 36.0), (1, 1, 1)) * round_edge(xx, yy, 40)[..., None]


def star_point():
    """A star picked out a little: what the supernova is before it goes, and what's left of it after."""
    xx, yy = grid()
    dx, dy = xx - C, yy - C
    r = np.hypot(dx, dy)
    g = 1.2 * np.exp(-(r / 0.75) ** 2) + 0.30 * np.exp(-r / 2.4) + 0.05 * np.exp(-r / 9)
    g += (np.exp(-np.abs(dy) / 0.6) * np.exp(-np.abs(dx) / 4.0) + np.exp(-np.abs(dx) / 0.6) * np.exp(-np.abs(dy) / 4.0)) * 0.25
    return col(g, (1, 1, 1)) * round_edge(xx, yy)[..., None]


def ring(radius=118.0, width=1.4, seed=5, broken=0.35):
    """A thin ring of light, uneven and broken here and there: a shock front. The game grows it from nothing."""
    xx, yy = grid()
    dx, dy = xx - C, yy - C
    r = np.hypot(dx, dy)
    theta = np.arctan2(dy, dx)
    knots = sg.polar_noise(spectral(EV, 2.4, seed, 2, 30), theta, r, 1, 0.05)
    lit = np.exp(-((r - radius) / width) ** 2) + 0.35 * np.exp(-((r - radius + 3) / (width * 3)) ** 2)
    lit *= (1 - broken) + broken * 2 * knots
    return col(lit, (1, 1, 1)) * 0.9


def remnant(seed=401):
    """What a supernova leaves at first, seen months on in a minute: a young bubble of ejecta, lumpy and torn, not a ring.
    Clumps and a web of filaments crowd its rim, coloured by what they're made of (sulphur red, oxygen green-blue, iron
    gold) in patches, not stripes; a thin broken blue-white shock runs outside it; the inside holds a faint glow and the
    dim spark of what's left."""
    xx, yy = grid()
    dx, dy = xx - C, yy - C
    r = np.hypot(dx, dy)
    theta = np.arctan2(dy, dx)
    wob = sample_wrap(spectral(EV, 3.2, seed, 1, 5), C + 60 * np.cos(theta), C + 60 * np.sin(theta))
    base = 80.0 * (1 + 0.22 * (wob - 0.5))
    u = r / base
    shell = np.exp(-((u - 0.92) / 0.13) ** 2) + 0.35 * np.exp(-((u - 0.70) / 0.2) ** 2)
    clumps = smoothstep(0.52, 0.85, spectral(EV, 2.0, seed + 1, 5, 60))
    web = np.exp(-((spectral(EV, 3.0, seed + 2, 3, 40) - 0.5) / 0.035) ** 2) * 0.8
    web += np.exp(-((spectral(EV, 3.0, seed + 6, 4, 50) - 0.5) / 0.03) ** 2) * 0.5
    matter = (clumps * 1.1 + web) * shell * (0.55 + 0.45 * smoothstep(0.3, 0.7, wob))
    mix = spectral(EV, 3.4, seed + 3, 1, 8)
    mix2 = spectral(EV, 3.4, seed + 4, 1, 8)
    tone = (np.array([1.0, 0.36, 0.32]) * smoothstep(0.35, 0.65, mix)[..., None]
            + np.array([0.40, 0.95, 0.80]) * smoothstep(0.65, 0.35, mix)[..., None] * smoothstep(0.4, 0.6, mix2)[..., None]
            + np.array([1.0, 0.80, 0.45]) * smoothstep(0.6, 0.4, mix2)[..., None] * 0.7)
    tone = tone * 0.75 + 0.25
    gaps = smoothstep(0.30, 0.60, sample_wrap(spectral(EV, 3.0, seed + 5, 1, 6), C + 50 * np.cos(theta), C + 50 * np.sin(theta)))
    shock = np.exp(-((u - 1.10) / 0.025) ** 2) * gaps * 0.55
    fill = np.exp(-(u / 0.8) ** 4) * (0.4 + 0.6 * spectral(EV, 2.6, seed + 7, 2, 18)) * 0.07
    lit = matter[..., None] * tone * 0.75 + col(shock, (0.65, 0.82, 1.0)) + col(fill, (0.55, 0.45, 0.95))
    lit = shoulder(blur_plain(lit, 0.7) + blur_plain(lit, 4.0) * 0.45, 1.3)
    core = np.exp(-(r / 0.8) ** 2) * 0.8 + np.exp(-r / 3.0) * 0.12
    return (lit + col(core, (0.75, 0.85, 1.0))) * round_edge(xx, yy, 20)[..., None]


# ---------------------------------------------------------------- a far-off battle

def fleet(frame, seed, ships=16):
    """A battle line: small lit hulls pointing east (the game turns each side to face the other), each with a drive glow at its
    stern and a sunlit edge, one capital ship three times their size, and the odd muzzle flash. White: the game tints each side.
    (Real-client check 2026-11-21: single-pixel ships read as dots; these read as ships at the size the game draws them.)"""
    rng = np.random.default_rng(seed)
    flick = np.random.default_rng(seed * 10 + frame)
    xx, yy = grid()
    lit = np.zeros((EV, EV))
    drive = np.zeros((EV, EV))
    flash_ = np.zeros((EV, EV))
    placed = []
    for k in range(ships):
        for _ in range(30):  # a loose line, no two hulls on top of each other
            x = C + rng.normal(0, 30)
            y = C + rng.normal(0, 14)
            if all(np.hypot(x - px, y - py) > 12 for px, py in placed):
                break
        placed.append((x, y))
        length = 24.0 if k == 0 else rng.uniform(8.0, 14.0)
        width = length * (0.30 if k == 0 else 0.34)
        u, v = (xx - x) / (length / 2), (yy - y) / (width / 2)
        taper = 1 - 0.55 * smoothstep(0.1, 1.0, u)  # a pointed bow, a blunt stern
        body = smoothstep(1.05, 0.75, np.hypot(u, v / np.maximum(taper, 0.2)))
        edge_ = body * smoothstep(0.1, -0.9, v)  # the sunlit side
        lit += body * 0.55 + edge_ * 0.65
        if k == 0:  # a capital ship's superstructure: a lit ridge and a few lights along it
            lit += np.exp(-((v + 0.1) / 0.18) ** 2) * (np.abs(u) < 0.6) * body * 0.45
        sx = x - length / 2
        drive += np.exp(-(((xx - sx) / 1.4) ** 2 + ((yy - y) / 1.1) ** 2)) * flick.uniform(0.7, 1.0) * (1.4 if k == 0 else 1.0)
        drive += np.exp(-(((xx - sx + 2.5) / 3.0) ** 2 + ((yy - y) / 1.0) ** 2)) * 0.16  # its exhaust
        if flick.uniform() < 0.2:
            fx = x + length / 2
            flash_ += np.exp(-((xx - fx) ** 2 + (yy - y) ** 2) / 1.2) * 1.4 + np.exp(-((xx - fx) ** 2 + (yy - y) ** 2) / 9.0) * 0.3
    hull = blur_plain(col(np.clip(lit, 0, 1.2), (0.92, 0.94, 1.0)), 0.4)
    img = hull + col(drive, (0.75, 0.85, 1.0)) + col(flash_, (1.0, 1.0, 1.0))
    return img * edge(xx, yy)[..., None]


def bolt(length=18.0):
    """A shot: a bright head and a short fading streak (east). White: tinted per side."""
    xx, yy = grid()
    hx = C + length / 2
    b = hx - xx
    along = np.where(b < 0, np.exp(-(b / 0.8) ** 2), np.exp(-np.clip(b, 0, None) / (length * 0.45)) * (b < length * 1.6))
    return col(along * np.exp(-((yy - C) / 0.55) ** 2) * 1.3 + np.exp(-((xx - hx) ** 2 + (yy - C) ** 2) / 1.4) * 0.6, (1, 1, 1))


def volley():
    """Four shots fired together from a line of ships, staggered."""
    xx, yy = grid()
    out = np.zeros((EV, EV, 3))
    for k, (dy, dx) in enumerate(((-6, 0), (-2, 7), (3, -4), (7, 4))):
        out += np.roll(np.roll(bolt(16.0 - k), dy, 0), dx, 1) * (1.0 - k * 0.12)
    return out * edge(xx, yy)[..., None]


def lance():
    """A capital ship's beam: a long hard line with a glow round it, brightest at the gun (west end)."""
    xx, yy = grid()
    x0, x1 = 14.0, EV - 14.0
    on = smoothstep(x0 - 1, x0 + 2, xx) * smoothstep(x1 + 1, x1 - 30, xx)
    fall = 0.65 + 0.35 * np.exp(-(xx - x0) / 80.0)
    lit = (np.exp(-((yy - C) / 0.55) ** 2) * 1.2 + np.exp(-((yy - C) / 2.6) ** 2) * 0.25) * on * fall
    lit += np.exp(-((xx - x0) ** 2 + (yy - C) ** 2) / 6.0) * 1.2
    return col(lit, (1, 1, 1))


def pop(seed=7):
    """A ship going up, small: a white flash in an orange ball, a few sparks thrown out."""
    rng = np.random.default_rng(seed)
    xx, yy = grid()
    r = np.hypot(xx - C, yy - C)
    img = col(1.6 * np.exp(-(r / 2.2) ** 2), (1, 0.98, 0.9)) + col(0.65 * np.exp(-(r / 7.0) ** 2), (1, 0.55, 0.20)) + col(0.12 * np.exp(-r / 16.0), (1, 0.35, 0.12))
    for _ in range(22):
        a = rng.uniform(0, 2 * np.pi)
        d = rng.uniform(6, 22)
        splat(img, int(C + np.cos(a) * d), int(C + np.sin(a) * d), np.array([1.0, 0.75, 0.4]), rng.uniform(0.3, 0.9) * np.exp(-d / 26))
    return img * round_edge(xx, yy, 60)[..., None]


def kill(seed=8):
    """A capital ship breaking apart: a hard flash, a ball of fire, a spray of burning wreckage and a cloud of glowing gas."""
    rng = np.random.default_rng(seed)
    xx, yy = grid()
    r = np.hypot(xx - C, yy - C)
    theta = np.arctan2(yy - C, xx - C)
    lumpy = sg.polar_noise(spectral(EV, 2.6, seed, 2, 20), theta, r, 1, 0.08)
    gas = np.exp(-(r / (22 * (0.7 + 0.6 * lumpy))) ** 2)
    img = col(2.0 * np.exp(-(r / 3.5) ** 2), (1, 1, 0.95)) + col(gas * 0.55, (1.0, 0.58, 0.25)) + col(gas ** 3 * 0.5, (1, 0.9, 0.7))
    img += col(np.exp(-r / 40.0) * 0.12 * lumpy, (0.9, 0.4, 0.5))
    for _ in range(46):
        a = rng.uniform(0, 2 * np.pi)
        d = rng.uniform(10, 70)
        x, y = C + np.cos(a) * d, C + np.sin(a) * d
        splat(img, int(x), int(y), np.array([1.0, 0.7, 0.35]), rng.uniform(0.35, 1.0) * np.exp(-d / 80))
        for s in range(1, 5):  # a short streak back toward the middle
            splat(img, int(x - np.cos(a) * s), int(y - np.sin(a) * s), np.array([1.0, 0.5, 0.2]), 0.25 * (1 - s / 5) * np.exp(-d / 80))
    return img * round_edge(xx, yy, 40)[..., None]


# ---------------------------------------------------------------- an ion storm on Lavaland

AURORA_FRAMES = 8
AURORA_DELAY = 3


def aurora(phase, seed=501):
    """Aurorae round both of Lavaland's poles in an ion storm, at the planet's size (the game lays this over it): tall
    curtains standing on each auroral oval, a hard green foot shading up into a soft crimson top, folding and rippling along
    the oval (phase 0..1). The near side of an oval lies over the disc; the far side shows where it stands up past the limb,
    where it's brightest, seen edge on through the whole height of the curtains."""
    rng = np.random.default_rng(seed)
    R = AURORA_R
    cx = cy = C
    canvas = np.zeros((EV, EV, 3))
    wobble = spectral(EV, 2.4, seed, 2, 24)
    rays = spectral(EV, 1.4, seed + 1, 12, None)
    xx, yy = grid()
    green = np.array([0.20, 1.00, 0.42])
    crimson = np.array([0.85, 0.12, 0.60])
    for pole, power, lat_y, a_x, a_y in ((-1, 1.0, 0.80, 0.56, 0.16), (1, 0.6, 0.84, 0.48, 0.13)):
        steps = 640
        for k in range(steps):
            th = 2 * np.pi * k / steps
            bx = cx + a_x * R * np.cos(th)
            by = cy + pole * lat_y * R - pole * a_y * R * np.sin(th)
            near = np.sin(th) > 0  # the half of the oval on our side of the pole
            ripple = 0.5 + 0.5 * np.sin(5 * th - 2 * np.pi * phase) * np.sin(3 * th + 4 * np.pi * phase + 1.3)
            fold = sample_wrap(wobble, np.array([th / (2 * np.pi) * EV * 2]), np.array([phase * EV * 0.25 + (pole + 1) * 60]))[0]
            ray = sample_wrap(rays, np.array([th / (2 * np.pi) * EV * 3]), np.array([phase * EV + (pole + 1) * 90]))[0]
            strength = power * (0.25 + 0.75 * ripple) * (0.35 + 0.9 * fold) * (0.2 + 0.8 * abs(np.sin(th))) * (0.35 + 0.9 * ray ** 2)
            # curtains stand along the field: straight up off the pole, leaning out a little with the oval
            ux, uy = (bx - cx) / R * 1.1, float(pole)
            n = np.hypot(ux, uy)
            ux, uy = ux / n, uy / n
            height = R * (0.30 + 0.45 * fold + 0.25 * ray)
            for s in range(0, 30):
                t = s / 29.0
                px = bx + ux * height * t + rng.normal(0, 0.3)
                py = by + uy * height * t
                foot = np.exp(-t * 2.2) * smoothstep(0.0, 0.06, t)
                top = np.exp(-((t - 0.66) / 0.24) ** 2) * 0.40
                c = green * foot + crimson * top
                over = np.hypot(px - cx, py - cy) < R
                dim = (0.5 if near else 0.06) if over else 1.0  # the far side shows only once it's past the limb
                ix, iy = int(round(px)), int(round(py))
                if 1 <= ix < EV - 1 and 1 <= iy < EV - 1:
                    canvas[iy, ix] += c * strength * 0.13 * dim
    canvas = blur_plain(canvas, 0.7) * 2.4 + blur_plain(canvas, 4.0) * 1.2
    r = np.hypot(xx - cx, yy - cy)
    limb = np.exp(-((r - R - 2.0) / 2.5) ** 2) * 0.07 + np.exp(-((r - R - 5) / 8.0) ** 2) * 0.025
    canvas += col(limb * (0.7 + 0.3 * np.sin(np.arctan2(yy - cy, xx - cx) * 3 + phase * 2 * np.pi)), (0.55, 0.40, 1.0))
    return shoulder(canvas, 1.3) * round_edge(xx, yy, 20)[..., None]


# ---------------------------------------------------------------- comet breakup

def puff(seed=601):
    """The dust a breaking comet throws off: a lumpy, grainy cloud, cream, lit from one side."""
    xx, yy = grid()
    r = np.hypot(xx - C, yy - C)
    lump = spectral(EV, 2.6, seed, 2, 30)
    grain = spectral(EV, 1.2, seed + 1, 30, None)
    cloud = np.exp(-(r / (34 * (0.7 + 0.6 * lump))) ** 2) * (0.7 + 0.3 * grain)
    return col(cloud * 0.45, (1.0, 0.9, 0.74)) * round_edge(xx, yy, 40)[..., None]


# ---------------------------------------------------------------- the maelstrom: an ion vortex opening over the station

def vortex(seed=901, arms=3, wind=5.0, inner=(0.80, 0.92, 1.00), mid=(0.46, 0.58, 1.00), outer=(0.56, 0.32, 0.88), power=0.70, sharp=3.2):
    """A storm of glowing gas wound into a spiral round a dark eye, filling the frame when the game draws it three times over:
    log-spiral arms (arms of them, wound wind radians per e-fold) with clear dark lanes between, broken into soft billows
    rather than grain, hot white-cyan at the eye's rim, periwinkle through the middle, violet at the edge. No light at all in
    the eye: the stars behind show through."""
    xx, yy = grid()
    dx, dy = (xx - C) / (EV / 2), (yy - C) / (EV / 2)
    r = np.hypot(dx, dy) + 1e-6
    theta = np.arctan2(dy, dx)
    bend = (sample_wrap(spectral(EV, 3.2, seed, 1, 8), xx, yy) - 0.5) * 1.2
    phase = arms * theta + wind * np.log(r) + bend
    arm = (0.5 + 0.5 * np.cos(phase)) ** sharp  # sharp: narrow arms, wide dark lanes (real-client check 2026-11-21: 2.4 read as haze)
    # filaments combed along each arm (lines of the same phase), so it holds detail drawn three times over
    comb = sample_wrap(spectral(EV, 1.8, seed + 2, 4, 40), xx + 20 * np.cos(phase), yy + 20 * np.sin(phase))
    arm = arm * (0.50 + 0.50 * (0.5 + 0.5 * np.cos(phase * 6 + comb * 6)))
    billow = 0.55 + 0.75 * sample_wrap(spectral(EV, 3.0, seed + 1, 2, 14), xx + 12 * np.cos(phase), yy + 12 * np.sin(phase))
    veil = 0.04 * (0.5 + 0.5 * np.cos(phase * 0.5 + 1.0))  # a faint haze in the lanes, so the arms sit in something
    eye = smoothstep(0.05, 0.17, r)
    edge_fall = smoothstep(1.0, 0.78, r)
    # the eye isn't empty: thin wisps of the arms' gas wind on into it, faint, the stars showing between them
    wisps = (0.5 + 0.5 * np.cos(phase * 2 + comb * 3)) ** 3 * smoothstep(0.0, 0.08, r) * (1 - eye) * 0.22
    lit = (arm * billow + veil) * eye * edge_fall + wisps
    t1 = smoothstep(0.12, 0.45, r)[..., None]
    t2 = smoothstep(0.45, 0.95, r)[..., None]
    tone = np.asarray(inner) * (1 - t1) + np.asarray(mid) * t1
    tone = tone * (1 - t2) + np.asarray(outer) * t2
    img = lit[..., None] * tone * power
    return blur_plain(img, 0.8) * round_edge(xx, yy, 10)[..., None]


def vortex_shroud(seed=901, arms=3, wind=5.0, lanes=0.50, body=0.20, eye_keep=0.85):
    """What the maelstrom's dust hides: a multiply layer (white leaves the sky as it is) turned with the near arms, darkest in
    their lanes, so the storm reads as one thing over a bright nebula instead of milk laid on it (real-client check
    2026-11-21: additive arms alone washed out over the ember sky). body darkens the whole storm, lanes the gaps between the
    arms on top; the eye keeps eye_keep of the stars."""
    xx, yy = grid()
    dx, dy = (xx - C) / (EV / 2), (yy - C) / (EV / 2)
    r = np.hypot(dx, dy) + 1e-6
    theta = np.arctan2(dy, dx)
    bend = (sample_wrap(spectral(EV, 3.2, seed, 1, 8), xx, yy) - 0.5) * 1.2  # the same field vortex(seed) bends its arms by
    phase = arms * theta + wind * np.log(r) + bend
    lane = (0.5 - 0.5 * np.cos(phase)) ** 1.6  # 1 mid-lane, 0 on an arm
    lumps = 0.75 + 0.5 * sample_wrap(spectral(EV, 3.0, seed + 5, 2, 12), xx + 10 * np.cos(phase), yy + 10 * np.sin(phase))
    storm = smoothstep(0.98, 0.55, r)  # soft all the way out: no edge to its shadow
    eye = smoothstep(0.06, 0.20, r)
    dark = (body + lanes * lane * lumps) * storm * (eye + (1 - eye) * (1 - eye_keep))
    dark = blur_plain(np.clip(dark, 0, 0.92)[..., None].repeat(3, axis=2), 1.2)
    return 1 - dark


def vortex_eye():
    """The eye's rim: a soft bright ring where the arms wind in, the hole inside left dark. The game pulses it."""
    xx, yy = grid()
    r = np.hypot(xx - C, yy - C) / (EV / 2)
    theta = np.arctan2(yy - C, xx - C)
    broken = 0.65 + 0.35 * np.cos(theta * 3 + 4 * np.log(r + 1e-3))  # the rim's brightest where the arms come in
    ring_ = np.exp(-((r - 0.15) / 0.040) ** 2) * 0.70 * broken + np.exp(-((r - 0.19) / 0.12) ** 2) * 0.16
    return col(ring_ * smoothstep(0.05, 0.12, r), (0.80, 0.92, 1.00)) * round_edge(xx, yy, 20)[..., None]


def lightning(seed):
    """A fork of lightning inside the storm, east-west across the sprite: a jagged main stroke (midpoint displaced), two or
    three branches off it, a white-violet core and a glow round it."""
    rng = np.random.default_rng(seed)

    def stroke(points, depth, spread):
        if depth == 0:
            return points
        out = [points[0]]
        for a, b in zip(points, points[1:]):
            m = (a + b) / 2
            d = b - a
            n = np.array([-d[1], d[0]]) / (np.hypot(*d) + 1e-6)
            out += [m + n * rng.normal(0, spread * np.hypot(*d)), b]
        return stroke(out, depth - 1, spread * 0.95)

    canvas = np.zeros((EV, EV, 3))
    main = stroke([np.array([C - 96.0, C + rng.normal(0, 6)]), np.array([C + 96.0, C + rng.normal(0, 6)])], 6, 0.22)
    paths = [(main, 1.0)]
    for _ in range(rng.integers(2, 4)):
        start = main[rng.integers(len(main) // 5, len(main) * 4 // 5)]
        end = start + np.array([rng.uniform(25, 60), rng.choice([-1, 1]) * rng.uniform(20, 50)])
        paths.append((stroke([start, end], 5, 0.25), 0.55))
    for pts, power in paths:
        for a, b in zip(pts, pts[1:]):
            steps = max(1, int(np.hypot(*(b - a)) * 2))
            for k in range(steps):
                p = a + (b - a) * k / steps
                ix, iy = int(round(p[0])), int(round(p[1]))
                if 0 <= ix < EV and 0 <= iy < EV:
                    canvas[iy, ix] = np.maximum(canvas[iy, ix], power)
    core = canvas[..., 0]
    glow_ = blur(core, 2.5) * 2.2 + blur(core, 9.0) * 3.0
    img = col(np.clip(core, 0, 1) * 1.2, (0.95, 0.94, 1.0)) + col(glow_, (0.62, 0.55, 1.0))
    xx, yy = grid()
    return img * edge(xx, yy, 10)[..., None]


# ---------------------------------------------------------------- the set

def build_tiles():
    """{state: PIL image or [frames]} for sky_events.dmi, and the delays for the animated ones."""
    out = {}
    for i, (name, args) in enumerate(METEORS.items()):
        out[name] = additive_image(meteor(700 + i, *args), 700 + i)
    out['comet'] = [additive_image(comet(f / COMET_FRAMES), 720 + f) for f in range(COMET_FRAMES)]
    out['comet_shard'] = additive_image(comet(0.3, seed=77, scale=0.55, ion_power=0.7), 731)
    out['ship'] = [additive_image(ship(f), 740 + f) for f in range(SHIP_FRAMES)]
    out['convoy'] = [additive_image(convoy(f), 750 + f) for f in range(SHIP_FRAMES)]
    out['flash'] = additive_image(flash(), 760)
    out['glow'] = additive_image(glow(), 761)
    out['star_point'] = additive_image(star_point(), 762)
    out['ring'] = additive_image(ring(), 763)
    out['remnant'] = additive_image(remnant(), 764)
    out['fleet_a'] = [additive_image(fleet(f, 11), 770 + f) for f in range(4)]
    out['fleet_b'] = [additive_image(fleet(f, 12), 774 + f) for f in range(4)]
    out['bolt'] = additive_image(bolt(), 778)
    out['volley'] = additive_image(volley(), 779)
    out['lance'] = additive_image(lance(), 780)
    out['pop'] = additive_image(pop(), 781)
    out['kill'] = additive_image(kill(), 782)
    out['aurora'] = [additive_image(aurora(f / AURORA_FRAMES), 790 + f) for f in range(AURORA_FRAMES)]
    out['puff'] = additive_image(puff(), 799)
    out['vortex'] = additive_image(vortex(), 801)
    out['vortex_far'] = additive_image(vortex(911, 2, 3.4, (0.60, 0.62, 1.0), (0.38, 0.36, 0.92), (0.46, 0.24, 0.76), 0.30, 2.6), 802)  # dimmer and violet: a backdrop, so the near arms' lanes stay dark
    out['vortex_eye'] = additive_image(vortex_eye(), 803)
    out['vortex_shroud'] = additive_image(vortex_shroud(), 804)  # drawn BLEND_MULTIPLY
    out['lightning'] = additive_image(lightning(931), 804)
    out['lightning2'] = additive_image(lightning(941), 805)
    import events2
    out.update(events2.build_tiles(additive_image))
    DELAYS.update(events2.DELAYS)
    return out


DELAYS = {'comet': [COMET_DELAY] * COMET_FRAMES, 'ship': SHIP_DELAYS, 'convoy': SHIP_DELAYS, 'fleet_a': [3, 2, 4, 3],
          'fleet_b': [2, 4, 3, 3], 'aurora': [AURORA_DELAY] * AURORA_FRAMES}


def write_sheet(states, path, size, delays):
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'mapmerge2'))
    from dmi import Dmi
    dmi = Dmi(size, size)
    for name, image in states.items():
        state = dmi.state(name)
        if isinstance(image, list):
            for frame, delay in zip(image, delays.get(name, [2] * len(image))):
                state.frame(frame, delay=delay)
        else:
            state.frame(image)
    dmi.to_file(path)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'build'
    import dust
    if mode == 'build':
        path = os.path.join(OUT_DIR, 'sky_events.dmi')
        write_sheet(build_tiles(), path, EV, DELAYS)
        print('%s  %d KB' % (os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))
        path = os.path.join(OUT_DIR, 'sky_events_dust.dmi')
        write_sheet(dust.build_tiles(), path, sg.TILE, dust.DELAYS)
        print('%s  %d KB' % (os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))
        import events2
        path = os.path.join(OUT_DIR, 'sky_events_big.dmi')
        write_sheet(events2.build_big(), path, events2.BIG, {})
        print('%s  %d KB' % (os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))
    elif mode == 'preview':
        import preview
        preview.main(sys.argv[2:])
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == '__main__':
    main()
