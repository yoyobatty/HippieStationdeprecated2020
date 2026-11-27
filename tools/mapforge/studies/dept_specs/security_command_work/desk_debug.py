"""Scratch: why desks.py makes (or skips) a counter for each owner on a map: the roll and the spots per face.

    python desk_debug.py <dmm> [owner substring]
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "gen"))
sys.path.insert(0, os.path.join(MF, "gen", "learn"))
from forge import dmm  # noqa: E402
import desks as D  # noqa: E402


def main():
    m = dmm.read(sys.argv[1])
    only = sys.argv[2] if len(sys.argv) > 2 else ""
    r = random.Random("desks|%s" % 1)
    by_area = {}
    for (x, y, z), t in m.tiles.items():
        if z == 1 and D._floor(t):
            by_area.setdefault(t.apath, set()).add((x, y))
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door")}
    hung = D._hung(m)
    for owner, faces, style, chance, nn, acc, name in D.COUNTERS:
        owners = [a for a in by_area if a == owner or (owner in D.PREFIX_OWNERS and a.startswith(owner + "/"))]
        roll = r.random() if owners else None
        if only and only not in owner:
            continue
        print("%s roll %s chance %.2f -> %s" % (owner, None if roll is None else "%.2f" % roll, chance,
                                                 "skip" if roll is None or roll > chance else "try"))
        for oa in owners:
            for want in faces:
                sp = D.spots(m, by_area[oa], oa, want, hung, doors)
                # also: raw shared walls (wall tiles between owner and want, ignoring the other tests)
                raw = 0
                for p in by_area[oa]:
                    for dx, dy in D.N4:
                        w = (p[0] + dx, p[1] + dy)
                        tw = m.get(*w)
                        tq = m.get(w[0] + dx, w[1] + dy)
                        if tw is not None and tw.tpath.startswith(D.WALL) and D._floor(tq) and D._matches(tq.apath, want, oa):
                            raw += 1
                print("   %-45s face %-28s shared wall %2d  spots %2d %s" % (oa, want, raw, len(sp),
                      [s[0] for s in sp][:6]))


if __name__ == "__main__":
    main()
