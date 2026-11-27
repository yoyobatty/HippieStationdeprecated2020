"""How the stock maps place each piece and keep their rooms walkable: a study, and the checks a generated station is
held to.

    python tools/mapforge/gen/learn/placestudy.py                 # build data/mapforge/learn/place.json, print it
    python tools/mapforge/gen/learn/placestudy.py --check <dmm>   # the generated map's misplacements, per 1000 pieces
    python tools/mapforge/gen/learn/placestudy.py --stock         # the same check on the stock maps (the bar)
    from gen.learn import placestudy; placestudy.check(m) -> {finding: [(x, y, text)]}

The user 2026-11-26: "there's still quite a few more iterations you need to do with extra studying on stock maps
for room layout, design, function, pathing and structure placement checks".

Per piece (a structure or machine on a room's floor, not hung on a wall, not pipes or cables), from the 8 stock maps:
  walls    how many of its four sides are wall or glass
  front    it stands on a door's front tile (the tile a door opens onto)
  reach    a free floor tile beside it is reached from the room's doors over free floor (someone can get to it)
  boxed    no free floor tile beside it at all
  door_d   its distance to the room's nearest front door (front_doors: its airlocks nearest the halls by walking),
           as a share of the room's size (front of the room 0, back 1)
Per family: how often each holds (a locker stands against a wall, a console never on a door front). Per room: the
share of its free floor reached from its doors (pathing), the share of its floor left free (layout density).

Checks (each a list of spots): off_wall (a piece off the wall whose family stands against one 90%+ of the time),
door_front (a piece on a door's front whose family does so under 3%), unreachable (a piece no one reaches whose
family is reached 95%+), boxed, cut_room (a room whose doors reach less of its free floor than the stock rooms of
its type at their 10th percentile), crammed / bare (a room's free share outside its type's stock 5th-95th).
"""
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN  # noqa: E402

OUT = os.path.join(CO.ROOT, "data", "mapforge", "learn", "place.json")
VERSION = 6
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
SKIP_AREA = ("/area/space", "/area/maintenance", "/area/hallway", "/area/solar", "/area/shuttle", "/area/centcom",
             "/area/lavaland", "/area/mine", "/area/ruin", "/area/holodeck", "/area/engine/supermatter",
             "/area/science/test_area", "/area/ai_monitored/turret_protected/ai", "/area/science/mixing/chamber")
SKIP_OBJ = ("/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposalpipe", "/obj/machinery/door",
            "/obj/structure/window", "/obj/structure/grille", "/obj/machinery/light", "/obj/machinery/power/apc",
            "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/camera", "/obj/machinery/navbeacon",
            "/obj/structure/lattice", "/obj/machinery/holopad", "/obj/machinery/power/terminal", "/obj/effect",
            "/obj/structure/sign", "/obj/machinery/status_display", "/obj/machinery/newscaster", "/obj/structure/plasticflaps",
            "/obj/machinery/conveyor", "/obj/machinery/button", "/obj/structure/extinguisher_cabinet",
            "/obj/machinery/light_switch", "/obj/machinery/requests_console", "/obj/structure/noticeboard",
            "/obj/machinery/porta_turret", "/obj/machinery/ai_slipper", "/obj/machinery/flasher", "/obj/structure/disposaloutlet",
            "/obj/machinery/door_timer", "/obj/machinery/magnetic_module", "/obj/machinery/mass_driver",
            "/obj/structure/fans", "/obj/machinery/shieldwallgen", "/obj/machinery/power/emitter")


# the learned departments' corridor areas (gen/learn/doorcount.py): every room opens on them, door counts don't apply
CORRIDOR_AREAS = ("/area/medical/medbay", "/area/security", "/area/crew_quarters/heads", "/area/science", "/area/engine",
                  "/area/quartermaster", "/area/crew_quarters", "/area/chapel", "/area/crew_quarters/dorms",
                  "/area/crew_quarters/fitness", "/area/engine/atmos", "/area/ai_monitored/turret_protected")


def family(path):
    parts = path.split("{")[0].strip().split("/")
    if path.startswith("/obj/structure/closet") and not path.startswith("/obj/structure/closet/crate"):
        return "/".join(parts[:5])
    return "/".join(parts[:4])


