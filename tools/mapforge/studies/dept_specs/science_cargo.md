# Science and Cargo: department spec (2026-11-26)

Brief: `dept_specs/BRIEF.md`. Map reviewed: `data/mapforge/gen_learn/f22_c100_s7.dmm` (crew 100, seed 7). Findings on
f21c still hold where noted. Pass: `tools/mapforge/gen/learn/fn_science_cargo.py`. Scratch studies and their outputs:
`dept_specs/science_cargo_work/` (`stock_study.py` -> `stock_study.json`, `kit_freq.py` -> `kit_freq.txt`, joins ->
`joins_freq.txt`, `explab_study.py`, `chamber_test.py`, `asciimap.py`, `shots.py`, `compare.py`). Pictures:
`data/previews/mapforge/dept_science_cargo/`.

Tools used: `gen/roomreview.py` (cards of every science and cargo room, `rooms_f22/`), `gen/audit.py --list`,
`gen/learn/placestudy.py --check` and `forge/function.py` (before/after: unchanged by the pass), `forge/render.py`
(all pictures), `forge/atmos.py` (pipe joins of the kill room, the burn chamber and the mixing kit), Bot Shift logs
(`data/mapforge/gen_learn/shift_genF22_c100_s7.log`, `data/logs/2026/11/25/round-22.08.03/game.log`). No build, no
server.

Counts below are "maps of 8" over `forge.corpus.MAPS` (Hippie and Box share a layout, MetaLake is Meta), floor tiles
as median (min-max).

## 1. What was wrong, in order of harm

1. **Slimes never tended (Bot Shift fails every run, f22: "0 fed", feed_slimes 0/5).** The bot feeds and harvests
   from the slime console, and the console only acts where a camera sees (`bot_camera_sees()` in
   `goals/xenobiology.dm`: the spot beside the slime, the kill-room tile, the spot beside the processor must all be
   on the camera net). **The generated xenobiology lab has no camera at all** (f22: 0; the whole generated station
   has 66 cameras, all in halls, the AI block, engine and telecomms; Box has 220, Meta 272, Delta 287). The stock labs have 4-16
   (Meta: one in each pen). The logs match: stock_console succeeds (cubes loaded), feed_slimes fails on its first
   click with no tile to drop a monkey on. Behind it, harvest could never work either: **no kill room** (stock 8 of 8:
   a pen of `/turf/open/floor/circuit/telecomms`, whose TCOMMS_ATMOS air is 80 K, plus a freezer; `find_kill_room()`
   wants a tile under 213 K in the console's own area), **6 slimes** (stock 2-3) with **one loose in the lab** at
   56,164, and the shield generators in the open floor (55,160) where the bot had to push one away.
   Causes: no camera pass anywhere in the generator; `floorplan.carve()` cuts the pens, but no piece is made the kill
   room; `essentials`/synth copy a slime per copied pen; `doordb` styles every pen door as the stock kill room's
   airlock ("Kill Chamber", access 55), because Box's kill room has the only airlock inside a stock xenobiology lab.
2. **The scientist died in the experimentation lab (f22 19:24 at 65,144, and f5 earlier).** The room is 27 tiles
   (stock 49, 33-202), the experimentor at 61,141 with its console beside it at 60,141, **no air vent and no scrubber**
   (stock 7 of 7 have both), no blast doors. Stock maps (7 of 7, `explab_study.py`): the experimentor sits in its own
   12-21 tile test chamber walled off by 3-4 windows and 1-5 blast doors with a button; the console is exactly 3
   tiles away (Chebyshev, inside its oview(3) link range) on the other side of the glass; the room has 1-6
   scrubbers, 1-6 vents, a radiation closet and 2 cameras. Its malfunctions are smoke, 1000 K air, flame bursts,
   radiation and thrown items, all on oview(1) or the room's air; with no vent or scrubber in a 27-tile room the bad
   air stays. Cause: `v6_station.air` gives a supply vent only to a "sealed room" region without one, and the explab
   shares a region with robotics and the nanite lab through their doors, so it got none; scrubbers come only from
   copied stock rooms; `roomdb.back_first`/essentials still put the console beside the machine.
3. **Toxins can't run.** No burn chamber (`/area/science/mixing/chamber`, stock 7 of 8), the mixing lab is 40 tiles
   (stock 89, 81-153) and not on the hull (stock 8 of 8: it vents the chamber to space), no mass driver "toxinsdriver"
   (stock 8 of 8), no freezer on a port in the lab (stock 7 of 8), no portable scrubber in the lab (the bot needs one),
   and the test range (/area/science/test_area) sits at 170-176,182-188, about 120 tiles from science.
4. **Cargo is an office block, not a cargo bay.** Stock cargo (8 of 8) is built round the bay: the supply shuttle docks
   onto the bay's airlocks with conveyors (11-17), plastic flaps (2) and blast doors; the office, sorting, QM office
   and mining open off it. f22 has a 2-wide stem corridor (`/area/quartermaster`, 79 tiles, no stock map has one) with
   small rooms either side; the bay (27-31,114-126) is 59 tiles (stock 157, 87-261) and nowhere near the dock: **the
   supply dock (port 34,148) opens off maintenance** through a 5-tile arm at the end of the stem, the **mining dock
   (port 23,133) opens onto port maintenance** (24,133), 2 tiles from the dock room. No conveyors, no flaps. The cargo
   office (36-39,107-116) has **no front on the hall**: the public walks into the stem (33,106 is public) and the
   office door is off the stem. The QM office (36-39,127-131) doesn't see the bay (stock 8 of 8: door and window
   onto it). Causes: `net.docks` tries the bay first, but floorplan never puts the bay on the block's hull, so
   `head_dock` falls back to "maint and halls near it" with `through=True` (a maint crossing); the cargo plan uses the
   generic stem corridor.
