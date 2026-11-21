# Sky events session (flybys + rare events + dust)

Heads-up: around 18:40 I ran `ss_call SSparallax sky_event(...)` (battle, shower, breakup, aurora, comet) without a port and it
went to the most recently started testkit server, a hippiestation-map one that is not mine. If your sky screenshots from then
show a battle / meteor shower / comet / aurora on Lavaland, that was me. Sorry. I pass port=45604 explicitly from now on.

Files I own: hippiestation/code/_onclick/hud/sky.dm (flyby + events + dust hooks), tools/sky_gen/v2/flyby.py, v2/dust.py,
hippiestation/icons/effects/sky_events.dmi, sky_events_dust.dmi.

Note: around 19:05 I ran `sed -i 's/\r$//'` over tools/sky_gen/v2/*.py by mistake, which also touched bodies.py, nebula.py,
stars.py and __init__.py. If they were CRLF they are LF now; content is otherwise unchanged. Python reads both.

## Integration notes for the coordinator (sky events session)

- Art: `python tools/sky_gen/v2/flyby.py build` writes hippiestation/icons/effects/sky_events.dmi (256 px, all fly-by and
  event sprites) and sky_events_dust.dmi (480 px tiles: `dust` grit, `dust_lit` 8-frame lit specks, white for tinting).
  `python tools/sky_gen/v2/flyby.py preview [flybys dust shower supernova battle aurora breakup]` -> data/previews/sky2_*.png.
  flyby.build_tiles() / dust.build_tiles() return {state: PIL or [frames]}; DELAYS dicts give per-frame delays.
- sky.dm hooks into types defined in parallax.dm WITHOUT editing parallax.dm:
  - `/obj/screen/parallax_layer/dust/Initialize()` sets icon = sky_events_dust.dmi, alpha = 255; `dust/set_quality()` puts the
    shared lit-specks sky_art (tinted theme.starlight) in its vis_contents.
  - `/obj/screen/parallax_layer/body/planet/set_quality()` carries SSparallax.aurora during an ion storm.
  If parallax.dm grows its own procs of those names, merge them (DM will silently let one override the other).
  If you fold the dust into sky.dmi, change the icon line in dust/Initialize and dust_art().
- flyby_art() now returns a holder (/obj/screen/sky_art/flyby, no icon); every piece is a /obj/screen/sky_art/piece in its
  vis_contents. tools/keybind_check/sky_shots.dm still works: holder.launch(kind, time) delegates to launch_flyby().
- The aurora sprite is drawn round Lavaland's disc as measured in the CURRENT sky_bodies.dmi planet_lava (centre 241.5,238.5,
  r 52, flyby.py PLANET_X/Y/R). If the planets session redraws/rescales Lavaland, update those three numbers and rebuild.
- Triggers: admin verb Fun > "Sky Event" (R_FUN); or `ss_call SSparallax sky_event "<shower|supernova|battle|aurora|breakup>"`
  and `ss_call SSparallax launch_flyby "<meteor|bolide|comet|ship|convoy>"`.
- Testkit camera quirk (not mine): a freshly connected observer camera had the flybys layer at invisibility 101 until it
  stepped a tile (update_status not run after the first placement). `client_view` to a neighbouring tile fixes it.
- Pieces and the holder drop RESET_TRANSFORM (they turn with the motion session's sky) and PIXEL_SCALE (glows are drawn
  scaled up to 5x; nearest-neighbour would make them blocky). Dust and aurora vis_contents go through carry().
- If bodies v2 (Lavaland disc r 128, centred) goes in: set SKY_LAVALAND_RADIUS 128 and SKY_LAVALAND_SHIFT_X/_Y 0 in sky.dm;
  the aurora then draws at 2x (soft). PLANET_X/Y/R in flyby.py are for the previews only.
- sky_flyby.dmi is no longer used by sky.dm (sky_gen.py still builds it).
- Engine shots: data/previews/sky2_engine.png (real client, testbench, port 45607, closed after the batch).

## Round 2 (after the Last Light bar and the placement ruling)
- New whole-frame event `vortex` (ion maelstrom): two spiral layers (3 arms near, a turn in 4 min; 2 arms far, 7 min), eye
  rim that opens and throbs, forked lightning lighting the storm. 45 s fades, 6-9 min peak.
- Pacing: memoryless. SKY_EVENT_FLOOR 15 min, SKY_EVENT_MEAN 180 min (~1 round in 3-4 at 60-90 min), SKY_EVENT_AFTER 45 min
  after an event ends, SKY_EVENT_RETRY 2 min when an event is still on. Aurora only picked if someone can see Lavaland.
- Peaks lengthened: shower 7 min (~900 meteors), battle 5-7 min (bigger, mid-frame), aurora 7-8 min.
- Placement: sky_clearance()/path_clearance()/clear_path()/clear_place() in sky.dm read body_places (sun, world, galaxy,
  deepN, only those the theme shows). Fly-bys run off-screen to off-screen and keep off them (comets also keep their tails
  off them). Shower radiant is off-screen on the side whose streams cross the most open sky (sun and world avoided; streaks
  may cross far nebulae). Supernova and battle sit near the middle, clear of the bodies. Bearings were not exported: the
  places in body_places are enough.
- Not checked in a real client: the vortex (DreamSeeker busy, GPU queue held by Last Light). Headless: no runtimes.

## Round 3 (2026-11-20 late): prism + giant
- New art module tools/sky_gen/v2/events2.py (imported by flyby.py build). New sheet hippiestation/icons/effects/
  sky_events_big.dmi (512 px, straight alpha): state `giant`. sky_events.dmi gains prism_shard/2/3 (8 frames each),
  prism_flare, prism_halo, moon, ring_shine (now ~1.45 MB).
- `prism`: ice-crystal stream on one wind, 60-72 faceted shards at depths (far small slow, near big quick), tumbling faces,
  spectral edge split, sun-catch flares that fan colour away from the sun, ~190 coloured glints, a 22-degree halo round the
  sun. Crystals cross the sun on purpose (that's the event) but keep off the other world (world_clearance()). Needs
  theme.sun (only picked then). 6-8 min + 45 s fades.
- `giant`: ringed gas giant, painted bands, rings with Cassini-style gap, planet shadow on rings, ring shadow on face,
  lit from the sun's bearing (turned to it), BLEND_OVERLAY so the night side hides stars. Comes out of the dark (colour
  black->white), drifts 60 px and grows 6%, a moon transits its face. Placement: biggest of size 0.76/0.64/0.54 whose disc
  and ring ellipse (giant_clearance()) clear the sun and world, far things allowed 40 px under a ring tip.
  pixel_x/y -128 puts the 512 sprite's middle where sky_at() expects a 256 one.
- Weights: vortex 3, shower 3, battle 2, breakup 2, giant 2, prism 2 (with a sun), supernova 1 (once), aurora 2 (if watched).
- NOTE (process): one ss_build ran while a hippie-sky-bench reservation was queued (my mistake, before the wait cleared).
- sky.dm was edited concurrently by another session (band/deep-sky procs at the top); my edits are below line ~570 only.
- Later in round 3: vortex eye no longer a black hole (smaller eye, wisps winding in, broken rim); lightning strikes keep
  off far things and their glow is smaller/dimmer (no more white nebula). Remnant redrawn: clumps + filament web in
  coloured patches, thin broken shock (was a tube-like ring).
- BLOCKED: real-client shots. Last Light lead (local_67b83098) put a GPU HOLD on all sessions ("until sky and clouds are
  perfect"), so no build/boot until GPU FREE. Last edits (giant_clearance, world_clearance, lightning placement, remnant)
  pass lint but are NOT compiled. Next step after GPU FREE: gpu_share.py wait, ss_build, ss_start testbench, ss_call
  SSparallax sky_event "vortex"/"prism"/"giant", ss_screenshot, ss_client_close, ss_stop.
- After GPU FREE: real-client check done (own dmb skyev.mdme, deleted after). data/previews/sky3_engine.png = vortex | prism |
  giant in DreamSeeker. Invariants clean on all three (0 runtimes, 0 hard deletes, 0 MC alerts). Lint 0 new.
- Fix from the engine: Lavaland now rests 210 px opposite the sun (motion session), exactly where the giant goes, and it's
  drawn over the giant. New lavaland_clearance() in sky.dm keeps the giant's disc and rings off it.
- FOR COORDINATOR: boot runtime in your sky_cores() (sky.dm:222 "cannot read from list") on testbench seed 7, rose theme.
- Testing tip: themes without a sun (rose, glacier, quiet...) never pick prism; testbench seed 5 gives ember (has a sun).
- Band check shot (plain open space, no event): data/previews/sky3_band_view.png (15x15 view; DreamSeeker drew the map in a quarter of the window, so no wider view). testbench seed 5, ember, band_offset 77, camera at 41,40,2. Built as skyev.mdme, so no testkit.mdme lock.

## Round 4 (2026-11-21): every event in a real client
- Tool: tools/sky_gen/v2/event_tour.py. Builds skyev.mdme, starts testbench seed 5, puts the camera at [110,60,2] with the window maximized and zoom 0 (stretch-to-fit), caps the client at 10 fps, and reseeds before each event. It captures every 30 s with lookkit and makes a sheet per event with lookkit, cropping each frame separately. `--sheets` rebuilds the sheets from saved frames.
- Traps:
  - DreamSeeker is not DPI-aware (2560x1440 at 133%).
  - A PrintWindow grab holds the map at its logical size, in the bottom-left of the pane. The grab can also switch between 1936x1048 and 2576x1408 in the middle of a run.
  - split.splitter can't be reached with winset or winget on this skin.
  - `.screenshot auto` hung the server (message buffer overflow).
- First pass: data/previews/sky_tour/before/*_sheet.png. Weak spots found and fixed:
  - Lavaland is drawn at R=127 now (bodies rework), but sky_clearance didn't know about it, so the giant, battle, breakup and supernova hid behind it. sky_clearance now includes lavaland_clearance (SKY_PLANET_CORE). SKY_LAVALAND_RADIUS changed from 52 to 127 and the shift from (2,1) to (-1,0); the aurora's size comes from it.
  - Vortex washed out over ember. Arms are sharper, and a new vortex_shroud piece (BLEND_MULTIPLY) darkens the lanes.
  - Prism read as wireframe boxes. Shards are tapered, the cross ridge and the caustic lines are gone, and the halo goes as the crystals thin out.
  - Shower was nearly invisible. 1600-1800 meteors with sd 0.17, and paths may graze bodies.
  - Battle ships were single-pixel dots. They are now lit hulls with drive glows and a capital ship, and the line gap is 105-130.
  - Giant: sizes 0.9/0.76/0.64, reach out to 185 (half off the frame's edge is allowed).
- Re-shoot of all eight is running: data/previews/sky_tour/*_sheet.png.
- Quick checks (event_tour.py --quick 0.3,0.55). The tool closed and reopened twice for Last Light. 0 runtimes, 0 MC alerts, 1 hard delete (/mob/dead/new_player, the lobby mob, not sky).
  - Second pass: sky_clearance takes lavaland=FALSE for the giant's ring tips (they may tuck 80 px behind Lavaland; the disc may not). Meteor aims keep off Lavaland only, since they're drawn over the sun and world. The remnant now grows to 0.7, then 1.1.
  - Final frames: data/previews/sky_tour/all_events.png (one per event) and data/previews/sky_tour/<kind>_sheet.png.
  - Open: the sky turns during a round, so Lavaland moves after an event is placed. The giant drifted half behind it in one run.
