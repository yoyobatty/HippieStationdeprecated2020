// Cargo: a Cargo Technician or the Quartermaster runs the supply shuttle the way the department does.
//
//  - orders something the station can use at the supply console, when the budget allows and nothing
//    is already on order: the "add" button's own effect (cargo/console.dm ui_act()) - a
//    /datum/supply_order on SSshuttle.shoppinglist, signed for in the ledger
//  - calls the shuttle in once there's an order waiting for it, with the console's "send" button
//  - when it docks, hauls each crate off it into the cargo bay: grab it, pull it, let go
//  - sends the shuttle back once it's empty and nobody's aboard, ready for the next order
//
// What's in the crates stays in them: the bay is where departments come to collect.

/// The budget has to cover an order this many times over before cargo spends on it - the station's money isn't cargo's to empty.
#define BOT_CARGO_BUDGET_MARGIN 2
/// Between one order going in and the next being thought about.
#define BOT_CARGO_ORDER_GAP (8 MINUTES)

/// What cargo orders when nobody has asked for anything: things most shifts end up wanting.
GLOBAL_LIST_INIT(bot_cargo_staples, list(
	/datum/supply_pack/materials/metal50,
	/datum/supply_pack/materials/glass50,
	/datum/supply_pack/engineering/tools,
	/datum/supply_pack/emergency/internals,
	/datum/supply_pack/service/janitor,
	/datum/supply_pack/organic/food,
	/datum/supply_pack/medical/supplies,
))

/// When cargo (any of them) last put an order in.
GLOBAL_VAR_INIT(bot_cargo_last_order, 0)
/// Crates left somewhere between the shuttle and the bay, to be gone back for.
GLOBAL_LIST_EMPTY(bot_cargo_strays)

/// Whether a crate is sat somewhere it can stay: in the bay, clear of the doors.
/proc/bot_crate_in_bay(obj/structure/closet/crate/C)
	var/turf/T = get_turf(C)
	return T && istype(T.loc, /area/quartermaster/storage) && !bot_aboard_supply_shuttle(C) && !(locate(/obj/machinery/door) in range(1, T))

/datum/bot_brain
	var/crates_unloaded = 0
	var/orders_placed = 0
	/// Orders put in because somebody asked for the crate (goals/orders.dm).
	var/requests_ordered = 0
	var/list/cargo_blocked

/datum/bot_brain/proc/is_cargo_job()
	var/role = owner.mind?.assigned_role
	return role == "Cargo Technician" || role == "Quartermaster"

/// A supply console that can place orders and move the shuttle (not a request-only one).
/datum/bot_brain/proc/find_cargo_console()
	var/obj/machinery/computer/cargo/best
	var/best_dist
	for(var/obj/machinery/computer/cargo/C as anything in bot_instances_of(/obj/machinery/computer/cargo))
		if(QDELETED(C) || C.z != owner.z || C.requestonly || (C.stat & (BROKEN|NOPOWER)) || !istype(get_area(C), /area/quartermaster))
			continue
		if(LAZYACCESS(cargo_blocked, C) > world.time)
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/// Whether the supply shuttle is sitting at the station.
/proc/bot_supply_shuttle_docked()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	return S && S.mode == SHUTTLE_IDLE && S.getDockedId() == "supply_home"

/proc/bot_supply_shuttle_away()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	return S && S.mode == SHUTTLE_IDLE && S.getDockedId() == "supply_away"

/// The crates still aboard the docked shuttle that nobody else is seeing to.
/datum/bot_brain/proc/crates_on_shuttle()
	. = list()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S?.shuttle_areas || !bot_supply_shuttle_docked())
		return
	for(var/area/A as anything in S.shuttle_areas)
		for(var/obj/structure/closet/crate/C in A)
			if(isturf(C.loc) && C.z == owner.z && !C.anchored && !(LAZYACCESS(cargo_blocked, C) > world.time))
				. += C

/// A clear bit of floor in the cargo bay to leave a crate on.
/datum/bot_brain/proc/find_bay_spot()
	var/area/bay = GLOB.areas_by_type[/area/quartermaster/storage]
	if(!bay)
		return null
	var/list/spots = list()
	for(var/turf/open/floor/T in bay)
		if(T.z != owner.z || is_blocked_turf(T, TRUE) || (locate(/obj/machinery/door) in range(1, T)) || (locate(/obj/machinery/conveyor) in T))
			continue
		if(locate(/mob/living) in T)
			continue
		spots += T
	return length(spots) ? pick(spots) : null

