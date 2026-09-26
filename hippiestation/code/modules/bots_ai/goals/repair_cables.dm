// Engineers repair broken power cables the way a player does: go to the gap, pick up the bit of
// cable that was left behind, make sure the coil is set to the broken cable's layer (the coil's
// Ctrl-click radial), and click the bare plating with the coil in hand. This codebase's cables
// auto-connect (cable.dm connect_wire()), so one cable laid on the gap rejoins both sides.
//
// How engineers find out, like players do:
//  - a mouse chewing through a cable (the usual cause) is recorded as a break; engineers "hear"
//    about it after a short delay - the APC alarm / power monitor - or at once if it's in sight
//  - they spot gaps themselves: a snipped bit of cable lying on plating between cable ends

#define BOT_CABLE_NOTICE_DELAY_MIN 300 //30s-90s after a break before an engineer "hears" about it
#define BOT_CABLE_NOTICE_DELAY_MAX 900
#define BOT_CABLE_CLAIM_TIME 1200 //one engineer per break

/// Broken cable spots: turf -> list("type" = cable type, "time" = when, "notice" = delay, "claim" = brain, "claim_time")
GLOBAL_LIST_EMPTY(bot_cable_breaks)

/datum/bot_brain
	var/next_cable_check_time = 0
	var/next_cable_look_time = 0
	/// turf -> world.time before which not to retry a failed repair there
	var/list/failed_cable_repairs

/proc/bot_record_cable_break(turf/T, cable_type)
	if(!T || !cable_type)
		return
	GLOB.bot_cable_breaks[T] = list("type" = cable_type, "time" = world.time, "notice" = rand(BOT_CABLE_NOTICE_DELAY_MIN, BOT_CABLE_NOTICE_DELAY_MAX))

/proc/bot_cable_break_fixed(turf/T, cable_type)
	for(var/obj/structure/cable/C in T)
		if(C.type == cable_type)
			return TRUE
	return FALSE

// Mice chew cable on bare plating (mouse.dm handle_automated_action) - note which ones they got.
/mob/living/simple_animal/mouse/handle_automated_action()
	var/turf/T = get_turf(src)
	var/list/cables
	for(var/obj/structure/cable/C in T)
		LAZYSET(cables, C, C.type)
	. = ..()
	for(var/obj/structure/cable/C in cables)
		if(QDELETED(C))
			bot_record_cable_break(T, cables[C])

/datum/bot_brain/proc/try_cable_repair_round()
	if(!is_power_engineer_job())
		return FALSE
	notice_cable_gaps()
	var/turf/best
	var/best_dist
	var/list/stale = list()
	for(var/turf/T in GLOB.bot_cable_breaks)
		var/list/info = GLOB.bot_cable_breaks[T]
		if(bot_cable_break_fixed(T, info["type"]))
			stale += T
			continue
		if(T.z != owner.z || LAZYACCESS(failed_cable_repairs, T) > world.time)
			continue
		var/datum/bot_brain/claimant = info["claim"]
		if(claimant && claimant != src && !QDELETED(claimant) && world.time < info["claim_time"] + BOT_CABLE_CLAIM_TIME)
			continue //another engineer is already on it
		if(world.time < info["time"] + info["notice"] && !(T in view(7, owner)))
			continue //hasn't come up on the alarms yet, and not in sight
		var/d = get_dist(owner, T)
		if(!best || d < best_dist)
			best = T
			best_dist = d
	for(var/turf/T in stale)
		GLOB.bot_cable_breaks -= T
	if(!best)
		return FALSE
	var/list/info = GLOB.bot_cable_breaks[best]
	info["claim"] = src
	info["claim_time"] = world.time
	return assign_goal(new /datum/bot_goal/repair_cable(best, info["type"]))

/// A gap an engineer can see: a bit of cable lying on bare plating with no cable of its own,
/// between cables on at least two sides. Records it with the layer most of those neighbours use.
/datum/bot_brain/proc/notice_cable_gaps()
	if(world.time < next_cable_look_time)
		return
	next_cable_look_time = world.time + 30
	for(var/obj/item/stack/cable_coil/piece in view(6, owner))
		var/turf/T = piece.loc
		if(!isturf(T) || T.intact || (T in GLOB.bot_cable_breaks) || (locate(/obj/structure/cable) in T))
			continue
		var/list/layer_votes = list()
		for(var/d in GLOB.cardinals)
			for(var/obj/structure/cable/C in get_step(T, d))
				layer_votes[C.type]++
		var/best_type
		for(var/cable_type in layer_votes)
			if(layer_votes[cable_type] >= 2 && (!best_type || layer_votes[cable_type] > layer_votes[best_type]))
				best_type = cable_type
		if(best_type)
			bot_record_cable_break(T, best_type)
			var/list/info = GLOB.bot_cable_breaks[T]
			info["notice"] = 0 //seen it with my own eyes
			bot_log(src, "spotted a break in the cable at [bot_coord(T)] ([get_area_name(T)])")

