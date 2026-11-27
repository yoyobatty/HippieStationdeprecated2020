"""Department previews without a station: one learned floorplan (gen/learn/floorplan.py) painted on its own, every
room furnished by the synthesizer, rendered in the game's sprites. Seconds a department: the fast look while tuning.

    python tools/mapforge/gen/learn/deptview.py medical                 # crew-80 size, seed 1
    python tools/mapforge/gen/learn/deptview.py medical science security --seeds 1,2
    python tools/mapforge/gen/learn/deptview.py all --seeds 1          # every learned department, one sheet

Writes data/previews/mapforge/learn/dept_<dept>_s<seed>.png and a sheet.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN, render  # noqa: E402
import deptdb  # noqa: E402
import floorplan  # noqa: E402

OUT = os.path.join(CO.ROOT, "data", "previews", "mapforge", "learn")
# wanted floor and front width as a crew-80 station build asks for them (compose log, 2026-11-25)
SIZES = {"medical": (550, 26), "science": (850, 40), "security": (550, 38), "cargo": (240, 12), "service": (410, 19),
         "civic": (200, 11), "dorms": (150, 21), "command": (220, 20), "engineering": (440, 26)}


def preview(dept, seed):
    target, W = SIZES[dept]
    P = floorplan.plan(dept, target, W, 40, "view|%d" % seed)
    M = deptdb.model()
    pad = 3
    m = dmm.Map(P.W + 2 * pad, P.Dmax + 2 * pad + 3, 1)
    S = lambda c: (c[0] + pad + 1, c[1] + pad + 3)  # noqa: E731
    for x in range(1, m.maxx + 1):
        for y in range(1, m.maxy + 1):
            m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space")))
    # a stretch of hall in front of the department
    for x in range(1, m.maxx + 1):
        for y in (pad, pad + 1):
            m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom("/area/hallway/primary/central")))
    area = "/area/" + dept
    for c in P.cells - P.space:
        m.set(*S(c), dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area)))
    for c in P.corr:
        m.set(*S(c), dmm.Tile([], dmm.Atom(P.corr_turf), dmm.Atom(area)))
    for rm in P.rooms:
        for c in rm["F"]:
            m.set(*S(c), dmm.Tile([], dmm.Atom(M["turf"].get(rm["area"], "/turf/open/floor/plasteel")), dmm.Atom(rm["area"])))
    for c in P.doors | P.front:
        t = m.get(*S(c))
        t.turf = dmm.Atom("/turf/open/floor/plasteel")
        t.objs = [dmm.Atom("/obj/machinery/door/airlock")]
    floorplan.glaze(m, P, S)
    floorplan.trim(m, P, S)
    n = floorplan.furnish(m, P, S)
    probs = FN.review(m, {S(c) for c in P.cells})
    tmp = os.path.join(OUT, "_dept_%s_%d.dmm" % (dept, seed))
    dmm.write(m, tmp)
    png = render.render(tmp, os.path.join(OUT, "dept_%s_s%d.png" % (dept, seed)), scale=0.5)
    os.remove(tmp)
    return png, len(P.rooms), len(probs), sorted({p[0] for p in probs})


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("depts", nargs="+")
    ap.add_argument("--seeds", default="1")
    a = ap.parse_args()
    depts = list(SIZES) if a.depts == ["all"] else a.depts
    pics, caps = [], []
    for d in depts:
        for s in [int(v) for v in a.seeds.split(",")]:
            png, nr, np_, rules = preview(d, s)
            pics.append(png)
            caps.append("%s s%d: %d rooms, %d problems %s" % (d, s, nr, np_, ",".join(rules)))
            print(caps[-1], png)
    print(render.sheet(pics, caps, os.path.join(OUT, "depts_sheet.png"), title="learned departments"))
