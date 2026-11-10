// The R&D bench: what the department does with research once it has it. All of it goes through the same machines a player
// uses.
//
//  - sheets off the lab tables go into the protolathe to start with (remote_materials OnAttackBy(): they land in the ore
//    silo, which every lathe draws on). After that the materials are what Mining brings up (goals/mining.dm), and when a
//    print is short of something the department says so on the radio, and the miners dig that first.
//  - the protolathe prints what's been researched (production/user_try_print_id()), onto its own tile.
//  - an RPED carries the new parts round: panel open, a click with the RPED, panel shut (exchange_parts()). It's too big for
//    any bag, so it's carried in a hand, and left at the lathe between jobs for whoever wants it next. The lab goes first,
//    then the machines that pay the station back, the ore redemption machine before anything.
//  - a lathe's panel coming open unlinks it from the console (rnd/attackby()), so the console's Sync goes after it.
//  - the parts the RPED swaps out are reused on lesser machines, and the junk goes in the destructive analyzer, which puts
//    their materials back in the silo.

/// Silo metal or glass below which the sheets on the lab tables go into the lathe, in sheets.
#define BOT_RND_LOW_SHEETS 20
/// How long between asking the department heads and the miners for something: nobody wants it every minute.
#define BOT_RND_ASK_GAP (6 MINUTES)
/// Spare parts of each kind kept in the RPED that aren't the best researched, for lesser machines: the rest are scrap (the user's ruling,
/// 2026-11-08: "analyzer, keep a few").
#define BOT_RPED_KEEP_SPARES 3
/// Free room in the RPED below which the junk goes in the analyzer before anything more is printed.
#define BOT_RPED_LOW_ROOM 8
/// Machines in one upgrade round at most.
#define BOT_ROUND_MACHINES 8
/// How far a bluespace RPED is used from, in tiles, with the machine in sight.
#define BOT_BRPED_RANGE 6

/// Design ids for each kind of part, best first. Cells too (2026-11-08): the SMES, the cyborg chargers and the chem dispensers take them.
GLOBAL_LIST_INIT(bot_part_designs, list(
	/obj/item/stock_parts/manipulator = list("femto_mani", "pico_mani", "nano_mani"),
	/obj/item/stock_parts/matter_bin = list("bluespace_matter_bin", "super_matter_bin", "adv_matter_bin"),
	/obj/item/stock_parts/micro_laser = list("quadultra_micro_laser", "ultra_micro_laser", "high_micro_laser"),
	/obj/item/stock_parts/scanning_module = list("triphasic_scanning", "phasic_scanning", "adv_scanning"),
	/obj/item/stock_parts/capacitor = list("quadratic_capacitor", "super_capacitor", "adv_capacitor"),
	/obj/item/stock_parts/cell = list("bluespace_cell", "hyper_cell", "super_cell", "high_cell"),
))

/// The best part tier researched so far, of the five stock part kinds: 1 to 4.
/proc/bot_best_researched_tier()
	. = 1
	for(var/kind in GLOB.bot_part_designs)
		if(ispath(kind, /obj/item/stock_parts/cell))
			continue
		for(var/id in GLOB.bot_part_designs[kind])
			var/datum/design/D = bot_researched_design(id)
			if(D)
				. = max(., bot_design_rating(D))
				break

/// The tier last announced on the radio: a new one starts a round right away.
GLOBAL_VAR_INIT(bot_part_tier_announced, 1)

/// Which of GLOB.bot_part_designs' kinds a part is, if any.
/proc/bot_part_kind(obj/item/part)
	for(var/kind in GLOB.bot_part_designs)
		if(istype(part, kind))
			return kind

/// What the best researched design of a kind rates, or 0.
/proc/bot_best_researched_value(kind)
	for(var/id in GLOB.bot_part_designs[kind])
		var/datum/design/D = bot_researched_design(id)
		if(D)
			return bot_design_rating(D)
	return 0

/// Free room in an RPED, in parts.
/proc/bot_rped_room(obj/item/storage/part_replacer/rped)
	var/datum/component/storage/S = rped.GetComponent(/datum/component/storage)
	return S ? max(0, S.max_items - length(rped.contents)) : 0

/// What in the RPED is junk: a tier 1 part (nothing it could go in is worse) or a basic cell, and of each kind, beyond the best few spares
/// that aren't the best researched. The best researched never is: it's what the round is for. Worst first.
/proc/bot_rped_junk(obj/item/storage/part_replacer/rped)
	. = list()
	var/list/kept = list()
	for(var/obj/item/part in sortTim(rped.contents.Copy(), GLOBAL_PROC_REF(cmp_rped_sort)))
		var/kind = bot_part_kind(part)
		if(!kind)
			continue
		var/value = part.get_part_rating()
		if(value >= bot_best_researched_value(kind))
			continue
		var/obj/item/stock_parts/cell/C = part
		var/lowest = istype(C) ? C.maxcharge < 10000 : value <= 1
		if(lowest || kept[kind] >= BOT_RPED_KEEP_SPARES)
			. += part
		else
			kept[kind]++
	reverseRange(.)

/// What gets upgraded, first things first (the user's ruling, 2026-11-04): Science's own lathes and printers, which save materials on
/// everything printed after them, and every other lathe; then Medbay; then the rest of Science; then the rest of the station, a
/// department at a time. Emitters and collectors are left be: new parts change how the engine runs, and that's Engineering's call.
GLOBAL_LIST_INIT(bot_upgrade_order, list(
	/obj/machinery/rnd/production/protolathe,
	/obj/machinery/rnd/production/circuit_imprinter,
	/obj/machinery/rnd/production/techfab,
	/obj/machinery/mecha_part_fabricator,
	/obj/machinery/autolathe,
	/obj/machinery/mineral/ore_redemption,
	/obj/machinery/sleeper,
	/obj/machinery/atmospherics/components/unary/cryo_cell,
	/obj/machinery/clonepod,
	/obj/machinery/dna_scannernew,
	/obj/machinery/chem_dispenser,
	/obj/machinery/chem_heater,
	/obj/machinery/limbgrower,
	/obj/machinery/rnd/destructive_analyzer,
	/obj/machinery/rnd/experimentor,
	/obj/machinery/atmospherics/components/unary/thermomachine/heater,
	/obj/machinery/atmospherics/components/unary/thermomachine/freezer,
	/obj/machinery/nanite_chamber,
	/obj/machinery/monkey_recycler,
	/obj/machinery/processor,
	/obj/machinery/power/smes,
	/obj/machinery/power/port_gen/pacman,
	/obj/machinery/recharge_station,
	/obj/machinery/mech_bay_recharge_port,
	/obj/machinery/recharger,
	/obj/machinery/cell_charger,
	/obj/machinery/hydroponics/constructable,
	/obj/machinery/biogenerator,
	/obj/machinery/seed_extractor,
	/obj/machinery/plantgenes,
	/obj/machinery/microwave,
	/obj/machinery/gibber,
	/obj/machinery/smoke_machine,
	/obj/machinery/space_heater,
))

/// When the department last asked for each material.
GLOBAL_LIST_EMPTY(bot_material_asked)

/datum/bot_brain
	var/designs_printed = 0
	var/machines_upgraded = 0
	var/items_analyzed = 0
	/// Machine -> when it's worth another look at upgrading it.
	var/list/upgrade_blocked
	var/rnd_bench_blocked_until = 0

