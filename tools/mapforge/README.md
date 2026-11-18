# mapforge

Hand-drawn blueprints in, finished map tiles out. The designer draws rooms and furniture as ASCII; mapforge does the
rest the way a careful mapper would, then checks it and draws pictures.

```
python tools/mapforge/mapforge.py build blueprints/hippie_service.py     # build, check, pictures
python tools/mapforge/mapforge.py build <bp> --apply                     # also write into the real map
python tools/mapforge/mapforge.py trace x1 y1 x2 y2 /area/a,/area/b     # skeleton of an existing zone to design over
bash tools/mapforge/run_zone_check.sh <name> x1,y1,x2,y2 [hippiestation] # boot the build headless, check in the engine
```

Output: `data/mapforge/<name>.dmm` (whole-map copy), `data/previews/mapforge/<name>_{before,after,wiring,sheet}.png`.

## Generated departments (`forge/proc`, the node graph)

A department can also come from a chain of nodes instead of a drawing. Each node takes the geometry (tiles with
attributes, rooms, placed pieces), changes it and hands it on, and each node's output can be drawn.

```
python tools/mapforge/blueprints/science_v3.py           # run the graph: one picture per node, in data/previews/mapforge/proc/
python tools/mapforge/blueprints/science_v3.py --wedge   # the same graph under other parameters, side by side
python tools/mapforge/mapforge.py build blueprints/science_v3.py   # the real build: pipes, cable, lights, checks, sprites
```

| node | what it does |
| --- | --- |
| outline | reads the footprint from the map: our tiles, the ring that must stay wall, kept tiles, doors leading in, the disposal line |
| slice | cuts the free tiles into rooms with a slicing tree (`X(...)`, `Y(...)`); every cut is a one-tile wall |
| stamp | sets prefab modules whose tiles are fixed against each other (the toxins burn chamber) |
| tidy | drops scraps, fills dents, reports doubled walls and corner-only joins |
| openings | doors, desks and glass by rule on the wall two rooms share (`door(a, b, at=...)`, `glass(a, b)`) |
| fields | per-tile attributes: what backs a tile, door aprons, walking lanes, alcoves, distance to walls |
| furnish | hands each room to its asset (`assets/science.py`) |

Two departments run through it: `blueprints/science_v3.py` (one block, two streets, 25 rooms) and
`blueprints/medbay_v2.py` (six blocks around a kept cryo bay, 11 rooms). What the outline fixes is passed in three
ways: `keep` (sealed and left alone: a chute, a launch run), `gates` (kept tiles people walk through: a neighbour's
door, an open public entrance) and `inside` (kept floor that is part of the department: the cryo bay; rooms open
onto it with no wall). A cut can be open-plan (`X(..., wall=0)`) and a leaf `"-"` belongs to no room.

`forge/proc/solve.py` writes the slicing trees from a room list instead of by hand
(`python tools/mapforge/blueprints/science_v3.py --solve`). Each room states its target area, smallest workable
size, the frontage it needs (street, public hall), the tiles the outline ties it to and the rooms it works with.
The solver assigns rooms to the blocks between the streets and tries every ordering and cut of each block. It
knows nothing about furniture: the rest of the graph judges its plan. The streets themselves are still given.

A room asset is a function of one room. It asks which wall faces which neighbour and where the doors are, then
places kits: authored groups of pieces that only work together (fabricator, belt and pickup tile; R&D console and
its machines), written once in their own frame with the tiles a person stands on. The placer never closes a door,
walls off floor, leaves a piece nobody can reach, makes a diagonal squeeze, furnishes a passage two tiles wide or
less, seats anyone in a doorway or stands a bin on the disposal line. A run of wall kits takes the wall that fits
the most of it.
`forge/proc/emit.py` turns the result into an ordinary blueprint, so everything below still applies.

## Whole stations (`station/`)

`station/to_dmm.py` grows a whole station from a seed and a layout and writes a playable map: the .dmm in
`_maps/map_files/Generated/` and its `_maps/<name>.json`. The committed seeds are 1 pinwheel, 2 spine and 3 ring.

```
python tools/mapforge/station/to_dmm.py 2 --layout spine                 # rebuild a committed map
MAPFORGE_OUT=<dir> python tools/mapforge/station/to_dmm.py 2 --layout spine   # trial: the .dmm only, in <dir>
```