5. **Science layout.** The department got 603 of the 1541 floor tiles it wanted (compose log), so its rooms are
   40-60% of stock: R&D lab 20 (48), robotics 32 (76), mixing 40 (89), explab 27 (49), xenobiology 187 (249).
   `/area/science/research` is a 36-tile dead-end room behind the R&D lab with the department's showers, vending and
   fire closets; on every stock map that area IS the department's corridor and lobby (186 tiles, 7 of 8). The RD
   office (54-58,140-147) is reached only through the server room; the explab only through robotics or the nanite
   lab; the mech bay has no door to robotics (stock 8 of 8); one R&D server (stock 2), no server freezer (stock 8 of 8).
6. **Desks.** No R&D desk, no robotics desk, no cargo desk, no mail desk on f22 (it was built without desks.py).
   desks.py run on f22 puts the R&D desk at 70,162 into the dead-end research room (useless: nobody goes there), the
   mail desk at 35,125 onto the stem; robotics and cargo office rolled none. See section 7.

## 2. Rooms, kit and frequencies (stock)

### Science

| Room (area) | Maps | Floor | Kit on 7-8 of 8 (5-6 noted) | Joins |
|---|---|---|---|---|
| Research corridor and lobby (`/science/research`) | 7 | 186 (145-299) | emergency showers + sinks 7, fire closets 7, coffee + cigarette vending 6, camera 7, blast doors 6 | it IS the corridor: every room below opens onto it |
| R&D lab (`/science/lab`) | 8 | 48 (36-60) | R&D console, protolathe, circuit imprinter, destructive analyzer, cell charger 7, stock parts 7, metal/glass, toolbox 7, shutters + button 8 | desk onto a primary hall 8 (and onto research 4), hall windows 8 |
| Robotics (`/science/robotics/lab`) | 8 | 76 (59-108) | 2-3 exosuit fabricators, R&D console, circuit imprinter, operating table + computer, surgery tools, MMIs, aug manipulator, cell charger, wardrobe, flashes 7, morgue tray 6, shutters 8 | door to the mech bay 8, window to it 7; desk onto a hall 6 |
| Mech bay | 8 | 30 (28-62) | 2-3 recharge ports + power console, 2-3 cyborg rechargers (in science), fuel tank 5 | robotics door 8, hall door 7 |
| Xenobiology | 8 | 249 (210-271) | 2 slime consoles, recycler (same area), processor, extract fridge, 7-9 pens + kill room, 2-3 slimes, 2 cube boxes, 7-10 bins with outlets into the pens, freezer 8 (kill room), 4-16 cameras, chem master 7, grinder 7, 2 bio closets 7, 2 shield generators 7, water tank 8, shower 5 | maint door 7, research door 5 |
| Pens (pieces of xenobiology) | 8 | 8-9 each | windoor front + blast door (14 windoors, 23-30 blast doors, 7-9 buttons), glass to the lab, camera (Meta 9 of 10) | lab only |
| Kill room | 8 | 4-15 | telecomms floor (80 K N2), freezer + siphon (Box), camera (Meta) | "Kill Chamber" airlock |
| Toxins mixing (`/science/mixing`) | 8 | 89 (81-153) | tank dispenser, transfer valves, igniters, signalers, timers 7, analyzer, pipe dispenser 7, bomb closets 6, freezer/heater on ports 7, portable pump 5, portable scrubber 4, doppler array 5 (8 counting misc_lab/research), mass driver 5 (8 likewise) | on the hull 8, maint door 8, windows to research 7 |
| Burn chamber (`/science/mixing/chamber`) | 7 | 18 (14-19) | Box's incinerator_toxmix set: vacuum chamber, injector, scrubber, sparkers, blast doors to space, cycling airlocks, nook with vent button, ignition switch, chamber air alarm | mixing |
| Toxins storage (`/science/storage`) | 8 | 27 (25-47) | canisters (plasma 4-6, O2 4-6, N2O 2, CO2 2, N2 1-2, BZ 1), portable scrubber | mixing 3, research 2 |
| Experimentation lab | 7 | 49 (33-202) | experimentor in a 12-21 tile chamber, console 3 away outside it, blast doors + button 7, scrubber 7, vent 7, radiation closet 7, 2 cameras 7 | research 5, maint 6 |
| Server room | 8 | 17 (13-17) | 2 servers, server control console, freezer 8 | research 7 |
| Nanite lab | 6 | 42 (25-89) | chamber + control, program hub, programmer, cloud controller | research 4 (window 6) |
| Testing lab / range | 5 / 4 | 50 / 52 | targets, recharger, doppler 2, mass driver 2 | maint 6 |
| Test range (`/science/test_area`) | 6 | 25 | out in space 22-59 tiles from the driver | none |
| RD office | 8 | 31 (21-71) | RD locker, robotics + mecha + card consoles, keycard device, AI card, AI core board, lab cage display, suit storage 5 | research door 7, windows 7 |
| Science checkpoint | 8 | 16 | security locker, recharger, pepper tank, security + records consoles | research 7 |

