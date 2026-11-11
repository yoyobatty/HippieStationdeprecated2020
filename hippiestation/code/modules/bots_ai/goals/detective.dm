// The detective: goes to wherever somebody has died, runs the forensic scanner over the body, and calls it in.
//
// This is what makes a quiet murder risky. Security only reacts to what it sees (goals/security_patrol.dm), so a traitor
// who waits for an empty room (goals/traitor.dm) would otherwise get away with it every time. A scan turns up prints and
// blood often enough to name somebody, less often when they wore gloves, and a name goes in the records for an officer
// to pick up, the same as a witnessed crime.

#define BOT_DETECTIVE_REACH 90
/// Chance a scan names who did it, gloves or no gloves.
#define BOT_SCAN_NAMES_BARE_HANDS 70
#define BOT_SCAN_NAMES_GLOVED 30

/mob/living/carbon/human
	/// Real name of the last person to hurt this one, and whether they wore gloves. Set by bot_security_witness_combat().
	var/last_assailant
	var/last_assailant_gloved = FALSE
	/// When they last did it (world.time): somebody who dies of it later is that person's murder (bot_victim_died(), goals/security_patrol.dm)
	var/last_assailant_at = 0

/// Bodies a detective has been over, by REF: a case stays closed however long the body lies there.
GLOBAL_LIST_EMPTY(bot_closed_cases)

/datum/bot_brain/proc/find_uninvestigated_body()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat != DEAD || H == owner || !H.mind?.assigned_role || !isturf(H.loc) || H.z != owner.z || GLOB.bot_closed_cases[REF(H)])
			continue
		if(get_dist(owner, H) > BOT_DETECTIVE_REACH || (gym_run && get_area(H) != get_area(owner)))
			continue
		if(can_walk_lawfully_to(H))
			return H
	return null

/datum/bot_duty/detective
	name = "detective work"
	jobs = list("Detective")
	interval_min = 200
	interval_max = 600

/datum/bot_duty/detective/try_start(datum/bot_brain/bot)
	var/mob/living/carbon/human/body = bot.find_uninvestigated_body()
	return body ? bot.assign_goal(new /datum/bot_goal/investigate_body(body)) : FALSE

/datum/bot_goal/investigate_body
	lawful = TRUE
	exclusive = TRUE
	doing = "working a case"

/datum/bot_goal/investigate_body/New(mob/living/carbon/human/body)
	. = ..()
	target = body

/datum/bot_goal/investigate_body/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/investigate_body/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/investigate_body/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/scan_body())
	return list(S)

/datum/bot_goal/investigate_body/on_give_up(datum/bot_brain/bot)
	if(target)
		GLOB.bot_closed_cases[REF(target)] = TRUE //somewhere it can't get to, as it turns out

/datum/bot_strategy/investigate_body/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// A look over the body with the scanner, a moment's thought, and a call on the radio.
/datum/bot_step/paced/scan_body
	max_clicks = 3
	var/scanned = FALSE

/datum/bot_step/paced/scan_body/start(datum/bot_brain/bot)
	scanned = FALSE
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/scan_body/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/body = bot.current_goal?.target
	if(scanned || QDELETED(body) || !bot.owner.Adjacent(body))
		return FALSE
	var/obj/item/detective_scanner/scanner = bot.find_carried_tool(/obj/item/detective_scanner)
	if(scanner)
		bot.use_tool_on(scanner, body)
	else
		bot.human_pause(body) //no scanner: a look with the naked eye still counts for something
	scanned = TRUE
	wait_for = rand(20, 40)
	return TRUE

/datum/bot_step/paced/scan_body/finish(datum/bot_brain/bot)
	var/mob/living/carbon/human/body = bot.current_goal?.target
	if(QDELETED(body) || !scanned)
		return GOAL_STEP_FAIL
	GLOB.bot_closed_cases[REF(body)] = TRUE
	bot.report_case(body)
	return GOAL_STEP_SUCCESS

/// Calls in what the scan found, and names somebody if it named anybody.
/datum/bot_brain/proc/report_case(mob/living/carbon/human/body)
	var/where = get_area_name(body, TRUE)
	var/mob/living/carbon/human/suspect
	if(body.last_assailant && prob(body.last_assailant_gloved ? BOT_SCAN_NAMES_GLOVED : BOT_SCAN_NAMES_BARE_HANDS))
		for(var/mob/living/carbon/human/H in GLOB.carbon_list)
			if(H.real_name == body.last_assailant && H != body && H != owner)
				suspect = H
				break
	if(!suspect)
		bot_say(owner, ";[body.real_name] is dead in [where]. Nothing to go on yet.")
		return
	bot_log(src, "the scan on [body] points at [suspect]")
	file_murder(suspect, "Forensics put them on the body of [body.real_name] in [where].")
	bot_say(owner, ";Security, [body.real_name] was killed in [where]. Forensics say it was [suspect.real_name]. Pick them up.")

#undef BOT_DETECTIVE_REACH
#undef BOT_SCAN_NAMES_BARE_HANDS
#undef BOT_SCAN_NAMES_GLOVED
