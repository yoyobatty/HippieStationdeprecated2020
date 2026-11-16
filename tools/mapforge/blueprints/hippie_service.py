"""Hippie Station service block: bar, stage, kitchen + cold room, hydroponics, husbandry, service hall.

Same outer shell as the 2020 map (hall doors, west shutters, kitchen counter, hydro desk, delivery chutes, theatre
maintenance door are kept as they are: '~'). Everything inside is redrawn.

Layout columns are x 130..166, rows y 153 (top) .. 131 (bottom). '~' keeps the existing tile.
"""
NAME = "hippie_service"
STYLE = "meta"
DRESS_HALL_FRONT = True
ORIGIN = (130, 131)

#         x: 0123456789012345678901234567890123456
#            1         1         1         1
#            3         4         5         6
LAYOUT = """
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~1.2.~~
~~~~~~~~~~~~~~~~~~~~~~~~~~F.~~~.../7.
~~~~~~~~~~~~~~~~~~~~~~~~~~1.~~~...|.7
~~~~~~~~~~~~~~~~~~~~~~~~~~2.~~~45.,7.
~~~~d...~~~~~~~~~~~~~~~~~~..~~~6.53~~
~~~~m..B~~~~~~~~~~~~~~~~~~~~~~~~.5~~~
~~~~a..l~~~~~~~~~~~~~~~~~~~~~~~~N#~~~
~~~~k..k~~~~~~~~~~~~~~~~~~~~~~~~..~~~
~~~~~#D#~~~~#K.Wk~~~~~~~~~~~~~~~..~~~
~~~~i..I.j.B#z....#7.7~#~q+.*^^:;.~~~
~~Prrrrrg...#M4...#....##.........~~~
~~o..4...6ZX#Z.G..#8.$.9##==..==..~~~
~~yqq.qq.#####D####0....!#...e...B~~~
~~v..5CCscOdeY.x#z##&#####.SS.SS.]~~~
~~V.3CKKsc.@u..R#.nu.fXVY#.SS.SS.]~~~
~~QLQ..h.c1c2ccw#q......G#zSS.SS.z~~~
~~QFQ.CC.ssssss.E..oobh..~.SS.SS.}~~~
~~.3.CTTC.......H..ltLj.r#.AA..A.[~~~
~~QLQ.CC..CC....H.......r#<..()..[~~~
~~QFQ....CTTC..m#OK.@@.RB#>......?~~~
~~p.N..4..CC.amm~~~~~~~~~~...~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""

ROOMS = """
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~HHHH~~
~~~~~~~~~~~~~~~~~~~~~~~~~~ss~~~HHHggg
~~~~~~~~~~~~~~~~~~~~~~~~~~ss~~~HHHggg
~~~~~~~~~~~~~~~~~~~~~~~~~~ss~~~HHHggg
~~~~wwww~~~~~~~~~~~~~~~~~~ss~~~HHHH~~
~~~~wwww~~~~~~~~~~~~~~~~~~~~~~~~HH~~~
~~~~wwww~~~~~~~~~~~~~~~~~~~~~~~~H~~~~
~~~~wwww~~~~~~~~~~~~~~~~~~~~~~~~HH~~~
~~~~~~w~~~~~~SSSS~~~~~~~~~~~~~~~HH~~~
~~~~pppppbbb~SSSSS~ccc~~~hhhhhhhhh~~~
~~pppppppbbb~SSSSS~cccc~~hhhhhhhhh~~~
~~lllllllbbb~SSSSS~ccccc~~~~hh~~hh~~~
~~lllllll~~~~~S~~~~cccccc~hhhhhhhh~~~
~~bbbbbbbbbbbbbb~k~~c~~~~~hhhhhhhh~~~
~~bbbbbbbbbbbbbb~kkkkkkkk~hhhhhhhh~~~
~~lllbbbbbbbbbbb~kkkkkkkk~hhhhhhhh~~~
~~lllbbbbbbbbbbbkkkkkkkkk~hhhhhhhh~~~
~~lllbbbbbbbbbbbkkkkkkkkk~hhhhhhhh~~~
~~lllbbbbbbbbbbbkkkkkkkkk~hhhhhhhh~~~
~~lllbbbbbbbbbbb~kkkkkkkk~hhhhhhhh~~~
~~bbbbbbbbbbbbbb~~~~~~~~~~hhh~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""

