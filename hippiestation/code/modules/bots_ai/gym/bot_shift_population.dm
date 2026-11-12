// A Bot Shift whose crew comes and goes (the user's ask, 2026-11-09: "Do tests where population changes and goes on for a long
// time, or low pop shifts"). -params "bot-pop=0:6,15:20,40:30,70:8,90:4" is how many are on at each minute of the shift, held till
// the next mark: below it, people arrive on the shuttle the way late-joiners do; above it, people log off. Nobody has a cryo pod
// here, so logging off is what a player does: finish up, find a bed in the dorms (or stop where they are if that's too far), lie
// down and go. The body stays, asleep and saying nothing (the SSD a player leaves), and the shift stops judging it.
//
// Who goes: anybody but an antagonist (they stay for the round), somebody in a fight, cuffed or in a cell, or the last of a head of
// staff. Who comes: the jobs the population manager would give (bot_population.dm).

/// How often the crew is counted against the schedule.
#define BOT_POP_CHECK (30 SECONDS)
/// How far a bot walks to a bed to log off in; further than that, it logs off where it stands.
#define BOT_POP_BED_RANGE 40
/// How long it has to get there before it logs off wherever it's got to.
#define BOT_POP_LEAVE_TIME (3 MINUTES)

/datum/bot_shift
	/// list(minute, crew) marks from bot-pop, in order. Null with no schedule.
	var/list/pop_schedule
	var/pop_joined = 0
	var/pop_left = 0
	/// "minute: on" for every change, for the summary.
	var/list/pop_curve = list()

/datum/bot_shift_member
	/// When it logged off, in shift time, or null.
	var/left_at
	/// On its way to log off.
	var/leaving = FALSE

/datum/bot_shift/muster()
	pop_schedule = bot_pop_parse(world.params["bot-pop"])
	. = ..()
	if(pop_schedule)
		note("crew schedule: [world.params["bot-pop"]]")
		addtimer(CALLBACK(src, PROC_REF(pop_check)), BOT_POP_CHECK)

/proc/bot_pop_parse(text)
	if(!text)
		return null
	. = list()
	for(var/mark in splittext("[text]", ","))
		var/list/parts = splittext(mark, ":")
		if(length(parts) != 2)
			continue
		var/minute = text2num(parts[1])
		var/crew = text2num(parts[2])
		if(isnum(minute) && isnum(crew))
			. += list(list(minute, max(0, crew)))
	if(!length(.))
		return null

/// The crew wanted at this point of the shift.
/datum/bot_shift/proc/pop_target()
	var/minute = elapsed() / (1 MINUTES)
	. = pop_schedule[1][2]
	for(var/list/mark as anything in pop_schedule)
		if(minute >= mark[1])
			. = mark[2]

/// The ones on the station still playing: alive, not logged off or on their way out.
/datum/bot_shift/proc/pop_on()
	. = list()
	for(var/datum/bot_shift_member/member as anything in members)
		if(member.brain && !member.leaving && !QDELETED(member.body) && member.body.stat != DEAD)
			. += member

/datum/bot_shift/proc/pop_check()
	if(elapsed() >= length || SSticker.current_state == GAME_STATE_FINISHED)
		return
	addtimer(CALLBACK(src, PROC_REF(pop_check)), BOT_POP_CHECK)
	var/list/on = pop_on()
	var/target = pop_target()
	if(length(on) < target)
		INVOKE_ASYNC(src, PROC_REF(pop_bring_in), min(target - length(on), 5))
	else if(length(on) > target)
		pop_send_off(on, min(length(on) - target, 5))

/datum/bot_shift/proc/pop_bring_in(count)
	for(var/i in 1 to count)
		var/job = GLOB.bot_population.pick_job() || "Assistant"
		var/mob/living/carbon/human/body = SSjob.GetJob(job) ? spawn_bot_crew_member(job) : null
		var/datum/bot_shift_member/member = new(src, job, body)
		members += member
		if(body)
			pop_joined++
			note("[member.label()] joined the crew")
		sleep(3 SECONDS) //bot_shift.dm's arrival gap
	pop_curve += "[round(elapsed() / (1 MINUTES))]: [length(pop_on())]"

/datum/bot_shift/proc/pop_send_off(list/on, count)
	var/list/candidates = list()
	var/list/heads_on = list()
	for(var/datum/bot_shift_member/member as anything in on)
		if(member.job in GLOB.command_positions)
			heads_on[member.job] = TRUE
	for(var/datum/bot_shift_member/member as anything in on)
		var/datum/bot_brain/B = member.brain
		var/mob/living/carbon/human/H = member.body
		if(H.mind?.special_role || B.state == BOT_STATE_COMBAT || B.state == BOT_STATE_ARREST || H.handcuffed || H.bot_life_sentence || B.is_in_active_cell(H))
			continue
		if((member.job in GLOB.command_positions) && length(heads_on) <= 1)
			continue //the last head on keeps the lights on
		candidates += member
	for(var/i in 1 to min(count, length(candidates)))
		var/datum/bot_shift_member/member = pick_n_take(candidates)
		member.leaving = TRUE
		member.brain.drop_goals("logging off")
		member.brain.assign_goal(new /datum/bot_goal/log_off)
		note("[member.label()] is logging off [member.where()]")
	pop_curve += "[round(elapsed() / (1 MINUTES))]: [length(pop_on())]"

