"""Scratch: a map coloured by station group (studies/stations.group_of), walls dark, doors white, maint brown, halls
light: the station's skeleton at a glance, for side-by-side looks at stock and generated maps.

    python groupmap.py <out.png> <dmm> [<dmm> ...]      (several maps side by side, same scale)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "studies"))
from forge import dmm  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402
import stations as ST  # noqa: E402

COL = {"security": (200, 50, 50), "command": (60, 90, 200), "medical": (90, 200, 220), "science": (170, 80, 200),
       "engineering": (230, 170, 40), "atmos": (120, 200, 120), "cargo": (160, 110, 60), "service": (90, 170, 70),
       "civic": (220, 140, 170), "dorms": (240, 220, 140), "ai": (40, 160, 140), "hall": (205, 205, 205),
       "maint": (110, 80, 60), "escape": (250, 250, 120), "arrivals": (250, 250, 120), "solar": (40, 40, 90)}
POST = (255, 120, 60)


def draw(path, px=4):
    m = dmm.read(path)
    pts = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and not (t.apath.startswith("/area/space") and
                                                                          t.tpath.startswith("/turf/open/space"))]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    im = Image.new("RGB", ((x1 - x0 + 1) * px, (y1 - y0 + 1) * px), (15, 15, 20))
    d = ImageDraw.Draw(im)
    cache = {}
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not (x0 <= x <= x1 and y0 <= y <= y1):
            continue
        if t.tpath.startswith("/turf/open/space") and t.apath.startswith("/area/space"):
            continue
        if t.tpath.startswith("/turf/closed"):
            c = (45, 45, 50)
        elif any(o.path.startswith("/obj/machinery/door/airlock") for o in t.objs):
            c = (255, 255, 255)
        else:
            a = t.apath
            if a not in cache:
                g = ST.group_of(a)
                cache[a] = POST if a.startswith("/area/security/checkpoint") else COL.get(g, (90, 90, 90))
            c = cache[a]
        X, Y = (x - x0) * px, (y1 - y) * px
        d.rectangle([X, Y, X + px - 1, Y + px - 1], fill=c)
    return im


def main():
    out = sys.argv[1]
    ims = [draw(p) for p in sys.argv[2:]]
    W = sum(i.width for i in ims) + 20 * (len(ims) + 1)
    H = max(i.height for i in ims) + 60
    sheet = Image.new("RGB", (W, H), (24, 26, 32))
    d = ImageDraw.Draw(sheet)
    x = 20
    for p, im in zip(sys.argv[2:], ims):
        d.text((x, 10), os.path.basename(p), fill=(230, 230, 230))
        sheet.paste(im, (x, 40))
        x += im.width + 20
    sheet.save(out)


if __name__ == "__main__":
    main()
