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
