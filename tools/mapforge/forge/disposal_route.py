"""Disposal routing for a redesigned zone.

The station's disposal loop runs through many departments. A redesign keeps every pipe tile the old bins' trash
travelled on (simulated with the game's rules, forge/disposals.py) and every tile between the zone's contacts with
the loop, drops the rest (old spurs to bins, old local lines), then:

- a bin with dest "station" (or any endpoint, e.g. "deathsposal" = where an old bin's trash ended) gets a spur to the
  nearest kept tile whose recorded flow leads to that endpoint; the spur joins with a junction whose primary side
  points downstream, so the trash leaves the way the old bins' trash did and through traffic is unchanged
- a bin with dest ("outlet", key) gets its own line to the outlet with that key (xenobiology pens)
Afterwards every bin is simulated again and must end where it was sent.
"""
import heapq

from forge import dmm
from forge import disposals as D

N, S, E, W = D.N, D.S, D.E, D.W
CARD = (N, S, E, W)


def nb(p, d):
    return (p[0] + D.DELTA[d][0], p[1] + D.DELTA[d][1])


def survey(m, zone):
    """Old flows from the zone's bins: {tile: set((leave_dir, endpoint))}, and each bin's endpoint."""
    rec = {}
    ends = {}
    for p in sorted(zone):
        t = m.get(*p)
        if not t or not t.has("/obj/machinery/disposal/bin"):
            continue
        tr = [o for o in t.objs if o.path.startswith(D.PIPE + "/trunk")]
        if not tr:
            continue
        path = D.flow(m, p, tr[0].num("dir", 2))
        end = path[-1][0]
        ends[p] = end
        for q, d in path:
            if d is not None:
                rec.setdefault(q, set()).add((d, end))
    return rec, ends


def backbone(m, zone):
    """Zone tiles of disposal networks that connect two or more points outside the zone (through lines)."""
    tiles = {p for p in zone if D.mask_at(m.get(*p))}
    deg = {}
    for p in tiles:
        deg[p] = len(D.neighbours(m, p))
    contacts = {p for p in tiles for q, d in D.neighbours(m, p) if q not in zone}
    keep = set(tiles)
    changed = True
    while changed:
        changed = False
        for p in list(keep):
            if p in contacts:
                continue
            live = [q for q, d in D.neighbours(m, p) if q in keep or q not in zone]
            if len(live) <= 1:
                keep.discard(p)
                changed = True
    return keep