/// What to order: a staple the budget covers comfortably and that isn't already sitting in the bay.
/datum/bot_brain/proc/pick_supply_pack()
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	if(!budget)
		return null
	// What somebody has asked for comes first (goals/orders.dm).
	var/datum/bot_request/asked = bot_next_cargo_request()
	if(asked)
		return SSshuttle.supply_packs[asked.detail]
	var/list/affordable = list()
	for(var/pack_type in GLOB.bot_cargo_staples)
		var/datum/supply_pack/P = SSshuttle.supply_packs[pack_type]
		if(P && P.cost * BOT_CARGO_BUDGET_MARGIN <= budget.account_balance)
			affordable += P
	return length(affordable) ? pick(affordable) : null

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/cargo
	name = "cargo"
	jobs = list("Cargo Technician", "Quartermaster")
	interval_min = 100
	interval_max = 250

/datum/bot_duty/cargo/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return FALSE
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S || SSshuttle.supplyBlocked)
		return FALSE
	// The shuttle's in: get the crates off it.
	for(var/obj/structure/closet/crate/C as anything in bot.crates_on_shuttle())
		if(!bot.taken_by_another(C) && bot.assign_goal(new /datum/bot_goal/unload_crate(C)))
			return TRUE
	// One that got left in the dock on the way: finish the job.
	for(var/obj/structure/closet/crate/C as anything in GLOB.bot_cargo_strays.Copy())
		if(QDELETED(C) || !isturf(C.loc) || C.z != bot.owner.z || bot_crate_in_bay(C))
			GLOB.bot_cargo_strays -= C
			continue
		if(LAZYACCESS(bot.cargo_blocked, C) > world.time || bot.taken_by_another(C))
			continue
		if(bot.assign_goal(new /datum/bot_goal/unload_crate(C)))
			return TRUE
	if(!bot.find_cargo_console())
		return FALSE
	// Empty and docked with nobody aboard: back it goes, so the next order has something to come in on.
	if(bot_supply_shuttle_docked() && !length(bot.crates_on_shuttle()) && S.canMove())
		return bot.assign_goal(new /datum/bot_goal/work_cargo_console("send"))
	// Something on order and the shuttle idle at CentCom: call it in.
	if(bot_supply_shuttle_away() && length(SSshuttle.shoppinglist))
		return bot.assign_goal(new /datum/bot_goal/work_cargo_console("call"))
	// Nothing on order: think about ordering.
	if(!length(SSshuttle.shoppinglist) && (!GLOB.bot_cargo_last_order || world.time >= GLOB.bot_cargo_last_order + BOT_CARGO_ORDER_GAP || bot_next_cargo_request()) && bot.pick_supply_pack())
		return bot.assign_goal(new /datum/bot_goal/work_cargo_console("order"))
	return FALSE

/datum/bot_brain/proc/continue_cargo_round()
	var/datum/bot_duty/cargo/duty = bot_duty_of(/datum/bot_duty/cargo)
	continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), src))

// ---------------------------------------------------------------------------------------------
// At the console
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/work_cargo_console
	lawful = TRUE
	exclusive = TRUE
	/// "order", "call" (bring the shuttle in) or "send" (send it back).
	var/task

/datum/bot_goal/work_cargo_console/New(task)
	. = ..()
	src.task = task
	doing = task == "order" ? "putting an order in" : "seeing to the supply shuttle"

/datum/bot_goal/work_cargo_console/resolve_target(datum/bot_brain/bot)
	target = bot.find_cargo_console()

/datum/bot_goal/work_cargo_console/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cargo/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/press_cargo_console())
	return list(S)

/datum/bot_goal/work_cargo_console/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.cargo_blocked, target, world.time + 2 MINUTES)

