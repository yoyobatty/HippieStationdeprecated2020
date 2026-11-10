// Bot Gym scenarios for engineering upkeep: kitting up (goals/engineer_gear.dm), fixing cables
// mice chewed through (goals/repair_cables.dm), and crew squashing mice in passing (bot_human.dm).

/datum/bot_scenario/se_insulated_gloves
	name = "engineer puts on insulated gloves"
	desc = "A station engineer without insulated gloves fetches a pair from a locker and wears them - and leaves the toolbox in there."
	layout = list(
		"#########",
		"#B...L..#",
		"#########")
	job = "Station Engineer"
	time_limit = 30 SECONDS

/datum/bot_scenario/se_insulated_gloves/setup()
	var/obj/structure/closet/C = first_placed("L")
	new /obj/item/clothing/gloves/color/yellow(C)
	new /obj/item/storage/toolbox/electrical(C)

/datum/bot_scenario/se_insulated_gloves/make_goal()
	return new /datum/bot_goal/engineer_gear()

/datum/bot_scenario/se_insulated_gloves/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(locate(/obj/item/storage/toolbox) in bot.GetAllContents())
		fail_reason = "took the toolbox as well"
		return BOT_GYM_FAIL
	if(istype(bot.gloves, /obj/item/clothing/gloves/color/yellow))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/ce_cloak_and_gloves
	name = "CE takes cloak + gloves from own locker"
	desc = "The Chief Engineer, wearing their black gloves, goes to their locker, puts on the cloak and insulated gloves, and bags the black gloves instead of dropping them. Takes nothing else."
	layout = list(
		"#########",
		"#B...L..#",
		"#########")
	job = "Chief Engineer"
	time_limit = 40 SECONDS

/datum/bot_scenario/ce_cloak_and_gloves/setup()
	var/obj/structure/closet/plain = first_placed("L")
	var/turf/T = get_turf(plain)
	qdel(plain)
	var/obj/structure/closet/secure_closet/engineering_chief/locker = new(T)
	locker.locked = FALSE //no ID in the gym; the lock isn't what's being tested
	locker.update_icon()
	placed["L"] = list(locker)

/datum/bot_scenario/ce_cloak_and_gloves/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/gloves/color/black/ce(bot), ITEM_SLOT_GLOVES)

/datum/bot_scenario/ce_cloak_and_gloves/make_goal()
	return new /datum/bot_goal/engineer_gear()

/datum/bot_scenario/ce_cloak_and_gloves/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	for(var/extra in list(/obj/item/storage/toolbox, /obj/item/areaeditor/blueprints, /obj/item/megaphone))
		if(locate(extra) in carried)
			fail_reason = "also took [extra]"
			return BOT_GYM_FAIL
	if(istype(bot.gloves, /obj/item/clothing/gloves/chief_engineer) && istype(bot.wear_neck, /obj/item/clothing/neck/cloak/ce))
		if(!(locate(/obj/item/clothing/gloves/color/black/ce) in carried))
			fail_reason = "dropped the black gloves instead of bagging them"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/repair_chewed_cable
	name = "engineer fixes a cable a mouse chewed"
	desc = "A yellow cable run with a chewed gap and the dropped bit of cable. Pick the bit up and click the plating with it; the run must be one powernet again."
	layout = list(
		"###########",
		"#B........#",
		"#PP===x===#",
		"###########")
	job = "Station Engineer"
	var/cable_type = /obj/structure/cable
	var/gap_char = "x"
	var/run_char = "="

/datum/bot_scenario/repair_chewed_cable/setup()
	bot_record_cable_break(first_marker(gap_char), cable_type)

/datum/bot_scenario/repair_chewed_cable/make_goal()
	return new /datum/bot_goal/repair_cable(first_marker(gap_char), cable_type)

/datum/bot_scenario/repair_chewed_cable/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/turf/gap = first_marker(gap_char)
	if(!bot_cable_break_fixed(gap, cable_type))
		return BOT_GYM_PENDING
	var/obj/structure/cable/left = locate(cable_type) in get_step(gap, WEST)
	var/obj/structure/cable/right = locate(cable_type) in get_step(gap, EAST)
	if(!left || !right || !left.powernet || left.powernet != right.powernet)
		fail_reason = "laid a cable but the run isn't one network (wrong layer?)"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/repair_chewed_cable/red_layer
	name = "engineer fixes a red-layer cable"
	desc = "Same, but the run is on the red layer and the engineer's own coil is set to yellow - it has to switch the coil's layer first."
	layout = list(
		"###########",
		"#B........#",
		"#PP~~~x~~~#",
		"###########")
	kit_backpack = list(/obj/item/stack/cable_coil)
	cable_type = /obj/structure/cable/layer1
	run_char = "~"

/datum/bot_scenario/crew_swats_mouse
	name = "crew squashes a mouse in passing"
	desc = "Walking past a mouse, the bot swats it (mice chew cables) and carries on."
	layout = list(
		"#########",
		"#B.....G#",
		"#...m...#",
		"#########")

/datum/bot_scenario/crew_swats_mouse/check()
	var/mob/living/simple_animal/mouse/M = first_placed("m")
	. = ..()
	if(. == BOT_GYM_PASS && M && !QDELETED(M) && M.stat != DEAD)
		fail_reason = "walked right past the mouse"
		return BOT_GYM_FAIL

