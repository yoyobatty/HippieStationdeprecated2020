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
/datum/bot_brain/proc/department_doorstep(department, area_type)
	var/turf/best
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(A) || A.z != owner.z || istype(A, /obj/machinery/door/airlock/external))
			continue
		if(area_type ? !istype(get_area(A), area_type) : bot_department_of(get_area(A)) != department)
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
		// Not while it's still riding the MULE: a scientist went for the silver on its way, lost it, and the crate was forgotten
		if(!isturf(C.loc) || LAZYACCESS(bot.unpack_blocked, REF(C)) > world.time)
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

/// Still somebody's crate: this bot leaves it a while, and it or a colleague goes back for it. Open with nothing of what came left in it
/// or under it, somebody's had it already: off the list. Three engineers in turn found the glass sheets crate empty and left it on.
/datum/bot_goal/unpack_crate/on_give_up(datum/bot_brain/bot)
	var/obj/structure/closet/crate/C = target
	if(!C)
		return
	if(istype(C) && C.opened && !bot_crate_has_left(C, wanted))
		GLOB.bot_delivered_crates -= C
		bot_log(bot, "[C]'s been emptied already - nothing to collect")
		return
	LAZYSET(bot.unpack_blocked, REF(C), world.time + 2 MINUTES)

/// Anything of `wanted` (any item, if null) still in the crate or on its tile
/proc/bot_crate_has_left(obj/structure/closet/crate/C, wanted)
	var/turf/T = get_turf(C)
	for(var/obj/item/I in T ? C.contents + T.contents : C.contents)
		if(!wanted || istype(I, wanted))
			return TRUE
	return FALSE

/datum/bot_brain
	/// Delivered crates it couldn't get at, by REF(), until when
	var/list/unpack_blocked

// ---------------------------------------------------------------------------------------------
// Leaving something for somebody
// ---------------------------------------------------------------------------------------------

/// A table in this kind of area that this bot can walk up to, the counter of a department it can't get into included. Null if there isn't one.
/// Counters first, the nearest six, then the nearest six of the rest: it took the six nearest tables whatever they were, and where
/// those were all inside a lab it had no way into it gave up, with the lab's counter a little further along the hall.
/datum/bot_brain/proc/find_drop_off(area_type)
	var/list/counters = list() //table -> how far off
	var/list/inside = list()
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(QDELETED(T) || T.z != owner.z || !istype(get_area(T), area_type))
			continue
		if(bot_is_counter(T, area_type))
			counters[T] = get_dist(owner, T)
		else
			inside[T] = get_dist(owner, T)
	for(var/list/found in list(counters, inside))
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

/// Whether a department's table is a counter: one with somewhere to stand beside it that isn't the department's.
/proc/bot_is_counter(obj/structure/table/T, area_type)
	for(var/direction in GLOB.cardinals)
		var/turf/beside = get_step(T, direction)
		if(isopenturf(beside) && !istype(get_area(beside), area_type) && !is_blocked_turf(beside, TRUE))
			return TRUE
	return FALSE

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
	if(work_role() != "Chemist")
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
	if(work_role() != "Chemist" || !find_poppy())
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

// ---------------------------------------------------------------------------------------------
// By MULE
// ---------------------------------------------------------------------------------------------

// A crate somebody's waiting for goes out on a MULE when one's free: pulled beside it, dragged on, the MULE's controls opened with
// the technician's ID, the department's delivery beacon picked and Go pressed, as a player works one (mulebot.dm MouseDrop_T(),
// bot_control(); set_destination() is what the panel's list of beacons sets). The user ruled it, 2026-11-05: "Cargo orders it and
// uses the mulebot to deliver it." Carried round by hand (deliver_crate) when there's no MULE or no beacon.

/// Whether a MULE's free to take a crate out: on, empty, idle, with charge, and nobody riding or driving it
/proc/bot_mule_free(mob/living/simple_animal/bot/mulebot/M)
	return istype(M) && !QDELETED(M) && M.on && !M.load && M.mode == BOT_IDLE && M.has_power() && !M.client && !M.paicard

/// The nearest free MULE it can walk to, near enough to the bay to be the bay's
/datum/bot_brain/proc/free_mule()
	var/mob/living/simple_animal/bot/mulebot/best
	for(var/mob/living/simple_animal/bot/mulebot/M in GLOB.bots_list)
		if(M.z != owner.z || get_dist(owner, M) > 20 || !bot_mule_free(M) || taken_by_another(M) || LAZYACCESS(cargo_blocked, M) > world.time)
			continue
		if(best && get_dist(owner, M) >= get_dist(owner, best))
			continue
		if(can_walk_lawfully_to(get_turf(M)))
			best = M
	return best

/// The delivery beacon a department's crates go to, by its tag: one in the department, or failing that the nearest to its door
/datum/bot_brain/proc/delivery_beacon_for(department)
	var/turf/door = department_doorstep(department)
	var/obj/machinery/navbeacon/best
	var/best_score
	for(var/obj/machinery/navbeacon/B in GLOB.deliverybeacons)
		if(QDELETED(B) || B.z != owner.z || !B.location)
			continue
		var/score
		if(bot_department_of(get_area(B)) == department)
			score = get_dist(owner, B) / 1000
		else if(door && get_dist(B, door) <= 10)
			score = 1 + get_dist(B, door)
		else
			continue
		if(!best || score < best_score)
			best = B
			best_score = score
	return best?.location

/datum/bot_goal/deliver_crate/by_mule
	doing = "sending a crate out on a MULE"
	var/mob/living/simple_animal/bot/mulebot/mule
	var/beacon_tag

/datum/bot_goal/deliver_crate/by_mule/New(obj/structure/closet/crate/C, mob/living/simple_animal/bot/mulebot/M, beacon)
	. = ..(C)
	mule = M
	beacon_tag = beacon

/datum/bot_goal/deliver_crate/by_mule/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !GLOB.bot_cargo_deliveries[pack_type] || !beacon_tag || (!bot_mule_free(mule) && mule?.load != target))
		target = null

/datum/bot_goal/deliver_crate/by_mule/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cargo/S = new
	var/datum/bot_step/move_to/to_mule = new
	to_mule.step_target = mule
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_crate(), to_mule, new /datum/bot_step/load_mule(), new /datum/bot_step/send_mule())
	return list(S)

/datum/bot_goal/deliver_crate/by_mule/on_success(datum/bot_brain/bot)
	var/list/delivery = GLOB.bot_cargo_deliveries[pack_type]
	if(delivery)
		GLOB.bot_delivered_crates[target] = delivery
		GLOB.bot_cargo_deliveries -= pack_type
		bot_tally("crates sent by MULE")
		bot_say(bot.owner, ";[capitalize(delivery[1])], your [lowertext(target.name)]'s on its way on [mule]. It'll be at your delivery point.")
	bot.continue_cargo_round()

/datum/bot_goal/deliver_crate/by_mule/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(mule)
		LAZYSET(bot.cargo_blocked, mule, world.time + 3 MINUTES) //carried round by hand next time

/// The crate, pulled up beside the MULE, dragged onto it
/datum/bot_step/load_mule/execute(datum/bot_brain/bot)
	var/datum/bot_goal/deliver_crate/by_mule/G = bot.current_goal
	var/obj/structure/closet/crate/C = G?.target
	var/mob/living/simple_animal/bot/mulebot/M = G?.mule
	if(!istype(G) || !istype(C) || QDELETED(C) || !bot_mule_free(M) || !bot.owner.Adjacent(M))
		return GOAL_STEP_FAIL
	bot.owner.stop_pulling()
	bot.human_pause(M)
	if(QDELETED(C) || !bot_mule_free(M) || !bot.owner.Adjacent(M) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(M)
	bot.telemetry_event("drag", list("target" = "[C]", "onto" = "[M]"))
	M.MouseDrop_T(C, bot.owner)
	return M.load == C ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Its controls opened with an ID, the destination set to the department's beacon, Go, and locked again
/datum/bot_step/send_mule/execute(datum/bot_brain/bot)
	var/datum/bot_goal/deliver_crate/by_mule/G = bot.current_goal
	var/mob/living/simple_animal/bot/mulebot/M = G?.mule
	if(!istype(G) || QDELETED(M) || M.load != G.target || !bot.owner.Adjacent(M))
		return GOAL_STEP_FAIL
	var/obj/item/card/id/card = bot.owner.get_idcard(TRUE)
	var/was_locked = M.locked
	if(was_locked)
		if(!card)
			return GOAL_STEP_FAIL
		M.attackby(card, bot.owner)
		if(M.locked)
			return GOAL_STEP_FAIL
	bot.human_pause(M)
	if(QDELETED(M) || !bot.owner.Adjacent(M))
		return GOAL_STEP_FAIL
	bot.telemetry_event("mule", list("target" = "[M]", "destination" = G.beacon_tag))
	M.set_destination(G.beacon_tag)
	M.bot_control("go", bot.owner)
	if(was_locked && !M.locked)
		M.attackby(card, bot.owner)
	if(M.mode != BOT_DELIVER)
		bot_log(bot, "[M] wouldn't set off for [G.beacon_tag]")
		return GOAL_STEP_FAIL
	bot_log(bot, "sent [G.target] to [G.beacon_tag] on [M]")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Materials with nobody mining
// ---------------------------------------------------------------------------------------------

// Mining called for with no miner on shift: a cargo technician says so and orders it from CentCom, to go round when it comes. In the
// user's round there were no miners, and "Mining we need materials" and "Mining, science needs silver" on Common got no answer at all.

/// What there is a crate of, by the word people ask with
GLOBAL_LIST_INIT(bot_material_packs, list(
	"silver" = /datum/supply_pack/materials/silver20, "gold" = /datum/supply_pack/materials/gold20,
	"diamond" = /datum/supply_pack/materials/diamond20, "diamonds" = /datum/supply_pack/materials/diamond20,
	"plasma" = /datum/supply_pack/materials/plasma20, "uranium" = /datum/supply_pack/materials/uranium20,
	"titanium" = /datum/supply_pack/materials/titanium20, "bananium" = /datum/supply_pack/materials/bananium20,
	"plasteel" = /datum/supply_pack/materials/plasteel20, "metal" = /datum/supply_pack/materials/metal50,
	"iron" = /datum/supply_pack/materials/metal50, "glass" = /datum/supply_pack/materials/glass50,
	"plastic" = /datum/supply_pack/materials/plastic50,
))

/// Departments by the words for them, for who a request's for
GLOBAL_LIST_INIT(bot_department_words, list(
	"science" = "science", "research" = "science", "rnd" = "science", "r&d" = "science", "robotics" = "science", "toxins" = "science",
	"medbay" = "medical", "medical" = "medical", "chemistry" = "medical", "engineering" = "engineering", "atmos" = "engineering",
	"security" = "security", "brig" = "security", "bridge" = "command",
))

/// Whose ask a technician has just answered, so the rest of Cargo leaves it: REF -> when
GLOBAL_LIST_EMPTY(bot_materials_answered)

/datum/bot_brain
	/// Asked what material they need: who, and until when the answer's taken as one
	var/datum/weakref/materials_asker
	var/materials_ask_until = 0

/// The material a line asks for, by its word
/proc/bot_material_named(lower_msg)
	for(var/word in GLOB.bot_material_packs)
		if(bot_text_has_any(lower_msg, list(word)))
			return word
	return null

/// The department somebody works for, the way you'd guess it: their job, or where they are
/proc/bot_department_of_person(mob/living/L)
	var/job = L?.mind?.assigned_role
	for(var/department in list("science", "medical", "engineering", "security", "supply", "command"))
		if(job in bot_positions_of(department))
			return department
	return L ? bot_department_of(get_area(L)) : null

/// A cargo technician told Mining's wanted when nobody's mining: it says so and orders the crate in, for whoever it's for (named, or
/// the asker's department). Asked for "materials", it asks which. TRUE if it answered.
/datum/bot_brain/proc/order_materials_for(mob/living/talker, lower_msg, radio_freq)
	if(!(work_role() in list("Cargo Technician", "Quartermaster")) || state == BOT_STATE_COMBAT || !isliving(talker))
		return FALSE
	var/asker_key = REF(talker)
	if(world.time < GLOB.bot_materials_answered[asker_key] + 3 SECONDS)
		return TRUE //another technician's answering
	var/what = bot_material_named(lower_msg)
	if(!what && !bot_text_has_any(lower_msg, list("need", "needs", "want", "could", "can", "send", "get", "materials", "minerals", "ore", "please")))
		return FALSE
	GLOB.bot_materials_answered[asker_key] = world.time
	var/prefix = bot_radio_prefix(radio_freq)
	var/them = talker.first_name()
	talking_to(talker)
	if(!what)
		materials_asker = WEAKREF(talker)
		materials_ask_until = world.time + 1 MINUTES
		say_after_typing(prefix + "[them], nobody's mining today. What do you need? I can order metal, glass, silver, gold, plasma, the lot.")
		return TRUE
	materials_asker = null
	var/pack_type = GLOB.bot_material_packs[what]
	for(var/datum/bot_request/R as anything in GLOB.bot_cargo_requests)
		if(R.detail == pack_type)
			say_after_typing(prefix + "[them], the [what]'s already on order. It'll come round when it's in.")
			return TRUE
	var/department = null
	for(var/word in GLOB.bot_department_words)
		if(bot_text_has_any(lower_msg, list(word)))
			department = GLOB.bot_department_words[word]
			break
	department = department || bot_department_of_person(talker)
	var/datum/bot_request/R = new
	R.caller_ref = WEAKREF(talker)
	R.detail = pack_type
	R.made = world.time
	R.radio_freq = radio_freq
	GLOB.bot_cargo_requests |= R
	if(department && department != "supply")
		GLOB.bot_cargo_deliveries[pack_type] = list(department, null)
	bot_log(src, "nobody mining: ordering [what] for [department || them]")
	bot_tally("materials ordered with nobody mining")
	var/datum/supply_pack/P = SSshuttle.supply_packs[pack_type]
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	var/spendable = bot_cargo_spendable(budget)
	if(P && budget && P.cost > spendable)
		say_after_typing(prefix + "[them], nobody's mining today, and the [lowertext(P.name)] is [P.cost] credits. Cargo's got [max(0, spendable)] to spend; I'll order it once we can afford it.")
		return TRUE
	say_after_typing(prefix + pick("[them], nobody's mining today. I'll order you some [what] from CentCom.", "No miners on, [them]. I'll get some [what] sent up from CentCom."))
	return TRUE

#undef BOT_CARGO_ASK_GAP
#undef BOT_BACKUP_GAP
