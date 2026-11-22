"""The full generator's gate (studies/full_generator_plan.md section 3). Every build runs it; it exits 1 on a failure.

    python tools/mapforge/gen/gate.py <map.dmm> [--stage blocks|full] [--accept] [--name N]
    python tools/mapforge/gen/gate.py --calibrate          # the gate on all 38 human maps: M0's exit test
    python tools/mapforge/gen/gate.py --bands               # print every band

Three kinds of check:
  band     every number the five corpus studies measure (studies/skeleton_types, dept_scaling, dept_adjacency,
           space_sizes), inside its band. A band is the union of the corpus families with the int(0.1 n) most extreme at each end dropped, and
           the min..max of the four look maps (forge/room_stats.REFS: Meta, Delta, Omega, Hippie), so each look map
           passes every band by construction and "as good as the look maps" means inside their envelope.
  pair     department pairs: a pair that 80%+ of families AND all four look maps join must touch ("must touch");
           a pair that 5% or fewer of families and none of the look maps join must not ("never touch"). Plus the
           adjacency log-likelihood of the whole arrangement (a band check).
  hard     whole-map checks from station/v6_gate.py (walk, wall filler, room sizes against stock, core room types),
           bounded by the look maps; RULED ones are the user's rulings, stricter than the stock maps (vents apart,
           pipes stay seen, hull corners, apc areas): the stock maps fail them and calibration reports them apart.
           gen-only: every object path known to this codebase (forge/typeindex).
  ratchet  --name N keeps data/mapforge/gen/baseline/N.json; a build may not be further outside any band, or worse
           on a ratchet count, than its accepted twin. --accept writes it (only after the user has looked).

--stage blocks runs the checks a block plan can answer (skeleton, shares, pairs, radial): M1's test.
Calibration (M0 exit): every look map passes every band, pair and stock-bounded hard check; every band check passes
80%+ of the 32 families; RULED checks are listed with how many look maps fail them.
"""
import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "studies"))
sys.path.append(os.path.join(HERE, "..", "station"))  # last: station/ has its own program.py
import corpus_common as CC  # noqa: E402
import skeleton_types as SK  # noqa: E402
import dept_scaling as DS  # noqa: E402
import dept_adjacency as DA  # noqa: E402
import space_sizes as SP  # noqa: E402
from forge import parse, room_stats as RS  # noqa: E402

ROOT = parse.ROOT
BASE_DIR = os.path.join(ROOT, "data", "mapforge", "gen", "baseline")
LOOK = RS.REFS
SKEL_KEYS = ("hall_share", "loops", "core", "core_dist", "spokes", "spoke_len", "spoke_reach", "arms", "arm_len",
             "spine", "on_loop", "walk_loops", "aspect", "fill", "main")
SHARE_GROUPS = DS.GROUPS
MUST_P, NEVER_P = 0.80, 0.05
RULED = ("vents apart", "pipes stay seen", "hull corners", "apc areas", "vents off terminals", "corridors clear")
BLOCK_PREFIX = ("skel.", "share.", "radial.", "adj.")


# ------------------------------------------------------------------------------------------------ features
def _get(d, k):
    if d is None:
        return None
    if k in d:
        return d[k]
    return d.get(str(k))


def flat_skeleton(v):
    if not v:
        return {}
    return {"skel." + k: v[k] for k in SKEL_KEYS if v.get(k) is not None}


def flat_shares(v):
    if not v:
        return {}
    return {"share." + g: v["share"].get(g, 0.0) for g in SHARE_GROUPS}


