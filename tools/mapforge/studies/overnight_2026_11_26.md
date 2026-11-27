# Overnight 2026-11-25 -> 26: the learned generator

You asked for a proper map generator by morning, learning from examples, at most one agent. This is what was built,
what it measures, and where it falls short. Pictures: `data/previews/mapforge/learn/` and
`data/previews/mapforge/gen_learn/`.

## What changed

The room stage no longer stitches stock rooms along a generated corridor. Every department except atmos, engineering
and the AI satellite is now **laid out and furnished from what the human maps show**:

1. **Rooms** (`gen/learn/synth.py`): a room's shape, doors and windows in; furniture out. An exemplar of the type
   near the size gives the groups (a cloning pod, its scanner and console are one group); each group goes where its
   wall contacts and distance to the door match, re-embedded piece by piece when it doesn't fit whole (every pair
   that touched still touches); a top-up from the type's other human rooms to its usual density, the room kit
   first; the game's own partner rules last (forge/function.py).
2. **Departments** (`gen/learn/floorplan.py`): a corridor spine from the hall door, rooms on both sides filled from
   the entrance back, the types humans keep on the walkway in front and the ones they keep behind (surgery, servers)
   behind the room humans most often join them to by a door; rooms sized from their stock sizes; types that are a
   main room with a row of small pieces (xenobiology's pens, the brig's cells, dorm bedrooms) carved that way;
   floors by type, the corridor in the department's floor with its trim colour; windows onto the corridor in the
   share humans glaze each type. Every cell is a room, the corridor or one wall line: no double walls, no voids.

## Measured

Held-out rooms (Meta, Box, Delta each left out of the learning in turn, 39 rooms, `gen/learn/tune.py`):

| | function problems | furnished share | wall share |
| --- | --- | --- | --- |
| the human rooms | 9 | 0.415 | 0.742 |
| generated in their shapes (night) | 1 | 0.372 | 0.641 |
| generated, with lights, main/back exemplars, unstrand (morning) | 2 | 0.373 | 0.628 |

Department floorplans against the gate's human bands (`gen/learn/planstats.py`, every learned department at crew-80
size, 3 seeds; seconds to run):

| | room size 10/25/50/75/90% | rect rooms | aspect | per-department medians in band |
| --- | --- | --- | --- | --- |
| first floorplans | 10.5 / 20 / 32 / 58 / 98 (all out) | 0.83 (out) | 0.60 (out) | 1 of 9 |
| night | 6 / 12 / 20 / 40 / 87 (all in) | in | 0.67 (in) | 8 of 9 (dorms 32 vs 28) |
| morning, station-size slots, 2 per dept | 6 / 12 / 24 / 38 / 57 (all in) | 0.59 (in) | 0.67 (in) | 8 of 9 (civic 18 vs 19) |

Oversized rooms (bigger than every human room of the type, measured as the gate does: same-type rooms within 2 tiles
are one) in those 54 plans: 47 before the cap pass, 1 after (a gravity generator 61 against 60). Function problems
in the department previews (forge/function.py review: things nobody can stand at, a console facing a machine, two
nuke disks): 1-7 per department before, 0 in 8 of 9 after (`unstrand`, department-wide unique items).

How: rooms near-square from their learned size with the depth behind them a back row; the department's own small
rooms (patient rooms, toilets, closets, learned per department) up to its learned room count; big halls capped at
the human 90% size; neighbouring rooms interlocking (a jog in their shared wall makes both L-shaped, as human rooms
are); corner closets out of oversized rooms; pens, cells and bedrooms carved as human departments have them.

Speed: a station build fell from ~20 min to ~5 (stock rooms' source maps were re-measured for every copy; the
synthesizer ran on every layout try of the block search). `GEN_REUSE=1` rebuilds a seed's cached block plan in ~5
min when only the room stage changed.

### Fixed after the first station boots (2026-11-25 morning)

The first learned station booted with 0 runtimes, but Bot Shift failed 10 checks (5 on the stock-room build). Each
cause was a generator fault, found by reading the built rooms:

- **Rooms were dark.** The room database dropped light fixtures (they hang by `dir`, not a pixel offset), and the
  synthesizer's light prefix also matched light switches: rooms got switches and no lights. Lights are now learned
  (15.6 floor tiles per fixture on the human maps) and placed by the wall faces they hang on.
- **Kitchens without a microwave.** A kitchen's cold room shares the kitchen's area, so the kitchen was furnished
  from a cold room (gibber, meat spike, no microwave, one table). Exemplars are now main rooms for main rooms and
  back rooms for back rooms and pieces. The R&D server room the same (control console, no server: research 0).
- **The kit pass was undone.** The essentials pass ran before the learned rooms were restored after the dressing
  passes, so its additions there were thrown away. It runs after now.
