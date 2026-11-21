"""Room assets for the v6 station's Dorms (Meta's dormitories, fitness room, lockers and restrooms).

  cabin      bed in the far corner, the dresser and a closet, a small table with a lamp and a chair, the bolt button
             by the door (the door's id_tag is the cabin's)
  restroom   a row of toilets in stalls on the far wall, showers on another, sinks with mirrors by the door
  lockers    wardrobes along the walls, two washing machines, benches in the middle
  fitness    the weight machines and the punching bag on the walls, a bench, the middle open to spar in
  lounge     the entrance: sofas and tables, the vendors, a plant either side of the hall door
"""
from forge.proc.place import Kit, cell, dist
from assets.science import TABLE, CHAIR, PAPER, PLANT_K, BIN, SINK, one, hang, seat_at, apart, near_tiles

WOOD = "/obj/structure/table/wood"
ASSISTANT = "/obj/effect/landmark/start/assistant"


def free_spots(R, near, n):
    free = [p for p in R.tiles if R.free(p) and p not in R.front and p not in R.lane]
    return sorted(free, key=lambda p: (dist(p, near), p))[:n]


def bolt(rid):
    return "Dorm" + rid[-1]


def cabin(R):
    door = R.doors()[0]
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/random", back="any"), far=door)
    R.place(one("dresser", "DR", "/obj/structure/dresser"), far=door, must=False)
    R.place(one("closet", "L", "/obj/structure/closet/secure_closet/personal/cabinet"), must=False)
    R.place(Kit("desk", [cell(0, 0, WOOD, "/obj/item/flashlight/lamp", PAPER, label="t"),
                         seat_at(0, 1, "/obj/structure/chair/wood")], use=[(0, 1)]), must=False)
    R.place(Kit("bolt", [(0, 0, dict(obj=[], open=True, free=True, label="b", mount=[(
        "button", "/obj/machinery/button/door",
        {"name": "Dorm Bolt Control", "id": bolt(R.rid), "normaldoorcontrol": 1, "specialfunctions": 4})]))],
        back="wall"), near=door, must=False)
    R.place(hang("poster", "sign", "/obj/structure/sign/poster/random"), far=door, must=False)


STALL = Kit("toilet", [cell(0, 0, ("/obj/structure/toilet", {"dir": "IN"}), label="WC")], use=[(0, 1)], back="wall")
SHOWER = Kit("shower", [(0, 0, dict(obj=[("/obj/machinery/shower", {"dir": "IN"})], open=True, label="SH"))],
             use=[], back="wall")


def restroom(R):
    door = (R.doors("hall") or R.doors())[0]
    R.run([STALL, STALL], far=door)
    R.run([SHOWER, SHOWER])
    R.run([SINK, SINK], near=door)
    R.place(one("urinal", "UR", ("/obj/structure/urinal", {"dir": "IN"}), back="wall", use=()), must=False)
    R.place(hang("no smoking", "sign", "/obj/structure/sign/warning/nosmoking"), near=door, must=False)


def lockers(R):
    door = (R.doors("hall") or R.doors())[0]
    R.run([one("wardrobe", "L", path) for path in (
        "/obj/structure/closet/wardrobe/grey", "/obj/structure/closet/wardrobe/black",
        "/obj/structure/closet/wardrobe/mixed", "/obj/structure/closet/wardrobe/pjs")], far=door)
    R.run([one("washer", "WM", "/obj/machinery/washing_machine"), one("washer", "WM", "/obj/machinery/washing_machine")])
    R.place(Kit("bench", [(i, 0, dict(obj=[("/obj/structure/chair/stool", {})], open=True, seat=True, label="s"))
                          for i in range(3)], use=[], back=None, mirror=False),
            near=R.room.attrs["heart"], must=False, need=lambda pl: apart(R, pl, 1))
    R.place(hang("laundry poster", "sign", "/obj/structure/sign/poster/official/cleanliness"), must=False)


def fitness(R):
    door = (R.doors("hall") or R.doors())[0]
    R.run([one("weights", "WT", "/obj/structure/weightmachine/weightlifter", back="any"),
           one("stacklifter", "WT", "/obj/structure/weightmachine/stacklifter", back="any")], far=door)
    R.place(one("punching bag", "PB", "/obj/structure/punching_bag", back="any"), far=door, must=False)
    R.place(one("punching bag", "PB", "/obj/structure/punching_bag", back="any"), must=False)
    R.place(one("water", "WC", "/obj/structure/reagent_dispensers/water_cooler"), near=door, must=False)
    R.run([one("bench", "c", (CHAIR, {"dir": "IN"}), back="wall", use=())] * 3, near=door)
    R.place(hang("fitness poster", "sign", "/obj/structure/sign/poster/official/fruit_bowl"), must=False)


def table2(name):
    return Kit(name, [cell(0, 0, WOOD, label="t"),
                      (-1, 0, dict(obj=[(CHAIR, {"dir": "A+"})], open=True, seat=True, label="c")),
                      (1, 0, dict(obj=[(CHAIR, {"dir": "A-"})], open=True, seat=True, label="c"))],
               use=[], back=None, mirror=False)


def lounge(R):
    # the dorms' entrance off arm E: tables to sit at, the vendors, plants by the hall
    street = (R.doors("hall") or R.doors())[0]
    dwall = R.geo.field("dwall")
    for _ in range(2):
        R.place(table2("lounge table"), near=R.room.attrs["heart"], must=False,
                need=lambda pl: apart(R, pl, 1) and dwall.get(pl.origin, 0) >= 1)
    R.run([one("snacks", "V", "/obj/machinery/vending/snack/random"),
           one("cola", "V", "/obj/machinery/vending/cola/random")], far=street)
    R.place(one("arcade", "AR", ("/obj/machinery/computer/arcade/battle", {"dir": "IN"})), far=street, must=False)
    R.place(PLANT_K, must=False)
    R.place(PLANT_K, must=False)
    R.place(BIN, must=False)
    R.place(hang("dorm map", "sign", "/obj/structure/sign/map/left"), near=street, must=False)
    for p in free_spots(R, R.room.attrs["heart"], 3):
        R.mark(p, ASSISTANT)


def hall(R):
    R.place(hang("poster", "sign", "/obj/structure/sign/poster/official/random"), must=False)
    R.place(hang("poster", "sign", "/obj/structure/sign/poster/official/random"), must=False)


ASSETS = {"dorm1": cabin, "dorm2": cabin, "dorm3": cabin, "dorm4": cabin, "dorm5": cabin, "dorm6": cabin,
          "restroom": restroom, "lockers": lockers, "fitness": fitness, "lounge": lounge, "dormhall": hall}


# ================================================================================================= review 1 (11-21)
WIN = "/obj/structure/window/reinforced"


def stall(R):
    # a toilet stall: the toilet facing the door, the bolt button beside it
    door = R.doors()[0]
    seat = max(R.tiles, key=lambda p: (dist(p, door), p))
    R.put(seat, "obj", obj=[("/obj/structure/toilet", {"dir": {(0, 1): 2, (0, -1): 1, (1, 0): 8, (-1, 0): 4}.get(
        (max(-1, min(1, seat[0] - door[0])), max(-1, min(1, seat[1] - door[1]))), 2)})])
    R.put(seat, None, obj=[("/obj/machinery/button/door", {"name": "Stall Bolt", "id": R.rid, "normaldoorcontrol": 1,
                                                            "specialfunctions": 4,
                                                            "pixel_x": 25 if seat[0] == max(p[0] for p in R.tiles) and
                                                            len(R.tiles) > 1 else -25})])


def washroom(R):
    door = (R.doors("dormhall") or R.doors())[0]
    sink_mirror = Kit("sink", [(0, 0, dict(obj=[], open=True, free=True, label="s",
                                           mount=[("sink", "/obj/structure/sink", {}),
                                                  ("sign", "/obj/structure/mirror", {})]))], back="wall")
    R.run([sink_mirror, sink_mirror], far=door)
    R.place(hang("no smoking", "sign", "/obj/structure/sign/warning/nosmoking"), near=door, must=False)


def lockers2(R):
    # showers with curtains at the east end on freezer floor, personal lockers on the north wall, the washers
    for (x, y) in ((138, 107), (138, 106)):
        if (x, y) in R.tiles:
            R.put((x, y), "open", obj=[("/obj/machinery/shower", {"dir": 8}), "/obj/structure/curtain"],
                  floor="/turf/open/floor/plasteel/freezer")
    R.reserve([(137, 107), (137, 106)], "open")
    for x in (133, 134, 135, 136):
        if (x, 108) in R.tiles:
            R.put((x, 108), "obj", obj=["/obj/structure/closet/secure_closet/personal"],
                  decal=["/obj/effect/turf_decal/bot"])
    door = (R.doors("dormhall") or R.doors())[0]
    R.run([one("washer", "WM", "/obj/machinery/washing_machine"), one("washer", "WM", "/obj/machinery/washing_machine"),
           one("laundry", "t", TABLE, "/obj/item/storage/backpack/duffelbag", "/obj/item/clothing/under/color/grey",
               back="wall")], near=door)
    for x in (131, 132, 133):
        if (x, 107) in R.tiles and R.geo.taken.get((x, 107)) != "obj":
            R.put((x, 107), "open", obj=[("/obj/structure/chair/stool", {})])
    R.run([one("wardrobe", "L", "/obj/structure/closet/wardrobe/grey"),
           one("wardrobe", "L", "/obj/structure/closet/wardrobe/mixed")], near=door)


