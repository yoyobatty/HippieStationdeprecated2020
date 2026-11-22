"""Build a station from a seed and a crew size (studies/full_generator_plan.md). Today: stages S0-S2, the block plan
(M1), gated with gen/gate.py's block stage. A build that fails is retried with the next sub-seed and its numbers
nudged toward the band middle (spread, spoke reach, hall width, maint runs, a department's radial place); the
first build that passes every check is kept, else the one with the fewest failures.

    python tools/mapforge/gen/build.py --crew 80 --seed 1            # data/mapforge/gen/gen_hub_c80_s1.dmm + .png
    python tools/mapforge/gen/build.py --set                         # the regression set (gen/seeds.py)
    python tools/mapforge/gen/build.py --set --sheet                 # and one contact sheet of all of them

Output: data/mapforge/gen/<name>.dmm, <name>.json (program, tries, checks), and the block picture
data/previews/mapforge/gen/<name>.png (departments coloured, walls dark, doors yellow).
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import gate as G  # noqa: E402
import program as PR  # noqa: E402
import blocks as BL  # noqa: E402
import seeds as SE  # noqa: E402
from forge import dmm, parse  # noqa: E402

OUT = os.environ.get("GEN_OUT") or os.path.join(parse.ROOT, "data", "mapforge", "gen")   # GEN_OUT: a trial folder
NUDGES = 2
# M2's exit test: every band and pair, plus these hard checks (walk, air and power belong to M3)
M2_HARD = ("core room types", "oversized rooms", "known paths", "solid wall filler")
PIC = os.path.join(OUT, "pictures") if os.environ.get("GEN_OUT") else os.path.join(parse.ROOT, "data", "previews",
                                                                                    "mapforge", "gen")
COL = {"command": (70, 110, 200), "security": (200, 60, 60), "medical": (90, 190, 220), "science": (170, 90, 200),
       "engineering": (230, 160, 40), "atmos": (60, 200, 160), "cargo": (160, 120, 70), "service": (120, 200, 80),
       "civic": (200, 200, 120), "dorms": (220, 130, 180), "ai": (40, 160, 90), "hall": (190, 190, 195),
       "arrivals": (235, 235, 240), "escape": (235, 235, 240), "maint": (95, 85, 70)}


def targets():
    import corpus_common as CC
    da = json.load(open(os.path.join(CC.OUT, "dept_adjacency_targets.json")))
    sp = json.load(open(os.path.join(CC.OUT, "space_sizes_targets.json")))
    radial = {d: v[1] for d, v in da["radial"].items() if v[1] is not None}
    room = {k[len("room_size_"):]: v[1] for k, v in sp.items() if k.startswith("room_size_") and v[1]}
    return radial, room


def measure(m, name):
    band, rules, P, _ = G.bands()
    sm = parse.SemanticMap(m, name, 1)
    f = {}
    f.update(G.flat_skeleton(G.SK.measure(sm)))
    f.update(G.flat_shares(G.DS.measure(sm)))
    f.update(G.flat_adj(G.DA.measure(sm), P))
    return G.band_checks(f, "blocks"), f


def nudge(params, checks, prog=None):
    """Move the numbers that failed toward their band: one rule per check, from what each number depends on. Every
    department's quota is also scaled toward its program share (floor ratios differ by block shape)."""
    q = dict(params, radial_shift=dict(params.get("radial_shift", {})), qmul=dict(params.get("qmul", {})))
    band = G.bands()[0]
    # one outpost distance moves every radial place at once: by the mean signed miss of all departments' places
    devs = []
    for c in checks:
        if c["name"].startswith("radial.") and c["name"] != "radial.hall":
            lo, hi = band[c["name"]][0], band[c["name"]][1]
            devs.append((c["value"] - 0.5 * (lo + hi)) / max(0.05, 0.5 * (hi - lo)))
    if devs and any(not c["ok"] for c in checks if c["name"].startswith("radial.")):
        mdev = sum(devs) / len(devs)
        q["outpost"] = max(1.0, min(2.2, q["outpost"] * (1.0 + 0.2 * mdev)))
    if prog:
        for c in checks:
            if c["name"].startswith("share.") and c["value"]:
                d = c["name"][6:]
                if d in BL.RING or d in ("command", "maint"):
                    want = prog["budgets"][d] / float(prog["floor"])
                    q["qmul"][d] = max(0.5, min(2.0, q["qmul"].get(d, 1.0) * (want / c["value"]) ** 0.8))
    for c in checks:
        if c["ok"] or c["kind"] != "band":
            continue
        k, v = c["name"], c["value"]
        lo, hi = band[k][0], band[k][1]
        high = v > hi
        if k == "skel.fill":                            # the outpost sets the box: nearer when fill runs low
            q["outpost"] = max(1.0, min(2.2, q["outpost"] * (1.05 if high else 0.95)))
        elif k == "skel.aspect":
            q["spread"] *= 1.0
        elif k in ("skel.spoke_reach", "skel.spoke_len", "skel.spine"):
            q["depth"] = max(0.6, min(1.8, q["depth"] * (1.1 if high else 0.92)))
            if k == "skel.spoke_reach":                 # the outpost widens the radius reach is measured by
                q["outpost"] = max(1.0, min(2.2, q["outpost"] * (1.06 if high else 0.96)))
        elif k in ("share.hall", "skel.hall_share"):
            q["depth"] = max(0.6, min(1.8, q["depth"] * (1.15 if high else 0.9)))
        elif k == "share.maint":
            pass                                         # qmul["maint"] above
        elif k in ("share.arrivals", "share.escape"):
            q["lobby"] *= 0.8 if high else 1.25
        elif k.startswith("space.hall_w"):
            n = int(k[len("space.hall_w"):])
            if n in (3, 4, 5):
                ws = list(q.get("spoke_ws", BL.DEFAULT_PARAMS["spoke_ws"]))
                if high and n in ws and ws.count(n) >= 1 and n != 3:
                    ws[ws.index(n)] = 3
                elif not high and n not in ws:
                    ws[ws.index(3) if 3 in ws else 0] = n
                q["spoke_ws"] = tuple(ws)
                lw = list(q.get("lw", BL.DEFAULT_PARAMS["lw"]))
                if n in (3, 4):
                    lw[n - 3] *= 0.6 if high else 1.6
                    q["lw"] = tuple(lw)
            elif n in (1, 2):
                q["tails"] = max(0.0, min(3.0, q.get("tails", 1.0) * (0.7 if high else 1.5)))
            elif n >= 6:
                q["lobby"] = max(0.5, min(1.6, q.get("lobby", 1.0) * (0.85 if high else 1.15)))
        elif k.startswith("space.maint_w"):
            n = int(k[len("space.maint_w"):])
            rw = list(q.get("runw", BL.DEFAULT_PARAMS["runw"]))
            if n in (2, 3):
                rw[n - 2] = max(0.05, min(0.8, rw[n - 2] + (-0.1 if high else 0.1)))
                q["runw"] = tuple(rw)
            elif n >= 4:
                q["pockets"] = max(0.2, min(2.0, q.get("pockets", 0.7) * (0.8 if high else 1.2)))
        elif k in ("space.pocket_med", "space.pockets_per_1k", "space.maint_pocket"):
            if k == "space.pocket_med":
                q["pockets"] = max(0.2, min(2.0, q.get("pockets", 0.7) * (1.2 if high else 0.85)))
            else:
                q["pockets"] = max(0.2, min(2.0, q.get("pockets", 0.7) * (0.8 if high else 1.25)))
        elif k.startswith("radial."):
            d = k.split(".", 1)[1]
            if d in BL.RING:
                mid = 0.5 * (lo + hi)
                q["radial_shift"][d] = q["radial_shift"].get(d, 0.0) + 0.7 * (mid - v)
            elif d in ("arrivals", "escape", "hall"):
                q["reach"] *= 0.92 if high else 1.08
    return q


