// Alert console monitoring: an Atmospheric Technician/Station Engineer/Chief Engineer
// notices an alert console showing its "something's wrong" overlay from a distance
// (update_icon() adds an "alert:N" overlay the instant it has anything active - the same
// visual cue a real player relies on walking past one), walks up to actually read it, and
// dispatches toward whichever response goal matches what it found (Fire -> respond_to_
// fire.dm, Atmosphere -> respond_to_contamination.dm). "Walk up to the computer, see
// where the alerts occur, and respond accordingly" - the same causal chain a real
// engineer follows, rather than the bot just omnisciently already knowing where every
// hazard on the station is.
//
// Two DIFFERENT console types both count, and are treated uniformly below:
// - /obj/machinery/computer/station_alert (station_alert.dm) - the general board, alarms
//   split by class ("Fire"/"Atmosphere"/"Power"), each mapping area name -> list(area,
//   camera, sources). Registers into GLOB.alert_consoles and gets pushed alarms directly
//   via area/atmosalert()'s dispatch loop (areas.dm).
// - /obj/machinery/computer/atmos_alert (atmos_alert.dm) - the atmos-specific board,
//   split into priority_alarms/minor_alarms (plain zone-name strings, no area reference
//   or severity-per-class split) - fed over radio (FREQ_ATMOS_ALARMS) instead of a
//   direct proc dispatch, and never reports anything but atmosphere issues.
// Both are ordinary /obj/machinery/computer subtypes, so both show up in GLOB.machines
// (_machinery.dm's base Initialize()) - used here instead of station_alert's own
// GLOB.alert_consoles specifically, so the same scan covers either type without needing
// two separate lists.
//
// This is a THIRD discovery path alongside the two already in place - can_see_active_
// fire()/can_see_atmos_hazard() (direct line of sight to the hazard itself) and
// triggerAlarm() (the radio push every severe atmosphere alarm already sends, areas.dm)
// - not a replacement for either. A console might be showing an alert for a fire or
// flood the bot can't currently see or hasn't been pushed yet (it only just started
// reading severe, or the bot was mid-goal when the push went out), so this catches
// those too, on the same "reacts to what's actually observable" philosophy.

/datum/bot_brain/proc/console_reports_fire(atom/C)
	if(istype(C, /obj/machinery/computer/station_alert))
		var/obj/machinery/computer/station_alert/S = C
		return LAZYLEN(S.alarms["Fire"])
	return FALSE //atmos_alert has no Fire category at all

/// The places a station alert console lists fires in, now known to this bot (goals/respond_to_fire.dm): where it goes next.
/datum/bot_brain/proc/learn_fires_on_console(obj/machinery/computer/station_alert/S)
	if(!istype(S))
		return
	var/list/fires = S.alarms["Fire"]
	for(var/area_name in fires)
		var/list/alarm = fires[area_name]
		if(islist(alarm) && length(alarm) && isarea(alarm[1]))
			learn_of_fire(alarm[1], "read it on [S]")

// atmos_alert's minor_alarms deliberately does NOT count here, unlike priority_alarms -
// confirmed as a real starvation bug in-game: find_contaminated_air_alarm() (respond_to_
// contamination.dm) only ever acts on danger_level == 2 (severe), so a room stuck at
// "minor" forever (never quite crossing into severe, or an area with a chronically
// borderline reading) left the console permanently showing an alert this system could
// never actually resolve. Since can_see_alerted_console() is untimed (checked every
// single tick, bot_brain.dm) with no cooldown at all, that meant a bot passing the same
// console over and over got dispatched to "go check it" every time, forever - eating
// its attention badly enough that round-start work (the tesla engine checklist,
// setup_tesla_engine.dm) never got a turn. station_alert's own "Atmosphere" list doesn't
// have this problem - area/atmosalert() (areas.dm) only ever adds an area to it when
// danger_level hits 2 in the first place, so it's already severe-only.
/datum/bot_brain/proc/console_reports_atmos(atom/C)
	if(istype(C, /obj/machinery/computer/station_alert))
		var/obj/machinery/computer/station_alert/S = C
		return LAZYLEN(S.alarms["Atmosphere"])
	if(istype(C, /obj/machinery/computer/atmos_alert))
		var/obj/machinery/computer/atmos_alert/A = C
		return LAZYLEN(A.priority_alarms)
	return FALSE

/datum/bot_brain/proc/console_is_alerting(atom/C)
	if(QDELETED(C))
		return FALSE
	if(!istype(C, /obj/machinery/computer/station_alert) && !istype(C, /obj/machinery/computer/atmos_alert))
		return FALSE
	var/obj/machinery/computer/M = C
	if(M.stat & (NOPOWER|BROKEN))
		return FALSE
	return console_reports_fire(C) || console_reports_atmos(C)

/datum/bot_brain/proc/can_see_alerted_console()
	for(var/obj/machinery/computer/C in view(7, owner))
		if(console_is_alerting(C))
			return TRUE
	return FALSE

