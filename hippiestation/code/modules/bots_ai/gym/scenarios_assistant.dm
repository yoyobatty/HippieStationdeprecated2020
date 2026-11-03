// Assistants (goals/assistant.dm).

/datum/bot_scenario/assistant_rummage
	name = "assistant: goes through a maintenance locker and puts on the insulated gloves"
	desc = "A locker with insulated gloves, a crowbar and some rubbish in it. The assistant opens it, puts the gloves on, and leaves the rubbish."
	job = "Assistant"
	time_limit = 60 SECONDS
	layout = list(
		"#########",
		"#B.....k#",
		"#.......#",
		"#########")

/datum/bot_scenario/assistant_rummage/setup()
	for(var/turf/T in markers["k"])
		var/obj/structure/closet/C = new(T)
		new /obj/item/trash/chips(C)
		new /obj/item/clothing/gloves/color/yellow(C)
		new /obj/item/crowbar(C)
		place("k", C)

/datum/bot_scenario/assistant_rummage/make_goal()
	return new /datum/bot_goal/rummage(first_placed("k"))

/datum/bot_scenario/assistant_rummage/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(istype(bot.gloves, /obj/item/clothing/gloves/color/yellow))
		if(locate(/obj/item/trash/chips) in bot.GetAllContents())
			fail_reason = "it kept the rubbish"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING
