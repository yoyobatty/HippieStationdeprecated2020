"""Picture of a built map's networks: walls, floor, supply (blue), scrubbers (red), cable (yellow), disposals (green),
vents and scrubbers as dots, APCs as white squares. The game render hides under-floor pipes; this shows the routing.

    python studies/net_view.py station_v6 [--scale 6] [--box x1 y1 x2 y2] [--only supply,cable]

Writes data/previews/mapforge/<name>_nets.png.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
COL = {"supply": (60, 120, 255), "scrubbers": (230, 60, 60), "cable": (240, 200, 40), "disposal": (60, 200, 90)}


def main():
    from PIL import Image, ImageDraw
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--scale", type=int, default=6)
    ap.add_argument("--box", nargs=4, type=int)
    ap.add_argument("--only", default="supply,scrubbers,cable,disposal")
    a = ap.parse_args()
    m = dmm.read(os.path.join(ROOT, "data", "mapforge", a.name + ".dmm"))
    xs = [x for x, y, z in m.tiles]
    ys = [y for x, y, z in m.tiles]
    x1, y1, x2, y2 = a.box or (min(xs), min(ys), max(xs), max(ys))
    s = a.scale
    W, H = (x2 - x1 + 1) * s, (y2 - y1 + 1) * s
    im = Image.new("RGB", (W, H), (10, 10, 20))
    dr = ImageDraw.Draw(im)
    only = set(a.only.split(","))
    offs = {"supply": -1, "scrubbers": 1, "cable": 0, "disposal": 2}

    def px(x, y):
        return (x - x1) * s, (y2 - y) * s
    for (x, y, z), t in m.tiles.items():
        if not (x1 <= x <= x2 and y1 <= y <= y2):
            continue
        X, Y = px(x, y)
        if t.tpath.startswith("/turf/closed"):
            c = (70, 70, 78)
        elif t.tpath.startswith("/turf/open/space"):
            continue
        elif t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
            c = (60, 90, 110)
        else:
            c = (28, 28, 34)
        dr.rectangle([X, Y, X + s - 1, Y + s - 1], fill=c)
    for (x, y, z), t in m.tiles.items():
        if not (x1 <= x <= x2 and y1 <= y <= y2):
            continue
        X, Y = px(x, y)
        cx, cy = X + s // 2, Y + s // 2
        for o in t.objs:
            cls = kit.pipe_class(o.path)
            if kit.is_cable(o):
                cls = "cable"
            elif o.path.startswith("/obj/structure/disposalpipe"):
                cls = "disposal"
            if cls not in only or cls not in COL:
                continue
            k = offs[cls]
            if "vent_pump" in o.path or "vent_scrubber" in o.path:
                dr.ellipse([cx - s // 2 + 1, cy - s // 2 + 1, cx + s // 2 - 1, cy + s // 2 - 1], fill=COL[cls])
                continue
            dr.rectangle([cx - 1 + k, cy - 1 + k, cx + k, cy + k], fill=COL[cls])
            # draw toward linked neighbours of the same class
            for d, (dx, dy) in kit.DELTA.items():
                q = m.get(x + dx, y + dy)
                if q is None:
                    continue
                if any((kit.is_cable(p) and cls == "cable") or (kit.pipe_class(p.path) == cls) or
                       (cls == "disposal" and p.path.startswith("/obj/structure/disposalpipe")) for p in q.objs):
                    dr.line([cx + k, cy + k, cx + k + dx * s, cy + k - dy * s], fill=COL[cls], width=1)
        if t.has("/obj/machinery/power/apc"):
            dr.rectangle([cx - 2, cy - 2, cx + 2, cy + 2], outline=(255, 255, 255))
    out = os.path.join(ROOT, "data", "previews", "mapforge", a.name + "_nets.png")
    im.save(out)
    print(os.path.relpath(out, ROOT), im.size)


if __name__ == "__main__":
    main()
