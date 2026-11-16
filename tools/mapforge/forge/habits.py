"""Small habits of human mappers, mined from the station maps (data/mapforge/habits.json).

    python tools/mapforge/forge/habits.py        # rebuild + print

companions   wall pieces that come with a floor piece on the same tile: sink -> mirror, bed -> defib mount, ...
             (share of that floor piece's tiles that have the companion, and the companion's offsets per wall side)
door_signs   the sign put on the wall beside a room's door, outside, by the room type the door leads into
             (CHEM by chemistry, EXAM by exam rooms, no smoking by medbay rooms, biohazard by virology, ...)
firelock     how often an open (doorless) boundary between two areas carries a firelock line
"""
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402
from forge.corpus import ANCHOR, INFRA, MAPS, mounted, solid  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE = os.path.join(ROOT, "data", "mapforge", "habits.json")
D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
# wall pieces that belong to the furniture they hang over (not the room's infrastructure: APC, alarms, lights, ...)
COMPANIONS = ("/obj/structure/mirror", "/obj/machinery/vending/wallmed", "/obj/machinery/defibrillator_mount",
              "/obj/structure/sign", "/obj/structure/noticeboard", "/obj/machinery/computer/security/telescreen",
              "/obj/structure/extinguisher_cabinet", "/obj/machinery/status_display", "/obj/item/radio/intercom",
              "/obj/machinery/newscaster", "/obj/structure/fireaxecabinet", "/obj/machinery/flasher",
              "/obj/item/storage/secure/safe", "/obj/machinery/light_switch", "/obj/structure/sink")


def side_of(o, walls):
    px, py = o.num("pixel_x"), o.num("pixel_y")
    if abs(py) >= abs(px) and abs(py) >= 8:
        return 1 if py > 0 else 2
    if abs(px) >= 8:
        return 4 if px > 0 else 8
    return next(iter(walls)) if len(walls) == 1 else 0


def room_type(a):
    parts = a.split("/")
    return "/".join(parts[:4]) if len(parts) > 3 else a


def mine():
    comp = defaultdict(Counter)       # anchor path -> companion path -> tiles
    comp_n = Counter()                # anchor path -> tiles (with a wall beside)
    comp_off = defaultdict(Counter)   # companion path -> "side:px,py"
    signs = defaultdict(Counter)      # room type -> sign path (beside a door into it)
    doors_n = Counter()
    fl = Counter()
    for rel in MAPS:
        path = os.path.join(ROOT, "_maps", "map_files", rel)
        if not os.path.exists(path):
            continue
        m = dmm.read(path)
        for (x, y, z), t in m.tiles.items():
            if z != 1 or not t.tpath.startswith("/turf/open"):
                continue
            walls = {d for d, (dx, dy) in D4.items() if solid(m.get(x + dx, y + dy, z))}
            an = [o for o in t.objs if o.path.startswith(ANCHOR) and not o.path.startswith(INFRA) and not mounted(o)]
            mts = [o for o in t.objs if mounted(o) and o.path.startswith(COMPANIONS)]
            if an and walls:
                # same tile, or one tile along the wall it hangs on
                near = list(mts)
                for d, (dx, dy) in D4.items():
                    if d in walls:
                        continue
                    nt = m.get(x + dx, y + dy, z)
                    if nt is not None:
                        near += [o for o in nt.objs if mounted(o) and o.path.startswith(COMPANIONS)
                                 and side_of(o, walls) in walls]
                for key in (an[0].path, an[0].path + "@" + room_type(t.apath)):
                    comp_n[key] += 1
                    for c in {o.path for o in near}:
                        comp[key][c] += 1
            for o in mts:
                comp_off[o.path]["%d:%d,%d" % (side_of(o, walls), o.num("pixel_x"), o.num("pixel_y"))] += 1
            # a door: which room does it lead into, and what sign hangs beside it on the other side
            if t.has("/obj/machinery/door/airlock"):
                for d, (dx, dy) in D4.items():
                    inner = m.get(x + dx, y + dy, z)
                    outer = m.get(x - dx, y - dy, z)
                    if inner is None or outer is None or inner.apath == outer.apath or inner.apath.startswith(("/area/hallway", "/area/maintenance")):
                        continue
                    rt = room_type(inner.apath)
                    doors_n[rt] += 1
                    # signs within 2 tiles of the door, on the outer side's row/column
                    found = set()
                    for k in (-2, -1, 1, 2):
                        sx, sy = (x + (k if dy else 0) - dx, y + (k if dx else 0) - dy)
                        st = m.get(sx, sy, z)
                        if st is None:
                            continue
                        for o in st.objs:
                            if o.path.startswith("/obj/structure/sign") and "poster" not in o.path:
                                found.add(o.path)
                    for s in found:
                        signs[rt][s] += 1
            # open area boundaries
            for d, (dx, dy) in ((1, (0, 1)), (4, (1, 0))):
                nt = m.get(x + dx, y + dy, z)
                if nt is None or not nt.tpath.startswith("/turf/open") or nt.apath == t.apath:
                    continue
                if t.has("/obj/machinery/door/airlock") or nt.has("/obj/machinery/door/airlock") or "space" in t.apath + nt.apath:
                    continue
                fl["boundaries"] += 1
                if t.has("/obj/machinery/door/firedoor") or nt.has("/obj/machinery/door/firedoor"):
                    fl["with_firelock"] += 1
    out = {"companions": {a: {c: n / comp_n[a] for c, n in cs.items()} for a, cs in comp.items() if comp_n[a] >= 3},
           "companion_n": dict(comp_n),
           "companion_offsets": {c: dict(v) for c, v in comp_off.items()},
           "door_signs": {r: {s: n / doors_n[r] for s, n in ss.items()} for r, ss in signs.items()},
           "doors_n": dict(doors_n),
           "firelock": dict(fl)}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(out, open(CACHE, "w"))
    return out


_H = None


def habits():
    global _H
    if _H is None:
        _H = json.load(open(CACHE)) if os.path.exists(CACHE) else mine()
    return _H


if __name__ == "__main__":
    h = mine()
    print("== companions (>=30% of the floor piece's wall tiles)")
    for a, cs in sorted(h["companions"].items(), key=lambda kv: -h["companion_n"][kv[0]]):
        strong = {c.replace("/obj/", ""): round(v, 2) for c, v in cs.items() if v >= 0.3}
        if strong:
            print("  %-50s n=%-4d %s" % (a.replace("/obj/", ""), h["companion_n"][a], strong))
    print("== signs beside doors into room types (share of doors)")
    for r, ss in sorted(h["door_signs"].items(), key=lambda kv: -h["doors_n"][kv[0]]):
        top = sorted(ss.items(), key=lambda kv: -kv[1])[:3]
        if top and top[0][1] >= 0.2:
            print("  %-40s doors=%-3d %s" % (r, h["doors_n"][r], ", ".join("%s %.0f%%" % (s.replace("/obj/structure/sign/", ""), 100 * v) for s, v in top)))
    print("== open area boundaries with a firelock:", h["firelock"])