/// A machine counts as part of the lab if it's in Science. A Bot Gym bot's lab is its arena.
/datum/bot_brain/proc/in_science(atom/A)
	var/area/where = get_area(A)
	return gym_run ? (where == get_area(owner)) : istype(where, /area/science)

/// The department's protolathe, free and powered: it has to be one the console is linked to, or one that doesn't need it.
/datum/bot_brain/proc/find_lathe()
	var/obj/machinery/rnd/production/protolathe/best
	var/best_dist
	for(var/obj/machinery/rnd/production/protolathe/L as anything in bot_instances_of(/obj/machinery/rnd/production/protolathe))
		if(QDELETED(L) || L.z != owner.z || !in_science(L) || L.panel_open || (L.stat & (BROKEN|NOPOWER)) || !L.materials?.mat_container || L.materials.on_hold())
			continue
		if(L.requires_console && !L.linked_console)
			continue
		var/dist = get_dist(owner, L)
		if(!best || dist < best_dist)
			best = L
			best_dist = dist
	return best

/// How many sheets of a material the lathe has to work with.
/proc/bot_lathe_sheets(obj/machinery/rnd/production/L, mat)
	return L?.materials?.mat_container ? L.materials.mat_container.amount(mat) / MINERAL_MATERIAL_AMOUNT : 0

/// Whether the lathe can print this much of this design right now, parts efficiency and all. What it's short of goes in `short`.
/proc/bot_lathe_can_afford(obj/machinery/rnd/production/L, datum/design/D, amount, list/short)
	. = TRUE
	var/coeff = L.efficient_with(D.build_path) ? L.efficiency_coeff : 1
	for(var/mat in D.materials)
		if(L.materials.mat_container.amount(mat) < D.materials[mat] / coeff * amount)
			. = FALSE
			short?[mat] = TRUE

