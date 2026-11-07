// The engine let loose (goals/sabotage.dm). Which engine is the map's:
//
//  - the tesla (Hippie Station): its emitters switched off and the particle accelerator turned all the way up. The field has about
//    seventy seconds in it with the emitters gone, and a ball fed harder grows faster once it's out.
//  - the supermatter (the rest): the pumps on its cooling loop switched off, so the crystal cooks in its own heat.
//
// The crew's side was there already, and this is what it's for: engineers drop everything when the tesla's emitters go down
// (engine_alarm, setup_tesla_engine.dm) and put the supermatter's loop back as they find it (the supermatter duty walks its
// checklist again, setup_supermatter.dm). A loose ball everybody keeps clear of (bot_hazards.dm). Whether the engineers get there
// in time is the round's business.

/datum/bot_sabotage/engine
	id = "engine"
	name = "the engine let loose"

/datum/bot_sabotage/engine/weight(datum/bot_brain/bot)
	if(!length(bot.engine_sabotage_targets()))
		return 0
	return (bot.work_role() in list("Station Engineer", "Chief Engineer", "Atmospheric Technician")) ? 5 : 1

/datum/bot_sabotage/engine/start(datum/bot_brain/bot)
	var/list/targets = bot.engine_sabotage_targets()
	return length(targets) ? bot.assign_goal(new /datum/bot_goal/sabotage_engine(targets, src)) : FALSE

/// What there is to switch off on the station's running engine, and the accelerator to turn up: nothing if it isn't running.
/datum/bot_brain/proc/engine_sabotage_targets()
	. = list()
	var/turf/site = bot_caged_tesla_site() //setup_tesla_engine.dm
	if(site)
		for(var/obj/machinery/power/emitter/anchored/E as anything in bot_instances_of(/obj/machinery/power/emitter/anchored))
			if(E.active && E.z == site.z && get_dist(E, site) <= 40)
				. += E
		var/obj/machinery/particle_accelerator/control_box/CB = find_pa_console()
		if(CB?.active && CB.strength < CB.strength_upper_limit)
			. += CB
		return
	var/obj/machinery/power/supermatter_crystal/S = station_crystal() //setup_supermatter.dm: null where the tesla's the engine
	if(QDELETED(S) || S.power < 100)
		return
	// Not the ones in among the crystal's radiation: nobody walks in there (bot_hazards.dm), and a saboteur on Box Station tried the pump
	// by the chamber three times with "no path" each time.
	for(var/obj/machinery/atmospherics/components/binary/pump/P as anything in bot_instances_of(/obj/machinery/atmospherics/components/binary/pump))
		if(P.on && P.z == S.z && get_dist(S, P) <= 22 && sm_loop_pump(P) && !bot_in_crystal_rads(P))
			. += P

/datum/bot_goal/sabotage_engine
	doing = "checking on the engine"
	breaks_in = TRUE
	var/list/parts
	var/datum/bot_sabotage/act
	var/done = 0

/datum/bot_goal/sabotage_engine/New(list/targets, datum/bot_sabotage/A)
	. = ..()
	parts = targets
	act = A

/datum/bot_goal/sabotage_engine/resolve_target(datum/bot_brain/bot)
	for(var/atom/A as anything in parts)
		if(!QDELETED(A))
			target = A
			return

/datum/bot_goal/sabotage_engine/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list()
	for(var/atom/A as anything in parts)
		if(QDELETED(A))
			continue
		var/datum/bot_step/move_to/to_part = new
		to_part.step_target = A
		S.steps += list(to_part, new /datum/bot_step/paced/sabotage_switch_off(src, A))
	return list(S)

/datum/bot_goal/sabotage_engine/on_success(datum/bot_brain/bot)
	if(!done)
		return
	bot.sabotage_finished(act, get_area_name(bot.owner, TRUE))
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/lay_low()))

/// At one of them: nobody looking, and it's off (or the accelerator's up).
/datum/bot_step/paced/sabotage_switch_off
	max_clicks = 40
	var/datum/bot_goal/sabotage_engine/goal
	var/atom/part
	var/waiting_since = 0
	var/switched = FALSE

/datum/bot_step/paced/sabotage_switch_off/New(datum/bot_goal/sabotage_engine/G, atom/A)
	. = ..()
	goal = G
	part = A

/datum/bot_step/paced/sabotage_switch_off/start(datum/bot_brain/bot)
	waiting_since = world.time
	return TRUE

/datum/bot_step/paced/sabotage_switch_off/do_click(datum/bot_brain/bot)
	if(switched || QDELETED(part) || !bot.owner.Adjacent(part))
		return FALSE
	if(!bot.sabotage_unwatched(waiting_since))
		wait_for = 10
		return TRUE
	bot.human_pause(part)
	bot.telemetry_ui_action(part, "sabotage")
	if(istype(part, /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/E = part
		E.active = FALSE
		E.update_icon()
	else if(istype(part, /obj/machinery/particle_accelerator/control_box))
		var/obj/machinery/particle_accelerator/control_box/CB = part
		while(CB.strength < CB.strength_upper_limit)
			CB.add_strength()
	else if(istype(part, /obj/machinery/atmospherics/components/binary/pump))
		var/obj/machinery/atmospherics/components/binary/pump/P = part
		P.on = FALSE
		P.update_icon()
		P.investigate_log("was turned off by [key_name(bot.owner)] (bot saboteur)", INVESTIGATE_ATMOS)
	switched = TRUE
	goal.done++
	bot_log(bot, "SABOTAGE: [istype(part, /obj/machinery/particle_accelerator/control_box) ? "turned [part] all the way up" : "switched off [part]"]")
	log_game("BOT SABOTAGE: [key_name(bot.owner)] sabotaged [part] at [AREACOORD(part)]")
	bot_witness_sabotage(bot.owner, "is messing with the engine")
	return FALSE

/datum/bot_step/paced/sabotage_switch_off/finish(datum/bot_brain/bot)
	return GOAL_STEP_SUCCESS //one it couldn't get at doesn't stop it going on to the next
