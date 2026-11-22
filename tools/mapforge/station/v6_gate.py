"""The v6 build's gate: v6_station.py runs it on every build and exits non-zero when a check fails, so a map worse
than the stock maps (or worse than the last accepted build) never passes as done (the user, 2026-11-22: "shouldn't
the lints ensure no generation generates poor maps to begin with").

    python tools/mapforge/station/v6_gate.py data/mapforge/station_v6.dmm [--accept]

Two kinds of check:
  stock    against Meta, Delta, Omega and Hippie (forge/size_budget.py, style_bands.py, disc_rooms.py):
             - every department's share of the station floor inside the stock min..max
             - hall floor 7+ tiles wide no more than the most any stock map has
             - no room bigger than every stock room of its type (size_budget "oversized")
             - no room type 3+ stock maps have missing (bar the two that need space outside the hull)
             - no room the discriminator calls generated on average (mean tile logit above 0)
             - no solid wall filler beyond the stock max (3x3 blocks of plain wall)
             - how it walks (forge/walk.py): every solar array reached from the halls, no more unreached floor than
               stock, no room reached only through maint unless a stock map has that room so, dead-end corridors
               and open maint fields within the stock max, the disposals outlet near the atmos waste outlet
             - atmos faults (forge/atmos.py: open ends, scrubbers piped into another loop) no more than accepted
  ratchet  never worse than the accepted baseline (data/mapforge/gate_v6.json), for numbers the stock maps don't
           bound but the rulings do: wall pieces stacked, on both faces of a wall, over furniture (piece_audit);
           rooms below the stock band in furniture, items and wall pieces (style_bands). --accept writes the
           current numbers as the new baseline (only when the user has looked at a build).

Prints one line per check, PASS or FAIL with the numbers, and returns the failures.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, room_stats as RS, size_budget, style_bands  # noqa: E402

ROOT = parse.ROOT
BASELINE = os.path.join(ROOT, "data", "mapforge", "gate_v6.json")
OUTSIDE = ("/area/construction/mining/aux_base", "/area/science/test_area")
SKIP_GROUPS = ("shuttle", "solar", None)


def wall_mass(sm):
    """Solid wall filler: station wall tiles whose whole 3x3 block is wall (not glass, not mineral rock). The user
    (2026-11-22, a repeated ruling): "you filled in space with a shit ton of walls". Stock: Meta 8, Delta 0, Hippie
    12, Omega 23 (its 382 tiles of labour-camp rock left out)."""
    W = {p for p, c in sm.cls.items() if c == "W" and p not in sm.glass
         and not (sm.m.tiles[(p[0], p[1], sm.z)].tpath or "").startswith("/turf/closed/mineral")}
    return sum(1 for p in W if all((p[0] + dx, p[1] + dy) in W for dx in (-1, 0, 1) for dy in (-1, 0, 1)))


def wall_mass_stock():
    return max(wall_mass(parse.load(n)) for n in RS.REFS)


def left_out(path):
    """Vents and scrubbers the build's air pass left out because no pipe reached them (v6_station.py writes them to
    <name>.air.json beside the map), as ["supply 102,37", ...]; None when there is no record."""
    side = path[:-4] + ".air.json"
    if not os.path.exists(side):
        return None
    return ["%s %d,%d" % (cls, v[0], v[1]) for cls, vs in sorted(json.load(open(side)).items()) for v in vs]


def atmos_faults(path):
    """forge/atmos.py's faults over the whole station level: open pipe ends, a unary device on nothing, the station
    scrubbers plain-piped into another loop."""
    from forge import atmos, dmm
    m = dmm.read(path)
    return atmos.check(m, [(x, y) for (x, y, z) in m.tiles if z == 1])


# how the map walks (forge/walk.py), each bound by the stock maps; the user, 2026-11-22, after a solar corridor that
# met maint corner to corner, maint fields "huge empty, pointless", atmos with "no primary way in except via maint" and
# the disposals outlet gone: "make sure none of these happen again"
def walk_checks(sm):
    """[(name, ok, detail)]."""
    from forge import walk
    r, st = walk.measure(sm), walk.stock()
    mx = lambda k: max(v[k] for v in st.values())  # noqa: E731
    allowed = {a for v in st.values() for a in v["maint_only"]}
    out = []
    un = [p for p in walk.reach(sm)[0] if "/solar" in sm.area.get(p, "")]
    out.append(("solars reached", not un, "%d solar tiles cut off from the halls (stock 0)%s" % (
        len(un), (" e.g. %d,%d" % un[0]) if un else "")))
    out.append(("floor reached", r["unreached"] <= mx("unreached"), "%d station floor tiles no walk reaches "
                "(stock max %d)" % (r["unreached"], mx("unreached"))))
    bad = sorted(a for a in r["maint_only"] if a not in allowed and "abandoned" not in a)
    out.append(("ways in", not bad, ("reached only through maint: " + ", ".join(
        "%s %d" % (a, r["maint_only"][a]) for a in bad)) if bad else "every room maint-only on v6 is so on a stock map"))
    out.append(("dead ends", r["stubs_per_k"] <= mx("stubs_per_k") and r["stub_max"] <= mx("stub_max"),
                "%.2f per 1k corridor tiles, longest %d (stock max %.2f, %d)%s" % (
                    r["stubs_per_k"], r["stub_max"], mx("stubs_per_k"), mx("stub_max"),
                    "".join(" %d,%d len %d;" % (t[0][0], t[0][1], t[1]) for t in r["stub_tips"][:3]))))
    # furniture across a corridor: the stock maps block maint pockets with junk (Hippie 112 tiles, Meta 43), the user
    # rules it out (2026-11-22, a vending machine across the way to the SW solars): never more than accepted
    bl, bl_acc = walk.blocked(sm), len(walk.blocked(parse.load(ACCEPTED)))
    out.append(("corridors clear", len(bl) <= bl_acc, "%d maint/hall tiles cut off by furniture (accepted %d)%s" % (
        len(bl), bl_acc, (" e.g. %d,%d" % bl[0]) if bl else "")))
    vt = sorted((x, y) for (x, y, z), t in sm.m.tiles.items() if z == sm.z and t.has("/obj/machinery/power/terminal")
                and any("vent_pump" in o.path or "vent_scrubber" in o.path for o in t.objs))
    out.append(("vents off terminals", not vt, "%d vents or scrubbers on a power terminal (the user's ruling: 0)%s" % (
        len(vt), (" e.g. %d,%d" % vt[0]) if vt else "")))
    # vents and scrubbers: never two on one tile, never two of a kind side by side outside the supermatter (the
    # user 2026-11-22: "2 vents stacked on top of each other ... that's just not how stock maps work"; stock: 2-4
    # vent pairs and 2 scrubber pairs a map, 10-12 vent-scrubber pairs, none on one tile)
    kind = {}
    for (x, y, z), t in sm.m.tiles.items():
        if z == sm.z and not t.apath.startswith("/area/engine/supermatter"):
            for o in t.objs:
                if "vent_pump" in o.path or "vent_scrubber" in o.path:
                    kind.setdefault((x, y), []).append("V" if "vent_pump" in o.path else "S")
    stacked = sorted(p for p, k in kind.items() if len(k) > 1)
    twins = sorted(p for p, k in kind.items() for dx, dy in ((1, 0), (0, 1))
                   if kind.get((p[0] + dx, p[1] + dy), [""])[0] == k[0])
    out.append(("vents apart", not stacked and not twins, "%d tiles with two, %d same-kind pairs side by side outside "
                "the supermatter%s" % (len(stacked), len(twins), (" e.g. %d,%d" % (stacked + twins)[0]) if stacked or twins else "")))
    # an APC's areastring must name an area on this map (copied Hippie rooms brought "Mime's Office APC" with
    # /area/hippie/mime, an area this map doesn't have: a roundstart stack trace the boot's runtime count didn't show,
    # 2026-11-22)
    on_map = {t.apath for (x, y, z), t in sm.m.tiles.items() if z == sm.z}
    bad_apc = sorted((x, y) for (x, y, z), t in sm.m.tiles.items() if z == sm.z for o in t.objs
                     if o.path.startswith("/obj/machinery/power/apc") and o.get("areastring")
                     and o.get("areastring").strip('"') not in on_map)
    out.append(("apc areas", not bad_apc, "%d APCs naming an area not on the map%s" % (
        len(bad_apc), (" e.g. %d,%d" % bad_apc[0]) if bad_apc else "")))
    # a visible pipe line that runs into a pipe hidden under the floor seems to stop dead (the user 2026-11-22: "the
    # sudden hidden pipes look weird, make sure that's not a pattern"; stock maps have 14-21, the ruling is none)
    from forge import atmos as _atmos
    hb = _atmos.hidden_breaks(sm.m, sm.z)
    out.append(("pipes stay seen", not hb, "%d visible lines running into a pipe hidden under the floor%s" % (
        len(hb), (" e.g. %d,%d" % hb[0][1]) if hb else "")))
    cg = walk.corner_gaps(sm)
    out.append(("hull corners", not cg, "%d walls meeting corner to corner round station floor (stock 0)%s" % (
        len(cg), (" e.g. %d,%d" % cg[0]) if cg else "")))
    out.append(("open maint", r["open_maint"] <= mx("open_maint"), "%.3f of the maint floor in open 3x3 fields "
                "(stock max %.3f)" % (r["open_maint"], mx("open_maint"))))
    out.append(("disposals outlet", r["outlet_gap"] <= mx("outlet_gap"), "%s tiles from the atmos waste outlet "
                "(stock max %d)" % (r["outlet_gap"] if r["outlets"] else "no outlet:", mx("outlet_gap"))))
    return out


def measure(path):
    sys.path.insert(0, os.path.join(HERE, "..", "studies"))
    import piece_audit
    import io
    import contextlib
    out = {}
    plan = size_budget.plan(path)
    out["groups"] = plan["groups"]
    out["wide"] = plan["halls"]["map"]["wide"]
    out["wide_stock"] = max(v["wide"] for v in plan["halls"]["stock"].values())
    out["oversized"] = [(r["area"], r["tiles"], r["stock"]) for r in plan["oversized"]]
    out["missing"] = [r["area"] for r in plan["missing"] if r["area"] not in OUTSIDE]
    with contextlib.redirect_stdout(io.StringIO()):
        out["pieces"] = piece_audit.audit(path, False)
    sm = parse.load(path)
    out["wall_mass"], out["wall_mass_stock"] = wall_mass(sm), wall_mass_stock()
    out["walk"] = walk_checks(sm)
    out["atmos"], out["atmos_accepted"] = atmos_faults(path), len(atmos_faults(ACCEPTED))
    out["left_out"] = left_out(path)
    below = {"furn": 0, "items": 0, "pieces": 0}
    n = 0
    for rm in RS.rooms(sm):
        r = style_bands.lint(rm)
        if not r or r["n"] < style_bands.MIN_PEERS:
            continue
        n += 1
        for k in below:
            if r["out"].get(k, ("",))[0] == "low":
                below[k] += 1
    out["below"] = {k: round(v / float(max(1, n)), 3) for k, v in below.items()}
    try:
        from forge import disc_rooms
        L, mask, held = disc_rooms.logits(disc_rooms.RUN, path)
        worst = []
        for kind, area, ts, box in disc_rooms.places(sm):
            vs = [L[y - 1, x - 1] for x, y in ts if mask[y - 1, x - 1] > 0]
            if vs and kind == "room" and sum(vs) / len(vs) > 0:
                worst.append((area, round(float(sum(vs) / len(vs)), 2)))
        out["disc"] = dict(held=held, generated_rooms=worst)
    except Exception as e:          # no torch or no run: the check is skipped, and says so
        out["disc"] = dict(error=str(e)[:200])
    return out


# ------------------------------------------------------------------------------------------- full regression
# The user, 2026-11-22: "leave nothing regressed". Every measurement, per room, against the accepted build: a number
# may not move further outside its stock band than it was, a new room must sit inside its band, every maint pocket
# must be as full as stock ones are, and no fingerprint feature may move further outside the human range.
ACCEPTED = os.path.join(ROOT, "data", "mapforge", "station_v6_accepted.dmm")
FP_RANGES = os.path.join(ROOT, "data", "mapforge", "gate_fp_ranges.json")
NEW_ROOM_STATS = ("tiles", "furn", "items", "pieces", "doors")
EPS = 1e-6


def _dist(v, lo, hi):
    span = max(hi - lo, 1e-6)
    return max(0.0, (lo - v) / span, (v - hi) / span)


def _fp_ranges():
    from forge import fingerprint as FP
    if os.path.exists(FP_RANGES):
        return json.load(open(FP_RANGES))
    res = FP.run(list(FP.HUMAN))
    _, rng, _ = FP.table(dict(res, **{"_": dict(f={k: float("nan") for k, _, _ in FP.FEATURES}, human=False)}))
    out = {k: [v[0], v[2]] for k, v in rng.items() if k not in FP.RULED}
    json.dump(out, open(FP_RANGES, "w"), indent=1)
    return out


def full_measure(path):
    from forge import fingerprint as FP
    sm = parse.load(path)
    rooms = {}
    for rm in RS.rooms(sm):
        kind = RS.type_of(rm.area)
        peers = RS.peers(kind) if kind else []
        if len(peers) < 3:
            continue
        band = {k: (min(p.stats[k] for p in peers), max(p.stats[k] for p in peers)) for k in RS.STATS}
        rooms[rm.area] = {k: _dist(rm.stats[k], *band[k]) for k in RS.STATS}
    lo_fill, big = size_budget.stock_pocket_band()
    pockets = [(n, f, box, area) for n, f, box, area, _ in size_budget.maint_pockets(sm) if f < lo_fill or n > big]
    f, _, _ = FP.measure(sm)
    rng = _fp_ranges()
    # struct3_js and furn3_js are measured against the pooled human maps (fingerprint.run, ~3 min): not here
    fp = {k: _dist(f[k], lo, hi) for k, (lo, hi) in rng.items() if k in f and f[k] == f[k]}
    return dict(rooms=rooms, pockets=pockets, fp=fp, lo_fill=lo_fill, big=big)


def _base():
    """full_measure of the accepted build, cached beside it."""
    cache = ACCEPTED + ".gate.json"
    if os.path.exists(cache) and os.path.getmtime(cache) > os.path.getmtime(ACCEPTED):
        return json.load(open(cache))
    base = full_measure(ACCEPTED)
    json.dump(base, open(cache, "w"))
    return base


def summary(path):
    """[(name, ok, value)] of the whole-map checks that need no discriminator (station/v6_ablate.py)."""
    sys.path.insert(0, os.path.join(HERE, "..", "studies"))
    import piece_audit
    import io
    import contextlib
    plan = size_budget.plan(path)
    base = json.load(open(BASELINE)) if os.path.exists(BASELINE) else None
    out = []
    for g, v in sorted(plan["groups"].items()):
        if g not in SKIP_GROUPS:
            out.append(("share " + g, v["stock_min"] <= v["share"] <= v["stock_max"], round(v["share"], 3)))
    wide, wide_stock = plan["halls"]["map"]["wide"], max(v["wide"] for v in plan["halls"]["stock"].values())
    out.append(("halls 7+ wide", wide <= wide_stock, round(wide, 3)))
    out.append(("oversized rooms", not plan["oversized"], len(plan["oversized"])))
    wm = wall_mass(parse.load(path))
    out.append(("solid wall filler", wm <= wall_mass_stock(), wm))
    for name, ok, detail in walk_checks(parse.load(path)):
        out.append((name, ok, detail.split(" (")[0][:40]))
    out.append(("atmos faults", len(atmos_faults(path)) <= len(atmos_faults(ACCEPTED)), len(atmos_faults(path))))
    lo = left_out(path)
    out.append(("vents all piped", lo is not None and not lo, len(lo) if lo is not None else "no record"))
    with contextlib.redirect_stdout(io.StringIO()):
        pc = piece_audit.audit(path, False)
    for k in ("stacked", "both", "over"):
        out.append(("pieces " + k, base is None or pc[k] <= base["pieces"][k], pc[k]))
    return out


def full_check(path):
    """[(name, detail)] of every regression against the accepted build."""
    base = _base()
    cur = full_measure(path)
    out = []
    for area, st in sorted(cur["rooms"].items()):
        b = base["rooms"].get(area)
        if b is None:
            bad = ["%s %.2f" % (k, st[k]) for k in NEW_ROOM_STATS if st[k] > EPS]
            if bad:
                out.append(("new room outside its stock band", "%s: %s" % (area, ", ".join(bad))))
            continue
        bad = ["%s %.2f->%.2f" % (k, b[k], st[k]) for k in RS.STATS if st[k] > b[k] + EPS]
        if bad:
            out.append(("room further from stock", "%s: %s" % (area, ", ".join(bad))))
    for n, f, box, area in cur["pockets"]:
        out.append(("maint pocket empty or huge", "%d tiles, furniture %.2f/tile (stock min %.2f, max %d tiles) at %d,%d-%d,%d" % (
            (n, f, cur["lo_fill"], cur["big"]) + tuple(box))))
    for k, v in sorted(cur["fp"].items()):
        if v > base["fp"].get(k, 0.0) + 0.02:
            out.append(("fingerprint feature further from human", "%s %.2f->%.2f" % (k, base["fp"].get(k, 0.0), v)))
    return out


def check(path, accept=False):
    cur = measure(path)
    base = json.load(open(BASELINE)) if os.path.exists(BASELINE) else None
    fails, lines = [], []

    def res(ok, name, detail):
        lines.append("%s  %-22s %s" % ("PASS" if ok else "FAIL", name, detail))
        if not ok:
            fails.append(name)
    for g, v in sorted(cur["groups"].items()):
        if g in SKIP_GROUPS:
            continue
        ok = v["stock_min"] <= v["share"] <= v["stock_max"]
        res(ok, "share " + g, "%.1f%% (stock %.1f..%.1f)" % (100 * v["share"], 100 * v["stock_min"], 100 * v["stock_max"]))
    res(cur["wide"] <= cur["wide_stock"], "halls 7+ wide", "%.0f%% (stock max %.0f%%)" % (100 * cur["wide"], 100 * cur["wide_stock"]))
    res(cur["wall_mass"] <= cur["wall_mass_stock"], "solid wall filler",
        "%d tiles of 3x3 solid wall (stock max %d)" % (cur["wall_mass"], cur["wall_mass_stock"]))
    for name, ok, detail in cur["walk"]:
        res(ok, name, detail)
    lo = cur["left_out"]
    res(lo is not None and not lo, "vents all piped", "no build record (<name>.air.json)" if lo is None else
        "%d vents or scrubbers the air pass had to leave out%s" % (len(lo), (" e.g. %s" % lo[0]) if lo else ""))
    res(len(cur["atmos"]) <= cur["atmos_accepted"], "atmos faults", "%d (accepted %d)%s" % (
        len(cur["atmos"]), cur["atmos_accepted"], "".join("; " + p for p in cur["atmos"][:4])))
    res(not cur["oversized"], "oversized rooms", "; ".join("%s %d (stock %s)" % o for o in cur["oversized"]) or "none")
    res(not cur["missing"], "missing room types", ", ".join(cur["missing"]) or "none")
    d = cur["disc"]
    if "error" in d:
        lines.append("SKIP  %-22s %s" % ("discriminator", d["error"]))
    else:
        res(not d["generated_rooms"], "rooms read generated", (", ".join("%s %+.2f" % r for r in d["generated_rooms"]) or "none")
            + ("" if d["held"] else " (map SEEN in training: the verdict is not independent)"))
    for k in ("stacked", "both", "over"):
        b = base["pieces"][k] if base else None
        res(b is None or cur["pieces"][k] <= b, "pieces " + k, "%d (baseline %s)" % (cur["pieces"][k], b))
    for k in ("furn", "items", "pieces"):
        b = base["below"][k] if base else None
        res(b is None or cur["below"][k] <= b + 1e-9, "rooms low on " + k,
            "%.0f%% below the stock band (baseline %s)" % (100 * cur["below"][k], "%.0f%%" % (100 * b) if b is not None else "none"))
    regs = full_check(path)
    res(not regs, "nothing regressed", "%d regressions against the accepted build" % len(regs))
    for name, detail in regs:
        lines.append("      %s: %s" % (name, detail))
    for ln in lines:
        print("gate: " + ln)
    print("gate: %s (%d of %d checks failed)" % ("FAIL" if fails else "PASS", len(fails), len(lines)))
    if accept:
        json.dump(dict(pieces=cur["pieces"], below=cur["below"]), open(BASELINE, "w"), indent=1)
        print("gate: baseline written to %s" % os.path.relpath(BASELINE, ROOT))
    return fails


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("map", nargs="?", default=os.path.join(ROOT, "data", "mapforge", "station_v6.dmm"))
    ap.add_argument("--accept", action="store_true")
    a = ap.parse_args()
    sys.exit(1 if check(a.map, a.accept) else 0)
