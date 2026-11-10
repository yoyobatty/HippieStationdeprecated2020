// Robotics builds a Ripley (the user's ask, 2026-11-09: low-pop players "going to ruins/Lava land in a mech to get rare items").
// The mech comes first: a Roboticist with the lab to itself puts an APLU together for the station, the way a player does it.
//
//  - The chassis and the four limbs and torso off the exosuit fabricator (the Ripley set, roundstart research), metal fed to it
//    from the lab's stack if the stores can't cover a part.
//  - The parts onto the chassis where it was printed (a chassis can't be picked up), any order.
//  - Then each step the chassis asks for, read off its construction (mecha_construction_paths.dm: the examine text a player goes
//    by): a wrench, a screwdriver, cable, the two Ripley boards from a circuit imprinter, a scanning module and a capacitor and a
//    cell off a protolathe (or the lab's tables), metal for the plating, rods made from metal for the cockpit, a lit welder.
//  - The mech stands where the chassis was, and a drill off the fabricator goes on it. One a shift; it's left in the lab for whoever
//    wants it (goals/mech_pilot.dm takes it down to Lavaland).

/// Before it tries again when the build couldn't go on (no metal, nothing to print with).
#define BOT_RIPLEY_REST (10 MINUTES)
/// How far into the shift before a Roboticist starts on one: the medibots first.
#define BOT_RIPLEY_AFTER (6 MINUTES)

/// The parts onto the chassis, and their designs at the exosuit fabricator.
GLOBAL_LIST_INIT(bot_ripley_part_designs, list(
	/obj/item/mecha_parts/part/ripley_torso = "ripley_torso",
	/obj/item/mecha_parts/part/ripley_left_arm = "ripley_left_arm",
	/obj/item/mecha_parts/part/ripley_right_arm = "ripley_right_arm",
	/obj/item/mecha_parts/part/ripley_left_leg = "ripley_left_leg",
	/obj/item/mecha_parts/part/ripley_right_leg = "ripley_right_leg",
))
/// What a construction step wants that a lathe prints, and the design.
GLOBAL_LIST_INIT(bot_mech_step_designs, list(
	/obj/item/circuitboard/mecha/ripley/main = "ripley_main",
	/obj/item/circuitboard/mecha/ripley/peripherals = "ripley_peri",
	/obj/item/stock_parts/scanning_module = "basic_scanning",
	/obj/item/stock_parts/capacitor = "basic_capacitor",
	/obj/item/stock_parts/cell = "basic_cell",
))
/// A tool behaviour a step names -> the tool.
GLOBAL_LIST_INIT(bot_tool_for_behaviour, list(TOOL_WRENCH = /obj/item/wrench, TOOL_SCREWDRIVER = /obj/item/screwdriver,
	TOOL_WIRECUTTER = /obj/item/wirecutters, TOOL_WELDER = /obj/item/weldingtool, TOOL_CROWBAR = /obj/item/crowbar, TOOL_MULTITOOL = /obj/item/multitool))

/datum/bot_brain
	var/ripley_blocked_until = 0
	var/ripleys_built = 0

/// A Ripley about the station already (built, or one a crew's been at), or one being put together.
/proc/bot_ripley_about(z)
	for(var/obj/mecha/working/ripley/R in GLOB.mechas_list)
		if(R.z == z)
			return R
	return null

/datum/bot_duty/build_ripley
	name = "building a Ripley"
	jobs = list("Roboticist")
	priority = 2
	interval_min = 2 MINUTES
	interval_max = 5 MINUTES

/datum/bot_duty/build_ripley/try_start(datum/bot_brain/bot)
	if(world.time < bot.ripley_blocked_until || bot.ripleys_built || (!bot.gym_run && world.time < SSticker.round_start_time + BOT_RIPLEY_AFTER))
		return FALSE
	if(!bot.gym_run && bot_ripley_about(bot.owner.z))
		return FALSE
	var/obj/machinery/mecha_part_fabricator/F = bot.find_exofab()
	if(!F || !F.stored_research?.researched_designs["ripley_chassis"])
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/build_ripley(F))

/datum/bot_goal/build_ripley
	lawful = TRUE
	exclusive = TRUE //one at the fabricator
	doing = "building a Ripley"
	var/obj/item/mecha_parts/chassis/chassis

