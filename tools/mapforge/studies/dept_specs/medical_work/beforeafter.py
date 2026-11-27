"""Before/after pictures of the rooms gen/learn/fn_medical.py changes: each region rendered from both maps (dmm-tools,
forge/render.py), labelled, side by side in one sheet per region.

    python tools/mapforge/studies/dept_specs/medical_work/beforeafter.py <before.dmm> <after.dmm> <outdir> \
        name:x0,y0,x1,y1 [name:x0,y0,x1,y1 ...] [--scale 1.0]
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, HERE)
from forge import render  # noqa: E402
import shots  # noqa: E402

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("before")
    ap.add_argument("after")
    ap.add_argument("out")
    ap.add_argument("regions", nargs="+")
    ap.add_argument("--scale", type=float, default=1.0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for spec in a.regions:
        name, box = spec.split(":")
        reg = tuple(int(v) for v in box.split(","))
        pb = os.path.join(a.out, "%s_before.png" % name)
        pa = os.path.join(a.out, "%s_after.png" % name)
        shots.shot(a.before, pb, reg, a.scale)
        shots.shot(a.after, pa, reg, a.scale)
        render.sheet([pb, pa], ["before", "after (fn_medical)"], os.path.join(a.out, "%s_sheet.png" % name),
                     title="%s  x %d-%d  y %d-%d" % (name, reg[0], reg[2], reg[1], reg[3]))
        print(name, os.path.join(a.out, "%s_sheet.png" % name))
