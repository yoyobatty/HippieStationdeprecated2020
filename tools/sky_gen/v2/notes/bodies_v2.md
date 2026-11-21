# Sky bodies v2 (tools/sky_gen/v2/bodies.py)

Uncommitted. New files only: `tools/sky_gen/v2/__init__.py` (empty) and `tools/sky_gen/v2/bodies.py`. sky_gen.py, .dm and .dmi files were not touched.

## API
- `build_bodies()` returns `{state: PIL RGBA 480x480}`. States:
  - planet_lava
  - world_ice, world_jungle, world_rock, world_redrock, world_ocean
  - world_gas (new)
  - galaxy, galaxy2, galaxy3, galaxy4 (new, generated)
  - sun
- Planets and galaxies are straight-alpha images for BLEND_OVERLAY. Glow and haze carry alpha by brightness. The night-side lava glow is baked in.
- `sun` is an opaque additive image, white; the game tints it.
- To integrate, sky_gen.build_tiles can use `from v2.bodies import build_bodies; bodies = build_bodies()`. The full build takes about 45 s.
- The previews are baked east-lit (the default). Every body state is now generated. No ported Paradise/TGMC art is used, and `ported_bodies()` is only read for the before previews.

## Sun direction and placement (ruling: day side faces the round's sun)
- Every lit body is baked lit from screen east (0 degrees, counter-clockwise from +x, y up). That covers planet_lava and all six world_* states.
- The whole picture is turned at bake time: surface, lava glow, bloom and haze rim together. The rim is round, so a DM turn is exact. **No separate additive glow state is needed.**
- `build_bodies(light_angle=0.0)` takes the angle as a parameter, if pre-baked headings are ever wanted instead of a DM turn.
- **DM turn:** the sun is far away, so its light direction is its screen bearing for every body. In sky.dm, `sun_bearing` is used as x = cos, y = sin with y up, so: `transform = matrix().Turn(-sun_bearing)` on the planet and world layers. BYOND's Turn is clockwise. Keep PIXEL_SCALE off so the turned sprite filters smoothly.
- With the world placed 110-180 degrees from the sun, its lit side faces the sun's side of the screen.
- The galaxies and the sun are not lit, so they need no turn. A galaxy can take any turn for variety.

## Visual radius inside the 480 state (centre 240,240)
| state | opaque disc | visible (alpha >= 8) | faint (alpha >= 2) |
|---|---|---|---|
| planet_lava | 128 | 134 | 137 |
| world_ice | 58 | 60 | 62 |
| world_jungle | 58 | 61 | 63 |
| world_rock | 58 | 58 | 58 |
| world_redrock | 58 | 61 | 62 |
| world_ocean | 58 | 61 | 63 |
| world_gas | 78 | 82 | 84 |
| galaxy | - | 160 | 166 |
| galaxy2 | - | 150 | 156 |
| galaxy3 | - | 187 | 195 |
| galaxy4 | - | 185 | 201 |
| sun (additive) | core 3 | 179 | 223 |

The galaxies are elongated, and their radius is along the major axis. galaxy3's major axis is at 32 degrees, galaxy4's at -14 degrees.

## DM changes needed (not done)
1. Point the galaxy layer `/obj/screen/parallax_layer/body/galaxy` at `hippiestation/icons/effects/sky_bodies.dmi`. The state names are the same.
2. Turn the planet and world layers as described above.
3. Still tg art elsewhere, outside this task: the random asteroids and space_gas layers, and layer1-3, in `icons/effects/parallax.dmi`.

## Weak spots fixed (before/after: data/previews/sky2_body_fixes.png; per-state *_before.png vs plain)
- **world_rock:** low sun for relief, crisp maria shores, central-peak craters, a ray crater with broken rays, and no more clover crater cluster.
- **world_gas:** rewritten. Uneven gamma-width belts and zones at low contrast, 40 edge eddies, festoons, a white-oval chain, a red oval with a pale collar, mottled poles, limb darkening, a tight penumbra.
- **world_ocean:** no land relief or speckles under the polar cap, shallows round the coasts, fair-weather cumulus, a narrower glint, thinner and crisper air.
- **world_jungle:** thinner, crisper air (shared EARTH_AIR).
- **planet_lava:** hot yellow cores down wide rivers and fresh cracks. The haze sits at the rim (smaller scale height), so the day side is clearer.
- **world_redrock:** the north cap is in view and smaller, the dark regions are wind-streaked, the snake canyon is replaced by straight rift troughs.
- **world_ice:** curved cycloid cracks, varied stain colours, reddish mottling, almost no air.
- **galaxy1-4:** new. A face-on grand-design spiral, a barred spiral, an inclined Andromeda-style spiral, and an edge-on disc with a mid-plane dust lane.

## Round 2: the far-away read (2026-11-20)
Before/after: data/previews/sky2_body_r2_compare.png. Half-size (zoomed-out client) sheet: sky2_body_r2_far.png. The per-state
before images are sky2_body_<state>_r2before.png. Still east-lit, so the DM turn is unchanged.
- **No pixel outline.** The disc edge is feathered over about 1 px. Opaque (alpha 255) radius is now 127 / 57 / 77 (lava / world / gas). Visible and faint radii are unchanged.
- **Night sides are black.** Air inside the planet's shadow cylinder no longer scatters light. Only a twilight band at the terminator stays lit. Before this, ice, Mars, gas and ocean carried a grey or brown veil over the night side, with a hard line at the terminator: the "glass shell" look. The night-side fill now scales with sqrt(albedo) at a lower level, so bright ice no longer glows grey.
- **Limb darkening** on Lavaland (limb 0.2). The gas giant has its own (0.35) plus a soft terminator, `render(terminator=(-0.10, 0.32))`, for deep air.
- **Lavaland:**
  - Sunlit lava is outshone by day (day-side emission 0.3 -> 0.08), so the cracks read on the night side as asked.
  - Plate cracks taper and break open, so they no longer close into a drawn polygon net.
  - The fine crust mesh is thinner, dimmer and patchy, which also cures the dotted-line aliasing at the limb.
  - Added 90 small vents and lava lakes over the active faces.
