"""Stages S4-S6 on a furnished build: the station-wide passes station/v6_station.py proved, run on a generated map
in v6's order (used read-only; nothing in station/ is changed).

    from gen import dress
    dress.dress(m, log)          # m: a furnished dmm.Map (gen/rooms.py), edited in place

Order and what each adds (v6_station.build):
  close_corners   walls meeting corner to corner round station floor closed
  layout          back doors into rooms with one or two ways in; table islands in big offices
  glaze           hull windows, hall windows into public rooms, glass between rooms of one department
  open_dead_ends  a maint door near each long maint stub
  shared          halls, maint and department corridors: APC, air alarm, lights (greedy cover), vents, scrubbers
  polish          hall firelock lines, direction and department signs, one piece per wall face, maint clutter,
                  hall edge trim in the colour of the department whose door is near
  pocket_fill     maint pockets under the stock furniture density get stock clutter
  plazas          benches, plants, vending along open hall walls
  details         items on tables and in closets, litter in halls and maint, spare starts, hall cameras
  bins            a disposal bin in bigger crew rooms
  fixtures        intercoms, newscasters, posters
  tidy, habits    wall-piece faults fixed; furniture, lights and wall pieces up to the room's stock peers
Not here yet (M3 networks): solars and docks (v6 places them by its plan's coordinates), power, air and disposals
(v6 routes from its own SMES, tank and engine tiles).
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "station"))

# v6's "layout" (back doors) is left out: the room stage already gives rooms their second doors, and with both the
# one-door share fell to 0.19 against the human 0.34-0.45 (full-stage set, 2026-11-22)
PASSES = ("close_corners", "glaze", "open_dead_ends", "carve_open_maint", "shared", "polish", "pocket_fill", "plazas",
          "details", "bins", "fixtures", "tidy", "habits", "bin_swap", "vents")


VENT = ("/obj/machinery/atmospherics/components/unary/vent_pump", "/obj/machinery/atmospherics/components/unary/vent_scrubber")


def vents_apart(m, log=print):
    """The user's rulings the gate checks: no vent or scrubber on a power terminal, never two on one tile, never two of
    a kind side by side outside the supermatter. Copied rooms bring their own vents and the shared pass adds more:
    the later one of a clash goes."""
    gone = 0
    kind = {}
    for (x, y, z), t in sorted(m.tiles.items()):
        vs = [o for o in t.objs if o.path.startswith(VENT)]
        if not vs:
            continue
        drop = []
        if t.has("/obj/machinery/power/terminal") or t.apath.startswith("/area/engine/supermatter"):
            if t.has("/obj/machinery/power/terminal"):
                drop = vs
        else:
            k = "V" if vs[0].path.startswith(VENT[0]) else "S"
            drop = vs[1:]
            if any(kind.get((x + dx, y + dy)) == k for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                drop = vs
            else:
                kind[(x, y)] = k
        if drop:
            t.objs = [o for o in t.objs if not any(o is d for d in drop)]
            gone += len(drop)
    log("dress: %d vents or scrubbers removed (on a terminal, stacked or side by side)" % gone)


def dress(m, log=print, skip=()):
    """Run the passes; each one's failure is logged and the rest go on (a pass written for v6's map may meet a shape
    it never saw). Returns {pass: seconds or 'error: ...'}."""
    from station import v6_station as V6
    import rooms as RM
    out = {}
    extra = tuple(RM.CORRIDOR_AREA.values())
    for name in PASSES:
        if name in skip or os.environ.get("GEN_SKIP_" + name.upper()):
            continue
        t0 = time.time()
        try:
            if name == "shared":
                V6.shared(m, log, extra)
            elif name == "tidy":
                from station.v6_tidy import tidy
                tidy(m, log)
            elif name == "habits":
                from station.v6_habits import habits
                habits(m, log)
            elif name == "open_dead_ends":
                V6.open_dead_ends(m, log)
            elif name == "carve_open_maint":
                from station import v6_rooms
                v6_rooms.carve_open_maint(m, log)
            elif name == "vents":
                vents_apart(m, log)
            else:
                getattr(V6, name)(m, log)
            out[name] = round(time.time() - t0, 1)
        except Exception as e:                       # noqa: BLE001 - logged and counted, the build goes on
            out[name] = "error: %s" % str(e)[:160]
            log("dress: %s failed: %s" % (name, out[name]))
    return out
