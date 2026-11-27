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
STALL = 30            # repair stops after this many moves without improvement
# M2's exit test: every band and pair, plus these hard checks (walk, air and power belong to M3)
M2_HARD = ("core room types", "oversized rooms", "known paths", "solid wall filler")
# stage full gates every check but these (none since gen/net.py lays power, air and disposals, 2026-11-25)
M3_PENDING = ()
# GEN_NET=0 builds the full stage without gen/net.py's engine, docks, solars and networks (the 2026-11-23 full stage)
NETWORKS = os.environ.get("GEN_NET", "1") != "0"
# the room stage: departments composed bottom-up (gen/compose.py), or GEN_ROOMS=topdown for the old packing into
# pre-made blocks (gen/rooms.py)
BOTTOM_UP = os.environ.get("GEN_ROOMS", "bottomup") != "topdown"


def _layout(*a, **k):
    if BOTTOM_UP:
        import compose as CP
        return CP.layout(*a, **k)
    return BL.layout(*a, **k)


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


# block-stage checks of what the station needs from its layout, not its shape; each counts as BLOCK_HEAVY band fails
# in the search (a layout without the cargo dock strip loses to one with it and two more shape misses)
BLOCK_HEAVY = {"cargo dock strip": 3}


def measure(m, name):
    band, rules, P, _ = G.bands()
    sm = parse.SemanticMap(m, name, 1)
    f = {}
    f.update(G.flat_skeleton(G.SK.measure(sm)))
    f.update(G.flat_shares(G.DS.measure(sm)))
    f.update(G.flat_adj(G.DA.measure(sm), P))
    checks = G.band_checks(f, "blocks")
    if BOTTOM_UP:
        import net as NT_
        fits = NT_.strip_fits(m)
        if fits is not None:
            checks.append(dict(kind="hard", name="cargo dock strip", ok=bool(fits), value=int(bool(fits)),
                               dist=0.0 if fits else BLOCK_HEAVY["cargo dock strip"] - 1.0,
                               detail="Box's supply dock strip fits on the cargo bay" if fits else
                               "no hull wall of the cargo bay takes the supply dock strip (the shuttle's 12 x 7 rect)"))
    return checks, f


def _nfail(fails):
    return sum(BLOCK_HEAVY.get(c["name"], 1) for c in fails)


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
    since = 0
    for it in range(evals):
        if cur_sc == 0 or since >= STALL:
            break
        since += 1
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
        m2, L2 = _layout(prog, q, sub, P, radial, room, rband, force=asg)
        ch2, f2 = measure(m2, name)
        sc2 = _score(ch2)
        log.append(dict(sub=sub, try_="repair", fails=[c["name"] for c in ch2 if not c["ok"]], params={}))
        if sc2 < cur_sc - 1e-9:
            since = 0
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
        m, L = _layout(prog, params, sub, P, radial, room, rband)
        checks, f = measure(m, name)
        fails = [c for c in checks if not c["ok"]]
        log.append(dict(sub=sub, try_=i, fails=[c["name"] for c in fails], params={k: v for k, v in params.items()
                                                                            if k != "radial_shift"}))
        if not quiet:
            print("  %s try %2d (layout %d): %d fails %s" % (name, i, sub, len(fails), ", ".join(
                "%s=%s" % (c["name"], G.CC.fmt(c["value"])) for c in fails[:6])))
        if best is None or _nfail(fails) < _nfail(best[2]):
            best = (m, L, fails, checks, f, sub)
        if not fails:
            break
        params = nudge(params, checks, prog)
    if best[2]:
        best = repair(best, prog, P, radial, room, rband, name, log, quiet, evals=int(os.environ.get("GEN_REPAIR", 80)))
    return best, dict(best[1].q)


ROOM_ROUNDS = 4


REUSE_ROUNDS = 2      # room rounds when the block plan is reused
# a station without these doesn't run: a round missing one loses to any round that has it (two rounds tied on 17
# failures kept the one with no engine, 2026-11-25)
ESSENTIAL = ("engine placed", "docks", "grid reach", "atmos works", "walkable rooms", "solar arrays", "floor reached",
             "function: rooms", "function: doors", "function: big machines", "function: public rooms",
             "function: wall joins", "function: wall mounts")


def _weight(fails):
    return sum(10 if c["name"] in ESSENTIAL else 1 for c in fails)


def _save_layout(name, params, sub, asg):
    """The block plan a seed's search settled on (params, sub-seed, the slot assignment), for GEN_REUSE=1 rebuilds:
    a change to the room stage is then judged on the same station in minutes, not after a 20-minute search."""
    cmap, smap, lob, ai = asg
    d = dict(params=params, sub=sub, cmap=cmap, smap={"%s|%s" % k: v for k, v in smap.items()}, lob=lob, ai=ai)
    json.dump(d, open(os.path.join(OUT, name + ".layout.json"), "w"), default=str)


