// Bot Gym scenarios for powergaming (goals/powergame.dm).

/// A DNA scanner at `scanner_at` and its console at `console_at` (side by side), with a gene stored on the console.
/datum/bot_scenario/proc/build_genetics(turf/scanner_at, turf/console_at, stored_type)
	var/obj/machinery/dna_scannernew/S = new(scanner_at)
	var/obj/machinery/computer/scan_consolenew/C = new(console_at)
	if(!C.connected)
		C.connected = S
	C.stored_mutations += new stored_type()
	place("s", S)
	place("k", C)
	return C

/datum/bot_scenario/powergame_mutator
	name = "powergame: prints itself a mutator at Genetics and injects it"
	desc = "A powergamer with the run of Genetics. The console has Strength stored. It prints a mutator off it and injects it."
	job = "Assistant"
	layout = list(
		"#########",
		"#B....sk#",
		"#.......#",
		"#########")
	time_limit = 60 SECONDS

/datum/bot_scenario/powergame_mutator/setup()
	build_genetics(first_marker("s"), first_marker("k"), /datum/mutation/human/strong)

/datum/bot_scenario/powergame_mutator/post_spawn()
	brain.set_playstyle(BOT_STYLE_POWERGAMER)

/datum/bot_scenario/powergame_mutator/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/power_ladder"))
	if(!D)
		log_line("there's no such duty")
	else
		LAZYSET(brain.power_rests, "access", world.time + 1 HOURS) //this one's about the powers
		if(!D.try_start(brain))
			log_line("the duty didn't start")
	return null

/datum/bot_scenario/powergame_mutator/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.dna?.get_mutation(/datum/mutation/human/strong))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/powergame_access
	name = "powergame: asks the HoP for more access"
	desc = "A powergamer whose card opens next to nothing puts it down for the HoP and asks for maintenance and the departments with the good stuff in them."
	job = "Assistant"
	layout = list(
		"#######",
		"#B....#",
		"#######")
	time_limit = 20 SECONDS

/datum/bot_scenario/powergame_access/post_spawn()
	brain.set_playstyle(BOT_STYLE_POWERGAMER)
	give_job_id(list(ACCESS_MAINT_TUNNELS))

/datum/bot_scenario/powergame_access/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/power_ladder"))
	if(!D)
		log_line("there's no such duty")
	else if(!D.try_start(brain))
		log_line("the duty didn't start")
	return null

/datum/bot_scenario/powergame_access/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/card/id/card = locate() in get_turf(bot)
	if(!card)
		for(var/obj/item/card/id/C in range(1, bot))
			if(isturf(C.loc))
				card = C
	if(!card)
		return BOT_GYM_PENDING
	for(var/line in transcript)
		if(findtext(line, "research") && findtext(line, "access"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/powergame_geneticist
	name = "powergame: the Geneticist brings over a mutator somebody asked for"
	desc = "Somebody asks Genetics on the radio for a power. The Geneticist prints a mutator off a gene stored on its console and puts it down at their feet."
	job = "Geneticist"
	layout = list(
		"##########",
		"#B..sk...#",
		"#.......C#",
		"##########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/visitor

/datum/bot_scenario/powergame_geneticist/setup()
	build_genetics(first_marker("s"), first_marker("k"), /datum/mutation/human/strong)

/datum/bot_scenario/powergame_geneticist/post_spawn()
	visitor = stand_in(first_marker("C"), "Casey Visitor")
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/powergame_geneticist/make_goal()
	return null

/datum/bot_scenario/powergame_geneticist/proc/ask()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	var/kind_type = text2path("/datum/bot_request_kind/genes")
	var/datum/bot_request_kind/kind = kind_type ? (locate(kind_type) in GLOB.bot_request_kinds) : null
	if(!kind)
		log_line("there's no such request")
		return
	log_line("visitor (over the radio): \"Genetics, could I get a Strength mutator?\"")
	var/datum/bot_request/R = bot_new_request(kind, visitor, null, visitor)
	bot_offer_request(R)

/datum/bot_scenario/powergame_geneticist/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/dnainjector/activator/I in range(1, visitor))
		if(isturf(I.loc) && bot_injector_gives(I, visitor))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/powergame_chemist
	name = "powergame: a chemist brings heal pills to whoever asked"
	desc = "Somebody asks Chemistry on the radio for tricord. The chemist has three tricordrazine pills on it, takes one over and puts it down at their feet."
	job = "Chemist"
	layout = list(
		"##########",
		"#B.......#",
		"#.......C#",
		"##########")
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/visitor

/datum/bot_scenario/powergame_chemist/post_spawn()
	for(var/i in 1 to 3)
		var/obj/item/reagent_containers/pill/P = new(bot)
		P.name = "tricordrazine pill"
		P.reagents.add_reagent(/datum/reagent/medicine/tricordrazine, 15)
		bot.equip_to_slot_or_del(P, ITEM_SLOT_BACKPACK)
	visitor = stand_in(first_marker("C"), "Casey Visitor")
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/powergame_chemist/make_goal()
	return null

/datum/bot_scenario/powergame_chemist/proc/ask()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	var/kind_type = text2path("/datum/bot_request_kind/heal_chems")
	var/datum/bot_request_kind/kind = kind_type ? (locate(kind_type) in GLOB.bot_request_kinds) : null
	if(!kind)
		log_line("there's no such request")
		return
	log_line("visitor (over the radio): \"Chemistry, could I get a couple of tricord pills?\"")
	bot_offer_request(bot_new_request(kind, visitor, null, visitor))

/datum/bot_scenario/powergame_chemist/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/reagent_containers/pill/P in range(1, visitor))
		if(isturf(P.loc) && P.reagents.has_reagent(/datum/reagent/medicine/tricordrazine))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/powergame_virus
	name = "powergame: a virologist brews itself a healing virus and drinks it"
	desc = "A powergamer Virologist, the virus fridge (f) with its flu and plasma, and the PanDEMIC (p). It works the flu up a drop of plasma at a time until the virus heals and does nothing worse than a cough, and takes a gulp. If the plasma runs out first it leaves it: that's a pass too, as long as it never drank a bad one."
	job = "Virologist"
	time_limit = 150 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large)
	layout = list(
		"##############",
		"#B..f..p.....#",
		"#............#",
		"##############")

/datum/bot_scenario/powergame_virus/build_tile(turf/T, char)
	switch(char)
		if("f")
			place(char, new /obj/machinery/smartfridge/chemistry/virology/preloaded(T))
		if("p")
			place(char, new /obj/machinery/computer/pandemic(T))
		else
			return ..()

/datum/bot_scenario/powergame_virus/post_spawn()
	brain.set_playstyle(BOT_STYLE_POWERGAMER)

/datum/bot_scenario/powergame_virus/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/power_ladder"))
	if(!D)
		log_line("there's no such duty")
		return null
	for(var/rung in list("access", "genes", "heals", "gun"))
		LAZYSET(brain.power_rests, rung, world.time + 1 HOURS) //this one's about the virus
	if(!D.try_start(brain))
		log_line("the duty didn't start")
	return null

/datum/bot_scenario/powergame_virus/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/datum/disease/advance/D in bot.diseases)
		if(!bot_virus_good(D))
			fail_reason = "drank a virus that isn't all good: [bot_virus_symptoms(D)]"
			return BOT_GYM_FAIL
		log_line("infected with [bot_virus_symptoms(D)]")
		return BOT_GYM_PASS
	for(var/line in transcript)
		if(findtext(line, "no good to me"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/self_heal_patch
	name = "self-heal: one patch, and a wait for it to work"
	desc = "Hurt with three brute patches in its bag. It puts one on and lets it work, rather than three in a row and a give-up because it wasn't better the moment after each."
	job = "Assistant"
	layout = list(
		"#######",
		"#B....#",
		"#######")
	time_limit = 25 SECONDS

/datum/bot_scenario/self_heal_patch/post_spawn()
	for(var/i in 1 to 3)
		bot.equip_to_slot_or_del(new /obj/item/reagent_containers/pill/patch/styptic(bot), ITEM_SLOT_BACKPACK)
	bot.adjustBruteLoss(40)

/datum/bot_scenario/self_heal_patch/make_goal()
	if(goal_attempts > 1)
		return null
	if(!brain.try_self_heal_round())
		log_line("didn't start healing")
	return null

/datum/bot_scenario/self_heal_patch/proc/patches_left()
	. = 0
	for(var/obj/item/reagent_containers/pill/patch/styptic/P in bot.GetAllContents())
		.++

/datum/bot_scenario/self_heal_patch/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(patches_left() < 2)
		fail_reason = "used [3 - patches_left()] patches"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/self_heal_patch/on_timeout()
	if(patches_left() == 2)
		return BOT_GYM_PASS
	fail_reason = "used [3 - patches_left()] patches"
	return BOT_GYM_FAIL

/datum/bot_scenario/powergame_laser_eyes
	name = "powergame: laser eyes at somebody across the room"
	desc = "A bot with the laser eyes mutation and no gun is attacked from across the room. It fires its eyes at them rather than only running in to punch."
	job = "Assistant"
	layout = list(
		"##########",
		"#B.....C.#",
		"##########")
	time_limit = 15 SECONDS
	var/mob/living/carbon/human/foe

/datum/bot_scenario/powergame_laser_eyes/post_spawn()
	bot.dna.add_mutation(/datum/mutation/human/laser_eyes, MUT_EXTRA)
	foe = stand_in(first_marker("C"), "Casey Assailant")
	brain.on_attacked(foe, "shot", null)

/datum/bot_scenario/powergame_laser_eyes/make_goal()
	return null

/datum/bot_scenario/powergame_laser_eyes/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (!QDELETED(foe) && foe.getFireLoss() > 0) ? BOT_GYM_PASS : BOT_GYM_PENDING