TABLE = "/obj/structure/table"
RTABLE = "/obj/structure/table/reinforced"
WTABLE = "/obj/structure/table/wood"


def L(*objs, **kw):
    d = dict(kw)
    d["obj"] = list(objs)
    return d


LEGEND = {
    "B": {"no_vent": True},  # carried-over disposal bin
    "p": L("/obj/item/twohanded/required/kirbyplants/random"),
    "C": L("/obj/structure/chair/wood/normal", face="table"),
    "T": L(WTABLE),
    "t": L(TABLE),
    "c": L(RTABLE),
    "s": L("/obj/structure/chair/stool/bar"),
}

BAR = {
    "Q": L("/obj/structure/chair/comfy/brown", face="table"),
    "F": L("/obj/structure/table/wood/fancy/black"),
    "L": L("/obj/structure/table/wood/fancy/black", "/obj/item/flashlight/lamp/green"),
    "q": L("/obj/structure/chair/comfy/black", face="north"),
    "1": L(RTABLE, "/obj/item/reagent_containers/food/drinks/shaker", "/obj/item/reagent_containers/glass/rag"),
    "2": L(RTABLE, "/obj/item/toy/cards/deck", "/obj/item/clothing/mask/cigarette/cigar"),
    "w": L(("/obj/machinery/door/window/southright", {"name": "Bar Door", "req_one_access_txt": "25;28"})),
    "g": L(("/obj/machinery/door/window/westleft", {"name": "Bar Hatch", "req_access_txt": "25"})),
    "O": L("/obj/machinery/vending/boozeomat"),
    "d": L("/obj/machinery/chem_dispenser/drinks", face="open"),
    "e": L("/obj/machinery/chem_dispenser/drinks/beer", face="open"),
    "Y": {"no_vent": True, "mount": [("sign", "/obj/structure/sign/warning/securearea", {
        "name": "Mr. Deempisi portrait",
        "desc": "Under the painting a plaque reads: 'While the meat grinder may not have spared you, fear not. "
                "Not one part of you has gone to waste... You were delicious.'",
        "icon_state": "monkey_painting"})]},
    "x": dict(obj=[RTABLE, "/obj/item/reagent_containers/food/drinks/shaker", "/obj/item/book/manual/wiki/barman_recipes",
                   "/obj/item/clothing/head/that"],
              mount=[("button", "/obj/machinery/button/door", {"name": "bar shutters", "id": "barShutters"})]),
    "j": L("/obj/machinery/jukebox"),
    "@": L("/obj/effect/landmark/start/bartender"),
    "u": L("/mob/living/carbon/monkey/punpun"),
    "R": dict(mount=[("requests_console", "/obj/machinery/requests_console",
                      {"department": "Bar", "departmentType": 2, "receive_ore_updates": 1})]),
    "V": dict(mount=[("telescreen", "/obj/machinery/computer/security/telescreen/entertainment", {})]),
    "v": L("/obj/machinery/vending/cola/random"),
    "y": L("/obj/machinery/vending/cigarette"),
    "o": L("/obj/machinery/vending/coffee"),
    "a": L("/obj/machinery/computer/arcade", face="open"),
    "m": L("/obj/machinery/computer/slot_machine", face="open"),
    "h": L("/obj/machinery/holopad"),
    "3": L("/obj/effect/landmark/start/assistant"),
    "4": L("/obj/effect/landmark/event_spawn"),
    "5": L("/obj/effect/landmark/blobstart"),
    "6": L("/obj/effect/landmark/xeno_spawn"),
    "X": L("/obj/effect/spawner/xmastree"),
    "K": L("/obj/structure/table/wood/poker", "/obj/item/toy/cards/deck"),
    "N": dict(mount=[("noticeboard", "/obj/structure/noticeboard", {})]),
    "Z": dict(mount=[("status_display", "/obj/machinery/status_display/evac", {})]),
}

