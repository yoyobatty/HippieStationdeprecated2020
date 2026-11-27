"""Held-out test of the room synthesizer (plan M-L1): human rooms of a map family left out of the learning, stripped
to their shell (floor, walls, doors, windows, turfs, decals, pipes kept) and furnished again from the other maps only.

    python tools/mapforge/gen/learn/heldout.py                       # Meta's rooms of the test types
    python tools/mapforge/gen/learn/heldout.py --family BoxStation.dmm --types cloning,chemistry
    python tools/mapforge/gen/learn/heldout.py --seed 3

Writes data/previews/mapforge/learn/heldout_<family>.png: each room, the human original beside the generated one,
with forge/function.py's problems for each under it; prints the numbers.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from forge import corpus as CO, dmm, function as FN, render  # noqa: E402
import roomdb  # noqa: E402
import synth  # noqa: E402

TYPES = ("genetics/cloning", "medical/chemistry", "crew_quarters/kitchen", "crew_quarters/bar", "medical/surgery",
         "security/office", "science/lab", "science/robotics/lab", "hydroponics", "crew_quarters/heads/captain",
         "quartermaster/office", "engine/break_room", "medical/virology", "security/brig", "library")
OUT = os.path.join(CO.ROOT, "data", "previews", "mapforge", "learn")


def strip(t):
    """A tile's furniture, loose items and wall pieces off; turf, area, pipes, cable, decals, doors, windows stay."""
    keep = []
    for a in t.objs:
        if a.path.startswith(("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/structure/disposalpipe",
                              "/obj/effect", "/obj/machinery/door", "/obj/structure/window", "/obj/structure/grille")):
            keep.append(a)
    t.objs = keep


def shape_stats(m, floor):
    """(furnished share of the floor, share of furnished tiles against a wall or glass)."""
    furn = [p for p in floor if CO.furniture(m.get(*p))[0]]
    walled = [p for p in furn if any(CO.solid(m.get(p[0] + dx, p[1] + dy)) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    return len(furn) / float(max(1, len(floor))), len(walled) / float(max(1, len(furn)))


def one(args):
    """Test one held-out room: (room record, map path, seed, render?) -> dict of numbers (+ picture paths)."""
    r, path, seed, pics = args
    m = dmm.read(path)
    x0, y0 = r["at"]
    floor = {(x0 + f[0], y0 + f[1]) for f in r["floor"]}
    doors = {(x0 + d[0], y0 + d[1]) for d in r["doors"]}
    windows = {(x0 + w[0], y0 + w[1]) for w in r["windows"]}
    xs = [p[0] for p in floor]
    ys = [p[1] for p in floor]
    reg = (min(xs) - 2, min(ys) - 2, max(xs) + 2, max(ys) + 2)
    zone = {(x, y) for x in range(reg[0], reg[2] + 1) for y in range(reg[1], reg[3] + 1)}
    res = dict(area=r["area"], map=r["map"])
    res["probs_h"] = len([p for p in FN.review(m, zone) if p[1] in floor])
    res["fill_h"], res["wall_h"] = shape_stats(m, floor)
    tag = "%s_%s" % (r["map"][:-4], r["area"].rsplit("/", 1)[-1])
    if pics:
        tmp = os.path.join(OUT, "_tmp_%s.dmm" % tag)
        dmm.write(m, tmp)
        res["pic_h"] = render.render(tmp, os.path.join(OUT, "h_%s.png" % tag), region=reg, scale=0.75)
    for p in floor:
        strip(m.get(*p))
    solid = lambda p: CO.solid(m.get(*p)) and p not in doors  # noqa: E731
    out, rep = synth.furnish(floor, solid, doors, windows, r["area"], seed=seed, exclude=(r["family"],))
    for p, atoms in out.items():
        m.get(*p).objs.extend(dmm.Atom.parse(t) for t in atoms)
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))}
    FN.fix(m, floor, protect=fronts)
    import floorplan
    floorplan.unstrand(m, floor, synth._kit(r["area"]))     # as gen/learn/floorplan.py furnish does
    probs = [p for p in FN.review(m, zone) if p[1] in floor]
    res["probs_g"] = len(probs)
    res["rules_g"] = sorted({p[0] for p in probs})
    res["fill_g"], res["wall_g"] = shape_stats(m, floor)
    res["left"] = rep["left_out"]
    res["exemplar"] = rep["exemplar"]
    if pics:
        tmp = os.path.join(OUT, "_tmp_%s.dmm" % tag)
        dmm.write(m, tmp)
        res["pic_g"] = render.render(tmp, os.path.join(OUT, "g_%s.png" % tag), region=reg, scale=0.75)
        os.remove(tmp)
    return res


def score(results):
    """One number to drive tuning (lower is better): function problems over the humans', and the gaps in furnished
    share and wall share, room by room."""
    s = 0.0
    for r in results:
        s += 1.0 * max(0, r["probs_g"] - r["probs_h"])
        s += 4.0 * abs(r["fill_g"] - r["fill_h"])
        s += 2.0 * abs(r["wall_g"] - r["wall_h"])
        s += 0.3 * r["left"]
    return round(s / max(1, len(results)), 3)