/// Says on the radio what the lab has run out of, unless it's been said lately, and tells the miners what to dig first.
/datum/bot_brain/proc/ask_for_materials(list/short)
	var/list/names = list()
	for(var/mat in short)
		GLOB.bot_wanted_minerals[mat] = world.time
		if(world.time >= GLOB.bot_material_asked[mat] + BOT_RND_ASK_GAP)
			GLOB.bot_material_asked[mat] = world.time
			names += lowertext(CallMaterialName(mat))
	if(!length(names) || gym_scripted)
		return
	// Nobody on the rock, or nothing's come of asking: what comes in a crate, Cargo can send (bot_collabs.dm).
	if(MAT_METAL in short)
		ask_cargo_for(/datum/supply_pack/materials/metal50, "some metal", "science", /obj/item/stack/sheet/metal)
	else if(MAT_GLASS in short)
		ask_cargo_for(/datum/supply_pack/materials/glass50, "some glass", "science", /obj/item/stack/sheet/glass)
	if(!is_science_job())
		say_after_typing(";[pick("Mining, could use some [english_list(names)] in the silo for the techfab.", "Anyone got [english_list(names)]? The techfab's out.")]")
		return
	say_after_typing(";[pick("Mining, R&D is out of [english_list(names)]. Anything you can bring up would help.", "Could use more [english_list(names)] in the silo, Mining.", "We're short on [english_list(names)] up here in Science. Can Mining dig some up?")]")

/// A design the station has researched, if it's a real one.
/proc/bot_researched_design(id)
	if(!SSresearch.science_tech.researched_designs[id])
		return null
	var/datum/design/D = SSresearch.techweb_design_by_id(id)
	return (istype(D) && D != SSresearch.error_design) ? D : null

/// What a design's part rates as the RPED sees it (get_part_rating()): its tier, or a cell's tier times its capacity.
/proc/bot_design_rating(datum/design/D)
	var/obj/item/stock_parts/part = D.build_path
	if(ispath(part, /obj/item/stock_parts/cell))
		var/obj/item/stock_parts/cell/C = part
		return initial(C.rating) * initial(C.maxcharge)
	return initial(part.rating)

/// Design id -> how many of it would bring this machine up to the best that's been researched.
/datum/bot_brain/proc/parts_to_upgrade(obj/machinery/M)
	. = list()
	var/obj/item/circuitboard/machine/board = locate() in M.component_parts
	if(!board)
		return
	for(var/obj/item/stock_parts/part in M.component_parts)
		for(var/kind in GLOB.bot_part_designs)
			if(!istype(part, kind))
				continue
			var/worth_it = FALSE
			for(var/path in board.req_components)
				if(ispath(path, kind))
					worth_it = TRUE
			if(!worth_it)
				break
			for(var/id in GLOB.bot_part_designs[kind])
				var/datum/design/D = bot_researched_design(id)
				if(D && bot_design_rating(D) > part.get_part_rating())
					.[id]++
					break
			break

/// The RPED this bot has on it, or the one left by its own lathe: Science's for Science, its department's for anybody else. Three
/// engineers set off one after another for the lab's, behind doors none of them could open. A bluespace one before a plain one.
/datum/bot_brain/proc/find_rped()
	var/obj/item/storage/part_replacer/R = find_carried_tool(/obj/item/storage/part_replacer/bluespace) || find_carried_tool(/obj/item/storage/part_replacer)
	if(R)
		return R
	var/science = is_science_job()
	var/obj/item/storage/part_replacer/plain
	glance_at_items()
	for(var/obj/item/storage/part_replacer/loose as anything in bot_instances_of(/obj/item/storage/part_replacer))
		if(QDELETED(loose) || !isturf(loose.loc) || loose.z != owner.z || taken_by_another(loose) || !knows_of_in_room(loose)) //what it knows of, or can see round the room (bot_knowledge.dm)
			continue
		if(science ? in_science(loose) : (gym_run ? get_area(loose) == get_area(owner) : is_my_department(get_area(loose))))
			if(loose.works_from_distance)
				return loose
			plain = plain || loose
	return plain

/// Somebody else in its department out with the department's RPED just now: one at a time, as Science goes.
/datum/bot_brain/proc/department_rped_in_use()
	var/mine = department()
	for(var/obj/item/storage/part_replacer/R as anything in bot_instances_of(/obj/item/storage/part_replacer))
		if(QDELETED(R) || isturf(R.loc) || R.loc == owner)
			continue
		var/mob/living/carbon/human/holder = bot_outermost_holder(R)
		if(istype(holder) && holder != owner && holder.bot_brain && holder.bot_brain.department() == mine && (!gym_run || holder.bot_brain.gym_run == gym_run))
			return TRUE
	return FALSE

/// Whether somebody else in the department is going round with the RPED. A lab has the one, and they don't queue up to print
/// a second: two scientists used to print the same bins a couple of hundred times between them, for parts neither could carry.
/datum/bot_brain/proc/rped_in_use_by_another()
	for(var/obj/item/storage/part_replacer/R as anything in bot_instances_of(/obj/item/storage/part_replacer))
		if(QDELETED(R) || isturf(R.loc) || R.loc == owner)
			continue
		var/turf/T = get_turf(R) //its own z is 0, in somebody's hand
		if(T?.z != owner.z || (gym_run && !in_science(T)))
			continue
		// Science's: one an engineer printed at the Engineering techfab for its own machines isn't the lab's to wait on.
		var/mob/living/carbon/human/holder = bot_outermost_holder(R)
		if(istype(holder) && holder.bot_brain ? holder.bot_brain.is_science_job() : in_science(T))
			return TRUE
	return FALSE

/// What the RPED doesn't already hold and isn't waiting at the lathe, of the upgrade lists of a machine or a round of them. Parts swapped
/// out of a better machine do for a worse one.
/datum/bot_brain/proc/parts_still_to_print(machines, obj/item/storage/part_replacer/rped, obj/machinery/rnd/production/L)
	. = list()
	for(var/obj/machinery/M in (islist(machines) ? machines : list(machines)))
		var/list/need = parts_to_upgrade(M)
		for(var/id in need)
			.[id] += need[id]
	if(!rped)
		return
	var/list/spares = rped.contents.Copy()
	for(var/obj/item/stock_parts/waiting in get_turf(L))
		spares += waiting
	for(var/id in .)
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		var/rating = bot_design_rating(D)
		for(var/obj/item/stock_parts/part in spares)
			if(!.[id])
				break
			if(istype(part, D.build_path) || (part.get_part_rating() >= rating && bot_same_part_kind(part, D.build_path)))
				spares -= part
				.[id]--
		if(!.[id])
			. -= id

/proc/bot_same_part_kind(obj/item/stock_parts/part, build_path)
	for(var/kind in GLOB.bot_part_designs)
		if(istype(part, kind))
			return ispath(build_path, kind)
	return FALSE

/// The next machine that could do with better parts and that this bot can have a go at.
/datum/bot_brain/proc/next_upgrade_target(list/exclude)
	// Somewhere somebody asked for (bot_asks.dm) goes first.
	if(upgrade_wanted_in && world.time < upgrade_wanted_until)
		for(var/machine_type in GLOB.bot_upgrade_order)
			for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
				if(QDELETED(M) || (M in exclude) || get_area(M) != upgrade_wanted_in || M.panel_open || (M.stat & BROKEN) || !length(M.component_parts))
					continue
				if(LAZYACCESS(upgrade_blocked, M) > world.time || taken_by_another(M) || !length(parts_to_upgrade(M)) || !can_walk_lawfully_to(M))
					continue
				return M
		upgrade_wanted_in = null
	for(var/machine_type in GLOB.bot_upgrade_order)
		for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
			if(QDELETED(M) || (M in exclude) || M.z != owner.z || M.panel_open || (M.stat & BROKEN) || !length(M.component_parts))
				continue
			if(gym_run && !in_science(M))
				continue
			if(LAZYACCESS(upgrade_blocked, M) > world.time || taken_by_another(M) || !length(parts_to_upgrade(M)))
				continue
			// Toxins' heater and freezer, that is. The rest belong to Atmospherics, and one is keeping the slime kill room cold.
			if(istype(M, /obj/machinery/atmospherics/components/unary/thermomachine) && !istype(get_area(M), /area/science/mixing))
				continue
			// The machines in other departments, when this bot's ID goes there. Nobody prints the parts first and finds out at the door.
			if(!in_science(M) && !can_walk_lawfully_to(M))
				LAZYSET(upgrade_blocked, M, world.time + 15 MINUTES)
				continue
			return M
	return null

/// A stack of sheets lying in the lab, for the lathe.
/datum/bot_brain/proc/find_lab_sheets(sheet_type)
	for(var/obj/item/stack/sheet/S as anything in bot_instances_of(sheet_type))
		if(!QDELETED(S) && isturf(S.loc) && S.z == owner.z && S.amount >= 10 && (gym_run ? in_science(S) : istype(get_area(S), /area/science/lab)) && !taken_by_another(S))
			return S
	return null

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/rnd_bench
	name = "R&D bench"
	jobs = list("Scientist", "Research Director")
	interval_min = 150
	interval_max = 400

/datum/bot_duty/rnd_bench/try_start(datum/bot_brain/bot)
	if(world.time < bot.rnd_bench_blocked_until)
		return FALSE
	var/obj/machinery/left_open = bot.find_panel_left_open()
	if(left_open)
		return bot.assign_goal(new /datum/bot_goal/close_panel(left_open))
	var/obj/machinery/rnd/production/protolathe/lathe = bot.find_lathe()
	if(!lathe)
		// A lathe left unlinked by somebody's upgrade: the console's Sync sorts that out.
		var/obj/machinery/computer/rdconsole/console = bot.find_rd_console()
		if(console && !console.linked_lathe)
			return bot.assign_goal(new /datum/bot_goal/sync_console())
		return FALSE
	for(var/mat in list(MAT_METAL = /obj/item/stack/sheet/metal, MAT_GLASS = /obj/item/stack/sheet/glass))
		if(bot_lathe_sheets(lathe, mat) < BOT_RND_LOW_SHEETS)
			var/obj/item/stack/sheet/S = bot.find_lab_sheets(list(MAT_METAL = /obj/item/stack/sheet/metal, MAT_GLASS = /obj/item/stack/sheet/glass)[mat])
			if(S)
				return bot.assign_goal(new /datum/bot_goal/stock_lathe(S))
	if(lathe.busy || bot.rped_in_use_by_another())
		return FALSE
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!rped)
		var/datum/design/D = bot_researched_design("bs_rped") || bot_researched_design("rped")
		if(!D)
			return FALSE
		return bot.print_or_ask(lathe, D, 1)
	// A new tier researched: said on the radio, and a round straight away with what's been printed of it (the user's ruling, 2026-11-08).
	var/tier = bot_best_researched_tier()
	if(tier > GLOB.bot_part_tier_announced)
		GLOB.bot_part_tier_announced = tier
		bot.upgrade_round = null
		if(!bot.gym_scripted)
			bot.say_after_typing(";[pick("Tier [tier] parts are researched. Doing an upgrade round.", "We've got tier [tier] parts now, going round upgrading.", "Tier [tier] stock parts are in. Upgrade round starting.")]")
	// The bluespace RPED once it's researched, between rounds: it works from across the room, no screwdriver, no panel, no lathe unlinked.
	if(!rped.works_from_distance && !length(bot.upgrade_round))
		var/obj/item/storage/part_replacer/bluespace/brped = locate() in get_turf(lathe)
		if(brped && !bot.taken_by_another(brped))
			return bot.assign_goal(new /datum/bot_goal/switch_to_brped(brped, rped))
		var/datum/design/BS = bot_researched_design("bs_rped")
		if(BS && world.time >= bot.brped_print_after)
			bot.brped_print_after = world.time + 10 MINUTES
			if(bot.print_or_ask(lathe, BS, 1))
				return TRUE
	// Prints left on the tile go in first, with room made if it's full
	var/obj/item/stock_parts/waiting = bot_parts_to_collect(lathe)
	if(waiting && bot_rped_room(rped) < 1 && length(bot_rped_junk(rped)))
		return bot.assign_goal(new /datum/bot_goal/put_rped_back/scrap_only(rped))
	if(waiting)
		return bot.assign_goal(new /datum/bot_goal/collect_prints(lathe))
	bot.prune_upgrade_round(rped)
	if(!length(bot.upgrade_round))
		// Junk out before planning, so there's room for the next round's parts
		if(bot_rped_room(rped) < BOT_RPED_LOW_ROOM && length(bot_rped_junk(rped)))
			return bot.assign_goal(new /datum/bot_goal/put_rped_back/scrap_only(rped))
		bot.upgrade_round = bot.plan_upgrade_round(rped)
		bot.upgrade_round_fitting = FALSE
		if(!length(bot.upgrade_round))
			if(length(bot_rped_junk(rped)) || (rped in bot.owner.held_items))
				return bot.assign_goal(new /datum/bot_goal/put_rped_back(rped))
			return FALSE
		bot_log(bot, "upgrade round: [english_list(bot.upgrade_round)]")
	// Everything for the round printed first, then the machines one after another, the nearest next
	if(!bot.upgrade_round_fitting)
		var/list/to_print = bot.parts_still_to_print(bot.upgrade_round, rped, lathe)
		if(length(to_print))
			var/id = to_print[1]
			// Only as much as the RPED will take
			var/amount = min(to_print[id], max(1, bot_rped_room(rped) - bot_prints_waiting(lathe, /obj/item/stock_parts)))
			if(bot.print_or_ask(lathe, SSresearch.techweb_design_by_id(id), amount))
				return TRUE
		// Printed, or the silo's short: off round with what there is
		bot.upgrade_round_fitting = TRUE
	var/obj/machinery/M = bot.next_in_round(rped)
	if(!M)
		// Nothing to fit (the silo's short of something): the bench rests rather than planning the same round every few seconds, as a
		// scientist did forty times in one shift
		bot.upgrade_round = null
		bot.rnd_bench_blocked_until = world.time + 3 MINUTES
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/fit_upgrades(M))

/datum/bot_brain
	/// The machines this round's parts are for: printed for all at once, then fitted one after another.
	var/list/upgrade_round
	/// Fitting's begun: nothing more gets printed until the round's done.
	var/upgrade_round_fitting = FALSE
	/// When it'll next try printing a bluespace RPED.
	var/brped_print_after = 0

/// A round of machines, by the usual order: as many as the RPED has room for the parts of, BOT_ROUND_MACHINES at most. The first one
/// always, whatever it needs.
/datum/bot_brain/proc/plan_upgrade_round(obj/item/storage/part_replacer/rped, department = FALSE)
	. = list()
	var/budget = bot_rped_room(rped)
	if(!budget) // full up with old parts: nothing printed would go in
		return
	var/parts = 0
	while(length(.) < BOT_ROUND_MACHINES)
		var/obj/machinery/M = department ? next_department_upgrade(.) : next_upgrade_target(.)
		if(!M)
			break
		var/list/need = parts_to_upgrade(M)
		var/n = 0
		for(var/id in need)
			n += need[id]
		if(length(.) && parts + n > budget)
			break
		. += M
		parts += n

/// Drops what's done, gone, opened by somebody else or given up on from the round.
/datum/bot_brain/proc/prune_upgrade_round(obj/item/storage/part_replacer/rped)
	for(var/obj/machinery/M as anything in upgrade_round)
		if(QDELETED(M) || M.panel_open || (M.stat & BROKEN) || LAZYACCESS(upgrade_blocked, M) > world.time || taken_by_another(M) || !length(parts_to_upgrade(M)))
			upgrade_round -= M
	if(!length(upgrade_round))
		upgrade_round = null
		upgrade_round_fitting = FALSE

/// The nearest machine of the round the RPED has something better for.
/datum/bot_brain/proc/next_in_round(obj/item/storage/part_replacer/rped)
	var/obj/machinery/best
	var/best_dist
	for(var/obj/machinery/M as anything in upgrade_round)
		if(!M.rped_upgrade_count(rped))
			continue
		var/dist = get_dist(owner, M) + (M.z != owner.z ? 1000 : 0)
		if(!best || dist < best_dist)
			best = M
			best_dist = dist
	return best

/// Prints it if the lathe can, and says so on the radio if it can't.
/datum/bot_brain/proc/print_or_ask(obj/machinery/rnd/production/L, datum/design/D, amount)
	var/list/short = list()
	if(!bot_lathe_can_afford(L, D, amount, short))
		// Down to one at a time before giving up on it: a little in the silo can still go a little way.
		if(amount > 1 && bot_lathe_can_afford(L, D, 1))
			amount = 1
		else
			ask_for_materials(short)
			return FALSE
	return assign_goal(new /datum/bot_goal/print_design(L, D, amount))

// ---------------------------------------------------------------------------------------------
// Stocking the lathe
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/stock_lathe
	lawful = TRUE
	exclusive = TRUE
	doing = "stocking the lathe"
	var/obj/item/stack/sheet/sheets

/datum/bot_goal/stock_lathe/New(obj/item/stack/sheet/S)
	. = ..()
	sheets = S

/datum/bot_goal/stock_lathe/resolve_target(datum/bot_brain/bot)
	target = !QDELETED(sheets) && bot.find_lathe()

/datum/bot_goal/stock_lathe/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/feed_lathe())
	return list(S)

