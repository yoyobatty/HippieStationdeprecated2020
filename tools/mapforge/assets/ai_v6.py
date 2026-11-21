"""Room assets for the v6 station's AI satellite (Meta's): foyer, hall, atmos, borg service, core chamber, stores.

  core      the AI's start in the middle of the chamber facing the door, a turret in each corner, the turret
            control and three intercoms on the walls, the holopad in front of the AI
  foyer     the way in off the bridge: two turrets watching the door, a fire closet
  service   two borg chargers on the wall, the cyborgs' starts, cells and a welder on a table
  atmos     the satellite's spare air: canisters on connectors, a portable pump and scrubber
  stores    emergency closets and a table of spare parts
"""
from forge.proc.place import Kit, cell, dist
from assets.science import TABLE, BOT, one, hang

TURRET = "/obj/machinery/porta_turret/ai"


def corners(R, n=4):
    xs, ys = [p[0] for p in R.tiles], [p[1] for p in R.tiles]
    want = [(min(xs), min(ys)), (max(xs), min(ys)), (min(xs), max(ys)), (max(xs), max(ys))]
    return [p for p in want if p in R.tiles][:n]


def core(R):
    door = R.doors()[0]
    xs, ys = [p[0] for p in R.tiles], [p[1] for p in R.tiles]
    mid = ((min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2)
    R.put(mid, "obj", obj=["/obj/effect/landmark/start/ai"])
    front = min(((mid[0] + dx, mid[1] + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))),
                key=lambda p: dist(p, door))
    R.put(front, "open", obj=["/obj/machinery/holopad"])
    for p in corners(R):
        if p not in R.geo.taken:
            R.put(p, "obj", obj=[TURRET])
    R.place(hang("turret control", "button", "/obj/machinery/turretid", {"name": "AI Chamber turret control"}),
            near=door)
    for _ in range(3):
        R.place(hang("intercom", "intercom", "/obj/item/radio/intercom", {"name": "Private AI Channel"}), must=False)


def foyer(R):
    door = (R.doors("hall") or R.doors())[0]
    far = [p for p in corners(R) if dist(p, door) > 2][:2]
    for p in far:
        if p not in R.geo.taken:
            R.put(p, "obj", obj=[TURRET])
    R.place(one("fire closet", "L", "/obj/structure/closet/firecloset"), must=False)
    R.place(hang("turret control", "button", "/obj/machinery/turretid", {"name": "AI Foyer turret control"}),
            must=False)


def service(R):
    R.run([one("borg charger", "RS", "/obj/machinery/recharge_station", decal=[BOT]),
           one("borg charger", "RS", "/obj/machinery/recharge_station", decal=[BOT])])
    R.place(one("parts", "t", TABLE, "/obj/item/stock_parts/cell/high", "/obj/item/stock_parts/cell/high",
                "/obj/item/weldingtool", back="wall"))
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    for p in free[:2]:
        R.mark(p, "/obj/effect/landmark/start/cyborg")


def atmos(R):
    R.run([one("air", "AC", "/obj/machinery/portable_atmospherics/canister/air", decal=[BOT]),
           one("oxygen", "OC", "/obj/machinery/portable_atmospherics/canister/oxygen", decal=[BOT]),
           one("pump", "pp", "/obj/machinery/portable_atmospherics/pump", decal=[BOT]),
           one("scrubber", "sc", "/obj/machinery/portable_atmospherics/scrubber", decal=[BOT])])


def stores(R):
    R.run([one("emergency closet", "L", "/obj/structure/closet/emcloset"),
           one("parts", "t", TABLE, "/obj/item/storage/toolbox/electrical", "/obj/item/stack/cable_coil",
               back="wall")])


def hall(R):
    R.place(hang("sat map", "sign", "/obj/structure/sign/warning/securearea"), must=False)


ASSETS = {"core": core, "foyer": foyer, "service": service, "atmos": atmos, "power": stores, "stores": stores,
          "sathall": hall}


# ================================================================================================= review 1 (11-21)
WIN = "/obj/effect/spawner/structure/window/reinforced"


def core2(R):
    # Meta's core: the AI in a reinforced-glass box with windoors east and west, slippers beyond them, the
    # intercom trio on the AI's own tile, a turret in each corner, flashers and the turret control on the walls
    door = R.doors()[0]
    xs, ys = [p[0] for p in R.tiles], [p[1] for p in R.tiles]
    mx, my = (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2
    R.put((mx, my), "obj", obj=[
        "/obj/effect/landmark/start/ai",
        ("/obj/item/radio/intercom", {"name": "Common Channel", "freerange": 1, "listening": 0}),
        ("/obj/item/radio/intercom", {"name": "Private Channel", "frequency": 1447, "freerange": 1}),
        ("/obj/item/radio/intercom", {"name": "Custom Channel", "freerange": 1, "listening": 0})])
    for dx in (-1, 0, 1):
        for dy in (-1, 1):
            R.put((mx + dx, my + dy), "obj", obj=[WIN])
    for dx, d in ((-1, 8), (1, 4)):
        R.put((mx + dx, my), "open", obj=[("/obj/machinery/door/window/westleft", {"dir": d, "name": "AI Core Door",
                                                                                   "req_access_txt": "16"})])
    for dx in (-2, 2):
        if (mx + dx, my) in R.tiles:
            R.put((mx + dx, my), "open", obj=["/obj/machinery/ai_slipper"])
    R.put((mx, my + 2), "open", obj=["/obj/machinery/holopad"]) if (mx, my + 2) in R.tiles else None
    for p in corners(R):
        if p not in R.geo.taken and p not in R.front:      # never in the doorway
            R.put(p, "obj", obj=[TURRET])
    R.place(hang("turret control", "button", "/obj/machinery/turretid", {"name": "AI Chamber turret control"}),
            near=door, must=False)
    # the flashers flank the glass box, one on each side wall level with the windoors' row above
    for x, px in ((mx - 3, -28), (mx + 3, 28)):
        if (x, my + 1) in R.tiles:
            R.put((x, my + 1), None, obj=[("/obj/machinery/flasher", {"id": "AI", "pixel_x": px})])
    R.place(hang("AI display", "status_display", "/obj/machinery/status_display/ai"), must=False)


def foyer2(R):
    # the satellite's teleporter on the north wall, turrets watching the door, the turret control by it
    door = (R.doors("hall") or R.doors())[0]
    R.place(Kit("teleporter", [cell(0, 0, ("/obj/machinery/computer/teleporter", {"dir": "IN"}), label="TC"),
                               cell(1, 0, ("/obj/machinery/teleport/station", {"dir": "IN"}), label="TS"),
                               cell(2, 0, ("/obj/machinery/teleport/hub", {"dir": "IN"}), label="TH")],
                use=[(0, 1), (2, 1)]), far=door, must=False)
    R.place(one("beacon", "t", TABLE, "/obj/item/beacon", back="wall"), must=False)
    far = [p for p in corners(R) if dist(p, door) > 2 and p not in R.geo.taken][:2]
    for p in far:
        R.put(p, "obj", obj=[TURRET])
    R.place(hang("turret control", "button", "/obj/machinery/turretid", {"name": "AI Foyer turret control"}),
            near=door, must=False)
    xs, ys = [p[0] for p in R.tiles], [p[1] for p in R.tiles]
    R.put((min(xs) + 1, (min(ys) + max(ys)) // 2 + 1), "open", obj=["/obj/machinery/holopad"])
    for p in ((min(xs), max(ys)), (min(xs), min(ys))):
        if p not in R.geo.taken and p not in R.front:
            R.put(p, "obj", obj=[TURRET])
            break


def smes_room(R):
    # the satellite's own power: an SMES with its terminal, a power monitor
    xs, ys = [p[0] for p in R.tiles], [p[1] for p in R.tiles]
    p = (min(xs), max(ys))
    R.put(p, "obj", obj=[("/obj/machinery/power/smes", {"charge": 5e6})])
    t = (p[0], p[1] - 1)
    if t in R.tiles:
        R.put(t, "open", obj=[("/obj/machinery/power/terminal", {"dir": 1})])
    R.place(one("power monitor", "C", ("/obj/machinery/computer/monitor", {"dir": "IN"})), must=False)


def stores2(R):
    R.run([one("parts", "t", TABLE, "/obj/item/stock_parts/cell/high", ("/obj/machinery/cell_charger", {}),
               back="wall"),
           one("tools", "t", TABLE, "/obj/item/storage/toolbox/electrical", "/obj/item/stack/cable_coil",
               back="wall"),
           one("emergency closet", "L", "/obj/structure/closet/emcloset")])


def hall2(R):
    xs, ys = [p[0] for p in R.tiles], [p[1] for p in R.tiles]
    R.put((min(xs), (min(ys) + max(ys)) // 2), "open", obj=["/obj/machinery/holopad"])
    # the AI sees the whole hall: a camera at each end
    for y, d, tag in ((max(ys), 2, "North"), (min(ys), 1, "South")):
        R.put((max(xs), y), None, obj=[("/obj/machinery/camera", {"dir": d, "c_tag": "AI Satellite Hallway %s" % tag})])


ASSETS.update({"core": core2, "foyer": foyer2, "power": smes_room, "stores": stores2, "sathall": hall2})


# ================================================================================================= review 3 (11-21)
def hall3(R):
    hall2(R)
    # turrets at both ends of the hall, their control by the foyer door: past the foyer is not a free walk (review 3 #2)
    for p in ((178, 92), (178, 79)):
        if p in R.tiles and R.geo.taken.get(p) != "obj":
            R.put(p, "obj", obj=[TURRET])
        else:
            R.geo.problem("sat hall: no room for a turret at %d,%d" % p)
    R.put((178, 88), None, obj=[("/obj/machinery/turretid", {"name": "AI Satellite Hallway turret control",
                                                              "pixel_x": -24})])
    R.faces[((178, 88), 8)] = "turret control"


def stores3(R):
    stores2(R)
    R.put((183, 79), None, obj=[("/obj/machinery/camera", {"dir": 8, "c_tag": "AI Satellite Storage"})])
    R.faces[((183, 79), 4)] = "camera"


ASSETS.update({"sathall": hall3, "stores": stores3})


def core3(R):
    core2(R)
    # one pane north and south on the chamber's centre line x184 (review 3 #6)
    for p in ((184, 91), (184, 81)):
        R.put(p, None, floor="/turf/open/floor/plating", obj=["/obj/effect/spawner/structure/window/reinforced"])


ASSETS.update({"core": core3})
