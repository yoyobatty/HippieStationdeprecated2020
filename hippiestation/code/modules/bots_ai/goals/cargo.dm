// Cargo: a Cargo Technician or the Quartermaster runs the supply shuttle the way the department does.
//
//  - orders something the station can use at the supply console, when the budget allows and nothing
//    is already on order: the "add" button's own effect (cargo/console.dm ui_act()) - a
//    /datum/supply_order on SSshuttle.shoppinglist, signed for in the ledger
//  - calls the shuttle in once there's an order waiting for it, with the console's "send" button
//  - when it docks, hauls each crate off it into the cargo bay: grab it, pull it, let go. With Cargo's
//    rubber stamp, each crate's manifest comes off first, stamped and left aboard to go back for credits
//  - sends the shuttle back once it's empty and nobody's aboard, ready for the next order
//
// What's in the crates stays in them: the bay is where departments come to collect.

/// What's kept back from a staple nobody asked for, for what people ask for: the station's money isn't cargo's to empty. With twice a
/// staple's cost as the only bar, a toolbox crate and a bot's medical supplies took the budget from 5000 to 2000 before anybody asked
/// for anything, and the silver asked for at Science's console a few minutes later went unordered.
#define BOT_CARGO_KEEP_FOR_ASKS 3000
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
/// Crates the shuttle brought that went into the bay: back aboard once they're empty, for 500 credits each from CentCom
/// (cargo/exports/large_objects.dm). Only these: the station's own bins and freezers are crates too.
GLOBAL_LIST_EMPTY(bot_cargo_brought_in)
/// Empty ones put aboard to go back: not to be unloaded again
GLOBAL_LIST_EMPTY(bot_cargo_going_back)

/// Off every list of crates when it goes (sold with the shuttle, mostly): a list still holding it would keep it from being deleted
/obj/structure/closet/crate/Destroy()
	GLOB.bot_cargo_strays -= src
	GLOB.bot_cargo_brought_in -= src
	GLOB.bot_cargo_going_back -= src
	GLOB.bot_delivered_crates -= src
	return ..()

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
	/// Manifests stamped and left aboard the shuttle to go back
	var/manifests_filed = 0
	/// Crates whose manifest it couldn't get to: unloaded with it still on
	var/list/manifests_passed

/datum/bot_brain/proc/is_cargo_job()
	var/role = work_role()
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
			if(isturf(C.loc) && C.z == owner.z && !C.anchored && !(LAZYACCESS(cargo_blocked, C) > world.time) && !(C in GLOB.bot_cargo_going_back))
				. += C

/// Every crate aboard the docked supply shuttle to come off it, whoever can or can't get at them
/proc/bot_supply_shuttle_crates()
	. = 0
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S?.shuttle_areas || !bot_supply_shuttle_docked())
		return
	for(var/area/A as anything in S.shuttle_areas)
		for(var/obj/structure/closet/crate/C in A)
			if(isturf(C.loc) && !C.anchored && !(C in GLOB.bot_cargo_going_back))
				.++

GLOBAL_VAR_INIT(bot_cargo_air_asked, -INFINITY)