def flat_space(v):
    if not v:
        return {}
    d = {}
    for k in range(1, 10):
        d["space.hall_w%d" % k] = _get(v["hall_w"], k) or 0.0
        d["space.maint_w%d" % k] = _get(v["maint_w"], k) or 0.0
    for f in ("hall_mean_w", "hall_run", "maint_pocket", "pockets_per_1k", "pocket_med", "rooms_per_1k", "aspect",
              "rect", "one_door"):
        if v.get(f) is not None:
            d["space." + f] = v[f]
    for q in ("0.1", "0.25", "0.5", "0.75", "0.9", "1.0"):
        x = _get(v["room_q"], q)
        if x is None:
            x = _get(v["room_q"], float(q))
        if x is not None:
            d["space.room_q" + q] = x
    for g, x in v["room_size"].items():
        if g in SP.DEPTS and x is not None:
            d["space.room_size_" + g] = x
    return d


def touching(v):
    """{pair: bool} for every department pair both present."""
    out = {}
    for i, a in enumerate(DA.DEPTS):
        for b in DA.DEPTS[i + 1:]:
            if v["tiles"].get(a) and v["tiles"].get(b):
                k = DA._key(a, b)
                out[k] = v["contact"].get(k, 0) >= 3 or bool(v["door"].get(k))
    return out


def adj_model():
    """{pair: P(adj) over families} from the corpus cache."""
    res = CC.measure_all(DA.STUDY, DA.measure, version=DA.VERSION)
    return {k: p["p_adj"] for k, p in DA.analyse(res)["pairs"].items()}


def flat_adj(v, P):
    if not v:
        return {}
    d = {"radial." + g: x for g, x in v["radial"].items() if g in DA.DEPTS + DA.OPEN}
    t = touching(v)
    ll = []
    for k, on in t.items():
        p = min(0.98, max(0.02, P.get(k, 0.16)))
        ll.append(math.log(p) if on else math.log(1 - p))
    if ll:
        d["adj.loglik"] = sum(ll) / len(ll)
    for k, on in t.items():
        d["pair." + k] = 1.0 if on else 0.0
    return d


def features(sm, P):
    f = {}
    f.update(flat_skeleton(SK.measure(sm)))
    f.update(flat_shares(DS.measure(sm)))
    f.update(flat_adj(DA.measure(sm), P))
    f.update(flat_space(SP.measure(sm)))
    return f


def corpus_features(P):
    """{map: features} for every human map, from the four studies' caches."""
    sk = CC.measure_all(SK.STUDY, SK.measure, version=SK.VERSION)
    ds = CC.measure_all(DS.STUDY, DS.measure, version=DS.VERSION)
    da = CC.measure_all(DA.STUDY, DA.measure, version=DA.VERSION)
    sp = CC.measure_all(SP.STUDY, SP.measure, version=SP.VERSION)
    out = {}
    for n, _ in CC.maps():
        f = {}
        f.update(flat_skeleton(sk.get(n)))
        f.update(flat_shares(ds.get(n)))
        f.update(flat_adj(da.get(n), P))
        f.update(flat_space(sp.get(n)))
        if sk.get(n) and sk[n].get("type"):
            f["_type"] = SK.classify(sk[n])
        out[n] = f
    return out


# ------------------------------------------------------------------------------------------------ bands
_BANDS = None


def trimmed(per_map, k):
    """(lo, hi) over family values with int(0.1 n) families dropped at each end: at least 80% of families inside
    (an interpolated p10..p90 leaves only 75% of 32 inside)."""
    vs = sorted(CC.family_values(per_map, lambda f: f.get(k)).values())
    if not vs:
        return None, None
    t = int(0.1 * len(vs))
    return vs[t], vs[len(vs) - 1 - t]


