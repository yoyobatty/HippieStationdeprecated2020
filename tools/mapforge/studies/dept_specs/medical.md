# Medical: department spec (2026-11-26)

Scope: everything under `/area/medical`, the CMO's office (`/area/crew_quarters/heads/cmo`) and the medical security
post (`/area/security/checkpoint/medical`). Bar: the 8 stock maps of `forge.corpus.MAPS` (Meta, Box, Delta best).

Made with (all in `studies/dept_specs/medical_work/`, own scratch):

- `study.py` types every medical room piece **by what it holds**, not by its area name (an operating table makes a
  surgery: Box and Hippie keep theirs in `/area/medical/sleeper`; Delta and Pubby keep cryo in `medbay/central` or
  `sleeper`), then counts per map: types, sizes, door/opening/desk/window pairs, what the public reaches, the hall
  doors, kit per type. Output `study.txt`, `study.json`. `survey.py` is the raw per-area listing (`survey.txt`).
- `shots.py` (labelled crops with coordinates), `ascii.py` (one character a tile, for reading joins), `beforeafter.py`
  (before/after sheets).
- Pictures: `data/previews/mapforge/dept_medical/` - `meta_medical.png`, `box_medical.png`, `delta_medical.png`,
  `f22_medical_before.png` / `_after.png`, `review_f22/` and `review_f21c/` (gen/roomreview.py, one card per room),
  `f22/*_sheet.png` (before/after of every room `fn_medical.py` changes).

Counts below are "n/8" over the stock maps (MetaLake is a Meta copy, so 7 families) unless marked.

## 1. What a medbay is, on the stock maps

Size: 512-1084 tiles (median 576; f21c 508, f22 468). Virology is 12-21% of it (median 17%; f22 24%).

The shape is always the same, whatever the outline:

1. **The front, on a main hall** (8/8): a public waiting area (Meta: an open firelock arch into a lobby with seats,
   Box: a lobby with a reception desk, Delta: a big glass-fronted lobby). Glass onto the hall 7/8. From it the public
   sees: the **chemistry desk** (table + windoor, 8/8 onto the lobby/walkway, 3/8 a second desk onto the hall), the
   **security post** behind glass (windows onto the walkway 8/8), and the staff door "Medbay" (access 5).
2. **The walkway** behind the staff door (a hall or a T of halls, 120-323 tiles, beds, rollers, IV drips, a NanoMed
   8/8, an emergency shower 7/8, maintenance doors 8/8): every working room opens off it.
3. **Near the front, off the walkway**: treatment (sleepers/stasis, 12-25 tiles), cryo beside it (20 tiles on every
   map, windows onto the walkway 6/8), storage (18-34 tiles, door to the walkway 7/8, often a counter), patient rooms
   (6 tiles each, 2-3).
4. **Further back**: surgery (25 tiles a theatre on 7/8, Delta/Endo two), often with observation/prep (4/8) and its
   own maintenance door (7/8); the CMO's office in the middle with windows onto the walkway (8/8).
5. **The genetics/cloning/morgue cluster**: cloning next to genetics (a door 7/8), cloning off the walkway (7/8),
   genetics with its own front door onto the hall ("Genetics Lab"/"Genetics Access", research style, access 9: 4/8),
   the morgue next to genetics (deptdb nb 0.71), opening onto a hall (6/8) and maintenance (7/8) toward the chapel's
   crematorium.
6. **Virology at the far end, sealed**: reached only through its airlock room (8/8: 9 tiles, 2 biosuit closets, an
   emergency closet, 1-2 showers, a sink, doors "Virology Exterior Airlock" / "Interior Airlock", access 39), from the
   walkway (6/8) or maintenance (2/8). Lab 30-41 tiles, 2-4 isolation cells of 6 tiles, a monkey pen 7/8.