### Cargo

| Room | Maps | Floor | Kit | Joins |
|---|---|---|---|---|
| Cargo bay (`/quartermaster/storage`) | 8 | 157 (87-261) | supply dock airlocks + conveyor run 11-17 + 2 flaps + 2-3 switches + blast doors/button 8, 2 MULEs + 4 nav beacons 7, cargo console 5, wardrobe 6 (8 in the department), crates 6 | supply dock into it 8, QM door 8, office door 7, maint 6 |
| Cargo office | 8 | 71 (37-90) | autolathe, cargo console, desk windoor, photocopier 7, stamps 7, requests console 7, bounty console 5, ORM 4 | public front onto a primary hall 8 (desk 4, door 4, Box an open lobby), hall windows 8, sorting door 7, bay door 7 |
| Mail sorting | 7 | 39 (33-49) | delivery chute 7, conveyors + flaps 7, tagger, wrapping, hand labeler 7, desk 7 | desk onto a hall 6, office door 7 |
| Warehouse | 8 | 29 (20-68) | crates 8, racks 6, blast door 6 | maint 7 |
| QM office | 8 | 20 (13-49) | QM locker, cargo console, bounty 7, QM stamp | bay door 8 and windows 8 |
| Mining dock / mining office | 5 / 3 | 60 / 40 | mining vendor 8, shuttle console 8, 3 miner lockers 8 (in one room), ORM 4 (dock 3, office 1, else office), emergency closet | mining shuttle into it 8; maint 5 |
| Cargo checkpoint | 7 | 13-25 | security locker, consoles | windows onto office or hall |

## 3. Role workflows (what the map must let each do)

- **Scientist (R&D):** in from the hall through the science entrance, R&D console -> deconstruct parts at the
  destructive analyzer -> print at the protolathe/imprinter -> leave prints on the R&D desk for whoever asked; the
  crew collects at the desk from the hall without entering science. Needs: desk onto the hall, materials in reach.
- **Roboticist:** exosuit fabricator -> parts to the operating table -> borgs on the table; mechs walk next door into
  the mech bay to the recharge port; finished parts handed out over the robotics desk.
