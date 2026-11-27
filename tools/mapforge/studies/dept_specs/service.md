# Service and civilian: department spec (2026-11-26)

Scope: kitchen and cold room, bar (and atrium/cafeteria), hydroponics and the garden, janitor's closet, theatre,
chapel and chapel office (crematorium), library, law office, dorms, restrooms, locker room, fitness, primary tool
storage, art storage, emergency storage, vacant rooms. The HoP and the courtroom are other agents'.

Map reviewed: `data/mapforge/gen_learn/f22_c100_s7.dmm` (crew 100 seed 7, built without desks.py). Stock maps: the 8
of `forge.corpus.MAPS` (Hippie, Meta, Box, Delta, Pubby, Donut, Endo, MetaLake). "n/8" below is how many of the 8 do
it. "Public" = floor a crew member with no access reaches from the primary halls (no-access airlocks only, never a
windoor or a table); the measure is `fn_service.Ctx.public`.

Pass: `tools/mapforge/gen/learn/fn_service.py` (checks + fixes, `--stock` runs the checks on the 8 maps).
Scratch tools: `studies/dept_specs/service_work/` (`survey.py` joins and kit per room, `ascii.py` two-char-a-tile
crops, `front_stats.py` what each room's doors and counters open on, `pairs.py` before/after pictures).
Pictures: `data/previews/mapforge/dept_service/` (before | after pairs, `roomreview_f22/` cards).

## 1. The Bot Shift failure, found

"botany: harvest stocked in the fridge" fails every generated run and passes every stock run (atmos_bench and
shift_batch logs: 3:05-5:50 on hippiestation). Cause, map side: **no generated map has a plain
`/obj/machinery/smartfridge`** (f21c, f22, c80_s1, c60_s23, c90_s31, c120_s41: 0; they have the disks, virology and
extract fridges only). The bot (`goals/tend_hydroponics.dm find_produce_fridge()`) wants that exact type, powered,
within 30 tiles; with none, `produce` is 0, `stock_produce` is never assigned (the f21c log: 228 tend_tray, 0
stock_produce), and the check's own count (`bot_shift.dm produce_stocked`, exact type) stays 0.

Why it is missing: on the stock maps the produce fridge stands **on the wall turf** between hydroponics and the kitchen
(Hippie, Meta, Box, Pubby, MetaLake; Delta and Endo: in hydroponics' wall onto the staff service hall; Donut: none). The
generator copies rooms by their floor tiles (roomdb/synth) and essentials counts floor families, so in-wall machines
never come across: stock walls carry 8 plain smartfridges (7/8 maps), 14 chemistry fridges (8/8), 3 drinks fridges
and 5 vendors; f22 walls carry none. `essentials.py --show hydroponics` has no smartfridge either.

fn_service.fix_fridge sets one into hydroponics' wall: the wall it shares with the kitchen first, else the wall onto
the corridor or hall the Cook reaches in 30 steps (staff/service corridor before a public primary hall), straight wall,
both fronts free, every workplace tray within 30; a hung poster is slid along (desks._shift); with no such wall, a
free-standing one inside hydroponics. f22: (100,84), hydroponics (99,84) / service corridor (101,84), 5 steps from the
kitchen door (104,85). Not booted (no servers in this pass): the next Bot Shift on a fixed map is the proof.

## 2. Rooms: required and optional (stock)

| room (area) | stock | tiles (stock) | f22 |
|---|---|---|---|
| kitchen | 8/8 | 45-90 | 45 |
| cold room (kitchen/coldroom) | 4/8 (Meta, Donut, Endo, MetaLake; others keep the freezers in the kitchen) | 25-29 | 21 |
| bar (+ Delta's atrium, Pubby's cafeteria) | 8/8 | 128-173 | 126 |
| bar backroom / storage (in the bar area, door 25) | Hippie, Meta, Box | | none |
| hydroponics | 8/8 | 87-121 | 101 |
| garden (public, soil plots) | 6/8 | 43-56 | 20 |
| staff service hall (hallway/secondary/service) | 6/8 (84 and 170 tiles on Delta and Endo, 6-9 tile stubs elsewhere) | | none (a public corridor in /area/crew_quarters instead) |
| janitor's closet | 8/8 | 16-27, one piece | 17 in two pieces |
| theatre (backstage) | 8/8 | 17-51 | 24 |
| chapel (main) | 8/8 | 120-169 (Pubby 405) | 94 |
| chapel office / crematorium | 8/8 | 36-94 | 31 |
| library | 8/8 | 108-234 | 87 |
| law office | 8/8 | 24-35 | 16 |
| dorms (corridor + cabins) | 8/8 | 97-126 (Donut 35, Endo 298) | 106 |
| restrooms (crew_quarters/toilet*) | 7/8 (Donut: showers in the locker room) | 21-73 | **none** |
| locker room | 6/8 | 35-132 | 48 |
| fitness | 7/8 | 32-344 | 93 |
| primary tool storage | 7/8 | 51-84 | 45 |
| art storage | 6/8 | 12-14 | 8 |
| auxiliary tool storage (storage/tools) | 6/8 | 18-27 | 12 |
| emergency storage | 3/8 | 16-39 | 8 |
| vacant room / office | 7/8 | 21-166 | 36 + 8 |

## 3. Each room: what it is for, who uses it, what it holds

**Kitchen (Cook).** The cook takes eggs and milk from the kitchen fridge (`secure_closet/freezer/fridge`), meat from
the meat freezer, produce from the shared smartfridge, cooks in the microwave (2 on 8/8), processor (1), deep fryer (2
on 8/8), grill (Hippie), and sets plates on the **serving counter** the crew helps itself from (`goals/cook.dm
find_serving_table()`: a table on kitchen ground beside floor outside the kitchen). Kit (essentials, 74-100% of stock
kitchens): processor, rolling pin, grinder, kitchen sink, microwave, egg fridge, paper sacks, deep fryer, dinnerware
vendor, disposal bin, recipe book, CondiMaster (1 on 8/8). Gibber 1 a station (7/8), meat spikes 2. Staff only: 0
public tiles 8/8, doors 28. Joins: serving counter onto the bar 6/8 or a public hall 3/8 (8/8 have one; 4-8 counter
tiles, table + shutters "Serving Hatch"); a staff door into the bar's staff side 6/8 (Hippie, Meta, Box, Pubby, Endo,
MetaLake); a door into hydroponics 3/8 ("28;35"); its cold room 4/8; maintenance 2/8.

**Cold room.** Gibber, 2 meat spikes, meat freezer, (ice cream vat, cooking oil). Opens into the kitchen and
maintenance only (8/8 of the 4 that have one: never the bar or a hall).

**Bar (Bartender).** Patrons' floor (stools at the counter, tables, the arcade, the cigarette and snack machines) is
public; the **staff side** behind a counter of reinforced tables holds the Booze-O-Mat (glasses), the soda and booze
dispensers on tables, the drinks fridge; the bartender enters by a "Bar Door" windoor (25;28) or the backroom.
Measured: no public tile in front of any dispenser or Booze-O-Mat on 8/8. Bot: `goals/bartender.dm` (glass from the
Booze-O-Mat, spirit from the beer dispenser, mixer from the soda one, glass set on the counter). Backroom/storage: the
shotgun, the bar closet, the beer keg (Hippie, Meta, Box). Doors: a primary hall 7/8 (public "Bar" glass airlocks),
maintenance 6/8 (Delta, Endo: the staff service hall instead), the kitchen 6/8.

**Hydroponics (Botanist).** 14-16 trays (8/8), seed vendor, nutrient vendor, seed extractor, biogenerator, DNA
manipulator, high-capacity water tank (91%), sinks, grinder, CondiMaster, hydroponics closets and crates, the disks
fridge, the botanist wardrobe. The harvest goes into the **produce smartfridge set in the wall it shares with the
kitchen** (5/8; Delta, Endo: onto the staff service hall; 7/8 have one), often beside a "Hydroponics Window" counter
(28/35) and a staff door (Meta, Pubby, MetaLake). Staff only (0 public tiles 8/8, doors 35); a **public desk** (table +
windoor "Hydroponics Desk", 35) onto a primary hall 7/8 (Endo: onto the bar), 2 tiles; a maintenance door 8/8.

**Garden.** Public soil plots, seed extractor, biogenerator, cultivators, plant analyzers, hatchets (75-90%); doors to
a hall or the locker room / maintenance.

**Janitor's closet (Janitor).** One room of 16-27 tiles, door "Custodial Closet" (26) **straight onto a primary hall
(5/8) or maintenance (6/8)**: the cart rolls out at once. Holds the janitorial cart, mop bucket(s), the janicart (+key),
the JaniDrobe (galoshes: `goals/janitor.dm` gets them first), a sink or water tank (the bucket fills there), the
custodial closet, light replacer, wet floor signs. 0 public tiles 8/8.

**Theatre (Clown, Mime).** Backstage: 0 public tiles 7/8, doors 46 "Theatre Backstage" plus maintenance 8/8. The stage
is the bar's: the theatre adjoins the bar 6/8 by "Theatre Stage" windows/windoors or a door. Holds the autodrobe, piano,
dresser, mirrors, instruments, costume crates.

**Chapel (Chaplain).** Public chapel (pews 6+, the altar table at the front: `goals/chapel.dm` holds services there),
doors onto the departures/exit hall 5/8 or a primary hall 2/8 (funerals by the escape shuttle). Chapel office (22) with the crematorium (one, `id =
"crematoriumChapel"`, and its `button/crematorium` with the same id, 27) or a separate crematorium room (27), coffins,
the chaplain's closet, a maintenance door 7/8.

**Library (Curator).** Public, 108-234 tiles, doors onto primary halls 6/8 (and the chapel 3/8). Bookcases, the
library consoles (public + bookmanagement), scanner, binder, photocopier, reading tables, the curator's back room and
"Library Desk" windoor (37) on Meta/Box/Delta.

**Law office (Lawyer).** 24-35 tiles, doors "Law Office" 38 onto a primary hall 6/8 or the courtroom 3/8, maintenance
7/8; **never inside security (0/8)**. Desk, filing cabinet, briefcase, law closet, photocopier.

**Dorms, restrooms, locker room, fitness (crew off duty).** Dorm cabins (beds, dressers, lockers) off a dorm corridor;
the restrooms beside the dorms or the locker room (doors to the dorms 6/8, the locker room 5/8): 5-28 showers and 2-9
toilets in the crew quarters on 8/8, sinks, mirrors, toilet stalls ("Unit 1-4" doors). Locker room: wardrobes, personal
lockers, the clothes vendor, washing machines. Fitness: weights, punching bag, boxing ring, holodeck.

**Primary tool storage.** Public, doors onto a primary hall on every stock map that has one (7/7; + maintenance 5/7), the YouTool and
Vendomat, toolboxes, cell charger, welding and fuel tanks.

## 4. Checkable rules (fn_service.RULES; stock = maps that pass of 8)

| id | rule | stock |
|---|---|---|
| produce_fridge | a plain smartfridge beside hydroponics floor, every tray within 30, the Cook reaches it in 30 steps | 7/8 (Donut has none) |
| kitchen_counter | a table on kitchen ground beside public floor (the serving hatch) | 8/8 |
| kitchen_staff | no public floor in the kitchen or cold room | 8/8 |
| coldroom_joins | the cold room opens only into the kitchen or maintenance | 8/8 |
| hydro_staff | no public floor in hydroponics | 8/8 |
| hydro_desk | a hydroponics table beside public floor (the desk) | 8/8 |
| hydro_kit | 8+ trays, seed + nutrient vendors, seed extractor, biogenerator, DNA manipulator, water | 8/8 |
| bar_staff_side | no public tile in front of the Booze-O-Mat or a drink dispenser | 8/8 |
| bar_kit | soda dispenser, booze dispenser, Booze-O-Mat (in-wall ones count) | 8/8 |
| bar_public | the public reaches the bar | 8/8 |
| kitchen_kit | microwave, processor, fryer, sink, egg fridge, dinnerware; gibber, spike, meat freezer | 8/8 |
| kitchen_counts | one gibber, one CondiMaster, two microwaves | 7/8 (Donut 2 gibbers) |
| janitor_door | each closet piece has its own airlock onto a hall, corridor or maintenance | 7/8 (Pubby) |
| janitor_kit | mop bucket or cart, JaniDrobe, sink or water tank | 8/8 |
| theatre_staff | no public floor in the theatre | 7/8 (Endo) |
| theatre_bar | the theatre within 2 tiles of the bar | 6/8 (Delta, Endo) |
| restroom | 2+ showers, 2+ toilets, a sink in the crew quarters, within 25 steps of the dorms | 8/8 |
| dorm_beds | 4+ beds in the dorms | 7/8 (Pubby 3) |
| chapel | 6+ seats, a front table, one crematorium with its button | 7/8 (Pubby: 2 crematoria) |
| library | 3+ bookcases, console, scanner, binder, public | 7/8 (Pubby's is off the chapel only) |
| law_office | no door into the armory, brig or warden's; the Lawyer (38, 42, 63) walks in from the halls | 8/8 |
| tool_storage | public, YouTool or Vendomat | 8/8 |

## 5. Review of f22, room by room (defect, coordinates, cause)

Layout of the service block (ascii.py 88 62 117 88): hydroponics (91-99, 74-85) | 3-wide public corridor
`/area/crew_quarters` (101-103, 65-86, "Central Access" doors from the starboard hall at 101-103,86) | kitchen (105-110,
78-85) with the cold room (112-114, 79-85) above the bar (105-114, 65-77); theatre (91-94, 67-73), garden (96-99,
65-69) and the janitor's two pieces west of the corridor.

| # | defect | where | cause (generator) |
|---|---|---|---|
| 1 | no produce smartfridge anywhere: Bot Shift botany fail | station | in-wall machines never copied (roomdb/synth floor tiles, essentials floor families) |
| 2 | kitchen has no serving counter (the user's "kitchen needs a serving window") | kitchen-bar wall 105-109,77-78 | desks.py not in f22's build; when it runs, chance 0.85 |
| 3 | hydroponics and kitchen don't share a wall; the 3-wide public corridor between them | 100-104 | floorplan strips: kitchen and hydroponics on opposite sides of the stem corridor (stock 5/8 share a wall) |
| 4 | hydroponics public: its only door "Central Access" (no access) | 100,81 | doordb treats the service corridor as the central hall (doordb.py line 44 maps /area/crew_quarters to hallway/primary/central) and learned "public" from what lies beyond |
| 5 | no hydroponics desk; front wall onto the hall lined with trays, east wall glass | 94-99,86; 100,76-78 | synth fills the hall-side wall; desks HALL only (no service corridor), chance 0.8 |
| 6 | bar has no staff side: Booze-O-Mat (105,65), soda (109,66) and beer (109,70) dispensers on the patrons' floor; a half counter line of glass tables at x 109 | bar | synth's bar exemplar copied in pieces; the counter line lost its ends |
| 7 | bar reached only through the service corridor, no hall door, no maintenance door, no backroom | 104,74 | floorplan: the bar is a strip room off the stem, not on the hall side |
| 8 | cold room door straight into the bar ("Kitchen Cold Room", 28) | 114,78 | a second door to its other neighbour (doorcount or compose.second_doors, not traced) |
| 9 | janitor's closet in two pieces (91-94,65-66 and 96-99,71-73), reached only through the theatre (91,67) and the garden (95,65; 98,70) | | the closet's area split over two strip leftovers (not traced: floorplan carve or walls), doors to whatever neighbours |
| 10 | no JaniDrobe (galoshes: the bot's first errand) | janitor | essentials share 0.7 not met by the closet's family; not in WORK_KIT |
| 11 | theatre public (door "Garden", no access) and not by the bar (across the corridor, behind hydroponics) | 95,69 | doordb public-room rule; deptdb has no theatre-bar partner |
| 12 | **no crew restroom: no shower or toilet for the crew on the station** | dorms block 77-96,112-129 | dorms program never drew /area/crew_quarters/toilet (the stock type is split over toilet, toilet/restrooms, toilet/auxiliary, toilet/locker so no single type reaches must-have) |
| 13 | kitchen: 2 gibbers (105,83 + cold room 114,80), 2 CondiMasters (kitchen + 113,80), 1 microwave (stock 1/1/2) | | per-station caps missing for these (roomdb.caps covers SMES, clone pods) |
| 14 | chapel office: two crematoria (52,114; 52,122), no button: nothing can be cremated | | synth LINKED drops buttons; no station cap on crematoria |
| 15 | chapel main 94 tiles (stock 120+), office 31 (36+), law office 16 (24+), tool storage 45 (51+) | | civic plan squeezed; room sizes |
| 16 | law office inside the security block: doors to the security office (135,80, needs 1;4 beyond) and **into the armory (141,79)**: a Lawyer's 38 opens the armory; the Lawyer can't reach the office | 136-140,78-81 | program put lawoffice in the security plan; doordb named both doors "Law Office" 38 |
| 17 | the civic block's corridor is /area/chapel (holy ambience, no clockwork warp, the HUD says Chapel): tool storage, library, art and vacant rooms open onto "the chapel" | 45-71,124-125 | rooms.CORRIDOR_AREA["civic"] = "/area/chapel" |
| 18 | tool storage opens only onto that corridor, not a primary hall (stock 7/7 hall) | 66,123 | same |
| 19 | hydroponics and the bar have no maintenance door (stock 8/8 and 6/8) | | doorcount adds doors toward halls/neighbours, not maintenance |
| 20 | audit "orphan" false alarm on a crematorium button | 50,122 | audit.py counts ids on /obj/machinery only; the crematorium is /obj/structure |

## 6. fn_service.py on f22

`python tools/mapforge/gen/learn/fn_service.py data/mapforge/gen_learn/f22_c100_s7.dmm <out>`; 16 changes; checks
**23 -> 4**; second run 0 changes (idempotent); audit.py before/after: no new finding except the false crematorium
orphan (#20), missing_kit 12 -> 12 (janitor's wardrobe gone from the list); also run on f21c (15 -> 3), c80_s1 (18 -> 9),
c60_s23 (17 -> 6), c90_s31 (17 -> 7) without errors.

| fix | f22 |
|---|---|
| produce smartfridge in hydroponics' wall | (100,84), poster slid to (100,85) |
| kitchen serving hatch (desks.py's own pieces; bar, atrium, cafeteria, hall, public corridor) | (108,77), (109,77) onto the bar |
| hydroponics desk | none: no clear wall (see #5) |
| staff access on public doors | hydroponics 100,81 -> 35; theatre 95,69 -> 46 "Theatre Backstage" |
| bar staff side | counter 109-113,67 + "Bar Door" windoor 114,67 (southright, 25;28); Booze-O-Mat 114,65, soda 113,65, beer 110,65 on tables; walk row 110-114,66; shotgun, cash, bottles, grinder on the staff table 109,66 |
| cold room door into the bar | 114,78 walled |
| law office door into the armory | 141,79 walled |
| janitor | door cut 100,73 onto the corridor; garden door 98,70 walled; JaniDrobe 98,71 |
| restroom | cabin by 88,116 (6 tiles): 2 showers, 2 toilets, sink, door "Unisex Restrooms" (a stopgap: stock restrooms are 21-73 tiles) |
| crematorium | 52,114 removed; button 50,122 (id crematoriumChapel, 27) |
| kitchen counts | gibber 105,83 out (cold room keeps its own), CondiMaster 113,80 out, microwave on 108,81 |

Left (layout): hydro_desk, janitor_door (the 8-tile piece behind the theatre), theatre_bar, law_office (the Lawyer
can't walk in).

Pictures (before | after): `service_block.png`, `kitchen_bar.png` (hatch, counter, walled cold-room door),
`hydro_fridge.png`, `janitor_theatre.png`, `dorms_restroom.png`, `chapel_office.png`, `law_office.png`,
`bar_after_zoom.png` (the staff side at full scale).

## 7. desks.py on our map, and what its table should change

On f22 desks.py cut kitchen->bar x2 at (108,77), (109,77) and nothing else of ours (no hydroponics desk: the hall wall
is all trays and the service corridor isn't a HALL; no hydroponics-kitchen pass: no shared wall). Changes to COUNTERS:

1. Kitchen: one row, faces in order bar, bar/atrium, cafeteria, HALL, the department corridor when public; chance
   0.85 -> **1.0** (8/8 kitchens serve onto public floor); tiles (2,3) -> **(2,4)** (stock hatches 4-8 tiles).
2. Hydroponics desk: chance 0.8 -> **1.0** (8/8), faces HALL, then the department corridor when public, then the bar
   (Endo).
3. Hydroponics -> kitchen "pass": keep 0.4 for the windoor, but always add the **produce smartfridge** in that shared
   wall (5/8 stock; it is what the Botanist and Cook bots use). Or leave the fridge to fn_service.fix_fridge.
4. HALL (`_matches`) takes /area/hallway/secondary/*, which includes the staff service hall: public desks (kitchen
   hatch, hydroponics desk, chemistry) should not count /area/hallway/secondary/service as public.
5. Lean test: `_hung` uses CO.mounted (16 px); sinks hang at 11 px, so a desk can cut the wall a sink leans on
   (f22 100,75). Use 8 px (fn_service._leans_unmounted).
6. New row: theatre -> bar "Theatre Stage" (window + windoor, 46) when they share a wall (stock: 4 "Theatre Stage"
   windows/windoors).

## 8. Generator changes (priority order)

1. **In-wall machines (Bot Shift botany fail).** Either run `fn_service.fix(m)` in gen/build.py after desks.fix and
   before fixtures/nets (it needs the final walls; the fridge needs power, so before net.power's APC sweep is fine,
   its tile takes the hydroponics area), or carry in-wall machines in gen/learn/synth.py: when a room is furnished from
   a stock exemplar, record the machines on the exemplar's wall tiles beside its floor with the type of room across,
   and re-seat them on the generated room's wall toward the same neighbour type after walls are final. Stock: plain
   smartfridge 8 on walls over 7/8 maps, chemistry fridge 14 over 8/8 (medical's), drinks fridge 3/8, vendors 5.
2. **Kitchen beside hydroponics, sharing a wall.** gen/learn/floorplan.py (deptdb nb partners): kitchen-hydroponics as
   side-by-side partners in the service plan (stock 5/8 share a wall with the fridge, +3/8 a staff door "28;35"; 2/8 face
   the same staff service hall; f22 put the 3-wide public corridor between them).
3. **Restroom must-have.** gen/program.py / floorplan must-have list: treat /area/crew_quarters/toilet and its
   subtypes (restrooms, auxiliary, locker) as one type so it reaches must-have (7/8 have the area, 8/8 have 5-28 crew
   showers and 2-9 toilets); place it beside the dorms or the locker room (doors 6/8 dorms, 5/8 locker), 21-73 tiles,
   freezer floor, showers + stalls.
4. **Service hall staff-only, public fronts on the hall.** gen/rooms.py CORRIDOR_AREA["service"]: "/area/crew_quarters"
   -> "/area/hallway/secondary/service" (6/8 have that area), its doors req_one_access "25;26;28;35;37;46" like the
   stock "Service Hall"/"Bar Maintenance" doors; doordb.py line 44 stops mapping it to the central hall. Then the
   floorplan must give the bar (public doors, 7/8 on a primary hall), the hydroponics desk (7/8) and the garden the
   strip facing the primary hall, and the kitchen, hydroponics door, janitor and theatre backstage the service hall.
5. **Bar staff side.** synth/roomdb: the bar exemplar keeps its counter line whole (or furnish the bar from a "staff
   band" first, as fn_service.fix_bar does: back row on a wall from a corner, walk row, reinforced-table counter, "Bar
   Door" windoor 25;28); a bar backroom (bar area, door 25) and a maintenance or service-hall back door (8/8).
6. **Janitor's closet one piece, own door.** floorplan: the janitor type is never carved into pieces; its door faces
   the corridor/hall or maintenance (5/8 hall, 6/8 maint), never another room; essentials WORK_KIT["/area/janitor"]
   += JaniDrobe, mop bucket (the bot's galoshes and bucket).
7. **Theatre by the bar, backstage access.** deptdb partners theatre-bar (6/8 adjoin); doordb: theatre doors 46
   "Theatre Backstage" (7/8 no public floor); a maintenance door (8/8).
8. **Law office out of security.** program: lawoffice belongs to the civic block (or beside the courtroom on its hall
   side): doors onto a primary hall 6/8, the courtroom 3/8, maintenance 7/8, inside security 0/8; 24-35 tiles.
   doordb must never put a "Law Office" door onto the armory/brig/warden.
9. **Civic corridor area.** rooms.CORRIDOR_AREA["civic"] = "/area/chapel" makes the hall holy and names it Chapel;
   use the adjoining primary hall's area (tool storage 7/7, library 6/8 open onto a primary hall) so doordb/desks see a
   HALL.
10. **Linked and capped pieces.** synth.LINKED: keep a crematorium and its button together (same id) instead of
    dropping the button; roomdb.caps: crematorium 1, gibber 1, CondiMaster 1 (kitchen), microwave 2, deep fryer 2 a
    station (7-8/8).
11. **Maintenance back doors.** doorcount.py: hydroponics (8/8), theatre (8/8), chapel office (7/8), law office (7/8),
    bar (6/8) get a maintenance door when maintenance lies across one wall.
12. **Sizes.** chapel main 120+, chapel office 36+, law office 24+, tool storage 51+ (stock minimums; f22 94/31/16/45).
13. audit.py orphan: count ids on /obj/structure/bodycontainer/crematorium too (false alarm after the button fix).