def _load_layout(name):
    p = os.path.join(OUT, name + ".layout.json")
    if not os.path.exists(p):
        return None
    d = json.load(open(p))
    smap = {}
    for k, v in d["smap"].items():
        a, b = k.split("|")
        smap[(int(a), int(b))] = v
    ai = tuple(d["ai"]) if isinstance(d["ai"], list) else d["ai"]
    return d["params"], d["sub"], (d["cmap"], smap, d["lob"], ai)


# medical before the alarms and networks (its cryo bay and moved morgue want their fixtures and power); the rest
# after mend, as their agents tested them on finished maps (trim took the engine vestibule's closets, doordb renamed
# the new doors); science last (the air pass put a supply vent in xenobiology's kill room)
FN_EARLY = ("fn_medical",)
FN_LATE = ("fn_security_command", "fn_service", "fn_engineering", "fn_science_cargo")


def _fn_passes(m, seed, log, names):
    """The department function passes (gen/learn/fn_<dept>.py fix(m, seed, log)); one that fails is logged with
    its traceback and the build goes on (a half-run pass leaves what it did)."""
    import importlib
    import traceback
    sys.path.insert(0, os.path.join(HERE, "learn"))
    for nm in names:
        if not os.path.exists(os.path.join(HERE, "learn", nm + ".py")):
            continue
        try:
            n = importlib.import_module(nm).fix(m, seed, log)
            log("%s: %s changes" % (nm, n))
        except Exception:                      # noqa: BLE001
            log("%s FAILED: %s" % (nm, traceback.format_exc()[-800:].replace(chr(10), " | ")))


