"""Twinkle art for the v2 sky: twinkle1-3 in sky.dmi, made to sit on stars.py's stars_near stars.

    python tools/sky_gen/v2/twinkle.py preview          data/previews/sky2_twinkle_*.png (frames at the faint and full
                                                        alpha of the game's fade, zooms, old vs new)
    python tools/sky_gen/v2/twinkle.py stage [DIR]      DIR/sky.dmi (default data/sky_twinkle_stage): the installed sky.dmi
                                                        with only twinkle1-3 replaced; every other state copied pixel for
                                                        pixel and checked
    python tools/sky_gen/v2/twinkle.py check A B        compares two sky.dmi files state by state (exit 1 if any state
                                                        other than twinkle1-3 differs)

How the game uses it (sky.dm twinkle_art, parallax.dm stars/near/set_quality): each group is an additive sky_art in the
near layer's vis_contents, tinted theme.star_tint, fading alpha 255 -> 45 -> 255 with a half period of 9 + 4 * group
deciseconds (1.3, 1.7, 2.1 s). The steady stars are in stars_near, which build_v2.py takes from stars.py and is not
touched here. So a twinkle state holds only the extra light a twinkling star gains at the top of its fade: a share of
its own flux in its own blackbody colour, centred on the very pixel stars.py drew it on.

The look ("painterly-real", subtle):
- Only the light round the core swells; the core itself is already rolled off near white, so a twinkle there would
  clip. The extra is a slightly wider core (1.5x sigma) plus the star's own faint glow and, on the brightest, its
  diffraction spikes flaring a little longer.
- Scintillation is chromatic: each twinkling star's extra light is shifted a little in temperature (hot stars flash
  bluer, cool ones redder), so the star shimmers in hue as well as brightness, faintly.
- 7 of the tile's near stars twinkle, spread over the three groups; the rest stay steady. Strength at full alpha is
  about a quarter of the star's flux; the game's faint end (alpha 45) leaves about 4%.

The near stars are replayed from stars.star_field's own random draws (same seed, same order), so their places and
colours are stars.py's exactly; stage checks that the replayed stars_near matches the installed one.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import sky_gen as sg  # noqa: E402
import stars  # noqa: E402
from dmi import Dmi  # noqa: E402

ROOT = sg.ROOT
TILE = sg.TILE
SKY_DMI = os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'sky.dmi')
STAGE = os.path.join(ROOT, 'data', 'sky_twinkle_stage')
PREVIEW = os.path.join(ROOT, 'data', 'previews')
GROUPS = 3
TWINKLERS = 7           # how many near stars twinkle
STRENGTH = 0.26         # extra light at full alpha, share of the star's flux
TEMP_SHIFT = 0.10       # chromatic scintillation: the extra light's temperature is the star's x (1 +- this)
FADE = (45, 255)        # sky_art/twinkle(): alpha range
NEAR_SEED = 401         # stars.build_layers(): stars_near is the first layer, seed 401 + 0
NEAR_STATE_SEED = 804   # build_v2.py: 801 + i over deep, far, mid, near: the dither seed of stars_near


def near_stars():
    """[(x, y, temperature K, rgb, flux)] for stars_near, replaying stars.star_field's random draws in order."""
    m0, m1 = stars.LAYERS['stars_near']
    n = TILE
    rng = np.random.default_rng(NEAR_SEED)
    count = stars.count_between(m0, m1, stars.SKY_FRACTION)
    clump = sg.spectral(n, 3.0, NEAR_SEED + 500, 1, 8)
    xs, ys = stars.place(rng, count, 0.75 + 0.25 * clump, n)
    mags = stars.magnitudes(rng, m0, m1, count)
    f = stars.flux(mags) * 2.2 * stars.EXPOSURE
    temps = stars.temperatures(rng, count, np.clip((3.0 - mags) / 4, 0, 1))
    rgb = stars.saturate(stars.blackbody(temps), np.interp(mags, [1.0, 4.0, 6.5], [1.15, 0.8, 0.25]))
    return [(x, y, t, c, fl, m) for x, y, t, c, fl, m in zip(xs, ys, temps, rgb, f, mags)]


