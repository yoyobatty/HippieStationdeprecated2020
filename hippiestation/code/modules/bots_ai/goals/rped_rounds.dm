// The RPED beyond the machines (the user's rulings, 2026-11-08; the RPED's side is research/rped_targets.dm):
//  - engineers put better cells in the APCs: ID swipe, the cover unlocked on its panel, crowbar, RPED, crowbar, ID swipe. Only while the
//    APC has grid power: lathes print cells empty, and an APC on the grid charges its own, where one on its battery would go dark.
//  - roboticists charge a cell in a cell charger first, then swap it into a cyborg (cover unlocked with an ID, crowbar, RPED) or an
//    exosuit parked in Robotics, along with its scanning module and capacitor (in, maintenance permitted from the seat, out; ID for
//    the protocols; RPED; the protocols back off and the permission taken back).
//  - Cargo restocks vending machines that are running low: the vendor's refill crate ordered, its canisters carried round.

/// APCs in one engineer's round at most.
#define BOT_APC_ROUND 6
/// APC main_status for "the grid's powering it" (apc.dm's APC_HAS_POWER is its own define).
#define BOT_APC_ON_GRID 2

/// The best cell design researched, if any.
/proc/bot_best_cell_design()
	for(var/id in GLOB.bot_part_designs[/obj/item/stock_parts/cell])
		var/datum/design/D = bot_researched_design(id)
		if(D)
			return D

/// Whether a design can be printed on this fabricator, its research synced as anybody does before printing.
/datum/bot_brain/proc/fab_can_print(obj/machinery/rnd/production/fab, datum/design/D)
	if(!D || !(D.build_type & fab.allowed_buildtypes) || !(isnull(fab.allowed_department_flags) || (D.departmental_flags & fab.allowed_department_flags)))
		return FALSE
	if(!fab.requires_console && !fab.stored_research.researched_designs[D.id] && SSresearch.science_tech.researched_designs[D.id])
		telemetry_ui_action(fab, "sync")
		fab.update_research()
	return TRUE

/// A print for one of these duties, which it goes back to when done.
/datum/bot_brain/proc/print_for_duty(obj/machinery/rnd/production/fab, datum/design/D, amount, duty_type)
	var/list/short = list()
	if(!bot_lathe_can_afford(fab, D, amount, short))
		if(amount > 1 && bot_lathe_can_afford(fab, D, 1))
			amount = 1
		else
			ask_for_materials(short)
			return FALSE
	var/datum/bot_goal/print_design/G = new(fab, D, amount)
	G.chain_duty = duty_type
	return assign_goal(G)

/// How many cells the RPED holds that rate at least this.
/proc/bot_rped_cells_at(obj/item/storage/part_replacer/rped, value)
	. = 0
	for(var/obj/item/stock_parts/cell/C in rped)
		if(C.get_part_rating() >= value)
			.++

// ---------------------------------------------------------------------------------------------
// Engineers: APC cells
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	/// The APCs this round's cells are for.
	var/list/apc_round
	var/apc_round_fitting = FALSE
	var/apc_blocked_until = 0

/// Whether the grid is powering it right now. The Bot Gym's has no grid, so its APC says so itself.
/obj/machinery/power/apc/proc/bot_on_grid()
	return main_status == BOT_APC_ON_GRID

/// Whether this APC would take a cell rating `value`, and this bot could do it.
/datum/bot_brain/proc/apc_wants_cell(obj/machinery/power/apc/A, value)
	if(QDELETED(A) || A.z != owner.z || (A.stat & (BROKEN|MAINT)) || A.opened || A.panel_open || (A.obj_flags & EMAGGED) || A.malfhack)
		return FALSE
	if(!A.cell || A.cell.get_part_rating() >= value || !A.bot_on_grid() || !A.allowed(owner))
		return FALSE
	if(gym_run && get_area(A) != get_area(owner))
		return FALSE
	return !taken_by_another(A) && LAZYACCESS(upgrade_blocked, A) <= world.time

/// The nearest APCs that want a better cell, BOT_APC_ROUND at most, each one this bot can lawfully walk to.
/datum/bot_brain/proc/plan_apc_round(value)
	var/list/dists = list()
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(apc_wants_cell(A, value))
			dists[A] = get_dist(owner, A)
	. = list()
	for(var/obj/machinery/power/apc/A as anything in sortTim(dists, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE))
		if(length(.) >= BOT_APC_ROUND)
			break
		if(!gym_run && !can_walk_lawfully_to(A))
			LAZYSET(upgrade_blocked, A, world.time + 15 MINUTES)
			continue
		. += A

/datum/bot_duty/apc_cells
	name = "putting better cells in the APCs"
	jobs = list("Station Engineer", "Chief Engineer")
	interval_min = 900
	interval_max = 2400

/datum/bot_duty/apc_cells/applies_to(datum/bot_brain/bot)
	return ..() && bot.diligence >= 0.5

/datum/bot_duty/apc_cells/try_start(datum/bot_brain/bot)
	if(world.time < bot.apc_blocked_until || world.time < bot.rnd_bench_blocked_until)
		return FALSE
	var/obj/machinery/rnd/production/fab = bot.department_fabricator()
	if(!fab || fab.busy || bot.department_rped_in_use())
		return FALSE
	// The best cell its own lathe makes: Engineering's can't make a bluespace one (Science's department flag only), and every engineer
	// in a batch of six shifts gave up for want of one
	var/datum/design/D
	for(var/id in GLOB.bot_part_designs[/obj/item/stock_parts/cell])
		var/datum/design/candidate = bot_researched_design(id)
		if(candidate && bot.fab_can_print(fab, candidate))
			D = candidate
			break
	if(!D)
		bot_log_verbose(bot, "APC cells: [fab] makes no cell that's been researched")
		bot.apc_blocked_until = world.time + 10 MINUTES
		return FALSE
	var/value = bot_design_rating(D)
	for(var/obj/machinery/power/apc/A as anything in bot.apc_round)
		if(!bot.apc_wants_cell(A, value))
			bot.apc_round -= A
	if(!length(bot.apc_round))
		bot.apc_round = bot.plan_apc_round(value)
		bot.apc_round_fitting = FALSE
		if(!length(bot.apc_round))
			bot_log_verbose(bot, "APC cells: no APC wants a [D.name]")
			for(var/obj/machinery/power/apc/A in get_area(bot.owner))
				bot_log_verbose(bot, "  [A]: cell [A.cell] ([A.cell?.get_part_rating()] vs [value]), grid [A.bot_on_grid()], stat [A.stat], opened [A.opened], allowed [A.allowed(bot.owner)]")
			bot.apc_round = null
			bot.apc_blocked_until = world.time + 10 MINUTES
			return FALSE
		bot_log(bot, "APC round: [english_list(bot.apc_round)]")
	var/obj/item/storage/part_replacer/rped = bot.find_rped() || (locate(/obj/item/storage/part_replacer) in get_turf(fab))
	if(!rped)
		var/datum/design/R = bot_researched_design("rped")
		if(!bot.fab_can_print(fab, R))
			return FALSE
		return bot.print_for_duty(fab, R, 1, type)
	if(bot_parts_to_collect(fab))
		var/datum/bot_goal/collect_prints/collect = new(fab)
		collect.chain_duty = type
		return bot.assign_goal(collect)
	if(!bot.apc_round_fitting)
		var/need = length(bot.apc_round) - bot_rped_cells_at(rped, value)
		if(need > 0 && bot_rped_room(rped) > 0)
			if(bot.print_for_duty(fab, D, min(need, bot_rped_room(rped)), type))
				return TRUE
		bot.apc_round_fitting = TRUE
	var/obj/machinery/power/apc/next
	var/best_dist
	for(var/obj/machinery/power/apc/A as anything in bot.apc_round)
		if(!rped.best_part_over(/obj/item/stock_parts/cell, A.cell))
			continue
		var/dist = get_dist(bot.owner, A)
		if(!next || dist < best_dist)
			next = A
			best_dist = dist
	if(!next)
		bot.apc_round = null
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/apc_cell(next))

/datum/bot_goal/apc_cell
	lawful = TRUE
	exclusive = TRUE
	doing = "putting a better cell in an APC"

/datum/bot_goal/apc_cell/New(obj/machinery/power/apc/A)
	. = ..()
	target = A

/datum/bot_goal/apc_cell/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/apc_cell/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/take_rped(), new /datum/bot_step/take_tool/crowbar(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/apc_cell())
	return list(S)

/datum/bot_goal/apc_cell/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/apc_cells), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/apc_cell/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.upgrade_blocked, target, world.time + 5 MINUTES) // often a lathe fire under it: unreachable ones are left out when the round's planned
		bot.apc_round -= target

/// A tool of a kind on the bot, fetched if it hasn't one.
/datum/bot_step/take_tool
	var/tool_type
	var/tried = FALSE

/datum/bot_step/take_tool/crowbar
	tool_type = /obj/item/crowbar

/datum/bot_step/take_tool/execute(datum/bot_brain/bot)
	if(bot.find_carried_tool(tool_type))
		return GOAL_STEP_SUCCESS
	if(tried)
		return GOAL_STEP_FAIL
	tried = TRUE
	var/datum/bot_goal/acquire_item_type/fetch = new()
	fetch.item_type = tool_type
	fetch.lawful = TRUE
	return bot.suspend_goal_for(fetch) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// The player's clicks, one a beat: ID (interface unlocked), the panel's cover lock, crowbar (open), RPED, crowbar (shut: the cover locks
/// itself again), ID (interface locked).
/datum/bot_step/paced/apc_cell
	max_clicks = 12
	/// Done at the cell, one way or the other: what's left is shutting up.
	var/swapped = FALSE
	/// A better cell went in.
	var/fitted = FALSE

/datum/bot_step/paced/apc_cell/start(datum/bot_brain/bot)
	swapped = FALSE
	fitted = FALSE
	return TRUE