What the public reaches without access (8/8): the lobby/front walkway only; Delta and Pubby also let it into treatment
and cryo. Never the morgue, surgery, storage, chemistry, genetics, virology (0/8).

## 2. Rooms

Kit lines: "n/8" = share of maps whose rooms of that type hold it (study.txt "Kit per type"). Doors: stock names and
styles from 3565 learned airlocks (study.json, `med.DOOR_OF` in fn_medical.py).

### Lobby / front (required 8/8)
- For: the patient walking in from the hall; the chemist and the security officer watch it.
- Kit: seats (8/8 front halls), a table with first aid / forms (lobby 2/3), the medical records or crew monitor
  behind the reception (reception 4/4 where there is one), requests console. Plants, a NanoMed nearby.
- Joins: the hall (public glass doors or an open firelock arch; glass onto the hall 7/8); the chemistry desk; the
  security post's windows; the staff door "Medbay" (medical/glass, access 5) into the walkway. Never behind another
  room (stock 0/8).

### Walkway / central (required 8/8)
- For: doctors moving patients (rollers), the place everything opens off.
- Kit: beds/rollers 8/8, IV drips 8/8, NanoMed 8/8 (or in storage), emergency shower 7/8, fire extinguishers,
  disposal bin, holopad. Maintenance door 8/8 ("Medbay Maintenance", access 5).

### Treatment (required 8/8)
- For: a doctor puts a patient in a sleeper or on a stasis bed straight from the front.
- Kit: stasis 7/8 or sleepers 4/8 (2 of either), medical records 6/8, a shower 6/8, a sink, a wardrobe.
- Joins: the walkway (door or open); cryo beside it (cryo|treatment windows 3/8); patient rooms off it on Box/Hippie.
- Door: "Treatment Center"/"Recovery Room", medical/glass, access 5 or public.

