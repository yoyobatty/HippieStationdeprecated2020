"""Sky v2 build: sky_gen's sheets with the v2 stars, galaxy band, nebulae and bodies put in.

    python tools/sky_gen/v2/build_v2.py [out_dir]    default: data/sky_v2_stage (look first); the game's sheets live in
                                                     hippiestation/icons/effects (pass that to install)

Sheets:
  sky.dmi         stars_deep/far/mid/near from stars.py (magnitude layers); twinkle1-3 from twinkle.py (on the v2 near
                  stars); dust kept from sky_gen
  sky_band.dmi    band (960 x 960, stars.py band_layer: bulge to arms, rift, grain stars, knots) as four 480 px quarters
                  (quarters()); drawn at scale 1, its repeat is the nebula repeat (PARALLAX_TILE * SKY_NEBULA_SCALE)
  sky_nebula.dmi  sky_gen's old states (old theme lists keep working) plus nebula.py's billow/veil/haze states
  sky_bodies.dmi  bodies.py build_bodies(): lit from screen east, turned to the sun in game
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
import asteroids  # noqa: E402
import twinkle  # noqa: E402

STAGE = os.path.join(sg.ROOT, 'data', 'sky_v2_stage')


def quarters(image, name):
    """A sprite twice the sky's tile as its four quarters, name_XY with X and Y 0 or 1 counted from the bottom left as BYOND does.

    A screen object (or anything in its vis_contents) bigger than the view makes BYOND grow the map to fit it, and the view
    then fills only part of the pane: the 960 px band left a 15 tile view in the bottom left quarter of the map for any
    player with the sky on. The game puts the quarters back together with transforms, which don't grow the map.
    """
    half_w, half_h = image.width // 2, image.height // 2
    out = {}
    for qx in (0, 1):
        for qy in (0, 1):
            top = half_h if qy == 0 else 0
            out['%s_%d%d' % (name, qx, qy)] = image.crop((qx * half_w, top, qx * half_w + half_w, top + half_h))
    return out


def build():
    tiles = sg.build_tiles()
    tiles.pop('sky_flyby', None)  # replaced by flyby.py's sky_events.dmi
    layers = stars.build_layers()
    for i, state in enumerate(('stars_deep', 'stars_far', 'stars_mid', 'stars_near')):
        tiles['sky'][state] = sg.additive_image(layers[state], 801 + i)
    for state, rgb in twinkle.build_twinkles()[0].items():  # twinkles on the v2 near stars, not sky_gen's old ones
        tiles['sky'][state] = twinkle.as_image(rgb, int(state[-1]))
    tiles['sky_band'] = quarters(sg.additive_image(layers['band'], 805), 'band')
    tiles['sky_nebula'].update(nebula.build_images())
    tiles['sky_bodies'] = bodies.build_bodies(0.0)
    tiles['sky_asteroids'] = asteroids.build_asteroids()
    return tiles


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else STAGE
    os.makedirs(out, exist_ok=True)
    tiles = build()
    sg.write_sheets(tiles, out)
    for sheet, states in tiles.items():
        print('%-12s %s' % (sheet, ', '.join(states)))
    print(out)


if __name__ == '__main__':
    main()
