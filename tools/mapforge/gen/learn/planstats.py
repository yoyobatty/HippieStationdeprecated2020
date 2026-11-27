"""The gate's room numbers (gen/gate.py space.*) straight from the learned floorplans, without building a station: the
seconds-long loop for tuning gen/learn/floorplan.py against the human bands.

    python tools/mapforge/gen/learn/planstats.py             # all learned departments, crew-80 sizes, seeds 1-3

Prints, against each band: room size quantiles over every room, the share of rectangular rooms, the median room
aspect, each department's median room size. A room is one floorplan room (pieces count apart, as the gate's
regions do); rooms under 4 tiles are left out, as the gate does.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import floorplan as FP  # noqa: E402
import gate as G  # noqa: E402

# (wanted floor, front width) per department, two each, as station builds ask for them (compose log lines of crew 80
# seed 1 and crew 100 seed 7, 2026-11-25)
SIZES = {"medical": ((550, 26), (950, 45)), "science": ((850, 40), (1000, 49)), "security": ((550, 38), (1400, 64)),
         "cargo": ((240, 12), (320, 15)), "service": ((410, 19), (450, 22)), "civic": ((200, 11), (320, 15)),
         "dorms": ((150, 21), (230, 22)), "command": ((220, 20), (400, 35)), "engineering": ((440, 26), (850, 49))}


def q(v, f):
    v = sorted(v)
    return v[min(len(v) - 1, int(f * len(v)))] if v else 0


OVER = []      # (dept, area, tiles, human max): areas bigger than every human room of their type (gate "oversized")


def stats(seeds=(1, 2, 3)):
    import rooms as RM
    sizes, rects, aspects, per = [], [], [], {}
    del OVER[:]
    for d, sz in SIZES.items():
        for (t, W) in sz:
            for s in seeds:
                P = FP.plan(d, t, W, 40, "ps|%d" % s)
                tot = {}
                for a, _, n in FP.area_groups(P):      # the gate: same-area rooms within 2 tiles are one room
                    tot[a] = max(tot.get(a, 0), n)
                OVER.extend((d, a, n, RM.look_max(a)) for a, n in tot.items() if n > RM.look_max(a))
                for rm in P.rooms:
                    F = rm["F"]
                    if len(F) < 4:
                        continue
                    xs = [c[0] for c in F]
                    ys = [c[1] for c in F]
                    w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
                    sizes.append(len(F))
                    rects.append(len(F) == w * h)
                    aspects.append(min(w, h) / float(max(w, h)))
                    per.setdefault(d, []).append(len(F))
    return sizes, rects, aspects, per


def report():
    b = G.bands()[0]
    sizes, rects, aspects, per = stats()
    out = []

    def line(name, val):
        lo, hi = b[name][:2]
        ok = lo <= val <= hi
        out.append(ok)
        print("%-28s %7.2f  band %6.2f..%6.2f %s" % (name, val, lo, hi, "" if ok else "OUT"))
    for f in ("0.1", "0.25", "0.5", "0.75", "0.9"):
        line("space.room_q" + f, q(sizes, float(f)))
    line("space.rect", sum(rects) / float(len(rects)))
    line("space.aspect", q(aspects, 0.5))
    for d, v in sorted(per.items()):
        if "space.room_size_" + d in b:
            line("space.room_size_" + d, q(v, 0.5))
    for o in OVER:
        print("oversized  %-12s %-40s %4d > human max %d" % o)
    print("%d of %d in band, %d oversized areas" % (sum(out), len(out), len(OVER)))
    return sum(out), len(out)


if __name__ == "__main__":
    report()