/datum/bot_goal/build_ripley/New(obj/machinery/mecha_part_fabricator/F)
	. = ..()
	target = F

/datum/bot_goal/build_ripley/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/mecha_part_fabricator/F = target
	if(QDELETED(F) || (F.stat & (BROKEN|NOPOWER)))
		target = null

/datum/bot_goal/build_ripley/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/work_on_ripley())
	return list(S)

/datum/bot_goal/build_ripley/on_give_up(datum/bot_brain/bot)
	bot.ripley_blocked_until = world.time + BOT_RIPLEY_REST

/datum/bot_goal/build_ripley/on_success(datum/bot_brain/bot)
	bot.ripleys_built++
	bot_tally("ripleys built")
	if(!bot.gym_scripted)
		bot_say(bot.owner, pick(";Ripley's built, it's in Robotics if Mining wants it.", ";Got an APLU together. It's in the lab.", ";There's a Ripley in Robotics now, for whoever needs one."))

/// A Ripley chassis in the lab (in the Bot Gym, the arena), part-built or not.
/datum/bot_brain/proc/find_ripley_chassis()
	for(var/obj/item/mecha_parts/chassis/ripley/C as anything in bot_instances_of(/obj/item/mecha_parts/chassis/ripley))
		if(!QDELETED(C) && isturf(C.loc) && C.z == owner.z && in_robotics(C))
			return C
	return null

/// One of these lying in the lab, or by `near` (a lathe that printed it), that nobody else is after.
/datum/bot_brain/proc/mech_part_lying(item_type, atom/near, amount = 1)
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(QDELETED(I) || !isturf(I.loc) || I.anchored || I.z != owner.z || taken_by_another(I))
			continue
		if(!in_robotics(I) && !(near && get_dist(I, near) <= 1))
			continue
		var/obj/item/stack/S = I
		if(istype(S) && S.get_amount() < amount)
			continue
		return I
	return null

/// The build, one thing at a time, each look deciding the next: run again after every click, fetch and print.
/datum/bot_step/work_on_ripley
	var/actions = 0
	var/fetches = 0
	var/turf/built_at
	/// A lathe it's had print something, so what's on its tile counts as the bot's.
	var/obj/machinery/rnd/production/printed_at
	var/waits = 0
	/// How far the chassis has got, as a number that only goes up.
	var/best_progress = 0
	var/drill_goes = 0

/datum/bot_step/work_on_ripley/proc/again(datum/bot_brain/bot, delay = 5)
	addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), delay)
	return GOAL_STEP_PENDING

/datum/bot_step/work_on_ripley/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || !bot.on_this_step(src))
		return
	var/result
	try
		result = execute(bot)
	catch(var/exception/e)
		bot_log_exception(bot, "work_on_ripley", e)
		result = GOAL_STEP_FAIL
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/work_on_ripley/proc/fetch(datum/bot_brain/bot, datum/bot_goal/G)
	if(++fetches > 30)
		bot_log(bot, "RIPLEY: too many trips for parts, leaving it")
		return GOAL_STEP_FAIL
	return bot.suspend_goal_for(G) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/datum/bot_step/work_on_ripley/proc/use(datum/bot_brain/bot, obj/item/I, atom/on)
	if(!bot.owner.Adjacent(on))
		return fetch(bot, new /datum/bot_goal/walk_up_to(on))
	bot.owner.face_atom(on)
	bot.use_tool_on(I, on)
	return again(bot)