def _door(t):
    return t is not None and any(o.path.startswith(("/obj/machinery/door/airlock", "/obj/machinery/door/window"))
                                 for o in t.objs)


def _solid(t):
    return t is None or t.tpath.startswith("/turf/closed") or CO.solid(t)


def _dense(t):
    return any(FN.is_dense(o) for o in t.objs)


def pieces_of(m):
    """[(area, set of floor tiles)]: each room piece (connected floor of one area, doors apart)."""
    by = defaultdict(set)
    for (x, y, z), t in m.tiles.items():
        if z == 1 and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
                and not t.apath.startswith(SKIP_AREA) and not CO.solid(t) and not _door(t):
            by[t.apath].add((x, y))
    out = []
    for area, tiles in by.items():
        left = set(tiles)
        while left:
            s = left.pop()
            comp, q = {s}, [s]
            while q:
                p = q.pop()
                for dx, dy in N4:
                    n = (p[0] + dx, p[1] + dy)
                    if n in left:
                        left.discard(n)
                        comp.add(n)
                        q.append(n)
            if len(comp) >= 6:
                out.append((area, comp))
    return out


def hall_dist(m):
    """Walking steps from the halls (hallway areas and the departments' corridor areas) to every open tile, over floor
    and through doors (furniture ignored, walls, windows and grilles not)."""
    dist = {}
    q = []
    for (x, y, z), t in m.tiles.items():
        if z == 1 and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")                 and (t.apath.startswith("/area/hallway") or t.apath in CORRIDOR_AREAS) and not CO.solid(t):
            dist[(x, y)] = 0
            q.append((x, y))
    i = 0
    while i < len(q):
        p = q[i]
        i += 1
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in dist:
                continue
            t = m.get(*n)
            if t is None or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space") or                     (CO.solid(t) and not _door(t)):
                continue
            dist[n] = dist[p] + 1
            q.append(n)
    return dist


def front_doors(m, F, doors, hd=None):
    """The room's front doors: its airlocks nearest the halls by walking (a room entered through a vestibule or another
    room counts the door it is entered by; windoors are counters, not ways in). A piece's depth is measured from
    these: from every door, a big room with fewer doors than its stock type had its back pieces "misplaced", and the
    stock bridges' console windoors made their consoles read as "front" (2026-11-26)."""
    if hd is None:
        hd = hall_dist(m)
    air = [d for d in doors if any(o.path.startswith("/obj/machinery/door/airlock") for o in m.get(*d).objs)] or list(doors)
    best = [(hd.get(d, 10 ** 6), d) for d in air]
    lo = min(b for b, _ in best)
    if lo >= 10 ** 6:
        return set(air)
    return {d for b, d in best if b <= lo + 2}


def measure(m):
    """(pieces [dict], rooms [dict]) for one map."""
    P, R = [], []
    hd = hall_dist(m)
    for area, F in pieces_of(m):
        doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if _door(m.get(p[0] + dx, p[1] + dy))}
        fronts = {p for p in F for dx, dy in N4 if (p[0] + dx, p[1] + dy) in doors}
        free = {p for p in F if not _dense(m.get(*p))}
        seen = set(fronts & free)
        q = list(seen)
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in free and n not in seen:
                    seen.add(n)
                    q.append(n)
        if not doors:
            continue
        xs, ys = [p[0] for p in F], [p[1] for p in F]
        span = max(1, (max(xs) - min(xs)) + (max(ys) - min(ys)))
        tc = Counter(m.get(*q).tpath for q in F)
        front = front_doors(m, F, doors, hd)
        R.append(dict(area=area, tiles=len(F), free=round(len(free) / float(len(F)), 3),
                      reach=round(len(seen) / float(max(1, len(free))), 3), doors=len(doors),
                      turf=tc.most_common(1)[0][0]))
        for p in F:
            t = m.get(*p)
            for o in t.objs:
                if not o.path.startswith(("/obj/structure", "/obj/machinery")) or o.path.startswith(SKIP_OBJ) \
                        or CO.mounted(o):
                    continue
                nbs = [(p[0] + dx, p[1] + dy) for dx, dy in N4]
                walls = sum(1 for n in nbs if _solid(m.get(*n)) and n not in doors)
                frees = [n for n in nbs if n in free]
                dd = min(abs(p[0] - d[0]) + abs(p[1] - d[1]) for d in front)
                P.append(dict(fam=family(o.path), area=area, at=p, walls=walls, front=p in fronts,
                              reach=any(n in seen for n in frees) or p in seen, boxed=not frees and not FN.is_dense(o) is False,
                              door_d=round(dd / float(span), 3)))
    return P, R


def build():
    per_fam = defaultdict(lambda: Counter())
    rooms = defaultdict(list)
    where = defaultdict(list)         # "area|family" -> door distances (share of the room's span)
    turfs = defaultdict(Counter)      # area -> main floor turf of its rooms
    for rel in CO.MAPS:
        path = os.path.join(CO.ROOT, "_maps", "map_files", rel)
        if not os.path.exists(path):
            continue
        P, R = measure(dmm.read(path))
        for p in P:
            c = per_fam[p["fam"]]
            c["n"] += 1
            c["wall"] += p["walls"] >= 1
            c["front"] += p["front"]
            c["reach"] += p["reach"]
            c["boxed"] += p["boxed"]
            where["%s|%s" % (p["area"], p["fam"])].append(p["door_d"])
        for r in R:
            rooms[r["area"]].append((r["free"], r["reach"], r["doors"]))
            turfs[r["area"]][r["turf"]] += 1
    out = dict(version=VERSION, fam={f: dict(c) for f, c in per_fam.items()},
               rooms={a: v for a, v in rooms.items()},
               where={k: sorted(v) for k, v in where.items() if len(v) >= 8},
               turfs={a: dict(c) for a, c in turfs.items()})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w"))
    return out


_S = None


def study():
    global _S
    if _S is None:
        if os.path.exists(OUT):
            d = json.load(open(OUT))
            if d.get("version") == VERSION:
                _S = d
        if _S is None:
            _S = build()
    return _S


def _q(v, f):
    v = sorted(v)
    return v[min(len(v) - 1, int(f * len(v)))] if v else None


def check(m):
    S = study()
    F = S["fam"]
    allroom = [x for v in S["rooms"].values() for x in v]
    P, R = measure(m)
    out = defaultdict(list)
    for p in P:
        c = F.get(p["fam"])
        if not c or c["n"] < 15:
            continue
        n = float(c["n"])
        name = p["fam"].replace("/obj/structure/", "").replace("/obj/machinery/", "")
        if p["walls"] == 0 and c["wall"] / n >= 0.9:
            out["off_wall"].append(p["at"] + ("%s off the wall in %s (stock: against one %.0f%%)" % (name, p["area"], 100 * c["wall"] / n),))
        if p["front"] and c["front"] / n <= 0.03:
            out["door_front"].append(p["at"] + ("%s on a door front in %s (stock %.1f%%)" % (name, p["area"], 100 * c["front"] / n),))
        if not p["reach"] and c["reach"] / n >= 0.95:
            out["unreachable"].append(p["at"] + ("%s no one reaches in %s (stock reached %.0f%%)" % (name, p["area"], 100 * c["reach"] / n),))
        # where in its room: a piece of a type the stock rooms keep at their front (a reception desk, a counter) or
        # their back (lockers, the server), well outside that spread
        w = S.get("where", {}).get("%s|%s" % (p["area"], p["fam"]))
        if w and p["fam"] not in ("/obj/structure/table", "/obj/structure/chair"):
            lo, hi = _q(w, 0.1), _q(w, 0.9)
            if hi - lo <= 0.4 and (p["door_d"] < lo - 0.25 or p["door_d"] > hi + 0.25):
                out["misplaced"].append(p["at"] + ("%s at %.2f of %s's depth from its door (stock %.2f-%.2f)" % (
                    name, p["door_d"], p["area"], lo, hi),))
    for r in R:
        v = S["rooms"].get(r["area"]) or allroom
        lo_reach = _q([x[1] for x in v], 0.1) if len(v) >= 5 else _q([x[1] for x in allroom], 0.1)
        fr = [x[0] for x in (v if len(v) >= 5 else allroom)]
        lo_free, hi_free = _q(fr, 0.05), _q(fr, 0.95)
        if r["reach"] < lo_reach:
            out["cut_room"].append((0, 0, "%s: doors reach %.0f%% of its free floor (stock 10th pct %.0f%%)" % (
                r["area"], 100 * r["reach"], 100 * lo_reach)))
        dc = [x[2] for x in (v if len(v) >= 5 else allroom) if len(x) > 2]
        if dc and len(v) >= 5 and r["area"] not in CORRIDOR_AREAS:
            lo_d, hi_d = _q(dc, 0.05), _q(dc, 0.95)
            if r["doors"] < lo_d or r["doors"] > hi_d:
                out["doors"].append((0, 0, "%s: %d doors (stock %d-%d)" % (r["area"], r["doors"], lo_d, hi_d)))
        tc = S.get("turfs", {}).get(r["area"])
        if tc and sum(tc.values()) >= 4 and r["area"] not in CORRIDOR_AREAS:
            fam_ = lambda t: "/".join(t.split("/")[:5])  # noqa: E731 - plasteel/white and its dark/checker kin
            if not any(fam_(t) == fam_(r["turf"]) for t in tc):
                out["floor"].append((0, 0, "%s floored %s (stock: %s)" % (
                    r["area"], r["turf"].replace("/turf/open/floor/", ""),
                    ", ".join(t.replace("/turf/open/floor/", "") for t, _ in sorted(tc.items(), key=lambda kv: -kv[1])[:3]))))
        if r["free"] < lo_free:
            out["crammed"].append((0, 0, "%s: %.0f%% of its floor free (stock 5th pct %.0f%%)" % (r["area"], 100 * r["free"], 100 * lo_free)))
        elif r["free"] > hi_free:
            out["bare"].append((0, 0, "%s: %.0f%% of its floor free (stock 95th pct %.0f%%)" % (r["area"], 100 * r["free"], 100 * hi_free)))
    out["_pieces"] = len(P)
    out["_rooms"] = len(R)
    return out


