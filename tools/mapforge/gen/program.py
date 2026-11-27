"""Stage S0, the program: seed + crew -> station floor, shape, per-department floor budgets and skeleton draws, all
from the corpus studies (data/mapforge/gen_targets/*_targets.json; run the studies first).

    python tools/mapforge/gen/program.py --crew 80 --seed 1

floor     228 * crew^0.81 (studies/dept_scaling.py), times exp(0.6 z s) with s the corpus' residual spread in log
          floor and z one normal draw per seed (the same at every crew, so a seed's station grows with crew), held inside the corpus floor-per-crew band (64..139 tiles a job slot).
budgets   each group's fit tiles = a * floor^b at that floor, scaled so they sum to the floor, each share then held
          inside the gate's band (gen/gate.py) with a margin of 12% of the band.
draws     spokes, core share, hall width: drawn from the hub maps of the corpus (one value per map, so the seed
          picks a real station's number, not a mean).
"""
import argparse
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "studies"))
sys.path.insert(0, HERE)
import corpus_common as CC  # noqa: E402

GROUPS = ("command", "security", "medical", "science", "engineering", "atmos", "cargo", "service", "civic", "dorms",
          "ai", "hall", "arrivals", "escape", "maint")
DEPTS = ("command", "security", "medical", "science", "engineering", "atmos", "cargo", "service", "civic", "dorms",
         "ai")


def _load(study):
    p = os.path.join(CC.OUT, study + "_targets.json")
    if not os.path.exists(p):
        raise SystemExit("run studies/%s first (no %s)" % (study.replace("dept_", "dept_") + ".py", p))
    return json.load(open(p))


def rng_for(*parts):
    return random.Random("|".join(str(p) for p in parts))


def floor_residual():
    """Spread of log(floor) round the crew fit, over maps with 20+ job slots."""
    ds = _load("dept_scaling")
    a, b, _ = ds["station"]["floor_vs_crew"]
    cache = json.load(open(os.path.join(CC.OUT, "dept_scaling.json")))
    rs = []
    for k, v in cache.items():
        if k.startswith("_") or not v["v"] or v["v"]["crew"] < 20:
            continue
        rs.append(math.log(v["v"]["floor"]) - math.log(a * v["v"]["crew"] ** b))
    m = sum(rs) / len(rs)
    return (sum((r - m) ** 2 for r in rs) / len(rs)) ** 0.5


AI_SHARE = 0.034      # the AI satellite's least share of the floor (human look band 0.031-0.044)


def program(seed, crew, shape="hub"):
    r = rng_for("program", shape, crew, seed)
    ds = _load("dept_scaling")
    sk = _load("skeleton")
    a, b, _ = ds["station"]["floor_vs_crew"]
    lo, _, hi, _ = ds["station"]["floor_per_crew"]
    s = floor_residual()
    # the residual is drawn per seed, not per crew, so one seed grows with its crew dial
    z = max(-1.5, min(1.5, rng_for("floor", shape, seed).gauss(0, 1)))
    floor = a * crew ** b * math.exp(z * s * 0.6)
    floor = max(lo * crew, min(hi * crew, floor))
    raw = {}
    for g in GROUPS:
        f = ds["groups"][g]["tiles_vs_floor"]
        raw[g] = f[0] * floor ** f[1]
    tot = sum(raw.values())
    budgets = {g: raw[g] * floor / tot for g in GROUPS}
    # the fits are size-aware, the gate's share bands are not: keep every share inside its band (a margin in),
    # then spread the difference over the rest
    import gate
    band = gate.bands()[0]
    for _ in range(6):
        fixed = {}
        for g in GROUPS:
            b_ = band.get("share." + g)
            if not b_:
                continue
            lo, hi = b_[0], b_[1]
            sh = budgets[g] / floor
            m = 0.12 * (hi - lo)
            if sh < lo + m:
                fixed[g] = (lo + m) * floor
            elif sh > hi - m:
                fixed[g] = (hi - m) * floor
        if not fixed:
            break
        rest = [g for g in GROUPS if g not in fixed]
        left = floor - sum(fixed.values())
        rs = sum(budgets[g] for g in rest)
        for g in rest:
            budgets[g] = budgets[g] * left / rs
        budgets.update(fixed)
    # the AI satellite holds the AI's core, its upload and telecomms (the radio and the requests consoles' message
    # server): at least the human look band's share, taken from the rest (at 0.026 its block had no room for the
    # core, crew 100 seed 7, 2026-11-26)
    ai_min = AI_SHARE * floor
    if budgets["ai"] < ai_min:
        extra = ai_min - budgets["ai"]
        rest = [g for g in GROUPS if g != "ai"]
        rs = sum(budgets[g] for g in rest)
        for g in rest:
            budgets[g] -= extra * budgets[g] / rs
        budgets["ai"] = ai_min
    # spokes and core from the 8 hub maps nearest this floor (a small station has fewer, shorter spokes)
    hubs = sorted([v for v in sk["per_map"].values() if v["type"] == "hub"], key=lambda v: abs(v["floor"] - floor))[:8]
    # 4 for now (the hub median): with fewer, the slot layout queues blocks single file and spokes run past the
    # human 62-tile walk; a 2-spoke hub (Meta) puts departments on the bare loop sides, which it can't yet (M6)
    spokes = 4
    r.choice(hubs)
    core = r.choice([v["core"] for v in hubs if v["core"] >= 0.015] or [0.037])
    # what sits inside the core loop besides command (skeleton study: service 9 of 30 hub maps, AI 6)
    core_service = r.random() < 9 / 30.0
    return dict(seed=seed, crew=crew, shape=shape, floor=int(round(floor)), budgets=budgets, spokes=spokes,
                core=core, core_service=core_service, floor_resid=s)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--crew", type=int, default=80)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    p = program(a.seed, a.crew)
    print(json.dumps(dict(p, budgets={k: round(v) for k, v in p["budgets"].items()}), indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
