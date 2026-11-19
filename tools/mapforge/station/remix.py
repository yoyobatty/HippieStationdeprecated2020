"""Stations remixed from human ones (the user's rulings of 2026-11-18: "build departments from real stock-map rooms
and layouts (cut, adapt and stitch pieces of the 38 human maps)", and for the whole station "real skeletons,
remixed").

    python tools/mapforge/station/remix.py MetaStation --seed 1 [--only medical,science] [--dry]

A skeleton is one of the human stations as it is: its halls, its maint, its hull, engineering, atmospherics, the
AI satellite, the docks and shuttles. Each department zone in it is then rebuilt with a whole department cut from
another human map (forge/depts.py), turned and mirrored to fit:

    zone      the skeleton's department floor, its inner walls and doors, and maint within 3 tiles of it (the
              slack a donor of another shape needs); the walls it shares with halls are kept, only a door may be cut
              into them, and walls on other rooms or space are never touched
    fit       every orientation and offset where the donor's floor lies on zone tiles, its walls land on zone tiles
              or on wall the skeleton already has, and at least one of its hall doors opens onto a skeleton hall;
              scored for hall doors on halls, maint doors on maint, how much of the old department it covers
    leftover  zone floor the donor doesn't use becomes maint; an old hall door into it becomes a maint door; a pocket
              with no way in becomes wall
    build     forge/build.py rebuilds the zone in the skeleton: the donor's rooms keep their own areas, floors,
              furniture, decals and wall pieces (furnish mode "copy"); the builder lays airlocks' firelocks,
              lights, APCs, alarms, vents and cable, and joins pipes and power to the skeleton's at the zone edge

Job start landmarks and one-of-a-kind items (the nuke disk, the spare ID, the pets) from the old zone are put back
in the new department. Output: data/mapforge/remix/remix_<skeleton>_s<seed>.dmm
"""
import argparse
import os
import random
import re
import sys
import types
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, depts, dmm, kit, typeindex  # noqa: E402
from forge import rooms as RM  # noqa: E402
from forge import build as B  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "mapforge", "remix")
SKELETONS = ("MetaStation", "DeltaStation", "BoxStation", "PubbyStation", "DonutStation", "HippieStation",
             "MiniStation", "EndoStation")
SWAP = ("medical", "science", "security", "cargo", "command", "service", "dorms", "civic")
SLACK = 5
D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
D8 = D4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))
DIRW = {"north": 1, "south": 2, "east": 4, "west": 8}
WDIR = {v: k for k, v in DIRW.items()}
FALLBACK_AREA = {"medical": "/area/medical/medbay/central", "science": "/area/science/research",
                 "security": "/area/security/main", "cargo": "/area/quartermaster/storage", "command": "/area/bridge",
                 "service": "/area/crew_quarters/bar", "dorms": "/area/crew_quarters/dorms", "civic": "/area/library"}
UNIQUE = ("/obj/item/disk/nuclear", "/obj/item/card/id/captains_spare", "/obj/machinery/nuclearbomb/selfdestruct",
          "/mob/living/simple_animal/pet/dog/corgi/Ian", "/mob/living/simple_animal/pet/cat/Runtime",
          "/mob/living/simple_animal/parrot/Poly", "/mob/living/simple_animal/pet/dog/pug/mcgriff",
          "/mob/living/simple_animal/sloth/paperwork", "/mob/living/simple_animal/pet/fox/Renault",
          "/obj/item/areaeditor/blueprints", "/obj/item/hand_tele", "/obj/item/aicard",
          "/obj/machinery/computer/upload/ai", "/obj/machinery/computer/upload/borg",
          "/obj/structure/displaycase/captain")
FAMILY = (("meta", "metalake", "icemeta"), ("box", "hippie"), ("delta",), ("pubby",), ("donut",), ("mini",),
          ("endo",), ("kilo",), ("omega",), ("cere",))


def family(name):
    n = name.split(":")[-1].lower()
    for fam in FAMILY:
        if any(n.startswith(f) for f in fam):
            return fam[0]
    return n


# ------------------------------------------------------------------------------------------ donor orientations
def rot_door(text, k, mirror):
    """A door atom turned with its piece: windoor paths name their facing (northleft) and hinge (left/right)."""
    a = RM.tatom(text, k, mirror)
    m = re.match(r"^(/obj/machinery/door/window/(?:brigdoor/)?(?:[a-z_]+/)?)(north|south|east|west)(left|right)(.*)$", a)
    if m:
        d = RM.tdir(DIRW[m.group(2)], k, mirror)
        hinge = m.group(3)
        if mirror:
            hinge = "right" if hinge == "left" else "left"
        a = m.group(1) + WDIR[d] + hinge + m.group(4)
    return a


