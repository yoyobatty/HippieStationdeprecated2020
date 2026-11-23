# mapforge: plan for the full station generator

Written 2026-11-22. From a seed and a crew size, the generator builds a whole SS13 station: any shape the human
stations use, any size from MiniStation to Delta. It must be as good to look at and play as MetaStation,
DeltaStation, OmegaStation and HippieStation, and pass its gate with no failures. This plan reuses what the v6 station
proved on 2026-11-22: the gate, copying stock rooms, stock dressing habits, the wall-piece tidy, and cause-finding by
ablation. It replaces the guessed shapes of the old pinwheel/spine/ring layouts with targets measured on 38 human maps.

The earlier plan (`perfect_generation_plan.md`) still holds for the judges and the bar. This plan says what to
build, in what order, with what numbers.

## 1. The targets, measured

Five new studies in `tools/mapforge/studies/` read every human map in `parse.humans()` (38 maps, 32 families). Each
family counts once, so remakes like Meta on tg, bee and paradise don't outvote the rest. A band is the 10th..90th
percentile over families. Results are cached in `data/mapforge/gen_targets/`, and `--map <dmm>` checks a build
against the bands.

| study | what it gives the generator |
| --- | --- |
| `skeleton_types.py` | the hall skeleton: type, core loop, spokes, spine length, hall share, aspect (`--picture`: contact sheet) |
| `dept_scaling.py` | floor from crew; each department's floor from the station floor; rooms per department |
| `dept_adjacency.py` | which departments touch (P(adj), P(door), lift), radial position, where doors lead, maint skin |
| `space_sizes.py` | hall and maint width mix, straight hall runs, maint pockets, room size quantiles, room shape, one-door rooms |
| `stamp_supply.py` | stock rooms to copy per type: on the four look maps and in the corpus, with sizes |

`corpus_common.py` holds the shared parts: the map list with families, the per-study cache, bands, power fits, and
the crew count. The crew count is job start landmarks only: no assistants, AI, cyborgs, prisoners, depsec copies or
tg's hangover spawns. parse.crew counted tg Delta at 635, because 463 of its landmarks are hangover spawns.

### 1.1 Skeleton (`skeleton_types.py`)

Types by family (32): **hub 19, hub-donut 5, spine 3, tree 2, islands 2**, and 1 untagged (Nebula doesn't put its
halls in /area/hallway). Contact sheet: `data/previews/mapforge/gen_targets/skeletons.png`.

- **hub** (Meta, Delta, Box, Hippie, Pubby, Yog, Manatee...): a small hall loop at the centre with spokes out to
  the edge.
  - The loop holds 0-11.5% of the floor (median 3.7%).
  - Its centroid sits within 0.17 of the radius from the station centre.
  - Inside the loop, over the 30 hub maps: command in 18, maint in 12, service in 9, AI in 6, engineering and civic
    in 5 each.
- **Spokes:** median 3 (p90 6). Median walk from the loop to a spoke's end is 38 tiles (p90 62). Spokes reach 0.50
  of the radius (p90 0.64).
- **hub-donut** (Donut, Kilo, Omega, Cere): a wide round loop that holds 10-17% of the floor, with the departments
  round it. Median 2 spokes.
- **spine** (Cardinal, Cog, Tram): no central loop. The hall centre line runs 0.85-0.96 of the long side.
- **Whole station:**
  - Hall share (hall + arrivals + escape) is 0.130 / 0.158 / 0.210 (p10 / median / p90).
  - Aspect is 0.76-0.96 (near square), and the floor fills 0.24-0.36 of the station box.
  - 77-100% of hall floor is in one piece.
  - The hall centre line runs 0.68-1.01 of the long side.
  - Hall + maint close 2-16 loops (median 8): maint is the second network.

### 1.2 Size and share against crew (`dept_scaling.py`)

- **Floor and crew:** floor = 228 * crew^0.81 (r² 0.47). Crew explains only half of the size, so the seed picks the
  floor from the band round the fit.
  - Floor per job slot: 64 / 101 / 139.
  - Rooms per 1000 floor tiles: 15.0 / 19.0 / 23.3.
- **Departments are fixed kits that grow slower than the station.** tiles = a * floor^b with b = 0.76-0.86 for
  command, medical, science, engineering, cargo, service and AI (r² 0.43-0.79).
- **Grows faster than the station:** maint (b 1.56, r² 0.63), security (1.18) and civic (1.17). A big station spends
  its extra floor on maint, the brig and public rooms.
- **Atmos is close to fixed:** b 0.56 (r² 0.30).
- Shares at the fit, for crew 30 / 80 / 160 (floor 3.5k / 7.8k / 13.6k):
  - hall 13.9 / 11.7 / 10.3%
  - maint 11.1 / 17.3 / 23.7%
  - security 7.7 / 8.8 / 9.7%
  - science 10.6 / 9.0 / 8.0%
  - engineering 8.6 / 7.5 / 6.8%
  - atmos 7.3 / 5.2 / 4.0%
  - medical 8.0 / 7.0 / 6.4%
  - command 5.5 / 4.6 / 4.0%
  The per-department fits add up to 96-99% of the floor, so they are consistent with each other.
