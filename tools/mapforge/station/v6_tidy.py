"""Wall-piece tidy for the v6 station (v6_station.py runs it after habits, before disposals): the three faults
studies/piece_audit.py counts and the gate holds to the accepted baseline, fixed wherever they are.

    over furniture   a wall piece over a tile that holds furniture (rule: wall pieces prefer bare tiles)
    stacked          two wall pieces on one floor tile (ruling 2026-11-16: one piece per wall face)
    both faces       one wall tile drawn on from both sides

The copied stock rooms (station/v6_rooms.py) bring the stock maps' own habit of hanging pieces over desks and
lockers (the gate after the room budget, 2026-11-22: over furniture 213 against the baseline 160). A piece in fault
slides along the same wall, in the same area, to the nearest face whose floor is bare, holds no other piece, and
whose wall tile nothing hangs on from the other side. Its vars stay as they are (it hangs on the same side). APCs
never move (the power pass has already cabled them); a sink-and-mirror or button pair counts as one piece. A piece
with no free face within 6 tiles stays where it is.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "studies"))
from forge import kit  # noqa: E402
import piece_audit as PA  # noqa: E402

FIXED = ("/obj/machinery/power/apc",)
REACH = 6


SIDE = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}


def turned(h, off, new):
    """The piece hung on another wall: a pixel-shifted piece keeps its distance from the tile's centre on the new
    axis; a light's dir is its wall, a camera's the opposite (kit.MOUNT)."""
    from forge import dmm
    vs = [(k, v) for k, v in h.vars if k not in ("pixel_x", "pixel_y", "dir")]
    px, py = h.num("pixel_x"), h.num("pixel_y")
    if abs(px) >= 16 or abs(py) >= 16:
        mag = max(abs(px), abs(py))
        if new[0]:
            vs.append(("pixel_x", str(mag * new[0])))
        else:
            vs.append(("pixel_y", str(mag * new[1])))
        if h.get("dir") is not None:
            vs.append(("dir", h.get("dir")))
    elif h.path.startswith("/obj/machinery/camera"):
        vs.append(("dir", str({1: 2, 2: 1, 4: 8, 8: 4}[SIDE[new]])))
    else:
        vs.append(("dir", str(SIDE[new])))
    return dmm.Atom(h.path, vs)


def accepted_areas():
    """Areas of the accepted build (v6_gate.ACCEPTED): rooms the user has already accepted are left as they are (the
    gate's ablation 2026-11-22: tidying them dropped lights and pieces below their stock band in 12 rooms)."""
    from forge import dmm
    from station.v6_gate import ACCEPTED
    m = dmm.read(ACCEPTED)
    return {t.apath for t in m.tiles.values()} - {a for a in (t.apath for t in m.tiles.values())
                                                     if a.startswith(("/area/hallway", "/area/maintenance"))}


_ACC_FAULTS = []


def accepted_fault_tiles():
    """Tiles that were wall-piece faults in the accepted build already (over furniture or stacked): left as the user
    accepted them. Every other fault is new and fixed wherever it is (2026-11-22: scoping by area had left the faults
    in rooms a redraw changed, storage/tools, the RD's office, the dorms restroom)."""
    if not _ACC_FAULTS:
        from forge import dmm
        from station.v6_gate import ACCEPTED
        ma = dmm.read(ACCEPTED)
        out = set()
        for (x, y, z), t in ma.tiles.items():
            hs = PA.hung(t)
            if not hs:
                continue
            real = [h for h, _ in hs if not h.path.startswith(PA.PAIRS)]
            if len(real) >= 2 or any(o.path.startswith(PA.FURN) or (kit.dense([o]) and not o.path.startswith("/obj/machinery/door"))
                                     for o in t.objs if all(o is not h for h, _ in hs)):
                out.add((x, y))
        _ACC_FAULTS.append(out)
    return _ACC_FAULTS[0]


def tidy(m, log):
    keep = accepted_areas()
    old_faults = accepted_fault_tiles()
    def furn(t):
        return any(o.path.startswith(PA.FURN) or (kit.dense([o]) and not o.path.startswith("/obj/machinery/door"))
                   for o in t.objs if not any(o is h for h, _ in PA.hung(t)))

    def walls_use():
        use = {}
        for (x, y, z), t in m.tiles.items():
            if not t.tpath.startswith("/turf/open"):
                continue
            for h, (dx, dy) in PA.hung(t):
                use.setdefault((x + dx, y + dy), set()).add((x, y))
        return use

    from station.v6_station import regions
    region_of, region_tiles = {}, []
    for i, g in enumerate(regions(m)):
        region_tiles.append(sorted(g))
        for p in g:
            region_of[p] = i
    moved = dropped_none = dropped = 0
    for _ in range(2):
        use = walls_use()
        for (x, y, z), t in sorted(m.tiles.items()):
            if not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
                continue
            # a fault the accepted build already had is moved when its room has a clean face (never dropped): the
            # gate counts faults station-wide, and a piece moved within its room keeps the room's numbers
            was_fault = (x, y) in old_faults
            hs = PA.hung(t)
            if not hs:
                continue
            real = [(h, off) for h, off in hs if not h.path.startswith(PA.PAIRS)]
            bad = []
            if furn(t):
                # over furniture every piece is a fault, a mirror or button too (a pair only counts as one for
                # stacking: copied maint rooms brought mirrors over tables, 2026-11-22)
                bad = [(h, off) for h, off in hs if not (h.path.startswith("/obj/structure/sink"))]
            elif len(real) >= 2:
                bad = real[1:]
            # both faces only in rooms the accepted build didn't have: its own both-face walls are as accepted
            for h, off in real:
                w = (x + off[0], y + off[1])
                if t.apath not in keep and len(use.get(w, ())) >= 2 and (h, off) not in bad:
                    bad.append((h, off))
            for h, off in bad:
                if h.path.startswith(FIXED):
                    continue
                best = None
                # any tile of the piece's own room (it was REACH tiles round it: the copied rooms had no clean face
                # that near, and 150 pieces stayed in their faults)
                here = region_tiles[region_of[(x, y)]] if (x, y) in region_of else []
                for (qx, qy) in here:
                    if True:
                        q = (qx, qy)
                        tq = m.get(qx, qy)
                        if q == (x, y) or tq is None or tq.apath != t.apath or not tq.tpath.startswith("/turf/open") \
                                or region_of.get(q) != region_of.get((x, y)) \
                                or tq.has("/obj/machinery/door") or PA.hung(tq) or furn(tq):
                            continue
                        w = (qx + off[0], qy + off[1])
                        tw = m.get(*w)
                        if tw is None or not tw.tpath.startswith("/turf/closed") or tw.has("/obj/machinery/door") or use.get(w):
                            continue
                        k = (abs(qx - x) + abs(qy - y), q)
                        if best is None or k < best[0]:
                            best = (k, q, w)
                newh = h
                if best is None:
                    # no clean face on that side: any wall of the room, the piece turned to hang on it
                    for (qx, qy) in here:
                        if True:
                            q = (qx, qy)
                            tq = m.get(qx, qy)
                            if q == (x, y) or tq is None or tq.apath != t.apath or not tq.tpath.startswith("/turf/open")                                     or region_of.get(q) != region_of.get((x, y))                                     or tq.has("/obj/machinery/door") or PA.hung(tq) or furn(tq):
                                continue
                            for o2 in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                                w = (qx + o2[0], qy + o2[1])
                                tw = m.get(*w)
                                if tw is None or not tw.tpath.startswith("/turf/closed") or tw.has("/obj/machinery/door")                                         or use.get(w):
                                    continue
                                k = (abs(qx - x) + abs(qy - y), q, o2)
                                if best is None or k < best[0]:
                                    best = (k, q, w)
                    if best is None and len(real) >= 2 and not furn(t):
                        # a pile with no bare face left: a face over furniture with no piece of its own. One piece per
                        # wall face is the user's ruling (2026-11-16, sprites fighting for a spot); a bare tile under
                        # a piece is the softer preference the stock maps break all the time (the gate 2026-11-22:
                        # cameras piled with alarms in the small copied rooms, every stock room of their types has one)
                        for (qx, qy) in here:
                            q = (qx, qy)
                            tq = m.get(qx, qy)
                            if q == (x, y) or tq is None or tq.apath != t.apath or not tq.tpath.startswith("/turf/open") \
                                    or tq.has("/obj/machinery/door") or PA.hung(tq):
                                continue
                            for o2 in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                                w = (qx + o2[0], qy + o2[1])
                                tw = m.get(*w)
                                if tw is None or not tw.tpath.startswith("/turf/closed") or tw.has("/obj/machinery/door") \
                                        or use.get(w):
                                    continue
                                k = (abs(qx - x) + abs(qy - y), q, o2)
                                if best is None or k < best[0]:
                                    best = (k, q, w)
                        if best is not None:
                            newh = turned(h, off, best[0][2])
                    if best is None:
                        # still nowhere: the ruling beats the stock habit for a pile (stacked), so the less needed
                        # piece goes: decoration always, a camera, light or intercom when its area keeps another
                        if not was_fault and t.apath not in keep and len(real) >= 2 and droppable(m, t.apath, h, (x, y)):
                            t.objs = [o for o in t.objs if o is not h]
                            dropped += 1
                            real = [r for r in real if r[0] is not h]
                        else:
                            dropped_none += 1
                        continue
                    newh = turned(h, off, best[0][2])
                _, q, w = best
                t.objs = [o for o in t.objs if o is not h]
                m.get(*q).objs.append(newh)
                use.setdefault(w, set()).add(q)
                old = (x + off[0], y + off[1])
                if old in use:
                    use[old].discard((x, y))
                moved += 1
    # a room the accepted build didn't have, hanging more pieces per wall face than any stock room of its type, sheds
    # decoration until it fits (the gate 2026-11-22: the copied gateway at 0.59 against the stock 0.26-0.43)
    from forge import room_stats as RS
    from forge import parse
    shed = 0
    # by the stock-room measure's own rooms (pieces within 2 tiles are one room): the copied gateway's two intercoms
    # sat in two door-split regions, each under the band on its own
    for rm in RS.rooms(parse.SemanticMap(m, "v6")):
        a, g = rm.area, rm.tiles
        if a in keep or a.startswith(("/area/hallway", "/area/maintenance")):
            continue
        kind = RS.type_of(a)
        peers = RS.peers(kind) if kind else []
        if len(peers) < 3:
            continue
        hi = max(p.stats["pieces"] for p in peers)
        while True:
            pieces, faces = RS.map_pieces(m, g)
            if pieces / float(max(1, faces)) <= hi:
                break
            dec = next(((q, o) for q in sorted(g) for o in m.get(*q).objs if o.path.startswith(DECOR)), None)
            if dec is None:
                # then a second intercom or camera (the copied gateway carried two intercoms)
                dec = next(((q, o) for q in sorted(g) for o in m.get(*q).objs if o.path.startswith(SPARE) and
                            sum(1 for q2 in g for o2 in m.get(*q2).objs if o2.path.startswith(SPARE) and
                                o2.path.split("/")[3] == o.path.split("/")[3]) >= 2), None)
            if dec is None:
                break
            m.get(*dec[0]).objs.remove(dec[1])
            shed += 1
    log("tidy: %d wall pieces moved to a clean face, %d dropped from piles, %d with no clean face left where they were, "
        "%d decorations shed from new rooms over their stock band" % (moved, dropped, dropped_none, shed))


DECOR = ("/obj/structure/sign", "/obj/machinery/newscaster", "/obj/machinery/status_display")
SPARE = ("/obj/machinery/camera", "/obj/item/radio/intercom")     # never a light: it is the room's light


def droppable(m, area, h, at):
    if h.path.startswith(DECOR):
        return True
    kind = next((k for k in SPARE if h.path.startswith(k)), None)
    if not kind:
        return False
    return any(o.path.startswith(kind) and o is not h for (x, y, z), t in m.tiles.items() if t.apath == area
               for o in t.objs)
