"""Geo -> a mapforge blueprint (the attributes forge.build reads), so the generated department gets the builder's
pipes, cable, lights, wall pieces, dressing and checks like a hand-drawn one."""
from .geo import OPP, NAME

ROOMDEF_KEYS = ("area", "floor", "name", "main", "vents", "apc", "bare", "dress", "lights", "trim", "camera",
                "light_switch", "extinguisher", "newscaster", "plant", "table_items", "auto_trim")
PASS_KEYS = ("dest", "outlet", "throw", "no_vent", "face", "face_obj", "firedoor", "turf")
FD = "/obj/machinery/door/firedoor"


def door_objs(dr):
    """The pieces of a generated door, from what the link asked for."""
    sp = dr["spec"]
    d = dr["dir"]            # toward room a
    kind = sp.get("type", "airlock")
    acc = {}
    if sp.get("access"):
        acc["req_access_txt"] = sp["access"]
    if sp.get("one_access"):
        acc["req_one_access_txt"] = sp["one_access"]
    if kind == "airlock":
        vs = dict(name=sp.get("name", "Airlock"), **acc)
        vs.update(sp.get("vars", {}))           # id_tag for a door a button works, and the like
        path = "/obj/machinery/door/airlock/%s%s" % (sp.get("kind", "research"), "/glass" if sp.get("glass") else "")
        return [(path, vs)] + ([FD] if sp.get("firedoor") else []) + list(sp.get("extra", ()))
    if kind == "shutter":
        return [("/obj/machinery/door/poddoor/shutters/preopen", {"name": sp.get("name", "shutters"), "id": sp["id"]}), FD]
    if kind == "driver":    # the mass driver's blast door out to space
        return [("/obj/machinery/door/poddoor", {"name": sp.get("name", "Mass Driver Door"), "id": sp["id"]})]
    if kind == "biohazard":
        return [("/obj/machinery/door/poddoor/preopen/biohazard", {"id": sp["id"]}), "/obj/machinery/door/firedoor/heavy"]
    if kind == "desk":
        return ["/obj/structure/table/reinforced",
                ("/obj/machinery/door/window/southleft", dict(name=sp.get("name", "Desk"), dir=OPP[d], **acc)),
                ("/obj/machinery/door/poddoor/shutters/preopen", {"name": "%s shutters" % sp.get("name", "desk").lower(),
                                                                  "id": sp["id"]})]
    extra = list(sp.get("extra", ()))
    if kind == "blast":     # a glass airlock with a blast door over it
        vs = dict(name=sp.get("name", "Test Chamber"), **acc)
        vs.update(sp.get("vars", {}))
        return [("/obj/machinery/door/airlock/%s/glass" % sp.get("kind", "research"), vs),
                ("/obj/machinery/door/poddoor/preopen", {"name": "%s blast door" % sp.get("name", "chamber").lower(),
                                                         "id": sp["id"]})] + extra
    if kind == "pen":       # a windoor on the pen's side with a containment blast door
        return [("/obj/machinery/door/window/southleft", dict(name=sp.get("name", "Containment Pen"), dir=d, **acc)),
                ("/obj/machinery/door/poddoor/preopen/biohazard", {"id": sp["id"]})]
    if kind == "windoor":
        return [("/obj/machinery/door/window/southleft", dict(name=sp.get("name", "Windoor"), dir=OPP[d], **acc))]
    if kind == "cell":      # a brig cell: a secure windoor the cell's door timer (same id) opens and shuts
        return [("/obj/machinery/door/window/brigdoor/security/cell", dict(name=sp.get("name", "Cell"), id=sp["id"],
                                                                           dir=OPP[d]))]
    if kind == "brigdesk":  # a desk the public are served over: reinforced table, secure windoor, shutters
        return ["/obj/structure/table/reinforced",
                ("/obj/machinery/door/window/brigdoor", dict(name=sp.get("name", "Desk"), dir=OPP[d], **acc)),
                ("/obj/machinery/door/poddoor/shutters/preopen", {"name": "%s shutters" % sp.get("name", "desk").lower(),
                                                                  "id": sp["id"]})]
    if kind == "flaps":     # a loading lane through the wall: blast door, plastic flaps, the belt running through
        flow = d if sp.get("flow", "in") == "in" else OPP[d]
        return [("/obj/machinery/door/poddoor", {"name": sp.get("name", "loading door"), "id": sp["id"]}),
                "/obj/structure/plasticflaps", ("/obj/machinery/conveyor", {"dir": flow, "id": sp["belt"]})]
    if kind == "smartfridge":   # a smartfridge set into the wall, loaded and emptied from both sides
        return [("/obj/machinery/smartfridge", {})]
    if kind == "orm":       # an ore redemption machine set into the wall: input on its north side, output south
        return [("/obj/machinery/mineral/ore_redemption", {})]
    raise ValueError("unknown door type %r" % kind)


def blueprint(geo, name, extra=None):
    """A dict of blueprint attributes: NAME, ORIGIN, LAYOUT, ROOMS, ROOMDEFS, LEGEND, FOOTPRINT ..."""
    x0, y0, x1, y1 = geo.bounds()
    pool = [chr(c) for c in range(0x100, 0x3000)]
    legend, specs = {"%": {"turf": "rwindow"}}, {}
    letters = {}
    roomdefs = {}
    for i, rid in enumerate(sorted(geo.rooms)):
        ch = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"[i]
        letters[rid] = ch
        roomdefs[ch] = {k: v for k, v in geo.rooms[rid].attrs.items() if k in ROOMDEF_KEYS}

    def char(sp):
        key = repr(sp)
        if key not in specs:
            specs[key] = pool.pop(0)
            legend[specs[key]] = sp
        return specs[key]

    lay, room = {}, {}
    for p in geo.zone:
        k = geo.kind[p]
        if k.startswith("keep_"):
            continue
        if k in ("wall", "ring"):
            # a sign an asset hung on the wall turf itself (a door sign on the hall face): the builder rehangs it
            objs = [o for c in geo.cells.get(p, []) for o in c.get("obj", [])]
            floor = next((c["floor"] for c in geo.cells.get(p, []) if c.get("floor")), None)
            # ... or a cut through it: an asset giving the wall tile a floor (a window onto a stamp's room)
            lay[p] = char({"floor": floor, "obj": objs}) if floor else char({"turf": "wall", "obj": objs}) if objs else "#"
        elif k == "glass":
            sid = geo.attr.get("_shutter", {}).get(p)
            brig = "gate" in sid.lower() or "cell" in sid.lower() if sid else False
            lay[p] = char({"turf": "rwindow", "obj": [("/obj/machinery/door/poddoor/preopen", {"id": sid, "name": "brig shutters"})
                                                       if brig else ("/obj/machinery/door/poddoor/shutters/preopen",
                                                                     {"id": sid, "name": "privacy shutters"})]}) \
                if sid else "%"
        elif k == "raw":
            rid, spec, _ = geo.raw[p]
            lay[p] = char(spec)
            room[p] = letters[rid]
        elif k == "door":
            dr = geo.doors[p]
            lay[p] = char({"obj": door_objs(dr)})
            a = dr["a"] if dr["a"] in letters else dr["b"]
            room[p] = letters[a]
        else:
            room[p] = letters[geo.room[p]]
            cells = geo.cells.get(p)
            if not cells:
                lay[p] = "."
                continue
            sp = {"obj": []}
            for c in cells:
                sp["obj"] += c.get("obj", [])
                if c.get("decal"):
                    sp["decal"] = sp.get("decal", []) + list(c["decal"])
                if c.get("mount"):
                    # each piece keeps its own wall: a corner tile can carry a cell timer on one wall and a poster
                    # on the other (one shared mount_side moved the timer onto the poster's wall)
                    side = c.get("mount_side")
                    sp["mount"] = sp.get("mount", []) + [tuple(m[:3]) + (side,) if side and len(m) == 3 else m
                                                         for m in c["mount"]]
                    sp["mount_side"] = c.get("mount_side", sp.get("mount_side"))
                if c.get("floor"):
                    sp["floor"] = c["floor"]
                for key in PASS_KEYS:
                    if key in c:
                        sp[key] = c[key]
            lay[p] = char(sp)
    bp = dict(
        NAME=name, ORIGIN=(x0, y0), LEGEND=legend, ROOMDEFS=roomdefs, THIN_WALLS=False,
        LAYOUT="\n".join("".join(lay.get((x, y), "~") for x in range(x0, x1 + 1)) for y in range(y1, y0 - 1, -1)),
        ROOMS="\n".join("".join(room.get((x, y), "~") for x in range(x0, x1 + 1)) for y in range(y1, y0 - 1, -1)),
        FOOTPRINT=sorted({geo.base.get(*p).apath for p in geo.zone}),
    )
    bp.update(extra or {})
    return bp