- Share bands (p10 / median / p90):

  | department | p10 | median | p90 |
  | --- | --- | --- | --- |
  | science | 0.070 | 0.092 | 0.105 |
  | security | 0.066 | 0.092 | 0.121 |
  | engineering | 0.051 | 0.075 | 0.104 |
  | medical | 0.051 | 0.068 | 0.088 |
  | civic | 0.030 | 0.052 | 0.069 |
  | service | 0.038 | 0.048 | 0.072 |
  | atmos | 0.026 | 0.045 | 0.081 |
  | command | 0.035 | 0.043 | 0.060 |
  | cargo | 0.030 | 0.035 | 0.064 |
  | ai | 0.020 | 0.033 | 0.055 |
  | dorms | 0.014 | 0.031 | 0.046 |
  | hall | 0.083 | 0.114 | 0.162 |
  | maint | 0.146 | 0.208 | 0.297 |

### 1.3 Who sits next to whom (`dept_adjacency.py`)

Department security posts (`/area/security/checkpoint*`) count as their own group, so the brig isn't mixed up with
the posts inside other departments. The mean P(adj) over department pairs is 0.16.

- **Nearly always together:**

  | pair | P(adj) | P(door) |
  | --- | --- | --- |
  | atmos + engineering | 0.90 | 0.90 |
  | dorms + service | 0.79 | 0.74 |
  | civic + service | 0.76 | 0.24 |
  | civic + dorms | 0.63 | 0.37 |
  | AI + command | 0.50 | |
  | command + security | 0.44 | |
  | civic + security | 0.44 | |

- **Never or almost never (P(adj) 0.00-0.05):**
  - cargo with command or medical;
  - medical with atmos, service or AI;
  - AI with atmos, cargo, dorms, service or civic;
  - atmos with civic, dorms, cargo or command;
  - engineering with science or medical;
  - command with dorms.
- **Posts:** science, medical, cargo and engineering each have a post inside or beside them (P 0.57-0.65).
- **Radial position** (centroid over the radius, p10 / median / p90):
  - central: hall 0.09, service 0.20, civic 0.24, command 0.26, medical 0.30, dorms 0.33;
  - ring: engineering 0.41, cargo 0.41, security 0.43, science 0.43, atmos 0.46;
  - edge: escape 0.51, arrivals 0.56, AI 0.65 (0.33-0.81).
- Civic touches arrivals in 0.72 of families and escape in 0.66. Service touches arrivals in 0.38.
- **Outer doors** (median shares):
  - command opens to the hall (0.72);
  - medical, science and cargo open mostly to maint (0.56-0.62);
  - atmos has no hall door at the median (maint 0.50, other departments 0.50);
  - the AI opens to the hall (0.50) and other departments (0.42), and never to maint.

### 1.4 Halls, maint and rooms (`space_sizes.py`)

- **Hall width mix** (median share of hall floor): w1 2.5%, w2 5.4%, **w3 44%**, w4 12.6%, w5 8.7%, w6 2.5%,
  w7 2.3%, w8 2.9%, w9+ 11.9%.
  - The 9+ share is the lobbies and plazas.
  - Mean width is 3.9-5.3.
  - Straight hall runs have a median length of 10.5 (9.0-13.0).
- **Maint width mix:** w1 17%, w2 23%, w3 24%, w4 11%, w5+ 25%.
  - 30-68% of maint floor sits in open 3x3 blocks.
  - There are 1.8-5.9 maint pockets per 1000 tiles, median 21 tiles each (15-43).
- **Room size quantiles** (p10 / median / p90 over families):

  | quantile | p10 | median | p90 |
  | --- | --- | --- | --- |
  | q10 | 6 | 6 | 8 |
  | q25 | 9 | 9 | 12 |
  | median | 17 | 20 | 25 |
  | q75 | 29 | 38 | 47 |
  | q90 | 59 | 75 | 89 |
  | biggest room | 200 | 268 | 431 |

- **Room shape and doors:**
  - Rooms that fill their box: 0.40 / 0.52 / 0.59.
  - Room aspect: median 0.75.
  - One-door rooms: 0.34 / 0.38 / 0.45.
- **Median room size by department:** atmos 9, dorms 10, security 18, science 18, medical 21, AI 21,
  engineering 22, service 25, command 26, civic 31, cargo 32.

### 1.5 Stock rooms to copy (`stamp_supply.py`)

- **Room types:** 444 in all. 265 are "ready", meaning 3+ families have one; 126 of those have a copy on the four
  look maps.
- **Core types:** 78 types are on at least half the families, and 75 of them are on the look maps. The 3 that aren't
  are the medbay lobby, paramedic and interrogation.
- **Coverage:** 88-99% of each department's human room floor is of a ready type:
  - command 0.99, medical 0.97, security 0.96, science 0.96, cargo 0.96, dorms 0.96, civic 0.95, engineering 0.93,
    AI 0.92, service 0.90, atmos 0.88.

  So copying stock rooms can build almost every department. The rest is kits and fill.

### 1.6 Where today's builds stand on the new bands

