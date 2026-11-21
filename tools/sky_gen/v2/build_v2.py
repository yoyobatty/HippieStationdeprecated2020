"""Sky v2 build: sky_gen's sheets with the v2 stars, galaxy band, nebulae and bodies put in.

    python tools/sky_gen/v2/build_v2.py [out_dir]    default: data/sky_v2_stage (look first); the game's sheets live in
                                                     hippiestation/icons/effects (pass that to install)

Sheets:
  sky.dmi         stars_deep/far/mid/near from stars.py (magnitude layers); twinkle1-3 and dust kept from sky_gen
  sky_band.dmi    band (960 x 960, stars.py band_layer: bulge to arms, rift, grain stars, knots); drawn at scale 1, its repeat
                  is the nebula repeat (PARALLAX_TILE * SKY_NEBULA_SCALE)
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

STAGE = os.path.join(sg.ROOT, 'data', 'sky_v2_stage')


def build():
    tiles = sg.build_tiles()
    tiles.pop('sky_flyby', None)  # replaced by flyby.py's sky_events.dmi
    layers = stars.build_layers()
    for i, state in enumerate(('stars_deep', 'stars_far', 'stars_mid', 'stars_near')):
        tiles['sky'][state] = sg.additive_image(layers[state], 801 + i)
    tiles['sky_band'] = {'band': sg.additive_image(layers['band'], 805)}
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
