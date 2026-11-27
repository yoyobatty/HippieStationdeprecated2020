# A generator that learns from the human maps (2026-11-25)

The user, after the network stage made generated stations playable: "I feel like using this huge rules list is just
never gonna work, we need a much more sophisticated generator that maps it like a real map would." Copying whole
human departments was rejected ("No I don't like that"). The pick: **learn from examples**: new rooms and departments,
arranged by what the 38 human maps show, not by hand-written rules; judged against maps held out of the learning.

## 1. Why the current generator looks wrong

`gen/compose.py` drops whole stock rooms along a generated corridor, then ~30 passes patch what the stitching breaks.
What a player sees (the user's list, 2026-11-25): double walls between rooms (64.6 a 1000 wall tiles against stock
8-13), rooms as islands in grey plating, 1x1 space pockets, a counter windoor facing a wall, an air alarm over an
airlock, a table in front of an airlock, the cloning machines apart. Each fix is one more rule, and the passes fight
(walkfix moved 300 dense things a build, which is how a cloning pod leaves its console).

## 2. What the literature offers, and what fits 38 maps

- Learned floorplans (House-GAN 2020, Graph2Plan 2020, HouseDiffusion 2023): room outlines from a bubble graph,
  trained on RPLAN's ~80k apartments. Outlines only, and far more data than 38 stations. Not usable directly.
- Merrell, Schkufza, Koltun 2010, "Computer-generated residential building layouts": a Bayesian network learned from
  examples gives the room program and adjacencies; stochastic optimization lays rooms out against learned costs.
  Small data, statistics not deep nets: the department level here.
- Fisher et al. 2012, "Example-based synthesis of 3D object arrangements"; Yu et al. 2011, "Make it Home": learn
  which objects occur together and their relative placements from example scenes; synthesize new arrangements by
  sampling and optimizing that model. The room level here.
- Model synthesis / WaveFunctionCollapse (Merrell 2007; Gumin 2016): local tile statistics only; tried here
  (look_wfc), local texture without function. Not the core.
- Games that ship generated levels (Spelunky, Diablo, Unexplored): authored pieces + procedural assembly. The
  module idea; rejected as copying.

So: statistical models learned from the corpus (no deep nets; the CNN discriminator from mapforge stays as a critic),
plus optimization, at two levels: room arrangement (Fisher/Yu) and department floorplan (Merrell).

## 3. Levels

**L0 corpus model** (`gen/learn/`), learned once from the 38 maps, cached:
- rooms: per type, size, aspect, rectangularity, doors (count, side, which room types they join), windows;
- motifs: groups of objects that stand together (forge/corpus clusters: cloning pod + scanner + console, a counter
  with its windoor and shutters, a bed with its nightstand), kept rigid with their wall contacts and use tiles;
- placement: per motif family, wall contact, distance to the nearest door (in bins), distance to the room's centre,
  facing relative to the door, by room type;
- pairs: for motifs that share rooms, their relative placement (same wall, facing, distance bins);
- departments: room program (types, counts, sizes by department size), the room graph (which types share a wall,
  which a door, which open onto the department's corridor), corridor width and floor style, glass between types.

**L1 room synthesis**: given a room's floor, walls, doors and windows (from L2 or any room), pick an exemplar
composition (a human room of the type near the size, by seed), then place its motifs in the new shape by simulated
annealing on: placement log-likelihood + pair log-likelihood + hard play constraints from the game's own code
(forge/function.py: partner machines adjacent, use tiles free, nothing dense in front of a door, every free tile
reachable, wall pieces on solid wall only).

**L2 department floorplan**: from the learned program and room graph, lay out the department block by optimization
(rooms as rectangles and L shapes sharing walls, the corridor as one more room with its own learned shape), so double
walls and voids can't happen by construction; doors where the graph says; then L1 in every room.

**L3 station**: today's skeleton, slots, engine, atmos blueprint, docks, solars and networks (gen/net.py).

## 4. Judged by

Leave-one-family-out: learn from 37 families, generate rooms and departments in the held-out map's own shapes,
compare:
- function problems (forge/function.py review) = 0, gen/mapinspect.py numbers inside the stock band;
- room-feature log-likelihood under a model learned without that map, no worse than the held-out human rooms;
- the discriminator's share of tiles called generated, per room;
- room twins (forge/room_twin.py) side by side, and the user's eye.

## 5. Milestones

| | build | exit test |
| --- | --- | --- |
| M-L1 | L0 rooms + motifs + placement + pairs; L1 room synthesis | in 30 held-out human room shapes of 10 types: 0 function problems, likelihood within the held-out humans' range, pictures beside the originals |
| M-L2 | L0 departments; L2 floorplans | held-out department outlines refilled: 0 double walls, 0 voids, program and room graph inside the human band, pictures |
| M-L3 | L2 + L1 in the station generator | gate at most 7 failures; boot 0 runtimes; Bot Shift; inspect numbers in the stock band |

## 6. Progress log

### 2026-11-25 night: L0, L1 and the first L2

**L0** (`gen/learn/roomdb.py`): 1563 rooms of 165 types from the 8 tg-family maps (floor with wall sides, doors and
what they join, windows, furniture groups with wall contacts and use tiles, wall pieces; no loose floor items).
`gen/learn/deptdb.py`: floor turf by room type, how often a type sits on the walkway (front), door shares between
touching types, corridor turf and share by department.

**L1** (`gen/learn/synth.py`), measured on held-out rooms (`gen/learn/tune.py`: Meta, Box and Delta held out in turn,
39 rooms, ~30 s, numbers only):
- an exemplar of the type near the size; its furniture groups placed rigid in any of 8 turns, scored on wall
  contacts and door distance; the free floor kept in one piece with door fronts and use tiles in it;
- a group that fits nowhere whole is re-embedded piece by piece keeping its adjacency graph (`flex`: every pair that
  touched still touches; that is how Donut's cloning set fits Meta's 3-wide room with its links intact), then split
  if that fails;
- top-up to the type's furnished share from the other human rooms of the type, the room kit's missing families
  first, never a station-unique thing;
- forge/function.py's fix (the game's partner and use rules) last.
Bugs found by the numbers: merging nearby groups glued dense rooms into one block that fit nowhere (rooms came out
empty); a rejected spot dropped the group instead of trying the next; flex wrote atoms character by character.

| | function problems | furnished share | wall share | groups left out |
| --- | --- | --- | --- | --- |
| human (39 rooms) | 9 | 0.415 | 0.742 | - |
| generated | 1 | 0.372 | 0.641 | 43 |

**L2** (`gen/learn/floorplan.py`): the department block cut into rooms around a corridor spine from its hall door,
both sides filled from the entrance back (the side whose free spot is nearest the door takes the next room),
walkway types in front, types humans keep behind (surgery, servers) in a back row with a door to the front room
humans most often join them to (deptdb door shares), rooms sized from their stock sizes over the strip's depth, the
block cut back to its longest strip, strip ends as the department's storage room. Every cell is a room, the
corridor or one wall line: no double walls, no voids. Floors by type (deptdb turf), the corridor in the department's
own floor. Every room furnished by L1, then function.fix. `gen/learn/deptview.py` previews a department alone in
seconds; data/previews/mapforge/learn/dept_*.png. Wired into compose (`GEN_DEPTS=learned`, the default) for all
departments but atmos, engineering and the AI satellite.
Gaps seen: rooms whose walls are their function (xenobiology pens, brig cells) get machines round open floor; big
rooms sparse; no glass or trim inside departments yet (the station's dress pass adds some).
