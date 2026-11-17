"""Whole-room templates: every room of every human-made map, kept as one design, fitted onto a target room.

    python tools/mapforge/forge/rooms.py                      # (re)build data/mapforge/rooms.json
    python tools/mapforge/forge/rooms.py /area/crew_quarters/heads/hor   # list the templates for a room type

A template is a room as a person laid it out: per floor tile its turf, furniture and items, its floor decals
(hazard stripes, trims), and the pieces hanging on its walls; plus which of its edges are wall, glass or door.
Infrastructure (pipes, cables, lights, APCs, alarms, cameras) is left out: the target room keeps its own.

fit(target, kind) tries every template of that room type in all 8 orientations. When sizes differ it keeps the
template's edge bands (the furniture along the walls) as they are and stretches or squeezes only its middle rows
and columns, choosing the emptiest ones, so rows stay rows and walkways stay walkways. Each candidate is scored on
shape, doors (the template's walkway must land in front of the target's doors) and nothing lost, then checked by
the caller with the usual rules.
"""
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402
from forge.corpus import MAPS, solid  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE = os.path.join(ROOT, "data", "mapforge", "rooms.json")
D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
SKIP = ("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/machinery/light", "/obj/machinery/power/apc",
        "/obj/machinery/power/terminal", "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/camera",
        "/obj/machinery/door", "/obj/structure/window", "/obj/structure/grille", "/obj/effect/spawner/structure/window",
        "/obj/structure/disposalpipe", "/obj/machinery/disposal", "/obj/effect/landmark", "/obj/effect/mapping_helpers",
        "/obj/machinery/navbeacon", "/obj/structure/plasticflaps", "/obj/machinery/light_switch", "/obj/effect/decal/cleanable",
        "/obj/machinery/conveyor", "/obj/machinery/conveyor_switch", "/obj/machinery/button", "/obj/machinery/holopad",
        "/obj/structure/lattice", "/obj/docking_port", "/obj/machinery/requests_console", "/obj/machinery/keycard_auth",
        "/obj/machinery/door_timer", "/obj/machinery/flasher", "/obj/structure/light_construct", "/mob")


def edge_kind(t):
    """wall / glass / door / open. Shutters over a window are glass; a windoor desk counts as a door (you stand at it)."""
    if t is None:
        return "wall"
    glassy = t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille")
    if t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/window"):
        return "door"
    if glassy:
        return "glass"
    if t.has("/obj/machinery/door/poddoor"):
        return "glass" if t.has("/obj/structure/table") else "door"
    if solid(t):
        return "wall"
    return "open"


def mine():
    rooms = []
    for rel in MAPS:
        path = os.path.join(ROOT, "_maps", "map_files", rel)
        if not os.path.exists(path):
            continue
        m = dmm.read(path)
        seen = set()
        for (x, y, z), t in m.tiles.items():
            if z != 1 or (x, y) in seen or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
                continue
            area = t.apath
            if area.startswith(("/area/space", "/area/maintenance", "/area/hallway", "/area/solar", "/area/shuttle")):
                continue
            room, q = set(), [(x, y)]
            seen.add((x, y))
            while q:
                p = q.pop()
                room.add(p)
                for dx, dy in D4.values():
                    n = (p[0] + dx, p[1] + dy)
                    nt = m.get(n[0], n[1], z)
                    if n not in seen and nt is not None and nt.apath == area and nt.tpath.startswith("/turf/open") \
                            and not nt.tpath.startswith("/turf/open/space") and not nt.has("/obj/machinery/door") \
                            and not nt.has("/obj/effect/spawner/structure/window"):
                        seen.add(n)
                        q.append(n)
            if not 6 <= len(room) <= 200:
                continue
            x0, y0 = min(p[0] for p in room), min(p[1] for p in room)
            cells = {}
            edges = {}
            n_furn = 0
            for p in room:
                tt = m.get(p[0], p[1], z)
                objs = [o.text() for o in tt.objs if not o.path.startswith(SKIP)]
                n_furn += any(not o.startswith("/obj/effect/turf_decal") and not o.startswith("/obj/item") for o in objs)
                cells["%d,%d" % (p[0] - x0, p[1] - y0)] = [tt.tpath] + objs
                for d, (dx, dy) in D4.items():
                    nb = (p[0] + dx, p[1] + dy)
                    if nb not in room:
                        edges["%d,%d,%d" % (p[0] - x0, p[1] - y0, d)] = edge_kind(m.get(nb[0], nb[1], z))
            if n_furn < 2:
                continue
            rooms.append({"area": area, "map": os.path.basename(rel), "at": [x0, y0], "cells": cells, "edges": edges,
                          "w": max(p[0] for p in room) - x0 + 1, "h": max(p[1] for p in room) - y0 + 1})
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(rooms, open(CACHE, "w"))
    return rooms


_R = None


def rooms():
    global _R
    if _R is None:
        _R = json.load(open(CACHE)) if os.path.exists(CACHE) else mine()
    return _R


def candidates(kind):
    """Templates of this room type: exact area, else its siblings (same parent path)."""
    rs = rooms()
    exact = [r for r in rs if r["area"] == kind]
    if exact:
        return exact
    parent = kind.rsplit("/", 1)[0]
    return [r for r in rs if r["area"].startswith(parent + "/") or r["area"] == parent]


# ----------------------------------------------------------------------------------------------- transforms
CW = {1: 4, 4: 2, 2: 8, 8: 1}
MX = {4: 8, 8: 4, 1: 1, 2: 2}


def tdir(d, k, mirror):
    if d in CW:
        if mirror:
            d = MX[d]
        for _ in range(k):
            d = CW[d]
        return d
    bits = [b for b in (1, 2, 4, 8) if d & b]
    return sum(tdir(b, k, mirror) for b in bits) if bits else d


def tatom(text, k, mirror):
    if k == 0 and not mirror:
        return text
    a = dmm.Atom.parse(text)
    vs = []
    px, py = a.num("pixel_x"), a.num("pixel_y")
    if mirror:
        px = -px
    for _ in range(k):
        px, py = py, -px
    directional = a.path.startswith(("/obj/structure/chair", "/obj/machinery/computer", "/obj/effect/turf_decal",
                                     "/obj/structure/bed", "/obj/machinery/sleeper", "/obj/machinery/chem"))
    d = a.get("dir")
    for n, v in a.vars:
        if n in ("pixel_x", "pixel_y", "dir"):
            continue
        vs.append((n, v))
    if d is not None or directional:
        dv = int(d) if d is not None and d.strip().lstrip("-").isdigit() else 2
        nd = tdir(dv, k, mirror)
        if nd != 2:
            vs.append(("dir", str(nd)))
    if px:
        vs.append(("pixel_x", str(px)))
    if py:
        vs.append(("pixel_y", str(py)))
    return dmm.Atom(a.path, vs).text()


def oriented(r, k, mirror):
    """Template cells/edges in one of 8 orientations, normalised to (0,0)."""
    def tp(x, y):
        if mirror:
            x = -x
        for _ in range(k):
            x, y = y, -x
        return x, y
    cells, edges = {}, {}
    for key, objs in r["cells"].items():
        x, y = map(int, key.split(","))
        cells[tp(x, y)] = [objs[0]] + [tatom(o, k, mirror) for o in objs[1:]]
    for key, kind in r["edges"].items():
        x, y, d = map(int, key.split(","))
        edges[(tp(x, y), tdir(d, k, mirror))] = kind
    mx = min(p[0] for p in cells)
    my = min(p[1] for p in cells)
    cells = {(p[0] - mx, p[1] - my): v for p, v in cells.items()}
    edges = {((p[0] - mx, p[1] - my), d): v for (p, d), v in edges.items()}
    return cells, edges


