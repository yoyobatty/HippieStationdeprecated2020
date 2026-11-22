"""Style bands: what every room of a type looks like on Meta, Delta, Omega and Hippie, and a lint of a map's rooms
against it. Where room_twin.py shows a room beside its nearest twins, this holds it against all the stock rooms of
its type and reports in text, for the whole map at once.

    python tools/mapforge/forge/style_bands.py data/mapforge/station_v6.dmm          # lint a map
    python tools/mapforge/forge/style_bands.py station_v6.dmm --dept science          # one department
    python tools/mapforge/forge/style_bands.py --show medical/surgery                 # the band of one type

Per room type (room_stats.type_of) the band of each number is the stock rooms' min..max (types with 3+ stock
rooms; with fewer, only the object checks run). Object checks, by object family (room_stats._family):
    missing   a family in 60%+ of the stock rooms of the type (3+ rooms) that the room lacks
    stranger  a family the room has that none of 3+ stock rooms of its type has (shared fixtures excluded)

The summary first: for each number, the share of the map's rooms above and below their band. A number most rooms
miss the same way is a habit of the generator, not of one room (fill above the band in most rooms = rooms too
rectangular). Output: data/mapforge/style_bands/<map>.md and the summary on stdout.
"""
import argparse
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, room_stats as RS  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "mapforge", "style_bands")
MIN_PEERS = 3
COMMON = 0.6
# in every kind of room; never "missing" or "strange" by type
SHARED = ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
          "/obj/machinery/camera", "/obj/machinery/light_switch", "/obj/machinery/door", "/obj/structure/sign",
          "/obj/item/radio/intercom", "/obj/machinery/newscaster", "/obj/structure/extinguisher_cabinet",
          "/obj/machinery/status_display", "/obj/structure/window", "/obj/structure/grille", "/obj/structure/lattice",
          "/obj/machinery/navbeacon", "/obj/structure/disposaloutlet", "/obj/item/paper", "/obj/item/pen",
          "/obj/item/cigbutt", "/obj/item/trash", "/obj/item/stack", "/obj/item/storage/box", "/obj/structure/cable")


