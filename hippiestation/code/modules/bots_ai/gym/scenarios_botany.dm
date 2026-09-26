// Bot Gym scenarios for the Botanist (goals/tend_hydroponics.dm). No scripted goal: the bot has
// to notice what the bay needs through its own botany round, like it would on the station.
//
// Extra legend for these layouts:
//  H hydroponics tray   K water tank   u bucket   N NutriMax   M MegaSeed Servitor
//  Z seed extractor     R smartfridge   Q plant DNA manipulator

/datum/bot_scenario/botany
	job = "Botanist"
	time_limit = 90 SECONDS

/datum/bot_scenario/botany/build_tile(turf/T, char)
	switch(char)
		if("H")
			place(char, new /obj/machinery/hydroponics(T))
		if("K")
			place(char, new /obj/structure/reagent_dispensers/watertank/high(T)) //what Hydroponics has on the station
		if("u")
			place(char, new /obj/item/reagent_containers/glass/bucket(T))
		if("N")
			place(char, new /obj/machinery/vending/hydronutrients(T))
		if("M")
			place(char, new /obj/machinery/vending/hydroseeds(T))
		if("Z")
			place(char, new /obj/machinery/seed_extractor(T))
		if("R")
			place(char, new /obj/machinery/smartfridge(T))
		if("Q")
			place(char, new /obj/machinery/plantgenes(T))
		else
			return ..()

/// A botanist's ID with a Botanist bank account - the NutriMax and MegaSeed only vend to a card,
/// and are free for the service department.
/datum/bot_scenario/botany/post_spawn()
	var/obj/item/card/id/C = new(bot)
	C.registered_name = bot.real_name
	C.assignment = "Botanist"
	C.access = list(ACCESS_HYDROPONICS)
	C.registered_account = new /datum/bank_account(bot.real_name, SSjob.GetJob("Botanist"))
	C.registered_account.adjust_money(500) //a few paychecks in, like a real botanist
	bot.equip_to_slot_or_del(C, ITEM_SLOT_ID)
	bot.equip_to_slot_or_del(new /obj/item/clothing/gloves/botanic_leather(bot), ITEM_SLOT_GLOVES)

/datum/bot_scenario/botany/issue_goal()
	if(world.time < brain.next_botany_check_time || brain.goal_chain_pending)
		return //waiting out a give-up, or the round is already moving on to its next goal - as handle_wander() would
	goal_attempts++
	if(brain.try_botany_round())
		log_line("botany round picked up work (attempt [goal_attempts]/[max_goal_attempts])")

/// Puts a growing plant of seed_type in H with the given levels.
/datum/bot_scenario/botany/proc/plant(obj/machinery/hydroponics/H, seed_type, water = 100, nutri = 10)
	H.myseed = new seed_type(H)
	H.age = 1
	H.dead = FALSE
	H.plant_health = H.myseed.endurance
	H.lastcycle = world.time
	H.waterlevel = water
	H.nutrilevel = nutri
	H.update_icon()

/datum/bot_scenario/botany/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(istype(bot.head, /obj/item/reagent_containers/glass/bucket))
		fail_reason = "put the bucket on its head"
		return BOT_GYM_FAIL
	return botany_check()

/datum/bot_scenario/botany/proc/botany_check()
	return BOT_GYM_PENDING

/datum/bot_scenario/botany/water_tray
	name = "botanist waters a thirsty tray"
	desc = "A wheat plant almost out of water. Pick up the bucket, fill it at the water tank a scoop at a time, pour it on the tray - and don't wear the bucket."
	layout = list(
		"##########",
		"#B.u.H.K.#",
		"#........#",
		"##########")

/datum/bot_scenario/botany/water_tray/setup()
	plant(first_placed("H"), /obj/item/seeds/wheat, water = 5)

/datum/bot_scenario/botany/water_tray/botany_check()
	var/obj/machinery/hydroponics/H = first_placed("H")
	return H.waterlevel >= 60 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/botany/plant_empty_bay
	name = "botanist plants an empty bay"
	desc = "Three empty trays and a MegaSeed Servitor. Buy a few different packets in one trip and plant all three, not the same crop everywhere."
	layout = list(
		"###########",
		"#B.......M#",
		"#.H.H.H...#",
		"###########")

