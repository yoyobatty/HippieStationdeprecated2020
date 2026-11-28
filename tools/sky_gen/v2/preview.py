"""Previews of the fly-bys, the rare events and the dust, over the current sky: data/previews/sky2_*.png.

    python tools/sky_gen/v2/flyby.py preview [name ...]

Each event is the same timeline the game runs (hippiestation/code/_onclick/hud/sky.dm), ported line for line: pieces made at
the times the game's timers make them, animate() steps with their easing, the same transforms. A small renderer draws the
pieces at a moment the way the client does (bilinear, additive, alpha and colour) over sky_gen's picture of a theme. Key moments
go side by side, each a 480 x 480 view (15 tiles) shown at twice size, captioned with the time.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import sky_gen as sg  # noqa: E402
import flyby  # noqa: E402
import dust  # noqa: E402

VIEW = 480
MIDDLE = VIEW / 2 - flyby.EV / 2  # SKY_EVENT_MIDDLE
OUT = os.path.join(sg.ROOT, 'data', 'previews')
STREAK_LEAD, COMET_LEAD, SHARD_LEAD = 84.5, 94.5, 63

# ---------------------------------------------------------------- DM's maths, as BYOND does it


def cos(d):
    return math.cos(math.radians(d))


def sin(d):
    return math.sin(math.radians(d))


def arctan(x, y):
    return math.degrees(math.atan2(y, x))


def matrix(a=1, b=0, c=0, d=0, e=1, f=0):
    return [a, b, c, d, e, f]


def turned(m, angle):
    """M.Turn(angle): clockwise, after what's there."""
    ca, sa = cos(angle), sin(angle)
    a, b, c, d, e, f = m
    return [ca * a + sa * d, ca * b + sa * e, ca * c + sa * f, -sa * a + ca * d, -sa * b + ca * e, -sa * c + ca * f]


def sky_at(x, y, heading=0, size=1, size_y=None):
    m = matrix(size, 0, 0, 0, size if size_y is None else size_y, 0)
    if heading:
        m = turned(m, heading)
    m[2] += x + MIDDLE
    m[5] += y + MIDDLE
    return m


def hexrgb(text):
    text = text.lstrip('#')
    return np.array([int(text[i:i + 2], 16) for i in (0, 2, 4)], dtype=float) / 255


def ease(kind, t):
    if kind == 'sine':
        return 0.5 - 0.5 * math.cos(math.pi * t)
    if kind == 'quad_out':
        return 1 - (1 - t) ** 2
    if kind == 'quad_in':
        return t * t
    return t


class Piece:
    """An /obj/screen/sky_art/piece: made at t0, gone after life (0 stays), animated by steps."""

    def __init__(self, sim, state, life, layer_add=0):
        self.state, self.t0, self.life, self.layer = state, sim.now, life, 20 + layer_add
        self.alpha, self.transform, self.color = 0.0, matrix(), np.ones(3)
        self.steps = []
        self.spin = None  # (period, first angle, size): SSparallax.spin(), turned by angle (BYOND takes a turn apart)
        self.parallel = []  # a second chain run alongside (ANIMATION_PARALLEL)
        self.overlay, self.pixel, self.turning = False, (0, 0), None
        self.multiply = False  # BLEND_MULTIPLY: dst * (1 - a + a * src), white leaves it as it is  # drawn over (BLEND_OVERLAY), pixel_x/y, prism turn
        sim.pieces.append(self)

    def animate(self, time, easing=None, loop=False, parallel=False, **changes):
        if 'color' in changes:
            changes['color'] = hexrgb(changes['color'])
        if parallel:
            self._in_parallel = True
        (self.parallel if self._in_parallel else self.steps).append((max(time, 0.001), changes, easing, loop))
        return self

    _in_parallel = False

    def at(self, t):
        """alpha, transform, colour t ds after it was made"""
        t -= self.t0
        if t < 0 or (self.life and t >= self.life):
            return None
        state = {'alpha': self.alpha, 'transform': list(self.transform), 'color': self.color}
        for chain in (self.steps, self.parallel):
            clock = 0
            loop_len = sum(x[0] for x in chain) if chain and chain[0][3] else None
            tt = t % loop_len if loop_len else t
            for time, changes, easing, _ in chain:
                if tt <= clock:
                    break
                f = ease(easing, min(1.0, (tt - clock) / time))
                for key, goal in changes.items():
                    start = state[key]
                    if key == 'transform':
                        state[key] = [s + (g - s) * f for s, g in zip(start, goal)]
                    else:
                        state[key] = start + (np.asarray(goal, dtype=float) - start) * f
                clock += time
        if self.turning:
            path, angle, turn, size, crossing = self.turning
            f = min(1.0, t / crossing)
            state['transform'] = sky_at(path[0] + path[2] * path[4] * (2 * f - 1), path[1] + path[3] * path[4] * (2 * f - 1), angle + turn * f, size)
        if self.spin:
            period, angle, size = self.spin
            state['transform'] = sky_at(0, 0, angle + 360 * (t / period), size)
        return state


class Sim:
    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.pieces = []
        self.timers = []
        self.now = 0
        self.planet = False
        # the round's sky, as SSparallax.body_places has it (pixels from the middle) and each one's reach (sky_clearance())
        self.places = {'sun': (-150, 90, 110), 'world': (120, -95, 70), 'deep1': (170, 120, 110)}

    def rand(self, lo, hi):
        return int(self.rng.integers(lo, hi + 1))

    def prob(self, p):
        return self.rng.uniform(0, 100) < p

    def pick(self, items):
        return items[self.rng.integers(0, len(items))]

    def pickweight(self, weights):
        keys = [k for k, w in weights.items() if w > 0]
        w = np.array([weights[k] for k in keys], dtype=float)
        return keys[self.rng.choice(len(keys), p=w / w.sum())]

    def addtimer(self, fn, delay):
        self.timers.append((self.now + delay, fn))

    def run_until(self, t):
        """Runs the timers due by t, in order (they may add more)."""
        while True:
            due = [x for x in self.timers if x[0] <= t]
            if not due:
                return
            first = min(due, key=lambda x: x[0])
            self.timers.remove(first)
            self.now = first[0]
            first[1]()