def band(kind):
    peers = RS.peers(kind)
    out = {}
    if len(peers) >= MIN_PEERS:
        for k in RS.STATS:
            vs = sorted(p.stats[k] for p in peers)
            out[k] = (vs[0], vs[len(vs) // 2], vs[-1])
    fam = Counter()
    for p in peers:
        fam.update(set(p.paths))
    return peers, out, fam


def lint(rm):
    kind = RS.type_of(rm.area, need=1)
    if not kind:
        return None
    peers, b, fam = band(kind)
    res = dict(kind=kind, n=len(peers), out={}, missing=[], stranger=[])
    for k, (lo, med, hi) in b.items():
        v = rm.stats[k]
        slack = 0.02 if k in ("fill", "glass", "turf_top") else 0.0
        if v < lo - slack:
            res["out"][k] = ("low", v, lo, med, hi)
        elif v > hi + slack:
            res["out"][k] = ("high", v, lo, med, hi)
    if len(peers) >= MIN_PEERS:
        have = set(rm.paths)
        for f, c in fam.most_common():
            if c / len(peers) >= COMMON and f not in have and not f.startswith(SHARED):
                res["missing"].append((f, c))
        for f in sorted(have):
            if fam[f] == 0 and not f.startswith(SHARED):
                res["stranger"].append(f)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map", nargs="?")
    ap.add_argument("--dept", default="")
    ap.add_argument("--show", default="", help="print the band of one area type and stop")
    a = ap.parse_args()
    if a.show:
        # "medical/surgery" works too (Git Bash rewrites a leading /area/... into a Windows path)
        a.show = "/area/" + a.show.split("/area/", 1)[-1].lstrip("/")
        peers, b, fam = band(a.show)
        print("%s: %d stock rooms: %s" % (a.show, len(peers), ", ".join("%s %s" % (RS.SHORT[p.map], p.name) for p in peers)))
        for k, (lo, med, hi) in b.items():
            print("  %-9s %s .. %s .. %s" % (k, RS.fmt(lo, k), RS.fmt(med, k), RS.fmt(hi, k)))
        print("  objects in most:", ", ".join("%s %d/%d" % (f, c, len(peers)) for f, c in fam.most_common(25)))
        return
    if not a.map:
        ap.error("map or --show")
    path = a.map
    if not os.path.exists(path) and os.path.exists(os.path.join(parse.ROOT, "data", "mapforge", path)):
        path = os.path.join(parse.ROOT, "data", "mapforge", path)
    sm = parse.load(path)
    label = os.path.splitext(os.path.basename(path))[0]
    from forge.room_twin import _dept
    rows = []
    for rm in sorted(RS.rooms(sm), key=lambda r: r.area):
        d = _dept(sm, rm)
        if a.dept and d != a.dept:
            continue
        r = lint(rm)
        if r:
            rows.append((d, rm, r))

    banded = [x for x in rows if x[2]["n"] >= MIN_PEERS]
    print("%s: %d rooms, %d with a stock band (3+ stock rooms of their type)" % (label, len(rows), len(banded)))
    print("habits (share of banded rooms outside the band, and the median room vs the stock median):")
    summary = []
    for k in RS.STATS:
        hi = [x for x in banded if x[2]["out"].get(k, ("",))[0] == "high"]
        lo = [x for x in banded if x[2]["out"].get(k, ("",))[0] == "low"]
        ratios = sorted(x[1].stats[k] / max(1e-6, band(x[2]["kind"])[1][k][1]) for x in banded
                        if band(x[2]["kind"])[1][k][1] > 0)
        med = ratios[len(ratios) // 2] if ratios else 0
        summary.append((len(hi) + len(lo), k, len(hi), len(lo), med))
    n = max(1, len(banded))
    lines = []
    for tot, k, h, l, med in sorted(summary, reverse=True):
        s = "  %-9s above %3d%%  below %3d%%   room/stock median x%.2f" % (k, 100 * h // n, 100 * l // n, med)
        print(s)
        lines.append(s)
    miss = Counter(f for _, _, r in rows for f, _ in r["missing"])
    strange = Counter(f for _, _, r in rows for f in r["stranger"])
    print("most missed objects:", ", ".join("%s x%d" % kv for kv in miss.most_common(8)))
    print("most strange objects:", ", ".join("%s x%d" % kv for kv in strange.most_common(8)))

    md = ["# Style bands: %s" % label, "", "Bands are the min..median..max of the stock rooms of each type "
          "(Meta, Delta, Omega, Hippie).", "", "## Habits", "", "```"] + lines + ["```", "",
          "Most missed: " + ", ".join("`%s` x%d" % kv for kv in miss.most_common(15)), "",
          "Most strange: " + ", ".join("`%s` x%d" % kv for kv in strange.most_common(15)), "", "## Rooms", ""]
    rank = sorted(rows, key=lambda x: -(len(x[2]["out"]) + 0.5 * len(x[2]["missing"]) + 0.3 * len(x[2]["stranger"])))
    for d, rm, r in rank:
        if not (r["out"] or r["missing"] or r["stranger"]):
            continue
        md.append("### %s %s (type %s, %d stock rooms) at %d,%d-%d,%d" % ((d, rm.area, r["kind"], r["n"]) + rm.box))
        for k, (way, v, lo, med, hi) in r["out"].items():
            md.append("- %s %s %s (stock %s..%s..%s)" % (k, way, RS.fmt(v, k), RS.fmt(lo, k), RS.fmt(med, k), RS.fmt(hi, k)))
        if r["missing"]:
            md.append("- missing: " + ", ".join("`%s` (%d/%d)" % (f, c, r["n"]) for f, c in r["missing"]))
        if r["stranger"]:
            md.append("- never in stock rooms of this type: " + ", ".join("`%s`" % f for f in r["stranger"]))
        md.append("")
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, label + ("_" + a.dept if a.dept else "") + ".md")
    open(out, "w", encoding="utf-8").write("\n".join(md))
    print("->", os.path.relpath(out, parse.ROOT))


if __name__ == "__main__":
    main()
