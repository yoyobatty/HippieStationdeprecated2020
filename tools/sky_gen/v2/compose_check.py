"""Composition check: where the round's sky puts its things, over many rounds, and what reads awkward.

    python tools/sky_gen/v2/compose_check.py [rule] [rounds]      rule: now (sky.dm today) or new (the proposed rules)

Ports SSparallax.set_theme()/pick_deep_sky() placement (hippiestation/code/_onclick/hud/sky.dm) and the planet's rest
(parallax.dm planet_rest), draws each round's 480 x 480 view (15 tiles) from the map's middle with the real sprites of
sky_bodies.dmi / sky_deep.dmi, and scores it:
  overlap   two things' bright cores touch (sun on the other world, a far nebula on the sun...)
  band_sun  the galaxy band runs through the sun's core
  band_deep a far thing sits on the band (lost in it)
  lopsided  everything on one side, the other half empty
  cut       a thing's core is mostly off screen (wasted)
Writes data/previews/sky2_compose_<rule>.png (a sheet of rounds, the worst first) and prints the counts.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(ROOT, 'data', 'previews')
VIEW = 480
HALF = VIEW / 2
PLANET_REST = 210


def cos(d):
    return math.cos(math.radians(d))


def sin(d):
    return math.sin(math.radians(d))


def arctan(x, y):
    return math.degrees(math.atan2(y, x))


def gap(a, b):
    return abs(((a - b) % 360 + 540) % 360 - 180)


def dmi_states(path):
    im = Image.open(path)
    desc = im.info['Description']
    w = int(desc.split('width = ')[1].split()[0])
    names = [line.split('"')[1] for line in desc.splitlines() if line.startswith('state')]
    frames = {}
    cur = None
    for line in desc.splitlines():
        if line.startswith('state'):
            cur = line.split('"')[1]
        elif cur and line.strip().startswith('frames'):
            frames[cur] = int(line.split('=')[1])
    arr = np.asarray(im.convert('RGBA')).astype(np.float32) / 255
    cols = arr.shape[1] // w
    out, i = {}, 0
    for n in names:
        out[n] = arr[(i // cols) * w:(i // cols + 1) * w, (i % cols) * w:(i % cols + 1) * w]
        i += frames.get(n, 1)
    return out


BODIES = dmi_states(os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'sky_bodies.dmi'))
DEEP = dmi_states(os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'sky_deep.dmi'))


def core_radius(tile, share=0.6):
    """Radius holding `share` of the sprite's light (alpha x brightness): what the eye reads as the thing."""
    w = tile.shape[0]
    light = tile[..., 3] * tile[..., :3].max(-1)
    yy, xx = np.mgrid[:w, :w]
    r = np.hypot(xx - w / 2 + 0.5, yy - w / 2 + 0.5).ravel()
    order = np.argsort(r)
    acc = np.cumsum(light.ravel()[order])
    if acc[-1] <= 0:
        return 0
    return float(r[order][np.searchsorted(acc, share * acc[-1])])


CORE = {n: core_radius(t) for n, t in list(BODIES.items()) + list(DEEP.items())}
DEEP_SIZES = {'nebula_ring': (70, 95), 'nebula_bipolar': (55, 80), 'nebula_remnant': (55, 80), 'quasar': (75, 100)}
THEMES = [  # name, neighbour, sun, band
    ('ember', 'world_redrock', True, False), ('glacier', 'world_ice', False, False), ('violet', 'world_rock', True, False),
    ('verdant', 'world_jungle', False, False), ('gold', None, True, True), ('rose', 'world_ocean', False, False),
    ('quiet', None, False, True)]


def place_now(rng, theme, band_everywhere):
    """sky.dm set_theme() as it is."""
    name, neighbour, has_sun, band = theme
    sun_b = rng.randint(0, 359)
    world_b = sun_b + rng.randint(110, 180)
    galaxy_b = world_b + rng.randint(70, 110)
    things = {}
    if has_sun:
        things['sun'] = (cos(sun_b) * 170, sin(sun_b) * 170, 'sun', 1.0)
    if neighbour:
        things['world'] = (cos(world_b) * 130, sin(world_b) * 130, neighbour, 1.0)
    taken = [sun_b, world_b, galaxy_b]
    kinds = list(DEEP_SIZES)
    for index in range(rng.choice([0, 1, 1, 1, 2, 2])):
        kind = kinds.pop(rng.randrange(len(kinds)))
        best, bearing = -1, 0
        for _ in range(24):
            maybe = rng.randint(0, 359)
            g = min([gap(maybe, o) for o in taken] + [180])
            if g > best:
                best, bearing = g, maybe
            if g >= 60:
                break
        taken.append(bearing)
        reach = rng.randint(75, 100) / 100
        lo, hi = DEEP_SIZES[kind]
        things['deep%d' % index] = (cos(bearing) * 210 * reach, sin(bearing) * 160 * reach, kind, rng.randint(lo, hi) / 100)
    away = sun_b + 180
    things['planet'] = (cos(away) * PLANET_REST, sin(away) * PLANET_REST, 'planet_lava', 1.0)
    # the band: angle 0 (band_angle never set), offset by a random nebula shift across its 960 px repeat
    band_line = None
    if band or band_everywhere:
        band_line = (0.0, rng.uniform(-480, 480))
    return things, band_line, sun_b


def band_dist(band_line, x, y):
    if not band_line:
        return 1e9
    angle, offset = band_line  # clockwise degrees, offset along its normal; repeats every 960 px
    nx, ny = -sin(-angle), cos(-angle)  # normal of a line turned clockwise by angle (y up)
    d = (x * nx + y * ny) - offset
    d = (d + 480) % 960 - 480
    return abs(d)


def score(things, band_line):
    issues = []
    names = list(things)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if 'planet' in (a, b) and not ({'sun', 'world'} & {a, b}):
                continue  # Lavaland is drawn over the far things: passing in front is fine; beside the sun or the world is a clutter
            xa, ya, sa, ka = things[a]
            xb, yb, sb, kb = things[b]
            ra, rb = CORE[sa] * ka, CORE[sb] * kb
            if math.hypot(xa - xb, ya - yb) < (ra + rb) * (1.6 if 'planet' in (a, b) else 0.8):
                issues.append('overlap %s/%s' % (a, b))
    if band_line:
        if 'sun' in things and band_dist(band_line, *things['sun'][:2]) < 60:
            issues.append('band_sun')
        for n, (x, y, s, k) in things.items():
            if n.startswith('deep') and band_dist(band_line, x, y) < 70:
                issues.append('band_deep')
    weights = [(x, y, CORE[s] * k) for n, (x, y, s, k) in things.items() if n != 'planet']
    if len(weights) >= 2:
        cx = sum(x * w for x, y, w in weights) / sum(w for *_, w in weights)
        cy = sum(y * w for x, y, w in weights) / sum(w for *_, w in weights)
        if math.hypot(cx, cy) > 120:
            issues.append('lopsided')
    for n, (x, y, s, k) in things.items():
        if n == 'planet':
            continue
        r = max(CORE[s] * k, 1)
        inside = (min(HALF, x + r) - max(-HALF, x - r)) * (min(HALF, y + r) - max(-HALF, y - r)) / (4 * r * r)
        if inside < 0.4:
            issues.append('cut %s' % n)
    return issues


def draw(things, band_line, label, issues):
    img = np.zeros((VIEW, VIEW, 3), np.float32)
    rng = np.random.default_rng(len(label))
    sx, sy = rng.integers(0, VIEW, 500), rng.integers(0, VIEW, 500)
    img[sy, sx] = rng.uniform(0.1, 0.6, (500, 1))
    if band_line:
        yy, xx = np.mgrid[:VIEW, :VIEW]
        d = np.vectorize(lambda x, y: band_dist(band_line, x, y))(xx - HALF, HALF - yy)
        img += (np.exp(-(d / 70) ** 2) * 0.25)[..., None] * np.array([1, 0.9, 0.75])
    order = sorted(things, key=lambda n: {'sun': 1, 'planet': 9, 'world': 5}.get(n, 2))
    for n in order:
        x, y, state, k = things[n]
        tile = (BODIES.get(state) if state in BODIES else DEEP[state])
        size = max(1, int(tile.shape[0] * k))
        spr = np.asarray(Image.fromarray((tile * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR)).astype(np.float32) / 255
        x0, y0 = int(HALF + x - size / 2), int(HALF - y - size / 2)
        ax0, ay0, ax1, ay1 = max(0, x0), max(0, y0), min(VIEW, x0 + size), min(VIEW, y0 + size)
        if ax1 <= ax0 or ay1 <= ay0:
            continue
        part = spr[ay0 - y0:ay1 - y0, ax0 - x0:ax1 - x0]
        a = part[..., 3:4]
        if state.startswith('world') or state.startswith('planet'):
            img[ay0:ay1, ax0:ax1] = img[ay0:ay1, ax0:ax1] * (1 - a) + part[..., :3] * a
        else:
            img[ay0:ay1, ax0:ax1] += part[..., :3] * a
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(out)
    d.text((6, 4), label, fill=(255, 255, 255))
    for i, s in enumerate(issues[:5]):
        d.text((6, 18 + 12 * i), s, fill=(255, 110, 110))
    return out


def main():
    rule = sys.argv[1] if len(sys.argv) > 1 else 'now'
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    placer = {'now': place_now}[rule] if rule == 'now' else __import__('compose_rules').place_new
    rng = random.Random(1)
    counts, sample = {}, []
    for r in range(rounds):
        theme = THEMES[r % len(THEMES)]
        things, band_line, sun_b = placer(rng, theme, True)
        issues = score(things, band_line)
        for s in {i.split()[0] for i in issues}:
            counts[s] = counts.get(s, 0) + 1
        sample.append((len(issues), r, theme[0], things, band_line, issues))
    print('rule %s, %d rounds (band on every theme): %d with an issue' % (rule, rounds, sum(1 for s in sample if s[0])))
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
        print('  %-10s %5.1f%%' % (k, 100 * v / rounds))
    sample.sort(key=lambda s: (-s[0], s[1]))
    picks = sample[:8] + sample[len(sample) // 2:len(sample) // 2 + 4] + sample[-4:]
    sheet = Image.new('RGB', (VIEW * 4 // 2, VIEW * 4 // 2))
    for i, (_, r, tname, things, band_line, issues) in enumerate(picks):
        tile = draw(things, band_line, '#%d %s' % (r, tname), issues).resize((VIEW // 2, VIEW // 2), Image.BILINEAR)
        sheet.paste(tile, ((i % 4) * VIEW // 2, (i // 4) * VIEW // 2))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, 'sky2_compose_%s.png' % rule)
    sheet.save(path)
    print(path)


if __name__ == '__main__':
    main()