# ---------------------------------------------------------------- sky.dm's events, ported

def sky_path(heading, miss, half):
    ax, ay = cos(heading), -sin(heading)
    return [-ay * miss, ax * miss, ax, ay, half]


def on_path(path, f, face, lead=0, size=1, flip=1):
    hx = path[0] + path[2] * path[4] * (2 * f - 1)
    hy = path[1] + path[3] * path[4] * (2 * f - 1)
    return sky_at(hx - cos(face) * lead * size, hy + sin(face) * lead * size, face, size, size * flip)


def sky_clearance(s, x, y, solid=False, lavaland=True):
    out = min(math.hypot(x - px, y - py) - reach for name, (px, py, reach) in s.places.items() if not (solid and name.startswith('deep')))
    return min(out, lavaland_clearance(s, x, y)) if lavaland else out  # Lavaland's drawn over the fly-bys


def path_clearance(s, path, tail=0, solid=False):
    out = math.inf
    sun = s.places['sun']
    for step in range(25):
        f = step / 24
        x = path[0] + path[2] * path[4] * (2 * f - 1)
        y = path[1] + path[3] * path[4] * (2 * f - 1)
        if abs(x) < 310 and abs(y) < 250:
            out = min(out, sky_clearance(s, x, y, solid))
        if tail:
            away = math.hypot(x - sun[0], y - sun[1]) or 1
            for part in (0.5, 1):
                tx, ty = x + (x - sun[0]) / away * tail * part, y + (y - sun[1]) / away * tail * part
                if abs(tx) < 310 and abs(ty) < 250:
                    out = min(out, sky_clearance(s, tx, ty))
    return out


def clear_path(s, lo, hi, half=400, tail=0):
    best, best_clear = None, -math.inf
    for _ in range(40):
        path = sky_path(s.rand(0, 359), s.rand(lo, hi) * s.pick([-1, 1]), half)
        c = path_clearance(s, path, tail)
        if c > best_clear:
            best, best_clear = path, c
        if c >= 0:
            break
    return best


def clear_place(s, lo, hi, margin):
    best, best_clear = None, -math.inf
    for _ in range(30):
        a = s.rand(0, 359)
        out = s.rand(lo, hi)
        x, y = cos(a) * out * 1.15, sin(a) * out * 0.85
        c = sky_clearance(s, x, y)
        if c > best_clear:
            best, best_clear = (x, y), c
        if c >= margin:
            break
    return best


def send_meteor(s, state, path, time, size=1):
    P = Piece(s, state, time + 5)
    heading = -arctan(path[2], path[3])
    P.transform = on_path(path, 0, heading, STREAK_LEAD, size)
    if state == 'bolide':
        P.animate(time * 0.15, alpha=255, transform=on_path(path, 0.15, heading, STREAK_LEAD, size))
        P.animate(time * 0.4, transform=on_path(path, 0.55, heading, STREAK_LEAD, size))
        P.animate(time * 0.1, transform=on_path(path, 0.65, heading, STREAK_LEAD, size * 1.3))
        P.animate(time * 0.35, alpha=0, transform=on_path(path, 1, heading, STREAK_LEAD, size * 1.1))
        return P
    P.animate(time * 0.1, alpha=255, transform=on_path(path, 0.1, heading, STREAK_LEAD, size))
    P.animate(time * 0.8, transform=on_path(path, 0.9, heading, STREAK_LEAD, size))
    P.animate(time * 0.1, alpha=0, transform=on_path(path, 1, heading, STREAK_LEAD, size))
    return P


def send_ship(s, kind, time=None):
    time = time or (s.rand(500, 800) if kind == 'convoy' else s.rand(350, 600))
    path = clear_path(s, 0, 170)
    heading = -arctan(path[2], path[3])
    P = Piece(s, kind, time + 5)
    P.transform = on_path(path, 0, heading)
    P.animate(time * 0.15, alpha=225, transform=on_path(path, 0.15, heading))
    P.animate(time * 0.7, transform=on_path(path, 0.85, heading))
    P.animate(time * 0.15, alpha=0, transform=on_path(path, 1, heading))
    return time


def send_comet(s, time=None, through_middle=False, break_at=None):
    time = time or s.rand(2400, 3300)
    path = clear_path(s, 0, 90, 400, 170) if through_middle else clear_path(s, 0, 160, 400, 170)
    if break_at:
        best = -math.inf
        for attempt in range(20):
            maybe = path if attempt == 0 else clear_path(s, 0, 90, 400, 170)
            ax = maybe[0] + maybe[2] * maybe[4] * (2 * break_at - 1)
            ay = maybe[1] + maybe[3] * maybe[4] * (2 * break_at - 1)
            clear = min(lavaland_clearance(s, ax, ay) - 60, path_clearance(s, maybe, 170) + 30)
            if clear > best:
                best, path = clear, maybe
            if clear >= 0:
                break
    sun = s.places['sun']
    toward = arctan(sun[0] - path[0], sun[1] - path[1])
    face = -toward
    flip = 1 if (path[2] * -sin(toward) + path[3] * cos(toward)) > 0 else -1
    P = Piece(s, 'comet', time + 5)
    P.transform = on_path(path, 0, face, COMET_LEAD, 1, flip)
    P.animate(time * 0.15, alpha=235, transform=on_path(path, 0.15, face, COMET_LEAD, 1, flip))
    if not break_at:
        P.animate(time * 0.7, transform=on_path(path, 0.85, face, COMET_LEAD, 1, flip))
        P.animate(time * 0.15, alpha=0, transform=on_path(path, 1, face, COMET_LEAD, 1, flip))
        return time
    P.animate(time * (break_at - 0.15), transform=on_path(path, break_at, face, COMET_LEAD, 1, flip))
    P.animate(20, alpha=0, transform=on_path(path, break_at + 20 / time, face, COMET_LEAD, 1, flip))
    s.addtimer(lambda: comet_breaks(s, path, break_at, time, face, flip), time * break_at)
    return time


