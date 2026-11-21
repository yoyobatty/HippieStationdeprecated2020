"""Hand-drawn department blocks for the v6 station (Security v6 first, then every department after it).

A department is drawn in plan coordinates (plan/station_plan.py: x right, y down), one character per tile: "#" is
wall (the outline ring or a wall between rooms), a space is outside the block, any other character is a room. The
drawing is cut straight into rooms by the slicer (one-tile plan rects), so rooms can be any shape.

    python tools/mapforge/forge/proc/drawing.py grid engineering        # the block: ring "#", free "o", neighbours
    python tools/mapforge/forge/proc/drawing.py rects engineering r.txt # rooms as rects -> a drawing to paste

rects file: one room per line, "<char> x0 y0 x1 y1" (inclusive, plan coordinates, // comments); a room may take
several lines. The command checks no room tile lands on the ring or outside the block and prints the drawing.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
OX, OY = 6, 165             # plan -> map: x + 6, 165 - y (plan/canvas.py)
NB = {"hall": ".", "maint": "m", "maint room": "r", "public": "p", "dock": "d"}


def to_map(px, py):
    return px + OX, OY - py


def block(dept):
    from plan import station_plan as P
    g = P.grid()
    tiles = {p for p, v in g.items() if v == dept}
    ring = {p for p in tiles if any((p[0] + dx, p[1] + dy) not in tiles for dx in (-1, 0, 1) for dy in (-1, 0, 1))}
    return g, tiles, ring


def origin(drawing_box):
    return drawing_box[0], drawing_box[1]


def plans(drawing, chars, x0, y0):
    """The drawing as one-tile plan rects in map coordinates."""
    out = []
    for row, line in enumerate(drawing.splitlines()):
        for col, ch in enumerate(line):
            if ch in chars:
                x, y = to_map(x0 + col, y0 + row)
                out.append(((x, y, x, y), chars[ch]))
    return out


def check_node(drawing, chars, x0, y0):
    """A graph node: every drawn room tile must be a free tile of the outline (not ring, not outside)."""
    def check(geo, P):
        drawn = {r[0][:2] for r in plans(drawing, chars, x0, y0)}
        for p in sorted(drawn):
            if p not in geo.zone or geo.kind.get(p) != "free":
                geo.problem("drawing: room tile %d,%d is on the outline ring or outside the block" % p)
        geo.notes.append("drawing: %d room tiles, %d free tiles left as wall" % (
            len(drawn), sum(1 for q in geo.zone if geo.kind.get(q) == "free" and q not in drawn)))
    return check


def bbox(drawing, x0, y0, pad=2):
    """The map-coordinate box the outline reads (the drawing's extent plus a margin)."""
    lines = drawing.splitlines()
    w = max(len(l) for l in lines)
    a, b = to_map(x0 - pad, y0 + len(lines) - 1 + pad)
    c, d = to_map(x0 + w - 1 + pad, y0 - pad)
    return (a, b, c, d)


def department(name, base, drawing, chars, x0, y0, rooms, links, assets, in_zone, stamps=None, extra=None, seed=1):
    """The whole graph for a drawn department: outline, drawing check, slice, (stamp), tidy, openings, fields,
    furnish. Returns (graph, geo, blueprint attributes) for a blueprint module to put in its globals()."""
    from . import geo as G, shell, furnish, emit
    g = G.Graph(name, seed=seed)
    g.add("outline", shell.outline, view="kind", base=base, bbox=bbox(drawing, x0, y0), in_zone=in_zone)
    g.add("check", check_node(drawing, chars, x0, y0), view="kind")
    g.add("slice", shell.slice_rooms, view="rooms", plans=plans(drawing, chars, x0, y0), rooms=rooms)
    if stamps:
        g.add("stamp", shell.stamp, view="rooms", stamps=stamps, rooms=rooms)
    g.add("tidy", shell.tidy, view="rooms")
    g.add("openings", shell.openings, view="rooms", links=links)
    g.add("fields", shell.fields, view="fields")
    g.add("furnish", furnish.furnish, view="items", assets=assets)
    geo = g.run()
    bp = emit.blueprint(geo, name, extra=dict(dict(STYLE="meta", DISPOSALS="route", BASE=base), **(extra or {})))
    if bp.get("RWALL"):         # a hardened block (the AI satellite, the vault): every wall reinforced
        bp["LAYOUT"] = bp["LAYOUT"].replace("#", "R")
    return g, geo, bp


def report(g, geo, root):
    """What a blueprint prints when run directly: notes, problems, the node pictures."""
    from . import geo as G
    out = os.path.join(root, "data", "previews", "mapforge", "proc")
    paths = g.pictures(out, tile=20)
    G.sheet(paths, os.path.join(out, g.name + "_nodes.png"), cols=3)
    G.draw(geo, "items", os.path.join(out, g.name + "_furnish_big.png"), tile=24, title="furnish")
    for n in geo.notes:
        print(n)
    for p in geo.problems:
        print("PROBLEM", p)


def grid(dept, pad=3):
    g, tiles, ring = block(dept)
    xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
    x0, x1, y0, y1 = min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad
    out = ["     " + "".join(str((x // 10) % 10) for x in range(x0, x1 + 1)),
           "     " + "".join(str(x % 10) for x in range(x0, x1 + 1))]
    for y in range(y0, y1 + 1):
        row = ""
        for x in range(x0, x1 + 1):
            p = (x, y)
            if p in tiles:
                row += "#" if p in ring else "o"
            else:
                v = g.get(p)
                row += NB.get(v, " " if v is None else v[0].upper())
        out.append("%4d %s" % (y, row))
    out.append("free %d, ring %d, box x %d-%d y %d-%d" % (len(tiles - ring), len(ring), min(xs), max(xs), min(ys), max(ys)))
    return "\n".join(out)


def from_rects(dept, path):
    g, tiles, ring = block(dept)
    R = {}
    for line in open(path):
        line = line.split("//")[0].strip()
        if not line:
            continue
        ch, a, b, c, d = line.split()
        for x in range(int(a), int(c) + 1):
            for y in range(int(b), int(d) + 1):
                R[(x, y)] = ch
    bad = sorted(p for p in R if p not in tiles or p in ring)
    xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
    lines = ["".join(R.get((x, y), "#" if (x, y) in tiles else " ") for x in range(min(xs), max(xs) + 1)).rstrip()
             for y in range(min(ys), max(ys) + 1)]
    return "\n".join(lines) + "\n", (min(xs), min(ys)), bad


if __name__ == "__main__":
    if sys.argv[1] == "grid":
        print(grid(sys.argv[2]))
    else:
        d, o, bad = from_rects(sys.argv[2], sys.argv[3])
        if bad:
            print("BAD (ring/outside):", bad)
        print("origin", o)
        print(d)
        if "--into" in sys.argv and not bad:
            # write it over the blueprint's DRAWING literal
            import re
            bp = sys.argv[sys.argv.index("--into") + 1]
            s = open(bp).read()
            s2 = re.sub(r'DRAWING = """\\\n.*?"""', lambda m: 'DRAWING = """\\\n' + d + '"""', s, count=1, flags=re.S)
            open(bp, "w", newline="\n").write(s2)
            print("wrote", bp, "(unchanged)" if s2 == s else "")