/datum/bot_goal/stock_lathe/on_give_up(datum/bot_brain/bot)
	bot.rnd_bench_blocked_until = world.time + 2 MINUTES

/// Fetches the stack, walks it to the machine, clicks. Runs again after each leg, from wherever things have got to.
/datum/bot_step/feed_lathe
	var/fetched = FALSE
	var/walked = FALSE

/datum/bot_step/feed_lathe/execute(datum/bot_brain/bot)
	var/datum/bot_goal/stock_lathe/G = bot.current_goal
	var/obj/machinery/rnd/production/protolathe/L = G?.target
	if(!istype(G) || !istype(L) || QDELETED(L))
		return GOAL_STEP_FAIL
	if(QDELETED(G.sheets))
		return GOAL_STEP_SUCCESS
	if(isturf(G.sheets.loc))
		if(fetched)
			return GOAL_STEP_FAIL
		fetched = TRUE
		return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(G.sheets)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(L))
		if(walked)
			return GOAL_STEP_FAIL
		walked = TRUE
		return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(L)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	var/amount = G.sheets.amount
	var/kind = G.sheets.name
	bot_log(bot, "feeding [amount] [kind] to [L]")
	if(!bot.use_tool_on(G.sheets, L))
		return GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Printing
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/print_design
	lawful = TRUE
	exclusive = TRUE //one at a lathe
	doing = "printing something at the lathe"
	var/datum/design/design
	var/amount = 1

/datum/bot_goal/print_design/New(obj/machinery/rnd/production/L, datum/design/D, amount)
	. = ..()
	target = L
	design = D
	src.amount = amount

/datum/bot_goal/print_design/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/rnd/production/L = target
	if(QDELETED(L) || L.busy)
		target = null

/datum/bot_goal/print_design/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/print_design())
	return list(S)

/datum/bot_goal/print_design/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/duty = bot_duty_of(chain_duty)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/print_design/on_give_up(datum/bot_brain/bot)
	bot.rnd_bench_blocked_until = world.time + 2 MINUTES

/// A printed part lying on the lathe's tile, the RPED's business. Cells and the rest of what gets left around aren't.
/proc/bot_parts_to_collect(obj/machinery/M)
	for(var/obj/item/stock_parts/part in get_turf(M))
		for(var/kind in GLOB.bot_part_designs)
			if(istype(part, kind))
				return part
	return null

