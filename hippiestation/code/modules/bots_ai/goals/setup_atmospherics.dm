// Atmospherics setup: an Atmospheric Technician brings the Atmospherics room's air/waste
// loop online - confirmed via the map source (_maps/map_files/HippieStation/
// hippiestation.dmm) and corrected against real in-game feedback, this is NOT "flip
// every valve in the room": the room's actual breathable air supply (~80:20 N2:O2) only
// depends on two pumps, "Air to Distro" (pushes it out onto the Distro network) and
// "Waste In" (pulls returning waste gas back in for processing) - both need to be ON AND
// AT MAX PRESSURE to actually run at capacity, not just nominally switched on.
//
// Everything else in the room is either irrelevant to that (canister outlet routing, the
// Pure/Port/Filter production chain) or actively the wrong thing to enable: "Distro to
// Waste" and "Air to Port" both have "waste"/"air" in their own names despite being a
// manual bypass and a canister-filling spur respectively, and the whole mix tank system
// (name containing "Mix") is the room's manual gas-combining setup - a different ratio
// than the station's air, and exactly the tool a malicious player actually wants, so it
// should always stay off. "Mix to Filter" specifically is mapped /on by the map (unlike
// the rest of the mix tank's plumbing), so it needs to be actively switched back off
// rather than just left alone.
//
// Keyed by P.name (unique within this room) rather than a keyword rule - the naming
// isn't consistent enough to tell "the real air/waste loop" apart from "everything else
// that happens to mention air or waste" any other way (that's exactly how the previous
// keyword version got "Distro to Waste" and "Air to Port" wrong).
//
// The mix-tank entries below aren't just "leave them alone if they're off" - they're
// actively enforced off, same as "Mix to Filter". This is the fix for a real sabotage
// pattern: a malicious player doesn't need to break anything to flood the WHOLE
// station's air supply with plasma, just turn on "Plasma Outlet Pump" (feeds the
// plasma canister into the Pure line) and "Mix to Distro" (the one pump standing
// between the mix tank and the station's actual breathable-air network) - two clicks,
// no tools, no access beyond the room itself. try_atmos_round() re-runs this check
// every 5-15s for as long as the bot's alive (bot_brain.dm), so a saboteur re-opening
// any of these mid-round gets caught and shut again, not just once at round start.
// "Mix to Distro" specifically is the critical choke point - as long as IT stays off,
// nothing upstream in the mix tank can ever reach the station's air, however it got
// contaminated.
#define ATMOS_ACTION_ON_MAXED "on_maxed"
#define ATMOS_ACTION_OFF "off"

GLOBAL_LIST_INIT(bot_atmos_pump_actions, list(
	"Air to Distro" = ATMOS_ACTION_ON_MAXED,
	"Waste In" = ATMOS_ACTION_ON_MAXED,
	"Mix to Filter" = ATMOS_ACTION_OFF,
	"Distro to Waste" = ATMOS_ACTION_OFF,
	"Air to Port" = ATMOS_ACTION_OFF,
	"Mix to Distro" = ATMOS_ACTION_OFF,
	"Mix to Incinerator" = ATMOS_ACTION_OFF,
	"Mix Outlet Pump" = ATMOS_ACTION_OFF,
	"Air to Mix" = ATMOS_ACTION_OFF,
	"Pure to Mix" = ATMOS_ACTION_OFF,
	"Mix to Port" = ATMOS_ACTION_OFF,
	"Mix to Engine" = ATMOS_ACTION_OFF,
	"Plasma Outlet Pump" = ATMOS_ACTION_OFF,
))

/datum/bot_brain/proc/is_atmos_job()
	var/role = owner.mind?.assigned_role
	return role == "Atmospheric Technician"

/datum/bot_brain/proc/atmos_pump_needs_action(obj/machinery/atmospherics/components/binary/pump/P)
	var/action = GLOB.bot_atmos_pump_actions[P.name]
	if(!action)
		return FALSE //not one of the pumps this goal has any business touching at all
	if(action == ATMOS_ACTION_OFF)
		return P.on
	return !P.on || P.target_pressure < MAX_OUTPUT_PRESSURE //ATMOS_ACTION_ON_MAXED

// Picked by distance to the bot's own position (same reasoning as
// find_incomplete_tesla_emitter(), setup_tesla_engine.dm - closest first, not arbitrary
// GLOB.machines order). Area is the other filter: every pump this goal should ever touch
// lives in exactly one room, confirmed via the map source.
/datum/bot_brain/proc/find_atmos_pump_needing_action()
	var/turf/bot_turf = get_turf(owner)
	var/obj/machinery/atmospherics/components/binary/pump/best
	var/best_dist
	for(var/obj/machinery/atmospherics/components/binary/pump/P in GLOB.machines)
		if(P.z != owner.z)
			continue
		if(!istype(get_area(P), /area/engine/atmos))
			continue
		if(!atmos_pump_needs_action(P))
			continue
		if(is_failed_atmos_part(P))
			continue
		var/dist = get_dist(bot_turf, P)
		if(!best || dist < best_dist)
			best = P
			best_dist = dist
	return best

/datum/bot_brain/proc/try_atmos_round()
	if(!is_atmos_job())
		return FALSE
	return assign_goal(new /datum/bot_goal/activate_atmos_pump())

// Same immediate-rechain idea as continue_engineering_round() (setup_tesla_engine.dm) -
// finish one pump, go straight to the next instead of waiting out the normal wander pace.
/datum/bot_brain/proc/continue_atmos_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_atmos_round)))

/datum/bot_goal/activate_atmos_pump

/datum/bot_goal/activate_atmos_pump/resolve_target(datum/bot_brain/bot)
	target = bot.find_atmos_pump_needing_action()

/datum/bot_goal/activate_atmos_pump/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/activate_atmos_pump())

/datum/bot_goal/activate_atmos_pump/on_success(datum/bot_brain/bot)
	bot.continue_atmos_round()

// Cooldown, not permanent - see is_failed_engine_part()'s comment (setup_tesla_engine.dm)
// for why a permanent blacklist over-corrects: a pump that fails to reach right now
// (mid-pathfind hiccup, room briefly blocked) is still worth retrying later, it just
// shouldn't be picked again on the very next cycle.
/datum/bot_goal/activate_atmos_pump/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.failed_atmos_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/activate_atmos_pump/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/activate_atmos_pump())

/datum/bot_strategy/activate_atmos_pump/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/activate_atmos_pump/execute(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/binary/pump/P = bot.current_goal?.target
	if(!P || QDELETED(P))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(P))
		return GOAL_STEP_FAIL
	var/action = GLOB.bot_atmos_pump_actions[P.name]
	if(!bot.atmos_pump_needs_action(P)) //already fixed up by someone else since this step was queued
		return GOAL_STEP_SUCCESS
	if(action == ATMOS_ACTION_OFF)
		P.on = FALSE
		bot_log(bot, "shut off [P]")
	else //ATMOS_ACTION_ON_MAXED
		P.on = TRUE
		P.target_pressure = MAX_OUTPUT_PRESSURE
		bot_log(bot, "maxed out [P]")
	P.update_icon()
	return GOAL_STEP_SUCCESS

#undef ATMOS_ACTION_ON_MAXED
#undef ATMOS_ACTION_OFF
