"""Which pass causes which gate failure, measured: take furnished maps (gen/rooms.py output), apply the dress passes
(gen/dress.py) and then gen/connect.py one at a time, run the gate after each, and print what each pass turned on
and off. No guessing which pass to blame.

    python tools/mapforge/gen/trace.py [--dir data/mapforge/gen_rooms] [--maps gen_hub_c80_s4,...] [--jobs 5]

Per map, a line per step: the failing checks added (+) and cleared (-) by that step, the one-door share and the
count of areas reached only through maint. At the end, per check, the steps that turned it on across the maps.
Writes data/mapforge/gen/trace.json.
"""
import argparse
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from forge import dmm, parse  # noqa: E402

STEPS = None


def _fails(path):
    import gate as G
    import build as B
    parse._CACHE.pop((path, 1), None)
    ch = G.run(path, "full", quiet=True)
    ch = [c for c in ch if c["kind"] in ("band", "pair", "hard", "ruled") and c["name"] not in B.M3_PENDING]
    od = next((c["value"] for c in ch if c["name"] == "space.one_door"), None)
    wi = next((c["detail"] for c in ch if c["name"] == "ways in"), "")
    return {c["name"] for c in ch if not c["ok"]}, od, wi


def trace_one(args):
    src, = args
    import dress as DR
    import connect as CN
    from station import v6_station as V6
    m = dmm.read(src)
    tmp = os.path.join(tempfile.gettempdir(), "trace_%d.dmm" % os.getpid())
    rows = []
    dmm.write(m, tmp)
    prev, od, wi = _fails(tmp)
    rows.append(("rooms", sorted(prev), [], od, wi))
    steps = list(DR.PASSES) + ["connect"]
    for st in steps:
        quiet = lambda s: None  # noqa: E731
        try:
            if st == "connect":
                CN.connect(m, quiet)
            else:
                DR.dress(m, quiet, skip=tuple(p for p in DR.PASSES if p != st))
        except Exception as e:      # noqa: BLE001
            rows.append((st, ["ERROR " + str(e)[:80]], [], None, ""))
            continue
        dmm.write(m, tmp)
        cur, od, wi = _fails(tmp)
        rows.append((st, sorted(cur - prev), sorted(prev - cur), od, wi))
        prev = cur
    os.remove(tmp)
    return os.path.basename(src), rows, sorted(prev)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(parse.ROOT, "data", "mapforge", "gen_rooms"))
    ap.add_argument("--maps", default="gen_hub_c40_s3,gen_hub_c80_s1,gen_hub_c80_s4,gen_hub_c120_s1,gen_hub_c120_s2")
    ap.add_argument("--jobs", type=int, default=5)
    a = ap.parse_args(argv)
    srcs = [os.path.join(a.dir, n + ".dmm") for n in a.maps.split(",")]
    if a.jobs > 1:
        import multiprocessing as mp
        with mp.get_context("spawn").Pool(a.jobs) as pool:
            out = pool.map(trace_one, [(s,) for s in srcs])
    else:
        out = [trace_one((s,)) for s in srcs]
    blame = {}
    for name, rows, final in out:
        print("== %s  (final fails: %d)" % (name, len(final)))
        for st, on, off, od, wi in rows:
            if st == "rooms":
                print("   %-16s fails %s  one_door %s" % (st, ", ".join(on) or "-", od))
                continue
            if on or off:
                print("   %-16s +%s  -%s  one_door %s  maint-only areas %d" % (
                    st, ",".join(on) or "", ",".join(off) or "", "%.3f" % od if od is not None else "-",
                    wi.count("/area/")))
            for c in on:
                blame.setdefault(c, []).append(st)
    print("\nchecks turned on, by step (over %d maps):" % len(out))
    for c, sts in sorted(blame.items(), key=lambda kv: -len(kv[1])):
        from collections import Counter
        print("  %-30s %s" % (c, dict(Counter(sts))))
    json.dump(dict(out=out, blame=blame), open(os.path.join(parse.ROOT, "data", "mapforge", "gen", "trace.json"), "w"),
              indent=1, default=str)


if __name__ == "__main__":
    main(sys.argv[1:])
