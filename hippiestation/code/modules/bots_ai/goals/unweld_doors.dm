// Welded doors put right (the user's ruling, 2026-11-13). A bot running from a killer welds the door shut behind it (foundation/tactics.dm),
// and so do players; the doors stayed welded for the rest of the round (the Bridge's, Central Access). Once nobody's being chased through it,
// two minutes after it's first seen welded, an engineer cuts a door welded in the round open again, as station upkeep. Public and command
// doors: not maintenance (a welded maintenance door is somebody's own business), not an airlock to space, and not the doors that were
// welded when the round began (airlock.dm LateInitialize() welds some abandoned ones).

/// Airlock -> TRUE: welded when the round began
GLOBAL_LIST_EMPTY(bot_roundstart_welded)
/// Airlock -> when it was first seen welded
GLOBAL_LIST_EMPTY(bot_welds_seen)
/// How long after a weld's first seen it's left: the chase it was for is over by then
#define BOT_UNWELD_AFTER (2 MINUTES)

/proc/bot_note_roundstart_welds()
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(!QDELETED(A) && A.welded)
			GLOB.bot_roundstart_welded[A] = TRUE

/datum/controller/subsystem/ticker/Initialize(timeofday)
	. = ..()
	OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_note_roundstart_welds)))

/// A door welded in the round that's the station's to put right (above), and it's been long enough.
/proc/bot_weld_to_undo(obj/machinery/door/airlock/A)
	if(QDELETED(A) || !A.welded || !A.density || GLOB.bot_roundstart_welded[A] || istype(A, /obj/machinery/door/airlock/external))
		return FALSE
	var/area/AR = get_area(A)
	if(istype(AR, /area/maintenance) || !(is_station_level(A.z) || istype(AR, /area/bot_gym)))
		return FALSE
	var/seen = GLOB.bot_welds_seen[A]
	if(!seen)
		GLOB.bot_welds_seen[A] = world.time
		return FALSE
	return world.time >= seen + BOT_UNWELD_AFTER

/datum/bot_duty/unweld_doors
	name = "unwelding doors"
	jobs = list("Station Engineer", "Chief Engineer")
	priority = 5
	interval_min = 300
	interval_max = 600

/datum/bot_duty/unweld_doors/try_start(datum/bot_brain/bot)
	if(bot.gone_loud() || !bot.can_unweld())
		return FALSE
	var/turf/here = get_turf(bot.owner)
	var/obj/machinery/door/airlock/best
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(A.z != here?.z || !bot_weld_to_undo(A) || bot.taken_by_another(A))
			continue
		if(!best || get_dist(A, here) < get_dist(best, here))
			best = A
	return best ? bot.assign_goal(new /datum/bot_goal/unweld_door(best)) : FALSE

/datum/bot_goal/unweld_door
	lawful = TRUE
	exclusive = TRUE
	doing = "cutting a welded door open"

/datum/bot_goal/unweld_door/New(obj/machinery/door/airlock/A)
	. = ..()
	target = A

/datum/bot_goal/unweld_door/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/unweld_door/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	var/obj/machinery/door/airlock/A = target
	if(QDELETED(A))
		return GOAL_STEP_FAIL
	if(!A.welded)
		bot_log(bot, "[A] is open to use again")
		bot_tally("welded doors put right")
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(A) || ++step.tries > 3)
		return GOAL_STEP_FAIL
	bot.try_unweld(A) //bot_breach.dm: the lit welder on it, harm intent, four seconds
	return step.again(bot, 5)

#undef BOT_UNWELD_AFTER