def twinkle_patch(canvas, x, y, rgb, f):
    """The extra light of one star at the top of its twinkle: wider core, its glow, its spikes a little longer."""
    n = canvas.shape[0]
    sigma = 0.45 * (1.0 + 0.5 * np.log2(max(f, 1.0))) * 1.5
    reach = int(np.ceil(max(3 * sigma, 7 + 2 * np.log2(max(f, 1.0)))))
    d = np.arange(-reach, reach + 1)
    dy, dx = np.meshgrid(d, d, indexing='ij')
    r = np.hypot(dx, dy)
    core = np.exp(-r * r / (2 * sigma * sigma))
    core *= 0.75 / core.sum()
    glow = np.exp(-r / 3.0)
    glow *= 0.25 / glow.sum()
    patch = (core + glow) * f * STRENGTH
    if f > 4:
        spike = 0.025 * np.log2(f) * (np.exp(-np.abs(dx) / 7.0) * (dy == 0) + np.exp(-np.abs(dy) / 7.0) * (dx == 0))
        patch = patch + spike * 0.6
    np.add.at(canvas, ((int(y) + dy) % n, (int(x) + dx) % n), patch[..., None] * rgb[None, None, :])


def build_twinkles(seed=55):
    """{'twinkle1'..'twinkle3': float RGB}, and the picks [(star index, group)]."""
    near = near_stars()
    rng = np.random.default_rng(seed)
    order = sorted(range(len(near)), key=lambda i: -near[i][4])
    # all but the very brightest few twinkle candidates; skip none by size, pick at random
    picks = sorted(rng.choice(len(near), size=min(TWINKLERS, len(near)), replace=False).tolist())
    groups = {i: 1 + k % GROUPS for k, i in enumerate(sorted(picks, key=lambda i: order.index(i)))}
    out = {}
    for g in range(1, GROUPS + 1):
        canvas = np.zeros((TILE, TILE, 3))
        for i, gi in groups.items():
            if gi != g:
                continue
            x, y, t, c, fl, m = near[i]
            shift = 1.0 + TEMP_SHIFT * (1 if rng.uniform() < 0.5 + 0.3 * np.tanh((t - 6000) / 3000) else -1)
            tc = stars.saturate(stars.blackbody(np.array([t * shift])), np.array([1.15]))[0]
            twinkle_patch(canvas, x, y, 0.5 * (c + tc), fl)
        out['twinkle%d' % g] = np.clip(canvas, 0, 1)
    return out, sorted(groups.items())


def as_image(rgb, g):
    return sg.additive_image(rgb, 810 + g)


def near_layer():
    return stars.roll_off(stars.star_field(NEAR_SEED, *stars.LAYERS['stars_near'])[0])


def states_of(path):
    d = Dmi.from_file(path)
    return d, {s.name: s for s in d.states}


def stage(out_dir=STAGE):
    """Writes out_dir/sky.dmi: the installed sheet with twinkle1-3 replaced. Returns the path."""
    old, old_states = states_of(SKY_DMI)
    near_now = np.asarray(old_states['stars_near'].frames[0], np.uint8)
    near_replay = np.asarray(sg.additive_image(near_layer(), NEAR_STATE_SEED), np.uint8)
    if not np.array_equal(near_now, near_replay):
        print('WARNING: installed stars_near is not stars.py seed %d; twinkles may not sit on its stars' % NEAR_SEED)
    tw, picks = build_twinkles()
    new = Dmi(old.width, old.height)
    for s in old.states:
        st = new.state(s.name, loop=s.loop, rewind=s.rewind, movement=s.movement, dirs=s.dirs)
        if s.name in tw:
            st.frame(as_image(tw[s.name], int(s.name[-1])))
        else:
            delays = s.delays or [1] * len(s.frames)  # dmi.py leaves delays empty for single-frame states
            for frame, delay in zip(s.frames, delays):
                st.frame(frame, delay=delay)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, 'sky.dmi')
    new.to_file(path)
    print('twinkling (star index, group):', picks)
    return path