def comet_breaks(s, path, break_at, time, face, flip):
    hx = path[0] + path[2] * path[4] * (2 * break_at - 1)
    hy = path[1] + path[3] * path[4] * (2 * break_at - 1)
    speed = path[4] * 2 / time
    motion = -arctan(path[2], path[3])
    f = Piece(s, 'flash', 60, 0.3)
    f.color = hexrgb('#d8f6ff')
    f.transform = sky_at(hx, hy, 0, 0.12)
    f.animate(3, alpha=255, transform=sky_at(hx, hy, 0, 0.45))
    f.animate(50, 'quad_out', alpha=0, transform=sky_at(hx, hy, 0, 0.2))
    turn = s.rand(0, 359)
    sh = Piece(s, 'ring', 70, 0.2)
    sh.transform = sky_at(hx, hy, turn, 0.02)
    sh.animate(2, alpha=140)
    sh.animate(65, 'quad_out', alpha=0, transform=sky_at(hx, hy, turn, 0.35))
    d = Piece(s, 'puff', 910, -0.1)
    d.transform = sky_at(hx, hy, turn, 0.2)
    d.animate(150, alpha=150, transform=sky_at(hx + path[2] * speed * 75, hy + path[3] * speed * 75, turn, 0.7))
    d.animate(750, alpha=0, transform=sky_at(hx + path[2] * speed * 450, hy + path[3] * speed * 450, turn, 1.5))
    left = time * (1 - break_at)
    for piece in range(1, 5):
        swerve = 0 if piece == 1 else s.rand(-7, 7)
        pace = speed if piece == 1 else speed * s.rand(84, 112) / 100
        size = 1 if piece == 1 else s.rand(55, 85) / 100
        sp = [0, 0, cos(motion + swerve), -sin(motion + swerve), pace * left / 2]
        sp[0] = hx + s.rand(-2, 2) + sp[2] * sp[4]
        sp[1] = hy + s.rand(-2, 2) + sp[3] * sp[4]
        sf = face + s.rand(-3, 3)
        P = Piece(s, 'comet_shard', left + 5, piece * 0.01)
        P.transform = on_path(sp, 0, sf, SHARD_LEAD, size, flip)
        lit = 30 / left
        P.animate(30, alpha=120 + 110 * size, transform=on_path(sp, lit, sf, SHARD_LEAD, size, flip))
        P.animate(left * (0.8 - lit), transform=on_path(sp, 0.8, sf, SHARD_LEAD, size, flip))
        P.animate(left * 0.2, alpha=0, transform=on_path(sp, 1, sf, SHARD_LEAD, size, flip))


def start_vortex(s, peak=None):
    fade = 450
    peak = peak or s.rand(3600, 5400)
    life = peak + fade * 2 + 5
    far = Piece(s, 'vortex_far', life, -3)
    far.spin = (4200, s.rand(0, 359), 3.1)
    far.animate(fade, 'sine', alpha=170)
    far.animate(peak)
    far.animate(fade, 'sine', alpha=0)
    near_angle = s.rand(0, 359)
    shroud = Piece(s, 'vortex_shroud', life, -3.05)
    shroud.multiply = True
    shroud.spin = (2400, near_angle, 3.4)
    shroud.animate(fade, 'sine', alpha=255)
    shroud.animate(peak)
    shroud.animate(fade, 'sine', alpha=0)
    near = Piece(s, 'vortex', life, -2.9)
    near.spin = (2400, near_angle, 3.4)
    near.animate(fade, 'sine', alpha=215)
    near.animate(peak)
    near.animate(fade, 'sine', alpha=0)
    eye = Piece(s, 'vortex_eye', life, -2.8)
    eye.transform = sky_at(0, 0, 0, 2.0)
    eye.animate(25, 'sine', loop=True, color='#7c7c7c')
    eye.animate(18, 'sine', color='#ffffff')
    eye.animate(fade * 1.6, 'sine', parallel=True, alpha=220, transform=sky_at(0, 0, 0, 3.4))
    eye.animate(peak - fade * 0.6)
    eye.animate(fade, 'sine', alpha=0)
    at = fade
    while at < fade + peak:
        s.addtimer(lambda: vortex_lightning(s), at)
        if s.prob(30):
            s.addtimer(lambda: vortex_lightning(s), at + s.rand(3, 8))
        at += s.rand(25, 160)
    s.lightning_at = [x[0] for x in s.timers]
    return life


def vortex_lightning(s):
    for _ in range(6):
        angle = s.rand(0, 359)
        out = s.rand(90, 230)
        x, y = cos(angle) * out, sin(angle) * out
        if sky_clearance(s, x, y) > 40:
            break
    size = s.rand(80, 135) / 100
    B = Piece(s, s.pick(['lightning', 'lightning2']), 15, 0.5)
    B.transform = sky_at(x, y, -angle + 90 + s.rand(-35, 35), size, size * s.pick([-1, 1]))
    for alpha, t in ((255, 1), (80, 1), (255, 1)):
        B.animate(t, alpha=alpha)
    B.animate(9, 'quad_out', alpha=0)
    L = Piece(s, 'glow', 14, -2.5)
    L.color = hexrgb('#9c94e0')
    L.transform = sky_at(x * 0.85, y * 0.85, 0, 2.6)
    for alpha, t in ((34, 1), (12, 1), (28, 1)):
        L.animate(t, alpha=alpha)
    L.animate(10, 'quad_out', alpha=0)


