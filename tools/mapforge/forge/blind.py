"""Blind test and tile tagging (plan F1 + F2): a local page that shows crops of human and generated maps.

    python tools/mapforge/forge/blind.py build [--seed N] [--pairs 12]   # cut crops, data/mapforge/blind/
    python tools/mapforge/forge/blind.py serve [--port 8765]             # http://localhost:8765
    python tools/mapforge/forge/blind.py score                           # human-pick rate per scale

Blind: two crops at one scale, one from a human map and one generated, sides shuffled. Pick the human one. The pass
bar (plan section 1) is human picked at most 55% of the time at every scale. Scales: room (12 tiles), dept (28),
quarter (56), whole station. Crops come from the cached full renders (forge/gallery.py), no labels, no names.
Tag: a generated crop; click tiles and give each a word (wrong, ugly, good, why). Tags are what the taste model and
the rule registry learn from.
Answers: data/mapforge/blind/answers.jsonl (one line per pick or tag, with map, box and time taken).
"""
import json
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, gallery  # noqa: E402

ROOT = parse.ROOT
OUT = os.path.join(ROOT, "data", "mapforge", "blind")
SCALES = (("room", 12), ("dept", 28), ("quarter", 56), ("whole", 0))
PX = gallery.PX


def _boxes(sm, size, n, rnd):
    """n boxes of size x size tiles, mostly station floor and walls, little space."""
    st = sm.station_tiles()
    out, tries = [], 0
    while len(out) < n and tries < 4000:
        tries += 1
        c = rnd.choice(st)
        x0, y0 = c[0] - size // 2, c[1] - size // 2
        box = (x0, y0, x0 + size - 1, y0 + size - 1)
        cells = [sm.cls.get((x, y), "S") for x in range(box[0], box[2] + 1) for y in range(box[1], box[3] + 1)]
        floor = sum(1 for k in cells if k == "F") / float(len(cells))
        space = sum(1 for k in cells if k == "S") / float(len(cells))
        if floor < 0.45 or space > 0.15:
            continue
        if any(abs(b[0] - box[0]) < size // 2 and abs(b[1] - box[1]) < size // 2 for b in out):
            continue
        out.append(box)
    return out


def build(seed=1, pairs=12):
    from PIL import Image
    rnd = random.Random(seed)
    humans = [parse.map_path(n) for n in parse.MAPS]
    gens = sorted(p for p in __import__("glob").glob(os.path.join(gallery.GEN_DIR, "*.dmm")))
    pngs = gallery.full_renders(humans + gens)
    imgdir = os.path.join(OUT, "img")
    os.makedirs(imgdir, exist_ok=True)
    crops = {}  # (path, scale) -> [crop records]
    cache = {}

    def img_of(p):
        if p not in cache:
            cache[p] = Image.open(pngs[p]).convert("RGB")
        return cache[p]

    def cut(p, scale, box):
        sm = parse.load(p)
        im = gallery.crop(img_of(p), sm.m.maxy, box)
        if scale == "whole":
            k = 900.0 / max(im.width, im.height)
            im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
        cid = "c%05d" % rnd.randrange(100000)
        while os.path.exists(os.path.join(imgdir, cid + ".png")):
            cid = "c%05d" % rnd.randrange(100000)
        im.save(os.path.join(imgdir, cid + ".png"))
        return dict(id=cid, map=sm.name, path=p, human=p in humans, scale=scale, box=box,
                    w=box[2] - box[0] + 1, h=box[3] - box[1] + 1)

    items = []
    for scale, size in SCALES:
        for p in humans + gens:
            sm = parse.load(p)
            if scale == "whole":
                x0, y0, x1, y1 = sm.bbox(sm.station_tiles())
                boxes = [(x0 - 2, y0 - 2, x1 + 2, y1 + 2)]
            else:
                per = max(2, pairs // len(gens) + 1) if p in gens else max(1, pairs // len(humans) + 1)
                boxes = _boxes(sm, size, per, rnd)
            crops[(p, scale)] = [cut(p, scale, b) for b in boxes]
    blind = []
    for scale, _ in SCALES:
        hs = [c for p in humans for c in crops[(p, scale)]]
        gs = [c for p in gens for c in crops[(p, scale)]]
        rnd.shuffle(hs)
        rnd.shuffle(gs)
        n = pairs if scale != "whole" else min(pairs, len(hs), 2 * len(gs))
        for i in range(n):
            h, g = hs[i % len(hs)], gs[i % len(gs)]
            pair = [h["id"], g["id"]]
            rnd.shuffle(pair)
            blind.append(dict(pid="%s%02d" % (scale, i), scale=scale, left=pair[0], right=pair[1]))
    rnd.shuffle(blind)
    tags = [c["id"] for p in gens for s in ("room", "dept") for c in crops[(p, s)]]
    allc = {c["id"]: c for v in crops.values() for c in v}
    json.dump(dict(seed=seed, made=time.strftime("%Y-%m-%d %H:%M"), crops=allc, blind=blind, tags=tags),
              open(os.path.join(OUT, "set.json"), "w"), indent=1)
    print("blind set: %d pairs, %d tag crops, %d images in %s" % (len(blind), len(tags), len(allc), imgdir))


def score():
    s = json.load(open(os.path.join(OUT, "set.json")))
    crops = s["crops"]
    path = os.path.join(OUT, "answers.jsonl")
    if not os.path.exists(path):
        print("no answers yet")
        return
    per = {}
    last = {}  # the newest pick per pair counts (the page's Back lets a pair be picked again)
    for line in open(path):
        a = json.loads(line)
        if a.get("kind") == "pick" and a["pick"] in crops:
            last[a["pid"]] = a
    for a in last.values():
        k = per.setdefault(a["scale"], [0, 0, []])
        k[1] += 1
        if crops[a["pick"]]["human"]:
            k[0] += 1
        else:
            k[2].append(crops[a["pick"]]["map"])
    print("%-8s %5s %5s %6s  (pass: human picked <= 55%%)" % ("scale", "picks", "human", "rate"))
    for scale, _ in SCALES:
        if scale in per:
            h, n, fooled = per[scale]
            print("%-8s %5d %5d %5.0f%%  %s" % (scale, n, h, 100.0 * h / n, "fooled by " + ", ".join(fooled) if fooled else ""))


PAGE = os.path.join(HERE, "blind_page.html")


def serve(port=8765):
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class H(BaseHTTPRequestHandler):
        def _send(self, code, body, ctype):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path in ("/", "/index.html"):
                return self._send(200, open(PAGE, "rb").read(), "text/html; charset=utf-8")
            if self.path == "/set":
                s = json.load(open(os.path.join(OUT, "set.json")))
                # the page never learns which crop is human
                pub = {k: dict(w=v["w"], h=v["h"], scale=v["scale"]) for k, v in s["crops"].items()}
                done = []
                ap = os.path.join(OUT, "answers.jsonl")
                if os.path.exists(ap):
                    done = [json.loads(l).get("pid") for l in open(ap)]
                return self._send(200, json.dumps(dict(crops=pub, blind=s["blind"], tags=s["tags"],
                                                       done=[d for d in done if d])).encode(), "application/json")
            if self.path.startswith("/img/"):
                name = os.path.basename(self.path)
                f = os.path.join(OUT, "img", name)
                if name.endswith(".png") and os.path.exists(f):
                    return self._send(200, open(f, "rb").read(), "image/png")
            self._send(404, b"not found", "text/plain")

        def do_POST(self):
            if self.path != "/answer":
                return self._send(404, b"", "text/plain")
            n = int(self.headers.get("Content-Length", 0))
            a = json.loads(self.rfile.read(n) or b"{}")
            s = json.load(open(os.path.join(OUT, "set.json")))
            c = s["crops"].get(a.get("crop") or a.get("pick") or "")
            if c:
                a.update(map=c["map"], box=c["box"])
            a["t"] = time.strftime("%Y-%m-%d %H:%M:%S")
            with open(os.path.join(OUT, "answers.jsonl"), "a") as f:
                f.write(json.dumps(a) + "\n")
            self._send(200, b"{}", "application/json")

        def log_message(self, *a):
            pass

    print("blind page on http://localhost:%d" % port)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args[0] if args else "build"
    opt = dict(zip(args[1::2], args[2::2])) if len(args) > 1 else {}
    if cmd == "build":
        build(int(opt.get("--seed", 1)), int(opt.get("--pairs", 12)))
    elif cmd == "serve":
        serve(int(opt.get("--port", 8765)))
    elif cmd == "score":
        score()