- **Gas giant:** 70 more eddies from 0.008 to 0.03 rad, so the hooks no longer repeat. Thin threads run inside every band.
- **Mars:** the rifts are wider and softer, so they read as troughs instead of scratched lines.
- **Ratings (honest):**

  | body | rating |
  |---|---|
  | planet_lava | 9.5 |
  | world_rock | 9.5 |
  | world_ocean | 9.5 |
  | world_jungle | 9 |
  | world_ice | 9 |
  | world_redrock | 9 |
  | world_gas | 9 |
  | galaxies | 9 |
  | sun | 9 |

- **Round 3 (after GPU FREE; Python only):**
  - Gas giant: belt and zone edges soft (0.014-0.032), stronger streaks and threads, darker belt edges, weaker hooks. The clip-art fills are gone, so it rates 9.5 now.
  - Lavaland by day: fresh black flows spread from the active channels, with red-oxide plains and a little sulphur fallout. The day side no longer reads as a grey moon, so it rates 9.5+ now.
  - Galaxies: alpha over is kept on purpose. In the outskirts the alpha is low, so stars show through; bright cores and dust lanes would hide them in real life too.
- Meteors are not in bodies.py. They are the events session's flyby.py (sky_events.dmi).

## Round 4: asteroid field + Lavaland at game scale (2026-11-20)
- **Asteroids:** new file `tools/sky_gen/v2/asteroids.py`. `build_asteroids()` returns `{asteroids_0..asteroids_15: PIL RGBA 480x480}`, each a seamless tile.
  - State i is lit from heading 22.5*i degrees (counter-clockwise from screen east, y up). The layer tiles, so it can't be turned: pick the state instead. In DM: `icon_state = "asteroids_[round(sun_bearing / 22.5) % 16]"`.
  - It is the same field under every heading. Suggested sheet: add `tiles['sky_asteroids'] = asteroids.build_asteroids()` in build_v2.py, then point `/obj/screen/parallax_layer/random/asteroids` at `sky_asteroids.dmi`.
  - The field holds 76 rocks: 42 specks of r 1-3 px, 22 small of r 3-5, 9 medium of r 6-10 and 3 big of r 12-18. They are loosely clustered round 4 drift centres and never overlap.
  - Each rock is a ray-marched lump with craters and carbon/stone/metal albedos. It has a soft terminator and a sun-side rim, and its night side is near black.
  - Build takes about 25 s.
  - Previews:
    - data/previews/sky2_body_asteroids_compare.png (old vs new)
    - sky2_body_asteroids_h0/h4/h10.png (tiled game view; sun east, north, about 225 degrees)
    - sky2_body_asteroids_rock_zoom.png
- **Lavaland:**
  - It is now side-lit (`light_at(0.0)`), so about half the disc is night side and the lava network reads at game scale.
  - Night emission 0.14, stronger bloom and night glow.
  - Still east-lit, so the DM turn is unchanged. Before/after: data/previews/sky2_body_planet_lava_r3_compare.png.

## Remaining weak spots (honest)
- At 116 px the worlds are limited by resolution. Fine detail (rays, rifts, lineae) reads only as texture.
- The gas giant's eddy hooks repeat a little along a band edge.
- Lavaland's plate cracks are still a bit polygonal in the busiest patch.
- The galaxy knots are few, and the galaxies cover the stars behind them (alpha over); real galaxies are transparent. An additive galaxy layer would fix that.

## Twinkle v2 (2026-11-21)
- New tool: `tools/sky_gen/v2/twinkle.py` (preview / stage [DIR] / check A B). It makes twinkle1-3 sit on stars.py's
  stars_near stars: it replays star_field seed 401's draws and checks the replay against the installed stars_near (dither
  seed 804 = build_v2's 801 + 3).
- Why: the old sky_gen twinkles were drawn on sky_gen's old near stars, so in the v2 sky they lit ~30 phantom stars
  where no star is (data/previews/sky2_twinkle_sheet.png, left panel).
- Art: 7 of the 10 near stars twinkle, spread over 3 groups. Each twinkle state holds only the extra light at the top
  of the fade: 26% of the star's flux in its own blackbody colour, shifted +-10% in temperature (chromatic
  scintillation). It is a wider core (1.5x sigma) plus glow, and on the brightest the spikes run a little longer.
  At the game's alpha 45 low point it adds ~4%. The DM fade (sky.dm twinkle()) is unchanged.
- INSTALLED: hippiestation/icons/effects/sky.dmi, twinkle1-3 only. The other 5 states have identical pixels, and the
  DMI description is identical (twinkle.py check, lookkit diff 0.00%). The previous sheet is at
  data/sky_twinkle_stage/sky_before.dmi.
- FOR COORDINATOR: build_v2.py still takes twinkle1-3 from sky_gen, so a rerun would bring the phantom twinkles back.
  Add `import twinkle` and `tiles['sky'].update({k: twinkle.as_image(v, int(k[-1])) for k, v in twinkle.build_twinkles()[0].items()})`
  after the stars loop.