STORAGE = {
    "K": L(("/obj/structure/closet/secure_closet/bar", {"req_access_txt": "25"})),
    "k": L("/obj/structure/reagent_dispensers/beerkeg"),
    "W": L("/obj/machinery/vending/wardrobe/bar_wardrobe"),
    "M": L(TABLE, "/obj/item/stack/sheet/metal/fifty", "/obj/item/stack/sheet/glass/fifty", "/obj/item/stack/cable_coil",
           "/obj/item/clothing/head/hardhat/cakehat", "/obj/item/toy/beach_ball/holoball"),
    "z": dict(mount=[("sink", "/obj/structure/sink/kitchen", {})]),
    "Z": L("/obj/structure/closet/crate/bin"),
    "G": L(TABLE, "/obj/item/gun/ballistic/shotgun/doublebarrel", "/obj/item/lighter", "/obj/item/stack/spacecash/c100"),
    "D": L(("/obj/machinery/door/airlock", {"name": "Bar Storage", "req_access_txt": "25"})),
    "4": L("/obj/effect/landmark/event_spawn"),
}

STAGE = {
    "P": L(("/obj/structure/piano", {"icon_state": "piano"}), ("/obj/structure/railing", {})),
    "r": L(("/obj/structure/railing", {})),
    "g": L(("/obj/structure/railing", {}), ("/obj/machinery/door/window", {"name": "Theatre Stage", "dir": 4})),
    "i": L(WTABLE, "/obj/item/instrument/violin", "/obj/item/saxophone"),
    "I": L(WTABLE, ("/obj/item/instrument/guitar", {"pixel_x": -7}), ("/obj/item/instrument/eguitar", {"pixel_x": 5})),
}

BACKSTAGE = {
    "d": L("/obj/structure/dresser"),
    "m": dict(obj=["/obj/structure/chair/stool"], mount=[("mirror", "/obj/structure/mirror", {})]),
    "a": L("/obj/machinery/vending/autodrobe"),
    "l": L(WTABLE, "/obj/item/lipstick/random", "/obj/item/storage/crayons"),
    "k": L("/obj/structure/closet"),
    "D": L(("/obj/machinery/door/airlock", {"name": "Theatre Backstage", "req_access_txt": "46"})),
}

KITCHEN = {
    "E": L(("/obj/machinery/door/airlock/public/glass", {"name": "Kitchen", "req_access_txt": "28"})),
    "H": L(RTABLE, ("/obj/machinery/door/poddoor/shutters/preopen", {"name": "kitchen shutters", "id": "kitchen"}),
           "/obj/machinery/door/firedoor"),
    "z": dict(mount=[("sink", "/obj/structure/sink/kitchen", {})]),
    "n": L(("/obj/machinery/chem_master/condimaster", {"name": "CondiMaster Neo"})),
    "u": L("/obj/machinery/vending/dinnerware"),
    "f": L("/obj/machinery/smartfridge"),
    "X": L("/obj/machinery/vending/wardrobe/chef_wardrobe"),
    "Y": L("/obj/machinery/food_cart"),
    "V": L("/obj/machinery/icecream_vat"),
    "R": L("/obj/machinery/processor"),
    "q": dict(mount=[("requests_console", "/obj/machinery/requests_console", {"department": "Kitchen", "departmentType": 2})]),
    "o": L(TABLE, ("/obj/machinery/microwave", {"pixel_y": 6})),
    "b": L(TABLE, "/obj/item/book/manual/chef_recipes", "/obj/item/kitchen/rollingpin"),
    "h": L(TABLE, ("/obj/item/reagent_containers/food/condiment/saltshaker", {"pixel_x": -3}),
           ("/obj/item/reagent_containers/food/condiment/peppermill", {"pixel_x": 3}),
           ("/obj/item/reagent_containers/food/condiment/enzyme", {"layer": 5})),
    "l": L(TABLE, "/obj/item/storage/fancy/donut_box"),
    "t": L(TABLE, ("/obj/item/storage/box/donkpockets", {"pixel_x": 3, "pixel_y": 3})),
    "L": L(TABLE, "/obj/machinery/reagentgrinder"),
    "j": L(TABLE, ("/obj/item/reagent_containers/glass/beaker", {"pixel_x": 5}), "/obj/item/stack/packageWrap"),
    "r": L("/obj/machinery/deepfryer"),
    "G": L("/obj/machinery/grill"),
    "O": L("/obj/structure/reagent_dispensers/cooking_oil"),
    "@": L("/obj/effect/landmark/start/cook"),
    "K": dict(mount=[("button", "/obj/machinery/button/door",
                      {"name": "Kitchen Shutters Control", "id": "kitchen", "req_access_txt": "28"})]),
    "e": L("/obj/effect/landmark/event_spawn"),
}

