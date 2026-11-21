"""The v6 station in one map: the plan canvas with all ten hand-drawn departments laid in, then the station-wide
networks every department review was waiting on.

    python tools/mapforge/station/v6_station.py                 # data/mapforge/station_v6.dmm + a picture
    python tools/mapforge/station/v6_station.py --no-render

Steps:
  1. assemble   canvas_v6.dmm, then every tile a department build changed (data/mapforge/<dept>_v6.dmm)
  2. shared     the canvas halls and maint get what the department builds never gave them: an APC and an air
                alarm per area, lights along the walls, vents (halls: a vent and scrubber pair per ~60 tiles;
                maint corridors a vent per ~90, no scrubbers, as the stock maps do)
  3. power      the SMES in Engineering gets its terminals; every station cable is taken up and laid again as one
                grid from the SMES to every APC (the supermatter block's own cables are kept and joined)
  4. air        every supply and scrubber pipe is taken up (the department builds left stubs that ended at their zone
                edge) and laid again as two trees: supply from an air tank in Atmospherics to every vent, scrubbers
                from every scrubber to a waste tank beside it (stand-ins until the atmos machinery island)

The trees grow from their root with one search that carries on as branches join (station/to_dmm.StationBuilder's
forest), so the pipes share runs instead of each vent finding its own way home.
"""
import argparse
import heapq
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit, atmos  # noqa: E402
from forge.kit import CARD, DELTA, OPP  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
DATA = os.path.join(ROOT, "data", "mapforge")
DEPTS = ["medical", "science", "security", "cargo", "service", "dorms", "civic", "command", "ai", "engineering"]
SHARED = ("/area/hallway", "/area/maintenance")

# Engineering (map tiles): the SMES row and where its terminals go, the atmos room's tanks
SMES_TILES = [(141, 78), (142, 78), (143, 78)]
# the block's own run from Engine Control's APC to the collector ring: the APC goes on the station grid instead, or the
# grid and the SMES input would be one net through it
ENGINE_UNWIRE = set()     # none: Engine Control's APC rides the emitter net, which the grid feeds
TANKS = {"supply": ((117, 50), 8), "scrubbers": ((117, 48), 8)}     # tank tile, the side its pipe leaves by


def nb(p, d):
    return (p[0] + DELTA[d][0], p[1] + DELTA[d][1])


def key(t):
    return (t.tpath, t.apath, tuple((o.path, tuple(o.vars)) for o in t.objs))


# ================================================================================================= 1. assemble
def assemble(log):
    base = dmm.read(os.path.join(DATA, "canvas_v6.dmm"))
    m = dmm.read(os.path.join(DATA, "canvas_v6.dmm"))
    owner = {}
    for d in DEPTS:
        md = dmm.read(os.path.join(DATA, "%s_v6.dmm" % d))
        n = clash = 0
        for (x, y, z), t in md.tiles.items():
            b = base.get(x, y, z)
            if b is not None and key(b) == key(t):
                continue
            if (x, y) in owner:
                clash += 1
                # two builds touched one tile (a stub trimmed outside a zone): the department whose area it is wins
                if not t.apath.startswith(("/area/hallway", "/area/maintenance", "/area/space")):
                    m.set(x, y, t)
                    owner[(x, y)] = d
                continue
            m.set(x, y, t)
            owner[(x, y)] = d
            n += 1
        log("assemble: %-12s %5d tiles%s" % (d, n, (", %d clashes" % clash) if clash else ""))
    return m, owner


# ================================================================================================= helpers
def is_floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")


def is_window(t):
    return t is not None and (t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/window")
                              or t.has("/obj/structure/grille"))


def solid(t):
    return t is None or t.tpath.startswith("/turf/closed") or is_window(t)


def area_floors(m):
    out = {}
    for (x, y, z), t in m.tiles.items():
        if is_floor(t) and not is_window(t):
            out.setdefault(t.apath, []).append((x, y))
    return out


def faces_of(m, tiles):
    """(floor tile, side) where the side is a plain wall a piece can hang on."""
    out = []
    for p in tiles:
        t = m.get(*p)
        if t.has("/obj/machinery/door"):
            continue
        for d in CARD:
            q = m.get(*nb(p, d))
            if q is not None and q.tpath.startswith("/turf/closed") and not q.has("/obj/machinery/door"):
                out.append((p, d))
    return out


def hung(m, p):
    t = m.get(*p)
    return any(abs(o.num("pixel_x")) >= 20 or abs(o.num("pixel_y")) >= 20 or o.path.startswith(
        ("/obj/machinery/light", "/obj/machinery/camera")) for o in t.objs)


def mount(m, p, d, kind, extra=()):
    dd, px, py = kit.MOUNT[kind][d]
    vs = []
    if dd is not None:
        vs.append(("dir", str(dd)))
    if px is not None:
        vs.append(("pixel_x", str(px)))
    if py is not None:
        vs.append(("pixel_y", str(py)))
    m.get(*p).objs.append(dmm.Atom(kit.MOUNT_PATHS[kind], vs + list(extra)))


# ================================================================================================= maint rooms
# the plan's maint rooms (plan/station_plan.py MAINT_ROOMS, map tiles): "the abandoned or odd rooms that signpost each
# maint stretch". The canvas left them open plating merged with the maint runs; each is walled off on its own edge,
# given maint doors onto the runs round it and one of tg's abandoned areas (the user's pick 2026-11-21: abandoned rooms)
J = "/obj/item/reagent_containers/food/drinks/bottle/"
MAINT_ROOMS = [
    ((44, 120, 58, 131), "Abandoned Theatre", "/area/crew_quarters/theatre/abandoned", "/turf/open/floor/wood", dict(
        wall=[["/obj/structure/table/wood", J + "whiskey"], ["/obj/structure/table/wood", J + "vodka"],
              ["/obj/structure/table/wood", J + "rum", "/obj/item/reagent_containers/food/drinks/drinkingglass"],
              ["/obj/structure/table/wood", "/obj/item/reagent_containers/food/drinks/shaker"], ["/obj/structure/piano"],
              ["/obj/structure/closet/crate/bin"], ["/obj/machinery/vending/boozeomat/all_access"]],
        island="table", scatter=["/obj/effect/decal/cleanable/dirt", "/obj/item/cigbutt", "/obj/effect/decal/cleanable/vomit/old"])),
    ((61, 120, 73, 131), "Auxiliary Tool Storage", "/area/storage/tools", "/turf/open/floor/plasteel", dict(
        wall=[["/obj/machinery/vending/tool"], ["/obj/machinery/vending/assist"], ["/obj/structure/closet/toolcloset"],
              ["/obj/structure/closet/toolcloset"], ["/obj/structure/reagent_dispensers/fueltank"],
              ["/obj/structure/reagent_dispensers/watertank"],
              ["/obj/structure/rack", "/obj/item/storage/toolbox/mechanical", "/obj/item/storage/toolbox/electrical"],
              ["/obj/structure/table", "/obj/item/stack/cable_coil", "/obj/item/stack/cable_coil", "/obj/item/t_scanner"],
              ["/obj/structure/table", "/obj/item/clothing/gloves/color/fyellow", "/obj/item/flashlight"]],
        island=None, scatter=["/obj/effect/decal/cleanable/dirt"])),
    ((97, 55, 106, 62), "Abandoned Gambling Den", "/area/crew_quarters/abandoned_gambling_den", "/turf/open/floor/carpet", dict(
        wall=[["/obj/machinery/computer/slot_machine"], ["/obj/machinery/computer/slot_machine"],
              ["/obj/structure/table/wood", J + "whiskey", "/obj/item/reagent_containers/food/drinks/drinkingglass"],
              ["/obj/structure/closet/crate/bin"]],
        island="poker", scatter=["/obj/item/cigbutt", "/obj/effect/decal/cleanable/dirt", "/obj/item/coin/iron"])),
    ((38, 60, 49, 78), "Abandoned Garden", "/area/hydroponics/garden/abandoned", "/turf/open/floor/grass", dict(
        wall=[["/obj/structure/reagent_dispensers/watertank"], ["/obj/structure/closet/crate/hydroponics"],
              ["/obj/structure/table", "/obj/item/cultivator", "/obj/item/reagent_containers/glass/bucket", "/obj/item/hatchet"],
              ["/obj/item/twohanded/required/kirbyplants/random"], ["/obj/item/twohanded/required/kirbyplants/random"]],
        island="soil", scatter=["/obj/effect/decal/cleanable/dirt"])),
    ((52, 60, 59, 78), "Abandoned Library", "/area/library/abandoned", "/turf/open/floor/wood", dict(
        wall=[["/obj/structure/bookcase/random"]] * 8 + [["/obj/structure/table/wood", "/obj/item/paper_bin", "/obj/item/pen"]],
        island="reading", scatter=["/obj/effect/decal/cleanable/dirt", "/obj/item/paper"])),
    ((38, 40, 50, 55), "Abandoned Research Lab", "/area/science/research/abandoned", "/turf/open/floor/plasteel/white", dict(
        wall=[["/obj/structure/table", "/obj/item/reagent_containers/glass/beaker", "/obj/item/stock_parts/cell"],
              ["/obj/structure/table", "/obj/item/stock_parts/manipulator", "/obj/item/stock_parts/micro_laser"],
              ["/obj/structure/closet/crate/science"], ["/obj/structure/girder"], ["/obj/structure/rack",
              "/obj/item/stack/sheet/glass", "/obj/item/stack/sheet/metal"], ["/obj/structure/closet/l3closet/scientist"],
              ["/obj/structure/table", "/obj/item/clipboard", "/obj/item/paper"], ["/obj/structure/girder"]],
        island="lab", scatter=["/obj/item/shard", "/obj/effect/decal/cleanable/dirt", "/obj/effect/decal/cleanable/oil"])),
    ((114, 35, 118, 39), "Emergency Storage", "/area/storage/emergency/starboard", "/turf/open/floor/plasteel", dict(
        wall=[["/obj/structure/closet/emcloset"], ["/obj/structure/closet/firecloset"],
              ["/obj/machinery/portable_atmospherics/canister/air"],
              ["/obj/structure/rack", "/obj/item/tank/internals/oxygen", "/obj/item/clothing/mask/gas"]],
        island=None, scatter=[])),
    ((62, 58, 67, 65), "Abandoned Clinic", "/area/medical/abandoned", "/turf/open/floor/plasteel/white", dict(
        wall=[["/obj/structure/bed", "/obj/item/bedsheet/medical"], ["/obj/machinery/iv_drip"],
              ["/obj/structure/table", "/obj/item/storage/firstaid/regular", "/obj/item/healthanalyzer"],
              ["/obj/structure/closet/crate/medical"], ["/obj/structure/bed/roller"]],
        island=None, scatter=["/obj/effect/decal/cleanable/blood/old", "/obj/effect/decal/cleanable/dirt"])),
]


