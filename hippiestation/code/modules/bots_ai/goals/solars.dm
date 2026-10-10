// Solars: an engineer with the engine seen to goes round the solar rooms and sets each array tracking the sun.
// At the console that's two buttons - Refresh, which finds the panels and the tracker on its wiring
// (solar_control/search_for_connected()), and Auto (solar_control/ui_act("tracking")). Untouched, the panels sit
// where they were built and only catch the sun for part of its round.
//
// And, for everybody: a PDA light switched on when it's dark, and off again when it isn't.

/datum/bot_brain
	var/solar_consoles_set = 0
	var/list/solar_blocked

/// Whether a solar console has a tracker on its circuit to follow the sun with - what its screen shows as
/// "connected". Hippie Station's four arrays are built with ten tiles of catwalk between each room and its array
/// that carry no cable, so every console there finds nothing: until somebody lays that cable (an EVA job, not
/// done by bots yet), there is nothing at the console worth walking over for.
/proc/bot_solar_console_is_wired(obj/machinery/power/solar_control/C)
	if(C.connected_tracker)
		return TRUE
	if(!C.powernet)
		return FALSE
	for(var/obj/machinery/power/tracker/T in C.powernet.nodes)
		return TRUE
	return FALSE

/// A solar console that isn't tracking yet and that this bot can walk to, the nearest first.
/datum/bot_brain/proc/find_unset_solar_console()
	var/list/consoles = list() //console -> how far off
	for(var/obj/machinery/power/solar_control/C as anything in bot_instances_of(/obj/machinery/power/solar_control))
		if(QDELETED(C) || C.z != owner.z || (C.stat & (BROKEN|NOPOWER)) || C.track == SOLAR_TRACK_AUTO || !bot_solar_console_is_wired(C))
			continue
		if(gym_run && get_area(C) != get_area(owner))
			continue
		if(LAZYACCESS(solar_blocked, C) > world.time || taken_by_another(C))
			continue
		consoles[C] = get_dist(owner, C)
	var/tries = 0
	while(length(consoles) && tries++ < 2)
		var/obj/machinery/power/solar_control/nearest
		for(var/obj/machinery/power/solar_control/C as anything in consoles)
			if(!nearest || consoles[C] < consoles[nearest])
				nearest = C
		consoles -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
		LAZYSET(solar_blocked, nearest, world.time + 10 MINUTES)
	return null

/datum/bot_duty/solars
	name = "the solars"
	jobs = list("Station Engineer", "Chief Engineer")
	interval_min = 600
	interval_max = 1500

/datum/bot_duty/solars/try_start(datum/bot_brain/bot)
	var/obj/machinery/power/solar_control/C = bot.find_unset_solar_console()
	return C ? bot.assign_goal(new /datum/bot_goal/set_up_solars(C)) : FALSE

/datum/bot_goal/set_up_solars
	lawful = TRUE
	exclusive = TRUE
	doing = "setting the solars up"

/datum/bot_goal/set_up_solars/New(obj/machinery/power/solar_control/C)
	. = ..()
	target = C

/datum/bot_goal/set_up_solars/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/set_up_solars/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/solars/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/work_solar_console())
	return list(S)

/datum/bot_goal/set_up_solars/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.solar_blocked, target, world.time + 10 MINUTES)

/datum/bot_strategy/solars/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the console: Refresh, then Auto - a button a turn.
/datum/bot_step/paced/work_solar_console
	max_clicks = 3
	var/refreshed = FALSE

/datum/bot_step/paced/work_solar_console/start(datum/bot_brain/bot)
	refreshed = FALSE
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/work_solar_console/do_click(datum/bot_brain/bot)
	var/obj/machinery/power/solar_control/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C) || (C.stat & (BROKEN|NOPOWER)) || C.track == SOLAR_TRACK_AUTO)
		return FALSE
	bot.human_pause(C)
	if(QDELETED(C) || !bot.owner.Adjacent(C))
		return FALSE
	bot.owner.face_atom(C)
	if(!refreshed)
		refreshed = TRUE
		bot.telemetry_ui_action(C, "refresh")
		C.search_for_connected()
		return TRUE
	if(!C.connected_tracker)
		bot_log(bot, "[C] found [length(C.connected_panels)] panel\s and no tracker on its wiring")
		return FALSE //nothing on its wiring to follow the sun with
	bot.telemetry_ui_action(C, "tracking auto")
	C.track = SOLAR_TRACK_AUTO
	C.connected_tracker.sun_update(SSsun, SSsun.azimuth)
	return TRUE

/datum/bot_step/paced/work_solar_console/finish(datum/bot_brain/bot)
	var/obj/machinery/power/solar_control/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || C.track != SOLAR_TRACK_AUTO)
		return GOAL_STEP_FAIL
	bot.solar_consoles_set++
	bot_log(bot, "set [C] in [get_area_name(C, TRUE)] to track the sun ([length(C.connected_panels)] panels)")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// A light in the dark
// ---------------------------------------------------------------------------------------------

/// The game's own line for "in the dark" (nyctophobia, shadowpeople): a tile at or under this is dark.
#define BOT_DARK_LUMCOUNT 0.2

/datum/bot_brain
	var/next_light_check = 0
	/// Looks in a row that came back dark (or, with the light on, lit): it takes a couple before the light is touched.
	var/light_votes = 0

/// The PDA this bot has about it somewhere its light would show: in a hand, on the belt, in the ID slot or a pocket.
/datum/bot_brain/proc/handy_pda()
	for(var/obj/item/pda/P in owner.contents)
		return P
	return null

/// Whether it's dark round about - judged a few tiles off, where the bot's own light doesn't reach.
/datum/bot_brain/proc/in_the_dark()
	var/turf/here = get_turf(owner)
	if(!here || isspaceturf(here))
		return FALSE
	var/dark = 0
	var/looked = 0
	for(var/d in GLOB.cardinals)
		var/turf/T = here
		for(var/i in 1 to 4)
			var/turf/next = get_step(T, d)
			if(!isopenturf(next) || next.density || isspaceturf(next))
				break
			T = next
		if(T == here)
			continue
		looked++
		if(T.get_lumcount() <= BOT_DARK_LUMCOUNT)
			dark++
	if(!looked)
		return here.get_lumcount() <= BOT_DARK_LUMCOUNT
	return dark * 2 > looked

/// Every few seconds: the PDA light goes on in the dark and off in the light, after a moment's thought either way.
/datum/bot_brain/proc/mind_the_dark()
	if(world.time < next_light_check)
		return
	next_light_check = world.time + rand(30, 50)
	if(gym_scripted && !gym_minds_the_dark)
		return
	var/obj/item/pda/P = handy_pda()
	if(!P || owner.stat != CONSCIOUS)
		return
	var/dark = in_the_dark()
	if(dark == !!P.fon)
		light_votes = 0
		return
	if(++light_votes < 2)
		return
	light_votes = 0
	telemetry_ui_action(P, dark ? "light on" : "light off")
	P.fon = dark
	P.set_light(dark ? P.f_lum : 0)
	P.update_icon()
	bot_log_verbose(src, "PDA light [dark ? "on" : "off"]")

/datum/bot_brain
	/// A Bot Gym bot leaves its PDA light alone unless its scenario is about that.
	var/gym_minds_the_dark = FALSE

#undef BOT_DARK_LUMCOUNT