/datum/bot_step/paced/apc_cell/do_click(datum/bot_brain/bot)
	var/obj/machinery/power/apc/A = bot.current_goal?.target
	if(!istype(A) || QDELETED(A) || !bot.owner.Adjacent(A))
		return FALSE
	var/obj/item/crowbar/bar = bot.find_carried_tool(/obj/item/crowbar)
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!bar || !rped)
		return FALSE
	bot.owner.face_atom(A)
	if(A.opened)
		if(!swapped)
			if(!A.bot_on_grid())
				bot_log(bot, "[A] is off the grid now: leaving its cell be")
				swapped = TRUE // nothing more to do but shut it
				return TRUE
			var/obj/item/stock_parts/cell/old = A.cell
			bot.telemetry_ui_action(A, "swap cell")
			bot.use_tool_on(rped, A)
			if(A.cell == old)
				bot_log(bot, "[rped] didn't swap [A]'s cell")
				return FALSE
			bot.machines_upgraded++
			bot_log(bot, "swapped [old] for [A.cell] in [A]")
			swapped = TRUE
			fitted = TRUE
			return TRUE
		bot.use_tool_on(bar, A)
		return !A.opened
	if(!swapped)
		if(A.locked)
			usr = bot.owner
			bot.telemetry_ui_action(A, "swipe ID")
			A.togglelock(bot.owner)
			return !A.locked
		if(A.coverlocked)
			bot.telemetry_ui_action(A, "cover lock off")
			A.coverlocked = FALSE
			return TRUE
		bot.use_tool_on(bar, A)
		return A.opened
	if(!A.locked)
		usr = bot.owner
		bot.telemetry_ui_action(A, "swipe ID")
		A.togglelock(bot.owner)
	return FALSE

/datum/bot_step/paced/apc_cell/finish(datum/bot_brain/bot)
	var/obj/machinery/power/apc/A = bot.current_goal?.target
	var/obj/item/crowbar/bar = bot.find_carried_tool(/obj/item/crowbar)
	// Never left open: a cover off is a cell anybody can walk off with
	if(istype(A) && !QDELETED(A) && A.opened && bar && bot.owner.Adjacent(A))
		bot.use_tool_on(bar, A)
	return fitted ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Roboticists: cyborgs and exosuits
// ---------------------------------------------------------------------------------------------

/// A cell charged enough to go in a cyborg or an exosuit, as a fraction.
#define BOT_CELL_CHARGED 0.9
/// How long a cyborg has to stand in Robotics before it's taken to be there for the roboticist.
#define BOT_BORG_STILL (8 SECONDS)

/datum/bot_brain
	/// Cyborgs seen in Robotics: borg -> list(turf, since when)
	var/list/borgs_seen
	var/robotics_cells_blocked_until = 0

/// What an RPED would take out of it: its cell's rating, 0 for none.
/proc/bot_cell_value(obj/item/stock_parts/cell/C)
	return C ? C.get_part_rating() : 0

/// A cyborg stood in Robotics a while, or an empty exosuit parked there with no DNA lock, that a cell rated `value` would beat or the RPED
/// carries a better scanning module or capacitor for.
/datum/bot_brain/proc/robotics_cell_target(value, obj/item/storage/part_replacer/rped)
	var/list/still = list()
	for(var/mob/living/silicon/robot/R as anything in GLOB.silicon_mobs)
		if(!istype(R) || QDELETED(R) || R.stat == DEAD || R.z != owner.z || !in_robotics(R) || R.opened || !R.allowed(owner))
			continue
		still += R
		var/list/seen = LAZYACCESS(borgs_seen, R)
		if(!seen || seen[1] != get_turf(R))
			LAZYSET(borgs_seen, R, list(get_turf(R), world.time))
			continue
		if(world.time - seen[2] >= BOT_BORG_STILL && bot_cell_value(R.cell) < value && !taken_by_another(R) && LAZYACCESS(upgrade_blocked, R) <= world.time)
			return R
	for(var/mob/living/silicon/robot/gone as anything in borgs_seen)
		if(!(gone in still))
			borgs_seen -= gone
	for(var/obj/mecha/M as anything in bot_instances_of(/obj/mecha))
		if(QDELETED(M) || M.occupant || M.dna_lock || M.z != owner.z || !in_robotics(M) || taken_by_another(M) || LAZYACCESS(upgrade_blocked, M) > world.time)
			continue
		if(!M.operation_allowed(owner) || !M.internals_access_allowed(owner))
			continue
		if(bot_cell_value(M.cell) < value)
			return M
		if(rped && (rped.best_part_over(/obj/item/stock_parts/scanning_module, M.rped_scanmod) || rped.best_part_over(/obj/item/stock_parts/capacitor, M.rped_capacitor)))
			return M

/// The cell in it now.
/proc/bot_target_cell(atom/A)
	var/mob/living/silicon/robot/R = A
	if(istype(R))
		return R.cell
	var/obj/mecha/M = A
	return istype(M) ? M.cell : null

/// A powered cell charger in Robotics (or else the rest of Science), with nothing in it unless `holding`.
/datum/bot_brain/proc/find_cell_charger(holding = FALSE)
	var/obj/machinery/cell_charger/best
	for(var/obj/machinery/cell_charger/C as anything in bot_instances_of(/obj/machinery/cell_charger))
		if(QDELETED(C) || C.z != owner.z || C.panel_open || !C.anchored || (C.stat & (BROKEN|NOPOWER)) || (!holding && C.charging) || !in_science(C))
			continue
		if(in_robotics(C))
			return C
		best = best || C
	return best

/// A printed cell rated over `over` that isn't charged yet: in the RPED, or lying in Robotics.
/datum/bot_brain/proc/flat_cell_over(over, obj/item/storage/part_replacer/rped)
	for(var/obj/item/stock_parts/cell/C in rped)
		if(C.get_part_rating() > over && C.charge < C.maxcharge * BOT_CELL_CHARGED)
			return C
	for(var/obj/item/stock_parts/cell/C as anything in bot_instances_of(/obj/item/stock_parts/cell))
		if(!QDELETED(C) && isturf(C.loc) && C.z == owner.z && in_robotics(C) && C.get_part_rating() > over && !taken_by_another(C))
			return C

