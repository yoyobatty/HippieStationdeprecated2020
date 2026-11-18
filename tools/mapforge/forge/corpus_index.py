"""Corpus index (plan A1): the human station maps cloned from other codebases into data/mapforge/corpus/<source>/,
read through forge/alias.py, each on its main station z-level, near-copies of maps we already have dropped.

    python tools/mapforge/forge/corpus_index.py          # writes data/mapforge/corpus/index.json and prints a table

A map is kept when it has 2500+ station floor tiles and its wall/floor grid is under 70% the same as a map already
kept (the 9 in parse.MAPS come first). The clones are sparse (map files only) and blobless:
    git clone --filter=blob:none --no-checkout --sparse <repo> <source>
    git sparse-checkout set --no-cone '/_maps/map_files/*/*.dmm' ...
Sources: tg (tgstation master), bee (BeeStation-Hornet), yog (Yogstation), paradise (ParadiseSS13), citadel.
"""
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, dmm, alias  # noqa: E402

ROOT = parse.ROOT
CORPUS = os.path.join(ROOT, "data", "mapforge", "corpus")
SKIP_NAMES = ("debug", "test", "festive", "syndicate", "wilderness", "centcom", "shuttle", "ruin", "away", "mining",
              "lavaland", "icemoon", "template", "multiz", "runtime", "lobby", "mafia", "event", "ctf")


def candidates():
    out = []
    for src in sorted(os.listdir(CORPUS)):
        base = os.path.join(CORPUS, src, "_maps", "map_files")
        if not os.path.isdir(base):
            continue
        for p in sorted(glob.glob(os.path.join(base, "**", "*.dmm"), recursive=True)):
            low = p.replace("\\", "/").lower()
            if os.path.getsize(p) < 900000 or any(s in low.rsplit("/map_files/", 1)[1] for s in SKIP_NAMES):
                continue
            out.append((src, p))
    return out


def grid(sm):
    """Wall/floor/door tiles of the station's box at map coordinates, for near-copy checks."""
    st = sm.station_tiles()
    if not st:
        return None, 0
    x0, y0, x1, y1 = sm.bbox(st)
    g = {(x, y): sm.cls.get((x, y)) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)
         if sm.cls.get((x, y)) in ("W", "F", "D")}
    return g, len(st)


def same(a, b):
    """Share of tiles agreeing on wall/floor at the same map coordinates (copies of one map keep their coordinates)."""
    keys = set(a) | set(b)
    if not keys:
        return 0.0
    return sum(1 for k in keys if a.get(k) == b.get(k)) / float(len(keys))


def main():
    t0 = time.time()
    sys.path.insert(0, os.path.join(HERE, "..", "studies"))
    import stations as ST
    kept = []  # (name, grid)
    family = {}  # remakes of one map share a family, so held-out tests hold out the whole family
    for n in parse.MAPS:
        g, _ = grid(parse.load(n))
        kept.append((n, g))
        family[n] = n
    family["MetaLake"] = "MetaStation"
    index = {}
    for src, p in candidates():
        m = dmm.read(p)
        counts = dict(alias.apply(m))
        # the z-level with the most station floor
        per_z = {}
        for (x, y, z), t in m.tiles.items():
            if t.area is None or t.turf is None or not t.turf.path.startswith("/turf/open"):
                continue
            g = ST.group_of(t.area.path)
            if g and g not in ("shuttle", "solar") and not g.startswith("other:"):
                per_z[z] = per_z.get(z, 0) + 1
        if not per_z:
            continue
        z = max(per_z, key=per_z.get)
        name = "%s:%s" % (src, os.path.splitext(os.path.basename(p))[0])
        sm = parse.SemanticMap(m, name, z)
        g, floor = grid(sm)
        rec = dict(path=p.replace("\\", "/"), z=z, source=src, floor=floor, levels=len(per_z), alias=counts)
        if floor < 2500:
            rec.update(keep=False, why="small (%d floor)" % floor)
        else:
            near = max(((same(g, kg), kn) for kn, kg in kept), default=(0, None))
            if near[0] >= 0.70:
                rec.update(keep=False, why="near-copy of %s (%.0f%%)" % (near[1], 100 * near[0]))
            else:
                rec.update(keep=True, why="closest %s %.0f%%" % (near[1], 100 * near[0]))
                family[name] = family[near[1]] if near[0] >= 0.5 else name
                rec["family"] = family[name]
                kept.append((name, g))
        # unknown areas left after aliasing: the alias table's to-do list
        other = {}
        for t in sm.area.values():
            gg = ST.group_of(t)
            if gg and gg.startswith("other:"):
                other[t] = other.get(t, 0) + 1
        rec["unknown_areas"] = sorted(other, key=lambda k: -other[k])[:8]
        index[name] = rec
        print("%-34s z%d floor %5d %-5s %s%s" % (name, z, floor, "KEEP" if rec["keep"] else "-", rec["why"],
                                                  ("  unknown: " + ", ".join(rec["unknown_areas"][:4])) if rec["unknown_areas"] else ""))
    json.dump(index, open(os.path.join(CORPUS, "index.json"), "w"), indent=1)
    print("%d kept of %d (%.0fs) -> %s" % (sum(1 for v in index.values() if v["keep"]), len(index), time.time() - t0,
                                           os.path.join(CORPUS, "index.json")))


if __name__ == "__main__":
    main()
