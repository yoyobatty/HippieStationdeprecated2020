"""How hall, maint and room sizes are distributed on every human map in parse.humans(): the generator's width and
size targets, and the bands its gate checks.

    python tools/mapforge/studies/space_sizes.py                  # tables, data/mapforge/gen_targets/
    python tools/mapforge/studies/space_sizes.py --map data/mapforge/station_v6.dmm   # a build against the bands
    python tools/mapforge/studies/space_sizes.py --fresh

Per map:
  hall_w[k]    share of hall floor (hallway, arrivals, escape) whose width is k (forge/size_budget.hall_widths: the
               shorter of the tile's row and column run through hall floor; 9 = 9 or more).
  hall_run     median length of straight hall runs (centre-line rows/columns of hall 2+ tiles wide, end to end).
  maint_w[k]   the same for maint floor.
  maint_pocket share of maint floor covered by a 3x3 block of maint floor (open maint: junk rooms, wide spots);
               pockets_per_1k and pocket_med: maint regions holding such a block, and their size
               (forge/size_budget.maint_pockets).
  rooms        wall-bounded rooms of 4+ tiles (parse.rooms): size p10/p25/median/p75/p90/max, per 1k station floor.
  room_size[g] median room size per department.
  aspect       median of room box short side / long side; rect = share of rooms that fill their box.
  one_door     share of rooms with one way in (doors or open seams).
"""
import argparse
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import corpus_common as CC  # noqa: E402
from forge import size_budget as SB  # noqa: E402

STUDY = "space_sizes"
VERSION = 2
HALL = ("hall", "arrivals", "escape")
DEPTS = ("command", "security", "medical", "science", "engineering", "atmos", "cargo", "service", "civic", "dorms",
         "ai")


def widths(tiles):
    def run(p, dx, dy):
        n, q = 1, (p[0] + dx, p[1] + dy)
        while q in tiles:
            n, q = n + 1, (q[0] + dx, q[1] + dy)
        q = (p[0] - dx, p[1] - dy)
        while q in tiles:
            n, q = n + 1, (q[0] - dx, q[1] - dy)
        return n
    return {p: min(run(p, 1, 0), run(p, 0, 1), 9) for p in tiles}


def straight_runs(tiles, w):
    """Lengths of straight hall runs: for each row (and column), maximal runs of tiles whose width is 2+ and whose
    run along that axis is longer than the width (a corridor along that axis)."""
    out = []
    for axis in (0, 1):
        lines = {}
        for p in tiles:
            lines.setdefault(p[1 - axis], []).append(p[axis])
        for k, xs in lines.items():
            xs.sort()
            start = prev = None
            for x in xs:
                if prev is not None and x == prev + 1:
                    prev = x
                    continue
                if start is not None and prev - start + 1 >= 6:
                    out.append(prev - start + 1)
                start = prev = x
            if start is not None and prev - start + 1 >= 6:
                out.append(prev - start + 1)
    return out