/datum/bot_duty/robotics_cells
	name = "better cells for the cyborgs and exosuits"
	jobs = list("Roboticist")
	interval_min = 200
	interval_max = 600

/datum/bot_duty/robotics_cells/applies_to(datum/bot_brain/bot)
	return ..() && bot.diligence >= 0.4

/datum/bot_duty/robotics_cells/try_start(datum/bot_brain/bot)
	if(world.time < bot.robotics_cells_blocked_until)
		return FALSE
	var/datum/design/D = bot_best_cell_design()
	if(!D)
		return FALSE
	var/value = bot_design_rating(D)
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	var/atom/target = bot.robotics_cell_target(value, rped)
	if(!target)
		if(bot.gym_run)
			for(var/mob/living/silicon/robot/R in get_area(bot.owner))
				bot_log_verbose(bot, "robotics cells: [R] not yet: cell [bot_cell_value(R.cell)] vs [value], seen [json_encode(LAZYACCESS(bot.borgs_seen, R))], listed [(R in GLOB.silicon_mobs)], allowed [R.allowed(bot.owner)], stat [R.stat]")
		return FALSE
	if(!rped || bot.rped_in_use_by_another())
		bot_log_verbose(bot, "robotics cells: no RPED to be had for [target]")
		return FALSE
	var/over = bot_cell_value(bot_target_cell(target))
	// A charged one in the RPED that beats what's in: off to it (or the exosuit's other parts, with a cell no better than its own)
	var/obj/item/stock_parts/cell/charged = rped.best_part_over(/obj/item/stock_parts/cell, bot_target_cell(target), BOT_CELL_CHARGED)
	if(charged || (istype(target, /obj/mecha) && over >= value))
		return bot.assign_goal(new /datum/bot_goal/fit_robotics_cell(target))
	// One in a charger: taken out when it's charged, waited on until then
	for(var/obj/machinery/cell_charger/C as anything in bot_instances_of(/obj/machinery/cell_charger))
		if(QDELETED(C) || !C.charging || C.z != bot.owner.z || !bot.in_science(C) || C.charging.get_part_rating() <= over)
			continue
		if(C.charging.percent() >= BOT_CELL_CHARGED * 100)
			return bot.assign_goal(new /datum/bot_goal/take_charged_cell(C))
		bot.robotics_cells_blocked_until = world.time + 15 SECONDS
		return FALSE
	// One printed and not charged: into the charger
	var/obj/item/stock_parts/cell/flat = bot.flat_cell_over(over, rped)
	var/obj/machinery/cell_charger/charger = bot.find_cell_charger()
	if(flat)
		if(!charger)
			bot_log_verbose(bot, "robotics cells: no cell charger free for [flat]")
			bot.robotics_cells_blocked_until = world.time + 1 MINUTES
			return FALSE
		return bot.assign_goal(new /datum/bot_goal/charge_cell(flat, charger))
	// None at all: one printed at the exosuit fabricator
	var/obj/machinery/mecha_part_fabricator/F = bot.find_exofab()
	if(!F || !charger)
		bot_log_verbose(bot, "robotics cells: [F ? "no cell charger" : "no exosuit fabricator"] for a [D.name]")
		bot.robotics_cells_blocked_until = world.time + 2 MINUTES
		return FALSE
	if(!F.stored_research.researched_designs[D.id])
		// Its Sync button: it copies from an R&D console in sight, after a few seconds (mech_fabricator.dm sync())
		bot.telemetry_ui_action(F, "sync with R&D servers")
		INVOKE_ASYNC(F, TYPE_PROC_REF(/obj/machinery/mecha_part_fabricator, sync))
		bot.robotics_cells_blocked_until = world.time + 5 SECONDS
		return FALSE
	if(!F.stored_research.researched_designs[D.id] || !F.check_resources(D))
		bot_log_verbose(bot, "robotics cells: [F] can't make a [D.name] just now")
		bot.robotics_cells_blocked_until = world.time + 2 MINUTES
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/exofab_print(F, D))

/// One design at the exosuit fabricator, watched until it's out.
/datum/bot_goal/exofab_print
	lawful = TRUE
	exclusive = TRUE
	doing = "printing at the exosuit fabricator"
	var/datum/design/design

/datum/bot_goal/exofab_print/New(obj/machinery/mecha_part_fabricator/F, datum/design/D)
	. = ..()
	target = F
	design = D

/datum/bot_goal/exofab_print/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/exofab_print())
	return list(S)

/datum/bot_goal/exofab_print/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/robotics_cells), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/exofab_print/on_give_up(datum/bot_brain/bot)
	bot.robotics_cells_blocked_until = world.time + 2 MINUTES

/datum/bot_step/paced/exofab_print
	max_clicks = 120
	var/started = FALSE
	var/waited = 0

/datum/bot_step/paced/exofab_print/start(datum/bot_brain/bot)
	started = FALSE
	waited = 0
	return TRUE

