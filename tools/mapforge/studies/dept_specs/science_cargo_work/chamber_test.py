"""Scratch test of fn_science_cargo.place_burn_chamber():

1. Box round trip: Box's own chamber wiped back to mixing floor and hull wall, then placed again; every block cell
   must come back with the same atoms (station pipes and decals aside).
2. A plain 11x9 mixing lab with its hull on each of the 4 sides of a blank map: the chamber must land on the hull,
   find_lab's pieces must be in the right areas, its two lines must run injector/scrubber -> pump -> valve -> port
   (forge/atmos joins), and the nook and ports must be reached from the lab's door. Pictures of the four.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "gen", "learn"))
from forge import atmos as AT, dmm, render  # noqa: E402
import fn_science_cargo as F  # noqa: E402

OUT = os.path.join(MF, "..", "..", "data", "previews", "mapforge", "dept_science_cargo")


def box_round_trip():
    path = os.path.join(F.CO.ROOT, "_maps", "map_files", "BoxStation", "BoxStation.dmm")
    m = dmm.read(path)
    orig = {}
    x0, y0, x1, y1 = F.BOX_CHAMBER
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            orig[(x, y)] = m.get(x, y).copy()
            t = m.get(x, y)
            keep = [o for o in t.objs if F._station_pipe(o)]
            if x == x0:
                m.set(x, y, dmm.Tile(keep, dmm.Atom("/turf/closed/wall/r_wall"), dmm.Atom("/area/science/mixing")))
            else:
                m.set(x, y, dmm.Tile(keep, dmm.Atom("/turf/open/floor/plasteel/white"), dmm.Atom("/area/science/mixing")))
    got = F.place_burn_chamber(m, log=print)
    bad = 0

    def norm(o):
        vs = sorted((k, v) for k, v in o.vars if not (k == "dir" and v.strip() == "2"))
        return (o.path, tuple(vs))
    for (x, y), t in orig.items():
        a = sorted(norm(o) for o in t.objs if not F._station_pipe(o) and not o.path.startswith("/obj/effect/turf_decal"))
        b = sorted(norm(o) for o in m.get(x, y).objs if not F._station_pipe(o) and not o.path.startswith("/obj/effect/turf_decal"))
        if a != b or t.tpath != m.get(x, y).tpath:
            bad += 1
            print("  differs at %d,%d:\n    box %s %s\n    got %s %s" % (x, y, t.tpath, a, m.get(x, y).tpath, b))
    print("box round trip: placed %d, %d of %d cells differ" % (got, bad, len(orig)))
    return bad == 0 and got == 1


def blank(side):
    """A 24x24 map of space with an 11x9 mixing lab whose hull wall faces `side`; its door on the opposite wall."""
    m = dmm.Map(24, 24, 1)
    for x in range(1, 25):
        for y in range(1, 25):
            m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/space"), dmm.Atom("/area/space")))
    x0, y0, x1, y1 = 7, 7, 17, 15          # floor
    for x in range(x0 - 1, x1 + 2):
        for y in range(y0 - 1, y1 + 2):
            inner = x0 <= x <= x1 and y0 <= y <= y1
            m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/floor/plasteel/white" if inner else "/turf/closed/wall/r_wall"),
                                 dmm.Atom("/area/science/mixing")))
    # a corridor on the side away from the hull, the door into it
    opp = {8: 4, 4: 8, 1: 2, 2: 1}[side]
    v = F.DIRV[opp]
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    door = {4: (x1 + 1, cy), 8: (x0 - 1, cy), 1: (cx, y1 + 1), 2: (cx, y0 - 1)}[opp]
    m.get(*door).turf = dmm.Atom("/turf/open/floor/plasteel")
    m.get(*door).objs = [dmm.Atom("/obj/machinery/door/airlock/research")]
    out = (door[0] + v[0], door[1] + v[1])
    m.set(out[0], out[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom("/area/science")))
    # the other three sides: the station around (walls, not space) so only `side` is hull
    for x in range(1, 25):
        for y in range(1, 25):
            t = m.get(x, y)
            if not t.tpath.startswith("/turf/open/space"):
                continue
            hull = {8: x < x0 - 1, 4: x > x1 + 1, 1: y > y1 + 1, 2: y < y0 - 1}[side]
            if not hull:
                m.set(x, y, dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom("/area/maintenance/fore")))
    return m


def lines_ok(m):
    tiles = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/science/mixing")]
    inj = [p for p in tiles if m.get(*p).has("/obj/machinery/atmospherics/components/unary/outlet_injector")]
    scr = [p for p in tiles if m.get(*p).has("/obj/machinery/atmospherics/components/unary/vent_scrubber")]
    ok = True
    for name, start in (("inlet", inj), ("outlet", scr)):
        if len(start) != 1:
            print("  %s: %d devices" % (name, len(start)))
            ok = False
            continue
        # walk the joins from the device: it must reach a pump, a valve and a port
        seen_, q, kinds = {start[0]}, [start[0]], set()
        while q:
            p = q.pop()
            for a in AT.atoms(m.get(*p)):
                for k in ("binary/pump", "binary/valve", "portables_connector"):
                    if k in a.path:
                        kinds.add(k)
                for d, (dx, dy) in AT.DELTA.items():
                    n = (p[0] + dx, p[1] + dy)
                    if n not in seen_ and any(AT.joins(a, b, d) for b in AT.atoms(m.get(*n))):
                        seen_.add(n)
                        q.append(n)
        print("  %s line reaches %s" % (name, sorted(kinds)))
        ok = ok and kinds == {"binary/pump", "binary/valve", "portables_connector"}
    areas = {}
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            for key, pre in (("injector", "/obj/machinery/atmospherics/components/unary/outlet_injector"),
                             ("scrubber", "/obj/machinery/atmospherics/components/unary/vent_scrubber"),
                             ("alarm", "/obj/machinery/airalarm"), ("ignition", "/obj/machinery/button/ignition"),
                             ("vent_button", "/obj/machinery/button/door"), ("blast", "/obj/machinery/door/poddoor")):
                if o.path.startswith(pre):
                    areas.setdefault(key, set()).add(t.apath)
    print("  areas:", {k: sorted(v) for k, v in areas.items()})
    for key in ("injector", "scrubber", "alarm"):
        ok = ok and areas.get(key) == {F.CHAMBER}
    # the blast doors on the hull with space beyond
    for (x, y, z), t in m.tiles.items():
        if t.has("/obj/machinery/door/poddoor"):
            if not any(m.get(x + dx, y + dy) is not None and m.get(x + dx, y + dy).tpath.startswith("/turf/open/space")
                       for dx, dy in F.N4):
                print("  blast door at %d,%d not on space" % (x, y))
                ok = False
    return ok


def main():
    ok = box_round_trip()
    shots, caps = [], []
    for side in (8, 1, 4, 2):
        m = blank(side)
        got = F.place_burn_chamber(m, log=print)
        good = got == 1 and lines_ok(m)
        print("hull %s: %s" % (F.DIRNAME[side], "OK" if good else "FAIL"))
        ok = ok and good
        p = os.path.join(HERE, "chamber_%s.dmm" % F.DIRNAME[side])
        dmm.write(m, p)
        shots.append(render.render(p, os.path.join(OUT, "chamber_test_%s.png" % F.DIRNAME[side]), region=(3, 3, 21, 21)))
        caps.append("hull %s" % F.DIRNAME[side])
    render.sheet(shots, caps, os.path.join(OUT, "chamber_test_sheet.png"), title="Box's burn chamber placed by place_burn_chamber()")
    print("ALL OK" if ok else "FAILED")


if __name__ == "__main__":
    main()
