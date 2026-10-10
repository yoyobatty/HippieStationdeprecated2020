// Robotics: the Roboticist builds a medibot out of what the lab has on its tables, the way it's done by hand.
//
//  - metal into the exosuit fabricator if the station's stores can't cover a robot arm (a stack off the lab
//    table, clicked on the machine: it goes to the ore silo the fabricator draws on)
//  - the fabricator's "Cyborg Left Arm" button (mecha_part_fabricator/build_part()), and a wait while it prints
//  - the arm onto an EMPTY first-aid kit (storage/firstaid/attackby()): that makes the assembly, in hand
//  - a health analyzer onto the assembly, then a proximity sensor - and the medibot is stood there
//    (bot_assembly/medbot/attackby(); the assembly has to be in a hand for the last step, not in a bag)
//
// One or two a shift, and none once the station has plenty. The medibot is left to get on with it.

/// Medibots about the station before Robotics stops making more.
#define BOT_ROBOTICS_ENOUGH_MEDIBOTS 4
/// How many one roboticist builds in a shift.
#define BOT_ROBOTICS_PER_SHIFT 2

/datum/bot_brain
	var/bots_built = 0
	var/robotics_blocked_until = 0

/// Whether something is in the robotics lab (in the Bot Gym: in this bot's arena).
/datum/bot_brain/proc/in_robotics(atom/A)
	var/area/where = get_area(A)
	return gym_run ? (where == get_area(owner)) : istype(where, /area/science/robotics)

/// A working exosuit fabricator in the lab that isn't in the middle of something.
/datum/bot_brain/proc/find_exofab()
	var/obj/machinery/mecha_part_fabricator/best
	var/best_dist
	for(var/obj/machinery/mecha_part_fabricator/F as anything in bot_instances_of(/obj/machinery/mecha_part_fabricator))
		if(QDELETED(F) || F.z != owner.z || !in_robotics(F) || F.panel_open || (F.stat & (BROKEN|NOPOWER)) || F.being_built || taken_by_another(F))
			continue
		if(!F.rmat?.mat_container || F.rmat.on_hold())
			continue
		var/dist = get_dist(owner, F)
		if(!best || dist < best_dist)
			best = F
			best_dist = dist
	return best

/// A loose part of some type lying about the lab, the nearest. `empty` asks for a container with nothing in it.
/datum/bot_brain/proc/find_lab_part(item_type, empty = FALSE)
	var/obj/item/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(QDELETED(I) || !isturf(I.loc) || I.anchored || I.z != owner.z || !in_robotics(I))
			continue
		if(empty && length(I.contents))
			continue
		var/dist = get_dist(owner, I)
		if(!best || dist < best_dist)
			best = I
			best_dist = dist
	return best

/// One of these the bot has on it already - in a hand, for a kit (its own medical kit isn't for taking apart).
/datum/bot_brain/proc/held_part(item_type, empty = FALSE)
	for(var/obj/item/I in owner.held_items)
		if(istype(I, item_type) && (!empty || !length(I.contents)))
			return I
	return null

/// The design for a robot arm, if this fabricator can print it and the stores cover it.
/datum/bot_brain/proc/robot_arm_design(obj/machinery/mecha_part_fabricator/F)
	var/datum/design/D = SSresearch.techweb_design_by_id("borg_l_arm")
	if(!D || !F.stored_research || !F.stored_research.researched_designs[D.id])
		return null
	return D

/datum/bot_duty/roboticist
	name = "robotics"
	jobs = list("Roboticist")
	interval_min = 400
	interval_max = 900

/datum/bot_duty/roboticist/try_start(datum/bot_brain/bot)
	if(world.time < bot.robotics_blocked_until || bot.bots_built >= BOT_ROBOTICS_PER_SHIFT)
		return FALSE
	if(!bot.gym_run)
		var/about = 0
		for(var/mob/living/simple_animal/bot/medbot/M in GLOB.alive_mob_list)
			if(M.z == bot.owner.z)
				about++
		if(about >= BOT_ROBOTICS_ENOUGH_MEDIBOTS)
			return FALSE
	return bot.assign_goal(new /datum/bot_goal/build_medibot())

/datum/bot_goal/build_medibot
	lawful = TRUE
	exclusive = TRUE //one at a fabricator
	doing = "building a medibot"

