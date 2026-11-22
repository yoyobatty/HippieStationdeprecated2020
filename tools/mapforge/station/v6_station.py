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
    ((38, 60, 49, 78), "Abandoned Garden", "/area/hydroponics/garden/abandoned", "/turf/open/floor/plasteel", dict(
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
    # Emergency Storage (114, 35, 118, 39) went to atmos' 2026-11-22 refit
    ((62, 58, 67, 65), "Abandoned Clinic", "/area/medical/abandoned", "/turf/open/floor/plasteel/white", dict(
        wall=[["/obj/structure/bed", "/obj/item/bedsheet/medical"], ["/obj/machinery/iv_drip"],
              ["/obj/structure/table", "/obj/item/storage/firstaid/regular", "/obj/item/healthanalyzer"],
              ["/obj/structure/closet/crate/medical"], ["/obj/structure/bed/roller"]],
        island=None, scatter=["/obj/effect/decal/cleanable/blood/old", "/obj/effect/decal/cleanable/dirt"])),
]


def maint_rooms(m, log, skip=()):
    import random
    rnd = random.Random(21)
    for (x0, y0, x1, y1), name, area, floor, th in MAINT_ROOMS:
        if area in skip:
            continue
        # each room its own seed: one shared stream let skipping one room reshape every room after it
        rnd = random.Random("maint|%s" % name)
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
                # a worn tile here and there (stock abandoned rooms are never one clean floor); clumps of bare
                # plating read generated to the discriminator (disc_rooms 2026-11-22: the garden 99% red)
                bare = rnd.random() < 0.06
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
        spots = []
        if isl in ("soil", "reading", "lab", "table"):
            # rows along the room's long side, two-tile aisles between, a crossing gap every fifth tile: stock
            # abandoned rooms are full (room_twin 2026-11-22: furniture 0.10 per tile against the stock 0.35-0.41)
            horiz = (x1 - x0) >= (y1 - y0)
            for p in sorted(core):
                along, across = (p[0] - x0, p[1] - y0) if horiz else (p[1] - y0, p[0] - x0)
                if across % 3 == 2 and along % 5 != 0:
                    spots.append(p)
        else:
            # islands in loose clusters, each with a clear tile all round it (not a grid)
            for p in sorted(core, key=lambda q: rnd.random()):
                if len(spots) >= max(1, len(core) // 10):
                    break
                if all(max(abs(p[0] - q[0]), abs(p[1] - q[1])) >= 3 for q in spots):
                    spots.append(p)
        for p in spots:
            if isl:
                t = m.get(*p)
                if isl == "soil":
                    t.objs.append(dmm.Atom("/obj/machinery/hydroponics/constructable"))
                elif isl == "poker":
                    t.objs += [dmm.Atom("/obj/structure/table/wood/poker"), dmm.Atom("/obj/item/toy/cards/deck")]
                    for d, cd in ((4, 8), (8, 4)):
                        q = nb(p, d)
                        if q in core:
                            m.get(*q).objs.append(dmm.Atom("/obj/structure/chair/wood", [("dir", str(cd))]))
                elif isl == "reading":
                    t.objs.append(dmm.Atom("/obj/structure/bookcase/random"))
                elif isl in ("table", "lab"):
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
    return [a for _, _, a, _, _ in MAINT_ROOMS if a not in skip]


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


def room_budgets(m):
    """tile -> [room's left, per stat] for the loose items and grime details adds: a room may hold up to the most any
    stock room of its type holds per tile (forge/room_stats "items", "grime"); rooms with no stock band are open (the
    gate 2026-11-22: litter put grime in tech storage, 0.03 against the stock 0.00-0.01, and crate stocking took the
    warehouse's items to 0.50 against 0.36)."""
    from forge import room_stats as RS, corpus
    out = {}
    for g in regions(m):
        a = m.get(*next(iter(g))).apath
        kind = RS.type_of(a) if not a.startswith(("/area/hallway", "/area/maintenance")) else None
        peers = RS.peers(kind) if kind else []
        if len(peers) < 3:
            continue
        n = len(g)
        items = sum(1 for p in g for o in m.get(*p).objs if o.path.startswith("/obj/item") and not corpus.mounted(o))
        grime = sum(1 for p in g for o in m.get(*p).objs if o.path.startswith("/obj/effect/decal/cleanable"))
        left = {"items": int(max(p.stats["items"] for p in peers) * n) - items,
                "grime": int(max(p.stats["grime"] for p in peers) * n) - grime}
        for p in g:
            out[p] = left
    return out


def details(m, log):
    import random
    rnd = random.Random(1121)
    added = {"items": 0, "grime": 0, "starts": 0, "cameras": 0}
    floors = [(x, y) for (x, y, z), t in m.tiles.items() if is_floor(t) and not is_window(t)
              and not t.apath.startswith(("/area/space", "/area/solar", "/area/shuttle"))]
    budget = room_budgets(m)
    OPEN = {"items": 10 ** 9, "grime": 10 ** 9}
    for p in floors:
        t = m.get(*p)
        if t.has("/obj/machinery/door"):
            continue
        # per tile: one shared stream let any change elsewhere move every room's items and litter (the gate 2026-11-22)
        rnd = random.Random("detail|%d,%d" % p)
        tables = t.has("/obj/structure/table")
        items = sum(1 for o in t.objs if o.path.startswith("/obj/item"))
        if tables and items == 0 and not t.has("/obj/machinery") and \
                not t.apath.startswith(("/area/crew_quarters/kitchen", "/area/crew_quarters/bar")):
            pool = next(pl for pre, pl in TABLE_ITEMS if t.apath.startswith(pre))
            left = budget.get(p, OPEN)
            for o in rnd.sample(pool, min(rnd.choice((1, 2, 2)), max(0, left["items"]))):
                t.objs.append(dmm.Atom(o, [("pixel_x", str(rnd.randint(-6, 6))), ("pixel_y", str(rnd.randint(-4, 6)))]))
                added["items"] += 1
                left["items"] -= 1
        elif not kit.dense(t.objs) and t.apath.startswith(LITTER_AREAS) and not t.objs:
            r = rnd.random()
            maint = t.apath.startswith("/area/maintenance")
            # nothing dropped in a one-tile corridor (the AI sat bridge): walls on both sides
            if (solid(m.get(*nb(p, 1))) and solid(m.get(*nb(p, 2)))) or (solid(m.get(*nb(p, 4))) and solid(m.get(*nb(p, 8)))):
                continue
            left = budget.get(p, OPEN)
            if r < (0.06 if maint else 0.045):
                if left["items"] > 0:
                    t.objs.append(dmm.Atom(rnd.choice(FLOOR_LITTER)))
                    added["items"] += 1
                    left["items"] -= 1
            elif r < (0.15 if maint else 0.065):
                if left["grime"] > 0:
                    t.objs.insert(0, dmm.Atom("/obj/effect/decal/cleanable/dirt"))
                    added["grime"] += 1
                    left["grime"] -= 1
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
        rnd = random.Random("stock|%d,%d" % p)
        left = budget.get(p, OPEN)
        for o in rnd.sample(pool, max(0, min(len(pool), rnd.choice((2, 3, 3)), left["items"]))):
            t.objs.append(dmm.Atom(o))
            added["items"] += 1
            left["items"] -= 1
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


def m_one(o):
    """A one-tile map holding just o at (0, 0), for hung() on a single object."""
    class _M:
        def get(self, x, y):
            return dmm.Tile([o], dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom("/area/space"))
    return _M()


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
        # a wall between this room and maint floor, not beside a corner, not hung on either face; failing that, one
        # whose only obstacle is a piece hung on the room's face, which moves to another bare face of the room (the
        # gate 2026-11-22: the shrunk law office hung a camera, a light and an alarm on every face toward maint)
        opts, moves = [], []
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
                if hung(m, beyond):
                    continue
                if hung(m, p):
                    moves.append((p, w, d))
                    continue
                opts.append((p, w, d))
        if not opts and moves:
            from station.v6_tidy import turned
            bare = [(q, dd) for q, dd in faces_of(m, g) if not hung(m, q) and not kit.dense(m.get(*q).objs)
                    and not m.get(*nb(q, dd)).objs]
            for p, w, d in sorted(moves):
                ps = [o for o in m.get(*p).objs if hung(m_one(o), (0, 0))]
                dest = [f for f in bare if f[0] != p and nb(*f) != w]
                if len(dest) < len(ps):
                    continue
                for o in ps:
                    q, dd = dest.pop(0)
                    m.get(*p).objs.remove(o)
                    m.get(*q).objs.append(turned(o, None, DELTA[dd]))
                    dest = [f for f in dest if f[0] != q]
                opts = [(p, w, d)]
                break
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
        rnd = random.Random("island|%s|%d,%d" % ((t0.apath,) + min(g)))     # per room (see fixtures)
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
        trim_dock(m, name, log)


# a dock box deeper than any stock hall is wide (size_budget: stock hall floor runs 7+ wide at most 19%, v6 23% with
# both 7-row dock boxes holding 119 of the 322 wide tiles): the row named here, away from the shuttle's airlocks and
# the lobby, goes back to the hull. The hull moves in one row (its tiles copied, windows and all), and the old hull
# row turns to space where that leaves no wall joined only by a corner.
DOCK_TRIM = {"escape": (13, -1), "arrivals": (89, 1)}     # the row cut, and which way is outside (y)
STOCK_HALL_MAX = 6


def trim_dock(m, name, log):
    x0, y0, x1, y1 = DOCK_BOXES[name]
    row, out = DOCK_TRIM[name]
    cols = [x for x in range(x0 - 1, x1 + 2) if is_floor(m.get(x, row)) or (x in (x0 - 1, x1 + 1) and
                                                                           solid(m.get(x, row)))]
    floor_cols = [x for x in cols if is_floor(m.get(x, row)) and m.get(x, row).apath.startswith("/area/hallway")]
    if y1 - y0 + 1 <= STOCK_HALL_MAX or not floor_cols or any(m.get(x, row).has("/obj/machinery/door") or
                                                                  m.get(x, row).has("/obj/docking_port") for x in cols):
        return
    hull_y, space_y = row + out, row + 2 * out
    moved = []
    for x in range(min(floor_cols), max(floor_cols) + 1):
        h = m.get(x, hull_y)
        if h is None or not solid(h):
            return          # the row isn't against the hull: leave it
        m.set(x, row, dmm.Tile([dmm.Atom(o.path, list(o.vars)) for o in h.objs], dmm.Atom(h.tpath, list(h.turf.vars)),
                               m.get(x, row).area.copy()))
        moved.append(x)
    spaced = 0
    for x in moved:
        s, h = m.get(x, space_y), m.get(x, hull_y)
        sides = [m.get(x - 1, hull_y), m.get(x + 1, hull_y)]
        if s is not None and s.tpath.startswith("/turf/open/space") and all(
                (xx in moved) or (t is not None and t.tpath.startswith("/turf/open/space"))
                for xx, t in ((x - 1, sides[0]), (x + 1, sides[1]))):
            m.set(x, hull_y, dmm.Tile([], dmm.Atom(s.tpath, list(s.turf.vars)), s.area.copy()))
            spaced += 1
    log("docks: %s box trimmed to %d rows: row %d is hull now (%d tiles), %d old hull tiles back to space" % (
        name, y1 - y0, row, len(moved), spaced))


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


def below_pieces(m, g, area, rnd):
    """A poster when the room hangs fewer pieces per wall face than every stock room of its type (forge/room_stats
    "pieces"); a room with no stock band keeps the old 70% chance. A coin flip had dropped the HoP office's poster
    and put it below its band (the gate 2026-11-22)."""
    from forge import room_stats as RS
    kind = RS.type_of(area)
    peers = RS.peers(kind) if kind else []
    if len(peers) < 3:
        return rnd.random() < 0.7
    pieces, faces = RS.map_pieces(m, g)
    return pieces / float(max(1, faces)) < min(p.stats["pieces"] for p in peers)


def _band_dist(v, lo, hi):
    return max(0.0, (lo - v) / max(hi - lo, 1e-6), (v - hi) / max(hi - lo, 1e-6))


def room_pieces(m, g, area):
    """(pieces, wall faces, stock min, stock max) of a region, or None when its type has no stock band."""
    from forge import room_stats as RS
    kind = RS.type_of(area)
    peers = RS.peers(kind) if kind else []
    if len(peers) < 3:
        return None
    pieces, faces = RS.map_pieces(m, g)
    return pieces, max(1, faces), min(p.stats["pieces"] for p in peers), max(p.stats["pieces"] for p in peers)


def bin_gives_way(m, g, area, used_w=frozenset(), base=None):
    """A face held only by a disposal bin, freed for a wall piece when the room's summed distance from its stock
    bands for pieces and dense goes down without the bin (the gate 2026-11-22: the captain's office, whose bin took
    the face its poster had, pieces 0.33 against the stock 0.40-0.66). Returns the freed (tile, side) or None."""
    from forge import room_stats as RS
    kind = RS.type_of(area)
    peers = RS.peers(kind) if kind else []
    if len(peers) < 3:
        return None
    plo, phi = min(p.stats["pieces"] for p in peers), max(p.stats["pieces"] for p in peers)
    dlo, dhi = min(p.stats["dense"] for p in peers), max(p.stats["dense"] for p in peers)
    pieces, nfaces = RS.map_pieces(m, g)
    faces = [(p, d) for p in g for d in CARD if m.get(*nb(p, d)) is not None and solid(m.get(*nb(p, d)))
             and not m.get(*nb(p, d)).has("/obj/machinery/door")]
    dense = sum(1 for p in g if kit.dense(m.get(*p).objs))
    nf, n = float(max(1, nfaces)), float(len(g))
    now = _band_dist(pieces / nf, plo, phi) + _band_dist(dense / n, dlo, dhi)
    sp, sd = _band_dist((pieces + 1) / nf, plo, phi), _band_dist((dense - 1) / n, dlo, dhi)
    if sp + sd >= now:
        return None
    # and neither number further from its band than the accepted build has it (station/v6_gate.py's own rule: the
    # cargo QM's office traded its bin for a poster and fell under its accepted dense)
    if base is not None and (sp > base.get("pieces", 0.0) + 1e-6 or sd > max(base.get("dense", 0.0),
                                                                           _band_dist(dense / n, dlo, dhi)) + 1e-6):
        return None
    under = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe", "/obj/effect")
    for p, d in faces:
        t = m.get(*p)
        if nb(p, d) in used_w or m.get(*nb(p, d)).has("/obj/machinery/door") or not m.get(*nb(p, d)).tpath.startswith("/turf/closed"):
            continue
        if t.has("/obj/machinery/disposal/bin") and not hung(m, p) and all(
                o.path.startswith(under + ("/obj/machinery/disposal/bin", "/obj/item")) for o in t.objs):
            t.objs = [o for o in t.objs if not o.path.startswith("/obj/machinery/disposal/bin")]
            return (p, d)
    return None


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
    from station.v6_tidy import accepted_areas
    accepted = accepted_areas()        # rooms of the accepted build: the over-band guard is for copied rooms
    for g in regions(m):
        t0 = m.get(*next(iter(g)))
        a = t0.apath
        if len(g) < 12 or a in ABANDONED or a.startswith(("/area/hallway", "/area/maintenance", "/area/space", "/area/solar", "/area/shuttle",
                                        "/area/engine/supermatter", "/area/ai_monitored/turret_protected/ai",
                                        "/area/science/mixing/chamber", "/area/security/prison/cell")):
            continue
        def objs_in(pre):
            return any(m.get(*p).has(pre) for p in g)
        # a seed of the room's own (its area and corner): one shared stream let any change elsewhere reshuffle every
        # room's pieces (the gate 2026-11-22: the bridge's intercom moved onto its only bin spot)
        rnd = random.Random("%s|%d,%d" % ((a,) + min(g)))
        faces = [(p, d) for p, d in faces_of(m, g) if not hung(m, p) and nb(p, d) not in used_w
                 and not any(o.path.startswith(("/obj/structure", "/obj/machinery")) for o in m.get(*p).objs)]
        rnd.shuffle(faces)
        want = []
        if len(g) >= 15 and not objs_in("/obj/item/radio/intercom"):
            want.append("intercom")
        if a.startswith(NEWS_AREAS) and not objs_in("/obj/machinery/newscaster"):
            want.append("newscaster")
        # posters while the room is under its stock band for wall pieces (two at most); a room with no band keeps
        # the old rule (20+ tiles, 70%)
        from forge import room_stats as RS
        kind = RS.type_of(a)
        banded = bool(kind) and len(RS.peers(kind)) >= 3
        if banded:
            want += ["poster", "poster"]
        elif len(g) >= 20 and not objs_in("/obj/structure/sign/poster") and rnd.random() < 0.7:
            want.append("poster")
        for kind in want:
            if not faces:
                break
            if kind == "poster" and banded and not below_pieces(m, g, a, rnd):
                continue
            rp = room_pieces(m, g, a) if a not in accepted else None
            if rp and (rp[0] + 1) / float(rp[1]) > rp[3]:
                break       # never past the most any stock room of the type hangs (the gateway went to 0.59 of 0.43)
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
            "/area/engine/gravity_generator", "/area/engine/atmos", "/area/crew_quarters/toilet", "/area/crew_quarters/dorms",
            "/area/crew_quarters/heads/captain/private", "/area/maintenance", "/area/storage", "/area/tcommsat",
            "/area/medical/morgue", "/area/science/server", "/area/security/detectives_office")
INNER_GLASS = ("/area/medical", "/area/science", "/area/hydroponics", "/area/crew_quarters/kitchen",
               "/area/crew_quarters/bar", "/area/crew_quarters/cafeteria", "/area/library", "/area/chapel/main",
               "/area/quartermaster", "/area/engine/break_room", "/area/crew_quarters/fitness",
               "/area/crew_quarters/lounge", "/area/lawoffice", "/area/janitor", "/area/hallway/secondary/exit",
               "/area/crew_quarters/theatre", "/area/security/main", "/area/security/office")


PA_FURN = ("/obj/structure/chair", "/obj/structure/table", "/obj/structure/bed", "/obj/structure/displaycase",
           "/obj/structure/statue", "/obj/structure/filingcabinet", "/obj/structure/easel", "/obj/structure/flora",
           "/obj/item/twohanded/required/kirbyplants", "/obj/machinery/disposal", "/obj/structure/rack",
           "/obj/machinery/computer", "/obj/structure/closet", "/obj/machinery/vending", "/obj/structure/bookcase",
           "/obj/structure/dresser", "/obj/machinery/suit_storage_unit", "/obj/structure/reagent_dispensers",
           "/obj/machinery/washing_machine")      # studies/piece_audit.py FURN: what a piece may not hang over


def parse_group(area):
    from forge import parse
    return parse.ST.group_of(area)


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

    def wall_run(p):
        """A plain wall tile, or one with a piece hung on it: a run of wall goes on past a piece (it only can't be a
        pane itself); the hung pieces had cut 217 of the 276 inner candidates into runs too short to glaze."""
        t = m.get(*p)
        return t is not None and t.tpath.startswith("/turf/closed/wall") and not t.objs

    def ok_area(t, inner):
        if t is None or not is_floor(t) or t.has("/obj/machinery/door") or is_window(t):
            return False
        # maint hull takes glass, the solar corridors too (stock solar corridors: 0.36-0.58 of their hull walls are
        # glass, Meta 0.36; v6 had none, 2026-11-22)
        if t.apath.startswith(NO_GLASS) and not (not inner and t.apath.startswith("/area/maintenance/")):
            return False
        # no hall windows into Engineering: radiation and break-ins (Engineering review 5)
        return (not inner) or not t.apath.startswith(("/area/crew_quarters/heads", "/area/security/checkpoint", "/area/engine"))

    def cands(kind):
        out = {}
        for (x, y, z), t in m.tiles.items():
            p = (x, y)
            if not wall_run(p):
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
                    room = [s for s in (a, b) if (ok_area(s, True) or (s.apath in under_cap and ok_area(s, False)))
                            and not s.apath.startswith("/area/hallway")]
                    if len(hall) == 1 and len(room) == 1:
                        out[p] = d
                    # or two rooms of the open departments side by side (a lab looking into the next lab)
                    elif all(ok_area(s, True) for s in (a, b)) and (all(s.apath.startswith(INNER_GLASS) for s in (a, b)) or
                                                                   a.apath.split("/")[2] == b.apath.split("/")[2] and a.apath != b.apath):
                        out[p] = d
                    # a room under its stock glass minimum looks into a neighbour of its own department too (the
                    # gate 2026-11-22: the room budget's removed maint rooms took 62 inner panes with them)
                    # maint looking into maint (a maint room onto its run): stock 0.07-0.21 of those walls are glass,
                    # v6 0.02 (the gate 2026-11-22)
                    elif all(is_floor(s) and s.apath.startswith("/area/maintenance") and not s.apath.startswith(
                            "/area/maintenance/solars") and not s.has("/obj/machinery/door") for s in (a, b)):
                        out[p] = d
                    # two rooms of one department under their caps look into each other (stock: 0.26-0.32 of the walls
                    # between rooms of one department are glass, v6 0.16 and its inner glass 0.14 of the human
                    # 0.16-0.23; the gate 2026-11-22)
                    elif all(ok_area(s, False) for s in (a, b)) and a.apath != b.apath and                             (a.apath in under_cap and b.apath in under_cap) and                             parse_group(a.apath) == parse_group(b.apath) and parse_group(a.apath) not in (None, "maint", "hall"):
                        out[p] = d
        return out
    # a room's glass stays within the most any stock room of its type has (forge/room_stats "glass": window share of
    # the room's wall tiles); the gate 2026-11-22: the meeting room grew two columns and took 4 hall panes, the
    # library lounge's glass 0.16 against the stock 0.03-0.08
    from forge import room_stats as RS
    walls_of, glass_of, cap, tiles_of = {}, {}, {}, {}
    for (x, y, z), t in m.tiles.items():
        if not is_floor(t) or is_window(t) or t.apath.startswith(("/area/hallway", "/area/space")):
            continue
        tiles_of.setdefault(t.apath, []).append((x, y))
        for d in CARD:
            q = nb((x, y), d)
            tq = m.get(*q)
            if tq is not None and (tq.tpath.startswith("/turf/closed") or is_window(tq)) and not tq.has("/obj/machinery/door"):
                walls_of.setdefault(t.apath, set()).add(q)
    # the cap is the stock maximum, or the accepted build's own glass where that was higher (the gate's rule: no
    # worse than accepted; capping those rooms at the stock maximum cost v6 18 inner panes, 0.136 against 0.146)
    from forge import parse as _parse
    from station.v6_gate import ACCEPTED
    acc_glass = {r.area: r.stats["glass"] for r in RS.rooms(_parse.load(ACCEPTED))}
    for a, ws in walls_of.items():
        glass_of[a] = sum(1 for q in ws if is_window(m.get(*q)))
        kind_ = RS.type_of(a)
        peers = RS.peers(kind_) if kind_ else []
        cap[a] = max([p.stats["glass"] for p in peers] + [acc_glass.get(a, 0.0)]) if len(peers) >= 3 else None

    # a room under the least glass any stock room of its type has gets hall windows too, whatever its kind (the gate
    # 2026-11-22: inner glass 0.13 of v6's inner walls against the accepted 0.15 and the human 0.16-0.23; the HoP's
    # office, medbay, cargo's office, the courtroom and security were under their stock bands)
    below_lo = set()
    for a, ws in walls_of.items():
        kind_ = RS.type_of(a)
        peers = RS.peers(kind_) if kind_ else []
        if len(peers) >= 3 and glass_of[a] / float(len(ws)) < min(p.stats["glass"] for p in peers):
            below_lo.add(a)

    # any typed room under its cap may take hall windows (the stock maps' inner glass is 0.16-0.23 of their inner
    # walls, v6's 0.14); glass_ok holds each to its cap
    under_cap = {a for a in walls_of if cap.get(a) is not None and glass_of[a] / float(len(walls_of[a])) < cap[a]}
    # a room under its stock band for wall pieces keeps its bare walls for them (the gate 2026-11-22: the library and
    # the courtroom lost their posters' faces to new panes)
    # (judged on the accepted build: one piece fewer would put it under its band; at this point of the build no
    # room has its fixtures yet)
    poor = set()
    for r in RS.rooms(_parse.load(ACCEPTED)):
        kind_ = RS.type_of(r.area)
        peers = RS.peers(kind_) if kind_ else []
        if len(peers) >= 3:
            pc, fc = r.stats["pieces"], 0
            sm_a = _parse.load(ACCEPTED)
            fc = sum(1 for p in r.tiles for s_, (dx, dy) in _parse.SIDE.items() if sm_a.cls.get((p[0] + dx, p[1] + dy)) == "W")
            if (pc * fc - 1) / float(max(1, fc)) < min(p.stats["pieces"] for p in peers):
                poor.add(r.area)

    def glass_ok(w):
        areas = {m.get(*nb(w, d)).apath for d in CARD if m.get(*nb(w, d)) is not None and is_floor(m.get(*nb(w, d)))
                 and not is_window(m.get(*nb(w, d))) and m.get(*nb(w, d)).apath in walls_of}
        def face_free(a):
            # the room's tiles against this wall all hold furniture: no piece could hang there anyway
            ts = [nb(w, d) for d in CARD if m.get(*nb(w, d)) is not None and m.get(*nb(w, d)).apath == a]
            return a not in poor or all(kit.dense(m.get(*q).objs) or any(o.path.startswith(PA_FURN) for o in m.get(*q).objs)
                                        for q in ts)
        return all((cap.get(a) is None or (glass_of[a] + 1) / float(len(walls_of[a])) <= cap[a] + 1e-9) and face_free(a)
                   for a in areas), areas
    made = {"hull": 0, "inner": 0}
    why = {"cands": 0, "short runs": 0, "capped": 0}
    for kind in ("hull", "inner"):
        c = cands(kind)
        if kind == "inner":
            why["cands"] = len(c)
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
                if kind == "inner":
                    why["short runs"] += len(run)
                continue
            # pairs of panes with a wall between, never at a run's ends (corners and door jambs stay wall)
            for i, w in enumerate(run[1:-1]):
                maint = kind == "hull" and any(m.get(*nb(w, dd)) is not None and m.get(*nb(w, dd)).apath.startswith(
                    "/area/maintenance") for dd in CARD)
                # maint hull every other tile (stock maint hull is 0.24-0.59 glass, Meta 0.24; one in four left v6 at
                # 0.11 and the station's hull glass under the human range, the gate 2026-11-22)
                # between two rooms every interior tile (stock: 0.26-0.32 of the walls between rooms of one
                # department are glass, v6 0.16); a hall wall keeps two in three (stock and v6 both 0.28)
                hall_side = any(m.get(*nb(w, dd)) is not None and m.get(*nb(w, dd)).apath.startswith("/area/hallway")
                                for dd in CARD)
                maint_in = kind == "inner" and all(m.get(*nb(w, dd)) is None or not is_floor(m.get(*nb(w, dd))) or
                                                   m.get(*nb(w, dd)).apath.startswith("/area/maintenance") for dd in CARD)
                pat = ((i % 2) == 1) if maint else ((i % 4) != 3 if kind == "hull" else
                                                    ((i % 3) == 1 if maint_in else
                                                     ((i % 3) in (0, 1) if hall_side else True)))
                pat = pat and w not in hungw       # a wall a piece hangs on stays wall
                ok_g, areas = glass_ok(w) if pat else (False, ())
                if pat and not ok_g and kind == "inner":
                    why["capped"] += 1
                if pat and ok_g and not (kind == "inner" and len(run) < 3):
                    for a in areas:
                        glass_of[a] += 1
                    t = m.get(*w)
                    m.set(w[0], w[1], dmm.Tile([dmm.Atom("/obj/effect/spawner/structure/window/reinforced")],
                                               dmm.Atom("/turf/open/floor/plating"), t.area.copy() if t.area else None))
                    made[kind] += 1
    log("glaze: %d hull panes, %d hall panes (inner: %d candidate walls, %d in runs under 3, %d at their room's cap)" % (
        made["hull"], made["inner"], why["cands"], why["short runs"], why["capped"]))


# ================================================================================================= solars
# the plan's four corner docks (plan/station_plan.py DOCKS "solars *"), map tiles of the field inside its ring wall

FACE = {1: lambda o: o.num("pixel_y") >= 20, 2: lambda o: o.num("pixel_y") <= -20,
        4: lambda o: o.num("pixel_x") >= 20, 8: lambda o: o.num("pixel_x") <= -20}


def faces_wall(m, p, d):
    """A piece on floor tile p hangs on its side d (pixel offset, or a light/camera turned that way)."""
    for o in m.get(*p).objs:
        if FACE[d](o) or (o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera"))
                          and o.num("dir") in (d, 0 if d == 2 else -1)):
            return True
    return False


def close_corners(m, log):
    """Hull corners left open to space: a space tile between two walls that meet only corner to corner round a
    station floor tile (the user 2026-11-22: "2 walls don't join to form a corner"; stock maps have none) becomes
    wall, so the hull turns its corner as built hulls do."""
    def wall(c):
        t = m.get(*c)
        return t is not None and (t.tpath.startswith("/turf/closed") or is_window(t))
    done = []
    for (x, y, z), t in sorted(m.tiles.items()):
        if not t.tpath.startswith("/turf/open/space") or t.objs:
            continue
        for a, b in ((4, 1), (4, 2), (8, 1), (8, 2)):
            pa, pb = nb((x, y), a), nb((x, y), b)
            dg = nb(pa, b)
            td = m.get(*dg)
            if wall(pa) and wall(pb) and is_floor(td) and not is_window(td) and \
                    not td.apath.startswith(("/area/space", "/area/solar", "/area/shuttle")):
                m.set(x, y, dmm.Tile([], dmm.Atom("/turf/closed/wall/r_wall"), td.area.copy()))
                done.append("%d,%d" % (x, y))
                break
    log("hull corners closed: %s" % (", ".join(done) or "none"))


def open_dead_ends(m, log, back=4):
    """Maint and hall corridors that stop against a wall with no door (the user 2026-11-22: "there's a dead end
    here"; forge/walk.py: stock maps have at most 2.9 such stubs per 1000 corridor tiles, none longer than 5, v6 had
    4.2 and a 22). Each stub gets a maint door within a few tiles of its end, through one plain wall onto a hall
    (else other maint) straight across, as the stock maps end theirs; the door sits in a straight wall run, has no
    door beside it, and no piece hangs on either face of the wall it replaces."""
    def walk_t(p):
        t = m.get(*p)
        return t is not None and is_floor(t) and not is_window(t)

    def corr(p):
        t = m.get(*p)
        return walk_t(p) and t.apath.startswith(SHARED) and not t.has("/obj/machinery/door") \
            and "/solars" not in t.apath

    def ways(p):
        return [nb(p, d) for d in CARD if walk_t(nb(p, d))]
    added = []
    tips = sorted(p for (x, y, z), t in m.tiles.items() for p in [(x, y)] if corr(p))
    for p in tips:
        w = ways(p)
        if len(w) != 1 or m.get(*w[0]).has("/obj/machinery/door"):
            continue
        path, prev, cur = [p], p, w[0]
        while len(path) <= back and corr(cur):
            nn = [q for q in ways(cur) if q != prev]
            if len(nn) != 1 or any(m.get(*q).has("/obj/machinery/door") for q in ways(cur)):
                break
            path.append(cur)
            prev, cur = cur, nn[0]
        if len(path) < 2:
            continue
        best = None
        for i, a in enumerate(path):
            for d in CARD:
                q, r = nb(a, d), nb(nb(a, d), d)
                tq, tr = m.get(*q), m.get(*r)
                if tq is None or tr is None or not tq.tpath.startswith("/turf/closed") or is_window(tq) \
                        or tq.has("/obj/machinery/door") or not corr(r) or r in path:
                    continue
                side = [nb(q, e) for e in CARD if e not in (d, OPP[d])]
                if not all(m.get(*s) is not None and m.get(*s).tpath.startswith("/turf/closed") and not is_window(m.get(*s))
                           for s in side):
                    continue
                if any(m.get(*nb(r, e)).has("/obj/machinery/door") for e in CARD if m.get(*nb(r, e)) is not None):
                    continue
                if faces_wall(m, a, d) or faces_wall(m, r, OPP[d]):
                    continue
                score = (0 if tr.apath.startswith("/area/hallway") else 1, i)
                if best is None or score < best[0]:
                    best = (score, q, a)
        if best:
            q, a = best[1], best[2]
            under = [o for o in m.get(*q).objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipes",
                                                                       "/obj/structure/disposalpipe"))]
            m.set(q[0], q[1], dmm.Tile(under + [dmm.Atom("/obj/machinery/door/airlock/maintenance",
                                                           [("req_one_access_txt", '"12"')])],
                                       dmm.Atom("/turf/open/floor/plating"), m.get(*a).area.copy()))
            added.append("%d,%d (stub %d long)" % (q[0], q[1], len(path)))
    log("dead ends: %d maint doors: %s" % (len(added), ", ".join(added) or "none"))


