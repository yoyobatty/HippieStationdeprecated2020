"""Whole departments from the human maps, as the room stage's unit (2026-11-25).

    from gen import deptstamp
    C = deptstamp.comp("medical", target, W, Dmax, salt)     # a Comp-like department for compose.BU, or None
    python tools/mapforge/gen/deptstamp.py medical            # the candidates for one department

Why: departments composed room by room (gen/compose.py) put stock rooms along a thin generated corridor; the user
(2026-11-25): "not a single department looks good like even close". A human department is one designed block (Meta's
medbay: a wide white spine with blue trim, rooms sharing walls and glazed onto it). Here a department is a whole human
department, copied with room_stamp.apply (so pipes, cable and disposals are dropped and laid again by gen/net.py,
the room's own loops kept), turned (8 ways) so a door that led to a hall in its own map is on the frame's front row,
and picked by the seed among the ones near the department's floor budget.

A candidate: a connected piece of a department group's rooms (forge/parse groups; rooms joined by their doors) on any
of the 38 human maps, MIN_FLOOR tiles or more, every object, turf and area path known here (gen/stamps.resolve), with
at least one door to a hall. Its outer doors that don't face the hall become wall (gen/connect.py and walkfix.py give
cut-off rooms a way in again).
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from forge import parse, room_stamp  # noqa: E402

STAMPED = ("medical", "science", "security", "cargo", "service", "civic", "dorms")
MIN_FLOOR = 60
HALLS = ("hall", "arrivals", "escape")
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]


class DeptSource(room_stamp.Source):
    """room_stamp.Source over a whole department piece: its rooms' floor, each tile keeping its own area."""

    def __init__(self, mapname, group, tiles):
        sm = parse.load(mapname)
        self.map, self.area, self.sm, self.group = mapname, None, sm, group
        self.floor = set(tiles)
        self.areas = {p: sm.area[p] for p in tiles}
        self.area = max(set(self.areas.values()), key=lambda a: sum(1 for v in self.areas.values() if v == a))
        self.o = (min(p[0] for p in self.floor), min(p[1] for p in self.floor))
        self.ring = {(p[0] + dx, p[1] + dy) for p in self.floor for dx, dy in N8} - self.floor
        self.inner = {q for q in self.ring if any((q[0] + dx, q[1] + dy) in self.floor and (q[0] - dx, q[1] - dy) in self.floor
                                                  for dx, dy in ((1, 0), (0, 1)))}
        self.doors = {q for q in self.ring - self.inner if sm.cls.get(q) == "D"}
        self.tiles = len(self.floor)
        self.halls = set()
        for q in self.doors:
            for dx, dy in N4:
                n = (q[0] + dx, q[1] + dy)
                if n not in self.floor and sm.cls.get(n) == "F" and sm.group.get(n) in HALLS:
                    self.halls.add(q)


_CANDS = {}


def _pieces(sm, group):
    regs = [r for r in sm.regions.values() if r.group == group and r.kind == "room"]
    ids = {r.id for r in regs}
    seen, out = set(), []
    for r in regs:
        if r.id in seen:
            continue
        comp, st = [], [r.id]
        seen.add(r.id)
        while st:
            a = st.pop()
            comp.append(a)
            for b in sm.regions[a].links:
                if b in ids and b not in seen:
                    seen.add(b)
                    st.append(b)
        tiles = [p for i in comp for p in sm.regions[i].tiles]
        out.append(tiles)
    return out


def _known(src):
    import stamps
    for p in src.floor | src.inner:
        t = src.sm.m.get(p[0], p[1], src.sm.z)
        if t is None:
            continue
        for a in t.objs:
            if stamps.resolve(a.path) == "":
                return False
        if t.turf is not None and stamps.resolve(t.turf.path) == "":
            return False
    return True


CACHE = os.path.join(parse.ROOT, "data", "mapforge", "gen", "deptstamps.json")
VERSION = 1


