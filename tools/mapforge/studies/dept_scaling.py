"""How department size and share scale with crew, over every human map in parse.humans(). The generator reads
its floor budget per department from the fits this writes.

    python tools/mapforge/studies/dept_scaling.py                 # table, fits, data/mapforge/gen_targets/
    python tools/mapforge/studies/dept_scaling.py --map data/mapforge/station_v6.dmm   # a build against the fits
    python tools/mapforge/studies/dept_scaling.py --fresh

Per map:
  crew       roundstart job slots (corpus_common.crew: job start landmarks, no assistants, AI, cyborgs,
             prisoners, depsec copies or hangover spawns).
  floor      station floor tiles (parse.station_tiles: no space, shuttles, solars).
  tiles[g]   floor of each department group (studies/stations.py GROUPS), share[g] = tiles[g] / floor.
  rooms[g]   wall-bounded rooms of 4+ tiles in the group; room_med[g] their median size.
  jobs[g]    job slots whose job belongs to the group (JOB_GROUP); tiles_per_job[g] = tiles[g] / jobs[g].

Fits, over all maps (each map one point; families also checked one point each):
  floor = a * crew^b                 how the whole station grows with crew
  tiles[g] = a * floor^b             b ~ 1: the share stays the same at every size; b < 1: the department
                                     is a fixed kit that takes a smaller share of a bigger station
  share[g] vs crew, vs floor         Pearson r
  rooms[g] = a * tiles[g]^b          bigger departments: more rooms, or bigger rooms?
The report gives the share band (p10..median..p90 over families) and the fits with r^2.
"""
import argparse
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import corpus_common as CC  # noqa: E402

STUDY = "dept_scaling"
VERSION = 1
GROUPS = ("command", "security", "medical", "science", "engineering", "atmos", "cargo", "service", "civic", "dorms",
          "ai", "hall", "arrivals", "escape", "maint")
JOB_GROUP = {
    "captain": "command", "head_of_personnel": "command", "hop": "command",
    "head_of_security": "security", "hos": "security", "warden": "security", "detective": "security",
    "security_officer": "security", "lawyer": "security", "brig_physician": "security",
    "chief_medical_officer": "medical", "cmo": "medical", "medical_doctor": "medical", "doctor": "medical",
    "chemist": "medical", "geneticist": "medical", "virologist": "medical", "paramedic": "medical",
    "coroner": "medical", "psychiatrist": "medical", "mining_medic": "medical",
    "research_director": "science", "rd": "science", "scientist": "science", "roboticist": "science",
    "xenobiologist": "science",
    "chief_engineer": "engineering", "ce": "engineering", "station_engineer": "engineering", "engineer": "engineering",
    "atmospheric_technician": "atmos", "atmos": "atmos", "atmospheric": "atmos",
    "quartermaster": "cargo", "cargo_technician": "cargo", "shaft_miner": "cargo", "explorer": "cargo",
    "bitrunner": "cargo", "miner": "cargo",
    "bartender": "service", "cook": "service", "chef": "service", "botanist": "service", "janitor": "service",
    "clown": "service", "mime": "service", "chaplain": "civic", "curator": "civic", "librarian": "civic",
}


def _jobs(sm):
    c = Counter()
    for (x, y, z), t in sm.m.tiles.items():
        if z != sm.z:
            continue
        for a in t.objs:
            if a.path.startswith("/obj/effect/landmark/start/"):
                parts = a.path[len("/obj/effect/landmark/start/"):].split("/")
                if parts[0] in CC.NOT_CREW:
                    continue
                job = parts[-1]
                g = JOB_GROUP.get(job) or JOB_GROUP.get(parts[0])
                c[g or "other"] += 1
    return c


def measure(sm):
    st = sm.station_tiles()
    if not st:
        return None
    n = float(len(st))
    tiles = Counter(sm.group.get(p) for p in st)
    rooms, sizes = Counter(), {}
    for r in sm.rooms():
        rooms[r.group] += 1
        sizes.setdefault(r.group, []).append(len(r.tiles))
    jobs = _jobs(sm)
    return dict(
        crew=CC.crew(sm), floor=len(st),
        tiles={g: tiles[g] for g in tiles if g and not g.startswith("other")},
        other=sum(v for g, v in tiles.items() if g and g.startswith("other")) / n,
        share={g: round(tiles[g] / n, 4) for g in tiles if g and not g.startswith("other")},
        rooms=dict(rooms), room_med={g: CC.median(v) for g, v in sizes.items()},
        jobs=dict(jobs),
    )


