// Traitor objectives past killing and stealing (goals/traitor_objectives.dm). Letters: h a protolathe, C an R&D console.

/datum/bot_scenario/duty/traitor/download
	name = "traitor: prints a technology disk and copies the station's research onto it"
	desc = "A download objective, a protolathe with materials in it, and an R&D console. The traitor prints a disk, puts it in the console, loads the research onto it, and takes it away in its bag."
	time_limit = 120 SECONDS
	layout = list(
		"##########",
		"#B.h.C...#",
		"#........#",
		"##########")
	var/datum/objective/download/objective

/datum/bot_scenario/duty/traitor/download/setup()
	for(var/turf/T in markers["h"])
		var/obj/machinery/rnd/production/protolathe/L = place("h", new /obj/machinery/rnd/production/protolathe(T))
		L.materials?.mat_container?.insert_amount(MINERAL_MATERIAL_AMOUNT * 2, MAT_METAL)
		L.materials?.mat_container?.insert_amount(MINERAL_MATERIAL_AMOUNT * 2, MAT_GLASS)
	for(var/turf/T in markers["C"])
		var/obj/machinery/computer/rdconsole/core/C = place("C", new /obj/machinery/computer/rdconsole/core(T))
		C.SyncRDevices()
	//more than a fresh disk comes with, so only a copy passes
	SSresearch.science_tech.research_node_id("engineering", TRUE, FALSE)
	SSresearch.science_tech.research_node_id("biotech", TRUE, FALSE)

/datum/bot_scenario/duty/traitor/download/post_spawn()
	..()
	objective = new
	objective.owner = bot.mind
	objective.target_amount = 999 //never met, so it keeps at it
	objective.update_explanation_text()
	antag.objectives += objective

/datum/bot_scenario/duty/traitor/download/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/disk/tech_disk/disk = locate() in bot.GetAllContents()
	if(disk && (disk in bot.held_items))
		return BOT_GYM_PENDING //still putting it away
	if(disk && length(disk.stored_research.researched_nodes) >= length(SSresearch.science_tech.researched_nodes))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING
