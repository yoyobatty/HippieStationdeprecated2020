"""Room assets for the v6 station's Science: Science v3's rooms (assets/science.py) with the pieces the new block
carries itself.

  launch      the mass driver fires out of a door in the hull (v3 kept an old one from the map); windows onto the
              range and the test site's monitor
  mechbay     the charge bays lie along the wall as on the stock maps: port, pad, console in one row
  spine       the research street: v3's, without the vending pair at its west end when that end is the maint door
"""
from forge.proc.geo import step
from forge.proc.place import Kit, cell, dist
from assets.science import ASSETS as V3, STRIPE, CHAIR, ENG, BORG, BAY_TOOLS, FUEL, one, hang, burn_chamber
from assets.science import button, near_tiles, cans, DARK, BOT, BOMBS, L3, BOMB_BENCH, BIN, PLANT_K
from assets.science import foyer as v3_foyer, PIPE, TABLE, seat_at, RD_DESK, CARPET, console
from plan.canvas import HULL_WINDOWS, to_map

OPP = {1: 2, 2: 1, 4: 8, 8: 4}


def _gate(R):
    """The driver's blast door: the launch run's door to space."""
    run = R.geo.rooms.get("launchrun")
    if not run:
        return None, None
    gate = [p for p, dr in R.geo.doors.items() if "launchrun" in dr["sides"] and dr["spec"].get("type") == "driver"]
    return run, (gate[0] if gate else None)


def launchrun(R):
    # the driver stands at the far end of the run and throws towards the blast door; the run is striped
    run, gate = _gate(R)
    if gate is None:
        return
    seat = max(R.tiles, key=lambda p: (dist(p, gate), p))
    d = [k for k in (1, 2, 4, 8) if dist(step(seat, k), gate) < dist(seat, gate)][0] if seat != gate else 2
    R.mark(seat, ("/obj/machinery/mass_driver", {"dir": d, "id": "toxinsdriver"}), label="MD")
    for p in R.tiles:
        if p != seat:
            R.mark(p, decal=[(STRIPE, {"dir": 1})])


# a charge bay as Meta lays it: the port, its recharge pad and the power console in one row against the wall; the
# port charges the pad beside it. A mech parks on the pad from the floor in front.
CHARGE_ROW = Kit("charge bay", [
    cell(0, 0, ("/obj/machinery/mech_bay_recharge_port", {"dir": "A+"}), floor="/turf/open/floor/plating", label="MP"),
    (1, 0, dict(obj=[], open=True, floor="/turf/open/floor/mech_bay_recharge_floor", label="pad")),
    cell(2, 0, ("/obj/machinery/computer/mech_bay_power_console", {"dir": "IN"}), floor="/turf/open/floor/circuit", label="MC"),
], use=[(1, 1), (2, 1)])


def grabs(console, port):
    """Whether a mech bay power console would take this port: it looks one tile round itself first, then exactly two
    tiles out in a straight line (mech_bay.dm reconnect())."""
    dx, dy = abs(console[0] - port[0]), abs(console[1] - port[1])
    return max(dx, dy) <= 1 or (min(dx, dy) == 0 and max(dx, dy) == 2)


def apart(pl, other):
    # each console must reach only its own port
    return not grabs(pl.at(2, 0), other.at(0, 0)) and not grabs(other.at(2, 0), pl.at(0, 0))


