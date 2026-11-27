"""Scratch: Science and Cargo of Box, Meta, Delta and a generated map side by side (scale 0.5).

    python compare.py <generated.dmm> <gen science x0,y0,x1,y1> <gen cargo x0,y0,x1,y1>
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import corpus as CO, render  # noqa: E402

OUT = os.path.join(MF, "..", "..", "data", "previews", "mapforge", "dept_science_cargo")
MAPS = os.path.join(CO.ROOT, "_maps", "map_files")
STOCK = {
    "science": [("Box", "BoxStation/BoxStation.dmm", (162, 82, 205, 129)),
                ("Meta (labs)", "MetaStation/MetaStation.dmm", (105, 76, 148, 112)),
                ("Meta (xenobiology)", "MetaStation/MetaStation.dmm", (116, 32, 142, 79)),
                ("Delta", "Deltastation/DeltaStation2.dmm", (95, 62, 152, 106))],
    "cargo": [("Box", "BoxStation/BoxStation.dmm", (66, 100, 100, 135)),
              ("Meta", "MetaStation/MetaStation.dmm", (58, 132, 84, 168)),
              ("Delta", "Deltastation/DeltaStation2.dmm", (150, 146, 190, 184))],
}


def main():
    gen = sys.argv[1]
    regs = {"science": tuple(int(v) for v in sys.argv[2].split(",")), "cargo": tuple(int(v) for v in sys.argv[3].split(","))}
    for dept, rows in STOCK.items():
        shots, caps = [], []
        for name, rel, reg in rows:
            p = os.path.join(OUT, "stock_%s_%s.png" % (dept, name.split()[0].lower() + ("_xeno" if "xeno" in name else "")))
            shots.append(render.render(os.path.join(MAPS, rel), p, region=reg, scale=0.5))
            caps.append("%s %s" % (name, reg))
        p = os.path.join(OUT, "gen_%s.png" % dept)
        shots.append(render.render(gen, p, region=regs[dept], scale=0.5))
        caps.append("generated %s %s" % (os.path.basename(gen), regs[dept]))
        out = render.sheet(shots, caps, os.path.join(OUT, "compare_%s.png" % dept), title="%s: stock vs generated" % dept)
        print(out)


if __name__ == "__main__":
    main()