/// How many of a thing are sat on a machine's tile.
/proc/bot_prints_waiting(obj/machinery/M, build_path)
	. = 0
	for(var/obj/item/I in get_turf(M))
		if(istype(I, build_path))
			.++

/// The button, and a wait: the print turns up on the lathe's own tile when it's done.
/datum/bot_step/paced/print_design
	max_clicks = 200
	var/started = FALSE
	var/waited = 0

/datum/bot_step/paced/print_design/start(datum/bot_brain/bot)
	started = FALSE
	waited = 0
	return TRUE

/datum/bot_step/paced/print_design/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/print_design/G = bot.current_goal
	var/obj/machinery/rnd/production/L = G?.target
	if(!istype(G) || !istype(L) || QDELETED(L) || (L.stat & (BROKEN|NOPOWER)))
		return FALSE
	if(started)
		if(bot_prints_waiting(L, G.design.build_path) >= G.amount)
			return FALSE
		waited += 10
		wait_for = 10
		return waited < 600 //watching it print
	if(L.busy || !bot.owner.Adjacent(L))
		return FALSE
	bot.human_pause(L)
	if(QDELETED(L) || L.busy || !bot.owner.Adjacent(L))
		return FALSE
	bot.owner.face_atom(L)
	bot.telemetry_ui_action(L, "print [G.design.name]")
	if(!L.user_try_print_id(G.design.id, G.amount))
		bot_log(bot, "the lathe wouldn't print [G.design.name]")
		return FALSE
	started = TRUE
	bot.designs_printed += G.amount
	bot_log(bot, "printing [G.amount] [G.design.name]")
	wait_for = 10
	return TRUE

/datum/bot_step/paced/print_design/finish(datum/bot_brain/bot)
	return started ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Parts sat on the lathe's tile, into the RPED: with it in a hand, a click each.
/datum/bot_goal/collect_prints
	lawful = TRUE
	exclusive = TRUE
	doing = "collecting what the lathe made"

/datum/bot_goal/collect_prints/New(obj/machinery/rnd/production/L)
	. = ..()
	target = L

/datum/bot_goal/collect_prints/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/collect_prints/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/take_rped(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/gather_print())
	return list(S)

/datum/bot_goal/collect_prints/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/duty = bot_duty_of(chain_duty)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/collect_prints/on_give_up(datum/bot_brain/bot)
	bot.rnd_bench_blocked_until = world.time + 2 MINUTES

/datum/bot_step/paced/gather_print
	max_clicks = 30
	var/gathered = 0

/datum/bot_step/paced/gather_print/finish(datum/bot_brain/bot)
	return gathered ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/paced/gather_print/do_click(datum/bot_brain/bot)
	var/obj/machinery/rnd/production/L = bot.current_goal?.target
	if(!istype(L) || QDELETED(L) || !bot.owner.Adjacent(L))
		return FALSE
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!rped || !(rped in bot.owner.held_items))
		return FALSE
	var/obj/item/stock_parts/part = bot_parts_to_collect(L)
	if(!part)
		return FALSE
	bot.human_pause(part)
	if(QDELETED(part) || QDELETED(rped))
		return FALSE
	bot.owner.face_atom(part)
	if(!SEND_SIGNAL(rped, COMSIG_TRY_STORAGE_INSERT, part, bot.owner, TRUE))
		bot_log(bot, "[rped] wouldn't take [part]")
		return FALSE
	bot.telemetry_clicked(part)
	gathered++
	return TRUE

// ---------------------------------------------------------------------------------------------
// Fitting
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/fit_upgrades
	lawful = TRUE
	exclusive = TRUE
	doing = "upgrading a machine"

/datum/bot_goal/fit_upgrades/New(obj/machinery/M)
	. = ..()
	target = M

/datum/bot_goal/fit_upgrades/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/M = target
	if(QDELETED(M) || M.panel_open)
		target = null

/datum/bot_goal/fit_upgrades/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(rped?.works_from_distance)
		S.steps = list(new /datum/bot_step/take_rped(), new /datum/bot_step/paced/fit_from_range())
	else
		S.steps = list(new /datum/bot_step/take_rped(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/fit_upgrades())
	return list(S)

/datum/bot_goal/fit_upgrades/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.upgrade_blocked, target, world.time + 30 MINUTES)

/datum/bot_goal/fit_upgrades/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/duty = bot_duty_of(chain_duty)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/// The RPED into a hand, walking over to it if it's lying about, and a screwdriver on the bot to go with it.
/datum/bot_step/take_rped
	var/tries = 0

/datum/bot_step/take_rped/execute(datum/bot_brain/bot)
	if(++tries > 4)
		return GOAL_STEP_FAIL
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!rped)
		return GOAL_STEP_FAIL
	if(!(rped in bot.owner.held_items))
		if(isturf(rped.loc) && !bot.owner.Adjacent(rped))
			return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(rped)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if(!bot.ready_in_hand(rped))
			return GOAL_STEP_FAIL
	if(rped.works_from_distance || bot.find_carried_tool(/obj/item/screwdriver)) // the bluespace one needs no panel open
		return GOAL_STEP_SUCCESS
	var/datum/bot_goal/acquire_item_type/fetch = new()
	fetch.item_type = /obj/item/screwdriver
	fetch.lawful = TRUE
	return bot.suspend_goal_for(fetch) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// The bluespace RPED: walking until the machine's in sight and near enough, then one click from there. No panel, no screwdriver.
/datum/bot_step/paced/fit_from_range
	max_clicks = 120
	var/fitted = FALSE

/datum/bot_step/paced/fit_from_range/start(datum/bot_brain/bot)
	fitted = FALSE
	return TRUE

/datum/bot_step/paced/fit_from_range/do_click(datum/bot_brain/bot)
	var/obj/machinery/M = bot.current_goal?.target
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(fitted || !istype(M) || QDELETED(M) || !rped || !(rped in bot.owner.held_items))
		return FALSE
	if(M.z != bot.owner.z || get_dist(bot.owner, M) > BOT_BRPED_RANGE || !can_see(bot.owner, M, BOT_BRPED_RANGE))
		if(!bot.pursuing_kind)
			bot.pursue(M, "follow", force = TRUE) //not "goal": that one's arrival would end the step
		wait_for = 5
		return TRUE
	bot.stop_pursuit()
	bot.human_pause(M)
	if(QDELETED(M) || QDELETED(rped))
		return FALSE
	var/before = M.rped_upgrade_count(rped)
	fitted = TRUE
	if(!before)
		return FALSE
	bot.owner.face_atom(M)
	bot.telemetry_ui_action(M, "upgrade parts")
	if(bot.owner.Adjacent(M))
		bot.use_tool_on(rped, M)
	else
		rped.afterattack(M, bot.owner, FALSE)
	var/after = M.rped_upgrade_count(rped)
	if(after >= before)
		bot_log(bot, "[rped] did nothing to [M] from [get_dist(bot.owner, M)] tiles")
		fitted = FALSE
		return FALSE
	bot.machines_upgraded++
	bot_log(bot, "upgraded [before - after] part\s in [M] from [get_dist(bot.owner, M)] tiles")
	return FALSE