- **Xenobiologist:** cubes into the console, feed through the console where cameras see, slimes into the cold kill
  room with the console, body to the processor, extracts into the fridge beside it. Never walks into a pen. Needs
  cameras on every pen, the kill room and the processor; the kill room in the console's area; fridge within 4 of the
  processor; windoor + blast-door pens so a breakout can be shut.
- **Toxins:** canisters from storage -> chamber ports (inlet and outlet behind valves) -> ignition switch -> vent
  button blows the burn out to space -> tanks onto a transfer valve -> mass driver -> doppler reads the blast at the
  test range. Needs the chamber on the hull, the driver aimed at the range.
- **Experimenter:** item into the experimentor, tests from beside it, step back into the control side; blast doors
  shut the chamber; scrubbers clear it.
- **RD:** office off the corridor, sees the corridor through glass, server room next door.
- **Cargo technician:** requests at the office desk from the hall, order at the console, crates come off the shuttle
  on the conveyor into the bay, delivered or handed over the desk; mail in by the delivery chute, sorted and tagged at
  the mail desk.
- **Shaft miner:** gear from the mining office/dock lockers and vendor, shuttle from the dock room, ore into the ORM,
  which the public side reads.
- **QM:** office looking onto the bay, approves orders at the console.

## 4. Checkable rules (`fn_science_cargo.check()`)

Rule ids in the text. "Stock" is how many of the 8 maps break it (from `science_cargo_work/stock_check_counts.txt`).

