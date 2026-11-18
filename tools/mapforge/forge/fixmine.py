"""Map fix mining (plan A3): what human mappers fix in station maps after they ship, read from tg's git history. Each
fix is a fault a generator should not make; the commonest are the first rules and checks to write.

    python tools/mapforge/forge/fixmine.py list               # every commit touching a station map, sorted by kind
    python tools/mapforge/forge/fixmine.py diff [--n 40]      # tile diffs of the newest N fix commits

The tg clone is data/mapforge/corpus/tg (full history, blobless: a map version is fetched from GitHub the first time
it is read, about 3-6 MB each). Output in data/mapforge/fixes/: commits.jsonl (list), diffs.jsonl and report.txt
(diff): per fix, how many tiles changed and how (wall to floor, door added, object kinds added and removed), and over
all fixes, which changes are commonest.

A commit is a fix when its title says so (fix, missing, broken, unreachable, ...), it touches 3 station maps or fewer
(a fix to one map, not a repath across all of them), and it isn't an [MDB IGNORE] code change.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, dmm, alias, corpus_index  # noqa: E402

ROOT = parse.ROOT
TG = os.path.join(ROOT, "data", "mapforge", "corpus", "tg")
OUT = os.path.join(ROOT, "data", "mapforge", "fixes")
FIX = re.compile(r"\b(fix\w*|missing|broken|unreachable|can'?t|cannot|stuck|block\w*|wrong|misplac\w*|disconnect\w*|"
                 r"doesn'?t|isn'?t|unwired|unpowered|no power|leak\w*|depressuri\w*|access|inaccessible|"
                 r"overlap\w*|duplicate\w*|stacked|floating|mislabel\w*|incorrect)\b", re.I)
NOT_FIX = re.compile(r"\[?mdb ignore\]?|refactor|repath|port[s ]|adds? .* to all|replaces? .* (with|on all)", re.I)
SPLIT = "\x1e"


def git(*args, binary=False):
    r = subprocess.run(["git", "-C", TG] + list(args), capture_output=True)
    if r.returncode:
        raise RuntimeError(r.stderr.decode("utf-8", "replace")[:300])
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def station_map(path):
    low = path.lower()
    if not low.startswith("_maps/map_files/") or not low.endswith(".dmm"):
        return False
    return not any(s in low[len("_maps/map_files/"):] for s in corpus_index.SKIP_NAMES)


def commits():
    """Every commit touching a station map: (sha, date, title, [station maps])."""
    raw = git("log", "--format=" + SPLIT + "%H|%ad|%s", "--date=short", "--name-only", "--", "_maps/map_files")
    out = []
    for block in raw.split(SPLIT)[1:]:
        lines = [l for l in block.splitlines() if l.strip()]
        sha, date, title = lines[0].split("|", 2)
        maps = [l for l in lines[1:] if station_map(l)]
        if maps:
            out.append(dict(sha=sha, date=date, title=title, maps=maps))
    return out


def kind(c):
    t = c["title"]
    if NOT_FIX.search(t):
        return "code"
    if len(c["maps"]) > 3:
        return "wide"
    return "fix" if FIX.search(t) else "change"


# what a fix is about, read from its title: each is a family of checks a generator's output should pass
FAULTS = [
    ("access", r"access|req_|id lock|locked"),
    ("power", r"\bapc|power|wire|wiring|cable|smes|unpowered|solar"),
    ("pipes", r"pipe|vent|scrubber|atmos|distro|waste|meter|valve|pump"),
    ("airtight", r"spaced|space|leak|breach|depressur|exposed|airtight|vacuum|hull"),
    ("walls", r"\bwall|window|grille|r_wall"),
    ("doors", r"door|airlock|windoor|shutter|blast"),
    ("area", r"\barea|apc area|named|name|label|sign"),
    ("missing", r"missing|forgot|lacks|no \w+ in"),
    ("dupes", r"duplicate|stacked|overlap|double|two \w+ on"),
    ("placement", r"misplac|wrong|floating|offset|pixel|dir\b|facing|rotat|inside|on top|clipping"),
    ("reach", r"unreachable|inaccessible|can'?t (get|reach|access|enter|leave)|stuck|trapped|block"),
    ("disposals", r"disposal|conveyor|mail"),
    ("cameras", r"camera"),
    ("lights", r"\blight"),
]
FAULT_RE = [(n, re.compile(p, re.I)) for n, p in FAULTS]


def faults(title):
    return [n for n, r in FAULT_RE if r.search(title)] or ["other"]


def cmd_list(a):
    os.makedirs(OUT, exist_ok=True)
    cs = commits()
    with open(os.path.join(OUT, "commits.jsonl"), "w", encoding="utf-8") as f:
        for c in cs:
            c["kind"] = kind(c)
            f.write(json.dumps(c) + "\n")
    k = Counter(c["kind"] for c in cs)
    print("%d commits touch station maps: %s" % (len(cs), dict(k)))
    words = Counter(w.lower() for c in cs if c["kind"] == "fix" for w in FIX.findall(c["title"]))
    print("fix words:", ", ".join("%s %d" % kv for kv in words.most_common(20)))
    per = Counter(os.path.basename(m) for c in cs if c["kind"] == "fix" for m in c["maps"])
    print("fixes per map:", ", ".join("%s %d" % kv for kv in per.most_common(12)))
    fc = Counter(f for c in cs if c["kind"] == "fix" for f in faults(c["title"]))
    nfix = sum(1 for c in cs if c["kind"] == "fix")
    print("fault classes (by title, of %d fixes):" % nfix)
    for f, v in fc.most_common():
        print("  %-12s %4d  %3.0f%%" % (f, v, 100.0 * v / nfix))
    for c in [c for c in cs if c["kind"] == "fix"][:25]:
        print("  %s %s  %s" % (c["date"], c["sha"][:9], c["title"][:100]))


# ------------------------------------------------------------------------------------------------ tile diffs

def version(sha, path, tmp):
    """A map as it was at a commit, aliased and read semantically on its station z-level."""
    data = git("show", "%s:%s" % (sha, path), binary=True)
    f = os.path.join(tmp, "v.dmm")
    open(f, "wb").write(data)
    m = dmm.read(f)
    alias.apply(m)
    per_z = Counter(z for (x, y, z), t in m.tiles.items() if t.turf is not None and t.turf.path.startswith("/turf/open"))
    z = max(per_z, key=per_z.get) if per_z else 1
    return m, parse.SemanticMap(m, os.path.basename(path), z), z


def kinds_of(tile):
    """Object kinds on a tile, cut to 3 path parts (/obj/machinery/door), so a renamed subtype isn't a change."""
    return Counter("/".join(o.path.split("/")[:4]) for o in tile.objs) if tile else Counter()


