"""Icon smoothing done the game's way, for renders.

Hippie keeps smoothing groups as strings ("-34,12,"), which dmm-tools' smoothing pass doesn't read, so it only joins
atoms of the very same type (a table never joins a reinforced table, a window never joins a reinforced window).
prepare() does what SSicon_smooth does at roundstart (code/__HELPERS/icon_smoothing.dm bitmask_smooth): expands
window spawners, then gives every smoothing atom icon_state "<base_icon_state>-<junction>", diagonals only with both
cardinals, object groups only against anchored objects, area_limited_icon_smoothing respected. The render then runs
with dmm-tools' own smoothing off.

Data comes from data/mapforge/smoothing.txt (tools/mapforge/smooth_dump.sh).
"""
import os

from forge import dmm

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DATA = os.path.join(ROOT, "data", "mapforge", "smoothing.txt")
N, S, E, W, NE, SE, SW, NW = 1, 2, 4, 8, 16, 32, 64, 128
STEPS = {N: (0, 1), S: (0, -1), E: (1, 0), W: (-1, 0), NE: (1, 1), SE: (1, -1), SW: (-1, -1), NW: (-1, 1)}
DIAG = {N | W, N | E, S | W, S | E, N | W | NW, N | E | NE, S | W | SW, S | E | SE}
F_BITMASK, F_CARDINALS, F_DIAGONAL, F_BORDER = 1, 2, 4, 8

_data = None


def load():
    global _data
    if _data is None:
        types, areas, spawners, icons = {}, {}, {}, {}
        if not os.path.exists(DATA):
            raise RuntimeError("no %s: run tools/mapforge/smooth_dump.sh" % DATA)
        for line in open(DATA, encoding="utf-8", errors="replace"):
            f = line.rstrip("\n").split("\t")
            if f[0] == "A" and len(f) >= 8:
                types[f[1]] = {"flags": int(f[2] or 0), "base": f[3], "groups": set(g for g in f[4].split(",") if g),
                               "with": set(g for g in f[5].split(",") if g), "anchored": f[6] == "1", "unanch": f[7] == "1"}
            elif f[0] == "I" and len(f) >= 3 and f[2]:
                icons[f[1]] = f[2]
            elif f[0] == "R":
                areas[f[1]] = f[2]
            elif f[0] == "S" and len(f) >= 3:
                spawners[f[1]] = [p for p in f[2].split(",") if p]
        for p, ic in icons.items():
            if p in types:
                types[p]["icon"] = ic
        _data = (types, areas, spawners)
    return _data


def prepare(m):
    """Smooth map m in place (a dmm.Map). Returns how many atoms got a smoothed icon_state."""
    types, areas, spawners = load()
    # 1. window spawners -> what they spawn (other spawners are left to dmm-tools)
    for t in m.tiles.values():
        if not any(o.path in spawners and o.path.startswith("/obj/effect/spawner/structure/window") for o in t.objs):
            continue
        objs = []
        for o in t.objs:
            if o.path in spawners and o.path.startswith("/obj/effect/spawner/structure/window"):
                objs += [dmm.Atom(p) for p in spawners[o.path]]
            else:
                objs.append(o)
        t.objs = objs

    def is_anchored(o):
        v = o.get("anchored")
        if v is not None:
            return v.strip() not in ("0", "FALSE", "null")
        return types[o.path]["anchored"]

    def area_ok(home, other):
        lim = areas.get(home)
        if lim and not (other == lim or other.startswith(lim + "/")):
            return False
        lim2 = areas.get(other)
        if lim2 and not (home == lim2 or home.startswith(lim2 + "/")):
            return False
        return True

    count = 0
    for (x, y, z), t in m.tiles.items():
        atoms = ([t.turf] if t.turf is not None and t.turf.path in types else []) + [o for o in t.objs if o.path in types]
        for a in atoms:
            info = types[a.path]
            if not (info["flags"] & F_BITMASK):
                continue
            if a is not t.turf and info["unanch"] and not is_anchored(a):
                junction = 0
            else:
                want = info["with"]
                smooth_obj = any(g.startswith("-") for g in want)

                def joins(d):
                    dx, dy = STEPS[d]
                    nt = m.tiles.get((x + dx, y + dy, z))
                    if nt is None:
                        return bool(info["flags"] & F_BORDER)
                    if not area_ok(t.apath, nt.apath):
                        return False
                    if nt.turf is not None and nt.turf.path in types and want & types[nt.turf.path]["groups"]:
                        return True
                    if smooth_obj:
                        for o in nt.objs:
                            if o.path in types and want & types[o.path]["groups"] and is_anchored(o):
                                return True
                    return False
                junction = sum(d for d in (N, S, E, W) if joins(d))
                if not (info["flags"] & F_CARDINALS) and junction & (N | S) and junction & (E | W):
                    for diag, need in ((NW, N | W), (NE, N | E), (SW, S | W), (SE, S | E)):
                        if junction & need == need and joins(diag):
                            junction |= diag
            state = "%s-%d" % (info["base"], junction)
            if a is t.turf and info["flags"] & F_DIAGONAL and junction in DIAG:
                state += "-diagonal"
            a.vars = [(k, v) for k, v in a.vars if k not in ("icon_state", "icon")] + [("icon_state", '"%s"' % state)]
            if info.get("icon"):
                a.vars.append(("icon", "'%s'" % info["icon"]))
            count += 1
    return count