| Rule | Checks | Stock maps breaking it | f22 before | f22 after fix |
|---|---|---|---|---|
| X1-X3 | 2 slime consoles, recycler in their area, processor + extract fridge within 4 | 0 | 0 | 0 |
| X4 | 4+ pens besides the kill room | 0 | 0 | 0 |
| X5 | 2-3 slimes, all in pens | 0 | 2 | 0 |
| X6 | a camera sees a free tile beside each slime, the processor, the kill room | 0 | 7 | 0 |
| X7 | a kill room (cold telecomms pen) | 0 | 1 | 0 |
| X8 | pens behind windoor + blast door, not an airlock | 1 (Donut) | 5 | 0 |
| X9 | a cube box | 0 | 0 | 0 |
| X10 | no open pipe ends round xenobiology | 0 | 0 | 0 |
| X11 | shield generators against a wall | 0 | 1 | 0 |
| E1-E2 | console 2-3 from the experimentor (links in 3) | 0 | 1 | 0 |
| E3 | vent and scrubber in the explab | 0 | 2 | 2 (generator) |
| E4 | blast doors in the explab | 0 | 1 | 1 (generator) |
| T1 | burn chamber with injector, scrubber, air alarm, vent blast doors | 2 | 1 | 1 (generator) |
| T2 | mixing lab on the hull | 0 | 1 | 1 (generator) |
| T3 | toxins mass driver and button | 0 | 1 | 1 (generator) |
| T4 | freezer on a port in mixing | 1 | 1 | 1 (fixed only once a chamber exists) |
| T5-T6 | tank dispenser, doppler array | 0 | 0 | 0 |
| T7 | portable pump and scrubber in mixing (the bot's need) | 4 | 1 | 1 (as T4) |
| S1 | R&D desk onto a hall or the science corridor | 0 | 1 | 1 (desks.py) |
| S2 | robotics desk likewise | 2 (Meta) | 1 | 1 (desks.py) |
| S3 | mech bay door to robotics | 0 | 1 | 1 (generator) |
| S4-S7 | RD office, explab, xenobiology, server room have a door onto the corridor | 1-2 (Pubby, Delta) | 2 | 2 (generator) |
| S7 | 2 servers and a freezer in the server room | 0 | 2 | 2 (generator) |
| S8 | an emergency shower in the corridor or xenobiology | 0 | 0 | 0 |
| S9 | /science/research is not a dead-end room | 0 | 1 | 1 (generator) |
| C1-C2 | supply dock opens into the bay; mining dock into the mining room | 0 | 2 | 2 (generator) |
| C3 | 4+ conveyor belts in the bay | 0 | 1 | 1 (generator) |
| C4 | 3 miner lockers | 0 | 1 | 0 |
| C5-C9 | vendor, ORM, delivery chute, QM locker, autolathe, cargo wardrobe | 1 (Donut chute) | 1 | 0 |
| C10 | cargo office has a front on a hall | 0 | 1 | 1 (desks.py / generator) |
| C11 | QM office joins the bay | 0 | 1 | 1 (generator) |
| C12 | a cargo security post | 1 (Donut) | 0 | 0 |
| K1-K2 | a camera in every science/cargo room of 9+ tiles | 0-5 rooms | 22 | 0 |

Totals: stock maps 2-11 issues each (most of them a room or two without a camera); f22 **62 before, 21 after**.

## 5. f22 room by room (cards in `rooms_f22/`)

Science sits at 45-71,139-172 off the fore primary hall (3 doors at 71,153-155), its corridor `/area/science` running
west along y 153-155.

- **Corridor (46-70,153-155):** 75 tiles, no camera, no shower, no vending (they're in the research room). Stock
  puts the lobby kit at the entrance.
- **Xenobiology (46-60,157-171):** main lab 121 tiles + a 21-tile annex (46-48,161-167, chem master, grinder) + 5
  pens of 9. Pens 46-48/50-52/54-56/58-60 x 169-171 (fronts 47/51/55/59,168) and 46-48,157-159 (front 49,158), each
  behind a "Kill Chamber" airlock; windows only on their space side. Slimes at 47,170 51,170 55,170 59,170 46,157 and
  loose at 56,164. No camera, no kill room, no freezer. Consoles 59,157 and 59,161, processor 57,159, fridge 2 away
  (fine), cubes on the table at 53,157 (fine), shield generators at 50,163 and 55,160 (open floor).
  Fixed by the pass (picture `f22_xeno_sheet.png`).
- **Mixing (62-65,162-171):** 40 tiles, mid-department (maint row y 173, then hull), reached through toxins storage
  (63,161) and the research room (66,171). No chamber, no driver, 2 portable pumps, no portable scrubber, no freezer.
- **Research "lobby" (67-70,163-171):** showers, sinks, coffee/cigarette vending, fire closets: a dead end reached
  through the R&D lab (68,162) and mixing.
- **R&D lab (67-70,157-161):** 20 tiles, no desk, its east wall (x 71) is on the fore hall: the stock desk spot.
- **Toxins storage (62-65,157-161 and 46-48,140-146):** canisters (8 plasma, 7 O2): fine; the second piece is a
  storage annex of the testing lab.
- **Robotics (60-65,146-151) / mech bay (66-70,147-151):** side by side with no door between (S3); robotics has no
  desk; mech bay joins the corridor and the nanite lab.
- **Explab (60-65,140-144):** see section 1.2; console moved by the pass to 64,142 (`f22_explab_sheet.png`).
- **Server (55-58,149-151):** 1 server, no freezer; the RD office's only door leads through it.
- **RD office (54-58,140-147):** door only to the server room.
- **Checkpoint (46-49,148-151):** fine.

Cargo sits at 26-40,106-141 off the port primary hall (stem doors 33-34,106).

- **Stem (33-34,107-141):** the department's corridor; no stock map has one.
- **Bay (27-31,114-126):** 59 tiles, no conveyor, no dock; 2 MULEs, no nav beacons; the wardrobe added by the pass.
- **Warehouse (27-31,107-113), sorting (36-39,117-126), QM (36-39,127-131), office (36-39,107-116):** all off the
  stem; office and sorting join each other (fine); the QM office doesn't see the bay.
- **Mining dock (27-31,131-139) / mining office (36-39,132-139):** 6 miner lockers (3 + 3) and 2 shuttle consoles;
  the shuttle airlock 24,133 opens onto maint 25,133. The pass keeps 3 lockers (2 office, 1 dock).
- **Supply dock:** airlock 34,147 at the end of a maint arm north of the stem (34,141-146).

## 6. What `fn_science_cargo.fix()` does (f22: 44 changes, check 62 -> 21)

Run as the build's last pass, after the networks and `audit.mend` (the kill room must lose its supply vent after
`v6_station.air` puts one in every sealed room). Every move keeps each free tile reached from the room's doors and
every reached piece reachable; no dense piece goes on a door front. `gen/audit.py`, `placestudy --check` and
`forge/function.py` give the same counts before and after on f22.

- Xenobiology (`f22_xeno_sheet.png`): slimes to 3, one per pen (47,170 51,170 55,170); the pen nearest the processor
  (46-48,157-159) becomes the kill room: telecomms floor, supply vent removed and its dead pipe pruned back to the
  line (forge/atmos: no open ends), freezer/on + siphon joined head to head (Box's vars), "Kill Chamber" airlock,
  camera; the other 4 pen fronts become windoor + preopen blast door (`xenobio1-4`) on engine floor, with the
  button on the lab wall where free (3 of 4); free pen walls toward the lab glazed; a camera in each pen (back wall)
  and one over the processor (60,160); the loose shield generator to a wall (50,166).
- Explab: console 60,141 -> 64,142, 3 from the experimentor, facing the room, line of sight kept.
- Cameras in every science and cargo room of 9+ tiles without one (22), on the wall face that sees most of the room,
  networks `ss13,rd` (science) / `ss13,rd,xeno`.
- Cargo: miner lockers 6 -> 3; a cargo wardrobe in the bay (27,122).
- Mixing kit (portable pump, portable scrubber, freezer on its connector) only where a burn chamber exists (on f22
  it would push the 40-tile lab past the stock crammed band); tested on the chamber test maps.
- `place_burn_chamber(m)`: the generator's step for the chamber (section 8), tested in `chamber_test.py`: Box's own
  chamber wiped and placed again comes back identical (45 of 45 cells), and a plain lab with its hull on each of the
  four sides gets it with both lines injector/scrubber -> pump -> valve -> port joined, the find_lab pieces in
  `/area/science/mixing/chamber`, the blast doors on space, the nook and ports reached (`chamber_test_sheet.png`).

## 7. desks.py on our map, and its table

desks.py on f22 (as of tonight): R&D desk at 70,162 into the dead-end `/area/science/research` room; mail desk 35,125
onto the cargo stem; no robotics or cargo desk (their rolls). Changes to `COUNTERS`:

- `/area/science/lab`: faces `(HALL, "/area/science")`, chance 0.95, `req_one_access_txt "7;29"` instead of
  `req_access_txt "7"`. Stock: an R&D desk onto a primary hall on 8 of 8 (onto research 4 of 8 as well, but there
  research is the corridor); the stock windoor is "7;29" on 4 of 4 checked (roboticists collect there too). Drop
  `/area/science/research` while the generator makes it a room (S9); put it back after the corridor fix.
- `/area/science/robotics/lab`: `(HALL, "/area/science")`, chance 0.75 (6 of 8 onto a hall).
- `/area/quartermaster/office`: keep `(HALL, "/area/quartermaster")`, chance 0.9 (8 of 8 have a public front; with our
  office a staff room off the stem, the hall desk is the crew's only way to order).
- `/area/quartermaster/sorting`: chance 0.75 (desk onto a hall 6 of 8), name "Delivery Desk" (Box, Meta, Hippie).
- An R&D/robotics desk faces `HALL` before `/area/science`: on f22 the lab's east wall is the hall.

## 8. Generator changes (priority order)

1. **Run `fn_science_cargo.fix(m, seed, log)` in `gen/build.py` after `audit.mend`** (last pass). It is what makes
   Bot Shift's slime check passable on generated maps: cameras, kill room, slimes in pens. Then the lasting fixes:
   - `gen/learn/floorplan.py carve()`: for `/area/science/xenobiology` mark the piece nearest the console wall as the
     kill room (`kill=True`), the rest pens; paint: kill room turf `/turf/open/floor/circuit/telecomms`; pen fronts
     windoor + blast door instead of a door (`P.doors` entry with style "pen"); glaze the pen walls facing the main
     room (stock pens are glass to the lab).
   - `gen/learn/doordb.py`: no learned airlock style for xenobiology->xenobiology pens (Box's kill-room airlock is the
     only stock sample, so every pen became "Kill Chamber").
   - `station/v6_station.air`: skip regions on `/turf/open/floor/circuit/telecomms` in "every sealed room gets a
     supply vent" (it warms the kill room), as it already skips engine floor.
   - `gen/essentials.py`: xenobiology slimes capped at 3 (stock 2-3), two shield generators placed at the entrance's
     corners (stock 7 of 8).
2. **Cameras station-wide.** The generator never places room cameras (f22: 66 in all, Box 220). Add "camera" to
   `gen/learn/fixtures.py WANT` (stock share per room type; science/cargo rooms 8 of 8 at 9+ tiles, xenobiology one
   per pen), placed like `fn_science_cargo._cam_spot` (the free wall face that sees most of the room, dir away from
   the wall). Without it every console-camera feature (xenobiology, AI, security consoles) is blind.
3. **Explab as a test chamber.** `gen/essentials.py`/`roomdb`: the explab's console 3 tiles (Chebyshev) from the
   experimentor, never beside it; `floorplan`: an explab of 33+ tiles split by a window line with a blast door
   (button on the control side) into a 12-21 tile chamber holding the experimentor; `v6_station.air`: every room
   area (not region) of the crew gets a supply vent, and the explab, xenobiology, mixing, chemistry and virology a
   scrubber as their stock rooms have (explab 7 of 7). f22's explab had neither.
4. **Toxins.**
   a. `floorplan.plan()`: the mixing lab takes a slot on the block's hull edge (the back edge when compose puts the
      block's back on space; the plan needs to know which block edges are hull) at least 5 wide along the hull and 9
      deep, and its program size comes up to the stock 81+ tiles (it got 40). Stock 8 of 8 on the hull.
   b. After furnishing and **before `net.power` and `net.air`**: `fn_science_cargo.place_burn_chamber(m)` (Box's
      incinerator_toxmix chamber, the exact set `goals/toxins.dm find_lab()` looks for). The APC sweep then gives
      `/area/science/mixing/chamber` its APC.
   c. `station/v6_station.air`: leave `/area/science/mixing/chamber` tiles out when collecting vents and scrubbers
      (its scrubber is the chamber's own line to the outlet port, not the station's).
   d. A mass driver `id = "toxinsdriver"` on the mixing lab's hull wall beside the chamber, its blast door
      (`/obj/machinery/door/poddoor{id = "toxinsdriver"}`) in the hull and the `button/massdriver` inside (Box's launch
      corner), and `compose` placing the test site on that line 20-60 tiles out (stock 22-59; now the test-site angle
      is scored 0.03 on the science direction against the gate's aspect/fill terms, so it lands anywhere: f22 ~120
      tiles away).
   e. essentials kit for mixing: freezer and heater on connectors, a portable pump and a portable scrubber (exact
      type `/obj/machinery/portable_atmospherics/scrubber`), canisters stay in storage (`fix_mixing` does the first
      three once a chamber exists).
5. **Cargo round the bay.** `floorplan` for cargo: no stem corridor; the bay is the hub room (stock 157 tiles) on the
   block's hull edge, the office (public front on the primary hall: door + desk, or Box's open lobby), sorting, QM
   office (door + window onto the bay), warehouse and mining open off the bay. `net.docks`: then the supply dock opens
   into the bay; lay Box's dock strip there (blast doors, 2 plastic flaps, the conveyor run into the bay, its
   switches); never `through=True` maint crossings for cargo and mining (stock 0 of 8; f22 has both); the mining dock
   on the mining room's hull wall.
6. **Science corridor = research.** `gen/rooms.py CORRIDOR_AREA["science"]` and floorplan: the department corridor
   is `/area/science/research` (stock), not `/area/science` plus a 36-tile research room; its kit (emergency shower
   and sink, fire closets, vending) at the entrance. Rooms that open onto it on stock maps: RD office 7, server 7,
   checkpoint 7, xenobiology 5, explab 5, nanite 4. Robotics and the mech bay joined by a door (8 of 8), the mech bay
   with its own hall door (7 of 8).
7. **Science's budget.** compose gave science 603 of 1541 wanted tiles (39%); its rooms are 40-60% of stock. The
   block allotment should not cut the department below ~0.8 of its program, or the program should drop optional
   rooms (testing lab, nanite) before shrinking the labs.
8. **Server room:** 2 servers and a freezer (stock 8 of 8) in essentials' kit for `/area/science/server`.

## 9. Pictures

`data/previews/mapforge/dept_science_cargo/`:
- `compare_science.png`, `compare_cargo.png`: Box, Meta, Delta and f22 (after the pass) side by side.
- `f22_xeno_sheet.png`, `f22_explab_sheet.png`, `f22_cargo_sheet.png`, `f22_science_sheet.png`: before/after.
- `chamber_test_sheet.png`: the burn chamber placed on each hull side.
- `rooms_f22/`: roomreview cards of every science and cargo room on f22.