SOLARS = {"NW": ((20, 143, 28, 151), "fore"), "NE": ((156, 147, 164, 155), "starboard"),
          "SE": ((156, 39, 164, 47), "aft"), "SW": ((20, 19, 28, 27), "port")}
# the stock areas of each corner's array and its solar maint room (Meta: /area/solar/port/fore and
# /area/maintenance/solars/port/fore, and so on round the station)
SOLAR_AREAS = {"NW": "port/fore", "NE": "starboard/fore", "SE": "starboard/aft", "SW": "port/aft"}
# the arrays' own net beyond the SMES (room tiles in maint areas): power() keeps their cable and keeps the grid a tile
# clear of them, so the solars charge each room's SMES and the SMES feeds the station, as on the stock maps
SOLAR_NET = set()


def _old_corridor(m, ex, out, field):
    """The walled plating run the canvas drew from the array's way in to the station: one tile wide, up to the first
    junction or door, and the dock-area catwalk a diagonal step on from its end (SE)."""
    corr, p, prev = [], nb(ex, out), ex
    while True:
        t = m.get(*p)
        if not is_floor(t) or t.has("/obj/machinery/door") or \
                sum(1 for d in CARD if is_floor(m.get(*nb(p, d)))) > 2 or len(corr) > 60:
            break
        corr.append(p)
        nxt = [nb(p, d) for d in CARD if is_floor(m.get(*nb(p, d))) and nb(p, d) not in (prev, ex) and nb(p, d) not in corr]
        if len(nxt) != 1:
            break
        prev, p = p, nxt[0]
    if corr:
        tip = corr[-1]
        q = [(tip[0] + dx, tip[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
        q = [c for c in q if c not in corr and is_floor(m.get(*c)) and m.get(*c).apath == "/area/hallway/secondary/entry"]
        while q:
            c = q.pop()
            t = m.get(*c)
            if c in corr or not is_floor(t) or t.has("/obj/machinery/door") or t.apath != "/area/hallway/secondary/entry" \
                    or sum(1 for d in CARD if is_floor(m.get(*nb(c, d)))) > 2:
                continue
            corr.append(c)
            q += [nb(c, d) for d in CARD]
    return [c for c in corr if c not in field]


def _clear_corridor(m, corr, keep):
    """The old run goes back to space: its floor and the walls round it, except where they close the station (a tile
    beside station floor becomes or stays wall, a door onto it becomes wall)."""
    cs = set(corr)

    def station_floor(c):
        t = m.get(*c)
        return c not in cs and c not in keep and is_floor(t) and not t.apath.startswith("/area/solar")
    walls = {(c[0] + dx, c[1] + dy) for c in corr for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - cs - keep
    for c in sorted(cs | walls):
        t = m.get(*c)
        if t is None or (c in walls and is_floor(t) and not t.has("/obj/machinery/door")):
            continue
        if any(station_floor(nb(c, d)) for d in CARD):
            if c in cs or t.has("/obj/machinery/door"):
                m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/closed/wall/r_wall"), t.area.copy()))
        else:
            m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space/nearstation")))


def _solar_room(m, corr, field_near, avoid):
    """The best spot for the corner's solar maint room: inside 3x3 or 3x4 on space against the hull, within a few tiles
    of the old run, one door straight into station maint, and on another side an airlock, a one-tile cycling
    vestibule and the outer airlock with space beyond for the catwalk. Returns a plan dict or None."""
    near = {(c[0] + dx, c[1] + dy) for c in corr for dx in range(-5, 6) for dy in range(-5, 6)}

    def space(c):
        t = m.get(*c)
        return t is not None and t.tpath.startswith("/turf/open/space") and c not in avoid
    def wall(c):
        t = m.get(*c)
        return t is not None and t.tpath.startswith("/turf/closed") and not is_window(t) and not t.has("/obj/machinery/door")
    def maint(c):
        t = m.get(*c)
        return is_floor(t) and not is_window(t) and t.apath.startswith("/area/maintenance") and \
            "/solars" not in t.apath and not t.has("/obj/machinery/door") and not kit.dense(t.objs)
    best = None
    xs, ys = [c[0] for c in near], [c[1] for c in near]
    for ix0 in range(min(xs), max(xs) + 1):
        for iy0 in range(min(ys), max(ys) + 1):
            for w, h in ((3, 3), (3, 4), (4, 3)):
                inner = [(x, y) for x in range(ix0, ix0 + w) for y in range(iy0, iy0 + h)]
                if not all(c in near and space(c) for c in inner):
                    continue
                ringt = [(x, y) for x in range(ix0 - 1, ix0 + w + 1) for y in range(iy0 - 1, iy0 + h + 1) if (x, y) not in inner]
                if not all(space(c) or wall(c) for c in ringt):
                    continue
                if any(abs(c[0] - f[0]) <= 2 and abs(c[1] - f[1]) <= 2 for c in ringt for f in field_near):
                    continue
                corners = {(ix0 - 1, iy0 - 1), (ix0 + w, iy0 - 1), (ix0 - 1, iy0 + h), (ix0 + w, iy0 + h)}
                sides = {}
                for c in ringt:
                    if c in corners:
                        continue
                    d = 8 if c[0] == ix0 - 1 else 4 if c[0] == ix0 + w else 2 if c[1] == iy0 - 1 else 1
                    sides.setdefault(d, []).append(c)
                doors = [(c, d) for d, cs in sides.items() for c in cs if wall(c) and maint(nb(c, d))]
                if not doors:
                    continue
                for out, cs in sides.items():
                    cs = sorted(cs)
                    a1 = cs[len(cs) // 2] if len(cs) % 2 else cs[len(cs) // 2 - (1 if out in (1, 4) else 0)]
                    perp = [d for d in CARD if d not in (out, OPP[out])]
                    v, a2, c0 = nb(a1, out), nb(nb(a1, out), out), nb(nb(nb(a1, out), out), out)
                    flank = [nb(q, d) for q in (v, a2) for d in perp]
                    if not (space(a1) or wall(a1)) or not all(space(q) for q in (v, a2, c0)) or \
                            not all(space(q) or wall(q) for q in flank):
                        continue
                    if any(is_floor(m.get(*nb(q, d))) for q in [v, a2] + flank for d in CARD
                           if nb(q, d) not in inner):
                        continue
                    # the way in from the inner airlock stays a straight open line (the user 2026-11-22: "SMES kind
                    # of blocks the straight line path to the airlock, it's better being on the wall ... or the
                    # corner?"): the room is three deep; the first tile inside carries the array's cable to the wall
                    # beside it, along that wall to the terminal, and the SMES stands in the back corner behind it;
                    # the console against the other side of the entry
                    t_ = nb(a1, OPP[out])
                    if nb(nb(t_, OPP[out]), OPP[out]) not in inner:
                        continue
                    wall_side = [d for d in perp if nb(t_, d) in inner and nb(nb(t_, d), d) not in inner
                                 and nb(t_, OPP[d]) in inner]
                    if not wall_side:
                        continue
                    for ds in wall_side:          # either wall: the SMES must not stand at the door
                        cabs = [nb(t_, ds)]
                        while nb(nb(nb(cabs[-1], OPP[out]), OPP[out]), OPP[out]) in inner:
                            cabs.append(nb(cabs[-1], OPP[out]))
                        term_ = nb(cabs[-1], OPP[out])
                        smes = nb(term_, OPP[out])
                        if smes not in inner:
                            continue
                        cons = [nb(t_, OPP[ds])]
                        solar = {t_, term_, cons[0]} | set(cabs)
                        fenced = solar | {nb(s, d) for s in solar for d in CARD}
                        ok_doors = [(c, d) for c, d in doors if d != out and nb(c, OPP[d]) not in fenced]
                        if not ok_doors:
                            continue
                        door, dd = min(ok_doors, key=lambda cd: (cd[0][0], cd[0][1]))
                        k = (abs(c0[0] - field_near[0][0]) + abs(c0[1] - field_near[0][1]), w * h, ix0, iy0, out)
                        if best is None or k < best[0]:
                            best = (k, dict(inner=inner, ring=ringt, door=door, door_dir=dd, out=out, a1=a1, v=v, a2=a2,
                                            c0=c0, flank=flank, entry=t_, cabs=cabs, term=term_, smes=smes, console=cons[0], fenced=fenced))
    return best[1] if best else None


def solars(m, log):
    """Each corner dock becomes a solar array as the stock maps build them: rows of panels on solar-panel plating with
    catwalk rows and a spine between them, the tracker in the middle, every tile cabled so the field is one net; an
    open catwalk across space to a solar maint room on the hull (the user 2026-11-22: "the hallway leading down to the
    solars is long and there's no staging smes room before the solars like a real map has"). The room: an SMES with its
    terminal, the array's control console, an APC, a door into station maint, and a cycling airlock pair out to the
    catwalk. The old walled run the canvas drew is taken back to space. The array's net reaches the terminal and the
    console only; the station grid reaches the SMES (power()). Returns [] (the grid joins no array directly)."""
    SOLAR_NET.clear()
    avoid = {(x, y) for (x0, y0, x1, y1) in DOCK_BOXES.values() for x in range(x0 - 6, x1 + 7) for y in range(y0 - 6, y1 + 7)}
    for key_, ((x0, y0, x1, y1), word) in sorted(SOLARS.items()):
        sub = SOLAR_AREAS[key_]
        field = [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
        ring = [(x, y) for x in range(x0 - 1, x1 + 2) for y in (y0 - 1, y1 + 1)] + \
               [(x, y) for y in range(y0, y1 + 1) for x in (x0 - 1, x1 + 1)]
        exits = [p for p in ring if is_floor(m.get(*p))]
        if len(exits) != 1:
            log("solars %s: %d ways in, skipped" % (key_, len(exits)))
            continue
        ex = exits[0]
        out = next(d for d in CARD if nb(ex, d) not in field and is_floor(m.get(*nb(ex, d))))
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        area = dmm.Atom("/area/solar/%s" % sub)
        rarea = "/area/maintenance/solars/%s" % sub
        corr = _old_corridor(m, ex, out, set(field))
        lattice = lambda: dmm.Tile([dmm.Atom("/obj/structure/lattice")], dmm.Atom("/turf/open/space/basic"),  # noqa: E731
                                   dmm.Atom("/area/space/nearstation"))
        for p in ring:
            m.set(p[0], p[1], lattice())
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
        _clear_corridor(m, corr, set(field) | set(ring))
        plan_ = _solar_room(m, corr or [ex], [ex], avoid | set(field) | set(ring))
        if plan_ is None:
            log("solars %s: NO ROOM SPOT near the old run (array left without a way in)" % key_)
            continue
        P = plan_
        ra = dmm.Atom(rarea)
        for c in P["inner"]:
            m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plating"), ra.copy()))
        for c in P["ring"] + P["flank"]:
            t = m.get(*c)
            if not t.tpath.startswith("/turf/closed"):
                m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/closed/wall/r_wall"), ra.copy()))
        name = "%s Solar" % sub.replace("/", " ").title().replace("Fore", "Bow").replace("Aft", "Quarter")
        m.set(P["door"][0], P["door"][1], dmm.Tile(
            [dmm.Atom("/obj/machinery/door/airlock/engineering", [("name", '"%s Access"' % name), ("req_access_txt", '"10"')])],
            dmm.Atom("/turf/open/floor/plating"), ra.copy()))
        o_ = P["out"]
        ext = lambda toward: [dmm.Atom("/obj/machinery/door/airlock/external", [("name", '"Solar Maintenance"'),  # noqa: E731
                                                                               ("req_access_txt", '"13"')]),
                              dmm.Atom("/obj/effect/mapping_helpers/airlock/cyclelink_helper", [("dir", str(toward))]),
                              dmm.Atom(kit.CABLE)]
        m.set(P["a1"][0], P["a1"][1], dmm.Tile(ext(o_), dmm.Atom("/turf/open/floor/plating"), ra.copy()))
        m.set(P["v"][0], P["v"][1], dmm.Tile([dmm.Atom(kit.CABLE)], dmm.Atom("/turf/open/floor/plating"), ra.copy()))
        m.set(P["a2"][0], P["a2"][1], dmm.Tile(ext(OPP[o_]), dmm.Atom("/turf/open/floor/plating"), ra.copy()))
        m.get(*P["entry"]).objs.append(dmm.Atom(kit.CABLE))
        for c_ in P["cabs"]:
            m.get(*c_).objs.append(dmm.Atom(kit.CABLE))
        tt = m.get(*P["term"])
        tt.objs += [dmm.Atom("/obj/machinery/power/terminal", [("dir", str(OPP[o_]))]), dmm.Atom(kit.CABLE)]
        m.get(*P["smes"]).objs.append(dmm.Atom("/obj/machinery/power/smes", [("name", '"%s Storage"' % name)]))
        cdir = next(d for d in CARD if nb(P["console"], d) == P["entry"])
        m.get(*P["console"]).objs += [dmm.Atom("/obj/machinery/power/solar_control",
                                               [("id", '"%s"' % word), ("name", '"%s Control"' % name), ("dir", str(OPP[cdir]))]),
                                      dmm.Atom(kit.CABLE)]
        SOLAR_NET.update({P["a1"], P["v"], P["a2"], P["entry"], P["term"], P["console"]} | set(P["cabs"]))
        # the APC on a wall of the room away from the array's net (the grid reaches it), the light opposite
        faces = [(c, d) for c in P["inner"] for d in CARD if nb(c, d) in P["ring"] and nb(c, d) != P["door"]
                 and nb(c, d) != P["a1"] and c not in P["fenced"] and c != P["smes"]]
        faces.sort(key=lambda f: (abs(f[0][0] - P["door"][0]) + abs(f[0][1] - P["door"][1]), f))
        if faces:
            mount(m, faces[0][0], faces[0][1], "apc", [("name", '"%s APC"' % name)])
            lf = [f for f in faces[1:] if f[0] != faces[0][0]]
            if lf:
                m.get(*lf[-1][0]).objs.append(dmm.Atom("/obj/machinery/light/small", [("dir", str(lf[-1][1]))]))
        # the catwalk: the shortest run over open space from the outer airlock to the array's edge
        blocked = set(P["inner"]) | set(P["ring"]) | set(P["flank"]) | {P["a1"], P["v"], P["a2"]} | avoid

        def free(c):
            t = m.get(*c)
            return t is not None and t.tpath.startswith("/turf/open/space") and c not in blocked and c not in field
        prev_, q, goal = {P["c0"]: None}, [P["c0"]], None
        ringset = set(ring) - {(x0 - 1, y0 - 1), (x1 + 1, y0 - 1), (x0 - 1, y1 + 1), (x1 + 1, y1 + 1)}
        while q and goal is None:
            nq = []
            for c in q:
                if c in ringset:
                    goal = c
                    break
                for d in CARD:
                    n = nb(c, d)
                    if n not in prev_ and free(n):
                        prev_[n] = c
                        nq.append(n)
            q = nq
        path = []
        c = goal
        while c is not None:
            path.append(c)
            c = prev_[c]
        for c in path:
            m.set(c[0], c[1], dmm.Tile([dmm.Atom("/obj/structure/lattice/catwalk"), dmm.Atom(kit.CABLE)],
                                       dmm.Atom("/turf/open/space/basic"), area.copy()))
        log("solars %s: 48 panels, tracker at %d,%d; room %dx%d at %d,%d, door %d,%d, airlocks %d,%d / %d,%d, "
            "SMES %d,%d, catwalk %d tiles%s" % (
                key_, cx, cy, len({c[0] for c in P["inner"]}), len({c[1] for c in P["inner"]}),
                min(P["inner"])[0], min(P["inner"])[1], P["door"][0], P["door"][1], P["a1"][0], P["a1"][1],
                P["a2"][0], P["a2"][1], P["smes"][0], P["smes"][1], len(path), "" if goal else " NOT REACHING THE ARRAY"))
    return []


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
        # one quarter per wall side, as Meta's halls (486 of its 590 trimmed edge tiles hold one quarter): two on every
        # edge tile put v6 at 0.60 tile decals per floor tile against the human 0.03-0.56 (the gate 2026-11-22)
        quarters = sorted({QUARTERS[d][0] for d in sides})
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
        elif t.apath.startswith("/area/solar") or (x, y) in SOLAR_NET:
            continue        # the arrays' own net (solars()): field, catwalk, airlocks, the room's terminal and console
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
    # the solar nets and every tile beside them: a grid cable there would join an array to the station past its SMES
    # (cables join their same-layer neighbours); the solar rooms' SMES sit beside their terminals and stay reachable
    solar_net = {(x, y) for (x, y, z), t in m.tiles.items()
                 if (t.apath.startswith("/area/solar") and any(kit.is_cable(o) for o in t.objs)) or (x, y) in SOLAR_NET}
    fence |= solar_net | {nb(q, d) for q in solar_net for d in CARD}
    fence -= set(machines)
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
    # the whole works on three layers (atmos_works); the old single-layer air mix and waste bank are the fallback
    tops_ = {g: (((min(p[0] for p in t) + max(p[0] for p in t)) // 2), max(p[1] for p in t)) for g, t in groups.items()}
    if atmos_works(m, groups, tops_, roots, notes):
        for n in notes:
            log("atmos: %s" % n)
        return roots
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
    if waste_bank(m, groups, tops, roots, notes):
        for n in notes:
            log("atmos: %s" % n)
        return roots
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


AP = "/obj/machinery/atmospherics"
PIPE_DIR = {3: None, 12: 4, 5: 5, 6: 6, 9: 9, 10: 10}       # mask -> simple pipe dir (N-S: the default)


def _lay(layer):
    return "" if layer == 2 else "/layer%d" % layer


def atmos_works(m, groups, tops, roots, notes):
    """Atmospherics' pipework as a crew runs it, on all three piping layers (the user 2026-11-22: "build something
    insanely complicated and busy looking, multiple layers, do it smart"), every line doing a job:

    gas storage (the row of tank consoles and the three rows north of it)
      waste (layer 2, yellow)  the station scrubbers come in at the west end through the Waste In pump and run east
                               along the north row through a filter over each tank's input: plasma, CO2, N2, O2.
                               Each filter's catch drops down its tank's input column into the injector, so what the
                               scrubbers take out of the station refills the tanks; the rest leaves through the east
                               hull to the outlet. A port on the main floor dumps a canister into it (Port to Waste).
      air mix (layer 3)        N2 (cyan) and O2 (green) leave their tanks' outputs through layer manifolds, cross over
                               the catch columns on layer 3 into the 79/21 air mixer and on (grey) into the air tank,
                               whose siphon feeds distro (layer 1, the station supply).
    main floor
      thermal loop (layer 2, violet)  freezer and heater on one loop with a valved canister port: cool or heat a
                               canister's gas.
      mixing bench (layer 3, orange)  two canister ports through their pumps into a mixer, out through a pump to a
                               third port: any mix of any two gases.
      refinery (layer 3, brown) a canister port, a feed pump and a row of four filters (N2, O2, CO2, plasma), each
                               catch into its own canister, the rest into the last: a mixed canister split into its
                               gases.
    Meters on every line. Needs the five chambers in a row with the gas storage north of them and the main floor
    north of that (the v6 blueprint); returns False and changes nothing when the tiles aren't there."""
    if not all(g in tops for g in ("plasma", "co2", "n2", "o2", "air")):
        return False
    top = tops["plasma"][1]
    if any(tops[g][1] != top for g in tops):
        return False
    X0, Y0 = tops["plasma"][0] - 1, top          # (98, 34) on the v6 station
    yc, y1, y2, yw = top + 2, top + 3, top + 4, top + 5
    inj = {g: tops[g][0] + 1 for g in tops}     # each tank's input column
    out = {g: tops[g][0] - 1 for g in tops}     # and output column
    place = []                                    # (tile, [atoms], clear dense furniture, remove connectors)

    def A(path, **vs):
        return dmm.Atom(path, [(k, str(v)) for k, v in vs.items() if v is not None])

    def pipe(p, color, layer, mask, meter=False):
        d = PIPE_DIR[mask]
        atoms = [A("%s/pipe/simple/%s/visible%s" % (AP, color, _lay(layer)), dir=d)]
        if meter:
            atoms.append(A("/obj/machinery/meter", target_layer=layer if layer != 2 else None))
        place.append((p, atoms))

    def manifold(p, color, layer, missing):
        place.append((p, [A("%s/pipe/manifold/%s/visible%s" % (AP, color, _lay(layer)), dir=missing)]))

    def hop(p, axis=1):
        # the visible kind (level 2): the hidden one vanishes under the floor, so the line seemed to stop dead
        # (the user 2026-11-22: "the sudden hidden pipes look weird")
        place.append((p, [A("%s/pipe/layer_manifold/visible" % AP, dir=axis if axis != 2 else None)]))

    def dev(p, path, **vs):
        place.append((p, [A(path, **vs)]))

    def port(p, layer, d, canister=None):
        atoms = [A("%s/components/unary/portables_connector/visible%s" % (AP, _lay(layer)), dir=d if d != 2 else None),
                 A("/obj/effect/turf_decal/bot")]
        if canister:
            atoms.append(A("/obj/machinery/portable_atmospherics/canister" + canister))
        place.append((p, atoms))

    # ---- waste (layer 2, yellow), the north row of gas storage
    wx0, wx1 = X0, X0 + 19                        # 98 .. 117
    dev((wx0 + 1, yw), "%s/components/binary/pump/on" % AP, dir=4, name='"Waste In"', target_pressure=4500)
    filt = {inj["plasma"]: "plasma", inj["co2"]: "co2", inj["n2"]: "n2", inj["o2"]: "o2"}
    catch_color = {"plasma": "purple", "co2": "dark", "n2": "cyan", "o2": "green"}
    dump_x = wx1 - 1                              # 116: the dump joins just before the line leaves
    for x in range(wx0 + 2, wx1 + 1):
        if x in filt:
            g = filt[x]
            dev((x, yw), "%s/components/trinary/filter/atmos/%s" % (AP, "plasma" if g == "plasma" else g), dir=4, on=1,
                name='"%s Filter"' % {"plasma": "Plasma", "co2": "CO2", "n2": "N2", "o2": "O2"}[g])
            for y in (y2, y1, yc):                # the catch, down to the tank's injector
                pipe((x, y), catch_color[g], 2, 3, meter=(y == y1))
        elif x == dump_x:
            manifold((x, yw), "yellow", 2, 2)
        else:
            pipe((x, yw), "yellow", 2, 12, meter=x in (wx0 + 3, wx1))
    # the dump: a port on the main floor, its pump, through the wall into the manifold
    port((dump_x, yw + 3), 2, 2)
    dev((dump_x, yw + 2), "%s/components/binary/pump" % AP, dir=2, name='"Port to Waste"')
    pipe((dump_x, yw + 1), "yellow", 2, 3)
    # ---- air mix (layer 3): N2 along the upper row, O2 along the lower, into the mixer west of the air tank's input
    mx = inj["air"] - 2                           # 114
    hop((out["n2"], yc))
    pipe((out["n2"], y1), "cyan", 3, 3)
    pipe((out["n2"], y2), "cyan", 3, 6)
    for x in range(out["n2"] + 1, mx):
        pipe((x, y2), "cyan", 3, 12, meter=(x == out["n2"] + 1))
    hop((out["o2"], yc))
    pipe((out["o2"], y1), "green", 3, 6)
    for x in range(out["o2"] + 1, mx):
        pipe((x, y1), "green", 3, 12, meter=(x == out["o2"] + 1))
    pipe((mx, y1), "green", 3, 9)
    dev((mx, y2), "%s/components/trinary/mixer/airmix" % AP, dir=4, piping_layer=3, name='"Air Mixer"')
    for x in range(mx + 1, inj["air"]):
        pipe((x, y2), "general", 3, 12, meter=True)
    pipe((inj["air"], y2), "general", 3, 10)
    pipe((inj["air"], y1), "general", 3, 3)
    hop((inj["air"], yc))
    # ---- main floor (the room north of the gas storage's windows)
    fy = yw + 2                                   # 41: the walkway along the windows stays clear
    # refinery (layer 3, brown) along y 43, its catches on y 42
    ry = fy + 2
    port((X0 + 6, ry), 3, 4, "/air")
    dev((X0 + 7, ry), "%s/components/binary/pump/layer3" % AP, dir=4, name='"Refinery Feed"')
    for i, g in enumerate(("n2", "o2", "co2", "plasma")):
        fx = X0 + 8 + 2 * i
        dev((fx, ry), "%s/components/trinary/filter/on/layer3" % AP, dir=4, filter_type='"%s"' % g,
            name='"Refinery %s Filter"' % {"plasma": "Plasma", "co2": "CO2", "n2": "N2", "o2": "O2"}[g])
        port((fx, ry - 1), 3, 1, "")
        if i < 3:
            pipe((fx + 1, ry), "brown", 3, 12, meter=(i == 0))
    port((X0 + 15, ry), 3, 8, "")
    # mixing bench (layer 3, orange): ports on y 49, pumps on y 48, the mixer on y 47, out down x 111 to a port on y 44
    bx = X0 + 12                                  # 110
    port((bx, fy + 8), 3, 2, "/nitrogen")
    port((bx + 1, fy + 8), 3, 2, "/oxygen")
    dev((bx, fy + 7), "%s/components/binary/pump/layer3" % AP, dir=2, name='"Mix Input A"')
    dev((bx + 1, fy + 7), "%s/components/binary/pump/layer3" % AP, dir=2, name='"Mix Input B"')
    pipe((bx, fy + 6), "orange", 3, 5)
    dev((bx + 1, fy + 6), "%s/components/trinary/mixer/layer3" % AP, dir=2, name='"Canister Mixer"')
    pipe((bx + 1, fy + 5), "orange", 3, 3, meter=True)
    dev((bx + 1, fy + 4), "%s/components/binary/pump/layer3" % AP, dir=2, name='"Mix to Port"')
    port((bx + 1, fy + 3), 3, 1, "")
    # thermal loop (layer 2, violet): freezer and heater either side of a valved port, on y 49 / 48 / 47
    tx = X0 + 7                                   # 105
    dev((tx, fy + 8), "%s/components/unary/thermomachine/freezer" % AP, dir=4)
    pipe((tx + 1, fy + 8), "violet", 2, 12, meter=True)
    manifold((tx + 2, fy + 8), "violet", 2, 1)
    pipe((tx + 3, fy + 8), "violet", 2, 12)
    dev((tx + 4, fy + 8), "%s/components/unary/thermomachine/heater" % AP, dir=8)
    dev((tx + 2, fy + 7), "%s/components/binary/valve" % AP, dir=1, name='"Thermal Port Valve"')
    port((tx + 2, fy + 6), 2, 1)

    # every tile must be Atmospherics floor, clear of furniture other than what this lays (a tank console row tile
    # keeps its connectors only where they are replaced)
    tiles = {}
    for p, atoms in place:
        tiles.setdefault(p, []).extend(atoms)
    for p in tiles:
        t = m.get(*p)
        if t is None or t.apath != "/area/engine/atmos":
            notes.append("atmos works: %d,%d is not Atmospherics, not laid" % p)
            return False
        if not is_floor(t) and not t.tpath.startswith("/turf/closed"):
            notes.append("atmos works: %d,%d is not floor or wall, not laid" % p)
            return False
        if is_window(t) or t.has("/obj/machinery/door") or t.has("/obj/machinery/computer"):
            notes.append("atmos works: %d,%d holds a window, door or console, not laid" % p)
            return False
    for p, atoms in tiles.items():
        t = m.get(*p)
        t.objs = [o for o in t.objs if not o.path.startswith(AP + "/components/unary/portables_connector")
                  and not (kit.dense([o]) and not o.path.startswith(AP))
                  and not o.path.startswith("/obj/machinery/portable_atmospherics")]
        t.objs += atoms
    # east through the walls (and any maint) to the first space tile: the outlet
    P = "%s/pipe/simple/yellow/visible" % AP
    x = wx1 + 1
    while m.get(x, yw) is not None and not m.get(x, yw).tpath.startswith("/turf/open/space"):
        m.get(x, yw).objs.append(dmm.Atom(P, [("dir", "4")]))
        x += 1
    if m.get(x, yw) is None:
        return False
    m.get(x, yw).objs += [dmm.Atom("/obj/structure/lattice"),
                          dmm.Atom("%s/components/unary/outlet_injector/atmos/atmos_waste" % AP, [("dir", "8"), ("on", "1")])]
    roots["scrubbers"] = ((wx0, yw), 4, (wx0 + 1, yw))
    notes.append("atmos works: %d tiles of pipework on 3 layers; waste in at %d,%d through 4 filters back into the tanks, "
                 "out at %d,%d; air mix on layer 3; thermal loop, mixing bench and refinery on the main floor"
                 % (len(tiles), wx0, yw, x, yw))
    return True


FILTERED = ("plasma", "co2")       # tanks the waste bank refills; N2, O2 and air feed the air mix instead
FILTER_GAS = {"plasma": "plasma", "co2": "co2", "n2": "n2", "o2": "o2"}


def waste_bank(m, groups, tops, roots, notes):
    """The stock waste pattern (Meta, Delta, Hippie atmos, 2026-11-22 refit): the scrubber line comes into the gas
    storage room and runs east along its north row through a filter over each tank's input column. Each filter's
    catch goes south, down the column and through the chamber wall into the tank's injector, so the gas scrubbed
    out of the station goes back into its tank. The rest leaves through the east hull to an outlet in space.
    Filters (trinary_devices.dm): in from behind, out straight on, the catch to the right of the flow (flow east,
    catch south). Needs the chambers in a row with the gas storage north of them; returns False when they aren't."""
    fil = [g for g in FILTERED if g in tops]
    if not fil:
        return False
    top = tops[fil[0]][1]
    yw = top + 5                                         # the gas storage's north row
    row = sorted(x for (x, y, z), t in m.tiles.items() if y == yw and t.apath == "/area/engine/atmos" and is_floor(t))
    cols = {tops[g][0] + 1: g for g in fil}              # each tank's input (injector) column
    if not row or not all(c in row for c in cols) or any(tops[g][1] != top for g in fil):
        return False
    gx0, gx1 = row[0], row[-1]
    if any(x not in row for x in range(gx0, gx1 + 1)):
        return False
    P = "/obj/machinery/atmospherics/pipe/simple/general/visible"
    for x in range(gx0 + 1, gx1 + 1):
        t = m.get(x, yw)
        if x in cols:
            t.objs.append(dmm.Atom("/obj/machinery/atmospherics/components/trinary/filter/atmos/%s" % FILTER_GAS[cols[x]],
                                   [("dir", "4"), ("on", "1")]))
            # the catch, down to the injector: the input port's connector becomes pipe
            for y in range(top + 2, yw):
                ty = m.get(x, y)
                ty.objs = [o for o in ty.objs if not o.path.startswith("/obj/machinery/atmospherics/components/unary/portables_connector")]
                ty.objs.append(dmm.Atom(P))
        else:
            t.objs.append(dmm.Atom(P, [("dir", "4")]))
    m.get(gx0 + 2, yw).objs.append(dmm.Atom("/obj/machinery/meter"))
    # east through the walls (and any maint) to the first space tile: the outlet
    x = gx1 + 1
    while m.get(x, yw) is not None and not m.get(x, yw).tpath.startswith("/turf/open/space"):
        m.get(x, yw).objs.append(dmm.Atom(P, [("dir", "4")]))
        x += 1
    if m.get(x, yw) is None:
        return False
    m.get(x, yw).objs += [dmm.Atom("/obj/structure/lattice"),
                          dmm.Atom("/obj/machinery/atmospherics/components/unary/outlet_injector/atmos/atmos_waste",
                                   [("dir", "8"), ("on", "1")])]
    roots["scrubbers"] = ((gx0, yw), 4, (gx0 + 1, yw))
    notes.append("waste bank: in at %d,%d, %s filtered back into their tanks, out to space at %d,%d" % (
        gx0, yw, " and ".join(fil), x, yw))
    return True


# vents and scrubbers the air pass had to leave out (no pipe could reach them): written beside the map as
# <name>.air.json for the gate (station/v6_gate.py "vents all piped": none)
LEFT_OUT = {}


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
            # a network's root tile stays clear: a vent on the distro tap boxed the whole supply tree in (2026-11-22)
            taps_ = {r[0] for r in roots.values()}
            # nor on a power terminal (the user 2026-11-22: "terminals shouldn't be under vents/scrubbers")
            bad = kit.dense(t.objs) or bool(atmos.atoms(t)) or row or t.has("/obj/machinery/computer") or v in taps_ \
                or t.has("/obj/machinery/power/terminal")
            if bad:
                cand = [(x, y) for x in range(v[0] - 4, v[0] + 5) for y in range(v[1] - 4, v[1] + 5)
                        if (x, y) not in taken_v and (x, y) not in taps_ and m.get(x, y) is not None and m.get(x, y).apath == t.apath
                        and is_floor(m.get(x, y)) and not is_window(m.get(x, y)) and not kit.dense(m.get(x, y).objs)
                        and not m.get(x, y).has("/obj/machinery/door") and not atmos.atoms(m.get(x, y))
                        and not m.get(x, y).has("/obj/machinery/computer") and not m.get(x, y).has("/obj/machinery/power/terminal")
                        and not is_tank(m.get(x, y))]
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
            # a vent boxed in by other pipework: the nearest free tile of its room the tree can reach (a walk from
            # the laid tree over tiles the router may use), never a gas tank's floor, then lay the tree again (three
            # scrubbers had moved into the O2 tank, between the gas storage's catch columns and beside the
            # supermatter loop, and were left out, 2026-11-22)
            reach, todo_ = set(mask), list(mask)
            while todo_:
                p_ = todo_.pop()
                for d_ in CARD:
                    q_ = nb(p_, d_)
                    if q_ not in reach and abs(q_[0] - p_[0]) + abs(q_[1] - p_[1]) == 1 and cost(q_, p_, d_) is not None:
                        reach.add(q_)
                        todo_.append(q_)
            for v in sorted(left - {p for p, d in taps}):
                t = m.get(*v)
                cand = [(x, y) for x in range(v[0] - 6, v[0] + 7) for y in range(v[1] - 6, v[1] + 7)
                        if (x, y) not in vents[cls] and m.get(x, y) is not None and m.get(x, y).apath == t.apath
                        and is_floor(m.get(x, y)) and not is_window(m.get(x, y)) and not kit.dense(m.get(x, y).objs)
                        and not atmos.atoms(m.get(x, y)) and not m.get(x, y).has("/obj/machinery/door") and (x, y) not in block
                        and not m.get(x, y).has("/obj/machinery/power/terminal") and not is_tank(m.get(x, y))
                        and (x, y) in reach
                        and not any(nb((x, y), d_) in vents[cls] and nb((x, y), d_) != v for d_ in CARD)]
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
        LEFT_OUT[cls] = dropped
        left = left - set(dropped)
        unreached[cls] = left
        log("air: %-9s %3d vents, %4d pipe tiles%s" % (cls, len(vents[cls]), len(mask) - len(vents[cls]),
                                                      (", UNREACHED %s" % " ".join("%d,%d" % p for p in sorted(left)[:10])) if left else ""))
    unhide_breaks(m, log)
    return unreached


def unhide_breaks(m, log, most=60):
    """A visible line (a visible pipe or a pump, filter, connector) that joins a station pipe hidden under an intact
    floor tile seems to stop dead (the user 2026-11-22: "the sudden hidden pipes look weird, make sure that's not a
    pattern"): the hidden pipe turns visible, and the one after it, until the line reaches a wall, plating or another
    area, at most `most` tiles. forge/atmos.hidden_breaks is the measure; the gate wants none."""
    changed = 0
    for _ in range(most):
        breaks = atmos.hidden_breaks(m)
        todo = [(a, b) for a, b, _ in breaks if m.get(*a) is not None and m.get(*b) is not None
                and m.get(*a).apath == m.get(*b).apath]
        # across an area edge: a visible pipe on plating shows hidden or not, so it goes hidden instead (the engine's
        # waste pipe into the shared storage's floor)
        flip = [a for a, b, _ in breaks if m.get(*a) is not None and m.get(*b) is not None
                and m.get(*a).apath != m.get(*b).apath and m.get(*a).tpath.startswith("/turf/open/floor/plating")]
        for a in flip:
            t = m.get(*a)
            for i, o in enumerate(t.objs):
                if o.path.startswith("/obj/machinery/atmospherics/pipe/") and "/visible" in o.path:
                    t.objs[i] = dmm.Atom(o.path.replace("/visible", "/hidden"), list(o.vars))
                    changed += 1
        if not todo and not flip:
            break
        for a, q in todo:
            t = m.get(*q)
            for i, o in enumerate(t.objs):
                if o.path.startswith("/obj/machinery/atmospherics/pipe/") and "/hidden" in o.path:
                    t.objs[i] = dmm.Atom(o.path.replace("/hidden", "/visible"), list(o.vars))
                    changed += 1
    left = atmos.hidden_breaks(m)
    log("air: %d hidden pipes beside a visible line made visible%s" % (
        changed, (", %d breaks left: %s" % (len(left), " ".join("%d,%d" % b for _, b, _ in left[:6]))) if left else ""))


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
            # open space all the way out: a slot of space between two blocks of the station caught the trash
            # (2026-11-22: the exit at 89,28 threw into the one-tile gap at x 86)
            q, clear = sp, True
            while m.get(*q) is not None:
                if not m.get(*q).tpath.startswith("/turf/open/space"):
                    clear = False
                    break
                q = nb(q, d)
            if not clear:
                continue
            k = (abs(x - near[0]) + abs(y - near[1]), x, y, d)
            if best is None or k < best[0]:
                best = (k, (x, y), d)
    return (best[1], best[2]) if best else None


BIN_AREAS = ("/area/medical", "/area/science", "/area/security/main", "/area/security/office", "/area/engine/engineering",
             "/area/engine/break_room", "/area/crew_quarters/kitchen", "/area/crew_quarters/bar", "/area/hydroponics",
             "/area/janitor", "/area/bridge", "/area/crew_quarters/heads", "/area/crew_quarters/locker",
             "/area/crew_quarters/lounge", "/area/library", "/area/quartermaster", "/area/lawoffice", "/area/storage/tools")


BIN_DECOR = ("/obj/structure/sign", "/obj/machinery/newscaster")


def move_decor_for_bin(m, g, doors_):
    from station.v6_tidy import turned
    under = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe")

    def bare(q, allow_decor):
        t = m.get(*q)
        if any(o.path.startswith(("/obj/structure", "/obj/machinery")) and not o.path.startswith(under)
               and not (allow_decor and o.path.startswith(BIN_DECOR)) for o in t.objs):
            return False
        hs = [o for o in t.objs if abs(o.num("pixel_x")) >= 20 or abs(o.num("pixel_y")) >= 20
              or o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera"))]
        return all(o.path.startswith(BIN_DECOR) for o in hs) if allow_decor else not hs
    near_door = {q for q in g if any(abs(q[0] - d[0]) <= 2 and abs(q[1] - d[1]) <= 2 and
                                     abs(q[0] - d[0]) + abs(q[1] - d[1]) <= 2 for d in doors_)}
    used_w = set()
    for q in g:
        for o in m.get(*q).objs:
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if abs(px) >= 20 or abs(py) >= 20:
                used_w.add((q[0] + (1 if px >= 20 else -1 if px <= -20 else 0), q[1] + (1 if py >= 20 else -1 if py <= -20 else 0)))
    faces = [(p, d) for p, d in faces_of(m, g) if bare(p, False) and p not in near_door and nb(p, d) not in used_w]
    for q in sorted(g):
        if q in near_door or not any(m.get(*nb(q, d)).tpath.startswith("/turf/closed") for d in CARD) or not bare(q, True):
            continue
        decor = [o for o in m.get(*q).objs if o.path.startswith(BIN_DECOR)]
        dest = [f for f in faces if f[0] != q]
        if not decor or len(dest) < len(decor):
            continue
        for o in decor:
            p, d = dest.pop(0)
            off = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}[d]
            m.get(*q).objs.remove(o)
            m.get(*p).objs.append(turned(o, None, off))
            dest = [f for f in dest if f[0] != p]
        return q
    return None


def bins(m, log):
    """A disposal bin in each bigger crew room that has none (Medical, Service, Command and Dorms reviews: one or two
    bins a department), against a wall, off the door aprons; the disposals tree then reaches it."""
    added = 0
    doors_ = {(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/door")}
    # walls already hung on from their other side: no piece can hang on them here, so a bin backed by one costs the
    # room nothing (the gate 2026-11-22: the captain's bin took the one wall face the room had for its intercom)
    used_w = set()
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if abs(px) >= 16 or abs(py) >= 16:
                used_w.add((x + (1 if px >= 16 else -1 if px <= -16 else 0), y + (1 if py >= 16 else -1 if py <= -16 else 0)))
            elif o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera")) and not o.path.startswith("/obj/machinery/light_switch"):
                d = o.num("dir", 2)
                if o.path.startswith("/obj/machinery/camera"):
                    d = {1: 2, 2: 1, 4: 8, 8: 4}.get(d, 1)
                used_w.add(nb((x, y), d if d in CARD else 2))
    for g in regions(m):
        t0 = m.get(*next(iter(g)))
        if len(g) < 20 or t0.apath in ABANDONED or t0.apath == "/area/library/lounge" or not t0.apath.startswith(BIN_AREAS) \
                or any(m.get(*q).has("/obj/machinery/disposal") for q in g):
            continue
        # cable and pipe lie under the floor: stock bins stand on them (Meta 4/3, Delta 7/12, Hippie 3/2 of ~60), never
        # on a vent or scrubber. Without this, rooms whose wall row the cable or pipe routes run along got no bin.
        spots = [q for q in g if not any(o.path.startswith(("/obj/structure", "/obj/machinery")) and not o.path.startswith(
                     ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe"))
                     for o in m.get(*q).objs)
                 and not hung(m, q) and any(m.get(*nb(q, d)).tpath.startswith("/turf/closed") for d in CARD)
                 and not any(abs(q[0] - d_[0]) + abs(q[1] - d_[1]) <= 2 for d_ in doors_
                             if abs(q[0] - d_[0]) <= 2 and abs(q[1] - d_[1]) <= 2)]
        if not spots:
            # a poster, sign or newscaster on the only spots moves to another bare wall face of the room: a bin is
            # kit, the piece decoration (the gate 2026-11-22: the morgue's poster took its bin's spot)
            q = move_decor_for_bin(m, g, doors_)
            if q is None:
                continue
            spots = [q]
        cx = sum(q[0] for q in g) / len(g)
        cy = sum(q[1] for q in g) / len(g)
        q = min(spots, key=lambda q: (any(m.get(*nb(q, d)).tpath.startswith("/turf/closed") and nb(q, d) not in used_w
                                          for d in CARD), (q[0] - cx) ** 2 + (q[1] - cy) ** 2, q))
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
    # the trash goes out where atmos' waste does, one outlet spot as the accepted build had it at atmos (the user
    # 2026-11-22: "the disposals and waste pipe outlet spot is gone"); the bins' middle only when there is no waste outlet
    waste = [(x, y) for (x, y, z), t in m.tiles.items()
             if t.has("/obj/machinery/atmospherics/components/unary/outlet_injector/atmos/atmos_waste")]
    ex = disposal_exit(m, waste[0] if waste else (cx, cy))
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
    ap.add_argument("--no-gate", action="store_true", help="skip the gate (station/v6_gate.py)")
    ap.add_argument("--name", default="station_v6", help="data/mapforge/<name>.dmm (a trial copy while one boots)")
    a = ap.parse_args()
    lines = []
    gate_failed = [False]

    def log(s):
        print(s)
        lines.append(s)
    forced = set()
    for round_ in range(3):
        m = build(log, forced)
        if os.environ.get("V6_NO_ROOMS"):
            break
        # the iteration (the user, 2026-11-22: "objective data with iterations"): a department still over the most
        # any stock map gives it, with an abandoned maint room of its own still standing, loses that room (the
        # biggest first) and the station is built again
        from station import v6_rooms
        drop = v6_rooms.over_budget_rooms(m, MAINT_ROOMS, forced)
        if not drop:
            break
        log("budget round %d: rebuilding without %s" % (round_ + 1, ", ".join(sorted(drop))))
        forced |= drop
    out = os.path.join(DATA, a.name + ".dmm")
    dmm.write(m, out)
    import json
    json.dump({k: [list(v) for v in vs] for k, vs in LEFT_OUT.items()}, open(out[:-4] + ".air.json", "w"))
    log("wrote %s" % os.path.relpath(out, ROOT))
    if not a.no_gate:
        # the gate (station/v6_gate.py): a build worse than the stock maps or the accepted baseline fails
        from station import v6_gate
        fails = v6_gate.check(out)
        if fails:
            log("GATE FAILED: %s" % ", ".join(fails))
            gate_failed[0] = True
    if not a.no_render:
        from forge import render
        png = os.path.join(ROOT, "data", "previews", "mapforge", a.name + ".png")
        render.render(out, png, z=1, scale=0.5)
        log("picture %s" % os.path.relpath(png, ROOT))
    if gate_failed[0]:
        sys.exit(1)


def bin_swap(m, log):
    """After habits (its furniture counts toward dense): a room under its stock band for wall pieces with no bare
    wall face trades a disposal bin for a poster when that brings it nearer its bands (bin_gives_way)."""
    used_w = set()
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if abs(px) >= 16 or abs(py) >= 16:
                used_w.add((x + (1 if px >= 16 else -1 if px <= -16 else 0), y + (1 if py >= 16 else -1 if py <= -16 else 0)))
            elif o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera")) and not o.path.startswith("/obj/machinery/light_switch"):
                d = o.num("dir", 2)
                if o.path.startswith("/obj/machinery/camera"):
                    d = {1: 2, 2: 1, 4: 8, 8: 4}.get(d, 1)
                used_w.add(nb((x, y), d if d in CARD else 2))
    import random
    from station import v6_gate
    base_rooms = v6_gate._base()["rooms"]
    n = 0
    for g in regions(m):
        a = m.get(*next(iter(g))).apath
        if len(g) < 12 or not below_pieces(m, g, a, random.Random(0)):
            continue
        bare = [(p, d) for p, d in faces_of(m, g) if not hung(m, p) and nb(p, d) not in used_w
                and not any(o.path.startswith(("/obj/structure", "/obj/machinery")) and not o.path.startswith(
                    ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe"))
                    for o in m.get(*p).objs)]
        if bare:
            # a face freed after fixtures ran (tidy moves pieces off furniture): the poster the room is short of goes there
            p, d = sorted(bare)[0]
            dd, px, py = kit.MOUNT["sign"][d]
            m.get(*p).objs.append(dmm.Atom("/obj/structure/sign/poster/official/random",
                                           ([("pixel_x", str(px))] if px else []) + ([("pixel_y", str(py))] if py else [])))
            used_w.add(nb(p, d))
            n += 1
            continue
        # a camera hung on the far side of one of the room's walls moves to a bare face of its own room, so the wall
        # is free from both sides (the captain's office: the AI upload's camera held the wall its poster had)
        for p, d in faces_of(m, g):
            w = nb(p, d)
            far = nb(w, d)
            tf = m.get(*far)
            if w not in used_w or tf is None:
                continue
            cams = [o for o in tf.objs if o.path.startswith("/obj/machinery/camera") and
                    nb(far, {1: 2, 2: 1, 4: 8, 8: 4}.get(o.num("dir", 2), 1)) == w]
            others = [o for o in tf.objs if (abs(o.num("pixel_x")) >= 16 or abs(o.num("pixel_y")) >= 16 or
                                             o.path.startswith("/obj/machinery/light")) and o not in cams]
            if len(cams) != 1 or others:
                continue
            g2 = next((r for r in regions(m) if far in r), None)
            dest = [(q, dd) for q, dd in faces_of(m, g2 or ()) if q != far and not hung(m, q) and nb(q, dd) not in used_w
                    and not kit.dense(m.get(*q).objs)] if g2 else []
            if not dest:
                continue
            q, dd = dest[0]
            tf.objs.remove(cams[0])
            m.get(*q).objs.append(dmm.Atom(cams[0].path, [(k, v) for k, v in cams[0].vars if k != "dir"] +
                                           [("dir", str({1: 2, 2: 1, 4: 8, 8: 4}[dd]))]))
            used_w.discard(w)
            used_w.add(nb(q, dd))
            break
        freed = bin_gives_way(m, g, a, used_w, base_rooms.get(a, {}))
        if freed:
            p, d = freed
            dd, px, py = kit.MOUNT["sign"][d]
            m.get(*p).objs.append(dmm.Atom("/obj/structure/sign/poster/official/random",
                                           ([("pixel_x", str(px))] if px else []) + ([("pixel_y", str(py))] if py else [])))
            used_w.add(nb(p, d))
            n += 1
    log("bins: %d rooms under their pieces band given a poster late (a freed face, or a bin's)" % n)


def pocket_fill(m, log):
    """A maint pocket emptier than the emptiest stock ones (forge/size_budget.stock_pocket_band: furniture per tile)
    is dressed again on its own: polish's maint dressing spends one budget over all of maint, corners first, and
    left the leftover slot space bare (the gate 2026-11-22: two pockets at 0.04 and 0.05 against 0.076)."""
    import to_dmm as T
    from forge import parse, size_budget
    lo, _ = size_budget.stock_pocket_band()
    sm = parse.SemanticMap(m, "v6")
    n = 0
    for k, (tiles, f, box, area, r) in enumerate(size_budget.maint_pockets(sm)):
        if f < lo:
            T.dress_maint(m, set(r.tiles), 4000 + k, small=False)
            n += 1
    log("pockets: %d maint pockets under the stock fill (%.3f a tile) dressed again" % (n, lo))


def build(log, forced=()):
    """One whole build of the station from the department maps; forced: maint room areas not to build."""
    m, owner = assemble(log)
    if os.environ.get("V6_NO_ROOMS"):
        room_areas = maint_rooms(m, log)
    else:
        # the room budget (station/v6_rooms.py, size_budget findings 2026-11-22): the oversized maint rooms are left
        # unbuilt and their tiles, the plazas and the public lounges go to the stock room types v6 lacked
        from station import v6_rooms
        skip = v6_rooms.budget_skips(m, MAINT_ROOMS, log) | set(forced)
        room_areas = maint_rooms(m, log, skip=skip)
        slots = {(x, y) for (x0, y0, x1, y1), _, a, _, _ in MAINT_ROOMS if a in skip
                 for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
        v6_rooms.rooms(m, log, slots)
    # V6_SKIP=layout,glaze,... turns passes off for ablation (station/v6_ablate.py), like V6_NO_TIDY and the rest
    skip_pass = set(filter(None, os.environ.get("V6_SKIP", "").split(",")))
    solar_terms = solars(m, log)
    docks(m, log)
    close_corners(m, log)
    for name, fn in (("layout", layout), ("glaze", glaze)):
        if name not in skip_pass:
            fn(m, log)
    if "deadends" not in skip_pass:
        open_dead_ends(m, log)
    shared(m, log, room_areas)
    for name, fn in (("polish", polish), ("pockets", pocket_fill), ("plazas", plazas), ("details", details)):
        if name not in skip_pass:
            fn(m, log)
    # bins before fixtures: kit before decoration (the gate 2026-11-22: a fixtures poster or intercom on a room's
    # only bin spot cost the morgue and the kitchen their bins); the air pass keeps its vents off them (dense)
    bins(m, log)
    if "fixtures" not in skip_pass:
        fixtures(m, log)
    power(m, log, solar_terms)
    air(m, log)
    if not os.environ.get("V6_NO_TIDY"):
        # the wall-piece faults the gate counts, wherever they are; before habits, whose furniture would take the
        # bare wall faces the faulted pieces move to (2026-11-22: 151 pieces had no clean face left after habits)
        from station.v6_tidy import tidy
        tidy(m, log)
    if not os.environ.get("V6_NO_HABITS"):
        # the stock rooms' habits (forge/style_bands.py findings 2026-11-22); after bins, so its furniture never
        # takes a bin's wall spot, and before disposals, which reach the bins under whatever stands on the floor
        from station.v6_habits import habits
        habits(m, log)
        bin_swap(m, log)
    disposals(m, log)
    return m


if __name__ == "__main__":
    main()
