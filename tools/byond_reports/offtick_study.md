# Off-tick study: what subsystem work can leave BYOND's main thread

2026-11-28. Branch `fast-atmos` working tree, including the other session's uncommitted engine fixes (atmos follow-up yielding
through `SSair.tile_engine_pending`, path forget tracking, light sprites under `data/lightmaps/<port>`). BYOND 516.1689.
This is a study only: no game code was changed and nothing was committed.

## Short answer

Very little tick time can move. Every native engine is already a small share of its own subsystem. The cost that is left is
DM-bound: proc calls, reading atoms, writing gas lists and appearances. A worker thread cannot do any of that, because byondapi
is main-thread only. The most a worker could take is the compute inside the existing `call_ext`s. Even the measured upper bound
of that is under ~10% of SSair, ~20% of SSlighting, ~15% of a bot path search, and ~2% of an explosion's set-up. A real design
would get less, because the engines go back and forth with DM inside one tick.

Recommendation: do not build a general off-tick framework. The one candidate worth a prototype is atmos tick pipelining. Build it
only if a 4 ms/fire cut on disaster ticks matters, and accept that the design is hard to get right. Spend the effort on the
DM-bound costs listed under "Better targets" instead.

## How it was measured

Every server ran on its own dmb or port and never used `hippiestation.dmb`. Each one was closed afterwards, and none are left
running. Other sessions had 2 to 9 `dd.exe` running on the machine at the same time (16 logical cores), so absolute ms are
somewhat noisy. Shares within one run are reliable.

| Tool | What it gave |
|---|---|
| `tools/bot_gym/run_stress_bench.sh run offtick 1` (JOBS=1, saved build `data/stress_builds/run-offtick.dmb`) | exact per-subsystem ms per game second for 11 phases (40 bots, plasma fire, breaches, meteors, maxcap, tesla), plus the tile engine's pack/native/apply split |
| `tools/bot_gym/shift_profile.py` on that run's `profiler.json` | proc self/total split (world.Profile at PROFILE_DUTY, see the note below) |
| `tools/atmos_bench/run_atmos_bench.sh profile` (DMB=run-offtick) | SSair stages per fire for calm, gas release, plasma fire and breaches, plus a profile of react/update_visuals/hotspot_expose |
| `tools/lighting_bench` `lighting-bench=sections` (dd on a scratch dmb) | where a lamp update goes |
| `tools/path_bench/run_path_bench.sh` | library time against DM tile-answer time per search |
| `tools/map_engine/run_check.sh` | DLL against json_decode against DM object time per map parse |
| boot lines in the stress run's `runtime.log` | lobby build stage times |
| scratch probe (scratchpad only, not in the repo) on a scratch dmb | explosion set-up split: gather, blocks, grid, `path_blast`, map back |

`devkit toolfind` found nothing for this beyond the project's own benches. `probe` was not needed, because no stall needed
sampling. `hippie_prof.dll` could not be used: it refuses BYOND 516.1689 ("unsupported BYOND build (BYOND build 1689)"), so
SSprofiler fell back to world.Profile at 10% duty on every server. That adds about 255 ns per proc call, which inflates the DM
side and leaves native time inside `call_ext` as it is. The DM shares below are therefore upper bounds, and the native shares
lower bounds, which only strengthens the conclusion.

## Per candidate

The "movable" figure is the native time inside `call_ext`. It is an upper bound, since it also includes the byondapi list
reads and writes, which have to stay on the main thread.

### 1. Atmos tile sweep (`tools/atmos_engine`, `tile_engine.dm`)

Measured, stress bench (ms per game second; SSair fires ~1.9-2.0 times a second):

| phase | SSair | tile pack (DM) | tile native | tile apply (DM) | of apply: air write | machinery (DM) | high pressure (DM) |
|---|---|---|---|---|---|---|---|
| calm | 11.8 | 0.9 | 0.5 | 0.9 | 0.7 | 5.2 | 0.4 |
| plasma fire | 16.9 | 1.2 | 0.9 | 1.9 | 1.4 | 7.3 | 0.6 |
| hull breaches | 44.7 | 3.2 | 3.5 | 11.1 | 8.8 | 14.5 | 3.5 |
| maxcap | 80.6 | 4.7 | 8.1 | 23.3 | 19.9 | 21.9 | 14.7 |
| tesla | 78.0 | 5.3 | 7.3 | 18.9 | 16.1 | 19.2 | 14.4 |