def _trace(m, label, log):
    """GEN_TRACE_DOORS=1: the dead airlocks (gen/doorfix.py) after each late pass, to find the pass that makes them."""
    if os.environ.get("GEN_TRACE_DOORS"):
        import doorfix
        d = doorfix.dead(m)
        log.append("trace %-14s dead doors %d %s" % (label, len(d), " ".join("%d,%d" % (x, y) for x, y, _ in d[:12])))


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
    best = None
    reuse = _load_layout(name) if os.environ.get("GEN_REUSE") else None
    if reuse is not None:
        params, sub, asg = reuse
        rounds = min(rounds, REUSE_ROUNDS)
    for rnd in range(rounds):
        if reuse is not None and rnd == 0:
            # the block plan this seed settled on before (GEN_REUSE=1): no search, the room stage again
            m, L = _layout(prog, params, sub, P, radial, room, rband, force=asg)
            best = (m, L, [], [], 0, sub)
            block_fail = False
        elif best is None or block_fail:
            best, params = search(prog, params, tries if rnd == 0 else max(8, tries // 3), name, P, radial, room,
                                  rband, log, quiet)
            m, L, fails, checks, f, sub = best
            asg = (dict(L.cmap), {k: list(v) for k, v in L.smap.items()}, list(L.lob), L.ai_at)
            _save_layout(name, params, sub, asg)
        else:
            # the block plan passed: rebuild it as it was and furnish again with another room seed
            m, L = _layout(prog, params, sub, P, radial, room, rband, force=asg)
            L.info["room_salt"] = rnd
        rooms_log = []
        if stage in ("rooms", "full"):
            if BOTTOM_UP:
                import compose as CP
                CP.finish(L, m, log=rooms_log.append)
            else:
                import rooms as RM
                RM.furnish(L, m, log=rooms_log.append)
            if stage == "full":
                import dress as DR
                import connect as CN
                import net as NT
                if NETWORKS:
                    NT.REPORT.clear()
                    NT.engine(m, L, rooms_log.append)
                    NT.outside(m, L, rooms_log.append)
                    import voids as VD
                    VD.fill(m, seed, rooms_log.append)         # walled-in space made vacant rooms
                _trace(m, "engine+outside", rooms_log)
                keep = {}
                if getattr(L, "learned_tiles", None):
                    dx, dy = L.offset[0] - L.learned_off[0], L.offset[1] - L.learned_off[1]
                    keep = {(x + dx, y + dy): m.get(x + dx, y + dy).copy() for (x, y) in L.learned_tiles
                            if m.get(x + dx, y + dy) is not None}
                DR.dress(m, rooms_log.append)
                for p_, t_ in keep.items():
                    m.set(p_[0], p_[1], t_)
                if keep:
                    rooms_log.append("learned rooms: %d floor tiles kept as furnished through the dressing passes" % len(keep))
                if NETWORKS:
                    # after the restore: a learned room's missing kit (a kitchen's microwave) was added and then
                    # thrown away with the dressing passes' changes (2026-11-25)
                    import essentials as ES
                    ES.apply(m, rooms_log.append)
                _trace(m, "dress+es", rooms_log)
                CN.connect(m, rooms_log.append)
                _trace(m, "connect", rooms_log)
                if NETWORKS:
                    import walls as WLL
                    WLL.absorb_gaps(m, rooms_log.append)       # sealed 1-wide gaps taken into the rooms beside them
                    WLL.merge_doubles(m, rooms_log.append)     # one wall where two stood (gen/walls.py)
                    sys.path.insert(0, os.path.join(HERE, "learn"))
                    import audit as AU
                    AU.seat_big(m, rooms_log.append)           # the gravity generator's 3x3 first, before doors come
                    import doorcount as DCN
                    DCN.fix(m, rooms_log.append)               # each room's door count in its type's stock range
                    _trace(m, "merge_doubles", rooms_log)
                if NETWORKS:
                    import walkfix as WF
                    import doorfix as DF
                    DF.fix(m, rooms_log.append)                # no airlock into a wall or a blocked front
                    NT.REPORT["cut_off"] = WF.fix(m, rooms_log.append)
                    _trace(m, "walkfix", rooms_log)
                    # walls that meet only at a corner joined (medbay's wall to surgery stepped a row, f21)
                    WLL.join_corners(m, rooms_log.append)
                    # every area that takes power has its APC before the grid is laid (crew 100 seed 7's starboard
                    # maint had lost its own by here: nine maint doors without power, 2026-11-26)
                    sys.path.insert(0, os.path.join(HERE, "learn"))
                    import settle as STL
                    STL.settle(m, rooms_log.append)            # pieces where the stock maps put them (placestudy)
                    import density as DNS
                    DNS.fix(m, rooms_log.append)               # each room's free floor in its type's stock band
                    import airy as AIRY
                    AIRY.fix(m, rooms_log.append)              # no 1-tile squeezes where stock rooms keep walkways open
                    AU.pair_up(m, rooms_log.append)            # the experimentor's console within its 3 tiles
                    import desks as DSK
                    DSK.fix(m, seed, rooms_log.append)         # counters: kitchen hatch, chemistry/R&D/cargo desks (f21: 7)
                    # each department's functional patterns from the stock maps (tools/mapforge/studies/dept_specs/:
                    # cells with timers, Brig Control's desk, the serving hatch, the produce fridge, an operating room,
                    # the cryo bay, ...), before the alarms and the networks
                    _fn_passes(m, seed, rooms_log.append, FN_EARLY)
                    NT.dedupe_apcs(m, rooms_log.append)       # one an area (the security corridor had two)
                    n_apc = 0
                    for a_ in sorted({t.apath for t in m.tiles.values() if t.apath and not t.apath.startswith(
                            ("/area/space", "/area/solar", "/area/engine/supermatter", "/area/science/test_area",
                             "/area/shuttle"))}):
                        n_apc += NT.ensure_apc(m, a_, lambda s_: None)
                    rooms_log.append("apc: %d areas without one given one before the grid" % n_apc)
                    import fixtures as FXT
                    FXT.fix(m, seed, rooms_log.append)         # fire/air alarms, switches, extinguishers at stock rates
                    # (after the APCs: hung first, they took a small store's only free wall face and its door had no
                    # power, f17)
                    NT.networks(m, rooms_log.append)
                    _trace(m, "networks", rooms_log)
                    WLL.seal_hull(m, rooms_log.append)        # no station floor left open to space
                    WLL.fill_slivers(m, rooms_log.append)     # no 1-wide pocket of space sealed between two walls
                    WLL.hull_corners(m, rooms_log.append)     # no hull corner left open (walls meeting diagonally)
                    _trace(m, "seal_hull", rooms_log)
                    DF.fix(m, rooms_log.append)                # again: the seal can wall in a door that opened on space
                    sys.path.insert(0, os.path.join(HERE, "learn"))
                    import doordb as DD
                    DD.style(m, seed, rooms_log.append)        # learned airlock types, access and names
                    DF.door_areas(m, rooms_log.append)        # no airlock in space's unpowered area
                    import audit as AU
                    lt_ = set()
                    if getattr(L, "learned_tiles", None):
                        dx_, dy_ = L.offset[0] - L.learned_off[0], L.offset[1] - L.learned_off[1]
                        lt_ = {(x + dx_, y + dy_) for (x, y) in L.learned_tiles}
                    AU.trim(m, lt_, rooms_log.append)          # no more lockers than a human map's room type has
                    AU.mend(m, rooms_log.append)               # consoles off walls, machines where one can stand
                    AU.seat_big(m, rooms_log.append)           # last: the mend moved a table into the 3x3 (f17)
                    # after the networks: xenobiology's kill room loses the supply vent the air pass gave it
                    _fn_passes(m, seed, rooms_log.append, FN_LATE)
                    WLL.join_corners(m, rooms_log.append)      # the late passes' walls joined too
                    WLL.clear_stray_glass(m, rooms_log.append)  # panes left of wall lines that went (to space)
                    import mounts as MNT
                    MNT.fix(m, rooms_log.append)               # APCs, alarms, lights, signs on a wall that's there
                    import doordb as DDB
                    n_ = DDB.open_jobs(m, rooms_log.append)    # the late passes' areas: each piece reached by its jobs
                    rooms_log.append("doors: %d more doors opened for a department's own jobs after the late passes" % n_)
                    MNT.bot_decals(m, rooms_log.append)
                    WLL.hull_corners(m, rooms_log.append)
                    AU.seat_big(m, rooms_log.append)           # a late pass may stand a piece on the 3x3 (f30)
                    au_ = AU.audit(m)
                    rooms_log.append("audit: %s" % AU.summary(au_))
                    import placestudy as PSY
                    rooms_log.append("placement: %s" % PSY.summary(PSY.check(m)))
                    L.info["function"] = AU.function_checks(au_)
            if not quiet:
                for ln in rooms_log:
                    print("  " + ln)
            dmm.write(m, path)
            parse._CACHE.pop((path, 1), None)
            checks = G.run(path, "full", quiet=True)
            if stage == "full":
                checks = [c for c in checks if c["kind"] in ("band", "pair", "hard", "ruled")
                          and c["name"] not in M3_PENDING]
                if NETWORKS:
                    import net as NT
                    checks += NT.net_checks()
                    # what the function audit says a station can't do without (gen/audit.py function_checks): a round
                    # that lost the AI core, telecomms or virology to a tighter layout passed with 4 shape fails and
                    # was kept over ones that had them (crew 100 seed 7 f11, 2026-11-26)
                    checks += L.info.get("function", [])
            else:
                checks = [c for c in checks if c["kind"] in ("band", "pair") or c["name"] in M2_HARD]
            fails = [c for c in checks if not c["ok"]]
            log.append(dict(sub=sub, try_="rooms %d" % rnd, fails=[c["name"] for c in fails], params={}))
            if not quiet:
                print("  %s rooms round %d: %d fails %s" % (name, rnd, len(fails), ", ".join(c["name"] for c in fails)))
        block_fail = any(c["name"].startswith(G.BLOCK_PREFIX) or c["kind"] == "pair" for c in fails)
        if kept is None or _weight(fails) < _weight(kept[2]):
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


def auto_jobs(most=8, keep=4):
    """Workers for a batch: the cores idle right now (Windows' CPU load over a second), keeping `keep` cores for the
    other sessions on this PC, at most `most`, at least 1."""
    import subprocess
    n = os.cpu_count() or 4
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command",
                              "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average)"
                              ".Average"], capture_output=True, text=True, timeout=30).stdout.strip()
        load = float(out) / 100.0
    except Exception:            # noqa: BLE001
        load = 0.5
    idle = int(n * (1.0 - load))
    j = max(1, min(most, idle - keep))
    print("jobs: %d (%d cores, load %.0f%%)" % (j, n, 100 * load), flush=True)
    return j