def _index():
    """{group: [[map, [[x, y], ...]], ...]}: every candidate piece, found once (all 38 maps load in minutes) and kept."""
    import json
    if os.path.exists(CACHE):
        d = json.load(open(CACHE))
        if d.get("version") == VERSION:
            return d["groups"]
    groups = {}
    for name in parse.humans():
        try:
            sm = parse.load(name)
        except Exception:                    # noqa: BLE001 - a map that won't load is skipped
            continue
        for group in STAMPED:
            for tiles in _pieces(sm, group):
                if len(tiles) < MIN_FLOOR:
                    continue
                src = DeptSource(name, group, tiles)
                if not src.halls or not _known(src):
                    continue
                groups.setdefault(group, []).append([name, sorted(tiles)])
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(dict(version=VERSION, groups=groups), open(CACHE, "w"))
    return groups


def candidates(group):
    """[DeptSource] of a group from every human map; the index on disk, the sources built per process."""
    if group in _CANDS:
        return _CANDS[group]
    out = []
    for name, tiles in _index().get(group, []):
        out.append(DeptSource(name, group, [tuple(t) for t in tiles]))
    _CANDS[group] = out
    return out


class StampComp:
    """What compose.BU needs of a department: cells, floor, corridor (none), doors and front, one 'room' (the whole
    department, painted by paint_dept with room_stamp.apply)."""

    def __init__(self, dept, src, k):
        F0, R0, _ = src.footprint(k)
        allc = F0 | R0
        mx = min(c[0] for c in allc)
        my = min(c[1] for c in allc)
        sh = lambda c: (c[0] - mx, c[1] - my)  # noqa: E731
        self.dept, self.src, self.k = dept, src, k
        self.floor = {sh(c) for c in F0}
        self.ring = {sh(c) for c in R0}
        self.cells = self.floor | self.ring
        self.corr = set()
        halls = {sh(src.rel(p, k)) for p in src.halls}
        self.front = {c for c in halls if c[1] == 0}
        self.doors = set(self.front)
        self.W = max(c[0] for c in self.cells) + 1
        self.Dmax = max(c[1] for c in self.cells)
        self.voids, self.chambers, self.panes = set(), [], set()
        fx = min(c[0] for c in F0)
        fy = min(c[1] for c in F0)
        self.rooms = [dict(area=src.area, entry=None, src=src, k=k, A=(fx - mx, fy - my), off=(0, 0), F=self.floor,
                           R=self.ring, inner={sh(src.rel(p, k)) for p in src.inner}, door=next(iter(self.front), None))]
        self.wall = self.cells - self.floor - self.doors


def orient(dept, src, rnd):
    """The orientations that put a hall door on the front row (y 0 of the whole footprint), most such doors first."""
    best = []
    for k in range(8):
        C = StampComp(dept, src, k)
        if C.front:
            best.append((len(C.front), rnd.random(), k, C))
    best.sort(key=lambda b: (-b[0], b[1]))
    return [b[3] for b in best]


def comp(dept, target, W, Dmax, salt):
    """A stamped department near `target` floor tiles whose box suits a slot W wide and Dmax deep, or None."""
    if dept not in STAMPED:
        return None
    rnd = random.Random("deptstamp|%s|%s" % (dept, salt))
    scored = []
    for src in candidates(dept):
        r = src.tiles / float(max(1.0, target))
        if not 0.65 <= r <= 1.5:
            continue
        scored.append((abs(math.log(r)) + 0.25 * rnd.random(), src))
    scored.sort(key=lambda s: s[0])
    for _, src in scored[:8]:
        opts = orient(dept, src, rnd)
        # the slot's shape: prefer a footprint no deeper than the slot allows, nearest its width
        opts.sort(key=lambda C: ((C.Dmax > Dmax * 1.2), abs(C.W - W) / float(max(W, 1))))
        if opts:
            return opts[0]
    return None


if __name__ == "__main__":
    g = sys.argv[1] if len(sys.argv) > 1 else "medical"
    cs = candidates(g)
    print("%s: %d candidates" % (g, len(cs)))
    for s in sorted(cs, key=lambda s: -s.tiles)[:30]:
        print("  %-28s %4d floor, %d hall doors, %d rooms' areas" % (s.map, s.tiles, len(s.halls), len(set(s.areas.values()))))