COLD = {
    "7": L("/obj/structure/kitchenspike"),
    "8": L("/obj/machinery/gibber"),
    "9": L("/obj/structure/closet/secure_closet/freezer/fridge"),
    "0": L("/obj/structure/closet/secure_closet/freezer/kitchen"),
    "!": L("/obj/structure/closet/secure_closet/freezer/meat"),
    "$": L(("/mob/living/simple_animal/hostile/retaliate/goat", {"name": "Pete"})),
    "&": L(("/obj/machinery/door/airlock", {"name": "Kitchen Cold Room", "req_access_txt": "28"})),
}

HYDRO = {
    "S": dict(obj=["/obj/machinery/hydroponics/constructable"], floor="/turf/open/floor/plasteel/dark"),
    "+": L("/obj/machinery/seed_extractor"),
    "*": L("/obj/machinery/plantgenes"),
    "^": L("/obj/machinery/biogenerator"),
    ":": L("/obj/machinery/chem_master/condimaster"),
    ";": L(TABLE, "/obj/machinery/reagentgrinder"),
    "<": L(("/obj/machinery/vending/hydroseeds", {"slogan_delay": 700})),
    ">": L("/obj/machinery/vending/hydronutrients"),
    "?": L("/obj/machinery/vending/wardrobe/hydro_wardrobe"),
    "[": L("/obj/structure/reagent_dispensers/watertank/high"),
    "]": L("/obj/structure/closet/secure_closet/hydroponics"),
    "{": L("/obj/structure/closet/crate/hydroponics"),
    "}": L("/obj/structure/closet/crate/secure/hydroponics"),
    "(": L(TABLE, "/obj/item/reagent_containers/glass/bucket", "/obj/item/reagent_containers/glass/bucket",
           "/obj/item/shovel/spade", "/obj/item/wrench", "/obj/item/wirecutters", "/obj/item/watertank"),
    ")": L(TABLE, ("/obj/item/reagent_containers/spray/plantbgone", {"pixel_x": 8, "pixel_y": 8}),
           ("/obj/item/reagent_containers/spray/plantbgone", {"pixel_y": 3}), "/obj/item/melee/flyswatter",
           "/obj/item/book/manual/hydroponics_pod_people", "/obj/item/paper/guides/jobs/hydroponics"),
    "A": L("/obj/effect/landmark/start/botanist"),
    "q": dict(mount=[("requests_console", "/obj/machinery/requests_console", {"department": "Hydroponics", "departmentType": 2})]),
    "z": dict(mount=[("sink", "/obj/structure/sink", {})]),
    "e": L("/obj/effect/landmark/event_spawn"),
}

HUSBANDRY = {
    "1": L(TABLE, "/obj/item/honey_frame", "/obj/item/honey_frame", "/obj/item/honey_frame", "/obj/item/queen_bee/bought"),
    "2": L("/obj/structure/beebox/unwrenched"),
    "3": L(TABLE, "/obj/item/reagent_containers/food/snacks/grown/wheat", "/obj/item/reagent_containers/food/snacks/grown/wheat",
           "/obj/item/reagent_containers/glass/bucket"),
    "4": L(("/obj/structure/bed/dogbed", {"name": "chicken bed"}), "/mob/living/simple_animal/chicken"),
    "5": L("/mob/living/simple_animal/chicken"),
    "6": L("/obj/structure/closet/crate/hydroponics"),
    "N": L(("/obj/machinery/door/airlock/public/glass", {"name": "Animal Husbandry", "req_access_txt": "35"})),
}

PEN = {
    "/": L(("/obj/structure/railing", {"dir": 8}), ("/obj/structure/railing", {"dir": 1})),
    "|": L(("/obj/machinery/door/window/westleft", {"name": "Animal pen", "req_access_txt": "35"})),
    ",": L(("/obj/structure/railing", {"dir": 8}), ("/obj/structure/railing", {"dir": 2})),
    "7": L("/mob/living/simple_animal/cow"),
}

