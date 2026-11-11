// Bot Gym scenarios for duties (bot_duties.dm). The bot is handed nothing: the duty itself has to
// notice the work and start on it, the way it would in a round. Each duty's own scenarios follow the
// base type below.

/// A scenario whose bot is driven by one duty rather than a scripted goal.
/datum/bot_scenario/duty
	/// The /datum/bot_duty this run is about. It's asked once a second while the bot is idle, switched on or not.
	var/duty_type
	max_goal_attempts = 10

/datum/bot_scenario/duty/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(duty_type)
	if(!D)
		log_line("no such duty: [duty_type]")
		return
	if(D.try_start(brain))
		goal_attempts++
		log_line("[D.name]: started on [brain.current_goal ? brain.current_goal.type : "it"] (attempt [goal_attempts]/[max_goal_attempts])")

/// An ID for the bot's job with a bank account behind it - vending machines only sell to a card, and a department's
/// own machines are free to its staff.
/datum/bot_scenario/proc/give_job_id(list/access)
	var/obj/item/card/id/C = new(bot)
	C.registered_name = bot.real_name
	C.assignment = job
	C.access = access || list()
	C.registered_account = new /datum/bank_account(bot.real_name, SSjob.GetJob(job))
	C.registered_account.adjust_money(500) //a few paychecks in
	bot.equip_to_slot_or_del(C, ITEM_SLOT_ID)
	return C

/// Dead, or not: the first thing every check() asks.
/datum/bot_scenario/proc/bot_lost()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return TRUE
	return FALSE

/// The user's ruling after their Captain round (2026-11-10), where twenty were killed one at a time: once people are dying, the crew hide
/// or group up (goals/massacre.dm).
/datum/bot_scenario/duty/group_up
	name = "panic: three dead and the killer about, it goes and sticks with the others"
	desc = "Three bodies, all last hurt by the man standing over them. Two of the crew are at the far end of the room. The bot goes over to them and stays there."
	job = "Assistant"
	layout = list(
		"##############",
		"#B.K123....yz#",
		"##############")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/crew

/datum/bot_scenario/duty/group_up/setup()
	duty_type = text2path("/datum/bot_duty/group_up") // by name: a build without the fix has no such duty

/datum/bot_scenario/duty/group_up/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_NORMAL)
	brain.hardened = FALSE
	var/mob/living/carbon/human/killer = stand_in(first_marker("K"), "Max Killer")
	killer.mind_initialize()
	killer.mind.assigned_role = "Captain"
	for(var/n in 1 to 3)
		var/mob/living/carbon/human/body = stand_in(first_marker("[n]"), "Body [n]")
		body.mind_initialize()
		body.mind.assigned_role = "Assistant"
		body.last_assailant = killer.real_name
		body.death()
	for(var/c in list("y", "z"))
		var/mob/living/carbon/human/H = stand_in(first_marker(c), "Crew [c]")
		H.mind_initialize()
		H.mind.assigned_role = "Assistant"
		crew = crew || H
	if("bot_body_counts_at" in GLOB.vars)
		GLOB.vars["bot_body_counts_at"] = 0

/datum/bot_scenario/duty/group_up/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (get_dist(bot, crew) <= 4 && bot_transcript_said("with the others")) ? BOT_GYM_PASS : BOT_GYM_PENDING