/// Nothing gets started unless the lab has everything it will take: an arm (or the means to print one), an empty
/// kit, an analyzer and a sensor.
/datum/bot_goal/build_medibot/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/mecha_part_fabricator/F = bot.find_exofab()
	if(!F)
		return
	var/has_assembly = bot.find_carried_tool(/obj/item/bot_assembly/medbot)
	if(!has_assembly)
		if(!bot.held_part(/obj/item/storage/firstaid, TRUE) && !bot.find_lab_part(/obj/item/storage/firstaid, TRUE))
			return
		if(!bot.find_carried_tool(/obj/item/bodypart/l_arm/robot) && !bot.find_lab_part(/obj/item/bodypart/l_arm/robot))
			var/datum/design/D = bot.robot_arm_design(F)
			if(!D || (!F.check_resources(D) && !bot.find_carried_tool(/obj/item/stack/sheet/metal) && !bot.find_lab_part(/obj/item/stack/sheet/metal)))
				return
	if(!bot.find_carried_tool(/obj/item/healthanalyzer) && !bot.find_lab_part(/obj/item/healthanalyzer))
		return
	if(!bot.find_carried_tool(/obj/item/assembly/prox_sensor) && !bot.find_lab_part(/obj/item/assembly/prox_sensor))
		return
	target = F

/datum/bot_goal/build_medibot/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/stock_fabricator(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/print_robot_arm(), new /datum/bot_step/assemble_medibot())
	return list(S)

/datum/bot_goal/build_medibot/on_give_up(datum/bot_brain/bot)
	bot.robotics_blocked_until = world.time + 5 MINUTES

/datum/bot_strategy/robotics/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// Walks over to one particular loose thing and picks it up.
/datum/bot_goal/take_item/exact
	doing = "getting a part"

/datum/bot_goal/take_item/exact/New(obj/item/I)
	. = ..(I?.type)
	target = I

/datum/bot_goal/take_item/exact/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !isturf(target.loc))
		target = null

/// Whether an arm still has to be printed for this build.
/datum/bot_brain/proc/medibot_needs_arm()
	if(find_carried_tool(/obj/item/bot_assembly/medbot))
		return FALSE
	return !find_carried_tool(/obj/item/bodypart/l_arm/robot) && !find_lab_part(/obj/item/bodypart/l_arm/robot)

/// Metal for the arm, if the stores are short: a stack from the lab, fetched and fed to the fabricator.
/datum/bot_step/stock_fabricator
	var/fetched = FALSE

/datum/bot_step/stock_fabricator/execute(datum/bot_brain/bot)
	var/obj/machinery/mecha_part_fabricator/F = bot.current_goal?.target
	if(!istype(F) || QDELETED(F))
		return GOAL_STEP_FAIL
	var/datum/design/D = bot.robot_arm_design(F)
	if(!bot.medibot_needs_arm() || (D && F.check_resources(D)))
		return GOAL_STEP_SUCCESS
	if(!D)
		return GOAL_STEP_FAIL
	var/obj/item/stack/sheet/metal/sheets = bot.find_carried_tool(/obj/item/stack/sheet/metal)
	if(!sheets)
		if(fetched)
			return GOAL_STEP_FAIL
		fetched = TRUE
		var/obj/item/stack/sheet/metal/loose = bot.find_lab_part(/obj/item/stack/sheet/metal)
		if(loose && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(loose)))
			return GOAL_STEP_PENDING
		return GOAL_STEP_FAIL
	// In hand already (or just fetched): over to the machine with it.
	if(!bot.owner.Adjacent(F))
		if(walked)
			return GOAL_STEP_FAIL
		walked = TRUE
		if(bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(F)))
			return GOAL_STEP_PENDING
		return GOAL_STEP_FAIL
	bot_log(bot, "feeding [sheets] to [F]")
	if(!bot.use_tool_on(sheets, F))
		return GOAL_STEP_FAIL
	return F.check_resources(D) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/stock_fabricator
	var/walked = FALSE

/// Nothing but the walk: up to something, for a step that needs to be stood at it.
/datum/bot_goal/walk_up_to
	lawful = TRUE
	doing = "on my way to something"

/datum/bot_goal/walk_up_to/New(atom/A)
	. = ..()
	target = A

/datum/bot_goal/walk_up_to/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/walk_up_to/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/// At the fabricator: the Cyborg Left Arm button, and a wait while it prints.
/datum/bot_step/paced/print_robot_arm
	max_clicks = 200
	var/started = FALSE
	var/waited = 0

/datum/bot_step/paced/print_robot_arm/start(datum/bot_brain/bot)
	started = FALSE
	waited = 0
	return TRUE

