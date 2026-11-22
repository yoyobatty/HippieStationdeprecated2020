"""Room twins: each room of a map beside the same room on Meta, Delta, Omega and Hippie, in the game's sprites,
with the numbers under each picture. A reviewer's "7/10" becomes "this sleeper is a 64-tile box with no trim; the
stock ones are 25-30 tiles, L-shaped, half trimmed".

    python tools/mapforge/forge/room_twin.py data/mapforge/station_v6.dmm                 # every department
    python tools/mapforge/forge/room_twin.py data/mapforge/station_v6.dmm --dept medical  # one department
    python tools/mapforge/forge/room_twin.py station_v6.dmm --area sleeper                # rooms whose area has this

Twins: for each stock map, its room of the same type (room_stats.type_of: the area path, or its parent when the
stock maps have too few) nearest in size and shape. Under every picture: tiles, fill, corners, doors and the
dressing numbers. A number of the map's room outside its twins' min..max is drawn red (above) or blue (below).

Output (data/previews/mapforge/room_twin/<map>/):
    <dept>.png    one row per room: the map's room, then its twins, all at the same scale in the row
    report.md     per room: its type, its twins, and each number outside the twins' range with that range
Pictures come from gallery.py's cached full renders (16 px a tile; ~25 s per map the first time, then cached).
"""
import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, room_stats as RS, gallery  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "previews", "mapforge", "room_twin")
SHOWN = ("tiles", "fill", "corners", "doors", "furn", "decal", "items", "pieces", "glass", "lights")
ROW_H = 260      # tallest crop in a row, px
COL_W = 330      # widest crop, px
PAD = 12


def _dist(a, b):
    sa, sb = a.stats, b.stats
    return abs(math.log(sa["tiles"] / sb["tiles"])) + abs(sa["fill"] - sb["fill"]) + 0.05 * abs(sa["corners"] - sb["corners"])


def twins(rm):
    """(type, [best stock room of each stock map]) for a room."""
    kind = RS.type_of(rm.area)
    if not kind:
        return None, []
    peers = RS.peers(kind)
    best = {}
    for p in peers:
        # the exact area path beats a sibling under the same parent
        d = _dist(rm, p) + (0 if p.area == rm.area else 0.5)
        if p.map not in best or d < best[p.map][0]:
            best[p.map] = (d, p)
    order = [RS.SHORT.get(m, m) for m in RS.REFS]
    return kind, sorted((v[1] for v in best.values()), key=lambda p: order.index(RS.SHORT.get(p.map, p.map)))


def gaps(rm, tw):
    """stat -> (value, lo, hi) for each number outside its twins' range (two twins or more)."""
    out = {}
    if len(tw) < 2:
        return out
    for k in RS.STATS:
        vs = [t.stats[k] for t in tw]
        lo, hi = min(vs), max(vs)
        v = rm.stats[k]
        slack = 0.02 if k in ("fill", "glass", "turf_top") else 0.0
        if v < lo - slack or v > hi + slack:
            out[k] = (v, lo, hi)
    return out


def _gap_size(g):
    s = 0.0
    for k, (v, lo, hi) in g.items():
        span = max(hi - lo, 0.25 * max(abs(hi), abs(lo), 0.1))
        s += min(3.0, (lo - v if v < lo else v - hi) / span)
    return s


def _dept(sm, rm):
    from collections import Counter
    c = Counter(sm.group.get(p) for p in rm.tiles)
    g = c.most_common(1)[0][0]
    return g or "other"


class Renders:
    def __init__(self):
        self.img, self.maxy = {}, {}

    def get(self, name, sm):
        if name not in self.img:
            from PIL import Image
            cm = parse.corpus_maps().get(name)
            path = cm["path"] if cm else parse.map_path(name)
            png = gallery.full_renders([path], jobs=1)[path]
            self.img[name] = Image.open(png).convert("RGB")
            self.maxy[name] = sm.m.maxy
        return self.img[name], self.maxy[name]

    def crop(self, name, sm, rm, pad=2):
        img, maxy = self.get(name, sm)
        x0, y0, x1, y1 = rm.box
        return gallery.crop(img, maxy, (x0 - pad, y0 - pad, x1 + pad, y1 + pad))


