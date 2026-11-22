"""Stock-room supply: how many human rooms of each type there are to copy whole (forge/room_stamp.py), over the four
look maps (room_stats.REFS: Meta, Delta, Omega, Hippie) and over the whole corpus (parse.humans(), 38 maps). The
generator's room stage copies stock rooms first; this says for which types that is possible and how much choice
each type gives, by size.

    python tools/mapforge/studies/stamp_supply.py                 # table, data/mapforge/gen_targets/
    python tools/mapforge/studies/stamp_supply.py --fresh

Per room type (the area path, as forge/room_stats.rooms reads rooms: one area's floor, its biggest piece):
  refs       rooms on the four look maps; corpus = rooms on all 38; families = distinct map families with one.
  size       p10 / median / p90 tiles over the corpus rooms.
  ready      3+ families have it: a seed can pick among real variants.
Totals per department: types, ready types, and the share of the department's human room floor whose type is ready
(how much of a department can be built from copies alone).
"""
import argparse
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import corpus_common as CC  # noqa: E402
from forge import room_stats as RS  # noqa: E402

STUDY = "stamp_supply"
VERSION = 1


def measure(sm):
    out = []
    for r in RS.rooms(sm):
        out.append(dict(area=r.area, tiles=int(r.stats["tiles"]), fill=round(r.stats["fill"], 3),
                        group=sm.group.get(r.tiles[0])))
    return out


def analyse(res):
    fam = dict(CC.maps())
    by = defaultdict(lambda: dict(refs=0, corpus=0, fams=set(), sizes=[], group=None))
    for n, rooms in res.items():
        for r in rooms or []:
            d = by[r["area"]]
            d["corpus"] += 1
            d["fams"].add(fam.get(n, n))
            d["sizes"].append(r["tiles"])
            d["group"] = d["group"] or r["group"]
            if n in RS.REFS:
                d["refs"] += 1
    types = {}
    for a, d in by.items():
        types[a] = dict(refs=d["refs"], corpus=d["corpus"], families=len(d["fams"]), group=d["group"],
                        size=[CC.quant(d["sizes"], 0.1), CC.median(d["sizes"]), CC.quant(d["sizes"], 0.9)],
                        ready=len(d["fams"]) >= 3)
    depts = {}
    for a, t in types.items():
        g = t["group"] or "?"
        if g.startswith("other") or g in ("hall", "arrivals", "escape", "shuttle", "solar"):
            continue
        d = depts.setdefault(g, dict(types=0, ready=0, ready_refs=0, floor=0, ready_floor=0))
        d["types"] += 1
        fl = sum(by[a]["sizes"])
        d["floor"] += fl
        if t["ready"]:
            d["ready"] += 1
            d["ready_floor"] += fl
        if t["refs"] >= 1:
            d["ready_refs"] += 1
    for d in depts.values():
        d["ready_share"] = round(d["ready_floor"] / float(max(1, d["floor"])), 3)
    return dict(types=types, depts=depts)


def text(out):
    L = ["%-12s %6s %6s %9s %12s" % ("department", "types", "ready", "on REFS", "ready floor")]
    for g, d in sorted(out["depts"].items(), key=lambda kv: -kv[1]["floor"]):
        L.append("%-12s %6d %6d %9d %12.2f" % (g, d["types"], d["ready"], d["ready_refs"], d["ready_share"]))
    L.append("")
    L.append("ready types (3+ families), by department, most families first: area  families/corpus/refs  size p10/med/p90")
    rows = sorted(((a, t) for a, t in out["types"].items() if t["ready"]),
                  key=lambda kv: (kv[1]["group"] or "", -kv[1]["families"]))
    last = None
    for a, t in rows:
        if t["group"] != last:
            L.append("[%s]" % t["group"])
            last = t["group"]
        s = t["size"]
        L.append("  %-52s %2d/%3d/%d  %4s/%4s/%4s" % (a[:52], t["families"], t["corpus"], t["refs"], CC.fmt(s[0], 0),
                                                     CC.fmt(s[1], 0), CC.fmt(s[2], 0)))
    return "\n".join(L)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--fresh", action="store_true")
    a = ap.parse_args(argv)
    res = CC.measure_all(STUDY, measure, fresh=a.fresh, version=VERSION)
    out = analyse(res)
    t = text(out)
    print(t)
    p = CC.save(STUDY, out)
    open(os.path.join(CC.OUT, STUDY + ".txt"), "w").write(t + "\n")
    print("\nwrote", p)


if __name__ == "__main__":
    main(sys.argv[1:])
