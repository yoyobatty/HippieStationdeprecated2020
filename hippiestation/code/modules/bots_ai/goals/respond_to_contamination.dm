// Localized plasma flood response: an Atmospheric Technician/Station Engineer/Chief
// Engineer switches a contaminated room's air alarm to CONTAMINATED mode (fast, wide-net
// scrubbing that specifically targets plasma among every other hazardous trace gas -
// apply_mode(), airalarm.dm) rather than doing anything to the room's contents directly.
// This is the real in-game answer to "someone opened a plasma canister in a room" - no
// need to find or touch the canister itself, the room's own scrubbers (every device in
// the area's air_scrub_names, apply_mode() already handles the fan-out) do the actual
// cleanup once told to prioritize it.
//
// Detection uses the air alarm's OWN danger_level (airalarm.dm) rather than the bot
// reading gas mixtures itself - this is the exact real mechanic a player actually relies
// on (the same value that drives an alarm's own flashing light color, and what the
// atmospheric alert console's priority/minor alarm lists are built from, atmos_alert.dm):
// each alarm continuously checks pressure, temperature, AND every tracked gas's partial
// pressure against its own TLV thresholds (get_danger_level(), airalarm.dm) and keeps
// danger_level current on its own - 0 safe, 1 minor, 2 severe. Reusing it instead of a
// hand-rolled plasma-fraction scan means this reacts to ANY dangerous atmosphere (a CO2
// buildup, an overheated room, not just plasma specifically), for free, using thresholds
// that already match what a human player would see flashing on the alarm itself.
//
// AALARM_MODE_SCRUBBING/AALARM_MODE_CONTAMINATED are #define'd inside airalarm.dm and
// #undef'd at that file's own end, so - same situation as setup_tesla_engine.dm's
// PA_CONSTRUCTION_* constants - they're not referenceable by name from a file compiled
// after it. Their literal values (confirmed via source read, not assumed) are hardcoded
// below, each labelled with the macro name they correspond to.
//
// Reverts back to normal scrubbing once the room's danger_level has dropped to fully
// clear (not just below "severe") - left on contaminated mode forever it would keep
// hammering the room's air (widenet + every trace gas filtered) long after there's
// anything left to clean, which isn't what a real atmos tech does once a room reads clear.

/datum/bot_brain/proc/is_atmos_response_job()
	var/role = owner.mind?.assigned_role
	return role == "Station Engineer" || role == "Chief Engineer" || role == "Atmospheric Technician"

// Every bot_brain registers itself here on creation (bot_brain.dm's New()/Destroy()),
// mirroring how the AI/drones/alert consoles/alarm-monitor tablets already get pushed
// atmosphere alarms - see /area/proc/atmosalert()'s dispatch block for those four
// (areas.dm), which this is a fifth entry in. Reacting to the push the instant a room
// actually goes severe, rather than only ever finding out on the next 5-15s poll
// (try_contamination_round(), below), is a closer match for "a real engineer hears the
// alarm" than pure polling - the poll stays too though, as a fallback for a bot that
// wasn't registered yet when an already-ongoing alarm first triggered (a bot spawning
// mid-round into an already-alarmed area gets no edge-triggered push at all, since
// atmosalert() only fires on a STATE CHANGE).
GLOBAL_LIST_EMPTY(atmos_alert_bots)

/datum/bot_brain/proc/triggerAlarm(class, area/A, O, obj/alarmsource)
	if(class != "Atmosphere" || !is_atmos_response_job())
		return
	if(alarmsource && alarmsource.z != owner.z)
		return
	bot_log(src, "noticed an atmosphere alarm in [A.name] - heading over to check it")
	try_contamination_round()

// Deliberately a no-op - unlike the AI/drones/consoles (which show a running list of
// active alarms that need to visibly clear), this bot doesn't track "which alarms are
// currently ringing" as its own state at all. find_air_alarm_needing_revert() (below)
// already re-derives "is this room actually clear" fresh from the alarm's own
// danger_level every time it's asked, the same way every other finder in this file
// works - there's nothing here that a cancelAlarm push would need to update.
/datum/bot_brain/proc/cancelAlarm(class, area/A, obj/origin)
	return

// True the instant the bot can actually SEE trouble, not just "the network told me about
// it somewhere on the station" - checked every tick in handle_wander() (bot_brain.dm),
// ahead of and independent from both the radio push (triggerAlarm(), above) and the
// timer-gated poll (try_contamination_round(), below). Two separate things count:
//
// - A visibly rendered plasma cloud (turf.atmos_overlay_types, LINDA_turf_tile.dm's
//   update_visuals() - the same "is there enough gas here to actually be drawn" check
//   the game itself uses to decide whether to show the purple haze at all) - this can
//   catch a flood before it's even accumulated enough to cross the air alarm's own
//   TLV "severe" threshold (get_danger_level(), airalarm.dm), the same way a person
//   would notice the haze on sight well before an alarm necessarily trips.
// - An air alarm the bot can see that's ALREADY reading severe (danger_level == 2) -
//   same threshold find_contaminated_air_alarm() below uses, just scoped to what's
//   currently in view instead of the whole station, for the cases where the radio push
//   was missed (a bot that wasn't registered yet, see atmos_alert_bots' comment) but
//   the bot happens to be standing right there regardless.
/datum/bot_brain/proc/can_see_atmos_hazard()
	for(var/turf/open/T in view(7, owner))
		if(LAZYLEN(T.atmos_overlay_types))
			return TRUE
	for(var/obj/machinery/airalarm/AA in view(7, owner))
		if(AA.danger_level >= 2 && AA.mode != 8) //AALARM_MODE_CONTAMINATED - already handling this one
			return TRUE
	return FALSE

// Nearest air alarm reading "severe" (danger_level == 2, the same threshold the atmos
// alert console treats as a priority alarm, atmos_alert.dm) that isn't already in
// contaminated mode.
/datum/bot_brain/proc/find_contaminated_air_alarm()
	var/turf/bot_turf = get_turf(owner)
	var/obj/machinery/airalarm/best
	var/best_dist
	for(var/obj/machinery/airalarm/AA in GLOB.machines)
		if(AA.z != owner.z)
			continue
		if(AA.mode == 8) //AALARM_MODE_CONTAMINATED - already handling this one
			continue
		if(AA.danger_level < 2)
			continue
		var/dist = get_dist(bot_turf, AA)
		if(!best || dist < best_dist)
			best = AA
			best_dist = dist
	return best

// The other half of the pair above - an alarm THIS SYSTEM put into contaminated mode
// whose room has actually cleared since (danger_level back to 0, not just below
// "severe" - see this file's header comment for why). Only reverts alarms in
// contaminated mode at all - one a player set for their own reasons (a chem spill, say)
// is left alone, not silently switched back by a bot that had no part in raising it.
/datum/bot_brain/proc/find_air_alarm_needing_revert()
	for(var/obj/machinery/airalarm/AA in GLOB.machines)
		if(AA.z != owner.z)
			continue
		if(AA.mode != 8) //AALARM_MODE_CONTAMINATED
			continue
		if(AA.danger_level > 0)
			continue
		return AA
	return null

/datum/bot_brain/proc/try_contamination_round()
	if(!is_atmos_response_job())
		return FALSE
	return assign_goal(new /datum/bot_goal/clean_contamination())

// Same immediate-rechain idea as continue_atmos_round() (setup_atmospherics.dm) - finish
// one alarm, go straight to the next (another contaminated room, or one ready to revert)
// instead of waiting out the normal wander pace.
/datum/bot_brain/proc/continue_contamination_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_contamination_round)))

/datum/bot_goal/clean_contamination
	// TRUE = switching this alarm INTO contaminated mode, FALSE = reverting it back to
	// normal scrubbing - decided once in resolve_target() and carried through to the step
	// that actually applies it, so the step doesn't have to re-derive which direction
	// this particular trip was for.
	var/set_to_contaminated

/datum/bot_goal/clean_contamination/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/airalarm/AA = bot.find_contaminated_air_alarm()
	if(AA)
		target = AA
		set_to_contaminated = TRUE
		return
	AA = bot.find_air_alarm_needing_revert()
	if(AA)
		target = AA
		set_to_contaminated = FALSE

/datum/bot_goal/clean_contamination/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/clean_contamination(set_to_contaminated))

/datum/bot_goal/clean_contamination/on_success(datum/bot_brain/bot)
	bot.continue_contamination_round()

/datum/bot_strategy/clean_contamination
	var/set_to_contaminated

/datum/bot_strategy/clean_contamination/New(set_to_contaminated)
	. = ..()
	src.set_to_contaminated = set_to_contaminated
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/set_air_alarm_mode(set_to_contaminated))

/datum/bot_strategy/clean_contamination/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/set_air_alarm_mode
	var/set_to_contaminated

/datum/bot_step/set_air_alarm_mode/New(set_to_contaminated)
	. = ..()
	src.set_to_contaminated = set_to_contaminated

/datum/bot_step/set_air_alarm_mode/execute(datum/bot_brain/bot)
	var/obj/machinery/airalarm/AA = bot.current_goal?.target
	if(!AA || QDELETED(AA))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(AA))
		return GOAL_STEP_FAIL
	AA.mode = set_to_contaminated ? 8 : 1 //AALARM_MODE_CONTAMINATED / AALARM_MODE_SCRUBBING (airalarm.dm)
	AA.apply_mode(bot.owner)
	bot_log(bot, "[set_to_contaminated ? "switched [AA] to wide-net contaminant filtering" : "restored normal filtering on [AA] - room reads clear"]")
	return GOAL_STEP_SUCCESS