def measure(sm):
    st = set(sm.station_tiles())
    if not st:
        return None
    hall = {p for p in st if sm.group.get(p) in HALL}
    maint = {p for p in st if sm.group.get(p) == "maint"}
    hw, mw = widths(hall), widths(maint)
    hn, mn = float(max(1, len(hw))), float(max(1, len(mw)))
    pockets = SB.maint_pockets(sm)
    cover = set()
    for p in maint:
        blk = [(p[0] + dx, p[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
        if all(q in maint for q in blk):
            cover.update(blk)
    ptiles = len(cover)
    rooms = sm.rooms()
    sizes = sorted(len(r.tiles) for r in rooms)
    by = {}
    for r in rooms:
        by.setdefault(r.group, []).append(len(r.tiles))
    asp, rect, one = [], 0, 0
    for r in rooms:
        x0, y0, x1, y1 = sm.bbox(r.tiles)
        a, b = x1 - x0 + 1, y1 - y0 + 1
        asp.append(min(a, b) / float(max(a, b)))
        if a * b == len(r.tiles):
            rect += 1
        if len(r.links) <= 1:
            one += 1
    nr = float(max(1, len(rooms)))
    return dict(
        floor=len(st), crew=CC.crew(sm),
        hall_w={k: round(v / hn, 4) for k, v in Counter(hw.values()).items()},
        hall_mean_w=round(sum(hw.values()) / hn, 3),
        hall_run=CC.median(straight_runs(hall, hw)),
        maint_w={k: round(v / mn, 4) for k, v in Counter(mw.values()).items()},
        maint_pocket=round(ptiles / mn, 3), pockets_per_1k=round(1000.0 * len(pockets) / len(st), 2),
        pocket_med=CC.median([p[0] for p in pockets]),
        rooms_per_1k=round(1000.0 * len(rooms) / len(st), 2),
        room_q={q: CC.quant(sizes, q) for q in (0.1, 0.25, 0.5, 0.75, 0.9, 1.0)},
        room_size={g: CC.median(v) for g, v in by.items()},
        aspect=CC.median(asp), rect=round(rect / nr, 3), one_door=round(one / nr, 3),
    )


def analyse(res):
    res = {k: v for k, v in res.items() if v}
    out = {}
    for k in range(1, 10):
        out["hall_w%d" % k] = CC.band(res, lambda v, k=k: v["hall_w"].get(str(k), v["hall_w"].get(k, 0.0)))
        out["maint_w%d" % k] = CC.band(res, lambda v, k=k: v["maint_w"].get(str(k), v["maint_w"].get(k, 0.0)))
    for f in ("hall_mean_w", "hall_run", "maint_pocket", "pockets_per_1k", "pocket_med", "rooms_per_1k", "aspect",
              "rect", "one_door"):
        out[f] = CC.band(res, lambda v, f=f: v[f])
    for q in ("0.1", "0.25", "0.5", "0.75", "0.9", "1.0"):
        out["room_q" + q] = CC.band(res, lambda v, q=q: v["room_q"].get(q, v["room_q"].get(float(q))))
    for g in DEPTS:
        out["room_size_" + g] = CC.band(res, lambda v, g=g: v["room_size"].get(g))
    return out


def text(out):
    L = ["bands over families (p10 / median / p90)"]
    L.append("hall width share   " + "  ".join("w%d %s" % (k, CC.fmt(out["hall_w%d" % k][1], 3)) for k in range(1, 10)))
    L.append("  p10               " + "  ".join("w%d %s" % (k, CC.fmt(out["hall_w%d" % k][0], 3)) for k in range(1, 10)))
    L.append("  p90               " + "  ".join("w%d %s" % (k, CC.fmt(out["hall_w%d" % k][2], 3)) for k in range(1, 10)))
    L.append("maint width share  " + "  ".join("w%d %s" % (k, CC.fmt(out["maint_w%d" % k][1], 3)) for k in range(1, 10)))
    L.append("  p90               " + "  ".join("w%d %s" % (k, CC.fmt(out["maint_w%d" % k][2], 3)) for k in range(1, 10)))
    for f in ("hall_mean_w", "hall_run", "maint_pocket", "pockets_per_1k", "pocket_med", "rooms_per_1k", "aspect",
              "rect", "one_door"):
        lo, med, hi, n = out[f]
        L.append("%-18s %8s %8s %8s" % (f, CC.fmt(lo), CC.fmt(med), CC.fmt(hi)))
    L.append("room size quantiles (each map's p10..max, then banded):")
    for q in ("0.1", "0.25", "0.5", "0.75", "0.9", "1.0"):
        lo, med, hi, n = out["room_q" + q]
        L.append("  q%-5s %8s %8s %8s" % (q, CC.fmt(lo, 1), CC.fmt(med, 1), CC.fmt(hi, 1)))
    L.append("median room size per department:")
    for g in DEPTS:
        lo, med, hi, n = out["room_size_" + g]
        L.append("  %-12s %6s %6s %6s" % (g, CC.fmt(lo, 1), CC.fmt(med, 1), CC.fmt(hi, 1)))
    return "\n".join(L)


def flat(v):
    """A measured map as the same keys analyse() bands, for --map."""
    d = {}
    for k in range(1, 10):
        d["hall_w%d" % k] = v["hall_w"].get(k, 0.0)
        d["maint_w%d" % k] = v["maint_w"].get(k, 0.0)
    for f in ("hall_mean_w", "hall_run", "maint_pocket", "pockets_per_1k", "pocket_med", "rooms_per_1k", "aspect",
              "rect", "one_door"):
        d[f] = v[f]
    for q, x in v["room_q"].items():
        d["room_q" + str(q)] = x
    for g, x in v["room_size"].items():
        d["room_size_" + str(g)] = x
    return d


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--map")
    a = ap.parse_args(argv)
    res = CC.measure_all(STUDY, measure, fresh=a.fresh, version=VERSION)
    out = analyse(res)
    if a.map:
        d = flat(CC.measure_one(a.map, measure))
        for k, (lo, med, hi, n) in sorted(out.items()):
            x = d.get(k)
            if x is None or lo is None:
                continue
            flag = "" if lo <= x <= hi else "  OUT"
            print("  %-20s %9s   human %s .. %s .. %s%s" % (k, CC.fmt(x), CC.fmt(lo), CC.fmt(med), CC.fmt(hi), flag))
        return
    t = text(out)
    print(t)
    p = CC.save(STUDY, out)
    open(os.path.join(CC.OUT, STUDY + ".txt"), "w").write(t + "\n")
    print("\nwrote", p)


if __name__ == "__main__":
    main(sys.argv[1:])
