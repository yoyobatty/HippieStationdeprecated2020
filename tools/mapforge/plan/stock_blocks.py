"""Stock stations drawn the way plan/station_plan.py draws a plan: department floor and walls in its colour, halls,
maint, docks; so a plan can be judged beside real ones.

    python tools/mapforge/plan/stock_blocks.py MetaStation DeltaStation ...   # data/previews/mapforge/plan/stock_<name>.png
"""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402
from plan.station_plan import COL, OUT  # noqa: E402

D8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]


def blocks(sm):
    g = {}
    for p, c in sm.cls.items():
        if c != "F":
            continue
        r = sm.regions.get(sm.region.get(p))
        k = r.kind if r else "other"
        grp = sm.group.get(p)
        if k == "hall":
            g[p] = "hall"
        elif k == "maint":
            g[p] = "maint"
        elif grp in ("atmos",):
            g[p] = "engineering"
        elif grp in COL:
            g[p] = grp
        elif grp in ("shuttle",):
            g[p] = "dock"
        else:
            g[p] = "other"
    # walls and doors take the colour of the floor beside them (department first)
    for p, c in sm.cls.items():
        if c in ("W", "D") and p not in g:
            near = [g.get((p[0] + dx, p[1] + dy)) for dx, dy in D8]
            near = [n for n in near if n]
            if near:
                dept = [n for n in near if n not in ("hall", "maint", "other", "dock")]
                g[p] = dept[0] if dept else ("maint" if "maint" in near else near[0])
    # y down like the plan
    ys = [p[1] for p in g]
    top = max(ys)
    return {(x, top - y): v for (x, y), v in g.items()}


if __name__ == "__main__":
    from plan.station_plan import render
    for name in sys.argv[1:]:
        g = blocks(parse.load(name))
        print(name, render(g, os.path.join(OUT, "stock_%s.png" % name), T=5, labels=False))
