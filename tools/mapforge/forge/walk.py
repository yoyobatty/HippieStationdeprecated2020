"""How a map walks: what can't be reached, what is reached only through maint, corridors that stop dead, open fields of
maint, and where the disposals and waste outlets sit. Stock and generated maps go through the same code, so the v6
gate (station/v6_gate.py) bounds each number by what the stock maps do.

    python tools/mapforge/forge/walk.py                       # the stock maps (room_stats.REFS)
    python tools/mapforge/forge/walk.py data/mapforge/x.dmm   # plus a build, with each finding's place

Walking is 4-connected over floor and door tiles (parse cls 'F'/'D'), access ignored; it starts from every hall tile.
  unreached     station floor tiles (any department group, solars too) no walk from the halls gets to
  maint_only    department floor reached from the halls only through maint, as {area: tiles}: a room whose only way
                in is a maint door (the user 2026-11-22: atmos had "no primary way in except via maint")
  stubs         maint/hall dead ends of length >= STUB_LEN (a corridor that stops against a wall, no door), and the
                longest one (the user 2026-11-22: "there's a dead end here": the SW solar corridor met maint corner to
                corner)
  open_maint    maint floor whose whole 3x3 is maint floor, as a share of the maint floor (the user 2026-11-22: "huge
                empty, pointless maint rooms")
  outlets       tiles between the disposals outlet and the atmos waste injector nearest it (stock maps put them on
                one stretch of hull)
"""
import os
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, room_stats as RS  # noqa: E402

D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
STUB_LEN = 3
OFF = (None, "shuttle")
WASTE = "/obj/machinery/atmospherics/components/unary/outlet_injector"


def _bfs(starts, ok):
    seen, q = set(starts), deque(starts)
    while q:
        p = q.popleft()
        for dx, dy in D4:
            n = (p[0] + dx, p[1] + dy)
            if n not in seen and ok(n):
                seen.add(n)
                q.append(n)
    return seen


def reach(sm):
    """(unreached tiles, {area: tiles reached only through maint})."""
    walk = {p for p, c in sm.cls.items() if c in ("F", "D")}
    halls = [p for p in walk if sm.group.get(p) == "hall"]
    allr = _bfs(halls, lambda n: n in walk)
    nomaint = _bfs(halls, lambda n: n in walk and sm.group.get(n) != "maint")
    station = {p for p in walk if sm.cls[p] == "F" and sm.group.get(p) not in OFF}
    unreached = station - allr
    only = {}
    for p in station & allr - nomaint:
        if sm.group.get(p) not in ("maint", "hall", "solar"):
            only[sm.area[p]] = only.get(sm.area[p], 0) + 1
    return unreached, only


def blocked(sm):
    """Maint and hall floor that furniture cuts off: tiles a walk from the halls reaches over bare floor and doors
    when furniture is ignored, but not when every dense object blocks (the user 2026-11-22: "the vending machine
    blocks the pathway"). The furniture's own tiles don't count."""
    walk = {p for p, c in sm.cls.items() if c in ("F", "D")}
    halls = [p for p in walk if sm.group.get(p) == "hall" and p not in sm.dense]
    free = _bfs(halls, lambda n: n in walk and n not in sm.dense)
    allr = _bfs(halls, lambda n: n in walk)
    return sorted(p for p in allr - free if p not in sm.dense and sm.group.get(p) in ("maint", "hall"))


def corner_gaps(sm):
    """Space tiles between two walls that meet only corner to corner round a station floor tile: a hull that doesn't
    turn its corner (the user 2026-11-22: "2 walls don't join to form a corner"). Stock maps: none."""
    out = []
    for p, c in sm.cls.items():
        if c != "S":
            continue
        for (ax, ay), (bx, by) in (((1, 0), (0, 1)), ((1, 0), (0, -1)), ((-1, 0), (0, 1)), ((-1, 0), (0, -1))):
            a, b, dg = (p[0] + ax, p[1] + ay), (p[0] + bx, p[1] + by), (p[0] + ax + bx, p[1] + ay + by)
            if sm.cls.get(a) == "W" and sm.cls.get(b) == "W" and sm.cls.get(dg) in ("F", "D") and \
                    sm.group.get(dg) not in OFF + ("solar",):
                out.append(p)
                break
    return sorted(out)


