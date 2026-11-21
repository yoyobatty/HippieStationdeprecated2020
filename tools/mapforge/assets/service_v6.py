"""Room assets for the v6 station's Service: service.py's kitchen, cold room and hydroponics plus the rooms the drawn
block adds.

  bar        the counter runs along the back wall with the bartender's lane behind it and stools in front; the
             booze-o-mat and the dispensers on the back wall, tables with chairs out front
  dining     the cafeteria: tables of four, the vendors on the walls, the kitchen hatch on one side
  theatre    rows of seats facing a wooden stage with the piano; the clown's and mime's places, the autodrobe
  janitor    the cart and the mop bucket, the closet, the sink, the vendor; the light replacer on a table
"""
from forge.proc.place import Kit, cell, dist
from assets.service import ASSETS as V1
from assets.science import TABLE, PAPER, PLANT_K, BIN, BOT, CHAIR, one, hang, seat_at, apart, near_tiles

WOOD = "/obj/structure/table/wood"
STOOL = "/obj/structure/chair/stool/bar"


def free_spots(R, near, n):
    free = [p for p in R.tiles if R.free(p) and p not in R.front and p not in R.lane]
    return sorted(free, key=lambda p: (dist(p, near), p))[:n]


def renamed(fn, names):
    """Run a service.py asset with its door names mapped onto this block's room ids."""
    def run(R):
        orig = R.doors
        R.doors = lambda t=None: orig(names.get(t, t)) if t is not None else orig()
        fn(R)
    return run


# ================================================================================================= bar
COUNTER = Kit("bar counter", [(u, 0, dict(obj=[], open=True, label=".")) for u in range(5)] +
              [cell(u, 1, WOOD, *items, label="t") for u, items in enumerate((
                  ["/obj/machinery/chem_dispenser/drinks"], ["/obj/item/reagent_containers/food/drinks/shaker"],
                  ["/obj/item/storage/box/drinkingglasses"], ["/obj/item/reagent_containers/food/drinks/drinkingglass"],
                  ["/obj/machinery/chem_dispenser/drinks/beer"]))] +
              [(u, 2, dict(obj=[(STOOL, {"dir": "OUT"})], open=True, seat=True, label="s")) for u in range(5)],
              use=[(-1, 0), (5, 0)], back="wall", mirror=False)