def oriented(pc, k, mirror):
    def tp(key):
        x, y = map(int, key.split(","))
        if mirror:
            x = -x
        for _ in range(k):
            x, y = y, -x
        return x, y
    cells = {tp(key): v for key, v in pc["cells"].items()}
    mx = min(p[0] for p in cells)
    my = min(p[1] for p in cells)

    def n(p):
        return (p[0] - mx, p[1] - my)
    out = types.SimpleNamespace()
    out.cells = {n(p): [v[0], v[1]] + [RM.tatom(o, k, mirror) for o in v[2:]] for p, v in cells.items()}
    out.doors = {n(tp(key)): [rot_door(o, k, mirror) for o in v] for key, v in pc["doors"].items()}
    out.glass = {n(tp(key)) for key in pc["glass"]}
    out.exits = {n(tp(key)): v for key, v in pc["exits"].items()}
    fl = set(out.cells)
    ring = set()
    for p in fl:
        for dx, dy in D8:
            q = (p[0] + dx, p[1] + dy)
            if q not in fl:
                ring.add(q)
    out.floor, out.ring = fl, ring
    return out


# ------------------------------------------------------------------------------------------ skeleton zones
def kind_of(sm, p):
    c = sm.cls.get(p)
    if c is None or c == "S":
        return "space"
    if c != "F":
        return c
    r = sm.regions.get(sm.region.get(p))
    return r.kind if r else "other"


def zones(sm, groups):
    """group -> zone: D (department floor), M (maint slack), Zw (inner walls/doors), Zb (walls shared with halls)."""
    out = {}
    taken = set()
    comps = {}
    for g in groups:
        cs = depts.cut(sm, g)
        if cs:
            comps[g] = max(cs, key=len)
            taken |= comps[g]
    # maint slack: BFS through maint from each department, nearest department wins a tile
    owner, dist = {}, {}
    frontier = []
    for g, D in comps.items():
        for p in D:
            frontier.append((p, g))
    for step in range(1, SLACK + 1):
        nxt = []
        for p, g in frontier:
            for dx, dy in D4:
                q = (p[0] + dx, p[1] + dy)
                if q in taken or q in owner:
                    continue
                k = kind_of(sm, q)
                if k == "maint":
                    owner[q] = g
                    nxt.append((q, g))
                elif k in ("W", "D") and step == 1:
                    # through one wall into maint behind it
                    q2 = (q[0] + dx, q[1] + dy)
                    if kind_of(sm, q2) == "maint" and q2 not in taken and q2 not in owner:
                        owner[q2] = g
                        nxt.append((q2, g))
        frontier = nxt
    for g, D in comps.items():
        M = {p for p, o in owner.items() if o == g}
        F = D | M
        Zw, Zb = set(), set()
        for p in D:
            for dx, dy in D8:
                q = (p[0] + dx, p[1] + dy)
                if q in F or sm.cls.get(q) not in ("W", "D"):
                    continue
                # what the wall touches besides the zone
                outside = {kind_of(sm, (q[0] + ex, q[1] + ey)) for ex, ey in D8
                           if (q[0] + ex, q[1] + ey) not in F and sm.cls.get((q[0] + ex, q[1] + ey)) == "F"}
                space = any(sm.cls.get((q[0] + ex, q[1] + ey)) in (None, "S") for ex, ey in D8)
                if not outside and not space:
                    Zw.add(q)
                elif outside <= {"hall", "maint"} and not space:
                    Zb.add(q)
        # walls between maint slack tiles (only touching the zone) are inner too
        for p in M:
            for dx, dy in D8:
                q = (p[0] + dx, p[1] + dy)
                if q in F or q in Zw or q in Zb or sm.cls.get(q) != "W" or q in sm.glass:
                    continue
                if all((q[0] + ex, q[1] + ey) in F or sm.cls.get((q[0] + ex, q[1] + ey)) == "W"
                       for ex, ey in D8):
                    Zw.add(q)
        # the skeleton's own rooms in the department: one may stay as it is where the donor leaves it whole
        orig = {}
        for p in D:
            orig.setdefault(sm.region.get(p), set()).add(p)
        rooms = []
        for tiles in orig.values():
            ring = {(p[0] + dx, p[1] + dy) for p in tiles for dx, dy in D8} - tiles
            exits = [q for q in ring if sm.cls.get(q) == "D"]
            rooms.append((tiles, ring, exits))
        out[g] = types.SimpleNamespace(g=g, D=D, M=M, F=F, Zw=Zw, Zb=Zb, rooms=rooms)
    return out


