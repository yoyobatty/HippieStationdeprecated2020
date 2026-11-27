"""Text picture of a map region for reviewing a department: one character a tile, rooms told apart by letter, doors
and the safety/work kit by symbol, coordinates on the edges.

    python tools/mapforge/studies/dept_specs/engineering_work/ascii.py <dmm> x0 y0 x1 y1

Legend: '#' wall, 'o' window, '+' airlock, '/' windoor, '=' blast door/shutter, ' ' space, lowercase letter: floor of
a room (the key printed under the picture), uppercase/symbols: kit (KEY below), '*' other dense thing.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import engstudy as ES  # noqa: E402
from forge import corpus as CO, dmm, function as FN  # noqa: E402

KEY = [("shower", "S"), ("rad_closet", "R"), ("fire_closet", "F"), ("em_closet", "E"), ("eng_locker", "L"),
       ("elec_locker", "L"), ("weld_locker", "L"), ("ce_locker", "C"), ("atmos_locker", "L"), ("tool_closet", "T"),
       ("sus_engine", "U"), ("sus_ce", "U"), ("sus_atmos", "U"), ("sus_other", "U"), ("smes", "M"), ("terminal", "t"),
       ("grav", "G"), ("emitter", "X"), ("field_gen", "Q"), ("shieldgen", "q"), ("rad_collector", "K"), ("crystal", "@"),
       ("engivend", "V"), ("toolvend", "V"), ("engi_wardrobe", "V"), ("atmos_wardrobe", "V"), ("coffee", "v"),
       ("station_alert", "c"), ("atmos_alert", "c"), ("eng_modcon", "c"), ("power_mon", "c"), ("apc_ctrl", "c"),
       ("card_ce", "c"), ("rdconsole", "c"), ("atmos_ctrl", "c"), ("cam_console", "c"), ("lathe_eng", "P"),
       ("imprinter", "P"), ("tank_disp", "D"), ("fueltank", "f"), ("watertank", "w"), ("canister", "n"),
       ("port_gen", "g"), ("disposal", "d"), ("rack", "r"), ("table", "_"), ("pipe_disp", "p"), ("thermo", "h"),
       ("port_pump", "u"), ("port_scrub", "u"), ("heater", "u"), ("recharger", "_"), ("cell_charger", "_"),
       ("microwave", "_"), ("chair", "~"), ("bed", "b"), ("fireaxe", "A"), ("extinguisher", "x")]


def picture(m, box, z=1):
    x0, y0, x1, y1 = box
    rooms = ES.segment(m, scope=lambda a: bool(a) and not a.startswith("/area/space"))
    idx = ES.room_index(m, rooms)
    letters = {}
    names = "0123456789aeijklmosyzABHIJNOWYZ"
    label_at = {}
    for i, r in enumerate(rooms):
        free = [p for p in sorted(r["tiles"], key=lambda q: (-q[1], q[0]))
                if not any(ES.fam(o.path) or FN.is_dense(o) for o in m.get(*p).objs)]
        label_at[i] = (free or sorted(r["tiles"]))[0]
    lines = []
    for y in range(y1, y0 - 1, -1):
        row = []
        for x in range(x0, x1 + 1):
            t = m.get(x, y)
            ch = " "
            if t is None:
                ch = " "
            elif ES.is_door(t):
                a = ES.door_atom(t)
                ch = "/" if "/window" in a.path else ("=" if "poddoor" in a.path else "+")
            elif t.tpath.startswith("/turf/closed"):
                ch = "#"
            elif CO.solid(t):
                ch = "o"
            elif t.tpath.startswith("/turf/open/space"):
                ch = " "
            else:
                i = idx.get((x, y))
                if i is not None:
                    if i not in letters and x0 <= label_at[i][0] <= x1 and y0 <= label_at[i][1] <= y1:
                        letters[i] = names[len(letters) % len(names)]
                    ch = letters[i] if label_at.get(i) == (x, y) and i in letters else "."
                else:
                    ch = ","
                fams = [ES.fam(o.path) for o in t.objs if CO.mounted(o) is False]
                sym = None
                for f, s in KEY:
                    if f in fams and f != "extinguisher":
                        sym = s
                        break
                if sym:
                    ch = sym
                elif any(FN.is_dense(o) for o in t.objs):
                    ch = "*"
            row.append(ch)
        lines.append("%4d " % y + "".join(row))
    xs = "".join(str(x % 10) for x in range(x0, x1 + 1))
    tens = "".join((str((x // 10) % 10) if x % 10 == 0 else " ") for x in range(x0, x1 + 1))
    out = ["     " + tens, "     " + xs] + lines + ["     " + xs]
    seen = {}
    for i, l in letters.items():
        r = rooms[i]
        seen.setdefault(l, "%s %d t" % (r["area"].replace("/area/", ""), len(r["tiles"])))
    out.append("rooms: " + "; ".join("%s=%s" % kv for kv in sorted(seen.items())))
    out.append("kit: " + " ".join("%s=%s" % (s, f) for f, s in KEY))
    return "\n".join(out)


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    print(picture(m, tuple(int(v) for v in sys.argv[2:6])))
