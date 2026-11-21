"""Room assets for the v6 station's Cargo: cargo.py's office, lobby and QM office plus the rooms the drawn block adds.

  bay         the supply shuttle's airlock on one wall, a clear apron inside it for crates, the MULE parking row,
              the cargo vendors and the crate pile on the other walls
  warehouse   crates and closets stacked along the walls, a way down the middle
  sorting     the mail: wrapping tables, the destination tagger, the disposal bin that posts parcels
  mining      Meta's mining office: the equipment vendor, the miners' lockers, the shuttle console by the dock airlock,
              the mining cameras and the ore box
"""
from forge.proc.place import Kit, cell, dist
from assets.cargo import ASSETS as V1, CARGO_TECH, CARGO_RC
from assets.science import TABLE, PAPER, PLANT_K, BIN, BOT, DELIVERY, one, hang, seat_at
from assets.security import button

MINER = "/obj/effect/landmark/start/shaft_miner"


def free_spots(R, near, n):
    free = [p for p in R.tiles if R.free(p) and p not in R.front and p not in R.lane]
    return sorted(free, key=lambda p: (dist(p, near), p))[:n]


def office(R):
    V1["office"](R)
    # a clerk's chair behind the desk windoor, facing it
    for p, dr in sorted(R.geo.doors.items()):
        if dr.get("spec", {}).get("type") == "desk" and R.rid in dr.get("sides", {}):
            q = dr["sides"][R.rid]
            d = {(1, 0): 4, (-1, 0): 8, (0, 1): 1, (0, -1): 2}[(p[0] - q[0], p[1] - q[1])]
            if q not in R.geo.taken or R.geo.taken.get(q) != "obj":
                R.mark(q, ("/obj/structure/chair/office", {"dir": d}))


def belts(R):
    """The loading lanes: each flaps door's belt runs on 4 tiles into the bay, a switch at its inner end, the lane
    edged with hazard stripes; returns the lane tiles."""
    from forge.proc.geo import step, CARD, CW
    lanes = []
    for p, dr in sorted(R.geo.doors.items()):
        sp = dr.get("spec", {})
        if sp.get("type") != "flaps" or R.rid not in dr.get("sides", {}):
            continue
        q = dr["sides"][R.rid]
        d = [k for k in CARD if step(p, k) == q][0]
        flow = d if sp.get("flow", "in") == "in" else {1: 2, 2: 1, 4: 8, 8: 4}[d]
        lane = [step(q, d, k) for k in range(4) if step(q, d, k) in R.tiles]
        for t in lane:
            R.put(t, "open", obj=[("/obj/machinery/conveyor", {"dir": flow, "id": sp["belt"]})],
                  decal=[("/obj/effect/turf_decal/stripes/line", {"dir": CW[d]})])
        end = step(lane[-1], d) if lane else q
        side = step(lane[-1], CW[d]) if lane else q
        if side in R.tiles and side not in R.geo.taken:
            R.put(side, "obj", obj=[("/obj/machinery/conveyor_switch/oneway", {"id": sp["belt"],
                                                                                "name": "loading belt switch"})])
        R.reserve([end], "open")
        lanes += lane
    return lanes


