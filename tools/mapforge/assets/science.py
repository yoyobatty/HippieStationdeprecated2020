"""Room assets for a Science department: how each room is played, written as kits and placing rules.

The play facts come from tools/mapforge/studies/science.md (each link checked in the game code):
  exosuit fabricator   drops its print on the tile it faces -> fab, belt, pickup tile, assembly floor in one line
  mech recharge port   charges the mech on the tile it faces; its console finds it two tiles off in a straight line
  R&D console          links the analyzer, protolathe and imprinter it sees within 3 tiles
  operating computer   finds the operating table on the tile beside it
An asset never names a coordinate. It asks the room which wall faces which neighbour and where its doors are.
"""
from forge.proc.geo import OPP, CW, CCW, step
from forge.proc.place import Kit, cell, dist

TABLE, RTABLE, GTABLE = "/obj/structure/table", "/obj/structure/table/reinforced", "/obj/structure/table/glass"
STRIPE = "/obj/effect/turf_decal/stripes/line"
BOT, DELIVERY = "/obj/effect/turf_decal/bot", "/obj/effect/turf_decal/delivery"
DARK, ENG = "/turf/open/floor/plasteel/dark", "/turf/open/floor/engine"
PLANT = "/obj/item/twohanded/required/kirbyplants/random"
CHAIR, OCHAIR = "/obj/structure/chair", "/obj/structure/chair/office/light"


def one(name, label, *obj, back="wall", use=((0, 1),), **kw):
    """A single piece on one tile, used from the tile in front."""
    return Kit(name, [cell(0, 0, *obj, label=label, **kw)], use=use, back=back)


def button(name, label, vs):
    """A wall button: takes no floor, hangs on the wall behind its tile."""
    return Kit(name, [(0, 0, dict(obj=[], open=True, free=True, label=label,
                                  mount=[("button", "/obj/machinery/button/door", vs)]))], back="wall")