Count of measures outside the bands, from the four `--map` checks:

| build | skeleton | shares | adjacency + radial | halls, maint, rooms | total |
| --- | --- | --- | --- | --- | --- |
| `station_v6_accepted` (46a3a40f) | 7 | 5 | 6 | 22 | **40** |
| `gen_pinwheel_c80_s1` | 8 | 6 | 7 | 28 | **49** |

- **v6:**
  - Hall share is 0.223, and 0.35 of its halls are 9+ wide; the lobbies are 0.12 of halls at width 7.
  - 62% of maint is 2 wide, with 0 at width 3.
  - 73% of rooms are rectangles.
  - Atmos is apart from engineering, dorms apart from service.
  - Spokes and arms are too long (arm median 43 against 15-20).
- **Pinwheel:**
  - Rooms are twice the human size (median 38).
  - 12 rooms per 1k tiles against 15-24; 52% are one-door rooms.
  - It reads as a hub-donut, with 7 spokes and a 0.15 core.

Neither was built to these targets. They are the before numbers for M1.

## 2. The generator, stage by stage

The new package is `tools/mapforge/gen/`, built as `gen/build.py --seed N --crew C [--shape hub|donut|spine]`. It
writes `data/mapforge/gen_<shape>_c<crew>_s<seed>.dmm` and gates the result.

The v6 files are not edited. Their generic parts are lifted into `gen/` after the v6 session commits, with the
v6-only parts made into parameters: the accepted areas in tidy, the plan coordinates, the hand blueprints.

Every stage writes its plan to a JSON. A later stage that fails sends the station back to the stage that owns the
fault, instead of making do.

| # | stage | input -> output | reuses | judged by (gate check, band) | seed varies |
| --- | --- | --- | --- | --- | --- |
| S0 | **Program** | seed, crew -> floor, shape, department budgets, room list | `dept_scaling` fits, `stamp_supply` prevalence | floor inside the fit's band; each budget = the fit at this floor; room types: every core type (50%+ of families) present | floor within the fit's residual band; shape drawn by family frequency (hub 0.61, donut 0.16, spine 0.10, tree/islands later); optional types by their prevalence |
| S1 | **Skeleton** | -> hall graph: core loop, spokes, arrivals/escape ends, maint loop seeds | `skeleton_types` measures, `station/shapes.py` arm tails as a proposal source | every `skeleton_types --map` feature in its band: hall share, core, core_dist, spokes, spoke_len, spoke_reach, spine, aspect, main, walk_loops | spoke count (2-6), angles, bends, loop size, which sides take arrivals and escape |
| S2 | **Department blocks** | -> one region per department between spokes, sized to its budget | `dept_adjacency` P(adj) as the score, `station/grow.py` growth for outlines | all pairs with P(adj) >= 0.6 touch; no pair with P(adj) <= 0.05 touches; radial centroids in band; shares in band; posts beside science, medical, cargo, engineering | the sector order: the top-k assignments by adjacency score; block outlines (growth seed) |
| S3 | **Rooms, stock copies first** | -> rooms in each block | `forge/room_stamp.py`, the `station/v6_rooms.py` packer and score, `size_budget`, `room_stats`, `forge/typeindex.py` (every copied path must exist) | `space_sizes` room quantiles, rect, one_door, rooms per 1k, per-department room size; `size_budget` 0 oversized and 0 missing; `style_bands` per room; `disc_rooms` no room reads generated | which stock example of each type (ready types give 3+ families), orientation (8), placement order |
| S4 | **Halls and maint fill** | -> hall widths, lobbies, maint runs, pockets, maint rooms | `v6_rooms.fill_maint`, `carve_open_maint`, the arterial-to-maint step, `open_dead_ends`, `close_corners` | hall width mix and straight runs, maint width mix, maint_pocket, pockets per 1k, pocket size; walk checks: dead ends, open maint, no hull corner joins, no solid wall filler | which stock maint rooms fill which pockets |
| S5 | **Networks** | -> power (grid, engine input, AI sat), air (chambers, distro, waste works), disposals, solars, docks | the `v6_station` passes: power, air, `atmos_works`, bins and disposals, stock solar rooms, `to_dmm.side_dock` | atmos faults 0 new, pipes stay seen, vents apart and off terminals, solars reached, disposals outlet by the waste outlet; boot (`run_zone_check.sh`): 0 runtimes, every vent on a network, docks dock | none needed: routing is deterministic from the plan |
| S6 | **Dressing** | -> habits, glaze, fixtures, details, polish, tidy | `station/v6_habits.py`, glaze, fixtures, details, polish, `station/v6_tidy.py`, `forge/look_wfc.py` later | `style_bands` bands, `piece_audit` (stacked, both faces, over furniture) ratchet, hull glass and inner glass in band | per-room and per-tile seeds (one random stream per room: the v6 lesson), station look rolls |
| S7 | **Gate** | -> PASS or FAIL list | `station/v6_gate.py` checks, `forge/walk.py`, `forge/fingerprint.py`, the five studies | see section 3 | none |
| S8 | **Play proof** (finalists) | -> boot and Bot Shift | `run_zone_check.sh`, `run_bot_shift.sh` | Meta's spread: APCs powered, crystal stable, evac boarded, failed path searches | none |

What each stage owns:

- **S0** turns the targets into a program. Each department's budget is the fit at this floor; the fits add up to
  96-99%. The room list is every core type, then optional types by prevalence, until the department's room count
  reaches its band. Sizes come from the type's stock size band.
- **S1** builds the hall graph first and measures it with `skeleton_types.measure()` before any geometry. A skeleton
  outside the bands is thrown away and redrawn with the next sub-seed; it costs milliseconds.
- **S2** places the departments. With 11 departments and 3-6 sectors, the assignment search scores every sector
  order: the sum of log(P(adj)) over the pairs that touch, plus the radial band, plus the arrival/escape pairs.
  The top-k orders become the seed's choices. Growth then fills each sector to its budget with ragged outlines.
- **S3** fills blocks with real human rooms. It generalises v6_rooms' score: stock size, distance to the room's
  department, a door out, the department's share. Within a type, the copy with the fewest wall-piece faults goes
  first (v6 lesson).
  - Sources are all 38 human maps (the user's ruling, section 6). That gives 265 ready types. The four look maps
    hold 75 of the 78 core types.
  - Rooms no stock copy fits are built from `forge/proc` kits and assets: the Science/Medical node graphs that
    scored "brilliant".
- **S4** owns the floor between rooms. Halls are drawn to the width mix (mostly 3 wide; lobbies and plazas take the
  9+ share). Maint is drawn to its own width mix, and pockets are filled with stock maint rooms. Wall filler is never
  used (the user's ruling).
- **S5 and S6** are the v6 passes, lifted with their lessons:
  - underfloor cable and pipe never count as taken;
  - assets never hard-code room shapes;
  - seeds are per room;
  - drawings are written by the Write tool or byte-safe Python, never a Bash heredoc.

## 3. The gate

`gen/gate.py` runs on every build, about 30 s, and exits 1 on any failure. It has three kinds of check.

1. **Hard checks.** These must be 0 or true: walk (every solar reached, nothing unreached, no maint-only rooms
   except stock-backed ones, no dead ends past stock, no hull corner joins, disposals outlet), atmos faults, pipes
   stay seen, vents apart and off terminals, every copied object path in `typeindex`, oversized 0, missing 0, no
   room the discriminator calls generated, solid wall filler within stock.
2. **Stock bands.** Every number from the five studies, plus the existing `v6_gate` stock checks and the
   fingerprint. A band is the union of the corpus p10..p90 and the min..max of the four look maps. The union makes
   every look map pass by construction: "as good as Meta, Delta, Omega and Hippie" means inside their envelope.
   - A pure p10..p90 band would fail 20% of human families on every check, and a human map would fail about 12 of
     60. Calibration is milestone M0's exit test.
3. **Ratchet per seed.** A regression set of fixed seeds (5 seeds x crew 40 / 80 / 120 x each shape built so far)
   keeps an accepted baseline per seed, as `gate_v6.json` does. A build may not be worse than its accepted twin on
   any room or whole-map number (`v6_gate.full_check` logic). `--accept` only after the user has looked.

A gate failure is traced by ablation, never by guessing. `gen/ablate.py` generalises `v6_ablate.py`: switch one
stage or pass off, rebuild the same seed, and diff the failure lists. Stages report the tiles they own, so a failure
names its stage.

## 4. How seeds vary the result, and the variety test

- **The seed chooses:**
  - the floor inside the band;
  - the shape, by family frequency;
  - the spoke count, angles and bends;
  - the arrival and escape sides;
  - the sector order (top-k by adjacency);
  - the block outlines;
  - the stock example and orientation for each room;
  - the maint fillers;
  - the look rolls.
  Everything below the program is seeded per room or per tile, so a change in one room doesn't reshuffle the
  station.
- **Variety test** (expressive range, plan B3): measure 50 seeds per shape on the skeleton features plus department
  order. Pass when two things hold:
  - the seeds cover at least the spread of the human families on each axis;
  - no two seeds are closer than the two closest human families. Meta and MetaLake are the same map, so the closest
    pair is taken over distinct families.

## 5. Milestones, each with an objective exit test

| milestone | build | exit test |
| --- | --- | --- |
| **M0 Targets and gate** | the five studies (done today), `gen/gate.py` with the band union, the regression seed list | the gate passes all 4 look maps with 0 failures; every band check passes at least 80% of the 32 families (printed per check); `--map` on v6 and pinwheel reproduces section 1.6 |
| **M1 Program + skeleton + blocks** | S0-S2, block-plan pictures | 15/15 builds (crew 40/80/120 x 5 seeds, hub): skeleton, share, adjacency and radial checks all pass; then pictures to the user (taste stop) |
| **M2 Rooms** | S3 | the same 15: rooms per 1k, room quantiles, rect, one_door, per-department room size in band; 0 oversized, 0 missing, 0 unknown paths; no room the discriminator calls generated; style_bands no worse than the v6 accepted build's medians |
| **M3 Halls, maint, networks** | S4-S5 | the 15 pass every hard check; 3 of them boot one at a time (`run_zone_check.sh`) with 0 runtimes, 0 new open pipe ends, every APC on a powered net, docks dock |
| **M4 Dressing + full gate** | S6, ratchet baseline | 15/15 gate PASS with 0 failures; before/after room sheets; the user looks, then `--accept` |
| **M5 Play and blind** | S8 | Bot Shift on 3 finalists inside MetaStation's spread (APCs, crystal, evac boarded, failed path searches); the blind test (`forge/blind.py`) at most 55% human picks at room, department, quarter and whole scale |
| **M6 Shapes and range** | donut, spine, then tree and islands; the variety test | each shape's 15-build set passes M1-M4's tests; the variety test passes over 50 seeds per shape |

Each milestone ends with a report of what was done and found, plus pictures where taste is involved
(`feedback_decide_the_how`: report, don't ask how).

## 6. Risks and open choices

- **Crew is a weak predictor** (r² 0.47). The floor band comes from the residuals, not a single number. Job slots
  per department (`dept_scaling` tiles/job) set the floor below which a department's kit can't shrink.
- **Copies carry human faults.** Human rooms stack wall pieces and hang them over furniture. Tidy fixes copied rooms
  (v6 iteration 4), and the per-type pick prefers the copy with the fewest faults.
- **Paths from other codebases.** `alias.py` maps areas and wall pieces, but bee, yog, paradise and citadel objects
  may not exist here. The typeindex check makes a copy that has them fall back to a look-map example.
- **Goodhart.** Matching bands can give a statistical copy with no purpose. Hard checks and play judge function
  first, and bands only choose among maps that already work (earlier plan, section 6).
- **Shared PC.** Python stages only, until M3. Boots and Bot Shifts are one server at a time, on finalists only.
  Wait with `tools/gpu_share.py wait` first.
- **Stamp sources: all 38 maps** (the user's ruling, 2026-11-22: "All 38 maps"). The look maps alone cover 75 of the
  78 core types (126 ready types). Copies from the whole corpus raise that to 265 ready types. A copy whose object
  paths don't all exist here (`typeindex`) falls back to another example of its type.

## 7. Progress log

### M0, 2026-11-22: targets and gate (done)

- `gen/gate.py --calibrate`: **PASS, 0 of 128 checks fail the M0 test.**
  - Every look map passes every band, pair and stock-bounded hard check.
  - Every band check passes at least 80% of the 32 families. The lowest are 81%, by construction.
- **Band rule, a decision from measurement.** An interpolated p10..p90 left only 75% of 32 families inside on 20
  checks. The gate drops the int(0.1 n) most extreme families at each end instead (3 of 32), then joins the look
  maps' min..max.
- **Pair rules from the corpus:**
  - must touch (P >= 0.80 and all four look maps): atmos + engineering;
  - never touch (P <= 0.05 and no look map): 23 pairs, e.g. cargo + command, AI + medical, engineering + science.
- **RULED checks fail on stock maps, as expected for rulings:**
  - pipes stay seen: all 4 look maps;
  - apc areas: 3;
  - vents apart: Omega;
  - vents off terminals: Meta.
- **On today's builds:**
  - `station_v6` (= the accepted build): 16 of 129 checks fail. Hall widths, maint widths, rect rooms, the arm and
    spoke lengths, fill, atmos-engineering apart, and per-department room sizes.
  - `gen_pinwheel_c80_s1`: 41 fail.
- **Known paths:** `forge/typeindex` misses the pipe types the HELPER macros declare (mapping.dm). The gate expands
  them, so v6's layer1/layer3 pipes no longer read as unknown.

### M1, 2026-11-22: program, skeleton and department blocks (9 of 15)

`gen/program.py`, `gen/blocks.py` and `gen/build.py` build a hub block plan from a seed and a crew. On the regression
set (hub x crew 40/80/120 x seeds 1-5, 50 tries, repair 150):
- **9 of 15 pass every block check:** 69 checks covering skeleton, shares, radial places, adjacency log-likelihood
  and pairs.
- **The other 6 fail one check each:** radial security (2), atmos, service; spoke walk (2, crew 120).
- About 1-5 min a seed, CPU only, after `tools/gpu_share.py wait`.
- Contact sheet: `data/previews/mapforge/gen/sheet.png`.

Decisions, each from a measurement:
- **The test range.**
  - On Meta, Delta, Omega, Hippie and Box the toxins test range (12-25 tiles) sits at 0.86-0.98 of the station
    radius. It is often the farthest floor, so it sets the radius every radial place is measured by.
  - The block plan places it; its distance (outpost) is a tuned number.
- **4 spokes for M1.**
  - With 2-3, the slot layout queues blocks single file along a spoke: walks ran 66-98 tiles against the human 62
    max.
  - A 2-spoke hub (Meta) puts departments on the bare loop sides; that is M6 work.
- **Corners.**
  - Inner departments wrap the loop corners as L blocks, only those whose radial band reaches 0.2.
  - Engineering never takes a corner: atmos must touch it, and only two blocks in a row guarantee that.
  - A corner block may hold no more than about 18 rows over the corner's width.
  - Corners are given out after the spoke blocks stand, nearest the station's centroid first.
- **Spoke blocks.**
  - Blocks are deep and short (length/depth 0.45-1.1).
  - A spoke side's second block goes in a second row once the walk would pass 42.
  - Notches between touching blocks go back to the department, not to maint.
- **Lopsided by design.** Load balancing is off: human hubs sit 0.08-0.17 of the radius off their centroid, and
  the hall's centroid 0.05-0.13 off.
- **Search.**
  - Of the slot search's top 10 assignments, each is placed for real and the one whose placed numbers miss least
    is kept.
  - Then nudges between tries.
  - Then a seeded local search (repair) on failures plus band distance.

### M2, 2026-11-22: rooms by stock copies (in progress)

- **Library.** `gen/stamps.py`: 1381 copyable rooms of 135 types in 3+ families; 76 of the 78 common types.
  - Other codebases' paths are renamed, dropped (mapping helpers, nav landmarks, their extra items) or resolved to
    a known ancestor.
  - A bare base type is never used: it drew magenta.
- **Packing.** `gen/rooms.py` fills each block with copied rooms, 3-12 per department.
  - Department corridors take 8-25% of a block and their own area.
  - Corridor pieces over 120 tiles become walled maint pockets.
  - Atmos gets its gas chambers.
  - One-door rooms get a second door down to 40%.
  - Atmos and engineering get a door through their shared wall.
- **Crew 80 seed 4, room stage.** Every room check passes: sizes, quantiles, rooms per 1k, oversized,
  core types, known paths, and the atmos-engineering touch.
  - Hall width mix still misses: the plan has too few hall segments, so a few random width draws swing it.
  - Maint width mix still misses.
- **Next:** widths allocated per segment to the human mix (spoke widths 3/3/4/5, a 2-wide T arm with a 1-wide
  tail, 7-wide then 9+-wide lobby tiers), then the room-stage set.

### M2 status at the end of the night (2026-11-22)

- **Gate change, from a count.**
  - With one band per width bin (9 hall + 9 maint), the median human map failed 10 band checks; only the four look
    maps passed all, by construction.
  - Each width mix is now one check: total-variation distance of the map's histogram to the human median
    histogram, in a trimmed + look band (hall 91%, maint 84% of families inside). Per-bin numbers stay in the report
    as info.
  - Calibration: PASS, 0 of 130.
  - Under the new rule the median human map fails 7 checks (p25 4, max 26).
- **Room-stage set** (15 builds, `data/mapforge/gen_rooms/`, 101-117 checks: bands, pairs, core types, oversized,
  known paths, wall filler):
  - 2 pass all: crew 40 seed 4, crew 80 seed 5.
  - 13 fail 1-5 each, every one at or under the median human map's 7.
  - The repeat failures, each fixed since at its cause (not yet re-run on all 15):
    - a department's corridor pieces joined by room_stats into one oversized room;
    - small civic rooms;
    - atmos-engineering more than 4 walls apart at crew 120.
- **Discriminator v7** (CUDA, `data/mapforge/disc/v7`, after `tools/gpu_share.py wait`):
  - Data: 38 human maps against 19 generated (pinwheel, ring, spine, station_v6, the 15 hub room builds).
  - Folds hold out whole families, so the hub builds were judged by a network trained on no hub build.
  - Hub builds: 48-90% of crops called generated (mean logit +0.7 to +5.4), fold AUC 0.97.
  - The older generators: 100% (+7.5 to +7.9).
  - station_v6: 2%.
  - Per room (`forge/disc_rooms.py`, crew 80 seed 4): the copied stock rooms themselves read 100% generated, and so
    do the halls. The tell is what the generator does not add yet, not the room interiors: no lights, vents,
    firelocks, decals or cameras in halls, no pipes or cable, the plain hull. That is M3 (networks) and M4 (the v6
    dressing passes).
- **Next, in order:**
  1. Re-run the 15 room builds on the fixed code.
  2. M3: lift v6_station's power, air, disposals, solars and docks passes into gen/, then boot checks one at a
     time.
  3. M4: the dressing passes (habits, glaze, fixtures, polish, tidy).
  4. Retrain the discriminator after each and watch the hub builds' share of tiles called generated fall.

### M2-M3, 2026-11-22 later: speed, the full stage, and what the trace measured

- **Speed** (profile): the block gap check kept per department, 4 candidates instead of 10, repair stopping after
  30 steps without gain, and room rounds that re-furnish instead of re-searching. The 15-seed room set went from
  105 min to 15-30 min with `--jobs 5`; workers stay warm (furnish 22.6 s cold, 1.7 s warm).
- **Full stage** (`build.py --stage full`: rooms, `gen/dress.py`, `gen/connect.py`, every check but the disposals
  outlet): 0 of 15 passed, 3-11 failures each.
- **`gen/trace.py`** applies each pass in turn to a furnished map and gates after each. Over 5 maps:
  - The room stage leaves 13-48 areas reached only through maint, and 400-900 floor tiles unreached: maint networks
    with no door to a hall, and second-row blocks with no hall of their own.
  - connect.py reaches them (unreached floor 872 -> 43, maint-only areas 45 -> 3-13), but its 45-67 rescue doors
    give rooms second ways in. The one-door share falls 0.34-0.42 -> 0.20-0.31 on every map.
  - shared.py's vents clash with the copied rooms' vents; dress.vents_apart clears that.
- **Conclusion: the cause is top-down packing.** Rooms are cut into pre-made department blocks; the leftover
  corridor, pockets and unreachable pieces are then patched, and each patch moves another number.

### Next: departments built bottom-up (the user's suggestion, 2026-11-22)

The idea: a map as a graph of nodes, built from the bottom up by combining structures into bigger ones up to the
root, with the space between filled from nearby terrain by Dijkstra.

Applied here, keeping what passes (S0 program, S1 skeleton, the slot order of S2):
1. **Department as a structure.** Its rooms (stock copies) are composed around a corridor graph:
   - each room's door attaches to the corridor;
   - the rooms humans join (surgery beside treatment, the server room beside R&D) join;
   - one end of the corridor is the hall front.
   - The department's footprint is the union of what its rooms need. Nothing is left over, so there are no
     corridor scraps, every room is reached from the hall, and doors come only from the rooms' own.
2. **Station as the root.** Each composed department is placed at its slot on the skeleton (radial place,
   neighbours), turned to face its spoke.
3. **Fill.** Space between departments is filled by multi-source Dijkstra from the hall and department edges:
   - within 1-3 tiles of two different departments: maint, which links to the nearest hall by construction;
   - farther out: space.
   - That gives the maint width mix and its loops.
4. **Judged as now:** `gen/gate.py` and `gen/trace.py`. Exit test: the trace's two shared failures (ways in,
   one-door share) gone on all 5 trace seeds, with no new failure.

### M2-M3, 2026-11-22 night: bottom-up departments built (`gen/compose.py`)

`build.py` uses it by default; `GEN_ROOMS=topdown` keeps the old packing (`gen/rooms.py`). Commit 78fc76a8 plus the
fixes after it.

**How it works:**
- **A department is composed in its own frame** (x along its hall front, y away from it).
  - The whole corridor is planned first and kept free of rooms: a stem from the front, with branches across it when
    the frame is 32+ wide or under 30 deep.
  - Stock copies are attached nearest the front first. Each goes on with a door cell of its own wall on the
    corridor wall, the copy's own door where one lands there. Of those fits, the tightest wins.
  - Three stem positions are tried (the seed's, low end, high end); the one with the most floor wins. One deep side
    is what fits engineering's main room.
  - The corridor is cut back to its last door. A closed pocket beside the corridor becomes an alcove, up to the
    corridor's cap.
  - The corridor is capped at 0.85 of its area type's biggest look-map room: it is a room to room_stats.
  - A small-room pass follows while the department's median room size is over its band.
- **Placed at the slot** from `blocks.Layout` (core, spoke sides, corners, past a spoke tip), turned to face its hall.
  - A spoke department is composed at most 1.4x its slot's depth, then widened 20% at a time.
  - The command core box is the composed footprint.
- **Fill:** a multi-source search from department edges and halls.
  - Maint where two departments are within 3 tiles, or a department and a hall within 2.
  - Each maint piece is joined to its nearest hall by the shortest path through space.
  - Maint no hall reaches is dropped.
  - Then runs and pockets up to the maint budget, as before.
- **Doors last, measured on parse regions:**
  - room pieces no walk reaches get a door to their own department (never maint); a window becomes the door as a
    last resort;
  - closets of 1-3 tiles with no such wall are walled;
  - then second doors to a room of the department, the hall or maint, until the one-door share is 0.39.

**Decisions, each from a measurement:**
- **The two failures were caused by connect.** Its rescue doors gave 2-tile stock closets a maint door ("ways in"),
  and its doors into rooms pulled the one-door share down. With every piece reached before connect runs, connect
  cuts 0-6 doors a map (it cut 15-67 before).
- **Second-row side halls are off.** A department behind another got a side hall of its own: those ran 50-64 tiles
  against the human arm's 19.5 max, and spokes ran to 80.
- **Even-width spokes are drawn exactly over lo..hi.** `blocks.Layout._strip` put N and W spokes one cell over, so a
  department composed against lo-1 fronted onto nothing.
- **Enclosed voids are no longer wall:** as wall they were 59 tiles of solid filler on crew 80 seed 4.
- **Widened before deepened.** Deeper first (1.8x the slot) passed the spoke walk on crew 80 seed 4, but radial,
  maint and fill then failed: 6 checks against 2.

**Trace** (5 trace seeds, `data/mapforge/gen_bu`; before/after in `data/mapforge/gen/trace_topdown_2026-11-22.json`
and `trace_bottomup_run3.json`):

| | top-down | bottom-up |
| --- | --- | --- |
| "ways in" fails | 5 of 5 | 0 of 5 |
| one-door share after connect | 0.20-0.31 (out of band on 5) | 0.363-0.388 (in band on 5) |
| final failures | 30 (4-7 a map) | 21 (2-8 a map) |

- The exit test's last clause is **not met.** Every map traded its old failures for others.
  - Gone: floor reached, oversized, open maint, maint_tv, maint_pocket, walk_loops, room_size_atmos, and halls
    7+ wide on one map.
  - New: `skel.fill` (4 of 5), `skel.spoke_len`, `share.hall`, `skel.core_dist`, `share.command`, and some
    departments' median room size.

**Full stage** (`build.py --set --stage full --jobs 5`, 48 min): **0 of 15 pass, 2-7 failures each** (top-down: 0 of
15, 3-11).
- No build fails "ways in" or the one-door share.
- Failures over the 15:

  | count | checks |
  | --- | --- |
  | 9 | `skel.fill` |
  | 6 each | `space.room_size_security`, `share.command` |
  | 5 | `space.room_size_civic` |
  | 4 each | `skel.spoke_len`, halls 7+ wide |
  | 3 each | `space.pockets_per_1k`, `share.hall` |
  | 2 | must touch atmos-engineering (`rooms.touch_doors` found no wall run between them) |
  | 1-2 each | the rest |

**Next, by count:**
1. **`skel.fill`.** Composed departments are ragged at the back, so the station box holds less floor (0.17-0.21
   against 0.234). Square the back edge: rooms at the far end take the frame's full width first, or the footprint is
   cut at the last full row.
2. **Room-size medians** (security, civic) and **`share.command`.** The core is sized from command's composition,
   which lands under its budget on big crews.
3. **The atmos-engineering door.** Let the pair's footprints share one wall instead of standing two walls apart.

### M2-M3, 2026-11-22 night: fill, and the first passing builds

**`skel.fill` (station floor / station box) came from the test range, not the departments.**
- Composed footprints are as dense as the old blocks: floor/cells 0.61-0.62 (the old FLOOR_RATIO 0.62).
- Two other levers barely moved their box fill (floor/box), on 10 compositions:

  | lever tried | box fill |
  | --- | --- |
  | a score cost on the bay behind each room | 0.442 -> 0.450 |
  | the stem variant chosen by floor less 0.2x its box | 0.447 -> 0.463 |
- Depth caps of 36 and 30 changed nothing measurable: fill moved 0.14-0.28 between configurations, which is noise.
- Taking each element out of the box in turn named the cause: without the test range the box shrank 1.57x and 1.98x
  on crew 80 seeds 1 and 4, and no more than 1.05x for any department.
  - `blocks._test_site` took the compass point nearest science, at outpost x the farthest floor. On a diagonal that
    grows the box both ways.
- **Fix:** `compose.BU._test_site` keeps the distance and picks one of 32 directions by the gate's own bands:
  distance out of `skel.aspect` (0.762..) plus distance out of `skel.fill` (0.234..). Floor is estimated as 0.71 of
  the claimed cells. A small box term follows, with science's side as the tie-break.
  - The bay cost (`BAY_W` 0.04) and box-aware variant choice (`BOX_W` 0.2) stay in. Both are small.

**Trace** (5 trace seeds, `data/mapforge/gen_bu2`, `data/mapforge/gen/trace_bottomup_run4.json`):

| | top-down | bottom-up before | bottom-up now |
| --- | --- | --- | --- |
| final failures | 30 | 21 | 11 |
| maps failing `skel.fill` | - | 4 of 5 | 0 of 5 (0.237-0.256) |
| "ways in" | 5 of 5 | 0 of 5 | 0 of 5 |
| one-door share | out of band | in band | 0.369-0.390, in band |

- Crew 80 seed 1 passes every check after connect.
- Still new against top-down:
  - crew 40 seed 3: radial.command, room_size_medical;
  - crew 80 seed 4: share.hall, spoke_len;
  - crew 120 seed 1: radial.civic, radial.hall, spoke_len;
  - crew 120 seed 2: radial.engineering, share.command.

**Full stage** (`build.py --set --stage full --jobs 5`, about 50 min): **2 of 15 pass** (crew 80 seeds 1 and 4), the
first full-stage passes.
- The rest fail 1-8 checks: 52 in all, against 72 before this fix.
- `skel.fill` fails on 5 builds, down from 9. All 5 are crew 120 or crew 40 seed 2 and crew 80 seed 2.
- No build fails "ways in" or the one-door share.

| count | checks |
| --- | --- |
| 6 | `share.hall` |
| 5 each | `skel.spoke_len`, `skel.fill` |
| 4 each | `space.room_size_civic`, `share.command` (all crew 120) |
| 2 each | room_size_medical, pocket_med, hall_share, share.service, radial.hall, radial.command, halls 7+ wide |
| 1 each | must touch atmos-engineering, oversized, open maint, and 10 more |

**Next:**
1. **Crew 120's command share.** The core box is the command composition, which comes in under budget: let the
   core take a second branch.
2. **Hall share and spoke length.** The spokes carry fewer, deeper departments than the blocks did. Try the second
   row back on, with side halls capped at the human arm length (19).
3. **The civic median room size.** Civic's copies are big (library 127, chapel 117).
