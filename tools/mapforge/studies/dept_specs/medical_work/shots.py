"""Labelled crops of a map's medical department (or any region), for the medical spec's side-by-side review.

    python tools/mapforge/studies/dept_specs/medical_work/shots.py <dmm> <out.png> [x0 y0 x1 y1] [--scale 0.6]

With no region, the box round every /area/medical, CMO office and medical checkpoint tile (+2). Area names are
printed on each room (gen/pictures._label) and a tick every 5 tiles on the edges so coordinates can be read.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "gen"))
from forge import dmm, render  # noqa: E402
import pictures  # noqa: E402

MED = ("/area/medical", "/area/crew_quarters/heads/cmo", "/area/security/checkpoint/medical")


def med_box(m, margin=2):
    ts = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith(MED) and t.tpath.startswith("/turf/open")]
    # the biggest cluster: drop strays more than 25 tiles from the median
    xs = sorted(p[0] for p in ts)
    ys = sorted(p[1] for p in ts)
    mx, my = xs[len(xs) // 2], ys[len(ys) // 2]
    ts = [p for p in ts if abs(p[0] - mx) <= 30 and abs(p[1] - my) <= 30]
    return (min(p[0] for p in ts) - margin, min(p[1] for p in ts) - margin,
            max(p[0] for p in ts) + margin, max(p[1] for p in ts) + margin)


def ticks(png, reg, scale):
    from PIL import Image, ImageDraw
    img = Image.open(png).convert("RGB")
    d = ImageDraw.Draw(img)
    f = render._font(max(9, int(12 * scale)))
    px = 32 * scale
    for x in range(reg[0], reg[2] + 1):
        if x % 5 == 0:
            d.text(((x - reg[0]) * px + 1, img.height - 14 * max(scale, 0.8)), str(x), fill=(255, 120, 255), font=f)
    for y in range(reg[1], reg[3] + 1):
        if y % 5 == 0:
            d.text((img.width - 26 * max(scale, 0.8), (reg[3] - y) * px + 1), str(y), fill=(255, 120, 255), font=f)
    img.save(png)


def shot(path, out, reg=None, scale=0.6):
    m = dmm.read(path)
    reg = reg or med_box(m)
    render.render(path, out, region=reg, scale=scale)
    pictures._label(m, out, reg, scale)
    ticks(out, reg, scale)
    return reg


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("dmm")
    ap.add_argument("out")
    ap.add_argument("region", nargs="*", type=int)
    ap.add_argument("--scale", type=float, default=0.6)
    a = ap.parse_args()
    print(shot(a.dmm, a.out, tuple(a.region) if a.region else None, a.scale))
