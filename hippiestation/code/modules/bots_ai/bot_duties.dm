// Duties - what a bot finds to do by itself between goals, one /datum/bot_duty each.
//
// The department rounds in handle_wander() (bot_brain.dm) are a hand-written ladder: medical, the
// engine, the air loop, the trays... Everything added since lives here instead, so a new job or habit
// is one file: a duty that says whose it is and how often to look, and a try_start() that hands the
// bot a goal when there is something to do.
//
// handle_wander() asks for them in three places:
//   BOT_DUTY_URGENT   ahead of the rounds - the shuttle is about to leave, the room is on fire
//   BOT_DUTY_WORK     after the rounds - the day job (mop the hall, cook, run the bar)
//   BOT_DUTY_LEISURE  only when about to stroll off somewhere anyway - a smoke, the arcade, a drink
//
// A duty that hasn't passed its Bot Gym scenarios ships with enabled = FALSE: it compiles and the gym
// can still run it by type (gym/scenarios_duties.dm), but no bot picks it up in a round.

/// Every duty there is, the most pressing first.
GLOBAL_LIST_INIT(bot_duties, init_bot_duties())

/proc/init_bot_duties()
	var/list/sorted = list()
	for(var/path in subtypesof(/datum/bot_duty))
		var/datum/bot_duty/D = new path
		if(!D.name)
			continue //a parent type that only groups others
		var/at = 1
		for(var/datum/bot_duty/other as anything in sorted)
			if(other.priority < D.priority)
				break
			at++
		sorted.Insert(at, D)
	return sorted

/proc/bot_duty_of(duty_type)
	for(var/datum/bot_duty/D as anything in GLOB.bot_duties)
		if(D.type == duty_type)
			return D
	return null

/datum/bot_duty
	var/name
	var/tier = BOT_DUTY_WORK
	/// Job titles this is for. null is everyone.
	var/list/jobs
	/// How often a bot looks for this, in deciseconds - somewhere between the two each time.
	var/interval_min = 50
	var/interval_max = 150
	/// Higher is asked first.
	var/priority = 0
	var/enabled = TRUE
	/// Asked even while the bot is on an errand, which it drops if should_interrupt() says so.
	var/interrupts = FALSE

/datum/bot_duty/proc/applies_to(datum/bot_brain/bot)
	return !jobs || (bot.owner.mind?.assigned_role in jobs)

/// Finds the bot something to do. TRUE if it is now busy with it.
/datum/bot_duty/proc/try_start(datum/bot_brain/bot)
	return FALSE

/// Whether this is worth dropping the errand in hand for, right now. Only asked of duties with `interrupts`.
/datum/bot_duty/proc/should_interrupt(datum/bot_brain/bot)
	return FALSE

/// Whether a bot this duty has waiting somewhere (bot_brain.holding_duty) should carry on waiting. Asked every tick.
/datum/bot_duty/proc/keep_holding(datum/bot_brain/bot)
	return FALSE

/// How long before this bot looks again. A slacker gets round to its work less often than a keen one.
/datum/bot_duty/proc/next_look(datum/bot_brain/bot)
	. = rand(interval_min, interval_max)
	if(tier == BOT_DUTY_WORK)
		. *= 1.6 - bot.diligence

/datum/bot_brain
	/// This bot's duties by tier (BOT_DUTY_*), worked out the first time they're wanted - a job never changes.
	var/list/duties
	/// Duty -> world.time it's next worth a look.
	var/list/duty_next_check
	var/next_duty_interrupt_time = 0
	/// A Bot Gym bot is only ever pulled off its goal by these duty types (gym/bot_gym.dm).
	var/list/gym_duties
	/// A duty that has the bot waiting where it is - at departures for the shuttle, on a bar stool with a drink. Its
	/// keep_holding() is asked every tick, and nothing further down handle_wander() happens until it says no.
	var/datum/bot_duty/holding_duty

/datum/bot_brain/proc/my_duties(tier)
	if(!duties)
		duties = list(list(), list(), list())
		duty_next_check = list()
		for(var/datum/bot_duty/D as anything in GLOB.bot_duties)
			if(!D.enabled || !D.applies_to(src))
				continue
			duties[D.tier] += D
			duty_next_check[D] = world.time + rand(0, D.interval_max) //not every bot on the same beat
	return duties[tier]

/// Asks this tier's duties in turn whether there's something to do. TRUE once one has set the bot going.
/datum/bot_brain/proc/run_duties(tier)
	for(var/datum/bot_duty/D as anything in my_duties(tier))
		if(world.time < duty_next_check[D])
			continue
		duty_next_check[D] = world.time + D.next_look(src)
		if(D.try_start(src))
			return TRUE
	return FALSE

/// Called from process() while the bot is on a goal: some things don't wait for it to finish.
/datum/bot_brain/proc/check_duty_interrupts()
	for(var/datum/bot_duty/D as anything in my_duties(BOT_DUTY_URGENT))
		if(!D.interrupts || (gym_scripted && !(D.type in gym_duties)))
			continue
		if(!D.should_interrupt(src))
			continue
		drop_goals("[D.name] can't wait")
		duty_next_check[D] = world.time + D.next_look(src)
		D.try_start(src)
		return

/// Lets go of whatever the bot is on, fetches included, for something that can't wait. Not a failure:
/// nothing gets blacklisted, and whatever it was will be found again later if it still needs doing.
/datum/bot_brain/proc/drop_goals(reason)
	if(current_goal)
		bot_log(src, "dropping [current_goal.type] - [reason]")
		telemetry_event("goal_end", list("goal" = bot_telemetry_short(current_goal.type), "result" = "dropped"))
	stop_pursuit()
	release_claim(current_goal)
	release_claim(suspended_goal)
	current_goal = null
	current_strategy = null
	current_step_index = 0
	suspended_goal = null
	suspended_strategy = null
	suspended_step_index = 0
	if(state == BOT_STATE_GOAL)
		state = BOT_STATE_WANDER
	update_gait()
