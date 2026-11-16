"""How things sit in a room, learned from human-made maps: which way they face, where in the room they stand.

    python tools/mapforge/forge/orient.py            # (re)build data/mapforge/orient.json and print the habits

Facing, per object type, relative to its surroundings (not compass):
    away     its back to a wall, facing the open floor (sleepers, computers, chairs against a wall)
    to:<f>   facing a neighbour of family f (a chair to its table, an operating console to the table)
    along    a wall beside it, facing along the wall
    into     facing a wall (rare: usually a mistake)
    free     no wall around it
Placement, per type: corner (2+ walls) / wall (1) / open (0), and near / far from the room's door.

fix_facing(b) turns directional objects in a build whose facing breaks their type's habit; placement_bonus() is
used by the furnisher to score where a piece goes.
"""
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402
from forge.corpus import ANCHOR, INFRA, MAPS, mounted, solid  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE = os.path.join(ROOT, "data", "mapforge", "orient.json")
D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
OPP = {1: 2, 2: 1, 4: 8, 8: 4}


def family(path):
    parts = path.split("/")
    return "/".join(parts[:4]) if len(parts) > 4 else path


def anchors_at(t):
    if t is None:
        return []
    return [o for o in t.objs if o.path.startswith(ANCHOR) and not o.path.startswith(INFRA) and not mounted(o)]


def relation(d, walls, neigh):
    """walls: set of solid sides; neigh: side -> family of the anchor there."""
    if d in neigh:
        return "to:" + neigh[d]
    if d in walls:
        return "into"
    if OPP[d] in walls:
        return "away"
    if walls:
        return "along"
    return "free"


def mine():
    face = defaultdict(Counter)
    front = defaultdict(Counter)  # path -> "blocked"/"free": is the tile it faces furnished?
    wfront = defaultdict(Counter)  # same for the tile opposite its wall (machines without a facing: fabs, lockers)
    dirs = defaultdict(Counter)
    place = defaultdict(Counter)
    for rel in MAPS:
        path = os.path.join(ROOT, "_maps", "map_files", rel)
        if not os.path.exists(path):
            continue
        m = dmm.read(path)
        doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door/airlock")}
        for (x, y, z), t in m.tiles.items():
            if z != 1 or not t.tpath.startswith("/turf/open"):
                continue
            an = anchors_at(t)
            if not an:
                continue
            walls = {d for d, (dx, dy) in D4.items() if solid(m.get(x + dx, y + dy, z))}
            neigh = {}
            for d, (dx, dy) in D4.items():
                na = anchors_at(m.get(x + dx, y + dy, z))
                if na:
                    neigh[d] = family(na[0].path)
            for a in an[:1]:
                p = a.path
                d = a.num("dir", 2)
                dirs[p][d] += 1
                if d in OPP:
                    face[p][relation(d, walls, neigh)] += 1
                    fx, fy = D4[d]
                    ft = m.get(x + fx, y + fy, z)
                    if ft is not None and not solid(ft):
                        front[p]["blocked" if anchors_at(ft) else "free"] += 1
                if len(walls) == 1:
                    wd = OPP[next(iter(walls))]
                    ft = m.get(x + D4[wd][0], y + D4[wd][1], z)
                    if ft is not None and not solid(ft):
                        wfront[p]["blocked" if anchors_at(ft) else "free"] += 1
                loc = "corner" if len(walls) >= 2 else "wall" if walls else "open"
                dd = min((abs(x - a2) + abs(y - b2) for a2, b2 in doors), default=99)
                place[p]["%s|%s" % (loc, "near" if dd <= 3 else "far")] += 1
    out = {"face": {k: dict(v) for k, v in face.items()}, "front": {k: dict(v) for k, v in front.items()},
           "wfront": {k: dict(v) for k, v in wfront.items()}, "dirs": {k: {str(a): b for a, b in v.items()} for k, v in dirs.items()},
           "place": {k: dict(v) for k, v in place.items()}}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(out, open(CACHE, "w"))
    return out


_M = None


def model():
    global _M
    if _M is None:
        _M = json.load(open(CACHE)) if os.path.exists(CACHE) else mine()
    return _M


def lookup(table, path):
    """Exact type, else its parent types."""
    t = model()[table]
    p = path
    while p.count("/") > 2:
        if p in t and sum(t[p].values()) >= 3:
            return t[p]
        p = p.rsplit("/", 1)[0]
    return None


FLOW = ("/obj/machinery/conveyor", "/obj/structure/reflector", "/obj/machinery/atmospherics", "/obj/structure/disposalpipe",
        "/obj/machinery/power/emitter", "/obj/machinery/mineral", "/obj/machinery/door")  # dir = flow or aim, not facing


def directional(path):
    if path.startswith(FLOW):
        return False
    d = lookup("dirs", path)
    return bool(d) and len([v for v in d.values() if v >= 1]) >= 2


def best_dir(path, walls, neigh, current):
    """The dir whose relation the type shows most often; current dir kept unless it's clearly unusual."""
    f = lookup("face", path)
    if not f or current not in OPP:
        return current
    tot = sum(f.values())

    def score(d):
        r = relation(d, walls, neigh)
        if r.startswith("to:"):
            return f.get(r, 0) / tot + 0.5 * f.get("to:" + r[3:].rsplit("/", 1)[0], 0) / tot
        return f.get(r, 0) / tot
    cur = score(current)
    best = max((1, 2, 4, 8), key=lambda d: (score(d), d == current))
    if cur < 0.15 and score(best) >= 0.4:
        return best
    return current