def bay(R):
    # crates come in on the belts and through the dock airlocks: the aprons stay clear; four MULE stalls on the far
    # wall with two MULEs parked; the ORM on the north wall by the sorting door, where miners come through
    dock = (R.doors("space") or R.doors())[0]
    belts(R)
    apron = [p for p in R.tiles if dist(p, dock) <= 3 and p not in R.geo.taken]
    R.reserve(apron, "open")
    # floor zoning (map coordinates of this drawn block): a dark loading strip between the two belts, a bot-decal
    # crate grid in the middle of the bay, a bot decal where the in-belt drops its crates
    for x in range(37, 41):
        for y in range(100, 103):
            if (x, y) in R.tiles:
                R.put((x, y), None, floor="/turf/open/floor/plasteel/dark")
    grid = [(x, y) for x in range(44, 51) for y in range(99, 102) if (x, y) in R.tiles]
    for p in grid:
        R.put(p, None, decal=[BOT])
    R.reserve(grid, "open")
    R.put((41, 103), None, decal=[BOT])
    # the lane mouth to arrivals (south-west) stays clear for carts and MULEs
    R.reserve([p for p in R.tiles if p[1] == 98 and 39 <= p[0] <= 44], "open")
    pads = R.run([one("MULE stall", "MU", "/obj/machinery/navbeacon", decal=[DELIVERY], back="wall", use=())] * 4,
                 far=dock)
    for k in (pads or [])[:2]:
        R.mark(k.origin, "/mob/living/simple_animal/bot/mulebot")
    R.place(button("Loading Doors", {"id": "QMLoaddoor", "req_access_txt": "31"}), near=dock, must=False)
    R.place(button("Loading Doors", {"id": "QMLoaddoor2", "req_access_txt": "31"}), near=dock, must=False)
    office_door = (R.doors("office") or [R.room.attrs["heart"]])[0]
    R.run([one("cargo vendor", "V", "/obj/machinery/vending/wardrobe/cargo_wardrobe"),
           one("crate", "CR", "/obj/structure/closet/crate"), one("crate", "CR", "/obj/structure/closet/crate"),
           one("crate", "CR", "/obj/structure/closet/crate/internals")], side=2, near=(47, 96))
    R.place(one("tools", "t", TABLE, "/obj/item/stack/packageWrap", "/obj/item/hand_labeler", "/obj/item/destTagger",
                back="any"), side=2, must=False)
    R.place(one("fire closet", "L", "/obj/structure/closet/firecloset"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console", dict(CARGO_RC)),
            near=office_door, must=False)
    for p in free_spots(R, R.room.attrs["heart"], 2):
        R.mark(p, CARGO_TECH)


def warehouse(R):
    door = R.doors()[0]
    R.run([one("crate", "CR", "/obj/structure/closet/crate")] * 3, far=door)
    R.run([one("cardboard", "CB", "/obj/structure/closet/cardboard"),
           one("freezer crate", "CR", "/obj/structure/closet/crate/freezer"),
           one("small crate", "CR", "/obj/structure/closet/crate/internals")], far=door)


def sorting(R):
    # parcels: wrapped on the tables, tagged, posted down the bin
    door = (R.doors("bay") or R.doors())[0]
    R.place(Kit("wrapping", [
        cell(0, 0, TABLE, "/obj/item/stack/packageWrap", "/obj/item/stack/packageWrap", label="t"),
        cell(1, 0, TABLE, "/obj/item/destTagger", "/obj/item/hand_labeler", label="t"),
        seat_at(0, 1, "/obj/structure/chair/office"),
    ], use=[(0, 1), (1, 1)]), must=False)
    R.place(BIN, near=door, must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet/filingcabinet", back="any"), must=False)
    R.place(one("parcels", "CR", "/obj/structure/closet/crate"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Mail RC", "department": "Mail Sorting", "departmentType": 2}), must=False)


def mining(R):
    # miners gear up between the vendor and their lockers; the shuttle console by the dock airlock
    dock = (R.doors("space") or R.doors())[0]
    R.place(one("shuttle console", "SH", ("/obj/machinery/computer/shuttle/mining", {"dir": "IN"})), near=dock)
    R.place(one("equipment vendor", "EV", "/obj/machinery/mineral/equipment_vendor"), far=dock)
    lockers = R.run([one("miner locker", "L", "/obj/structure/closet/secure_closet/miner")] * 4, far=dock)
    R.place(one("mining cameras", "MC", ("/obj/machinery/computer/security/mining", {"dir": "IN"})), must=False)
    R.place(one("ore box", "OB", "/obj/structure/ore_box"), near=dock, must=False)
    R.place(one("fuel", "FT", "/obj/structure/reagent_dispensers/fueltank"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Mining RC", "department": "Mining", "departmentType": 0}), must=False)
    for k in (lockers or [])[:4]:
        R.mark(k.use_tile if hasattr(k, "use_tile") else k.uses[0], MINER)


QM_DESK = Kit("QM desk", [
    cell(0, 0, TABLE, PAPER, "/obj/item/pen/fountain", "/obj/item/stamp/qm", label="t"),
    cell(1, 0, TABLE, "/obj/item/clipboard", "/obj/item/folder/yellow", label="t"),
    (0, -1, dict(obj=[("/obj/structure/chair/office", {"dir": "IN"}), "/obj/effect/landmark/start/quartermaster"],
                 open=True, seat=True, label="c")),
], use=[(0, -1)], back=None, mirror=False)


def qm(R):
    # the quartermaster sits facing the glass onto the bay, the consoles on the wall behind
    glass_side = R.side("bay")
    toward = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}.get(glass_side, (0, -1))
    def facing(pl):
        c, t = pl.at(0, -1), pl.at(0, 0)
        return (t[0] - c[0], t[1] - c[1]) == toward
    desk = R.place(QM_DESK, need=facing, must=False) or R.place(QM_DESK, must=False)
    chair = desk.at(0, -1) if desk else R.room.attrs["heart"]
    R.run([one("supply console", "SC", ("/obj/machinery/computer/cargo", {"dir": "IN"})),
           one("mining cameras", "MC", ("/obj/machinery/computer/security/mining", {"dir": "IN"}))], near=chair)
    R.place(one("QM locker", "L", "/obj/structure/closet/secure_closet/quartermaster"), must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False)
    R.place(BIN, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console", dict(CARGO_RC)),
            near=chair, must=False)
    R.place(hang("supply display", "status_display", "/obj/machinery/status_display/supply", {}), must=False)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


def lobby(R):
    V1["lobby"](R)
    R.place(PLANT_K, must=False)


ASSETS = dict(V1)
ASSETS.update({"office": office, "bay": bay, "warehouse": warehouse, "sorting": sorting, "mining": mining, "qm": qm,
               "lobby": lobby})