SERVICE = {
    "F": L("/obj/machinery/rnd/production/techfab/department/service"),
    "1": L(TABLE, "/obj/item/hatchet/wooden", "/obj/item/reagent_containers/glass/bucket"),
    "2": L(TABLE, "/obj/item/kitchen/rollingpin", "/obj/item/reagent_containers/spray/plantbgone"),
}

ROOMDEFS = {
    "b": dict(area="/area/crew_quarters/bar", floor="/turf/open/floor/wood", name="Bar", newscaster=True, legend=BAR),
    "l": dict(area="/area/crew_quarters/bar", floor="/turf/open/floor/carpet", name="Lounge", main=False, legend=BAR),
    "S": dict(area="/area/crew_quarters/bar", floor="/turf/open/floor/plasteel/dark", name="Bar Storage", main=False,
              legend=STORAGE),
    "p": dict(area="/area/crew_quarters/theatre", floor="/turf/open/floor/carpet/black", name="Theatre", legend=STAGE),
    "w": dict(area="/area/crew_quarters/theatre", floor="/turf/open/floor/wood", name="Backstage", main=False,
              legend=BACKSTAGE),
    "k": dict(area="/area/crew_quarters/kitchen", floor="/turf/open/floor/plasteel/cafeteria", name="Kitchen", legend=KITCHEN),
    "c": dict(area="/area/crew_quarters/kitchen", floor="/turf/open/floor/plasteel/kitchen_coldroom/freezerfloor",
              name="Cold Room", main=False, legend=COLD),
    "h": dict(area="/area/hydroponics", floor="/turf/open/floor/plasteel", name="Hydroponics", trim="green", legend=HYDRO),
    "H": dict(area="/area/hydroponics", floor="/turf/open/floor/plasteel", name="Animal Husbandry", main=False,
              legend=HUSBANDRY),
    "g": dict(area="/area/hydroponics", floor="/turf/open/floor/grass", name="Animal Pen", main=False, legend=PEN),
    "s": dict(area="/area/hallway/secondary/service", floor="/turf/open/floor/plasteel", name="Service Hall",
              legend=SERVICE, camera=False),
}

# finishing touches by coordinate
EXTRA = [
    (140, 133, "/obj/item/reagent_containers/food/condiment/saltshaker", {"pixel_x": -2, "pixel_y": 2}),
    (141, 133, "/obj/item/reagent_containers/food/condiment/peppermill", {"pixel_x": 5, "pixel_y": -2}),
    (136, 135, "/obj/item/kitchen/fork", {}),
    (137, 135, "/obj/item/flashlight/lamp", {}),
    (151, 135, "/obj/item/reagent_containers/food/snacks/mint", {}),
    (145, 141, "/obj/item/stack/spacecash/c100", {}),
    (145, 141, "/obj/item/stack/spacecash/c100", {}),
    (145, 141, "/obj/item/stack/spacecash/c10", {}),
    (159, 134, "/obj/item/reagent_containers/glass/bucket", {}),
    (160, 134, "/obj/item/reagent_containers/spray/plantbgone", {"pixel_x": 13, "pixel_y": 5}),
    (143, 138, "/obj/effect/landmark/event_spawn", {}),
    (135, 137, "/obj/effect/landmark/start/assistant", {}),
    (164, 148, "/obj/item/reagent_containers/food/snacks/grown/wheat", {}),
    (145, 139, "/obj/machinery/reagentgrinder", {"pixel_y": 8}),
]
MOUNTS = [
    (135, 132, "south", "sign", "/obj/structure/sign/poster/official/soft_cap_pop_art", {}),
    (163, 142, "east", "sign", "/obj/structure/sign/poster/official/high_class_martini", {}),
    (144, 132, "south", "telescreen", "/obj/machinery/computer/security/telescreen/entertainment", {}),
]

# the stage opens onto the bar on purpose (railings, not walls)
OPEN_SEAMS = [("/area/crew_quarters/bar", "/area/crew_quarters/theatre")]
