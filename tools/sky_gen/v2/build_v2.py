"""Sky v2 build: sky_gen's sheets with the v2 stars, galaxy band, nebulae and bodies put in.

    python tools/sky_gen/v2/build_v2.py [out_dir] [--scale 1|2]   default: data/sky_v2_stage (look first), --scale 1;
                                                                  the game's sheets live in hippiestation/icons/effects
                                                                  (pass that to install)

Art scale (2026-11-27): --scale 2 makes the stars, twinkles, band, the theme clouds and the bodies at twice the game's pixels
(the clouds at the game's pixels: they used to be drawn at twice size) for the game to draw at half size. It doesn't make the
sky sharper: DreamSeeker renders the map at the game's pixels through its planes and stretches the finished picture to the
window, so the 2x art is averaged back down (tools/sky_gen/v2/sky_sharpness.py, data/previews/sky_sharp_art1x/art2x_*: no
change in the pixel grid, slightly more shimmer), and it was 8 MB more to download. The game stays on --scale 1, which gives
the art exactly as before; the 2x path is kept for a client that renders finer. Anything over the sky's 480 px
tile is stored as 480 px pieces, name_XY with X and Y from 0 at the bottom left (pieces()): the game puts them back together
with transforms (sky.dm tile_pieces()), since a sprite bigger than the view grows everyone's map.

Sheets:
  sky.dmi         stars_deep/far/mid/near from stars.py (magnitude layers, 960 px a 480 px repeat in 2x2 pieces); twinkle1-3
                  from twinkle.py (on the v2 near stars, likewise); dust kept from sky_gen
  sky_band.dmi    band (stars.py band_layer: bulge to arms, rift, grain stars, knots), 1920 px a 960 px repeat in 4x4 pieces
  sky_nebula.dmi  sky_gen's old 480 px states (old theme lists keep working) plus nebula.py's billow/veil/haze states, 960 px
                  in 2x2 pieces
  sky_bodies.dmi  bodies.py build_bodies() with planets.py's Lavaland and worlds (repaint_states()), 960 px in 2x2 pieces;
                  lit from screen east (Lavaland backlit from the upper left), turned to the sun in game
  sky_deep.dmi    as sky_gen makes it
  sky_asteroids.dmi  asteroids.py: one tiling field per sun heading (asteroids_0..15, 22.5 degrees apart)
Fly-bys, events and dust (sky_events*.dmi) are flyby.py's / events2.py's / dust.py's own builds.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import sky_gen as sg  # noqa: E402
import stars  # noqa: E402
import nebula  # noqa: E402
import bodies  # noqa: E402
import planets  # noqa: E402
import asteroids  # noqa: E402
import twinkle  # noqa: E402

STAGE = os.path.join(sg.ROOT, 'data', 'sky_v2_stage')


def pieces(image, name, size=None):
    """A sprite bigger than the sky's tile as size x size px pieces (default the tile, 480), name_XY with X and Y from 0 counted
    from the bottom left as BYOND does. A sprite the tile's size or smaller is kept whole under its own name.

    A screen object (or anything in its vis_contents) bigger than the view makes BYOND grow the map to fit it, and the view
    then fills only part of the pane: the 960 px band left a 15 tile view in the bottom left quarter of the map for any
    player with the sky on. The game puts the pieces back together with transforms, which don't grow the map.
    """
    size = size or sg.TILE
    if image.width <= size and image.height <= size:
        return {name: image}
    grid = image.width // size
    out = {}
    for qx in range(grid):
        for qy in range(grid):
            top = (grid - 1 - qy) * size
            out['%s_%d%d' % (name, qx, qy)] = image.crop((qx * size, top, qx * size + size, top + size))
    return out


def quarters(image, name):
    """The old name for pieces() of a sprite twice the tile"""
    return pieces(image, name)


# The far things are drawn smaller than their 384 px art (sky.dm pick_deep_sky() sizes): the remnant at 40-55%, the bipolar
# nebula at 55-75%. Their 1 px filaments then fell on about 1.1-1.6 screen pixels, and as the sky turned the smooth sampling
# kept reweighing them: rings of thin lines crawling across them (tools/sky_gen/v2/sky_sharpness.py --shimmer, 2026-11-27).
# A Gaussian this wide (art px) keeps their finest detail about two screen pixels across at their smallest.
DEEP_SOFTEN = {'nebula_remnant': 0.9, 'nebula_bipolar': 0.5}


def soften(image, sigma):
    """A Gaussian blur of a sprite, on premultiplied colour so its edges don't go dark"""
    import numpy as np
    from PIL import Image
    rgba = np.asarray(image.convert('RGBA'), dtype=np.float64) / 255
    pre = np.dstack([rgba[..., :3] * rgba[..., 3:4], rgba[..., 3]])
    r = int(np.ceil(sigma * 3))
    k = np.exp(-np.arange(-r, r + 1) ** 2 / (2 * sigma * sigma))
    k /= k.sum()
    out = pre
    for axis in (0, 1):
        padded = np.pad(out, [(r, r) if a == axis else (0, 0) for a in range(3)], mode='constant')
        out = sum(k[i] * np.take(padded, range(i, i + out.shape[axis]), axis=axis) for i in range(2 * r + 1))
    a = np.clip(out[..., 3:4], 0, 1)
    rgb = np.where(a > 1e-6, out[..., :3] / np.maximum(a, 1e-6), 0)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), a]) * 255 + 0.5).astype(np.uint8), 'RGBA').convert(image.mode)


def build(scale=1):
    tiles = sg.build_tiles()
    tiles.pop('sky_flyby', None)  # replaced by flyby.py's sky_events.dmi
    layers = stars.build_layers(scale=scale)
    for i, state in enumerate(('stars_deep', 'stars_far', 'stars_mid', 'stars_near')):
        tiles['sky'].pop(state, None)
        tiles['sky'].update(pieces(sg.additive_image(layers[state], 801 + i), state))
    for state, rgb in twinkle.build_twinkles(scale=scale)[0].items():  # twinkles on the v2 near stars, not sky_gen's old ones
        tiles['sky'].pop(state, None)
        tiles['sky'].update(pieces(twinkle.as_image(rgb, int(state[-1])), state))
    tiles['sky_band'] = pieces(sg.additive_image(layers['band'], 805), 'band')
    for state, image in nebula.build_images(scale=scale).items():
        tiles['sky_nebula'].pop(state, None)
        tiles['sky_nebula'].update(pieces(image, state))
    body_states = planets.repaint_states(bodies.build_bodies(0.0, scale=scale), scale=scale)
    tiles['sky_bodies'] = {}
    for state, image in body_states.items():
        tiles['sky_bodies'].update(pieces(image, state))
    tiles['sky_asteroids'] = asteroids.build_asteroids()
    for state, sigma in DEEP_SOFTEN.items():
        if state in tiles.get('sky_deep', {}):
            tiles['sky_deep'][state] = soften(tiles['sky_deep'][state], sigma)
    return tiles


def main():
    args = sys.argv[1:]
    scale = 1
    if '--scale' in args:
        i = args.index('--scale')
        scale = int(args[i + 1])
        del args[i:i + 2]
    out = args[0] if args else STAGE
    os.makedirs(out, exist_ok=True)
    tiles = build(scale)
    sg.write_sheets(tiles, out)
    for sheet, states in tiles.items():
        print('%-12s %s' % (sheet, ', '.join(states)))
    print(out)


if __name__ == '__main__':
    main()
