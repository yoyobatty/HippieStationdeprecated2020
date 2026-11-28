# Sky v2 notes (2026-11-20 .. 11-21)

Hand-over notes from the sky v2 work: one lead session and four side sessions (nebulae, bodies, events, motion).
Each file is that session's own record; this page is the lead's summary and the open items.

| file | session | what |
|---|---|---|
| `nebula_v2.md`, `nebula_dm_lists.txt` | sky-nebulae | nebula.py art rounds 1-5, palettes, the DM lists pasted into sky_themes.dm |
| `bodies_v2.md` | sky-bodies | generated Lavaland, worlds, galaxies, sun, asteroids; twinkle v2 (twinkle.py) |
| `sky_events_session.md` | sky-events | fly-bys, dust, the eight rare events, event_tour.py, real-client shooting rules |
| `sky_motion.md` | sky-motion | depth table, slow sky turn, shuttle streaks, join fix, Lavaland drift (drift_check.py) |

## What shipped

- 2a1eaca6 Sky v2: painted skies, galaxy band, lit worlds, rare events, turning sky (placement rules: compose_check.py)
- 5c230455 Lavaland turns with the sky; nebulae round 5; twinkles on the v2 stars; devkit hooks
- 30c6a409 Events clear of Lavaland (drawn R 127), new art for all eight, event_tour.py

Sheets: `build_v2.py [out]` builds every sky sheet (stage first, install into hippiestation/icons/effects). Install only
the sheet you changed when others work on the sky at the same time.

## Back from the Paradise port (2026-11-27)

The sky was ported to Paradise (branch sky-v2, 9955baebca; ledger and checks in Paradise
tools/perf_bench/worktree_archive/sky-v2/). What came back:

- Engine bugs, all hidden here by the slow 1.5 deg/min turn: BYOND turns each of a parent's vis_contents about the child's
  own middle, so layers slid by pixel_w/pixel_z spun apart as the sky turned. Each layer now sits in a
  /obj/screen/parallax_holder at the screen's middle and slides by the holder's transform (slide_to()). The band's and the
  giant's pixel offsets are transforms now (sky_at() nudge). No PIXEL_SCALE on layers (stair-stepped rims, seam lines when
  turned). sky_events_big.dmi is 448 px (512 grew everyone's map by a tile), drawn at SKY_GIANT_SCALE.
- The sky turns with SSsun: SSparallax.turn_line, sun_moved() from SSsun Initialize/complete_movement (sky.dm), resynced
  only when over a degree off; the painted sun sits at SSsun.azimuth. 3-12 deg/min, either way (was 1.5).
- One depth for everything beyond the station (SKY_DEPTH_FAR 0.06), Lavaland 0.15, dust as before; nebulae don't drift.
- planets.py: Lavaland backlit from the upper left (SKY_PLANET_BAKE_ANGLE 135) with a rock belt, a moon and airglow; the
  six worlds re-rendered (crisp terminators, airglow, small moons, the gas giant's rings). build_v2.py runs it after
  build_bodies(). The gas giant's equator follows its rings (gas_frame(), user 2026-11-27).
- sky_weather.dm + weather.py: an ash storm on Lavaland, Aurora Caelus's curtains, a radiation storm's shimmer.
- Checks: tools/power_check/sky_check.dm (headless, 35), tools/keybind_check/sky_shots.dm `port` (real client).

## Follow-up (2026-11-27)

- The headless sky check passed 35/35 with no runtimes. `drift_check.py both port_resume 60` measured 0 px of Lavaland
  drift relative to the event layer for a stationary viewer and up to 4.56 px between fresh layouts at the test spot.
  About 5% of the rolls had near-touching body cores at the start. The rate stayed the same as the sky turned.
- DreamSeeker captured the sky at 0, 60 and 120 degrees and confirmed the weather effects. The giant keeps the map the
  same size while it shows. The `port` and `polish` checks only photograph a giant after one fits in the current sky.
- Reduced the band, veil and haze brightness for Ember, Violet and Verdant. Softened the band grain and attenuated
  star clusters behind its rift. Only `sky_band.dmi` needed rebuilding. Captures are in `data/previews/sky_polish_themes_client.png`.
- Captured the comet before, during and after breakup, and confirmed twinkle from fixed-angle frames. The pre-flash star
  brightens and grows earlier. The supernova captures cover 20, 45, 61 and 80 seconds.
- The default player view is 19×15, matching Paradise. The square preference uses 15×15. DreamSeeker showed both views
  and kept the same map dimensions when parallax was toggled at 19×15. See `data/previews/mapfit19_comparison.png`.

## Review fixes (2026-11-27, evening)

A code review of the port found these; all fixed, with checks added to tools/power_check/sky_check.dm (sky_check_review_fixes()):

- A False Alarm announces an Aurora Caelus after killing it: announce(fake) now skips the starlight, kitchen and sky curtains for a
  fake, and kill() takes the curtains down (aurora_caelus.dm).
- A layer and its holder point at each other, which BYOND never frees: /client/Destroy deletes the client's layers and home
  (parallax.dm). A camera picture's home deletes its own layers.
- Lavaland's art (ion storm aurora, ash storm) goes on every planet layer, players' and camera pictures' (SSparallax.planet_layers),
  not only clients' cached ones.
- The turn queues at most SKY_TURN_MAX_STEPS (100) animate steps: normal suns need 25-97 for 12 hours, an admin's fast sun gets
  re-armed by sun_moved() before they run out (turn_armed_until).
- Weather art follows the storms that began it (SSparallax.ash_storms, rad_storms; weather_began()/weather_over(), also on
  Destroy): a storm that never began can't end another's sky.
- The near weather layer (rad storm, Aurora Caelus) shows only on station levels, as the planet layer does.
- Camera pictures turn with the sun (SSparallax.view_homes, sky_turn_home()), hold the nearest quarter turn in a shuttle's flight
  like a player's screen, fly only layers that fly, and keep each layer's own angle at rest (rest_transform(): Lavaland toward the
  sun, the band at the theme's angle).
- sky_sun_bearing() returns null with no sun painted instead of a runtime.

## Smooth shared art (2026-11-27, night)

Keegan saw lines in the clouds. /obj/screen/sky_art set no appearance_flags, so it took /obj/screen's APPEARANCE_UI with
PIXEL_SCALE: every cloud (drawn 2x), the band, the far things and the twinkle groups were nearest-neighbour, blocky, and
stair-stepped into lines as the sky turned. Paradise's fix (77384aca20) dropped PIXEL_SCALE from the layers only; its screen
type has no PIXEL_SCALE by default, ours does. sky_art and parallax_home now drop it. Checked with sky_shots.dm `seams` (each
layer kind alone at 0 and 20 degrees, then nearest again) and seam_check.py, which finds straight lines along the sky's angle.

## Sharpness, rotation lines and the 2x experiment (2026-11-27, late)

Keegan: pixelation, and lines crawling when the sky turns on its own. Measured with tools/sky_gen/v2/sky_sharpness.py on
sky_shots.dm `sharpness` pictures (each layer kind alone, held at 20 / 20.35 / 20.7 degrees): game-pixel grid energy per
layer (1x: band 9.3, clouds 7.3, other 4.2, stars 2.9; ~1 is none) and shimmer between the angles with the turn taken out.
- The lines: fine detail about one game pixel wide re-sampled as the sky turns. Worst were the far nebulae drawn small (the
  remnant at 40-55% of its 384 px art, 1 px filaments: rings of crawling lines). build_v2.py DEEP_SOFTEN blurs the remnant
  (0.9 px) and the bipolar nebula (0.5 px) in sky_deep.dmi; their shimmer dropped.
- 2x art was built (stars, twinkles, band, theme clouds, bodies at twice the game's pixels in 480 px pieces; stars.py,
  twinkle.py, nebula.py, bodies.py, planets.py all take scale=, scale 1 is bit-identical; *2x_check.py for each) and drawn at
  half size (sky.dm tile_pieces(), star_art(), body_art(); layers fall back to whole sprites when a sheet has no pieces). It
  changed nothing on screen: DreamSeeker renders the map at the game's pixels (its planes are drawn at map size) and stretches
  the finished picture, so art finer than a game pixel is averaged away (grid 9.3 -> 9.5 band, 7.3 -> 7.2 clouds; shimmer a
  little worse). Reverted to the 1x sheets (+8 MB saved); build_v2.py defaults to --scale 1 and rebuilds the installed sheets
  exactly.

## Blocky clouds in a playtest (2026-11-28)

Keegan's playtest (Violet Deep) showed the 2x theme clouds in hard 2x2 game-pixel blocks while the moon looked clean. The
clouds alone draw smooth; with the deep stars on they came out nearest-neighbour. BYOND seems to take a run of sprites'
texture filtering from the first in it: the deep stars (layer 2, drawn at their own size) came just before the clouds (3.0x,
drawn at twice size) and the clouds took their nearest-neighbour sampling. A hair of scale (1.001) or a 0.01 px shift on the
stars' art didn't change it; drawing the deep stars after the clouds did. The deep stars are at layer 3.5 now (parallax.dm;
all these layers add their light, so the order doesn't change the picture): blocks score with every layer on 0.20 -> 0.07,
the turned sky live smooth too. The far nebulae, drawn small after the far and mid stars, came out the same with and without
them. sky_check.dm `sky_check_scaled_first()` keeps every unscaled star layer above every scaled one.
Tools: sky_sharpness.py's blocks score (2x2 game-pixel blocks, read at 0 degrees: 0.72 forced nearest, ~0.1 smooth);
sky_shots.dm `scaling` (each Scaling Mode), `layers` (each layer alone, or with a kind or type kept on:
data/sky_shots_layers_with), `batch` (the experiment above) and `lobby_ghost` (observing from the lobby, then the round
starting with the sky turning live). The map's Scaling Mode and being a ghost made no difference.
The 2x clouds (960 px) carried no more fine detail than the 1x ones (0.055 against 0.065): the 1x sheets stay.
Two `layers` runs drew a rainbow smear over the whole map, the player sprite tinted too; not seen again in six runs (one
starting on the same sky, one with the card's memory full and busy from tools/gpu_load/gpu_load.py). Cause unknown, left.
A layer shot alone shows white where nothing of the parallax plane is drawn (it multiplies over the white space mask), and a
far thing's whole square as black there: an artifact of the lone-layer picture, not seen in play.

## The far sky holds still (2026-11-28)

Keegan: the sky wobbles a little as you move, side to side flying left and right, up and down flying up and down. Filmed
(sky_shots.dm `walk`: a ghost flies 12 tiles east and back, 10 north and back; tools/keybind_check/record.ps1 takes the game
window by PrintWindow, never the screen; tools/sky_gen/v2/sky_motion.py tracks the sky by phase correlation): at
SKY_DEPTH_FAR 0.06 px a tile the far sky never moved as parallax, it jumped a whole game pixel (2.96 screen px) every 12-17
tiles and back again on the way back. Keegan's call: hold it still. SKY_DEPTH_FAR is 0 (stars, clouds, band, far things, sun,
other world); Lavaland (0.15) and the dust keep their parallax. Filmed again: 0.00 px over 88 steps. sky_check.dm holds it.

## Ratings at hand-over

Nebulae 8.5-9.5. Events: vortex 9, prism 8.5, shower 8.5, battle 8.5, aurora 8.5, giant 8, supernova 8, breakup 7.5.
Bodies 9.5.

## Open items

- tools/testkit/client_lane.py close() sets split.splitter=66, but that control can't be reached on this skin: a no-op.

## Rules learned

- Real-client shots: fixed spot [110,60,2] on testbench, seed 5, maximized window, stretch-to-fit (what Keegan plays),
  10 fps; the test client logs in as Keegan's key and the map zoom is saved per key, so client_lane.close resets it.
- Never leave a testkit server or DreamSeeker up idle: Last Light's reserved timed runs wait for a quiet machine, and a
  session waiting on gpu_share with its own idle server deadlocks everyone. `devkit dk.py gpu` names the blocker.
- Fewest runs that prove it; one server and client at a time (Keegan, 2026-11-21).
