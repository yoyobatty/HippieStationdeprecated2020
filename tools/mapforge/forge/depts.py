"""Department library: every department of every human station, cut out whole, for the station generator to stitch
together (the user's ruling of 2026-11-18: "build departments from real stock-map rooms and layouts (cut, adapt and
stitch pieces of the 38 human maps) instead of hand rules").

    python tools/mapforge/forge/depts.py              # (re)build data/mapforge/depts.json and print a table
    python tools/mapforge/forge/depts.py medical      # list the medical pieces

A piece is one 4-connected stretch of a department group's floor (studies/stations.py GROUPS), joined through its
own doors, as a mapper drew it:
    cells   floor tile -> [area, turf, furniture, decals, items, wall pieces]; pipes, cables, lights, APCs, alarms,
            cameras, vents and landmarks are left out, because the builder lays the station's own
    doors   every door on or inside the piece: its door, firelock, windoor, desk and shutter atoms as written
    glass   window tiles round or inside the piece
    exits   door or open tile on the piece's edge -> what lies past it: hall, maint, room (another department),
            space, other
Pieces from other codebases keep only types our code declares (forge/typeindex.py); a piece that loses more than a
tenth of its furniture that way is dropped.
"""
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, typeindex, kit  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CACHE = os.path.join(ROOT, "data", "mapforge", "depts.json")
GROUPS = ("command", "security", "medical", "science", "cargo", "service", "dorms", "civic", "engineering", "atmos")
D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
# what the builder lays itself: left out of cells (doors keep their own atoms, see DOOR_KEEP)
INFRA = ("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/machinery/power/apc", "/obj/machinery/power/terminal",
         "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/light", "/obj/machinery/camera",
         "/obj/structure/disposalpipe", "/obj/effect/landmark", "/obj/machinery/navbeacon", "/obj/structure/lattice",
         "/obj/docking_port", "/obj/effect/spawner/structure/window", "/obj/structure/grille", "/obj/structure/window",
         "/obj/machinery/door", "/obj/machinery/holopad", "/obj/effect/decal/cleanable", "/obj/machinery/power/smes",
         "/obj/machinery/light_switch", "/obj/machinery/requests_console", "/obj/machinery/newscaster",
         "/obj/machinery/status_display", "/obj/machinery/ai_status_display", "/obj/item/radio/intercom",
         "/obj/structure/extinguisher_cabinet", "/mob/living/simple_animal/bot")
DOOR_KEEP = ("/obj/machinery/door", "/obj/structure/table", "/obj/effect/mapping_helpers/airlock")


def _known(path):
    return typeindex.known(path)


def cut(sm, g):
    """The pieces of group g on one map."""
    fl = {p for p, c in sm.cls.items() if c == "F" and sm.group.get(p) == g}
    dr = {p for p, c in sm.cls.items() if c == "D" and sm.group.get(p) == g}
    seen = set()
    out = []
    for s in sorted(fl):
        if s in seen:
            continue
        comp, st = {s}, [s]
        seen.add(s)
        while st:
            a = st.pop()
            for dx, dy in D4:
                b = (a[0] + dx, a[1] + dy)
                if b in seen:
                    continue
                if b in fl:
                    seen.add(b)
                    comp.add(b)
                    st.append(b)
                elif b in dr:
                    # a door of the group joins what is past it when that is the group's floor too
                    c = (b[0] + dx, b[1] + dy)
                    if c in fl and c not in seen:
                        seen.add(c)
                        comp.add(c)
                        st.append(c)
        if len(comp) >= 30:
            out.append(comp)
    return out


def kind_past(sm, q):
    if sm.cls.get(q) in (None, "S"):
        return "space"
    if sm.cls.get(q) != "F":
        return "other"
    r = sm.regions.get(sm.region.get(q))
    if r is None:
        return "other"
    return {"hall": "hall", "maint": "maint", "room": "room"}.get(r.kind, "other")


def piece(sm, g, comp):
    x0 = min(p[0] for p in comp)
    y0 = min(p[1] for p in comp)

    def key(p):
        return "%d,%d" % (p[0] - x0, p[1] - y0)
    cells, doors, glass, exits = {}, {}, set(), {}
    lost = kept = 0
    for p in comp:
        t = sm.m.get(p[0], p[1], sm.z)
        objs = []
        for o in t.objs:
            if o.path.startswith(INFRA):
                continue
            if not _known(o.path):
                if kit.is_dense_atom(o):
                    lost += 1
                continue
            if kit.is_dense_atom(o):
                kept += 1
            objs.append(o.text())
        turf = t.tpath if _known(t.tpath) else "/turf/open/floor/plasteel"
        cells[key(p)] = [t.apath, turf] + objs
        for dx, dy in D4:
            q = (p[0] + dx, p[1] + dy)
            if q in comp:
                continue
            c = sm.cls.get(q)
            if c == "D":
                tq = sm.m.get(q[0], q[1], sm.z)
                doors[key(q)] = [o.text() for o in tq.objs if o.path.startswith(DOOR_KEEP) and _known(o.path)]
                past = (q[0] + dx, q[1] + dy)
                if past not in comp:
                    exits[key(q)] = kind_past(sm, past)
            elif c == "W":
                if q in sm.glass:
                    glass.add(key(q))
            elif c == "F":
                exits[key(q)] = "open-" + kind_past(sm, q)
    if kept and lost > 0.1 * (lost + kept):
        return None
    areas = Counter(v[0] for v in cells.values())
    return {"map": sm.name, "group": g, "n": len(comp), "w": max(p[0] for p in comp) - x0 + 1,
            "h": max(p[1] for p in comp) - y0 + 1, "at": [x0, y0], "cells": cells, "doors": doors,
            "glass": sorted(glass), "exits": exits, "areas": dict(areas),
            "rooms": len({sm.region[p] for p in comp})}


def mine():
    out = []
    for name in parse.humans():
        try:
            sm = parse.load(name)
        except Exception as e:  # a corpus map that won't parse
            print("skip %s: %s" % (name, e))
            continue
        for g in GROUPS:
            for comp in cut(sm, g):
                pc = piece(sm, g, comp)
                if pc:
                    out.append(pc)
        print("%-28s %d pieces so far" % (name, len(out)), flush=True)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(out, open(CACHE, "w"))
    return out


_L = None


def library():
    global _L
    if _L is None:
        _L = json.load(open(CACHE)) if os.path.exists(CACHE) else mine()
    return _L


if __name__ == "__main__":
    if len(sys.argv) > 1:
        for pc in library():
            if pc["group"] == sys.argv[1]:
                ex = Counter(pc["exits"].values())
                print("%-24s n=%4d %3dx%-3d rooms=%2d exits=%s" % (pc["map"], pc["n"], pc["w"], pc["h"], pc["rooms"], dict(ex)))
    else:
        lib = mine()
        c = Counter(p["group"] for p in lib)
        print(dict(c))