// ---------------------------------------------------------------------------------------------

/datum/bot_goal/repair_cable
	var/turf/break_turf
	var/cable_type

/datum/bot_goal/repair_cable/New(turf/T, type)
	break_turf = T
	cable_type = type

/datum/bot_goal/repair_cable/resolve_target(datum/bot_brain/bot)
	if(break_turf && !bot_cable_break_fixed(break_turf, cable_type))
		target = break_turf

/datum/bot_goal/repair_cable/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/repair_cable())

/datum/bot_goal/repair_cable/on_success(datum/bot_brain/bot)
	GLOB.bot_cable_breaks -= break_turf

/datum/bot_goal/repair_cable/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.failed_cable_repairs, break_turf, world.time + 3 MINUTES)
	var/list/info = GLOB.bot_cable_breaks[break_turf]
	if(info)
		info["claim"] = null

/datum/bot_strategy/repair_cable
	max_attempts = 3 //laying live cable bare-handed can shock and fumble it - try again

/datum/bot_strategy/repair_cable/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/get_cable_coil(), new /datum/bot_step/lay_cable())

/datum/bot_strategy/repair_cable/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Pick up the bit of cable left at the gap (what a player grabs first), or use a carried coil,
/// or go and fetch one.
/datum/bot_step/get_cable_coil
	var/fetch_attempted = FALSE

/datum/bot_step/get_cable_coil/execute(datum/bot_brain/bot)
	var/datum/bot_goal/repair_cable/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	var/obj/item/stack/cable_coil/piece = locate() in G.break_turf
	if(piece && !bot.is_carried(piece))
		bot.try_pickup_target(piece)
	if(bot.find_carried_tool(/obj/item/stack/cable_coil))
		return GOAL_STEP_SUCCESS
	if(fetch_attempted)
		bot_log(bot, "no cable coil to fix the break with")
		return GOAL_STEP_FAIL
	fetch_attempted = TRUE
	var/datum/bot_goal/acquire_item_type/fetch = new
	fetch.item_type = /obj/item/stack/cable_coil
	if(bot.suspend_goal_for(fetch))
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/// Click the bare plating with the coil in hand, on the right layer.
/datum/bot_step/lay_cable/execute(datum/bot_brain/bot)
	var/datum/bot_goal/repair_cable/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	var/turf/T = G.break_turf
	if(bot_cable_break_fixed(T, G.cable_type))
		return GOAL_STEP_SUCCESS
	var/obj/item/stack/cable_coil/coil = bot.find_carried_tool(/obj/item/stack/cable_coil)
	if(!coil)
		var/obj/item/stack/cable_coil/piece = locate() in T //a shock made us fumble it - pick it back up
		if(piece)
			bot.try_pickup_target(piece)
			coil = bot.find_carried_tool(/obj/item/stack/cable_coil)
	if(!coil || !bot.ready_in_hand(coil))
		return GOAL_STEP_FAIL
	bot.set_coil_layer(coil, G.cable_type)
	bot_log(bot, "fixing the cable at [bot_coord(T)] ([get_area_name(T)])")
	bot.use_tool_on(coil, T) //turf/attackby() -> place_turf(); the new cable auto-connects both sides
	if(bot_cable_break_fixed(T, G.cable_type))
		bot_log(bot, "cable's fixed")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

/// The coil's Ctrl-click radial (cable.dm CtrlClick): pick the layer to lay on.
/datum/bot_brain/proc/set_coil_layer(obj/item/stack/cable_coil/coil, cable_type)
	if(coil.target_type == cable_type)
		return
	human_pause(coil)
	var/obj/structure/cable/layer = cable_type
	coil.target_type = cable_type
	coil.color = initial(layer.color)
	telemetry_event("radial", list("item" = "[coil]", "choice" = "[initial(layer.color)] layer"))
