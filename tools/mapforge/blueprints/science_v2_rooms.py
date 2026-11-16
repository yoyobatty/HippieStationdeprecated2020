"""Room-by-room working layout for science_v2 (imported by science_v2.py after the shell is carved).

Every machine pair is placed where the game links it (verified in code, see tools/mapforge/studies/science.md):
fab -> faced tile, mech port -> faced tile + console in range 1, R&D console -> machines within 3 (oview),
operating computer -> adjacent optable, nanite console -> adjacent chamber, experimentor -> console within 3,
mass driver on row 104 aimed at the bomb range.
"""


def furnish(g):
    spec, objs, put, window, line = g["spec"], g["objs"], g["put"], g["window"], g["line"]
    TABLE, RTABLE, GTABLE = "/obj/structure/table", "/obj/structure/table/reinforced", "/obj/structure/table/glass"
    STRIPE = "/obj/effect/turf_decal/stripes/line"

    def stripe(d):
        return (STRIPE, {"dir": d}) if d != 2 else STRIPE

    def at(x, y, *o, r=None, decal=(), **kw):
        sp = dict(kw)
        sp["obj"] = list(o)
        if decal:
            sp["decal"] = list(decal)
        spec(x, y, sp, r)

    def wall_item(x, y, path, vars_, r=None, decal=()):
        """A wall piece with hand-set offsets (the builder's mount table doesn't know it)."""
        at(x, y, (path, vars_), r=r, decal=decal)

    # ================================================================ MECH BAY (x165-169, y117-126)
    # mechs come in through the wide shutter (x170, y121-123), park on a pad, leave by the launch shutters (y127)
    # a power console links the port exactly two tiles straight from it when the round starts (mech_bay.dm
    # reconnect(): range(1) has no usr at Initialize, so only the two-tile fallback works)
    PAD = "/turf/open/floor/mech_bay_recharge_floor"
    for py, cy in ((123, 125), (118, 120)):
        spec(165, py, {"floor": "/turf/open/floor/plating", "obj": [("/obj/machinery/mech_bay_recharge_port", {"dir": 4})]}, "B")
        spec(166, py, {"floor": PAD, "obj": []}, "B")
        spec(165, cy, {"floor": "/turf/open/floor/circuit", "obj": [("/obj/machinery/computer/mech_bay_power_console", {"dir": 4})]}, "B")
    at(169, 125, "/obj/machinery/recharge_station", r="B", decal=["/obj/effect/turf_decal/delivery"])
    at(169, 117, "/obj/machinery/recharge_station", r="B", decal=["/obj/effect/turf_decal/delivery"])
    at(165, 121, TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/crowbar/large", r="B")
    at(169, 124, "/obj/structure/reagent_dispensers/fueltank", r="B")
    for y in (124, 125, 126):  # launch lane to the hall shutters
        at(167, y, decal=[stripe(4), stripe(8)], r="B")
    wall_item(169, 126, "/obj/machinery/button/door", {"name": "Mech Bay Door Control", "id": "Skynet_launch",
                                                       "req_access_txt": "29", "pixel_x": 24}, r="B")
    wall_item(169, 119, "/obj/machinery/button/door", {"name": "Robotics Shutters", "id": "robo_mechbay",
                                                       "req_access_txt": "29", "pixel_x": 24}, r="B")

    # ================================================================ ROBOTICS (x171-178, y117-125)
    # back row: imprinter + its console, vendors, paperwork, cell charging
    at(171, 126, "/obj/machinery/rnd/production/circuit_imprinter", r="R")
    at(172, 126, ("/obj/machinery/computer/rdconsole/robotics", {"dir": 2}), r="R")
    at(173, 126, "/obj/machinery/vending/robotics", r="R")
    at(171, 124, "/obj/machinery/vending/wardrobe/robo_wardrobe", r="R")
    at(177, 125, TABLE, ("/obj/item/paper_bin", {"pixel_x": -3, "pixel_y": 7}), "/obj/item/pen",
       ("/obj/item/book/manual/wiki/robotics_cyborgs", {"pixel_x": 2, "pixel_y": 5}), r="R")
    at(178, 125, TABLE, ("/obj/machinery/cell_charger", {"pixel_y": 5}), "/obj/item/stock_parts/cell/high/plus",
       "/obj/item/stock_parts/cell/high/plus", r="R")
    # assembly floor beside the mech bay shutter, fed by two fab lines (fab -> belt -> pickup tile)
    for x in (171, 172, 173):
        for y in (120, 121, 122, 123):
            d = []
            if y == 123:
                d.append(stripe(1))
            if y == 120:
                d.append(stripe(2))
            if x == 173:
                d.append(stripe(4))
            at(x, y, decal=d, r="R")
    for y, ident in ((123, "robo1"), (121, "robo2")):
        at(177, y, ("/obj/machinery/mecha_part_fabricator", {"dir": 8}), r="R", decal=["/obj/effect/turf_decal/bot"])
        at(176, y, ("/obj/machinery/conveyor", {"dir": 8, "id": ident}), r="R")
        at(175, y, ("/obj/machinery/conveyor", {"dir": 8, "id": ident}), r="R")
        at(174, y, r="R", decal=["/obj/effect/turf_decal/delivery"])
        at(178, y, ("/obj/machinery/conveyor_switch/oneway", {"id": ident}), r="R")
    at(178, 124, TABLE, "/obj/item/stack/sheet/metal/fifty", "/obj/item/stack/sheet/metal/fifty",
       ("/obj/item/stack/sheet/glass/fifty", {"pixel_x": 3, "pixel_y": 3}), r="R")
    at(178, 120, TABLE, "/obj/item/assembly/flash/handheld", "/obj/item/assembly/flash/handheld",
       ("/obj/item/assembly/prox_sensor", {"pixel_x": -8, "pixel_y": 4}), "/obj/item/stack/cable_coil", r="R")
    wall_item(171, 124, "/obj/machinery/button/door", {"name": "Mech Bay Shutters", "id": "robo_mechbay",
                                                       "req_access_txt": "29", "pixel_x": -24}, r="R")
    wall_item(178, 125, "/obj/machinery/button/door", {"name": "Desk Shutters", "id": "robotics_desk",
                                                       "req_access_txt": "29", "pixel_y": 24, "pixel_x": -6}, r="R")
    at(173, 124, "/obj/effect/landmark/start/roboticist", r="R")
    at(176, 122, "/obj/effect/landmark/start/roboticist", r="R")
    # surgery bay behind the glass: table and its computer side by side, instruments along the back wall
    spec(171, 118, {"mount": [("sink", "/obj/structure/sink", {})], "mount_side": "west"}, "R")
    at(171, 117, TABLE, "/obj/item/scalpel", "/obj/item/hemostat", "/obj/item/retractor", "/obj/item/cautery", r="R")
    at(172, 117, TABLE, "/obj/item/circular_saw", "/obj/item/surgicaldrill", "/obj/item/surgical_drapes",
       "/obj/item/clothing/gloves/color/latex", r="R")
    at(174, 117, ("/obj/structure/table/optable", {"name": "Robotics Operating Table"}), r="R")
    at(175, 117, ("/obj/machinery/computer/operating", {"name": "Robotics Operating Computer", "dir": 8}), r="R")
    at(177, 118, "/obj/machinery/aug_manipulator", r="R")
    at(178, 118, TABLE, "/obj/item/mmi", "/obj/item/mmi", "/obj/item/storage/box/bodybags", "/obj/item/razor", r="R")
    at(178, 117, ("/obj/structure/bodycontainer/morgue", {"dir": 8}), r="R")

    # ================================================================ FOYER (x180-182, y117-125)
    at(180, 125, "/obj/item/twohanded/required/kirbyplants/random", r="F")
    at(182, 125, "/obj/item/twohanded/required/kirbyplants/random", r="F")
    at(181, 121, "/obj/machinery/holopad", r="F")
    for x in (180, 181, 182):
        at(x, 117, decal=[stripe(2)], r="F")

    # ================================================================ R&D (x184-188, y117-125)
    # console faces the three machines it links (within 3); the delivery chute drops at 188,121
    at(186, 123, ("/obj/machinery/computer/rdconsole/core", {"dir": 2}), r="L")
    at(185, 120, "/obj/machinery/rnd/destructive_analyzer", r="L", decal=["/obj/effect/turf_decal/bot"])
    at(186, 120, "/obj/machinery/rnd/production/circuit_imprinter/department/science", r="L",
       decal=["/obj/effect/turf_decal/bot"])
    at(187, 120, "/obj/machinery/rnd/production/protolathe/department/science", r="L", decal=["/obj/effect/turf_decal/bot"])
    at(188, 121, r="L", decal=["/obj/effect/turf_decal/delivery"])
    at(184, 124, TABLE, "/obj/item/stack/sheet/glass/fifty", "/obj/item/stack/sheet/metal/fifty",
       "/obj/item/stack/cable_coil", r="L")
    at(184, 123, TABLE, ("/obj/machinery/cell_charger", {"pixel_y": 5}), "/obj/item/stock_parts/cell/high", r="L")
    at(188, 125, TABLE, "/obj/item/stock_parts/manipulator", "/obj/item/stock_parts/micro_laser",
       "/obj/item/stock_parts/capacitor", "/obj/item/stock_parts/matter_bin", "/obj/item/stock_parts/scanning_module", r="L")
    at(188, 124, TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/clothing/glasses/welding", r="L")
    at(184, 117, GTABLE, "/obj/item/reagent_containers/glass/beaker/large", "/obj/item/reagent_containers/dropper", r="L")
    at(187, 117, "/obj/machinery/disposal/bin", r="L", dest="station")
    at(187, 122, "/obj/effect/landmark/start/scientist", r="L")
    wall_item(186, 125, "/obj/machinery/button/door", {"name": "Desk Shutters", "id": "rnd", "req_access_txt": "47",
                                                       "pixel_y": 24, "pixel_x": 6}, r="L")

    # ================================================================ SERVER ROOM (x165-168, y106-111), cold loop
    at(166, 110, "/obj/machinery/rnd/server", r="V")
    at(165, 107, "/obj/machinery/rnd/server", r="V")
    at(168, 111, "/obj/machinery/atmospherics/components/unary/thermomachine/freezer/on", r="V")
    at(168, 110, ("/obj/machinery/atmospherics/pipe/manifold/general/visible", {"dir": 4}), r="V")
    at(167, 110, ("/obj/machinery/atmospherics/components/unary/vent_pump/on", {"name": "server vent", "dir": 4}), r="V")
    at(168, 109, "/obj/machinery/atmospherics/pipe/simple/general/visible", r="V")
    at(168, 108, "/obj/machinery/atmospherics/pipe/simple/general/visible", r="V")
    at(168, 107, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 9}), r="V")
    at(167, 107, ("/obj/machinery/atmospherics/components/unary/vent_pump/siphon/on", {"name": "server vent", "dir": 4}), r="V")

    # ================================================================ RD OFFICE (x170-177, y106-111)
    # desk faces the spine door, consoles behind the RD, the servers through the west door, the floor through glass
    at(173, 109, TABLE, "/obj/item/folder/white", "/obj/item/stamp/rd", r="H")
    at(174, 109, TABLE, ("/obj/item/paper_bin", {"pixel_x": -3, "pixel_y": 7}), "/obj/item/pen", r="H")
    at(175, 109, TABLE, "/obj/item/flashlight/lamp", r="H")
    at(174, 108, ("/obj/structure/chair/office/light", {"dir": 1}), "/obj/effect/landmark/start/research_director", r="H")
    at(171, 106, ("/obj/machinery/computer/robotics", {"dir": 1}), r="H")
    at(172, 106, ("/obj/machinery/computer/mecha", {"dir": 1}), r="H")
    at(173, 106, ("/obj/machinery/computer/rdservercontrol", {"dir": 1}), r="H")
    at(175, 106, ("/obj/machinery/computer/aifixer", {"dir": 1}), r="H")
    at(176, 106, ("/obj/machinery/computer/card/minor/rd", {"dir": 1}), r="H")
    at(170, 111, "/obj/machinery/suit_storage_unit/rd", r="H")
    at(170, 110, "/obj/structure/closet/secure_closet/RD", r="H")
    at(176, 111, "/obj/structure/filingcabinet/chestdrawer", r="H")
    at(177, 111, "/obj/structure/displaycase/labcage", r="H")
    at(177, 106, "/obj/machinery/disposal/bin", r="H", dest="station")
    wall_item(170, 108, "/obj/machinery/requests_console", {"name": "Research Director RC", "department": "Research Director's Desk",
                                                            "departmentType": 5, "announcementConsole": 1, "pixel_x": -30}, r="H")
    wall_item(174, 106, "/obj/machinery/computer/security/telescreen/rd", {"pixel_y": -32}, r="H")
    wall_item(170, 106, "/obj/machinery/keycard_auth", {"pixel_x": -24}, r="H")
    wall_item(177, 106, "/obj/machinery/button/door", {"name": "Biohazard Shutter Control", "id": "Biohazard",
                                                       "req_access_txt": "47", "pixel_y": -24}, r="H")

    # ================================================================ SECURITY POST (x183-185, y109-111)
    at(183, 111, TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), r="K")
    at(184, 111, TABLE, "/obj/item/book/manual/wiki/security_space_law", r="K")
    at(185, 111, "/obj/structure/closet/secure_closet/security/science", r="K")
    at(184, 110, ("/obj/structure/chair/office", {"dir": 1}), "/obj/effect/landmark/start/depsec/science", r="K")
    at(185, 110, ("/obj/machinery/computer/secure_data", {"dir": 8}), r="K")
    at(185, 109, "/obj/machinery/vending/wardrobe/sec_wardrobe", r="K")
    at(183, 109, "/obj/structure/filingcabinet", r="K")

    # holding cell under the post: the officer can hold someone at the department entrance
    from_post = g["carve"]
    from_post(183, 105, 185, 107, "K")
    for x in (183, 185):
        window(x, 108)
    spec(184, 108, {"obj": [("/obj/machinery/door/window/northleft", {"name": "Holding Cell", "dir": 1, "req_access_txt": "63"})]}, "K")
    at(183, 106, ("/obj/structure/bed", {}), r="K")
    at(185, 107, ("/obj/structure/chair", {"dir": 8}), r="K")
    wall_item(185, 106, "/obj/machinery/flasher", {"id": "scicell", "pixel_x": 24}, r="K")
    wall_item(185, 109, "/obj/machinery/button/flasher", {"id": "scicell", "pixel_x": 24, "pixel_y": 6}, r="K")

    # ================================================================ NANITES (x187-195, y106-111)
    # two chamber stations, each console beside its chamber (mirror pair), programming wall on the east
    at(188, 105, "/obj/machinery/nanite_chamber", r="N", decal=["/obj/effect/turf_decal/bot"])
    at(189, 105, ("/obj/machinery/computer/nanite_chamber_control", {"dir": 1}), r="N")
    at(187, 105, TABLE, "/obj/item/disk/nanite_program", "/obj/item/disk/nanite_program", r="N")
    at(191, 106, ("/obj/machinery/computer/nanite_chamber_control", {"dir": 1}), r="N")
    at(192, 106, "/obj/machinery/nanite_chamber", r="N", decal=["/obj/effect/turf_decal/bot"])
    at(189, 106, ("/obj/structure/chair/office/light", {"dir": 2}), r="N")
    at(191, 107, ("/obj/structure/chair/office/light", {"dir": 2}), r="N")
    at(195, 111, "/obj/machinery/nanite_program_hub", r="N")
    at(195, 110, "/obj/machinery/nanite_program_hub", r="N")
    at(195, 108, "/obj/machinery/nanite_programmer", r="N")
    at(195, 107, ("/obj/machinery/computer/nanite_cloud_controller", {"dir": 8}), r="N")
    at(195, 106, ("/obj/machinery/computer/nanite_cloud_controller", {"dir": 8}), r="N")
    at(194, 108, ("/obj/structure/chair/office/light", {"dir": 4}), r="N")
    at(187, 110, ("/obj/structure/chair", {"dir": 4}), r="N")
    at(187, 109, ("/obj/structure/chair", {"dir": 4}), r="N")
    at(193, 111, "/obj/machinery/disposal/bin", r="N", dest="station")

    # ================================================================ EXPERIMENTATION (x190-196, y113-119; chamber x194-196, y113-115)
    # walk in from the west door straight along row 114 to the chamber door; the console and a bench sit on the
    # chamber's north wall looking in through its glass, lockers along the north wall
    at(195, 114, "/obj/machinery/rnd/experimentor", r="e", decal=["/obj/effect/turf_decal/bot"])
    at(195, 117, ("/obj/machinery/computer/rdconsole/experiment", {"dir": 2}), r="E")
    at(195, 118, ("/obj/structure/chair/office/light", {"dir": 2}), r="E")
    at(193, 117, TABLE, "/obj/item/taperecorder", "/obj/item/clipboard", r="E")
    at(194, 117, TABLE, "/obj/item/stack/sheet/mineral/plasma", "/obj/item/clothing/glasses/science", r="E")
    at(193, 118, ("/obj/structure/chair/office/light", {"dir": 2}), r="E")
    wall_item(196, 118, "/obj/machinery/button/door", {"name": "Test Chamber Blast Doors", "id": "telelab",
                                                       "req_access_txt": "7", "pixel_x": 24}, r="E")
    at(190, 119, "/obj/structure/closet/l3closet/scientist", r="E")
    at(191, 119, "/obj/structure/closet/radiation", r="E")
    at(192, 119, "/obj/structure/closet/bombcloset", r="E")
    at(194, 119, TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/analyzer", r="E")
    at(196, 117, "/obj/machinery/disposal/bin", r="E", dest="station")
    at(191, 116, "/obj/machinery/holopad", r="E")
    at(192, 114, decal=[stripe(4)], r="E")

    # ================================================================ XENOBIOLOGY (x165-177, y85-104)
    # lab up top (processing along the north wall), a containment line at y96, six pens off a central aisle
    line(165, 96, 169, 96, "#")
    line(173, 96, 177, 96, "#")
    for x in (170, 171, 172):
        spec(x, 96, {"obj": [("/obj/machinery/door/poddoor/preopen/biohazard", {"id": "xeno_containment"}),
                             "/obj/machinery/door/firedoor/heavy"]}, "X")
    pens = [(165, 93, 168, 95, 169, 1), (165, 89, 168, 91, 169, 2), (165, 85, 168, 87, 169, 3),
            (174, 93, 177, 95, 173, 4), (174, 88, 177, 91, 173, 5)]
    # the east column stops at y87: below it is the station's space notch (x174-177, y83-86), so two pens there,
    # the lower one a row taller, and the aisle's east side closes in a straight wall down to the outline
    line(165, 92, 169, 92, "#")
    line(165, 88, 169, 88, "#")
    line(173, 92, 177, 92, "#")
    line(173, 87, 177, 87, "#")
    line(173, 85, 173, 86, "#")
    for x1, y1, x2, y2, fx, n in pens:
        mid = y1 + 1
        ident = "xenobio%d" % n
        for y in range(y1, y2):
            if y != mid:
                put(fx, y, "#")
        spec(fx, y2, {"turf": "rwindow", "obj": [("/obj/machinery/door/poddoor/preopen/biohazard", {"id": ident})]}, "X")
        inward = 8 if fx == 169 else 4
        spec(fx, mid, {"obj": [("/obj/machinery/door/window/northleft",
                                {"name": "Containment Pen", "dir": inward, "req_access_txt": "55"}),
                               ("/obj/machinery/door/poddoor/preopen/biohazard", {"id": ident})]}, "X")
        # bin on the aisle beside the pen front, outlet inside the pen
        bx = 170 if fx == 169 else 172
        ox = 168 if fx == 169 else 174
        spec(bx, y2, {"obj": ["/obj/machinery/disposal/bin"], "dest": ("outlet", ident)}, "X")
        spec(ox, y2, {"outlet": ident, "throw": inward, "obj": []}, "X")
        wall_item(bx, y1, "/obj/machinery/button/door", {"name": "Containment Blast Doors", "id": ident,
                                                          "req_access_txt": "55", "pixel_x": -24 if fx == 169 else 24}, r="X")
    # processing line along the north wall, the slime console looking down the aisle
    at(166, 104, "/obj/machinery/monkey_recycler", r="X")
    at(167, 104, "/obj/machinery/processor/slime", r="X")
    at(168, 104, "/obj/machinery/smartfridge/extract/preloaded", r="X")
    at(169, 104, GTABLE, ("/obj/machinery/reagentgrinder", {"pixel_y": 6}), r="X")
    at(170, 104, "/obj/machinery/chem_master", r="X")
    at(172, 104, "/obj/structure/reagent_dispensers/watertank", r="X")
    at(176, 104, "/obj/structure/closet/l3closet/scientist", r="X")
    at(175, 104, "/obj/structure/closet/l3closet/scientist", r="X")
    at(171, 98, ("/obj/machinery/computer/camera_advanced/xenobio", {"dir": 2}), r="X")
    at(171, 99, ("/obj/structure/chair/office/light", {"dir": 2}), r="X")
    at(166, 99, GTABLE, "/obj/item/storage/box/beakers", "/obj/item/storage/box/syringes", r="X")
    at(166, 100, GTABLE, "/obj/item/slime_scanner", "/obj/item/clothing/glasses/science", r="X")
    at(176, 99, TABLE, "/obj/item/storage/box/monkeycubes", "/obj/item/storage/box/monkeycubes", r="X")
    at(176, 100, TABLE, ("/obj/item/paper_bin", {"pixel_x": -3, "pixel_y": 7}), "/obj/item/pen", r="X")
    at(165, 97, "/obj/machinery/disposal/bin", r="X", dest="deathsposal",
       decal=["/obj/effect/turf_decal/stripes/red/box"])
    wall_item(165, 98, "/obj/structure/sign/warning/deathsposal", {"pixel_x": -32}, r="X")
    wall_item(177, 97, "/obj/machinery/button/door", {"name": "Containment Lockdown", "id": "xeno_containment",
                                                       "req_access_txt": "55", "pixel_x": 24}, r="X")
    at(171, 101, "/obj/machinery/holopad", r="X")
    at(170, 100, "/obj/effect/landmark/start/scientist", r="X")
    for x in (170, 171, 172):
        at(x, 97, decal=[stripe(1)], r="X")

    # ================================================================ TOXINS (x183-195, y95-104)
    # the burn chamber (x184-189, y101-103) is tg's toxmix incinerator: poddoors to the space notch, injector,
    # igniter, sensor, scrubber out, a dp-vent airlock to get in; controls on the wall at x190
    line(184, 104, 189, 104, "#")
    line(184, 100, 189, 100, "#")
    VAC = "/turf/open/floor/engine/vacuum"
    ENG = "/turf/open/floor/engine"
    spec(185, 101, {"floor": VAC, "obj": []}, "C")
    spec(185, 102, {"floor": VAC, "obj": ["/obj/machinery/air_sensor/atmos/toxins_mixing_tank"]}, "C")
    spec(185, 103, {"floor": VAC, "obj": [("/obj/structure/sign/warning/vacuum/external", {"pixel_y": 32})]}, "C")
    spec(186, 101, {"floor": VAC, "obj": [("/obj/machinery/atmospherics/components/unary/outlet_injector/atmos/toxins_mixing_input",
                                           {"dir": 4})]}, "C")
    spec(186, 102, {"floor": VAC, "obj": ["/obj/machinery/igniter/incinerator_toxmix"]}, "C")
    spec(186, 103, {"floor": VAC, "obj": [("/obj/machinery/atmospherics/components/unary/vent_scrubber/on", {"dir": 4})]}, "C")
    for y in (101, 102, 103):
        spec(184, y, {"floor": VAC, "obj": ["/obj/machinery/door/poddoor/incinerator_toxmix"]}, "C")
    spec(187, 101, {"turf": "rwall", "obj": [("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4})]}, "C")
    spec(187, 103, {"turf": "rwall", "obj": [("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4})]}, "C")
    spec(189, 101, {"turf": "rwall", "obj": [("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4})]}, "C")
    spec(189, 103, {"turf": "rwall", "obj": [("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4})]}, "C")
    spec(187, 102, {"floor": ENG, "obj": ["/obj/effect/mapping_helpers/airlock/locked",
                                          "/obj/machinery/door/airlock/research/glass/incinerator/toxmix_exterior"]}, "C")
    spec(189, 102, {"floor": ENG, "obj": ["/obj/effect/mapping_helpers/airlock/locked",
                                          "/obj/machinery/door/airlock/research/glass/incinerator/toxmix_interior"]}, "C")
    spec(188, 101, {"floor": ENG, "obj": [("/obj/machinery/atmospherics/components/binary/pump/on", {"dir": 8}),
                                          ("/obj/structure/sign/warning/fire", {"pixel_y": -32})]}, "C")
    spec(188, 102, {"floor": ENG, "obj": ["/obj/machinery/atmospherics/components/binary/dp_vent_pump/high_volume/incinerator_toxmix"]}, "C")
    spec(188, 103, {"floor": ENG, "obj": ["/obj/machinery/atmospherics/pipe/layer_manifold",
                                          ("/obj/machinery/atmospherics/components/binary/pump/on", {"dir": 4}),
                                          ("/obj/machinery/airlock_sensor/incinerator_toxmix", {"pixel_y": 24})]}, "C")
    # controls just outside the chamber
    at(190, 101, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4}), "/obj/machinery/meter",
       ("/obj/machinery/button/door/incinerator_vent_toxmix", {"pixel_x": -25, "pixel_y": 5}),
       ("/obj/machinery/button/ignition/incinerator/toxmix", {"pixel_x": -25, "pixel_y": -5}), r="T")
    at(190, 103, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4}), "/obj/machinery/meter",
       ("/obj/machinery/embedded_controller/radio/airlock_controller/incinerator_toxmix", {"pixel_x": -24}), r="T")
    at(190, 102, decal=["/obj/effect/turf_decal/stripes/line"], r="T")
    at(190, 100, ("/obj/machinery/airalarm/mixingchamber", {"dir": 4, "pixel_x": -24}), r="T")
    # fuel line: two canister ports feed a mixer, a pump sends the mix to the chamber's injector
    at(193, 99, ("/obj/machinery/atmospherics/components/unary/portables_connector/visible", {"dir": 1}), r="T",
       decal=["/obj/effect/turf_decal/bot"])
    at(194, 100, ("/obj/machinery/atmospherics/components/unary/portables_connector/visible", {"dir": 8}), r="T",
       decal=["/obj/effect/turf_decal/bot"])
    at(193, 100, ("/obj/machinery/atmospherics/components/trinary/mixer", {"dir": 1, "name": "Fuel Mixer"}), r="T")
    at(193, 101, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 10}), r="T")
    at(192, 101, ("/obj/machinery/atmospherics/components/binary/pump", {"dir": 8, "name": "Mix to Chamber"}), r="T")
    at(191, 101, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4}), r="T")
    # waste line: the chamber's scrubber out to a waste canister port
    at(191, 103, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4}), r="T")
    at(192, 103, ("/obj/machinery/atmospherics/components/binary/pump", {"dir": 4, "name": "Chamber to Waste"}), r="T")
    at(193, 103, ("/obj/machinery/atmospherics/components/unary/portables_connector/visible", {"dir": 8}), r="T",
       decal=["/obj/effect/turf_decal/bot"])
    # canister bay (east), bomb assembly (west), lockers by the door
    # two rows with an aisle between, so every canister can be wheeled out
    cans = [(191, 95, "toxins"), (192, 95, "toxins"), (193, 95, "toxins"), (194, 95, "toxins"), (192, 99, "toxins"),
            (191, 97, "oxygen"), (192, 97, "oxygen"), (193, 97, "oxygen"), (194, 97, "oxygen"),
            (195, 97, "nitrous_oxide"), (191, 99, "nitrous_oxide"), (195, 98, "carbon_dioxide"), (195, 99, "carbon_dioxide")]
    for x, y, gas in cans:
        at(x, y, "/obj/machinery/portable_atmospherics/canister/%s" % gas, r="T", decal=["/obj/effect/turf_decal/bot"])
    at(195, 101, "/obj/machinery/portable_atmospherics/scrubber/huge", r="T", decal=["/obj/effect/turf_decal/bot"])
    at(195, 102, "/obj/machinery/portable_atmospherics/pump", r="T", decal=["/obj/effect/turf_decal/bot"])
    at(194, 98, "/obj/machinery/portable_atmospherics/scrubber", r="T", decal=["/obj/effect/turf_decal/bot"])
    at(183, 95, "/obj/structure/closet/bombcloset", r="T")
    at(184, 95, "/obj/structure/closet/bombcloset", r="T")
    at(185, 95, "/obj/structure/closet/l3closet/scientist", r="T")
    at(186, 95, "/obj/machinery/vending/wardrobe/science_wardrobe", r="T")
    at(187, 95, "/obj/structure/tank_dispenser", r="T")
    at(183, 99, "/obj/machinery/vending/plasmaresearch", r="T")
    at(185, 98, RTABLE, "/obj/item/transfer_valve", "/obj/item/assembly/signaler", "/obj/item/assembly/signaler", r="T")
    at(186, 98, RTABLE, "/obj/item/assembly/timer", "/obj/item/assembly/prox_sensor", "/obj/item/screwdriver", r="T")
    at(186, 97, ("/obj/structure/chair/office/light", {"dir": 1}), r="T")
    at(189, 95, "/obj/machinery/disposal/bin", r="T", dest="station")
    wall_item(183, 97, "/obj/structure/sign/warning/explosives", {"pixel_x": -32}, r="T")
    at(189, 97, "/obj/effect/landmark/start/scientist", r="T")

    # ================================================================ LAUNCH ROOM (x202-206, y104-108)
    # reached from toxins through the science maint room (x198-200). Bombs go on the driver behind the windoor;
    # the driver throws east along row 104 to the bomb range; the watchers sit on the east wall by the doppler
    for x in (203, 204, 206):
        window(x, 105)
    put(205, 105, "#")
    at(202, 105, ("/obj/machinery/door/window/southleft", {"name": "Mass Driver Door", "req_access_txt": "7"}), r="D",
       decal=["/obj/effect/turf_decal/loading_area"])
    at(202, 104, ("/obj/machinery/mass_driver", {"dir": 4, "id": "toxinsdriver"}), r="D")
    at(203, 104, decal=[stripe(1)], r="D")
    at(204, 104, decal=[stripe(1)], r="D")
    at(206, 108, ("/obj/machinery/doppler_array/research/science", {"dir": 4}), r="D")
    at(206, 107, ("/obj/structure/chair", {"dir": 4}), r="D")
    at(206, 106, ("/obj/structure/chair", {"dir": 4}), r="D")
    wall_item(206, 107, "/obj/machinery/computer/security/telescreen",
              {"name": "Test Chamber Telescreen", "network": 'list("toxins")', "pixel_x": 32}, r="D")
    wall_item(206, 106, "/obj/structure/sign/warning/securearea", {"name": "BOMB RANGE", "pixel_x": 32}, r="D")
    wall_item(202, 107, "/obj/machinery/button/massdriver", {"id": "toxinsdriver", "pixel_x": -24}, r="D")
    spec(202, 106, {"no_vent": True, "obj": []}, "D")  # the only way in: pipes from the maint room pass here
    at(203, 108, ("/obj/structure/closet/crate/secure", {"name": "Test Site Materials Crate", "req_access_txt": "8"}), r="D")

    # ================================================================ TESTING LAB (x183-194, y88-93; range x186-188, y85-87)
    # ignition test chamber in the east (sealed, sparker + injector fed from a port outside), chem bench west,
    # magnet range to the south
    line(190, 88, 190, 93, "#")
    for y in (89, 91):
        window(190, y)
    spec(190, 90, {"obj": [("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4}),
                           ("/obj/machinery/door/airlock/research/glass", {"name": "Test Chamber", "req_access_txt": "47"}),
                           ("/obj/machinery/door/poddoor/preopen", {"name": "test chamber blast door", "id": "testlab"})]}, "M")
    at(193, 90, ("/obj/machinery/atmospherics/components/unary/outlet_injector/on", {"dir": 8}), r="M")
    at(192, 90, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4}), r="M")
    at(191, 90, ("/obj/machinery/atmospherics/pipe/simple/general/visible", {"dir": 4}), r="M")
    # (the pipe runs under the doorway into the lab, to a port beside the door)
    at(189, 90, ("/obj/machinery/atmospherics/components/binary/pump", {"dir": 4, "name": "Port to Chamber"}), r="M")
    at(188, 90, ("/obj/machinery/atmospherics/components/unary/portables_connector/visible", {"dir": 4}), r="M",
       decal=["/obj/effect/turf_decal/bot"])
    wall_item(194, 92, "/obj/machinery/sparker", {"id": "testigniter", "pixel_x": 25}, r="M")
    at(189, 92, TABLE, ("/obj/machinery/button/ignition", {"id": "testigniter", "pixel_x": -6, "pixel_y": 2}),
       ("/obj/machinery/button/door", {"name": "Test Chamber Blast Doors", "id": "testlab", "req_access_txt": "47",
                                       "pixel_x": 4, "pixel_y": 2}), r="M")
    at(189, 91, TABLE, ("/obj/machinery/computer/security/telescreen", {"name": "Test Chamber Monitor",
                                                                        "network": 'list("test")', "dir": 8}), r="M")
    at(188, 91, ("/obj/structure/chair/office/light", {"dir": 4}), r="M")
    at(183, 93, "/obj/machinery/chem_dispenser", r="M")
    at(184, 93, "/obj/machinery/chem_heater", r="M")
    at(185, 93, "/obj/machinery/chem_master", r="M")
    at(186, 93, TABLE, ("/obj/machinery/reagentgrinder", {"pixel_y": 6}), r="M")
    at(185, 92, ("/obj/structure/chair/office/light", {"dir": 1}), r="M")
    at(183, 88, "/obj/machinery/disposal/bin", r="M", dest="station")
    at(184, 88, TABLE, ("/obj/machinery/magnetic_controller", {"pixel_y": 3, "autolink": 1}), r="M")
    at(187, 93, TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), r="M")
    at(187, 86, "/obj/machinery/magnetic_module", "/obj/structure/target_stake", r="M")
    for y in (85, 86, 87):
        at(186, y, decal=[stripe(8)], r="M")

    # ================================================================ SPINES
    at(166, 113, "/obj/machinery/vending/cigarette", r="s")
    at(167, 113, "/obj/machinery/vending/coffee", r="s")
    at(178, 115, "/obj/structure/closet/firecloset", r="s")
    at(177, 115, "/obj/structure/closet/emcloset", r="s")
    at(181, 105, ("/obj/machinery/shower", {"dir": 8}), r="s")
    at(179, 95, "/obj/structure/closet/firecloset", r="s")


def enrich(g):
    """Floor zoning and lived-in detail: work zones on dark or engine floor, rugs where people sit, benches and
    plants along halls, islands in big rooms (the user: 'lacks detail, a lot of open space, feels liminal')."""
    spec, put, lay = g["spec"], g["put"], g["lay"]
    TABLE, GTABLE = "/obj/structure/table", "/obj/structure/table/glass"
    DARK, GREY, ENG = "/turf/open/floor/plasteel/dark", "/turf/open/floor/plasteel", "/turf/open/floor/engine"
    CARPET, GRIMY, CIRC = "/turf/open/floor/carpet", "/turf/open/floor/plasteel/grimy", "/turf/open/floor/circuit"
    STRIPE = "/obj/effect/turf_decal/stripes/line"
    PLANT = "/obj/item/twohanded/required/kirbyplants/random"

    def floor(x1, y1, x2, y2, turf):
        for x in range(x1, x2 + 1):
            for y in range(y1, y2 + 1):
                if lay.get((x, y)) not in (None, "#", "%"):
                    spec(x, y, {"floor": turf})

    def at(x, y, *o, decal=(), **kw):
        # dressing never turns a wall into floor (a stripe box drawn one tile too wide once opened a wall
        # beside the launch room airlock)
        if lay.get((x, y)) in (None, "#", "%"):
            if o:
                raise ValueError("enrich: %d,%d is a wall" % (x, y))
            return
        sp = dict(kw)
        sp["obj"] = list(o)
        if decal:
            sp["decal"] = list(decal)
        spec(x, y, sp)

    def stripes(x1, y1, x2, y2):
        """A striped box edge around a work zone."""
        for x in range(x1, x2 + 1):
            at(x, y2, decal=[(STRIPE, {"dir": 1})])
            at(x, y1, decal=[STRIPE])
        for y in range(y1, y2 + 1):
            at(x1, y, decal=[(STRIPE, {"dir": 8})])
            at(x2, y, decal=[(STRIPE, {"dir": 4})])

    # --- research spine: grey hall, dark junction, benches and plants between the doors
    floor(166, 113, 188, 115, GREY)
    floor(179, 88, 181, 112, GREY)
    floor(179, 113, 181, 115, DARK)
    for x in (169, 170):
        at(x, 115, ("/obj/structure/chair", {"dir": 2}))
    at(171, 115, PLANT)
    at(183, 115, PLANT)
    at(188, 113, PLANT)
    at(168, 113, ("/obj/structure/chair", {"dir": 1}))
    at(179, 107, ("/obj/structure/chair", {"dir": 4}))
    at(179, 106, ("/obj/structure/chair", {"dir": 4}))
    at(179, 105, PLANT)
    at(181, 93, PLANT)
    at(179, 88, PLANT)
    at(181, 101, "/obj/machinery/vending/cola/random")
    for y in (111, 99, 91):
        at(180, y, decal=[("/obj/effect/turf_decal/tile/purple", {"dir": 1}), "/obj/effect/turf_decal/tile/purple",
                          ("/obj/effect/turf_decal/tile/purple", {"dir": 4}), ("/obj/effect/turf_decal/tile/purple", {"dir": 8})])

    # --- foyer: grey with a dark runner to the lockdown doors
    floor(180, 117, 182, 125, GREY)
    floor(181, 117, 181, 125, DARK)
    at(180, 122, ("/obj/structure/chair", {"dir": 4}))
    at(180, 121, ("/obj/structure/chair", {"dir": 4}))

    # --- robotics: dark work floor under the assembly and fab lines, white elsewhere
    floor(171, 120, 178, 123, DARK)
    floor(171, 117, 178, 118, "/turf/open/floor/plasteel/white")
    # --- R&D: dark machine pen
    floor(184, 119, 188, 121, DARK)
    stripes(184, 119, 188, 121)
    # --- mech bay: circuit floor under the consoles is set; engine floor on the assembly-to-launch lane
    floor(167, 117, 168, 126, ENG)

    # --- RD office: a rug under the desk, a plant, a bookcase
    floor(172, 107, 176, 110, CARPET)
    at(171, 111, PLANT)
    at(170, 106, "/obj/structure/bookcase/random")

    # --- security post and cell: dark, the cell grimy
    floor(183, 105, 185, 107, GRIMY)

    # --- nanites: dark bays under the chambers, a grimy programming corner, a waiting rug
    floor(187, 105, 192, 107, DARK)
    floor(194, 106, 196, 111, GRIMY)
    floor(187, 109, 188, 110, CARPET)
    at(190, 111, PLANT)
    at(192, 110, GTABLE, "/obj/item/nanite_remote", "/obj/item/nanite_scanner")
    at(193, 110, GTABLE, "/obj/item/storage/box/disks_nanite", ("/obj/item/folder/white", {"pixel_x": 4, "pixel_y": -3}))

    # --- experimentation: grey work room, an island bench, a striped path to the chamber
    floor(190, 112, 196, 119, GREY)
    floor(190, 113, 192, 115, DARK)
    floor(194, 113, 196, 115, ENG)
    at(190, 113, PLANT)
    at(190, 117, GTABLE, "/obj/item/geiger_counter", "/obj/item/clothing/glasses/meson")
    at(190, 116, GTABLE, "/obj/item/multitool", "/obj/item/assembly/igniter")

    # --- xenobiology: dark processing strip, a lab island, dark pens with hazard edges at the fronts
    floor(165, 103, 177, 104, DARK)
    floor(169, 97, 173, 99, DARK)
    floor(166, 100, 168, 101, "/turf/open/floor/plasteel/white")
    at(169, 101, GTABLE, "/obj/item/slime_extract/grey", "/obj/item/reagent_containers/syringe/plasma")
    at(170, 101, GTABLE, "/obj/item/reagent_containers/glass/beaker/large", "/obj/item/reagent_containers/dropper")
    at(169, 102, ("/obj/structure/chair/office/light", {"dir": 2}))
    at(165, 101, PLANT)
    at(177, 101, PLANT)
    for (x1, y1, x2, y2) in ((165, 93, 168, 95), (165, 89, 168, 91), (165, 85, 168, 87),
                             (174, 93, 177, 95), (174, 88, 177, 91)):
        floor(x1, y1, x2, y2, ENG)
    floor(170, 85, 172, 95, DARK)
    for y in range(85, 96):
        at(170, y, decal=[(STRIPE, {"dir": 8})])
        at(172, y, decal=[(STRIPE, {"dir": 4})])

    # --- toxins: dark plumbing bay, dark canister bay, a second bomb bench, grey work floor
    floor(183, 95, 196, 99, GREY)
    floor(190, 100, 196, 103, DARK)
    floor(191, 95, 196, 99, DARK)
    stripes(190, 100, 195, 103)
    at(187, 98, "/obj/structure/table/reinforced", "/obj/item/tank/internals/plasma", "/obj/item/tank/internals/oxygen")
    at(187, 97, ("/obj/structure/chair/office/light", {"dir": 1}))
    at(188, 99, PLANT)

    # --- testing lab: engine floor in the test chamber, dark range, grey bench area
    floor(183, 88, 189, 93, GREY)
    floor(191, 88, 194, 93, ENG)
    floor(186, 85, 188, 87, DARK)
    at(183, 90, decal=[(STRIPE, {"dir": 8})])     # on the door side
    at(183, 92, "/obj/structure/closet/crate", "/obj/item/stack/sheet/metal/fifty")
