# Sky motion (parallax.dm) - notes from the motion session

Owner: hippiestation/code/_onclick/hud/parallax.dm only. Nothing committed.

## What it does
- The whole sky turns: `C.parallax_home` (the one screen object holding every layer in vis_contents) is rotated. Rate
  `SSparallax.sky_turn_per_minute` (default `SKY_TURN_PER_MINUTE` 1.5 deg/min clockwise; VV it for tests, then re-make the
  client's layers with `hud.update_parallax_pref()`). Angle = `sky_turn_angle()` = world.time * rate, same for everyone.
  One animate chain per client (8 steps of 90 deg, an hour each); no server work while standing still.
- Home now has `icon = sky.dmi` (480x480, null state draws nothing) so it turns about the screen centre.
- Layer slides (pixel_w/pixel_z) are in the turned frame; update_parallax() un-turns each step's delta, so walking east still
  slides the sky west on screen. Absolute layers (bodies) turn with the sky about the screen centre (`sky_rest()`); the planet's
  rest is (0,0), so Lavaland stays put while the stars turn (tidally locked orbit).
- Shuttle flight: the sky swings to the nearest quarter turn over 3 s (`parallax_snapped`) so the loop runs along the art's
  repeat (no seam), layers stretch along the heading (`streak`: deep 1.6, far 2.5, mid 4, near 6, dust 6) while easing in,
  then cruise; on arrival each layer slows from its estimated current place to a whole repeat (no tg jump-back) and shrinks,
  the sky swings back to its turn.
- Per-layer angle: `/obj/screen/parallax_layer/var/angle` + `set_angle()`. `/datum/sky_theme/var/band_angle` (declared in
  parallax.dm, default 0): a nebula entry with state "band" is turned by it. A new band layer type: call
  `set_angle(SSparallax.theme.band_angle)` in its setup. Angled layers don't fly (they hold still in transit) and wrap
  along their own turned axes.

## Depth (far-away sky), added later
- `speed` is now a distance: px slid per tile walked (a tile is 32). Table at the top of parallax.dm (`SKY_DEPTH_*`):
  deep stars 0.04, far 0.08, mid 0.15, near 0.3; nebulae = theme speed x0.25 (0.09-0.14); deep things x0.15; sun and
  galaxy 0.04; other world 0.12; Lavaland 0.4; random asteroids/gas 6; near dust 24; NEW mid dust 9 (`dust/mid`, alpha 95,
  appended in create_parallax because sky_themes.dm is included after parallax.dm).
- Flight uses its own `flight_speed` (old values: deep 0.2, far 0.45, mid 0.9, near 1.6, nebula = theme speed, dust 5,
  mid dust 2.5), so walking depth and flight streaming are tuned apart.
- Every visible 1 px move glides with the eye (no snapping on slow layers); offsets stay floats.
- Lavaland rests 210 px from screen centre on the side away from the sun (`planet_rest()`), barely slides, and is turned
  by `face_sun()` (art lit from east, sky_bodies). The other world turns the same way. Both use `set_angle()`.
  -> lighting-v2: `lighting_v2_space.dm` tints station tiles near SSparallax.planet_x/y_offset as "under the planet";
     the planet no longer sits over that spot on screen. sky-events: the aurora rides the planet layer and now turns with it.
  -> map_view.dm (camera consoles) still uses tg speeds semantics via L.speed: its sky is now near-still too (fine), but
     it animates every layer's transform to matrix(), which drops the planet's sun turn in camera views.

## Traps for the art/event sessions
- `/obj/screen` has APPEARANCE_UI, which includes RESET_TRANSFORM: anything in a layer's vis_contents ignores the layer's
  transform (and so the sky's turn and the flight stretch). Layers now drop that flag, and `carry()` drops it from the
  shared art each layer's set_quality() puts in vis_contents. Any NEW thing nested deeper (e.g. children added to the flyby
  object's vis_contents in sky.dm) needs `appearance_flags &= ~RESET_TRANSFORM` too, or it won't turn with the sky.
- Tiled coverage: layers' own overlays now reach the view's corners at any angle (radius, not half-width). Shared art from
  `sky_art.tile(reach = 2)` covers up to a ~24x18 tile view; nothing needed for 15x15 or 19x15.
- testkit: `testkit.mdme.rsc` is locked while any session's testkit server runs, so a build adding a new .dmi fails with
  "cannot find file". Build your own name: `tk.build(name='x.mdme')` + `tk.start(map, dmb=...)` from Python.

## State 2026-11-20 22:10 (GPU HOLD from Last Light lead; all processes stopped)
- Band offset fix (parallax.dm nebula setup): the band's nebula shift is read as (along, across) and turned by the band
  angle, so across = SSparallax.band_offset lands on the band's normal (matches sky.dm band_distance()). Layer
  offset_x/offset_y are in the sky frame (home's, before the whole-sky turn); a layer's own transform doesn't turn them.
  Compiles (skytk.mdme 0 errors); not seen in the engine yet.
- Cost A/B NOT run yet. Ready: skytk.mdme.dmb (mine) + skybase.mdme.dmb (HEAD parallax.dm + stubs, data/skybase_parallax.dm),
  both include data/skybench.dm (now rustg microsecond timer). Script: scratchpad abrun.py.
  TRAP: `gpu_share.py reserve` before tk.start deadlocks: tk.start's gpu_wait waits on your own reservation. Boot first,
  then reserve for the timed part.
- Cost A/B DONE 22:2x (hippiestation map, seed 7, one real client, update_parallax() per tile step, 200 steps x10, rustg us):
  mine median 29.2 us/step (25-36), 13 layers; base 18.2 (11-22), 12 layers. +11 us per tile walked per client (+60%).
  Sources: the extra mid-dust layer, the per-step un-turn matrix + own-angle matrix (new /matrix each step), glides on
  every 1 px change. 50 clients walking 4 tiles/s = ~2 ms/s server. Cheap wins if needed: cache the unturn matrix per
  client (sky turns 1.5 deg/min), precompute an angled layer's own matrix in set_angle().
- Join-streak bug FIXED (parallax.dm create_parallax -> track_parallax_mover()): a new ghost spawns in the arrivals shuttle
  (in transit on testbench, movedir WEST), so its sky starts a flight; it was then moved (testkit client_view forceMove, a
  ghost jump) before SSparallax registered it in client_mobs_in_contents, so Moved() didn't update the sky: flight kept
  looping and absolute bodies stayed laid out for the shuttle's z. create_parallax now registers the eye's mover at once.
  Proof: data/previews/sky3_join_fix_compare.png (old first shot | fixed first | fixed second). Lint 0 new.
  The ghost still starts and stops a flight in the same tick, which plays a short arrival slow-down (~invisible by 6 s).

## Drift over a round (2026-11-21)
- Tool: tools/sky_gen/v2/drift_check.py (+ drift_probe.dm): real layers from 60 headless sky rolls, turned the way the
  client draws them, judged at 0/30/60/120/240 min for a viewer laid out at round start and one laid out then (join, z change).
- Bug: planet sky_rest() was (0,0): a fresh layout always put Lavaland opposite where the sun was at round START, while the
  sun had turned. Fresh viewer: 46% of rounds Lavaland crowded the sun/world at 120 min, 46% dark side to the sun at 60-120.
- Fix: deleted /obj/screen/parallax_layer/body/planet/sky_rest(): Lavaland turns with the sky, always opposite the sun.
  After: 1-5% (all world-vs-Lavaland near-touches from placement: world 70-115 deg off the sun, Lavaland at 180).
- Turn is a closed form (world.time x rate), so no timewarp needed; nothing goes off screen (all centres <= 210 px).