def fix_facing(b, tiles=None):
    """Re-face directional objects in the zone (or the given tiles) to their type's habit. Returns changes."""
    changed = []
    m = b.m
    for p in sorted(tiles if tiles is not None else b.zone):
        t = m.get(*p)
        if t is None:
            continue
        an = anchors_at(t)
        if not an:
            continue
        a = an[0]
        if not directional(a.path):
            continue
        walls = {d for d, (dx, dy) in D4.items() if b.solid((p[0] + dx, p[1] + dy)) or b.kind((p[0] + dx, p[1] + dy)) in ("window", "rwindow")}
        neigh = {}
        for d, (dx, dy) in D4.items():
            na = anchors_at(m.get(p[0] + dx, p[1] + dy))
            if na:
                neigh[d] = family(na[0].path)
        cur = a.num("dir", 2)
        nd = best_dir(a.path, walls, neigh, cur)
        if nd != cur:
            a.vars = [(k, v) for k, v in a.vars if k != "dir"] + ([("dir", str(nd))] if nd != 2 else [])
            changed.append((p, a.path, cur, nd))
    return changed


def placement_bonus(path, loc, near):
    c = lookup("place", path)
    if not c:
        return 0.0
    tot = sum(c.values())
    key = "%s|%s" % (loc, "near" if near else "far")
    # how much more likely than an even spread over the six cells
    return 6.0 * c.get(key, 0) / tot - 1.0


if __name__ == "__main__":
    M = mine()
    for p in ("/obj/machinery/sleeper", "/obj/machinery/computer/operating", "/obj/machinery/computer/med_data",
              "/obj/structure/chair/office/light", "/obj/structure/chair", "/obj/machinery/computer/crew",
              "/obj/machinery/chem_dispenser", "/obj/machinery/vending/medical", "/obj/structure/bed/roller",
              "/obj/machinery/bodyscanner", "/obj/machinery/computer/rdconsole/core", "/obj/structure/table/optable"):
        print("%-40s face %s" % (p, dict(Counter(M["face"].get(p, {})).most_common(4))))
        print("%-40s place %s" % ("", dict(Counter(M["place"].get(p, {})).most_common(4))))


def mirror_pairs(b, tiles):
    """Two of the same directional thing standing in mirror spots of a room face mirror ways (a sleeper pair in the far
    corners faces each other): if one faces across the mirror line, the other is set to its reflection."""
    m = b.m
    tiles = set(tiles)
    if not tiles:
        return []
    cx = (min(p[0] for p in tiles) + max(p[0] for p in tiles)) / 2.0
    cy = (min(p[1] for p in tiles) + max(p[1] for p in tiles)) / 2.0
    by = {}
    for p in tiles:
        an = anchors_at(m.get(*p))
        if an and directional(an[0].path):
            by.setdefault(an[0].path, []).append((p, an[0]))
    flipx = {4: 8, 8: 4, 1: 1, 2: 2}
    flipy = {1: 2, 2: 1, 4: 4, 8: 8}
    changed = []
    for path, items in by.items():
        for i, (p, a) in enumerate(items):
            for q, c in items[i + 1:]:
                da, dc = a.num("dir", 2), c.num("dir", 2)
                if da not in flipx or dc not in flipx:
                    continue
                if p[1] == q[1] and abs((p[0] - cx) + (q[0] - cx)) < 0.6:
                    want = flipx
                elif p[0] == q[0] and abs((p[1] - cy) + (q[1] - cy)) < 0.6:
                    want = flipy
                else:
                    continue
                if want[da] == dc:
                    continue
                # keep the one facing across the mirror line, reflect it onto the other
                across = (lambda d: d in (4, 8)) if want is flipx else (lambda d: d in (1, 2))
                src, dst, sd = (a, c, da) if across(da) else (c, a, dc)
                nd = want[sd]
                dst.vars = [(k, v) for k, v in dst.vars if k != "dir"] + ([("dir", str(nd))] if nd != 2 else [])
                changed.append((path, nd))
    return changed


def keep_front_clear(b, tiles):
    """The tile a sleeper, console or dispenser faces is where you stand to use it: human maps almost never furnish
    it. Furnished pieces standing there are removed (with whatever was on them)."""
    m = b.m
    cleared = []
    for p in sorted(tiles):
        an = anchors_at(m.get(*p))
        if not an:
            continue
        if directional(an[0].path):
            fr = lookup("front", an[0].path)
            d = an[0].num("dir", 2)
        else:
            # no facing: its front is the side away from its wall (a fab, a locker, a vendor)
            walls = [w for w in D4 if b.solid((p[0] + D4[w][0], p[1] + D4[w][1]))]
            if len(walls) != 1 or not an[0].path.startswith("/obj/machinery"):
                continue
            fr = lookup("wfront", an[0].path)
            d = OPP[walls[0]]
        if not fr or sum(fr.values()) < 3 or fr.get("blocked", 0) / sum(fr.values()) > 0.15:
            continue
        if d not in D4:
            continue
        q = (p[0] + D4[d][0], p[1] + D4[d][1])
        if q not in getattr(b, "furnished", ()) or not anchors_at(m.get(*q)):
            continue
        t = m.get(*q)
        keep = ("/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposal", "/obj/machinery/disposal",
                "/obj/effect", "/obj/machinery/light", "/obj/machinery/door", "/obj/machinery/power", "/obj/machinery/airalarm",
                "/obj/machinery/firealarm", "/obj/machinery/camera", "/obj/machinery/light_switch")
        gone = [o.path for o in t.objs if not o.path.startswith(keep) and abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16]
        t.objs = [o for o in t.objs if o.path.startswith(keep) or abs(o.num("pixel_x")) >= 16 or abs(o.num("pixel_y")) >= 16]
        cleared.append((q, an[0].path, gone))
    return cleared
