"""Wall-mounted things on a wall: APCs, air and fire alarms, lights, light switches, extinguisher cabinets, signs,
status displays, buttons... each hangs on one side of its tile (an APC by its path's /auto_name/<side>, a light by its
dir, the rest by their pixel offset), and that side must be a wall, a window or a door frame. The user 2026-11-26
("floating apc"): an /auto_name/west APC stood mid-room with floor to its west (a copied Delta maint room's, f46).

    python tools/mapforge/gen/mounts.py data/mapforge/gen_learn/f46_c100_s7.dmm      list the floating ones

floating(m) lists them; fix(m) hangs each on a wall side of its own tile, else moves it to the nearest tile of its
area with a free wall side (6 steps at most), else takes it out (an APC stays and is logged). A button or flasher on
a table is on its desk, not floating. Stock maps: Meta 27 floating of 2149 (buttons, signs), never an APC or alarm.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import corpus as CO, dmm  # noqa: E402

D = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
NAMES = {"north": 1, "south": 2, "east": 4, "west": 8}
SIDE_NAME = {v: k for k, v in NAMES.items()}
FACE = {1: 2, 2: 1, 4: 8, 8: 4}         # an alarm on the north wall faces south
FACING = ("/obj/machinery/airalarm", "/obj/machinery/firealarm")
APC = "/obj/machinery/power/apc"
LIGHT = "/obj/machinery/light"
NOT_WALL = ("/obj/machinery/holopad", "/obj/machinery/light/floor", "/obj/effect", "/obj/item")


def _light(o):
    """A wall light (tube or bulb; not a light switch, not a floor light)."""
    return (o.path == LIGHT or o.path.startswith(LIGHT + "/")) and not o.path.startswith(LIGHT + "/floor")


def side(o):
    """The side of its tile a mount hangs on, or None for a thing that isn't one."""
    if o.path.startswith(APC):
        last = o.path.rsplit("/", 1)[-1]
        if last in NAMES:
            return NAMES[last]
        return CO.mount_side(o) if CO.mounted(o) else (o.num("dir", 2) or 2)
    if o.path.startswith(NOT_WALL):
        return None
    if _light(o):
        return o.num("dir", 2) or 2
    if CO.mounted(o):
        return CO.mount_side(o)
    return None


def wallish(t):
    return t is not None and (t.tpath.startswith("/turf/closed") or any(a.path.startswith((
        "/obj/effect/spawner/structure/window", "/obj/structure/window", "/obj/structure/grille",
        "/obj/machinery/door")) for a in t.objs))


def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")


def floating(m):
    """[(x, y, obj, side)] of mounts with no wall on their side."""
    out = []
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not _floor(t) or t.has("/obj/structure/table"):
            continue
        for o in t.objs:
            s = side(o)
            if s is not None and not wallish(m.get(x + D[s][0], y + D[s][1])):
                out.append((x, y, o, s))
    return out


def rehang(o, s):
    """The mount hung on side s of its tile."""
    if o.path.startswith(APC):
        base = o.path.split("/auto_name")[0]
        o.path = base + "/auto_name/" + SIDE_NAME[s]
        o.vars = [kv for kv in o.vars if kv[0] not in ("dir", "pixel_x", "pixel_y")]
        return
    if _light(o):
        o.vars = [kv for kv in o.vars if kv[0] != "dir"] + ([("dir", str(s))] if s != 2 else [])
        return
    r = max(abs(o.num("pixel_x")), abs(o.num("pixel_y"))) or 24
    px, py = {1: (0, r), 2: (0, -r), 4: (r, 0), 8: (-r, 0)}[s]
    keep = [kv for kv in o.vars if kv[0] not in ("pixel_x", "pixel_y") and not (kv[0] == "dir" and o.path.startswith(FACING))]
    if o.path.startswith(FACING) and FACE[s] != 2:
        keep.append(("dir", str(FACE[s])))
    o.vars = keep + ([("pixel_x", str(px))] if px else []) + ([("pixel_y", str(py))] if py else [])


def _taken(m, p, s, o):
    """Another mount of the same kind already hangs on that wall face of tile p."""
    fam = o.path.split("/")[3] if o.path.count("/") >= 3 else o.path
    return any(a is not o and side(a) == s and (a.path.split("/")[3] if a.path.count("/") >= 3 else a.path) == fam
               for a in m.get(*p).objs)


def fix(m, log=print):
    moved = turned = gone = kept = 0
    for x, y, o, s in floating(m):
        t = m.get(x, y)
        if o not in t.objs:
            continue
        sides = [s2 for s2 in (1, 2, 4, 8) if wallish(m.get(x + D[s2][0], y + D[s2][1])) and not _taken(m, (x, y), s2, o)]
        if sides:
            rehang(o, sides[0])
            turned += 1
            continue
        # the nearest tile of its area with a free wall side
        area = t.apath
        seen, todo, spot = {(x, y)}, [((x, y), 0)], None
        while todo and spot is None:
            p, d = todo.pop(0)
            if d >= 6:
                continue
            for dx, dy in D.values():
                q = (p[0] + dx, p[1] + dy)
                tq = m.get(*q)
                if q in seen or not _floor(tq) or tq.apath != area or tq.has("/obj/machinery/door"):
                    continue
                seen.add(q)
                free = [s2 for s2 in (1, 2, 4, 8) if wallish(m.get(q[0] + D[s2][0], q[1] + D[s2][1]))
                        and not _taken(m, q, s2, o)]
                if free:
                    spot = (q, free[0])
                    break
                todo.append((q, d + 1))
        if spot is not None:
            t.objs = [a for a in t.objs if a is not o]
            rehang(o, spot[1])
            m.get(*spot[0]).objs.append(o)
            moved += 1
        elif o.path.startswith(APC):
            kept += 1
        else:
            t.objs = [a for a in t.objs if a is not o]
            gone += 1
    log("mounts: %d floating wall mounts hung on a wall of their tile, %d moved to one nearby, %d taken out%s" % (
        turned, moved, gone, (", %d APCs left with no wall near" % kept) if kept else ""))
    return turned + moved + gone


def bot_decals(m, log=print):
    """A loading-spot marking (turf_decal/bot) under a vent or scrubber is left from what stood there (a copied room's
    canisters): taken off (the user 2026-11-26 asked what the hazard boxes round a room's vents were). Returns how
    many."""
    n = 0
    for (x, y, z), t in m.tiles.items():
        if any(o.path.startswith(("/obj/machinery/atmospherics/components/unary/vent_pump",
                                  "/obj/machinery/atmospherics/components/unary/vent_scrubber")) for o in t.objs) \
                and t.has("/obj/effect/turf_decal/bot"):
            t.objs = [o for o in t.objs if not o.path.startswith("/obj/effect/turf_decal/bot")]
            n += 1
    if n:
        log("mounts: %d spot markings under vents and scrubbers taken off" % n)
    return n


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    for x, y, o, s in floating(m):
        print("%d,%d  %-50s side %s, no wall there" % (x, y, o.path, SIDE_NAME[s]))
