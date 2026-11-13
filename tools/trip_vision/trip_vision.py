#!/usr/bin/env python3
"""Builds the art for a trip's vision (hippiestation/code/modules/trip_vision/trip_vision.dm): the flowing warp, and Grape
Blast's fractal, which is kishimisu's shader art intro (shadertoy.com/view/mtyGWy) drawn with BYOND filters.

    python tools/trip_vision/trip_vision.py build             writes hippiestation/icons/effects/trip_vision.dmi (the table)
                                                              and the maps, hippiestation/icons/effects/trip/*.png
    python tools/trip_vision/trip_vision.py preview [t]       writes data/previews/grape_fractal_{shader,byond,diff}.png
                                                              at t seconds: the shader itself, what the client should
                                                              draw, and the difference between them
    python tools/trip_vision/trip_vision.py check             fails if the committed sheet differs from what this builds

"wedge" is the kaleidoscope's mask: an eighth of the view, from straight right to 45 degrees up, a little wider each side so the
eight copies leave no seam. "disc" is the tunnel's mask: the view, fading out towards its edge. "bulge" is the fisheye's
displacement map: each pixel reads from nearer the middle, most at half way out, so the middle swells (or with a negative
size, shrinks).

Every map a filter uses is a PNG of its own, compiled into the game's resources: a filter given icon(file, state) gets a new
resource made on the spot, which a client that hasn't fetched it yet draws as nothing, and a plane master drawn through a filter
like that stays blank till its filters are set again (measured). The table, which a screen object shows, stays in the .dmi.

flow1.png and flow2.png are displacement maps of slow noise that repeats every VIEW pixels both ways, two by two so a
map can slide a whole repeat and still cover the screen. The picture is displaced by both, each sliding its own way (the filter's
map offset): everything breathes and swims together. They're maps of their own, not a plane the picture reads: a filter that reads
another plane's render target, made before that target is ready, left the whole picture blank (measured).

The fractal:

BYOND has no shaders, but each of the shader's four layers only moves in two ways over time: the rings' phase (sin(d*8 + t))
and the colour (palette(length + i*0.4 + t*0.4)). Everything else about a pixel never changes. So:
- "lut" is a table of glow x colour. Across, one ring period (pi of phase) every LUT_P pixels; up, one turn of the palette
  every LUT_Q pixels. It's scrolled on a hidden plane, so time is the scroll.
- "map1".."map4" are displacement maps, one per layer. Each pixel of the screen reads the scrolled table at the spot that
  holds its own phase and colour. A displace filter reads its map pixel for pixel, red across and green down the image,
  an offset of (value - 128) / 127 * size (measured on 516.1688 with a real client). The offset always points towards the
  middle of the screen, so it never reads off the edge of the plane.
The table is clamped to 1, and so is the sum of the layers, which gives the same picture as clamping the shader's sum.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'mapmerge2'))
from dmi import Dmi  # noqa: E402

VIEW = 480  # the 15x15 view, the only one it's drawn for
LUT_P = 96  # table pixels per ring period, across. Divides VIEW, so the table tiles with no seam
LUT_Q = 96  # table pixels per turn of the palette, up
SIZE = 96  # the displace filters' size: the furthest a pixel reads. Must cover a whole period
LAYERS = 4
# The scroll loops every 4 pi seconds: four ring periods and five palette turns. The palette moves at 5 / (4 pi) = 0.398 turns a
# second instead of the shader's 0.4, so the loop has no seam
LOOP_RINGS = 4
LOOP_TURNS = 5
PALETTE_SPEED = LOOP_TURNS / (LOOP_RINGS * np.pi)
OUT = os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'trip_vision.dmi')
MAPS_OUT = os.path.join(ROOT, 'hippiestation', 'icons', 'effects', 'trip')
FLOW_SEED = 1112


def palette(t):
    d = np.array([0.263, 0.416, 0.557])
    return 0.5 + 0.5 * np.cos(6.28318 * (t[..., None] + d))


def glow(phase):
    return np.power(0.01 / (np.abs(np.sin(phase)) / 8.0), 1.2)


def centres(n):
    """Pixel centres of an n x n view, y up, image rows top first."""
    x = np.arange(n) + 0.5
    y = (n - 0.5) - np.arange(n)
    return np.meshgrid(x, y)


def fract(x):
    return x - np.floor(x)


# The fractal's variations: the shader's own numbers first, then others of the same family. scale: how much each layer zooms
# into the last (the shader's 1.5); rings: ring frequency (8); falloff: how fast the rings spread from the middle (1);
# fold: folded into that many mirrored wedges before anything else (0 for none); twist: degrees each layer turns;
# colours: how fast the palette runs outwards (1).
VARIATIONS = [
    dict(scale=1.5, rings=8.0, falloff=1.0, fold=0, twist=0.0, colours=1.0),   # the shader itself
    dict(scale=1.3, rings=11.0, falloff=0.6, fold=0, twist=0.0, colours=1.3),  # a finer lattice
    dict(scale=1.6, rings=7.0, falloff=1.2, fold=6, twist=0.0, colours=1.0),   # six-pointed stars
    dict(scale=1.8, rings=6.0, falloff=0.8, fold=0, twist=20.0, colours=0.8),  # each layer twisted on the last
    dict(scale=1.4, rings=9.0, falloff=1.5, fold=8, twist=10.0, colours=1.5),  # an eight-fold mandala
]


def layer_fields(n=VIEW, variation=0):
    """Per layer: the rings' phase without time, and the palette's input without time, at each pixel."""
    k = VARIATIONS[variation]
    cx, cy = centres(n)
    u0 = (cx * 2 - n) / n
    v0 = (cy * 2 - n) / n
    r0 = np.hypot(u0, v0)
    u, v = u0, v0
    if k['fold']:
        wedge = 2 * np.pi / k['fold']
        a = np.mod(np.arctan2(v0, u0), wedge)
        a = np.abs(a - wedge / 2)
        u, v = r0 * np.cos(a), r0 * np.sin(a)
    out = []
    for i in range(LAYERS):
        if k['twist']:
            t = np.radians(k['twist'])
            u, v = u * np.cos(t) - v * np.sin(t), u * np.sin(t) + v * np.cos(t)
        u = fract(u * k['scale']) - 0.5
        v = fract(v * k['scale']) - 0.5
        phase = np.hypot(u, v) * np.exp(-r0 * k['falloff']) * k['rings']
        out.append((phase, r0 * k['colours'] + i * 0.4))
    return out


def shader(t, palette_speed=0.4, n=VIEW):
    """The shader itself at t seconds, clamped as the screen would."""
    total = np.zeros((n, n, 3))
    for phase, colour_in in layer_fields(n):
        total += palette(colour_in + t * palette_speed) * glow(phase + t)[..., None]
    return np.clip(total, 0, 1)


def lut_image():
    """The table, y up: glow across, palette up, clamped."""
    x = np.arange(VIEW) + 0.5
    y = (VIEW - 0.5) - np.arange(VIEW)
    gx, gy = np.meshgrid(x, y)
    value = palette(gy / LUT_Q) * glow(gx / LUT_P * np.pi)[..., None]
    return np.clip(value, 0, 1)


def map_offsets(phase, colour_in):
    """Each pixel's offset (y up) to the table spot that holds its phase and colour, pointing towards the middle."""
    cx, cy = centres(VIEW)
    want_x = phase / np.pi * LUT_P
    want_y = colour_in * LUT_Q
    rx = np.mod(want_x - cx, LUT_P)
    ry = np.mod(want_y - cy, LUT_Q)
    rx = np.where(cx < VIEW / 2, rx, rx - LUT_P)
    ry = np.where(cy < VIEW / 2, ry, ry - LUT_Q)
    return rx, ry