/datum/bot_step/paced/fit_from_range/finish(datum/bot_brain/bot)
	var/obj/machinery/M = bot.current_goal?.target
	if(bot.pursuing_kind)
		bot.stop_pursuit()
	if(!fitted)
		return GOAL_STEP_FAIL
	if(!bot.gym_scripted && istype(M) && !bot.in_science(M) && prob(30))
		bot.say_after_typing(pick("Better parts in [M].", "[capitalize(M.name)]'s upgraded.", "That should help."))
	return GOAL_STEP_SUCCESS

/// Panel open, RPED, panel shut, the three clicks a player makes.
/datum/bot_step/paced/fit_upgrades
	max_clicks = 8
	var/fitted = FALSE

/datum/bot_step/paced/fit_upgrades/start(datum/bot_brain/bot)
	fitted = FALSE
	return TRUE

/datum/bot_step/paced/fit_upgrades/do_click(datum/bot_brain/bot)
	var/obj/machinery/M = bot.current_goal?.target
	if(!istype(M) || QDELETED(M) || !bot.owner.Adjacent(M))
		return FALSE
	var/obj/item/screwdriver/driver = bot.find_carried_tool(/obj/item/screwdriver)
	var/obj/item/storage/part_replacer/rped = bot.find_rped()
	if(!driver || !rped)
		return FALSE
	if(fitted)
		if(!M.panel_open)
			return FALSE
		bot.use_tool_on(driver, M)
		return TRUE
	if(!M.panel_open)
		bot.use_tool_on(driver, M)
		if(!M.panel_open)
			return FALSE
		return TRUE
	var/before = M.rped_upgrade_count(rped)
	if(!before)
		fitted = TRUE
		return TRUE
	bot.telemetry_ui_action(M, "upgrade parts")
	if(!bot.use_tool_on(rped, M))
		return FALSE
	fitted = TRUE
	bot.machines_upgraded++
	bot_log(bot, "upgraded [before] part\s in [M]")
	return TRUE

/datum/bot_step/paced/fit_upgrades/finish(datum/bot_brain/bot)
	var/obj/machinery/M = bot.current_goal?.target
	// However it went. A machine left with its panel off doesn't work: an ore redemption machine left like that stopped taking
	// ore for the rest of a shift, and a lathe left like that took the whole department's printing with it.
	var/obj/item/screwdriver/driver = bot.find_carried_tool(/obj/item/screwdriver)
	if(istype(M) && !QDELETED(M) && M.panel_open && driver && bot.owner.Adjacent(M))
		bot.use_tool_on(driver, M)
	if(!fitted)
		return GOAL_STEP_FAIL
	if(!bot.gym_scripted && !bot.in_science(M) && prob(50))
		if(bot.is_science_job())
			bot.say_after_typing(";[pick("[M] has new parts in, courtesy of R&D.", "Just upgraded [M].", "[capitalize(M.name)] should run better now, R&D's been at it.")]")
		else
			bot.say_after_typing(pick("Better parts in [M].", "[capitalize(M.name)]'s upgraded.", "That should help."))
	return GOAL_STEP_SUCCESS

/// A machine the department looks after with its panel off and nobody working on it: somebody got called away.
/datum/bot_brain/proc/find_panel_left_open()
	for(var/machine_type in GLOB.bot_upgrade_order)
		for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
			if(QDELETED(M) || !M.panel_open || M.z != owner.z || taken_by_another(M) || LAZYACCESS(upgrade_blocked, M) > world.time)
				continue
			if(gym_run ? in_science(M) : TRUE)
				return M
	return null

/datum/bot_goal/close_panel
	lawful = TRUE
	exclusive = TRUE
	doing = "closing up a machine"

/datum/bot_goal/close_panel/New(obj/machinery/M)
	. = ..()
	target = M

/datum/bot_goal/close_panel/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/M = target
	if(QDELETED(M) || !M.panel_open)
		target = null

/datum/bot_goal/close_panel/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/take_screwdriver(), new /datum/bot_step/move_to(), new /datum/bot_step/shut_panel())
	return list(S)

/datum/bot_goal/close_panel/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.upgrade_blocked, target, world.time + 10 MINUTES)

/datum/bot_step/take_screwdriver
	var/tried = FALSE

/datum/bot_step/take_screwdriver/execute(datum/bot_brain/bot)
	if(bot.find_carried_tool(/obj/item/screwdriver))
		return GOAL_STEP_SUCCESS
	if(tried)
		return GOAL_STEP_FAIL
	tried = TRUE
	var/datum/bot_goal/acquire_item_type/fetch = new()
	fetch.item_type = /obj/item/screwdriver
	fetch.lawful = TRUE
	return bot.suspend_goal_for(fetch) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/datum/bot_step/shut_panel/execute(datum/bot_brain/bot)
	var/obj/machinery/M = bot.current_goal?.target
	var/obj/item/screwdriver/driver = bot.find_carried_tool(/obj/item/screwdriver)
	if(!istype(M) || QDELETED(M) || !driver || !bot.owner.Adjacent(M))
		return GOAL_STEP_FAIL
	if(M.panel_open)
		bot.use_tool_on(driver, M)
	return M.panel_open ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/// The console's Sync button, for a lathe left unlinked by a panel coming open.
/datum/bot_goal/sync_console
	lawful = TRUE
	doing = "seeing to the R&D console"

/datum/bot_goal/sync_console/resolve_target(datum/bot_brain/bot)
	target = bot.find_rd_console()

/datum/bot_goal/sync_console/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/research/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/press_sync())
	return list(S)

/datum/bot_goal/sync_console/on_give_up(datum/bot_brain/bot)
	bot.rnd_bench_blocked_until = world.time + 2 MINUTES

/datum/bot_step/press_sync/execute(datum/bot_brain/bot)
	var/obj/machinery/computer/rdconsole/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	if(QDELETED(C))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(C)
	bot.telemetry_ui_action(C, "sync devices")
	C.SyncRDevices()
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Putting things back, and the junk
// ---------------------------------------------------------------------------------------------

/// Takes the RPED back to the lathe, and on the way past the analyzer puts the worst of its spare parts through it.
/datum/bot_goal/put_rped_back
	lawful = TRUE
	doing = "tidying up the lab"
	var/obj/item/storage/part_replacer/rped

/datum/bot_goal/put_rped_back/New(obj/item/storage/part_replacer/R)
	. = ..()
	rped = R

/datum/bot_goal/put_rped_back/resolve_target(datum/bot_brain/bot)
	if(QDELETED(rped))
		return
	target = bot.find_analyzer() || bot.find_lathe()

/datum/bot_goal/put_rped_back/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/take_rped(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/scrap_spare_parts())
	return list(S)

/datum/bot_goal/put_rped_back/on_give_up(datum/bot_brain/bot)
	bot.rnd_bench_blocked_until = world.time + 2 MINUTES

/// The department's destructive analyzer, linked up and not in the middle of anything.
/datum/bot_brain/proc/find_analyzer()
	for(var/obj/machinery/rnd/destructive_analyzer/D as anything in bot_instances_of(/obj/machinery/rnd/destructive_analyzer))
		if(!QDELETED(D) && D.z == owner.z && in_science(D) && !D.panel_open && !(D.stat & (BROKEN|NOPOWER)) && D.linked_console && !D.busy && !D.loaded_item)
			return D
	return null

/// The bluespace RPED off the lathe, the plain one's parts tipped into it, and the plain one left at the bench for whoever wants it.
/datum/bot_goal/switch_to_brped
	lawful = TRUE
	exclusive = TRUE
	doing = "moving the parts into the bluespace RPED"
	var/obj/item/storage/part_replacer/bluespace/brped
	var/obj/item/storage/part_replacer/old