/datum/bot_scenario/botany/plant_empty_bay/botany_check()
	var/list/crops = list()
	for(var/obj/machinery/hydroponics/H in placed["H"])
		if(!H.myseed)
			return BOT_GYM_PENDING
		crops[H.myseed.plantname] = TRUE
	if(length(crops) < 2)
		fail_reason = "planted the same crop in every tray"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/botany/weeds_and_pests
	name = "botanist weeds and sprays a tray"
	desc = "Weeds and pests at 6 each. Get a cultivator and pest spray from the NutriMax, uproot the weeds and spray until the pests are gone."
	layout = list(
		"##########",
		"#B...H..N#",
		"#........#",
		"##########")

/datum/bot_scenario/botany/weeds_and_pests/setup()
	var/obj/machinery/hydroponics/H = first_placed("H")
	plant(H, /obj/item/seeds/wheat)
	H.weedlevel = 6
	H.pestlevel = 6

/datum/bot_scenario/botany/weeds_and_pests/botany_check()
	var/obj/machinery/hydroponics/H = first_placed("H")
	return (H.weedlevel == 0 && H.pestlevel < 2) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/botany/feed_tray
	name = "botanist feeds a starving tray"
	desc = "A plant with no nutrients left. Buy Robust Harvest (not E-Z-Nutrient or Left 4 Zed) from the NutriMax and pour it in."
	layout = list(
		"##########",
		"#B...H..N#",
		"#........#",
		"##########")

/datum/bot_scenario/botany/feed_tray/setup()
	plant(first_placed("H"), /obj/item/seeds/wheat, nutri = 0)

/datum/bot_scenario/botany/feed_tray/botany_check()
	var/obj/machinery/hydroponics/H = first_placed("H")
	if(H.nutrilevel < 5)
		return BOT_GYM_PENDING
	if(H.yieldmod != 1.3)
		fail_reason = "fed it [H.mutmod == 2 ? "Left 4 Zed" : "E-Z-Nutrient"] instead of Robust Harvest"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/botany/harvest_replant_stock
	name = "botanist harvests, replants and stocks the fridge"
	desc = "Ripe wheat. Get a plant bag, harvest into it, put a piece through the seed extractor, replant the tray with the seeds, and put the rest in the smartfridge."
	layout = list(
		"###########",
		"#B...N..Z.#",
		"#..H....R.#",
		"###########")
	time_limit = 120 SECONDS

/datum/bot_scenario/botany/harvest_replant_stock/setup()
	var/obj/machinery/hydroponics/H = first_placed("H")
	plant(H, /obj/item/seeds/wheat)
	H.age = 10
	H.harvest = TRUE
	H.update_icon()

/datum/bot_scenario/botany/harvest_replant_stock/botany_check()
	var/obj/machinery/hydroponics/H = first_placed("H")
	var/obj/machinery/smartfridge/F = first_placed("R")
	if(locate(/obj/item/seeds) in F)
		fail_reason = "put its seed packets in the fridge along with the produce"
		return BOT_GYM_FAIL
	if(!H.myseed || H.harvest || !(locate(/obj/item/reagent_containers/food/snacks/grown) in F))
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

/datum/bot_scenario/botany/flush_toxic_tray
	name = "botanist flushes a toxic tray"
	desc = "Toxicity at 50 in a tray already full of water. Overwater it - several buckets, refilling at the tank in between - until the toxin is down."
	layout = list(
		"##########",
		"#B.u.H.K.#",
		"#........#",
		"##########")

/datum/bot_scenario/botany/flush_toxic_tray/setup()
	var/obj/machinery/hydroponics/H = first_placed("H")
	plant(H, /obj/item/seeds/wheat)
	H.toxic = 50

/datum/bot_scenario/botany/flush_toxic_tray/botany_check()
	var/obj/machinery/hydroponics/H = first_placed("H")
	return H.toxic < 20 ? BOT_GYM_PASS : BOT_GYM_PENDING