def _score(checks):
    """Failures plus the total distance outside the bands (in band widths): continuous, so small steps count."""
    fails = [c for c in checks if not c["ok"]]
    return len(fails) + sum(min(3.0, c.get("dist", 0.0)) for c in fails)


def repair(best, prog, P, radial, room, rband, name, log, quiet, evals=80):
    """Local search on the best block plan (plan D7). It keeps the layout draw, makes one seeded random move at a
    time and keeps it when the score (_score) drops. Moves: swap two departments' slots; give the lobbies (and
    the AI) other spokes; scale a department's quota 0.85x / 1.15x; move the outpost 5% out or in; deeper or
    shallower spoke blocks; more or less maint."""
    import random as _r
    m, L, fails, checks, f, sub = best
    rnd = _r.Random("repair|%s" % name)
    params = dict(L.q, qmul=dict(L.q.get("qmul", {})))
    cur = (dict(L.cmap), {k: list(v) for k, v in L.smap.items()}, list(L.lob), L.ai_at)
    cur_sc = _score(checks)

    def where(asg):
        cmap, smap, lob, ai = asg
        out = {d: ("c", k) for k, d in cmap.items() if d}
        for key, ds in smap.items():
            for j, d in enumerate(ds):
                out[d] = ("s", key, j)
        return out

    def swapped(asg, a, b):
        cmap, smap, lob, ai = asg
        cmap = dict(cmap)
        smap = {k: list(v) for k, v in smap.items()}
        w = where((cmap, smap, lob, ai))
        for x, y in ((a, b), (b, a)):
            pos = w[x]
            if pos[0] == "c":
                cmap[pos[1]] = y
            else:
                smap[pos[1]][pos[2]] = y
        return (cmap, smap, list(lob), ai)
    nsp = len(L.spoke_list)
    for it in range(evals):
        if cur_sc == 0:
            break
        bad = [c["name"] for c in checks if not c["ok"]]
        q = dict(params, qmul=dict(params["qmul"]))
        asg = cur
        w = where(cur)
        spoke_depts = [d for d, pos in w.items() if pos[0] == "s"]
        corner_depts = [d for d, pos in w.items() if pos[0] == "c"]
        focus = [n.split(".", 1)[1] for n in bad if n.startswith(("radial.", "share."))]
        focus = [d for d in focus if d in w] or list(w)
        kind = rnd.choice(("swap", "swap", "qscale", "qscale", "outpost", "lob", "depth", "maint"))
        if kind == "swap":
            d = rnd.choice(focus)
            pool = corner_depts if d in corner_depts else spoke_depts
            others = [e for e in pool if e != d]
            if not others:
                continue
            asg = swapped(cur, d, rnd.choice(others))
        elif kind == "qscale":
            d = rnd.choice(focus)
            q["qmul"][d] = max(0.4, min(2.5, q["qmul"].get(d, 1.0) * rnd.choice((0.85, 0.92, 1.08, 1.15))))
        elif kind == "outpost":
            q["outpost"] = max(1.0, min(2.4, q.get("outpost", 1.3) * rnd.choice((0.95, 1.05))))
        elif kind == "lob":
            i, j = rnd.sample(range(nsp), 2)
            ai = cur[3]
            if ai in (i, j):
                ai = next((k for k in range(nsp) if k not in (i, j)), None)
            asg = (cur[0], cur[1], [i, j], ai)
        elif kind == "depth":
            q["depth"] = max(0.6, min(1.8, q.get("depth", 1.0) * rnd.choice((0.9, 1.1))))
        else:
            q["qmul"]["maint"] = max(0.5, min(2.5, q["qmul"].get("maint", 1.0) * rnd.choice((0.9, 1.1))))
        m2, L2 = BL.layout(prog, q, sub, P, radial, room, rband, force=asg)
        ch2, f2 = measure(m2, name)
        sc2 = _score(ch2)
        log.append(dict(sub=sub, try_="repair", fails=[c["name"] for c in ch2 if not c["ok"]], params={}))
        if sc2 < cur_sc - 1e-9:
            cur_sc, params, checks = sc2, q, ch2
            cur = (dict(L2.cmap), {k: list(v) for k, v in L2.smap.items()}, list(L2.lob), L2.ai_at)
            best = (m2, L2, [c for c in ch2 if not c["ok"]], ch2, f2, sub)
            if not quiet:
                print("  %s repair %d %s: score %.2f, %d fails" % (name, it, kind, sc2, len(best[2])))
    return best