/// Prints a part at the exosuit fabricator, feeding it the lab's metal first if it's short.
/datum/bot_step/work_on_ripley/proc/print_at_fab(datum/bot_brain/bot, obj/machinery/mecha_part_fabricator/F, id)
	var/datum/design/D = SSresearch.techweb_design_by_id(id)
	if(!D || !F.stored_research?.researched_designs[id])
		bot_log(bot, "RIPLEY: [F] can't make [id]")
		return GOAL_STEP_FAIL
	if(F.being_built)
		if(++waits > 120)
			return GOAL_STEP_FAIL
		return again(bot, 1 SECONDS)
	if(!F.check_resources(D))
		// Whatever it's short of (metal for all of it, glass for the torso), from the lab's stacks.
		var/datum/component/material_container/stores = F.rmat.mat_container
		var/list/need = F.get_resources_w_coeff(D)
		for(var/mat_id in need)
			var/datum/material/M = stores.materials[mat_id]
			if(!M || M.amount >= need[mat_id] || !M.sheet_type)
				continue
			var/obj/item/stack/sheet/S = bot.find_carried_tool(M.sheet_type)
			if(S)
				if(!bot.owner.Adjacent(F))
					return fetch(bot, new /datum/bot_goal/walk_up_to(F))
				bot_log(bot, "RIPLEY: feeding [S] to [F] for the [D.name]")
				bot.use_tool_on(S, F)
				return again(bot)
			var/obj/item/stack/sheet/loose = bot.mech_part_lying(M.sheet_type)
			if(loose)
				return fetch(bot, new /datum/bot_goal/take_item/exact(loose))
			bot_log(bot, "RIPLEY: no [lowertext(M.name)] for the [D.name]")
			return GOAL_STEP_FAIL
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(F))
		return fetch(bot, new /datum/bot_goal/walk_up_to(F))
	bot.human_pause(F)
	if(F.being_built || !bot.owner.Adjacent(F))
		return again(bot)
	bot.owner.face_atom(F)
	bot.telemetry_ui_action(F, "build [D.name]")
	bot_log(bot, "RIPLEY: printing the [D.name]")
	INVOKE_ASYNC(F, TYPE_PROC_REF(/obj/machinery/mecha_part_fabricator, build_part), D)
	return again(bot, 2 SECONDS)

/datum/bot_step/work_on_ripley/execute(datum/bot_brain/bot)
	var/datum/bot_goal/build_ripley/G = bot.current_goal
	var/obj/machinery/mecha_part_fabricator/F = G?.target
	if(!istype(G) || QDELETED(F))
		return GOAL_STEP_FAIL
	if(++actions > 200)
		bot_log(bot, "RIPLEY: still not done after [actions] goes, leaving it")
		return GOAL_STEP_FAIL
	// Done: the mech stands where the chassis was.
	if(built_at && (QDELETED(G.chassis) || !G.chassis))
		var/obj/mecha/working/ripley/R = locate() in built_at
		if(R)
			// A drill on it, for the rock (goals/mech_pilot.dm): off the fabricator, and on with a click.
			if(bot_mech_drill(R) || drill_goes > 3)
				bot_log(bot, "RIPLEY: built [R][bot_mech_drill(R) ? ", with a drill" : ""]")
				return GOAL_STEP_SUCCESS
			var/obj/item/mecha_parts/mecha_equipment/drill/D = bot.find_carried_tool(/obj/item/mecha_parts/mecha_equipment/drill)
			if(D)
				drill_goes++
				return use(bot, D, R)
			D = bot.mech_part_lying(/obj/item/mecha_parts/mecha_equipment/drill)
			if(D)
				return fetch(bot, new /datum/bot_goal/take_item/exact(D))
			if(!F.being_built)
				drill_goes++ //a print started, not a wait for one
			. = print_at_fab(bot, F, "mech_drill")
			if(. == GOAL_STEP_FAIL)
				drill_goes = 4 //no drill to be had: the Ripley as it is
				return again(bot)
			return
	if(QDELETED(G.chassis))
		G.chassis = bot.find_ripley_chassis()
	var/obj/item/mecha_parts/chassis/ripley/C = G.chassis
	if(!C)
		return print_at_fab(bot, F, "ripley_chassis")
	built_at = get_turf(C)
	var/datum/component/construction/K = C.GetComponent(/datum/component/construction)
	if(!K)
		return GOAL_STEP_FAIL
	var/datum/component/construction/unordered/parts = K
	// Every step the chassis takes is progress: the brain's cap on fetches for one errand (fifteen, suspend_goal_for()) is for an
	// errand going round in circles, and a Ripley takes about thirty honest ones.
	var/progress = istype(parts) ? 10 - length(parts.steps) : 10 + K.index
	if(progress > best_progress)
		best_progress = progress
		bot.goal_suspend_count = 0
	// The parts, in any order.
	if(istype(parts))
		for(var/part_type in parts.steps)
			var/obj/item/I = bot.find_carried_tool(part_type)
			if(I)
				return use(bot, I, C)
		for(var/part_type in parts.steps)
			var/obj/item/I = bot.mech_part_lying(part_type)
			if(I)
				return fetch(bot, new /datum/bot_goal/take_item/exact(I))
		return print_at_fab(bot, F, GLOB.bot_ripley_part_designs[parts.steps[1]])
	// Then whatever the chassis says it wants next.
	var/list/step_now = K.steps[K.index]
	var/key = step_now["key"]
	var/amount = step_now["amount"] || 1
	if(istext(key))
		var/tool_type = GLOB.bot_tool_for_behaviour[key]
		if(!tool_type)
			bot_log(bot, "RIPLEY: don't know a tool for [key]")
			return GOAL_STEP_FAIL
		var/obj/item/T = bot.find_or_transform_tool(tool_type)
		if(!T)
			return fetch(bot, new /datum/bot_goal/acquire_tool(tool_type))
		var/obj/item/weldingtool/W = T
		if(istype(W))
			if(!W.get_fuel())
				bot_log(bot, "RIPLEY: the welder's dry")
				return GOAL_STEP_FAIL
			bot.equip_welding_eye_protection()
			if(!W.isOn())
				bot.toggle_in_hand(W)
		return use(bot, T, C)
	if(!ispath(key))
		return GOAL_STEP_FAIL
	var/obj/item/have = bot.find_carried_tool(key)
	var/obj/item/stack/have_stack = have
	if(have && (!istype(have_stack) || have_stack.get_amount() >= amount))
		return use(bot, have, C)
	var/obj/item/lying = bot.mech_part_lying(key, printed_at, amount)
	if(lying)
		return fetch(bot, new /datum/bot_goal/take_item/exact(lying))
	// Rods: made from metal, a sheet for two (the metal's own recipes).
	if(ispath(key, /obj/item/stack/rods))
		return make_rods(bot, amount)
	// A board or a part: printed at a lathe it can get to.
	var/id = GLOB.bot_mech_step_designs[key]
	if(!id)
		for(var/path in GLOB.bot_mech_step_designs)
			if(ispath(key, path))
				id = GLOB.bot_mech_step_designs[path]
				break
	if(id)
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		var/obj/machinery/rnd/production/L = D && SSresearch.science_tech.researched_designs[id] ? bot.lathe_for(D) : null
		if(L)
			printed_at = L
			return fetch(bot, new /datum/bot_goal/print_design/for_mech(L, D, 1))
	// Anything else (cable, metal): wherever it knows of one.
	var/datum/bot_goal/acquire_item_type/A = new
	A.item_type = key
	A.lawful = TRUE
	return fetch(bot, A)

