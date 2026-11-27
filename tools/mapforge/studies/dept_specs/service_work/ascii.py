"""ASCII view of a map crop (north up) for reading layouts exactly: two characters a tile.

    python tools/mapforge/studies/dept_specs/service_work/ascii.py <dmm> x0 y0 x1 y1

First char: the area's letter (legend printed), '#' wall, ' ' space. Second char: what stands there:
D airlock, C counter (table + windoor), H hatch (table + shutters/firelock), W windoor, g glass, F produce
smartfridge, f other smartfridge, T tray, V vendor, M machine, L locker/closet, t table, c chair, b bed, s sink,
S shower, o toilet, = other dense structure, i item, . bare floor.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import dmm  # noqa: E402

SKIP = ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
        "/obj/item/radio/intercom", "/obj/machinery/newscaster", "/obj/machinery/camera", "/obj/structure/cable",
        "/obj/machinery/atmospherics", "/obj/structure/disposalpipe", "/obj/effect", "/obj/machinery/door/firedoor",
        "/obj/machinery/light_switch", "/obj/machinery/status_display", "/obj/machinery/ai_status_display",
        "/obj/machinery/navbeacon", "/obj/machinery/holopad", "/obj/structure/lattice", "/obj/machinery/power/terminal",
        "/obj/structure/sign", "/obj/structure/extinguisher_cabinet", "/obj/machinery/requests_console",
        "/obj/structure/noticeboard", "/obj/machinery/button", "/obj/docking_port")


def code(t):
    if t.has("/obj/machinery/door/airlock"):
        return "D"
    if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
        return "C"
    if t.has("/obj/structure/table") and t.has("/obj/machinery/door/poddoor/shutters"):
        return "H"
    if t.has("/obj/machinery/door/window"):
        return "W"
    if any(o.path == "/obj/machinery/smartfridge" for o in t.objs):
        return "F"
    if t.has("/obj/machinery/smartfridge"):
        return "f"
    if t.has("/obj/structure/window") or t.has("/obj/effect/spawner/structure/window"):
        return "g"
    objs = [o.path for o in t.objs if not o.path.startswith(SKIP)]
    for pre, c in (("/obj/machinery/hydroponics", "T"), ("/obj/machinery/vending", "V"), ("/obj/machinery/shower", "S"),
                   ("/obj/structure/toilet", "o"), ("/obj/structure/sink", "s"), ("/obj/structure/closet", "L"),
                   ("/obj/structure/bed", "b"), ("/obj/structure/table", "t"), ("/obj/structure/chair", "c"),
                   ("/obj/machinery", "M"), ("/obj/structure", "=")):
        if any(p.startswith(pre) for p in objs):
            return c
    if objs:
        return "i"
    return "."


def show(m, x0, y0, x1, y1, out=print):
    letters = {}
    nxt = iter("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    rows = []
    for y in range(y1, y0 - 1, -1):
        row = ["%3d " % y]
        for x in range(x0, x1 + 1):
            t = m.get(x, y)
            if t is None or t.tpath.startswith("/turf/open/space") or t.apath.startswith("/area/space"):
                row.append("  ")
                continue
            if t.apath not in letters:
                letters[t.apath] = next(nxt, "?")
            a = letters[t.apath]
            if t.tpath.startswith("/turf/closed") and code(t) not in "FfDCHW":
                row.append("##")
                continue
            row.append(a + code(t))
        rows.append("".join(row))
    head = "    " + "".join(("%-2d" % (x % 100)) if x % 5 == 0 else "  " for x in range(x0, x1 + 1))
    out(head)
    for r in rows:
        out(r)
    out(head)
    for a, l in sorted(letters.items(), key=lambda kv: kv[1]):
        out("  %s = %s" % (l, a))


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    show(m, *[int(v) for v in sys.argv[2:6]])
