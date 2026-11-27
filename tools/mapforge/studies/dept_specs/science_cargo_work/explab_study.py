"""Scratch: how each map houses the experimentor (the user of it stands beside it: in_range in experimentor.dm).

    python explab_study.py [dmm ...]      (default: the 8 stock maps)

Per map: explab floor tiles, the experimentor's own piece (floor joined to it without crossing a door, blast door or
window), blast doors/shutters in the room, scrubbers and vents in the room, air alarm, doors out and the walk from the
experimentor's side to the nearest one, console distance, safety closets, and what the room borders.
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import corpus as CO, dmm, function as FN  # noqa: E402

ROOT = os.path.abspath(os.path.join(MF, "..", ".."))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def _open(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") and not CO.solid(t)


def _door(t):
    return t is not None and any(o.path.startswith("/obj/machinery/door") and not o.path.startswith("/obj/machinery/door/firedoor")
                                 for o in t.objs)


def study(path):
    m = dmm.read(path)
    area = "/area/science/explab"
    tiles = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath == area}
    if not tiles:
        return None
    floor = {p for p in tiles if _open(m.get(*p))}
    exp = [p for p in tiles if m.get(*p).has("/obj/machinery/rnd/experimentor")]
    con = [p for p in tiles if m.get(*p).has("/obj/machinery/computer/rdconsole")]
    r = {"floor": len(floor - {p for p in floor if _door(m.get(*p))})}
    if not exp:
        return r
    e = exp[0]
    # piece: from the tiles round the experimentor, through floor that is not a door of any kind
    seen, q = set(), [(e[0] + dx, e[1] + dy) for dx, dy in N4]
    q = [p for p in q if p in floor and not _door(m.get(*p))]
    seen |= set(q)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in floor and n not in seen and not _door(m.get(*n)):
                seen.add(n)
                q.append(n)
    r["exp_piece"] = len(seen)
    r["con_dist"] = min((max(abs(c[0] - e[0]), abs(c[1] - e[1])) for c in con), default=None)
    r["con_same_piece"] = any(c in seen or any((c[0] + dx, c[1] + dy) in seen for dx, dy in N4) for c in con)
    cnt = Counter()
    for p in tiles:
        for o in m.get(*p).objs:
            for k, pre in (("blast", "/obj/machinery/door/poddoor"), ("scrubber", "/obj/machinery/atmospherics/components/unary/vent_scrubber"),
                           ("vent", "/obj/machinery/atmospherics/components/unary/vent_pump"), ("airalarm", "/obj/machinery/airalarm"),
                           ("firedoor", "/obj/machinery/door/firedoor"), ("firecloset", "/obj/structure/closet/firecloset"),
                           ("emcloset", "/obj/structure/closet/emcloset"), ("radcloset", "/obj/structure/closet/radiation"),
                           ("l3", "/obj/structure/closet/l3closet"), ("extcab", "/obj/structure/extinguisher_cabinet"),
                           ("shower", "/obj/machinery/shower"), ("camera", "/obj/machinery/camera"), ("windoor", "/obj/machinery/door/window"),
                           ("button", "/obj/machinery/button"), ("airlock", "/obj/machinery/door/airlock")):
                if o.path.startswith(pre):
                    cnt[k] += 1
    r.update(cnt)
    # glass between the experimentor's piece and the rest of the room
    win = 0
    for p in seen:
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            t = m.get(*n)
            if t is not None and CO.solid(t) and not t.tpath.startswith("/turf/closed"):
                win += 1
    r["piece_windows"] = win
    # nearest way out of the room (a door tile on the room's edge) from a tile beside the experimentor, by walking
    outs = [p for p in tiles if _door(m.get(*p)) and any(m.get(p[0] + dx, p[1] + dy) is not None and m.get(p[0] + dx, p[1] + dy).apath != area
                                                         and _open(m.get(p[0] + dx, p[1] + dy)) for dx, dy in N4)]
    outs += [(x + dx, y + dy) for (x, y) in tiles for dx, dy in N4 if (x + dx, y + dy) not in tiles and _door(m.get(x + dx, y + dy))]
    outs = set(outs)
    dist = {p: 0 for p in seen if any(max(abs(p[0] - e[0]), abs(p[1] - e[1])) <= 1 for _ in [0])}
    q = list(dist)
    best = None
    while q:
        p = q.pop(0)
        if p in outs:
            best = dist[p]
            break
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            tn = m.get(*n)
            if n in dist or tn is None or not _open(tn):
                continue
            if any(FN.is_dense(o) for o in tn.objs) and n not in outs:
                continue
            dist[n] = dist[p] + 1
            q.append(n)
    r["walk_to_exit"] = best
    r["doors_out"] = len(outs)
    nb = Counter()
    for (x, y) in tiles:
        for dx, dy in N4:
            t = m.get(x + 2 * dx, y + 2 * dy)
            if t is not None and t.apath != area and (x + 2 * dx, y + 2 * dy) not in tiles:
                nb[t.apath] += 1
    r["borders"] = [a for a, n in nb.most_common(5)]
    return r


def main():
    import forge.corpus as C
    paths = sys.argv[1:] or [os.path.join(ROOT, "_maps", "map_files", p) for p in C.MAPS]
    for p in paths:
        print(os.path.basename(p), study(p))


if __name__ == "__main__":
    main()
