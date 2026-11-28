"""How the light map looks between tile corners: a simulated lamp pool, drawn the way BYOND draws it.

Each turf's lighting object is one 32x32 picture whose four channels are its corners' weights, and its colour matrix
multiplies the four corner colours in (code/modules/lighting/lighting_object.dm draw()). Light is exact only at the
corners; in between it's whatever the weights make of it. This draws one lamp's pool on a 15x15 tile view, corners
sampled from lighting_v2_lamps.dm's falloff, with several weight shapes and blur sizes side by side, so a change to the
gradient sheet (icons/effects/lighting_object.dmi) or the light plane's blur (light_glow.dm) can be judged before the game.

  python tools/lighting_v2/gradient_sim.py [--out PATH] [--lamp 7.3,6.6] [--range 6] [--k 6]

Shapes: bilinear (the sheet now), hermite (smoothstep weights), mix (half of each).
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TILE = 32
VIEW = 15


def falloff(d, reach, k):
    """lighting_v2_lamps.dm light_v2_falloff(): 1 / (1 + K d^2), rescaled to 0 at reach"""
    d = np.minimum(d, reach)
    f = 1 / (1 + k * (d / reach) ** 2)
    end = 1 / (1 + k)
    return np.clip((f - end) / (1 - end), 0, 1)


def weights(shape):
    """The four corner weights over a tile, (SW, SE, NW, NE), each TILE x TILE, y up"""
    t = (np.arange(TILE) + 0.5) / TILE
    x, y = np.meshgrid(t, t[::-1])  # row 0 is the tile's top
    if shape == 'hermite':
        x, y = x * x * (3 - 2 * x), y * y * (3 - 2 * y)
    elif shape == 'mix':
        hx, hy = x * x * (3 - 2 * x), y * y * (3 - 2 * y)
        x, y = (x + hx) / 2, (y + hy) / 2
    return ((1 - x) * (1 - y), x * (1 - y), (1 - x) * y, x * y)


def light_map(lamp, reach, k, shape):
    cx = np.arange(VIEW + 1)
    gx, gy = np.meshgrid(cx, cx)
    corners = falloff(np.hypot(gx - lamp[0], gy - lamp[1]), reach, k)  # corner (i, j): x i, y j
    sw, se, nw, ne = weights(shape)
    out = np.zeros((VIEW * TILE, VIEW * TILE))
    for j in range(VIEW):
        for i in range(VIEW):
            tile = (sw * corners[j, i] + se * corners[j, i + 1] + nw * corners[j + 1, i] + ne * corners[j + 1, i + 1])
            out[(VIEW - 1 - j) * TILE:(VIEW - j) * TILE, i * TILE:(i + 1) * TILE] = tile
    return out


def picture(light, blur):
    floor = np.full_like(light, 0.62)  # a mid grey floor under the light (the light plane multiplies the scene)
    img = Image.fromarray(np.clip(floor * light * 255, 0, 255).astype(np.uint8))
    if blur:
        # BYOND's blur filter size is about two Gaussian sigmas: light_glow.dm's 1.5 px is a sigma of about 0.75
        img = img.filter(ImageFilter.GaussianBlur(blur / 2))
    return img.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'data', 'previews',
                                                  'lighting_v2', 'gradient_sim.png'))
    ap.add_argument('--lamp', default='7.3,6.6')
    ap.add_argument('--range', type=float, default=6)
    ap.add_argument('--k', type=float, default=6)
    args = ap.parse_args()
    lamp = tuple(float(v) for v in args.lamp.split(','))
    rows = []
    for shape in ('bilinear', 'mix', 'hermite'):
        rows.append([(shape, blur, picture(light_map(lamp, args.range, args.k, shape), blur)) for blur in (1.5, 3, 4.5)])
    size = VIEW * TILE
    sheet = Image.new('RGB', (size * 3 + 40, size * 3 + 80), (24, 24, 30))
    draw = ImageDraw.Draw(sheet)
    for r, row in enumerate(rows):
        for c, (shape, blur, img) in enumerate(row):
            x, y = 10 + c * (size + 10), 30 + r * (size + 15)
            sheet.paste(img, (x, y))
            draw.text((x + 4, y - 14), '%s, blur %g px' % (shape, blur), fill=(220, 220, 220))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    sheet.save(args.out)
    print(args.out)


if __name__ == '__main__':
    main()
