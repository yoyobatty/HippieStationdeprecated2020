# Function pass, 2026-11-26

The user: "Focus on function. The generator missed a few airlocks having no path to them, wrong airlock colour or
type. Engineering has so many SMES that don't fit a purpose. Re audit the entire station yourself visually, ask what
the purpose of each room and placement of stuff does and iterate until it functionally makes sense."

## Start here (state 2026-11-27)

Everything below is UNCOMMITTED in the working tree (`git status` under `tools/mapforge/`). Latest build: f53
(`data/mapforge/gen_learn/f53_c100_s7.dmm`, crew 100 seed 7): gate 8 shape fails, 0 function fails; Bot Shift 3 fails.

**Tools added in this pass (each has a docstring):**

| tool | what it does |
|---|---|
| `gen/learn/plancheck.py` | department floor plans checked over many seeds in seconds, no station build: rooms touching, doors into walls, diagonal wall joins, rooms reached only through maint, gravity-generator room under 5x5; `--dept cargo` (hub figures), `--dump dept target W salt` (one plan as text). Run it after any floorplan edit. |
| `gen/learn/variety.py` | room size and shape mix of plans against the stock maps (`--plans N`) |
| `gen/learn/reshape.py` | room shapes toward the stock mix; `separate`, `fix_diagonals`, `trim` |
| `gen/learn/airy.py`, `gen/learn/desks.py` | pinch points in big rooms; counters (kitchen hatch, chemistry, R&D desk...) |
| `gen/mounts.py` | APCs, alarms, lights, signs on a real wall (`python gen/mounts.py <dmm>` lists floating ones) |
| `gen/roomreview.py` | one picture + card per room (`--only quartermaster --out <dir>`) |
| `gen/audit.py` | function audit; new findings `stray_window`, `blocked_driver`, `floating_mount`; `job_reach` per room piece |
| `gen/net.py` | `supply_dock` (Box's dock strip), `bay_to_hull`, `strip_fits` (block-stage dry run), `_hullish` |
| `gen/walls.py` | `clear_stray_glass`, `seal_hull` keeps a mass driver's throw line open |
| `data/mapforge/gen_learn/chainL.sh <build> <short>` | boot check + 30-min Bot Shift + pictures (~15 min) |

**Open items, in the order they hurt:**
1. Science upgrades fail (f50-f53): the ore silo runs dry, and crates cargo sends Science are left at Science's door
   in the hall ("Science, your crate's at your door"); the science delivery drill fails the same way. Next: how
   Science receives deliveries (a desk or drop-off the cargo tech can reach).
2. Size by need (the user's idea, measured on f42 below): 10 rooms 1.3x+ over stock (233 spare tiles), 28 rooms
   0.7x- under (780 short: bar, locker room, bridge, prison, captain's office). Trim + about 6% more floor. Not built.
3. Mining dock across maint when the mining room sits inside the block (f50-f53 layout). Plan fix: mining dock
   beside the bay on the hull.
4. Gate 8 shape fails on the strip-fitting layout (f50-f53) against f49's 5: small-room quantiles, halls 7+ wide,
   maint pockets, a 6-tile dead end. All near misses.
5. Other seeds not checked since the hub/strip work (only crew 100 seed 7).
6. Bar martini drill fails now and then (bot side, not traced).

**Pictures:** `data/previews/mapforge/genF44_c100_s7/cargo_before_after.png` (cargo f37 vs f44),
`data/previews/mapforge/stray_windows/sheet.png`, `data/previews/mapforge/genF5x_c100_s7/` (each build's full map
and close-ups, from chainL.sh).

## The audit (gen/audit.py)

Each finding is a count, so a build can be judged in one line (build.py logs `audit: {...}` every round):

    python tools/mapforge/gen/audit.py data/mapforge/gen_learn/gen_hub_c100_s7.dmm --list
    python tools/mapforge/gen/audit.py <dmm> --rooms security       # one line of doors and machines a room
    python tools/mapforge/gen/audit.py --stock                      # the stock maps' own counts

Stock maps (Meta, Box, Delta, Hippie): dead doors 0-7, odd doors 4-22, orphan buttons 1-5, missing kit 8-18,
function-review problems 22-74. Their "unreached" rooms are the AI satellite and the test range.

## What was wrong and the fix, by cause

| Finding (crew 100 seed 7) | Before | Cause | Fix |
|---|---|---|---|
| plain grey airlocks, no access | 168 of 256 | floorplan, connect and walkfix put `/obj/machinery/door/airlock` everywhere; the vault opened to the command corridor | gen/learn/doordb.py: type, access and name learned per (room, what's beyond) from 3565 human airlocks; public rooms (lobby, bar, chapel...) learned by what the public reaches on human maps, their way in opened |
| airlocks into walls | 6 | already there after compose (17), walkfix fixed most | gen/doorfix.py: a double wall behind the door opens, else the door is walled up; blocked fronts cleared |
| arrival airlocks unpowered | 2 | door tiles in /area/space (never powered) | doorfix.door_areas: the station side's area |
| SMES by the gravity generator | 5 (human 1) | three grav-gen rooms, every exemplar and the top-up added SMES | roomdb.caps(): per room / per type on a map / per station, synth.furnish spends a shared budget |
| clone pods | 4 | same | same (station cap 2) |
| SMES with no terminal | 2 (telecomms) | copied room | net.power takes out SMES with no terminal outside engine, arrays and satellite |
| orphan buttons, timers, controllers | 41 | synth copied exemplars' wall pieces with ids | synth skips linked pieces (LINKED) |
| dark rooms | 10 | small offices' wall faces all taken by mounts before lights; dorm corridor area not lit | lights first; CORR_ALT corridors lit |
| nanite lab with no chamber, mech bay with no port | | band fitting squeezed working rooms to 12 tiles | floorplan.work_size: 4 tiles a kit machine or locker + 6, at most the smallest human room |
| QM office 6 tiles, no locker or console | | it was a "closet" type | closets only types with under 2 kit pieces |
| cold room across the corridor from the kitchen | | strips filled by entrance order only | deptdb nb (how often two types neighbour on human maps); partners of 0.8+ go side by side |
| science corridor lined with bio closets, coffins in the chapel's | | the habits pass furnished corridor areas as rooms | habits skips the learned corridors |
| function review problems | 23 | later passes moved walls and added things | audit.mend: forge/function.py fixes over every room as the last pass |

More, found reading the cards and pictures:

| Finding | Cause | Fix |
|---|---|---|
| orphan buttons, door timers, airlock controllers (41) | synth copied the exemplar's wall pieces with ids | synth.LINKED skipped; audit "orphan" |
| arrival airlocks unpowered | door tiles in /area/space | doorfix.door_areas |
| starboard maint with no APC (9 doors unpowered) | lost after the shared pass | APC sweep before the grid; APCs deduped |
| SMES boxed in, no terminal | furniture on every side | net.power takes it out |
| NW solar array unreachable | field picked with no catwalk path | net._catwalk: the nearest field a catwalk reaches |
| Atmospherics with gloves and masks but no suit storage or canister | essentials added 4 things, items first | machines and lockers first, 4 of each |
| a second nuke disk in the captain's bedroom | essentials per area | station-unique items never added twice |
| loose conveyor belts in cargo | essentials | linked sets never added |
| radiation/fire closets doubled round the engine | dress on the engine block + learned room | audit.trim to the type's typical count |
| a bar of 17 tiles | squeezed into a strip end / back row | strips and back rows only take rooms that fit |
| big walled-in pockets of space | slots bigger than the learned plans | gen/voids.py: vacant/abandoned rooms with doors to maint or halls |

From the Bot Shifts (f5, f7):

| Finding | Cause | Fix |
|---|---|---|
| supermatter never started (f7: power 1) | trim took the engine block's plasma tank dispenser as "a second one" | dispensers out of trim |
| Engineering Storage unreachable (suits, plasma) | the gravity generator's runtime 3x3 (x-1..x+1, y..y+2) covered the storage door in a 4x4 room | audit.seat_big: moved to clear floor that keeps the room's doors joined; rooms with it planned 5x5+; audit "big" |
| requests consoles' messages never went through | net.power took telecomms' terminal-less SMES: they were its power | /area/tcommsat kept |
| experiments 0 (f7) | explab with an experimentor and no console | essentials WORK_KIT + NEAR: the console beside it |
| scientist killed by the experimentor (f5) | console beside the experimentor; human maps put it in a back room | roomdb.back_first: the type's back rooms furnished first when they hold its one-a-map machine |

From f10's Bot Shift and the new "missing_room" check (room types on every human station family but one):

| Finding | Cause | Fix |
|---|---|---|
| requests never went through (f5-f10) | the telecomms server room (message server, 23 machines) was dropped from the composed AI block at width 17 | compose AI_ANCHORS: other widths until it fits |
| no AI core (f10, and the overnight final) | the core's stock copy wants a frame 27 wide; the AI budget (share 0.026) never got one | program AI_SHARE 0.034 (human look band 0.031-0.044); the core an AI anchor |
| no virology (4 medical plans in 6) | in the program, but sorted behind and the strips filled first | must-have types placed first; must-haves the draw missed added to the program |
| experiments 0 (f10) | a second experimentor (kit entry under another family name) pushed into a 1-tile alcove behind a closet | kit has the console only; added machines need a free tile in front |

Access by job (gen/audit.py job_reach, access lists parsed from code/modules/jobs/job_types): a department's
room its own jobs can't reach from the halls. f7 had 7; Security Main was reached only through the courtroom, whose
door wanted the lawyer's 38. doordb.open_jobs gives the doors on the cheapest way in the department's access as
an alternative (req_one_access), only for rooms whose own learned door the jobs open (the captain's bedroom and the
armory stay shut). Left after: 2, the kinds stock maps show too (Meta 9, Box 4).

## Placement and pathing study (gen/learn/placestudy.py), the user's "extra studying on stock maps"

Learned from ~12,000 pieces on the 8 stock maps: per piece family how often it stands against a wall, on a door's
front, within reach of the doors; per (room type, family) where it stands between the door and the back; per room
type how much floor stays free and how much of it the doors reach. Per 1000 pieces / % of rooms:

| | stock maps | f11 | f11 + settle |
|---|---|---|---|
| off the wall (family 90%+ on a wall) | 3.9-9.1 | 33.1 | 0.7 |
| on a door front (family under 3%) | 1.1-5.6 | 0 | 0 |
| unreachable (family 95%+ reached) | 5.0-10.6 | 16.5 | 7.2 |
| misplaced front/back (out of the type's band) | 0-1.4 | 18.7 | 3.6 |
| rooms cut (doors reach less than the type's 10th pct) | 0.5-2.3% | 4.8% | (synth: CONNECT 0.98) |
| crammed / bare (free floor outside 5th-95th) | 1-3% / 0-1.4% | 12% / 6.4% | (synth: fill band) |

gen/learn/settle.py moves wall-bound, unreachable and misplaced pieces to free wall spots in their band that leave
no free tile newly unreached (run before the networks: bins get their pipes after). synth.furnish keeps 98% of a
room's free floor joined and its dense fill inside the type's stock band (fill_band).

Later in the study: door count per room type (stock 5th-95th; gen/learn/doorcount.py adds a door where a room has
too few, toward the hall/corridor or the neighbour its type shares doors with, removes one where it has too many and
both sides stay reached; corridor areas exempt), main floor turf per type (already matched: 0 odd), free-floor band
(gen/learn/density.py sheds optional furniture from crammed rooms, adds the type's commonest pieces to bare ones),
synth placement scored by the depth bands (W_BAND). Partners found in range, not beside (the experimentor and its
console, 3 tiles) are pinned in settle and re-paired (audit.pair_up); settle once moved them 4 apart and every
experiment failed. Gravity-generator rooms are no longer carved into pieces (no 3x3 plus walkway fit in 3-4 wide
pieces) and are seated before doors are added.

f14 round 0 (settle, doorcount): off-wall 0, unreachable 3.5, misplaced 3.5, doors 4.7%, cut 3.1%, crammed 6.2%,
bare 3.9%; density then took crammed to 0.8% and bare to 0. Bot Shift f14: 4 fails (botany fridge and slimes as
always, experiments from the separated console, a cargo budget "can't afford").

Wall fixtures (stock rooms of 15+ tiles with one): fire alarm 58-86%, light switch 70-86%, extinguisher 30-66%, air
alarm 96-100%; f14 had 49/52/22/90%. gen/learn/fixtures.py hangs the missing ones at the stock door distance (after
the APC sweep: hung first, they took a store's only free wall face and its door had no power). Mount distances to
doors already matched stock (median 2-3 tiles).

Two human measures disagree for our room mix: each type's door count (doorcount raised rooms to their type's 5th
percentile) against the station's one-door share (gate band 0.335-0.448; doorcount took it to 0.24). The human
maps' small one-door rooms are pieces (virology and brig cells, dorm cabins, pens), security checkpoints, servers and
stores; the generator lacked checkpoints entirely. doorcount now keeps the one-door share above 0.37, and medical,
engineering, cargo and science plans get their security checkpoint (5-10 of 7 families have one).

Bot Shift f17 (5 fails): experiments and the hydroponics bay pass now; the CE office had no CE locker (gloves,
cloak) and the R&D lab no console (0 parts printed). essentials WORK_KIT: every head's locker in their office, the R&D
console beside the science lathe; a work piece takes an optional table's wall spot when the room has none free;
a kit piece listed under two family keys is added once.

Bot Shift f19 (7 fails): bar 0 drinks (the bar had no booze dispenser, found later: see f21c below), 13 parts
printed and none installed, cargo slow on both requests drills ("on it"), botany fridge and slimes as always.

Still open: room door counts vs the one-door share (we lack small one-door rooms; checkpoints added), "misplaced" in
big rooms with fewer doors than their stock type (depth measured from fewer doors), shape fails that move with the
block layout (share.medical, halls 7+ wide, hull corners, open maint), the toxins burn chamber (never built).

Not a map fault: the "tired wiring" station look trips one department's lighting each round (science in f11,
medical in f14 boot snapshots).

Must-have rooms in department plans: types on 6+ of 7 human families go first; one left over when the strips fill
(virology, 136 tiles) is retried smaller (half its pieces), then with the rarest optional types dropped.

Door model, held out by map (train on the other maps, predict each door's colour family): 0.72 match against the
human mapper's choice; the old plain-everywhere scheme 0.29.

## Small rooms, depth from the front door, door styles (f20, f21)

The user: "Keep iterating". Measured first (studies/stations.group_of per room piece, 12 tiles or less with one door):

| | rooms | one-door share | small share | small one-door rooms: security / medical / science |
|---|---|---|---|---|
| MetaStation | 173 | 0.28 | 0.33 | 10 / 6 / 8 |
| BoxStation / DeltaStation2 | 140 / 200 | 0.34 / 0.24 | 0.30 / 0.29 | |
| f19 | 109 | 0.30 | 0.25 | 4 / 1 / 4 |
| f21 | 126 | 0.36 | 0.31 | 7 / 5 / 4 |

Causes and fixes:

| Finding | Cause | Fix |
|---|---|---|
| no virology cells in any medical plan | virology is a must-have but a back room: must-first only ordered it inside the back-room list, so it came up with a strip's last 5 tiles (29-55 tiles of its 136) | floorplan: a must-have back room with pieces is placed first at a strip's far end ("tails"); the block crop keeps it. 3-5 cells |
| brig 3-4 cells (human 7), slime pens 3-4 (human 10) | carve() cut one row along one wall | up to two rows on two sides away from the door: prison 5, brig 3-5, xenobiology 5-6 |
| cells with two doors (9 of 20 in f20) | compose.second_doors gives one-door rooms a second door, a one-door neighbour of the same department first: cell to cell | floorplan pieces (16 tiles or less, a pieces type) are left out of it both ways |
| "misplaced" counted from every door: f19 28 per 1000 under a corrected study | the stock bridges' console windoors and vestibules made their consoles read "front"; our rooms with fewer doors than their type had back pieces "misplaced" | placestudy.front_doors: a room's airlocks nearest the halls by walking (hall_dist); study VERSION 6. Stock 0-1.4, f21 5.6 after settle |
| settle boxed three bridge consoles in (f19) | its spot test kept free floor reached, not the other pieces | _spot rejects a move that leaves any reached piece with no reached tile beside it; then a dense neighbour of a boxed piece moves when that opens it |
| a medical "Cloning" door between art storage and an emergency closet (f20, f21) | one human emergency storage (inner side) has a Cloning door to genetics; the learned list for "emergency storage to a room" held that style only | doordb: a style must have a human door joining the same pair of station groups (fits_pair, door_pair); names by pair too; odd styled doors are restyled; audit odd_door counts them (stock maps: 0 such) |

| the bar poured 0 drinks (f19, f21; first put down to the bartender's full bag) | essentials checks a kit piece by family: the soda dispenser (family chem_dispenser/drinks) stood in for the beer dispenser, so every bar had two soda dispensers and no booze; the only beer dispenser was in a maint speakeasy | essentials EXACT_KIT: the beer dispenser by its exact path; a second soda dispenser turns into it. f21c: 27 drinks poured, the order drill passes |
| walls meeting only at a corner (the user: "this awkward diagonal" in medbay) | a wall between two rooms steps a row and its runs never meet | walls.join_corners after walkfix: one wall tile on a bare floor tile of the corner (not a door front, its room stays joined and 6+ tiles); joins with glass or a door at the corner stay, as on the stock maps (Meta 15, Box 7, f21 18) |

Bot Shift f21 (4 fails): botany fridge, slimes, bar x2. f21c (f21 with the beer dispenser): bar passes; upgrades
(0 installed, 30 parts printed) and the evac drill (a cargo technician left behind) failed on the same map that
passed them in f21: run-to-run, not the map.

Gate fails crew 100 seed 7: f19 7 (share.medical, room sizes, halls 7+, hull corners, open maint, function: doors),
f21 4 (skel.aspect, halls 7+ wide, dead ends, open maint): no function fails left in the kept round.

The toxins burn chamber is still not built: bots vent the chamber after a burn (goals/toxins.dm), so it has to open
on space, and the generated toxins room sits in the middle of science. It needs the mixing room placed on the hull
(or a sealed space pocket) plus the launch room's mass driver; the Bot Shift toxins check needs a 40 minute shift and
a mass driver on the map, so our 30 minute shifts skip it.

## Department function passes (five agents, studies/dept_specs/)

The user: "not just counters ... the entire station, kitchen needs a serving window, engineering needs safety,
showers, equipment, think exactly what each department does ... Use 4-5 agents ... departments will be random so it
can vary in size, shape just like real maps but overall it will follow the same functional patterns."

Five agents, one department each (shared brief `studies/dept_specs/BRIEF.md`): each studied its department room by
room on the 7 stock families, wrote a spec with checkable rules at their stock frequency (`<dept>.md`), reviewed f22
room by room, and wrote `gen/learn/fn_<dept>.py` (check + fix). Calibration: the stock maps flag 0-7 each.

| pass | f22 findings before -> after | what it fixes |
|---|---|---|
| fn_engineering | 45 -> 4 | stem end into the engine ("Engine Room" door, access 10), safety vestibule (facing showers, 2 rad closets, fire closet, rad sign), CE's extra door made a shuttered window, hall doors for tech storage/checkpoint/foyer, the 9 circuit-board spawners (none on the station: wall/effect pieces never copied), Atmospherics' desk, access 24 and kit, orphan SMES terminals |
| fn_medical | 29 -> 6 | an operating room (none on f22), the cryo bay (cells + freezer), chemistry desk + wall fridge + shower, NanoMed, morgue trays/access/maint door, genetics' own hall door (was only through the security post, access 63), virology access 39 + monkey pen, cloning reseated |
| fn_service | 23 -> 4 | the produce smartfridge in the hydroponics wall (none on any generated map: why "harvest stocked in the fridge" failed every Bot Shift), the kitchen serving hatch, a bar counter with the machines behind it, hydroponics access 35, theatre 46, cold-room door into the bar walled, janitor's door, a restroom, one crematorium with its button, kitchen counts |
| fn_security_command | 42 -> 26 | timed cells (no door timers on the map: no bot could ever brig anyone), Brig Control's desk, warden locker and consoles, 4 doors between rooms no stock map joins walled, courtroom/detective public doors, maint doors, HoP hall door + queue when it touches a hall |
| fn_science_cargo | 62 -> 21 | cameras in xenobiology (the slime console acts only where a camera sees: why slimes failed every Bot Shift), a kill room, 3 slimes one a pen, pen windoors + blast doors, the explab console 3 tiles from the experimentor (a scientist died there in f5 and f22), 22 cameras, cargo lockers; place_burn_chamber() ready for a mixing lab on the hull |

Station-wide from their findings: room cameras in fixtures.py (stock rooms of 15+ tiles 88-96% have one, f22 6%);
door pairs no stock map joins kept out of compose.second_doors, doorcount and the floorplan's back rows, closets and
cut-offs (doordb.pair_seen, from the 3,565 human airlocks; plans' unseen back doors 90 -> 7 of ~120); desks.py table
per the specs (kitchen hatch, hydroponics, chemistry, warden, HoP always; R&D onto the hall; customs only).

Bot Shift f23b (all five passes, cameras, desks, pair-checked doors): 2 fails, against f22 3 and f19 7. For the
first time on a generated map botany's harvest reached the fridge (42 stocked) and the slimes were fed (6); bar,
experiments, evac pass. Left: upgrades (14 parts printed, collect_prints given up 5 times) and the cargo drill (the
crate for Science left at Science's front doors, more than 15 tiles from its requests console).

Found on f23 and fixed in the generator: science had two R&D labs in every plan (a back row's filler took "lab"
before the program's own lab came up; the empty one got the R&D desk and was reached only through the mech bay):
_filler now skips types the program still has to place. The cargo office's public door kept its access because
doordb.open_public routed the way in through the new cargo desk: counters are no way in.

Builds after f23 (crew 100 seed 7, fresh search each time):

| build | gate fails | Bot Shift fails | note |
|---|---|---|---|
| f23b | 6 (shape, + cargo public rooms fixed after) | 2: upgrades, cargo drill | botany + slimes pass for the first time |
| f24 | 8 (QM office missing, a grav gen cutting its room) | 4 | filler skipping pending types: cargo lost its mining dock in 7 plans of 15 |
| f25 | 10 | 5 (no research: server room empty, R&D lab 17 tiles) | pending types struck at the filler's size |
| f26 | 7, all shape | 4: botany fridge, experiments 0 (36 upgrades instead), both cargo drills (on it / can't afford) | pending types struck at their program size |

f26's kept round had no produce fridge: hydroponics shared no wall with the kitchen and had no free wall tile, so
fn_service now swaps a spare wall piece (never a counter) for it. Experiments 0 with 36 upgrades and cargo "can't
afford" are the bots' time and budget, not the map.

Layout-level backlog (the agents' "generator changes", in the order to take them):
1. Engineering: the engine block's wall row must leave an "Engine Room" door on the stem; a vestibule piece; foyer,
   checkpoint and tech storage on the hall; a secure storage room; Atmospherics' front room.
2. Medical: count must-have rooms by function (surgery is /area/medical/sleeper on Box and Hippie); lobby at the hall
   door; cloning beside genetics and the morgue; virology at most 18% of medical; morgue on the edge.
3. Service: kitchen and hydroponics partners sharing a wall; a restroom as a must-have type; the service corridor a
   staff hall; the theatre beside the bar; the law office out of security; the civic corridor's area not /area/chapel.
4. Security/command: cells with timers in floorplan; partners warden-armory, warden-brig, HoS-office, captain-bridge;
   hall-front rooms (HoP, courtroom, law office, detective); arrivals beside civic/service/dorms (2.29 radii from
   command, stock 0.33-0.93); maint back doors per department (stock 3-20, ours 0-1); a labor dock.
5. Science/cargo: the mixing lab on the hull + burn chamber + mass driver toward the range; cargo built round a bay on
   the hull with conveyors (ours a 2-wide corridor, docks off maint); the science corridor area /area/science/research;
   science's budget (got 603 of 1541 tiles).
6. Wall-set machines (produce/chemistry fridges, vendors) carried by synth/essentials, not patched after.

## Airy rooms, the engine's side, room size and shape (f27-f30)

The user: "it could be a bit more airy, some of the structures block walking and only give 1 tile paths, bigger
departments should shy away from claustrophobic item placement". gen/learn/airy.py: a pinch is a free tile blocked
on both sides along one axis; share of free floor in pinches by room size, stock (Meta, Box, Delta, Hippie, Pubby)
0.14-0.21 / 0.12-0.14 / 0.03-0.06 for rooms of 12-39 / 40-79 / 80+ tiles, ours 0.28 / 0.17-0.22 / 0.13-0.15. The
pass moves the pieces beside pinch tiles to wall spots that lower the count (settle's reach tests), takes a spare
piece out when nothing else works and the room stays inside its type's free-floor band: f26b 0.146 / 0.101 / 0.054.

The user on the engine: "that walk way is a 1 by 1 which looks horrible, 1x1 walkways are for maint, the 3 doors come
out feel strange too ... the 3 airlocks have purpose in meta, the room it opens into has purpose, this is just a dead
end hallway ... many departments and areas of a map feel like they contribute to the structure of the space station
itself". On Meta the core's three west airlocks open on engineering's main floor (4-6 wide: gear tables, vendors),
and that floor's far side is the SMES room, secure storage behind blast doors and a store. gen/net.py engine(): the
block now brings Meta's main floor down the core's side (CTRL_W 4, its tables and gear with it) and three rooms on
the far side (ROOM_D 5: Engine Monitoring behind glass, secure storage packed in rows behind a blast door with its
button, the engine's gas store; order and lengths by seed), falling back to the floor alone, then the old walkway.
Secure storage (the user: "secure storage doesn't look right" at the first scatter-along-the-walls try) is packed as
the stock stores are: dark floor, machines in rows by kind from the back, one aisle in from the blast door.

The user: "I notice you don't go creative with room size and shape, why is that? ... Yes, do it then, fix it."
gen/learn/variety.py measures it (shape classes rect / L / notch / T / Z / other against the bounding box):

| | rooms | size p10/25/50/75/90 | spread | rect | L | T | other |
|---|---|---|---|---|---|---|---|
| stock (8 maps) | 128-200 | 6 / 9-12 / 18-24 / 34-44 / 60-81 | 0.95-1.28 | 0.42-0.63 | 0.04-0.11 | 0.05-0.12 | 0.18-0.32 |
| plans before | 115 | 6 / 12 / 24 / 44 / 62 | 0.79 | 0.60 | 0.26 | 0.03 | 0.05 |
| plans after | 118 | 8 / 12 / 21 / 44 / 63 | 0.89 | 0.57 | 0.13 | 0.07 | 0.18 |

By size the stock rooms of 6-11 tiles are rectangles (0.93), those of 48+ tiles complex shapes (other 0.70).
- Sizes: each room's size is drawn from its type's own stock spread (a bar is 28-144 tiles there), not its median;
  the department's biggest room may be a hall up to 150 (was capped at 90); closets 4-10 tiles, not 8.
- Shapes (gen/learn/reshape.py): each room draws a target class from the stock mix for its type and size and gets
  there by shifting stretches of its walls: a neighbour gains a bump, the hall a nook, or on the block's outer side
  the cells are given up. Door fronts, 2-wide minimum, work sizes and caps kept; no shift may leave two walls meeting
  only at a corner. reshape.trim cuts the block back to what its floor touches: no solid wall blocks behind rooms.
- Departments: a deep strip may open a side corridor off the stem with rooms both sides and now and then a room
  closing its end (floorplan open_bay); a strip may stop short of the block's end (outline steps in).
- Found on the way: the second row of pens took the row xenobiology's door opened on (the lab was entered through a
  pen): a row of pieces never covers a door's front.

Walls that join (the user, four times in one evening: "this awkward diagonal", "this corner has an empty wall, leaving
a diagonal", "now we have double walls, so the departments could just carve them out and have props move into them
properly", "walls need to join without this stupid diagonal"). The rule, checked now by the audit ("diagonal", a
function failure in the build's round choice): no 2x2 square with plain wall on one diagonal and floor on the other.
- gen/walls.py absorb_gaps (before merge_doubles and the networks): a small pocket of space sealed between two walls
  (the engine block stamped one tile from Atmospherics: a 1x2 pocket) is taken over by the rooms beside it: each side
  grows one tile onto its own wall line, or one side two, the edge row moving out with what stands and hangs on it;
  an option is kept only if it leaves no floor of two areas open to each other and no corner-only join. (The first
  version walled the pocket: three walls thick; the second grew the room and the maint niche pass then removed the
  wall under the new alcove: the room stood open to maint.)
- merge_doubles: a hall niche keeps its ends closed (wall, another niche tile, the hall's own floor).
- hull_corners: a hull corner left as space (two hull walls corner to corner round station floor) becomes wall.
- fill_slivers (after seal_hull): what's still sealed and small is closed; blind_windows: a window with nothing to
  look at becomes wall. net.engine scores sites by gap tiles beside the block first: abut or stand clear.
- reshape.fix_diagonals in the plan (22 corner joins in 66 plans before, 1 real one after); join_corners may clear
  loose maint clutter to wall a corner, and runs again after the late passes.

Bot Shift f30: the supermatter never started (power 1): fn_engineering's secure storage had kept the back room's
plasma tank dispenser behind its closed blast door ("setup_supermatter failed (target: the tank dispenser)" 12
times in game.log). _fix_secure now moves every standing piece that isn't secure kit out to the main room first, and
leaves the room alone when one can't move. f31 (sizes x0.85, cap guard, plan diagonals): 6 gate fails
(room_q0.75, room sizes engineering and service, halls 7+ wide, open maint, 1 corner-only join at a chapel corner with
a table on it), Bot Shift 3 fails (experiments never attempted, the two cargo budget drills); supermatter, slimes,
botany, upgrades pass. join_corners now moves the one standing piece off a corner tile (settle._spot) when neither
tile is bare: f31 0 corner-only joins.

f32 (all of the above): 5 gate fails (room_q0.75, room sizes engineering and service, halls 7+ wide, open maint), no
function fails, 0 corner-only joins; Bot Shift 1 fail (experiments never attempted). Its kept layout had no room for
the engine's side rooms (30 wide + margins against a reserve of 31): floor-only fallback.
f33 (reserve 34, block forced as wide): the side rooms fit every round and work (Bot Shift: supermatter power 1657,
2 fails: a bar order drill, a cargo delivery), but the gate went to 14 fails; f34 (reserve 34 overhanging a 25-wide
block): rounds of 20, 11, 13 fails, stopped. The bigger reserve itself upsets the layout search. So the rooms are 3
deep (ROOM_D 3: monitoring 3x4-5, secure storage 3x6-7 with its 14 machines in 3 columns, gas store 3x4-5) and the
reserve is 31 again; the floor may drop to 3 wide before the rooms are given up.

Also for f35: a room grows (when its department is far under budget) no bigger than its type's biggest stock main
room and by x1.35 at most (the SMES room had grown to 65 tiles against the stock 18-48); own back rooms as many as
the stock rooms of the type keep (floorplan backcount(): engineering's main room 3, the gravity generator 2, medbay
2), and departments with no closet types get theirs too (corner_closets returned early: service never got the bar's
backroom); in maint a small light may go with the tile a corner join walls.

f35 (rooms 3 deep, reserve 31): the side rooms fit in all four rounds; 8 gate fails (room_q0.1 9 against 8,
room_q0.75 50 against 47, security's room size, halls 7+ wide, open maint, and three new: a gravity generator with a
corner cut out of its room, a 6-tile medbay back room whose door didn't open on its host, dead ends of 12-13); Bot
Shift 3 fails (supermatter, slimes, botany pass; experiments never attempted; a cargo budget drill; "3 orders placed,
0 crates unloaded": this layout's supply dock opens into a 3-wide cluttered cargo room: cargo is still not built
round a bay). For f36: no corner cuts in a room with a 3x3 machine; a back room's door opens on its host's floor.

f36: kept a round with 5 gate fails, of which "floor reached: 403 tiles no walk reaches": the engine room was sealed.
fn_engineering._fix_engine_doors walls a store's door into the engine "while another way in stays", and counted the
new side rooms' airlocks (off the engine's own floor) as ways in: it walled the engine's one door. It now keeps the
door unless the engine-side tile is still walked to from the halls (audit._reach_all), and "floor reached" weighs as
an essential in the round choice. Two corner-only joins left on f36 were hall-edge nooks (a 2-tile piece of
maint-area floor counted as a room too small to lose a tile; a maint tile with a pipe on it): halls and maint count
as one floor for the room test, pipes and cables stay under a joining wall. f32, f33, f35, f36 re-run: 0 left.

f37 (all of the above; crew 100 seed 7): 4 gate fails, each by a hair (radial.command 0.078 against 0.079,
share.engineering 0.105 against 0.104, one walk loop where the band starts at 2, open maint 0.151 against 0.146); no
room-size, function or wall-join fail; audit diagonal 0; the engine's side rooms in, the engine reached. Variety:
103-105 rooms, sizes 9 / 12 / 24 / 41 / 68, rect 0.48, L 0.16, T 0.04, other 0.26. Bot Shift 2 fails: the cargo
delivery drill (crate left in the hall), and "kitchen: 0 dishes" (the cook never started a dish in this run: 9 goals
all shift, waiting on medicine three times; the kitchen has its machines, fridge, tables, hatch and access 28:
no map cause found, not seen in f32-f35).

Still open after this pass (layout): cargo built round a bay (f35's dock opened into a 3-wide room and no crate came
off the shuttle); small sub-rooms short of stock (pieces p10/p25 9 / 12-15 against 6 / 9-12: vestibules, airlock
rooms, booths); departments reach 35-75% of their floor budget (each room type once); the toxins burn chamber; the
service and engineering layout items in the list above.

f30 (first build with the spurs and the size draw): 13 gate fails, the size quartiles a class too big (9 / 14 / 51
against the bands' 8 / 12 / 47), a 54-tile janitor's closet, the gravity generator's footprint stood on by a late
pass. For f31: drawn sizes x0.85 (the hall aside), cap_rooms again after the shape pass, seat_big again after the
late passes.

## Cargo round its bay; plan faults found on the way (f39)

The user picked nothing between the two open layout items ("Any"); cargo first, because it broke function.

**What was wrong.** On f37 the cargo bay was a 29-tile room inside the block (x 80-88, y 144-147) and the supply
shuttle docked onto the mining office. On f35 it docked onto a 3-wide room and no crate was unloaded. Cause: the bay
was one more room in a strip. In a narrow slot (14 wide) a strip is 4 deep, so the bay came out 4 x 9; and nothing
put it on the hull, so `net.docks` fell back to any hull wall of the department. Stock (8 maps of 8): the bay is
the department's hall (157 tiles, 75-249), on the hull, the supply dock into it, the office, QM and warehouse round
it.

**The plan (gen/learn/floorplan.py `HUB`).** A department can name a hub room. It leaves the strips' program and
goes across the block's far end, over the stem: the stem is a short lobby that ends at the bay's door, the rooms
either side are the department's front (office first, as before). Size 0.3-0.4 of the department's floor (60-170).
Where the block is wider than the bay, the cells beside it take a room that opens off the bay (the mining dock
first, then the warehouse: both want the hull too). Rooms that end against the bay and sit beside it on the stock
maps (QM office, cargo office, warehouse, mining office) get a door onto it, and two window panes if their type is
glazed on stock maps. The bay keeps 0.88 of its floor through the shape pass. One bay only (the filler and the
cut-room retype no longer make a second "/storage").

**The dock (gen/net.py).** `bay_to_hull`: where a maint corridor (1-3 wide) lies between the bay's wall and the hull
wall, the bay takes it for the longest such run (9+ tiles), and the corridor is shut at both ends with a maintenance
airlock into the bay (stock: maint doors into the bay on 6 of 8, the dock across maint on none). `supply_dock`: Box's
dock strip on the bay's hull wall, turned to the hull's side: two cycling airlocks, two conveyor lanes with blast
doors and plastic flaps, the belts into the bay (up to 7), their switches and door buttons, the port past it. The
mining dock room reaches the hull the same way (5+ tiles) before its head-on dock.

**Rooms left out of plans.** The mining dock vanished from 9 cargo plans in 72: rooms come out bigger than their
program size (a strip's depth rounds them up, the last rooms grow to the strip's end), so the strips fill before
the program does and the rest was dropped; a later cut then made a 9-tile "mining dock" off the checkpoint. Cargo now
plans again deeper by the rows the leftover rooms take while the slot has depth (`DEEPEN`). The same drop happens in
every department at f37's budgets (8 seeds each): medical loses surgery 4 and cryo 4 of 8, security the range 5,
command the meeting room 3 and the vault 2, science its checkpoint 8; floor reached 0.68-0.91 of budget. With the
deeper retry for all: nothing dropped, floor 0.81-1.12. That is the "departments reach 35-75% of their budget" item
above; it goes in the build after f39 so each change is judged alone.

**Plan faults (new tool gen/learn/plancheck.py).** The plan checker from the shape work is now a tool (structure
faults per plan, `--dept` for a department's frames and hub figures, `--dump` for one plan as text). First run: 208
"rooms touch" in 84 plans (two rooms with no wall between), 10 doors into walls, 6 rooms off their doors, 20
diagonal joins. Causes and fixes:
- a back row's leftover cells joined the front room from the wall line on, opening it to the last back room: a few
  cells go to the back room, more become the front room's leg behind a wall;
- `cap_rooms` cut a room in front of a door, or left the room's own door with the part cut off: the cut skips door
  fronts, keeps the door with the kept part, and leaves no corner-only join;
- `reshape.fix_diagonals` refused every cell of a room that already had a 1-wide nook: it now compares 1-wide floor
  before and after, and takes the stub with the cell;
- `reshape.separate`: a last pass that walls any two rooms still side by side (2 in 168 plans, three steps together).
After: 252 plans (18 seeds, 14 frames), 0 faults. Shape variety unchanged (rect 0.55, L 0.14, other 0.18, cv 0.90).

**Builds (crew 100 seed 7).**

| build | what was new | gate fails | function fails |
|---|---|---|---|
| f37 | before this section | 4 | none |
| f39 | hub plan, bay to hull, dock strip; plan-fault fixes | 8 | ways in (4 rooms reached only through maint) |
| f40 | + every department deeper, mining dock tries walls, ways-in fixes | 10 | wall joins (1) |
| f41 | + engineering's budget less the engine block, pocket doors, cells | 9 | none |
| f42 | engineering out of the deeper retry, budget cut dropped | 4 | big machines (gravity generator) |
| f43 | + gravity generator room kept whole | 3 | none |

What each build taught:
- f39 "ways in": fn_security_command walled the brig's door into the HoS's office because the office's maint door
  counted as another way in, then "kept" the maint door as the only one. doorcount took a room's inner door first and
  left the mining dock room (two new maint airlocks) with maint doors alone. Both now keep a way in that isn't through
  maint.
- f40 wall joins: a maintenance hatch from the vacant office onto a single tile at a hall corner. doorfix.pockets:
  a door onto an empty pocket of one or two tiles, with no other door, window or way on, is walled up with it.
- f40/f41 engineering: its block is as wide as the engine behind it whatever its program, so the deeper retry only
  added floor (share 0.113 against the band's 0.104, median room 34.5). Taking 200 tiles off its budget made it worse
  (median 39): with fewer rooms in the program compose widened the block and the strips' depth sized the rooms.
  Engineering is out of DEEPEN; PLAN_LESS is left empty with the reason.
- f42 big machines: the gravity generator's room came out 6 x 4. Three causes, all plan level (plancheck's new "big
  machine room under 5x5", 39 engineering plans of 60): placed in a strip's last rows; taken as a back row behind a
  4-row room; reshaped, jogged or cut afterwards; and a second, 20-tile "gravity generator" came out as a closet
  type. Now: 5 rows of strip or the plan again deeper, a back row only at 5 by 5, the room flagged `whole` (no jog,
  cut or shape shift), never a filler or closet type. 60 plans of 60 hold 5 x 5.
- Cells: the prison kept no cells in 6 plans of 12 and the brig in 3 (stock 3 and 4 a map). The row now tries the
  room's other walls and cells turned 3 x 2, and a pieces room wants strip length for its row (deeper retry if none):
  brig 12 of 12, prison 9 of 12.
- f43's dock still crossed maint: the hull behind the bay was glazed every other tile and the hull test took bare
  wall only, so no run of 9 was found. net._hullish (wall or window) in bay_to_hull, the strip's fit and
  _hull_cands; docks() tries the strip first and takes the maint when no wall of the bay fits it. Dry run on f43's
  bay: 98 -> 124 tiles, maint airlock at each end, strip with 7 belts.

With every room of the program placed (f43 against f37): 152 rooms against 139; surgery, medical storage, the firing
range, processing, the education chamber, the transfer centre, the SMES room, the library lounge, a misc lab and the
science checkpoint are there from the plan and not from a later patch.

**The user's budget question (same day): "departments could get budget from emptish rooms that don't need to be big,
or just increase station budget, allocating to rooms where the appropriate size for function and usability is
needed".** Measured on f42, each area's main room against the stock median of its type (86 rooms):
- 10 rooms at 1.3x stock or more, 233 tiles over: transfer centre 57 (stock 20), CE's office 51 (24), warden 54
  (32), processing 39 (20), shared engineering storage 36 (17), surgery 42 (25), range 36 (23).
- 28 rooms at 0.7x or less, 780 tiles short: bar 37 (stock 121), locker room 31 (104), recreation 21 (108), bridge
  48 (107), prison 38 (83), captain's office 23 (54), primary tool storage 34 (64), mining dock 27 (51), morgue 18
  (39), armory 22 (40), genetics 18 (37).
So both halves of the idea hold: the spare floor exists but covers under a third of what the short rooms lack; the
rest needs budget (about 550 tiles, 6% of the station's floor). The short rooms are mostly the ones people gather in.
Not built yet: a size-by-need pass (a ceiling near the stock median for rooms with little work in them, a floor at
the work size for the rest, the difference and a budget rise to the gathering rooms).

**Later the same day (f45-f49): the user's "random windows that spawn on their own turf in space" and "floating
apc ... what is this room".**
- Stray windows: connect.prune_stubs turns walls with no floor round them to space and skipped windows, so an old
  outer wall line stood as single panes off the hull every other tile (f46: 10). walls.clear_stray_glass sweeps
  every window with no floor or door round it (8 ways) after the last wall passes; audit "stray_window" fails
  "function: wall joins". Picture: data/previews/mapforge/stray_windows/sheet.png.
- The room in the user's picture (f46, 66-69 x 71-73): a 12-tile maint room copied from DeltaStation by the maint
  dressing (white floor, plants, an IV drip, a crate), sitting in a bump of the hull. Its APC came with the copy as
  /auto_name/west on a tile whose wall is to the south, so it stood mid-room; its vent and scrubber went onto the two
  spots Delta's room marked for canisters (turf_decal/bot), hence the hazard boxes. gen/mounts.py: every wall mount
  (APC by its path, lights by dir, the rest by pixel offset) hangs on a side of its tile that is a wall, else moves to
  the nearest tile of its room with one; spot markings under vents go. Audit "floating_mount" fails the new hard check
  "function: wall mounts" (ESSENTIAL). Stock Meta has 27 such of 2149 (buttons, signs), never an APC.
- The disposal exit was walled: seal_hull walls space beside station floor and walled the mass driver's throw line
  (f46: trash would hit r_wall). The line stays open and the floor beside it is walled instead; audit
  "blocked_driver" fails "function: big machines".
- Rooms reached only through maint (f45: the CE's back room behind a maint store): floorplan.reach_rooms gives such a
  room a door through a straight wall to the corridor or a room a human map joins it to, else the store becomes the
  department's store; types stock maps reach through maint (janitor, tech storage, detective) are allowed
  (forge/walk.py stock maint_only). plancheck: 0 in 384 plans.
- Mining dock: a hull wall of the room isn't enough, the shuttle must fit there (dry run); else the room takes the
  maint behind it (f48's went across maint from the corridor).
- Cargo strip geometry: on f48 the bay's 12-tile hull wall had a department below and maint above, and the shuttle's
  12 x 7 rect fit one tile short of where the strip's two airlocks must line up with the shuttle's; the head-on dock
  into the bay (6-tile arm) was used. Mirroring the strip would misalign the shuttle's doors, so it isn't done.

**The dock strip's fit (the user: "fix dock strip first").** Why it missed on f47-f49: the layout put another block at
the bay's corner, so the shuttle's 12 x 7 rect (and its ring) had no room past the bay's hull wall where the strip's
airlocks must line up with the shuttle's. Mirroring the strip would misalign the doors, and an arm doesn't help
(the neighbour runs out as far). So the layout decides it: net.strip_fits(m) is a dry run of the strip (with the bay
taking the maint behind it when it must) on the block-stage map, and gen/build.py measure() adds it as a block check
"cargo dock strip" that weighs as 3 band fails in the search and repair (BLOCK_HEAVY). On crew 100 seed 7 about 40%
of block layouts miss it; f50 and f51 have it in all four rounds: 145-tile bay, 14 belts, 2 flaps, 4 airlocks, 8
crates unloaded in the shift. Cost: f50/f51 land on another layout with 8 shape fails (small-room quantiles 8.7
against 8.0 and 12.25 against 12, halls 7+ wide 0.218 against 0.195, maint pockets 0.714 against 0.675, one dead end
of 6 against 5) where f49 had 5.
- f50's Bot Shift failed science (no upgrades, no experiments): the xenobiology lab got one shield generator, not
  the pair; fn_science_cargo.shield_gens skipped a lone one, which stood mid-passage and with a table and a disposal
  bin cut the lab in two; the scientist was stuck behind it all shift. A lone generator now gets its partner and the
  pair goes to the entrance's corners, or it is taken out.
- The shield pair didn't bring science back (f51: still 0 upgrades, 0 experiments). The scientist had "no path" to
  a piece of the research corridor (the parts it needed lay there): the door into it from the stem was a command
  airlock with the RD's 30 (styled when its inner side was judged another room), and its only other way in ran
  through the server room, whose R&D server heats it over a shift until the bots' door rules turn back from the
  air. audit.job_reach pooled every science job's access, so the RD's 30 hid it. Now each piece (4+ tiles, entered
  by an airlock) of an area is judged with the least access of the jobs meant to enter it (those holding the area's
  own learned door access), server rooms and chambers end a way but never carry one on (audit.NO_THROUGH), and
  doordb.open_jobs, run again after the late passes, opens the cheapest door for them in the room's own style and
  name ("Research Division Access", research, 30;47). On f44, f49 and f52 alike it found such pieces (4 doors each).
- Still open: the mining dock room sits inside the block on this layout (no hull near it), so the mining dock goes
  across maint (C2). The fix is the plan's: the mining dock beside the bay on the hull when the bay leaves room.

## Results

| crew 100 seed 7 | overnight final | f6 | f7 |
|---|---|---|---|
| gate fails | 5 | 5 | 5 |
| dead / plain doors | 6 / 168 | 0 / 0 | 0 / 0 |
| unpowered doors | 2 | 0 | 0 |
| machine over-counts (room / type) | 19 / 45 | 3 / 3 | 3 / 3 |
| orphans | 41 | 0 | 0 |
| dark rooms (all stock-like: crystal, test range, a pipe nook) | 10 | 3 | 3 |
| function review problems | 23 | 1 | 1 |

Bot Shift on f5 (before the APC, solar, essentials fixes): 7 fails. The one scientist was killed at 7:19 by the
experimentor's fireball in the explab (human maps keep the experimentor in a back room apart from its console);
research, upgrades and both requests-console drills failed with him. Botany fridge and slimes fail as before.
