// Department gear pass: the new researchable items. Their nodes are in code/modules/research/techweb/all_nodes.dm.

/datum/design/blast_calculator
	name = "Blast Yield Calculator"
	desc = "Simulates the gas in a tank transfer valve, one-tank bomb or gas tank to predict its blast."
	id = "blast_calculator"
	build_type = PROTOLATHE
	materials = list(MAT_METAL = 500, MAT_GLASS = 500, MAT_PLASMA = 200)
	build_path = /obj/item/blast_calculator
	category = list("Equipment")
	departmental_flags = DEPARTMENTAL_FLAG_SCIENCE

/datum/design/scrubber_pack
	name = "Backpack Air Scrubber"
	desc = "A worn scrubber that filters toxic gases out of the air around its wearer into an internal tank."
	id = "scrubber_pack"
	build_type = PROTOLATHE
	materials = list(MAT_METAL = 4000, MAT_GLASS = 1000, MAT_SILVER = 500)
	build_path = /obj/item/scrubber_pack
	category = list("Equipment")
	departmental_flags = DEPARTMENTAL_FLAG_ENGINEERING

/datum/design/plant_hud
	name = "Botanical HUD"
	desc = "A heads-up display that shows the state of every hydroponics tray in view."
	id = "plant_hud"
	build_type = PROTOLATHE
	materials = list(MAT_METAL = 500, MAT_GLASS = 500)
	build_path = /obj/item/clothing/glasses/hud/botany
	category = list("Equipment")
	departmental_flags = DEPARTMENTAL_FLAG_SERVICE | DEPARTMENTAL_FLAG_SCIENCE
