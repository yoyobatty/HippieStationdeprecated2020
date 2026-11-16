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

A room asset is a function of one room. It asks which wall faces which neighbour and where the doors are, then
places kits: authored groups of pieces that only work together (fabricator, belt and pickup tile; R&D console and
its machines), written once in their own frame with the tiles a person stands on. The placer never closes a door,
walls off floor, leaves a piece nobody can reach, seats anyone in a doorway or stands a bin on the disposal line.
`forge/proc/emit.py` turns the result into an ordinary blueprint, so everything below still applies.

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
