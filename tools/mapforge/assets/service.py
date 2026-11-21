"""Room assets for Service's kitchen and hydroponics: how each room is played, as kits and placing rules.

From Hippie's own kitchen and garden (census 2026-11-16, x146-164 y131-146) and how a shift uses it:
  kitchen     the cook works between the counter (served over its shutters onto the hallway) and the stoves;
              the bar's doors on one side, the garden's windoor and smartfridge on the other
  cold room   meat: spikes, the gibber, the meat freezer, the oil; the delivery chute comes in here
  hydroponics rows of trays with room to walk round each, the vendors and the seed extractor by the desk
  back room   the gene machine, lockers, the bees, tools on a table; its own delivery chute
An asset never names a coordinate. It asks the room which wall faces which neighbour and where its doors are.
"""
from forge.proc.place import Kit, cell, dist
from assets.science import TABLE, BOT, one, hang, apart

COOK = "/obj/effect/landmark/start/cook"
BOTANIST = "/obj/effect/landmark/start/botanist"


def free_spots(R, near, n):
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    return sorted(free, key=lambda p: (dist(p, near), p))[:n]


# ================================================================================================= kitchen
STOVES = Kit("stoves", [
    cell(0, 0, "/obj/machinery/grill", label="GR"),
    cell(1, 0, "/obj/machinery/deepfryer", label="DF"),
    cell(2, 0, "/obj/machinery/deepfryer", label="DF"),
], use=[(0, 1), (1, 1), (2, 1)])
PREP = Kit("prep table", [
    cell(0, 0, TABLE, "/obj/item/kitchen/rollingpin", "/obj/item/book/manual/chef_recipes", label="t"),
    cell(1, 0, TABLE, "/obj/item/reagent_containers/food/condiment/saltshaker",
         "/obj/item/reagent_containers/food/condiment/peppermill", "/obj/item/reagent_containers/food/snacks/mint", label="t"),
    cell(2, 0, TABLE, "/obj/item/storage/box/donkpockets", "/obj/item/reagent_containers/glass/beaker",
         "/obj/item/reagent_containers/food/condiment/enzyme", "/obj/item/stack/packageWrap", label="t"),
], use=[(0, 1), (1, 1), (2, 1), (0, -1), (1, -1), (2, -1)], back=None, tight=True)