def mechbay(R):
    # a mech drives in through the robotics shutters, parks on a pad, leaves by the launch shutters onto the hall
    turn = R.apron("robotics", 4)
    lane = R.apron("hall", 3)
    R.reserve(turn + lane)
    R.zone(lane, floor=ENG, edge=STRIPE)
    far = OPP[R.side("robotics")]
    mid = turn[len(turn) // 2] if turn else R.room.attrs["heart"]
    first = R.place(CHARGE_ROW, side=far, near=mid)
    R.place(CHARGE_ROW, side=far, near=first.origin if first else mid,
            need=lambda pl: first is None or apart(pl, first))
    R.run([BORG, BORG], side=R.side("robotics"), near=mid)
    R.place(BAY_TOOLS, near=mid, must=False)
    R.place(FUEL, far=mid, must=False)
    R.place(button("launch button", "b", {"name": "Mech Bay Door Control", "id": "Skynet_launch", "req_access_txt": "29"}),
            near=lane[0] if lane else mid, must=False)
    R.place(button("shutter button", "b", {"name": "Robotics Shutters", "id": "robo_mechbay", "req_access_txt": "29"}),
            side=R.side("robotics"), near=mid, must=False)


def launch(R):
    # a bomb is set on the driver through the windoor and thrown out to the range. The hull in front is glazed in
    # viewing sections; on the piers between them hang the test site monitor and the range camera, the watch seats
    # face the glass, the doppler array listens beside it
    door = (R.doors("toxins") or R.doors())[0]
    hatch = (R.doors("launchrun") or [door])[0]
    R.mark(hatch, decal=["/obj/effect/turf_decal/loading_area"])
    glass = {to_map(p) for p in HULL_WINDOWS}
    front = sorted(p for p in R.tiles if (p[0], p[1] - 1) in glass)          # floor right behind a window
    piers = sorted(p for p in R.tiles if (p[0], p[1] - 1) not in glass
                   and (p[0] - 1, p[1] - 1) in glass and (p[0] + 1, p[1] - 1) in glass)
    if piers:
        R.mark(piers[0], ("/obj/machinery/computer/security/telescreen/toxins", {"dir": 1, "pixel_y": -30}))
        R.mark(piers[-1], ("/obj/machinery/camera", {"dir": 2, "network": 'list("ss13","rd","toxins")',
                                                     "c_tag": "Toxins - Launch Range"}))
        seats = [q for q in front if abs(q[0] - piers[0][0]) == 1]
        for q in seats:
            R.mark(q, (CHAIR, {"dir": 2}))
        R.reserve(seats)
    R.place(hang("driver button", "button", "/obj/machinery/button/massdriver", {"id": "toxinsdriver"}), near=hatch, must=False)
    R.place(hang("blast door button", "button", "/obj/machinery/button/door",
                 {"name": "Mass Driver Door", "id": "toxinsdriver", "req_access_txt": "8"}), near=hatch, must=False)
    R.place(one("doppler array", "DA", ("/obj/machinery/doppler_array/research/science", {"dir": 2}), back="any"),
            near=front[0] if front else door, must=False)
    R.place(one("test site crate", "cr", ("/obj/structure/closet/crate/secure", {"name": "Test Site Materials Crate",
                                                                                "req_access_txt": "8"}), back="any"),
            near=door, must=False)
    R.place(hang("range sign", "sign", "/obj/structure/sign/warning/securearea", {"name": "BOMB RANGE"}), near=hatch, must=False)


def toxins(R):
    # v3's toxins with its own stock first: tanks and plasma by the door, the suits after; the wardrobe is out in the
    # foyer. The burn chamber and its plumbing are already stamped in.
    geo = R.geo
    door = (R.doors("toxhall") or R.doors())[0]
    ports = sorted(p for p in R.tiles if any(c.get("label") == "po" for c in geo.cells.get(p, [])))
    plumb = [p for p in R.tiles if geo.taken.get(p) == "open"]
    if plumb:
        R.zone(near_tiles(R, plumb, 0) + [p for p in near_tiles(R, plumb, 1) if p in R.front], floor=DARK, edge=STRIPE)
    port = ports[0] if ports else R.room.attrs["heart"]
    dwall = geo.field("dwall")
    R.run([one("tank dispenser", "TD", "/obj/structure/tank_dispenser"),
           one("plasma vendor", "V", "/obj/machinery/vending/plasmaresearch")], near=door)
    bays = R.run([cans("plasma canisters", "toxins", "toxins", "toxins", "toxins"),
                  cans("oxygen canisters", "oxygen", "oxygen", "oxygen", "oxygen"),
                  cans("other canisters", "nitrous_oxide", "carbon_dioxide")], near=port)
    for pl in bays:
        R.zone(pl.tiles, floor=DARK)
    R.run([one("big scrubber", "sc", "/obj/machinery/portable_atmospherics/scrubber/huge", decal=[BOT]),
           one("pump", "pp", "/obj/machinery/portable_atmospherics/pump", decal=[BOT]),
           one("scrubber", "sc", "/obj/machinery/portable_atmospherics/scrubber", decal=[BOT])], near=port)
    R.run([one("bomb suits", "L", BOMBS), one("bomb suits", "L", BOMBS), one("biosuits", "L", L3)], near=door)
    R.place(BOMB_BENCH, near=door, must=False, zone=(DARK, None), need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    R.place(BIN, near=door, must=False)
    R.place(hang("explosives sign", "sign", "/obj/structure/sign/warning/explosives"), near=door, must=False)
    R.mark(door, "/obj/effect/landmark/start/scientist")


def foyer(R):
    # v3's foyer, with the science wardrobe where every scientist passes on the way in: tucked into a corner beside
    # the street shutters, off their apron
    v3_foyer(R)
    fronts = set(R.doors())
    corner = lambda q: sum(step(q, d) not in R.tiles for d in (1, 2, 4, 8)) >= 2 and q not in fronts
    R.place(one("science wardrobe", "W", "/obj/machinery/vending/wardrobe/science_wardrobe"),
            near=(R.doors("spine") or [R.room.attrs["heart"]])[0], need=lambda pl: corner(pl.origin), must=False)
    # the division's name either side of its front doors, read from the arterial
    side = R.side("hall")
    for q in R.doors("hall")[:1]:
        for _ in range(2):
            R.place(hang("science sign", "sign", "/obj/structure/sign/departments/science"), side=side, near=q, must=False)


def toxhall(R):
    # the corridor down to toxins: an emergency closet and a shower by the toxins door, nothing in the way
    tox = (R.doors("toxins") or R.doors())[0]
    R.place(one("emergency closet", "L", "/obj/structure/closet/emcloset", use=()), near=tox, must=False)
    R.place(one("fire closet", "L", "/obj/structure/closet/firecloset", use=()), near=tox, must=False)
    R.place(hang("explosives sign", "sign", "/obj/structure/sign/warning/explosives"), near=tox, must=False)
    for q in R.doors("xeno")[:1]:
        R.place(hang("xenobiology sign", "sign", "/obj/structure/sign/departments/xenobio"), near=q, must=False)


def burn_chamber_closed():
    """v3's burn chamber with its own north wall: here the chamber sits low in toxins, a strip of lab floor above it
    leading in from the corridor, so the room's wall line can't close it. The vent column's corners are walled too."""
    m = burn_chamber()
    for dx in range(0, 6):
        m[(dx, 4)] = dict(raw={"turf": "wall"})
    m[(0, 0)] = dict(raw={"turf": "wall"})
    return m


# ================================================================================================= servers
AT = "/obj/machinery/atmospherics/components/unary"
SERVER_SIGN = ("/obj/structure/sign/warning/securearea",
               {"name": "SERVER ROOM", "desc": "A warning sign which reads 'SERVER ROOM'.", "pixel_y": 32})


def server_core():
    """The server chamber as Meta and Box lay it: two servers on one side, two server vents on the other, a manifold
    between them; sealed off from the control room by a glazed wall with a glass airlock. The freezer in the control
    room feeds the loop through the airlock. Anchored on the bottom tile of the glazed wall, the chamber to its east."""
    SRV, TEL = "/turf/open/floor/circuit/telecomms/server", "/turf/open/floor/plasteel/dark/telecomms"
    WIN = "/obj/effect/spawner/structure/window/reinforced"
    E = (PIPE, {"dir": 4})
    m = {
        (0, 0): dict(raw={"floor": "/turf/open/floor/plating", "obj": [WIN]}),
        (0, 1): dict(raw={"floor": "/turf/open/floor/plasteel/dark", "obj": [
            "/obj/machinery/door/firedoor",
            ("/obj/machinery/door/airlock/command/glass", {"name": "Server Access", "req_access_txt": "30"}), E]},
            back="door"),
        (0, 2): dict(raw={"floor": "/turf/open/floor/plating", "obj": [WIN, SERVER_SIGN]}),
        (1, 0): dict(raw={"floor": SRV, "obj": ["/obj/machinery/rnd/server"]}),
        (1, 1): dict(raw={"floor": TEL, "obj": [E]}),
        (1, 2): dict(raw={"floor": SRV, "obj": ["/obj/machinery/rnd/server"]}),
        (2, 0): dict(raw={"floor": SRV, "obj": [(AT + "/vent_pump/siphon/on", {
            "dir": 1, "name": "server vent", "external_pressure_bound": 120})]}),
        (2, 1): dict(raw={"floor": TEL, "obj": [
            ("/obj/machinery/atmospherics/pipe/manifold/general/visible", {"dir": 4}),
            ("/obj/machinery/light/small", {"dir": 4}),
            ("/obj/machinery/airalarm/server", {"dir": 8, "pixel_x": 22})]}),
        (2, 2): dict(raw={"floor": SRV, "obj": [(AT + "/vent_pump/on", {
            "dir": 2, "name": "server vent", "external_pressure_bound": 140, "pressure_checks": 0})]}),
        # the control room's side: the freezer in the corner, its pipe turning in through the airlock
        (-1, 2): dict(take="obj", cell={"label": "FZ", "obj": [(AT + "/thermomachine/freezer/on", {"dir": 2})]}),
        (-1, 1): dict(take="open", cell={"label": "=", "obj": [(PIPE, {"dir": 5})]}),
    }
    return m


SERVER_DESK = Kit("server control", [
    cell(0, 0, ("/obj/machinery/computer/rdservercontrol", {"dir": "IN"}), label="C"),
    seat_at(0, 1, "/obj/structure/chair/office/light"),
], use=[(0, 1)], back="any")


def server(R):
    # the control room: the server console looks at the glass, a table and the files beside it, the freezer already
    # stamped in by the airlock
    door = (R.doors("rdoffice") or R.doors())[0]
    R.place(SERVER_DESK, side=1, near=door)
    R.place(one("server notes", "t", TABLE, ("/obj/item/folder/white", {"pixel_x": 4, "pixel_y": -3}), "/obj/item/pen",
                back="any"), near=door, must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet/chestdrawer", back="any"), far=door, must=False)


def rdoffice(R):
    # v3's office without the server console: that one lives in the server control room, as on the stock maps
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


ASSETS = dict(V3)
ASSETS.update({"launch": launch, "launchrun": launchrun, "toxhall": toxhall, "mechbay": mechbay, "toxins": toxins,
               "foyer": foyer, "server": server, "rdoffice": rdoffice, "servercore": lambda R: None})