def summary(out):
    n = max(1, out.get("_pieces", 1))
    nr = max(1, out.get("_rooms", 1))
    return dict(pieces=out.get("_pieces"), rooms=out.get("_rooms"),
                off_wall=round(1000.0 * len(out["off_wall"]) / n, 1), door_front=round(1000.0 * len(out["door_front"]) / n, 1),
                unreachable=round(1000.0 * len(out["unreachable"]) / n, 1),
                misplaced=round(1000.0 * len(out["misplaced"]) / n, 1),
                doors=round(100.0 * len(out["doors"]) / nr, 1), floor=round(100.0 * len(out["floor"]) / nr, 1),
                cut_room=round(100.0 * len(out["cut_room"]) / nr, 1), crammed=round(100.0 * len(out["crammed"]) / nr, 1),
                bare=round(100.0 * len(out["bare"]) / nr, 1))


if __name__ == "__main__":
    if "--rebuild" in sys.argv or not os.path.exists(OUT):
        build()
    if "--stock" in sys.argv:
        for rel in CO.MAPS:
            path = os.path.join(CO.ROOT, "_maps", "map_files", rel)
            if os.path.exists(path):
                print("%-28s %s" % (os.path.basename(rel), summary(check(dmm.read(path)))), flush=True)
    elif "--check" in sys.argv:
        path = sys.argv[sys.argv.index("--check") + 1]
        out = check(dmm.read(path))
        print(summary(out))
        for k in ("off_wall", "door_front", "unreachable", "misplaced", "doors", "floor", "cut_room", "crammed", "bare"):
            for x in out[k][:25]:
                print("  %-11s %3d,%3d %s" % (k, x[0], x[1], x[2]))
    else:
        S = study()
        rows = sorted(S["fam"].items(), key=lambda kv: -kv[1]["n"])
        for f, c in rows[:60]:
            n = float(c["n"])
            print("%-52s n=%4d wall %3.0f%% front %4.1f%% reach %3.0f%%" % (f, c["n"], 100 * c.get("wall", 0) / n,
                                                                          100 * c.get("front", 0) / n, 100 * c.get("reach", 0) / n))