def start_shower(s, length=4200):
    best, rx, ry = -1, 0, 0
    first = s.rand(0, 23) * 15
    for turn in range(24):
        bearing = first + turn * 15
        x, y = cos(bearing) * 380, sin(bearing) * 330
        clear = 0
        for aim in range(1, 13):
            ax, ay = (aim % 4 - 1.5) * 160, ((aim - 1) // 4 - 1) * 150
            dist = math.hypot(ax - x, ay - y)
            if path_clearance(s, [x + (ax - x) / dist * 450, y + (ay - y) / dist * 450, (ax - x) / dist, (ay - y) / dist, 450], 0, True) >= 0:
                clear += 1
        if clear > best:
            best, rx, ry = clear, x, y
    for _ in range(s.rand(1600, 1800)):
        s.addtimer(lambda: shower_meteor(s, rx, ry), min(0.99, max(0.01, s.rng.normal(0.5, 0.17))) * length)
    s.radiant = (rx, ry)
    return length


def shower_meteor(s, rx, ry):
    path = None
    for _ in range(12):
        ax, ay = s.rand(-280, 280), s.rand(-220, 220)
        dx, dy = ax - rx, ay - ry
        dist = math.hypot(dx, dy)
        start = s.rand(0, 90)
        maybe = [rx + dx / dist * (start + 450), ry + dy / dist * (start + 450), dx / dist, dy / dist, 450]
        if lavaland_clearance(s, ax, ay) >= 0:
            path = maybe
            break
    if not path:
        return
    state = s.pickweight({'meteor': 6, 'meteor_o': 2, 'meteor_b': 3, 'bolide': 1})
    send_meteor(s, state, path, s.rand(30, 40) if state == 'bolide' else s.rand(15, 24), 1 if state == 'bolide' else s.rand(65, 100) / 100)


def start_supernova(s):
    x, y = clear_place(s, 70, 140, 60)
    star = Piece(s, 'star_point', 640)
    star.transform = sky_at(x, y)
    star.color = hexrgb('#ffe6c8')
    star.animate(200, alpha=190, transform=sky_at(x, y, 0, 1.25))
    star.animate(400, 'quad_in', alpha=255, color='#ffffff', transform=sky_at(x, y, 0, 2.2))
    star.animate(20, alpha=0)
    s.addtimer(lambda: supernova_flash(s, x, y), 600)
    return 6000


def supernova_flash(s, x, y):
    f = Piece(s, 'flash', 0, 0.3)
    f.color = hexrgb('#f4f8ff')
    f.transform = sky_at(x, y, 0, 0.3)
    f.animate(12, 'sine', alpha=255, transform=sky_at(x, y, 0, 1.5))
    f.animate(150, 'sine', alpha=220, transform=sky_at(x, y, 0, 1.05))
    f.animate(900, 'sine', alpha=150, color='#ffd9b4', transform=sky_at(x, y, 0, 0.75))
    f.animate(4800, 'sine', alpha=80, color='#ff9a7c', transform=sky_at(x, y, 0, 0.5))
    g = Piece(s, 'glow', 360, -2)
    g.color = hexrgb('#e8f0ff')
    g.transform = sky_at(x, y, 0, 5)
    g.animate(12, 'sine', alpha=105)
    g.animate(340, 'quad_out', alpha=0)
    turn = s.rand(0, 359)
    sh = Piece(s, 'ring', 470, 0.2)
    sh.color = hexrgb('#cfe4ff')
    sh.transform = sky_at(x, y, turn, 0.03)
    sh.animate(25, alpha=120)
    sh.animate(460, 'quad_out', alpha=0, transform=sky_at(x, y, turn, 2.4))
    turn = s.rand(0, 359)
    r = Piece(s, 'remnant', 0, -0.2)
    r.transform = sky_at(x, y, turn, 0.1)
    r.animate(60, alpha=0)
    r.animate(3000, 'sine', alpha=230, transform=sky_at(x, y, turn, 0.7))
    r.animate(15000, alpha=190, transform=sky_at(x, y, turn, 1.1))


def start_battle(s, time=None):
    fade = 450
    time = time or s.rand(3000, 4200) + fade * 2
    mx, my = clear_place(s, 0, 70, 110)
    short = 70 - lavaland_clearance(s, mx, my)
    if short > 0:
        sun = s.places['sun']
        away = arctan(-sun[0], -sun[1])
        mx, my = mx - cos(away) * short, my - sin(away) * short
    line = s.rand(-25, 25) + s.pick([0, 180])
    gap = s.rand(105, 130)
    sides = [[mx - cos(line) * gap, my + sin(line) * gap, line, '#ffb48c', 'fleet_a'],
             [mx + cos(line) * gap, my - sin(line) * gap, line + 180, '#9edcff', 'fleet_b']]
    for side in sides:
        F = Piece(s, side[4], time + 5)
        F.color = hexrgb(side[3])
        F.transform = sky_at(side[0], side[1], side[2], 2.2)
        F.animate(fade, alpha=235)
        F.animate(time - fade * 2)
        F.animate(fade, alpha=0)
    at = fade * 0.6
    while at < time - fade:
        s.addtimer(lambda: battle_shot(s, sides), at)
        at += s.rand(1, 7)
    s.kills = []
    for when in (0.3, 0.55, 0.8):
        side = s.pick(sides)
        k = time * when + s.rand(-60, 60)
        s.kills.append(k)
        s.addtimer(lambda side=side: battle_kill(s, side), k)
    return time


def battle_shot(s, sides):
    frm = s.pick(sides)
    target = sides[1] if frm is sides[0] else sides[0]
    fx, fy = frm[0] + s.rand(-22, 22), frm[1] + s.rand(-12, 12)
    tx, ty = target[0] + s.rand(-24, 24), target[1] + s.rand(-13, 13)
    dx, dy = tx - fx, ty - fy
    dist = max(1, math.hypot(dx, dy))
    heading = -arctan(dx, dy)
    if s.prob(10):
        B = Piece(s, 'lance', 22, 0.1)
        B.color = hexrgb(frm[3])
        B.transform = sky_at(fx + dx * 0.5, fy + dy * 0.5, heading, dist / 228, 1.6)
        for alpha, t in ((255, 1), (140, 2), (255, 2), (205, 8), (0, 6)):
            B.animate(t, alpha=alpha)
        hit_in = 2
    else:
        V = Piece(s, 'volley', 25)
        V.color = hexrgb(frm[3])
        flight = max(4, dist / 12)
        V.transform = sky_at(fx, fy, heading, 1.7)
        V.animate(1, alpha=255, transform=sky_at(fx + dx / flight, fy + dy / flight, heading, 1.7))
        V.animate(flight - 2, alpha=210, transform=sky_at(fx + dx * 0.9, fy + dy * 0.9, heading, 1.7))
        V.animate(1, alpha=0, transform=sky_at(tx, ty, heading, 1.7))
        hit_in = flight
        if s.prob(50):
            return
    H = Piece(s, 'pop', hit_in + 16, 0.2)
    turn = s.rand(0, 359)
    H.transform = sky_at(tx, ty, turn, 0.3)
    H.animate(hit_in)
    H.animate(1, alpha=255, transform=sky_at(tx, ty, turn, 0.65))
    H.animate(s.rand(6, 12), 'quad_out', alpha=0, transform=sky_at(tx, ty, turn, 1.1))


def battle_kill(s, side):
    x, y = side[0] + s.rand(-18, 18), side[1] + s.rand(-9, 9)
    turn = s.rand(0, 359)
    K = Piece(s, 'kill', 95, 0.3)
    K.transform = sky_at(x, y, turn, 0.3)
    K.animate(2, alpha=255, transform=sky_at(x, y, turn, 0.8))
    K.animate(90, 'quad_out', alpha=0, transform=sky_at(x, y, turn, 1.8))
    R = Piece(s, 'ring', 60, 0.2)
    R.color = hexrgb('#ffd2a0')
    R.transform = sky_at(x, y, turn, 0.02)
    R.animate(1, alpha=80)
    R.animate(55, 'quad_out', alpha=0, transform=sky_at(x, y, turn, 0.8))
    L = Piece(s, 'glow', 50, -1)
    L.color = hexrgb('#ffc890')
    L.transform = sky_at(x, y, 0, 1.8)
    L.animate(2, alpha=90)
    L.animate(45, 'quad_out', alpha=0)


def start_aurora(s, time=None):
    fade = 450
    time = time or s.rand(4200, 4800)
    A = Piece(s, 'aurora', time)
    size = flyby.PLANET_R / flyby.AURORA_R
    A.transform = matrix(size, 0, MIDDLE + flyby.PLANET_X - 239.5, 0, size, MIDDLE + 239.5 - flyby.PLANET_Y)
    A.animate(fade, 'sine', alpha=170)
    A.animate(600, 'sine', alpha=120)
    A.animate(50, alpha=255)
    A.animate(500, 'sine', alpha=190)
    A.animate(400, 'sine', alpha=235)
    A.animate(time - fade * 2 - 1550)
    A.animate(fade, 'sine', alpha=0)
    s.planet = True
    return time


def start_prism(s, time=None):
    sun = s.places['sun']
    fade = 450
    time = time or s.rand(3600, 4800) + fade * 2
    wind = s.rand(0, 359)
    halo = Piece(s, 'prism_halo', time + 5, -3)
    halo.transform = sky_at(sun[0], sun[1], wind, 1.25)
    hold = max(0, time * 0.6 - fade - 1200)  # the halo goes as the crystals thin out
    halo.animate(fade).animate(1200, 'sine', alpha=110).animate(hold).animate(time - fade - 1200 - hold, 'sine', alpha=0)
    for _ in range(s.rand(60, 72)):
        depth = s.rand(0, 100) / 100
        crossing = round(1900 - 1150 * depth)
        start = min(1, max(0, s.rng.normal(0.45, 0.24))) * max(10, time - fade - crossing)
        s.addtimer(lambda d=depth, c=crossing: prism_shard(s, wind, d, c), start)
    for _ in range(s.rand(170, 210)):
        s.addtimer(lambda: prism_speck(s), min(0.97, max(0.03, s.rng.normal(0.5, 0.25))) * time)
    return time


def prism_shard(s, wind, depth, crossing):
    size = 0.3 + 0.85 * depth
    path = None
    for _ in range(8):
        maybe = sky_path(wind + s.rand(-10, 10), s.rand(-270, 270), 330 + 130 * size)
        if world_clearance(s, maybe) >= 75 * size:
            path = maybe
            break
    if not path:
        return
    P = Piece(s, s.pick(['prism_shard', 'prism_shard2', 'prism_shard3']), crossing + 5, depth * 0.5)
    angle = s.rand(0, 359)
    turning = s.rand(35, 140) * s.pick([-1, 1])
    P.transform = sky_at(path[0] - path[2] * path[4], path[1] - path[3] * path[4], angle, size)
    P.turning = (path, angle, turning * crossing / 600, size, crossing)  # decomposed: the turn and the move interpolate apart
    P.animate(40, parallel=True, alpha=round(80 + 130 * depth))
    sun = s.places['sun']
    if depth > 0.45 and s.prob(60):
        at = s.rand(25, 75) / 100
        x = path[0] + path[2] * path[4] * (2 * at - 1)
        y = path[1] + path[3] * path[4] * (2 * at - 1)
        s.addtimer(lambda: prism_flare(s, x, y, sun[0], sun[1], 0.7 + depth * 0.6), round(crossing * at))


def world_clearance(s, path):
    out = math.inf
    wx, wy, _ = s.places['world']
    for step in range(25):
        f = step / 24
        x = path[0] + path[2] * path[4] * (2 * f - 1)
        y = path[1] + path[3] * path[4] * (2 * f - 1)
        if abs(x) < 310 and abs(y) < 250:
            out = min(out, math.hypot(x - wx, y - wy) - 70)
    return out


def prism_flare(s, x, y, sx, sy, size):
    away = -arctan(x - sx, y - sy)
    P = Piece(s, 'prism_flare', 40, 1)
    P.transform = sky_at(x + cos(away) * 68 * size, y - sin(away) * 68 * size, away, size)
    P.animate(4, 'sine', alpha=255).animate(6).animate(25, 'quad_out', alpha=0)


def prism_speck(s):
    x, y = s.rand(-250, 250), s.rand(-200, 200)
    if sky_clearance(s, x, y, True) < 0:
        return
    P = Piece(s, 'star_point', 30, -0.5)
    P.color = hexrgb(s.pick(['#ffe0d0', '#fff4d0', '#e0ffe8', '#d8ecff', '#ead8ff']))
    P.transform = sky_at(x, y, s.rand(0, 359), s.rand(18, 40) / 100)
    P.animate(4, alpha=s.rand(150, 255)).animate(s.rand(12, 24), 'quad_out', alpha=0)


def lavaland_clearance(s, x, y):
    sun = s.places['sun']
    away = arctan(-sun[0], -sun[1])
    return math.hypot(x - cos(away) * 210, y - sin(away) * 210) - 150  # SKY_PLANET_CORE


def giant_clearance(s, x, y, light, size):
    out = min(sky_clearance(s, x, y, True), sky_clearance(s, x, y) + 40, lavaland_clearance(s, x, y)) - 112 * size
    major = 112 * 2.18 * size
    minor = major * 0.32
    for along in range(0, 360, 15):
        ax, ay = cos(along) * major, sin(along) * minor
        px, py = x + cos(light + 32) * ax + cos(light + 122) * ay, y + sin(light + 32) * ax + sin(light + 122) * ay
        out = min(out, sky_clearance(s, px, py, True, False), sky_clearance(s, px, py, False, False) + 40, lavaland_clearance(s, px, py) + 80)
    return out


def start_giant(s, time=None):
    fade = 450
    time = time or s.rand(3600, 5400) + fade * 2
    sun = s.places['sun']
    away = arctan(-sun[0], -sun[1])
    best, x, y, size, light = -math.inf, 0, 0, 0, 0
    for try_size in (0.9, 0.76, 0.64):
        first = s.rand(0, 11) * 30
        for turn in range(12):
            for out in (40, 75, 110, 150, 185):
                cx, cy = cos(first + turn * 30) * out * 1.1, sin(first + turn * 30) * out * 0.9
                toward = arctan(sun[0] - cx, sun[1] - cy)
                score = min(giant_clearance(s, cx, cy, toward, try_size), 40) - out * 0.06
                if score > best:
                    best, x, y, size, light = score, cx, cy, try_size, toward
        if best >= 0:
            break
    if best < -30:
        return None
    dx, dy, drift_clear = 0, 0, -math.inf
    for drift in range(8):
        ddx, ddy = cos(drift * 45 + away) * 30, sin(drift * 45 + away) * 30
        clear = min(giant_clearance(s, x - ddx, y - ddy, light, size), giant_clearance(s, x + ddx, y + ddy, light, size * 1.06))
        if clear > drift_clear + 1:
            dx, dy, drift_clear = ddx, ddy, clear
    shine = Piece(s, 'ring_shine', time + 5, -1.1)
    shine.transform = sky_at(x, y, -light, size * 2.1)
    shine.animate(fade * 2, 'sine', alpha=150).animate(time - fade * 4).animate(fade * 2, 'sine', alpha=0)
    G = Piece(s, 'giant', time + 5, -1)
    G.overlay, G.pixel = True, (-128, -128)
    G.color = np.zeros(3)
    G.transform = sky_at(x - dx, y - dy, -light, size)
    G.animate(fade * 1.5, 'sine', alpha=255, color='#ffffff').animate(time - fade * 3).animate(fade * 1.5, 'sine', alpha=0, color='#000000')
    G.animate(time, 'sine', parallel=True, transform=sky_at(x + dx, y + dy, -light, size * 1.06))
    M = Piece(s, 'moon', time + 5, -0.9)
    M.overlay = True
    major = 112 * 1.2 * size
    minor = major * 0.32
    steps = 12
    for step in range(steps + 1):
        along = 15 + 150 * step / steps
        f = step / steps
        ax, ay = cos(along) * major, sin(along) * minor
        mx = x - dx + dx * 2 * f + cos(light + 32) * ax + cos(light + 122) * ay
        my = y - dy + dy * 2 * f + sin(light + 32) * ax + sin(light + 122) * ay
        if not step:
            M.transform = sky_at(mx, my, -light, 0.9)
        else:
            M.animate(time / steps, transform=sky_at(mx, my, -light, 0.9))
    M.color = np.zeros(3)
    M.animate(fade * 1.5, 'sine', parallel=True, alpha=255, color='#ffffff').animate(time - fade * 3).animate(fade * 1.5, 'sine', alpha=0, color='#000000')
    s.giant_at = (x, y)
    return time


class Renderer:
    def __init__(self, theme_name='ember', seed=3):
        self.tiles = flyby.build_tiles()
        self.delays = flyby.DELAYS
        self.arrays = {}
        import events2
        self.tiles.update(events2.build_big())
        for name, image in self.tiles.items():
            frames = image if isinstance(image, list) else [image]
            mode = 'RGBA' if name in ('giant', 'moon') else 'RGB'  # drawn over, with their own alpha
            self.arrays[name] = [np.asarray(f.convert(mode), dtype=float) / 255 for f in frames]
        print('sky_gen tiles for the background...')
        sky = sg.build_tiles()
        self.sky_tiles = sky
        themes = sg.read_themes()
        self.theme = themes[theme_name]
        no_dust = dict(sky['sky'])
        sky['sky'] = dict(no_dust, dust=Image.new('RGBA', no_dust['dust'].size, (0, 0, 0, 255)))
        self.background = sg.as_float(sg.compose(sky, self.theme, w=VIEW, h=VIEW, seed=seed))  # the dust is the dust preview's
        self.old_dust = np.asarray(no_dust['dust'].convert('RGB'), dtype=float) / 255
        sky['sky'] = no_dust
        planet = np.asarray(sky['sky_bodies']['planet_lava'].convert('RGBA'), dtype=float) / 255
        self.planet = planet  # 480 square, drawn centred: the eye at the planet's offset
        # the round's bodies where Sim.places has them, so what keeps clear of them can be seen to
        places = Sim(0).places
        self.background += shifted(sg.as_float(sky['sky_bodies']['sun']), places['sun']) * hexrgb('#ffd2a8')
        world = np.asarray(sky['sky_bodies']['world_redrock'].convert('RGBA'), dtype=float) / 255
        world = shifted(world, places['world'])
        self.background = self.background * (1 - world[..., 3:4]) + world[..., :3] * world[..., 3:4]
        deep = Image.fromarray((sg.as_float(sky['sky_deep']['nebula_ring']) * 255).astype(np.uint8)).resize((288, 288), Image.LANCZOS)
        canvas = np.zeros((VIEW, VIEW, 3))
        canvas[96:384, 96:384] = np.asarray(deep, dtype=float) / 255
        self.background = np.clip(self.background + shifted(canvas, places['deep1']), 0, 1)
        sys.path.insert(0, os.path.join(sg.ROOT, 'tools', 'mapmerge2'))
        from dmi import Dmi
        old = Dmi.from_file(os.path.join(sg.OUT_DIR, 'sky_flyby.dmi'))  # the fly-bys as they were, for before/after
        for name in ('meteor', 'comet', 'ship'):
            self.arrays['old_' + name] = [np.asarray(f.convert('RGB'), dtype=float) / 255 for f in old.get_state(name).frames]

    def frame_of(self, name, t):
        frames = self.arrays[name]
        if len(frames) == 1:
            return frames[0]
        delays = self.delays.get(name, [2] * len(frames))
        t = t % sum(delays)
        for f, d in zip(frames, delays):
            if t < d:
                return f
            t -= d
        return frames[-1]

    def draw(self, sim, t, planet=False, base=None):
        view = (self.background if base is None else base).copy()
        if planet:
            a = self.planet[..., 3:4]
            view = view * (1 - a) + self.planet[..., :3] * a
        ys, xs = np.mgrid[0:VIEW, 0:VIEW].astype(float)
        X = xs + 0.5  # layer coordinates, y up
        Y = VIEW - (ys + 0.5)
        c = flyby.EV / 2
        for P in sorted(sim.pieces, key=lambda p: p.layer):
            img = self.frame_of(P.state, t - P.t0)
            n = img.shape[0]
            c = n / 2  # a sprite turns and scales round its own middle
            st = P.at(t)
            if st is None or st['alpha'] <= 0.5:
                continue
            a, b, cc, d, e, f = st['transform']
            det = a * e - b * d
            if abs(det) < 1e-9:
                continue
            # screen = M (p - c) + c  ->  p = M^-1 (screen - c - (cc, f)) + c
            u = X - c - cc - P.pixel[0]
            v = Y - c - f - P.pixel[1]
            px = (e * u - b * v) / det + n / 2
            py = (-d * u + a * v) / det + n / 2
            sample = bilinear(img, px - 0.5, n - py - 0.5)
            if P.multiply:
                a_ = st['alpha'] / 255.0
                view = view * (1 - a_ + a_ * sample[..., :3] * st['color'])
            elif P.overlay:
                a_ = sample[..., 3:4] * (st['alpha'] / 255.0)
                view = view * (1 - a_) + sample[..., :3] * st['color'] * a_
            else:
                view += sample * (st['alpha'] / 255.0) * st['color']
        return np.clip(view, 0, 1)


def bilinear(img, x, y):
    n = img.shape[0]
    inside = (x > -1) & (x < n) & (y > -1) & (y < n)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]

    def at(yy, xx):
        ok = (xx >= 0) & (xx < n) & (yy >= 0) & (yy < n)
        out = img[np.clip(yy, 0, n - 1), np.clip(xx, 0, n - 1)]
        return out * ok[..., None]
    out = at(y0, x0) * (1 - fx) * (1 - fy) + at(y0, x0 + 1) * fx * (1 - fy) + at(y0 + 1, x0) * (1 - fx) * fy + at(y0 + 1, x0 + 1) * fx * fy
    return out * inside[..., None]