def fitness2(R):
    # a boxing ring of low walls (directional windows) with a gate on the west side, gloves by it, the weights on
    # the walls, benches facing the ring
    x0, y0, x1, y1 = 132, 99, 136, 103
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            if (x, y) not in R.tiles:
                continue
            edges = [d for d, ok in ((8, x == x0), (4, x == x1), (2, y == y0), (1, y == y1)) if ok]
            objs = [(WIN, {"dir": d}) for d in edges if not (d == 8 and y == 101)]
            if x == x0 and y == 101:
                objs.append(("/obj/machinery/door/window/westleft", {"dir": 8, "name": "Boxing Ring"}))
            # each edge tile's stripe faces its own side, corners take both (Dorms review 3 #1: all faced one way)
            R.put((x, y), "open", obj=objs, decal=[("/obj/effect/turf_decal/stripes/line", {"dir": d}) for d in edges])
    R.put((138, 103), "obj", obj=["/obj/structure/closet/athletic_mixed"])
    R.put((138, 102), "obj", obj=["/obj/structure/rack", "/obj/item/clothing/gloves/boxing",
                                  "/obj/item/clothing/gloves/boxing"])
    door = (R.doors("dormhall") or R.doors())[0]
    R.run([one("weights", "WT", "/obj/structure/weightmachine/weightlifter", back="any"),
           one("stacklifter", "WT", "/obj/structure/weightmachine/stacklifter", back="any")])
    R.place(one("punching bag", "PB", "/obj/structure/punching_bag", back="any"), must=False)
    for x in (131, 132, 133):
        if (x, 97) in R.tiles and (x, 97) not in R.geo.taken:
            R.put((x, 97), "open", obj=[(CHAIR, {"dir": 1})])
    R.place(one("water", "WC", "/obj/structure/reagent_dispensers/water_cooler"), near=door, must=False)


def lounge2(R):
    # the line from the street doors to the hall mouth stays clear; a table of two either side on rugs
    R.reserve([(x, y) for x in (127, 128) for y in (89, 90, 91)], "open")
    for tx in (124, 130):
        for x in (tx - 1, tx, tx + 1):
            for y in (89, 90, 91):
                if (x, y) in R.tiles:
                    R.put((x, y), None, floor="/turf/open/floor/carpet")
        R.put((tx, 90), "obj", obj=[WOOD])
        R.put((tx - 1, 90), "open", obj=[("/obj/structure/chair/wood", {"dir": 4})])
        R.put((tx + 1, 90), "open", obj=[("/obj/structure/chair/wood", {"dir": 8})])
    for x in (126, 129):
        if (x, 91) in R.tiles:
            R.put((x, 91), "obj", obj=["/obj/item/twohanded/required/kirbyplants/random"])
    R.run([one("snacks", "V", "/obj/machinery/vending/snack/random"),
           one("cola", "V", "/obj/machinery/vending/cola/random")])
    R.place(BIN, must=False)
    for p in free_spots(R, (124, 89), 3):
        R.mark(p, ASSISTANT)


ASSETS.update({"stall1": stall, "stall2": stall, "restroom": washroom, "lockers": lockers2, "fitness": fitness2,
               "lounge": lounge2})


# ================================================================================================= review 2 (11-21)
def lounge3(R):
    lounge2(R)
    # the lounge's newscaster and the station map on the north wall, either side of the hall mouth (review 2 #7)
    for p, path, why in (((124, 91), "/obj/machinery/newscaster", "newscaster"),
                         ((125, 91), "/obj/structure/sign/map/left", "map")):
        if p in R.tiles and R.geo.taken.get(p) != "obj" and (p, 1) not in R.faces:
            R.put(p, None, obj=[(path, {"pixel_y": 32})])
            R.faces[(p, 1)] = why
        else:
            R.geo.problem("lounge: no wall face for the %s at %d,%d" % (why, p[0], p[1]))


def fitness3(R):
    fitness2(R)
    # the second punching bag by the ring (review 2 #11)
    p = (138, 98)
    if p in R.tiles and R.geo.taken.get(p) != "obj":
        R.put(p, "obj", obj=["/obj/structure/punching_bag"])


def hall3(R):
    hall(R)
    # hazard stripes inside the maint door (review 2 #8)
    for d in R.doors("maint"):
        # doors() already gives the tile just inside the door (Dorms review 3 #3: the stripe sat a tile too far in)
        R.put(d, None, decal=[("/obj/effect/turf_decal/stripes/line", {"dir": 1})])


ASSETS.update({"lounge": lounge3, "fitness": fitness3, "dormhall": hall3})