/datum/bot_brain/proc/find_alerted_console()
	var/turf/bot_turf = get_turf(owner)
	var/obj/machinery/computer/best
	var/best_dist
	for(var/obj/machinery/computer/C as anything in bot_instances_of(/obj/machinery/computer))
		if(!console_is_alerting(C))
			continue
		var/turf/T = get_turf(C)
		if(!T || T.z != owner.z)
			continue
		var/dist = get_dist(bot_turf, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/datum/bot_brain
	/// Having read a console, it's not worth reading again before this. An alarm it could do nothing about stayed on the
	/// screen, and the bot beside it read it again every tick for the rest of the round: 1,900 times, one engineer.
	var/next_console_read_time = 0

/datum/bot_brain/proc/try_check_alert_console_round()
	if(!is_fire_response_job()) //same three jobs fire/contamination response use - the names differ but the role check is identical
		return FALSE
	return assign_goal(new /datum/bot_goal/check_alert_console())

/datum/bot_goal/check_alert_console
	// Set by read_alert_console's execute() once the console's actually been read -
	// on_success() (below) can't dispatch straight to the matching response goal itself
	// (assign_goal() refuses to interrupt the goal that's still technically active while
	// on_success() runs, same reason every other "chain to the next thing" case in this
	// system - continue_atmos_round() and friends - defers by one tick instead of
	// calling straight through), so it needs these to still be around one tick later.
	var/saw_fire
	var/saw_atmos

/datum/bot_goal/check_alert_console/resolve_target(datum/bot_brain/bot)
	target = bot.find_alerted_console()

/datum/bot_goal/check_alert_console/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/check_alert_console())

/datum/bot_goal/check_alert_console/on_success(datum/bot_brain/bot)
	if(saw_fire)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, try_fire_response_round)))
	else if(saw_atmos)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, try_contamination_round)))

/datum/bot_strategy/check_alert_console/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/read_alert_console())

/datum/bot_strategy/check_alert_console/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/read_alert_console/execute(datum/bot_brain/bot)
	var/obj/machinery/computer/C = bot.current_goal?.target
	if(!C || QDELETED(C))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	var/datum/bot_goal/check_alert_console/goal = bot.current_goal
	bot.next_console_read_time = world.time + rand(600, 1200)
	bot.settle_cold_false_alarms(C)
	goal.saw_fire = bot.console_reports_fire(C)
	goal.saw_atmos = bot.console_reports_atmos(C)
	if(goal.saw_fire)
		bot.learn_fires_on_console(C)
	if(!goal.saw_fire && !goal.saw_atmos)
		bot_log(bot, "checked [C] - nothing alarming anymore")
	else
		bot_log(bot, "checked [C] - [goal.saw_fire ? "fire" : ""][(goal.saw_fire && goal.saw_atmos) ? " and " : ""][goal.saw_atmos ? "an atmosphere alarm" : ""] reported - heading over")
	return GOAL_STEP_SUCCESS

// ---- The Chief Engineer's fire alarm controls (hippiestation/code/game/machinery/computer/station_alert_tgui.dm)

/// Rooms kept cold on purpose: their fire alarms go off on the cold. In the batch of 2026-11-08 every one of 52 console reads was the
/// Kitchen Cold Room or a server room, and the engineers walked to each to find nothing.
GLOBAL_LIST_INIT(bot_cold_by_design_areas, typecacheof(list(/area/crew_quarters/kitchen/coldroom, /area/server, /area/science/server, /area/tcommsat/server)))

/// The Chief Engineer at a station alert console, reading a fire alarm that's a cold room being cold: it turns that room's cold trip
/// point down below how cold it is and clears the alarm, as a CE who knows the station would (the user's ruling, 2026-11-10). Air
/// that's thin as well as cold is a breach, and is left alarming. How many it settled.
/datum/bot_brain/proc/settle_cold_false_alarms(obj/machinery/computer/station_alert/S)
	if(!istype(S) || work_role() != "Chief Engineer" || !S.can_set_trips(owner))
		return 0
	. = 0
	var/list/fires = S.alarms["Fire"]
	for(var/area_name in fires?.Copy())
		var/list/alarm = fires[area_name]
		if(!islist(alarm) || !isarea(alarm[1]))
			continue
		var/area/A = alarm[1]
		if(!is_type_in_typecache(A, GLOB.bot_cold_by_design_areas))
			continue
		var/obj/machinery/firealarm/F = locate() in A.firealarms
		var/turf/T = get_turf(F)
		var/datum/gas_mixture/air = T?.return_air()
		if(!air || air.return_pressure() < WARNING_LOW_PRESSURE || air.return_temperature() >= A.fire_trip_cold_point())
			continue
		var/cold = max(0, round(air.return_temperature() - 20, 5))
		human_pause(S)
		telemetry_ui_action(S, "cold trip point")
		S.set_trip(A, "cold", cold, owner)
		S.reset_fire_alarm(area_name, owner)
		bot_log(src, "the fire alarm in [area_name] was the cold: its cold trip point down to [cold] K and cleared")
		bot_tally("cold fire alarms settled at the console")
		bot_say(owner, ":e [pick("Fire alarm in", "The alarm in")] [area_name]'s just the cold. Turned its cold trip down and cleared it.")
		.++