def strip(frames, captions, path, scale=2):
    W = VIEW * scale
    out = Image.new('RGB', (W * len(frames) + 8 * (len(frames) - 1), W + 30), (18, 18, 20))
    draw = ImageDraw.Draw(out)
    for i, (arr, cap) in enumerate(zip(frames, captions)):
        im = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), 'RGB').resize((W, W), Image.NEAREST)
        out.paste(im, (i * (W + 8), 30))
        draw.text((i * (W + 8) + 8, 8), cap, fill=(220, 220, 220))
    out.save(path)
    print(os.path.relpath(path, sg.ROOT))


def secs(t):
    return '%d:%02d' % (t // 600, (t // 10) % 60)


# ---------------------------------------------------------------- the previews

def shifted(arr, place):
    """A view-sized picture with its middle moved to a sky place (pixels from the middle, y up); what's moved off is lost."""
    x, y = int(round(place[0])), int(round(-place[1]))
    out = np.zeros_like(arr)
    h, w = arr.shape[:2]
    ys, yd = (slice(max(0, -y), min(h, h - y)), slice(max(0, y), min(h, h + y)))
    xs, xd = (slice(max(0, -x), min(w, w - x)), slice(max(0, x), min(w, w + x)))
    out[yd, xd] = arr[ys, xs]
    return out


def preview_events(R, names):
    def moments_for(name, s, length):
        if name == 'vortex':
            strike = min((t for t in s.lightning_at if t > 2000), default=2000)
            return [200, 700, strike + 1, 3000, length - 200]
        if name == 'shower':
            return [600, 1400, 2100, 2800, 3600]
        if name == 'supernova':
            return [300, 595, 606, 640, 1200, 4200, 15000]
        if name == 'battle':
            return sorted([300, 1200] + [s.kills[0] + 2, s.kills[0] + 25, s.kills[2] + 4] + [length - 200])
        if name == 'aurora':
            return [300, 1000, 1110, 2400, length - 200]
        if name == 'prism':
            return [450, 1500, 2400, 3300, length - 300]
        if name == 'giant':
            return [300, 900, 2400, 3900, length - 200]
        return [500, 1240, 1270, 1450, 2100, 2700]  # breakup
    starts = {
        'vortex': lambda s: start_vortex(s, peak=4200),
        'shower': lambda s: start_shower(s),
        'supernova': lambda s: start_supernova(s),
        'battle': lambda s: start_battle(s, time=4200),
        'aurora': lambda s: start_aurora(s, time=4500),
        'breakup': lambda s: send_comet(s, time=2700, through_middle=True, break_at=0.45),
        'prism': lambda s: start_prism(s, time=4800),
        'giant': lambda s: start_giant(s, time=5100),
    }
    for name in names:
        if name not in starts:
            continue
        s = Sim(17)
        length = starts[name](s)
        moments = moments_for(name, s, length)
        frames, caps = [], []
        for t in moments:
            s.run_until(t)
            frames.append(R.draw(s, t, planet=s.planet))
            caps.append(secs(t))
        if name == 'shower':  # two seconds at the peak piled up: every trail points back to the radiant, off to the side
            s.run_until(2120)
            frames.append(np.max([R.draw(s, t) for t in range(2100, 2121, 2)], axis=0))
            caps.append('3:30-3:32, two seconds piled up')
        strip(frames, caps, os.path.join(OUT, 'sky2_event_%s.png' % name))


def preview_flybys(R):
    """Before and after, each fly-by at the same place: the old sprites (sky_flyby.dmi) on top, the new ones under them."""
    rows = []
    for era in ('old', 'new'):
        frames, caps = [], []
        # a meteor, a fireball (new only) and a comet, mid-crossing
        s = Sim(5)
        path = sky_path(205, 40, 400)
        if era == 'old':
            P = Piece(s, 'old_meteor', 0)
            P.alpha = 255
            P.transform = on_path(path, 0.45, -arctan(path[2], path[3]), 45)
        else:
            send_meteor(s, 'meteor', path, 10)
            send_meteor(s, 'bolide', sky_path(160, -120, 400), 20)
        frames.append(R.draw(s, 4.5))
        caps.append('%s: shooting star%s' % (era, '' if era == 'old' else ', and a fireball'))
        s = Sim(6)
        path = sky_path(20, -60, 400)
        sun = s.places['sun']
        if era == 'old':
            P = Piece(s, 'old_comet', 0)
            P.alpha = 230
            P.transform = on_path(path, 0.5, -arctan(path[2], path[3]), 48)  # the old comet's tail trailed its motion
        else:
            toward = arctan(sun[0] - path[0], sun[1] - path[1])
            flip = 1 if (path[2] * -sin(toward) + path[3] * cos(toward)) > 0 else -1
            P = Piece(s, 'comet', 0)
            P.alpha = 235
            P.transform = on_path(path, 0.5, -toward, COMET_LEAD, 1, flip)
        frames.append(R.draw(s, 0))
        caps.append('%s: comet%s' % (era, '' if era == 'old' else ' (tails away from the sun, upper left)'))
        s = Sim(7)
        for state, x, y, h in ((('old_ship', -60, 40, 340), ('old_ship', 80, -60, 200)) if era == 'old' else (('ship', -60, 40, 340), ('convoy', 80, -60, 200))):
            P = Piece(s, state, 0)
            P.alpha = 225
            P.transform = sky_at(x, y, h)
        frames.append(R.draw(s, 0))
        caps.append('%s: ship%s' % (era, '' if era == 'old' else ', convoy'))
        rows.append((frames, caps))
    W = VIEW * 2
    out = Image.new('RGB', (W * 3 + 16, (W + 30) * 2), (18, 18, 20))
    draw = ImageDraw.Draw(out)
    for r, (frames, caps) in enumerate(rows):
        for i, (arr, cap) in enumerate(zip(frames, caps)):
            im = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), 'RGB').resize((W, W), Image.NEAREST)
            out.paste(im, (i * (W + 8), r * (W + 30) + 30))
            draw.text((i * (W + 8) + 8, r * (W + 30) + 8), cap, fill=(220, 220, 220))
    out.save(os.path.join(OUT, 'sky2_flybys.png'))
    print('data/previews/sky2_flybys.png')
    # up close at four times: the new ship, convoy and comet
    s = Sim(7)
    for state, x, y, h in (('ship', -60, 40, 340), ('convoy', 80, -60, 200)):
        P = Piece(s, state, 0)
        P.alpha = 225
        P.transform = sky_at(x, y, h)
    img = R.draw(s, 0)
    crops = [img[VIEW // 2 - 40 - 30:VIEW // 2 - 40 + 30, VIEW // 2 - 60 - 60:VIEW // 2 - 60 + 60],
             img[VIEW // 2 + 60 - 30:VIEW // 2 + 60 + 30, VIEW // 2 + 80 - 60:VIEW // 2 + 80 + 60]]
    tiles = [Image.fromarray((c * 255).astype(np.uint8)).resize((c.shape[1] * 4, c.shape[0] * 4), Image.NEAREST) for c in crops]
    out = Image.new('RGB', (sum(t.width for t in tiles) + 8, max(t.height for t in tiles)), (18, 18, 20))
    x = 0
    for t in tiles:
        out.paste(t, (x, 0))
        x += t.width + 8
    out.save(os.path.join(OUT, 'sky2_flyby_close.png'))
    print('data/previews/sky2_flyby_close.png')


def preview_dust(R):
    """The near dust over the sky, old and new, and the new one's lit specks glinting (theme colour), a slide apart."""
    tiles = dust.build_tiles()
    starlight = hexrgb('#f08a6c')  # Ember Reach's starlight
    grit = np.asarray(tiles['dust'].convert('RGB'), dtype=float) / 255
    base = R.background
    frames = [np.clip(base + R.old_dust * 170 / 255, 0, 1)]
    caps = ['old dust']
    for f, label in ((0, 'new: grit + lit specks'), (1, 'a glint (one short frame)'), (4, 'another glint')):
        lit = np.asarray(tiles['dust_lit'][f].convert('RGB'), dtype=float) / 255
        frames.append(np.clip(base + grit + lit * starlight, 0, 1))
        caps.append(label)
    strip(frames, caps, os.path.join(OUT, 'sky2_dust.png'))
    lit = np.asarray(tiles['dust_lit'][1].convert('RGB'), dtype=float) / 255 * starlight
    view = np.clip(base + grit + lit, 0, 1)[120:360, 0:320]  # a corner of the view at three times, as a player sees it
    Image.fromarray((view * 255).astype(np.uint8)).resize((960, 720), Image.NEAREST).save(os.path.join(OUT, 'sky2_dust_close.png'))
    print('data/previews/sky2_dust_close.png')


def main(names):
    os.makedirs(OUT, exist_ok=True)
    R = Renderer()
    names = names or ['flybys', 'dust', 'vortex', 'shower', 'supernova', 'battle', 'aurora', 'breakup', 'prism', 'giant']
    if 'flybys' in names:
        preview_flybys(R)
    if 'dust' in names:
        preview_dust(R)
    preview_events(R, names)
