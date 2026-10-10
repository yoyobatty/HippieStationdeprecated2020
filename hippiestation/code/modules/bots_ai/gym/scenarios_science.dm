// Bot Gym scenarios for Science (goals/science.dm).
//
// Layout letters used here: C an R&D console.

/datum/bot_scenario/duty/science
	duty_type = /datum/bot_duty/research
	job = "Scientist"
	time_limit = 60 SECONDS

/datum/bot_scenario/duty/science/setup()
	for(var/turf/T in markers["C"])
		place("C", new /obj/machinery/computer/rdconsole/core(T))
	// The station's servers have barely started: enough in the bank for a couple of first-tier nodes.
	SSresearch.science_tech.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = 6000))

/datum/bot_scenario/duty/science/research
	name = "scientist unlocks research at the console"
	desc = "Points in the bank and an R&D console down the corridor. The scientist walks over and unlocks what the department can afford, one node per click - not from across the room."
	layout = list(
		"#########",
		"#B.....C#",
		"#########")

/datum/bot_scenario/duty/science/research/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (brain.nodes_researched && brain.state == BOT_STATE_WANDER) ? BOT_GYM_PASS : BOT_GYM_PENDING