/datum/bot_goal/switch_to_brped/New(obj/item/storage/part_replacer/bluespace/B, obj/item/storage/part_replacer/O)
	. = ..()
	brped = B
	old = O
	target = B

/datum/bot_goal/switch_to_brped/resolve_target(datum/bot_brain/bot)
	if(QDELETED(brped) || QDELETED(old))
		target = null

/datum/bot_goal/switch_to_brped/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/fill_brped())
	return list(S)

/datum/bot_goal/switch_to_brped/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/rnd_bench), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/switch_to_brped/on_give_up(datum/bot_brain/bot)
	bot.rnd_bench_blocked_until = world.time + 2 MINUTES

/// Fetches each RPED in turn, then tips the plain one into the bluespace one: a click, the whole lot.
/datum/bot_step/fill_brped
	var/tries = 0

/datum/bot_step/fill_brped/execute(datum/bot_brain/bot)
	var/datum/bot_goal/switch_to_brped/G = bot.current_goal
	if(!istype(G) || QDELETED(G.brped) || QDELETED(G.old) || ++tries > 6)
		return GOAL_STEP_FAIL
	for(var/obj/item/storage/part_replacer/R in list(G.old, G.brped))
		if(R in bot.owner.held_items)
			continue
		if(isturf(R.loc) && !bot.owner.Adjacent(R))
			return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(R)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if(!bot.ready_in_hand(R))
			return GOAL_STEP_FAIL
	bot.human_pause(G.brped)
	if(QDELETED(G.brped) || QDELETED(G.old))
		return GOAL_STEP_FAIL
	var/moved = 0
	for(var/obj/item/part in G.old.contents.Copy())
		if(SEND_SIGNAL(G.old, COMSIG_TRY_STORAGE_TAKE, part, bot.owner.drop_location()) && SEND_SIGNAL(G.brped, COMSIG_TRY_STORAGE_INSERT, part, bot.owner, TRUE))
			moved++
	G.brped.play_rped_sound()
	bot.telemetry_ui_action(G.brped, "tip [G.old] into it")
	bot.owner.dropItemToGround(G.old)
	bot_log(bot, "moved [moved] part\s into [G.brped] and left [G.old] by the bench")
	return GOAL_STEP_SUCCESS

/// Junk out of the RPED when it's filling up mid-round, the RPED kept in hand.
/datum/bot_goal/put_rped_back/scrap_only
	doing = "clearing old parts out of the RPED"

/datum/bot_goal/put_rped_back/scrap_only/resolve_target(datum/bot_brain/bot)
	if(QDELETED(rped))
		return
	target = bot.find_analyzer()

/datum/bot_goal/put_rped_back/scrap_only/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/rnd_bench), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/// The junk (bot_rped_junk()) one part at a time, worst first, and the RPED set down at the end unless the round goes on.
/datum/bot_step/paced/scrap_spare_parts
	max_clicks = 80
	optional = TRUE

/datum/bot_step/paced/scrap_spare_parts/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/put_rped_back/G = bot.current_goal
	var/obj/machinery/rnd/destructive_analyzer/D = G?.target
	if(!istype(G) || QDELETED(G.rped) || !istype(D) || QDELETED(D) || !bot.owner.Adjacent(D))
		return FALSE
	if(D.busy || D.loaded_item)
		wait_for = 10
		return TRUE
	var/list/junk = bot_rped_junk(G.rped)
	if(!length(junk))
		return FALSE
	// Mid-round, room for a round's parts is enough: each one through the analyzer is a few seconds
	if(istype(G, /datum/bot_goal/put_rped_back/scrap_only) && bot_rped_room(G.rped) >= BOT_RPED_LOW_ROOM * 2)
		return FALSE
	var/obj/item/worst = junk[1]
	// A hand free for the part: whatever's in the other one put away, the RPED kept
	for(var/obj/item/held in bot.owner.held_items)
		if(held == G.rped || length(bot.owner.held_items) - length(bot.owner.get_empty_held_indexes()) < 2)
			continue
		bot.stow_item(held)
		if(held in bot.owner.held_items)
			bot_log(bot, "setting [held] down for a moment")
			bot.owner.dropItemToGround(held)
			LAZYADD(bot.set_down_items, held)
	bot.human_pause(D)
	if(QDELETED(worst) || QDELETED(D) || !SEND_SIGNAL(G.rped, COMSIG_TRY_STORAGE_TAKE, worst, bot.owner.drop_location()))
		bot_log(bot, "couldn't get [worst] out of [G.rped]")
		return FALSE
	if(!bot.owner.put_in_hands(worst))
		bot_log(bot, "no free hand for [worst]: back in [G.rped]")
		SEND_SIGNAL(G.rped, COMSIG_TRY_STORAGE_INSERT, worst, bot.owner, TRUE, TRUE)
		return FALSE
	if(!D.Insert_Item(worst, bot.owner) || D.loaded_item != worst)
		bot_log(bot, "[D] wouldn't take [worst]")
		if(worst.loc == bot.owner)
			SEND_SIGNAL(G.rped, COMSIG_TRY_STORAGE_INSERT, worst, bot.owner, TRUE, TRUE)
		return FALSE
	bot.telemetry_ui_action(D, "deconstruct [worst]")
	bot.items_analyzed++
	addtimer(CALLBACK(D, TYPE_PROC_REF(/obj/machinery/rnd/destructive_analyzer, destroy_item), worst), 15)
	wait_for = 30
	return TRUE

/datum/bot_step/paced/scrap_spare_parts/finish(datum/bot_brain/bot)
	var/datum/bot_goal/put_rped_back/G = bot.current_goal
	if(istype(G) && !istype(G, /datum/bot_goal/put_rped_back/scrap_only) && !QDELETED(G.rped) && (G.rped in bot.owner.held_items))
		bot.owner.dropItemToGround(G.rped)
		bot_log(bot, "left [G.rped] by the bench")
	return GOAL_STEP_SUCCESS

#undef BOT_RND_LOW_SHEETS
#undef BOT_RND_ASK_GAP

// ---------------------------------------------------------------------------------------------
// The departments' own
// ---------------------------------------------------------------------------------------------

// Department staff who like a job done right fit their own department's machines (the user's ruling, 2026-11-04: "department staff and
// science can do it, depends on personality"): an RPED and the parts printed at the department's own techfab, which draws on the ore
// silo, and in they go, a machine at a time, the same three clicks a scientist makes.

/datum/bot_brain
	/// When it'll next ask Science to upgrade its department's machines.
	var/next_upgrade_ask = 0

/// Which duty a bench goal goes back to when it's done: Science's bench, or a department's.
/datum/bot_goal/print_design
	var/chain_duty = /datum/bot_duty/rnd_bench

/datum/bot_goal/collect_prints
	var/chain_duty = /datum/bot_duty/rnd_bench

/datum/bot_goal/fit_upgrades
	var/chain_duty = /datum/bot_duty/rnd_bench