The atmos bench, per SSair fire, gives the same picture. In the plasma fire, of 11.94 ms the engine itself took 1.05 ms (9%),
packing 0.62 ms and following up 2.79 ms. Hotspots took 0.84 ms and machinery 2.69 ms. In the breaches, of 15.87 ms the engine
took 1.33 ms (8%) and following up 4.26 ms.

- Native share: 4-10% of SSair, which is at most ~4.3 ms a fire on the worst phase (maxcap: 8.1 ms/s at 1.9 fires/s).
- The reviewer's claim is partly refuted. The follow-up is the cost, but `react()`, `update_visuals()` and `hotspot_expose()`
  are not where it goes. In the whole atmos bench profile, `react` is 0.014 s self, `update_visuals` 0.05 s and
  `hotspot_expose` 0.002 s, against `tile_engine_write_air` at 0.113 s self. In the stress phases, "apply react/redraw/hot"
  never passes 1.1 ms/s. The follow-up is the air write-back (`apply air`, 76-86% of apply). That is
  `atmos_engine_write` putting changed gases into DM's gas_mixture lists through byondapi, which can only happen on the main
  thread.
- It is also not one clean compute. Each fire makes ~20 `run` rounds on maxcap (#rounds 38.9/s), and between rounds the
  engine asks DM to pack turfs it lacks (status 2). A worker can only run the stretch after the last round's inputs are in.

Design sketch (pipelining). At the end of fire N, once `results` and `write` are done, DM calls a new `atmos_engine_launch(fire N+1)`.
The engine copies its own kept air and state, which it already holds through `atmos_engine_kept_air` and own=on, and starts the
sweep of N+1 on a worker from that snapshot. Between fires, every DM touch of a turf's air (`air_touched`, `TILE_EVENT_*`)
already goes into `tile_engine_events` and `touched`/`dirty`. At fire N+1, DM sends those as usual. The engine then
throws away the worker's result for every turf touched since the snapshot, and for its neighbours out to the sweep's reach.
It re-runs those on the main thread through the existing rounds, then hands back results as today. Double-buffered air is
the engine's own two copies. DM's lists stay the only DM-visible air, written once a fire as now.

Failure and fallback: if the worker is not done by fire N+1, join it, which costs the same as today's in-line run. If too
many turfs were touched (a bomb), drop the worker's result and run in line. A panic on the worker shows up as an error status
in `run`, and the existing `tile_engine_failed()` hands everything back to LINDA. A run with `atmos-engine-pipeline=check`
should compare the pipelined result with the in-line one, the way the shadow modes do.

Risk: high. Correctness depends on noticing every DM write to air between fires, and the events path is already the
fragile part. A missed touch gives one fire of wrong air, which is silent and spreads. The gain is ≤ ~4 ms per fire on the
worst ticks and ~0.5 ms on a calm station.

### 2. Lighting corners and falloff (`tools/lighting_engine`, `lighting_engine.dm`)

Measured. SSlighting is 3.5-41 ms/s, peaking in aurora and grid check, and ~17 ms/s from calm on. In the profile, lighting is
2.73 s self. Of that, `lighting_object/draw` is 1.19 s (DM appearance writes, 193k calls), `native_draw` 0.75 s self (this
includes the `lighting_flush` call and the DM loop over its output), `native_update` 0.178 s self (almost all of it the
`lighting_update` call, 14 µs a call), `can_wait_unseen` 0.29 s and `update_eyes` 0.28 s. In the lighting bench, a whole
forced lamp update is 30 µs and relighting all 6,692 lights is 98-101 ms. `view()` alone would be 177 µs a lamp, but that is
already native by default.

- Native share: `native_update` is ~7% of lighting. Part of `native_draw`'s self is native too, but the split could not be
  measured without instrumenting the DLL. Upper bound ≤ ~20% of SSlighting, which is ~3.5 ms/s on average and ~8 ms/s in the
  aurora.
- Design sketch: `lighting_update` becomes "queue the request". A worker works out the corners, and `lighting_flush` on the
  next fire hands back what is finished. Lights would land one SSlighting fire late (~one tick), which no one can see.
  Fallback: anything the worker has not finished, the flush computes in line. On an engine error, the existing
  `native_failed()` hands lighting back to the DM code.
- Risk: medium. The engine keeps corner state across lights, so concurrent updates to overlapping corners need the worker
  to own all of it, and that makes `lighting_object` queries (`byond:lighting_object`) wait on the worker. The gain is small,
  and the cost that actually dominates is `draw()`, which stays.
- Sprite PNG encoding (`sprites.rs`): this is not on the round's path. Light textures are off unless `lighting-render` is set,
  and each picture is an 11x11 PNG with stored (not compressed) deflate, so encoding is microseconds. If the textures are
  turned on, the DM side (loading the file as an icon and setting appearances) will be the cost. Not worth threading.

### 3. Bot path searches (`tools/path_engine`, `bot_path_engine.dm`)

Measured, path bench, 600 searches each. Strict searches: 855 µs a search, of which the library is 129 µs (15%) and telling it
about tiles 658 µs, over 46.6 rounds a search. Permissive weighted searches: 1,522 µs a search, of which the library is 145 µs
(10%) and tiles 1,295 µs, over 49.5 rounds. In the stress profile, `path_engine_rounds` is 2.65 s self and 5.7 s total, the
largest single proc.

- Native share: 10-15%, split across ~47 round trips. Each round blocks on DM answering the tiles the engine just asked about,
  so nothing can run ahead on a thread. A worker helps only for searches whose every tile is already in the station picture.
  Even then the win is ~130 µs a search, at the cost of one tick of latency for the bot.
- Recommendation: no thread. The cost is DM's tile answers (8-13 µs a tile), and the fix for that is the station picture
  caching more tile kinds, which is bot AI work and outside this study.

### 4. Explosion shapes (`path_blast`, `explosions_shape.dm`)

Measured with the scratch probe on the real station (ms a blast, set-up only):

| size | tiles | gather | blocks (DM) | grid (DM) | path_blast (native) | map back (DM) |
|---|---|---|---|---|---|---|
| medium, range 8 | 289 | 0.09 | 1.39 | 0.12 | 0.10 | 0.15 |
| maxcap, range 20 | 1,681 | 0.38 | 7.40 | 0.67 | 0.22 | 1.18 |
| admin, range 50 | 10,201 | 2.13 | 56.2 | 4.70 | 1.32 | 20.1 |

In the stress run, the explosion subsystem is 3.5-20 ms/s (tesla), and in the profile `SSexplosions.hit` totals 1.06 s against
0.026 s for `explosion_shape` (ex_act and the hits themselves dominate).

- Native share: 2-3% of the set-up, and well under 1% of an explosion overall. Making it async would save 0.2 ms per
  maxcap and delay every blast by a tick.
- Recommendation: no. The real cost of the set-up is `CaculateExplosionBlock` at 7.4 ms per maxcap. It is DM reading every
  atom's `explosion_block`, and a per-turf cached block, updated on change, would cut it. That is not threading work.

### 5. Map parsing (`tools/map_engine`, `map_engine.dm`, `lobby_build.dm`)

Measured. For `hippiestation.dmm`, the DLL takes 37 ms, `json_decode` 63 ms, and the whole parse with the model cache 231 ms.
Loading it takes 680-791 ms. For Lavaland, the DLL takes 14 ms and `json_decode` 51 ms. Over all 208 maps, the native parse
part is 2,637 ms against 11,647 ms in DM. At boot, the station load is 0.79 s, Atoms 5.2 s, and the lobby build 11.1 s (atoms
6.35 s, air 1.43 s, lighting 1.79 s, Lavaland load 0.43 s, ruins 0.78 s), all of it already off the round's critical path
during the lobby.

- Native share: 37 ms out of a ~0.8 s station load, once a boot. `json_decode` and instancing are DM.
- Design sketch, if ever wanted: start `map_parse` for every planned map on a worker at `world/New`, and have `load()` collect
  the finished JSON. Fallback: parse in line if it is not ready.
- Risk: low. Gain: ~50 ms of boot. Not worth the code.

### 6. The rest: statpanels, timers, GC, overlays, tgui

These are confirmed DM-bound for what can be measured headless. In the profile, timers are 0.32 s self, GC `Queue` and
`HandleQueue` 0.64 s, overlays 0.32 s, tgui 0.01 s and icon smoothing 0.05 s. All of that is DM proc execution on atoms, with
no pure compute in it. This bench has no clients, so statpanels, tgui pushes and BYOND's own map sending were not exercised.
Those are BYOND-internal or built from atom vars, and none can leave the main thread from our side. "Outside" time (real time
not in any subsystem: procs waking from sleep, BYOND's own work) was 17-70 ms/s, and it is not reachable either.

## Existing threaded examples: patterns to copy

- `tools/log_writer` (a queue under a Mutex, a writer thread that polls every 20 ms, never woken per line). Lesson: waking a
  thread per item costs more main-thread time (1.4 µs a line) than the work. A pipelined engine should likewise never signal
  from DM. It should start the work at the end of a fire and collect it at the next one.
- `tools/dashboard` (a server thread that owns the sockets and reads the latest snapshot under a Mutex; DM only pushes JSON).
  Lesson: the worker owns everything it touches, and DM only hands over copies.
- `Byond_ThreadSync` exists in 516.1689's byondcore (its export was checked). Use it only to post a "done" flag. A collect at a
  fixed point (the next fire) keeps the result deterministic and matches how the MC already yields. A callback landing at
  some random moment in the tick does not.

## Ranked recommendation

1. **Atmos tick pipelining.** This is the only one worth a prototype, and only if disaster ticks matter enough. Gain: ≤ 4 ms
   per SSair fire on maxcap/tesla, ≤ 1 ms in fires, ~0.5 ms calm. Risk is high (missed air touches). It needs an
   `atmos-engine-pipeline=check` mode before anything else.
2. **Lighting async corners.** Gain ≤ ~3.5 ms/s on average and ≤ ~8 ms/s in an aurora. Risk is medium. Lights land a fire late.
   Prototype only after the DLL is instrumented to split `lighting_flush` into compute and list writes, so the bound is
   tightened first.
3. **Map pre-parse at boot.** About 50 ms a boot, low risk, not worth it.
4. **Explosion shapes, path searches, light sprite PNGs.** No: these are 2-15% of their own work, and that work is already
   tiny (explosions, sprites) or split by DM round trips (paths).

## Better targets, measured along the way (not threading)

- Atmos air write-back: `apply air` is 19.9 ms/s on maxcap and 8.8 ms/s on breaches. Write fewer gases, or fewer turfs a fire,
  for example by writing turfs nobody reads lazily.
- SSair machinery (up to 21.9 ms/s) and high pressure movements (up to 14.7 ms/s): DM.
- `lighting_object/draw` is 1.19 s of the lighting's 2.73 s: appearance churn.
- `CaculateExplosionBlock` is 7.4 ms per maxcap and 56 ms per range-50 blast.
- Path DM tile answers are 77-85% of a search.
- Tesla phase: Throwing 32 ms/s, Objects 32 ms/s, worst tick 188 ms.

## Side findings

- `hippie_prof.dll` refuses BYOND 516.1689. Its table has offsets for 1666 and 1688 only, so every server on this BYOND is
  back on world.Profile at 10% duty. `tools/hippie_prof/find_offsets.py` should find the 1689 offsets.
  (`hippie_prof.c` is being edited by another session right now.)
- The lighting bench (sections, on this working tree) reported "relighting everything: 749 TILES DIFFER from how they
  booted", and the same for the bounce toggle and the restamp, plus "1 lighting corners in the world". This is not from the
  uncommitted edits. A clean `HEAD` (15a5694b) build in a scratch worktree, with the same config and DLLs, gave 723 and 731
  tiles differing, against 749 and 736 on the working tree, and it printed the same "1 lighting corners" line. It was already
  there before these edits, and its cause was not looked into.

Raw outputs: `data/logs/shift_batch/stress-offtick/run1/` (stress.txt, stress.json, profiler.json). The saved build is
`data/stress_builds/run-offtick.dmb`.