def tile_diff(a, b):
    ma, sa, za = a
    mb, sb, zb = b
    if (ma.maxx, ma.maxy, ma.maxz) != (mb.maxx, mb.maxy, mb.maxz):
        return None
    res = dict(tiles=0, cls=Counter(), added=Counter(), removed=Counter(), edited=Counter(), turf=Counter(), area=0,
               places=Counter(), other_z=0)
    for pos, tb in mb.tiles.items():
        ta = ma.tiles.get(pos)
        # the tile's whole text (every var), so an access or dir edit counts too
        if ta is not None and ta.text() == tb.text():
            continue
        x, y, z = pos
        res["tiles"] += 1
        if z != zb:
            res["other_z"] += 1
        else:
            ca, cb = sa.cls.get((x, y)), sb.cls.get((x, y))
            if ca != cb:
                res["cls"]["%s>%s" % (ca, cb)] += 1
            res["places"][sb.group.get((x, y)) or sa.group.get((x, y)) or "-"] += 1
        ka, kb = kinds_of(ta), kinds_of(tb)
        for k, v in (kb - ka).items():
            res["added"][k] += v
        for k, v in (ka - kb).items():
            res["removed"][k] += v
        if ta is not None:
            # same kind on both sides but its vars (access, dir, name, pixel offset) changed
            sa_ = Counter(o.text() for o in ta.objs)
            sb_ = Counter(o.text() for o in tb.objs)
            for o in tb.objs:
                if sb_[o.text()] > sa_.get(o.text(), 0) and any(p.path == o.path for p in ta.objs):
                    res["edited"]["/".join(o.path.split("/")[:4])] += 1
            if ta.tpath != tb.tpath:
                res["turf"]["%s>%s" % (ta.tpath.rsplit("/", 1)[-1], tb.tpath.rsplit("/", 1)[-1])] += 1
            if ta.apath != tb.apath:
                res["area"] += 1
    return res


