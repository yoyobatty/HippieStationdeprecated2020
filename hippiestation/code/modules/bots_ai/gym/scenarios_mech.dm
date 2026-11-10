// Bot Gym scenarios for building mechs (goals/mech_build.dm). Layout letters: k the exosuit fabricator (it prints onto the tile
// below it), a metal (fifty sheets a stack), u glass, h the tools (wrench, screwdriver, wirecutters, a welder, cable), y the boards
// and parts (both Ripley boards, a scanning module, a capacitor, a cell).

/datum/bot_scenario/mech_ripley
	name = "robotics: builds a Ripley from scratch and fits it a drill"
	desc = "A Roboticist in a lab with an empty exosuit fabricator, three stacks of metal, one of glass, the tools, both Ripley boards and the stock parts. It feeds the fabricator, prints the chassis and the parts, puts them together and works through every step the chassis asks for until the Ripley stands up, then prints a drill and fits it."
	job = "Roboticist"
	layout = list(
		"############",
		"#B..k......#",
		"#..........#",
		"#.aaau.....#",
		"#.hhy......#",
		"############")
	time_limit = 6 MINUTES
	max_goal_attempts = 4

/datum/bot_scenario/mech_ripley/setup()
	var/obj/machinery/mecha_part_fabricator/F = new(first_marker("k"))
	F.setDir(SOUTH)
	place("k", F)
	for(var/turf/T in markers["a"])
		place("a", new /obj/item/stack/sheet/metal(T, 50))
	for(var/turf/T in markers["u"])
		place("u", new /obj/item/stack/sheet/glass(T, 50))
	var/turf/tools = first_marker("h")
	for(var/path in list(/obj/item/wrench, /obj/item/screwdriver, /obj/item/wirecutters, /obj/item/weldingtool/largetank))
		place("h", new path(tools))
	place("h", new /obj/item/stack/cable_coil(tools, 30))
	var/turf/parts = first_marker("y")
	for(var/path in list(/obj/item/circuitboard/mecha/ripley/main, /obj/item/circuitboard/mecha/ripley/peripherals, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/capacitor, /obj/item/stock_parts/cell/high))
		place("y", new path(parts))

/datum/bot_scenario/mech_ripley/post_spawn()
	give_job_id(list(ACCESS_ROBOTICS, ACCESS_RESEARCH))

/datum/bot_scenario/mech_ripley/make_goal()
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/build_ripley"))
	if(!D)
		log_line("there's no such duty")
	else if(!D.try_start(brain))
		log_line("the duty didn't start")
	return null

/datum/bot_scenario/mech_ripley/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/mecha/working/ripley/R in arena_area)
		if(bot_mech_drill(R))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// The gym's own errand for driving: to the exosuit, in, and to G in it.
/datum/bot_goal/gym_drive_mech
	lawful = TRUE
	doing = "driving the Ripley"
	var/turf/drive_to

/datum/bot_goal/gym_drive_mech/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	var/datum/bot_step/move_to/drive = new
	drive.step_target = drive_to
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/gym_climb_in(), drive)
	return list(S)

/datum/bot_step/gym_climb_in/execute(datum/bot_brain/bot)
	return bot.climb_into_mech(bot.current_goal?.target) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_scenario/mech_drive
	name = "mech: climbs into a Ripley and drives it through a door"
	desc = "A Ripley stands by the bot, and the far end is through an airlock. It climbs in and drives there, the Ripley opening the door for its ID."
	job = "Shaft Miner"
	layout = list(
		"############",
		"#B.k...D..G#",
		"############")
	time_limit = 40 SECONDS

/datum/bot_scenario/mech_drive/setup()
	place("k", new /obj/mecha/working/ripley(first_marker("k")))

/datum/bot_scenario/mech_drive/make_goal()
	var/obj/mecha/M = first_placed("k")
	if(goal_attempts > 2 || QDELETED(M))
		return null
	var/datum/bot_goal/gym_drive_mech/G = new
	G.target = M
	G.drive_to = first_marker("G")
	return G

/datum/bot_scenario/mech_drive/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/mecha/M = first_placed("k")
	if(M?.occupant == bot && get_dist(M, first_marker("G")) <= 1)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// Bot Shift drill (mech-drill=1): a Ripley waiting in Robotics from the start, for the trips that use one (goals/mech_pilot.dm).
/datum/bot_shift/muster()
	. = ..()
	if(!world.params["mech-drill"])
		return
	for(var/area/science/robotics/A in world)
		for(var/turf/open/floor/T in A)
			if(T.density || (locate(/obj/machinery) in T) || (locate(/obj/structure) in T))
				continue
			var/obj/mecha/working/ripley/R = new(T)
			var/obj/item/mecha_parts/mecha_equipment/drill/D = new(T)
			D.attach(R)
			note("mech drill: a Ripley with a drill waiting at [R.x],[R.y] in [A.name]")
			return
