"""Room assets for Cargo's front: how each room is played, as kits and placing rules.

From Hippie's own cargo office, QM office and supply checkpoint (census 2026-11-16, x77-95 y110-124) and how a shift
uses it:
  office      behind the counter: the supply console the techs order on, the bounty console, the cargo techfab and
              the autolathe, a table of paperwork and stamps, the photocopier; doors to the bay and to sorting
  lobby       the public side of the counter: the request console, a few chairs, the open front onto the hallway
  qm          the quartermaster's desk facing the door, the supply console and the mining cameras, the QM locker
  checkpoint  one officer by the mining dock: records, the mining cameras, the locker and the pepper tank
The bay itself (conveyors, the shuttle dock, the MULE beacons), the sorting room's chutes and the mining dock stay as
they are. An asset never names a coordinate. It asks the room which wall faces which neighbour and where its doors are.
"""
from forge.proc.place import Kit, cell, dist
from assets.science import TABLE, PAPER, PLANT_K, SEAT, BIN, one, hang, seat_at

CARGO_TECH = "/obj/effect/landmark/start/cargo_technician"
RTABLE = "/obj/structure/table/reinforced"
CARGO_RC = {"name": "Cargo Bay RC", "department": "Cargo Bay", "departmentType": 2}


def free_spots(R, near, n):
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    return sorted(free, key=lambda p: (dist(p, near), p))[:n]


# ================================================================================================= office
SUPPLY_DESK = Kit("supply console", [
    cell(0, 0, ("/obj/machinery/computer/cargo", {"dir": "IN"}), label="SC"),
    seat_at(0, 1, "/obj/structure/chair/office", CARGO_TECH),
], use=[(0, 1)])


def office(R):
    # the techs order at the supply console by the counter, the fabricators on the back wall, paperwork at hand
    counter = (R.doors("lobby") or R.doors())[0]
    desk = R.place(SUPPLY_DESK, near=counter, must=False)
    R.place(one("bounty console", "BC", ("/obj/machinery/computer/bounty", {"dir": "IN"})), near=counter, must=False)
    R.run([one("techfab", "TF", "/obj/machinery/rnd/production/techfab/department/cargo"),
           one("autolathe", "AL", "/obj/machinery/autolathe")], far=counter)
    chair = desk.at(0, 1) if desk else R.room.attrs["heart"]
    R.place(one("paperwork", "t", TABLE, PAPER, "/obj/item/pen/red", "/obj/item/clipboard", "/obj/item/stamp",
                "/obj/item/stamp/denied", back="any"), near=chair, must=False)
    R.place(one("tools", "t", TABLE, "/obj/item/folder/yellow", "/obj/item/multitool", "/obj/item/staplegun",
                "/obj/item/storage/firstaid", back="any"), must=False)
    R.place(one("photocopier", "PC", "/obj/machinery/photocopier", back="any"), must=False)
    R.place(one("crate", "CR", "/obj/structure/closet/crate"), must=False)
    R.place(BIN, near=(R.doors("bay") or [counter])[0], must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console", dict(CARGO_RC)),
            near=counter, must=False)
    R.place(hang("noticeboard", "noticeboard", "/obj/structure/noticeboard"), must=False)
    R.place(hang("intercom", "intercom", "/obj/item/radio/intercom"), must=False)
    R.place(hang("poster", "sign", "/obj/structure/sign/poster/official/pda_ad"), must=False)
    for p in free_spots(R, chair, 1):
        R.mark(p, CARGO_TECH)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


def lobby(R):
    # the crew walks in off the hallway to the request console at the counter, and waits on the chairs
    counter = (R.doors("office") or R.doors())[0]
    R.place(one("request console", "RQ", ("/obj/machinery/computer/cargo/request", {"dir": "IN"})), near=counter,
            must=False)
    R.run([one("chair", "c", ("/obj/structure/chair", {"dir": "IN"}), back="any")] * 3, far=counter)
    R.place(PLANT_K, must=False)
    R.place(hang("sign", "sign", "/obj/structure/sign/departments/cargo"), must=False)
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")


# ================================================================================================= QM
QM_DESK = Kit("QM desk", [
    cell(0, 0, TABLE, "/obj/item/folder/yellow", "/obj/item/stamp/qm", label="t"),
    cell(1, 0, TABLE, "/obj/item/clipboard", PAPER, "/obj/item/pen", "/obj/item/pen/red", label="t"),
    seat_at(0, 1, "/obj/structure/chair/office", "/obj/effect/landmark/start/quartermaster"),
], use=[(0, 1)])


def qm(R):
    # the quartermaster faces the door from the desk, the supply console and mining cameras at the back
    door = (R.doors("bay") or R.doors())[0]
    desk = R.place(QM_DESK, far=door, must=False)
    R.place(BIN, near=door, must=False)
    R.place(one("QM locker", "L", "/obj/structure/closet/secure_closet/quartermaster"), must=False)
    R.run([one("supply console", "SC", ("/obj/machinery/computer/cargo", {"dir": "IN"})),
           one("mining cameras", "MC", ("/obj/machinery/computer/security/mining", {"dir": "IN"}))],
          near=desk.origin if desk else R.room.attrs["heart"])
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False)
    R.place(one("cartridges", "t", TABLE, "/obj/item/cartridge/quartermaster", "/obj/item/cartridge/quartermaster",
                "/obj/item/cartridge/quartermaster", "/obj/item/coin/silver", back="any"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console", dict(CARGO_RC)),
            must=False)
    R.place(hang("supply display", "status_display", "/obj/machinery/status_display/supply", {}), must=False)
    R.place(hang("intercom", "intercom", "/obj/item/radio/intercom"), must=False)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


# ================================================================================================= checkpoint
CHECK_DESK = Kit("checkpoint desk", [
    cell(0, 0, ("/obj/machinery/computer/secure_data", {"dir": "IN"}), label="SD"),
    seat_at(0, 1, "/obj/structure/chair/office", "/obj/effect/landmark/start/depsec/supply"),
], use=[(0, 1)])


def checkpoint(R):
    # one officer, records and the mining cameras at hand, by the dock where the miners come and go
    door = R.doors()[0]
    desk = R.place(CHECK_DESK, far=door, must=False)
    chair = desk.at(0, 1) if desk else R.room.attrs["heart"]
    R.place(one("mining cameras", "MC", ("/obj/machinery/computer/security/mining", {"dir": "IN"})), near=chair,
            must=False)
    R.place(one("desk", "t", TABLE, PAPER, "/obj/item/pen", "/obj/item/book/manual/wiki/security_space_law",
                back="any"), near=chair, must=False)
    R.place(one("charger", "t", TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), "/obj/item/radio/off",
                "/obj/item/screwdriver", back="any"), must=False)
    R.place(one("officer locker", "L", "/obj/structure/closet/secure_closet/security/cargo"), must=False)
    R.place(one("SecDrobe", "W", "/obj/machinery/vending/wardrobe/sec_wardrobe"), must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False)
    R.place(one("pepper", "PT", "/obj/structure/reagent_dispensers/peppertank"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Security RC", "department": "Security", "departmentType": 5}), must=False)
    R.place(hang("newscaster", "newscaster", "/obj/machinery/newscaster/security_unit"), must=False)
    R.place(hang("intercom", "intercom", "/obj/item/radio/intercom"), must=False)
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")


ASSETS = {"office": office, "lobby": lobby, "qm": qm, "checkpoint": checkpoint}