The log reports each pass. After the departments are built it runs these:
- **Engine:** MetaStation's supermatter block is copied whole and turned to fit the engine room.
- **Maint:** every run gets exits, and pockets left between rooms become maint rooms or wall.
- **Bathrooms:** toilets and sinks stand on the floor facing out, and each restroom gets a maint door.
- **Hall firelocks:** a full-width line every 7-12 corridor tiles.
- **Maint dressing:** at MetaStation's density.
- **One piece per wall face:** a light, urinal, alarm or sign never shares a bit of wall with another.

Then `forge/function.py` reviews every machine where it stands, and `forge/check.py` runs.

Pictures of a whole station use the game's own sprites:
`forge.render.render(dmm, png, z=1, scale=0.5)`, cropped to the station.

## What the builder does

- **Areas, turfs, windows** from `LAYOUT` + `ROOMS`; `~` keeps the existing tile (shell walls, hall doors, chutes).
- **Furniture** from the legend (global `LEGEND`, overridden per room by `ROOMDEFS[r]["legend"]`). `face="table"`
  turns chairs to their table, `face="open"` turns machines to the room.
- **Doors**: firelocks added where an airlock joins two areas.
- **Wall mounts** with offsets mined from hippiestation.dmm + MetaStation (`forge/kit.py` `MOUNT`): APC (skipped
  when the area already has one in maintenance via `areastring`, Hippie's habit), air alarm, fire alarm beside each
  door, light switch, extinguisher, newscaster, camera in a corner; explicit ones (`mount=[...]`) first.
- **Lights**: greedy cover of the floor from wall faces, tubes ~4.6 tiles reach, small bulbs in small rooms.
- **Atmos**: vents by k-means over each area's floor, scrubbers beside them; pipes routed as a forest: through-lines
  the old zone carried are kept joined, each vent fed from the nearest stub or laid pipe, walls between rooms avoided,
  edges hugged, supply and scrubbers run together. Unused stubs in maintenance are trimmed back to their junction.
- **Cable** the same way from new APCs to the grid; never touches kept cables it shouldn't join.
- **Disposals** in the zone are carried over unchanged (design around the bins).
- **Decals**: `trim="green"` paints tile-corner trim along walls (dir 1=NW, 4=NE, 2=SE, 8=SW quarters).

## Checks (`forge/check.py`, every build)

APC/air alarm/vent/scrubber/light/fire alarm per area; pipes joined to the station, no open ends; APCs cabled;
every floor tile walkable from outside, every machine reachable (diagonals count); no stacked dense objects;
nothing outside the old footprint; unknown types; inventory lost/gained against the old rooms.
`zone_check.dm` repeats the important ones in the running game (mains, lights on, pressure and temperature after
the air settles, vents on a pipenet, open ends, bins on trunks, runtimes).

## Measuring against human maps (`studies/perfect_generation_plan.md`, phase P0)

Every map, human or generated, is read by the same parser, so the numbers compare like with like.

```
python tools/mapforge/forge/parse.py MetaStation            # rooms, halls, doors, hung pieces of one map
python tools/mapforge/forge/fingerprint.py                  # 38 features: human range vs Generated/*.dmm
python tools/mapforge/forge/fingerprint.py --fresh a.dmm b.dmm   # only these trial builds
python tools/mapforge/forge/rules.py                        # the user's rulings, hits per 1000 floor, every map
python tools/mapforge/forge/rules.py --list                 # each ruling in the user's words, what enforces it
python tools/mapforge/forge/rules.py --crops                # crops of each rule's hits, data/previews/mapforge/rules/
python tools/mapforge/forge/gallery.py [--tag before a.dmm]  # department crops in game sprites, per tag
python tools/mapforge/forge/gallery.py --compare before after   # the same crops side by side
```

- `forge/parse.py`: `SemanticMap` (tile classes, glass, rooms as wall-bounded regions of one area, doors and what
  they join, open seams, dense/furniture tiles, wall pieces per face, counts on station floor).
- `forge/fingerprint.py`: station, department, room, fixture, wall and tile features; the 3x3 pattern distance is
  measured against the other human maps (leave one out). `RULED` marks features where a ruling overrides the human
  maps (shown, not counted). Output: `data/mapforge/fingerprint/report.{txt,json}` and
  `data/previews/mapforge/fingerprint/fingerprint.png`.
- `forge/rules.py`: the registry. A new ruling gets an entry the same day (date, the user's words, the rule, a map
  check, what in the builder enforces it).
- `forge/gallery.py`: full renders cached by file hash in `data/mapforge/gallery_cache/` (16 px a tile).
- `forge/space.py` (plan B2): space syntax on the region graph. It measures mean depth, integration, how much the
  halls are the core, intelligibility, depth of rooms from the halls, dead ends, loops and cut nodes, all against
  the human range. Output: `data/mapforge/space/report.txt`. Takes about 11 s.
- `forge/walk.py` (plan C4): walks 93 shift trips on every map (commutes, deliveries, patients, arrests, escape),
  shortest 4-way path over walkable tiles. It reports detour, trip length, failures, shortcuts through other
  departments, maintenance walking, 1-wide traffic, hot corridors and blocked airlocks. `--heat` draws traffic
  pictures to `data/previews/mapforge/walk/traffic.png`. Takes about 13 s.
- `forge/review.py` (plan C5): department crops at 32 px a tile with map coordinates and the review rubric, written
  to `data/mapforge/review/<map>/`. Claude reviews them and writes findings that name tiles to `review.md`.
- `forge/blind.py` (plan F1, F2): `build` cuts blind pairs (one human crop, one generated, at room, dept, quarter and
  whole scales) and tag crops. `serve` runs the page on http://localhost:8765 (launch config `mapforge-blind`).
  `score` gives the human-pick rate per scale (pass: 55% or less). Answers and tile tags go to
  `data/mapforge/blind/answers.jsonl`.

### Human corpus and the discriminator (plan A1, A3, C2)

```
python tools/mapforge/forge/corpus_index.py                 # index the cloned maps: data/mapforge/corpus/index.json
python tools/mapforge/forge/tensor.py MetaStation           # one map's semantic tensor and channel sums
python tools/mapforge/forge/disc.py smoke                   # CPU check of the discriminator code
python tools/mapforge/forge/disc.py train --device cuda     # held-out folds, data/mapforge/disc/<run>/report.txt
python tools/mapforge/forge/disc.py heat <run dir> <map>    # heatmaps, data/previews/mapforge/disc/
python tools/mapforge/forge/fixmine.py list                 # tg commits touching station maps, fault classes
python tools/mapforge/forge/fixmine.py diff --n 200         # tile diffs of fixes: data/mapforge/fixes/report.txt
```

- Corpus: sparse, blobless clones of tg, BeeStation, Yogstation, Paradise and Citadel in `data/mapforge/corpus/<src>/`
  (map files only, about 900 MB). `corpus_index.py` reads each station map on its main z-level, drops near-copies
  (70%+ of wall/floor tiles the same at the same coordinates) and maps under 2500 floor tiles, and groups remakes into
  families (50%+ the same). 29 kept, so 38 human maps in all. `parse.humans()` lists them, `parse.load()` reads them.
  With 20+ human maps the judges' human range is the 10th to 90th percentile, not min to max.
- `forge/alias.py`: rewrites later and other codebases' paths to 2020 tg ones (areas under `/area/station/`, the 2021
  department renames, Paradise `/turf/simulated`, `.../directional/<dir>` wall pieces back to pixel offsets).