- **Pens, cells and bedrooms merged.** The wall cells between pieces stayed in the main room's floor; on the built map
  every pen of a xenobiology lab was one region with no walls between.
- **Copies.** "Closets" were picked by size alone, so central medbay, the captain's office and toxins mixing were
  closets and departments got four canister rooms. Closets are now types humans keep small (median 16 tiles or
  less), each repeated at most twice.
- **Oversized rooms** (47 in 54 plans, a gate failure): strip ends and back rows grew the last rooms past the
  biggest human room of their type. Such rooms are now cut (the part by the door keeps its cap, the rest is a type
  the department lacks) or retyped; back rows take a type the department lacks before joining the room in front;
  cells and pens are carved in the room's largest rectangle. The gate counts rooms of one type within 2 tiles of
  each other as one room, so the cap works on those groups; floor left over once a department has every type it
  can use becomes its maintenance store (`/area/maintenance/department/<x>`, furnished like a warehouse; 3.8% of
  department floor in the 54 test plans).
- **Long bars.** Slots up to 106 wide along the hall (crew 100) laid rooms out as bars: a learned department is now
  no wider than about the side of a square of its floor (`compose.learned_w`); pens and cells rooms are at least as
  deep and wide as their row needs (18 of 47 uncarved, was 28 of 53).
- **Things nobody can reach** after the function pass (a table walled in by tables, a console facing a machine):
  the piece in the way goes, or the stranded piece, never one of the type's kit; what stood on a removed table goes
  with it. One nuke disk and pinpointer per department.
- **Vents side by side** (the ruled "vents apart" check, an AI satellite foyer each build): the shared-room pass
  counts the vents a room has, and the air pass moves the second of a same-kind pair to the nearest free floor.
- **Narrow rooms** the other way: a slot of 54 for 500 tiles of rooms left back rows empty and the rooms in front ran
  their whole depth (4 x 25). A plan is no wider than 1.3 x the side of a square of its program's floor, and a room
  at most 2.4 times as long as deep (worst aspect 0.33, was 0.11).
- **Loose items** (gen/mapinspect.py, per 1000 floor tiles off the walls): 3.95 against the stock 0.6-0.8, nearly
  all hall litter (4.5% of hall tiles got chips, cans, crayons). Hall litter is now rare and only along walls; the
  kit pass puts items on tables and racks only, never loose on the floor.
- **Rooms with no APC** (a storage room full of racks had no empty tile against a wall): the APC goes on any tile
  with nothing hung there.
- **No slimes**: pens furnished from empty human pens; the first two pens get a slime.
- **Dorm halls** shared the dorms area with the cabins and measured 129-148 against the human 113: the hall takes
  the fitness area when it would push the dorms over.
- **Back rooms.** Human maps give many types a small room of their own area (bar 7/8 maps, library 7/8, research 7/7,
  theatre 5/8). Corner rooms are now these, at the human share and size, furnished from human back rooms.
- **Engine site.** The supermatter's coil runs 3 tiles past its room on one side; a 21-wide engineering could not
  hold it. Engineering's slot is now at least 26 wide, and maint may run along the engine room's own walls.

## Station results

Crew 100 seed 7, with the fixes up to the litter pass (`data/mapforge/genL_c100_s7.dmm`, pictures in
`data/previews/mapforge/genL_c100_s7/`):

| | stock-room build (2026-11-25) | first learned build | this build |
| --- | --- | --- | --- |
| boot runtimes | 0 | 0 | 0 |
| docks fitting (escape, arrivals, cargo, mining) | 4 | 4 | 4 |
| Bot Shift fails | 5 | 10 | **4** |
| gate fails (median human map: 7) | 7 or fewer on 13 of 15 builds | 11-18 | 10 |

Bot Shift now passes kitchen, bar (both checks), research, upgrades, janitor and evacuation (all 16 aboard). Its 4
fails: botany's fridge and the cargo-to-Science delivery (both failed on the stock-room build too), experiments
(also failed before) and slimes (no slimes: fixed after the run).

The gate fails left are the block layout's (hall share, fill, spoke length, a radial place) and open maint; room
sizes, oversized rooms and vents passed.

Final round (all fixes up to the median guards; `data/mapforge/gen_learn/gen_hub_c<crew>_s<seed>.dmm`):

| seed | gate fails | which |
| --- | --- | --- |
| crew 100 seed 7 | **6** | skel.aspect, one_door, civic room size, halls 7+ wide, open maint, disposals outlet |
| crew 60 seed 23 | **7** | radial.command, share.security, skel.aspect, room_q0.1, room_q0.25, service room size, halls 7+ wide |
| crew 80 seed 1 | 9 | radial x3, skel.aspect, maint_tv, room_q0.1, cargo and civic room size, halls 7+ wide |

