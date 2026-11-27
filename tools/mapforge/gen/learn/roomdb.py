"""L0 room model: every room of the human tg maps as a record the room synthesizer learns from (plan:
studies/learned_generator_plan.md).

    python tools/mapforge/gen/learn/roomdb.py              # build data/mapforge/learn/rooms.json, print a summary
    python tools/mapforge/gen/learn/roomdb.py chemistry    # the rooms of types matching "chemistry"
    from gen.learn import roomdb; roomdb.rooms() -> [room]

A room is one connected piece of an area's floor (not maint, halls, space, shuttles). Coordinates are relative to the
room's lowest corner. A record keeps:
  floor    [[x, y, wall mask]]: the sides (N1 S2 E4 W8) that are wall, glass or another area (not a door)
  doors    [[x, y, side, other]]: a door tile beside the room, the room's side it is on, the area beyond it
  windows  [[x, y]]: glass tiles of the room's ring
  motifs   furniture groups (8-connected furniture tiles, forge/corpus's clusters): cells [[dx, dy, [atoms], mask]],
           use [[dx, dy]] (open floor beside it, where a player stands to use it), at [x, y] its lowest corner
  mounts   wall pieces on the room's floor tiles: [[x, y, side, atom]] (APC, alarms, lights, signs, screens...)
Loose items on bare floor are not kept: a generated room never inherits a stray crowbar.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm  # noqa: E402

ROOT = CO.ROOT
OUT = os.path.join(ROOT, "data", "mapforge", "learn", "rooms.json")
VERSION = 3
def _lamp(o):
    return o.path.startswith("/obj/machinery/light") and not o.path.startswith("/obj/machinery/light_switch")


SKIP = ("/area/space", "/area/maintenance", "/area/hallway", "/area/solar", "/area/shuttle", "/area/lavaland",
        "/area/mine", "/area/ruin", "/area/centcom")
MAX_MOTIF = 40
D4 = CO.D4


def family(name):
    """The map family a corpus map belongs to (MetaLake is Meta's)."""
    return {"MetaLake.dmm": "MetaStation.dmm"}.get(name, name)


def _door(t):
    return t is not None and any(o.path.startswith("/obj/machinery/door") and not o.path.startswith("/obj/machinery/door/firedoor")
                                 for o in t.objs)


def _glass(t):
    return t is not None and (t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille")
                              or any(o.path.startswith("/obj/structure/window") and "fulltile" in o.path for o in t.objs))


# pieces forge/corpus files as infrastructure that are still what a room is for: an SMES room's SMES and their
# terminals, a room's disposal bin, emergency and fire closets
ROOM_KIT = ("/obj/machinery/power/smes", "/obj/machinery/power/terminal", "/obj/machinery/disposal/bin",
            "/obj/structure/closet/emcloset", "/obj/structure/closet/firecloset")


def furniture(t):
    """forge/corpus.furniture with ROOM_KIT counted as furniture."""
    an, it = CO.furniture(t)
    extra = [a for a in t.objs if a.path.startswith(ROOM_KIT) and not CO.mounted(a) and a not in an]
    return an + extra, it


def mine(path):
    m = dmm.read(path)
    name = os.path.basename(path)
    seen, out = set(), []
    for (x, y, z), t in sorted(m.tiles.items()):
        if z != 1 or (x, y) in seen or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
            continue
        area = t.apath
        if not area or area.startswith(SKIP) or CO.solid(t) or _door(t):
            continue
        room, q = set(), [(x, y)]
        seen.add((x, y))
        while q:
            p = q.pop()
            room.add(p)
            for dx, dy in D4.values():
                n = (p[0] + dx, p[1] + dy)
                nt = m.get(n[0], n[1])
                if n not in seen and nt is not None and nt.apath == area and nt.tpath.startswith("/turf/open") \
                        and not nt.tpath.startswith("/turf/open/space") and not CO.solid(nt) and not _door(nt):
                    seen.add(n)
                    q.append(n)
        if len(room) < 6:
            continue
        x0, y0 = min(p[0] for p in room), min(p[1] for p in room)
        rel = lambda p: [p[0] - x0, p[1] - y0]  # noqa: E731
        floor, doors, windows, furn, mounts = [], [], set(), {}, []
        for p in sorted(room):
            tt = m.get(*p)
            wm = 0
            for d, (dx, dy) in D4.items():
                n = (p[0] + dx, p[1] + dy)
                nt = m.get(*n)
                if n in room:
                    continue
                if _door(nt):
                    other = next((m.get(n[0] + dx, n[1] + dy).apath for _ in [0] if m.get(n[0] + dx, n[1] + dy)), "")
                    doors.append(rel(n) + [d, other])
                    continue
                wm |= d
                if _glass(nt):
                    windows.add(tuple(rel(n)))
            floor.append(rel(p) + [wm])
            an, it = furniture(tt)
            if an:
                furn[p] = (an, it, wm)
            for o in tt.objs:
                if CO.mounted(o) and not o.path.startswith(("/obj/effect", "/obj/machinery/atmospherics")):
                    mounts.append(rel(p) + [CO.mount_side(o), o.text()])
                elif _lamp(o):
                    # light fixtures hang by their dir, with no pixel offset (rooms came out with none, 2026-11-25)
                    d = o.num("dir", 2)
                    mounts.append(rel(p) + [d if d in (1, 2, 4, 8) else 2, o.text()])
        motifs = []
        left = set(furn)
        while left:
            s = left.pop()
            comp, q = [s], [s]
            while q:
                p = q.pop()
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        n = (p[0] + dx, p[1] + dy)
                        if n in left:
                            left.discard(n)
                            comp.append(n)
                            q.append(n)
            if len(comp) > MAX_MOTIF:
                continue
            mx, my = min(p[0] for p in comp), min(p[1] for p in comp)
            cells, use = [], set()
            for p in comp:
                an, it, wm = furn[p]
                cells.append([p[0] - mx, p[1] - my, [a.text() for a in an] + [a.text() for a in it], wm])
                for dx, dy in D4.values():
                    n = (p[0] + dx, p[1] + dy)
                    if n in room and n not in furn:
                        use.add((n[0] - mx, n[1] - my))
            motifs.append(dict(cells=cells, use=sorted(use), at=[mx - x0, my - y0]))
        out.append(dict(map=name, family=family(name), area=area, at=[x0, y0], floor=floor, doors=doors,
                        windows=sorted(windows), motifs=motifs, mounts=mounts, tiles=len(room)))
    return out


def build():
    rooms = []
    for rel in CO.MAPS:
        p = os.path.join(ROOT, "_maps", "map_files", rel)
        if os.path.exists(p):
            rooms += mine(p)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(dict(version=VERSION, rooms=rooms), open(OUT, "w"))
    return rooms


_R = None


def rooms():
    global _R
    if _R is None:
        if os.path.exists(OUT):
            d = json.load(open(OUT))
            if d.get("version") == VERSION:
                _R = d["rooms"]
        if _R is None:
            _R = build()
        # main: the largest region of its area on its map (a kitchen's cold room or the bar's backroom share the
        # area; a main kitchen furnished from a cold room came out with a gibber and no microwave, 2026-11-25)
        big = {}
        for r in _R:
            k = (r["map"], r["area"])
            big[k] = max(big.get(k, 0), r["tiles"])
        for r in _R:
            r["main"] = r["tiles"] == big[(r["map"], r["area"])]
    return _R


def family(atom_text):
    """A machine's family for counting: its path to the fourth part (/obj/machinery/power/smes,
    /obj/machinery/computer/med_data), None for anything that isn't a machine."""
    path = atom_text.split("{", 1)[0].strip()
    if path.startswith("/obj/machinery/rnd/production"):
        return path             # each department's lathe its own (engineering had two: break room and shared storage)
    if path.startswith("/obj/structure/closet") and not path.startswith(("/obj/structure/closet/crate",
                                                                         "/obj/structure/closet/cardboard")):
        # lockers by kind: seven radiation closets round the gravity generator (crew 100 seed 7, 2026-11-26)
        return "/".join(path.split("/")[:6])
    if path.startswith(("/obj/structure/reagent_dispensers", "/obj/structure/tank_dispenser")):
        return "/".join(path.split("/")[:5])
    if not path.startswith("/obj/machinery") or path.startswith(("/obj/machinery/light", "/obj/machinery/door",
                                                                  "/obj/machinery/atmospherics/pipe")):
        return None
    return "/".join(path.split("/")[:5])


_CAPS = None


def caps():
    """{area: {machine family: [most in one human room of the area, most in all the area's rooms on one map]}}.
    The user 2026-11-26: "Engineering has so many SMES that don't fit a purpose": the gravity generator's three
    rooms took SMES from every exemplar and the top-up (5 SMES; every human map has 1 there)."""
    global _CAPS
    if _CAPS is None:
        from collections import Counter, defaultdict
        per_room = defaultdict(Counter)          # (area) -> fam -> max in a room
        per_map = defaultdict(Counter)           # (area, map) -> fam -> total
        for r in rooms():
            c = Counter()
            for mo in r["motifs"]:
                for cell in mo["cells"]:
                    for a in cell[2]:
                        f = family(a)
                        if f:
                            c[f] += 1
            for f, n in c.items():
                per_room[r["area"]][f] = max(per_room[r["area"]][f], n)
                per_map[(r["area"], r["map"])][f] += n
        totals = defaultdict(list)
        for (area, _), c in per_map.items():
            for f, n in c.items():
                totals[(area, f)].append(n)
        out = defaultdict(dict)
        for (area, f), ns in totals.items():
            ns.sort()
            # the typical map that has the machine there (upper median): 4 SMES in the SMES room, not Endo's 6
            out[area][f] = [per_room[area][f], ns[len(ns) // 2]]
        _CAPS = dict(out)
    return _CAPS


_BACKF = None


def back_first(area):
    """The type's back rooms hold one of its one-a-map machines more often than its main rooms do (the explab's
    experimentor stands in a back room apart from its console on 6 of 7 human maps; a fireball from one killed the
    Bot Shift's scientist at the console beside it, crew 100 seed 7, 2026-11-26): furnish the back rooms first."""
    global _BACKF
    if _BACKF is None:
        from collections import Counter, defaultdict
        main, back, nm, nb = defaultdict(Counter), defaultdict(Counter), Counter(), Counter()
        for r in rooms():
            fams = {family(a) for mo in r["motifs"] for cell in mo["cells"] for a in cell[2]} - {None}
            (main if r.get("main") else back)[r["area"]].update(fams)
            (nm if r.get("main") else nb)[r["area"]] += 1
        cp = caps()
        # a machine the back rooms nearly always hold and the main rooms nearly never do
        _BACKF = {a for a in back for f, n in back[a].items()
                  if cp.get(a, {}).get(f, [0, 0])[1] == 1 and n >= 2 and n >= 0.5 * nb[a]
                  and main[a][f] <= 0.25 * max(1, nm[a])}
    return area in _BACKF


_SCAPS = None
# a machine every department has its own of (the station total is the sum of rooms, not one map's count)
SHARED = ("/obj/machinery/disposal", "/obj/machinery/vending", "/obj/machinery/power/terminal", "/obj/machinery/holopad",
          "/obj/machinery/computer/security", "/obj/machinery/computer/crew", "/obj/machinery/computer/secure_data",
          "/obj/machinery/computer/med_data", "/obj/machinery/recharger", "/obj/machinery/cell_charger",
          "/obj/machinery/portable_atmospherics", "/obj/machinery/space_heater", "/obj/machinery/photocopier",
          "/obj/machinery/computer/rdconsole", "/obj/machinery/shower", "/obj/structure/closet",
          "/obj/structure/reagent_dispensers", "/obj/structure/tank_dispenser")


def station_caps():
    """{machine family: most of it on one human station}, for the machines a station has a handful of (gulag
    teleporter, clone pod, gravity generator, SMES): crew 100 seed 7 had the labour camp teleporter in both processing
    and transfer, and four clone pods."""
    global _SCAPS
    if _SCAPS is None:
        from collections import Counter, defaultdict
        per = defaultdict(Counter)
        for r in rooms():
            for mo in r["motifs"]:
                for cell in mo["cells"]:
                    for a in cell[2]:
                        f = family(a)
                        if f and not f.startswith(SHARED):
                            per[r["map"]][f] += 1
        out = Counter()
        for c in per.values():
            for f, n in c.items():
                out[f] = max(out[f], n)
        _SCAPS = {f: n for f, n in out.items() if n <= 6}
    return dict(_SCAPS)


if __name__ == "__main__":
    rs = build() if len(sys.argv) < 2 or sys.argv[1] == "--rebuild" else rooms()
    want = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != "--rebuild" else None
    from collections import Counter
    c = Counter(r["area"] for r in rs)
    print("%d rooms of %d types from %d maps" % (len(rs), len(c), len({r["map"] for r in rs})))
    for r in rs:
        if want and want in r["area"]:
            print("  %-16s %-40s %3d tiles, %d doors, %d motifs, %d mounts" % (r["map"], r["area"], r["tiles"],
                                                                             len(r["doors"]), len(r["motifs"]), len(r["mounts"])))
