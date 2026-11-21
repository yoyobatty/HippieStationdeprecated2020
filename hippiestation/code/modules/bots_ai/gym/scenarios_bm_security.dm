// Bot gym scenarios from the 2026-11-21 bot audit, security area.
//
// What a scenario refers to that only the fix adds is reached by name (GLOB.vars["bot_cell_waiting"], case.vars["passed_over"]), so the
// "before" build of ab_gym.sh compiles and the scenario fails there on what the bots do, not on a missing symbol.

/// The Warden gets to the cell for a lifer with nothing to cuff them with: it says so and the case goes to the next officer, instead of the
/// same duty sending it back every few seconds for the rest of the shift.
/datum/bot_scenario/brigged/perma_collect/no_cuffs
	name = "brig: a Warden with no cuffs who can't take a lifer out of the cell passes the case on"
	desc = "Shift batch play1114b: collect_prisoner ran 88, 71, 55 and 47 times a shift for one capital prisoner, the Warden walking to the cell, starting nothing and wandering off, and one lifer waited fourteen minutes for another officer to happen by. When the arrest doesn't start the officer notes why and hands the case on."
	kit_backpack = list()
	time_limit = 30 SECONDS

/datum/bot_scenario/brigged/perma_collect/no_cuffs/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/passed = case.vars["passed_over"]
	if(length(passed))
		return BOT_GYM_PASS
	fail_reason = "went to the cell and started nothing, and didn't hand the case on"
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Lethal force: armed isn't dangerous until they use it
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal
	name = "security: an officer doesn't go lethal on a vandal with a fire axe who hasn't hurt anybody"
	desc = "Shift batches play1114b run12 and gen1116f run11: an officer went \"lethal, armed and dangerous\" on an assistant and a chemist arrested for vandalism, who were holding the fire axe they were smashing windows with, and put seven and eleven laser shots into them. Greytiders are never killed (the user's ruling): armed only counts once they've hurt somebody or come at the officer. The officer has a laser and a taser; it never says it's going lethal."
	time_limit = 16 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded, /obj/item/gun/energy/laser, /obj/item/gun/energy/e_gun/advtaser)
	layout = list(
		"###############",
		"#B...........C#",
		"#.............#",
		"###############")
	var/obj/item/twohanded/fireaxe/axe
	/// The control: this one's laid into somebody a moment ago
	var/hurt_somebody = FALSE

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal/grief()
	GLOB.security_level = SEC_LEVEL_GREEN //a red alert left up by a scenario before this one makes lethal force fair for anybody
	axe = griefer_holds(/obj/item/twohanded/fireaxe)
	officers = list(bot)
	make_griefer_wanted("Major Vandalism", BOT_CRIME_MAJOR)
	if(hurt_somebody)
		var/mob/living/carbon/human/victim = stand_in(get_step(bot, SOUTH), "Vic Victim") //beside the officer, off the line of fire
		GLOB.bot_recent_aggression["[REF(griefer)]>[REF(victim)]"] = world.time
	brain.begin_arrest(griefer)

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/lethal = bot_transcript_said("Going lethal on")
	if(hurt_somebody)
		if(lethal)
			return BOT_GYM_PASS
		fail_reason = "didn't go lethal on somebody armed with a fire axe who's just hit somebody"
		return BOT_GYM_PENDING
	if(lethal)
		fail_reason = "went lethal on a vandal who hadn't hurt anybody"
		return BOT_GYM_FAIL
	return world.time > start_time + 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal/hit_somebody
	name = "security: an officer does go lethal on somebody with a fire axe who's just laid into somebody"
	desc = "The control for the vandal: the same fire axe, and they've hit somebody in the last half minute."
	hurt_somebody = TRUE

// ---------------------------------------------------------------------------------------------
// A call for help
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/security_call_cap
	name = "security: a call for help draws two officers, not the whole of Security"
	desc = "Shift batches play1114b and gen1116f: two calls in three took four or more officers off their posts at once (all five or six on a third of them), for a flickering light or a locked door. Four officers hear somebody ask Security to come and look at something: two go, the others carry on. A call that says somebody's being attacked draws three (the next scenario)."
	job = "Security Officer"
	layout = list(
		"###########",
		"#BONM..C..#",
		"###########")
	time_limit = 10 SECONDS
	var/list/mob/living/carbon/human/others = list()
	var/mob/living/carbon/human/visitor
	var/called_at = 0
	/// What the visitor says, and how many officers it takes
	var/the_call = "Security, can somebody come and look at the light in here?"
	var/officers_wanted = 2

/datum/bot_scenario/security_call_cap/issue_goal()
	return

/datum/bot_scenario/security_call_cap/post_spawn()
	brain.register_security()
	for(var/mark in list("O", "N", "M"))
		var/mob/living/carbon/human/H = second_bot(first_marker(mark), "Officer [mark]")
		H.mind.assigned_role = "Security Officer"
		H.bot_brain.register_security()
		others += H
	visitor = stand_in(first_marker("C"), "Cal Caller")
	addtimer(CALLBACK(src, PROC_REF(call_it)), 2 SECONDS)

/datum/bot_scenario/security_call_cap/proc/call_it()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	called_at = world.time
	log_line("visitor: \"[the_call]\"")
	visitor.say(the_call)

/// Officers who took the call: a taken call sets next_security_call_time a minute ahead, in every build.
/datum/bot_scenario/security_call_cap/proc/answering()
	. = 0
	var/list/brains = list(brain)
	for(var/mob/living/carbon/human/H in others)
		brains += H.bot_brain
	for(var/datum/bot_brain/B as anything in brains)
		if(B.next_security_call_time > world.time)
			.++

/datum/bot_scenario/security_call_cap/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!called_at || world.time < called_at + 4 SECONDS)
		return BOT_GYM_PENDING
	var/n = answering()
	if(n == officers_wanted)
		return BOT_GYM_PASS
	fail_reason = "[n] of the four officers took the call, not [officers_wanted]"
	return BOT_GYM_FAIL

/datum/bot_scenario/security_call_cap/danger
	name = "security: a call that says somebody's being attacked draws three officers"
	desc = "The same four officers, and the visitor cries that somebody's attacking them: three go. (A cap of two for everything would leave a fight short.)"
	the_call = "Security! Somebody is attacking me in here!"
	officers_wanted = 3