# ================================================================================================= mech bay
CHARGE = Kit("charge bay", [
    cell(0, 0, ("/obj/machinery/mech_bay_recharge_port", {"dir": "IN"}), floor="/turf/open/floor/plating", label="MP"),
    (0, 1, dict(obj=[], open=True, floor="/turf/open/floor/mech_bay_recharge_floor", label="pad")),
    (1, 0, dict(obj=[], open=True, floor="/turf/open/floor/circuit")),     # the bay is one unit: nothing between
    cell(2, 0, ("/obj/machinery/computer/mech_bay_power_console", {"dir": "IN"}), floor="/turf/open/floor/circuit", label="MC"),
], use=[(2, 1)])
BORG = one("borg charger", "RS", "/obj/machinery/recharge_station", decal=[DELIVERY])
BAY_TOOLS = one("mech tools", "T", TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/crowbar/large")
FUEL = one("fuel tank", "FT", "/obj/structure/reagent_dispensers/fueltank")


def mechbay(R):
    # a mech drives in through the robotics shutters, parks on a pad, leaves by the launch shutters onto the hall
    turn = R.apron("robotics", 4)
    lane = R.apron("hall", 3)
    R.reserve(turn + lane)
    R.zone(lane, floor=ENG, edge=STRIPE)
    far = OPP[R.side("robotics")]
    mid = turn[len(turn) // 2] if turn else R.room.attrs["heart"]
    first = R.place(CHARGE, side=far, near=mid)
    R.place(CHARGE, side=far, near=first.origin if first else mid)
    R.run([BORG, BORG], side=R.side("robotics"), near=mid)
    R.place(BAY_TOOLS, near=mid, must=False)
    R.place(FUEL, far=mid, must=False)
    R.place(button("launch button", "b", {"name": "Mech Bay Door Control", "id": "Skynet_launch", "req_access_txt": "29"}),
            near=lane[0] if lane else mid, must=False)
    R.place(button("shutter button", "b", {"name": "Robotics Shutters", "id": "robo_mechbay", "req_access_txt": "29"}),
            side=R.side("robotics"), near=mid, must=False)


# ================================================================================================= robotics
def fab_pair(belts):
    """Two fabricators back to the wall, a shared aisle between them to load both, each feeding a belt that ends on
    a pickup tile at the assembly floor."""
    cells = [(1, 0, dict(obj=[("/obj/machinery/conveyor_switch/oneway", {"id": "robo{n}"})], open=True, label="sw"))]
    for u in (0, 2):
        cells.append(cell(u, 0, ("/obj/machinery/mecha_part_fabricator", {"dir": "IN"}), decal=[BOT], label="FB"))
        for v in range(1, belts + 1):
            cells.append(cell(u, v, ("/obj/machinery/conveyor", {"dir": "IN", "id": "robo{n}"}), label=">>"))
        cells.append((u, belts + 1, dict(obj=[], open=True, decal=[DELIVERY], label="pk")))
    return Kit("fab lines", cells, use=[(1, 0), (1, 1)], back="wall")


ROBO_RND = Kit("robotics console", [
    cell(0, 0, ("/obj/machinery/computer/rdconsole/robotics", {"dir": "IN"}), label="RC"),
    cell(1, 0, "/obj/machinery/rnd/production/circuit_imprinter", label="CI"),
], use=[(0, 1), (1, 1)])
ROBO_VEND = one("robotics vendor", "V", "/obj/machinery/vending/robotics")
ROBO_WARD = one("robotics wardrobe", "W", "/obj/machinery/vending/wardrobe/robo_wardrobe")
PAPERS = one("paperwork", "t", TABLE, ("/obj/item/paper_bin", {"pixel_x": -3, "pixel_y": 7}), "/obj/item/pen",
             ("/obj/item/book/manual/wiki/robotics_cyborgs", {"pixel_x": 2, "pixel_y": 5}), back="any")
CELLS = one("cell charging", "t", TABLE, ("/obj/machinery/cell_charger", {"pixel_y": 5}),
            "/obj/item/stock_parts/cell/high/plus", "/obj/item/stock_parts/cell/high/plus", back="any")
SHEETS = one("sheet stock", "t", TABLE, "/obj/item/stack/sheet/metal/fifty", "/obj/item/stack/sheet/metal/fifty",
             ("/obj/item/stack/sheet/glass/fifty", {"pixel_x": 3, "pixel_y": 3}), back="any")
BORG_PARTS = one("borg parts", "t", TABLE, "/obj/item/assembly/flash/handheld", "/obj/item/assembly/flash/handheld",
                 ("/obj/item/assembly/prox_sensor", {"pixel_x": -8, "pixel_y": 4}), "/obj/item/stack/cable_coil", back="any")
MMIS = one("brain bench", "t", TABLE, "/obj/item/mmi", "/obj/item/mmi", "/obj/item/storage/box/bodybags", "/obj/item/razor",
           back="any")
AUG = one("augment manipulator", "AM", "/obj/machinery/aug_manipulator", back="any")


def robotics(R):
    # the line: fab -> belt -> pickup -> assembly floor -> mech bay shutters. Everything else serves it.
    bay = R.side("mechbay")
    floor = R.apron("mechbay", 3)
    R.reserve(floor)
    R.zone(floor, floor=DARK, edge=STRIPE)
    # as many belt tiles as the room is wide: wall, fab, belts, pickup, three tiles of assembly floor
    across, p = 0, (R.doors("mechbay") or [R.room.attrs["heart"]])[0]
    while p in R.tiles:
        across += 1
        p = step(p, OPP[bay])
    belts = max(1, min(3, across - 5))
    kit = fab_pair(belts)
    fabs = R.place(kit, side=OPP[bay], need=lambda pl: all(step(pl.at(u, belts + 1), pl.n) in floor for u in (0, 2)))
    if fabs:
        R.zone(R.box(fabs.tiles), floor=DARK)
    # the front office: the desk on the hall, the console and imprinter behind whoever serves it
    desk = (R.doors("hall") or [R.room.attrs["heart"]])[0]
    R.place(ROBO_RND, near=desk)
    R.place(ROBO_VEND, near=desk)
    R.run([PAPERS, CELLS], near=desk)
    R.place(button("desk button", "b", {"name": "Desk Shutters", "id": "robotics_desk", "req_access_txt": "29"}),
            near=desk, must=False)
    # stock within reach of the fabs
    aisle = fabs.uses[0] if fabs else desk
    R.run([SHEETS, BORG_PARTS], near=aisle)
    # brains come out in surgery and go into bodies on the assembly floor: the bench and the manipulator by its door
    surg = (R.doors("surgery") or [aisle])[0]
    R.run([MMIS, AUG], near=surg)
    staff = (R.doors("spine") or [desk])[0]
    R.place(ROBO_WARD, near=staff, must=False)
    R.place(button("bay button", "b", {"name": "Mech Bay Shutters", "id": "robo_mechbay", "req_access_txt": "29"}),
            side=bay, near=R.doors("mechbay")[0], must=False)
    for spot in (desk, aisle):
        R.mark(spot, "/obj/effect/landmark/start/roboticist")


OPSET = Kit("operating table", [
    cell(0, 0, ("/obj/structure/table/optable", {"name": "Robotics Operating Table"}), label="OT"),
    cell(1, 0, ("/obj/machinery/computer/operating", {"name": "Robotics Operating Computer", "dir": "A-"}), label="OC"),
], use=[(0, 1)])
SURG_TOOLS = one("surgery tools", "t", TABLE, "/obj/item/scalpel", "/obj/item/hemostat", "/obj/item/retractor",
                 "/obj/item/cautery", "/obj/item/circular_saw", "/obj/item/surgicaldrill", "/obj/item/surgical_drapes",
                 "/obj/item/clothing/gloves/color/latex")
MORGUE = one("morgue tray", "MG", ("/obj/structure/bodycontainer/morgue", {"dir": "IN"}))
SINK = Kit("sink", [(0, 0, dict(obj=[], open=True, free=True, label="s", mount=[("sink", "/obj/structure/sink", {})]))])


def surgery(R):
    # bodies wait at the back, away from the door its tray would block; the table sits mid-room, tools by the door
    door = R.doors()[0]
    R.place(MORGUE, far=door, must=False)
    table = R.place(OPSET, near=R.room.attrs["heart"])
    R.place(SURG_TOOLS, near=table.uses[0] if table else door)
    R.place(SINK, far=door, must=False)


# ================================================================================================= R&D
RND_PEN = Kit("research pen", [
    cell(0, 0, ("/obj/machinery/computer/rdconsole/core", {"dir": "IN"}), label="RD"),
    cell(1, 0, "/obj/machinery/rnd/destructive_analyzer", decal=[BOT], label="DA"),
    cell(2, 0, "/obj/machinery/rnd/production/circuit_imprinter/department/science", decal=[BOT], label="CI"),
    cell(3, 0, "/obj/machinery/rnd/production/protolathe/department/science", decal=[BOT], label="PL"),
], use=[(0, 1), (1, 1), (2, 1), (3, 1)])
STOCK = one("stock parts", "t", TABLE, "/obj/item/stock_parts/manipulator", "/obj/item/stock_parts/micro_laser",
            "/obj/item/stock_parts/capacitor", "/obj/item/stock_parts/matter_bin", "/obj/item/stock_parts/scanning_module",
            back="any")
RND_TOOLS = one("lab tools", "t", TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/clothing/glasses/welding",
                back="any")
RND_SHEETS = one("lab sheets", "t", TABLE, "/obj/item/stack/sheet/glass/fifty", "/obj/item/stack/sheet/metal/fifty",
                 "/obj/item/stack/cable_coil", back="any")
RND_CELLS = one("lab cells", "t", TABLE, ("/obj/machinery/cell_charger", {"pixel_y": 5}), "/obj/item/stock_parts/cell/high",
                back="any")
BEAKERS = one("beakers", "g", GTABLE, "/obj/item/reagent_containers/glass/beaker/large", "/obj/item/reagent_containers/dropper",
              back="any")
BIN = one("disposal bin", "DB", "/obj/machinery/disposal/bin", dest="station")


RND_ISLAND = Kit("lab bench", [
    cell(0, 0, GTABLE, "/obj/item/analyzer", "/obj/item/stack/cable_coil", label="g"),
    cell(1, 0, GTABLE, "/obj/item/multitool", "/obj/item/screwdriver", "/obj/item/wrench", label="g"),
    (0, 1, dict(obj=[(OCHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
], use=[(0, 1), (1, 1), (0, -1), (1, -1)], back=None)


def rnd(R):
    # cargo's chute drops materials on one tile; the lathes stand beside it; prints go out over the hall desk
    drop = (R.doors("keep") or [R.room.attrs["heart"]])[0]
    R.mark(drop, decal=[DELIVERY])
    desk = (R.doors("hall") or [drop])[0]
    solid = OPP[R.side("foyer")] if R.side("foyer") else None
    pen = R.place(RND_PEN, side=solid, near=drop)
    if pen:
        R.zone(pen.tiles + pen.uses, floor=DARK, edge=STRIPE)
    R.run([STOCK, RND_TOOLS], near=desk)
    R.place(button("desk button", "b", {"name": "Desk Shutters", "id": "rnd", "req_access_txt": "47"}), near=desk, must=False)
    R.run([RND_SHEETS, RND_CELLS], near=pen.uses[-1] if pen else drop)
    staff = (R.doors("spine") or [desk])[0]
    R.place(BIN, near=staff, must=False)
    R.place(BEAKERS, far=desk, must=False)
    # the middle of the lab is a workbench, not empty floor
    dwall = R.geo.field("dwall")
    R.place(RND_ISLAND, near=R.room.attrs["heart"], must=False, zone=(DARK, None), need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    R.run([one("lab coats", "L", "/obj/structure/closet/secure_closet/personal/cabinet", back="wall"),
           one("fire gear", "L", "/obj/structure/closet/firecloset")], far=desk)
    R.place(PLANT_K, far=staff, must=False)
    heart = R.room.attrs["heart"]
    nook = max(R.tiles, key=lambda p: (dist(p, heart), p))
    R.run([one("lab notes", "t", TABLE, PAPER, "/obj/item/pen", "/obj/item/folder/white", back="any"),
           one("samples", "g", GTABLE, "/obj/item/storage/box/beakers", "/obj/item/reagent_containers/dropper", back="any")],
          near=nook)
    R.mark(pen.uses[0] if pen else desk, "/obj/effect/landmark/start/scientist")


# ================================================================================================= foyer
PLANT_K = one("plant", "p", PLANT, back="any", use=())
SEAT = one("seat", "c", (CHAIR, {"dir": "IN"}), back="any", use=())


def foyer(R):
    # people wait here for the desks either side; the way through stays clear
    hall = (R.doors("hall") or [R.room.attrs["heart"]])[0]
    R.place(PLANT_K, near=hall, must=False)
    R.place(PLANT_K, near=hall, must=False)
    heart = R.room.attrs["heart"]
    dwall = R.geo.field("dwall")
    R.zone([p for p in R.tiles if dwall.get(p, 0) >= 1], floor=DARK)
    R.run([SEAT, SEAT], near=heart)
    R.mark(heart, "/obj/machinery/holopad")
    for q in R.doors("spine"):
        R.mark(q, decal=[STRIPE])


# ================================================================================================= shared pieces
CARPET = "/turf/open/floor/carpet"
PIPE = "/obj/machinery/atmospherics/pipe/simple/general/visible"
PAPER = ("/obj/item/paper_bin", {"pixel_x": -3, "pixel_y": 7})
L3, RADS, BOMBS = ("/obj/structure/closet/l3closet/scientist", "/obj/structure/closet/radiation",
                   "/obj/structure/closet/bombcloset")


def hang(name, kind, path, vs=None, label="m"):
    """A wall piece (button, sign, console on the wall): takes no floor."""
    return Kit(name, [(0, 0, dict(obj=[], open=True, free=True, label=label, mount=[(kind, path, vs or {})]))], back="wall")


def seat_at(u, v, kind=OCHAIR, *more):
    """A chair on a kit's use tile, turned to what it serves."""
    return (u, v, dict(obj=[(kind, {"dir": "OUT"})] + list(more), open=True, seat=True, label="c"))


def cheb(p, q):
    return max(abs(p[0] - q[0]), abs(p[1] - q[1]))


def near_tiles(R, tiles, r=1):
    return [p for p in R.tiles if any(cheb(p, t) <= r for t in tiles)]


# ================================================================================================= RD office
RD_DESK = Kit("RD desk", [
    cell(0, 0, TABLE, "/obj/item/folder/white", "/obj/item/stamp/rd", label="t"),
    cell(1, 0, TABLE, PAPER, "/obj/item/pen", label="t"),
    cell(2, 0, TABLE, "/obj/item/flashlight/lamp", label="t"),
    seat_at(1, 1, OCHAIR, "/obj/effect/landmark/start/research_director"),
], use=[(0, -1), (1, -1), (2, -1)], back=None)


def console(name, label, path):
    return one(name, label, (path, {"dir": "IN"}))


def rdoffice(R):
    # the RD sits facing the door with the department's control consoles behind the chair; visitors stand in front
    door = (R.doors("spine") or R.doors())[0]
    dwall = R.geo.field("dwall")
    desk = R.place(RD_DESK, near=R.room.attrs["heart"],
                   need=lambda pl: dist(pl.at(1, 1), door) > dist(pl.at(1, -1), door)
                   and all(dwall.get(t, 0) >= 1 for t in pl.tiles))
    chair = desk.at(1, 1) if desk else R.room.attrs["heart"]
    if desk:
        R.zone(near_tiles(R, desk.tiles), floor=CARPET)
    R.run([console("robot control", "C", "/obj/machinery/computer/robotics"),
           console("mech tracking", "C", "/obj/machinery/computer/mecha"),
           console("server control", "C", "/obj/machinery/computer/rdservercontrol"),
           console("AI restorer", "C", "/obj/machinery/computer/aifixer"),
           console("ID console", "C", "/obj/machinery/computer/card/minor/rd")], near=chair, side=None)
    servers = (R.doors("server") or [chair])[0]
    R.run([one("RD suit", "SU", "/obj/machinery/suit_storage_unit/rd"),
           one("RD locker", "L", "/obj/structure/closet/secure_closet/RD")], near=servers)
    R.run([one("Lamarr", "LC", "/obj/structure/displaycase/labcage", back="any"),
           one("files", "F", "/obj/structure/filingcabinet/chestdrawer", back="any")], near=door)
    R.place(one("bookcase", "B", "/obj/structure/bookcase/random"), far=door, must=False)
    R.place(BIN, far=chair, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Research Director RC", "department": "Research Director's Desk", "departmentType": 5,
                  "announcementConsole": 1}), near=chair, must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), near=chair, must=False)
    R.place(hang("lockdown button", "button", "/obj/machinery/button/door",
                 {"name": "Biohazard Shutter Control", "id": "Biohazard", "req_access_txt": "47"}), near=chair, must=False)


# ================================================================================================= servers
COLD_LOOP = Kit("cold loop", [
    cell(0, 0, ("/obj/machinery/atmospherics/components/unary/thermomachine/freezer/on", {"dir": "A+"}), label="FZ"),
    (1, 0, dict(obj=[("/obj/machinery/atmospherics/pipe/manifold/general/visible", {"dir": "OUT"})], open=True, label="=")),
    (1, 1, dict(obj=[("/obj/machinery/atmospherics/components/unary/vent_pump/on", {"dir": "OUT", "name": "server vent"})],
                open=True, label="v")),
    (2, 0, dict(obj=[(PIPE, {"dir": "A+"})], open=True, label="=")),
    (3, 0, dict(obj=[(PIPE, {"dir": ("A-", "IN")})], open=True, label="=")),
    (3, 1, dict(obj=[("/obj/machinery/atmospherics/components/unary/vent_pump/siphon/on", {"dir": "OUT", "name": "server vent"})],
                open=True, label="v")),
], use=[(0, 1)])
SERVER = one("server", "SV", "/obj/machinery/rnd/server")


def server(R):
    # the room is its own cold loop: a freezer feeding one vent and drawing from another; servers on the other walls
    door = R.doors()[0]
    loop = R.place(COLD_LOOP, far=door)
    R.run([SERVER, SERVER], far=door, near=None if loop else door)


# ================================================================================================= security post
SEC_DESK = Kit("records console", [
    cell(0, 0, ("/obj/machinery/computer/secure_data", {"dir": "IN"}), label="C"),
    seat_at(0, 1, "/obj/structure/chair/office", "/obj/effect/landmark/start/depsec/science"),
], use=[(0, 1)], back="any")


def secpost(R):
    # the officer sits at the glass watching the crossroads, the cell behind
    door = (R.doors("spine") or R.doors())[0]
    R.place(SEC_DESK, near=door)
    R.place(one("officer's locker", "L", "/obj/structure/closet/secure_closet/security/science"), far=door, must=False)
    R.place(one("recharger", "t", TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), back="any"), must=False, near=door)
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False, far=door)
    R.place(hang("flasher button", "button", "/obj/machinery/button/flasher", {"id": "scicell"}), must=False,
            near=(R.doors("cell") or [door])[0])


def cell_room(R):
    door = R.doors()[0]
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet", back="any", use=()), far=door, must=False)
    R.place(one("stool", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), far=door, must=False)
    R.place(hang("flasher", "button", "/obj/machinery/flasher", {"id": "scicell"}), far=door, must=False)


# ================================================================================================= nanites
NANO = Kit("nanite station", [
    cell(0, 0, "/obj/machinery/nanite_chamber", decal=[BOT], label="NC"),
    cell(1, 0, ("/obj/machinery/computer/nanite_chamber_control", {"dir": "IN"}), label="CC"),
    seat_at(1, 1),
], use=[(0, 1), (1, 1)])
NANO_PROG = Kit("program wall", [
    cell(0, 0, "/obj/machinery/nanite_program_hub", label="PH"),
    cell(1, 0, "/obj/machinery/nanite_program_hub", label="PH"),
    cell(2, 0, "/obj/machinery/nanite_programmer", label="PR"),
    cell(3, 0, ("/obj/machinery/computer/nanite_cloud_controller", {"dir": "IN"}), label="CL"),
    cell(4, 0, ("/obj/machinery/computer/nanite_cloud_controller", {"dir": "IN"}), label="CL"),
    seat_at(2, 1), seat_at(3, 1),
], use=[(0, 1), (1, 1), (2, 1), (3, 1), (4, 1)])
NANO_BENCH = Kit("nanite bench", [
    cell(0, 0, GTABLE, "/obj/item/nanite_remote", "/obj/item/nanite_scanner", label="g"),
    cell(1, 0, GTABLE, "/obj/item/storage/box/disks_nanite", ("/obj/item/folder/white", {"pixel_x": 4, "pixel_y": -3}), label="g"),
    cell(2, 0, GTABLE, "/obj/item/disk/nanite_program", "/obj/item/disk/nanite_program", label="g"),
], use=[(0, 1), (1, 1), (2, 1), (0, -1), (1, -1), (2, -1)], back=None)


def nanite(R):
    # crew come in for an injection: two chamber stations by the door; programming is the scientists' wall at the back
    door = R.doors()[0]
    dwall = R.geo.field("dwall")
    a = R.place(NANO, near=door)
    b = R.place(NANO, near=a.origin if a else door)
    for pl in (a, b):
        if pl:
            R.zone(pl.tiles + pl.uses, floor=DARK)
    R.place(NANO_PROG, far=door)
    R.place(NANO_BENCH, near=R.room.attrs["heart"], must=False, zone=(DARK, None), need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    seats = R.run([SEAT, SEAT], near=door)
    if seats:       # the people waiting for an injection sit on a rug
        R.zone([t for pl in seats for t in (pl.origin, pl.at(0, 1))], floor=CARPET)
    R.place(BIN, near=door, must=False)
    R.place(PLANT_K, far=door, must=False)
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/start/scientist")


# ================================================================================================= experimentation
EXP_DESK = Kit("experiment console", [
    cell(0, 0, ("/obj/machinery/computer/rdconsole/experiment", {"dir": "IN"}), label="RD"),
    seat_at(0, 1),
], use=[(0, 1)], back="any")
EXP_NOTES = Kit("notes bench", [
    cell(0, 0, TABLE, "/obj/item/taperecorder", "/obj/item/clipboard", label="t"),
    cell(1, 0, TABLE, "/obj/item/stack/sheet/mineral/plasma", "/obj/item/clothing/glasses/science", label="t"),
], use=[(0, 1), (1, 1)], back="any")


def chamber(R):
    R.put(R.room.attrs["heart"], "obj", obj=["/obj/machinery/rnd/experimentor"], decal=[BOT], label="EX")


def explab(R):
    # the experimentor works alone behind a blast door; its console must see it within 3 tiles, through the glass
    geo = R.geo
    machine = geo.rooms["chamber"].attrs.get("heart") if "chamber" in geo.rooms else None
    cdoor = (R.doors("chamber") or R.doors())[0]
    door = (R.doors("spine") or R.doors())[0]
    desk = R.place(EXP_DESK, near=cdoor, need=lambda pl: machine is None or cheb(pl.origin, machine) <= 3)
    R.place(EXP_NOTES, near=desk.origin if desk else cdoor, must=False)
    R.place(hang("blast door button", "button", "/obj/machinery/button/door",
                 {"name": "Test Chamber Blast Doors", "id": "telelab", "req_access_txt": "7"}), near=cdoor, must=False)
    R.run([one("biosuits", "L", L3), one("radiation suits", "L", RADS), one("bomb suits", "L", BOMBS)], near=door)
    R.run([one("tools", "t", TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/analyzer", back="any"),
           one("meters", "g", GTABLE, "/obj/item/geiger_counter", "/obj/item/clothing/glasses/meson", back="any"),
           one("parts", "g", GTABLE, "/obj/item/multitool", "/obj/item/assembly/igniter", back="any")], far=door)
    R.place(BIN, far=cdoor, must=False)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")
    for q in R.doors("chamber"):
        R.mark(q, decal=[STRIPE])


# ================================================================================================= xenobiology
XENO_LINE = Kit("slime processing", [
    cell(0, 0, "/obj/machinery/monkey_recycler", label="MR"),
    cell(1, 0, "/obj/machinery/processor/slime", label="SP"),
    cell(2, 0, "/obj/machinery/smartfridge/extract/preloaded", label="SF"),
    cell(3, 0, GTABLE, ("/obj/machinery/reagentgrinder", {"pixel_y": 6}), label="g"),
    cell(4, 0, "/obj/machinery/chem_master", label="CM"),
], use=[(0, 1), (1, 1), (2, 1), (3, 1), (4, 1)])
XENO_CONSOLE = Kit("slime console", [
    cell(0, 0, ("/obj/machinery/computer/camera_advanced/xenobio", {"dir": "IN"}), label="XC"),
    seat_at(0, 1),
], use=[(0, 1)], back="any")
XENO_ISLAND = Kit("extract bench", [
    cell(0, 0, GTABLE, "/obj/item/slime_extract/grey", "/obj/item/reagent_containers/syringe/plasma", label="g"),
    cell(1, 0, GTABLE, "/obj/item/reagent_containers/glass/beaker/large", "/obj/item/reagent_containers/dropper", label="g"),
    cell(2, 0, GTABLE, "/obj/item/slime_scanner", "/obj/item/clothing/glasses/science", label="g"),
    seat_at(1, 1),
], use=[(0, 1), (1, 1), (2, 1), (0, -1), (1, -1), (2, -1)], back=None)


XENO_PREP = Kit("monkey bench", [
    cell(0, 0, TABLE, "/obj/item/storage/box/monkeycubes", "/obj/item/storage/box/monkeycubes", label="t"),
    cell(1, 0, TABLE, "/obj/item/reagent_containers/glass/bucket", "/obj/item/extinguisher", label="t"),
    seat_at(0, 1),
], use=[(0, 1), (1, 1), (0, -1), (1, -1)], back=None)


def apart(R, pl, r):
    """A kit's pieces stand at least r tiles clear of every piece already in the room."""
    mine = set(pl.tiles)
    return not any(R.geo.taken.get(p) == "obj" and p not in mine and any(cheb(p, t) <= r for t in mine) for p in R.tiles)


def xeno(R):
    # monkeys in, slimes fed in the pens, extracts back out: the consoles look down the pens' aisle, the processing
    # line stands on the wall away from them, the island in the middle is where extracts get mixed
    gate = R.doors("pens")
    door = (R.doors("spine") or R.doors())[0]
    mid = gate[len(gate) // 2] if gate else R.room.attrs["heart"]
    pens = R.side("pens")
    dwall = R.geo.field("dwall")
    a = R.place(XENO_CONSOLE, side=pens, near=mid)
    R.place(XENO_CONSOLE, side=pens, near=mid, must=False)
    line = R.place(XENO_LINE, side=OPP[pens] if pens else None, near=R.room.attrs["heart"])
    if line:
        R.zone(line.tiles + line.uses, floor=DARK)
    R.place(XENO_ISLAND, near=R.room.attrs["heart"], must=False, zone=(DARK, None), need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    # a second bench where monkeys are unboxed, clear of the first so both can be walked round
    R.place(XENO_PREP, near=R.room.attrs["heart"], must=False, zone=(DARK, None),
            need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles) and apart(R, pl, 2))
    R.run([one("syringes", "g", GTABLE, "/obj/item/storage/box/beakers", "/obj/item/storage/box/syringes", back="any"),
           one("notes", "t", TABLE, PAPER, "/obj/item/pen", back="any")], near=line.origin if line else door)
    R.run([one("biosuits", "L", L3), one("biosuits", "L", L3), one("water tank", "WT", "/obj/structure/reagent_dispensers/watertank")],
          near=door)
    kill = R.place(one("deathsposal", "DB", "/obj/machinery/disposal/bin", dest="deathsposal",
                       decal=["/obj/effect/turf_decal/stripes/red/box"]), far=door, must=False)
    if kill:
        R.place(hang("deathsposal sign", "sign", "/obj/structure/sign/warning/deathsposal"), near=kill.origin, must=False)
    R.place(hang("lockdown button", "button", "/obj/machinery/button/door",
                 {"name": "Containment Lockdown", "id": "xeno_containment", "req_access_txt": "55"}), near=mid, must=False)
    R.place(PLANT_K, near=door, must=False)
    for q in gate:
        R.mark(q, decal=[(STRIPE, {"dir": pens})] if pens else [STRIPE])
    R.mark(a.uses[0] if a else mid, "/obj/effect/landmark/start/scientist")
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


def pens(R):
    # each pen: a windoor in its glass front, a bin on the aisle that drops food through an outlet inside, a button
    geo = R.geo
    for p, dr in sorted(geo.doors.items()):
        if dr.get("b") != R.rid or not str(dr.get("a", "")).startswith("pen"):
            continue
        d, ident = dr["dir"], dr["spec"]["id"]
        for side in (CW[d], CCW[d]):
            g = step(p, side)
            bin_at, out_at = step(g, OPP[d]), step(g, d)
            if geo.kind.get(g) == "glass" and R.free(bin_at) and bin_at not in R.front and bin_at not in R.trunk                     and geo.kind.get(out_at) == "floor":
                R.put(bin_at, "obj", obj=["/obj/machinery/disposal/bin"], dest=("outlet", ident), label="DB")
                geo.cells.setdefault(out_at, []).append({"obj": [], "outlet": ident, "throw": d})
                break
        R.place(hang("pen button", "button", "/obj/machinery/button/door",
                     {"name": "Containment Blast Doors", "id": ident, "req_access_txt": "55"}),
                near=dr["sides"][R.rid], must=False)


# ================================================================================================= toxins
def burn_chamber():
    """tg's toxins incinerator as a prefab, anchored on the tile one east and one south of the space pocket it vents
    into: vent doors, the burn cell (injector, igniter, sensor, scrubber), an airlock with its pumps, the controls
    outside, a two-port fuel mixer feeding the injector and a waste line back out to a port."""
    VAC, EN = "/turf/open/floor/engine/vacuum", "/turf/open/floor/engine"
    E_PIPE = (PIPE, {"dir": 4})
    AT = "/obj/machinery/atmospherics/components"
    m = {}
    for dx in range(1, 6):
        m[(dx, 0)] = dict(raw={"turf": "wall"})
    for dy in (1, 2, 3):
        m[(0, dy)] = dict(raw={"floor": VAC, "obj": ["/obj/machinery/door/poddoor/incinerator_toxmix"]})
    m[(1, 1)] = dict(raw={"floor": VAC, "obj": []})
    m[(1, 2)] = dict(raw={"floor": VAC, "obj": ["/obj/machinery/air_sensor/atmos/toxins_mixing_tank"]})
    m[(1, 3)] = dict(raw={"floor": VAC, "obj": [("/obj/structure/sign/warning/vacuum/external", {"pixel_y": 32})]})
    m[(2, 1)] = dict(raw={"floor": VAC, "obj": [(AT + "/unary/outlet_injector/atmos/toxins_mixing_input", {"dir": 4})]})
    m[(2, 2)] = dict(raw={"floor": VAC, "obj": ["/obj/machinery/igniter/incinerator_toxmix"]})
    m[(2, 3)] = dict(raw={"floor": VAC, "obj": [(AT + "/unary/vent_scrubber/on", {"dir": 4})]})
    for p in ((3, 1), (3, 3), (5, 1), (5, 3)):
        m[p] = dict(raw={"turf": "rwall", "obj": [E_PIPE]})
    m[(3, 2)] = dict(raw={"floor": EN, "obj": ["/obj/effect/mapping_helpers/airlock/locked",
                                              "/obj/machinery/door/airlock/research/glass/incinerator/toxmix_exterior"]})
    m[(5, 2)] = dict(raw={"floor": EN, "obj": ["/obj/effect/mapping_helpers/airlock/locked",
                                              "/obj/machinery/door/airlock/research/glass/incinerator/toxmix_interior"]}, back="door")
    m[(4, 1)] = dict(raw={"floor": EN, "obj": [(AT + "/binary/pump/on", {"dir": 8}), ("/obj/structure/sign/warning/fire", {"pixel_y": -32})]})
    m[(4, 2)] = dict(raw={"floor": EN, "obj": [AT + "/binary/dp_vent_pump/high_volume/incinerator_toxmix"]})
    m[(4, 3)] = dict(raw={"floor": EN, "obj": ["/obj/machinery/atmospherics/pipe/layer_manifold", (AT + "/binary/pump/on", {"dir": 4}),
                                              ("/obj/machinery/airlock_sensor/incinerator_toxmix", {"pixel_y": 24})]})
    # controls on the lab side of the airlock
    m[(6, 1)] = dict(take="open", cell={"label": "ct", "obj": [E_PIPE, "/obj/machinery/meter",
                     ("/obj/machinery/button/door/incinerator_vent_toxmix", {"pixel_x": -25, "pixel_y": 5}),
                     ("/obj/machinery/button/ignition/incinerator/toxmix", {"pixel_x": -25, "pixel_y": -5})]})
    m[(6, 3)] = dict(take="open", cell={"label": "ct", "obj": [E_PIPE, "/obj/machinery/meter",
                     ("/obj/machinery/embedded_controller/radio/airlock_controller/incinerator_toxmix", {"pixel_x": -24})]})
    m[(6, 2)] = dict(front=True, cell={"obj": [], "decal": [STRIPE]})
    m[(6, 0)] = dict(cell={"obj": [("/obj/machinery/airalarm/mixingchamber", {"dir": 4, "pixel_x": -24})]})
    # fuel in: two canister ports -> mixer -> pump -> the injector's pipe
    m[(9, -1)] = dict(take="open", cell={"label": "po", "obj": [(AT + "/unary/portables_connector/visible", {"dir": 1})], "decal": [BOT]})
    m[(10, 0)] = dict(take="open", cell={"label": "po", "obj": [(AT + "/unary/portables_connector/visible", {"dir": 8})], "decal": [BOT]})
    m[(9, 0)] = dict(take="open", cell={"label": "mx", "obj": [(AT + "/trinary/mixer", {"dir": 1, "name": "Fuel Mixer"})]})
    m[(9, 1)] = dict(take="open", cell={"label": "=", "obj": [(PIPE, {"dir": 10})]})
    m[(8, 1)] = dict(take="open", cell={"label": "pu", "obj": [(AT + "/binary/pump", {"dir": 8, "name": "Mix to Chamber"})]})
    m[(7, 1)] = dict(take="open", cell={"label": "=", "obj": [E_PIPE]})
    # waste out: the chamber's scrubber -> pump -> a port
    m[(7, 3)] = dict(take="open", cell={"label": "=", "obj": [E_PIPE]})
    m[(8, 3)] = dict(take="open", cell={"label": "pu", "obj": [(AT + "/binary/pump", {"dir": 4, "name": "Chamber to Waste"})]})
    m[(9, 3)] = dict(take="open", cell={"label": "po", "obj": [(AT + "/unary/portables_connector/visible", {"dir": 8})], "decal": [BOT]})
    return m


def cans(name, *gases):
    return Kit(name, [cell(i, 0, "/obj/machinery/portable_atmospherics/canister/%s" % g, decal=[BOT], label="cn")
                      for i, g in enumerate(gases)], use=[(i, 1) for i in range(len(gases))])


BOMB_BENCH = Kit("bomb bench", [
    cell(0, 0, RTABLE, "/obj/item/transfer_valve", "/obj/item/assembly/signaler", "/obj/item/assembly/signaler", label="t"),
    cell(1, 0, RTABLE, "/obj/item/assembly/timer", "/obj/item/assembly/prox_sensor", "/obj/item/screwdriver", label="t"),
    cell(2, 0, RTABLE, "/obj/item/tank/internals/plasma", "/obj/item/tank/internals/oxygen", "/obj/item/transfer_valve", label="t"),
    seat_at(0, 1), seat_at(2, 1),
], use=[(0, 1), (1, 1), (2, 1), (0, -1), (1, -1), (2, -1)], back=None)


def toxins(R):
    # canisters roll from the bay to the fuel ports; tanks are filled, a bomb is built at the bench and carried out
    # the maintenance door to the launch room. The burn chamber and its plumbing are already stamped in.
    geo = R.geo
    door = (R.doors("spine") or R.doors())[0]
    out = (R.doors("maint") or [door])[0]
    ports = sorted(p for p in R.tiles if any(c.get("label") == "po" for c in geo.cells.get(p, [])))
    plumb = [p for p in R.tiles if geo.taken.get(p) == "open"]
    if plumb:
        R.zone(near_tiles(R, plumb, 0) + [p for p in near_tiles(R, plumb, 1) if p in R.front], floor=DARK, edge=STRIPE)
    port = ports[0] if ports else R.room.attrs["heart"]
    dwall = geo.field("dwall")
    bays = R.run([cans("plasma canisters", "toxins", "toxins", "toxins", "toxins"),
                  cans("oxygen canisters", "oxygen", "oxygen", "oxygen", "oxygen"),
                  cans("other canisters", "nitrous_oxide", "carbon_dioxide", "toxins")], near=port)
    for pl in bays:
        R.zone(pl.tiles, floor=DARK)
    R.run([one("big scrubber", "sc", "/obj/machinery/portable_atmospherics/scrubber/huge", decal=[BOT]),
           one("pump", "pp", "/obj/machinery/portable_atmospherics/pump", decal=[BOT]),
           one("scrubber", "sc", "/obj/machinery/portable_atmospherics/scrubber", decal=[BOT])], near=out)
    R.run([one("bomb suits", "L", BOMBS), one("bomb suits", "L", BOMBS), one("biosuits", "L", L3),
           one("wardrobe", "W", "/obj/machinery/vending/wardrobe/science_wardrobe"),
           one("tank dispenser", "TD", "/obj/structure/tank_dispenser"),
           one("plasma vendor", "V", "/obj/machinery/vending/plasmaresearch")], near=door)
    R.place(BOMB_BENCH, near=door, must=False, zone=(DARK, None), need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    R.place(BIN, near=door, must=False)
    R.place(hang("explosives sign", "sign", "/obj/structure/sign/warning/explosives"), near=door, must=False)
    R.place(PLANT_K, near=door, must=False)
    R.mark(door, "/obj/effect/landmark/start/scientist")


# ================================================================================================= testing lab
INJECT = Kit("test injector", [
    (0, 0, dict(obj=[(PIPE, {"dir": "IN"})], open=True, label="=")),
    (0, 1, dict(obj=[(PIPE, {"dir": "IN"})], open=True, label="=")),
    cell(0, 2, ("/obj/machinery/atmospherics/components/unary/outlet_injector/on", {"dir": "OUT"}), label="ij"),
], back=None, mirror=False)
TEST_PORT = Kit("test port", [
    (0, 0, dict(obj=[("/obj/machinery/atmospherics/components/binary/pump", {"dir": "OUT", "name": "Port to Chamber"})],
                open=True, label="pu")),
    (0, 1, dict(obj=[("/obj/machinery/atmospherics/components/unary/portables_connector/visible", {"dir": "OUT"})],
                open=True, decal=[BOT], label="po")),
], back=None, mirror=False)
TEST_DESK = Kit("test controls", [
    cell(0, 0, TABLE, ("/obj/machinery/button/ignition", {"id": "testigniter", "pixel_x": -6, "pixel_y": 2}),
         ("/obj/machinery/button/door", {"name": "Test Chamber Blast Doors", "id": "testlab", "req_access_txt": "47",
                                         "pixel_x": 4, "pixel_y": 2}), label="t"),
    cell(1, 0, TABLE, ("/obj/machinery/computer/security/telescreen", {"name": "Test Chamber Monitor",
                                                                      "network": 'list("test")', "dir": "IN"}), label="t"),
    seat_at(0, 1),
], use=[(0, 1), (1, 1)], back="any")
CHEM_BENCH = Kit("chem bench", [
    cell(0, 0, "/obj/machinery/chem_dispenser", label="CD"),
    cell(1, 0, "/obj/machinery/chem_heater", label="CH"),
    cell(2, 0, "/obj/machinery/chem_master", label="CM"),
    cell(3, 0, TABLE, ("/obj/machinery/reagentgrinder", {"pixel_y": 6}), label="t"),
    seat_at(1, 1),
], use=[(0, 1), (1, 1), (2, 1), (3, 1)])


def inward(R, q):
    """The direction a door's inside tile is entered in."""
    for d in (1, 2, 4, 8):
        if R.geo.what(step(q, d)) in ("door", "keep_door") and step(q, OPP[d]) in R.tiles:
            return OPP[d]
    return None


def testchamber(R):
    # gas comes in by a pipe under the door from a port outside; a sparker on the far wall lights it
    q = R.doors()[0]
    d = inward(R, q)
    if d:
        R.place(INJECT, on={q}, side=OPP[d])
    R.place(hang("sparker", "button", "/obj/machinery/sparker", {"id": "testigniter"}), far=q, must=False)


def testing(R):
    # three benches: the ignition chamber's controls at its glass, a chemistry bench, and a magnet range in the nub
    door = (R.doors("spine") or R.doors())[0]
    cq = (R.doors("testchamber") or [door])[0]
    d = inward(R, cq)
    if d and cq != door:
        R.place(TEST_PORT, on={cq}, side=OPP[d])
    R.place(TEST_DESK, side=R.side("testchamber"), near=cq, must=False)
    bench = R.place(CHEM_BENCH, near=door)
    depth = R.geo.field("depth")
    deep = max(R.tiles, key=lambda p: (depth.get(p, 0), p))
    nub = [p for p in R.tiles if cheb(p, deep) <= 2 and depth.get(p, 0) >= depth.get(deep, 0) - 3]
    spot = min(nub, key=lambda p: (sum(cheb(p, t) for t in nub), p))
    R.zone(nub, floor=DARK)
    R.put(spot, "obj", obj=["/obj/machinery/magnetic_module", "/obj/structure/target_stake"], label="MG")
    R.place(one("magnet controls", "t", TABLE, ("/obj/machinery/magnetic_controller", {"pixel_y": 3, "autolink": 1}), back="any"),
            near=spot, must=False, need=lambda pl: pl.origin not in nub)
    R.run([one("recharger", "t", TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), back="any"),
           one("crate", "cr", "/obj/structure/closet/crate", "/obj/item/stack/sheet/metal/fifty", back="any")],
          near=bench.origin if bench else door)
    R.place(BIN, near=door, must=False)
    R.place(PLANT_K, near=door, must=False)


# ================================================================================================= launch room
def launchrun(R):
    gate = (R.doors("keep") or R.doors())[0]
    seat = max(R.tiles, key=lambda p: (dist(p, gate), p))
    d = [k for k in (1, 2, 4, 8) if dist(step(seat, k), gate) < dist(seat, gate)][0] if seat != gate else 4
    R.mark(seat, ("/obj/machinery/mass_driver", {"dir": d, "id": "toxinsdriver"}), label="MD")
    for p in R.tiles:
        if p != seat:
            R.mark(p, decal=[(STRIPE, {"dir": 1})])


def launch(R):
    # a bomb is set on the driver through the windoor and thrown to the range; the watchers sit at the glass
    door = (R.doors("maint") or R.doors())[0]
    hatch = (R.doors("launchrun") or [door])[0]
    # the watchers face the way the driver throws
    run = R.geo.rooms.get("launchrun")
    gate = [p for p, dr in R.geo.doors.items() if dr.get("keep") and "launchrun" in dr["sides"]]
    view = R.side("space")
    if run and gate:
        seat = max(run.tiles, key=lambda p: (dist(p, gate[0]), p))
        view = 4 if gate[0][0] > seat[0] else 8 if gate[0][0] < seat[0] else 1 if gate[0][1] > seat[1] else 2
    R.mark(hatch, decal=["/obj/effect/turf_decal/loading_area"])
    R.place(hang("driver button", "button", "/obj/machinery/button/massdriver", {"id": "toxinsdriver"}), near=hatch, must=False)
    R.place(one("doppler array", "DA", ("/obj/machinery/doppler_array/research/science", {"dir": "OUT"}), back="any"),
            side=view, far=door, must=False)
    R.run([one("watch seat", "c", (CHAIR, {"dir": "OUT"}), back="any", use=()),
           one("watch seat", "c", (CHAIR, {"dir": "OUT"}), back="any", use=())], side=view, far=door)
    R.place(one("test site crate", "cr", ("/obj/structure/closet/crate/secure", {"name": "Test Site Materials Crate",
                                                                                "req_access_txt": "8"}), back="any"),
            near=door, must=False)
    R.place(hang("range sign", "sign", "/obj/structure/sign/warning/securearea", {"name": "BOMB RANGE"}), far=door, must=False)


# ================================================================================================= the streets
DOOR_SIGNS = [("xeno", "/obj/structure/sign/warning/biohazard"), ("toxins", "/obj/structure/sign/warning/explosives"),
              ("testing", "/obj/structure/sign/warning/nosmoking"), ("explab", "/obj/structure/sign/warning/securearea"),
              ("nanite", "/obj/structure/sign/warning/nosmoking")]


def spine(R):
    # a street, not a room: a few things at its edges, never in a doorway, the middle always clear
    west = (R.doors("hall") or R.doors())[0]
    heart = R.room.attrs["heart"]
    tox = (R.doors("toxins") or [heart])[0]

    def length(p, d):
        n, q = 1, step(p, d)
        while q in R.tiles:
            n, q = n + 1, step(q, d)
        q = step(p, OPP[d])
        while q in R.tiles:
            n, q = n + 1, step(q, OPP[d])
        return n
    R.zone([p for p in R.tiles if length(p, 1) > 6 and length(p, 4) > 6], floor=DARK)
    R.run([one("cigarettes", "V", "/obj/machinery/vending/cigarette", use=()),
           one("coffee", "V", "/obj/machinery/vending/coffee", use=())], near=west)
    R.run([one("fire closet", "L", "/obj/structure/closet/firecloset", use=()),
           one("emergency closet", "L", "/obj/structure/closet/emcloset", use=())], near=heart)
    R.place(Kit("shower", [(0, 0, dict(obj=[("/obj/machinery/shower", {"dir": "IN"})], open=True, label="sh"))]),
            near=tox, must=False)
    R.place(one("cola", "V", "/obj/machinery/vending/cola/random", use=()), near=tox, must=False)
    for target in (heart, tox, (R.doors("xeno") or [heart])[0], (R.doors("testing") or [heart])[0]):
        R.place(PLANT_K, near=target, must=False)
    R.run([SEAT, SEAT], near=(R.doors("rdoffice") or [heart])[0])
    R.run([SEAT, SEAT], near=(R.doors("nanite") or [heart])[0])
    # a warning on the wall beside each door that needs one
    for room, sign in DOOR_SIGNS:
        for q in R.doors(room)[:1]:
            R.place(hang("%s sign" % room, "sign", sign), near=q, must=False,
                    need=lambda pl, q=q: 1 <= dist(pl.origin, q) <= 3)


ASSETS = {"pen": lambda R: None, "burn": lambda R: None, "mechbay": mechbay, "robotics": robotics, "surgery": surgery, "rnd": rnd, "foyer": foyer,
          "rdoffice": rdoffice, "server": server, "secpost": secpost, "cell": cell_room, "nanite": nanite,
          "chamber": chamber, "explab": explab, "xeno": xeno, "pens": pens, "toxins": toxins,
          "testchamber": testchamber, "testing": testing, "launchrun": launchrun, "launch": launch, "spine": spine}
