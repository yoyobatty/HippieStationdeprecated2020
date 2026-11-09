// What a bot knows of where things are (bot_knowledge.dm): where things are kept, and what it has seen, but not what it hasn't.

/datum/bot_scenario/knows_kept_not_unseen
	name = "knowledge: after a screwdriver it goes where one's kept, not for a nearer one dropped out of sight"
	desc = "Bots used to know where every item on the station was. One dropped behind walls since the round began isn't something anybody knows of."
	time_limit = 30 SECONDS
	// the kept one near (arenas run side by side, and another's is a candidate too), the dropped one nearer, behind the wall
	layout = list(
		"#########",
		"#k...B..#",
		"#######.#",
		"#######.#",
		"#....q..#",
		"#########")
	var/obj/item/screwdriver/kept
	var/obj/item/screwdriver/dropped

/datum/bot_scenario/knows_kept_not_unseen/setup()
	kept = new(first_marker("k"))
	place("k", kept)

/datum/bot_scenario/knows_kept_not_unseen/make_goal()
	if(goal_attempts > 1)
		return null
	// dropped after the arena became the "map": nearer as the crow flies, behind the walls
	if(!dropped)
		dropped = new(first_marker("q"))
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	return get

/datum/bot_scenario/knows_kept_not_unseen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	if(dropped in carried)
		return BOT_GYM_FAIL
	return (kept in carried) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/knows_what_it_sees
	name = "knowledge: after a screwdriver it takes the nearer one it can see lying about"
	desc = "Something dropped since the round began is known to whoever sees it."
	time_limit = 20 SECONDS
	layout = list(
		"###############",
		"#k........q..B#",
		"###############")
	var/obj/item/screwdriver/kept
	var/obj/item/screwdriver/dropped

/datum/bot_scenario/knows_what_it_sees/setup()
	kept = new(first_marker("k"))
	place("k", kept)

/datum/bot_scenario/knows_what_it_sees/make_goal()
	if(goal_attempts > 1)
		return null
	if(!dropped)
		dropped = new(first_marker("q"))
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	return get

/datum/bot_scenario/knows_what_it_sees/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	if(kept in carried)
		return BOT_GYM_FAIL
	return (dropped in carried) ? BOT_GYM_PASS : BOT_GYM_PENDING

// Layout letter Y: a YouTool.
/datum/bot_scenario/knows_what_machines_sell
	name = "knowledge: with no screwdriver about, it buys one from the YouTool"
	desc = "Everybody knows what the vending machines sell. Nothing lying about and nothing in a locker isn't the end of it."
	job = "Assistant"
	time_limit = 30 SECONDS
	layout = list(
		"##########",
		"#B......Y#",
		"##########")

/datum/bot_scenario/knows_what_machines_sell/setup()
	for(var/turf/T in markers["Y"])
		place("Y", new /obj/machinery/vending/tool(T))

/datum/bot_scenario/knows_what_machines_sell/post_spawn()
	give_job_id()

/datum/bot_scenario/knows_what_machines_sell/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/knows_what_machines_sell/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/screwdriver) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/knows_what_machines_sell/sold_out
	name = "knowledge: a YouTool it found sold out, it doesn't go back to"
	desc = "What a machine has left is found out at the machine. Sold out of screwdrivers, it goes for the one kept further off, and doesn't walk back to the machine for another look."
	time_limit = 40 SECONDS
	layout = list(
		"#############",
		"#k........BY#",
		"#############")
	var/obj/item/screwdriver/kept

/datum/bot_scenario/knows_what_machines_sell/sold_out/setup()
	. = ..()
	var/obj/machinery/vending/V = locate() in first_marker("Y")
	for(var/datum/data/vending_product/R in V.product_records)
		if(R.product_path == /obj/item/screwdriver)
			R.amount = 0
	kept = new(first_marker("k"))
	place("k", kept)

/datum/bot_scenario/knows_what_machines_sell/sold_out/make_goal()
	if(goal_attempts > 2)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/knows_what_machines_sell/sold_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!(kept in bot.GetAllContents()))
		return BOT_GYM_PENDING
	if(!length(brain.sold_out_seen))
		fail_reason = "went for the kept one without trying the machine beside it"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
