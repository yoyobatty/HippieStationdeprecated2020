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

// The mech miner (goals/mining_mech.dm), without the shuttle. Letters as for digging on foot (R rock, O iron, l lava), and Y the Ripley
// Hippie's Mining keeps: drill, clamp, ore box and scanner fitted.
/datum/bot_scenario/mining/mech
	name = "mech miner: drills the seams the Ripley's scanner shows, and the ore goes into its box"
	desc = "Three seams of iron in a bank of rock. The miner climbs into the Ripley, drives over and drills them out; the ore goes straight into the box in the hold."
	kit_hands = list()
	kit_backpack = list()
	time_limit = 90 SECONDS
	layout = list(
		"############",
		"#B.Y.......#",
		"#......RROR#",
		"#.....RROOR#",
		"#......RRRR#",
		"############")
	var/obj/mecha/working/ripley/R

/datum/bot_scenario/mining/mech/setup()
	..()
	for(var/turf/T in markers["Y"])
		R = new /obj/mecha/working/ripley/mining_roundstart(T)
		place("Y", R)

/datum/bot_scenario/mining/mech/make_goal()
	return new /datum/bot_goal/mech_mine(R)

/datum/bot_scenario/mining/mech/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/turf/T in markers["O"])
		if(bot_turf_is_ore(T))
			return BOT_GYM_PENDING
	var/ore = bot_ore_count(bot_mech_ore_box(R))
	if(!ore)
		fail_reason = "the seams are gone but the box is empty"
		return BOT_GYM_FAIL
	log_line("[ore] ore in the box")
	return BOT_GYM_PASS

/// A goliath between it and the seam: it drives off, not at it.
/datum/bot_scenario/mining/mech/goliath
	name = "mech miner: drives off from a goliath rather than fight it"
	desc = "A goliath stands by the only seam. The miner in the Ripley backs off from it instead of drilling it."
	time_limit = 60 SECONDS
	layout = list(
		"##################",
		"#B.Y.............#",
		"#................#",
		"#..........G..OR.#",
		"#.............RR.#",
		"##################")
	var/mob/living/simple_animal/hostile/asteroid/goliath/beast

/datum/bot_scenario/mining/mech/goliath/setup()
	..()
	for(var/turf/T in markers["G"])
		beast = new(T)
		place("G", beast)

/datum/bot_scenario/mining/mech/goliath/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(beast) || beast.health < beast.maxHealth)
		fail_reason = "went at the goliath"
		return BOT_GYM_FAIL
	return brain.mech_retreats ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Back at the station: the box onto the ore machine's input (M, taking from the west), emptied, clamped back up, and the Ripley onto the
/// charger (Z, the port, facing the floor east of it).
/datum/bot_scenario/mech_unload
	name = "mech miner: sets the ore box down on the ore machine, clamps it back and parks on the charger"
	desc = "The Ripley's back with a box of iron. The miner drives it onto the redemption machine's input, sets the box down, waits for it to be emptied, takes it back with the clamp and parks on the charger."
	job = "Shaft Miner"
	time_limit = 90 SECONDS
	layout = list(
		"############",
		"#B.Y......M#",
		"#..........#",
		"#Z.........#",
		"############")
	var/obj/mecha/working/ripley/R
	var/obj/machinery/mineral/ore_redemption/machine

/datum/bot_scenario/mech_unload/setup()
	for(var/turf/T in markers["Y"])
		R = new /obj/mecha/working/ripley/mining_roundstart(T)
		place("Y", R)
		var/obj/structure/ore_box/box = bot_mech_ore_box(R)
		new /obj/item/stack/ore/iron(box, 20)
	for(var/turf/T in markers["M"])
		machine = new(T)
		machine.input_dir = WEST
		machine.output_dir = EAST
		place("M", machine)
	for(var/turf/T in markers["Z"])
		var/turf/floor = get_step(T, EAST)
		floor.ChangeTurf(/turf/open/floor/mech_bay_recharge_floor)
		var/obj/machinery/mech_bay_recharge_port/P = new(T)
		P.setDir(EAST)
		place("Z", P)

/datum/bot_scenario/mech_unload/make_goal()
	return new /datum/bot_goal/mech_unload(R)

/datum/bot_scenario/mech_unload/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/structure/ore_box/box = bot_mech_ore_box(R)
	if(!box || bot_ore_count(box) || !bot_mech_on_charger(R) || brain.in_mech())
		var/obj/structure/ore_box/loose = locate() in get_step(machine, machine.input_dir)
		var/said = "box [box ? "in the hold" : (loose ? "on the input with [bot_ore_count(loose)] ore" : "elsewhere")], machine powered=[machine.powered()] container=[!!machine.materials?.mat_container] processing=[(machine in SSmachines.processing)] panel=[machine.panel_open]"
		if(said != last_said)
			last_said = said
			log_line(said)
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

/datum/bot_scenario/mech_unload
	var/last_said
