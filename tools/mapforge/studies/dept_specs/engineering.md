# Engineering: function spec (2026-11-26)

The user: "I think we should work engineering properly. Get it right"; "engineering needs safety, showers,
equipment". This spec says what an SS13 engineering department is for, room by room, as the stock maps build it, the
rules a generated station is checked against (each with its stock count), what our crew 100 seed 7 build (f22) gets
wrong and why, what `gen/learn/fn_engineering.py` fixes on a finished map, and what the generator must change.

Scope: everything under `/area/engine` except the crystal chamber's inside (the engine room round it and its
monitoring are in), `/area/crew_quarters/heads/chief`, `/area/storage/tech`, `/area/security/checkpoint/engineering`,
and Atmospherics as the secondary part.

Stock maps: MetaStation, BoxStation, DeltaStation2, hippiestation, PubbyStation, Donutstation, EndoStation (7
families; MetaLake is a Meta copy and gives Meta's numbers). "6/7" below means 6 of these 7 maps.

Tools written for this (all in `studies/dept_specs/engineering_work/`, each with a docstring):

| tool | what it does |
| --- | --- |
| `engstudy.py` | the department cut into rooms at walls, doors and area changes; per room its kit (110 families), doors (style, name, access, what's beyond), glass; `stock.txt`/`stock.json` (8 maps), `f22.txt` |
| `aggregate.py` | one line per question, one column per map (`agg.txt`): vestibule, showers, closets, distances from the crystal's door, lockers, suits, SMES, consoles, CE office, checkpoint, tech storage, foyer, atmos desk and kit, walks to solars/telecomms |
| `pathgear.py` | the walk from the department's front to the crystal's door and how far the shower, radiation and fire closets stand from it |
| `ascii.py` | a text picture of a region: rooms by label, doors, kit by symbol (the fastest way to read a layout) |
| `shot.py` | a dmm-tools render of a region with a coordinate grid and red marks |
| `pictures.py` | before/after sheets of `fn_engineering.py`, changed tiles marked |

Pictures: `data/previews/mapforge/dept_engineering/` - `stock_vs_f22_engineering.png` (Meta, Box, Delta, ours, same
scale), `f22_engineering_before_after.png`, `f22_atmos_before_after.png`, `f21c_*_before_after.png`, room cards
`rooms_f22/` and `rooms_f22_fixed/` (gen/roomreview.py), `f22_eng_grid.png`, `f22_west.png`, `f22_east.png`.

## 1. What the department does, by role

**Station Engineer** (access 10 engine, 11 equipment, 23 tech storage, 32 construction, 12 maint, 13 external,
61 telecomms; no 24 under minimal access, which is on above 20 players):

1. Arrives at the department's front from a primary hall: the foyer / break room (`"Engineering Foyer"`, access
   32;19). Through the `"Engine Room"` airlock (10) into a small vestibule: two showers facing each other, radiation
   closets, fire closets, often tool closets, a radiation / secure-area sign; out through the second `"Engine Room"`
   airlock onto the engineering floor.
2. Main room (lockers): personal locker (`engineering_personal`), electrical supplies (`engineering_electrical`:
   the insulated gloves the bot crew fetches first, `goals/engineer_gear.dm`), welding supplies, EngiVend,
   engineering wardrobe, YouTool, toolbelt, mesons, cell charger, requests console, disposal.
3. Engineering Storage: suit storage units with engineering hardsuits (EVA, breaches; `goals/gear_up_eva.dm`
   raids the nearest engineering SSU), tank dispenser (plasma tanks for the collectors), metal/glass/plasteel,
   fuel and water tanks, portable generator, canister, cable, light boxes, airlock electronics.
4. Engine start (`goals/setup_supermatter.dm`): nitrogen canisters onto the loop's ports (within 22 tiles of the
   crystal), pumps and filters set, plasma tanks into the six collectors (tank dispenser within 32), emitters on in
   the laser room, the chamber's air alarm; a radiation suit from a radiation closet for anything in the radiation
   (`find_rad_suit`: any closet it can open on the level - the nearer, the faster).