### Cryo (required 8/8)
- For: a doctor sets the freezer, puts a patient in a cell; the bot "medical rounds" goal uses sleepers and cells.
- Kit: 2 cells (8/8) facing pipes to a freezer and two oxygen canisters on connectors (Meta's bay: `forge/function.py
  CRYO`), a table with cryoxadone beakers (8/8), sometimes a medicine locker.
- Size 20 tiles on every map; windows onto the walkway 6/8; door from the walkway or treatment (often open).

### Surgery (required 8/8 by function; 5/7 families by area name)
- For: a doctor wheels a patient from treatment or the walkway onto the operating table; tools on a tray within reach
  (bot `goals/surgery.dm`: scalpel, retractor, hemostat, cautery within 4 tiles), anesthetic tank, the operating
  computer beside the table.
- Kit (Meta/Box template, 5 x 5): the table in the middle, the computer below it facing it (it finds the table by
  adjacency), a row of tool tables on one wall (saw, drill, drapes, razor, gloves, mask, apron, manual), the
  anesthetic closet (medical2) and a blood freezer in the corners, a sink, a wall NanoMed. Medicine locker 8/8.
- Joins: from the walkway directly, observation/prep (4/8) or the ward (Box/Hippie: through the patient rooms);
  maintenance door 7/8 ("Surgery Maintenance", 45). Never through storage, the morgue or an office.
- Door "Operating Theatre"/"Surgery", medical, access 45.

### Storage (required 8/8)
- For: doctors grab first-aid kits, medicine, bodybags. Kit: 2 medicine lockers, 6-12 first-aid kits, beakers,
  bio closets 5/8, NanoMed 4/8. Off the walkway (7/8), windows onto it (7/8), a delivery desk/windoor 5/8.
- Door "Medbay Storage", medical/glass, access 5.

### Patient rooms (2-3 a map)
- 6 tiles: bed, glass patient locker (9/10 rooms), wall NanoMed, chair/table. Door "Patient Room", medical.

### Chemistry (required 8/8)
- For: the chemist makes pills and patches (bot `goals/synthesize_medicine.dm`: dispenser, ChemMaster, the medicine
  smartfridge in `/area/medical`), hands them out over the desk.
- Kit: 2 dispensers, 2 ChemMasters, 2 heaters, beakers, chemical locker 7/8, disposal 8/8, requests console 8/8; the
  **medicine smartfridge set in the wall** between chemistry and the lobby/walkway (8/8, on the wall turf itself).
- Safety: extinguisher 8/8; nearest emergency shower 4-26 walking tiles from the dispensers (median 13; Hippie and
  Endo keep one in chemistry; this 2020 tree has no eyewash). Glass onto the hall 6/8 (it's on display).
- Desk 8/8 onto the lobby/walkway (2-3 tiles, reinforced table, windoor with access 33 on the **served** side 8 of 11
  stock desk tiles, shutters, firelock), a hall desk 3/8.
- Door "Chemistry Lab", medical/glass, access "5; 33"; maintenance 5/8.

### Genetics (required 8/8)
- For: the geneticist scans monkeys and crew at 2 DNA scanners with their consoles (each console finds its scanner by
  adjacency), keeps monkeys (8/10 live, cubes 7/10).
- Kit: 2 scanners + consoles, pill bottles, requests console, disposal 7/8, a monkey pen windoor (4/8 "Monkey Pen").
- Joins: cloning (door 7/8, "Genetics Lab", research/glass "5; 9; 68"); its own hall door 4/8 ("Genetics Lab",
  research, 9); windows onto the walkway 4/8. Never behind a security post.

### Cloning (required 8/8)
- Pod, scanner, console in a row (the console finds both by adjacency), each with a tile to stand at; bodybags 7/8,
  a wardrobe, a patient locker. 16-39 tiles (median 22). Off the walkway (7/8, "Cloning Lab", 5) beside genetics.

### Morgue (required 8/8)
- 8-13 trays on the walls, each with its front tile free (the tray slides out), a table with bodybags 9/10.
- Joins: a hall ("Morgue", grunge, access 6: 6/8) and maintenance ("Morgue Maintenance", 6: 7/8), the walkway
  (5/8), genetics (3/8). Dark floor. Never public, never the way into another room.

### Virology (required 8/8)
- Airlock room 9 tiles (bio closets 2, emergency closet, showers, sink, biohazard sign) is the only way in.
- Lab 30-41 tiles: PanDEMIC, 2 smartfridges (virology), disposal, requests console, medicine/virology lockers,
  extinguisher 8/8, sink 7/8. Cells 2-4 x 6 tiles (bed, IV, locker), monkey pen 7/8 (3-6 monkeys), a break room 5/8.
- Every door from outside virology wants 39 (8/8). Inner doors "Isolation A/B", "Monkey Pen", virology/glass, 39.

### CMO's office (required 8/8)
- One office 24-35 tiles (Delta/Endo add a bedroom off it): CMO locker, keycard device, medical records, crew monitor
  (6/8), requests console, disposal, a bed 5/8. Door to the walkway 8/8 ("Chief Medical Officer's Office", command,
  40); windows onto the walkway 8/8; maintenance door 3/8.

### Security post (required in medical 8/8)
- 8-21 tiles, security locker 8/8, records/security console 8/8, windows onto the walkway/lobby 8/8, door to the
  walkway 6/8 ("Medbay Security Post", security/glass, 63). Never a door into genetics or cloning (0/8).

## 3. Role workflows (what has to work)

- **Patient**: hall -> lobby (seats, sees the chemistry desk and the post) -> a doctor takes them through the staff
  door. Never through a store, the morgue or a lab to reach the waiting area.
- **Medical doctor**: walkway -> treatment (sleeper/stasis) -> cryo next door -> surgery (roller along the walkway,
  one door) -> patient room. Storage and the NanoMed one door off the walkway. Bodies: ward -> morgue (one door) ->
  maintenance -> chapel.
- **Chemist**: chemistry -> desk onto the lobby; fridge in the wall; shower within ~20 tiles.
- **Geneticist**: hall or walkway -> genetics (access 9, never 63) -> cloning next door; monkeys in reach.
- **Virologist**: walkway -> exterior airlock -> airlock room (suit up, shower) -> interior airlock -> lab -> cells /
  pen.
- **CMO**: office on the walkway with windows; keycard, crew monitor, locker in that one office.
- **Security officer**: post at the front, glass onto the lobby/walkway.

## 4. Checkable rules (gen/learn/fn_medical.py `check(m)`)

Each finding is `(x, y, "med.<rule>: text")`. On the stock maps: Meta 0, MetaLake 0, Pubby 1, Donut 1, Box 2, Delta
2, Hippie 2, Endo 7 (Endo's odd morgue complex and post). Rules:

| rule | what | stock |
|---|---|---|
| surgery | an operating table (not in the morgue), the operating computer beside it, scalpel/hemostat/retractor/cautery within 4 | 8/8 |
| surgery_path | the theatre opens onto the walkway, observation, prep, the ward or treatment | 8/8 |
| cryo | 2+ cryo cells and a freezer | 8/8 |
| treatment | sleepers or stasis beds | 8/8 |
| chemistry / chem_kit | a lab with dispenser, ChemMaster, heater | 8/8 |
| chem_fridge | a medicine smartfridge in the chemistry wall (or room) | 8/8 |
| chem_desk | a table + windoor desk from chemistry onto the walkway, lobby, treatment or hall | 8/8 |
| chem_shower | a shower within 20 walking tiles of the nearer dispenser | 7/8 |
| medvend | a NanoMed Plus in medical | 8/8 |
| morgue, morgue_trays | a morgue with 8+ trays | 8/8 (8-13) |
| morgue_exit | a morgue door to maintenance, a hall or the chapel | 8/8 |
| morgue_public | the public can't walk into the morgue | 8/8 |
| through | lobby, chemistry, storage, post, CMO, morgue, treatment: one of each has a door/opening onto the walkway (morgue: or hall/chapel) | 8/8 |
| job_reach | surgery/treatment/cryo/storage/morgue (doctor), chemistry (chemist), genetics/cloning (geneticist), virology lab (virologist), CMO: reached from the halls (walking halls, medical, maintenance, chapel) with that job's access (job_types `access`) | 8/8 |
| clone_use | pod, scanner, console each with a free tile beside it | 8/8 (Endo 1 miss) |
| clone_size | cloning 16+ tiles | 8/8 |
| clone_genetics | cloning and genetics share a door or sit within 10 tiles | 7/8 door |
| virology, viro_access, viro_airlock | a lab; every door from outside virology wants 39; that door is the airlock room's | 8/8 |
| viro_cells, viro_monkeys | 2+ isolation cells; monkeys | 8/8, 7/8 |
| cmo_kit, cmo_split, cmo_window | locker, keycard, records; one office (or joined pieces); a window onto medbay | 8/8 |
| checkpoint_kit, checkpoint_window | security locker; glass or desk onto the walkway/hall | 8/8 |
| storage_kit | a medicine locker or 4+ first-aid kits | 8/8 |
| patient_locker | each patient room has its glass locker | 9/10 rooms |
| lobby, lobby_seats | the public reaches a waiting room from the hall, with seats | 8/8 |
| public | the public walks into none of surgery/storage/chemistry/CMO/genetics/cloning/virology/a spare room | 8/8 |
| shower | an emergency shower on the walkway, treatment, cryo or chemistry | 7/8 |
| door_name | a door's name names a room on one of its sides | stock 0-1 |

## 5. Review of our map (f22, crew 100 seed 7; f21c where it differs)

Layout (`f22_medical_before.png`, `ascii.py ... 55 50 84 84`): a 3-wide stem corridor `/area/medical/medbay` (58-80,
65-67) runs west from three hall doors at (81,65-67) on the aft hall; rooms in strips north and south of it. Checks
before: **29 findings** (f21c: 21). Room by room (`review_f22/NNN_*.png` cards):

| room (tiles, box) | defect | cause in the generator |
|---|---|---|
| (no surgery) | **no operating room at all** (no optable/computer in medical; bot surgery goal can't run) | `audit.must_have` counts by area: surgery is `/area/medical/sleeper` on Box/Hippie, so 5/7 families, not a must; medical got 501 of 1199 wanted tiles (build log `compose: medical`) and surgery came last. Virology took 111 tiles (24%) |
| cryo 15 (69-71,53-57) | **no cryo cells, no freezer** (2 O2 canisters, beakers) | `corpus.INFRA` holds `/obj/machinery/atmospherics`: synth never copies cells or freezers; `forge/function.place_cryo` is only called by the old `station/to_dmm.py`. Same on f21c (18 tiles, 119-124,115-117) |
| lobby 21 (58-62,53-57) | **at the back corner, reached only through the morgue (60,58) or storage (62,53)**; the hall leads straight into the staff corridor, which is the de-facto lobby with no seats | lobby type learned from Donut only (stock lobbies are called medbay/central); not a must, placed late, and `floorplan.plan` fills back rows from `walkway[-3:]` once `behind` runs out. f21c: lobby 8 tiles behind patient room A |
| corridor 69 (58-80,65-67) | front doors (81,65-67) are 3 plain medical airlocks, one public, two access 5; the whole staff corridor is public | doordb/doorcount on the stem; no lobby at the door |
| morgue 25 (58-62,59-63) | public (door 59,64 has no access; stock 6); 4 trays (stock 8-13); no maint or hall door though its west wall is on port maintenance; a through-room to the lobby | doordb learned "Morgue" with no access for corridor pairs; floorplan placed the lobby behind it |
| genetics 24 (77-80,74-80) | **only door is through the security post (79,73), security/glass access 63: geneticists can't get in** (doctors neither); cloning 29 tiles away | floorplan back room behind the checkpoint front room (`pool_` pick by door_p fell back to the best of a poor pool); doordb styled the door by the post |
| cloning 6 (73-74,53-55) | 2x3: console (73,53) boxed in, faces a wall (audit `use`); 29 tiles from genetics, no door between | cloning sized to work_size of its kit without stand tiles; placed behind the ward, not paired with genetics (deptdb nb 1.0) |
| chemistry 30 (71-76,69-73) | no desk, no medicine smartfridge, nearest shower 21 tiles; door to storage needs "5; 33" and a CMO door (75,74) into it | desks.py not in f22's build; fridge is wall-set on stock (synth copies floor pieces only) |
| CMO office **two rooms**: 13 (64-67,60-63) and 16 (74-76,75-81), 12 tiles apart, no door between | locker/keycard in one, monitor/records/bed in the other; no window onto medbay | `floorplan._filler` gives leftover back-row floor to a program type "it doesn't have yet" while that type is still queued in walkway/behind |
| storage two rooms: 27 (63-67,53-58) and 14 (71-72,75-81) | **neither opens onto the walkway**: the first through the lobby/morgue or the CMO's office (40), the second through chemistry ("5; 33") or the CMO's office | same `_filler` (storage REPEATABLE x2) plus back rows |
| treatment 17 (68-71,59-63) | fine (2 sleepers, 2 stasis); its door named "Medbay Storage", the cryo door "Medbay Maintenance" | doordb names by station-group pair, not by the room |
| central ward 56 (73-80,57-63) | no NanoMed in medical at all (f21c had one); door from the corridor named "Chemistry Lab" | essentials kit for medhall types doesn't hold the vendor; doordb names |
| virology 111 (58-69,69-81) | **lab door (63,68) is a plain medical door "Chemistry Lab", access 5, straight off the public corridor**; the decon room (67-69,74-76) sits inside between the lab and a cell; no monkeys | floorplan.carve makes every piece a cell; the airlock piece isn't at the room's door; doordb names |
| security post 12 (78-80,69-72) | no security locker, no glass onto the corridor or hall, a door into genetics | post kit from a wardrobe exemplar; back room behind it |
| patient rooms 6+6 | no patient lockers | kit |
| f21c surgery 33 (94-103,110-113) | only door through medical storage (104,112); tools more than 4 tiles from the table; virology windows into it | floorplan back room behind storage |

Whole department against Meta/Box/Delta (`meta_medical.png`, `box_medical.png`, `delta_medical.png`): ours has the
stem-and-strips look but not the medbay structure - no front (lobby + desk + post glass) at the hall door, working
rooms placed by size not by workflow (genetics and cloning on opposite sides, morgue and lobby swapped, storage behind
offices), virology not sealed. A player would read it as generated.

## 6. What gen/learn/fn_medical.py does

`python tools/mapforge/gen/learn/fn_medical.py <in.dmm> <out.dmm>`; run it after `gen/learn/desks.py`, before
`fixtures.py` and `gen/net.py` (its cryo loop is self-contained on the default pipe layer; it refuses tiles holding
default-layer station pipes). Every placement keeps a room no worse than it was: no free floor newly cut off from its
doors, no dense piece newly boxed in, door and firelock fronts free (`_ok` against `_state` taken first).

Fixes, in order:
1. **Operating room** when there is none: a room off the walkway, 16-40 tiles, becomes the theatre (Meta/Box template:
   table, computer facing it, two tool tables, anesthetic closet, blood freezer, sink, white floor, door "Operating
   Theatre" 45). A spare room (second storage/CMO piece, an unreachable lobby) is taken as is; a morgue/storage there
   moves into the dead-end room behind it, the morgue with its trays, bodybags and a maintenance door. With a table
   but tools out of reach: a tool table beside it.
2. **Cryo bay** in the cryo room (else treatment): freezer, two connectors with oxygen, the loop, two cells; the room's
   furniture goes back where it keeps the bay reached.
3. **Chemistry**: a desk onto the walkway/lobby (windoor with 33 on the served side, shutters, firelock; a table or one
   machine in the way moves; wall pieces rehung), the medicine smartfridge set in the wall beside it, an emergency
   shower when none is within 20 tiles.
4. NanoMed Plus (storage on the walkway, else the ward). 5. Morgue: trays to 8, a maintenance/hall door, its doors to
   access 6. 6. Genetics' own door when its jobs can't get in (research, "Genetics Lab", 9, to the hall or walkway; a
   wall piece rehung), and the door through the security post walled up. 7. Cloning machines re-seated (console
   touching pod and scanner, each with a stand tile). 8. Virology: outer doors to virology style and access 39, a
   spare isolation cell (3+) made the monkey pen. 9. Security post locker (in place of a wardrobe when full) and glass
   onto the walkway; CMO windows onto the walkway (wall pieces rehung, never APC/alarms). 10. Patient lockers, a
   medicine closet in a bare storage, seats by the hall door where the public waits. 11. Door names that name a room
   on neither side.

Results (`medical_work/f22_fnmed.log`, `f22_fnmed.dmm`):

| map | check before | after | fixes |
|---|---|---|---|
| f22 c100 s7 | 29 | **6** | 19 |
| f21c c100 s7 | 21 | **8** | 12 |
| stock Box | 2 | 0 | 2 (a patient locker, a door name) |

f22 audit (`gen/audit.py`) before -> after: use 5 -> 4 (the cloning console), missing_kit 12 -> 11, odd_door 3 -> 4
(the virology exterior door, see G9), everything else equal (dead doors 0, unreached 1, no_apc 2).

Left on f22 (layout, section 7): storage only through the CMO's office/morgue, the morgue now behind the theatre (it
has its maintenance exit), cloning 6 tiles and far from genetics, virology without an entry airlock, the CMO split.
Pictures: `data/previews/mapforge/dept_medical/f22/{surgery_morgue,cryo_cloning,chem_post_genetics,virology,whole}_sheet.png`.

## 7. Generator changes (proposed; not edited)

In priority order.

**G1. Must-haves by function** - `gen/audit.py must_have()` (used by `floorplan._must`): count a family as having a
type when any of its medical rooms holds the type's signature piece, not only by area path:
`{"/area/medical/surgery": "/obj/structure/table/optable", "/area/medical/cryo":
".../unary/cryo_cell", "/area/medical/genetics/cloning": "/obj/machinery/clonepod"}` (outside the morgue). Surgery
and cryo are on 8/8 maps by function, 5/7 and 3/7 families by area. f22 lost its operating room to this; f21c and
f22 got no cryo cells either way (G2). In `floorplan._program`, cap virology at 0.18 x target (stock 12-21%, median
17%; f22 24%, 111 of 468 tiles) so the must-haves fit when the slot is short (medical got 501 of 1199 wanted).

**G2. Cryo bay** - `gen/build.py`: after furnishing and before `net.py`, call `fn_medical.fix_cryo(m, Dept(m), log)`
(or `forge/function.place_cryo` with a builder adapter; it strips layer-1 supply pipes and vents in the block, ours
keeps them). Cause: `forge/corpus.INFRA` starts with `/obj/machinery/atmospherics`, so synth/essentials never place
cells or freezers. 0 cells on f21c and f22; stock 8/8 have 2-3.

**G3. The front: lobby at the hall door** - `gen/learn/floorplan.py plan()`:
(a) when the program holds `/area/medical/medbay/lobby`, cut the stem's first 4-6 tiles from the hall door into the
lobby (area lobby, seats, "Medbay" staff door access 5 across the corridor behind it) and give the first strip slots
either side to chemistry (desk onto the lobby) and the security post (glass onto it) - stock 8/8;
(b) `pool_ = [... (behind or walkway[-3:]) ...]` puts walkway types into back rows when `behind` is empty: keep
FRONT_ONLY types (lobby, chemistry, checkpoint, storage, morgue, cmo) out of back rows; take a closet instead (f22 lobby
behind the morgue, f21c lobby behind a patient room, both storages behind offices/chemistry);
(c) the hall doors of a department with a lobby: one public glass pair into the lobby (stock 8/8 public front), not
three plain doors two of which want access 5.

**G4. `_filler` takes queued types** - `floorplan._filler(dept, P, size)`: exclude the types still waiting in
`walkway`/`behind` (pass them in), and treat `/storage` as non-repeatable for medical (stock: one medbay storage on
6/8, Delta/Endo two side by side). f22: CMO office in two rooms 12 tiles apart (13 + 16 tiles), a second storage
behind chemistry reached only through chemistry ("5; 33") or the CMO office.

**G5. Back-room pairing** - `floorplan.plan` back rows: never behind a security post or a head's office (f22
genetics behind the post: access 63, geneticists locked out); pick the back room by `door_p(front, back)` >= 0.2 else
a closet; seat cloning beside genetics (deptdb nb 1.0, stock door 7/8) and the morgue next to them (nb 0.71). Cloning
and cryo `work_size` at least 16 and 20 tiles (stock minimum 16 and 20; f22 cloning 6 tiles, console unusable).

**G6. Virology's airlock** - `floorplan.carve()` for `/area/medical/virology`: the piece at the room's door is the
airlock room (9 tiles: 2 `l3closet/virology`, emergency closet, 1-2 showers, sink, biohazard sign), the room's outer
door is on it ("Virology Exterior Airlock", virology, 39) and its inner door leads to the lab ("Interior Airlock").
Stock 8/8; f22 lab door (63,68) opens off the public corridor, f21c (108,115) the same.

**G7. Morgue placement** - `floorplan.plan`: the morgue takes a slot on the department edge touching maintenance (or a
hall), with a door there ("Morgue Maintenance", maintenance, 6: stock 7/8; hall "Morgue", grunge, 6: 6/8); no room
behind it. f22's morgue (58-62,59-63) touched port maintenance with no door and led to the lobby.

**G8. Door names and access by room** - `gen/learn/doordb.py`: name a door by the inner room's type (table
`fn_medical.DOOR_OF`; stock names section 2), not a name learned for the station-group pair. f22: "Chemistry Lab" on
the corridor -> virology (63,68) and corridor -> ward (75,64) doors, "Medbay Storage" on treatment (70,64), "Medbay
Maintenance" between treatment and cryo (70,58), "Medbay" between lobby and morgue (60,58). Morgue doors want 6 (f22
59,64 and 60,58 had none: the public walked into the morgue).

**G9. inner/outer on generated maps** - `doordb.inner_outer(size=...)` takes the smaller area as the inner room; the
department corridor (`rooms.CORRIDOR_AREA`, e.g. `/area/medical/medbay`, which also holds every door tile) can be the
smaller one, so a stock-correct virology exterior door reads `odd_door` ("virology/glass belongs to virology, not
medbay"). Treat the corridor area as the outer side always.

**G10. Kit** - `gen/essentials.py`: the NanoMed Plus (`/obj/machinery/vending/medical`, 8/8) for the medical walkway or
storage, the security locker (`secure_closet/security/med`, 8/8) for the medical post, the patient locker for patient
rooms (9/10), the chemistry smartfridge as a wall piece (8/8, on the wall turf between chemistry and the lobby).

### desks.py on our map and its table

On f22 `desks.fix` makes `chemistry->medbay x1` at (71,68): one tile onto the stem corridor (here the public entry, so
the right side), with the access windoor `northright` on the **chemistry** side, and `medical->hall x1`: a "Security
Checkpoint" brigdoor desk at (81,72) from the post onto the aft hall (it moved the intercom and the table at (71,69)).
On f21c chemistry's walkway wall had a machine behind every wall tile; fn_medical could not place one either (a window
tile at (112,111) qualifies but the heater behind it has nowhere to go).

Proposed changes to its `COUNTERS` (medical rows):
- Chemistry: chance 0.8 -> **1.0** (stock 8/8), tiles (1, 2) -> **(2, 3)** (stock desks are 2-3 tiles), faces keep
  lobby, central, medbay, then add `/area/medical/sleeper` (treatment) before HALL; allow a window tile of chemistry as
  a spot (stock desks stand in the glass front). Add a second row `("/area/medical/chemistry", (HALL,), "desk", 0.35,
  (1, 1), "33", "Chemistry Desk")` (hall desk 3/8).
- `counter_objs` style "desk": the access windoor on the **served** side (`out`), not the owner side (stock 8 of 11
  chemistry desk tiles; Meta (103,107) `northleft` faces the lobby, Box (137,123/125) `eastright` face central), an
  optional plain windoor on the inner side.
- Add storage: `("/area/medical/storage", ("/area/medical/sleeper", "/area/medical/medbay/central",
  "/area/medical/medbay"), "desk", 0.6, (1, 1), "5", "Medical Delivery")` (stock storage desks/windoors 5/8).
- The checkpoint row: the medical post wants glass onto the lobby/walkway (8/8), not a brigdoor desk onto the hall
  (stock 0/8 for medical, Endo's "Medical Cell" aside); give `/area/security/checkpoint/medical` faces
  `("/area/medical/medbay/lobby", "/area/medical/medbay")` first, or leave the post to fn_medical's windows.
- Genetics row (0.35, hall/lobby/medbay): fine (stock genetics desk onto the hall 2/8).