/// A crate in air this bot can't breathe, with no suit on: left for a couple of minutes. assign_goal() turned these down every time
/// it was asked, and it was asked every few seconds: two cargo technicians asked 183 times between them in one shift over a crate of
/// glass in a dock that had lost its air.
/datum/bot_brain/proc/crate_in_bad_air(obj/structure/closet/crate/C)
	if(!in_bad_air(C) || is_eva_ready())
		return FALSE
	bot_log(src, "[C] is somewhere I can't breathe and I'm not suited up - leaving it for now")
	LAZYSET(cargo_blocked, C, world.time + 2 MINUTES)
	return TRUE

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
	if(GLOB.bot_cargo_saving_for) //saving up for somebody's: no staples before it
		return null
	var/list/affordable = list()
	for(var/pack_type in GLOB.bot_cargo_staples)
		var/datum/supply_pack/P = SSshuttle.supply_packs[pack_type]
		if(P && bot_cargo_spendable(budget) - P.cost >= BOT_CARGO_KEEP_FOR_ASKS)
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
	// The shuttle's in: get the crates off it, each one's manifest stamped and left aboard first. Cargo's stamp first, if it's lying about.
	var/list/aboard_crates = bot.crates_on_shuttle()
	if(length(aboard_crates) && !bot.carried_approval_stamp())
		for(var/obj/structure/closet/crate/C as anything in aboard_crates)
			if(bot_manifest_to_file(C))
				var/obj/item/stamp/stamp = bot.find_cargo_stamp()
				if(stamp && !bot.taken_by_another(stamp) && bot.assign_goal(new /datum/bot_goal/take_item/exact(stamp)))
					return TRUE
				break
	for(var/obj/structure/closet/crate/C as anything in aboard_crates)
		if(bot.crate_in_bad_air(C) || bot.taken_by_another(C))
			continue
		if(bot_manifest_to_file(C) && !LAZYACCESS(bot.manifests_passed, REF(C)) && bot.carried_approval_stamp() && bot.assign_goal(new /datum/bot_goal/file_manifest(C)))
			return TRUE
		if(bot.assign_goal(new /datum/bot_goal/unload_crate(C)))
			return TRUE
	// One that got left in the dock on the way: finish the job.
	for(var/obj/structure/closet/crate/C as anything in GLOB.bot_cargo_strays.Copy())
		if(QDELETED(C) || !isturf(C.loc) || C.z != bot.owner.z || bot_crate_in_bay(C))
			GLOB.bot_cargo_strays -= C
			continue
		if(LAZYACCESS(bot.cargo_blocked, C) > world.time || bot.taken_by_another(C) || bot.crate_in_bad_air(C))
			continue
		if(bot.assign_goal(new /datum/bot_goal/unload_crate(C)))
			return TRUE
	// Something somebody's waiting for: round to their door with it (bot_collabs.dm).
	var/obj/structure/closet/crate/parcel = bot.crate_to_deliver()
	if(parcel)
		// On a MULE when there's one free and the department has a delivery beacon; carried round otherwise (bot_collabs.dm)
		var/list/delivery = GLOB.bot_cargo_deliveries[bot_crate_delivery(parcel)]
		var/mob/living/simple_animal/bot/mulebot/mule = bot.free_mule()
		var/beacon = (mule && delivery) ? bot.delivery_beacon_for(delivery[1]) : null
		if(beacon && bot.assign_goal(new /datum/bot_goal/deliver_crate/by_mule(parcel, mule, beacon)))
			return TRUE
		if(bot.assign_goal(new /datum/bot_goal/deliver_crate(parcel)))
			return TRUE
	// Docked with nothing left to come off: the empty crates that came in on it back aboard first, a few a trip
	if(bot_supply_shuttle_docked() && !bot_supply_shuttle_crates() && length(GLOB.bot_cargo_going_back) < 6)
		var/obj/structure/closet/crate/empty = bot.empty_crate_to_return()
		if(empty && bot.assign_goal(new /datum/bot_goal/unload_crate/return_crate(empty)))
			return TRUE
	if(!bot.find_cargo_console())
		return FALSE
	// Empty and docked with nobody aboard: back it goes, so the next order has something to come in on. Every crate aboard counts, the
	// ones it's leaving for now too: one in bad air was left out, the shuttle went back with it, and the crate was sold. Somebody's
	// silver and a desk's glass went that way in one shift.
	var/aboard = bot_supply_shuttle_crates()
	if(bot_supply_shuttle_docked() && !aboard && S.canMove())
		return bot.assign_goal(new /datum/bot_goal/work_cargo_console("send"))
	if(aboard && !length(bot.crates_on_shuttle()) && world.time > GLOB.bot_cargo_air_asked + 5 MINUTES)
		GLOB.bot_cargo_air_asked = world.time
		bot_log(bot, "crates on the supply shuttle in air I can't work in")
		bot.say_after_typing(";Engineering, the supply shuttle's lost its air and there's [aboard] crate\s aboard I can't get off. Can somebody fill it?")
	// Something on order and the shuttle idle at CentCom: call it in. Saving up for somebody's crate, it comes in for the empties too.
	if(bot_supply_shuttle_away() && (length(SSshuttle.shoppinglist) || (GLOB.bot_cargo_saving_for && bot.empty_crate_to_return())))
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
			if(asked)
				bot_station_request_ordered(asked, order, bot) // a requests console's crate request: off the cargo console's list
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
			if(!bot_supply_shuttle_away())
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
	GLOB.bot_cargo_brought_in |= target
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

// ---------------------------------------------------------------------------------------------
// Manifests
// ---------------------------------------------------------------------------------------------
// Every crate comes with its shipping manifest taped on, and one stamped and sent back on the shuttle is 200 credits from CentCom
// (cargo/exports/manifest.dm). Nothing else pays Cargo here, not even a wage, and the bots never sent one back: the budget only went
// down. Three 1000-credit crates and the cargo staff's pay left 1958 in one shift, and the 20 silver sheets somebody asked for at
// Science's console (2000) were never ordered. Five shifts in six went that way; the one with 2086 left got its silver.
// A manifest that doesn't match its crate stays on it: approving one pays nothing, and denying one costs 500 here (the order's cost is
// never written on it, cargo/order.dm generateManifest()).

/// A manifest worth sending back: still on its crate, and right (a person checks it against what's inside)
/proc/bot_manifest_to_file(obj/structure/closet/crate/C)
	var/obj/item/paper/fluff/jobs/cargo/manifest/M = C.manifest
	return istype(M) && !M.errors

/// A stamp on the bot that approves: anything but DENIED
/datum/bot_brain/proc/carried_approval_stamp()
	for(var/obj/item/stamp/S in owner)
		if(!istype(S, /obj/item/stamp/denied))
			return S
	for(var/obj/item/storage/B in owner)
		for(var/obj/item/stamp/S in B)
			if(!istype(S, /obj/item/stamp/denied))
				return S
	return null

/// Cargo's own rubber stamp, lying about in the department: not the Captain's off the bridge
/datum/bot_brain/proc/find_cargo_stamp()
	var/obj/item/stamp/best
	var/best_dist
	for(var/obj/item/stamp/S as anything in bot_instances_of(/obj/item/stamp))
		if(QDELETED(S) || !isturf(S.loc) || S.z != owner.z || istype(S, /obj/item/stamp/denied) || !istype(get_area(S), /area/quartermaster))
			continue
		var/dist = get_dist(owner, S)
		if(!best || dist < best_dist)
			best = S
			best_dist = dist
	return best

/datum/bot_goal/file_manifest
	lawful = TRUE
	exclusive = TRUE
	doing = "signing for a crate"

/datum/bot_goal/file_manifest/New(obj/structure/closet/crate/C)
	. = ..()
	target = C

/datum/bot_goal/file_manifest/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !bot_manifest_to_file(target) || !bot.carried_approval_stamp())
		target = null

/datum/bot_goal/file_manifest/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cargo/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/stamp_manifest())
	return list(S)

/datum/bot_goal/file_manifest/on_success(datum/bot_brain/bot)
	bot.continue_cargo_round()

/datum/bot_goal/file_manifest/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.manifests_passed, REF(target), TRUE)

// ---------------------------------------------------------------------------------------------
// Empty crates back
// ---------------------------------------------------------------------------------------------

/// Nothing in it but paperwork
/proc/bot_crate_emptied(obj/structure/closet/crate/C)
	for(var/atom/movable/AM as anything in C)
		if(!istype(AM, /obj/item/paper))
			return FALSE
	return TRUE

/// An empty crate in Cargo that came in on the shuttle, to go back on it
/datum/bot_brain/proc/empty_crate_to_return()
	for(var/obj/structure/closet/crate/C as anything in GLOB.bot_cargo_brought_in)
		if(!isturf(C.loc) || !istype(get_area(C), /area/quartermaster))
			GLOB.bot_cargo_brought_in -= C //taken round to somebody, or off somewhere: not Cargo's to send back
			continue
		if(C.z != owner.z || C.anchored || bot_aboard_supply_shuttle(C) || !bot_crate_emptied(C) || bot_crate_delivery(C))
			continue
		if(taken_by_another(C) || LAZYACCESS(returns_blocked, REF(C)) > world.time)
			continue
		return C
	return null