def encode(rx, ry):
    """Offsets to map colours: red across, green down the image (so up is below 128)."""
    red = np.clip(np.round(128 + rx * 127 / SIZE), 0, 255)
    green = np.clip(np.round(128 - ry * 127 / SIZE), 0, 255)
    return red.astype(np.uint8), green.astype(np.uint8)


def decode(red, green):
    return (red.astype(float) - 128) * SIZE / 127, -(green.astype(float) - 128) * SIZE / 127


def to_image(rgb):
    alpha = np.full(rgb.shape[:2] + (1,), 255, np.uint8)
    return Image.fromarray(np.concatenate([np.round(rgb * 255).astype(np.uint8), alpha], 2), 'RGBA')


def flow_field(seed):
    """Smooth noise in -1..1 that repeats every VIEW pixels both ways: a few waves of 1 to 3 cycles across the tile."""
    rng = np.random.default_rng(seed)
    x = np.arange(VIEW) + 0.5
    gx, gy = np.meshgrid(x, x)
    field = np.zeros((VIEW, VIEW))
    for fx in range(-3, 4):
        for fy in range(0, 4):
            if (fy == 0 and fx <= 0) or fx * fx + fy * fy > 10:
                continue
            amp = rng.normal() / (fx * fx + fy * fy) ** 0.75
            field += amp * np.sin(2 * np.pi * (fx * gx + fy * gy) / VIEW + rng.uniform(0, 2 * np.pi))
    return field / np.abs(field).max()