def kitchen(R):
    # the stoves and microwaves on the walls, the prep table in the middle, fridges by the cold room
    counter = (R.doors("counter") or R.doors())[0]
    R.place(STOVES, far=counter, must=False)
    R.run([one("microwave", "t", TABLE, "/obj/machinery/microwave", back="any"),
           one("microwave", "t", TABLE, "/obj/machinery/microwave", back="any")])
    dwall = R.geo.field("dwall")
    R.place(PREP, near=R.room.attrs["heart"], must=False,
            need=lambda pl: apart(R, pl, 1) and all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    R.run([one("processor", "PR", "/obj/machinery/processor"),
           one("grinder", "t", TABLE, "/obj/machinery/reagentgrinder", back="any")])
    R.run([one("fridge", "L", "/obj/structure/closet/secure_closet/freezer/fridge"),
           one("kitchen freezer", "L", "/obj/structure/closet/secure_closet/freezer/kitchen")],
          near=(R.doors("cold") or [counter])[0])
    # a smartfridge already set into the kitchen/hydroponics wall (v6) is the shared one
    if not any(dr.get("spec", {}).get("type") == "smartfridge" for dr in R.geo.doors.values()):
        R.place(one("smartfridge", "SF", "/obj/machinery/smartfridge"), near=(R.doors("hydro") or [counter])[0],
                must=False)
    R.run([one("dinnerware", "V", "/obj/machinery/vending/dinnerware"),
           one("chef wardrobe", "W", "/obj/machinery/vending/wardrobe/chef_wardrobe")])
    R.place(one("condimaster", "CM", "/obj/machinery/chem_master/condimaster"), must=False)
    R.place(one("ice cream", "IC", "/obj/machinery/icecream_vat"), must=False)
    R.place(one("sink", "SK", ("/obj/structure/sink/kitchen", {"dir": "IN"}), back="wall"), must=False)
    R.place(one("food cart", "FC", "/obj/machinery/food_cart", back="any"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Kitchen RC", "department": "Kitchen", "departmentType": 2}), near=counter, must=False)
    R.place(hang("counter shutters", "button", "/obj/machinery/button/door",
                 {"name": "Kitchen Counter Shutters", "id": "kitchen", "req_access_txt": "28"}), near=counter,
            must=False)
    R.place(hang("intercom", "intercom", "/obj/item/radio/intercom"), must=False)
    for p in free_spots(R, counter, 2):
        R.mark(p, COOK)
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")


def cold(R):
    # meat on the spikes by the door, the gibber beyond, the freezer and the oil drum
    door = (R.doors("kitchen") or R.doors())[0]
    R.run([one("spike", "SP", "/obj/structure/kitchenspike")] * 2, far=door)
    R.place(one("gibber", "GB", "/obj/machinery/gibber"), must=False)
    R.place(one("meat freezer", "L", "/obj/structure/closet/secure_closet/freezer/meat"), must=False)
    R.place(one("oil", "OL", "/obj/structure/reagent_dispensers/cooking_oil"), must=False)
    spots = free_spots(R, R.room.attrs["heart"], 1)
    if spots:
        R.mark(spots[0], "/mob/living/simple_animal/hostile/retaliate/goat")


# ================================================================================================= hydroponics
TRAYS = Kit("tray row", [
    cell(0, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
    cell(1, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
    cell(2, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
    cell(3, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
], use=[(0, 1), (1, 1), (2, 1), (3, 1), (0, -1), (1, -1), (2, -1), (3, -1)], back=None, tight=True)
TRAYS3 = Kit("short tray row", [
    cell(0, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
    cell(1, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
    cell(2, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
], use=[(0, 1), (1, 1), (2, 1), (0, -1), (1, -1), (2, -1)], back=None, tight=True)


TRAYS2 = Kit("tray pair", [
    cell(0, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
    cell(1, 0, "/obj/machinery/hydroponics/constructable", label="H", decal=[BOT]),
], use=[(0, 1), (1, 1), (0, -1), (1, -1)], back=None, tight=True)


def hydro(R):
    # tray rows with a walk round each, the vendors and extractor near the desk, water at hand
    desk = (R.doors("desk") or R.doors())[0]
    dwall = R.geo.field("dwall")
    # rows in the open first, then rows along a wall (a garden is mostly trays)
    # each row beside the last, so the rows pack and leave room for the next
    near = R.room.attrs["heart"]
    trays = 0
    for k in (TRAYS, TRAYS, TRAYS, TRAYS3, TRAYS3):
        pl = R.place(k, near=near, must=False,
                     need=lambda pl: apart(R, pl, 1) and all(dwall.get(t, 0) >= 2 for t in pl.tiles))
        pl = pl or R.place(k, near=near, must=False, need=lambda pl: apart(R, pl, 1))
        if pl:
            near = pl.origin
            trays += len(k.cells)
    # where the walkways cut the room short, pairs fill in (a garden wants a dozen trays)
    while trays < 12:
        pl = R.place(TRAYS2, near=near, must=False, need=lambda pl: apart(R, pl, 1))
        if not pl:
            break
        near, trays = pl.origin, trays + 2
    R.run([one("nutrients", "V", "/obj/machinery/vending/hydronutrients"),
           one("seeds", "V", "/obj/machinery/vending/hydroseeds"),
           one("seed extractor", "SE", "/obj/machinery/seed_extractor"),
           one("biogenerator", "BG", "/obj/machinery/biogenerator")], near=desk)
    R.run([one("water tank", "WT", "/obj/structure/reagent_dispensers/watertank/high"),
           one("sink", "SK", ("/obj/structure/sink", {"dir": "IN"}), back="wall")])
    R.place(one("water tank", "WT", "/obj/structure/reagent_dispensers/watertank/high"), far=desk, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Hydroponics RC", "department": "Hydroponics", "departmentType": 2}), near=desk, must=False)
    for p in free_spots(R, desk, 2):
        R.mark(p, BOTANIST)
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")


def hydroback(R):
    # the gene machine and lockers, the hive, tools; the way through to the pen kept clear
    R.place(one("gene machine", "PG", "/obj/machinery/plantgenes"), must=False)
    R.run([one("botanist locker", "L", "/obj/structure/closet/secure_closet/hydroponics")] * 2)
    R.place(one("hydro wardrobe", "W", "/obj/machinery/vending/wardrobe/hydro_wardrobe"), must=False)
    R.place(one("bees", "BX", "/obj/structure/beebox/unwrenched", back="any"), must=False)
    R.place(one("bee crate", "CR", "/obj/structure/closet/crate/secure/hydroponics", "/obj/item/queen_bee/bought",
                "/obj/item/honey_frame", "/obj/item/honey_frame", "/obj/item/honey_frame",
                "/obj/item/melee/flyswatter"), must=False)
    R.place(one("tools", "t", TABLE, "/obj/item/reagent_containers/spray/plantbgone",
                "/obj/item/reagent_containers/spray/plantbgone", "/obj/item/watertank", "/obj/item/shovel/spade",
                "/obj/item/wrench", "/obj/item/wirecutters", "/obj/item/reagent_containers/glass/bucket", back="any"),
            must=False)
    R.place(one("books", "t", TABLE, "/obj/item/book/manual/hydroponics_pod_people",
                "/obj/item/paper/guides/jobs/hydroponics", back="any"), must=False)
    R.place(one("condimaster", "CM", "/obj/machinery/chem_master/condimaster"), must=False)
    R.place(one("grinder", "t", TABLE, "/obj/machinery/reagentgrinder", back="any"), must=False)
    R.place(one("sink", "SK", ("/obj/structure/sink", {"dir": "IN"}), back="wall"), must=False)
    for p in free_spots(R, R.room.attrs["heart"], 1):
        R.mark(p, BOTANIST)


ASSETS = {"kitchen": kitchen, "cold": cold, "hydro": hydro, "hydroback": hydroback}
