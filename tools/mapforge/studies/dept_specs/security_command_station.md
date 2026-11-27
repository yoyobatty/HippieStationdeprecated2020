# Security, Command and the station as a whole: function spec (2026-11-26)

Scope: Security (brig, cells and timers, Brig Control, armory, office and gear, HoS, courtroom, law office, prison
wing, labor dock and transfer, detective, the posts), Command (bridge, captain's office and quarters, HoP and the
queue, vault, EVA, teleporter, gateway, AI upload, telecomms control, the command hall), and the whole station (halls,
arrivals and escape, who sits next to whom, routes, maint backs, the "generated" look).

Measured, not remembered: `security_command_work/study.py` runs `gen/learn/fn_security_command.measure()` over the 8
stock maps (Meta, Box, Delta, Pubby, Donut, Endo, Hippie, MetaLake; MetaLake is Meta's copy, so counts below are over
**7 families**) and writes `security_command_work/study.json`; `table.py` prints it. Door pairs between room kinds:
`security_command_work/door_pairs.txt`. Generated map reviewed: `data/mapforge/gen_learn/f22_c100_s7.dmm` (crew 100,
seed 7), cross-checked on `f21c_c100_s7.dmm`. Tools used: `gen/roomreview.py` (cards + pictures), `gen/audit.py`,
`forge/walk.py`, `gen/learn/placestudy.py --check`, `forge/render.py`, and scratch tools in
`security_command_work/` (`shot.py` grid renders, `groupmap.py` station-by-group sheets, `desk_debug.py`,
`areas.py`).

Pictures: `data/previews/mapforge/dept_security_command/` - `groups_f22_meta_box_delta.png` (whole stations coloured
by group, f22 beside Meta, Box, Delta), `meta_security.png`, `box_security.png`, `delta_security.png`,
`f22_sec_grid.png`, `f22_cmd_grid.png` (f22 with a tile grid), `sec_before_after.png`, `brig_before_after.png`,
`cmd_before_after.png` (fn fix), `rr_f22_security/`, `rr_f22_heads/`, `rr_f22_bridge/`, `rr_f22fn_security/` (room
cards before / after).

## 1. Security on the stock maps, room by room

Sizes are floor tiles (Box / Delta / Donut / Endo / Hippie / Meta / Pubby; f22 in brackets).