def run(families=("MetaStation.dmm",), types=TYPES, seed=1, pics=False, jobs=4):
    tests = []
    for fam in families:
        rel = next(r for r in CO.MAPS if os.path.basename(r) == fam)
        path = os.path.join(CO.ROOT, "_maps", "map_files", rel)
        got = set()
        for r in roomdb.rooms():
            if r["map"] != fam or r["tiles"] < 9:
                continue
            tp = next((tp for tp in types if r["area"].endswith(tp)), None)
            if tp and tp not in got:
                got.add(tp)
                tests.append((r, path, seed, pics))
    if jobs > 1:
        import multiprocessing as mp
        with mp.get_context("spawn").Pool(jobs) as pool:
            res = pool.map(one, tests)
    else:
        res = [one(t) for t in tests]
    return res


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", default="MetaStation.dmm")
    ap.add_argument("--types", default=",".join(TYPES))
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    types = a.types.split(",")
    rel = next(r for r in CO.MAPS if os.path.basename(r) == a.family)
    path = os.path.join(CO.ROOT, "_maps", "map_files", rel)
    tests = []
    for r in roomdb.rooms():
        if r["map"] != a.family or r["tiles"] < 9:
            continue
        if any(r["area"].endswith(tp) for tp in types) and not any(t["area"] == r["area"] for t in tests):
            tests.append(r)
    os.makedirs(OUT, exist_ok=True)
    pics, caps, tot = [], [], dict(rooms=0, probs_h=0, probs_g=0, left=0)
    for r in tests:
        m = dmm.read(path)
        x0, y0 = r["at"]
        floor = {(x0 + f[0], y0 + f[1]) for f in r["floor"]}
        doors = {(x0 + d[0], y0 + d[1]) for d in r["doors"]}
        windows = {(x0 + w[0], y0 + w[1]) for w in r["windows"]}
        xs = [p[0] for p in floor]
        ys = [p[1] for p in floor]
        reg = (min(xs) - 2, min(ys) - 2, max(xs) + 2, max(ys) + 2)
        zone = {(x, y) for x in range(reg[0], reg[2] + 1) for y in range(reg[1], reg[3] + 1)}
        probs_h = [p for p in FN.review(m, zone) if p[1] in floor]
        fh, wh = shape_stats(m, floor)
        human_png = os.path.join(OUT, "h_%s_%s.png" % (a.family[:-4], r["area"].rsplit("/", 1)[-1]))
        tmp = os.path.join(OUT, "_tmp.dmm")
        dmm.write(m, tmp)
        render.render(tmp, human_png, region=reg, scale=0.75)
        for p in floor:
            strip(m.get(*p))
        solid = lambda p: CO.solid(m.get(*p)) and p not in doors  # noqa: E731
        out, rep = synth.furnish(floor, solid, doors, windows, r["area"], seed=a.seed, exclude=(r["family"],))
        for p, atoms in out.items():
            m.get(*p).objs.extend(dmm.Atom.parse(t) for t in atoms)
        fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))}
        FN.fix(m, floor, protect=fronts)
        probs_g = [p for p in FN.review(m, zone) if p[1] in floor]
        fg, wg = shape_stats(m, floor)
        tot.setdefault("fill_h", []).append(fh)
        tot.setdefault("fill_g", []).append(fg)
        tot.setdefault("wall_h", []).append(wh)
        tot.setdefault("wall_g", []).append(wg)
        dmm.write(m, tmp)
        gen_png = os.path.join(OUT, "g_%s_%s.png" % (a.family[:-4], r["area"].rsplit("/", 1)[-1]))
        render.render(tmp, gen_png, region=reg, scale=0.75)
        name = r["area"].replace("/area/", "")
        pics += [human_png, gen_png]
        caps += ["%s (human, %d problems)" % (name, len(probs_h)),
                 "generated from %s: %d problems, %d groups, %d left out" % (
                     (rep["exemplar"] or "-").split(" ")[0], len(probs_g), rep["placed"], rep["left_out"])]
        tot["rooms"] += 1
        tot["probs_h"] += len(probs_h)
        tot["probs_g"] += len(probs_g)
        tot["left"] += rep["left_out"]
        print("%-28s %-34s problems h%d g%d  fill h%.2f g%.2f  wall h%.2f g%.2f  %s" % (
            name, (rep["exemplar"] or "-")[:34], len(probs_h), len(probs_g), fh, fg, wh, wg,
            "; ".join(sorted({p[0] for p in probs_g}))[:60]))
    sheet = render.sheet(pics, caps, os.path.join(OUT, "heldout_%s_s%d.png" % (a.family[:-4], a.seed)),
                         title="held out: %s, seed %d" % (a.family, a.seed))
    for k in ("fill_h", "fill_g", "wall_h", "wall_g"):
        v = tot.get(k, [0])
        tot[k] = round(sum(v) / float(len(v)), 3)
    print(tot, sheet)
    return tot


if __name__ == "__main__":
    main()
