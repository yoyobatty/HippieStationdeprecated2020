# Hand-drawn sky art from other SS13 codebases

`sky_gen.py build` cuts the planets out of these sheets, scales them and writes them to
`hippiestation/icons/effects/sky_bodies.dmi` (the `PORTED` list in `sky_gen.py` says which state becomes which).
The sheets are kept whole and unedited so a rebuild gives the same pixels.

| File | From | Commit | States used |
| --- | --- | --- | --- |
| `paradise_parallax.dmi` | ParadiseSS13/Paradise, `icons/effects/parallax.dmi` | `bd91a1b962fe9bd38e346e9fafd4ebb10784fcb3` (2024-08-15) | `planet_lava` |
| `tgmc_parallax.dmi` | tgstation/TerraGov-Marine-Corps, `icons/effects/parallax.dmi` | `971b3daa89c16fe30e05bc77228e33abd87d3a61` (2025-10-12) | `ice`, `jungle`, `rock`, `redrock`, `Palmaria` |

Both projects license their icons under CC BY-SA 3.0, the same as this codebase's. Credit goes to their sprite contributors.

tgstation's own sheet was compared too (tgstation/tgstation at `12131504f3bcfbb15a81aaefe847a859e647c8df`): its stars, gas and
asteroids are the ones this codebase already has, and its newer lava planet has an ice moon, which belongs to a map we don't run.

Everything else in the sky (stars, twinkle groups, nebula clouds, dust, the sun, comets, shooting stars, ships) is drawn by
`sky_gen.py` itself.