- `forge/tensor.py`: a map as 19 channels (space, wall, glass, door, floor, dense, furniture, wall pieces per side,
  hall, maint, dept, decal, light, vent, item, area edge) plus the station mask, cached in `data/mapforge/tensors/`.
  Floor and rock outside the station read as space, so a planet or asteroid round a station is not a tell. Bump
  `VERSION` when alias.py or parse.py change what a map reads as.
- `forge/disc.py`: a fully convolutional network scoring 48x48 crops human or generated; its per-tile logits are the
  heatmap. Folds hold out whole families (and generated layouts). Needs more generated maps than the 3 committed:
  pass `--gen <dir>` for extra builds.
- `forge/fixmine.py`: reads tg's history (blobless clone: each map version is fetched on first read). A fix is a
  commit whose title says so, touching 3 station maps or fewer. `diff` compares each tile's whole text before and
  after, so access and dir edits count, and sums what changed: layout, objects, vars, turfs, areas.

### Plan passes that close the discriminator's tells (`station/to_dmm.py`, after `carve_pens`)

- `split_rooms`: rooms of 56+ tiles get a straight partition (glass in most of it, a door in the middle); rooms of
  24+ tiles get a closet or two in a corner. Humans have twice our rooms per area and half our median room size.
  `MAPFORGE_NO_SPLIT=1` skips it.