def search(prog, params, tries, name, P, radial, room, rband, log, quiet):
    """S1 + S2: tries layouts (the draws change every NUDGES tries, nudged numbers between), keeps the plan with the
    fewest block-stage failures, then repairs it. Returns (best, params)."""
    best = None
    for i in range(tries):
        sub = i // NUDGES
        if i % NUDGES == 0 and i:
            keep = ("qmul", "outpost", "depth", "sw", "lw", "tails", "pockets", "runw", "lobby", "spoke_ws")
            params = dict(BL.DEFAULT_PARAMS, **{k: params[k] for k in keep if k in params})
        m, L = BL.layout(prog, params, sub, P, radial, room, rband)
        checks, f = measure(m, name)
        fails = [c for c in checks if not c["ok"]]
        log.append(dict(sub=sub, try_=i, fails=[c["name"] for c in fails], params={k: v for k, v in params.items()
                                                                            if k != "radial_shift"}))
        if not quiet:
            print("  %s try %2d (layout %d): %d fails %s" % (name, i, sub, len(fails), ", ".join(
                "%s=%s" % (c["name"], G.CC.fmt(c["value"])) for c in fails[:6])))
        if best is None or len(fails) < len(best[2]):
            best = (m, L, fails, checks, f, sub)
        if not fails:
            break
        params = nudge(params, checks, prog)
    if best[2]:
        best = repair(best, prog, P, radial, room, rband, name, log, quiet, evals=int(os.environ.get("GEN_REPAIR", 80)))
    return best, dict(best[1].q)


