"""One-off edit of gen/learn/fn_medical.py (rehang anywhere in the room, lights as hung, windows beside doors, glaze by
rank, fridge fallback). Scratch, kept for the record."""
p = 'tools/mapforge/gen/learn/fn_medical.py'
s = open(p).read()


def rep(old, new, cnt=1):
    global s
    assert s.count(old) == cnt, (old[:70], s.count(old))
    s = s.replace(old, new)


rep('''    out = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        for o in t.objs:
            if CO.mounted(o):
                v = DIRV.get(CO.mount_side(o))
                if v:
                    out[(x + v[0], y + v[1])].append(((x, y), o))
    return out''', '''    out = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        for o in t.objs:
            v = None
            if o.path.startswith("/obj/machinery/light") and not o.path.startswith("/obj/machinery/light_switch"):
                v = DIRV.get(o.num("dir", 2) or 2)
            elif CO.mounted(o):
                v = DIRV.get(CO.mount_side(o))
            if v:
                out[(x + v[0], y + v[1])].append(((x, y), o))
    return out''')
start = s.index('def _rehang(')
end = s.index('def _ok(')
s = s[:start] + '''def _rehang(m, w, hung, exclude=()):
    """Move what hangs on wall tile w to another bare wall face of the same room within 6 tiles (the same facing
    first; turned, its pixel shift or a light's dir follow); APCs and alarms stay. True if w is left bare."""
    moves, taken = [], set()
    for f, o in hung.get(w, []):
        if o.path.startswith(PINNED):
            return False
        v = (w[0] - f[0], w[1] - f[1])
        area = m.get(*f).apath
        best = None
        for dx in range(-6, 7):
            for dy in range(-6, 7):
                q = (f[0] + dx, f[1] + dy)
                tq = m.get(*q)
                if abs(dx) + abs(dy) > 6 or tq is None or tq.area is None or tq.apath != area or not _room_floor(tq):
                    continue
                for d, u in DIRV.items():
                    wq = (q[0] + u[0], q[1] + u[1])
                    if wq == w or wq in hung or wq in taken or wq in exclude or not _plain_wall(m.get(*wq)):
                        continue
                    key = (u != v, abs(dx) + abs(dy), q, d)
                    if best is None or key < best[0]:
                        best = (key, q, wq, d)
        if best is None:
            return False
        moves.append((f, o, best[1], best[2], best[3]))
        taken.add(best[2])
    for f, o, q, wq, d in moves:
        m.get(*f).objs = [x for x in m.get(*f).objs if x is not o]
        if o.path.startswith("/obj/machinery/light"):
            o.vars = [(k, v_) for k, v_ in o.vars if k != "dir"] + ([("dir", str(d))] if d != 2 else [])
        else:
            mag = max(abs(o.num("pixel_x")), abs(o.num("pixel_y"))) or 30
            u = DIRV[d]
            o.vars = [(k, v_) for k, v_ in o.vars if k not in ("pixel_x", "pixel_y")] + \\
                [(k, str(mag * c)) for k, c in (("pixel_x", u[0]), ("pixel_y", u[1])) if c]
        m.get(*q).objs.append(o)
        hung[wq].append((q, o))
    hung.pop(w, None)
    return True


''' + s[end:]
rep('''def _wall_runs(m, D, P, want_types, hung, allow_hung=False):''',
    '''def _wall_runs(m, D, P, want_types, hung, allow_hung=False, by_door=False):''')
rep('''            along = (dy, dx)
            if not all(_wallish(m.get(w[0] + k * along[0], w[1] + k * along[1])) for k in (1, -1)):
                continue
            out.append((w, (dx, dy), p, q))''', '''            along = (dy, dx)
            if not all(_wallish(m.get(w[0] + k * along[0], w[1] + k * along[1])) or
                       (by_door and m.get(w[0] + k * along[0], w[1] + k * along[1]).has("/obj/machinery/door"))
                       for k in (1, -1)):
                continue
            out.append((w, (dx, dy), p, q))''')
