"""Station block plans: one picture per seed, a contact sheet, the checks.

    python tools/mapforge/station/plan.py                 # seeds 1-5 at crew 80
    python tools/mapforge/station/plan.py 1 2 3 --crew 40
"""
import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from station import layout, render, check, shapes  # noqa: E402
from forge.proc import geo as G  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "previews", "mapforge", "station")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("seeds", nargs="*", type=int, default=[1, 2, 3, 4, 5])
    ap.add_argument("--crew", type=int, default=80)
    ap.add_argument("--tile", type=int, default=7)
    ap.add_argument("--ring", action="store_true", help="the first, ring-and-band layout")
    ap.add_argument("--layout", default="mix", help="mix (picked by seed), " + ", ".join(sorted(shapes.LAYOUTS)))
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    paths = []
    for s in a.seeds:
        t = time.time()
        plan = layout.generate(s, a.crew) if a.ring else shapes.generate(s, a.crew, a.layout)
        res = check.check(plan)
        open_tiles = sum(1 for r in plan.floor.values() if r not in ("catwalk",))
        xs = [p[0] for p in plan.walls]
        ys = [p[1] for p in plan.walls]
        size = "%dx%d" % (max(xs) - min(xs) + 1, max(ys) - min(ys) + 1)
        title = "seed %d  crew %d  %s  %d floor tiles  %d rooms  problems %d" % (
            s, a.crew, size, open_tiles, sum(1 for m in plan.rooms.values() if m.get("kind") == "room"),
            len(plan.problems))
        path = os.path.join(OUT, "station_%s_c%d_s%d.png" % (a.layout, a.crew, s))
        render.draw(plan, path, T=a.tile, title=title)
        paths.append(path)
        print("seed %d: %s, %.1f s" % (s, title, time.time() - t))
        hall = sum(1 for r in plan.floor.values() if r == "ring")
        maint = sum(1 for r in plan.floor.values()
                    if plan.rooms.get(r, {}).get("kind") == "maint" and r != "catwalk"
                    or plan.rooms.get(r, {}).get("dept") == "maint")
        print("    hall %d (%.0f%%)  maint %d (%.0f%%)" % (hall, 100.0 * hall / open_tiles, maint,
                                                       100.0 * maint / open_tiles))
        for n in plan.notes + res:
            print("   ", n)
        for p in plan.problems:
            print("    PROBLEM", p)
    if len(paths) > 1:
        sheet = os.path.join(OUT, "station_%s_c%d_sheet.png" % (a.layout, a.crew))
        G.sheet(paths, sheet, cols=min(3, len(paths)))
        print("sheet:", os.path.relpath(sheet, ROOT))


if __name__ == "__main__":
    main()