def bands():
    """(band {key: (lo, hi, trim_lo, trim_hi, look_lo, look_hi)}, pair rules {pair: 'must'|'never'}, P, corpus features)."""
    global _BANDS
    if _BANDS is not None:
        return _BANDS
    P = adj_model()
    cf = corpus_features(P)
    tagged = {n: f for n, f in cf.items() if f.get("_type") != "untagged"}
    keys = sorted({k for f in cf.values() for k in f if not k.startswith(("pair.", "_"))})
    band = {}
    for k in keys:
        src = tagged if k.startswith("skel.") else cf
        lo, hi = trimmed(src, k)
        lv = [cf[n].get(k) for n in LOOK if cf.get(n, {}).get(k) is not None]
        if lo is None:
            continue
        llo, lhi = (min(lv), max(lv)) if lv else (lo, hi)
        band[k] = (min(lo, llo), max(hi, lhi), lo, hi, llo, lhi)
    rules = {}
    for k, p in P.items():
        a, b = k.split("|")
        if a not in DA.DEPTS or b not in DA.DEPTS:
            continue
        look = [cf[n].get("pair." + k) for n in LOOK]
        if p >= MUST_P and all(x == 1.0 for x in look):
            rules[k] = "must"
        elif p <= NEVER_P and all(x in (0.0, None) for x in look):
            rules[k] = "never"
    _BANDS = (band, rules, P, cf)
    return _BANDS


def _dist(v, lo, hi):
    span = max(hi - lo, 1e-6)
    return max(0.0, (lo - v) / span, (v - hi) / span)


# ------------------------------------------------------------------------------------------------ checks
def band_checks(f, stage="full"):
    band, rules, P, _ = bands()
    out = []
    for k, (lo, hi, p10, p90, llo, lhi) in sorted(band.items()):
        if stage == "blocks" and not k.startswith(BLOCK_PREFIX):
            continue
        v = f.get(k)
        if v is None:
            continue
        out.append(dict(kind="band", name=k, ok=lo - 1e-9 <= v <= hi + 1e-9, value=v, dist=_dist(v, lo, hi),
                        detail="%s (band %s..%s; corpus 80%% %s..%s, look %s..%s)" % (
                            CC.fmt(v), CC.fmt(lo), CC.fmt(hi), CC.fmt(p10), CC.fmt(p90), CC.fmt(llo), CC.fmt(lhi))))
    for k, rule in sorted(rules.items()):
        v = f.get("pair." + k)
        if v is None:
            continue
        ok = v == 1.0 if rule == "must" else v == 0.0
        out.append(dict(kind="pair", name="%s %s" % ("must touch" if rule == "must" else "never touch", k), ok=ok,
                        value=v, dist=0.0 if ok else 1.0, detail="P(adj) %.2f over families" % P[k]))
    return out


def core_types():
    """Area types on half the families or more (studies/stamp_supply.py): a station should have them."""
    import stamp_supply
    res = CC.measure_all(stamp_supply.STUDY, stamp_supply.measure, version=stamp_supply.VERSION)
    T = stamp_supply.analyse(res)["types"]
    nfam = len(set(f for _, f in CC.maps()))
    return {a for a, t in T.items() if t["families"] >= nfam / 2.0}


_LOOK_HARD = None


def _look_hard():
    """The look maps' values for the stock-bounded hard checks (cached for the process)."""
    global _LOOK_HARD
    if _LOOK_HARD is None:
        _LOOK_HARD = {n: hard_values(parse.load(n)) for n in LOOK}
    return _LOOK_HARD


def hard_values(sm):
    import v6_gate
    from forge import size_budget
    core = core_types()
    have = {r.area for r in RS.rooms(sm)} | set(sm.area.values())
    missing = sorted(a for a in core if not any(h == a or h.startswith(a + "/") for h in have))
    over = 0
    for rm in RS.rooms(sm):
        kind = RS.type_of(rm.area)
        if not kind:
            continue
        sizes = [p.stats["tiles"] for p in RS.peers(kind)]
        if len(sizes) >= 3 and rm.stats["tiles"] > max(sizes):
            over += 1
    wide = size_budget.width_shares(sm)["wide"]
    walk = {name: (ok, detail) for name, ok, detail in v6_gate.walk_checks(sm)}
    return dict(missing=missing, oversized=over, wall_mass=v6_gate.wall_mass(sm), wide=wide, walk=walk)


_MACRO = None