5. Power: the SMES bank (3-6 in one room) set to charge/discharge (`configure_smes`: SMES within 30 tiles of the
   crystal on the collectors' grid), the power monitor / supermatter monitor consoles.
6. Repairs: breaches (EVA suit, metal, the external airlock), cables, APCs, solars (`goals/solars.dm`: the
   maintenance route to the solar arrays), telecomms (MiniSat access from engineering on Meta, Box, Delta, Pubby).
7. Washes off radiation or burning on the way out: the vestibule's showers (a shower cleanses radioactive
   contamination and puts out a burning player: `shower.dm` `contamination_cleanse`, water reagent).

**Chief Engineer** (56, 19 heads, 11, 10, 61, 65 MiniSat, ...): the office off the engineering floor, glass onto it
with privacy shutters; CE locker (advanced gloves, cloak), CE hardsuit SSU, ID console (minor/ce), station alerts,
APC control, keycard authenticator, requests console, an engine camera telescreen, and 4-5 blast-door buttons
(privacy shutters, secure storage, engineering lockdown, atmos lockdown). The gravity generator and secure tech
storage are head-locked on 4/7 maps.

**Atmospheric Technician** (24, 12, 32 under minimal access): Atmospherics' front desk to the public; atmos lockers
(fire suit, firefighter helmet, backpack water tank, advanced extinguisher, RPD: the station's firefighters), the
atmos suit storage unit, fire axe cabinet, pipe dispensers, portable pumps and scrubbers, spare canisters; reaches the
engineering foyer, break room and shared lathe through the 32;19 doors (6/7 maps join Atmospherics to the foyer with
an `"Atmospherics"` airlock, access 24).

**Security Officer (engineering post)**: the checkpoint opens on the foyer (Meta, Box, Hippie, Pubby), the
engineering floor (Delta) or a hall (Endo), never through a store.

**The public**: sees engineering through the foyer's glass and talks to Atmospherics at its desk; reaches tech
storage only with 23; nothing else.

## 2. The rooms (stock counts and sizes in floor tiles)

| room | stock | size | holds | joins |
| --- | --- | --- | --- | --- |
| foyer / break room | 6/7 (Donut uses its atmos foyer) | 35-78 | 2 coffee/snack vendors (4/7), microwave (3/7), disposal, extinguisher, first aid, light replacer, tables | hall door `"Engineering Foyer"` 32;19 (6/7); checkpoint (5/7); atmos door 24 (4/7); shared storage 32;19 (2/7); the vestibule's `"Engine Room"` 10; CE office glass with shutters (3/7) |
| safety vestibule | 6/7 (all but Pubby) | 6-12 (3 wide, 2-4 deep) | showers 2 facing (Meta, Box, Endo; Hippie 1; Delta's 4 in its engine access), radiation closets 1-2, fire closets 1-2, tool closets (Meta, Delta), sign | cycling `"Engine Room"` airlocks 10 (or "Engineering Access", "Engineering Foyer"), between front and works |
| main room (lockers) | 7/7 | 81-169 | engineer lockers 2-4, electrical 1-2, welding 1-2, EngiVend 7/7, wardrobe 7/7, YouTool 5/7, disposal, requests console, cell charger, belts, mesons, gloves; sheets and tanks on Box, Hippie, Endo; a shower on Meta, Pubby | the vestibule, CE office (6/7 its only door), storage, SMES room, secure storage (blast doors), engine room doors |
| Engineering Storage | 7/7 | 9-47 | engineering SSU 2-3 (7/7), tank dispenser (5/7 here), metal/glass/plasteel, fuel + water tank, portable generator, canister, cable, light boxes, airlock electronics | one door to the main room (Meta, Delta, Donut windoor, Endo) |
| SMES / Power Monitoring | 6/7 (Donut's sit in its engine room) | 12-48 | SMES 3-6 with as many terminals, the consoles (station alert, atmos alert, SM monitor) on Meta and Delta | one airlock (5/6) `"Power Monitoring"` / `"SMES Room"` / `"Power Storage"`, access 32 or 11; never the way into the engine (Hippie's opens on its second engine) |
| secure storage | 7/7 | 16-36 | emitters 4-5, field generators 4-5, shield generators 2-4, portable generator, canister, metal/glass, cell, airlock electronics | blast doors `"Secure Storage"`, button (access 11) in the main room or CE office |
| laser room | 5/7 | 43-78 | emitters 3-5, nothing else | two `"Laser Room"` glass airlocks (10) from the engine room |
| engine room | 7/7 | 87-166 | crystal chamber (21, collectors 6), N2 canisters 3-4 on ports, thermomachines 2, mesons, radiation suits and geiger counters (Box, Hippie), RPD, 1 fire and 1 radiation closet, radiation shutters' button, fire/radiation signs | `"Supermatter Engine"` glass airlocks (10) from the main room; critical airlock into the chamber |
| CE office | 7/7 | 20-48 | see role list; disposal 7/7, cell charger 5/7, keycard 5/7 | one airlock 56 (6/7, onto the main room 6/7); glass onto the department 7/7, privacy shutters 5/7, buttons 4-5 (7/7) |
| checkpoint | 6/7 | 12-30 | recharger 7/7, requests console 7/7, telescreen 6/7, blast button 5/7 | one airlock 63 onto foyer / floor / hall (6/6) |
| tech storage | 7/7 | 23-63 | the six circuit board spawners (service, rnd, security, engineering, tcomms, medical) on racks (7/7 exactly), toolboxes 2, insulated gloves, mesons, cell charger, cells, cable, airlock electronics, requests console (5/7) | `"Tech Storage"` airlock/engineering 23 onto a primary hall (7/7) |
| secure tech storage | 6/7 | 6-7, r-walled | 3 racks: AI, command, RnD_secure spawners (7/7) | one airlock/highsecurity `"Secure Tech Storage"` 19;23, into tech storage only (6/6) |
| shared storage | 2/7 (Meta, Delta; the lathe is in the break room, main room or atmos foyer elsewhere) | 17-20 | engineering protolathe, circuit imprinter, R&D console, YouTool, tool closet | `"Shared Engineering Storage"` 32;19 off the foyer |
| gravity generator | 7/7 | chamber 20-25 (5x5) + antechamber 10-20 + foyer 6-12 | generator; antechamber: 1 SMES + terminal, portable generator (7/7); foyer: 2 radiation closets (6/7), radiation signs (5/7) | `"Gravity Generator Foyer"` 10, then 19;23 and 19;61 (Meta, Delta, Hippie) or 11 throughout (Box, Pubby, Donut, Endo) |
| external access | 6/7 | | `"Engineering External Access"` 10;13 cycling airlocks to space (3-20 external airlocks in the department) | |
| deliveries | 7/7 | | `"Engineering Delivery"` windoor (mulebot drop), 5/7 also `"Atmospherics Delivery"` | |

Atmospherics (7/7): a front monitoring room 32-44 tiles with the desk windoor(s) onto a hall (access 24) behind
blast doors, the atmos alert, station alert and atmos control consoles, tank dispenser, 8-12 spare canisters,
disposal, requests console; the main floor 213-316 with atmos lockers 2, atmos wardrobe, atmos SSU 1-3, fire axe
cabinet, pipe dispensers 3 (pipe, disposal, transit tube; 6/7), hazard vests 4, welding masks 2, belts, space heaters
2-3, portable pumps 2 and scrubbers 2 (6/7), thermomachines 2, fuel tank, high-capacity water tank (6/7),
metal/glass, requests console, extinguisher cabinets 2 (7/7), a shower on Meta and Endo; the distribution loop room
35; gas chambers 9 each (6-8). Every atmos airlock carries 24; 2/7 have a hall airlock (Pubby, Donut), the rest are
entered from engineering's foyer.

Walking distances (stock, front door to): crystal door 27-46, gravity generator 0-45 (Box's opens on a hall), SMES room 18-46, solar
maintenance 30-88, telecomms 7-132, Atmospherics 3-10. Crystal door to the nearest radiation closet 7-21, shower 6-32
(6/7 have one), fire closet 6-39, extinguisher 6-34.

## 3. Checkable rules (`gen/learn/fn_engineering.py check()`)

Each finding is `(x, y, "rule: text")`. Stock maps scored: Meta 0, Box 0, Hippie 0, Delta 5 (fire closet 4 steps off
the walk, one orphan terminal, CE windows unshuttered, no fuel/water tank in atmos), Pubby 3 (no vestibule), Donut 6
(no shower, no secure tech storage, no external airlock, unshuttered CE, no pipe dispenser/scrubbers), Endo 3
(no sign on the walk in, one grav radiation closet, unshuttered CE).

| rule | what is checked | stock |
| --- | --- | --- |
| way_in | the walk from the front (eng hall airlocks, tech storage's left out) to the crystal's chamber door passes a shower, a radiation closet and a fire closet within 2 steps, before the engine's own door | shower 5/7, radiation 6/7, fire 5/7 (1 step each where present) |
| rad_sign | a radiation / secure-area sign along the last 12 steps of the walk in; one at the gravity generator | 5/6 where the walk is found; 5/7 |
| corridor | the department corridor (`/area/engine`) meets the engine through an airlock, not only glass | stock has no such corridor; the generator's own |
| engine_door | every airlock into the engine has access (10, or 24;10) | 7/7 |
| store | the walk in does not go through a store (SMES bank, engineering storage, gravity generator, CE office, tech storage) | 6/6 where found |
| grav | 2 radiation closets in the gravity generator's rooms or by their doors | 6/7 |
| terminal | no power terminal without an SMES facing it | 6/7 |
| ce_office | every airlock 56; one airlock onto the station (a door to a room only reached through the office, the CE's quarters, is allowed); glass onto the department; privacy shutters on it | 7/7, 6/7, 7/7, 5/7 |
| checkpoint | the post (largest piece) has an airlock onto a hall or the department's floor (not a store or an office) | 6/6 |
| tech | tech storage airlock onto a hall; its inner door named for it; the secure room opens into tech storage only, one airlock; 6 + 3 board spawners; no suit storage in the secure room | 7/7, -, 6/6, 7/7, - |
| foyer | the break room / foyer area has an airlock onto a hall | 6/7 |
| atmos_door | an engineering-atmos airlock is atmos-styled, named Atmospherics..., not "critical" | 6/6 |
| atmos | hall airlocks carry access; desk windoor onto a hall; lockers 2, wardrobe, SSU, pipe dispenser, pumps 2, scrubbers 2, tank dispenser, alert console, fuel tank, water tank, disposal, fire axe, extinguishers 2, requests console; 6+ spare canisters | 7/7 each (pipe dispenser, scrubbers, tanks 6/7) |
| layout | secure storage (field/shield generators) present; an external airlock from engineering; tank dispensers at most 2 | 7/7, 6/7, 7/7 |

## 4. Our map, room by room (f22, crew 100 seed 7, before the pass)

Read with `ascii.py data/mapforge/gen_learn/f22_c100_s7.dmm 99 88 153 134`, the room cards in `rooms_f22/` and
`f22_eng_grid.png`. Layout: hall along y 90; the engineering stem corridor (`/area/engine`, 3 wide) runs north from
a triple `"Engine Room"` airlock (115-117, 91) to y 113; rooms either side; the stamped Meta engine block above
(x 109-128, y 115-132); Atmospherics is its own composed block east (x 130-151).

| # | room (tiles) | defect | cause in the generator |
| --- | --- | --- | --- |
| 1 | stem corridor x115-117 y92-113 (66) | ends at a window (116,114) onto the engine block's corridor: no way to the engine from the department's corridor; the only way in is through the SMES room | the engine block's wall row (gen/net.py engine stamp, floorplan.engine_annex) lands on the stem's end; nothing reopens it |
| 2 | SMES room x119-123 y105-113 (41) | 4 SMES; doors to the stem (32), Engineering Storage (10) and `"Supermatter Engine"` (119,114) into the engine with NO access: the walk to the crystal goes past the batteries, open to any 32 holder (atmospheric technicians) | compose.second_doors / gen/learn/doorcount.py add the door to the annex; doordb.style leaves it without access |
| 3 | whole department | no safety vestibule, no showers on the way in (nearest shower 40 steps from the crystal's door, in the locker room against a wall), radiation closets 15 steps, no radiation sign anywhere (stock 2-19) | floorplan has no vestibule piece; the stamped block's own closets are inside the radiation |
| 4 | CE office x103-107 y99-104 (27) | second door (108,101) `"Shared Engineering Storage"` 32;19 from shared storage: anyone with 32 walks in; the CE's own door (107,98) opens into a 1-tile pocket (107,99) boxed by the CE suit storage (107,100) and the console row; no window, no shutters, no buttons | doorcount / second_doors give the office a second door; doordb names and locks it by the far room; synth furnishing judged reach from both doors |
| 5 | checkpoint x126-129 y92-97 (24) | only door (125,95) into tech storage: the officer goes through a store; its south wall is on the hall | floorplan places the CHECKPOINT as a strip room; doors join it to a neighbour |
| 6 | tech storage x119-124 y92-98 (30) | no hall door (stock 7/7); inner door (118,96) named `"Gravity Generator"`, highsecurity, 19;23;63; NO circuit board spawners (the whole station has 0, stock 9 on every map): no boards to rebuild consoles; east side (123-124, 95-98) cut off by racks and a table, reached only through the secure room | corpus.INFRA / furniture() skip every `/obj/effect`, so synth never copies the spawners; essentials NOT_KIT also skips `/obj/effect`; doordb names doors by the far room; floorplan puts tech storage inside the [10] stem |
| 7 | secure tech x123-124 y92-93 (4) | two doors (122,93), (123,94); holds a standard suit storage unit, no boards | synth copied an SSU; doorcount gave a second door |
| 8 | break room x103-113 y92-98 (69) | no hall door: the department's whole face is the triple [10] stem door, so atmospheric technicians (24, 32) reach neither the break room nor the shared lathe | floorplan front room has its door on the stem only |
| 9 | "engine_smes" piece x126-129 y99-103 (16) | holds an engineering SSU, tank dispenser, sheets (a store), labelled SMES; its atmos door (130,99) is `"SMES Room"` atmos/glass/critical 24;10 (critical = the chamber's style) | floorplan pieces; doordb style/name learned for (engine_smes, atmos) |
| 10 | Engineering Storage x125-128 y105-113 (36) | good kit (3 SSU, magboots, tank dispenser, sheets, tanks); reached only through the SMES room or the piece above, not the stem or main room | floorplan back room behind the SMES room |
| 11 | SMES closet x103-106 y105-108 (11) | a second bank (2 SMES) in a closet off the locker room with 4 terminals, 2 of them for nothing; grav room (122,103) another: 3 orphan terminals (f21c: 7) | roomdb caps take SMES out and leave their terminals |
| 12 | gravity generator x119-124 y99-104 (29) | one room for generator, SMES and portable generator, 1 radiation closet, no sign; stock 3-room suite with 2 radiation closets in the foyer | floorplan grav room unpieced (function pass: no 3x3 fit in pieces) |
| 13 | engine block | 3 tank dispensers in engineering (stock 1-2); laser room holds a YouTool, requests console, RPD besides its 3 emitters; 4 disposal bins (audit over_type) | dress / essentials on the block, the stamp's own |
| 14 | department | no secure storage (emitters, field and shield generators: stock 7/7), no external airlock (6/7), no delivery windoor (7/7), one maintenance door (stock 1-7, median 3) | floorplan program lacks these types |
| 15 | Atmospherics x130-151 y91-121 | two hall airlocks (139,91), (140,91) with access 0: anyone walks in; no desk; the 320-tile floor holds 4 canisters and 2 thermomachines only: no lockers (no fire suits), SSU, wardrobe, fire axe, extinguishers, pipe dispenser, pumps, scrubbers, tank dispenser, alert console, requests console, fuel/water tank, disposal (audit missing_kit agrees); joined to engineering only through the store piece #9; 24 steps from engineering's front (stock 3-10) | compose builds the block as atmos's corridor area ("atmos 0 rooms, corridor 360"); essentials.apply runs before net.networks lays the atmos works and adds at most 4 a room (f21c still had an SSU and a water tank there, f22 none); doordb.style left the hall doors without access |

Engineering stays good on: lockers, vendors, CE kit, consoles, shared storage, engine block, SMES count in the bank,
Engineering Storage contents, the Bot Shift checks (gloves, solars, supermatter).

## 5. What `fn_engineering.fix()` does (f22: 45 findings before, 4 after, 60 changes)

`python tools/mapforge/gen/learn/fn_engineering.py data/mapforge/gen_learn/f22_c100_s7.dmm out.dmm`; output kept at
`engineering_work/out/f22_c100_s7_fe.dmm`, run log `out/f22_run.txt`, audits `out/audit_before.txt` / `after`.

- corridor: (116,114) window -> `"Engine Room"` engineering/glass airlock, access 10.
- engine_door / store: (119,114) gets access 10, then is walled (r-wall): the SMES bank is a dead end again and the
  walk in is stem -> Engine Room door (f21c: Engineering Storage's door into the engine walled the same way).
- way_in: at the stem's end, beside the walk and off its tiles: showers (115,109) facing east and (117,109) facing
  west, radiation closets (115,113), (117,113), fire closet (115,111); radiation sign on the wall at (117,114).
- CE office: the station alert console that boxed the CE's door moved (106,99) -> (103,99); (108,101) becomes a
  reinforced window with privacy shutters (id ceprivacy) onto shared storage; the shutters' button in the office.
- checkpoint: airlock (128,91) `"Engineering Security Post"` security/glass 63 onto the hall; (125,95) walled.
- tech storage: airlock (121,91) `"Tech Storage"` 23 onto the hall; inner door (118,96) renamed, access 23,
  engineering style; the table (122,96) cutting the store in two moved; secure room's second door (123,94) walled
  (r-wall); its suit storage unit out (Engineering Storage has its own); spawners service, rnd, security,
  engineering, tcomms, medical on racks; AI, command, RnD_secure on the secure room's racks.
- foyer: airlock (106,91) `"Engineering Foyer"` engineering/glass 32;19 onto the hall.
- atmos_door: (130,99) -> atmos/glass `"Atmospherics Access"`, its tile in Atmospherics' area.
- atmos: (139,91), (140,91) access 24; the desk (136,91) `"Atmospherics Desk"` (desks.counter_objs); along the front
  wall: 2 atmos lockers, atmos wardrobe, atmos SSU, pipe dispenser, 2 pumps, 2 scrubbers, tank dispenser, atmos alert
  console (facing the room), fuel tank, high water tank, 5 spare canisters; fire axe cabinet, 2 extinguisher cabinets,
  requests console on the walls.
- terminals: 3 orphan power terminals taken out (105,107), (106,106), (122,103).
- grav: a second radiation closet (124,103); radiation sign on the wall at (125,100).

Left: the atmos disposal bin (needs gen/net.py's disposal network) and the 3 layout findings (secure storage,
external airlock, 3 tank dispensers).

Safety of the pass: every dense piece goes through settle._spot's reach test (no free tile newly cut off, no reached
piece boxed in, off door fronts; the gravity generator's runtime 3x3 counted as dense), every door walled or glazed
only if every tile reached from the halls before still is, nothing wired, piped or linked is moved (settle.FIXED,
disposal bins), showers never on a cable tile (forge/function.py "wet"). A second run makes 0 changes. gen/audit.py
on f22: over_room 4 -> 2, over_type 7 -> 5, missing_kit 12 -> 11, everything else equal (odd_door 3 -> 3: the atmos
door now reads "/atmos/glass belongs to atmos" - the audit's generated-map rule takes the smaller room's style; the
stock eng-atmos doors are atmos-styled 6/6). placestudy: one more "misplaced" piece (the grav radiation closet at 0.30
of its room's depth, stock band 0.6-1.0), otherwise equal. Also run on f21c (44 -> 6), gen_hub_c80_s1, c60_s23,
c120_s41, c90_s31 (older builds, 31-45 -> 6-11): what's left there are rooms the pass can't repair (a CE door boxed by
a disposal bin, no real secure tech room, a 9-tile tech storage piece opening on the checkpoint and SMES room).

Where it runs: last, after `AU.mend` and before the final `AU.seat_big` / audit in gen/build.py (trim would take the
vestibule's closets as a corridor's surplus; doordb.style would rename the doors it makes).

## 6. Generator changes (priority order)

1. **Run the pass in the build.** gen/build.py, after `AU.mend(m, rooms_log.append)` (line 467):
   `sys.path.insert(0, os.path.join(HERE, "learn")); import fn_engineering as FEN; FEN.fix(m, seed, rooms_log.append)`.
   Fixes 41 of f22's 45 findings, including every safety and access one.
2. **Keep the stem's way into the engine.** gen/net.py engine stamp (and floorplan.engine_annex): record the
   corridor's end tile when the annex is claimed; after the block is pasted, put an `"Engine Room"` airlock (10)
   where the block's wall row crosses it. Stock: the department corridor/main room is the way in (6/6).
3. **No store opens into the engine.** gen/learn/doorcount.py and compose.second_doors: never add a door between
   `/area/engine/engineering` annex or `/area/engine/supermatter` and a store type (`engine_smes`, `storage`,
   `gravity_generator`, CE office, tech storage); doordb.style: every airlock into the engine zone takes access 10.
   Stock SMES rooms have one door 5/6.
4. **The safety vestibule as a floorplan piece.** gen/learn/floorplan.py plan(), engineering: the stem's last 4-5
   cells before the annex (or its mouth after the foyer) cut off as a 3-wide vestibule, cycling airlocks
   `"Engine Room"` 10 at both ends (`/obj/effect/mapping_helpers/airlock/cyclelink_helper`), kit by gen/essentials.py
   WORK_KIT for it: 2 showers facing across the aisle (dir 4 on a west wall, 8 on an east wall), 2 radiation closets,
   1-2 fire closets, a radiation sign beside the door. Stock 6/7, 6-12 tiles.
5. **The front: foyer, checkpoint, tech storage on the hall.** floorplan (deptdb front slots): the break room is
   engineering's front room with its own `"Engineering Foyer"` door (32;19, 6/7); the checkpoint opens on the foyer or
   the hall (6/6), never on a store; tech storage takes a hall slot with its `"Tech Storage"` airlock/engineering door
   (23, 7/7) and a 6-tile r-walled secure room inside it (highsecurity 19;23, one door, 6/6); Engineering Storage
   opens on the main room or corridor. The triple stem door (3 airlocks side by side) becomes one or two.
6. **Board spawners.** gen/essentials.py EXACT_KIT/WORK_KIT for `/area/storage/tech`: the six
   `/obj/effect/spawner/lootdrop/techstorage/*` (service, rnd, security, engineering, tcomms, medical), one a rack,
   and AI, command, RnD_secure in the secure room (forge/corpus.py furniture() and essentials NOT_KIT drop every
   `/obj/effect`, so they never arrive; stock 9 on every map, ours 0 on the whole station).
7. **Atmospherics' kit and front.** compose.py atmos block: carve a 30-44 tile front monitoring room on the hall side
   (desk windoor 24 behind blast doors, atmos alert + station alert, tank dispenser, 8-12 canisters, disposal on the
   disposal net); kit the main floor after net.networks lays the works (essentials runs before it and adds 4 at most):
   the list in rule `atmos`; doordb: atmos hall airlocks access 24; join Atmospherics to engineering's foyer with an
   `"Atmospherics"` airlock (24), not through a store (6/7; front-to-atmos walk stock 3-10, ours 24).
8. **Heads' offices.** doordb + doorcount: a head's office has one airlock with the head's access (CE 56), extra ones
   only to the head's own quarters; floorplan paint: a 2-3 tile window run onto the department floor with privacy
   shutters (`/obj/machinery/door/poddoor/preopen{id = "ceprivacy"}`) and the `"Privacy Shutters Control"` button
   (7/7 glass, 5/7 shutters); synth judges the office's reach from its one door.
9. **Secure storage.** floorplan engineering program: a 16-36 tile room off the main room behind blast doors
   (`/obj/machinery/door/poddoor{id = "Secure Storage"}`, button access 11): emitters 4, field generators 4-5, shield
   generators 2-4, portable generator, canister (7/7).
10. **Gravity generator suite.** floorplan: chamber 5x5 + antechamber (SMES, terminal, portable generator) + foyer
    with 2 radiation closets and radiation signs; doors `"Gravity Generator Foyer"` 10, then 19;23 (4/7 head-locked)
    or 11 (3/7).
11. **Smaller ones.** roomdb caps take an SMES's terminal with it (3 orphans on f22, 7 on f21c); one tank dispenser in
    Engineering Storage plus the block's (stock 1-2); an `"Engineering External Access"` cycling airlock pair (10;13)
    from the annex's space side (6/7); an `"Engineering Delivery"` windoor and navbeacon (7/7); 2-3 maintenance doors
    (stock median 3, ours 1); the laser room holds emitters only (dress skips it).