# ------------------------------------------------------------------------------------------ fitting
def room_parts(op):
    """The donor's rooms with what fitting needs: floor, ring, doors and the links between rooms."""
    if hasattr(op, "parts"):
        return op.parts
    rid = regions(op.cells)
    nr = max(rid.values()) + 1
    tiles = [[] for _ in range(nr)]
    for p, r in rid.items():
        tiles[r].append(p)
    rings, openh = [], []
    for r in range(nr):
        fs = set(tiles[r])
        ring = set()
        for p in fs:
            for dx, dy in D8:
                q = (p[0] + dx, p[1] + dy)
                if q not in fs:
                    ring.add(q)
        rings.append(sorted(ring))
        openh.append({q for q in ring if q not in op.cells and op.exits.get(q) == "open-hall"})
    links = set()
    for p, r in rid.items():
        for dx, dy in D4:
            q = (p[0] + dx, p[1] + dy)
            if q in rid and rid[q] != r:
                links.add((min(r, rid[q]), max(r, rid[q])))
    # every door side: (door tile, room inside, the tile past it)
    dside = []
    for d in op.doors:
        for dx, dy in D4:
            f = (d[0] - dx, d[1] - dy)
            if f in rid:
                dside.append((d, rid[f], (d[0] + dx, d[1] + dy)))
    op.parts = types.SimpleNamespace(rid=rid, tiles=tiles, rings=rings, openh=openh, links=links, dside=dside)
    return op.parts