def analyse(res):
    res = {k: v for k, v in res.items() if v and v["crew"] >= 20}
    out = dict(groups={}, station={})
    xs = [v["crew"] for v in res.values()]
    fl = [v["floor"] for v in res.values()]
    f = CC.fit_power(xs, fl)
    fc = CC.family_values(res, lambda v: v["crew"])
    ff = CC.family_values(res, lambda v: v["floor"])
    ffit = CC.fit_power([fc[k] for k in fc], [ff[k] for k in fc])
    out["station"] = dict(
        floor_vs_crew=f, floor_vs_crew_families=ffit, r_floor_crew=CC.pearson(xs, fl),
        floor_per_crew=CC.band(res, lambda v: v["floor"] / float(v["crew"])),
        floor=CC.band(res, lambda v: v["floor"]), crew=CC.band(res, lambda v: v["crew"]),
        rooms_per_1k=CC.band(res, lambda v: 1000.0 * sum(v["rooms"].get(g, 0) for g in GROUPS if g not in
                                                          ("hall", "arrivals", "escape", "maint")) / v["floor"]),
    )
    for g in GROUPS:
        have = {k: v for k, v in res.items() if v["tiles"].get(g)}
        if len(have) < 5:
            continue
        sh = CC.band(res, lambda v, g=g: v["share"].get(g, 0.0))
        tf = CC.fit_power([v["floor"] for v in have.values()], [v["tiles"][g] for v in have.values()])
        tc = CC.fit_power([v["crew"] for v in have.values()], [v["tiles"][g] for v in have.values()])
        rc = CC.pearson([v["crew"] for v in res.values()], [v["share"].get(g, 0.0) for v in res.values()])
        rf = CC.pearson([v["floor"] for v in res.values()], [v["share"].get(g, 0.0) for v in res.values()])
        rooms = CC.fit_power([v["tiles"][g] for v in have.values()], [v["rooms"].get(g, 0) for v in have.values()])
        jobs = {k: v for k, v in have.items() if v["jobs"].get(g)}
        tpj = CC.band(jobs, lambda v, g=g: v["tiles"][g] / float(v["jobs"][g])) if len(jobs) >= 5 else None
        jfit = CC.fit_power([v["jobs"][g] for v in jobs.values()], [v["tiles"][g] for v in jobs.values()]) \
            if len(jobs) >= 5 else None
        out["groups"][g] = dict(
            maps=len(have), share=sh, tiles=CC.band(have, lambda v, g=g: v["tiles"][g]),
            tiles_vs_floor=tf, tiles_vs_crew=tc, r_share_crew=rc, r_share_floor=rf, rooms_vs_tiles=rooms,
            rooms=CC.band(have, lambda v, g=g: v["rooms"].get(g, 0)),
            room_med=CC.band(have, lambda v, g=g: v["room_med"].get(g)),
            tiles_per_job=tpj, tiles_vs_jobs=jfit,
        )
    return out


def text(out, res):
    L = []
    s = out["station"]
    a, b, r2 = s["floor_vs_crew"] or (0, 0, 0)
    L.append("station: floor = %.0f * crew^%.2f (r2 %.2f, %d maps), families: %s; r(floor, crew) = %s" % (
        a, b, r2, len([v for v in res.values() if v and v["crew"] >= 20]),
        "floor = %.0f * crew^%.2f (r2 %.2f)" % s["floor_vs_crew_families"] if s["floor_vs_crew_families"] else "-",
        CC.fmt(s["r_floor_crew"], 2)))
    for k in ("floor", "crew", "floor_per_crew", "rooms_per_1k"):
        lo, med, hi, n = s[k]
        L.append("  %-15s %8s %8s %8s  (%d families)" % (k, CC.fmt(lo, 1), CC.fmt(med, 1), CC.fmt(hi, 1), n))
    L.append("")
    L.append("%-12s %5s  %-23s %-22s %-22s %6s %6s %-20s %-18s %-14s" % (
        "group", "maps", "share p10/med/p90", "tiles=a*floor^b (r2)", "tiles=a*crew^b (r2)", "r~crew", "r~flr",
        "rooms p10/med/p90", "room size med", "tiles/job med"))
    for g, d in out["groups"].items():
        def fit(f):
            return "%7.3f*x^%.2f (%.2f)" % f if f else "-"
        sh = d["share"]
        rm = d["rooms"]
        L.append("%-12s %5d  %.3f/%.3f/%.3f       %-22s %-22s %6s %6s %4s/%4s/%4s          %-18s %-14s" % (
            g, d["maps"], sh[0], sh[1], sh[2], fit(d["tiles_vs_floor"]), fit(d["tiles_vs_crew"]),
            CC.fmt(d["r_share_crew"], 2), CC.fmt(d["r_share_floor"], 2), CC.fmt(rm[0], 0), CC.fmt(rm[1], 0),
            CC.fmt(rm[2], 0), CC.fmt(d["room_med"][1], 0),
            CC.fmt(d["tiles_per_job"][1], 0) if d["tiles_per_job"] else "-"))
    return "\n".join(L)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--map")
    a = ap.parse_args(argv)
    res = CC.measure_all(STUDY, measure, fresh=a.fresh, version=VERSION)
    out = analyse(res)
    if a.map:
        v = CC.measure_one(a.map, measure)
        print("%s: crew %d floor %d" % (a.map, v["crew"], v["floor"]))
        for g, d in out["groups"].items():
            sh = v["share"].get(g, 0.0)
            fa = d["tiles_vs_floor"]
            want = fa[0] * v["floor"] ** fa[1] if fa else None
            lo, med, hi = d["share"][:3]
            print("  %-12s share %.3f  band %.3f..%.3f%s  tiles %5d  fit for this floor %s" % (
                g, sh, lo, hi, "" if lo <= sh <= hi else "  OUT", v["tiles"].get(g, 0), CC.fmt(want, 0)))
        return
    t = text(out, res)
    print(t)
    p = CC.save(STUDY, out)
    open(os.path.join(CC.OUT, STUDY + ".txt"), "w").write(t + "\n")
    print("\nwrote", p)


if __name__ == "__main__":
    main(sys.argv[1:])
