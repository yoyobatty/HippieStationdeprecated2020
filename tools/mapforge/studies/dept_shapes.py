"""How a department is shaped on the human maps against the generator's: outline, wings, room shapes, how its rooms
chain off each other. Crops of each department, human and generated, side by side.

    python tools/mapforge/studies/dept_shapes.py      # table + data/previews/mapforge/station/shape_<dept>.png

Measures, per department (largest piece of its floor, wall lines closed over):
    fill      floor+inner walls / bounding box (1.0 = a plain rectangle)
    corners   corners on the outline (a rectangle has 4)
    pieces    separate pieces of 20+ tiles (wings set apart behind maint or a hall)
    rooms     rooms (areas) in it; odd = share that are not rectangles (tiles / own box < 0.9)
    depth     most doors from a hall to reach a room; hubs = rooms with 3+ doors to other rooms of the department
    sizes     smallest / median / largest room
"""
import hashlib
import os
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from forge import dmm  # noqa: E402
import stations as S  # noqa: E402
from station import program as P, render as R  # noqa: E402

OUT = os.path.join(S.ROOT, "data", "previews", "mapforge", "station")
DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))
HUMAN = ("meta", "delta", "box", "hippie", "pubby")
DEPTS = ("security", "medical", "science", "engineering", "cargo", "service", "command", "dorms")


class Shape:
    """One department: tile -> room id, walls, doors (tile -> rooms either side), halls it opens onto."""

    def __init__(self, room, walls, doors, outside):
        self.room, self.walls, self.doors, self.outside = room, walls, doors, outside


def human(name):
    m = dmm.read(os.path.join(S.ROOT, "_maps", "map_files", S.MAPS[name]))
    grp, ap, kind = {}, {}, {}
    for y in range(1, m.maxy + 1):
        for x in range(1, m.maxx + 1):
            t = m.get(x, y)
            if t is None:
                continue
            g = S.group_of(t.apath)
            if g and g.startswith("other:"):
                g = "ai" if "aisat" in g else "civic"
            grp[(x, y)], ap[(x, y)] = g, t.apath
            if t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/window") \
                    or t.has("/obj/machinery/door/poddoor/shutters"):
                kind[(x, y)] = "door"
            elif t.tpath.startswith("/turf/closed") or t.has("/obj/effect/spawner/structure/window") \
                    or t.has("/obj/structure/window") or t.has("/obj/structure/grille"):
                kind[(x, y)] = "wall"
            elif t.tpath.startswith("/turf/open/space") or t.tpath.startswith("/turf/open/openspace"):
                kind[(x, y)] = "space"
            else:
                kind[(x, y)] = "floor"
    out = {}
    for d in DEPTS:
        room = {p: ap[p] for p, g in grp.items() if g == d and kind[p] == "floor"}
        doors = {}
        for p, k in kind.items():
            if k != "door":
                continue
            sides = set()
            for dx, dy in DIRS:
                q = (p[0] + dx, p[1] + dy)
                if kind.get(q) == "floor" and grp.get(q):
                    sides.add(ap[q] if grp[q] == d else "~" + grp[q])
            if any(not s.startswith("~") for s in sides):
                doors[p] = sides
        walls = {p for p, k in kind.items() if k == "wall" and any(
            grp.get((p[0] + dx, p[1] + dy)) == d and kind.get((p[0] + dx, p[1] + dy)) == "floor" for dx, dy in DIRS)}
        out[d] = Shape(room, walls, doors, None)
    return out


def generated(plan):
    out = {}
    for d in DEPTS:
        room = {p: r for p, r in plan.floor.items() if plan.rooms.get(r, {}).get("dept") == d}
        doors = {}
        for p in plan.doors:
            sides = set()
            for dx, dy in DIRS:
                r = plan.floor.get((p[0] + dx, p[1] + dy))
                if r is None:
                    continue
                m = plan.rooms.get(r, {})
                sides.add(r if m.get("dept") == d else "~" + (m.get("dept") or "x"))
            if any(not s.startswith("~") for s in sides):
                doors[p] = sides
        walls = {p for p in plan.walls if any(room.get((p[0] + dx, p[1] + dy)) for dx, dy in DIRS)}
        out[d] = Shape(room, walls, doors, None)
    return out