rep('''    runs = _wall_runs(m, D, P, want_types, hung, allow_hung=True)
    if not runs:
        return 0
    rank = {t: i for i, t in enumerate(want_types)}
    best = min(rank.get(D.name(D.side(r[3], None)), 99) for r in runs)
    runs = [r for r in runs if rank.get(D.name(D.side(r[3], None)), 99) == best]
    cx = sum(r[0][0] for r in runs) / float(len(runs))
    cy = sum(r[0][1] for r in runs) / float(len(runs))
    runs.sort(key=lambda r: (abs(r[0][0] - cx) + abs(r[0][1] - cy), r[0]))
    done = []
    for w, step, p, q in runs:''', '''    allr = _wall_runs(m, D, P, want_types, hung, allow_hung=True, by_door=True)
    if not allr:
        return 0
    rank = {t: i for i, t in enumerate(want_types)}
    done = []
    for level in sorted({rank.get(D.name(D.side(r[3], None)), 99) for r in allr}):
        if done:
            break
        runs = [r for r in allr if rank.get(D.name(D.side(r[3], None)), 99) == level]
        cx = sum(r[0][0] for r in runs) / float(len(runs))
        cy = sum(r[0][1] for r in runs) / float(len(runs))
        runs.sort(key=lambda r: (r[0] in hung, abs(r[0][0] - cx) + abs(r[0][1] - cy), r[0]))
        _glaze_run(m, runs, hung, n, done)
    if done:
        log("  fn_medical: %s windows %s" % (what, " ".join("%d,%d" % w for w in done)))
    return len(done)


def _glaze_run(m, runs, hung, n, done):
    for w, step, p, q in runs:''')
rep('''        tw = m.get(*w)
        tw.turf = dmm.Atom("/turf/open/floor/plating")
        tw.objs = [o for o in tw.objs if o.path.startswith("/obj/structure/cable")] + \\
            [dmm.Atom("/obj/effect/spawner/structure/window/reinforced")]
        done.append(w)
    if done:
        log("  fn_medical: %s windows %s" % (what, " ".join("%d,%d" % w for w in done)))
    return len(done)''', '''        tw = m.get(*w)
        tw.turf = dmm.Atom("/turf/open/floor/plating")
        tw.objs = [o for o in tw.objs if o.path.startswith("/obj/structure/cable")] + \\
            [dmm.Atom("/obj/effect/spawner/structure/window/reinforced")]
        done.append(w)''')
rep('''        runs = [r for r in _wall_runs(m, D, P, pub + ("storage", "cryo"), hung, allow_hung=True) if not near_lock(r[0])]''',
    '''        runs = [r for r in _wall_runs(m, D, P, pub + ("storage", "cryo"), hung, allow_hung=True, by_door=True)
                if not near_lock(r[0])]''')
rep('''            m.get(*w).objs.append(dmm.Atom("/obj/machinery/smartfridge/chemistry/preloaded"))
            log("  fn_medical: chemistry smartfridge in the wall at %d,%d" % w)
            n += 1
            break''', '''            m.get(*w).objs.append(dmm.Atom("/obj/machinery/smartfridge/chemistry/preloaded"))
            log("  fn_medical: chemistry smartfridge in the wall at %d,%d" % w)
            n += 1
            break
        else:
            # no wall to set it in: against a chemistry wall, nearest its desk or door
            serve = [w for w, s, a in D.desks if s == ("P", P["i"])] or [w for w in D.doors if any(
                (w[0] + dx, w[1] + dy) in P["tiles"] for dx, dy in N4)]
            p = _place(m, P["tiles"], D.fronts(), [dmm.Atom("/obj/machinery/smartfridge/chemistry/preloaded")],
                       want=lambda p: bool(_walls(m, p)),
                       prefer=lambda p: min([abs(p[0] - w[0]) + abs(p[1] - w[1]) for w in serve] or [0]))
            if p:
                log("  fn_medical: chemistry smartfridge against the wall at %d,%d" % p)
                n += 1''')
open(p, 'w', newline='').write(s)
print("patched")
