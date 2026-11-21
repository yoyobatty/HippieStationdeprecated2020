// Bot gym scenarios from the 2026-11-21 bot audit, perf area.

/datum/bot_scenario/glance_cap_on_a_pile
	name = "perf: a pile of hundreds of things in sight is taken in up to a cap, not all of it, at every glance"
	desc = "glance_at_items() (bot_knowledge.dm) noted every item in view once a second, ~2 us each: a crate's worth spawned on one tile in sight cost each bot that looked a millisecond or more a second. It takes in at most 300 now, the nearest first."
	time_limit = 20 SECONDS
	layout = list(
		"#########",
		"#B..p..G#",
		"#########")
	var/pile_made = FALSE

/datum/bot_scenario/glance_cap_on_a_pile/make_goal()
	return null //the scenario glances for it

/datum/bot_scenario/glance_cap_on_a_pile/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(pile_made)
		return BOT_GYM_PENDING
	pile_made = TRUE
	// after it arrived: what's laid out before that is the arena's "map" and isn't noted
	var/turf/where = first_marker("p")
	for(var/i in 1 to 1500)
		new /obj/item/paper(where)
	brain.seen_items = null
	brain.next_item_glance = 0
	var/started = TICK_USAGE_REAL
	brain.glance_at_items()
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	var/noted = length(brain.seen_items)
	var/most = ("bot_glance_most" in GLOB.vars) ? GLOB.vars["bot_glance_most"] : null //by name, so a build from before it was added still compiles
	log_line("one glance at 1500 papers on a tile in sight: [round(ms, 0.1)] ms, [noted] things noted, the most one glance has found in sight [most || "not counted"]")
	if(noted > 300)
		fail_reason = "one glance noted [noted] things from a pile of 1500, with no cap on what it takes in"
		return BOT_GYM_FAIL
	if(most != 301)
		fail_reason = "the cap wasn't reached by a pile of 1500 (the most in one glance: [most || "not counted"])"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/assailant_mark_let_go
	name = "perf: a monkey fed to a slime lets go of the bot when the bot is gibbed"
	desc = "A bot feeding slimes sets itself as the dropped monkey's LAssailant (goals/xenobiology.dm), a plain reference, and a bot gibbed while the monkey was still about was a hard delete (a 30-50 ms freeze). The brain takes itself back out of what it marked when it goes."
	time_limit = 20 SECONDS
	layout = list(
		"#######",
		"#B...G#",
		"#######")
	var/tested = FALSE

/datum/bot_scenario/assailant_mark_let_go/make_goal()
	return null //the scenario does the feeding and the gibbing

/datum/bot_scenario/assailant_mark_let_go/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(tested)
		return BOT_GYM_PENDING
	tested = TRUE
	var/mob/living/carbon/monkey/food = new(first_marker("G"))
	food.LAssailant = bot //what feed_slimes does with the monkey it drops in
	if(hascall(brain, "mark_as_assailant")) //by name, so a build from before it was added still compiles
		call(brain, "mark_as_assailant")(food)
	var/mob/living/carbon/human/body = bot
	qdel(body)
	if(food.LAssailant == body)
		fail_reason = "the monkey still has the gibbed bot as its LAssailant: that's a hard delete for the bot"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