def axis_map(n_src, n_dst, weight):
    """Map destination indices 0..n_dst-1 onto source indices, keeping two edge bands each side and stretching or
    squeezing the middle by repeating/dropping its emptiest lines (weight[i] = how much stands on source line i)."""
    if n_src == n_dst:
        return list(range(n_dst))
    band = 2 if min(n_src, n_dst) >= 5 else 1
    head = list(range(band))
    tail = list(range(n_src - band, n_src))
    mid_src = list(range(band, n_src - band))
    need = n_dst - 2 * band
    if need <= 0:
        return (head + tail)[:n_dst]
    if not mid_src:
        return head + [head[-1]] * need + tail
    mid = list(mid_src)
    while len(mid) > need:  # drop the emptiest middle line
        mid.remove(min(mid, key=lambda i: (weight.get(i, 0), abs(i - n_src / 2))))
    while len(mid) < need:  # repeat the emptiest middle line next to itself
        i = min(mid_src, key=lambda i: (weight.get(i, 0), abs(i - n_src / 2)))
        mid.insert(mid.index(i), i)
    return head + mid + tail


def fit(target, target_edges, kind, required=(), limit=40, skip=None):
    """target: set of (x,y) floor tiles (a room, any position); target_edges: {(tile, dir): 'wall'|'glass'|'door'|'open'}.
    Yields (score, placement {tile: [turf, objs...]}, source description) best first."""
    tx0 = min(p[0] for p in target)
    ty0 = min(p[1] for p in target)
    tw = max(p[0] for p in target) - tx0 + 1
    th = max(p[1] for p in target) - ty0 + 1
    out = []
    for r in candidates(kind):
        if skip and skip(r):
            continue
        # (stretching a small room over a big one only spreads its furniture thin: keep sizes within reach)
        if r["w"] * r["h"] > 3 * tw * th or 2.2 * r["w"] * r["h"] < tw * th:
            continue
        for k in range(4):
            for mirror in (False, True):
                cells, edges = oriented(r, k, mirror)
                sw = max(p[0] for p in cells) + 1
                sh = max(p[1] for p in cells) + 1
                if abs(sw - tw) > max(3, tw * 2 // 5) or abs(sh - th) > max(3, th * 2 // 5):
                    continue
                colw = Counter()
                roww = Counter()
                for (x, y), objs in cells.items():
                    heavy = sum(1 for o in objs[1:] if not o.startswith(("/obj/effect/turf_decal", "/obj/item")))
                    colw[x] += heavy
                    roww[y] += heavy
                xm = axis_map(sw, tw, colw)
                ym = axis_map(sh, th, roww)
                place, score, used = {}, 0.0, set()
                for p in target:
                    sx, sy = xm[p[0] - tx0], ym[p[1] - ty0]
                    src = cells.get((sx, sy))
                    if src is None:
                        score -= 1.0  # a target tile with nothing behind it in the template
                        continue
                    objs = list(src)
                    # a line repeated by stretching must not repeat unique things (a second console, a second desk lamp)
                    # (a long table or bench grows; chairs, operating tables and plants don't: a stretched room
                    # gave grids of office chairs and three operating tables to one computer)
                    if (sx, sy) in used:
                        objs = [objs[0]] + [o for o in objs[1:] if o.startswith(("/obj/effect/turf_decal/tile", "/obj/structure/table",
                                                                                 "/obj/structure/chair/pew", "/obj/structure/chair/sofa"))
                                            and not o.startswith("/obj/structure/table/optable")]
                    used.add((sx, sy))
                    place[p] = objs
                    # edges: walls in the template where the target has walls
                    for d in D4:
                        te = target_edges.get((p, d))
                        se = edges.get(((sx, sy), d))
                        if te is None or se is None:
                            continue
                        if te == se:
                            score += 0.5
                        elif te == "door" and any(not o.startswith(("/obj/effect", "/obj/item")) for o in objs[1:]):
                            score -= 6.0  # furniture in front of a door
                        elif te == "glass" and se == "wall" and any(o.startswith(TALL_T) for o in objs[1:]):
                            score -= 3.0  # tall furniture that stood on a wall now against glass
                lost = Counter()
                have = Counter(o.split("{")[0] for objs in place.values() for o in objs[1:])
                for pth, n in required:
                    if have[pth] < n:
                        lost[pth] = n - have[pth]
                score -= 8.0 * sum(lost.values())
                score -= 0.6 * (abs(sw - tw) + abs(sh - th))
                out.append((score, place, "%s %s %d,%d rot%d%s" % (r["map"], r["area"].rsplit("/", 1)[-1], r["at"][0], r["at"][1],
                                                                   k, " mirrored" if mirror else ""), lost))
    out.sort(key=lambda o: -o[0])
    return out[:limit]


TALL_T = ("/obj/machinery/vending", "/obj/structure/closet", "/obj/structure/bookcase", "/obj/machinery/rnd",
          "/obj/machinery/suit_storage_unit", "/obj/structure/reagent_dispensers")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        rs = mine()
        print("%d room templates" % len(rs))
    else:
        for r in candidates(sys.argv[1]):
            print("%s %s at %s, %dx%d" % (r["map"], r["area"], r["at"], r["w"], r["h"]))


def valid(place, target, target_edges, dense):
    """The usual rules on a fitted room: doorways clear, floor not split, every piece reachable, no squeezes, tall
    pieces on real walls. dense(text) -> bool. Returns (ok, reason)."""
    from forge.furnish import components, squeezes, WALL_BOUND, TALL
    occ = {p for p, objs in place.items() if any(dense(o) for o in objs[1:])}
    free = set(target) - occ
    for (p, d), k in target_edges.items():
        if k == "door" and p in occ:
            return False, "blocks a door at %d,%d" % p
    if components(free) > components(set(target)):
        return False, "splits the room"
    # walk in from the doors (or any open edge): every free tile and every piece must be reachable
    starts = {p for (p, d), k in target_edges.items() if k in ("door", "open") and p in free}
    if starts:
        seen, q = set(starts), list(starts)
        while q:
            c = q.pop()
            for dx, dy in D4.values():
                n = (c[0] + dx, c[1] + dy)
                if n in free and n not in seen:
                    seen.add(n)
                    q.append(n)
    else:
        seen = free
    for p in occ:
        if not any((p[0] + dx, p[1] + dy) in seen for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy):
            return False, "something unreachable at %d,%d" % p
    # an R&D console links what it sees within 3 tiles (2020 tg)
    from forge.furnish import RND_MACHINE, RND_CONSOLE
    cons = [p for p, objs in place.items() if any(o.startswith(RND_CONSOLE) for o in objs[1:])]
    for p, objs in place.items():
        if any(o.startswith(RND_MACHINE) and "/department" not in o.split("{")[0] for o in objs[1:]):
            if not any(max(abs(p[0] - c[0]), abs(p[1] - c[1])) <= 3 for c in cons):
                return False, "R&D machine at %d,%d out of its console's reach" % p
    # machines that find their partner on a cardinal neighbour (cloning, DNA, surgery, nanites, teleporter)
    from forge.function import LINKS
    for p, objs in place.items():
        for o in objs[1:]:
            path = o.split("{")[0]
            for piece, groups in LINKS:
                if path == piece or path.startswith(piece + "/"):
                    for g in groups:
                        if not any(x.split("{")[0].startswith(g) for d in D4.values()
                                   for x in place.get((p[0] + d[0], p[1] + d[1]), [""])[1:]):
                            return False, "%s cut off from its %s at %d,%d" % (path.rsplit("/", 1)[-1], g[0].rsplit("/", 1)[-1], p[0], p[1])
                    break
    if squeezes(free, occ):
        return False, "squeeze"
    for p in occ:
        tall = [o for o in place[p][1:] if o.startswith(TALL + WALL_BOUND) and dense(o)]
        if not tall:
            continue
        kinds = [target_edges.get((p, d)) for d in D4]
        if "wall" not in kinds:
            if "glass" in kinds or tall[0].startswith(WALL_BOUND):
                return False, "%s off the wall at %d,%d" % (tall[0].split("{")[0].rsplit("/", 1)[-1], p[0], p[1])
    return True, ""
