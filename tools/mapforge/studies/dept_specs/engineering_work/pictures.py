"""Before/after pictures of gen/learn/fn_engineering.py on a map, the changed tiles marked, plus stock references.

    python tools/mapforge/studies/dept_specs/engineering_work/pictures.py <before.dmm> <after.dmm> <tag>
        -> data/previews/mapforge/dept_engineering/<tag>_<region>_before_after.png for the engineering block and
           Atmospherics' front, regions found from the map (engineering's and atmos's tiles)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..", "..", "gen", "learn")))
import shot as SH  # noqa: E402
import fn_engineering as FE  # noqa: E402
from forge import dmm, render  # noqa: E402

OUT = os.path.join(FE.CO.ROOT, "data", "previews", "mapforge", "dept_engineering")


def changed(a, b, box):
    out = []
    for y in range(box[1], box[3] + 1):
        for x in range(box[0], box[2] + 1):
            ta, tb = a.get(x, y), b.get(x, y)
            if ta is None or tb is None:
                continue
            if ta.text() != tb.text():
                out.append((x, y, ""))
    return out


def boxes(m):
    D = FE.Dept(m)
    eng = [p for a, F in D.eng for p in F]
    atm = [p for a, F in D.atmos for p in F]
    out = []
    if eng:
        xs, ys = [p[0] for p in eng], [p[1] for p in eng]
        out.append(("engineering", (min(xs) - 2, min(ys) - 3, max(xs) + 2, max(ys) + 2)))
    if atm:
        xs, ys = [p[0] for p in atm], [p[1] for p in atm]
        out.append(("atmos", (min(xs) - 2, min(ys) - 3, max(xs) + 2, max(ys) + 2)))
    return out


def main():
    before, after, tag = sys.argv[1], sys.argv[2], sys.argv[3]
    a, b = dmm.read(before), dmm.read(after)
    os.makedirs(OUT, exist_ok=True)
    for name, box in boxes(b):
        marks = changed(a, b, box)
        p1 = SH.shot(before, box, os.path.join(OUT, "_b.png"), 0.75, title="%s before" % tag)
        p2 = SH.shot(after, box, os.path.join(OUT, "_a.png"), 0.75, marks, title="%s after fn_engineering (%d tiles changed, red)"
                     % (tag, len(marks)))
        out = os.path.join(OUT, "%s_%s_before_after.png" % (tag, name))
        render.sheet([p1, p2], ["before", "after"], out)
        os.remove(p1)
        os.remove(p2)
        print(out)


if __name__ == "__main__":
    main()