/datum/bot_step/paced/exofab_print/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/exofab_print/G = bot.current_goal
	var/obj/machinery/mecha_part_fabricator/F = G?.target
	if(!istype(G) || !istype(F) || QDELETED(F) || (F.stat & (BROKEN|NOPOWER)))
		return FALSE
	if(started)
		if(!F.being_built)
			return FALSE // out: on the floor in front of it
		waited += 10
		wait_for = 10
		return waited < 900
	if(F.being_built || !bot.owner.Adjacent(F) || !F.check_resources(G.design))
		return FALSE
	bot.human_pause(F)
	if(QDELETED(F) || F.being_built)
		return FALSE
	bot.owner.face_atom(F)
	bot.telemetry_ui_action(F, "build [G.design.name]")
	bot_log(bot, "printing a [lowertext(G.design.name)] at [F]")
	INVOKE_ASYNC(F, TYPE_PROC_REF(/obj/machinery/mecha_part_fabricator, build_part), G.design)
	started = TRUE
	wait_for = 10
	return TRUE

/datum/bot_step/paced/exofab_print/finish(datum/bot_brain/bot)
	return started ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// A flat cell into a cell charger: out of the RPED (or up off the floor) into a hand, and a click on the charger.
/datum/bot_goal/charge_cell
	lawful = TRUE
	exclusive = TRUE
	doing = "charging a cell"
	var/obj/item/stock_parts/cell/cell

/datum/bot_goal/charge_cell/New(obj/item/stock_parts/cell/C, obj/machinery/cell_charger/charger)
	. = ..()
	cell = C
	target = charger

/datum/bot_goal/charge_cell/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/cell_charger/C = target
	if(QDELETED(cell) || QDELETED(C) || C.charging)
		target = null

/datum/bot_goal/charge_cell/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/charge_cell())
	return list(S)

/datum/bot_goal/charge_cell/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/robotics_cells), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/charge_cell/on_give_up(datum/bot_brain/bot)
	bot.robotics_cells_blocked_until = world.time + 2 MINUTES

/datum/bot_step/charge_cell
	var/legs = 0

/datum/bot_step/charge_cell/execute(datum/bot_brain/bot)
	var/datum/bot_goal/charge_cell/G = bot.current_goal
	var/obj/machinery/cell_charger/C = G?.target
	if(!istype(G) || !istype(C) || QDELETED(C) || QDELETED(G.cell) || ++legs > 6)
		return GOAL_STEP_FAIL
	if(isturf(G.cell.loc))
		return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(G.cell)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	if(istype(G.cell.loc, /obj/item/storage/part_replacer))
		var/obj/item/storage/part_replacer/R = G.cell.loc
		bot.human_pause(R)
		if(!SEND_SIGNAL(R, COMSIG_TRY_STORAGE_TAKE, G.cell, bot.owner.drop_location()) || !bot.owner.put_in_hands(G.cell))
			return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(C))
		return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(C)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	if(!bot.ready_in_hand(G.cell))
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	bot.use_tool_on(G.cell, C)
	if(C.charging != G.cell)
		return GOAL_STEP_FAIL
	bot_log(bot, "put [G.cell] on to charge in [C]")
	return GOAL_STEP_SUCCESS

/// A charged cell out of the charger by hand, and into the RPED.
/datum/bot_goal/take_charged_cell
	lawful = TRUE
	exclusive = TRUE
	doing = "taking a charged cell out of the charger"

/datum/bot_goal/take_charged_cell/New(obj/machinery/cell_charger/C)
	. = ..()
	target = C

/datum/bot_goal/take_charged_cell/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/take_rped(), new /datum/bot_step/move_to(), new /datum/bot_step/take_charged_cell())
	return list(S)

/datum/bot_goal/take_charged_cell/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/robotics_cells), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/take_charged_cell/on_give_up(datum/bot_brain/bot)
	bot.robotics_cells_blocked_until = world.time + 1 MINUTES

/datum/bot_step/take_charged_cell/execute(datum/bot_brain/bot)
	var/obj/machinery/cell_charger/C = bot.current_goal?.target
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!istype(C) || QDELETED(C) || !C.charging || !rped || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	var/obj/item/stock_parts/cell/cell = C.charging
	// A hand free for it: the RPED stays in the other
	for(var/obj/item/held in bot.owner.held_items)
		if(held != rped && length(bot.owner.held_items) - length(bot.owner.get_empty_held_indexes()) >= 2)
			bot.stow_item(held)
	bot.human_pause(C)
	if(rped in bot.owner.held_items)
		var/obj/item/active = bot.owner.get_active_held_item()
		if(active == rped)
			bot.owner.swap_hand()
	C.attack_hand(bot.owner)
	if(!(cell in bot.owner.held_items))
		return GOAL_STEP_FAIL
	SEND_SIGNAL(rped, COMSIG_TRY_STORAGE_INSERT, cell, bot.owner, TRUE, TRUE)
	bot_log(bot, "took [cell] off charge ([round(cell.percent())]%)")
	return GOAL_STEP_SUCCESS

/// The cell (and, for an exosuit, its scanning module and capacitor) swapped with the RPED, the way the thing is opened up.
/datum/bot_goal/fit_robotics_cell
	lawful = TRUE
	exclusive = TRUE
	doing = "fitting a better cell"

/datum/bot_goal/fit_robotics_cell/New(atom/A)
	. = ..()
	target = A

/datum/bot_goal/fit_robotics_cell/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !bot.in_robotics(target))
		target = null

/datum/bot_goal/fit_robotics_cell/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	var/list/steps = list(new /datum/bot_step/take_rped())
	if(istype(target, /mob/living/silicon/robot))
		steps += new /datum/bot_step/take_tool/crowbar()
	steps += new /datum/bot_step/move_to()
	steps += istype(target, /obj/mecha) ? new /datum/bot_step/paced/fit_mecha() : new /datum/bot_step/paced/fit_cyborg()
	S.steps = steps
	return list(S)

