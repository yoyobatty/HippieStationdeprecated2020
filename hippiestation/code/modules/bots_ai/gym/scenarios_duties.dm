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