def maint_rooms(m, log):
    import random
    rnd = random.Random(21)
    for (x0, y0, x1, y1), name, area, floor, th in MAINT_ROOMS:
        rect = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
        mine = {p for p in rect if is_floor(m.get(*p)) and m.get(*p).apath.startswith("/area/maintenance")}
        if len(mine) < 0.8 * len(rect):
            log("maint room %s: only %d of %d tiles are maint floor, skipped" % (name, len(mine), len(rect)))
            continue
        edge = {p for p in rect if p[0] in (x0, x1) or p[1] in (y0, y1)}
        inner = rect - edge
        # doors: the middle of each side that faces a maint run, at most two
        sides = []
        for d, run in ((1, [(x, y1) for x in range(x0 + 1, x1)]), (2, [(x, y0) for x in range(x0 + 1, x1)]),
                       (4, [(x1, y) for y in range(y0 + 1, y1)]), (8, [(x0, y) for y in range(y0 + 1, y1)])):
            ok = [p for p in run if is_floor(m.get(*nb(p, d))) and m.get(*nb(p, d)).apath.startswith("/area/maintenance")
                  and nb(p, d) not in rect]
            if ok:
                mid = ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
                sides.append((len(ok), min(ok, key=lambda p: (abs(p[0] - mid[0]) + abs(p[1] - mid[1]), p)), d))
        doors = [p for _, p, _ in sorted(sides, key=lambda s: -s[0])[:2]]
        for p in edge:
            t = m.get(*p)
            if p in doors:
                m.set(p[0], p[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance", [("name", '"%s"' % name)])],
                                           dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
            elif p in mine:
                m.set(p[0], p[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area)))
        for p in inner:
            if p in mine:
                # worn patches of bare plating, in clumps (stock abandoned rooms are never one clean floor)
                bare = rnd.random() < 0.12 or any(nb(p, d) in inner and m.get(*nb(p, d)).tpath == "/turf/open/floor/plating"
                                                  for d in (2, 8)) and rnd.random() < 0.45
                m.set(p[0], p[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plating" if bare else floor), dmm.Atom(area)))
        keep = {q for p in doors for q in (nb(p, d) for d in CARD) if q in inner}
        # a big room is split: an inner wall across it at 40-60% with a door, and a big half split again the other
        # way (fingerprint: rooms too big and too square; disc: one grid of islands in a box reads generated)
        parts = set()
        w_, h_ = x1 - x0 - 1, y1 - y0 - 1
        if w_ >= 10:
            sx = x0 + 1 + rnd.randint(int(w_ * 0.4), int(w_ * 0.6))
            col = [(sx, y) for y in range(y0 + 1, y1) if (sx, y) in mine]
            dr = rnd.choice(col[1:-1]) if len(col) > 2 else None
            for q in col:
                if q == dr:
                    m.set(q[0], q[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock", [("name", '"%s"' % name)])],
                                               dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
                    keep |= {nb(q, 4), nb(q, 8)}
                else:
                    m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area)))
                parts.add(q)
            if h_ >= 9:
                lo, hi = (x0 + 1, sx - 1) if rnd.random() < 0.5 else (sx + 1, x1 - 1)
                sy = y0 + 1 + rnd.randint(int(h_ * 0.4), int(h_ * 0.6))
                row = [(x, sy) for x in range(lo, hi + 1) if (x, sy) in mine and (x, sy) not in keep]
                if len(row) > 3:
                    dr2 = rnd.choice(row[1:-1])
                    for q in row:
                        if q == dr2:
                            m.set(q[0], q[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock", [("name", '"%s"' % name)])],
                                                       dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
                            keep |= {nb(q, 1), nb(q, 2)}
                        else:
                            m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area)))
                        parts.add(q)
        elif h_ >= 12:
            sy = y0 + 1 + rnd.randint(int(h_ * 0.4), int(h_ * 0.6))
            row = [(x, sy) for x in range(x0 + 1, x1) if (x, sy) in mine]
            dr = rnd.choice(row[1:-1]) if len(row) > 2 else None
            for q in row:
                if q == dr:
                    m.set(q[0], q[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock", [("name", '"%s"' % name)])],
                                               dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
                    keep |= {nb(q, 1), nb(q, 2)}
                else:
                    m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area)))
                parts.add(q)
        inner = inner - parts
        edge = edge | parts
        ring = sorted((p for p in inner if any(nb(p, d) in edge for d in CARD) and p not in keep),
                      key=lambda p: (math.atan2(p[1] - (y0 + y1) / 2.0, p[0] - (x0 + x1) / 2.0)))
        # wall pieces round the walls, spaced, a tile left clear beside each door
        k = 0
        used = set()
        step_ = max(1, len(ring) // max(1, len(th["wall"]) * 2))
        for i in range(0, len(ring), step_):
            if k >= len(th["wall"]) * 2:
                break
            p = ring[i]
            if p in used or any(abs(p[0] - q[0]) + abs(p[1] - q[1]) <= 1 for q in keep):
                continue
            objs = th["wall"][k % len(th["wall"])]
            m.get(*p).objs += [dmm.Atom(o) for o in objs]
            used.add(p)
            k += 1
        # islands in the middle, every third tile both ways so a path always runs between them
        core = [p for p in inner if p not in ring and p not in keep and not any(nb(p, d) in edge for d in CARD)]
        isl = th.get("island")
        # islands in loose clusters, each with a clear tile all round it (not a grid)
        spots = []
        for p in sorted(core, key=lambda q: rnd.random()):
            if len(spots) >= max(1, len(core) // 10):
                break
            if all(max(abs(p[0] - q[0]), abs(p[1] - q[1])) >= 3 for q in spots):
                spots.append(p)
        for p in spots:
            if isl:
                t = m.get(*p)
                if isl == "soil":
                    t.objs.append(dmm.Atom("/obj/machinery/hydroponics/soil"))
                elif isl == "poker":
                    t.objs += [dmm.Atom("/obj/structure/table/wood/poker"), dmm.Atom("/obj/item/toy/cards/deck")]
                    for d, cd in ((4, 8), (8, 4)):
                        q = nb(p, d)
                        if q in core:
                            m.get(*q).objs.append(dmm.Atom("/obj/structure/chair/wood", [("dir", str(cd))]))
                elif isl in ("table", "reading", "lab"):
                    t.objs.append(dmm.Atom("/obj/structure/table/wood" if isl != "lab" else "/obj/structure/table"))
                    if isl == "reading":
                        t.objs.append(dmm.Atom("/obj/item/book/random") if False else dmm.Atom("/obj/item/paper"))
                    q = nb(p, 2)
                    if q in core and isl != "lab":
                        m.get(*q).objs.append(dmm.Atom("/obj/structure/chair/stool/bar" if isl == "table"
                                                       else "/obj/structure/chair/wood", [("dir", "1")]))
        for p in inner:
            if th["scatter"] and rnd.random() < 0.12 and p not in keep:
                m.get(*p).objs.append(dmm.Atom(rnd.choice(th["scatter"])))
        log("maint room: %-24s %2dx%-2d %d doors, %d wall pieces" % (name, x1 - x0 + 1, y1 - y0 + 1, len(doors), k))
    return [a for _, _, a, _, _ in MAINT_ROOMS]


# ================================================================================================= details
# what sits about in a lived-in station (fingerprint 2026-11-21: items 0.08 per floor tile against humans' 0.15-0.26,
# grime 0.012 against 0.017-0.18, one job start per 142 floor tiles against 39-129, cameras 1.8 per 100 against 2.0-3.1)
TABLE_ITEMS = (
    ("/area/medical", ["/obj/item/reagent_containers/syringe", "/obj/item/healthanalyzer", "/obj/item/reagent_containers/glass/bottle/epinephrine",
                       "/obj/item/stack/medical/gauze", "/obj/item/clipboard", "/obj/item/pen"]),
    ("/area/science", ["/obj/item/stock_parts/cell", "/obj/item/stock_parts/manipulator", "/obj/item/reagent_containers/glass/beaker",
                       "/obj/item/paper", "/obj/item/pen", "/obj/item/multitool"]),
    ("/area/security", ["/obj/item/restraints/handcuffs", "/obj/item/paper", "/obj/item/pen", "/obj/item/folder/red",
                        "/obj/item/radio", "/obj/item/flashlight/seclite"]),
    ("/area/engine", ["/obj/item/stack/cable_coil", "/obj/item/wrench", "/obj/item/screwdriver", "/obj/item/t_scanner",
                      "/obj/item/clothing/gloves/color/yellow", "/obj/item/analyzer"]),
    ("/area/quartermaster", ["/obj/item/paper", "/obj/item/pen", "/obj/item/clipboard", "/obj/item/stack/packageWrap",
                             "/obj/item/destTagger", "/obj/item/stamp/qm"]),
    ("/area/hydroponics", ["/obj/item/reagent_containers/glass/bucket", "/obj/item/cultivator", "/obj/item/plant_analyzer",
                           "/obj/item/seeds/wheat", "/obj/item/seeds/tomato"]),
    ("/area/crew_quarters/kitchen", ["/obj/item/kitchen/knife", "/obj/item/kitchen/rollingpin",
                                     "/obj/item/reagent_containers/food/condiment/saltshaker", "/obj/item/reagent_containers/food/condiment/peppermill"]),
    ("/area/crew_quarters/bar", ["/obj/item/reagent_containers/food/drinks/drinkingglass", "/obj/item/reagent_containers/food/drinks/shaker",
                                 "/obj/item/reagent_containers/food/condiment/saltshaker"]),
    ("/area", ["/obj/item/paper", "/obj/item/pen", "/obj/item/folder", "/obj/item/clipboard",
               "/obj/item/reagent_containers/food/drinks/coffee", "/obj/item/flashlight/lamp"]),
)
# litter and grime in the halls, maint, the abandoned rooms and the cargo bay: departments stay clean (Medical review 4)
CLOSET_ITEMS = ["/obj/item/clothing/suit/hazardvest", "/obj/item/flashlight", "/obj/item/storage/box", "/obj/item/clothing/gloves/color/black",
                "/obj/item/clothing/mask/breath", "/obj/item/tank/internals/emergency_oxygen", "/obj/item/clothing/head/hardhat",
                "/obj/item/stack/sheet/cloth", "/obj/item/clothing/shoes/sneakers/black", "/obj/item/storage/toolbox/emergency"]
LITTER_AREAS = ("/area/hallway", "/area/maintenance", "/area/quartermaster/storage", "/area/crew_quarters/abandoned_gambling_den",
                "/area/crew_quarters/theatre/abandoned", "/area/hydroponics/garden/abandoned", "/area/library/abandoned",
                "/area/science/research/abandoned", "/area/medical/abandoned", "/area/storage")
FLOOR_LITTER = ["/obj/item/paper", "/obj/item/cigbutt", "/obj/item/trash/candy", "/obj/item/trash/chips", "/obj/item/pen",
                "/obj/item/stack/cable_coil/cut", "/obj/item/crowbar/red", "/obj/item/trash/can"]


SPARE_JOBS = ("station_engineer", "medical_doctor", "scientist", "security_officer", "cargo_technician", "shaft_miner",
              "botanist", "atmospheric_technician", "roboticist", "chemist", "geneticist", "virologist", "janitor", "cook")


def details(m, log):
    import random
    rnd = random.Random(1121)
    added = {"items": 0, "grime": 0, "starts": 0, "cameras": 0}
    floors = [(x, y) for (x, y, z), t in m.tiles.items() if is_floor(t) and not is_window(t)
              and not t.apath.startswith(("/area/space", "/area/solar", "/area/shuttle"))]
    for p in floors:
        t = m.get(*p)
        if t.has("/obj/machinery/door"):
            continue
        tables = t.has("/obj/structure/table")
        items = sum(1 for o in t.objs if o.path.startswith("/obj/item"))
        if tables and items == 0 and not t.has("/obj/machinery") and \
                not t.apath.startswith(("/area/crew_quarters/kitchen", "/area/crew_quarters/bar")):
            pool = next(pl for pre, pl in TABLE_ITEMS if t.apath.startswith(pre))
            for o in rnd.sample(pool, rnd.choice((1, 2, 2))):
                t.objs.append(dmm.Atom(o, [("pixel_x", str(rnd.randint(-6, 6))), ("pixel_y", str(rnd.randint(-4, 6)))]))
                added["items"] += 1
        elif not kit.dense(t.objs) and t.apath.startswith(LITTER_AREAS) and not t.objs:
            r = rnd.random()
            maint = t.apath.startswith("/area/maintenance")
            # nothing dropped in a one-tile corridor (the AI sat bridge): walls on both sides
            if (solid(m.get(*nb(p, 1))) and solid(m.get(*nb(p, 2)))) or (solid(m.get(*nb(p, 4))) and solid(m.get(*nb(p, 8)))):
                continue
            if r < (0.06 if maint else 0.045):
                t.objs.append(dmm.Atom(rnd.choice(FLOOR_LITTER)))
                added["items"] += 1
            elif r < (0.15 if maint else 0.065):
                t.objs.insert(0, dmm.Atom("/obj/effect/decal/cleanable/dirt"))
                added["grime"] += 1
    # closets, crates and racks with nothing in them get a thing or two: mapped items on a closet's tile start inside it,
    # as the stock maps stock theirs (fingerprint: loose items 0.09 per floor tile against humans' 0.15-0.26 once litter
    # left the departments)
    for p in floors:
        t = m.get(*p)
        if not (t.has("/obj/structure/closet") or t.has("/obj/structure/rack")) or any(o.path.startswith("/obj/item") for o in t.objs):
            continue
        if not (any(o.path in ("/obj/structure/closet", "/obj/structure/closet/crate")
                    for o in t.objs) or t.has("/obj/structure/rack")):
            continue        # a specialist closet (suits, bombs, fire, emergency, a secure locker) spawns its own kit
        pool = CLOSET_ITEMS if t.has("/obj/structure/closet") else next(pl for pre, pl in TABLE_ITEMS if t.apath.startswith(pre))
        for o in rnd.sample(pool, min(len(pool), rnd.choice((2, 3, 3)))):
            t.objs.append(dmm.Atom(o))
            added["items"] += 1
    # spare job starts: a quarter more of each job, on free floor beside its own (humans place spares)
    starts = {}
    for p in floors:
        for o in m.get(*p).objs:
            if o.path.startswith("/obj/effect/landmark/start/") and o.path.rsplit("/", 1)[-1] in SPARE_JOBS:
                starts.setdefault(o.path, []).append(p)
    taken = {p for ps in starts.values() for p in ps}
    for path, ps in sorted(starts.items()):
        for _ in range(max(1, (len(ps) + 3) // 4)):
            base = ps[0]
            area = m.get(*base).apath
            free = [q for q in floors if m.get(*q).apath == area and q not in taken and not kit.dense(m.get(*q).objs)
                    and not m.get(*q).has("/obj/machinery/door") and abs(q[0] - base[0]) + abs(q[1] - base[1]) <= 6]
            if free:
                q = min(free, key=lambda q: (abs(q[0] - base[0]) + abs(q[1] - base[1]), q))
                m.get(*q).objs.append(dmm.Atom(path))
                taken.add(q)
                added["starts"] += 1
    # hall cameras: one per ~30 hall tiles, spread out, on a free wall face
    halls = {}
    for p in floors:
        a = m.get(*p).apath
        if a.startswith("/area/hallway"):
            halls.setdefault(a, []).append(p)
    for area, tiles in halls.items():
        have = [p for p in tiles if m.get(*p).has("/obj/machinery/camera")]
        want = max(1, round(len(tiles) / 30.0)) - len(have)
        faces = [f for f in faces_of(m, tiles) if not hung(m, f[0]) and not kit.dense(m.get(*f[0]).objs)]
        placed = list(have)
        name = area.rsplit("/", 1)[-1].replace("_", " ").title()
        for i in range(want):
            if not faces:
                break
            f = max(faces, key=lambda f: (min((abs(f[0][0] - q[0]) + abs(f[0][1] - q[1]) for q in placed), default=99), f))
            if placed and min(abs(f[0][0] - q[0]) + abs(f[0][1] - q[1]) for q in placed) < 7:
                break
            cd = {1: 2, 2: 1, 4: 8, 8: 4}[f[1]]
            m.get(*f[0]).objs.append(dmm.Atom("/obj/machinery/camera", [("dir", str(cd)), ("c_tag", '"%s %d"' % (name, i + 1))]))
            placed.append(f[0])
            faces = [g for g in faces if g[0] != f[0]]
            added["cameras"] += 1
    log("details: %(items)d items, %(grime)d grime, %(starts)d spare job starts, %(cameras)d hall cameras" % added)


def regions(m):
    """Enclosed rooms: floor tiles of one area joined without crossing a door or a window. Returns [tiles]."""
    seen, out = set(), []
    for (x, y, z), t in m.tiles.items():
        p = (x, y)
        if p in seen or not is_floor(t) or is_window(t) or t.has("/obj/machinery/door"):
            continue
        a = t.apath
        g, q = {p}, [p]
        seen.add(p)
        while q:
            c = q.pop()
            for d in CARD:
                n = nb(c, d)
                tn = m.get(*n)
                if n in seen or tn is None or tn.apath != a or not is_floor(tn) or is_window(tn) or tn.has("/obj/machinery/door"):
                    continue
                seen.add(n)
                g.add(n)
                q.append(n)
        out.append(g)
    return out


# offices and lounges only: a work floor (chemistry, a lab) has no use for a meeting table (Medical review 4)
ISLAND_AREAS = ("/area/security/main", "/area/security/office", "/area/crew_quarters/heads", "/area/library/abandoned_never",
                "/area/lawoffice", "/area/quartermaster/office", "/area/quartermaster/qm",
                "/area/engine/break_room", "/area/bridge/meeting_room")
BACKDOOR_NOT = ("/area/ai_monitored", "/area/security/armory", "/area/security/prison", "/area/engine/supermatter",
                "/area/crew_quarters/heads/captain", "/area/crew_quarters/dorms", "/area/crew_quarters/toilet",
                "/area/bridge", "/area/security/nuke_storage", "/area/science/mixing/chamber", "/area/solar",
                "/area/maintenance", "/area/hallway", "/area/space", "/area/shuttle", "/area/science/xenobiology",
                "/area/engine/gravity_generator", "/area/tcommsat", "/area/security/execution", "/area/science/explab",
                "/area/science/server", "/area/science/test_area", "/area/science/storage", "/area/security/prison")


def layout(m, log):
    """Back doors and islands (fingerprint: dead-end rooms 0.46 against humans' max 0.45, loops 5 per 1k floor against
    6.2-14; room centres 0.14 full against 0.18-0.33)."""
    import random
    rnd = random.Random(77)
    regs = regions(m)
    doors_added = islands = 0
    for g in regs:
        t0 = m.get(*next(iter(g)))
        a = t0.apath
        if len(g) < 6 or a.startswith(BACKDOOR_NOT):
            continue
        ways = [(p, d) for p in g for d in CARD if m.get(*nb(p, d)) is not None and m.get(*nb(p, d)).has("/obj/machinery/door")]
        if len(ways) not in (1, 2) or (len(ways) == 2 and len(g) < 16):
            continue
        door_t = m.get(*nb(*ways[0]))
        acc = next((o for o in door_t.objs if o.path.startswith("/obj/machinery/door/airlock")), None)
        # a wall between this room and maint floor, not beside a corner, not hung on either face
        opts = []
        for p in g:
            for d in CARD:
                w, beyond = nb(p, d), nb(nb(p, d), d)
                tw, tb = m.get(*w), m.get(*beyond)
                if not (tw and tw.tpath.startswith("/turf/closed/wall") and not tw.objs and tb and is_floor(tb)
                        and tb.apath.startswith("/area/maintenance") and not kit.dense(tb.objs) and not kit.dense(m.get(*p).objs)):
                    continue
                side = [dd for dd in CARD if dd not in (d, OPP[d])]
                if not all(m.get(*nb(w, s)) is not None and m.get(*nb(w, s)).tpath.startswith("/turf/closed") for s in side):
                    continue
                if hung(m, p) or hung(m, beyond):
                    continue
                opts.append((p, w, d))
        if not opts:
            continue
        p, w, d = min(opts, key=lambda o: (-(abs(o[0][0] - ways[0][0][0]) + abs(o[0][1] - ways[0][0][1])), o[1]))
        vs = [("name", '"%s Maintenance"' % (a.rsplit("/", 1)[-1].replace("_", " ").title()))]
        if acc:
            vs += [(k, v) for k, v in acc.vars if k in ("req_access_txt", "req_one_access_txt")]
        m.set(w[0], w[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance", vs), dmm.Atom("/obj/machinery/door/firedoor")],
                                   dmm.Atom("/turf/open/floor/plating"), m.get(*w).area.copy() if m.get(*w).area else dmm.Atom(a)))
        doors_added += 1
    # islands: an empty middle in an office, lab or lounge gets a table with chairs, as the stock rooms have
    for g in regions(m):
        t0 = m.get(*next(iter(g)))
        if len(g) < 20 or not t0.apath.startswith(ISLAND_AREAS) or (len(g) < 40 and any(m.get(*q).has("/obj/structure/table") for q in g)):
            continue        # a room with its own table needs no second one (Command review 5: a second conference table)
        core = [p for p in g if all(nb(p, d) in g and not kit.dense(m.get(*nb(p, d)).objs) and not m.get(*nb(p, d)).has("/obj/machinery/door")
                                    for d in CARD) and not m.get(*p).objs]
        # a 2-tile table whose ring of 8 neighbours is all free floor, so the way round it stays open
        cx = sum(p[0] for p in g) / len(g)
        cy = sum(p[1] for p in g) / len(g)
        best = None
        cs = set(core)
        for p in core:
            q = (p[0] + 1, p[1])
            if q not in cs:
                continue
            ring = {(x, y) for x in range(p[0] - 1, p[0] + 3) for y in range(p[1] - 1, p[1] + 2)} - {p, q}
            if not all(r in g and not kit.dense(m.get(*r).objs) and not m.get(*r).has("/obj/machinery/door") for r in ring):
                continue
            k = (abs(p[0] + 0.5 - cx) + abs(p[1] - cy), p)
            if best is None or k < best[0]:
                best = (k, p, q)
        if not best:
            continue
        _, p, q = best
        pool = next(pl for pre, pl in TABLE_ITEMS if t0.apath.startswith(pre))
        wood = t0.apath.startswith(("/area/library", "/area/lawoffice", "/area/crew_quarters", "/area/bridge"))
        for r in (p, q):
            m.get(*r).objs += [dmm.Atom("/obj/structure/table/wood" if wood else "/obj/structure/table"),
                               dmm.Atom(rnd.choice(pool))]
            for dy, cd in ((1, 2), (-1, 1)):
                c = (r[0], r[1] + dy)
                if rnd.random() < 0.8 and not m.get(*c).objs and not any(
                        m.get(*nb(c, dd)) is not None and m.get(*nb(c, dd)).has("/obj/machinery/door") for dd in CARD):
                    m.get(*c).objs.append(dmm.Atom("/obj/structure/chair/office" if not wood else "/obj/structure/chair/wood",
                                                   [("dir", str(cd))] if cd != 2 else []))
        islands += 1
    log("layout: %d back doors into maint, %d table islands" % (doors_added, islands))


# ================================================================================================= shuttle docks
# the plan's arrivals and escape boxes (map tiles, inside the walls): the shuttles dock there. Port sizes are
# station/to_dmm.py's, the ones its generated maps ran on: Birdboat for evac (the station json names it), the donut
# arrivals shuttle side-on
DOCK_BOXES = {"escape": (90, 13, 100, 19), "arrivals": (24, 83, 30, 89)}


def docks(m, log):
    import to_dmm as T
    for name, (x0, y0, x1, y1) in DOCK_BOXES.items():
        box = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
        cands = []
        for x in range(x0 - 1, x1 + 2):
            for y in range(y0 - 1, y1 + 2):
                if (x, y) in box:
                    continue
                for sdv in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    back, front = (x - sdv[0], y - sdv[1]), (x + sdv[0], y + sdv[1])
                    tf = m.get(*front)
                    if back in box and tf is not None and tf.tpath.startswith("/turf/open/space"):
                        cands.append(((x, y), sdv))
        # the middle of a side first
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        cands.sort(key=lambda c: (abs(c[0][0] - cx) + abs(c[0][1] - cy), c[0]))
        note = None
        if name == "arrivals":
            pid, w, dw, h, extra = T.PORTS["arrivals"]
            for dp, sdv in cands:
                if sdv != (-1, 0):
                    continue
                # side_dock turns a dock door into the shuttle's two airlocks: put a door in first
                t = m.get(*dp)
                saved = (t.turf, list(t.objs), t.area)
                t.turf = dmm.Atom("/turf/open/floor/plating")
                t.objs = [dmm.Atom("/obj/machinery/door/airlock/external", [("name", '"Arrival Airlock"')])]
                note = T.side_dock(m, dp, sdv, pid, w, dw, h, extra)
                if note:
                    break
                t.turf, t.objs, t.area = saved
        else:
            pid, w, dw, h, extra = T.PORTS["escape"]
            for dp, sdv in cands:
                dirn = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}[sdv]

                def clear(q):
                    xa, ya, xb, yb = T.port_rect(q, dirn, w, dw, h)
                    return all(m.get(x, y) is not None and m.get(x, y).tpath.startswith("/turf/open/space") and
                               not any(o.path.startswith("/obj/structure/lattice") for o in m.get(x, y).objs)
                               for x in range(min(xa, xb), max(xa, xb) + 1) for y in range(min(ya, yb), max(ya, yb) + 1))
                for k in range(0, 4):
                    arm = [(dp[0] + i * sdv[0], dp[1] + i * sdv[1]) for i in range(1, k + 1)]
                    q = (dp[0] + (k + 1) * sdv[0], dp[1] + (k + 1) * sdv[1])
                    if not all(m.get(*a) is not None and m.get(*a).tpath.startswith("/turf/open/space") for a in arm):
                        break
                    if not clear(q):
                        continue
                    inner = m.get(dp[0] - sdv[0], dp[1] - sdv[1])
                    door_at = arm[-1] if arm else dp
                    for a in [dp] + arm:
                        m.set(a[0], a[1], dmm.Tile([], dmm.Atom(inner.turf.path, list(inner.turf.vars)), inner.area.copy()))
                        for s_ in (1, -1):
                            f = (a[0] + s_ * sdv[1], a[1] + s_ * sdv[0])
                            if a != dp and m.get(*f) is not None and m.get(*f).tpath.startswith("/turf/open/space"):
                                m.set(f[0], f[1], dmm.Tile([], dmm.Atom("/turf/closed/wall/r_wall"), inner.area.copy()))
                    m.get(*door_at).objs = [dmm.Atom("/obj/machinery/door/airlock/external",
                                                     [("name", '"Escape Airlock"')])]
                    vs = [("dir", str(dirn)), ("dwidth", str(dw)), ("height", str(h)), ("id", '"%s"' % pid),
                          ("name", '"emergency evac bay"'), ("width", str(w))]
                    m.get(*q).objs.append(dmm.Atom("/obj/docking_port/stationary", vs))
                    note = "escape dock: airlock at %d,%d, port at %d,%d dir %d%s" % (
                        door_at[0], door_at[1], q[0], q[1], dirn, (", %d-tile arm" % k) if k else "")
                    break
                if note:
                    break
        log("docks: %s" % (note or "%s: NO room for the shuttle" % name))


PLAZA_PIECES = (("bench", None), ("plant", "/obj/item/twohanded/required/kirbyplants/random"),
                ("vend", "/obj/machinery/vending/cola/random"), ("bench", None),
                ("plant", "/obj/item/twohanded/required/kirbyplants/random"), ("vend", "/obj/machinery/vending/snack/random"),
                ("bench", None), ("vend", "/obj/machinery/vending/cigarette"), ("plant", "/obj/item/twohanded/required/kirbyplants/random"))


def plazas(m, log):
    """Hall walls where the hall opens wider than a corridor (the plazas, arrivals, the docks) get what stock halls
    line them with: benches facing in, plants, vending machines, spaced, never in a door's way (the v6 discriminator
    marked the big bare plazas and the arrivals box as the most generated-looking floor left, 2026-11-21)."""
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/door")}
    spots = []
    for (x, y, z), t in m.tiles.items():
        p = (x, y)
        if not is_floor(t) or not t.apath.startswith("/area/hallway") or t.objs and any(
                kit.dense([o]) or o.path.startswith(("/obj/machinery/door", "/obj/machinery/atmospherics/components",
                                                     "/obj/structure/disposal", "/obj/machinery/disposal")) for o in t.objs):
            continue
        if any(abs(p[0] - q[0]) + abs(p[1] - q[1]) <= 2 for q in doors if abs(p[0] - q[0]) <= 2 and abs(p[1] - q[1]) <= 2):
            continue
        for d in CARD:
            w = m.get(*nb(p, d))
            if w is None or not w.tpath.startswith("/turf/closed"):
                continue
            depth, q = 0, p
            while depth < 12:
                q = nb(q, OPP[d])
                tq = m.get(*q)
                if not is_floor(tq) or not tq.apath.startswith("/area/hallway"):
                    break
                depth += 1
            # the tiles either side along the wall must be hall too (not a corridor's corner)
            side = [s for s in CARD if s not in (d, OPP[d])]
            if depth >= 6 and all(is_floor(m.get(*nb(p, s))) for s in side):
                spots.append((p, d))
            break
    rnd_order = sorted(spots, key=lambda s: ((s[0][0] * 7919 + s[0][1] * 104729) % 1000, s[0]))
    placed, k = [], 0
    for p, d in rnd_order:
        if any(abs(p[0] - q[0]) + abs(p[1] - q[1]) < 5 for q in placed):
            continue
        kind, path = PLAZA_PIECES[k % len(PLAZA_PIECES)]
        t = m.get(*p)
        if kind == "bench":
            # two seats side by side along the wall, facing into the hall
            s = next(s for s in CARD if s not in (d, OPP[d]))
            q = nb(p, s)
            if not (is_floor(m.get(*q)) and not kit.dense(m.get(*q).objs) and m.get(*nb(q, d)).tpath.startswith("/turf/closed")):
                continue
            for r in (p, q):
                m.get(*r).objs.append(dmm.Atom("/obj/structure/chair", [("dir", str(OPP[d]))]))
        else:
            t.objs.append(dmm.Atom(path, [("dir", str(OPP[d]))] if kind == "vend" else []))
        placed.append(p)
        k += 1
    log("plazas: %d pieces along %d open hall wall spots" % (len(placed), len(spots)))


ABANDONED = tuple(a for _, _, a, _, _ in MAINT_ROOMS)
NEWS_AREAS = ("/area/crew_quarters/bar", "/area/crew_quarters/cafeteria", "/area/crew_quarters/lounge", "/area/library",
              "/area/engine/break_room", "/area/medical/medbay/lobby", "/area/crew_quarters/dorms", "/area/crew_quarters/fitness",
              "/area/security/main", "/area/science/research", "/area/quartermaster/office", "/area/hydroponics")


def fixtures(m, log):
    """What stock rooms hang that the department builds left out (Science review 4: three intercoms in the whole
    department, no posters, no newscasters): an intercom in every crew room of 15+ tiles that has none, a newscaster
    in the public rooms, an official poster in most rooms of 20+ tiles, each on a bare free wall face."""
    import random
    rnd = random.Random(404)
    used_w = set()
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if abs(px) >= 16 or abs(py) >= 16:
                used_w.add((x + (1 if px >= 16 else -1 if px <= -16 else 0), y + (1 if py >= 16 else -1 if py <= -16 else 0)))
    made = {"intercom": 0, "newscaster": 0, "poster": 0}
    for g in regions(m):
        t0 = m.get(*next(iter(g)))
        a = t0.apath
        if len(g) < 12 or a in ABANDONED or a.startswith(("/area/hallway", "/area/maintenance", "/area/space", "/area/solar", "/area/shuttle",
                                        "/area/engine/supermatter", "/area/ai_monitored/turret_protected/ai",
                                        "/area/science/mixing/chamber", "/area/security/prison/cell")):
            continue
        def objs_in(pre):
            return any(m.get(*p).has(pre) for p in g)
        faces = [(p, d) for p, d in faces_of(m, g) if not hung(m, p) and nb(p, d) not in used_w
                 and not any(o.path.startswith(("/obj/structure", "/obj/machinery")) for o in m.get(*p).objs)]
        rnd.shuffle(faces)
        want = []
        if len(g) >= 15 and not objs_in("/obj/item/radio/intercom"):
            want.append("intercom")
        if a.startswith(NEWS_AREAS) and not objs_in("/obj/machinery/newscaster"):
            want.append("newscaster")
        if len(g) >= 20 and not objs_in("/obj/structure/sign/poster") and rnd.random() < 0.7:
            want.append("poster")
        for kind in want:
            if not faces:
                break
            p, d = faces.pop()
            if kind == "poster":
                dd, px, py = kit.MOUNT["sign"][d]
                vs = ([("pixel_x", str(px))] if px else []) + ([("pixel_y", str(py))] if py else [])
                m.get(*p).objs.append(dmm.Atom("/obj/structure/sign/poster/official/random", vs))
            else:
                mount(m, p, d, kind)
            used_w.add(nb(p, d))
            faces = [f for f in faces if f[0] != p]
            made[kind] += 1
    log("fixtures: %(intercom)d intercoms, %(newscaster)d newscasters, %(poster)d posters" % made)


# ================================================================================================= glazing
# rooms that never get a window cut (fingerprint 2026-11-21: hull glass 0.04 against humans' 0.24-0.43, inner glass
# 0.12 against 0.16-0.23)
NO_GLASS = ("/area/ai_monitored", "/area/security/armory", "/area/security/prison", "/area/security/brig",
            "/area/security/execution", "/area/security/nuke_storage", "/area/bridge/nuke", "/area/ai_monitored/nuke_storage",
            "/area/science/mixing/chamber", "/area/engine/supermatter", "/area/engine/engine_smes",
            "/area/engine/gravity_generator", "/area/crew_quarters/toilet", "/area/crew_quarters/dorms",
            "/area/crew_quarters/heads/captain/private", "/area/maintenance", "/area/storage", "/area/tcommsat",
            "/area/medical/morgue", "/area/science/server", "/area/security/detectives_office")
INNER_GLASS = ("/area/medical", "/area/science", "/area/hydroponics", "/area/crew_quarters/kitchen",
               "/area/crew_quarters/bar", "/area/crew_quarters/cafeteria", "/area/library", "/area/chapel/main",
               "/area/quartermaster", "/area/engine/break_room", "/area/crew_quarters/fitness",
               "/area/crew_quarters/lounge", "/area/lawoffice", "/area/janitor", "/area/hallway/secondary/exit",
               "/area/crew_quarters/theatre", "/area/security/main", "/area/security/office")


def glaze(m, log):
    hungw = set()
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if abs(px) >= 16 or abs(py) >= 16:
                hungw.add((x + (1 if px >= 16 else -1 if px <= -16 else 0), y + (1 if py >= 16 else -1 if py <= -16 else 0)))
            elif o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera")):
                d = o.num("dir", 2)
                if o.path.startswith("/obj/machinery/camera"):
                    d = {1: 2, 2: 1, 4: 8, 8: 4}.get(d, 1)
                hungw.add(nb((x, y), d if d in CARD else 2))

    def wall(p):
        t = m.get(*p)
        return t is not None and t.tpath.startswith("/turf/closed/wall") and not t.objs and p not in hungw

    def ok_area(t, inner):
        if t is None or not is_floor(t) or t.has("/obj/machinery/door") or is_window(t):
            return False
        if t.apath.startswith(NO_GLASS) and not (not inner and t.apath.startswith("/area/maintenance/") and
                                                 not t.apath.startswith("/area/maintenance/solars")):
            return False
        # no hall windows into Engineering: radiation and break-ins (Engineering review 5)
        return (not inner) or not t.apath.startswith(("/area/crew_quarters/heads", "/area/security/checkpoint", "/area/engine"))

    def cands(kind):
        out = {}
        for (x, y, z), t in m.tiles.items():
            p = (x, y)
            if not wall(p):
                continue
            for d in (1, 4):        # the axis across the wall: N-S (run along x) or E-W (run along y)
                a, b = m.get(*nb(p, d)), m.get(*nb(p, OPP[d]))
                if a is None or b is None:
                    continue
                if kind == "hull":
                    sp = [s for s in (a, b) if s.tpath.startswith("/turf/open/space")]
                    fl = [s for s in (a, b) if ok_area(s, False)]
                    if len(sp) == 1 and len(fl) == 1:
                        out[p] = d
                else:
                    hall = [s for s in (a, b) if is_floor(s) and s.apath.startswith("/area/hallway") and not s.has("/obj/machinery/door")]
                    room = [s for s in (a, b) if ok_area(s, True) and not s.apath.startswith("/area/hallway")]
                    if len(hall) == 1 and len(room) == 1:
                        out[p] = d
                    # or two rooms of the open departments side by side (a lab looking into the next lab)
                    elif all(ok_area(s, True) for s in (a, b)) and (all(s.apath.startswith(INNER_GLASS) for s in (a, b)) or
                                                                   a.apath.split("/")[2] == b.apath.split("/")[2] and a.apath != b.apath):
                        out[p] = d
        return out
    made = {"hull": 0, "inner": 0}
    for kind in ("hull", "inner"):
        c = cands(kind)
        seen = set()
        for p in sorted(c):
            if p in seen:
                continue
            d = c[p]
            along = (1, 0) if d == 1 else (0, 1)
            run = [p]
            q = (p[0] + along[0], p[1] + along[1])
            while c.get(q) == d:
                run.append(q)
                q = (q[0] + along[0], q[1] + along[1])
            seen |= set(run)
            if len(run) < 3:
                continue
            # pairs of panes with a wall between, never at a run's ends (corners and door jambs stay wall)
            for i, w in enumerate(run[1:-1]):
                maint = kind == "hull" and any(m.get(*nb(w, dd)) is not None and m.get(*nb(w, dd)).apath.startswith(
                    "/area/maintenance") for dd in CARD)
                pat = ((i % 4) == 1) if maint else ((i % 4) != 3 if kind == "hull" else (i % 3) in (0, 1))
                if pat and not (kind == "inner" and len(run) < 3):
                    t = m.get(*w)
                    m.set(w[0], w[1], dmm.Tile([dmm.Atom("/obj/effect/spawner/structure/window/reinforced")],
                                               dmm.Atom("/turf/open/floor/plating"), t.area.copy() if t.area else None))
                    made[kind] += 1
    log("glaze: %d hull panes, %d hall panes" % (made["hull"], made["inner"]))


# ================================================================================================= solars
# the plan's four corner docks (plan/station_plan.py DOCKS "solars *"), map tiles of the field inside its ring wall
SOLARS = {"NW": ((20, 143, 28, 151), "fore"), "NE": ((156, 147, 164, 155), "starboard"),
          "SE": ((156, 39, 164, 47), "aft"), "SW": ((20, 19, 28, 27), "port")}


def solars(m, log):
    """Each corner dock becomes a solar array open to space: rows of panels on solar-panel plating with catwalk rows
    and a spine between them, the tracker in the middle, every tile cabled so the field is one net; the catwalk
    corridor to it is solar maint with a cycling airlock at the field's end. Returns the field tiles the station grid
    must reach (one per array)."""
    terms = []
    for key_, ((x0, y0, x1, y1), word) in sorted(SOLARS.items()):
        field = [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
        ring = [(x, y) for x in range(x0 - 1, x1 + 2) for y in (y0 - 1, y1 + 1)] + \
               [(x, y) for y in range(y0, y1 + 1) for x in (x0 - 1, x1 + 1)]
        exits = [p for p in ring if is_floor(m.get(*p))]
        if len(exits) != 1:
            log("solars %s: %d ways in, skipped" % (key_, len(exits)))
            continue
        ex = exits[0]
        out = next(d for d in CARD if nb(ex, d) not in field and is_floor(m.get(*nb(ex, d))))
        inward = OPP[out]
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        area = dmm.Atom("/area/solar/%s" % word)
        for p in ring:
            if p != ex:
                m.set(p[0], p[1], dmm.Tile([dmm.Atom("/obj/structure/lattice")], dmm.Atom("/turf/open/space/basic"),
                                           dmm.Atom("/area/space/nearstation")))
        for (x, y) in field:
            catwalk = (y - y0) % 3 == 1 or x == cx
            if (x, y) == (cx, cy):
                objs = [dmm.Atom("/obj/machinery/power/tracker"), dmm.Atom(kit.CABLE)]
                turf = "/turf/open/floor/plating/airless"
            elif catwalk:
                objs = [dmm.Atom("/obj/structure/lattice/catwalk"), dmm.Atom(kit.CABLE)]
                turf = "/turf/open/floor/plating/airless"
            else:
                objs = [dmm.Atom("/obj/machinery/power/solar", [("id", '"%s"' % word)]), dmm.Atom(kit.CABLE)]
                turf = "/turf/open/floor/plasteel/airless/solarpanel"
            m.set(x, y, dmm.Tile(objs, dmm.Atom(turf), area.copy()))
        # the corridor: the 1-wide catwalk run back to the station, solar maint; a cycling airlock at the field end
        mword = "port" if key_ in ("NW", "SW") else "starboard"
        corr, p, prev = [], nb(ex, out), ex
        while True:
            t = m.get(*p)
            if not is_floor(t) or sum(1 for d in CARD if is_floor(m.get(*nb(p, d)))) > 2 or len(corr) > 60:
                break
            corr.append(p)
            nxt = [nb(p, d) for d in CARD if is_floor(m.get(*nb(p, d))) and nb(p, d) not in (prev,) and nb(p, d) not in corr]
            if len(nxt) != 1:
                break
            prev, p = p, nxt[0]
        for q in corr:
            m.get(*q).area = dmm.Atom("/area/maintenance/solars/%s" % mword)
        m.set(ex[0], ex[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/external",
                                               [("name", '"Solar Maintenance"'), ("req_access_txt", '"13"')]),
                                      dmm.Atom("/obj/effect/mapping_helpers/airlock/cyclelink_helper", [("dir", str(inward))]),
                                      dmm.Atom(kit.CABLE)],
                                     dmm.Atom("/turf/open/floor/plating"), dmm.Atom("/area/maintenance/solars/%s" % mword)))
        if len(corr) >= 3:
            inner = corr[1]
            t = m.get(*inner)
            t.objs = [o for o in t.objs if not kit.dense([o])]
            t.objs += [dmm.Atom("/obj/machinery/door/airlock/external", [("name", '"Solar Maintenance"'),
                                                                          ("req_access_txt", '"13"')]),
                       dmm.Atom("/obj/effect/mapping_helpers/airlock/cyclelink_helper", [("dir", str(out))])]
        # the array's control console just inside the field beside its way in (the corridor is one tile wide)
        entry = nb(ex, inward)
        for d in CARD:
            c = nb(entry, d)
            if d in (inward, out) or c not in field or c == (cx, cy):
                continue
            m.set(c[0], c[1], dmm.Tile([dmm.Atom("/obj/machinery/power/solar_control",
                                                 [("id", '"%s"' % word), ("name", '"%s Solar Control"' % word.title())]),
                                        dmm.Atom(kit.CABLE)], dmm.Atom("/turf/open/floor/plating/airless"), area.copy()))
            break
        terms.append(entry)
        log("solars %s: %d panels, tracker at %d,%d, airlock at %d,%d, %d-tile corridor" % (
            key_, sum(1 for (x, y) in field if not ((y - y0) % 3 == 1 or x == cx)), cx, cy, ex[0], ex[1], len(corr)))
    return terms


# ================================================================================================= 2. shared areas
def shared(m, log, extra_areas=()):
    floors = area_floors(m)
    for area, tiles in sorted(floors.items()):
        if not area.startswith(SHARED) and area not in extra_areas:
            continue
        ts = set(tiles)
        name = area.rsplit("/", 1)[-1].replace("_", " ").title()
        hall = area.startswith("/area/hallway")
        has_apc = any(m.get(*p).has("/obj/machinery/power/apc") for p in tiles)
        faces = [f for f in faces_of(m, tiles) if not hung(m, f[0])]
        cx = sum(p[0] for p in tiles) / len(tiles)
        cy = sum(p[1] for p in tiles) / len(tiles)
        placed = []
        if not has_apc and faces:
            f = min(faces, key=lambda f: (f[0][0] - cx) ** 2 + (f[0][1] - cy) ** 2)
            mount(m, f[0], f[1], "apc", [("name", '"%s APC"' % name)])
            placed.append(f[0])
        faces = [f for f in faces if f[0] not in placed]
        if faces and not any(m.get(*p).has("/obj/machinery/airalarm") for p in tiles):
            f = min(faces, key=lambda f: abs(math.hypot(f[0][0] - cx, f[0][1] - cy) - 6))
            mount(m, f[0], f[1], "airalarm")
            placed.append(f[0])
        # lights: greedy cover, tubes in halls and maint rooms, small bulbs in maint corridors
        small = not hall
        radius = 3.6 if small else 4.0
        path = "/obj/machinery/light/small" if small else "/obj/machinery/light"
        cands = [f for f in faces_of(m, tiles) if f[0] not in placed and not hung(m, f[0])]
        lit = set(p for p in tiles if any(o.path.startswith("/obj/machinery/light") for o in m.get(*p).objs))
        unc = set(ts)
        for p in lit:
            unc -= {q for q in ts if math.hypot(q[0] - p[0], q[1] - p[1]) <= radius}
        lights = []
        # cover cells: bucket the tiles so each candidate's gain is cheap
        while unc:
            best, bg = None, 0
            for p, d in cands:
                if any(math.hypot(p[0] - q[0], p[1] - q[1]) < radius for q in lights):
                    continue
                g = sum(1 for q in unc if abs(q[0] - p[0]) <= radius and abs(q[1] - p[1]) <= radius
                        and math.hypot(q[0] - p[0], q[1] - p[1]) <= radius)
                if g > bg:
                    best, bg = (p, d), g
            if not best or bg < 3:
                break
            p, d = best
            dd = kit.MOUNT["light"][d][0]
            m.get(*p).objs.append(dmm.Atom(path, [("dir", str(dd))] if dd is not None else []))
            lights.append(p)
            unc -= {q for q in ts if math.hypot(q[0] - p[0], q[1] - p[1]) <= radius}
        # vents: farthest-point spread, preferring the middle of the walk (no wall beside)
        corridor = area.startswith("/area/maintenance")
        n = max(1, round(len(tiles) / (90.0 if corridor else 60.0)))
        free = [p for p in tiles if not kit.dense(m.get(*p).objs) and not m.get(*p).has("/obj/machinery/door")
                and not m.get(*p).has("/obj/machinery/atmospherics")]
        mid = [p for p in free if not any(solid(m.get(*nb(p, d))) for d in CARD)] or free
        vents = []
        for _ in range(n):
            if not mid:
                break
            if not vents:
                v = min(mid, key=lambda p: ((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p))
            else:
                v = max(mid, key=lambda p: (min(abs(p[0] - q[0]) + abs(p[1] - q[1]) for q in vents), p))
                if min(abs(v[0] - q[0]) + abs(v[1] - q[1]) for q in vents) < 6:
                    break
            vents.append(v)
        scrub = []
        if not corridor:
            for v in vents:
                opts = [p for p in mid if p not in vents and p not in scrub and 2 <= abs(p[0] - v[0]) + abs(p[1] - v[1]) <= 3]
                if opts:
                    scrub.append(min(opts, key=lambda p: (abs(p[0] - v[0]) + abs(p[1] - v[1]), p)))
        for v in vents:
            m.get(*v).objs.append(dmm.Atom(kit.PIPES["supply"][3]))
        for s in scrub:
            m.get(*s).objs.append(dmm.Atom(kit.PIPES["scrubbers"][3]))
        log("shared: %-28s %4d tiles  APC %s  %d lights  %d vents %d scrubbers" % (
            area.replace("/area/", ""), len(tiles), "kept" if has_apc else "new", len(lights), len(vents), len(scrub)))


def polish(m, log):
    """The whole-station passes station/to_dmm.py runs on generated maps, on the shared halls and maint only (the
    departments are hand-made): firelock lines across the halls, direction and department signs on the hall walls,
    warnings by maint doors, one piece per wall face, clutter down the maint runs."""
    import random
    import to_dmm as T
    zone = {(x, y) for (x, y, z), t in m.tiles.items() if t.apath.startswith(SHARED)}
    # the sign pass walks the doors off the halls and hangs on the walls round them: give it those too
    edge = {nb(p, d) for p in zone for d in CARD} - zone
    edge = {q for q in edge if m.get(*q) is not None and (m.get(*q).tpath.startswith("/turf/closed")
                                                         or m.get(*q).has("/obj/machinery/door"))}
    for fn, args in ((T.fit_hall_firelocks, (m, zone)), (T.hall_signs, (m, zone | edge, random.Random(6))),
                     (T.one_per_wall_face, (m, zone)), (T.dress_maint, (m, zone, 6))):
        notes = fn(*args)
        for n in (notes if isinstance(notes, list) else [notes] if notes else []):
            log("polish: %s" % n)
    trim(m, zone, log)


# a department's colour on the hall floor round its doors (Meta: medbay blue, science purple, security red...)
DEPT_TRIM = (("/area/medical", "blue"), ("/area/science", "purple"), ("/area/security", "red"), ("/area/engine", "yellow"),
             ("/area/quartermaster", "brown"), ("/area/cargo", "brown"), ("/area/hydroponics", "green"),
             ("/area/crew_quarters/kitchen", "green"), ("/area/crew_quarters/bar", "green"), ("/area/bridge", "blue"),
             ("/area/crew_quarters/heads", "blue"), ("/area/ai_monitored", "blue"))
QUARTERS = {1: (1, 4), 2: (8, 2), 4: (4, 2), 8: (1, 8)}     # wall side -> the tile quarters (NW 1, NE 4, SE 2, SW 8)


def trim(m, zone, log):
    """Hall edge trim: each hall tile along a wall gets the quarter decals on that side, neutral grey, or the colour of
    the department whose door is within 3 tiles (the stock halls' look; the v6 reviews: "no door paint, no trim")."""
    doors = []
    for (x, y, z), t in m.tiles.items():
        if not t.has("/obj/machinery/door/airlock") or t.apath.startswith(SHARED):
            continue
        col = next((c for pre, c in DEPT_TRIM if t.apath.startswith(pre)), None)
        if col:
            doors.append(((x, y), col))
    n = coloured = 0
    for p in sorted(zone):
        t = m.get(*p)
        if not is_floor(t) or not t.apath.startswith("/area/hallway") or t.has("/obj/machinery/door") or \
                t.has("/obj/effect/turf_decal/tile"):
            continue
        sides = [d for d in CARD if (lambda q: q is not None and (q.tpath.startswith("/turf/closed") or
                                                                 q.has("/obj/machinery/door/airlock")))(m.get(*nb(p, d)))]
        if not sides:
            continue
        near = [(abs(p[0] - q[0]) + abs(p[1] - q[1]), c) for q, c in doors if abs(p[0] - q[0]) + abs(p[1] - q[1]) <= 3]
        col = min(near)[1] if near else "neutral"
        quarters = sorted({qd for d in sides for qd in QUARTERS[d]})
        for qd in quarters:
            t.objs.insert(0, dmm.Atom("/obj/effect/turf_decal/tile/%s" % col, [("dir", str(qd))] if qd != 2 else []))
        n += 1
        coloured += col != "neutral"
    painted = 0
    for q, col in doors:
        for d in CARD:
            h = nb(q, d)
            th = m.get(*h)
            if th is None or not is_floor(th) or not th.apath.startswith("/area/hallway") or th.has("/obj/machinery/door"):
                continue
            side = [s_ for s_ in CARD if s_ not in (d, OPP[d])]
            for r in [h] + [nb(h, s_) for s_ in side]:
                tr = m.get(*r)
                if tr is None or not is_floor(tr) or not tr.apath.startswith("/area/hallway") or tr.has("/obj/machinery/door"):
                    continue
                tr.objs = [o for o in tr.objs if not o.path.startswith("/obj/effect/turf_decal/tile")]
                for qd in (1, 4, 2, 8):
                    tr.objs.insert(0, dmm.Atom("/obj/effect/turf_decal/tile/%s" % col, [("dir", str(qd))] if qd != 2 else []))
                painted += 1
    log("polish: hall trim on %d tiles (%d in a department's colour by its doors), %d door-front tiles painted" % (
        n, coloured, painted))


# ================================================================================================= networks
def forest(m, root_sources, terminals, cost_fn, unary=()):
    """A tree from the sources to every terminal: one Dijkstra that carries on as each branch joins (to_dmm's
    StationBuilder.forest). Returns (mask {tile: dirs}, terminals left unreached)."""
    mask = {}
    unary = set(unary)

    def lay(path):
        for a, b in zip(path, path[1:]):
            d = next(dd for dd in CARD if nb(a, dd) == b)
            mask[a] = mask.get(a, 0) | d
            mask[b] = mask.get(b, 0) | OPP[d]
        if len(path) == 1:
            mask.setdefault(path[0], 0)
    left = set(terminals)
    dist, prev, heap = {}, {}, []

    def add_source(p):
        if p in unary or dist.get((p, 0), 1e9) == 0:
            return
        dist[(p, 0)] = 0
        prev.pop((p, 0), None)
        heapq.heappush(heap, (0, p, 0))
    for s in root_sources:
        lay([s])
        add_source(s)
    left -= set(mask)
    while left:
        found = None
        while heap:
            c, p, din = heapq.heappop(heap)
            if dist.get((p, din), 1e9) < c:
                continue
            if p in left:
                found = (p, din)
                break
            if p in unary and din:
                continue
            for d in CARD:
                q = nb(p, d)
                if q in mask:
                    continue
                step = cost_fn(q, p, d)
                if step is None:
                    continue
                if din and d != din:
                    step += 2.5
                nc = c + step
                if nc < dist.get((q, d), 1e9):
                    dist[(q, d)] = nc
                    prev[(q, d)] = (p, din)
                    heapq.heappush(heap, (nc, q, d))
        if not found:
            break
        path, node = [found[0]], found
        while node in prev:
            node = prev[node]
            path.append(node[0])
        path.reverse()
        lay(path)
        left -= set(mask)
        for p in path:
            add_source(p)
    return mask, left


def power(m, log, extra=()):
    # the SMES terminals on the floor north of the row, facing it
    for x, y in SMES_TILES:
        t = m.get(x, y + 1)
        if is_floor(t) and not t.has("/obj/machinery/power/terminal"):
            t.objs.append(dmm.Atom("/obj/machinery/power/terminal", [("dir", "2")]))
    eng = {p for (x, y, z), t in m.tiles.items() for p in [(x, y)]
           if t.apath.startswith(("/area/engine/supermatter", "/area/engine/engineering")) and 129 <= x <= 146 and 60 <= y <= 77}
    kept = set()
    for (x, y, z), t in m.tiles.items():
        cab = [o for o in t.objs if kit.is_cable(o)]
        if not cab:
            continue
        if (x, y) in eng and (x, y) not in ENGINE_UNWIRE:
            kept.add((x, y))
        elif t.apath.startswith("/area/solar"):
            continue        # the arrays' own wiring (solars()): the grid joins it at each array's way in
        else:
            for o in cab:
                t.objs.remove(o)
    apcs = [(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/power/apc")]
    terms = [(x, y + 1) for x, y in SMES_TILES]
    engine_out_ = [None]
    machines = [(x, y) for (x, y, z), t in m.tiles.items()
                if t.has("/obj/machinery/power/smes") or t.has("/obj/machinery/power/port_gen")]

    def cost(q, p, d):
        t = m.get(*q)
        # never through the crystal's chamber, nor across the block's own cable nets except where the grid joins them
        if t is None or t.tpath.startswith("/turf/open/space") or t.apath.startswith("/area/engine/supermatter") or                 (q in kept and q != engine_out_[0]):
            return None
        c = 1.0
        if t.tpath.startswith("/turf/closed"):
            c += 0.6
        if t.has("/obj/machinery/door"):
            c += 1.5
        if is_window(t):
            c += 3.0
        if any(o.path.startswith(("/obj/machinery/shower", "/obj/structure/sink", "/obj/structure/toilet")) for o in t.objs):
            c += 40
        if any(solid(m.get(*nb(q, dd))) for dd in CARD):
            c -= 0.3
        return c
    # The block's own cables are two nets (Engineering review 5): the emitters' feed, which carries Engine Control's
    # APC, and the rad collectors' ring, which is what the engine makes. As Meta wires it: the collectors charge the
    # SMES through their terminals; the SMES feed the station grid, the emitters on it. The game never links the cable
    # under an SMES to the one under its terminal (cable.dm), so these are separate nets:
    #   input  terminals -> collector ring, on cable layer 1 (it crosses the emitter wiring without joining it), a
    #          cable bridge at each end so the terminals and the ring's layer-2 cable take it
    #   grid   SMES tiles -> every APC, the generators, the solar arrays and the emitter net (layer 2), kept a tile clear
    #          of the collector ring
    #   sat    the AI satellite's SMES -> its own APCs; the grid feeds only that SMES's terminal
    comps = []
    left_k = set(kept)
    while left_k:
        s0 = left_k.pop()
        g, q = {s0}, [s0]
        while q:
            c = q.pop()
            for d in CARD:
                n = nb(c, d)
                if n in left_k:
                    left_k.discard(n)
                    g.add(n)
                    q.append(n)
        comps.append(g)

    def holds(g, pre):
        return any(m.get(*p).has(pre) for p in g)
    coll = next((g for g in comps if holds(g, "/obj/machinery/power/rad_collector")), set())
    emit = next((g for g in comps if holds(g, "/obj/machinery/power/emitter")), set())
    smes = set(SMES_TILES)

    def near(g, to):
        return min(g, key=lambda q: (min(abs(q[0] - t[0]) + abs(q[1] - t[1]) for t in to), q)) if g else None
    coll_join = near({q for q in coll if not m.get(*q).apath.startswith("/area/engine/supermatter")}, terms)

    def cost_in(q, p, d):
        t = m.get(*q)
        if t is None or t.tpath.startswith("/turf/open/space") or t.apath.startswith("/area/engine/supermatter") or q in smes:
            return None
        return 1.0 + (0.6 if t.tpath.startswith("/turf/closed") else 0)
    inmask, inleft = forest(m, sorted(terms), [coll_join] if coll_join else [], cost_in)
    for p in inmask:
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable/layer1"))
    for p in list(terms) + ([coll_join] if coll_join else []):
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable_bridge"))
    # the AI satellite's own net
    sat_smes = [(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/power/smes") and (x, y) not in smes]
    sat_term = []
    for sp in sat_smes:
        for d in CARD:
            q = nb(sp, d)
            if any(o.path.startswith("/obj/machinery/power/terminal") and o.num("dir", 2) == OPP[d] for o in m.get(*q).objs):
                sat_term.append(q)
    def in_sat(t):
        return t.apath == "/area/ai_monitored/turret_protected/ai" or t.apath.startswith("/area/ai_monitored/turret_protected/aisat")
    sat_apcs = [a for a in apcs if in_sat(m.get(*a))]

    def cost_sat(q, p, d):
        t = m.get(*q)
        if t is None or not in_sat(t) or q in sat_term or q in inmask:
            return None
        return cost(q, p, d)
    # on cable layer 1 like the input net, a bridge at the SMES and at each APC: the grid's layer-2 cable to the
    # terminal can pass beside it without joining (the sat review: its SMES fed nothing)
    satmask, satleft = forest(m, sorted(sat_smes), sat_apcs, cost_sat) if sat_smes else ({}, set())
    for p in satmask:
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable/layer1"))
    for p in list(sat_smes) + [a for a in sat_apcs if a in satmask]:
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable_bridge"))
    # the grid
    emit_join = near(emit, smes)
    on_emit = [a for a in apcs if a in emit]
    fence = set(coll) | {nb(q, d) for q in coll for d in CARD}
    # every bridge joins all the cables on its tile: the grid keeps off them
    fence |= set(terms) | ({coll_join} if coll_join else set()) | set(sat_smes) | set(sat_apcs)
    fence |= set(emit) - {emit_join}
    fence -= smes
    fence -= set(sat_term)
    engine_out_[0] = emit_join

    def cost_grid(q, p, d):
        return None if q in fence else cost(q, p, d)
    targets = [a for a in apcs if a not in sat_apcs and a not in on_emit] + machines + list(extra) + list(sat_term) +         ([emit_join] if emit_join else [])
    targets = [t for t in targets if t not in sat_smes]
    mask, left = forest(m, sorted(smes), targets, cost_grid)
    for p in mask:
        m.get(*p).objs.append(dmm.Atom(kit.CABLE))
    for p in left:
        m.get(*p).objs.append(dmm.Atom(kit.CABLE))
    log("power: %d APCs; grid %d cable tiles (emitters joined at %s); input net %d layer-1 tiles to the collector ring at "
        "%s; AI sat net %d tiles, %d APCs%s%s%s" % (
            len(apcs), len(mask), "%d,%d" % emit_join if emit_join else "-", len(inmask),
            "%d,%d" % coll_join if coll_join else "-", len(satmask), len(sat_apcs),
            (", UNREACHED %s" % " ".join("%d,%d" % p for p in sorted(left)[:10])) if left else "",
            ", COLLECTORS NOT JOINED" if inleft else "", (", SAT UNREACHED %d" % len(satleft)) if satleft else ""))
    return left


# the supermatter block's waste line ends pointing west at 132,71 (into the gravity room's notch): the station's
# scrubber network takes it there, so the engine's waste goes out with the rest (Engineering review 5)
ENGINE_WASTE_TAPS = [((131, 71), 4)]

# the gas chambers in Atmospherics, by their turf: tg's preset tags for each (the tank consoles find their machines by
# them): (gas word, siphon, injector)
GASES = {"air": ("air", "/obj/machinery/atmospherics/components/unary/vent_pump/high_volume/siphon/atmos/air_output"),
         "n2": ("nitrogen", None), "o2": ("oxygen", None), "co2": ("carbon", None), "plasma": ("toxin", None)}
CHAMBER_TURF = "/turf/open/floor/engine/"
D_CW = {1: 4, 4: 2, 2: 8, 8: 1}        # turn(dir, -90): a trinary filter's catch side


def is_tank(t):
    """An Atmospherics gas tank's floor (not the toxins burn chamber's vacuum floor)."""
    return t is not None and t.tpath.startswith(CHAMBER_TURF) and t.tpath[len(CHAMBER_TURF):].split("/")[0] in GASES


def chambers(m, log):
    """Atmospherics as a crew runs it: each gas chamber gets its sensor, an output siphon and an input injector, each
    piped through the chamber wall (two of its three panes turned to wall) to the room, where a tank console stands
    between them. The air chamber's output goes through the distro pump into the supply network (its root); the
    others end at portable connectors, so the canisters standing there fill from and refill the tanks. Waste: the
    scrubber network ends at an injector out past the hull. Returns {cls: (tap, side to device, device tile)}."""
    groups = {}
    for (x, y, z), t in m.tiles.items():
        if t.tpath.startswith(CHAMBER_TURF):
            g = t.tpath[len(CHAMBER_TURF):].split("/")[0]
            if g in GASES:
                groups.setdefault(g, []).append((x, y))
    roots = {}
    notes = []
    for g, tiles in sorted(groups.items()):
        word, siphon = GASES[g]
        siphon = siphon or "/obj/machinery/atmospherics/components/unary/vent_pump/siphon/atmos/%s_output" % word
        inject = "/obj/machinery/atmospherics/components/unary/outlet_injector/atmos/%s_input" % word
        xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
        cx, top = (min(xs) + max(xs)) // 2, max(ys)
        room_y = top + 2
        if not m.get(cx, top + 1).has("/obj/effect/spawner/structure/window"):
            notes.append("%s chamber: no pane north of it, skipped" % g)
            continue
        layer = [("piping_layer", "1")] if g == "air" else []

        def clear(p, keep_portable=False):
            t = m.get(*p)
            t.objs = [o for o in t.objs if not (kit.dense([o]) and not (keep_portable and
                                                                           o.path.startswith("/obj/machinery/portable_atmospherics")))]
        for x, dev in ((cx - 1, siphon), (cx + 1, inject)):
            lay_ = layer if dev == siphon else []        # only the distro side is on the supply's layer 1
            m.get(x, top).objs.append(dmm.Atom(dev, [("dir", "1")] + lay_))
            m.set(x, top + 1, dmm.Tile([dmm.Atom("/obj/machinery/atmospherics/pipe/simple/general/hidden", lay_)],
                                       dmm.Atom("/turf/closed/wall/r_wall"), m.get(x, top + 1).area.copy()))
        m.get(cx, top - 1).objs.append(dmm.Atom("/obj/machinery/air_sensor/atmos/%s_tank" % word))
        clear((cx, room_y))
        m.get(cx, room_y).objs.append(dmm.Atom("/obj/machinery/computer/atmos_control/tank/%s_tank" % word, [("dir", "1")]))
        if g == "air":
            # the distro pump: out of the air chamber into the supply network at 4.5 MPa (the vents bring it down)
            clear((cx - 1, room_y))
            clear((cx - 1, room_y + 1))
            m.get(cx - 1, room_y).objs.append(dmm.Atom("/obj/machinery/atmospherics/components/binary/pump/on/layer1",
                                                       [("dir", "1"), ("name", '"Air to Distro"'), ("target_pressure", "4500")]))
            roots["supply"] = ((cx - 1, room_y + 1), 2, (cx - 1, room_y))
        else:
            clear((cx - 1, room_y), keep_portable=True)
            m.get(cx - 1, room_y).objs.append(dmm.Atom("/obj/machinery/atmospherics/components/unary/portables_connector/visible",
                                                       [("dir", "2")]))
        clear((cx + 1, room_y), keep_portable=True)
        m.get(cx + 1, room_y).objs.append(dmm.Atom("/obj/machinery/atmospherics/components/unary/portables_connector/visible",
                                                   [("dir", "2")]))
        notes.append("%s chamber at %d,%d: sensor, %s out, %s in, tank console" % (
            g, cx, top, siphon.rsplit("/", 1)[-1], inject.rsplit("/", 1)[-1]))
    # the air mix: the N2 and O2 outputs into Meta's 78/22 mixer, and on into the air chamber's injector, so distro
    # never runs the air tank dry (Engineering review 5). Laid by hand along the two rows above the connectors.
    tops = {g: (((min(p[0] for p in t) + max(p[0] for p in t)) // 2), max(p[1] for p in t)) for g, t in groups.items()}
    if all(g in tops for g in ("n2", "o2", "air")):
        (nx, ty), (ox, _), (ax, _) = tops["n2"], tops["o2"], tops["air"]
        y1_, y2_, y3_ = ty + 2, ty + 3, ty + 4          # the connector row, then two rows up
        mx = ax - 2                                      # the mixer, west of the air chamber's input column
        P = "/obj/machinery/atmospherics/pipe/simple/general/visible"

        def lay(p, mask, extra=()):
            t = m.get(*p)
            t.objs = [o for o in t.objs if not (kit.dense([o]) and not o.path.startswith("/obj/machinery/atmospherics"))
                      and not o.path.startswith("/obj/machinery/atmospherics/components/unary/portables_connector")]
            d = {3: 1, 12: 4, 5: 5, 9: 9, 6: 6, 10: 10}[mask]
            t.objs.append(dmm.Atom(P, [("dir", str(d))] if d != 2 else []))
        n_out, o_out, a_in = (nx - 1, y1_), (ox - 1, y1_), (ax + 1, y1_)
        # N2: up its column to the top row, east to the mixer's west input
        lay(n_out, 1 | 2)
        lay((n_out[0], y2_), 1 | 2)
        lay((n_out[0], y3_), 2 | 4)
        for x in range(n_out[0] + 1, mx):
            lay((x, y3_), 4 | 8)
        # O2: up one row, east, up into the mixer's south input
        lay(o_out, 1 | 2)
        lay((o_out[0], y2_), 2 | 4)
        for x in range(o_out[0] + 1, mx):
            lay((x, y2_), 4 | 8)
        lay((mx, y2_), 8 | 1)
        t = m.get(mx, y3_)
        t.objs = [o for o in t.objs if not kit.dense([o])]
        t.objs.append(dmm.Atom("/obj/machinery/atmospherics/components/trinary/mixer/airmix", [("dir", "4")]))
        # out east and down into the air chamber's input
        for x in range(mx + 1, a_in[0]):
            lay((x, y3_), 4 | 8)
        lay((a_in[0], y3_), 8 | 2)
        lay((a_in[0], y2_), 1 | 2)
        lay(a_in, 1 | 2)
        notes.append("air mix: N2 %d,%d + O2 %d,%d -> airmix mixer %d,%d -> air injector %d,%d" % (
            n_out[0], n_out[1], o_out[0], o_out[1], mx, y3_, a_in[0], a_in[1] - 2))
    # waste: out past the hull nearest the atmos room, an injector on the space side of the wall
    atm = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath == "/area/engine/atmos" and is_floor(t)]
    ax = sum(p[0] for p in atm) / len(atm)
    ay = sum(p[1] for p in atm) / len(atm)
    best = None
    for (x, y, z), t in m.tiles.items():
        if not t.tpath.startswith("/turf/open/space"):
            continue
        for d in CARD:
            w = nb((x, y), d)
            inner = nb(w, d)
            tw, ti = m.get(*w), m.get(*inner)
            if tw is not None and tw.tpath.startswith("/turf/closed") and is_floor(ti) and not is_window(ti):
                k = (abs(x - ax) + abs(y - ay), x, y)
                if best is None or k < best[0]:
                    best = (k, (x, y), w, OPP[d])
    if best:
        _, inj, w, toward_inj = best
        m.get(*inj).objs += [dmm.Atom("/obj/structure/lattice"),
                             dmm.Atom("/obj/machinery/atmospherics/components/unary/outlet_injector/atmos/atmos_waste",
                                      [("dir", str(OPP[toward_inj])), ("on", "1")])]
        roots["scrubbers"] = (w, toward_inj, inj)
        notes.append("waste outlet at %d,%d through the hull at %d,%d" % (inj[0], inj[1], w[0], w[1]))
        # a plasma filter on the line before it leaves, its catch to a connector for a canister (Engineering review 6:
        # the waste went raw to space). Filter nodes (trinary_devices.dm): in from behind, the rest straight on
        # (toward the outlet), the catch to its right.
        up = OPP[toward_inj]
        f = nb(w, up)
        r = nb(f, up)
        catch = nb(f, D_CW[toward_inj])
        tf, tr, tc = m.get(*f), m.get(*r), m.get(*catch)
        if all(t_ is not None and is_floor(t_) and not kit.dense(t_.objs) and not t_.has("/obj/machinery/door")
               for t_ in (tf, tr, tc)):
            m.get(*w).objs.append(dmm.Atom("/obj/machinery/atmospherics/pipe/simple/general/visible",
                                           [("dir", str(toward_inj))] if toward_inj not in (1, 2) else []))
            tf.objs.append(dmm.Atom("/obj/machinery/atmospherics/components/trinary/filter/atmos/plasma",
                                    [("dir", str(toward_inj))]))
            tc.objs.append(dmm.Atom("/obj/machinery/atmospherics/components/unary/portables_connector/visible",
                                    [("dir", str(OPP[D_CW[toward_inj]]))]))
            roots["scrubbers"] = (r, toward_inj, f)
            notes.append("waste plasma filter at %d,%d, its catch to the connector at %d,%d" % (f[0], f[1], catch[0], catch[1]))
    for n in notes:
        log("atmos: %s" % n)
    return roots


def air(m, log):
    vents = {"supply": [], "scrubbers": []}
    for (x, y, z), t in m.tiles.items():
        for o in list(t.objs):
            cls = kit.pipe_class(o.path)
            if cls not in ("supply", "scrubbers"):
                continue
            # the supermatter block's own loop stays as laid: its visible scrubber pipes carry the engine's waste, and
            # the chamber's scrubbers feed it (Engineering review 5: stripping them left the loop with no way out)
            if "/visible" in o.path or t.apath.startswith("/area/engine/supermatter"):
                continue
            if "vent_pump" in o.path or "vent_scrubber" in o.path:
                vents[cls].append((x, y))
            t.objs.remove(o)
    unreached = {}
    roots = chambers(m, log)
    # every sealed room of the crew's gets a supply vent if it has none: a breached cell or a burned justice chamber
    # must refill (Security review 4: eleven sealed rooms had none)
    have = set(vents["supply"])
    every = set(vents["supply"]) | set(vents["scrubbers"])
    added = 0
    for g in regions(m):
        t0 = m.get(*next(iter(g)))
        if len(g) < 3 or t0.apath.startswith(("/area/maintenance", "/area/hallway", "/area/space", "/area/solar",
                                               "/area/shuttle", "/area/engine/supermatter", "/area/science/mixing/chamber",
                                               "/area/science/server", "/area/ai_monitored/turret_protected/ai",
                                               "/area/science/mixing")) \
                or t0.tpath.startswith("/turf/open/floor/engine") or any(p in have for p in g):
            continue
        free = [p for p in g if not kit.dense(m.get(*p).objs) and not atmos.atoms(m.get(*p)) and not m.get(*p).objs
                and p not in every]
        if free:
            cx_ = sum(p[0] for p in g) / len(g)
            cy_ = sum(p[1] for p in g) / len(g)
            v = min(free, key=lambda p: ((p[0] - cx_) ** 2 + (p[1] - cy_) ** 2, p))
            vents["supply"].append(v)
            added += 1
    if added:
        log("air: %d sealed rooms given their own vent" % added)
    # a vent never shares a tile with the room's own pipework, a connector or a console (Engineering review 5: vents
    # on the connector row): it moves to the nearest free floor of its room
    moved = 0
    for cls in ("supply", "scrubbers"):
        mine_l = 1 if cls == "supply" else 2
        out = []
        taken_v = set(vents["supply"]) | set(vents["scrubbers"])
        for v in vents[cls]:
            t = m.get(*v)
            row = any(m.get(*nb(v, d)) is not None and m.get(*nb(v, d)).has("/obj/machinery/atmospherics/components/unary/portables_connector")
                      for d in (4, 8))
            bad = kit.dense(t.objs) or bool(atmos.atoms(t)) or row or t.has("/obj/machinery/computer")
            if bad:
                cand = [(x, y) for x in range(v[0] - 4, v[0] + 5) for y in range(v[1] - 4, v[1] + 5)
                        if (x, y) not in taken_v and m.get(x, y) is not None and m.get(x, y).apath == t.apath
                        and is_floor(m.get(x, y)) and not is_window(m.get(x, y)) and not kit.dense(m.get(x, y).objs)
                        and not m.get(x, y).has("/obj/machinery/door") and not atmos.atoms(m.get(x, y))
                        and not m.get(x, y).has("/obj/machinery/computer")]
                if cand:
                    nv = min(cand, key=lambda q: (abs(q[0] - v[0]) + abs(q[1] - v[1]), q))
                    taken_v.add(nv)
                    out.append(nv)
                    moved += 1
                    continue
            out.append(v)
        vents[cls] = out
    if moved:
        log("air: moved %d vents off pipework, connectors and consoles" % moved)
    for cls in ("supply", "scrubbers"):
        tap, side, dev = roots[cls]
        mine = 1 if cls == "supply" else 2
        block = set(vents["scrubbers" if cls == "supply" else "supply"]) | {dev}

        def cost(q, p, d):
            t = m.get(*q)
            if t is None or t.tpath.startswith("/turf/open/space") or is_window(t) or q in block:
                return None
            if any(atmos.layer(o) == mine for o in atmos.atoms(t)):
                return None         # another loop on our layer: it would join or block it
            if is_tank(t) or (t.tpath.startswith("/turf/closed") and any(is_tank(m.get(*nb(q, dd))) for dd in CARD)):
                return None         # never through a gas tank or its wall (Engineering review 6: waste ran under the air tank)
            c = 1.0
            if t.tpath.startswith("/turf/closed"):
                a, b = m.get(*p), m.get(*nb(q, d))
                c += 5 if (a and b and a.apath == b.apath) else 12
            if t.has("/obj/machinery/door"):
                c += 0.8
            if kit.dense(t.objs):
                c += 0.4
            if any(solid(m.get(*nb(q, dd))) for dd in CARD):
                c -= 0.25
            return c
        taps = ENGINE_WASTE_TAPS if cls == "scrubbers" else []
        mask, left = forest(m, [tap], vents[cls] + [p for p, d in taps], cost, unary=vents[cls])
        if left - {p for p, d in taps}:
            # a vent boxed in by other pipework: the nearest free tile of its room, then lay the tree again
            for v in sorted(left - {p for p, d in taps}):
                t = m.get(*v)
                cand = [(x, y) for x in range(v[0] - 3, v[0] + 4) for y in range(v[1] - 3, v[1] + 4)
                        if (x, y) not in vents[cls] and m.get(x, y) is not None and m.get(x, y).apath == t.apath
                        and is_floor(m.get(x, y)) and not is_window(m.get(x, y)) and not kit.dense(m.get(x, y).objs)
                        and not atmos.atoms(m.get(x, y)) and not m.get(x, y).has("/obj/machinery/door") and (x, y) not in block]
                if cand:
                    vents[cls][vents[cls].index(v)] = min(cand, key=lambda q: (abs(q[0] - v[0]) + abs(q[1] - v[1]), q))
            mask, left = forest(m, [tap], vents[cls] + [p for p, d in taps], cost, unary=vents[cls])
        mask[tap] = mask.get(tap, 0) | side       # chambers() gives the side from the tap toward its device
        for p, d in taps:
            if p in mask:
                mask[p] |= d
            else:
                log("air: the engine's waste end at %d,%d was not reached" % (p[0] + DELTA[d][0], p[1] + DELTA[d][1]))
        simple, manifold, four, vent = kit.PIPES[cls]
        for p, mk in mask.items():
            t = m.get(*p)
            if p in vents[cls]:
                d = next((x for x in CARD if x & mk), 2)
                t.objs.append(dmm.Atom(vent, [("dir", str(d))] if d != 2 else []))
            else:
                pth, vs = kit.pipe_atom(cls, mk)
                t.objs.append(dmm.Atom(pth, vs))
        # a vent the tree still cannot reach (boxed in by a room's own pipework on its layer) is left out: an
        # unconnected vent is worse than none, and the room has others
        dropped = sorted(v for v in left if v in vents[cls])
        if dropped:
            log("air: %s left out, unreachable: %s" % (cls, " ".join("%d,%d" % v for v in dropped)))
        left = left - set(dropped)
        unreached[cls] = left
        log("air: %-9s %3d vents, %4d pipe tiles%s" % (cls, len(vents[cls]), len(mask) - len(vents[cls]),
                                                      (", UNREACHED %s" % " ".join("%d,%d" % p for p in sorted(left)[:10])) if left else ""))
    return unreached


# ================================================================================================= 5. disposals
def disposal_exit(m, near):
    """The disposals exit: a maint tile for the outlet, the mass driver in front of it, a blast door in the hull wall
    beyond and space past that, the nearest such run to `near`. Returns (outlet tile, throw dir) or None."""
    best = None
    for (x, y, z), t in m.tiles.items():
        if not is_floor(t) or not t.apath.startswith("/area/maintenance") or kit.dense(t.objs):
            continue
        for d in CARD:
            drv, wall, sp = nb((x, y), d), nb(nb((x, y), d), d), nb(nb(nb((x, y), d), d), d)
            td, tw, ts = m.get(*drv), m.get(*wall), m.get(*sp)
            if not (is_floor(td) and td.apath.startswith("/area/maintenance") and not kit.dense(td.objs)
                    and not td.has("/obj/machinery/door") and tw is not None and tw.tpath.startswith("/turf/closed")
                    and ts is not None and ts.tpath.startswith("/turf/open/space")):
                continue
            # the run is walled either side, so the blast door is the only way out
            side = [CW_ for CW_ in CARD if CW_ not in (d, OPP[d])]
            if not all(solid(m.get(*nb(wall, s))) for s in side):
                continue
            k = (abs(x - near[0]) + abs(y - near[1]), x, y, d)
            if best is None or k < best[0]:
                best = (k, (x, y), d)
    return (best[1], best[2]) if best else None


BIN_AREAS = ("/area/medical", "/area/science", "/area/security/main", "/area/security/office", "/area/engine/engineering",
             "/area/engine/break_room", "/area/crew_quarters/kitchen", "/area/crew_quarters/bar", "/area/hydroponics",
             "/area/janitor", "/area/bridge", "/area/crew_quarters/heads", "/area/crew_quarters/locker",
             "/area/crew_quarters/lounge", "/area/library", "/area/quartermaster", "/area/lawoffice", "/area/storage/tools")


def bins(m, log):
    """A disposal bin in each bigger crew room that has none (Medical, Service, Command and Dorms reviews: one or two
    bins a department), against a wall, off the door aprons; the disposals tree then reaches it."""
    added = 0
    doors_ = {(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/door")}
    for g in regions(m):
        t0 = m.get(*next(iter(g)))
        if len(g) < 20 or t0.apath in ABANDONED or t0.apath == "/area/library/lounge" or not t0.apath.startswith(BIN_AREAS) \
                or any(m.get(*q).has("/obj/machinery/disposal") for q in g):
            continue
        spots = [q for q in g if not any(o.path.startswith(("/obj/structure", "/obj/machinery")) for o in m.get(*q).objs)
                 and not hung(m, q) and any(m.get(*nb(q, d)).tpath.startswith("/turf/closed") for d in CARD)
                 and not any(abs(q[0] - d_[0]) + abs(q[1] - d_[1]) <= 2 for d_ in doors_
                             if abs(q[0] - d_[0]) <= 2 and abs(q[1] - d_[1]) <= 2)]
        if not spots:
            continue
        cx = sum(q[0] for q in g) / len(g)
        cy = sum(q[1] for q in g) / len(g)
        q = min(spots, key=lambda q: ((q[0] - cx) ** 2 + (q[1] - cy) ** 2, q))
        m.get(*q).objs.append(dmm.Atom("/obj/machinery/disposal/bin"))
        added += 1
    log("bins: %d rooms given a disposal bin" % added)


def disposals(m, log):
    from forge import disposals as D
    bins = sorted((x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/disposal/bin"))
    # the station's trash: every bin not on a local line (xenobiology's pens keep theirs)
    for p in bins:
        t = m.get(*p)
        t.objs = [o for o in t.objs if not o.path.startswith(D.PIPE + "/trunk")]
    local = {(x, y) for (x, y, z), t in m.tiles.items() if D.mask_at(t)}
    cx = sum(p[0] for p in bins) / len(bins)
    cy = sum(p[1] for p in bins) / len(bins)
    ex = disposal_exit(m, (cx, cy))
    if not ex:
        log("disposals: no place for the exit at the hull")
        return
    root, throw = ex
    drv, wall = nb(root, throw), nb(nb(root, throw), throw)
    for p in (root, drv):
        t = m.get(*p)
        t.area = dmm.Atom("/area/maintenance/disposal")
    m.get(*drv).objs.append(dmm.Atom("/obj/machinery/mass_driver", [("dir", str(throw)), ("id", '"trashdriver"')]))
    m.set(wall[0], wall[1], dmm.Tile([dmm.Atom("/obj/machinery/door/poddoor", [("id", '"trashdriver"'),
                                                                               ("name", '"Disposal Exit Vent"')])],
                                     dmm.Atom("/turf/open/floor/plating"), dmm.Atom("/area/maintenance/disposal")))
    # the driver's button on a side wall of the outlet tile
    for s in CARD:
        if s in (throw, OPP[throw]) or not m.get(*nb(root, s)).tpath.startswith("/turf/closed"):
            continue
        dd, px, py = kit.MOUNT["firealarm"][s]
        vs = [("id", '"trashdriver"'), ("name", '"Disposal Exit Vent"')] + \
            ([("pixel_x", str(px))] if px else []) + ([("pixel_y", str(py))] if py else [])
        m.get(*root).objs.append(dmm.Atom("/obj/machinery/button/massdriver", vs))
        break
    # the tree: flow runs from each bin to the root; sides[p] = the sides a pipe on p joins, out[p] = where it sends
    sides, out = {root: set()}, {}

    early = set()       # the trunk's first tiles from the exit stay straight: every bin's flow passes them (the mail)

    def can_branch(j, d):
        if j in early:
            return False
        if j == root:
            return not sides[root]
        s = sides[j]
        if len(s) != 2 or d in s:
            return False
        o = out[j]
        return OPP[o] in s | {d}

    def cost(q, p, d):
        t = m.get(*q)
        if t is None or t.tpath.startswith("/turf/open/space") or is_window(t) or q in local or q in (drv, wall):
            return None
        if t.has("/obj/machinery/disposal/bin") and q not in left:
            return None
        c = 1.0
        if t.tpath.startswith("/turf/closed"):
            c += 4.0
        if t.has("/obj/machinery/door"):
            c += 1.0
        if kit.dense(t.objs):
            c += 0.5
        if any(solid(m.get(*nb(q, dd))) for dd in CARD):
            c -= 0.25
        return c
    left = set(bins)
    reached = []
    while left:
        dist, prev, heap = {}, {}, []
        for j in sides:
            dist[(j, 0)] = 0
            heapq.heappush(heap, (0, j, 0))
        found = None
        while heap:
            c, p, din = heapq.heappop(heap)
            if dist.get((p, din), 1e9) < c:
                continue
            if p in left and din:
                found = (p, din)
                break
            for d in CARD:
                if din == 0 and not can_branch(p, d):
                    continue
                if din and p in left:
                    continue
                q = nb(p, d)
                if q in sides:
                    continue
                st = cost(q, p, d)
                if st is None:
                    continue
                if din and d != din:
                    st += 2.5
                nc = c + st
                if nc < dist.get((q, d), 1e9):
                    dist[(q, d)] = nc
                    prev[(q, d)] = (p, din)
                    heapq.heappush(heap, (nc, q, d))
        if not found:
            break
        path, node = [found[0]], found
        while node in prev:
            node = prev[node]
            path.append(node[0])
        path.reverse()      # path[0] is on the tree, path[-1] the bin
        for a, b in zip(path, path[1:]):
            d = next(dd for dd in CARD if nb(a, dd) == b)
            sides.setdefault(a, set()).add(d)
            sides.setdefault(b, set()).add(OPP[d])
            out[b] = OPP[d]
        left.discard(found[0])
        reached.append(found[0])
        if len(reached) == 1:
            early.update(path[1:4])
    # the atoms
    for p, s in sides.items():
        t = m.get(*p)
        if p == root:
            t.objs.insert(0, dmm.Atom.parse(D.trunk_atom(next(iter(s)))))
            t.objs.append(dmm.Atom("/obj/structure/disposaloutlet", [("dir", str(throw))] if throw != 2 else []))
        elif p in bins:
            t.objs.insert(0, dmm.Atom.parse(D.trunk_atom(out[p])))
        elif len(s) == 2:
            mk = 0
            for d in s:
                mk |= d
            t.objs.insert(0, dmm.Atom.parse(D.segment_atom(mk)))
        else:
            o = out[p]
            branch = next(d for d in s if d not in (o, OPP[o]))
            t.objs.insert(0, dmm.Atom.parse(D.junction_atom(o, branch)))
    # the mail: a wrap sorting junction on the trunk near the exit sends every wrapped parcel down a branch to a
    # delivery chute in the delivery office; trash goes on (Cargo review 3: all mail was fired into space)
    mail_note = "no mail line"
    office = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath == "/area/quartermaster/sorting" and is_floor(t)
              and not is_window(t) and not kit.dense(t.objs) and not t.has("/obj/machinery/door")
              and not t.has("/obj/machinery/disposal") and (x, y) not in sides]
    doors_ = {(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/door")}
    chutes = [(p, d) for p in office for d in CARD if m.get(*nb(p, d)).tpath.startswith("/turf/closed")
              and not any(abs(p[0] - q[0]) + abs(p[1] - q[1]) <= 1 for q in doors_)]
    # trunk tiles in flow order back from the exit: the first straight ones carry every bin's trash
    trunk, p = [], root
    for _ in range(40):
        ins = [nb(p, d) for d in sides.get(p, ()) if out.get(nb(p, d)) == OPP[d]]
        if len(ins) != 1:
            break
        p = ins[0]
        trunk.append(p)
    log("disposals: mail search: %d trunk tiles, %d chute spots" % (len(trunk), len(chutes)))
    for j in trunk:
        s = sides[j]
        o = out[j]
        if len(s) != 2 or OPP[o] not in s or not chutes:
            continue
        for b in (D.CW[o], D.CCW[o]):
            first = nb(j, b)
            if first in sides or cost(first, j, b) is None:
                continue
            # a path from the branch's first tile to a chute, not through the tree
            dist_, prev_, heap_ = {first: 0}, {}, [(0, first)]
            goal = {c for c, _ in chutes}
            got = None
            while heap_:
                c_, q = heapq.heappop(heap_)
                if c_ > dist_.get(q, 1e9):
                    continue
                if q in goal:
                    got = q
                    break
                for d in CARD:
                    n2 = nb(q, d)
                    if n2 in sides or n2 == j:
                        continue
                    st = cost(n2, q, d)
                    if st is None:
                        continue
                    if c_ + st < dist_.get(n2, 1e9):
                        dist_[n2] = c_ + st
                        prev_[n2] = q
                        heapq.heappush(heap_, (c_ + st, n2))
            if not got:
                continue
            path = [got]
            while path[-1] != first:
                path.append(prev_[path[-1]])
            path.reverse()
            path = [j] + path
            t = m.get(*j)
            t.objs = [ob for ob in t.objs if not ob.path.startswith(D.PIPE)]
            t.objs.insert(0, dmm.Atom("/obj/structure/disposalpipe/sorting/wrap" + ("" if b == D.CW[o] else "/flip"),
                                      [("dir", str(o))] if o != 2 else []))
            for a_, b_, c3 in zip(path, path[1:], path[2:]):
                d_in = next(d for d in CARD if nb(b_, d) == a_)
                d_out = next(d for d in CARD if nb(b_, d) == c3)
                m.get(*b_).objs.insert(0, dmm.Atom.parse(D.segment_atom(d_in | d_out)))
            last, before = path[-1], path[-2]
            back = next(d for d in CARD if nb(last, d) == before)
            wall_d = next(d for c, d in chutes if c == last)
            m.get(*last).objs.insert(0, dmm.Atom.parse(D.trunk_atom(back)))
            m.get(*last).objs.append(dmm.Atom("/obj/machinery/disposal/deliveryChute", [("dir", str(OPP[wall_d]))]))
            mail_note = "mail: wrap junction at %d,%d, %d-tile line to the delivery chute at %d,%d" % (
                j[0], j[1], len(path) - 1, last[0], last[1])
            break
        if mail_note != "no mail line":
            break
    log("disposals: %s" % mail_note)
    # every bin's trash must reach the exit
    bad = []
    for b in reached:
        fl = D.flow(m, b, out[b])
        if fl[-1][0] != root:
            bad.append("%d,%d->%d,%d" % (b[0], b[1], fl[-1][0][0], fl[-1][0][1]))
    log("disposals: exit at %d,%d throwing %d, %d bins on %d pipe tiles%s%s" % (
        root[0], root[1], throw, len(reached), len(sides) - len(reached) - 1,
        (", UNREACHED %s" % " ".join("%d,%d" % p for p in sorted(left))) if left else "",
        (", WRONG END %s" % " ".join(bad)) if bad else ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--name", default="station_v6", help="data/mapforge/<name>.dmm (a trial copy while one boots)")
    a = ap.parse_args()
    lines = []

    def log(s):
        print(s)
        lines.append(s)
    m, owner = assemble(log)
    room_areas = maint_rooms(m, log)
    solar_terms = solars(m, log)
    docks(m, log)
    layout(m, log)
    glaze(m, log)
    shared(m, log, room_areas)
    polish(m, log)
    plazas(m, log)
    details(m, log)
    fixtures(m, log)
    power(m, log, solar_terms)
    air(m, log)
    bins(m, log)
    disposals(m, log)
    out = os.path.join(DATA, a.name + ".dmm")
    dmm.write(m, out)
    log("wrote %s" % os.path.relpath(out, ROOT))
    if not a.no_render:
        from forge import render
        png = os.path.join(ROOT, "data", "previews", "mapforge", a.name + ".png")
        render.render(out, png, z=1, scale=0.5)
        log("picture %s" % os.path.relpath(png, ROOT))


if __name__ == "__main__":
    main()