- `break_walls`: glass strips in straight wall runs, with chances by what the wall parts (room and hall, two rooms,
  room and space, maint and space) taken from the shares on Meta, Delta, Box and Kilo; a hall door into a department
  hall or a big public room may get a second leaf. Closed rooms (vaults, cells, the AI) keep plain walls.
  `MAPFORGE_NO_BREAK=1` skips it.
- `add_doors`: a room with one way in gets a second door, onto a room of its own department first, then a hall,
  then maint; a room with two sometimes gets a third. Brought dead-end rooms from 0.51-0.55 into the human range
  (0.36-0.39). `MAPFORGE_NO_DOORS=1` skips it.
- `trim_maint` (opt-in, `MAPFORGE_TRIM=1`, runs before the others): where a 1-2 wide maint run lies between a room
  and another room, a hall or the hull, the room takes the run over, so maint wraps fewer rooms. Small effect so far
  (maint|room walls -4%): most of the excess comes from `pinwheel.trace_maint` tracing maint round every department.
- `bay_rooms` (after `split_rooms`): a big room with an open middle (floor 3+ tiles from any wall) gets a partition
  down its long axis that you walk round, or wall stubs every third tile off its longest wall, up to three times
  while the middle stays open; `fill_ward` puts a bed in each bay corner of the medbay ward. Open-middle share of room
  floor went 0.171 to 0.137 (humans 0.109). Stamped rooms (`NO_BAYS`) keep their floor. `MAPFORGE_NO_BAYS=1` skips it.
- `python tools/mapforge/forge/disc_ablate.py <run dir> --gen <dir>`: blanks each channel on each fold's held-out
  crops and prints how far the score gap falls. The channel whose loss closes the gap is the tell.

### Rooms that work as rooms (walk of the station, 2026-11-18)

A walk round a generated station asked what a player asks: where do I get treated, is the kitchen behind the bar,
can I use the microwave. Each answer was checked against the stock maps first.

- Suites (`SUITES` in `station/to_dmm.py`): the pieces `split_rooms` cuts off a room take roles by size, in order:
  treatment gets patient rooms, an exam room and recovery; surgery an observation room and a prep room; chemistry
  chemical storage and a pharmacy; virology two isolation cells. Every stock isolation cell is a 2x3 with a bed, so
  virology's closets are cut 2x3, virology takes one partition at most, and after the build a cell keeps one plain
  bed (the furnishing put two roller beds in each).
- Counters (`add_counters`, `COUNTERS`): a table in the wall line between two rooms that work together, on the owner's
  side, with a firedoor and the owner's windoor or shutters. Kitchen to bar (a serving hatch, 2-3 tiles), hydroponics
  to the hall and to the kitchen, chemistry and the warden onto their halls, the HoP's reception window, R&D and
  robotics desks, cargo, atmos and the checkpoints. Counter tiles take no wall mounts. `MAPFORGE_NO_COUNTERS=1` skips
  it. `rooms.edge_kind` reads a poddoor edge as a door, so a template never puts a table in front of the hatch.
- Access text: every `*_txt` var is written quoted. A bare `req_access_txt = 12` made tg's `text2access()` runtime in
  `splittext` and left the door open to anyone.
- Kitchen appliances (`forge/function.py`): a microwave, oven, griddle, fryer or grill needs the tile below it free
  to stand on; a processor, gibber, grinder or chem machine needs a straight side free. One that has neither moves to
  the nearest free table top of its room, else onto a new table against a wall, else goes if another of its kind in
  the room works. A pipe under a table no longer counts as a machine on it. `AREA_CAP` keeps an area to two fryers
  and two microwaves (every stock kitchen has two of each); the furnisher's `CAPPED` stops a fryer cluster being
  picked again.
- Placement: the captain's office links to its bedroom and the bridge, and hydroponics sits near the kitchen
  (`station/program.py`; `grow.py` near weight 0.7). A barber or photo studio counts toward the lounge cap
  (`SIDE_SHARES` in `station/pinwheel.py`), since both are drawn as the lounge area.
