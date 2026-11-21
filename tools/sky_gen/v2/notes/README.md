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

## Ratings at hand-over

Nebulae 8.5-9.5. Events: vortex 9, prism 8.5, shower 8.5, battle 8.5, aurora 8.5, giant 8, supernova 8, breakup 7.5.
Bodies 9.5. Twinkle unseen twinkling in the engine.

## Open items

- The sky turns during a round, so Lavaland can drift over an event placed earlier (the giant went half behind it once).
  Placement should use where Lavaland will be over the event's length, not where it is.
- Nebulae: ember, violet and verdant only 18-23% black sky; the band rift (stars.py) reads speckled in gold and quiet;
  nebulae slide at 0.42-0.58 while the band slides at 0.2, so gas leaves the band as a player walks.
- Supernova reads weakly early; breakup got only two checked frames.
- tools/testkit/client_lane.py close() sets split.splitter=66, but that control can't be reached on this skin: a no-op.

## Rules learned

- Real-client shots: fixed spot [110,60,2] on testbench, seed 5, maximized window, stretch-to-fit (what Keegan plays),
  10 fps; the test client logs in as Keegan's key and the map zoom is saved per key, so client_lane.close resets it.
- Never leave a testkit server or DreamSeeker up idle: Last Light's reserved timed runs wait for a quiet machine, and a
  session waiting on gpu_share with its own idle server deadlocks everyone. `devkit dk.py gpu` names the blocker.
- Fewest runs that prove it; one server and client at a time (Keegan, 2026-11-21).
