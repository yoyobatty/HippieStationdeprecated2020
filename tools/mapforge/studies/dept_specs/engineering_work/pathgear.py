"""Safety gear along the engineers' way to the engine: the shortest walk from the department's front (its airlocks onto
a hall, tech storage's left out) to the crystal's chamber door, and how far off that walk the nearest shower,
radiation closet, fire closet and extinguisher stand (walking steps from any tile of the walk). Calibrates the
"safety station on the way in" rule of studies/dept_specs/engineering.md.

    python tools/mapforge/studies/dept_specs/engineering_work/pathgear.py [extra.dmm ...]
"""
import os
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import engstudy as ES  # noqa: E402
from forge import corpus as CO, function as FN  # noqa: E402


def grp(a):
    if a.startswith("/area/security/checkpoint/engineering"):
        return "engineering"
    return ES.ST.group_of(a) if a else None


def walkable(t):
    if t is None or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
        return False
    if ES.is_door(t):
        return True
    return not CO.solid(t) and not any(FN.is_dense(o) for o in t.objs)


def bfs_path(m, starts, goals):
    prev = {s: None for s in starts}
    q = deque(starts)
    while q:
        p = q.popleft()
        if p in goals:
            out = []
            while p is not None:
                out.append(p)
                p = prev[p]
            return out[::-1]
        for dx, dy in ES.N4:
            n = (p[0] + dx, p[1] + dy)
            if n in prev or not walkable(m.get(*n)):
                continue
            prev[n] = p
            q.append(n)
    return None


def near(m, path, fam, limit=12):
    """Fewest steps from any path tile to a tile holding fam (dense targets count as reached when adjacent)."""
    dist = {p: 0 for p in path}
    q = deque(path)
    while q:
        p = q.popleft()
        t = m.get(*p)
        if any(ES.fam(o.path) == fam for o in t.objs):
            return dist[p]
        if dist[p] >= limit:
            continue
        for dx, dy in ES.N4:
            n = (p[0] + dx, p[1] + dy)
            if n in dist:
                continue
            tn = m.get(*n)
            if tn is None:
                continue
            if any(ES.fam(o.path) == fam for o in tn.objs):
                return dist[p] + 1
            if walkable(tn):
                dist[n] = dist[p] + 1
                q.append(n)
    return None


def analyse(path):
    m, rooms = ES.study(path)
    fronts = []
    for r in rooms:
        if grp(r["area"]) != "engineering" or "storage/tech" in r["area"]:
            continue
        for d in r["doors"]:
            if d["path"].startswith("/obj/machinery/door/airlock") and any(b.startswith("/area/hallway") for b in d["beyond"]):
                fronts.append((d["x"], d["y"]))
    goals = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and any(
        o.path.startswith("/obj/machinery/door/airlock") and o.path.endswith("/critical") for o in t.objs)}
    if not goals:
        goals = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/engine/supermatter")
                 and ES.is_door(t)}
    p = bfs_path(m, fronts, goals) if fronts and goals else None
    if not p:
        return "no path (fronts %d, crystal doors %d)" % (len(fronts), len(goals))
    return "walk %3d  shower %s  rad %s  fire %s  ext %s  rooms on way: %s" % (
        len(p), near(m, p, "shower"), near(m, p, "rad_closet"), near(m, p, "fire_closet"), near(m, p, "extinguisher"),
        " > ".join(dict.fromkeys(m.get(*q).apath.replace("/area/", "") for q in p if not ES.is_door(m.get(*q)))))


if __name__ == "__main__":
    maps = [(n, os.path.join(ES.ROOT, "_maps", "map_files", p)) for n, p in ES.STOCK if n != "metalake"]
    maps += [(os.path.basename(p)[:10], p) for p in sys.argv[1:]]
    for n, p in maps:
        print("%-10s %s" % (n, analyse(p)))