def table4(name, *items):
    return Kit(name, [
        cell(0, 0, WOOD, *items, label="t"),
        (-1, 0, dict(obj=[(CHAIR, {"dir": "A+"})], open=True, seat=True, label="c")),
        (1, 0, dict(obj=[(CHAIR, {"dir": "A-"})], open=True, seat=True, label="c")),
        (0, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
        (0, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
    ], use=[], back=None, mirror=False)


def bar(R):
    # the bartender works the lane between the back wall and the counter; the drinks on the back wall
    hall = (R.doors("hall") or R.doors())[0]
    counter = R.place(COUNTER, far=hall, must=False)
    # the dispensers stand on the counter's ends (tg's bars); the booze-o-mat and the locker by the lane's ends
    R.place(one("booze-o-mat", "V", "/obj/machinery/vending/boozeomat"), near=counter.origin if counter else None,
            must=False)
    R.place(one("bar locker", "L", "/obj/structure/closet/gmcloset"), near=counter.origin if counter else None,
            must=False)
    R.place(one("bar wardrobe", "W", "/obj/machinery/vending/wardrobe/bar_wardrobe"), must=False)
    dwall = R.geo.field("dwall")
    for i in range(2):
        R.place(table4("bar table", "/obj/item/reagent_containers/food/drinks/drinkingglass"),
                near=R.room.attrs["heart"], must=False, need=lambda pl: apart(R, pl, 1) and dwall.get(pl.origin, 0) >= 2)
    R.place(one("jukebox", "JB", "/obj/machinery/jukebox"), near=hall, must=False)
    R.place(PLANT_K, near=hall, must=False)
    R.place(hang("bar sign", "sign", "/obj/structure/sign/barsign"), near=hall, must=False)
    if counter:
        R.mark(counter.at(2, 0), "/obj/effect/landmark/start/bartender")
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


def dining(R):
    # tables of four through the middle, the vendors on the walls, a plant in each far corner
    hatch = (R.doors("kitchen") or R.doors())[0]
    dwall = R.geo.field("dwall")
    for i in range(4):
        R.place(table4("dining table", "/obj/item/reagent_containers/food/condiment/saltshaker",
                       "/obj/item/reagent_containers/food/condiment/peppermill"),
                near=hatch, must=False, need=lambda pl: apart(R, pl, 1) and dwall.get(pl.origin, 0) >= 2)
    R.run([one("snacks", "V", "/obj/machinery/vending/snack/random"),
           one("cola", "V", "/obj/machinery/vending/cola/random")])
    R.place(one("cigarettes", "V", "/obj/machinery/vending/cigarette"), must=False)
    R.place(PLANT_K, far=hatch, must=False)
    R.place(BIN, must=False)
    R.place(hang("menu", "sign", "/obj/structure/sign/poster/official/random"), near=hatch, must=False)


def theatre(R):
    # the stage is the far end from the door, wooden, with the piano; seats in rows face it
    door = (R.doors("hall") or R.doors())[0]
    far = max(R.tiles, key=lambda p: (dist(p, door), p))
    stage = [p for p in R.tiles if dist(p, far) <= 2]
    R.zone(stage, floor="/turf/open/floor/wood")
    R.place(one("piano", "PI", "/obj/structure/piano"), near=far, must=False)
    R.place(one("autodrobe", "V", "/obj/machinery/vending/autodrobe"), near=far, must=False)
    R.place(one("props", "t", WOOD, "/obj/item/bikehorn", "/obj/item/toy/crayon/mime", back="any"), near=far,
            must=False)
    R.reserve(stage, "open")
    side = R.side("hall")
    d = {1: 1, 2: 2, 4: 4, 8: 8}.get(side, 2)
    for _ in range(3):
        R.place(Kit("seat row", [(i, 0, dict(obj=[(CHAIR, {"dir": {1: 2, 2: 1, 4: 8, 8: 4}[d]})], open=True, seat=True,
                                                label="c")) for i in range(3)], use=[], back=None, mirror=False),
                near=door, must=False,
                need=lambda pl: all(t not in R.geo.taken and not any(R.geo.taken.get(q) == "open" and q not in pl.tiles
                                                                     for q in near_tiles(R, [t])) for t in pl.tiles))
    for job in ("clown", "mime"):
        spot = free_spots(R, far, 1)
        if spot:
            R.mark(spot[0], "/obj/effect/landmark/start/%s" % job)
    R.place(hang("theatre poster", "sign", "/obj/structure/sign/poster/official/random"), must=False)


def janitor(R):
    door = R.doors()[0]
    R.place(one("janitor cart", "JC", "/obj/structure/janitorialcart", back="any"), near=door, must=False)
    R.place(one("mop bucket", "MB", "/obj/structure/mopbucket", back="any"), must=False)
    R.place(one("janitor closet", "L", "/obj/structure/closet/jcloset"), far=door, must=False)
    R.place(one("janitor vendor", "V", "/obj/machinery/vending/wardrobe/jani_wardrobe"), must=False)
    R.place(one("sink", "SK", ("/obj/structure/sink", {"dir": "IN"}), back="wall"), must=False)
    R.place(one("supplies", "t", TABLE, "/obj/item/lightreplacer", "/obj/item/storage/box/lights/mixed",
                "/obj/item/reagent_containers/spray/cleaner", back="any"), must=False)
    spot = free_spots(R, door, 1)
    if spot:
        R.mark(spot[0], "/obj/effect/landmark/start/janitor")


ASSETS = {"kitchen": renamed(V1["kitchen"], {"counter": "dining"}), "cold": V1["cold"],
          "hydro": renamed(V1["hydro"], {"desk": "hall"}), "bar": bar, "dining": dining, "theatre": theatre,
          "janitor": janitor}


# ================================================================================================= review 1 (11-21)
BARTILE = "/obj/effect/turf_decal/tile/bar"


def bar2(R):
    # Meta's back bar: a counter wall-to-wall at x105 with the bartender's windoor, a 2-wide lane behind it that only
    # the windoor and the kitchen door reach, the dispensers and the booze-o-mat on the back wall, stools in front;
    # tables of four out on the bar's checker floor
    for y in range(108, 117):
        if (105, y) not in R.tiles:
            continue
        if y == 110:
            R.put((105, y), "obj", obj=[("/obj/machinery/door/window/westleft", {"dir": 8, "name": "Bar Door",
                                                                                 "req_access_txt": "25"})])
        else:
            R.put((105, y), "obj", obj=[WOOD] + {112: ["/obj/item/reagent_containers/glass/rag"],
                                                  114: ["/obj/item/storage/pill_bottle/dice"],
                                                  116: ["/obj/item/storage/box/matches"]}.get(y, []))
        if (104, y) in R.tiles and y != 110:
            R.put((104, y), "open", obj=[(STOOL, {"dir": 4})])
    back = [((107, 116), ["/obj/structure/closet/gmcloset"]),
            ((107, 115), [WOOD, ("/obj/machinery/chem_dispenser/drinks", {"dir": 8})]),
            ((107, 114), [WOOD, ("/obj/machinery/chem_dispenser/drinks/beer", {"dir": 8})]),
            ((107, 113), ["/obj/machinery/vending/boozeomat"]),
            ((107, 112), [WOOD, "/obj/item/reagent_containers/food/drinks/shaker",
                          "/obj/item/storage/box/drinkingglasses"]),
            ((107, 111), ["/obj/machinery/vending/wardrobe/bar_wardrobe"])]
    for p, objs in back:
        if p in R.tiles:
            R.put(p, "obj", obj=objs)
    R.reserve([(106, y) for y in range(108, 117)] + [(107, 108), (107, 109), (107, 110), (104, 110)], "open")
    R.mark((106, 113), "/obj/effect/landmark/start/bartender")
    for (x, y) in ((100, 115), (100, 110), (102, 112)):
        R.put((x, y), "obj", obj=[WOOD, "/obj/item/reagent_containers/food/drinks/drinkingglass"])
        for dx, dy, d in ((-1, 0, 4), (1, 0, 8), (0, 1, 2), (0, -1, 1)):
            q = (x + dx, y + dy)
            if q in R.tiles and q not in R.geo.taken:
                R.put(q, "open", obj=[(CHAIR, {"dir": d})])
    for p in R.tiles:
        if p[0] <= 104:
            R.put(p, None, decal=[(BARTILE, {"dir": 1}), (BARTILE, {"dir": 2})] if (p[0] + p[1]) % 2 == 0
                  else [(BARTILE, {"dir": 4}), (BARTILE, {"dir": 8})])
    hall = (R.doors("hall") or R.doors())[0]
    R.place(one("jukebox", "JB", "/obj/machinery/jukebox"), near=hall, must=False)
    R.place(hang("bar sign", "sign", "/obj/structure/sign/barsign"), side=R.side("hall"), near=hall, must=False)
    free = [p for p in R.tiles if p not in R.geo.taken]
    if free:
        R.put(min(free, key=lambda p: dist(p, R.room.attrs["heart"])), "open", obj=["/obj/machinery/holopad"])


def hydro2(R):
    # the botanists' kit first, along the walls by the door: the gene machine, lockers and wardrobe, the
    # biogenerator, the sink and a high water tank; then the tray rows
    desk = (R.doors("hall") or R.doors())[0]
    R.run([one("gene machine", "DN", "/obj/machinery/plantgenes"),
           one("botany locker", "L", "/obj/structure/closet/secure_closet/hydroponics"),
           one("botany wardrobe", "W", "/obj/machinery/vending/wardrobe/hydro_wardrobe")], near=desk)
    R.place(one("biogenerator", "BG", "/obj/machinery/biogenerator"))
    R.place(one("tools", "t", TABLE, "/obj/item/cultivator", "/obj/item/hatchet", "/obj/item/plant_analyzer",
                "/obj/item/reagent_containers/glass/bucket", back="wall"), must=False)
    V1["hydro"](R)


def theatre2(R):
    # a wooden stage across the east end, seats in rows facing it either side of the door aisle, the props
    # and the clown's and mime's places backstage in the tail
    for x in range(115, 118):
        for y in range(91, 98):
            if (x, y) in R.tiles:
                R.put((x, y), "open", floor="/turf/open/floor/wood")
    R.put((116, 97), "obj", obj=["/obj/structure/piano"])
    for x in range(115, 118):
        if (x, 91) in R.tiles:
            R.put((x, 91), "open", obj=["/obj/structure/curtain"])
    for x in range(110, 113):
        for y in (91, 92, 95, 96, 97):
            if (x, y) in R.tiles and (x, y) not in R.geo.taken:
                R.put((x, y), "open", obj=[(CHAIR, {"dir": 4})])
    for (x, y), objs in (((115, 89), ["/obj/machinery/vending/autodrobe"]), ((117, 89), ["/obj/structure/dresser"]),
                         ((116, 89), [WOOD, "/obj/item/bikehorn", "/obj/item/toy/crayon/mime"])):
        if (x, y) in R.tiles:
            R.put((x, y), "obj", obj=objs)
    for (x, y), job in (((115, 90), "clown"), ((117, 90), "mime")):
        if (x, y) in R.tiles:
            R.mark((x, y), "/obj/effect/landmark/start/%s" % job)
    R.place(hang("theatre poster", "sign", "/obj/structure/sign/poster/official/random"), must=False)


ASSETS.update({"bar": bar2, "hydro": hydro2, "theatre": theatre2})


# ================================================================================================= review 3 (11-21)
def put_if_free(R, p, why, **spec):
    if p in R.tiles and R.geo.taken.get(p) != "obj":
        R.put(p, why, **spec)
        return True
    R.geo.problem("%s: %d,%d is not free" % (R.rid, p[0], p[1]))
    return False


def hydro3(R):
    # water first, on the wall by the door: the high tank and the sink (review 3 #1)
    put_if_free(R, (109, 114), "obj", obj=["/obj/structure/reagent_dispensers/watertank/high"])
    put_if_free(R, (109, 112), "obj", obj=[("/obj/structure/sink", {"dir": 4, "pixel_x": -12})])
    hydro2(R)
    R.place(hang("botany sign", "sign", "/obj/structure/sign/departments/botany"), side=R.side("hall"), must=False)


def dining3(R):
    dining(R)
    # two more tables of four in the empty south part, the door landing clear (review 3 #2)
    for (x, y) in ((102, 101), (106, 100)):
        if put_if_free(R, (x, y), "obj", obj=[WOOD, "/obj/item/reagent_containers/food/condiment/saltshaker"]):
            for dx, dy, d in ((-1, 0, 4), (1, 0, 8), (0, 1, 2), (0, -1, 1)):
                q = (x + dx, y + dy)
                if q in R.tiles and q not in R.geo.taken and q not in ((101, 99), (102, 99)):
                    R.put(q, "open", obj=[(CHAIR, {"dir": d})])


def bar3(R):
    bar2(R)
    # the bar sign on the arterial face of the north wall: a sign on a wall turf shows on both faces (review 3 #4)
    R.put((100, 116), None, obj=[("/obj/structure/sign/barsign", {"pixel_y": 32})])
    R.faces[((100, 116), 1)] = "bar sign"


def theatre3(R):
    theatre2(R)
    R.put((110, 95), None, obj=[("/obj/structure/sign/poster/official/random", {"pixel_x": -32})])
    R.faces[((110, 95), 8)] = "theatre sign"


ASSETS.update({"hydro": hydro3, "dining": dining3, "bar": bar3, "theatre": theatre3})


# ================================================================================================= review 4 (11-21)
def hydro4(R):
    # one biogenerator (v1's hydro places its own), the water by the door, the tray rows; the botany sign over the
    # north-west tile, on the arterial wall (Service review 4 #1, #2)
    put_if_free(R, (109, 114), "obj", obj=["/obj/structure/reagent_dispensers/watertank/high"])
    put_if_free(R, (109, 112), "obj", obj=[("/obj/structure/sink", {"dir": 4, "pixel_x": -12})])
    desk = (R.doors("hall") or R.doors())[0]
    R.run([one("gene machine", "DN", "/obj/machinery/plantgenes"),
           one("botany locker", "L", "/obj/structure/closet/secure_closet/hydroponics"),
           one("botany wardrobe", "W", "/obj/machinery/vending/wardrobe/hydro_wardrobe")], near=desk)
    R.place(one("tools", "t", TABLE, "/obj/item/cultivator", "/obj/item/hatchet", "/obj/item/plant_analyzer",
                "/obj/item/reagent_containers/glass/bucket", back="wall"), must=False)
    R.reserve([(109, 116)], "open")
    V1["hydro"](R)
    R.put((109, 116), None, obj=[("/obj/structure/sign/departments/botany", {"pixel_y": 32})])
    R.faces[((109, 116), 1)] = "botany sign"


def theatre4(R):
    theatre3(R)
    R.put((110, 96), None, obj=[("/obj/structure/sign/poster/contraband/random", {"pixel_x": -32})])
    R.faces[((110, 96), 8)] = "theatre poster"


ASSETS.update({"hydro": hydro4, "theatre": theatre4})
