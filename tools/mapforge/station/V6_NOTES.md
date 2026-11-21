# station_v6: where it stands (paused 2026-11-22)

The v6 station is the hand-drawn plan (plan/station_plan.py, plan/canvas.py) with all ten departments drawn tile by
tile (blueprints/*_v6.py + assets/*_v6.py), laid into one map by `station/v6_station.py`, which then adds everything
the departments share.

```
python tools/mapforge/mapforge.py build blueprints/<dept>_v6.py     # one department -> data/mapforge/<dept>_v6.dmm
python tools/mapforge/station/v6_station.py [--no-render] [--name trial]   # all of them -> data/mapforge/station_v6.dmm
```

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