def stubs(sm):
    """[(tip, length)] of maint/hall dead ends, and the maint+hall floor count."""
    walk = {p for p, c in sm.cls.items() if c in ("F", "D")}
    corr = {p for p in walk if sm.group.get(p) in ("maint", "hall") and sm.cls[p] == "F"}

    def nb(p):
        return [(p[0] + dx, p[1] + dy) for dx, dy in D4 if (p[0] + dx, p[1] + dy) in walk]
    out = []
    for p in corr:
        n = nb(p)
        if len(n) != 1 or sm.cls.get(n[0]) == "D":
            continue
        prev, cur, ln = p, n[0], 1
        while cur in corr:
            nn = [q for q in nb(cur) if q != prev]
            if len(nn) != 1 or any(sm.cls.get(q) == "D" for q in nb(cur)):
                break
            prev, cur, ln = cur, nn[0], ln + 1
        out.append((p, ln))
    return out, len(corr)


def open_maint(sm):
    mt = {p for p, g in sm.group.items() if g == "maint" and sm.cls.get(p) == "F"
          and "/solars" not in sm.area.get(p, "")}
    op = {p for p in mt if all((p[0] + dx, p[1] + dy) in mt for dx in (-1, 0, 1) for dy in (-1, 0, 1))}
    return len(op) / float(max(1, len(mt)))


def outlets(sm):
    """Tiles (Chebyshev) from each disposals outlet to the nearest atmos waste injector: [(outlet, injector, d)]."""
    disp, inj = [], []
    for (x, y, z), t in sm.m.tiles.items():
        if z != sm.z:
            continue
        if t.has("/obj/structure/disposaloutlet"):
            disp.append((x, y))
        if any(o.path.startswith(WASTE) and "waste" in o.path for o in t.objs):
            inj.append((x, y))
    out = []
    for d in disp:
        if inj:
            i = min(inj, key=lambda q: max(abs(q[0] - d[0]), abs(q[1] - d[1])))
            out.append((d, i, max(abs(i[0] - d[0]), abs(i[1] - d[1]))))
    return out


def measure(sm):
    un, only = reach(sm)
    st, n = stubs(sm)
    long_ = sorted([s for s in st if s[1] >= STUB_LEN], key=lambda s: -s[1])
    ol = outlets(sm)
    return dict(unreached=len(un), unreached_at=sorted(un)[:5], maint_only=only,
                maint_only_max=max(only.values() or [0]), stubs_per_k=1000.0 * len(long_) / max(1, n),
                stub_max=max([s[1] for s in long_] or [0]), stub_tips=long_, open_maint=open_maint(sm),
                outlet_gap=min([o[2] for o in ol] or [999]), outlets=ol)


_STOCK = {}


def stock():
    """{map: measure} over the stock maps (cached for the process)."""
    if not _STOCK:
        for name in RS.REFS:
            _STOCK[name] = measure(parse.load(name))
    return _STOCK


def _line(name, r):
    return "%-14s unreached %3d  maint-only max %3d (%d areas)  stubs/1k %4.2f  longest %2d  open maint %.3f  " \
           "outlet gap %s" % (name[:14], r["unreached"], r["maint_only_max"], len(r["maint_only"]), r["stubs_per_k"],
                              r["stub_max"], r["open_maint"], r["outlet_gap"])


def main():
    for name, r in stock().items():
        print(_line(name, r))
        for a, n in sorted(r["maint_only"].items(), key=lambda kv: -kv[1])[:6]:
            print("      maint only: %s %d" % (a, n))
    for path in sys.argv[1:]:
        r = measure(parse.load(path))
        print(_line(os.path.basename(path), r))
        print("      unreached e.g. %s" % r["unreached_at"])
        for a, n in sorted(r["maint_only"].items(), key=lambda kv: -kv[1]):
            print("      maint only: %s %d" % (a, n))
        for tip, ln in r["stub_tips"]:
            print("      stub tip %s len %d" % (tip, ln))
        print("      outlets %s" % r["outlets"])


if __name__ == "__main__":
    main()