def flow_image(seed=FLOW_SEED, tiles=1):
    rgba = np.zeros((VIEW, VIEW, 4), np.uint8)
    rgba[..., 0] = np.round(128 + 127 * flow_field(seed))
    rgba[..., 1] = np.round(128 + 127 * flow_field(seed + 1))
    rgba[..., 3] = 255
    return Image.fromarray(np.tile(rgba, (tiles, tiles, 1)), 'RGBA')


def flow_states():
    return {'flow1': flow_image(FLOW_SEED, 2), 'flow2': flow_image(FLOW_SEED + 10, 2)}


def centred():
    """Pixel centres relative to the middle of the view, y up."""
    cx, cy = centres(VIEW)
    return cx - VIEW / 2, cy - VIEW / 2


def alpha_image(alpha):
    rgba = np.zeros((VIEW, VIEW, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(np.clip(alpha, 0, 1) * 255)
    return Image.fromarray(rgba, 'RGBA')


def wedge_image(degrees=45.0, spare=0.5):
    x, y = centred()
    lo = np.radians(-spare)
    hi = np.radians(degrees + spare)
    above_lo = y * np.cos(lo) - x * np.sin(lo)  # signed distance to the lower edge, positive inside
    below_hi = x * np.sin(hi) - y * np.cos(hi)  # and to the upper edge
    return alpha_image(np.minimum(above_lo, below_hi) + 0.5)


def disc_image(inner=170.0, outer=236.0):
    x, y = centred()
    t = np.clip((outer - np.hypot(x, y)) / (outer - inner), 0, 1)
    return alpha_image(t * t * (3 - 2 * t))


def bulge_image(reach=300.0):
    x, y = centred()
    r = np.hypot(x, y)
    pull = np.where(r < reach, np.sin(np.pi * np.minimum(r / reach, 1)), 0)  # how far towards the middle, most half way out
    with np.errstate(invalid='ignore', divide='ignore'):
        ux = np.where(r > 0, -x / r, 0)
        uy = np.where(r > 0, -y / r, 0)
    rgba = np.zeros((VIEW, VIEW, 4), np.uint8)
    rgba[..., 0] = np.round(128 + 127 * ux * pull)
    rgba[..., 1] = np.round(128 - 127 * uy * pull)  # green runs down the image
    rgba[..., 3] = 255
    return Image.fromarray(rgba, 'RGBA')


def states():
    out = {'lut': to_image(lut_image()), 'wedge': wedge_image(), 'disc': disc_image(),
           'bulge': bulge_image()}
    for variation in range(len(VARIATIONS)):
        add_maps(out, variation)
    return out


def add_maps(out, variation):
    for i, (phase, colour_in) in enumerate(layer_fields(variation=variation)):
        red, green = encode(*map_offsets(phase, colour_in))
        rgba = np.zeros((VIEW, VIEW, 4), np.uint8)
        rgba[..., 0] = red
        rgba[..., 1] = green
        rgba[..., 3] = 255
        out['v%dmap%d' % (variation + 1, i + 1)] = Image.fromarray(rgba, 'RGBA')
    return out


def maps():
    """Every filter map, by file name."""
    out = {name: image for name, image in states().items() if name != 'lut'}
    out.update(flow_states())
    return out


def write(path, maps_dir):
    dmi = Dmi(VIEW, VIEW)
    dmi.state('lut').frame(states()['lut'])
    dmi.to_file(path)
    os.makedirs(maps_dir, exist_ok=True)
    for name, image in maps().items():
        image.save(os.path.join(maps_dir, name + '.png'), optimize=True)


def bilinear(img, x, y, wrap=False):
    """img (row 0 at the top) sampled at continuous y-up coordinates, texel centres at k + 0.5. Outside it is transparent
    black, or with wrap it repeats."""
    h, w = img.shape[:2]
    fx = x - 0.5
    fy = (h - 0.5) - y  # to row space
    x0 = np.floor(fx).astype(int)
    y0 = np.floor(fy).astype(int)
    ax = (fx - x0)[..., None]
    ay = (fy - y0)[..., None]

    def at(yy, xx):
        if wrap:
            return img[yy % h, xx % w]
        inside = (xx >= 0) & (xx < w) & (yy >= 0) & (yy < h)
        return img[np.clip(yy, 0, h - 1), np.clip(xx, 0, w - 1)] * inside[..., None]
    return (at(y0, x0) * (1 - ax) * (1 - ay) + at(y0, x0 + 1) * ax * (1 - ay) + at(y0 + 1, x0) * (1 - ax) * ay +
            at(y0 + 1, x0 + 1) * ax * ay)


def byond(t):
    """What the client should draw at t seconds: the table scrolled on the plane, each layer read through its map, added."""
    sheet = states()
    lut = np.asarray(sheet['lut'], float)[..., :3] / 255
    sx = (t * LUT_P / np.pi) % VIEW
    sy = (t * PALETTE_SPEED * LUT_Q) % VIEW
    cx, cy = centres(VIEW)
    plane = bilinear(lut, cx + sx, cy + sy, wrap=True)  # the four table objects tile it 2 x 2, so it never runs out
    total = np.zeros((VIEW, VIEW, 3))
    for i in range(LAYERS):
        m = np.asarray(sheet['v1map%d' % (i + 1)])
        ox, oy = decode(m[..., 0], m[..., 1])
        total += bilinear(plane, cx + ox, cy + oy)
    return np.clip(total, 0, 1)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else 'build'
    if what == 'build':
        write(OUT, MAPS_OUT)
        total = sum(os.path.getsize(os.path.join(MAPS_OUT, f)) for f in os.listdir(MAPS_OUT))
        print('%s  %d KB; %d maps in %s, %d KB' % (os.path.relpath(OUT, ROOT), os.path.getsize(OUT) // 1024, len(os.listdir(MAPS_OUT)),
              os.path.relpath(MAPS_OUT, ROOT), total // 1024))
    elif what == 'check':
        old = Dmi.from_file(OUT)
        if np.asarray(old.states[0].frames[0]).tobytes() != np.asarray(states()['lut']).tobytes():
            print('trip_vision.dmi differs from the script: run build')
            sys.exit(1)
        for name, image in maps().items():
            path = os.path.join(MAPS_OUT, name + '.png')
            if not os.path.exists(path) or np.asarray(Image.open(path).convert('RGBA')).tobytes() != np.asarray(image.convert('RGBA')).tobytes():
                print('%s differs from the script: run build' % os.path.relpath(path, ROOT))
                sys.exit(1)
        print('trip_vision.dmi and the maps match')
    elif what == 'preview':
        t = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
        out = os.path.join(ROOT, 'data', 'previews')
        os.makedirs(out, exist_ok=True)
        want = shader(t, PALETTE_SPEED)
        got = byond(t)
        diff = np.abs(want - got)
        for name, img in (('shader', want), ('byond', got), ('diff', np.clip(diff * 4, 0, 1))):
            Image.fromarray(np.round(img * 255).astype(np.uint8), 'RGB').save(os.path.join(out, 'grape_fractal_%s.png' % name))
        print('t=%.2f  mean |diff| %.4f  99th %.4f  max %.4f' % (t, diff.mean(), np.percentile(diff, 99), diff.max()))
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