def check(a, b):
    """Prints each state's change between two sheets; returns the names of changed states."""
    _, sa = states_of(a)
    _, sb = states_of(b)
    changed = []
    for name in sorted(set(sa) | set(sb)):
        if name not in sa or name not in sb:
            print('%-12s only in %s' % (name, 'A' if name in sa else 'B'))
            changed.append(name)
            continue
        x, y = sa[name], sb[name]
        same = (len(x.frames) == len(y.frames) and x.delays == y.delays and x.dirs == y.dirs
                and all(np.array_equal(np.asarray(p), np.asarray(q)) for p, q in zip(x.frames, y.frames)))
        print('%-12s %s' % (name, 'same pixels' if same else 'CHANGED'))
        if not same:
            changed.append(name)
    return changed


def frame_at(tw, alpha):
    """The near layer with every group at one alpha of the fade, as the game adds them (float RGB)."""
    base = np.asarray(sg.additive_image(near_layer(), NEAR_STATE_SEED), float)[..., :3] / 255
    add = sum(np.asarray(as_image(tw['twinkle%d' % g], g), float)[..., :3] / 255 for g in range(1, GROUPS + 1))
    return np.clip(base + add * alpha / 255.0, 0, 1)


def preview():
    os.makedirs(PREVIEW, exist_ok=True)
    tw, picks = build_twinkles()
    near = near_stars()
    for alpha in FADE:
        img = Image.fromarray((frame_at(tw, alpha) * 255).astype(np.uint8))
        img.save(os.path.join(PREVIEW, 'sky2_twinkle_a%d.png' % alpha))
    # zooms of each twinkling star, faint | full, 6x nearest
    lo, hi = frame_at(tw, FADE[0]), frame_at(tw, FADE[1])
    tiles = []
    for i, g in picks:
        x, y = int(near[i][0]), int(near[i][1])
        rows = [(y + k) % TILE for k in range(-12, 13)]
        cols = [(x + k) % TILE for k in range(-12, 13)]
        pair = np.concatenate([lo[np.ix_(rows, cols)], np.zeros((25, 2, 3)), hi[np.ix_(rows, cols)]], axis=1)
        tiles.append(Image.fromarray((pair * 255).astype(np.uint8)).resize((52 * 6, 25 * 6), Image.NEAREST))
    sheet = Image.new('RGB', (52 * 6, 25 * 6 * len(tiles) + 4 * len(tiles)), (40, 40, 40))
    for k, t in enumerate(tiles):
        sheet.paste(t, (0, k * (25 * 6 + 4)))
    sheet.save(os.path.join(PREVIEW, 'sky2_twinkle_zoom.png'))
    # old art over the v2 near stars at full alpha: where the old twinkles land
    _, old_states = states_of(SKY_DMI)
    base = np.asarray(sg.additive_image(near_layer(), NEAR_STATE_SEED), float)[..., :3] / 255
    old = base + sum(np.asarray(old_states['twinkle%d' % g].frames[0], float)[..., :3] / 255 for g in range(1, GROUPS + 1))
    Image.fromarray((np.clip(old, 0, 1) * 255).astype(np.uint8)).save(os.path.join(PREVIEW, 'sky2_twinkle_old_a255.png'))
    for g in range(1, GROUPS + 1):
        as_image(tw['twinkle%d' % g], g).convert('RGB').save(os.path.join(PREVIEW, 'sky2_twinkle_state%d.png' % g))
    print('twinkling (star index, group):', picks)
    print(PREVIEW)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    if mode == 'preview':
        preview()
    elif mode == 'stage':
        print(stage(sys.argv[2] if len(sys.argv) > 2 else STAGE))
    elif mode == 'check' and len(sys.argv) == 4:
        changed = check(sys.argv[2], sys.argv[3])
        sys.exit(1 if set(changed) - {'twinkle1', 'twinkle2', 'twinkle3'} else 0)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == '__main__':
    main()
