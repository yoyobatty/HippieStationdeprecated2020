# station_v6: where it stands (paused 2026-11-22)

The v6 station is the hand-drawn plan (plan/station_plan.py, plan/canvas.py) with all ten departments drawn tile by
tile (blueprints/*_v6.py + assets/*_v6.py), laid into one map by `station/v6_station.py`, which then adds everything
the departments share.

```
python tools/mapforge/mapforge.py build blueprints/<dept>_v6.py     # one department -> data/mapforge/<dept>_v6.dmm
python tools/mapforge/station/v6_station.py [--no-render] [--name trial]   # all of them -> data/mapforge/station_v6.dmm
```

## 2026-11-22: room habits, room budget, and the gate (UNCOMMITTED)

The user's rulings this round:
- "fix habits";
- "rooms that are inappropriately oversized should be shrunk and that new room should be naturally absorbed into the
  station's size budget ... objective data with iterations";
- "shouldn't the lints ensure no generation generates poor maps to begin with".

New tools in `forge/`:
- `room_stats.py`: the per-room numbers the other tools share.
- `room_twin.py`: each room beside its stock twins.
- `style_bands.py`: each room against the band of every stock room of its type.
- `disc_rooms.py`: the discriminator's verdict per room.
- `size_budget.py`: oversized rooms, missing types, department shares and hall widths.
- `room_stamp.py`: copies a stock room whole.

New steps in `v6_station.py`:
- **rooms** (`station/v6_rooms.py`), right after maint rooms:
  - the arrivals and escape lobbies get the arrivals and escape hall areas;
  - the three oversized maint rooms (garden, aux tool storage, abandoned theatre) are left unbuilt;
  - their tiles, the plazas, the public lounges and nearby maint go to the 9 missing stock room types. Each is
    copied whole from Meta, Delta or Hippie, scored on size off the stock median, distance from its department,
    a door onto a way out, and the department's stock share;
  - leftover hall pockets become maint closets.
- **habits** (`station/v6_habits.py`), after bins, from each room's stock peers:
  - light switches, holopads, status displays and other wall pieces;
  - plain chairs swapped for the chair the peers use;
  - furniture and items up to the peers' median.
- **gate** (`station/v6_gate.py`), after the write. The build exits 1 when a check fails:
  - department shares and hall width against the stock maps;
  - no oversized rooms and no missing room types;
  - no room the discriminator calls generated;
  - wall-piece faults and rooms below the stock band, never worse than the accepted baseline in
    `data/mapforge/gate_v6.json` (written from the pushed 46a3a40f build; `--accept` only after the user looks).

Results of this round:
- Disc: 12% -> 0% of tiles called generated. It saw the stock maps in training, so its verdict on the copied rooms
  is not independent.
- Fingerprint: 15 -> 11/38 features outside the human range.
- Halls: 20.5% -> 14.1% of the floor. Hall floor 7+ wide: 52% -> 33%.
- Missing room types: 11 -> 2. Aux base and test range need space outside the hull and are not placed yet.
- Boot: 0 runtimes, the pre-existing 2 open pipe ends, every copied room powered.

**Gate failures left (10 of 25)**, the next iteration:
- Shares: hall 14.1% (max 12.9%), maint 13.9% (min 14.9%), science 10.8% (max 10.3%), civic 7.0% (max 6.8%),
  atmos 3.2% (min 3.5%).
- Hall floor 7+ wide: 33% (max 19%), mostly the arrivals and escape lobbies.
- Oversized department rooms, all in the hand-drawn blueprints: dorms 150, EVA 80, grav gen 79, sci lab 65, law
  office 35, teleporter 35, sci server 21.
- Wall pieces: stacked 24 (baseline 7), both faces 134 (127), over furniture 220 (160). Mostly from the copied
  stock rooms: humans hang pieces like that, and the ruling says no.

### Iteration 2 (same day): the gate passes, 25 of 25

What changed:
- **Gravity generator:** redrawn as a 6x5 chamber plus a 4x5 antechamber (50 tiles; stock 35-60).
- **Atmos** (plan block +5 rows south into space, over the maint row and the emergency storage):
  - a gas storage room holds the canisters and the tank consoles;
  - five chambers along the hull, a CO2 chamber added;
  - the waste filter bank (`v6_station.waste_bank`): plasma and CO2 go back into their tanks, the rest out east;
  - the main floor has both pipe dispensers, the tank dispenser and the alert consoles;
  - atmos is kept off the glazing list.
- **Redrawn rooms:**
  - EVA 80 -> 75; teleporter 35 -> 28; tech storage takes the difference, since command sits at its stock minimum.
  - Law office 35 -> 25.
  - Dorms 150 -> 112: the lounge became the locker room, and the old locker room went into fitness (108).
  - R&D 65 -> 40; server room 21 -> 15.
- **v6_rooms:**
  - arterials become maint, fewest public doors first, until the hall share fits (art SE);
  - the lobbies are cut to 6 wide, and the south end of arm S is escape;
  - a pocket that is the only way to something keeps a corridor through it;
  - department-share-aware placement;
  - abandoned maint rooms are skipped when their department is over budget (the research lab and the library).
- **v6_station:**
  - builds in rounds: an over-budget department loses an abandoned room, then the station is rebuilt;
  - a vent never lands on a network's root tile.
- **v6_tidy** fixes the wall-piece faults everywhere: slide along the wall, else re-hang on another wall, else drop
  decoration or a spare camera, light or intercom from a pile.

Proof:
- Gate: 25/25.
- Boot: 0 runtimes; the 2 known open pipe ends.
- Bot Shift 15 min: 99/99 APCs, SMES 60->84%, crystal 1519-1563 MeV, 3/3 emitters, all 16 bots aboard evac. The
  janitor fail and the Atmospherics flag are the same as in the committed build. Port Solar Maintenance no longer
  drops to 0 kPa.

Open:
- **Atmos main floor:** still mostly bare floor. The stock rooms run a mixing loop of pipes across it. The gate didn't
  catch this, because the room's numbers include the chambers. It needs a per-room content check in the gate, then
  the loop.
- **Aux base and test range:** not placed; they need space outside the hull.
- **Atmos chamber siphons:** zone_check calls them "not on a network". That's a false alarm, because the check counts
  pipelines of fewer than 3 segments as dead.

### Iteration 3 (same day): the full regression gate (IN PROGRESS, UNCOMMITTED)

The user, after seeing empty maint rooms: "leave nothing regressed ... how can we be much more efficient".

**Why regressions got past:** the gate had 25 whole-map checks and a ratchet on 6 numbers. Nothing measured maint
fill, and atmos' numbers included its chambers. I tuned margins by hand (0.97/0.93/0.95: ~5 wasted rebuilds) and
looked at pictures only after the gate passed.

**Now:**
- `v6_gate.full_check` runs on every build against `data/mapforge/station_v6_accepted.dmm` (the pushed 46a3a40f).
  It fails on any of these:
  - a room number further outside its stock band than in the accepted build;
  - a new room outside its stock band in tiles, furniture, items, pieces or doors;
  - a maint pocket emptier than the emptiest stock ones (0.076 furniture per tile) or bigger than the biggest
    (310 tiles);
  - a fingerprint feature further from the human range. All but `struct3_js` and `furn3_js`, which need the
    3-minute pooled run.
- It runs in about 14 s; the human ranges are cached in `data/mapforge/gate_fp_ranges.json`.

**Attribution by ablation, not guessing:**
- Switches: `V6_NO_TIDY`, `V6_NO_HABITS`, `V6_NO_ROOMS`.
- Build with `--name abl_X --no-gate`, then `v6_gate.py data/mapforge/abl_X.dmm`, then diff the regression lists.
- First result:
  - tidy caused 12 regressions (it dropped lights and pieces in accepted rooms);
  - habits caused none;
  - the room budget saves more than it costs (38 regressions without it).
- Tidy now touches only rooms that didn't exist in the accepted build, plus halls and maint, and never drops a light.

**Empty maint rooms:**
- Leftover slot space gets stock maint rooms copied in (`v6_rooms.fill_maint`: pockets from Meta, Delta and Hippie
  with at least the median furniture, 12-120 tiles). Four placed.
- The rest, and every hall pocket, becomes wall; corridors are kept where something needs them. Empty closets are gone.

**Left (the last ablation build, abl_NONE):**
- 21 regressions: mostly the blueprint redraws (dorms, locker, grav gen, law office, sci lab, tech storage, library
  lounge) and the fingerprint (hull glass, odd share, dead ends, loops, tile decals);
- halls 7+ wide at 22% (the walled pockets shrank the hall total, so the lobbies weigh more);
- stacked 11 and over furniture 197, against baselines of 7 and 160;
- the disposal exit moved to 37,75 by virology: check it;
- `data/mapforge/station_v6.dmm` is older than the code; rebuild before trusting it.
- Next: work the list one cause at a time; after each change, ablate and gate until 0. Make the lookkit before/after
  sheet of changed rooms part of every build (`dk.py lookkit diff` on same-region renders gives the changed boxes).

### Iteration 4 (same day): the gate at 0 (UNCOMMITTED)

The user, mid-way: "you filled in space with a shit ton of walls, I keep saying not to do that" (the leftover pockets
were walled: 255 tiles of 3x3 solid wall), then "is that the right call? seems like a guess", then "the styling of eva,
tech and secure tech needs an improvement, just kind of 1 uniform tile".

**Result:** `station_v6` gate PASS, 0 of 27 checks failed, 0 regressions against the accepted build (from 21 plus 3
failed checks). Pictures: `data/previews/mapforge/gate_v6_1122/` (now.png full map, before_after_sheet.png, one
*_pair.png per changed area).

**New tools:**
- `station/v6_ablate.py`: builds the station once per switch set (`--sets NONE,V6_NO_TIDY,...`, `--jobs 2`), gates each
  against the accepted build, prints one row per regressed stat with the raw value, the accepted value and the stock band.
  `--maps a.dmm,b.dmm` compares any builds. Switches: `V6_NO_TIDY/HABITS/ROOMS`, `V6_SKIP=layout|glaze|polish|pockets|
  plazas|details|fixtures`, `V6_POCKETS=stock|maint|wall`.
- `studies/room_diff.py AREA [--a map --b map --tiles]`: one room in two builds, stats against the band, floor and objects
  gained and lost per tile.
- `forge/room_stats.map_pieces(m, tiles)`: wall pieces and faces exactly as room_stats counts them, for builders.
- Gate check **solid wall filler**: 3x3 solid wall tiles (not mineral) against the stock max (Meta 8, Delta 0, Hippie 12,
  Omega 0). Now 4.

**Causes found and fixed (each by ablation or room_diff, then a rebuild and the gate):**
- Wall filler: leftover pockets now get stock maint rooms, then dressed maint behind one wall and a door
  (`V6_POCKETS=stock`, the gate's pick: 52 regressions vs maint 53 vs wall 50 + 255 filler tiles); a 1-wide pocket stays
  hall; `pocket_fill` dresses any maint pocket under the stock fill again. The 3-row wall left under the old gravity
  chamber became Shared Engineering Storage (`/area/engine/storage_shared`, Meta/Delta have one).
- Shared random streams: fixtures, details, layout islands, habits and maint rooms drew from one stream each, so any change
  reshuffled every room (the bridge's intercom landed on its only bin spot). All seeded per room or per tile now.
- Underfloor counted as taken: bins and habits refused tiles with cable or pipe (stock bins and furniture stand on them).
  Also: habits' furniture loop stopped after 12 tries, and its connectivity test wanted the whole room in one piece (most
  rooms the stock measure joins across a wall are several), so engineering, atmos and the lounge got nothing. Habits now
  furnishes atmos (not its gas chambers), stands loose furniture at each family's stock off-wall share, caps dense at the
  stock max, and adds lights up to the stock minimum before its furniture fills the walls.
- Room budget: free tiles are hall/maint only (a slot box stamped over genetics' maint door); a hall tile touching a room's
  floor stays (chemistry's counter); a copied room may not take the last maint a room's back door needs; of the stock
  examples of a type, the one with the fewest wall-piece faults is copied (Hippie mostly); copied maint rooms drop tile
  colour (stock maint is bare); fit_in hangs APCs and alarms over bare floor.
- Bins before fixtures (kit before decoration), backed by walls already dead for pieces when it can; a bin trades its face
  for a poster after habits only if neither pieces nor dense ends further from its band than accepted (captain's office;
  the AI upload camera that held its wall moved to another face).
- Fixtures: posters while a room is under its stock pieces band (not a 70% coin), never past the band max in a copied room.
- Tidy: runs before habits; fixes every fault that wasn't one in the accepted build, moves pieces within their own door-split
  room only, sheds decoration and duplicate intercoms/cameras from copied rooms over their pieces max, and moves a pile's
  piece over furniture when no bare face is left (one piece per face is the user's ruling; bare floor the softer one).
- Glaze: per-room glass cap (stock max or the accepted value); rooms under their glass band, two rooms of one department, and
  maint into maint may take windows (stock walls between rooms of one department are 0.26-0.32 glass, v6 was 0.16); runs go
  on past hung pieces; maint hull every other tile (stock maint hull 0.24-0.59, v6 was 0.11); rooms the accepted build had
  one piece from their band minimum keep their bare faces.
- Hall trim one quarter per wall side (Meta: 486 of 590 trimmed edge tiles); tile decals were 0.60 a floor tile against the
  human max 0.56.
- Docks trimmed to 6 rows (the hull moves in a row; halls 7+ wide 23% -> 14%, stock max 19%). Disposal exit must throw into
  open space to the map edge (it had picked a one-tile space slot at 89,28).
- The user, seeing atmos: "atmos doesn't appear to have a primary way in except via maint, also the disposals and waste
  pipe outlet spot is gone". Causes: the hall-share step had turned art SE, the arterial atmos' front door opens onto, into
  maint; the disposals exit followed the bins' middle away from atmos once the redraw put chambers on the south edge.
  Now an arterial turned to maint keeps, full width, the stretch from each public door on it to the rest of the halls
  (atmos and the room north of it: 44 tiles kept, one maint mouth at x119), and the disposals exit goes beside atmos' waste
  outlet (driver at 119,38 throwing east, the waste injector at 122,39).
- Blueprint redraws, each checked against the band and the accepted value:
  - Dorms: the hall ends at the cabins (fill 0.57), cabins 5-6 beside each other on wood, the locker room (rows 17-24) is
    the way in from arm E with the restrooms off it; `lockers3` places by wall runs (lockers2 had hard-coded the old
    room's tiles); fitness ring margin reserved. A heredoc had put a literal `\n` after `DRAWING = """` and shifted the
    whole block a row: use the Write/Edit tools or byte-safe Python for drawings.
  - Command: EVA 7 wide on top, 8 below; tech storage 4 wide + secure tech (fill 0.857 = accepted); stock floors
    (`stock_floor`: dark striped strips under suits/racks, bot boxes, neutral trim).
  - Engineering: grav gen foyer 4x3 with a window into the chamber (fill 0.76); shared storage; atmos maint corner room
    off the port run (fill 0.757); a hall window into shared storage.
  - Science: R&D beside the foyer with an L from the foyer's top rows (fill 0.75), dark zones under its closets and
    tables, a third light; the post on the research street, its cell behind.
  - Civic: law office door at the west end, 3 panes (glass 0.16), extinguisher and poster by the door; layout's back door
    may move a hung piece off its wall.

**Proof:**
- Gate on `station_v6`: PASS, 0 of 27 checks failed, 0 regressions; disc: no room reads generated.
- Boot (`run_zone_check.sh station_v6`): 0 runtimes; both docks can dock; the 2 known open ends (toxins incinerator); the
  3 atmos chamber siphons reported off-network (the known false alarm); 50 bins, all on trunks. Telecomms control got its
  APC back (fit_in over furniture only when no bare face is left). Engineering's lights read 0 in that boot: the
  "Tired wiring" station look rolled engineering (round 06.00 game.log), not the map.
- Bot Shift 15 min: 106/106 APCs, SMES 66% -> 96%, crystal 100% 1455-1596 MeV, 3/3 emitters, all 16 aboard evac at 12:58.
  FAIL only the janitor's mopping (as in the committed build); the Atmospherics room flag as before. The atmos tech stood
  2 min in the science server room and gave up refill_internals 9 times (holding a backpack firefighter tank): bot AI.

**Open (not gate items):**
- Atmos main floor: still mostly bare; the stock mixing loop is the next room job.
- Scrubbers left unreachable: 102,37 (as before), 111,33 and 145,70 (new; boot check below).
- Tech-storage rack row and the meeting room are plain; the R&D L and the shared storage want a reviewer's eye.
- Accepted baseline is still the pushed 46a3a40f build: re-accept only when the user says so.

### Iteration 5 (same day): the user's crop faults, solars, atmos works (UNCOMMITTED)

Each fault the user found by eye now has a gate check, measured on the stock maps by `forge/walk.py`:

| fault (the user's crop) | cause | fix | gate check |
|---|---|---|---|
| dead end to the SW solars | the plan's catwalks met maint corner to corner (SW, NW, SE): three arrays cut off since the canvas | stock solar rooms (below); `plan/station_plan.py` CATWALKS now overlap the maint | solars reached (stock 0 cut off), dead ends (stock max 5 long, 2.93 per 1k) |
| other dead ends | maint stubs | `open_dead_ends`: a maint door near each stub's end onto a hall or maint straight across | dead ends |
| huge empty maint rooms | open fields | `v6_rooms.carve_open_maint` (iteration 4) | open maint (stock max 0.146) |
| atmos only via maint, outlet gone | arterial conversion | iteration 4 | ways in (maint-only only where a stock map has the room so), disposals outlet (stock max 36 tiles from waste) |
| two walls meeting corner to corner | corridor clearing, old canvas | `close_corners` after docks | hull corners (stock 0) |
| vending machine across the path | the zig-zag solar join | gone with the solar rooms | corridors clear (ratchet vs accepted; stock maps block maint with junk) |
| a kitchen entered only over a counter | copied stock maint room | `fill_maint` takes back a copy whose bare floor isn't all reached from its doors | corridors clear |
| vents stacked / side by side | - | - | vents apart: none on one tile, no same-kind pair outside the supermatter (stock: 2-4 vent pairs a map) |
| vent on a power terminal | air pass | vents move off terminals | vents off terminals (0) |
| SMES in the walkway | first solar room design | SMES in the room's back corner on the wall | (layout rule) |

**Solars as the stock maps build them** (`solars()`): the old walled run goes back to space (a tile beside station floor
stays wall); a solar maint room 3-4 x 3-4 against the hull (`_solar_room` searches within 5 tiles of the old run): door
straight into station maint, cycling external airlock pair on another side, an open catwalk over space to the array.
Inside: the array's cable from the entry along the wall to the terminal, the SMES in the back corner, the control
console beside the entry, APC and light. Areas `/area/solar/<port|starboard>/<fore|aft>` and the same under
`/area/maintenance/solars`. `power()` keeps the arrays' nets (SOLAR_NET) and fences the grid a tile off them, so the
arrays charge their SMES and the SMES feed the grid; checked by script: each net reaches its terminal and console, not
the grid; each SMES on the grid.

**Atmos works** (`atmos_works()` in chambers(), the old air mix and waste bank are the fallback): waste on layer 2
(Waste In pump, plasma/CO2/N2/O2 filters, each catch down into its tank, a Port to Waste dump, out to the outlet); the
air mix on layer 3 through layer manifolds (N2 cyan, O2 green, airmix, grey into the air tank); main floor: refinery
(layer 3: feed pump, 4 filters into 4 canisters, remainder canister), mixing bench (layer 3: 2 ports, 2 pumps, mixer,
out pump, port), thermal loop (layer 2: freezer, heater, valved port). Meters on every line. The old fault (station
scrubbers plain-piped into the waste row) is gone: atmos faults back to the 3 known toxins ends.

**Renderer:** `forge/atmos.render_prep` draws the stubs the game adds at runtime (pipe_intact toward a joined node in its
colour, pipe_exposed toward nothing, layer 1/3 shift), and none for level-1 devices (vents, scrubbers, injectors) on
intact floor, as components_base.dm does.

**Later the same day:** "pipes stay seen" (forge/atmos.hidden_breaks: a visible line into a pipe hidden under floor;
stock 14-21, the ruling 0): visible layer manifolds, and `unhide_breaks` after the router turns such hidden station
pipes visible up to a wall, plating or door (a door tile counts as a threshold). "apc areas": copied stock rooms
brought "Mime's Office APC" (areastring /area/hippie/mime, not on this map: 3 roundstart stack traces the boot's
runtime count missed); copies now drop the APC's name and areastring.

**Proof:**
- Real `station_v6` build: gate PASS, 0 of 40 checks failed, 0 regressions.
- Boot (`run_zone_check.sh`, before the last two fixes): 0 runtimes; pipes only the 2 known incinerator ends and the 3
  known chamber-siphon false alarms; grid powernet holds 7 SMES (3 engine + 4 solar rooms); all docks can dock.
- In-game screenshot (testkit server on preview_station_v6) vs the renderer: stubs, layer shifts, meters and plain
  floor vents match (data/previews/mapforge/gate0/atmos_ingame_vs_render.png).
- Bot Shift 15 min: 116/116 APCs, SMES 35% -> 50%, crystal 100% ~1555 MeV, 3/3 emitters, solar arrays tracking (3 of
  4 set by the engineers), atmos air loop set, evac boarded. FAIL only the janitor's mopping (known bot AI).

**Open:** scrubbers left out as unreachable at 102,37, 111,33 and 145,70 (as in iteration 4); the canvas still has
the old diagonal catwalk joints (the plan is fixed; `_clear_corridor` removes them at build).

## What v6_station.py does, in order

1. **assemble**: canvas_v6.dmm, then every tile a department build changed.
2. **maint rooms**: the plan's 8 maint rooms become abandoned rooms (theatre bar, tool storage, gambling den, garden,
   library, research lab, emergency storage, clinic). Each is walled on its own edge, with maint doors onto the runs
   round it. Big ones are split by an inner wall and door, and furniture sits in loose clusters.
3. **solars**: four corner arrays open to space: panels, catwalk rows, a tracker, a control console beside the way in.
   Each has a cycling airlock at the field end and a solar-maint corridor.
4. **docks**: evac dock (Birdboat port `emergency_home`, docking arm if a neighbour's hull is in the way); arrivals
   side-on (donut template) via station/to_dmm.side_dock.
5. **layout**:
   - maint back doors into rooms with one or two ways in, using that room's own access;
   - table islands in big offices only.
6. **glaze**: hull windows (three panes in four; maint hull lighter) and hall windows into public rooms. Never cut into
   NO_GLASS rooms or Engineering.
7. **shared**: the canvas halls, maint and maint rooms get an APC, an air alarm, lights and vents.
8. **polish**:
   - to_dmm's firelocks, signs, one piece per wall face and maint dressing, on the shared zone;
   - hall trim, with department colour by its doors;
   - door-front paint.
9. **plazas**: benches, plants and vending along the walls of open hall.
10. **details**:
    - items on tables (not work tables, not the kitchen or bar);
    - items in plain closets, crates and racks;
    - litter and grime only in LITTER_AREAS;
    - spare starts for SPARE_JOBS;
    - hall cameras.
11. **fixtures**: an intercom in each crew room of 15+ tiles without one, newscasters in public rooms, posters.
12. **power**, three nets (the game never links the cable under an SMES to its terminal's, cable.dm):
    - grid: SMES tiles -> every APC, the emitter net, the generators and the solar arrays;
    - input: the terminals -> the rad-collector ring, on cable layer 1 with cable bridges at both ends;
    - AI sat: its SMES -> its APCs, on layer 1 with bridges.
13. **air**:
    - Gas chambers: tg presets for sensor, siphon (`<gas>_output`), injector (`<gas>_input`) and tank console.
    - Air mix: the N2 and O2 outputs feed an airmix mixer, which feeds the air injector.
    - Distro: the air siphon feeds the "Air to Distro" pump (layer 1, 4500 kPa), which is the supply root.
    - Waste: scrubbers run through a plasma filter (its catch goes to a connector), then an outlet past the hull.
    - The supermatter block's own pipes are kept. Its waste end is tapped at 131,71.
    - Every sealed room gets a vent.
    - Station pipes never cross a gas tank or its wall.
14. **bins + disposals**:
    - A bin goes in each bigger crew room without one.
    - One tree runs from every bin to a mass-driver exit at the hull.
    - The first trunk tiles stay straight, and a wrap sorting junction there sends parcels to a delivery chute in cargo
      sorting.

## How to check it

- **Pipes, cable and disposals:** `python tools/mapforge/studies/net_view.py station_v6 --scale 6 [--box x1 y1 x2 y2]`
  draws them.
- **Power:** `python tools/mapforge/studies/power_nets.py station_v6` lists the power nets by the game's cable rules
  (layers, bridges, SMES/terminal).
- **Tiles:** `python tools/mapforge/studies/tile_dump.py station_v6 x1 y1 x2 y2 [--ascii]`
- **Wall pieces:** `python tools/mapforge/studies/piece_audit.py station_v6` finds pieces over furniture, stacked, or on
  both faces of a wall.
- **Headless boot:** `EMERGENCY=emergency_birdboat bash tools/mapforge/run_zone_check.sh station_v6 15,15,195,160`
  (after `python tools/gpu_share.py wait`). It reports mains, air, open pipe ends, vents and bins, and now the docks:
  can the shuttle dock.
- **Bot Shift:** `MAP=../data/mapforge/preview_station_v6 EVAC=1 SPEED=10 bash tools/bot_gym/run_bot_shift.sh 15`.
  Its Power line reads the crystal, and the evac drill shows who boarded.
- **Stock-map measures:**
  - `python tools/mapforge/forge/fingerprint.py --fresh data/mapforge/station_v6.dmm`
  - `python tools/mapforge/forge/disc.py heat data/mapforge/disc/v6 data/mapforge/gen_v6/station_v6.dmm` (copy the
    build into data/mapforge/gen_v6/ first).

## Results at the pause

- **Boot:**
  - 2 open pipe ends, both the toxins incinerator.
  - 386 vents on networks; 46 bins on trunks.
  - Both docks can dock.
  - 0 runtimes.
- **Bot Shift (15 min):**
  - Crystal 100%, 1550-1630 MeV, 3/3 emitters.
  - SMES 59% -> 96%; all 94 APCs on.
  - All 16 bots aboard evac.
- **Fingerprint:** 15 of 38 features outside the human range (23 at the start of the night). Left: hall share 0.22
  (max 0.21), maint share 0.13 (min 0.14), depth, department fill and corners, room size and odd shapes, room fill,
  wall per floor, inner glass, doubled walls, struct3.
- **Discriminator v6** (retrained with v6 held out): 12% of tiles called generated (other generated maps 100%).
- **Reviews** (data/mapforge/reviews, local only):
  - 8.5: Medical.
  - 8: Science, Cargo, Service, Dorms, Civic, Command, AI sat, Engineering.
  - 7: Security.

## Open

- **Security:** HoS carpet, court spacing, infirmary IV in front of the sleeper.
- **Science:**
  - pens 3x3 (corridor to 2 rows, pens y31-33);
  - server APC out of the chamber;
  - toxins corridor and shower;
  - the tail's space column (needs a plan change).
- **Service:** hydro tray rows; kitchen microwaves off the bar door landing; theatre backstage window.
- **Engineering:** a way to fill N2/O2 canisters (valve + connector branches beside the mixer lines).
- **Civic:** department signs at the chapel and library doors; gallery display cases.
- **Command:** HoP queue stripes and sign; securearea signs by the bridge doors.
- **Port Solar Maintenance** reads 0 kPa after the engineer bots go out to the solars; the cause isn't found yet.
- **Structural fingerprint gaps:** need plan and department-shape work, not more passes.
- **In-game use:** a `_maps/station_v6.json` entry, so the map can be picked and played.