def route(b, requests):
    """b: Builder (after structure/furniture). requests: list of (bin_tile, dest) where dest is "station", an
    endpoint name from b.disposal_ends, or ("outlet", outlet_tile, throw_dir). Returns notes, problems."""
    m = b.m
    orig = b.orig_map
    zone = b.zone
    rec, ends = survey(orig, zone)
    keep = backbone(orig, zone) | set(rec)
    notes, probs = [], []
    # 1. wipe zone disposal pipes except kept tiles; kept tiles get their original pipes back
    for p in zone:
        t = m.get(*p)
        # old pipes go; bins placed by the blueprint stay (the old bins weren't carried over)
        t.objs = [o for o in t.objs if not (o.path.startswith(D.PIPE) or o.path.startswith("/obj/structure/disposaloutlet"))]
        if p in keep:
            for o in orig.get(*p).objs:
                if o.path.startswith(D.PIPE) and not o.path.startswith(D.PIPE + "/trunk"):
                    t.objs.insert(0, o.copy())
    # a kept tile that was a trunk (old bin) becomes a straight piece or is dropped by the pruning above
    # 2. endpoints by name: "station" = the endpoint most old bins reached
    end_count = {}
    for e in ends.values():
        end_count[e] = end_count.get(e, 0) + 1
    station_end = max(end_count, key=end_count.get) if end_count else None
    named = dict(getattr(b.bp, "DISPOSAL_ENDS", {}))
    named.setdefault("station", station_end)
    used = {p for p in zone if D.mask_at(m.get(*p))}
    used |= {bt for bt, d in requests}  # no spur may run under another bin's tile
    used |= {d[1] for bt, d in requests if isinstance(d, tuple)}

    def can_pass(q):
        if q not in zone or q in used:
            return False
        t = m.get(*q)
        return t is not None

    def path_to(start, goals):
        dist, prev, heap = {start: 0}, {}, [(0, start, 0)]
        while heap:
            c, p, din = heapq.heappop(heap)
            if p in goals and p != start:
                out = [p]
                while p in prev:
                    p = prev[p]
                    out.append(p)
                return out[::-1]
            for d in CARD:
                q = nb(p, d)
                if q in goals or can_pass(q):
                    w = 1 + (1.5 if din and d != din else 0) + (2 if b.kind(q) in ("wall", "rwall") else 0)
                    if c + w < dist.get(q, 1e9):
                        dist[q] = c + w
                        prev[q] = p
                        heapq.heappush(heap, (c + w, q, d))
        return None

    def dir_between(a, c):
        return next(d for d in CARD if nb(a, d) == c)

    def lay(path, start_trunk, end_kind, end_info=None):
        """path[0] = bin tile (trunk), path[-1] = join tile or outlet tile."""
        t0 = m.get(*path[0])
        t0.objs.insert(0, dmm.Atom.parse(D.trunk_atom(dir_between(path[0], path[1]))))
        for i in range(1, len(path) - 1):
            a, here, c = path[i - 1], path[i], path[i + 1]
            mk = dir_between(here, a) | dir_between(here, c)
            m.get(*here).objs.insert(0, dmm.Atom.parse(D.segment_atom(mk)))
            used.add(here)
        last, prevt = path[-1], path[-2]
        if end_kind == "outlet":
            back = dir_between(last, prevt)
            tl = m.get(*last)
            tl.objs.insert(0, dmm.Atom.parse(D.trunk_atom(back)))
            tl.objs.append(dmm.Atom("/obj/structure/disposaloutlet", [("dir", str(end_info))] if end_info != S else []))
            used.add(last)
            return True
        # join: replace the straight piece on `last` with a junction, primary downstream
        branch = dir_between(last, prevt)
        flows = {d for d, e in rec.get(last, ()) if e == end_info}
        if len(flows) != 1:
            return False
        primary = flows.pop()
        j = D.junction_atom(primary, branch)
        if not j:
            return False
        tl = m.get(*last)
        old = [o for o in tl.objs if o.path.startswith(D.PIPE) and D.dpdir(o) == (primary | D.OPP[primary])]
        if not old:
            return False
        tl.objs.remove(old[0])
        tl.objs.insert(0, dmm.Atom.parse(j))
        return True

    for bin_tile, dest in requests:
        used.add(bin_tile)
        if bin_tile in keep:
            probs.append("disposals: the bin at %d,%d stands on the station's disposal line; move it off" % bin_tile)
            continue
        if isinstance(dest, tuple) and dest[0] == "outlet":
            outlet, throw = dest[1], dest[2]
            used.discard(outlet)
            path = path_to(bin_tile, {outlet})
            if not path:
                probs.append("disposals: no way from the bin at %d,%d to its outlet at %d,%d" % (*bin_tile, *outlet))
                continue
            lay(path, True, "outlet", throw)
            continue
        end = named.get(dest, dest)
        # joinable tiles: kept straight pieces whose recorded flow (one direction only) reaches that endpoint
        goals = set()
        for q, fl in rec.items():
            if q not in keep or q in (bin_tile,):
                continue
            ds = {d for d, e in fl if e == end}
            if len(ds) != 1 or len({d for d, e in fl}) != 1:
                continue
            pieces = [o for o in m.get(*q).objs if o.path.startswith(D.PIPE)]
            if len(pieces) == 1 and pieces[0].path.startswith(D.PIPE + "/segment") and \
                    D.dpdir(pieces[0]) in (N | S, E | W):
                goals.add(q)
        for attempt in range(6):
            path = path_to(bin_tile, goals)
            if not path:
                break
            if lay(path, True, "join", end):
                break
            goals.discard(path[-1])
            # undo the spur we just laid
            for q in path[:-1]:
                m.get(*q).objs = [o for o in m.get(*q).objs if not o.path.startswith(D.PIPE)]
                used.discard(q)
            used.add(bin_tile)
        else:
            path = None
        if not path:
            probs.append("disposals: could not join the bin at %d,%d to the %s line" % (*bin_tile, dest))
    # 3. prove it: every bin flows where it was sent
    for bin_tile, dest in requests:
        tr = [o for o in m.get(*bin_tile).objs if o.path.startswith(D.PIPE + "/trunk")]
        if not tr:
            continue
        fl = D.flow(m, bin_tile, tr[0].num("dir", 2))
        end = fl[-1][0]
        want = dest[1] if isinstance(dest, tuple) else named.get(dest, dest)
        if end != want:
            probs.append("disposals: trash from the bin at %d,%d ends at %d,%d, not %d,%d" % (*bin_tile, *end, *want))
    notes.append("disposals: kept %d line tiles, routed %d bins" % (len(keep), len(requests)))
    return notes, probs