/datum/bot_goal/fit_robotics_cell/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.upgrade_blocked, target, world.time + 10 MINUTES)

/// ID (cover unlocked), crowbar (open), RPED, crowbar (shut), ID (locked).
/datum/bot_step/paced/fit_cyborg
	max_clicks = 12
	var/swapped = FALSE
	var/fitted = FALSE

/datum/bot_step/paced/fit_cyborg/start(datum/bot_brain/bot)
	swapped = FALSE
	fitted = FALSE
	return TRUE

/datum/bot_step/paced/fit_cyborg/do_click(datum/bot_brain/bot)
	var/mob/living/silicon/robot/R = bot.current_goal?.target
	var/obj/item/crowbar/bar = bot.find_carried_tool(/obj/item/crowbar)
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!istype(R) || QDELETED(R) || !bot.owner.Adjacent(R) || !bar || !rped)
		return FALSE
	bot.owner.face_atom(R)
	if(R.opened)
		if(!swapped)
			var/obj/item/stock_parts/cell/old = R.cell
			bot.telemetry_ui_action(R, "swap cell")
			bot.use_tool_on(rped, R)
			swapped = TRUE
			if(R.cell != old)
				fitted = TRUE
				bot.machines_upgraded++
				bot_log(bot, "swapped [old || "no cell"] for [R.cell] in [R]")
			return TRUE
		bot.use_tool_on(bar, R)
		return !R.opened
	if(!swapped)
		if(R.locked)
			if(!bot.gym_scripted)
				bot.say_after_typing(pick("Hold still, [R.name], new cell going in.", "Stay put a second, I've got a better cell for you.", "Better cell for you, [R.name]. Don't move."))
			usr = bot.owner
			bot.telemetry_ui_action(R, "swipe ID")
			if(R.allowed(bot.owner))
				R.locked = FALSE
				R.update_icons()
			return !R.locked
		bot.use_tool_on(bar, R)
		return R.opened
	if(!R.locked)
		bot.telemetry_ui_action(R, "swipe ID")
		R.locked = TRUE
		R.update_icons()
	return FALSE

/datum/bot_step/paced/fit_cyborg/finish(datum/bot_brain/bot)
	var/mob/living/silicon/robot/R = bot.current_goal?.target
	var/obj/item/crowbar/bar = bot.find_carried_tool(/obj/item/crowbar)
	if(istype(R) && !QDELETED(R) && R.opened && bar && bot.owner.Adjacent(R))
		bot.use_tool_on(bar, R)
	if(istype(R) && !QDELETED(R) && !R.locked && !R.opened && bot.owner.Adjacent(R))
		R.locked = TRUE
		R.update_icons()
	return fitted ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// tg's moved_inside() wants a client, and a bot crew member has none: it sits in all the same (the same body, mecha.dm, without the
/// client's mouse pointer). Before this no bot could get into an exosuit at all.
/obj/mecha/moved_inside(mob/living/carbon/human/H)
	if(!H || H.client || !H.bot_brain)
		return ..()
	if(!(H in range(1, src)))
		return 0
	occupant = H
	H.forceMove(src)
	add_fingerprint(H)
	GrantActions(H, human_occupant = 1)
	forceMove(loc)
	log_message("[H] moved in as pilot.", LOG_MECHA)
	icon_state = initial(icon_state)
	setDir(dir_in)
	playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
	return 1

/// An empty exosuit: in, maintenance protocols permitted from the seat, out; ID for the protocols; RPED; protocols off; in again to take
/// the permission back, out. The user's ruling (2026-11-08): a pilot has to permit them, so the roboticist sits in to do it.
/datum/bot_step/paced/fit_mecha
	max_clicks = 30
	var/permitted_here = FALSE
	var/fitted = FALSE
	var/swapped = FALSE

/datum/bot_step/paced/fit_mecha/start(datum/bot_brain/bot)
	permitted_here = FALSE
	fitted = FALSE
	swapped = FALSE
	return TRUE

/datum/bot_step/paced/fit_mecha/proc/climb_in(datum/bot_brain/bot, obj/mecha/M)
	bot.telemetry_ui_action(M, "climb in")
	M.MouseDrop_T(bot.owner, bot.owner) // do_after: the climb takes a few seconds
	if(M.occupant != bot.owner)
		bot_log(bot, "couldn't climb into [M] (beside it [bot.owner.Adjacent(M)], incapacitated [bot.owner.incapacitated()], occupant [M.occupant || "none"])")
		return FALSE
	return TRUE

