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
	RETURN_TYPE(/datum/bot_duty)
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
	/// A way of passing the time, neither work nor a need: a smoke, the arcade, a stroll round somebody else's department. Left alone
	/// while the station's in trouble (station_in_trouble()).
	var/pastime = FALSE

/datum/bot_duty/proc/applies_to(datum/bot_brain/bot)
	return !jobs || (bot.work_role() in jobs)

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
	var/loud = gone_loud() //goals/robust.dm
	var/trouble //worked out the first time a pastime is up
	for(var/datum/bot_duty/D as anything in my_duties(tier))
		if(world.time < duty_next_check[D])
			continue
		if(loud && !is_type_in_typecache(D, GLOB.bot_duties_when_loud))
			continue
		if(D.pastime)
			if(isnull(trouble))
				trouble = station_in_trouble()
			if(trouble)
				continue //asked again next look: it isn't put off for a whole interval, only for as long as the trouble lasts
		duty_next_check[D] = world.time + D.next_look(src)
		if(D.try_start(src))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// When the station's in trouble
// ---------------------------------------------------------------------------------------------
// Pastimes (a smoke, the arcade, a work-out, a stroll round somebody else's department, a clown's show) went on all through a bad shift:
// in play1114b, once three of the crew were dead, 197 more strolls round other departments, 14 smokes, 6 games of arcade and 29 shows
// followed, as often as before. The user's ruling after their Captain round (2026-11-10): "With the bodies piling up nobody's asking who's
// up for arcade". Work goes on, and so do eating and drinking: a bot that's hungry is hungry in a crisis too.

/// GLOB.bot_trouble_drill (gym/scenarios_bm_jobs.dm): the Bot Gym scenarios that say the station's in trouble. A gym arena's crew aren't on
/// the station's shift, and the dead in one arena are nothing to do with the next.
GLOBAL_VAR_INIT(bot_trouble_looked_at, -INFINITY)
GLOBAL_VAR(bot_trouble_found)

/// Integrity below which the crystal's a reason for the whole crew to be on edge.
#define BOT_CRYSTAL_WORRY 70

/// Whether the supermatter is far enough gone that the engineers are running and everybody else has noticed.
/proc/bot_crystal_failing()
	var/obj/machinery/power/supermatter_crystal/crystal = GLOB.main_supermatter_engine
	return !QDELETED(crystal) && crystal.get_integrity() < BOT_CRYSTAL_WORRY

/// Crew dead this recently, this many of them, and the killing's still going on as far as anybody can tell. A shift that lost three people
/// in the first quarter hour and then ran quietly for an hour isn't one nobody dares light a cigarette in.
#define BOT_TROUBLE_WINDOW (10 MINUTES)
#define BOT_TROUBLE_DEAD 2

/// Whether crew have been dying lately.
/proc/bot_crew_dying_lately()
	var/recent = 0
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.mind?.assigned_role && H.timeofdeath && world.time < H.timeofdeath + BOT_TROUBLE_WINDOW && ++recent >= BOT_TROUBLE_DEAD)
			return TRUE
	return FALSE

/// Whether it's no time for idling, anywhere on the station: two of the crew dead in the last ten minutes, red alert, a good part of the
/// station off the mains, or the crystal going. Looked at once every few seconds, for everybody.
/proc/bot_station_in_trouble()
	if(world.time < GLOB.bot_trouble_looked_at + 5 SECONDS)
		return GLOB.bot_trouble_found
	GLOB.bot_trouble_looked_at = world.time
	GLOB.bot_trouble_found = bot_crew_dying_lately() || GLOB.security_level >= SEC_LEVEL_RED || bot_power_failing() || bot_crystal_failing()
	return GLOB.bot_trouble_found

/// Whether this bot sees the station as in trouble: a Bot Gym bot only when its scenario says so.
/datum/bot_brain/proc/station_in_trouble()
	if(gym_run)
		return gym_run in GLOB.bot_trouble_drill
	return bot_station_in_trouble()

#undef BOT_CRYSTAL_WORRY
#undef BOT_TROUBLE_WINDOW
#undef BOT_TROUBLE_DEAD

/// Called from process() while the bot is on a goal: some things don't wait for it to finish.
/datum/bot_brain/proc/check_duty_interrupts()
	var/loud = gone_loud() //goals/robust.dm
	for(var/datum/bot_duty/D as anything in my_duties(BOT_DUTY_URGENT))
		if(!D.interrupts || (gym_scripted && !(D.type in gym_duties)))
			continue
		if(loud && !is_type_in_typecache(D, GLOB.bot_duties_when_loud))
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
