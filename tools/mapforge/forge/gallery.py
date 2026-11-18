"""Regression gallery: the same crops of every map, human and generated, in the game's own sprites, so a change to
the generator is judged by looking at the same places before and after.

    python tools/mapforge/forge/gallery.py                         # human maps + _maps/map_files/Generated, tag "now"
    python tools/mapforge/forge/gallery.py --tag before a.dmm b.dmm  # these generated maps under tag "before"
    python tools/mapforge/forge/gallery.py --compare before after  # side-by-side sheets of the two tags

Output: data/previews/mapforge/gallery/<tag>/dept_<dept>.png (human row, generated row, one crop per map) and
data/previews/mapforge/gallery/compare_<a>_<b>/<map>_<dept>.png. Full-map renders are cached by file hash in
data/mapforge/gallery_cache/ (one dmm-tools run per map, ~25 s; six at a time).
"""
import glob
import hashlib
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402

ROOT = parse.ROOT
CACHE = os.path.join(ROOT, "data", "mapforge", "gallery_cache")
OUT = os.path.join(ROOT, "data", "previews", "mapforge", "gallery")
PX = 16  # pixels per tile in the cached render (scale 0.5)
DEPTS = ("security", "medical", "science", "engineering", "cargo", "service", "command")
GEN_DIR = os.path.join(ROOT, "_maps", "map_files", "Generated")


def _hash(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()[:16]


def _render_one(path):
    from forge import render
    os.makedirs(CACHE, exist_ok=True)
    png = os.path.join(CACHE, _hash(path) + ".png")
    if not os.path.exists(png):
        render.render(path, png, scale=PX / 32.0)
    return png


def full_renders(paths, jobs=6):
    with ProcessPoolExecutor(jobs) as ex:
        return dict(zip(paths, ex.map(_render_one, paths)))


def dept_boxes(sm, pad=2):
    """Department -> tile box (x0, y0, x1, y1) of its largest connected piece."""
    from forge.fingerprint import _comps
    st = set(sm.station_tiles())
    out = {}
    for d in DEPTS:
        ts = [p for p in st if sm.group.get(p) == d]
        if len(ts) < 40:
            continue
        # doors join the rooms of a department into one piece
        tset = set(ts)
        ds = [p for p, c in sm.cls.items() if c == "D" and
              any((p[0] + dx, p[1] + dy) in tset for dx, dy in parse.DIRS)]
        piece = [p for p in _comps(ts + ds)[0] if p in tset]
        x0, y0, x1, y1 = sm.bbox(piece)
        out[d] = (x0 - pad, y0 - pad, x1 + pad, y1 + pad)
    return out


def crop(img, maxy, box):
    x0, y0, x1, y1 = box
    return img.crop(((x0 - 1) * PX, (maxy - y1) * PX, x1 * PX, (maxy - y0 + 1) * PX))


def label_of(p):
    base = os.path.splitext(os.path.basename(p))[0]
    return base.replace("gen_", "").replace("_c80", "")


def build(tag, extra, with_human=True):
    from PIL import Image
    from forge.render import sheet
    gens = list(extra) or sorted(glob.glob(os.path.join(GEN_DIR, "*.dmm")))
    humans = [parse.map_path(n) for n in parse.MAPS] if with_human else []
    paths = humans + gens
    pngs = full_renders(paths)
    tagdir = os.path.join(OUT, tag)
    os.makedirs(tagdir, exist_ok=True)
    index = {}
    crops = {d: ([], [], [], []) for d in DEPTS}  # human imgs, captions, gen imgs, captions
    for p in paths:
        sm = parse.load(p)
        img = Image.open(pngs[p]).convert("RGB")
        lab = sm.name if p in humans else label_of(p)
        boxes = dept_boxes(sm)
        index[lab] = dict(path=p, png=pngs[p], boxes=boxes, maxy=sm.m.maxy, human=p in humans)
        for d, box in boxes.items():
            c = crop(img, sm.m.maxy, box)
            if p not in humans:
                c.save(os.path.join(tagdir, "%s_%s.png" % (lab, d)))
            k = 0 if p in humans else 2
            crops[d][k].append(c)
            crops[d][k + 1].append(lab)
    for d, (hi, hc, gi, gc) in crops.items():
        rows = []
        for imgs, caps in ((hi, hc), (gi, gc)):
            if imgs:
                rows.append((imgs, caps))
        _rows_sheet(rows, os.path.join(tagdir, "dept_%s.png" % d), "%s: human maps (top), generated (bottom)" % d)
    json.dump(index, open(os.path.join(tagdir, "index.json"), "w"), indent=1)
    print("gallery %s: %d maps, sheets in %s" % (tag, len(paths), tagdir))


def _rows_sheet(rows, out, title, H=300, maxw=2400):
    from PIL import Image, ImageDraw
    from forge.render import _font
    ft, fs = _font(18), _font(13)
    lines = []
    for imgs, caps in rows:
        line, w = [], 0
        for im, cap in zip(imgs, caps):
            s = H / float(im.height)
            if im.width * s > maxw / 2:
                s = (maxw / 2) / float(im.width)
            r = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))))
            if w + r.width + 12 > maxw and line:
                lines.append(line)
                line, w = [], 0
            line.append((r, cap))
            w += r.width + 12
        if line:
            lines.append(line)
        lines.append(None)  # gap between human and generated rows
    W = max(sum(r.width + 12 for r, _ in ln) for ln in lines if ln) + 12
    Ht = 40 + sum((max(r.height for r, _ in ln) + 26) if ln else 14 for ln in lines)
    sheet = Image.new("RGB", (W, Ht), (22, 24, 30))
    d = ImageDraw.Draw(sheet)
    d.text((12, 10), title, fill=(240, 240, 240), font=ft)
    y = 40
    for ln in lines:
        if not ln:
            y += 14
            continue
        x = 12
        for r, cap in ln:
            d.text((x, y), cap, fill=(220, 220, 220), font=fs)
            sheet.paste(r, (x, y + 18))
            x += r.width + 12
        y += max(r.height for r, _ in ln) + 26
    sheet.save(out)


def compare(a, b):
    from PIL import Image
    ia = json.load(open(os.path.join(OUT, a, "index.json")))
    ib = json.load(open(os.path.join(OUT, b, "index.json")))
    out = os.path.join(OUT, "compare_%s_%s" % (a, b))
    os.makedirs(out, exist_ok=True)
    n = 0
    for lab, ea in ia.items():
        eb = ib.get(lab)
        if ea["human"] or not eb:
            continue
        A, B = Image.open(ea["png"]).convert("RGB"), Image.open(eb["png"]).convert("RGB")
        for d in DEPTS:
            ba, bb = ea["boxes"].get(d), eb["boxes"].get(d)
            if not ba or not bb:
                continue
            # one box covering both, so the two crops line up
            box = (min(ba[0], bb[0]), min(ba[1], bb[1]), max(ba[2], bb[2]), max(ba[3], bb[3]))
            _rows_sheet([([crop(A, ea["maxy"], box), crop(B, eb["maxy"], box)], [a, b])],
                        os.path.join(out, "%s_%s.png" % (lab, d)), "%s %s: %s | %s" % (lab, d, a, b), H=420)
            n += 1
    print("compare %s %s: %d sheets in %s" % (a, b, n, out))


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--compare"]:
        compare(args[1], args[2])
    else:
        tag = "now"
        if args[:1] == ["--tag"]:
            tag, args = args[1], args[2:]
        build(tag, args, with_human=True)