ROOM_ROUNDS = 4


def build(seed, crew, shape="hub", tries=24, quiet=False, stage="blocks"):
    """stage blocks: S0-S2, gated on the block checks. stage rooms: then S3 (gen/rooms.py) and the gate's band,
    pair and M2 hard checks on the furnished map; a furnished map that fails sends its numbers back (nudge) for
    another block search, up to ROOM_ROUNDS rounds, keeping the build with the fewest failures."""
    name = SE.name(shape, crew, seed)
    prog = PR.program(seed, crew, shape)
    radial, room = targets()
    P = G.bands()[2]
    rband = {k.split(".", 1)[1]: (v[0], v[1]) for k, v in G.bands()[0].items() if k.startswith("radial.")}
    params = dict(BL.DEFAULT_PARAMS)
    log = []
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".dmm")
    rounds = ROOM_ROUNDS if stage in ("rooms", "full") else 1
    kept = None
    for rnd in range(rounds):
        best, params = search(prog, params, tries if rnd == 0 else max(8, tries // 3), name, P, radial, room, rband,
                              log, quiet)
        m, L, fails, checks, f, sub = best
        rooms_log = []
        if stage in ("rooms", "full"):
            import rooms as RM
            RM.furnish(L, m, log=rooms_log.append)
            if not quiet:
                for ln in rooms_log:
                    print("  " + ln)
            dmm.write(m, path)
            parse._CACHE.pop((path, 1), None)
            checks = G.run(path, "full", quiet=True)
            checks = [c for c in checks if c["kind"] in ("band", "pair") or c["name"] in M2_HARD]
            fails = [c for c in checks if not c["ok"]]
            log.append(dict(sub=sub, try_="rooms %d" % rnd, fails=[c["name"] for c in fails], params={}))
            if not quiet:
                print("  %s rooms round %d: %d fails %s" % (name, rnd, len(fails), ", ".join(c["name"] for c in fails)))
        if kept is None or len(fails) < len(kept[2]):
            kept = (m, L, fails, checks, sub, rooms_log)
        if not fails:
            break
        params = nudge(params, checks, prog)
    m, L, fails, checks, sub, rooms_log = kept
    dmm.write(m, path)
    rep = dict(name=name, program=dict(prog, budgets={k: round(v) for k, v in prog["budgets"].items()}),
               kept_try=sub, tries=log, info=L.info, seconds=round(time.time() - t0, 1), rooms=rooms_log,
               checks=[dict(name=c["name"], ok=c["ok"], value=c["value"], detail=c["detail"]) for c in checks])
    json.dump(rep, open(os.path.join(OUT, name + ".json"), "w"), indent=1, default=str)
    pic = picture(m, L, os.path.join(PIC, name + ".png"), "%s  floor %d  %s" % (
        name, prog["floor"], "PASS" if not fails else "%d FAIL" % len(fails)))
    return dict(name=name, path=path, fails=[c["name"] for c in fails], checks=len(checks), picture=pic,
                tries=len(log), seconds=rep["seconds"])


def picture(m, L, out, title, scale=3):
    from PIL import Image, ImageDraw
    W, H = m.maxx, m.maxy
    im = Image.new("RGB", (W, H), (8, 8, 12))
    px = im.load()
    ox, oy = L.offset
    for (x, y, z), t in m.tiles.items():
        c = (x - ox, y - oy)
        o = L.own.get(c)
        tp = t.tpath
        if t.objs:
            col = (240, 210, 60)
        elif tp.startswith("/turf/closed"):
            col = (40, 40, 46) if o is None else tuple(int(v * 0.35) for v in COL.get(o, (90, 90, 90)))
        elif o is not None:
            col = COL.get(o, (120, 120, 120))
        else:
            continue
        px[x - 1, H - y] = col
    im = im.resize((W * scale, H * scale), Image.NEAREST)
    d = ImageDraw.Draw(im)
    cent = {}
    for c, o in L.own.items():
        if o in BL.AREA or o == "command":
            cent.setdefault(o, []).append(c)
    for o, cs in cent.items():
        x = sum(c[0] for c in cs) / len(cs) + ox
        y = sum(c[1] for c in cs) / len(cs) + oy
        d.text(((x - 1) * scale - 12, (H - y) * scale - 5), o[:5], fill=(255, 255, 255))
    d.rectangle((0, 0, im.width, 14), fill=(0, 0, 0))
    d.text((4, 2), title, fill=(255, 255, 255))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out)
    return out