/datum/bot_scenario/mouse_chews_engineer_notices
	name = "mouse chews a cable, engineer notices and fixes it"
	desc = "End to end: a mouse on bare plating chews through a cable (the real chew code, recorded by the break hook); the engineer's own cable round must notice it, claim it and fix it."
	layout = list(
		"###########",
		"#B........#",
		"#PP===P===#",
		"###########")
	job = "Station Engineer"
	var/turf/chew_spot
	var/mob/living/simple_animal/mouse/chewer

/datum/bot_scenario/mouse_chews_engineer_notices/setup()
	chew_spot = first_marker("P")
	for(var/turf/T in markers["P"]) //the P between the two cable runs
		if(locate(/obj/structure/cable) in get_step(T, WEST))
			chew_spot = T
	new /obj/structure/cable(chew_spot)
	chewer = new(chew_spot)
	chewer.stop_automated_movement = TRUE
	chewer.wander = FALSE
	chewer.chew_probability = 100
	// Simple mobs' AI idles with no players around, so drive its real chew routine directly.
	for(var/i in 1 to 200)
		if(!(locate(/obj/structure/cable) in chew_spot))
			break
		chewer.handle_automated_action()
	chewer.forceMove(get_step(chew_spot, NORTH)) //off the cable run, onto the walkway

/// No scripted goal: the engineer has to find the break through its own cable round.
/datum/bot_scenario/mouse_chews_engineer_notices/issue_goal()
	if(brain.try_cable_repair_round())
		goal_attempts++
		log_line("engineer's cable round picked up the break")

/datum/bot_scenario/mouse_chews_engineer_notices/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(!(chew_spot in GLOB.bot_cable_breaks) && !bot_cable_break_fixed(chew_spot, /obj/structure/cable) && goal_attempts == 0)
		fail_reason = "the chew was never recorded as a break"
		return BOT_GYM_FAIL
	if(!bot_cable_break_fixed(chew_spot, /obj/structure/cable))
		return BOT_GYM_PENDING
	var/obj/structure/cable/left = locate(/obj/structure/cable) in get_step(chew_spot, WEST)
	var/obj/structure/cable/right = locate(/obj/structure/cable) in get_step(chew_spot, EAST)
	if(!left || !right || left.powernet != right.powernet)
		fail_reason = "cable laid but the run isn't reconnected"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// An emitter's line of fire (bot_hazards.dm). Layout letter e: an emitter, pointed down the arena.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/beam_on_stroll
	name = "hazards: an emitter switched on across the way stops a stroll planned before it was"
	desc = "Strolling down a corridor when an emitter comes on across it, a few tiles ahead. The route was planned before there was a beam to keep off: an engineer on Meta lit the supermatter's emitter, strolled across its line a second later and went down to four beams, every shift."
	// Room enough that it isn't shut in (bot_doors.dm is_shut_in(), sixty tiles): somebody shut in crosses a beam to get out
	layout = list(
		"####################",
		"#..............e...#",
		"#B................G#",
		"#..................#",
		"#..................#",
		"#..................#",
		"####################")
	time_limit = 12 SECONDS
	var/obj/machinery/power/emitter/emitter
	/// Since when it's been on. Its own `active` goes off again by itself: there's no wire under it here.
	var/lit = FALSE
	var/stepped_in = FALSE

/datum/bot_scenario/beam_on_stroll/setup()
	emitter = place("e", new /obj/machinery/power/emitter(first_marker("e")))
	emitter.anchored = TRUE
	emitter.state = 2 //EMITTER_WELDED
	emitter.active_power_usage = 0 //there's no wire under it here, and without one it switches itself off again
	emitter.setDir(SOUTH)

/datum/bot_scenario/beam_on_stroll/issue_goal()
	return

/datum/bot_scenario/beam_on_stroll/post_spawn()
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	brain.pursue(first_marker("G"), "wander", force = TRUE)
	addtimer(CALLBACK(src, PROC_REF(light_it)), 3)

/// Switched on, and on the map of places to keep out of, with the bot already on its way
/datum/bot_scenario/beam_on_stroll/proc/light_it()
	if(result != BOT_GYM_PENDING || QDELETED(emitter))
		return
	emitter.active = TRUE
	lit = TRUE
	bot_refresh_hazards()
	log_line("the emitter's on; the bot's at [bot.x - first_marker("B").x] tiles along")

/datum/bot_scenario/beam_on_stroll/proc/stepped()
	SIGNAL_HANDLER
	if(lit && bot.x == emitter.x && bot.y < emitter.y)
		stepped_in = TRUE

/datum/bot_scenario/beam_on_stroll/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(stepped_in)
		fail_reason = "walked into the emitter's line of fire"
		return BOT_GYM_FAIL
	if(!lit)
		return BOT_GYM_PENDING
	if(bot.x >= emitter.x)
		fail_reason = "was past the emitter before it came on: nothing tried"
		return BOT_GYM_FAIL
	return world.time > start_time + 6 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/beam_on_stroll/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(!QDELETED(emitter))
		emitter.active = FALSE
	bot_refresh_hazards()
	return ..()

/datum/bot_scenario/beam_on_stroll/stood_in_it
	name = "hazards: stood where an emitter comes on, it steps out of the line of fire"
	desc = "Stood still on the tile an emitter starts firing across. Everybody an emitter killed took the first beam walking and the rest standing where it hit them."
	layout = list(
		"#######",
		"#..e..#",
		"#..B..#",
		"#.....#",
		"#######")

/datum/bot_scenario/beam_on_stroll/stood_in_it/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(light_it)), 10)

/datum/bot_scenario/beam_on_stroll/stood_in_it/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!lit)
		return BOT_GYM_PENDING
	if(bot.x != emitter.x)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING
