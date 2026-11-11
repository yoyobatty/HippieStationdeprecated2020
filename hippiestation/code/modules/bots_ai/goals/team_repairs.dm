// Repairs and hazards as a team (the user's rulings, 2026-11-11). Spoken-for jobs go to one person (bot_claims.dm); these don't.
//
//  - A helper: an Assistant who isn't a greytider and is both sociable and diligent (0.5 or more of each; no trait of its own).
//    About one assistant in twelve. At 0.6 with greytiders in, 7 of 8 helpers in a 12-shift batch spent the shift raiding (team1111).
//  - Helpers pitch in where engineers do: holes in the hull (suited up first, as an engineer is, goals/gear_up_eva.dm), smashed
//    windows, fires (an extinguisher, from far enough off), and fetching metal or glass to where an engineer's at work.
//  - A call for engineers ("hull breach in the bar", "power's out in Medbay") goes to every free engineer and the two nearest
//    free helpers, not one.

/// Sociability and diligence both at least this: an assistant who pitches in.
#define BOT_HELPER_TRAIT 0.5
/// Helpers sent with the engineers on a call.
#define BOT_TEAM_HELPERS 2

/proc/bot_is_helper(datum/bot_brain/B)
	return !QDELETED(B) && B.work_role() == "Assistant" && !B.greytider && B.sociability >= BOT_HELPER_TRAIT && B.diligence >= BOT_HELPER_TRAIT

/// Puts fires out when it sees or hears of them: the engineering trades, and helpers.
/datum/bot_brain/proc/is_fire_responder()
	return is_fire_response_job() || bot_is_helper(src)

/datum/bot_duty/patch_hull/applies_to(datum/bot_brain/bot)
	return ..() || bot_is_helper(bot)

/datum/bot_duty/repair_windows/applies_to(datum/bot_brain/bot)
	return ..() || bot_is_helper(bot)

// ---------------------------------------------------------------------------------------------
// A call for engineers: everybody free
// ---------------------------------------------------------------------------------------------

/datum/bot_request_kind
	/// Offered to everybody free whose call it is, not the nearest one (bot_offer_team()).
	var/team_call = FALSE

/datum/bot_request
	/// The names of everybody who took it (more than one on a team call), for the logs and the gym.
	var/list/takers

/datum/bot_request_kind/engineer
	team_call = TRUE

/datum/bot_request_kind/engineer/heard_by(datum/bot_brain/bot, named)
	return ..() || bot_is_helper(bot)

/datum/bot_request_kind/engineer/answered_by(datum/bot_brain/bot, datum/bot_request/R)
	return ..() || bot_is_helper(bot)

/datum/bot_request_kind/engineer/ack_for(datum/bot_brain/bot, datum/bot_request/R)
	if(bot_is_helper(bot))
		return pick("I'll come help.", "Coming to give a hand.", "On my way, I'll help out.", "I can help, coming.")
	return ..()

/datum/bot_request_kind/engineer/attend(datum/bot_brain/bot, datum/bot_request/R)
	if(bot_is_helper(bot))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, pitch_in)))
		return
	return ..()

/// Every free engineer, and the nearest helpers, each set off for it.
/proc/bot_offer_team(datum/bot_request/R)
	var/turf/there = isarea(R.place) ? null : get_turf(R.place)
	var/list/going = list()
	var/list/helpers = list() //brain -> how far off
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B) || QDELETED(B.owner) || !B.can_take_call(R))
			continue
		if(B.work_role() in R.kind.jobs)
			going += B
		else if(bot_is_helper(B))
			helpers[B] = there ? get_dist(B.owner, there) : 0
	for(var/i in 1 to BOT_TEAM_HELPERS)
		var/datum/bot_brain/nearest
		for(var/datum/bot_brain/B as anything in helpers)
			if(!nearest || helpers[B] < helpers[nearest])
				nearest = B
		if(!nearest)
			break
		helpers -= nearest
		going += nearest
	for(var/datum/bot_brain/B as anything in going)
		B.take_call(R)

/// There at an engineer call: whatever's to be done that a helper can do, nearest first, the fixes before the fetching.
/datum/bot_brain/proc/pitch_in()
	if(try_fire_response_round()) //goals/respond_to_fire.dm
		return TRUE
	for(var/duty_type in list(/datum/bot_duty/patch_hull, /datum/bot_duty/repair_windows, /datum/bot_duty/fetch_for_engineers))
		var/datum/bot_duty/D = bot_duty_of(duty_type)
		if(D?.try_start(src))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Fetching for the engineers
// ---------------------------------------------------------------------------------------------

/// REF(spot) -> when a helper last brought something there: once is enough.
GLOBAL_LIST_EMPTY(bot_team_stocked)