def sheet(pics, out):
    from PIL import Image
    ims = [Image.open(p) for p in pics]
    cols = 5
    cw = max(i.width for i in ims)
    ch = max(i.height for i in ims)
    sc = min(1.0, 600.0 / cw)
    cw, ch = int(cw * sc), int(ch * sc)
    rows = (len(ims) + cols - 1) // cols
    s = Image.new("RGB", (cols * cw, rows * ch), (0, 0, 0))
    for i, im in enumerate(ims):
        im = im.resize((int(im.width * sc), int(im.height * sc)), Image.LANCZOS)
        s.paste(im, ((i % cols) * cw, (i // cols) * ch))
    s.save(out)
    return out


def share_wait(what):
    """Before each build of a batch: tools/gpu_share.py wait, so a Last Light timed run (which needs a quiet CPU
    and GPU) goes first; this session's batches are untimed."""
    import subprocess
    subprocess.call([sys.executable, os.path.join(parse.ROOT, "tools", "gpu_share.py"), "wait", what],
                    stdout=subprocess.DEVNULL)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--crew", type=int, default=80)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--shape", default="hub")
    ap.add_argument("--tries", type=int, default=24)
    ap.add_argument("--set", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--stage", default="blocks", choices=("blocks", "rooms"))
    a = ap.parse_args(argv)
    jobs = SE.regression_set() if a.set else [(a.shape, a.crew, a.seed)]
    res = []
    for shape, crew, seed in jobs:
        if a.set:
            share_wait("gen-" + SE.name(shape, crew, seed))
        r = build(seed, crew, shape, a.tries, a.quiet, a.stage)
        res.append(r)
        print("%s: %s (%d checks, %d tries, %.0f s)%s" % (
            r["name"], "PASS" if not r["fails"] else "FAIL", r["checks"], r["tries"], r["seconds"],
            "" if not r["fails"] else " " + ", ".join(r["fails"])), flush=True)
    n = sum(1 for r in res if not r["fails"])
    print("passed %d of %d" % (n, len(res)))
    if a.sheet:
        print("sheet", sheet([r["picture"] for r in res], os.path.join(PIC, "sheet.png")))
    return 0 if n == len(res) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
