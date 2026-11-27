// Where fishing gear comes from: crafting, a cargo crate, and the exosuit rod from the exosuit fabricator

/datum/crafting_recipe/fishing_rod
	name = "Makeshift Fishing Rod"
	result = /obj/item/fishing_rod
	reqs = list(/obj/item/stack/rods = 2, /obj/item/stack/cable_coil = 5)
	time = 40
	category = CAT_MISC

/datum/crafting_recipe/fishing_hook
	name = "Fishing Hook"
	result = /obj/item/fishing_hook
	reqs = list(/obj/item/stack/rods = 1)
	tools = list(TOOL_WIRECUTTER)
	time = 20
	category = CAT_MISC

/datum/crafting_recipe/fishing_line
	name = "Fishing Line"
	result = /obj/item/fishing_line
	reqs = list(/obj/item/stack/cable_coil = 5)
	time = 20
	category = CAT_MISC

/datum/crafting_recipe/fishing_line_long
	name = "Deep Fishing Line"
	result = /obj/item/fishing_line/long
	reqs = list(/obj/item/stack/cable_coil = 15)
	time = 40
	category = CAT_MISC

/datum/crafting_recipe/fishing_line_sinew
	name = "Sinew Fishing Line"
	result = /obj/item/fishing_line/sinew
	reqs = list(/obj/item/stack/sheet/sinew = 3)
	time = 40
	category = CAT_PRIMAL

/datum/crafting_recipe/fish_plaque
	name = "Trophy Plaque"
	result = /obj/item/wallframe/fish_plaque
	reqs = list(/obj/item/stack/sheet/mineral/wood = 2)
	category = CAT_MISC

/datum/crafting_recipe/fishing_board
	name = "Angler's Record Board"
	result = /obj/item/wallframe/fishing_board
	reqs = list(/obj/item/stack/sheet/mineral/wood = 5)
	time = 40
	category = CAT_MISC

/datum/supply_pack/misc/fishing
	name = "Fishing Supplies Crate"
	desc = "Two telescopic fishing rods, a full tackle box, two trophy plaques and an angler's record board."
	cost = 1500
	contains = list(/obj/item/fishing_rod/telescopic,
					/obj/item/fishing_rod/telescopic,
					/obj/item/storage/fishing_tackle/full,
					/obj/item/wallframe/fish_plaque,
					/obj/item/wallframe/fish_plaque,
					/obj/item/wallframe/fishing_board)
	crate_name = "fishing supplies crate"

/datum/design/mech_fishing_rod
	name = "Exosuit Mining Equipment (Fishing Rod)"
	id = "mech_fishing_rod"
	build_type = MECHFAB
	build_path = /obj/item/mecha_parts/mecha_equipment/fishing_rod
	materials = list(MAT_METAL = 10000, MAT_GLASS = 2000, MAT_TITANIUM = 2000)
	construction_time = 100
	category = list("Exosuit Equipment")

/datum/techweb_node/mech_tools/New()
	. = ..()
	design_ids += "mech_fishing_rod"