/datum/bot_step/paced/fit_mecha/do_click(datum/bot_brain/bot)
	var/obj/mecha/M = bot.current_goal?.target
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!istype(M) || QDELETED(M) || !rped)
		return FALSE
	var/inside = M.occupant == bot.owner
	if(!inside && (M.occupant || !bot.owner.Adjacent(M)))
		return FALSE
	if(!swapped)
		if(!M.maint_access)
			if(!inside)
				return climb_in(bot, M)
			bot.telemetry_ui_action(M, "permit maintenance protocols")
			M.maint_access = TRUE
			permitted_here = TRUE
			return TRUE
		if(inside)
			M.go_out()
			return TRUE
		if(!M.state)
			bot.telemetry_ui_action(M, "initiate maintenance protocol")
			if(!M.internals_access_allowed(bot.owner))
				return FALSE
			M.state = 1
			return TRUE
		var/old_cell = M.cell
		var/old_scan = M.rped_scanmod
		var/old_cap = M.rped_capacitor
		bot.telemetry_ui_action(M, "swap parts")
		bot.use_tool_on(rped, M)
		swapped = TRUE
		if(M.cell != old_cell || M.rped_scanmod != old_scan || M.rped_capacitor != old_cap)
			fitted = TRUE
			bot.machines_upgraded++
			bot_log(bot, "upgraded [M]: [M.cell], [M.rped_scanmod || "no scanning module"], [M.rped_capacitor || "no capacitor"]")
		return TRUE
	if(M.state && !inside)
		bot.telemetry_ui_action(M, "terminate maintenance protocol")
		if(M.state == 1)
			M.state = 0
		return TRUE
	if(permitted_here)
		if(!inside)
			return climb_in(bot, M)
		bot.telemetry_ui_action(M, "forbid maintenance protocols")
		M.maint_access = FALSE
		permitted_here = FALSE
		return TRUE
	if(inside)
		M.go_out()
	return FALSE

/datum/bot_step/paced/fit_mecha/finish(datum/bot_brain/bot)
	var/obj/mecha/M = bot.current_goal?.target
	if(istype(M) && !QDELETED(M))
		if(M.occupant == bot.owner)
			M.go_out()
		if(M.state == 1)
			M.state = 0
	return fitted ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Cargo: vending machines restocked
// ---------------------------------------------------------------------------------------------

/// Stock below which a vendor is worth a refill, as a fraction of what it holds full.
#define BOT_VENDOR_LOW 0.25

/// Vendors somebody's said are nearly empty -> when. Cargo orders the refill crate and takes the canister round.
GLOBAL_LIST_EMPTY(bot_vendors_low)

/// How full a vendor is, of its ordinary stock.
/proc/bot_vendor_fullness(obj/machinery/vending/V)
	var/have = 0
	var/full = 0
	for(var/datum/data/vending_product/R in V.product_records)
		have += R.amount
		full += R.max_amount
	return full ? have / full : 1

/// The supply pack with this vendor's refill canister in, if Cargo sells one.
/proc/bot_vendor_refill_pack(obj/machinery/vending/V)
	if(!V.refill_canister)
		return null
	for(var/pack_type in SSshuttle.supply_packs)
		var/datum/supply_pack/P = SSshuttle.supply_packs[pack_type]
		if(!P.hidden && !P.contraband && !P.special && (V.refill_canister in P.contains))
			return pack_type

/datum/bot_request
	/// Asked for the crew, not for a bot's own errand: kept half an hour and ordered ahead of errands (orders.dm). A vendor nearly empty
	/// is (the user's ruling, 2026-11-08): as a bot's own ask it lost to the budget in all twelve shifts of two batches.
	var/crew_priority = FALSE

/// Bought from a vendor that's nearly out: Cargo told on the radio, the way anybody would. Said again a quarter of an hour on if it's
/// still empty: a bot's ask waits ten minutes for the budget, and in a batch of six shifts the one vendor reported never got its crate.
/datum/bot_brain/vend_from(obj/machinery/vending/V, product_path)
	. = ..()
	if(. && !QDELETED(V) && V.onstation && (!GLOB.bot_vendors_low[V] || world.time > GLOB.bot_vendors_low[V] + 15 MINUTES) && bot_vendor_fullness(V) < BOT_VENDOR_LOW)
		var/pack_type = bot_vendor_refill_pack(V)
		if(!pack_type || world.time < GLOB.bot_cargo_asked[pack_type])
			return
		GLOB.bot_vendors_low[V] = world.time
		GLOB.bot_cargo_asked[pack_type] = world.time + 10 MINUTES // bot_collabs.dm's BOT_CARGO_ASK_GAP
		var/datum/bot_request/R = new
		R.caller_ref = WEAKREF(owner)
		R.detail = pack_type
		R.made = world.time
		R.crew_priority = TRUE
		GLOB.bot_cargo_requests |= R
		bot_log(src, "told Cargo [V] is nearly empty")
		if(!gym_scripted && !is_cargo_job())
			say_after_typing(";[pick("Cargo, the [V.name] is nearly empty.", "[capitalize(V.name)]'s almost out, Cargo. Any chance of a refill?", "Could Cargo restock the [V.name]? It's nearly cleaned out.")]")

/// A refill canister for this vendor to hand: carried, lying in the bay, or in a crate there (opened or not).
/datum/bot_brain/proc/vendor_canister_for(obj/machinery/vending/V)
	var/obj/item/vending_refill/carried = locate(V.refill_canister) in owner
	if(carried && carried.get_part_rating())
		return carried
	var/area/bay = gym_run ? get_area(owner) : GLOB.areas_by_type[/area/quartermaster/storage]
	if(!bay)
		return null
	for(var/obj/item/vending_refill/C in bay)
		if(istype(C, V.refill_canister) && C.get_part_rating() && !taken_by_another(C) && isturf(C.loc))
			return C
	for(var/obj/structure/closet/crate/crate in bay)
		var/obj/item/vending_refill/C = locate(V.refill_canister) in crate
		if(C && C.get_part_rating() && !taken_by_another(crate))
			return C

