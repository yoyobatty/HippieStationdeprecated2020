"""Draw the human stations in the plan pictures' style (department colours, halls, maint, walls, doors), and measure
their hall networks: hall/maint share, hall widths, loops, walking distance from arrivals to each department.

    python tools/mapforge/studies/stations_draw.py      # data/previews/mapforge/station/human_<map>.png + table
"""
import os
import sys
from collections import Counter, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from forge import dmm  # noqa: E402
import stations as S  # noqa: E402
from station import program as P, render as R  # noqa: E402

OUT = os.path.join(S.ROOT, "data", "previews", "mapforge", "station")
COL = dict(P.C)
COL.update(hall=R.HALL, maint=R.MAINT, solar=(36, 52, 112), shuttle=(150, 156, 170), arrivals=(150, 150, 160),
           escape=(150, 150, 160))
DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def load(rel):
    m = dmm.read(os.path.join(S.ROOT, "_maps", "map_files", rel))
    g, kind = {}, {}
    for y in range(1, m.maxy + 1):
        for x in range(1, m.maxx + 1):
            t = m.get(x, y)
            if t is None:
                continue
            grp = S.group_of(t.apath)
            if grp is not None and grp.startswith("other:"):
                grp = "ai" if "aisat" in grp else "civic"
            if t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/window"):
                k = "door"
            elif t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/window"):
                k = "glass"
            elif t.tpath.startswith("/turf/closed"):
                k = "wall"
            elif t.tpath.startswith("/turf/open/space") or t.tpath.startswith("/turf/open/openspace"):
                k = "lattice" if t.has("/obj/structure/lattice") else "space"
            else:
                k = "floor"
            if grp is None and k in ("floor", "door"):
                k = "lattice"
            g[(x, y)] = grp
            kind[(x, y)] = k
    return m, g, kind


def draw(name, g, kind, path, T=4):
    from PIL import Image, ImageDraw
    pts = [p for p, k in kind.items() if k in ("floor", "wall", "door", "glass") and g.get(p)]
    x0 = min(p[0] for p in pts) - 2
    x1 = max(p[0] for p in pts) + 2
    y0 = min(p[1] for p in pts) - 2
    y1 = max(p[1] for p in pts) + 2
    img = Image.new("RGB", ((x1 - x0 + 1) * T, (y1 - y0 + 1) * T + 24), R.SPACE)
    d = ImageDraw.Draw(img)
    for (x, y), k in kind.items():
        if not (x0 <= x <= x1 and y0 <= y <= y1) or k == "space":
            continue
        b = [(x - x0) * T, (y1 - y) * T + 24, (x - x0) * T + T - 1, (y1 - y) * T + 24 + T - 1]
        grp = g.get((x, y))
        if k == "wall":
            if grp is None:
                continue
            col = R.WALL
        elif k == "glass":
            col = R.GLASS
        elif k == "door":
            col = (236, 196, 64)
        elif k == "lattice":
            col = (50, 50, 44)
        else:
            c = COL.get(grp, (200, 200, 200))
            col = c if grp in ("hall", "maint", "solar", "shuttle") else R.tint(c, 0.38)
        d.rectangle(b, fill=col)
    d.text((6, 4), name, fill=(255, 255, 255))
    img.save(path)


def _run(p, dx, dy, s):
    n, q = 1, (p[0] + dx, p[1] + dy)
    while q in s:
        n, q = n + 1, (q[0] + dx, q[1] + dy)
    q = (p[0] - dx, p[1] - dy)
    while q in s:
        n, q = n + 1, (q[0] - dx, q[1] - dy)
    return n


def holes(s):
    """Pieces of not-s that s encloses: the loops of a hall network (and how many enclose 150+ tiles)."""
    xs = [p[0] for p in s]
    ys = [p[1] for p in s]
    bx0, bx1, by0, by1 = min(xs) - 1, max(xs) + 1, min(ys) - 1, max(ys) + 1
    seen, n, big = set(), 0, 0
    for x in range(bx0, bx1 + 1):
        for y in range(by0, by1 + 1):
            if (x, y) in s or (x, y) in seen:
                continue
            comp, q, edge = 0, [(x, y)], False
            seen.add((x, y))
            while q:
                a = q.pop()
                comp += 1
                if a[0] in (bx0, bx1) or a[1] in (by0, by1):
                    edge = True
                for dx, dy in DIRS:
                    b = (a[0] + dx, a[1] + dy)
                    if bx0 <= b[0] <= bx1 and by0 <= b[1] <= by1 and b not in s and b not in seen:
                        seen.add(b)
                        q.append(b)
            if not edge:
                n += 1
                big += comp >= 150
    return n, big


def measure(name, g, kind):
    floor = {p for p, k in kind.items() if k in ("floor", "door") and g.get(p) and g[p] not in ("shuttle", "solar")}
    hall = {p for p in floor if g[p] in ("hall", "arrivals", "escape") and kind[p] == "floor"}
    maint = {p for p in floor if g[p] == "maint"}
    hw = Counter(min(_run(p, 1, 0, hall), _run(p, 0, 1, hall), 6) for p in hall)
    mw = Counter(min(_run(p, 1, 0, maint), _run(p, 0, 1, maint), 4) for p in maint)
    hdoor = {p for p in floor if kind[p] == "door" and g[p] == "hall"}
    hl = holes(hall | hdoor)
    ml = holes(maint | {p for p in floor if kind[p] == "door" and g[p] == "maint"})
    start = [p for p in floor if g[p] == "arrivals"]
    dist, q = {}, deque()
    for p in start:
        dist[p] = 0
        q.append(p)
    while q:
        p = q.popleft()
        for dx, dy in DIRS:
            n = (p[0] + dx, p[1] + dy)
            if n in floor and n not in dist:
                dist[n] = dist[p] + 1
                q.append(n)
    reach = {}
    for p, dd in dist.items():
        k = g[p]
        if k not in reach or dd < reach[k]:
            reach[k] = dd
    ent = Counter()
    for p in floor:
        if kind[p] != "door":
            continue
        sides = {g.get((p[0] + dx, p[1] + dy)) for dx, dy in DIRS}
        for s_ in sides:
            if s_ and s_ not in ("hall", "maint"):
                if "hall" in sides:
                    ent[s_] += 1
                if "maint" in sides:
                    ent[s_ + "/m"] += 1
    return dict(floor=len(floor), hall=len(hall), maint=len(maint), hw=dict(sorted(hw.items())),
                mw=dict(sorted(mw.items())), loops=hl, mloops=ml, reach=reach, ent=ent)


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or list(S.MAPS)
    for name in names:
        m, g, kind = load(S.MAPS[name])
        draw(name, g, kind, os.path.join(OUT, "human_%s.png" % name))
        r = measure(name, g, kind)
        print("%-6s floor %5d  hall %4d (%.0f%%) widths %s  loops %s  maint %4d (%.0f%%) widths %s loops %s" % (
            name, r["floor"], r["hall"], 100.0 * r["hall"] / r["floor"], r["hw"], r["loops"], r["maint"],
            100.0 * r["maint"] / r["floor"], r["mw"], r["mloops"]))
        print("       from arrivals:", " ".join("%s %d" % (k[:5], v) for k, v in sorted(r["reach"].items(),
                                                                                       key=lambda kv: kv[1])))
        print("       doors hall:", " ".join("%s %d" % (k[:7], v) for k, v in sorted(r["ent"].items())
                                             if not k.endswith("/m")))
        print("       doors maint:", " ".join("%s %d" % (k[:7], v) for k, v in sorted(r["ent"].items())
                                              if k.endswith("/m")))


if __name__ == "__main__":
    main()
