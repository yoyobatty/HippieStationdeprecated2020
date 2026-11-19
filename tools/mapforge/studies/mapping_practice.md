# How mappers make a station look right

Research of 2026-11-18, after the user judged every generated and remixed station "horrid everywhere" (shape, rooms,
furniture, maint). The point: mappers and level designers follow a fixed order, from purpose down to tiles, and
check each stage before the next. mapforge skipped the top stages and went straight to tiles, from statistics or
from copied pieces. That's why nothing came out designed.

Sources:
- [Paradise mapping design guide](https://devdocs.paradisestation.org/mapping/design/): the only SS13 guide that covers design rather than tooling
- [san7890's Mapping Reference Collection](https://hackmd.io/@tgstation/ry4-gbKH5) (tg maptainer)
- the old [tg Guide to mapping](https://wiki.tgstation13.org/Guide_to_mapping) (read via Wayback)
- [The Level Design Book: layout](https://book.leveldesignbook.com/process/layout)
- [top-down level design](https://gamedesignskills.com/game-design/top-down-level-design/)
- [Kudzu retro level design](https://www.gamedeveloper.com/design/zen-and-the-art-of-retro-level-design-in-kudzu-)

## The order of work (level design and architecture practice)

1. **Purpose and program.** What the place is for. Then a room list per department, giving each room's use, its
   size, which rooms must touch, and which side is public and which is staff. This is the architect's space
   program. The numbers come from the stock maps (below), and the uses come from the game code ([[design for play]]).
2. **Bubble diagram.** Bubbles sized by area, and lines for the links that must exist: which departments work
   together, where the docks are, and where the secure rooms are. Draw at least three arrangements and pick one.
3. **Parti.** The one idea that binds the plan, for example "a hall ring round a command core, with spokes to the
   docks". Every later choice serves it.
4. **Block plan (blockout).** On the tile grid, at the real scale. Lay out circulation first: the primary halls,
   then the arterials. Then the department blocks hug the halls, and maint runs as the servant ring behind them.
   Doors are added only once the blocks work. Check the size of every block against the program.
5. **Rooms inside each block.** Lay out the rooms by workflow: what comes in, what is made, who stands where. Size
   each room to its use. Keep scale consistent between rooms (a freezer is never bigger than its kitchen).
6. **Playtest the blockout.** Walk it: the critical paths (arrivals to every department, every department to
   escape), Security's routes, and antag routes through maint. Fix the layout before any dressing.
7. **Detail pass last.** Floors, decals, signs, lights and clutter go in only once the layout holds.

Rule of thumb: start with big shapes, then doors and windows, then detail. Never detail a layout that doesn't work yet.

## SS13 rules (Paradise guide, tg reference, old tg guide)

**Halls**
- Primary halls are 3 wide.
- Arterials branching off them are 2 wide.
- Corridors inside a department are 1 or 2 wide. The main halls of the brig, medbay and science may be 3 wide.
- Public spaces, halls included, must be interesting: windows onto space, benches, posters, plants, and floor
  tiles that define the space.

**Departments**
- Every department touches a public hall at its front.
- Every department also has a back or side door into maint, so players can escape and antags can break in.
- Every room has one weaker point (a back door, side door or window) in case the main entrance is out.
- Security matches need: reinforced walls and electrified windows only for secure rooms (vault, armory, AI,
  department heads, tech storage). Elsewhere use plain walls and reinforced windows.
- Never make a perfect room. Sensitive areas are hard to breach, not impossible.
- Leave setup work for the crew (a medbay that has to prepare its theatres, a kitchen that needs botany).

**Rooms**
- No "Big Room Disease": no room that is bigger, emptier or squarer than its use needs.
- No "bald spots": a large open area with no purpose gets furnished or cut down. The old tg guide says to replace
  the extra space with maintenance tunnels.
- Large rooms are rarely perfect rectangles.
- Furniture goes into the room as well, not only along the walls.
- Every room has a clear function and its own area type, even a vacant office.
- Give departments enough tables and racks to set things down.

**Maintenance**
- Primary maint corridors are mostly 2 wide (room to dodge and to pass).
- There is one primary maint path that can be walked from every entrance. Dead ends are rare.
- Signpost each maint stretch with a scene so players know where they are (an abandoned cryo tube, a gambling
  den, a laundry).
- A large abandoned maint area must look like it once had a purpose (an old robotics bay, a monkey-fight ring).
- Maint owns the walls of its tunnels.
- No AI cameras in maint.

**Detail**
- Use the department's floor colour (see [[MetaStation style]] for the numbers).
- Too many decals and tile variants is visual noise. Warning tape only where it means something.
- Light every room fully, and keep one colour temperature per room.
- Place emergency and fire closets at intervals along the primary halls, or just off them in maint.

## The numbers: six stock stations measured (forge/parse.py, tells.py)

Floor tiles of a medium station: 8,500 to 9,400 (Meta 9,386), of which 60% rooms, 15% halls, 18% maint and 8% other.

| department | floor (median, min-max) | rooms | room size p25 / p50 / p75 |
|---|---|---|---|
| command | 387 (310-540) | 14 | 8 / 20 / 36 |
| security | 777 (668-1130) | 39 | 6 / 12 / 27 |
| medical | 555 (522-963) | 22 | 6 / 19 / 34 |
| science | 872 (716-1117) | 33 | 6 / 9 / 30 |
| cargo | 296 (254-570) | 9 | 6 / 29 / 50 |
| service | 413 (406-786) | 15 | 13 / 23 / 50 |
| dorms | 315 (186-504) | 20 | 1 / 6 / 12 |
| civic | 586 (520-1047) | 15 | 8 / 18 / 49 |
| engineering | 565 (470-982) | 21 | 3 / 12 / 25 |
| atmos | 364 (308-490) | 15 | 1 / 9 / 9 |

Across 38 human maps (medians):
- 20% of floor is maint.
- Maint between rooms of one department: 1.5%.
- Room walls back onto: a room of the same department 37%, space 29%, maint 15%, a hall 7%, another department 6%,
  a double wall 4%.
- Rooms: median 20 tiles, 45% of rooms are 16 tiles or fewer, 51% are perfect rectangles.
- Furniture covers 34% of room floor, and 87% of it stands beside other furniture.
- Halls: 44% of hall tiles are 3 wide, 46% are 4 or more (junctions and lobbies), 6% are 2 wide.
- The station fills 45% of its bounding box.

What this says about the look:
- Departments are dense clusters of small rooms that share walls.
- Maint stays outside departments.
- Rooms are about half rectangles and half other shapes.
- Furniture comes in runs and groups, never alone in the middle of a room.