/// Called when it's lain down (or given up getting there): the shift lets go of it and its brain stops.
/datum/bot_shift_member/proc/logged_off()
	if(!brain)
		return
	left_at = shift.elapsed()
	shift.pop_left++
	shift.note("[label()] logged off [where()]")
	var/datum/bot_brain/B = brain
	wrap_up()
	B.log_off()

// ---------------------------------------------------------------------------------------------
// Logging off
// ---------------------------------------------------------------------------------------------

/// A bed in the dorms nobody's in, near enough to walk to.
/datum/bot_brain/proc/bed_to_log_off_in()
	var/obj/structure/bed/best
	var/best_dist
	for(var/obj/structure/bed/B as anything in bot_instances_of(/obj/structure/bed))
		if(QDELETED(B) || B.z != owner.z || B.has_buckled_mobs() || !istype(get_area(B), /area/crew_quarters/dorms))
			continue
		var/dist = get_dist(owner, B)
		if(dist > BOT_POP_BED_RANGE || (best && dist >= best_dist))
			continue
		if(!can_walk_lawfully_to(B))
			continue
		best = B
		best_dist = dist
	return best

/datum/bot_goal/log_off
	lawful = TRUE
	exclusive = TRUE
	never_rests = TRUE
	doing = "heading off"
	var/obj/structure/bed/bed
	var/give_up_at = 0

/datum/bot_goal/log_off/resolve_target(datum/bot_brain/bot)
	if(!give_up_at)
		give_up_at = world.time + BOT_POP_LEAVE_TIME
	bed = bot.bed_to_log_off_in()
	target = bed || get_turf(bot.owner)

/datum/bot_goal/log_off/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/lie_down_and_go())
	return list(S)

/datum/bot_goal/log_off/on_give_up(datum/bot_brain/bot)
	bot.go_now()

/datum/bot_step/lie_down_and_go/execute(datum/bot_brain/bot)
	var/datum/bot_goal/log_off/G = bot.current_goal
	var/obj/structure/bed/B = G?.bed
	if(istype(B) && !QDELETED(B) && !B.has_buckled_mobs() && get_turf(bot.owner) != get_turf(B) && bot.owner.Adjacent(B))
		step_towards(bot.owner, B) //onto it: a bed's not dense
	if(istype(B) && !QDELETED(B) && get_turf(bot.owner) == get_turf(B) && !B.has_buckled_mobs())
		B.user_buckle_mob(bot.owner, bot.owner) //the drag onto the bed a player does
	bot.go_now()
	return GOAL_STEP_SUCCESS

/// Off: told to the shift if there is one, and the brain stops on the next tick (not inside its own step).
/datum/bot_brain/proc/go_now()
	if(log_off_pending)
		return
	log_off_pending = TRUE
	bot_log(src, "logging off")
	telemetry_event("logged_off", list("where" = get_area_name(owner, TRUE)))
	addtimer(CALLBACK(src, PROC_REF(finish_log_off)), 1)

/datum/bot_brain
	var/log_off_pending = FALSE

/datum/bot_brain/proc/finish_log_off()
	if(QDELETED(src))
		return
	if(shift_member)
		shift_member.logged_off() //wrap_up() and log_off()
	else
		log_off()

/// The brain goes; the body stays where it lay down, a player who's left.
/datum/bot_brain/proc/log_off()
	if(QDELETED(src))
		return
	var/mob/living/carbon/human/H = owner
	drop_goals("logged off")
	stop_pursuit()
	STOP_PROCESSING(SSprocessing, src)
	if(H)
		H.bot_logged_off = TRUE
		if(H.bot_brain == src)
			H.bot_brain = null
	if(coming_back && H) //bot_comings.dm: back in a few minutes, the same person
		away_for_a_bit()
		return
	// Gone in a few seconds, not now: a click or a step already on a timer still runs, and found no body to run on (two bot AI exceptions
	// and a runtime in six shifts). Stopped and with nothing to do, they come to nothing.
	QDEL_IN(src, 10 SECONDS)

/mob/living/carbon/human
	/// Was a bot, and logged off: the body's still here, nobody's at the keyboard.
	var/bot_logged_off = FALSE

#undef BOT_POP_CHECK
#undef BOT_POP_BED_RANGE
#undef BOT_POP_LEAVE_TIME
