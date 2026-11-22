"""Which pass of the v6 build causes which gate regression, by ablation (the user, 2026-11-22: "objective data only,
no guessing"). Builds the station once per switch set (each switch turns one pass off), gates every build against the
accepted one, and prints a matrix: one row per regression item (a room's stat, a fingerprint feature, a whole-map
check), one column per build, with the raw value and the stock band beside it. A regression that goes away when a
pass is off belongs to that pass; one that stays in every column comes from the department blueprints or the plan.

    python tools/mapforge/station/v6_ablate.py                       # NONE + each of V6_NO_TIDY/HABITS/ROOMS
    python tools/mapforge/station/v6_ablate.py --sets NONE,V6_NO_TIDY --jobs 2
    python tools/mapforge/station/v6_ablate.py --reuse                # gate the abl_*.dmm already on disk
    python tools/mapforge/station/v6_ablate.py --maps data/mapforge/a.dmm,data/mapforge/b.dmm   # any maps

A set is NONE (every pass on) or switches joined by '+' (V6_NO_TIDY+V6_NO_HABITS, V6_SKIP=glaze,fixtures). Builds are written to
data/mapforge/abl_<set>.dmm with --no-render --no-gate; --jobs runs that many at once (each ~90 s, CPU only).
"""
import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, room_stats as RS, size_budget  # noqa: E402
from station import v6_gate  # noqa: E402

ROOT = parse.ROOT
DATA = os.path.join(ROOT, "data", "mapforge")
DEFAULT_SETS = ("NONE", "V6_NO_TIDY", "V6_NO_HABITS", "V6_NO_ROOMS")


def fname(s):
    return s.replace("=", "-").replace(",", "_")


def build_sets(sets, jobs, extra_env=None):
    procs, left = [], list(sets)
    t0 = time.time()
    while left or procs:
        while left and len(procs) < jobs:
            s = left.pop(0)
            env = dict(os.environ, CUDA_VISIBLE_DEVICES="", **(extra_env or {}))
            for sw in s.split("+"):
                if "=" in sw:
                    k, v = sw.split("=", 1)
                    env[k] = v
                elif sw != "NONE":
                    env[sw] = "1"
            log = open(os.path.join(DATA, "abl_%s.log" % fname(s)), "w")
            p = subprocess.Popen([sys.executable, os.path.join(HERE, "v6_station.py"), "--no-render", "--no-gate",
                                  "--name", "abl_" + fname(s)], env=env, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT)
            procs.append((s, p, log))
        for s, p, log in list(procs):
            if p.poll() is not None:
                log.close()
                procs.remove((s, p, log))
                print("ablate: built abl_%s in %.0f s (exit %d)" % (s, time.time() - t0, p.returncode), flush=True)
        time.sleep(1)


def items(path):
    """{key: (detail, cur_raw)} of every regression of one map against the accepted build."""
    base = v6_gate._base()
    cur = v6_gate.full_measure(path)
    out = {}
    raw = {rm.area: rm.stats for rm in RS.rooms(parse.load(path))}
    for area, st in cur["rooms"].items():
        b = base["rooms"].get(area)
        for k in RS.STATS:
            if b is None:
                if k in v6_gate.NEW_ROOM_STATS and st[k] > v6_gate.EPS:
                    out[("new room", area, k)] = (st[k], raw[area][k])
            elif st[k] > b[k] + v6_gate.EPS:
                out[("room", area, k)] = (st[k], raw[area][k])
    for n, f, box, area in cur["pockets"]:
        out[("pocket", "%d,%d-%d,%d" % tuple(box), area)] = (f, n)
    for k, v in cur["fp"].items():
        if v > base["fp"].get(k, 0.0) + 0.02:
            out[("fp", k, "")] = (v, None)
    s = v6_gate.summary(path)
    for name, ok, val in s:
        if not ok:
            out[("check", name, "")] = (val, None)
    return out


def band(area, stat):
    kind = RS.type_of(area)
    peers = RS.peers(kind) if kind else []
    if not peers:
        return ""
    vs = [p.stats[stat] for p in peers]
    return "%.2f..%.2f" % (min(vs), max(vs))


def accepted_raw():
    return {rm.area: rm.stats for rm in RS.rooms(parse.load(v6_gate.ACCEPTED))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sets", default=",".join(DEFAULT_SETS))
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--reuse", action="store_true", help="gate the abl_<set>.dmm on disk, build nothing")
    ap.add_argument("--maps", default="", help="comma-separated maps to gate instead of ablation builds")
    a = ap.parse_args()
    if a.maps:
        cols = [(os.path.splitext(os.path.basename(p))[0], p) for p in a.maps.split(",")]
    else:
        sets = a.sets.split(",")
        if not a.reuse:
            build_sets(sets, a.jobs)
        cols = [(s, os.path.join(DATA, "abl_%s.dmm" % fname(s))) for s in sets]
    res = {}
    for name, path in cols:
        res[name] = items(path)
        print("ablate: %-28s %d regressions" % (name, len(res[name])), flush=True)
    acc = accepted_raw()
    keys = sorted(set(k for r in res.values() for k in r))
    w = max(12, max(len(n) for n, _ in cols))
    print("\n%-62s %-12s %-14s " % ("regression", "accepted", "stock band") + " ".join("%-*s" % (w, n) for n, _ in cols))
    for k in keys:
        kind, a1, a2 = k
        label = ("%s %s %s" % (kind, a1.replace("/area/", ""), a2)).strip()[:62]
        accv = "%.2f" % acc[a1][a2] if kind == "room" and a1 in acc else ""
        bnd = band(a1, a2) if kind in ("room", "new room") else ""
        cells = []
        for n, _ in cols:
            v = res[n].get(k)
            if v is None:
                cells.append("-")
            elif kind in ("room", "new room"):
                cells.append("%.2f" % v[1])
            elif kind == "pocket":
                cells.append("%dt %.2f" % (v[1], v[0]))
            else:
                cells.append(str(v[0]) if not isinstance(v[0], float) else "%.2f" % v[0])
        print("%-62s %-12s %-14s " % (label, accv, bnd) + " ".join("%-*s" % (w, c) for c in cells))


if __name__ == "__main__":
    main()
