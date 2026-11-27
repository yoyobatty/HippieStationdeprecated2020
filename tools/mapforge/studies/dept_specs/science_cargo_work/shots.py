"""Scratch: before/after pictures of the rooms fn_science_cargo changes.

    python shots.py <before.dmm> <after.dmm> <prefix> name:x0,y0,x1,y1 [...]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import render  # noqa: E402

OUT = os.path.join(MF, "..", "..", "data", "previews", "mapforge", "dept_science_cargo")


def main():
    before, after, prefix = sys.argv[1:4]
    os.makedirs(OUT, exist_ok=True)
    for spec in sys.argv[4:]:
        name, reg = spec.split(":")
        reg = tuple(int(v) for v in reg.split(","))
        b = render.render(before, os.path.join(OUT, "%s_%s_before.png" % (prefix, name)), region=reg)
        a = render.render(after, os.path.join(OUT, "%s_%s_after.png" % (prefix, name)), region=reg)
        s = render.sheet([b, a], ["before", "after fn_science_cargo"], os.path.join(OUT, "%s_%s_sheet.png" % (prefix, name)),
                         title="%s %s x%d-%d y%d-%d" % (prefix, name, reg[0], reg[2], reg[1], reg[3]))
        print(s)


if __name__ == "__main__":
    main()
