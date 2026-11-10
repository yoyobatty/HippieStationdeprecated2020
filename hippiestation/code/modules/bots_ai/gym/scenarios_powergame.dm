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