def macro_types():
    """Pipe types the HELPER macros in code/modules/atmospherics/machinery/pipes/mapping.dm declare (forge/typeindex
    reads literal declarations only): <kind>/<colour>[/visible|/hidden][/layer1|/layer3]."""
    global _MACRO
    if _MACRO is None:
        import re
        _MACRO = set()
        src = open(os.path.join(ROOT, "code", "modules", "atmospherics", "machinery", "pipes", "mapping.dm")).read()
        for colour in re.findall(r"^HELPER(?:_NAMED)?\((\w+),", src, re.M):
            for kind in ("simple", "manifold", "manifold4w"):
                base = "/obj/machinery/atmospherics/pipe/%s/%s" % (kind, colour)
                _MACRO.add(base)
                for vis in ("visible", "hidden"):
                    _MACRO.update((base + "/" + vis, base + "/" + vis + "/layer1", base + "/" + vis + "/layer3"))
    return _MACRO


def known(path):
    from forge import typeindex
    return typeindex.known(path) or path in macro_types()


def hard_checks(sm, path=None, gen=True):
    hv = hard_values(sm)
    look = _look_hard()
    mx = lambda k: max(len(v[k]) if isinstance(v[k], list) else v[k] for v in look.values())  # noqa: E731
    out = []
    out.append(dict(kind="hard", name="core room types", ok=len(hv["missing"]) <= mx("missing"),
                    value=len(hv["missing"]), detail="%d core types missing (look max %d)%s" % (
                        len(hv["missing"]), mx("missing"), (": " + ", ".join(hv["missing"][:6])) if hv["missing"] else "")))
    out.append(dict(kind="hard", name="oversized rooms", ok=hv["oversized"] <= mx("oversized"), value=hv["oversized"],
                    detail="%d rooms bigger than every look-map room of their type (look max %d)" % (
                        hv["oversized"], mx("oversized"))))
    out.append(dict(kind="hard", name="solid wall filler", ok=hv["wall_mass"] <= mx("wall_mass"), value=hv["wall_mass"],
                    detail="%d 3x3 solid wall tiles (look max %d)" % (hv["wall_mass"], mx("wall_mass"))))
    out.append(dict(kind="hard", name="halls 7+ wide", ok=hv["wide"] <= mx("wide") + 1e-9, value=round(hv["wide"], 3),
                    detail="%.3f of hall floor (look max %.3f)" % (hv["wide"], mx("wide"))))
    for name, (ok, detail) in hv["walk"].items():
        kind = "ruled" if name in RULED else "hard"
        if name == "corridors clear":   # v6's check compares with the v6 accepted build: per-seed ratchet here
            continue
        out.append(dict(kind=kind, name=name, ok=ok, value=None, detail=detail))
    if gen and path:
        from forge import dmm
        m = dmm.read(path)
        unknown = sorted({o.path for t in m.tiles.values() for o in t.objs if not known(o.path)} |
                         {t.tpath for t in m.tiles.values() if t.tpath and not known(t.tpath)} |
                         {t.apath for t in m.tiles.values() if t.apath and not known(t.apath)})
        out.append(dict(kind="hard", name="known paths", ok=not unknown, value=len(unknown),
                        detail="%d paths this codebase doesn't declare%s" % (
                            len(unknown), (": " + ", ".join(unknown[:4])) if unknown else "")))
    return out