/datum/bot_strategy/cargo/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/press_cargo_console/execute(datum/bot_brain/bot)
	var/datum/bot_goal/work_cargo_console/G = bot.current_goal
	var/obj/machinery/computer/cargo/C = G?.target
	if(!istype(G) || !istype(C) || QDELETED(C) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	if(QDELETED(C) || !bot.owner.Adjacent(C) || (C.stat & (BROKEN|NOPOWER)))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(C)
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	switch(G.task)
		if("order")
			var/datum/supply_pack/pack = bot.pick_supply_pack()
			if(!pack || length(SSshuttle.shoppinglist))
				return GOAL_STEP_FAIL //someone else has just ordered
			bot.telemetry_ui_action(C, "order [pack.name]")
			// For whoever asked for it, if somebody did.
			var/datum/bot_request/asked
			for(var/datum/bot_request/R as anything in GLOB.bot_cargo_requests)
				if(R.detail == pack.type)
					asked = R
					break
			var/mob/living/asker = asked?.caller_ref?.resolve()
			if(asked)
				GLOB.bot_cargo_requests -= asked
				bot.requests_ordered++
			var/datum/supply_order/order = new(pack, bot.owner.real_name, bot.owner.get_assignment(hand_first = TRUE), bot.owner.ckey, asker ? "Requested by [asker.real_name]" : "Restocking")
			order.generateRequisition(get_turf(C))
			order.approved_by = cargo_ledger_signature(bot.owner)
			SSshuttle.shoppinglist += order
			GLOB.bot_cargo_last_order = world.time
			bot.orders_placed++
			C.say("Order placed: [pack.name].")
			bot_log(bot, "ordered [pack.name] ([pack.cost] credits)")
			if(asker)
				var/line = "[asker.first_name()], I've ordered the [lowertext(pack.name)] - it'll be in the cargo bay in a few minutes."
				bot.say_after_typing(bot_radio_prefix(asked.radio_freq) + line)
			else if(!bot.gym_scripted && prob(60))
				bot.say_after_typing(":u [pick("Ordered", "Put in for", "Got an order in for")] [lowertext(pack.name)].")
		if("call")
			if(!bot_supply_shuttle_away() || !length(SSshuttle.shoppinglist))
				return GOAL_STEP_SUCCESS //already on its way
			bot.telemetry_ui_action(C, "call shuttle")
			C.say("The supply shuttle has been called and will arrive in [S.timeLeft(600)] minutes.")
			SSshuttle.moveShuttle("supply", "supply_home", TRUE)
			bot_log(bot, "called the supply shuttle in")
		if("send")
			if(!bot_supply_shuttle_docked())
				return GOAL_STEP_SUCCESS
			if(!S.canMove())
				C.say(C.safety_warning)
				return GOAL_STEP_FAIL
			bot.telemetry_ui_action(C, "send shuttle")
			S.export_categories = C.get_export_categories()
			SSshuttle.moveShuttle("supply", "supply_away", TRUE)
			C.say("The supply shuttle is departing.")
			bot_log(bot, "sent the supply shuttle back")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Unloading
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/unload_crate
	lawful = TRUE
	exclusive = TRUE
	doing = "unloading the supply shuttle"
	var/turf/drop_spot

/datum/bot_goal/unload_crate/New(obj/structure/closet/crate/C)
	. = ..()
	target = C

/datum/bot_goal/unload_crate/resolve_target(datum/bot_brain/bot)
	drop_spot = bot.find_bay_spot()
	if(QDELETED(target) || !drop_spot)
		target = null

/datum/bot_goal/unload_crate/get_strategies(datum/bot_brain/bot)
	. = list()
	// A crate being pulled gets left behind when somebody squeezes past in the dock airlock (they end up stood where
	// it was about to go). Each try starts from wherever the crate is now: go back, take hold of it again, carry on.
	for(var/attempt in 1 to 3)
		var/datum/bot_strategy/cargo/S = new
		var/datum/bot_step/move_to/to_bay = new
		to_bay.step_target = drop_spot
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_crate(), to_bay, new /datum/bot_step/let_go_of_crate())
		. += S

/datum/bot_goal/unload_crate/on_success(datum/bot_brain/bot)
	GLOB.bot_cargo_strays -= target
	bot.continue_cargo_round()

/datum/bot_goal/unload_crate/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.cargo_blocked, target, world.time + 1 MINUTES)
		if(!QDELETED(target) && !bot_aboard_supply_shuttle(target) && !bot_crate_in_bay(target))
			GLOB.bot_cargo_strays |= target

/datum/bot_step/grab_crate/execute(datum/bot_brain/bot)
	var/obj/structure/closet/crate/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	if(QDELETED(C) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(C)
	bot.telemetry_event("pull", list("target" = "[C]"))
	bot.owner.start_pulling(C)
	return bot.owner.pulling == C ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/let_go_of_crate/execute(datum/bot_brain/bot)
	var/obj/structure/closet/crate/C = bot.current_goal?.target
	var/had_it = bot.owner.pulling == C
	bot.owner.stop_pulling()
	if(!had_it || QDELETED(C) || bot_aboard_supply_shuttle(C))
		return GOAL_STEP_FAIL
	bot.crates_unloaded++
	bot_log(bot, "unloaded [C] into the bay")
	return GOAL_STEP_SUCCESS

/proc/bot_aboard_supply_shuttle(atom/A)
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	return S?.shuttle_areas && S.shuttle_areas[get_area(A)]

#undef BOT_CARGO_BUDGET_MARGIN
#undef BOT_CARGO_ORDER_GAP