def place(sm, z, op, parts, keep, ox, oy):
    """One placement with the rooms in keep: drop room groups with no way out; (score, info, kept rooms)."""
    A2 = z.F | z.Zw | z.Zb
    rid = parts.rid
    P = lambda p: (p[0] + ox, p[1] + oy)  # noqa: E731
    kept_floor = {P(p) for p, r in rid.items() if r in keep}
    walls = set()
    for r in keep:
        for q in parts.rings[r]:
            if q not in op.cells or rid[q] not in keep:
                walls.add(P(q))
    walls -= kept_floor
    par = {r: r for r in keep}

    def root(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for a, b in parts.links:
        if a in keep and b in keep:
            par[root(a)] = root(b)
    ex = Counter()      # (root, kind) -> count
    for d, r, o in parts.dside:
        if r not in keep:
            continue
        if o in rid and rid[o] in keep:
            if rid[o] != r:
                par[root(r)] = root(rid[o])
            continue
        Q, O = P(d), P(o)
        if Q not in A2 or O in walls:
            continue
        if O in getattr(z, "walk", ()):
            ex[(r, "room")] += 1
            continue
        if O in z.F and O not in kept_floor:
            ex[(r, "maint")] += 1
            continue
        k = kind_of(sm, O)
        if k in ("hall", "maint", "room"):
            ex[(r, k)] += 1
    for r in keep:
        for q in parts.openh[r]:
            Q = P(q)
            if Q not in A2 and kind_of(sm, Q) == "hall":
                ex[(r, "hall")] += 1
    per = Counter()
    for (r, k), n in ex.items():
        per[(root(r), k)] += n
    live = {r for r in keep if any(per[(root(r), k)] for k in ("hall", "maint", "room"))}
    if not live:
        return None
    hall = sum(n for (rt, k), n in per.items() if k == "hall" and rt in {root(r) for r in live})
    maint = sum(n for (rt, k), n in per.items() if k == "maint" and rt in {root(r) for r in live})
    if not hall and getattr(z, "need_hall", True):
        return None
    live_floor = {P(p) for p, r in rid.items() if r in live}
    live_walls = set()
    for r in live:
        for q in parts.rings[r]:
            if q not in op.cells or rid[q] not in live:
                live_walls.add(P(q))
    live_walls -= live_floor
    origs = []
    for tiles, ring, doors in z.rooms:
        if tiles & live_floor or tiles & live_walls or ring & live_floor:
            continue
        if not any(d not in live_walls for d in doors):
            continue
        origs.append(tiles)
    nD = float(len(z.D))
    don = sum(1 for p in live_floor if p in z.D)
    old = sum(len(t) for t in origs)
    cover = (don + old) / nD
    n = len(op.cells)
    kept = sum(len(parts.tiles[r]) for r in live) / float(n)
    score = 100 * cover + 25 * min(hall, 3) + 4 * min(maint, 4) + 20 * kept + 40 * don / nD
    return score, dict(hall=hall, maint=maint, cover=cover, kept=kept, old=old,
                       rooms="%d/%d" % (len(live), len(parts.tiles))), live, origs


def zone_grid(sm, z, M=70):
    """Zone masks as numpy grids, once per zone: A1 donor floor may go here, B donor wall may, H skeleton hall,
    D old department floor. M is the margin: the widest donor that can be tried."""
    import numpy as np
    if getattr(z, "grid", None) is not None:
        return z.grid
    A1 = z.F | z.Zw
    A2 = z.F | z.Zw | z.Zb
    block = getattr(z, "block", set())
    xs = [p[0] for p in A2]
    ys = [p[1] for p in A2]
    X0, X1, Y0, Y1 = min(xs), max(xs), min(ys), max(ys)
    gx0, gy0 = X0 - M - 2, Y0 - M - 2
    GW, GH = X1 - X0 + 2 * M + 5, Y1 - Y0 + 2 * M + 5
    gA1 = np.zeros((GW, GH), bool)
    gB = np.zeros((GW, GH), bool)
    gH = np.zeros((GW, GH), bool)
    gD = np.zeros((GW, GH), np.int16)
    for x in range(max(0, M - 6), GW - max(0, M - 6)):
        for y in range(max(0, M - 6), GH - max(0, M - 6)):
            p = (x + gx0, y + gy0)
            if p in A1:
                gA1[x, y] = True
            c = sm.cls.get(p)
            if p in block:
                pass
            elif p in A2 or c in ("W", "D"):
                gB[x, y] = True
            elif c == "F" and kind_of(sm, p) == "hall":
                gH[x, y] = True
            if p in z.D:
                gD[x, y] = 1
    z.grid = types.SimpleNamespace(X0=X0, X1=X1, Y0=Y0, Y1=Y1, M=M, A1=gA1, B=gB, H=gH, D=gD)
    return z.grid


def fit(sm, z, op, min_keep=0.7):
    """Best placement of an oriented donor in zone z, dropping whole rooms that don't fit:
    (score, (dx, dy), info, kept rooms) or None. Every room is tested at every offset at once (numpy): its floor
    must land on zone floor or inner wall, its walls on writable zone tiles or on solid skeleton wall, an open side
    onto a hall only where the donor had one."""
    import numpy as np
    parts = room_parts(op)
    G = zone_grid(sm, z)
    X0, X1, Y0, Y1, M = G.X0, G.X1, G.Y0, G.Y1, G.M
    fw = max(p[0] for p in op.floor)
    fh = max(p[1] for p in op.floor)
    if fw > M or fh > M:
        return None
    nox, noy = X1 - X0 + fw + 1, Y1 - Y0 + fh + 1
    gA1, gB, gH, gD = G.A1, G.B, G.H, G.D

    def sl(g, t):
        i, j = t[0] + M - fw + 2, t[1] + M - fh + 2
        return g[i:i + nox, j:j + noy]
    nr = len(parts.tiles)
    fits = np.zeros((nr, nox, noy), bool)
    kept = np.zeros((nox, noy), np.int32)
    cov = np.zeros((nox, noy), np.int32)
    for r in range(nr):
        m = np.ones((nox, noy), bool)
        for t in parts.tiles[r]:
            m &= sl(gA1, t)
        if not m.any():
            continue
        oh = parts.openh[r]
        for t in parts.rings[r]:
            if t in oh:
                m &= sl(gB, t) | sl(gH, t)
            else:
                m &= sl(gB, t)
        if not m.any():
            continue
        fits[r] = m
        kept += m * len(parts.tiles[r])
        c = np.zeros((nox, noy), np.int32)
        for t in parts.tiles[r]:
            c += sl(gD, t)
        cov += c * m
    n = len(op.cells)
    ok = kept >= min_keep * n
    if not ok.any():
        return None
    pre = np.where(ok, cov * 100.0 / len(z.D) + 20.0 * kept / n, -1.0)
    flat = np.argsort(pre, axis=None)[::-1][:60]
    best = None
    for f in flat:
        i, j = np.unravel_index(f, pre.shape)
        if pre[i, j] < 0:
            break
        keep = {r for r in range(nr) if fits[r, i, j]}
        ox, oy = int(i) + X0 - fw, int(j) + Y0 - fh
        r_ = place(sm, z, op, parts, keep, ox, oy)
        if r_ and r_[1]["kept"] >= min_keep and (best is None or r_[0] > best[0]):
            best = (r_[0], (ox, oy), r_[1], r_[2], r_[3])
    return best


def trimmed(op, live):
    """The oriented donor with only the rooms in live: a namespace blueprint() takes."""
    parts = room_parts(op)
    out = types.SimpleNamespace()
    out.cells = {p: v for p, v in op.cells.items() if parts.rid[p] in live}
    fl = set(out.cells)
    ring = set()
    for p in fl:
        for dx, dy in D8:
            q = (p[0] + dx, p[1] + dy)
            if q not in fl:
                ring.add(q)
    out.floor, out.ring = fl, ring
    out.doors = {d: v for d, v in op.doors.items() if any((d[0] + dx, d[1] + dy) in fl for dx, dy in D4)}
    out.glass = op.glass & ring
    out.exits = {p: v for p, v in op.exits.items() if p in ring}
    # a door between a kept room and a dropped one is an edge door now
    for d in out.doors:
        if d not in out.exits and not all((d[0] + dx, d[1] + dy) in fl for dx, dy in ((1, 0), (-1, 0))) \
                and not all((d[0] + dx, d[1] + dy) in fl for dx, dy in ((0, 1), (0, -1))):
            out.exits[d] = "room"
    return out


def choose(sm, z, lib, rnd, skel_fam, used_fam):
    """The donor for one zone: candidates of the group from other map families, sized like the zone."""
    target = len(z.D)
    room = len(z.F)
    cands = [pc for pc in lib if pc["group"] == z.g and family(pc["map"]) != skel_fam
             and 0.55 * target <= pc["n"] <= 1.3 * room]
    rnd.shuffle(cands)
    cands.sort(key=lambda pc: (family(pc["map"]) in used_fam, abs(pc["n"] - target) / float(target)))
    found = []
    for pc in cands[:14]:
        for k in range(4):
            for mirror in (False, True):
                op = oriented(pc, k, mirror)
                r = fit(sm, z, op)
                if r:
                    r[2]["origs"] = r[4]
                    found.append((r[0] + 10 * rnd.random(), pc, trimmed(op, r[3]), r[1], r[2], (k, mirror)))
        if len(found) >= 6:
            break
    if not found:
        return None
    return max(found, key=lambda f: f[0])


def shifted(op, off):
    """An oriented donor moved to station coordinates."""
    ox, oy = off
    P = lambda p: (p[0] + ox, p[1] + oy)  # noqa: E731
    out = types.SimpleNamespace()
    out.cells = {P(p): v for p, v in op.cells.items()}
    out.doors = {P(p): v for p, v in op.doors.items()}
    out.glass = {P(p) for p in op.glass}
    out.exits = {P(p): v for p, v in op.exits.items()}
    out.floor = {P(p) for p in op.floor}
    out.ring = {P(p) for p in op.ring}
    return out


def normalized(op):
    mx = min(p[0] for p in op.floor)
    my = min(p[1] for p in op.floor)
    return shifted(op, (-mx, -my))


def merged(a, b):
    """Two placed donors as one (b's doors win over a's walls: a fill room may cut a door into the main piece)."""
    out = types.SimpleNamespace()
    out.cells = dict(a.cells)
    out.cells.update(b.cells)
    out.doors = dict(a.doors)
    out.doors.update(b.doors)
    out.glass = (a.glass | b.glass) - set(b.doors) - set(a.doors)
    out.exits = dict(a.exits)
    out.exits.update(b.exits)
    out.floor = set(out.cells)
    out.ring = (a.ring | b.ring) - out.floor
    return out


def room_pool(lib, g, skel_fam, rnd, limit=16):
    """Single rooms of group g from other map families, every orientation, ready to fit."""
    pcs = [pc for pc in lib if pc["group"] == g and family(pc["map"]) != skel_fam]
    rnd.shuffle(pcs)
    out = []
    for pc in pcs[:limit]:
        for k in range(4):
            for mirror in (False, True):
                op = oriented(pc, k, mirror)
                parts = room_parts(op)
                for r, tiles in enumerate(parts.tiles):
                    if not 10 <= len(tiles) <= 160:
                        continue
                    one = normalized(trimmed(op, {r}))
                    if not one.doors:
                        continue
                    area = op.cells[tiles[0]][0]
                    out.append((pc, area, one))
    return out


def fill(sm, z, cur, origs, lib, rnd, skel_fam, notes):
    """Leftover department floor filled room by room with single rooms from other maps' same department (a room
    type the department already has is not used twice). cur: the placed main donor; returns it with the rooms."""
    old = set()
    for t in origs:
        old |= t
        old |= {(p[0] + dx, p[1] + dy) for p in t for dx, dy in D8}
    A2 = z.F | z.Zw | z.Zb
    present = {v[0] for v in cur.cells.values()} | {sm.area.get(p) for t in origs for p in t}
    pool = room_pool(lib, z.g, skel_fam, rnd)
    for _ in range(10):
        walls = cur.ring & A2
        used = cur.floor | walls | old
        z2 = types.SimpleNamespace(g=z.g, D=z.D - used, F=z.F - used, Zw=z.Zw - used,
                                   Zb=((z.Zb | walls) - old - cur.floor), rooms=[], block=cur.floor,
                                   walk=cur.floor, need_hall=False, grid=None)
        if len(z2.D) < 12:
            break
        best = None
        for pc, area, one in pool:
            if area in present or len(one.cells) > len(z2.F):
                continue
            r = fit(sm, z2, one, min_keep=1.0)
            if not r:
                continue
            got = r[2]["cover"] * len(z2.D)
            if got < 10:
                continue
            sc = got + 3 * r[2]["maint"] + 6 * rnd.random()
            if best is None or sc > best[0]:
                best = (sc, pc, area, one, r[1], got)
        if not best:
            break
        sc, pc, area, one, off, got = best
        cur = merged(cur, shifted(one, off))
        present.add(area)
        notes.append("filled %d tiles with %s from %s" % (got, area.rsplit("/", 1)[-1], pc["map"]))
    return cur


# ------------------------------------------------------------------------------------------ blueprint
def area_ok(a, g):
    return a if typeindex.known(a) else FALLBACK_AREA.get(g, "/area/maintenance/port")


def regions(cells):
    """Donor floor split into rooms: 4-connected tiles of one area."""
    rid, seen = {}, 0
    for p in sorted(cells):
        if p in rid:
            continue
        a = cells[p][0]
        st = [p]
        rid[p] = seen
        while st:
            q = st.pop()
            for dx, dy in D4:
                r = (q[0] + dx, q[1] + dy)
                if r in cells and r not in rid and cells[r][0] == a:
                    rid[r] = seen
                    st.append(r)
        seen += 1
    return rid


def blueprint(name, base, sm, z, op, off, rnd, origs=()):
    """The zone rewritten with the donor: a forge/build.py blueprint namespace, plus notes."""
    ox, oy = off
    P = lambda p: (p[0] + ox, p[1] + oy)  # noqa: E731
    floor = {P(p): v for p, v in op.cells.items()}
    doors = {P(p): v for p, v in op.doors.items()}
    glass = {P(p) for p in op.glass}
    A2 = z.F | z.Zw | z.Zb
    ring = {P(p) for p in op.ring} & A2
    ch, room = {}, {}
    old = set()
    for t in origs:
        old |= t
        old |= {(p[0] + dx, p[1] + dy) for p in t for dx, dy in D8}
    pool = iter(chr(c) for c in range(0x100, 0x6000))
    roomdefs, legend = {}, {}
    notes = []
    # donor rooms
    rid = regions(op.cells)
    rc_of = {}
    for p, v in op.cells.items():
        r = rid[p]
        if r not in rc_of:
            rc_of[r] = next(pool)
            turfs = Counter(op.cells[q][1] for q in op.cells if rid[q] == r)
            roomdefs[rc_of[r]] = dict(area=area_ok(v[0], z.g), floor=turfs.most_common(1)[0][0],
                                      name="%s:%s" % (z.g, v[0].rsplit("/", 1)[-1]),
                                      furnish=dict(mode="copy", cells={}))
        q = P(p)
        ch[q] = "."
        room[q] = rc_of[r]
        roomdefs[rc_of[r]]["furnish"]["cells"][q] = [v[1]] + v[2:]
    # walls, windows and doors round and between them
    for q in ring:
        if q in floor:
            continue
        inner = [P(p) for p in op.floor if abs(P(p)[0] - q[0]) + abs(P(p)[1] - q[1]) == 1]
        if q in doors and doors[q]:
            spec = {"obj": [], "firedoor": False}
            for o in doors[q]:
                a = dmm.Atom.parse(o)
                spec["obj"].append((a.path, dict(a.vars)))
            key = repr(spec)
            c = legend.get(key)
            if c is None:
                c = next(pool)
                legend[key] = c
            ch[q] = c
            if inner:
                room[q] = room[inner[0]]
        elif q in glass:
            ch[q] = "="
        else:
            ch[q] = "#"
    # leftover: zone floor and old inner walls not used by the donor
    maint_area = Counter(sm.area[p] for p in z.M) or Counter({"/area/maintenance/port": 1})
    marea = maint_area.most_common(1)[0][0]
    mrc = next(pool)
    roomdefs[mrc] = dict(area=marea, floor="/turf/open/floor/plating", name="%s leftover maint" % z.g)
    for q in z.D:
        if q not in ch and q not in old:
            ch[q] = "."
            room[q] = mrc
    for q in z.Zw:
        if q in ch or q in old:
            continue
        if sm.cls.get(q) == "D":
            # an old inner door left in leftover maint: open floor
            ch[q] = "."
            room[q] = mrc
        else:
            ch[q] = "#"
    # old doors on the hall walls: onto leftover maint they become maint doors, onto donor walls they go
    mspec = {"obj": [("/obj/machinery/door/airlock/maintenance", {"req_access_txt": '"12"'})]}
    mkey = repr(mspec)
    for q in z.Zb:
        if q in ch or q in old or sm.cls.get(q) != "D":
            continue
        ins = [(q[0] + dx, q[1] + dy) for dx, dy in D4 if (q[0] + dx, q[1] + dy) in z.F]
        if any(room.get(i) == mrc for i in ins):
            c = legend.get(mkey) or next(pool)
            legend[mkey] = c
            ch[q] = c
            room[q] = mrc
        else:
            ch[q] = "#"
    # donor doors on its edge that now open onto wall become wall
    for p, kind in op.exits.items():
        q = P(p)
        if kind.startswith("open-") or q not in ch or ch[q] in "#=.":
            continue
        for dx, dy in D4:
            if (q[0] - dx, q[1] - dy) in floor:
                o = (q[0] + dx, q[1] + dy)
                dead = (o in ch and ch[o] in "#=") or (o not in ch and sm.cls.get(o) not in ("F", "D"))
                if dead:
                    ch[q] = "#"
                    room.pop(q, None)
                    notes.append("door at %d,%d opened onto wall: walled" % q)
                break
    # leftover maint slack the donor covered or walled stays as the skeleton has it otherwise ('~': untouched)
    # pockets of leftover with no way out become wall
    walk = set(p for p, c in ch.items() if c != "#" and c != "=")

    def open_out(p):
        t = sm.cls.get(p)
        return p not in ch and t in ("F", "D")
    seen = set()
    for s in sorted(p for p in walk if room.get(p) == mrc and ch[p] == "."):
        if s in seen:
            continue
        comp, st, out_ = {s}, [s], False
        seen.add(s)
        while st:
            a = st.pop()
            for dx, dy in D4:
                b = (a[0] + dx, a[1] + dy)
                if open_out(b):
                    out_ = True
                elif b in walk and b not in seen:
                    seen.add(b)
                    comp.add(b)
                    st.append(b)
        if not out_ and not any(room.get(b) != mrc for a in comp for b in [(a[0] + dx, a[1] + dy) for dx, dy in D4] if b in walk):
            for a in comp:
                ch[a] = "#"
                room.pop(a, None)
            notes.append("walled a %d-tile pocket" % len(comp))
    # the grid
    xs = [p[0] for p in ch]
    ys = [p[1] for p in ch]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    lay, rms = [], []
    for y in range(y1, y0 - 1, -1):
        lay.append("".join(ch.get((x, y), "~") for x in range(x0, x1 + 1)))
        rms.append("".join(room.get((x, y), " ") for x in range(x0, x1 + 1)))
    bp = types.SimpleNamespace(NAME=name, BASE=base, ORIGIN=(x0, y0), LAYOUT="\n".join(lay), ROOMS="\n".join(rms),
                               ROOMDEFS=roomdefs, LEGEND={c: eval(k) for k, c in legend.items()},
                               THIN_WALLS=False, REHANG=True, STYLE=None, SEED=rnd.randint(1, 10 ** 6))
    return bp, notes


# ------------------------------------------------------------------------------------------ after the build
def free_floor(m, tiles):
    out = []
    for p in tiles:
        t = m.get(*p)
        if t and t.tpath.startswith("/turf/open") and not kit.dense(t.objs) and not t.has("/obj/machinery/door") \
                and not t.has("/obj/effect/landmark"):
            out.append(p)
    return out


def put_back(m, tiles, lost, rnd):
    """Landmarks and one-of-a-kind things from the old zone onto free floor of the new department."""
    spots = free_floor(m, sorted(tiles))
    rnd.shuffle(spots)
    for o in lost:
        if not spots:
            break
        p = spots.pop()
        m.get(*p).objs.append(o.copy())


def dedupe(m, before):
    """One of each UNIQUE thing on the station level: extras a donor brought go."""
    seen = Counter()
    gone = []
    for (x, y, z), t in sorted(m.tiles.items()):
        if z != 1:
            continue
        keep = []
        for o in t.objs:
            u = next((u for u in UNIQUE if o.path == u), None)
            if u:
                seen[u] += 1
                if seen[u] > max(1, before.get(u, 1)):
                    gone.append((u, x, y))
                    continue
            keep.append(o)
        t.objs = keep
    return gone


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("skeleton")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--only", default="")
    ap.add_argument("--dry", action="store_true", help="choose and print the donors, build nothing")
    a = ap.parse_args()
    rnd = random.Random("remix|%s|%d" % (a.skeleton, a.seed))
    sm = parse.load(a.skeleton)
    base = parse.map_path(a.skeleton)
    groups = [g for g in (a.only.split(",") if a.only else SWAP)]
    lib = depts.library()
    zs = zones(sm, groups)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "remix_%s_s%d.dmm" % (a.skeleton, a.seed))
    cur = base
    used = set()
    m0 = dmm.read(base)
    before = Counter(o.path for (x, y, z), t in m0.tiles.items() if z == 1 for o in t.objs if o.path in UNIQUE)
    for g in groups:
        z = zs.get(g)
        if z is None:
            print("%-10s no zone on %s" % (g, a.skeleton))
            continue
        pick = choose(sm, z, lib, rnd, family(a.skeleton), used)
        if not pick:
            print("%-10s %d tiles: no donor fits" % (g, len(z.D)))
            continue
        score, pc, op, off, info, orient = pick
        used.add(family(pc["map"]))
        print("%-10s %4d tiles <- %-22s n=%4d k=%d%s rooms %s kept %.2f old %d cover %.2f, %d hall / %d maint doors" % (
            g, len(z.D), pc["map"], pc["n"], orient[0], "m" if orient[1] else "", info["rooms"], info["kept"],
            info["old"], info["cover"], info["hall"], info["maint"]), flush=True)
        if a.dry:
            notes = []
            whole = fill(sm, z, shifted(op, off), info["origs"], lib, rnd, family(a.skeleton), notes)
            used_ = len(z.D & whole.floor) + info["old"]
            print("    %s; cover now %.2f" % ("; ".join(notes) or "no fill", used_ / float(len(z.D))))
            continue
        notes = []
        whole = fill(sm, z, shifted(op, off), info["origs"], lib, rnd, family(a.skeleton), notes)
        bp, more = blueprint("remix_%s_%s" % (a.skeleton, g), cur, sm, z, whole, (0, 0), rnd, info["origs"])
        for n_ in notes + more:
            print("   ", n_)
        mcur = dmm.read(cur)
        old = set().union(*info["origs"]) if info["origs"] else set()
        lost = [o for p in z.D - old for o in mcur.get(*p).objs
                if o.path.startswith("/obj/effect/landmark/start") or o.path in UNIQUE]
        bd = B.Builder(bp, base=cur)
        bd.run()
        new_tiles = [p for p, rc in bd.room.items() if bp.ROOMDEFS[rc].get("furnish")]
        put_back(bd.m, new_tiles, lost, rnd)
        for w in bd.warn[:12]:
            print("    warn:", w)
        bd.save(out)
        cur = out
    if not a.dry and cur == out:
        m = dmm.read(out)
        gone = dedupe(m, before)
        if gone:
            dmm.merge_write(m, out)
            print("removed extra one-of-a-kind things:", gone[:8])
        print("wrote", out)


if __name__ == "__main__":
    main()