/// Metal into rods: the sheet in hand, its "metal rod" recipe, as many as it takes.
/datum/bot_step/work_on_ripley/proc/make_rods(datum/bot_brain/bot, amount)
	var/obj/item/stack/sheet/metal/M = bot.find_carried_tool(/obj/item/stack/sheet/metal)
	var/sheets = CEILING(amount / 2, 1)
	if(!M || M.get_amount() < sheets)
		var/obj/item/stack/sheet/metal/loose = bot.mech_part_lying(/obj/item/stack/sheet/metal, null, sheets)
		if(loose)
			return fetch(bot, new /datum/bot_goal/take_item/exact(loose))
		bot_log(bot, "RIPLEY: no metal for rods")
		return GOAL_STEP_FAIL
	var/index = 0
	for(var/i in 1 to length(M.recipes))
		var/datum/stack_recipe/R = M.recipes[i]
		if(istype(R) && ispath(R.result_type, /obj/item/stack/rods))
			index = i
			break
	if(!index || !bot.ready_in_hand(M))
		return GOAL_STEP_FAIL
	bot.human_pause(M)
	usr = bot.owner
	bot.telemetry_ui_action(M, "make metal rods")
	M.Topic(null, list("make" = "[index]", "multiplier" = "[sheets]"))
	bot_log(bot, "RIPLEY: made rods out of [sheets] sheets of metal")
	return again(bot)

/// A board or a part for the mech, printed, with nothing chained on after.
/datum/bot_goal/print_design/for_mech
	doing = "printing a part for the Ripley"
	chain_duty = null

/datum/bot_goal/print_design/for_mech/on_success(datum/bot_brain/bot)
	return

/datum/bot_goal/print_design/for_mech/on_give_up(datum/bot_brain/bot)
	return

#undef BOT_RIPLEY_REST
#undef BOT_RIPLEY_AFTER