/datum/bot_step/paced/print_robot_arm/do_click(datum/bot_brain/bot)
	var/obj/machinery/mecha_part_fabricator/F = bot.current_goal?.target
	if(!istype(F) || QDELETED(F) || (F.stat & (BROKEN|NOPOWER)))
		return FALSE
	if(!bot.medibot_needs_arm())
		return FALSE //printed (it's on the floor by the machine), or there was one about all along
	if(started)
		// Printing: stood watching it, like anyone.
		waited += 10
		wait_for = 10
		return waited < 900
	if(F.being_built || !bot.owner.Adjacent(F))
		return FALSE
	var/datum/design/D = bot.robot_arm_design(F)
	if(!D || !F.check_resources(D))
		return FALSE
	bot.human_pause(F)
	if(QDELETED(F) || F.being_built || !bot.owner.Adjacent(F))
		return FALSE
	bot.owner.face_atom(F)
	bot.telemetry_ui_action(F, "build [D.name]")
	bot_log(bot, "printing a [lowertext(D.name)]")
	INVOKE_ASYNC(F, TYPE_PROC_REF(/obj/machinery/mecha_part_fabricator, build_part), D)
	started = TRUE
	wait_for = 10
	return TRUE

/datum/bot_step/paced/print_robot_arm/finish(datum/bot_brain/bot)
	return bot.medibot_needs_arm() ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/// The assembly itself, a part at a time. Runs again after each fetch, and picks up from whatever is in hand.
/datum/bot_step/assemble_medibot
	var/fetches = 0

/datum/bot_step/assemble_medibot/proc/fetch(datum/bot_brain/bot, obj/item/part)
	if(!part || fetches >= 8)
		return GOAL_STEP_FAIL
	fetches++
	return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(part)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/datum/bot_step/assemble_medibot/proc/again(datum/bot_brain/bot)
	addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), rand(4, 8))
	return GOAL_STEP_PENDING

/datum/bot_step/assemble_medibot/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return
	var/result = execute(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/assemble_medibot/execute(datum/bot_brain/bot)
	var/obj/item/bot_assembly/medbot/assembly = bot.find_carried_tool(/obj/item/bot_assembly/medbot)
	if(assembly)
		var/needed = (assembly.build_step == ASSEMBLY_FIRST_STEP) ? /obj/item/healthanalyzer : /obj/item/assembly/prox_sensor
		var/obj/item/part = bot.find_carried_tool(needed)
		if(!part)
			return fetch(bot, bot.find_lab_part(needed))
		// The assembly in one hand, the part in the other: the last step doesn't work on one that's in a bag.
		if(!(assembly in bot.owner.held_items) && !bot.ready_in_hand(assembly))
			return GOAL_STEP_FAIL
		var/step_before = assembly.build_step
		var/turf/here = get_turf(bot.owner)
		if(!bot.use_tool_on(part, assembly))
			return GOAL_STEP_FAIL
		if(QDELETED(assembly))
			var/mob/living/simple_animal/bot/medbot/made = locate() in here
			bot.bots_built++
			bot_log(bot, "built [made || "a medibot"]")
			if(!bot.gym_scripted && prob(70))
				bot.say_after_typing(";[pick("New medibot coming out of Robotics.", "Medibot built - it'll find its own way to Medbay.", "One more medibot on the station, courtesy of Robotics.")]")
			return GOAL_STEP_SUCCESS
		if(assembly.build_step == step_before)
			return GOAL_STEP_FAIL
		return again(bot)
	// No assembly yet: a robot arm onto an empty first-aid kit.
	var/obj/item/bodypart/l_arm/robot/arm = bot.find_carried_tool(/obj/item/bodypart/l_arm/robot)
	if(!arm)
		return fetch(bot, bot.find_lab_part(/obj/item/bodypart/l_arm/robot))
	var/obj/item/storage/firstaid/kit = bot.held_part(/obj/item/storage/firstaid, TRUE)
	if(!kit)
		return fetch(bot, bot.find_lab_part(/obj/item/storage/firstaid, TRUE))
	if(!bot.use_tool_on(arm, kit))
		return GOAL_STEP_FAIL
	// With an arm in one hand and the kit in the other there was no hand for what they turned into: it's at the
	// bot's feet (firstaid/attackby() -> put_in_hands()). Picked up, like anything dropped.
	if(!bot.find_carried_tool(/obj/item/bot_assembly/medbot))
		var/obj/item/bot_assembly/medbot/dropped = locate() in get_turf(bot.owner)
		if(!dropped || !bot.take_in_hand(dropped))
			return GOAL_STEP_FAIL
	bot_log(bot, "fitted the arm to the first-aid kit")
	return again(bot)

#undef BOT_ROBOTICS_ENOUGH_MEDIBOTS
#undef BOT_ROBOTICS_PER_SHIFT
