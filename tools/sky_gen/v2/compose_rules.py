"""The proposed placement rules for compose_check.py, kept in step with sky.dm's set_theme()/pick_deep_sky() once ported.

Lavaland rests opposite the sun (parallax.dm planet_rest). The other world goes to the sun's side, never toward Lavaland. The
galaxy band crosses the view at a slant, near the middle, missing the sun. Far things go where the sky is emptiest: off the
band, clear of every core by distance (not by bearing), and to the lighter side so the view balances.
"""
import math

from compose_check import CORE, DEEP_SIZES, HALF, PLANET_REST, cos, sin, band_dist

DEEP_SIZES_NEW = {'nebula_ring': (70, 95), 'nebula_bipolar': (55, 75), 'nebula_remnant': (40, 55), 'quasar': (70, 90)}


def place_new(rng, theme, band_everywhere):
    name, neighbour, has_sun, band = theme
    sun_b = rng.randint(0, 359)
    things = {}
    if has_sun:
        things['sun'] = (cos(sun_b) * 170, sin(sun_b) * 170, 'sun', 1.0)
    away = sun_b + 180
    things['planet'] = (cos(away) * PLANET_REST, sin(away) * PLANET_REST, 'planet_lava', 1.0)
    if neighbour:
        world_b = sun_b + rng.choice([-1, 1]) * rng.randint(70, 115)
        things['world'] = (cos(world_b) * 140, sin(world_b) * 140, neighbour, 1.0)
    band_line = None
    if band or band_everywhere:
        # a slant, never flat or upright; passes within 90 px of the middle; misses the sun's core
        for _ in range(40):
            angle = rng.choice([-1, 1]) * rng.randint(20, 70)
            offset = rng.uniform(-90, 90)
            band_line = (angle, offset)
            if 'sun' not in things or band_dist(band_line, *things['sun'][:2]) >= 110:
                break
    kinds = list(DEEP_SIZES_NEW)
    for index in range(rng.choice([0, 1, 1, 1, 2, 2])):
        kind = kinds.pop(rng.randrange(len(kinds)))
        lo, hi = DEEP_SIZES_NEW[kind]
        size = rng.randint(lo, hi) / 100
        r = CORE[kind] * size
        best, spot = -1e9, None
        for _ in range(60):
            b = rng.uniform(0, 360)
            reach = rng.uniform(0.55, 1.0)
            x, y = cos(b) * 200 * reach, sin(b) * 170 * reach
            clear = min([math.hypot(x - tx, y - ty) - r - CORE[ts] * tk for tx, ty, ts, tk in things.values()] + [999])
            clear = min(clear, (band_dist(band_line, x, y) - 80) * 2) if band_line else clear
            # lean to the emptier side: away from what's already up there (Lavaland aside)
            mass = [(tx, ty, CORE[ts] * tk) for n, (tx, ty, ts, tk) in things.items() if n != 'planet']
            if mass:
                cx = sum(a * w for a, _, w in mass) / sum(w for *_, w in mass)
                cy = sum(b_ * w for _, b_, w in mass) / sum(w for *_, w in mass)
                clear -= 0.15 * max(0, (x * cx + y * cy) / max(1, math.hypot(cx, cy)))
            # keep most of its core on screen
            clear = min(clear, (HALF - max(abs(x), abs(y)) - r * 0.4) * 2)
            if clear > best:
                best, spot = clear, (x, y)
        things['deep%d' % index] = (spot[0], spot[1], kind, size)
    return things, band_line, sun_b