def row_image(cells):
    """cells: [(crop, caption, lines[(text, colour)])] -> one row, every crop at the row's scale."""
    from PIL import Image, ImageDraw
    from forge.render import _font
    s = min(1.0, min(ROW_H / c[0].height for c in cells), min(COL_W / c[0].width for c in cells))
    s = min(s * 2, 2.0) if s >= 1.0 else s  # small rooms are blown up 2x so they read
    ims = [c[0].resize((max(1, int(c[0].width * s)), max(1, int(c[0].height * s))),
                       Image.NEAREST if s >= 1 else Image.LANCZOS) for c in cells]
    colw = [max(im.width, 170) for im in ims]
    nl = max(len(c[2]) for c in cells)
    h = max(im.height for im in ims) + 34 + 18 * ((nl + 1) // 2)
    out = Image.new("RGB", (sum(colw) + PAD * (len(ims) + 1), h + PAD), (24, 26, 32))
    d = ImageDraw.Draw(out)
    f, fs = _font(17), _font(14)
    x = PAD
    for im, w, (_, cap, lines) in zip(ims, colw, cells):
        d.text((x, 4), cap, fill=(235, 235, 240), font=f)
        out.paste(im, (x, 28))
        y = 32 + max(i.height for i in ims)
        for i, (t, col) in enumerate(lines):
            d.text((x + (i % 2) * 85, y + (i // 2) * 18), t, fill=col, font=fs)
        x += w + PAD
    return out


def stack(rows, title, out_png):
    from PIL import Image, ImageDraw
    from forge.render import _font
    w = max(r.width for r in rows)
    h = sum(r.height for r in rows) + 50 + 4 * len(rows)
    out = Image.new("RGB", (w, h), (16, 17, 21))
    ImageDraw.Draw(out).text((PAD, 12), title, fill=(240, 240, 245), font=_font(24))
    y = 50
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + 4
    out.save(out_png)
    return out_png


def lines_for(rm, g=None, base=None):
    cols = []
    for k in SHOWN:
        col = (190, 195, 205)
        if g and k in g:
            v, lo, hi = g[k]
            col = (255, 110, 90) if v > hi else (110, 170, 255)
        cols.append(("%s %s" % (k, RS.fmt(rm.stats[k], k)), col))
    return cols


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map")
    ap.add_argument("--dept", default="", help="only this department group (medical, science, ...)")
    ap.add_argument("--area", default="", help="only rooms whose area path holds this")
    a = ap.parse_args()
    path = a.map
    if not os.path.exists(path) and os.path.exists(os.path.join(parse.ROOT, "data", "mapforge", path)):
        path = os.path.join(parse.ROOT, "data", "mapforge", path)
    sm = parse.load(path)
    label = os.path.splitext(os.path.basename(path))[0]
    outdir = os.path.join(OUT, label)
    os.makedirs(outdir, exist_ok=True)
    R = Renders()
    R.img[label], R.maxy[label] = None, sm.m.maxy
    from PIL import Image
    R.img[label] = Image.open(gallery.full_renders([path], jobs=1)[path]).convert("RGB")
    ref_sm = {n: parse.load(n) for n in RS.REFS}

    by_dept, report = {}, []
    for rm in sorted(RS.rooms(sm), key=lambda r: r.area):
        dept = _dept(sm, rm)
        if (a.dept and dept != a.dept) or (a.area and a.area not in rm.area):
            continue
        kind, tw = twins(rm)
        g = gaps(rm, tw)
        cells = [(R.crop(label, sm, rm), "%s %s" % (label.replace("station_", ""), rm.name), lines_for(rm, g))]
        for t in tw:
            cells.append((R.crop(t.map, ref_sm[t.map], t), "%s %s" % (RS.SHORT[t.map], t.name), lines_for(t)))
        by_dept.setdefault(dept, []).append((_gap_size(g), rm, row_image(cells)))
        report.append((dept, _gap_size(g), rm, kind, tw, g))

    written = []
    for dept, rows in sorted(by_dept.items()):
        rows.sort(key=lambda r: -r[0])
        # a sheet past ~12 rows is too tall to read: split it
        for i in range(0, len(rows), 12):
            part = "" if len(rows) <= 12 else "_%d" % (i // 12 + 1)
            out = os.path.join(outdir, "%s%s.png" % (dept, part))
            stack([r[2] for r in rows[i:i + 12]],
                  "%s %s: rooms beside their stock twins (red = above the twins, blue = below), worst first" % (label, dept), out)
            written.append(out)

    md = ["# Room twins: %s" % label, "",
          "Rooms ranked by how far their numbers fall outside their stock twins (Meta, Delta, Omega, Hippie).", ""]
    for dept, sc, rm, kind, tw, g in sorted(report, key=lambda r: -r[1]):
        md.append("## %s %s (%s, gap %.1f)" % (dept, rm.area, "type " + kind if kind else "no stock type", sc))
        md.append("at %d,%d-%d,%d; twins: %s" % (rm.box + (", ".join("%s %s" % (RS.SHORT[t.map], t.area) for t in tw) or "none",)))
        for k, (v, lo, hi) in g.items():
            md.append("- %s %s, twins %s-%s" % (k, RS.fmt(v, k), RS.fmt(lo, k), RS.fmt(hi, k)))
        md.append("")
    rp = os.path.join(outdir, "report.md")
    open(rp, "w", encoding="utf-8").write("\n".join(md))
    nt = sum(1 for r in report if r[4])
    print("%d rooms (%d with stock twins), %d sheets -> %s" % (len(report), nt, len(written), os.path.relpath(outdir, parse.ROOT)))
    for dept, sc, rm, kind, tw, g in sorted(report, key=lambda r: -r[1])[:15]:
        print("  %-12s %-44s gap %.1f  %s" % (dept, rm.area[:44], sc, " ".join(sorted(g))))


if __name__ == "__main__":
    main()
