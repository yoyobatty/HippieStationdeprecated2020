"""The rooms' wall fixtures at the stock maps' coverage: an air alarm in every room, a fire alarm, a light switch and an
extinguisher cabinet in as many rooms as the stock maps have them, hung on a free wall face of the room at the stock
distance from its door (median 2-3 tiles), never two pieces on one wall face.

    python tools/mapforge/gen/learn/fixtures.py <dmm> [out.dmm]
    from gen.learn import fixtures; fixtures.fix(m, seed, log)    # build.py: before the networks (alarms want power)

crew 100 seed 7 f14, rooms of 15+ tiles with one: fire alarm 49% (stock 58-86%), light switch 52% (70-86%), extinguisher
22% (30-66%), air alarm 90% (96-100%); f22 camera 6% (stock 88-96%).
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "station"))
from forge import corpus as CO, dmm, kit  # noqa: E402
import placestudy as PS  # noqa: E402

N4 = PS.N4
SIDE = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}
# (kind for kit.MOUNT, path prefix to look for, share of rooms of 15+ tiles that have one: the stock maps' median,
# the door distance it hangs at)
WANT = (("airalarm", "/obj/machinery/airalarm", 1.0, 3), ("firealarm", "/obj/machinery/firealarm", 0.75, 3),
        ("light_switch", "/obj/machinery/light_switch", 0.75, 2), ("extinguisher", "/obj/structure/extinguisher_cabinet", 0.45, 3),
        # stock rooms of 15+ tiles with a camera: 88-96% (Hippie, Meta, Box, Delta); f22 6%: the AI saw nothing, and
        # the slime console acts only where a camera sees (bots_ai bot_camera_sees: slimes 0 fed every Bot Shift)
        ("camera", "/obj/machinery/camera", 0.92, 4))
MIN_TILES = 15


def _faces(m, F, doors):
    """(tile, side) wall faces of the room with nothing hung on that tile and nothing hung on the wall from behind."""
    out = []
    hung_walls = set()
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if CO.mounted(o):
                d = CO.mount_side(o)
                v = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}.get(d)
                if v:
                    hung_walls.add((x + v[0], y + v[1]))
    for p in F:
        t = m.get(*p)
        if any(CO.mounted(o) or o.path.startswith(("/obj/machinery/light", "/obj/machinery/power/apc")) for o in t.objs):
            continue
        if PS._door(t):
            continue
        for v, d in SIDE.items():
            w = (p[0] + v[0], p[1] + v[1])
            tw = m.get(*w)
            if tw is None or not tw.tpath.startswith("/turf/closed/wall") or tw.objs or w in hung_walls or w in doors:
                continue
            out.append((p, d))
    return out


def fix(m, seed=1, log=print):
    import v6_station as V6
    r = random.Random("fixtures|%s" % seed)
    by_area = {}
    for area, F in PS.pieces_of(m):
        if area in PS.CORRIDOR_AREAS:
            continue
        by_area.setdefault(area, []).append(F)
    added = {}
    cams = {}
    for area, pieces in sorted(by_area.items()):
        F = max(pieces, key=len)
        if sum(len(p) for p in pieces) < MIN_TILES:
            continue
        all_tiles = set().union(*pieces)
        doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))}
        if not doors:
            continue
        for kind, path, share, dist in WANT:
            if any(o.path.startswith(path) for p in all_tiles for o in m.get(*p).objs):
                continue
            if r.random() > share:
                continue
            faces = _faces(m, F, doors)
            if not faces:
                continue
            p, d = min(faces, key=lambda f: (abs(min(abs(f[0][0] - q[0]) + abs(f[0][1] - q[1]) for q in doors) - dist),
                                             r.random()))
            extra = ()
            if kind == "camera":
                import doordb as DD
                n_ = cams.get(area, 0) + 1
                cams[area] = n_
                extra = (("c_tag", '"%s%s"' % (DD.name_for(area), " %d" % n_ if n_ > 1 else "")),)
            V6.mount(m, p, d, kind, extra)
            added[kind] = added.get(kind, 0) + 1
    log("fixtures: %s hung where rooms lacked them (stock coverage)" % (
        ", ".join("%s %d" % kv for kv in sorted(added.items())) or "none"))
    return sum(added.values())


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    fix(m)
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])
