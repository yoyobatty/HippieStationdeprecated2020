// Departments working with each other, past Mining bringing ore up for the lab (goals/mining.dm).
//
//  - Anybody short of something that comes in a crate asks Cargo on the radio, and it goes in the next order the way a player's would
//    (goals/orders.dm). When it lands, Cargo hauls it to the department's door and says so, and somebody who works there comes out
//    and gets what they asked for.
//  - Botany asks Chemistry for mutagen and it gets made, and left on Hydroponics' counter. Chemistry asks Botany for poppies when the
//    dispenser's flat, and they turn up on Chemistry's counter, for the grinder.
//  - Science looks after Medbay: the machines get upgraded along with everybody else's (goals/rnd_bench.dm), the lathe prints it a spare
//    defibrillator, and Robotics prints cyborg limbs for it. Chemistry keeps its fridge full (goals/synthesize_medicine.dm).
//  - Security comes when it's called (on_heard_security_call(), goals/security_patrol.dm), and says what it found. Staff with somebody
//    dangerous on the loose in their department and no officer in sight ask for one.

/// Between one request for the same thing and the next.
#define BOT_CARGO_ASK_GAP (10 MINUTES)
/// Between one call for backup and the next, for one bot.
#define BOT_BACKUP_GAP (2 MINUTES)

/// Supply pack -> when it can next be asked for.
GLOBAL_LIST_EMPTY(bot_cargo_asked)
/// Supply pack -> list(department, what they want out of it): crates that are to go to somebody's door.
GLOBAL_LIST_EMPTY(bot_cargo_deliveries)
/// Crate at somebody's door -> list(department, what they want out of it).
GLOBAL_LIST_EMPTY(bot_delivered_crates)
/// What somebody's asked Chemistry to make: each a list("label", "area" to leave it in, "by" who).
GLOBAL_LIST_EMPTY(bot_chem_orders)
/// When Chemistry last asked for poppies.
GLOBAL_VAR_INIT(bot_poppies_wanted_at, 0)

/// Where a department's parcels are left, by department.
GLOBAL_LIST_INIT(bot_drop_off_areas, list(
	"medical" = /area/medical,
	"science" = /area/science,
	"engineering" = /area/engine,
	"botany" = /area/hydroponics,
	"chemistry" = /area/medical/chemistry,
))

/datum/bot_brain
	/// When it next calls for backup.
	var/next_backup_call = 0
	/// Medbay has had what Robotics can do for it, and how many limbs that's been.
	var/medbay_supplied = FALSE
	var/limbs_sent = 0

// ---------------------------------------------------------------------------------------------
// Cargo
// ---------------------------------------------------------------------------------------------

/// On the radio to Cargo, for a crate of this for this department, and `wanted` out of it when it comes. TRUE if it asked.
/datum/bot_brain/proc/ask_cargo_for(pack_type, what, department, wanted)
	if(world.time < GLOB.bot_cargo_asked[pack_type])
		return FALSE
	GLOB.bot_cargo_asked[pack_type] = world.time + BOT_CARGO_ASK_GAP
	var/datum/bot_request/R = new
	R.caller_ref = WEAKREF(owner)
	R.detail = pack_type
	R.made = world.time
	GLOB.bot_cargo_requests |= R
	GLOB.bot_cargo_deliveries[pack_type] = list(department, wanted)
	bot_log(src, "asked Cargo for [what]")
	bot_tally("asked Cargo")
	if(!gym_scripted)
		say_after_typing(";[pick("Cargo, can we get", "Cargo, could you send up", "Anybody in Cargo? We need")] [what] for [capitalize(department)]?")
	return TRUE

/// What's to happen to this crate, if somebody's waiting for it.
/proc/bot_crate_delivery(obj/structure/closet/crate/C)
	for(var/pack_type in GLOB.bot_cargo_deliveries)
		var/datum/supply_pack/P = SSshuttle.supply_packs[pack_type]
		if(P && C.name == P.crate_name)
			return pack_type
	return null

/// A clear tile in the corridor outside this department, the nearest to the bot.
/datum/bot_brain/proc/department_doorstep(department)
	var/turf/best
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(A) || A.z != owner.z || bot_department_of(get_area(A)) != department || istype(A, /obj/machinery/door/airlock/external))
			continue
		for(var/direction in GLOB.cardinals)
			var/turf/T = get_step(A, direction)
			if(!isopenturf(T) || !istype(get_area(T), /area/hallway) || is_blocked_turf(T, TRUE))
				continue
			var/turf/beside = get_step(T, direction) //not stood right in the doorway
			if(isopenturf(beside) && !is_blocked_turf(beside, TRUE))
				T = beside
			if(!best || get_dist(owner, T) < get_dist(owner, best))
				best = T
	return best

/// Crates in the bay with somebody waiting for them.
/datum/bot_brain/proc/crate_to_deliver()
	var/area/bay = GLOB.areas_by_type[/area/quartermaster/storage]
	if(!length(GLOB.bot_cargo_deliveries) || !bay)
		return null
	for(var/obj/structure/closet/crate/C in bay)
		if(isturf(C.loc) && bot_crate_delivery(C) && !taken_by_another(C) && !(LAZYACCESS(cargo_blocked, C) > world.time))
			return C
	return null

/// Grabbed, pulled across the station, and left at their door.
/datum/bot_goal/deliver_crate
	lawful = TRUE
	exclusive = TRUE
	doing = "taking a crate round"
	var/pack_type
	var/turf/doorstep

/datum/bot_goal/deliver_crate/New(obj/structure/closet/crate/C)
	. = ..()
	target = C
	pack_type = bot_crate_delivery(C)

/datum/bot_goal/deliver_crate/resolve_target(datum/bot_brain/bot)
	var/list/delivery = GLOB.bot_cargo_deliveries[pack_type]
	if(QDELETED(target) || !delivery)
		target = null
		return
	doorstep = bot.department_doorstep(delivery[1])
	if(!doorstep || !bot.can_walk_lawfully_to(doorstep))
		target = null

/datum/bot_goal/deliver_crate/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cargo/S = new
	var/datum/bot_step/move_to/to_door = new
	to_door.step_target = doorstep
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_crate(), to_door, new /datum/bot_step/let_go_of_crate())
	return list(S)

/datum/bot_goal/deliver_crate/on_success(datum/bot_brain/bot)
	var/list/delivery = GLOB.bot_cargo_deliveries[pack_type]
	if(delivery)
		GLOB.bot_delivered_crates[target] = delivery
		GLOB.bot_cargo_deliveries -= pack_type
		bot_tally("crates delivered")
		bot_say(bot.owner, ";[capitalize(delivery[1])], your crate's at your door.")
	bot.continue_cargo_round()

/datum/bot_goal/deliver_crate/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.cargo_blocked, target, world.time + 2 MINUTES)

/// Somebody who works there comes out for it.
/datum/bot_duty/collect_delivery
	name = "getting what came in"
	priority = 14
	interval_min = 100
	interval_max = 300

/datum/bot_duty/collect_delivery/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_delivered_crates))
		return FALSE
	var/list/mine = bot.my_departments()
	for(var/obj/structure/closet/crate/C as anything in GLOB.bot_delivered_crates)
		var/list/delivery = GLOB.bot_delivered_crates[C]
		if(QDELETED(C))
			GLOB.bot_delivered_crates -= C
			continue
		if(!(delivery[1] in mine) || bot.taken_by_another(C) || !bot.can_walk_lawfully_to(C))
			continue
		if(bot.assign_goal(new /datum/bot_goal/unpack_crate(C, delivery[2])))
			return TRUE
	return FALSE

/datum/bot_goal/unpack_crate
	lawful = TRUE
	exclusive = TRUE
	doing = "getting something out of a crate"
	var/wanted

/datum/bot_goal/unpack_crate/New(obj/structure/closet/crate/C, what)
	. = ..()
	target = C
	wanted = what

/datum/bot_goal/unpack_crate/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/unpack_crate/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(wanted))
	return list(S)

/datum/bot_goal/unpack_crate/on_success(datum/bot_brain/bot)
	GLOB.bot_delivered_crates -= target
	bot_tally("crates collected")

/datum/bot_goal/unpack_crate/on_give_up(datum/bot_brain/bot)
	GLOB.bot_delivered_crates -= target

// ---------------------------------------------------------------------------------------------
// Leaving something for somebody
// ---------------------------------------------------------------------------------------------

/// A table in this kind of area that this bot can walk up to, the counter of a department it can't get into included. Null if there isn't one.
/datum/bot_brain/proc/find_drop_off(area_type)
	var/list/found = list() //table -> how far off
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(!QDELETED(T) && T.z == owner.z && istype(get_area(T), area_type))
			found[T] = get_dist(owner, T)
	var/tries = 0
	while(length(found) && tries++ < 6)
		var/atom/nearest
		for(var/atom/A as anything in found)
			if(!nearest || found[A] < found[nearest])
				nearest = A
		found -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
	return null

/// Over to their counter with it, on the table, and a word on the radio.
/datum/bot_goal/drop_off
	lawful = TRUE
	doing = "dropping something off"
	var/obj/item/parcel
	var/area_type
	var/for_whom

/datum/bot_goal/drop_off/New(obj/item/I, where, who)
	. = ..()
	parcel = I
	area_type = where
	for_whom = who

/datum/bot_goal/drop_off/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(parcel))
		target = bot.find_drop_off(area_type)

/datum/bot_goal/drop_off/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/leave_parcel())
	return list(S)

/datum/bot_step/leave_parcel/execute(datum/bot_brain/bot)
	var/datum/bot_goal/drop_off/G = bot.current_goal
	if(!istype(G) || QDELETED(G.parcel) || !bot.owner.Adjacent(G.target))
		return GOAL_STEP_FAIL
	if(!bot.use_item_on(G.parcel, G.target) || !isturf(G.parcel.loc))
		return GOAL_STEP_FAIL
	bot_log(bot, "left [G.parcel] in [get_area_name(G.target, TRUE)] for [G.for_whom]")
	bot_tally("left for another department")
	bot_say(bot.owner, ";[G.for_whom], I've left [G.parcel.name] on the counter in [get_area_name(G.target, TRUE)].")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Chemistry and Botany
// ---------------------------------------------------------------------------------------------

/// Somebody's asked Chemistry for something. The first one that can be made, as a brew.
/datum/bot_brain/proc/brew_for_order()
	if(owner.mind?.assigned_role != "Chemist")
		return null
	for(var/list/order as anything in GLOB.bot_chem_orders)
		for(var/list/brew in GLOB.bot_brews)
			if(brew["label"] == order["label"] && can_brew(brew))
				return brew
	return null

/// What a finished order means: off to whoever asked for it, in the beaker it was made in.
/datum/bot_brain/proc/deliver_chem_order(list/brew)
	for(var/list/order as anything in GLOB.bot_chem_orders)
		if(order["label"] != brew["label"])
			continue
		GLOB.bot_chem_orders -= list(order)
		var/obj/item/reagent_containers/glass/beaker/B = brew_beaker()
		if(B && assign_goal(new /datum/bot_goal/drop_off(B, order["area"], order["by"])))
			bot_tally("chem orders filled")
		return

/// Dispenser flat: a chemist asks Botany for something to put in the grinder instead.
/datum/bot_brain/proc/ask_for_poppies()
	if(world.time < GLOB.bot_poppies_wanted_at + BOT_CARGO_ASK_GAP)
		return
	GLOB.bot_poppies_wanted_at = world.time
	bot_tally("asked Botany")
	if(!gym_scripted)
		say_after_typing(";Botany, any poppies going? The dispenser's flat and Medbay still needs bicaridine.")

/// Poppies first, if Chemistry's asked lately.
/datum/bot_brain/proc/poppies_wanted()
	return GLOB.bot_poppies_wanted_at && world.time < GLOB.bot_poppies_wanted_at + BOT_CARGO_ASK_GAP

/// A botanist with poppies on it takes them over.
/datum/bot_duty/poppy_run
	name = "taking poppies to Chemistry"
	jobs = list("Botanist")
	tier = BOT_DUTY_URGENT //a botanist's rounds never run out: anything lower never gets asked
	priority = 1
	interval_min = 200
	interval_max = 500

/datum/bot_duty/poppy_run/try_start(datum/bot_brain/bot)
	var/obj/item/reagent_containers/food/snacks/grown/poppy/P = bot.find_carried_tool(/obj/item/reagent_containers/food/snacks/grown/poppy)
	if(P)
		return bot.assign_goal(new /datum/bot_goal/drop_off(P, /area/medical/chemistry, "Chemistry"))
	// Asked for, and nothing to plant: a packet off the vendor. The trays do the rest (pick_seed_to_plant(), goals/tend_hydroponics.dm).
	if(bot.poppies_wanted() && !bot.find_carried_tool(/obj/item/seeds/poppy) && !bot.poppies_growing())
		return bot.assign_goal(new /datum/bot_goal/botany_supply/seeds(/obj/item/seeds/poppy, "seed_vendor"))
	return FALSE

/// Off the seed vendor: find_botany_supply() only knows the one that sells nutrients.
/datum/bot_goal/botany_supply/seeds/resolve_target(datum/bot_brain/bot)
	target = bot.find_botany_vendor(/obj/machinery/vending/hydroseeds, list(item_type))

/datum/bot_brain/proc/poppies_growing()
	for(var/obj/machinery/hydroponics/H as anything in bot_instances_of(/obj/machinery/hydroponics))
		if(H.z == owner.z && istype(H.myseed, /obj/item/seeds/poppy) && !H.dead)
			return TRUE
	return FALSE

/// Poppies left for Chemistry, in reach of this chemist.
/datum/bot_brain/proc/find_poppy()
	for(var/obj/item/reagent_containers/food/snacks/grown/poppy/P as anything in bot_instances_of(/obj/item/reagent_containers/food/snacks/grown/poppy))
		if(!QDELETED(P) && isturf(P.loc) && P.z == owner.z && is_medbay_chemistry(P))
			return P
	return null

/// Poppies on Chemistry's counter, and a brew to go with them.
/datum/bot_brain/proc/brew_for_poppies()
	if(owner.mind?.assigned_role != "Chemist" || !find_poppy())
		return null
	for(var/list/brew in GLOB.bot_brews)
		if(brew["kind"] == "poppy" && can_brew(brew))
			return brew
	return null

/datum/bot_step/fetch_poppy/execute(datum/bot_brain/bot)
	if(bot.find_carried_tool(/obj/item/reagent_containers/food/snacks/grown/poppy))
		return GOAL_STEP_SUCCESS
	var/obj/item/reagent_containers/food/snacks/grown/poppy/P = bot.find_poppy()
	return (P && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(P))) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Into the grinder with a poppy, a beaker under it, and what comes out is in the beaker. ChemMaster next, the same as anything else.
/datum/bot_step/paced/grind_poppy
	max_clicks = 6
	var/obj/machinery/reagentgrinder/grinder
	var/ground = FALSE

/datum/bot_step/paced/grind_poppy/New(obj/machinery/reagentgrinder/G)
	. = ..()
	grinder = G

/datum/bot_step/paced/grind_poppy/start(datum/bot_brain/bot)
	ground = FALSE
	return !QDELETED(grinder) && bot.owner.Adjacent(grinder) && !grinder.operating

/datum/bot_step/paced/grind_poppy/do_click(datum/bot_brain/bot)
	if(grinder.operating)
		wait_for = 5
		clicks++
		return TRUE
	if(ground)
		return FALSE
	var/obj/item/reagent_containers/glass/beaker/B = bot.brew_beaker()
	if(!grinder.beaker)
		if(!B)
			return FALSE
		bot.use_item_on(B, grinder)
		return TRUE
	var/obj/item/reagent_containers/food/snacks/grown/poppy/P = bot.find_carried_tool(/obj/item/reagent_containers/food/snacks/grown/poppy)
	if(P)
		bot.use_item_on(P, grinder)
		return TRUE
	bot.telemetry_ui_action(grinder, "grind")
	grinder.grind(bot.owner)
	ground = TRUE
	wait_for = 5
	return TRUE

/datum/bot_step/paced/grind_poppy/finish(datum/bot_brain/bot)
	if(!QDELETED(grinder) && grinder.beaker)
		grinder.replace_beaker(bot.owner)
	return ground ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Science and Medbay
// ---------------------------------------------------------------------------------------------

/// A roboticist with spare time and a fabricator: a set of limbs for Medbay, left on its counter. Medbay's surgeons do the rest.
GLOBAL_LIST_INIT(bot_medbay_limbs, list(/obj/item/bodypart/r_arm/robot, /obj/item/bodypart/l_leg/robot, /obj/item/bodypart/r_leg/robot))

/datum/bot_duty/limbs_for_medbay
	name = "printing limbs for Medbay"
	jobs = list("Roboticist")
	priority = 9
	interval_min = 900
	interval_max = 1800

/datum/bot_duty/limbs_for_medbay/try_start(datum/bot_brain/bot)
	if(bot.medbay_supplied || world.time < bot.robotics_blocked_until)
		return FALSE
	var/obj/machinery/mecha_part_fabricator/F = bot.find_exofab()
	if(!F)
		return FALSE
	for(var/limb_type in GLOB.bot_medbay_limbs)
		var/obj/item/bodypart/spare = bot.find_carried_tool(limb_type)
		if(spare)
			bot.limbs_sent++
			bot.medbay_supplied = bot.limbs_sent >= length(GLOB.bot_medbay_limbs)
			return bot.assign_goal(new /datum/bot_goal/drop_off(spare, /area/medical, "Medbay"))
	return bot.assign_goal(new /datum/bot_goal/print_limb(F, GLOB.bot_medbay_limbs[min(bot.limbs_sent + 1, length(GLOB.bot_medbay_limbs))]))

/// The fabricator's button for one limb, and a wait while it prints. Comes out beside it.
/datum/bot_goal/print_limb
	lawful = TRUE
	exclusive = TRUE
	doing = "printing a limb"
	var/limb_type

/datum/bot_goal/print_limb/New(obj/machinery/mecha_part_fabricator/F, what)
	. = ..()
	target = F
	limb_type = what

/datum/bot_goal/print_limb/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/mecha_part_fabricator/F = target
	if(QDELETED(F) || F.being_built)
		target = null

/datum/bot_goal/print_limb/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	var/datum/bot_step/stock_fabricator/stock = new
	stock.limb_type = limb_type
	S.steps = list(stock, new /datum/bot_step/move_to(), new /datum/bot_step/paced/print_limb(limb_type))
	return list(S)

/datum/bot_goal/print_limb/on_give_up(datum/bot_brain/bot)
	bot.robotics_blocked_until = world.time + 5 MINUTES

/datum/bot_step/paced/print_limb
	max_clicks = 120
	var/limb_type
	var/started = FALSE

/datum/bot_step/paced/print_limb/New(what)
	. = ..()
	limb_type = what

/datum/bot_step/paced/print_limb/start(datum/bot_brain/bot)
	started = FALSE
	return TRUE

/datum/bot_step/paced/print_limb/do_click(datum/bot_brain/bot)
	var/obj/machinery/mecha_part_fabricator/F = bot.current_goal?.target
	if(!istype(F) || QDELETED(F) || (F.stat & (BROKEN|NOPOWER)))
		return FALSE
	var/obj/item/bodypart/made = locate(limb_type) in range(1, F)
	if(made)
		bot.try_pickup_target(made)
		return FALSE
	if(F.being_built)
		wait_for = 10
		clicks++
		return TRUE
	if(started)
		return FALSE
	started = TRUE
	var/datum/design/D = bot.fabricator_design(F, limb_type)
	if(!D || !F.check_resources(D))
		return FALSE
	bot.human_pause(F)
	if(QDELETED(F) || F.being_built || !bot.owner.Adjacent(F))
		return FALSE
	bot.telemetry_ui_action(F, "build [D.name]")
	INVOKE_ASYNC(F, TYPE_PROC_REF(/obj/machinery/mecha_part_fabricator, build_part), D)
	wait_for = 10
	return TRUE

/datum/bot_step/paced/print_limb/finish(datum/bot_brain/bot)
	return bot.find_carried_tool(limb_type) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// The fabricator's design for this build path.
/datum/bot_brain/proc/fabricator_design(obj/machinery/mecha_part_fabricator/F, build_path)
	for(var/id in F.stored_research?.researched_designs)
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		if(D?.build_path == build_path)
			return D
	return null

/// A scientist with the lathe to itself and a defibrillator researched: a spare for Medbay.
/datum/bot_duty/defib_for_medbay
	name = "printing a defibrillator for Medbay"
	jobs = list("Scientist", "Research Director")
	priority = 8
	interval_min = 900
	interval_max = 1800

/datum/bot_duty/defib_for_medbay/try_start(datum/bot_brain/bot)
	var/obj/item/defibrillator/D = bot.find_carried_tool(/obj/item/defibrillator)
	if(D)
		return bot.assign_goal(new /datum/bot_goal/drop_off(D, /area/medical, "Medbay"))
	if(GLOB.bot_medbay_defib_printed || world.time < bot.rnd_bench_blocked_until)
		return FALSE
	var/datum/design/design = bot_researched_design("defibrillator")
	var/obj/machinery/rnd/production/L = design && bot.find_lathe()
	if(!L)
		return FALSE
	GLOB.bot_medbay_defib_printed = TRUE
	return bot.print_or_ask(L, design, 1)

GLOBAL_VAR_INIT(bot_medbay_defib_printed, FALSE)

// ---------------------------------------------------------------------------------------------
// Security
// ---------------------------------------------------------------------------------------------

/// Somebody dangerous about in the department, and nobody from Security to be seen: it asks for somebody to come.
/datum/bot_duty/call_backup
	name = "calling for backup"
	tier = BOT_DUTY_URGENT
	priority = 16
	interval_min = 100
	interval_max = 200

/datum/bot_duty/call_backup/applies_to(datum/bot_brain/bot)
	return !bot.is_security_job()

/datum/bot_duty/call_backup/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_backup_call || !length(GLOB.bot_security_wanted))
		return FALSE
	var/mob/living/carbon/human/threat = bot.threat_in(bot.my_departments())
	if(!threat || bot.officer_in_sight())
		return FALSE
	bot.next_backup_call = world.time + BOT_BACKUP_GAP
	bot_tally("called for backup")
	bot_say(bot.owner, ";Security, we need somebody in [get_area_name(bot.owner, TRUE)]. [threat.name]'s been seen around here.")
	return FALSE

#undef BOT_CARGO_ASK_GAP
#undef BOT_BACKUP_GAP