/datum/bot_duty/restock_vendors
	name = "restocking the vending machines"
	jobs = list("Cargo Technician", "Quartermaster")
	interval_min = 300
	interval_max = 900

/datum/bot_duty/restock_vendors/try_start(datum/bot_brain/bot)
	for(var/obj/machinery/vending/V as anything in GLOB.bot_vendors_low)
		if(QDELETED(V) || bot_vendor_fullness(V) >= 0.5)
			GLOB.bot_vendors_low -= V
			continue
		if(V.z != bot.owner.z || bot.taken_by_another(V) || LAZYACCESS(bot.upgrade_blocked, V) > world.time || (bot.gym_run && get_area(V) != get_area(bot.owner)))
			continue
		var/obj/item/vending_refill/C = bot.vendor_canister_for(V)
		if(!C)
			continue
		if(!bot.gym_run && !bot.can_walk_lawfully_to(V))
			LAZYSET(bot.upgrade_blocked, V, world.time + 15 MINUTES)
			continue
		return bot.assign_goal(new /datum/bot_goal/restock_vendor(V, C))
	return FALSE

/datum/bot_goal/restock_vendor
	lawful = TRUE
	exclusive = TRUE
	doing = "restocking a vending machine"
	var/obj/item/vending_refill/canister

/datum/bot_goal/restock_vendor/New(obj/machinery/vending/V, obj/item/vending_refill/C)
	. = ..()
	target = V
	canister = C

/datum/bot_goal/restock_vendor/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || QDELETED(canister))
		target = null

/datum/bot_goal/restock_vendor/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cargo/S = new
	S.steps = list(new /datum/bot_step/fetch_canister(), new /datum/bot_step/take_screwdriver(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/restock_vendor())
	return list(S)

/datum/bot_goal/restock_vendor/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.upgrade_blocked, target, world.time + 10 MINUTES)

/// The canister into a hand: the crate it's in opened first.
/datum/bot_step/fetch_canister
	var/legs = 0

/datum/bot_step/fetch_canister/execute(datum/bot_brain/bot)
	var/datum/bot_goal/restock_vendor/G = bot.current_goal
	if(!istype(G) || QDELETED(G.canister) || ++legs > 6)
		return GOAL_STEP_FAIL
	if(G.canister in bot.owner.held_items)
		return GOAL_STEP_SUCCESS
	if(G.canister.loc == bot.owner || istype(G.canister.loc, /obj/item/storage))
		return bot.ready_in_hand(G.canister) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	var/obj/structure/closet/crate/crate = G.canister.loc
	if(istype(crate))
		if(!bot.owner.Adjacent(crate))
			return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(crate)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if(!crate.opened)
			bot.human_pause(crate)
			bot.telemetry_clicked(crate)
			crate.open(bot.owner)
			if(!crate.opened)
				return GOAL_STEP_FAIL
		// Open now: the canister's in it, to be taken out (take_item reaches into an open crate)
	return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(G.canister)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Screwdriver (service panel open), the canister, screwdriver (shut).
/datum/bot_step/paced/restock_vendor
	max_clicks = 8
	var/restocked = FALSE

/datum/bot_step/paced/restock_vendor/start(datum/bot_brain/bot)
	restocked = FALSE
	return TRUE

/datum/bot_step/paced/restock_vendor/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/restock_vendor/G = bot.current_goal
	var/obj/machinery/vending/V = G?.target
	var/obj/item/screwdriver/driver = bot.find_carried_tool(/obj/item/screwdriver)
	if(!istype(G) || !istype(V) || QDELETED(V) || !bot.owner.Adjacent(V) || !driver)
		return FALSE
	bot.owner.face_atom(V)
	if(restocked)
		if(V.panel_open)
			bot.use_tool_on(driver, V)
		return FALSE
	if(!V.panel_open)
		bot.use_tool_on(driver, V)
		return V.panel_open
	if(QDELETED(G.canister) || !bot.ready_in_hand(G.canister))
		return FALSE
	var/before = bot_vendor_fullness(V)
	bot.telemetry_ui_action(V, "restock")
	bot.use_tool_on(G.canister, V)
	restocked = TRUE
	if(bot_vendor_fullness(V) > before)
		GLOB.bot_vendors_low -= V
		bot_log(bot, "restocked [V]: [round(before * 100)]% -> [round(bot_vendor_fullness(V) * 100)]%")
	return TRUE

/datum/bot_step/paced/restock_vendor/finish(datum/bot_brain/bot)
	var/datum/bot_goal/restock_vendor/G = bot.current_goal
	var/obj/machinery/vending/V = G?.target
	var/obj/item/screwdriver/driver = bot.find_carried_tool(/obj/item/screwdriver)
	if(istype(V) && !QDELETED(V) && V.panel_open && driver && bot.owner.Adjacent(V))
		bot.use_tool_on(driver, V)
	// What's left of the canister goes with it: empty, it's rubbish
	if(istype(G) && !QDELETED(G.canister) && (G.canister in bot.owner.held_items))
		if(!G.canister.get_part_rating())
			bot.owner.dropItemToGround(G.canister)
		else
			bot.stow_item(G.canister)
	return (istype(V) && !(V in GLOB.bot_vendors_low)) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_VENDOR_LOW
#undef BOT_CELL_CHARGED
#undef BOT_BORG_STILL
#undef BOT_APC_ROUND
#undef BOT_APC_ON_GRID