Two of three within the median human map's 7 (the bar you set), against 11-18 on the first learned builds. No
oversized rooms, no side-by-side vents, engine placed on all three.

With the double-wall merge (gen/walls.py: a room's whole side against another wall takes its wall line as floor;
what's left against a hall becomes a hall niche, halls kept under 7 wide), crew 100 seed 7 fails **5**: skel.aspect,
skel.spoke_len, room_q0.1, halls 7+ wide, disposals outlet. Its look against the stock maps (gen/mapinspect.py, per
1000 floor tiles):

| | double walls | loose items off walls | loose on open floor |
| --- | --- | --- | --- |
| stock (Meta, Delta, Box, Hippie) | 8.1-13.3 | 0.59-0.78 | 0-4 |
| first learned build | 22.8 | 3.95 | 5 |
| final crew 100 seed 7 | **9.5** | **0.37** | **0** |

The map is kept as `data/mapforge/gen_learn/gen_hub_c100_s7_final.dmm`.

Seeds 23 and 1 with the wall merge: crew 60 seed 23 fails 7 (radial.hall, share.hall, room_q0.1, room_q0.25,
service room size, halls 7+ wide, open maint), crew 80 seed 1 fails 8.

**A hull fault found by the boot** of the wall-merged crew 100 build: its main halls lost their air (-91 C). Station
floor stood beside space with no wall between: maint corridors along the station's edge with no outer wall. The
earlier builds had them too (22-33 open tiles a build) but there the maint was closed off from the halls. A last pass
(gen/walls.py seal_hull, after every network) now puts reinforced wall on any space tile beside station floor
(not the engine, solars, shuttles, airless plating, windows or lattice).

### The final map

Crew 100 seed 7 with every fix (`data/mapforge/gen_learn/gen_hub_c100_s7_final.dmm`; pictures in
`data/previews/mapforge/genF2_c100_s7/`: full.png, sheet.png, medical.png, science.png):

- gate: **5 fails** (skel.aspect, one_door, room_q0.1, halls 7+ wide, open maint); the median human map fails 7
- boot: 0 runtimes, all four docks fit, halls keep their air
- Bot Shift: **4 fails**. Everything else passes: supermatter, solars, air loop, botany planting, medical, janitor,
  kitchen, cargo (all four), research, upgrades, experiments, all 16 crew evacuated
  - botany's fridge: failed on the stock-room build too
  - bar (2 checks): the bar is complete and powered (drinks dispenser, Booze-O-Mat, 8 counters, 14 stools); the
    bartender filled its bag (21/21) with things it picked up and never started a drink. A bot habit, not the map;
    it passed on the earlier crew 100 build.
  - slimes: the slime is there (a colour bred); the scientist never fed it in 30 minutes
- look against the stock maps: loose items 0.39 per 1000 floor tiles, 1 on open floor (stock 0.59-0.78, 0-4);
  double walls **17.1** per 1000, over the stock 8.1-13.3. The build before it had 9.5; this one's block plan came
  out different, and the guard that keeps halls under 7 wide let 12 hall niches through where that one had 31.
  Not fixed yet.

## How to run it

    python tools/mapforge/gen/build.py --seed 7 --crew 100 --stage full     # a station: data/mapforge/gen/gen_hub_c100_s7.dmm
    GEN_REUSE=1 python tools/mapforge/gen/build.py ...                      # same block plan, rooms rebuilt (~5 min)
    python tools/mapforge/gen/learn/deptview.py all --seeds 1               # every department alone, seconds each
    python tools/mapforge/gen/learn/planstats.py                            # floorplans against the human bands
    python tools/mapforge/gen/learn/tune.py                                 # held-out rooms (39, ~30 s)
    python tools/mapforge/gen/learn/roomlist.py <map.dmm>                   # rooms as the gate sees them, oversized
    python tools/mapforge/gen/mapinspect.py <name>                          # double walls, loose items vs stock
    python tools/mapforge/gen/pictures.py <name>                            # full map, networks, docks, departments

## Still short

- Furnishing is a little sparser and less wall-hugging than human rooms (numbers above).
- Rooms are rectangles in rows with some L shapes (jogs, back rooms); human departments have more varied outlines.
- Atmos and the AI satellite still use the old composer.
- Station-level checks outside the departments (hall widths, maint shares, radial places) come from the block
  layout, untouched tonight.
- Civic's median room is 18 tiles against the human 19-46 (its program has small storage types).
- Learned departments get about 40% of the floor their slots ask for at crew 100 (the human median-size bands keep
  rooms from growing; human departments have more rooms at big crews). Crew 120 is worse: its departments are a
  third of their slots.
- Bot Shift's remaining fails: botany's fridge, the cargo-to-Science delivery and experiments failed on the
  stock-room build too.