def cmd_diff(a):
    os.makedirs(OUT, exist_ok=True)
    src = os.path.join(OUT, "commits.jsonl")
    if not os.path.exists(src):
        cmd_list(a)
    fixes = [json.loads(l) for l in open(src, encoding="utf-8")]
    fixes = [c for c in fixes if c["kind"] == "fix" and c["date"] >= a.since][:a.n]
    tot = dict(cls=Counter(), added=Counter(), removed=Counter(), edited=Counter(), turf=Counter(), places=Counter(),
               size=Counter(), what=Counter())
    rep = open(os.path.join(OUT, "report.txt"), "w", encoding="utf-8")
    dj = open(os.path.join(OUT, "diffs.jsonl"), "a", encoding="utf-8")
    done = 0
    t0 = time.time()
    with tempfile.TemporaryDirectory() as tmp:
        for c in fixes:
            for path in c["maps"]:
                try:
                    before = version(c["sha"] + "^", path, tmp)
                    after = version(c["sha"], path, tmp)
                except Exception as e:  # a map added or deleted by the commit, or a fetch failure
                    print("  skip %s %s: %s" % (c["sha"][:9], os.path.basename(path), str(e)[:80]))
                    continue
                d = tile_diff(before, after)
                if d is None:
                    print("  skip %s %s: map resized" % (c["sha"][:9], os.path.basename(path)))
                    continue
                done += 1
                size = "0" if not d["tiles"] else "1-4" if d["tiles"] <= 4 else "5-20" if d["tiles"] <= 20 else "21-100" if d["tiles"] <= 100 else "100+"
                tot["size"][size] += 1
                for k in ("cls", "added", "removed", "edited", "turf", "places"):
                    tot[k].update(d[k])
                for w, on in (("layout", d["cls"]), ("objects", d["added"] or d["removed"]), ("vars", d["edited"]),
                              ("turf", d["turf"]), ("area", d["area"]), ("other z", d["other_z"])):
                    if on:
                        tot["what"][w] += 1
                rec = dict(sha=c["sha"], date=c["date"], title=c["title"], map=path, tiles=d["tiles"], area=d["area"],
                           other_z=d["other_z"], cls=dict(d["cls"]), added=dict(d["added"]), removed=dict(d["removed"]),
                           edited=dict(d["edited"]), turf=dict(d["turf"]), places=dict(d["places"]))
                dj.write(json.dumps(rec) + "\n")
                line = "%s %-22s %4d tiles  %-60s  +%s  -%s  ~%s" % (
                    c["date"], os.path.basename(path)[:22], d["tiles"], c["title"][:60],
                    ",".join("%s %d" % (k.rsplit("/", 1)[-1], v) for k, v in d["added"].most_common(3)),
                    ",".join("%s %d" % (k.rsplit("/", 1)[-1], v) for k, v in d["removed"].most_common(3)),
                    ",".join("%s %d" % (k.rsplit("/", 1)[-1], v) for k, v in (d["edited"] + d["turf"]).most_common(3)))
                print(line)
                rep.write(line + "\n")
    rep.write("\n%d map fixes read (%.0fs)\n" % (done, time.time() - t0))
    for k, title in (("what", "fixes that change (one fix can do several)"), ("size", "tiles changed per fix"), ("cls", "tile class changes (S space, W wall, D door, F floor)"),
                     ("added", "object kinds added"), ("removed", "object kinds removed"), ("edited", "object kinds with vars edited (access, dir, name)"),
                     ("turf", "turf changes"), ("places", "where")):
        rep.write("%s: %s\n" % (title, ", ".join("%s %d" % kv for kv in tot[k].most_common(15))))
    rep.close()
    print(open(os.path.join(OUT, "report.txt"), encoding="utf-8").read().split("\n\n", 1)[-1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("list", "diff"))
    ap.add_argument("--n", type=int, default=40)
    ap.add_argument("--since", default="2019-06-01")  # TGM-format maps from here
    a = ap.parse_args()
    cmd_list(a) if a.cmd == "list" else cmd_diff(a)


if __name__ == "__main__":
    main()