def run(path, stage="full", name=None, accept=False, quiet=False):
    band, rules, P, _ = bands()
    sm = parse.load(path)
    checks = band_checks(features(sm, P), stage)
    if stage == "full":
        checks += hard_checks(sm, path)
    if name:
        bp = os.path.join(BASE_DIR, name + ".json")
        base = json.load(open(bp)) if os.path.exists(bp) else None
        if base:
            worse = [c["name"] for c in checks if c.get("dist") is not None
                     and c["dist"] > base.get(c["name"], 0.0) + 1e-6]
            checks.append(dict(kind="ratchet", name="nothing regressed", ok=not worse, value=len(worse),
                               detail="%d checks further out than the accepted build%s" % (
                                   len(worse), (": " + ", ".join(worse[:6])) if worse else "")))
        if accept:
            os.makedirs(BASE_DIR, exist_ok=True)
            json.dump({c["name"]: c["dist"] for c in checks if c.get("dist") is not None}, open(bp, "w"), indent=1)
    fails = [c for c in checks if not c["ok"]]
    if not quiet:
        for c in checks:
            print("gate: %s  %-6s %-30s %s" % ("PASS" if c["ok"] else "FAIL", c["kind"], c["name"], c["detail"]))
        print("gate: %s (%d of %d checks failed; stage %s)" % ("FAIL" if fails else "PASS", len(fails), len(checks),
                                                               stage))
    return checks


# ------------------------------------------------------------------------------------------------ calibration
def calibrate(hard=True):
    band, rules, P, cf = bands()
    fam = dict(CC.maps())
    nfam = len(set(fam.values()))
    per = {}           # check name -> {map: ok}
    kinds = {}
    for n, f in cf.items():
        for c in band_checks(f):
            if c["name"].startswith("skel.") and f.get("_type") == "untagged":
                continue   # the halls aren't tagged as halls (Nebula): left out of the skeleton bands too
            per.setdefault(c["name"], {})[n] = c["ok"]
            kinds[c["name"]] = c["kind"]
    if hard:
        for n in LOOK:
            for c in hard_checks(parse.load(n), gen=False):
                per.setdefault(c["name"], {})[n] = c["ok"]
                kinds[c["name"]] = c["kind"]
    lines, bad = [], []
    for k in sorted(per, key=lambda k: (kinds[k], k)):
        res = per[k]
        famok = {}
        for n, ok in res.items():
            famok.setdefault(fam.get(n, n), []).append(ok)
        fr = sum(1 for v in famok.values() if sum(v) * 2 >= len(v)) / float(len(famok))
        lf = [n for n in LOOK if res.get(n) is False]
        rate_ok = kinds[k] not in ("band",) or fr >= 0.8 - 1e-9 or len(famok) < nfam / 2
        look_ok = not lf or kinds[k] == "ruled"
        if not (rate_ok and look_ok):
            bad.append(k)
        lines.append("%s %-6s %-34s families pass %3.0f%% (%d)  look fails: %s" % (
            "ok " if rate_ok and look_ok else "BAD", kinds[k], k[:34], 100 * fr, len(famok),
            ", ".join(RS.SHORT.get(n, n) for n in lf) or "-"))
    return lines, bad


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("map", nargs="?")
    ap.add_argument("--stage", default="full", choices=("blocks", "full"))
    ap.add_argument("--name")
    ap.add_argument("--accept", action="store_true")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--bands", action="store_true")
    a = ap.parse_args(argv)
    if a.bands:
        band, rules, P, _ = bands()
        for k, b in sorted(band.items()):
            print("%-30s %9s .. %9s   (p10..p90 %s..%s, look %s..%s)" % ((k,) + tuple(CC.fmt(x) for x in b)))
        for k, r in sorted(rules.items()):
            print("%-30s %s (P %.2f)" % (k, r, P[k]))
        return 0
    if a.calibrate:
        lines, bad = calibrate()
        print("\n".join(lines))
        print("calibration: %s (%d of %d checks fail the M0 test)" % ("PASS" if not bad else "FAIL", len(bad),
                                                                      len(lines)))
        os.makedirs(CC.OUT, exist_ok=True)
        open(os.path.join(CC.OUT, "gate_calibration.txt"), "w").write("\n".join(lines) + "\n")
        return 1 if bad else 0
    if not a.map:
        ap.error("a map, --calibrate or --bands")
    checks = run(a.map, a.stage, a.name, a.accept)
    return 1 if any(not c["ok"] for c in checks) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
