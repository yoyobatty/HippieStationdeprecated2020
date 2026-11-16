# How Hippie's Science is played (study, 2026-11-15)

Read from the original map and the game code before any redesign. Links marked (code) are verified.

## Robotics (x163-178, y117-127)
Purpose: turn metal, glass and brains into borgs, mechs and augments, and launch mechs onto the station.
- Public side: a desk windoor at 176,126 on the hall. Crew hand in brains and parts, collect finished limbs.
- Two exosuit fabricators. A fab drops what it prints on the tile it faces (code: `get_step(src, dir)`). Each fab
  faces a one-way conveyor (robo1, robo2). The conveyor carries parts east onto a striped pickup tile beside the
  assembly floor. Printing and assembly are one line: fab -> belt -> open floor to assemble on.
- The middle of the room is open striped floor: a mech is assembled on a free tile with room around it.
- Mech bay to the west (kept): recharge ports charge the mech standing on the tile they face (code:
  `recharging_turf = get_step(loc, dir)`). Each port's console sits within 2 straight tiles of it (code). Shutters
  `Skynet_launch` open the bay straight onto the main hall, so a finished mech walks out without crossing the lab.
- Surgery corner (south-west): operating table with its computer on the adjacent tile (code: the computer finds the
  optable at `get_step` beside it). Instruments on an L-bench, morgue tray for the bodies brains come out of.
  Augment manipulator beside it.
- Robotics R&D console and circuit imprinter next to the fabs. Robotics vendor and wardrobe by the staff door.

## R&D lab (x182-191, y121-127)
Purpose: research. Deconstruct items for points, print parts and boards, hand prints to the crew.
- The console links the analyzer, protolathe and imprinter it can see within 3 tiles (code: `oview(3)`). They sit
  in a striped enclosure, the console at the corner, reaching all three.
- Public desk windoor at 184,126 and shutters (`rnd`) onto the hall: crew queue at the desk and take prints.
- Benches with stock parts and tools along the walls; a cell charger.

## Research Director's office (x182-189, y104-110)
Between the labs and the toxins wing, staff-only. RD consoles (robotics, mecha tracking, AI integrity), the RD's
locker, Lamarr's cage, the RD's desk. It watches the floor: windows onto the research corridor.

## Toxins (storage x173-178 y105-110, mixing x183-207 y95-110, kept)
Canister storage feeds the mixing room. The burn chamber has its own pipe loop, igniter and vents; bombs leave
through the mass driver to the test range. Everything here is plumbing-bound.

## Experimentor lab (x189-197, y111-120, kept)
The experimentor has to see an R&D console within 3 tiles (code). Separate, striped, dangerous, close to the
research corridor's shower for accidents.

## The department as a whole
- The research corridor runs north-south behind the public hall, staff only, through biohazard doors.
- Public faces: the robotics and R&D desks on the main hall. Everything else is behind access doors.
- Flow: materials come in from cargo by the delivery chute (189,121). Robotics and R&D take them; finished things
  go out through the desks or, for mechs, the mech bay shutters.

## What that means for a remodel
These rooms already work. The fabs, belts, pickup tile, ports, console and optable pairs are working geometry.
Moving them at random breaks the line. A redesign has to keep each chain (fab -> belt -> floor, port -> tile,
console -> machines within 3, computer -> table) and the public desks, and change things only for a play reason.

## Proposed program (draft 1, data/previews/mapforge/science_plan.png)
Play reasons for each change:
- Security post moves to the front foyer, glass onto the hall and the foyer: the officer sees who comes in
  (today the checkpoint is buried mid-department and sees nothing).
- Toxins canister bay joins the mixing room: no wheeling canisters across the research corridor.
- RD office sits between the server room and the spine, windows on both: the RD watches the floor and owns servers.
- Experimentation (experimentor + blast chamber) moves to the east edge and takes the east maintenance strip: the
  dangerous room is furthest from the entrance.
- Nanites get a door on the spine near the front: crew come in for nanites without walking the department.
- Robotics keeps its fab > belt > pickup > assembly chain, with a bigger striped assembly floor and a wide shutter
  into the mech bay so a finished mech drives into charging, then out through the launch shutters onto the hall.
- Kept where they are for physics: the burn chamber module and the launch line on row 104 to the range.