/// Its department's own techfab or lathe, powered and stocked from the silo, if it's got one that works without a console.
/datum/bot_brain/proc/department_fabricator()
	var/obj/machinery/rnd/production/best
	var/best_dist
	for(var/obj/machinery/rnd/production/L as anything in bot_instances_of(/obj/machinery/rnd/production))
		if(QDELETED(L) || L.z != owner.z || L.requires_console || L.panel_open || (L.stat & (BROKEN|NOPOWER)) || !L.materials?.mat_container || L.materials.on_hold())
			continue
		if(gym_run ? (get_area(L) != get_area(owner)) : !is_my_department(get_area(L)))
			continue
		var/dist = get_dist(owner, L)
		if(!best || dist < best_dist)
			best = L
			best_dist = dist
	return best

/// A machine in its own department with its panel off and nobody at it.
/datum/bot_brain/proc/department_panel_left_open()
	for(var/machine_type in GLOB.bot_upgrade_order)
		for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
			if(QDELETED(M) || !M.panel_open || M.z != owner.z || taken_by_another(M) || LAZYACCESS(upgrade_blocked, M) > world.time)
				continue
			if(gym_run ? (get_area(M) == get_area(owner)) : is_my_department(get_area(M)))
				return M
	return null

/// The next machine in its own department that could do with the parts that have been researched.
/datum/bot_brain/proc/next_department_upgrade(list/exclude)
	for(var/machine_type in GLOB.bot_upgrade_order)
		for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
			if(QDELETED(M) || (M in exclude) || M.z != owner.z || M.panel_open || (M.stat & BROKEN) || !length(M.component_parts))
				continue
			if(gym_run ? (get_area(M) != get_area(owner)) : !is_my_department(get_area(M)))
				continue
			if(istype(M, /obj/machinery/atmospherics/components/unary/thermomachine) && !istype(get_area(M), /area/science/mixing))
				continue
			if(LAZYACCESS(upgrade_blocked, M) > world.time || taken_by_another(M) || !length(parts_to_upgrade(M)))
				continue
			// One it can't get to (an SMES behind the engine's shielding on Meta): engineers set off for it every ten minutes
			if(!gym_run && !can_walk_lawfully_to(M))
				LAZYSET(upgrade_blocked, M, world.time + 30 MINUTES)
				continue
			return M
	return null

/datum/bot_duty/department_upgrades
	name = "upgrading the department's machines"
	jobs = list("Station Engineer", "Chief Engineer", "Atmospheric Technician", "Medical Doctor", "Chief Medical Officer", "Chemist", "Paramedic", "Geneticist", "Virologist", "Cargo Technician", "Quartermaster", "Botanist", "Cook", "Bartender", "Roboticist")
	interval_min = 600
	interval_max = 1800

/// The diligent and handy: the rest leave it to Science.
/datum/bot_duty/department_upgrades/applies_to(datum/bot_brain/bot)
	return ..() && bot.diligence >= 0.6 && bot.competence >= 0.4

/datum/bot_duty/department_upgrades/try_start(datum/bot_brain/bot)
	if(world.time < bot.rnd_bench_blocked_until)
		return FALSE
	// One of its own left with the panel off: shut first. The techfab caught fire under an engineer mid-job, the screwdriver went with
	// everything else it was holding, and the recharger it had just fitted stood open.
	var/obj/machinery/left_open = bot.department_panel_left_open()
	if(left_open)
		return bot.assign_goal(new /datum/bot_goal/close_panel(left_open))
	var/obj/machinery/rnd/production/fab = bot.department_fabricator()
	if(!fab || fab.busy || bot.department_rped_in_use())
		return FALSE
	var/obj/machinery/M = bot.next_department_upgrade()
	if(!M)
		return FALSE
	// Carried, on the techfab, or wherever it was set down in the department: one dropped putting out a techfab fire had the engineer
	// printing a second
	var/obj/item/storage/part_replacer/rped = bot.find_rped() || (locate(/obj/item/storage/part_replacer) in get_turf(fab))
	// What's been researched since the techfab last looked, as anybody does before printing: its Sync button.
	if(!fab.stored_research.researched_designs["rped"] && SSresearch.science_tech.researched_designs["rped"])
		bot.telemetry_ui_action(fab, "sync")
		fab.update_research()
	if(!rped)
		var/datum/design/D = bot_researched_design("rped")
		if(!D || !(D.build_type & fab.allowed_buildtypes) || !(isnull(fab.allowed_department_flags) || (D.departmental_flags & fab.allowed_department_flags)))
			// No RPED to be had here (only Engineering's and Science's techfabs make them): Science asked to come and see to it, from
			// the room it's wanted in (bot_asks.dm, the upgrades call), the way a doctor would ask on the radio.
			if(D && world.time >= bot.next_upgrade_ask && get_area(bot.owner) == get_area(M))
				bot.next_upgrade_ask = world.time + 20 MINUTES
				bot.call_for(/datum/bot_request_kind/upgrades, "Science, could you upgrade the machines in [get_area_name(M, TRUE)]? [pick("They could do with it.", "Better parts would help.", "Whenever you're free.")]")
			return FALSE
		return bot.print_for_department(fab, D, 1)
	if(bot_parts_to_collect(fab))
		var/datum/bot_goal/collect_prints/collect = new(fab)
		collect.chain_duty = type
		return bot.assign_goal(collect)
	// A round, as Science does it: the department's machines' parts printed at once, then fitted one after another
	bot.prune_upgrade_round(rped)
	if(!length(bot.upgrade_round))
		bot.upgrade_round = bot.plan_upgrade_round(rped, TRUE)
		bot.upgrade_round_fitting = FALSE
		if(!length(bot.upgrade_round))
			return FALSE
	if(!bot.upgrade_round_fitting)
		var/list/to_print = bot.parts_still_to_print(bot.upgrade_round, rped, fab)
		if(length(to_print))
			var/id = to_print[1]
			var/datum/design/part = SSresearch.techweb_design_by_id(id)
			if(!fab.stored_research.researched_designs[id])
				bot.telemetry_ui_action(fab, "sync")
				fab.update_research()
			var/amount = min(to_print[id], max(1, bot_rped_room(rped) - bot_prints_waiting(fab, /obj/item/stock_parts)))
			if(bot.print_for_department(fab, part, amount))
				return TRUE
		bot.upgrade_round_fitting = TRUE
	var/obj/machinery/next = bot.next_in_round(rped)
	if(!next)
		bot.upgrade_round = null
		bot.rnd_bench_blocked_until = world.time + 3 MINUTES
		return FALSE
	var/datum/bot_goal/fit_upgrades/fit = new(next)
	fit.chain_duty = type
	return bot.assign_goal(fit)

/// print_or_ask(), at the department's own techfab.
/datum/bot_brain/proc/print_for_department(obj/machinery/rnd/production/fab, datum/design/D, amount)
	var/list/short = list()
	if(!bot_lathe_can_afford(fab, D, amount, short))
		if(amount > 1 && bot_lathe_can_afford(fab, D, 1))
			amount = 1
		else
			ask_for_materials(short)
			rnd_bench_blocked_until = world.time + 5 MINUTES
			return FALSE
	var/datum/bot_goal/print_design/G = new(fab, D, amount)
	G.chain_duty = /datum/bot_duty/department_upgrades
	return assign_goal(G)

#undef BOT_RPED_KEEP_SPARES
#undef BOT_RPED_LOW_ROOM
#undef BOT_ROUND_MACHINES
#undef BOT_BRPED_RANGE
