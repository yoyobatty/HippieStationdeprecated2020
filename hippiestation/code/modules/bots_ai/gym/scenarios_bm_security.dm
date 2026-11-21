// Bot gym scenarios from the 2026-11-21 bot audit, security area.
//
// What a scenario refers to that only the fix adds is reached by name (GLOB.vars["bot_cell_waiting"], case.vars["passed_over"]), so the
// "before" build of ab_gym.sh compiles and the scenario fails there on what the bots do, not on a missing symbol.

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