/// Clear floor aboard the docked supply shuttle, as far from its doors as it goes, for a crate to go back on
/datum/bot_brain/proc/find_shuttle_spot()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S?.shuttle_areas || !bot_supply_shuttle_docked())
		return null
	var/list/doors = list()
	var/list/spots = list()
	for(var/area/A as anything in S.shuttle_areas)
		for(var/turf/open/floor/T in A)
			if(locate(/obj/machinery/door) in T)
				doors += T
			else if(T.z == owner.z && !is_blocked_turf(T, TRUE) && !(locate(/obj/structure/closet) in T) && !(locate(/mob/living) in T))
				spots += T
	var/turf/best
	var/best_dist = -1
	for(var/turf/T as anything in spots)
		var/dist = 100
		for(var/turf/D as anything in doors)
			dist = min(dist, get_dist(T, D))
		if(dist > best_dist)
			best = T
			best_dist = dist
	return best

/datum/bot_brain
	/// Empty crates it couldn't get back aboard, by REF(), until when
	var/list/returns_blocked

/// Pulled back aboard the docked shuttle and left there to be sold with it
/datum/bot_goal/unload_crate/return_crate
	doing = "sending an empty crate back"

/datum/bot_goal/unload_crate/return_crate/resolve_target(datum/bot_brain/bot)
	drop_spot = bot.find_shuttle_spot()
	if(QDELETED(target) || !drop_spot)
		target = null

/datum/bot_goal/unload_crate/return_crate/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cargo/S = new
	var/datum/bot_step/move_to/aboard = new
	aboard.step_target = drop_spot
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_crate(), aboard, new /datum/bot_step/leave_crate_aboard())
	return list(S)

/datum/bot_goal/unload_crate/return_crate/on_success(datum/bot_brain/bot)
	GLOB.bot_cargo_brought_in -= target
	GLOB.bot_cargo_going_back |= target
	bot.continue_cargo_round()

/datum/bot_goal/unload_crate/return_crate/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.returns_blocked, REF(target), world.time + 2 MINUTES)

/datum/bot_step/leave_crate_aboard/execute(datum/bot_brain/bot)
	var/obj/structure/closet/crate/C = bot.current_goal?.target
	var/had_it = bot.owner.pulling == C
	bot.owner.stop_pulling()
	if(!had_it || QDELETED(C) || !bot_aboard_supply_shuttle(C))
		return GOAL_STEP_FAIL
	bot_log(bot, "put the empty [C] back aboard the supply shuttle")
	bot_tally("empty crates sent back")
	return GOAL_STEP_SUCCESS

/// Torn off the crate, stamped, and left on the crate's spot to go back with the shuttle
/datum/bot_step/stamp_manifest/execute(datum/bot_brain/bot)
	var/obj/structure/closet/crate/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C) || !bot_manifest_to_file(C))
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	var/obj/item/stamp/stamp = bot.carried_approval_stamp()
	if(QDELETED(C) || !bot.owner.Adjacent(C) || !bot_manifest_to_file(C) || !stamp)
		return GOAL_STEP_FAIL
	bot.owner.face_atom(C)
	var/obj/item/paper/fluff/jobs/cargo/manifest/M = C.manifest
	var/turf/spot = get_turf(C)
	bot.telemetry_event("manifest", list("target" = "[C]"))
	C.tear_manifest(bot.owner)
	M.attackby(stamp, bot.owner)
	if(bot.owner.is_holding(M))
		bot.owner.transferItemToLoc(M, spot)
	else
		M.forceMove(spot)
	if(!M.is_approved())
		return GOAL_STEP_FAIL
	bot.manifests_filed++
	bot_log(bot, "stamped [M] and left it aboard to go back")
	return GOAL_STEP_SUCCESS

#undef BOT_CARGO_KEEP_FOR_ASKS
#undef BOT_CARGO_ORDER_GAP