def _job(args):
    """One build in a worker (a batch's workers keep their loaded maps between seeds)."""
    (shape, crew, seed), tries, quiet, stage = args
    share_wait("gen-" + SE.name(shape, crew, seed))
    r = build(seed, crew, shape, tries, quiet, stage)
    r["_job"] = (shape, crew, seed)
    print("  done %s: %s" % (r["name"], "PASS" if not r["fails"] else "%d fails" % len(r["fails"])), flush=True)
    return r


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
    ap.add_argument("--stage", default="blocks", choices=("blocks", "rooms", "full"))
    ap.add_argument("--jobs", default="1", help="builds at once (worker processes), or auto: the idle cores")
    a = ap.parse_args(argv)
    jobs = SE.regression_set() if a.set else [(a.shape, a.crew, a.seed)]
    res = []
    a.jobs = auto_jobs() if a.jobs == "auto" else int(a.jobs)
    if a.jobs > 1 and len(jobs) > 1:
        import multiprocessing as mp
        with mp.get_context("spawn").Pool(a.jobs) as pool:
            it = pool.imap_unordered(_job, [(j, a.tries, a.quiet, a.stage) for j in jobs])
            out = list(it)
        out.sort(key=lambda r: jobs.index(r["_job"]))
    else:
        out = [_job((j, a.tries, a.quiet, a.stage)) for j in jobs]
    for r in out:
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