/// A helper with no fix of its own to take: metal to a hole an engineer's on, glass to a window, left by them on the floor (where the
/// engineer's own look for materials, acquire_item_type, finds it nearer than a locker).
/datum/bot_duty/fetch_for_engineers
	name = "fetching for the engineers"
	jobs = list()
	interval_min = 200
	interval_max = 500

/datum/bot_duty/fetch_for_engineers/applies_to(datum/bot_brain/bot)
	return bot_is_helper(bot)

/datum/bot_duty/fetch_for_engineers/try_start(datum/bot_brain/bot)
	var/turf/best
	var/best_type
	var/best_dist
	for(var/datum/bot_brain/E as anything in GLOB.bot_brains)
		if(E == bot || QDELETED(E) || QDELETED(E.owner) || E.owner.stat != CONSCIOUS)
			continue
		var/datum/bot_goal/G = (istype(E.suspended_goal, /datum/bot_goal/patch_hull) || istype(E.suspended_goal, /datum/bot_goal/repair_window)) ? E.suspended_goal : E.current_goal
		var/stack_type
		if(istype(G, /datum/bot_goal/patch_hull))
			stack_type = /obj/item/stack/sheet/metal
		else if(istype(G, /datum/bot_goal/repair_window))
			stack_type = /obj/item/stack/sheet/glass
		else
			continue
		var/turf/site = get_turf(G.target)
		if(!site || site.z != bot.owner.z || (bot.gym_run && get_area(site) != get_area(bot.owner)))
			continue
		var/stocked_at = GLOB.bot_team_stocked[REF(site)]
		if((stocked_at && world.time < stocked_at + 5 MINUTES) || (locate(stack_type) in range(2, site)))
			continue
		var/dist = get_dist(bot.owner, site)
		if(dist > 40)
			continue
		if(!best || dist < best_dist)
			best = site
			best_type = stack_type
			best_dist = dist
	if(!best)
		return FALSE
	GLOB.bot_team_stocked[REF(best)] = world.time
	return bot.assign_goal(new /datum/bot_goal/bring_materials(best, best_type))

/datum/bot_goal/bring_materials
	lawful = TRUE
	braves_bad_air = TRUE //suited up like the engineers: it's where they're working
	doing = "bringing materials for a repair"
	var/stack_type
	var/turf/site

/datum/bot_goal/bring_materials/New(turf/T, type)
	. = ..()
	site = T
	stack_type = type

/datum/bot_goal/bring_materials/resolve_target(datum/bot_brain/bot)
	target = bot_hull_standing_spot(site) || site

/datum/bot_goal/bring_materials/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/get_stack_to_bring(), new /datum/bot_step/ensure_suit_to_bring(), new /datum/bot_step/move_to(), new /datum/bot_step/leave_materials())
	return list(S)

/datum/bot_step/get_stack_to_bring
	var/tried = FALSE

/datum/bot_step/get_stack_to_bring/execute(datum/bot_brain/bot)
	var/datum/bot_goal/bring_materials/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	if(bot.carried_stack(G.stack_type, 1))
		return GOAL_STEP_SUCCESS
	if(tried)
		return GOAL_STEP_FAIL
	tried = TRUE
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = G.stack_type
	get.lawful = TRUE
	get.doing = "getting materials for the engineers"
	return bot.suspend_goal_for(get) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// A suit first if the air's gone where they're working, as for a hole (goals/repair_hull.dm). One try.
/datum/bot_step/ensure_suit_to_bring
	var/tried = FALSE

/datum/bot_step/ensure_suit_to_bring/execute(datum/bot_brain/bot)
	var/turf/T = bot.current_goal?.target
	if(bot.is_eva_ready() || (T && bot.turf_air_is_breathable(T)))
		return GOAL_STEP_SUCCESS
	if(tried)
		return GOAL_STEP_FAIL
	tried = TRUE
	return bot.suspend_goal_for(new /datum/bot_goal/gear_up_for_eva()) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Down on the floor by the work, and a word to whoever's at it.
/datum/bot_step/leave_materials/execute(datum/bot_brain/bot)
	var/datum/bot_goal/bring_materials/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	var/obj/item/stack/S = bot.carried_stack(G.stack_type, 1)
	if(!S)
		return GOAL_STEP_FAIL
	if(!bot.owner.dropItemToGround(S))
		return GOAL_STEP_FAIL
	bot_log(bot, "left [S] by the work at [bot_coord(G.site)]")
	bot_tally("materials brought to engineers")
	bot_say(bot.owner, pick("Brought you some [S.name].", "Here, [S.name] for this.", "Dropped some [S.name] here for you."))
	return GOAL_STEP_SUCCESS

#undef BOT_HELPER_TRAIT
#undef BOT_TEAM_HELPERS