| room | stock | size | what it is for, what it holds | joins (families with that door) |
|---|---|---|---|---|
| Brig (hall + cells) | 7/7 | 129-213 (f22 brig 54 + corridor 78) | the hub: the front door from the public hall, the cells along its hall, the timers outside each cell, a front desk where the public reports a crime | hall 6/7, office 7/7, Brig Control 7/7, prison 5/7, courtroom 4/7, labor dock 3/7, maint 3/7; front desk onto the hall 5/7 (Meta "Security Desk", Box/Pubby "Brig Desk", Delta), access 1 (Meta/Box/Pubby) or 63 (Delta), shutters 4/4 |
| Cells (in the brig's area) | 7/7, **3-4 timed cells** a brig (Delta, Endo: also one in each post) | **6** each (2x3) | a cell windoor (`brigdoor/security/cell`, id "Cell N"), **a door timer 1-2 tiles from the door outside** (Endo 3 and 6), a flasher with the cell's id, **a brig locker with the cell's id** (confiscated kit; the timer locks it), a bed: 7/7 cells have all | off the brig's hall only |
| Brig Control (warden) | 7/7 | 32-92 (25) | the Warden's post: **a desk onto the brig** (7/7: brigdoor access 3 inside, a plain "Reception/Outer Window" outside), warden's locker 7/7, prisoner management console 7/7, camera console 7/7, records console 7/7, rechargers; Meta/Endo also keep the officers' lockers here (79/92 tiles) | brig 7/7, **armory 7/7** (airlock or windoor), office 5/7 |
| Armory | 7/7 | 29-64 (35) | riot gear, guns, the armory locker; only Warden/HoS (access 3) | **Brig Control 7/7**, brig/office through a desk 4/7; never a hall, never a non-Security room |
| Security Office (main) | 7/7 | 95-120 (91) | roundstart, briefing tables, officers' lockers (6-8 in Security: office 4/7, Brig Control 2/7, brig 1/7), SecTech vendor 7/7, camera + records consoles 7/7 | brig 7/7, **HoS 7/7**, Brig Control 5/7, maint 5/7 |
| HoS office | 7/7 | 25-65 (32) | HoS locker 7/7, records 7/7, cameras, HoS ID console | **office 7/7** (only) |
| Courtroom | 6/7 | 59-121 (42) | judge's bench, jury, witness stand, gallery | **public hall door 5/6**, brig (the dock) 4/6, law office 2/6, maint 4/6 |
| Law office | 7/7 | 19-30 (16) | the lawyer (access 38, 42, 63) | hall 6/7, maint 6/7, courtroom 2/7 |
| Detective | 7/7 | 24-83 (18) | detective locker, forensics (wooden TV) console, filing cabinets, evidence | hall 6/7, maint 5/7, brig 1/7 |
| Prison wing | 7/7 | 107-206 (102) | perma cells (flashers "PCell", no timers), garden, kitchen, showers | brig 5/7, transfer 4/7, education 2/7, labor 1/7 |
| Labor dock (processing) | 5/7 + Meta/Pubby in the brig | 10-50 (28) | **the labor shuttle's dock (`laborcamp_home`: 7/7)**, labor shuttle console 7/7, gulag teleporter 7/7 | brig 3/7, maint 4/7, hall 2/7 |
| Transfer / education | 5/7 / 2/7 | 28-56 | execution, the education chamber | prison 4/7 / prison 2/7 (only) |
| Range | 2/7 | 23-32 | targets | office 1/7, brig 1/7, maint 2/7 |
| Evidence | 2/7 (Meta, Delta: in Brig Control) | | evidence lockers | |
| Posts | med 7/7, sci 6/7, eng 5/7, cargo 6/7; **arrivals customs 4/7**, escape 2/7 | 8-39 | sec locker, records, cameras, recharger, a desk (customs onto the arrivals hall) | into their department 5-7/7; customs: hall 4/4, maint 3/4 |

### Security, as each role plays it

- **Officer**: spawns in the office, takes kit from a locker and the SecTech vendor, patrols out of the front door.
  Arrests: drags the prisoner in through the front, along the brig hall to a free cell, opens the cell windoor (brig
  access), puts the prisoner and their kit (into the cell's brig locker) in, sets the timer on the wall outside. The
  bots do the same (`goals/security_patrol.dm`: `find_free_brig_cell` looks for door timers; `bot_get_cell_interior`
  floods the cell from the timer's linked cell windoor along its dir; `bot_find_cell_locker` wants the brig locker).
  **No door timer on the map = nobody is ever brigged.**
- **Warden**: sits in Brig Control at the desk onto the brig, watching the cameras, the prisoner console and the
  timers across the hall, hands gear out of the armory behind him.
- **HoS**: office off the Security Office; records, cameras, his locker.
- **Detective**: an office the public can find (hall 6/7) with a back way to maint (5/7); evidence and forensics.
- **Lawyer**: office on a hall, next to the courtroom on Meta/Delta; reaches the courtroom from the hall (public).
- **Public**: reports at the front desk; watches trials from the courtroom gallery.

## 2. Command on the stock maps

| room | stock | size | what it holds | joins |
|---|---|---|---|---|
| Bridge | 7/7 | 81-161 (92, in 3 pieces) | comms, ID, crew monitor, cameras, records, station alert, power consoles | hall 6/7 (Meta: the command hall), **captain 6/6**, HoP 4/7, meeting room 3/7, upload 3/7; on the station's front with space windows: Meta 15, Delta 17, Pubby 16 window tiles (Box 0) |
| Captain's office | 6/7 (Meta: one office+quarters area) | 21-74 (24) | captain's locker, comms + ID consoles, the disk | **bridge 6/6**, maint 3/7 |
| Captain's quarters | 4/7 | 12-68 (22) | bed, dresser, shower/toilet | office 2/4, bridge 2/4, Meta the command hall; never another room |
| HoP office | 7/7 | 32-73 (22) | ID console behind the desk, HoP locker, recharger, privacy shutters | **desk onto a public hall 7/7** (Donut through shutters), **hall airlock 6/7**, bridge 4/7, meeting room 3/7, command hall 2/7 |
| HoP queue | 4/4 measured (Meta, Box, Delta, Pubby) | | on the hall in front of the desk: the customer's tile (delivery decal + the "hopflash" flasher), 3 queue tiles along the wall (bot decals), a loading-area decal on the shutter, a paper table, windows beside the desk | |
| Vault | 7/7 | **20-43** (51 in two pieces) | the self-destruct nuke, bank machine, gold/silver crates, safe | **one door**: hall 3/7, maint 1/7, or inside Security (Meta, Delta, Endo: `/area/security/nuke_storage`) |
| EVA | 6/7 | 31-78 (42) | suit storage units, jetpacks, magboots | hall 4/7, command hall 2/7, maint 2/7 |
| Teleporter | 7/7 | 17-33 (18) | hub, station, console | hall 5/7, command hall 2/7, maint 2/7 |
| Gateway | 7/7 | 23-53 (27) | the gateway, kit racks | hall 5/7, command hall 2/7, maint 3/7 |
| AI upload | 7/7 | 25-51 | upload consoles | bridge 3/7 or the AI block 3/7 |
| Telecomms control | 7/7 | 28-69 | | the AI/telecomms block 7/7 |

Doors stock never makes (0/7): vault into EVA or the showroom, the captain's quarters into the gateway, the captain's
office into the teleporter, EVA into the HoP, the armory into anything but Security, the education chamber onto a
hall. Full list: `STOCK_DOOR_PAIRS` in `fn_security_command.py`.

### Command, as each role plays it

- **Captain**: from his quarters through his office onto the bridge, all without crossing a public hall.
- **HoP**: sits behind the desk; crew queue on the hall in front, hand over their ID on the desk. The bots
  (`bot_hopping.dm`): `job_transfer` walks to `department_doorstep(null, /area/crew_quarters/heads/hop)`, which needs
  **an airlock whose own tile is in the HoP's area with a hallway tile beside it**, and drops the card there.
- **Crew**: EVA, teleporter, gateway reached from a hall or the command hall with their access.

## 3. The station as a whole

The gate already bounds the skeleton (hub loop, spokes, hall share, aspect), dead ends (`forge/walk.py`: f22 0 stubs,
stock 0.64-2.93/1k) and open maint (f22 0.178, stock max 0.146). What it doesn't measure, measured here (radii =
walking steps / sqrt(station floor / pi); Endo left out: its halls are not hallway areas):

| | Box | Delta | Donut | Hippie | Meta | Pubby | **f22** |
|---|---|---|---|---|---|---|---|
| arrivals -> command's first floor | 0.46 | 0.93 | 0.33 | 0.53 | 0.73 | 0.89 | **2.29** |
| arrivals -> Security (no posts) | 1.43 | 0.93 | 1.02 | 1.31 | 1.32 | 0.67 | **2.89** |
| arrivals -> nearest civic/service/dorms | 0.02 | 0.02 | 0.18 | 0.02 | 0.02 | 0.02 | **0.97** |
| maint back doors: security / command | 5 / 3 | 8 / 0 | 3 / 2 | 6 / 3 | 5 / 2 | 5 / 2 | **1 / 0** |
| maint back doors: medical / science / service / dorms | 5/6/7/5 | 12/11/12/6 | 6/3/6/4 | 5/6/8/3 | 16/20/9/6 | 5/8/4/5 | **0/1/0/0** |
| footprint fill of its box: security / command | 0.41/0.23 | 0.17/0.47 | 0.27/0.06 | 0.37/0.31 | 0.33/0.49 | 0.38/0.26 | **0.75/0.75** |

Side by side (`groups_f22_meta_box_delta.png`) the f22 station reads as generated at a glance: every department is
a rectangle with straight edges (fill 0.75 against 0.06-0.49), each split by one straight corridor running its full
height (security x131-134, command x70-72); maint is a thin ring round the outside instead of threading between the
departments' backs; arrivals sits at the end of a 64-tile spoke (x63-82, y112-175) with only science along it, where
the stock maps open arrivals onto civic, service and dorms.

## 4. Checkable rules (fn_security_command.check)

Each line of `check()` starts with the id. Stock counts over 7 families; the stock maps flag only the things their
own family lacks (Meta 0 findings, Box 2: no customs, the courtroom only off maint; Delta 1, Pubby 1, Hippie 2: no
customs, a two-room vault; Donut 5 and Endo 6: no customs, no front desk, Endo's Security front is a window, Donut's
gateway off maint). f22 has 42.

| id | rule | stock |
|---|---|---|
| S1 | 3+ timed brig cells: a door timer, its cell windoor (dir into the cell), interior 2+ tiles | 3-4, 7/7 |
| S1b/c | each brig cell has a brig locker with its id, a bed, a flasher; its timer within 3 of its door | 7/7; 1-2 (Endo 3, 6) |
| S2 | Brig Control has a door onto the brig or its hall (the generator's security corridor counts) | 7/7 |
| S3 | Brig Control has a desk (table + windoor) | 7/7 |
| S3b | Brig Control holds the warden's locker, prisoner management, camera and records consoles | 7/7 each |
| S4 / S4b | no armory door into a non-Security room / the armory is off Brig Control | 7/7 / 7/7 |
| S5 | the HoS office opens into the Security Office | 7/7 |
| S6 / S6b | 4+ officers' lockers in Security / a SecTech vendor in the office, Brig Control or the brig | 6-8 / 7/7 |
| S7 / S7b | a Security front door on a hall / a front desk from the brig onto the hall | 7/7 / 5/7 |
| S8 | the courtroom has a public hall door | 5/6 |
| S9 / S14 | the detective / the law office open on a hall or maint | 7/7 / 7/7 |
| S10 | an arrivals customs post | 4/7 |
| S11 | each department post has a door into its department | 5-7/7 |
| S12 | every door between two of these rooms is a pair some stock map has (`STOCK_DOOR_PAIRS`) | |
| S13 | a labor shuttle dock (`laborcamp_home`) | 7/7 |
| S15 | the lawyer (access 38, 42, 63) reaches the law office and the courtroom | 7/7 |
| C1 | the bridge has a door onto a hall or the command hall | 7/7 |
| C2 / C2b | the captain's office is off the bridge / his quarters off the office, bridge or command hall | 6/6 / 4/4 |
| C3 / C3b | the HoP's desk faces a public hall / a HoP airlock in the HoP's area with a hall tile in front | 7/7 / 6/7 |
| C4 / b / c | the vault has one door / is 20-43 tiles / is one room | 7/7 / 7/7 / 6/7 (Hippie 2) |
| C5-C7 | EVA, teleporter, gateway have a door to a hall or the command hall | 7/7 |
| H1 | maint back doors: Security 3+, Command 1+ | 7/7, 6/7 |
| H2 / H2b | arrivals to command's door within 1.0 radius / to Security's within 1.5 | 0.33-0.93 / 0.67-1.43 |
| H3 | arrivals to the nearest civic/service/dorms door within 0.35 radius | 0.02-0.22 |

## 5. Review of f22 (crew 100 seed 7), defects with places and causes

Security (block x118-151, y59-87; pictures `f22_sec_grid.png`, `rr_f22_security/`):

1. **No door timers, no timed cells** (S1). The brig's three pieces (136-145, 63-66) are rooms with plain airlocks
   (136,63), (139,63), (143,63), one with four chairs; the prison's five pieces (136-150, 68-72) likewise. Stock
   brig lockers with copied ids ("Cell 4" at 139,65, "Cell 1" at 142,60; "engcell" x2 at 127/129,92) point at
   nothing. Causes: `floorplan.carve()` cuts cell pieces with no cell kit; `synth` skips linked pieces (LINKED) so no
   timer or cell windoor is ever placed, but still copies brig lockers with their ids.
2. **Brig Control (126-130, 74-78) is across the corridor from the cells and the armory**, 25 tiles holding five
   officers' lockers, no warden locker, no prisoner/camera/records console (S2 holds through the corridor, S3, S3b,
   S4b). Causes: floorplan strips place rooms by entrance order and `deptdb` nb pairs (armory|warden nb 1.0 is in the
   table but strips don't honour it); `essentials` WORK_KIT has no warden kit; `desks.py` rolled 0.8 and left the desk
   out in the build.
3. **Armory (142-150, 77-81)**: doors into the law office (141,79; access 38: the lawyer walks into the armory) and the
   education chamber (150,81); not off Brig Control (S4, S4b). Causes: layout (above) and second doors (below).
4. **HoS office (119-124, 73-78)** opens into the range (120,79) and Brig Control (125,76), not the Security Office
   (S5); it shares one wall tile with the office (124,73) and a disposal bin stands on the office side.
5. **Courtroom (124-130, 80-85)**: no public door (S8); doors into the range (123,82) and the corridor (131,80, 38);
   42 tiles (stock 59-121).
6. **Detective (136-142, 82-86)**: only into the corridor (135,84) and the education chamber (141,84) (S9).
7. **Law office (136-140, 78-81)**: buried inside Security between the armory and the detective, no hall or maint
   wall (S14); 16 tiles (19-30).
8. **Prisoner Education Chamber (142-150, 82-85)** has an airlock onto the public hall (142,86) and opens into the
   armory and the detective (S12); stock: only off the prison.
9. **Range (119-122, 80-85)** off the HoS and the courtroom; **Transfer Centre (119-122, 60-72)**, 49 tiles with the
   gulag teleporter, only off the Security Office (123,69).
10. **No labor shuttle dock** (S13): the processing room (147-150, 60-66) has the labor shuttle console and nothing
    to call. Cause: `gen/net.py` docks arrivals, supply, mining and the emergency shuttle only.
11. **No arrivals customs** (S10) and no escape post. Cause: `program`/`compose` give posts to departments only.
12. **No front desk** (S7b): the front doors (132-134, 86) fill the corridor's whole hall wall; `desks.spots` needs
    a wall tile 2 from any door.
13. **One maint door** in Security (S/H1; stock 3-9).

Command (block x59-85, y86-108; `f22_cmd_grid.png`, `rr_f22_heads/`, `rr_f22_bridge/`):

14. **The HoP office (74-78, 92-96) touches no hall**: its doors go to the command corridor (73,95) and the meeting
    room (79,94). No desk, no queue (C3), and **no airlock the bots find** (C3b): `department_doorstep` returns null,
    so no bot ever asks for a job transfer. The door tiles also carry the corridor's area (73,95 is
    `/area/crew_quarters/heads`, as is the meeting-room door 79,94); stock door tiles belong to the room they close.
15. **The captain's office (79-84, 87-90) opens only into the teleporter** (78,89); the bridge (74-84, 98-107) is two
    rooms north. **His quarters (60-63, 87-92) open only into the gateway** (64,89), on the far side of the block (C2,
    C2b). Cause: strips, as 2.
16. **The vault is two rooms, 51 tiles** (C4): (60-69, 104-107) with the nuke, doors to the corridor (70,107) and
    **EVA** (67,103); and a second vault (60-63, 93-97) whose only door is **through the corporate showroom** (64,95).
17. The bridge sits inside the block with no window on space (stock 3/4 with 15-17 space windows) and one door (73,99).
18. Command has no maint door (H1; stock 6/7 have 1-3).

Station (`groups_f22_meta_box_delta.png`, `f22_full.png`):

19. **Arrivals at the end of a 64-tile spoke** (63-82, 112-175): command 2.29 radii away (stock 0.33-0.93), Security
    2.89 (0.67-1.43), the nearest civic/service/dorms door 0.97 (0.02-0.22) (H2, H2b, H3). Cause:
    `compose`/`program` place arrivals as a spoke end with science beside it; civic/service/dorms aren't drawn to it.
20. **Department backs have no maint doors**: medical 0, service 0, dorms 0, command 0, science 1, civic 1 (stock
    3-20 each). Maint (1691 floor tiles, as much as Meta) is a ring round the outside, so it reaches few backs. Causes:
    `compose.second_doors` ranks maint last (rank 3) and `doorcount._new_door` scores it 2 (last); compose doesn't
    leave maint between blocks.
21. **13 doors between rooms no stock map joins** (S12; f21c 13 too: teleporter-vault, captain-vault, EVA-HoP,
    captain's quarters-hall ...). Causes: `compose.second_doors` takes "a room of its own department first" (rank 0)
    with no check of the pair, and `doorcount._new_door` scores a neighbour `1 - P(door)` with pairs missing from
    `deptdb.door` allowed at 1.0, the same as any unlikely pair.
22. **The look**: rectangles, one straight corridor per block, rooms in rows; see section 3.

## 6. What fn_security_command.py fixes (on a finished map)

`python tools/mapforge/gen/learn/fn_security_command.py <in.dmm> <out.dmm>`; f22 run log:
`security_command_work/fn_run_f22.txt`, output map `security_command_work/f22_fn.dmm`.

| crew 100 seed 7 | check before | after | fixed |
|---|---|---|---|
| f22 | 42 | 26 | S1 (3 timed cells), S3, S3b x4, S4, S8, S9, S15 x2, S12 13 -> 9, H1 2 -> 1 |
| f21c | 37 | 26 | 2 timed cells (S1 stays: its brig has only two one-door pieces), S3b x2, S8, S9, S15 x2, S12 13 -> 9, H1 2 -> 1 |

- **Cells**: (136,63), (139,63), (143,63) become cell windoors "Cell 1-3" facing into the cells, timers at
  (136,62) west wall, (139,60) south wall, (144,62), flashers, brig lockers with the ids, beds; the waiting-room chairs
  go; the stray "Cell 1" brig locker in the brig lobby (142,60) goes.
- **Doors walled up** (both rooms stay reached, every piece): education onto the hall (142,86), armory into the law
  office (141,79), EVA into the vault (67,103), courtroom into the range (123,82). Kept and reported (a room's only
  way in): the vault-showroom, quarters-gateway, captain-teleporter, armory-education, HoS-range, HoS-Brig Control,
  office-transfer, detective-education, corridor-law office doors.
- **Doors added** (doordb style and name): the courtroom's public glass door (126,86), the detective's hall door
  (138,86, access 4), maint doors from the Security Office (128,59, access 1) and the labor dock (151,61, access 2).
- **Brig Control**: desk onto the security corridor at (131,76) (desks.py, chance 1), the warden's locker, three
  officers' lockers moved to the Security Office, prisoner management, camera and records consoles at (126,78),
  (126,77), (129,78), facing into the room.
- **Lawyer**: reaches the law office through the courtroom's new public door and the courtroom's corridor door (38)
  (`fix_lawyer` adds 63 to a door on the way when there is none, as the stock brig's front door asks for 63).
- **HoP**: `fix_add_doors` gives the HoP a hall airlock in the HoP's own area and `fix_hop_queue` paints the queue
  when the office touches a hall (both tested on Box with its hall airlock walled up / its queue marks stripped: C3b
  passes again, the queue lands on the stock tiles); on f22 and f21c the office touches no hall.
- Checks after: `gen/audit.py` unchanged except Brig Control's missing kit (prisoner, security: done; crew monitor
  left) and one `over_room` (3 brig lockers in the brig area: the audit counts the cells as one room with the lobby;
  Meta's brig has 3 too); `forge/walk.py` no floor newly unreached; placestudy unchanged.
- Pictures: `brig_before_after.png`, `sec_before_after.png`, `cmd_before_after.png`.

Left for the generator: S4b, S5, S7b, S10, S12 x9, S13, S14, C2, C2b, C3, C3b, C4/b/c, H1 (command), H2, H2b, H3.

## 7. gen/learn/desks.py on our map

On f22 desks.py made 6 counters: kitchen->bar x2, chemistry->medbay, R&D lab->research, mail sorting->cargo, and the
engineering and medical posts onto the hall. Brig Control got none in the build (its 0.8 roll failed; with chance 1
it places one at (131,76) onto the security corridor, which is right). The HoP got none: the office shares no wall
with a hall (`desk_debug.py`: shared wall 0). Changes to its `COUNTERS` table, from the stock desks
(Meta, Box, Delta, Pubby read tile by tile):

1. **Brig Control**: chance 0.8 -> **1.0** (7/7). Its style "secure" puts only the brigdoor (access 3) on the owner's
   side; stock 7/7 add **a plain windoor on the brig side** ("Reception Window" / "Outer Window", no access or 63).
   Faces (`/area/security/brig`, `/area/security`, HALL) are right; tiles (1, 2) right (Meta has two desks).
2. **HoP**: chance 0.7 -> **1.0** (7/7); style "hop" needs **privacy shutters** too (`/obj/machinery/door/poddoor/
   shutters/preopen` "Privacy Shutters", 4/4). The queue in front (delivery decal + "hopflash" flasher and its button,
   three bot-decal queue tiles, a paper table) is in `fn_security_command.fix_hop_queue`; desks.py could do it.
3. **A brig front desk row is missing**: owner `/area/security/brig` and the generator's `/area/security`, faces
   (HALL,), style secure **with shutters** ("brig shutters" 4/4), chance 0.7 (5/7), tiles (1, 3), access "1" (Meta,
   Box, Pubby; Delta 63), name "Security Desk". (fn's `fix_front_desk` does it when a spot exists; on f22 none does,
   see 12.)
4. **Checkpoints**: one row (HALL, 0.5, access 63) for every post. Stock: customs and escape posts face the hall
   (Pubby 2, Box's auxiliary 1, Delta/Endo escape), department posts face **their department** (Delta's supply post
   onto cargo) or have no desk; a department post's desk onto the hall is 1/7 (Endo). Split it: customs/escape posts
   (HALL,) at 0.7; department posts (their department's own area,) at 0.3; access "1" (Meta, Box, Pubby) or 63.
5. `spots()` refuses a wall tile within 1 of any door (3x3): fine, but compose should leave 2+ wall tiles between a
   department's front doors and its corner so the brig and HoP desks have a place (f22: none).

## 8. Generator changes (priority order)

1. **Cells with timers** (`gen/learn/floorplan.py` carve(), `synth`): when the brig is carved, give each cell (3-4,
   6 tiles, 2x3, off the brig's hall) its kit as one linked set with a fresh id "Cell N": a
   `brigdoor/security/cell/<dir into the cell>` in the cell's doorway (not an airlock), a `door_timer` on the hall-side
   wall 1-2 tiles from it, a flasher inside, a `secure_closet/brig` with the id, a bed. synth should re-id linked
   pieces instead of skipping them (and stop copying brig lockers with stock ids). fn_security_command.fix_cells is
   the reference (the bots' cell flood reads the windoor's dir). Without it no one is ever brigged.
2. **Door pairs** (`gen/compose.py` second_doors, `gen/learn/doorcount.py` _new_door): join two rooms only when the
   stock maps have a door between their kinds (`fn_security_command.STOCK_DOOR_PAIRS`, or `deptdb.door` > 0 with the
   pair seen on 2+ families); otherwise go to the hall, the department corridor or maint. Never a second door for the
   armory, vault, captain's quarters, Brig Control, prison, education chamber or upload except to their stock
   partners. 13 bad doors on f22 and f21c each.
3. **Must-touch partners in the floorplan** (`floorplan.py` strips; deptdb nb >= 0.8 is not enforced today): Brig
   Control-armory (7/7, a door), Brig Control-brig hall (7/7, a desk), HoS-Security Office (7/7), Security Office-
   brig (7/7), captain's office-bridge (6/6), captain's quarters-office or bridge (4/4). Place the partner in the same
   strip, adjacent, before the strip fills; reject a plan that misses one.
4. **Hall-front rooms on the block edge** (floorplan front list): the HoP office (desk + airlock onto a primary hall:
   7/7, 6/7), the courtroom (public door 5/6), the law office and detective (hall or maint 7/7), EVA, teleporter and
   gateway (hall or command hall 7/7). The block's hall side should take these first. And **door tiles take the inner
   room's area** (doorfix / connect): bot_hopping's `department_doorstep` reads the airlock tile's area; f22's HoP
   doors are `/area/crew_quarters/heads` tiles.
5. **Maint at the departments' backs** (`compose`, `doorcount`): stock per department: security 3-9, command 0-3
   (6/7 have 1+), medical 5-16, science 3-20, service 3-12, civic 3-12, dorms 3-6 maint doors; f22 has 0-1 for most.
   Leave maint corridors between blocks (not only the outer ring) and give each department its stock minimum of
   maint doors where a room shares a wall with maint (fn adds Security's and Command's when the wall is there).
6. **Arrivals** (`compose`/`program`): arrivals on the hub loop or a short spoke whose sides are civic, service or
   dorms (arrivals to the nearest of them 0.02-0.22 radii; command within 0.33-0.93; Security 0.67-1.43). f22: 0.97,
   2.29, 2.89.
7. **Labor dock** (`gen/net.py` docks): a `laborcamp_home` stationary port on the hull at Security's processing room
   (7/7), with the labor shuttle console beside it.
8. **Posts** (`program`): an arrivals customs post (4/7) at the arrivals hall, with a desk onto it; an escape post
   (2/7) optional.
9. **Vault**: one room of 20-43 tiles with one door (hall, maint, command hall or inside Security); floorplan must not
   split a type across two strips (f22's two vault pieces).
10. **Essentials WORK_KIT**: Brig Control: warden's locker, prisoner management, camera and records consoles (7/7
    each); room for them: Brig Control 32+ tiles, or the officers' lockers in the office.
11. **The look**: the security block's brig hall as an L or T with the cells along it and the office/Brig
    Control/armory cluster at its knee (Meta, Box, Delta), block outlines irregular (fill 0.15-0.41, not 0.75), and
    the bridge at the command block's outer face with windows on space (Meta, Delta, Pubby).

## 9. Files

- Spec: `tools/mapforge/studies/dept_specs/security_command_station.md` (this file).
- Pass: `tools/mapforge/gen/learn/fn_security_command.py` (check, fix, measure, routes, STOCK_DOOR_PAIRS).
- Scratch: `tools/mapforge/studies/dept_specs/security_command_work/` (study.py, study.json, table.py,
  door_pairs.txt, shot.py, groupmap.py, desk_debug.py, areas.py, fn_run_f22.txt, fn_run_f21c.txt, f22_fn.dmm,
  f21c_fn.dmm, audit_f22*.txt).
- Pictures: `data/previews/mapforge/dept_security_command/`.