def _comps(tiles):
    left, comps = set(tiles), []
    while left:
        s = left.pop()
        c, q = {s}, [s]
        while q:
            a = q.pop()
            for dx, dy in DIRS:
                b = (a[0] + dx, a[1] + dy)
                if b in left:
                    left.discard(b)
                    c.add(b)
                    q.append(b)
        comps.append(c)
    return sorted(comps, key=len, reverse=True)


def measure(sh):
    if len(sh.room) < 30:
        return None
    pieces = [c for c in _comps(set(sh.room) | {p for p in sh.doors}) if len(c) >= 20]
    main = pieces[0]
    # close the wall lines: floor + walls/doors with department floor on two opposite sides or two sides
    body = set(main)
    for p in sh.walls | set(sh.doors):
        n = sum(1 for dx, dy in DIRS if (p[0] + dx, p[1] + dy) in main)
        if n >= 2:
            body.add(p)
    xs, ys = [p[0] for p in body], [p[1] for p in body]
    box = (max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1)
    corners = 0
    for x in range(min(xs) - 1, max(xs) + 1):
        for y in range(min(ys) - 1, max(ys) + 1):
            # a 2x2 window with 1 or 3 tiles of the body is one corner; the diagonal pair counts 2
            w = [(x, y) in body, (x + 1, y) in body, (x, y + 1) in body, (x + 1, y + 1) in body]
            n = sum(w)
            if n in (1, 3):
                corners += 1
            elif n == 2 and w[0] == w[3]:
                corners += 2
    rooms = defaultdict(set)
    for p, r in sh.room.items():
        if p in main:
            rooms[r].add(p)
    rooms = {r: ts for r, ts in rooms.items() if len(ts) >= 4}
    odd = 0
    for r, ts in rooms.items():
        rx, ry = [p[0] for p in ts], [p[1] for p in ts]
        if len(ts) / float((max(rx) - min(rx) + 1) * (max(ry) - min(ry) + 1)) < 0.9:
            odd += 1
    # room graph: doors between rooms of the department, and from outside halls
    adj = defaultdict(set)
    entry = set()
    for p, sides in sh.doors.items():
        ins = [s for s in sides if not s.startswith("~") and s in rooms]
        outs = [s for s in sides if s.startswith("~")]
        for a in ins:
            for b in ins:
                if a != b:
                    adj[a].add(b)
            if any(o in ("~hall", "~arrivals", "~escape") or o == "~ring" for o in outs):
                entry.add(a)
    # open joins (no door, rooms of different areas sharing an open edge) count as links too
    for p, r in sh.room.items():
        for dx, dy in ((1, 0), (0, 1)):
            r2 = sh.room.get((p[0] + dx, p[1] + dy))
            if r2 and r2 != r and r in rooms and r2 in rooms:
                adj[r].add(r2)
                adj[r2].add(r)
    dist = {}
    q = deque()
    for e in entry:
        dist[e] = 1
        q.append(e)
    while q:
        a = q.popleft()
        for b in adj[a]:
            if b not in dist:
                dist[b] = dist[a] + 1
                q.append(b)
    sizes = sorted(len(ts) for ts in rooms.values())
    return dict(tiles=len(main), fill=len(body) / float(box), corners=corners, pieces=len(pieces),
                rooms=len(rooms), odd=odd / float(max(1, len(rooms))), depth=max(dist.values()) if dist else 0,
                hubs=sum(1 for r in rooms if len(adj[r]) >= 3), sizes=(sizes[0], sizes[len(sizes) // 2], sizes[-1]),
                body=body, main=main)


def crop(sh, res, name, T=5):
    from PIL import Image, ImageDraw
    body = res["body"]
    xs, ys = [p[0] for p in body], [p[1] for p in body]
    x0, x1, y0, y1 = min(xs) - 2, max(xs) + 2, min(ys) - 2, max(ys) + 2
    img = Image.new("RGB", ((x1 - x0 + 1) * T, (y1 - y0 + 1) * T + 14), (24, 24, 30))
    d = ImageDraw.Draw(img)
    base = None
    for p, r in sh.room.items():
        if not (x0 <= p[0] <= x1 and y0 <= p[1] <= y1):
            continue
        h = int(hashlib.md5(r.encode()).hexdigest()[:6], 16)
        col = base or (180, 180, 180)
        col = tuple(max(0, min(255, c + ((h >> (8 * i)) & 63) - 32)) for i, c in enumerate(col))
        b = ((p[0] - x0) * T, (y1 - p[1]) * T + 14)
        d.rectangle([b[0], b[1], b[0] + T - 1, b[1] + T - 1], fill=R.tint(col, 0.2))
    for p in sh.walls:
        if x0 <= p[0] <= x1 and y0 <= p[1] <= y1:
            b = ((p[0] - x0) * T, (y1 - p[1]) * T + 14)
            d.rectangle([b[0], b[1], b[0] + T - 1, b[1] + T - 1], fill=R.WALL)
    for p in sh.doors:
        if x0 <= p[0] <= x1 and y0 <= p[1] <= y1:
            b = ((p[0] - x0) * T, (y1 - p[1]) * T + 14)
            d.rectangle([b[0], b[1], b[0] + T - 1, b[1] + T - 1], fill=(236, 196, 64))
    d.text((3, 1), name, fill=(255, 255, 255))
    return img


def row(r):
    return "%5d  fill %.2f  corners %3d  pieces %d  rooms %2d  odd %3.0f%%  depth %d  hubs %2d  sizes %s" % (
        r["tiles"], r["fill"], r["corners"], r["pieces"], r["rooms"], 100 * r["odd"], r["depth"], r["hubs"],
        "/".join(str(s) for s in r["sizes"]))


def main():
    from PIL import Image
    from station import pinwheel
    crew = 80
    shapes = {n: human(n) for n in HUMAN}
    gens = {s: generated(pinwheel.generate(s, crew)) for s in (1, 2, 3)}
    tot = defaultdict(lambda: defaultdict(list))
    for d in DEPTS:
        print(d)
        imgs = []
        for n, sh in list(shapes.items()) + [("gen s%d" % s, g) for s, g in gens.items()]:
            r = measure(sh[d])
            if not r:
                continue
            print("   %-7s %s" % (n, row(r)))
            who = "gen" if n.startswith("gen") else "human"
            for k in ("fill", "corners", "pieces", "rooms", "odd", "depth", "hubs"):
                tot[who][k].append(r[k])
            imgs.append(crop(sh[d], r, "%s %s" % (n, d)))
        # one sheet: human in the top row, generated below
        w = sum(i.width for i in imgs[:len(HUMAN)]) + 8 * len(HUMAN)
        w = max(w, sum(i.width for i in imgs[len(HUMAN):]) + 8 * 3)
        h1 = max(i.height for i in imgs[:len(HUMAN)])
        h2 = max(i.height for i in imgs[len(HUMAN):])
        sheet = Image.new("RGB", (w, h1 + h2 + 12), (10, 10, 14))
        x = 0
        for i in imgs[:len(HUMAN)]:
            sheet.paste(i, (x, 0))
            x += i.width + 8
        x = 0
        for i in imgs[len(HUMAN):]:
            sheet.paste(i, (x, h1 + 12))
            x += i.width + 8
        sheet.save(os.path.join(OUT, "shape_%s.png" % d))
    print("\naverages")
    for who, ks in tot.items():
        print("   %-6s %s" % (who, "  ".join("%s %.2f" % (k, sum(v) / len(v)) for k, v in ks.items())))


if __name__ == "__main__":
    main()
