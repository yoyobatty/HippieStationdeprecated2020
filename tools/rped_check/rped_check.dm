// RPED sweep, headless: every machine built from a board, panel open, a tier 4 bluespace RPED with cells in it. What it swaps, and
// whether anything about the machine changed for it (a number among its vars after RefreshParts()).
//
// Run:      tools/rped_check/run_rped_check.sh   (builds its own copy, so hippiestation.dmb is left alone)
// Results:  data/rped_check/results.txt (summary), data/rped_check/sweep.tsv (every machine)

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("rped-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_rped_check))
	return ..()

#define RPED_CHECK_DIR "data/rped_check/"

/// Vars that move on their own or that RefreshParts() has no say in.
GLOBAL_LIST_INIT(rped_check_ignored_vars, list("tag", "layer", "plane", "pixel_x", "pixel_y", "x", "y", "z", "last_tick", "datum_flags", "gc_destroyed", "weak_reference", "atom_integrity", "obj_integrity"))

/proc/rped_check_numbers(atom/A)
	. = list()
	for(var/v in A.vars)
		if(v in GLOB.rped_check_ignored_vars)
			continue
		var/value = A.vars[v]
		if(isnum(value))
			.[v] = value

/proc/run_rped_check()
	sleep(5 SECONDS)
	fdel(RPED_CHECK_DIR)
	var/turf/open/floor/spot
	for(var/turf/open/floor/F in world)
		if(is_station_level(F.z) && !F.density && !(locate(/obj) in F))
			spot = F
			break
	var/mob/living/carbon/human/tester = new(spot)
	var/list/tsv = list("type\tname\tswapped\tvars changed\tparts asked for\tnotes")
	var/list/works = list()
	var/list/no_effect = list()
	var/list/nothing_to_swap = list()
	var/list/refused = list()
	var/list/broke = list()
	for(var/path in subtypesof(/obj/machinery))
		var/obj/machinery/proto = path
		var/board_path = initial(proto.circuit)
		if(!ispath(board_path, /obj/item/circuitboard/machine))
			continue
		var/obj/machinery/M
		try
			M = new path(spot)
		catch(var/exception/e)
			broke += "[path] ([e.name])"
			continue
		if(QDELETED(M) || !length(M.component_parts))
			broke += "[path] (no parts after Initialize)"
			if(!QDELETED(M))
				qdel(M)
			continue
		var/obj/item/circuitboard/machine/board = locate() in M.component_parts
		var/list/asked = list()
		for(var/kind in board?.req_components)
			var/atom/K = kind
			asked += "[initial(K.name)] x[board.req_components[kind]]"
		var/obj/item/storage/part_replacer/bluespace/tier4/rped = new(spot)
		for(var/i in 1 to 5)
			new /obj/item/stock_parts/cell/bluespace(rped)
		var/list/before_parts = M.component_parts.Copy()
		var/list/before = rped_check_numbers(M)
		var/notes = ""
		if(M.flags_1 & NODECONSTRUCT_1)
			notes = "NODECONSTRUCT"
		M.panel_open = TRUE
		try
			M.exchange_parts(tester, rped)
		catch(var/exception/e2)
			notes += " exchange runtime: [e2.name]"
		var/swapped = length(before_parts - M.component_parts)
		var/list/after = rped_check_numbers(M)
		var/list/changed = list()
		for(var/v in before)
			if(after[v] != before[v])
				changed += "[v] [before[v]]->[after[v]]"
		var/line = "[path]\t[M.name]\t[swapped]\t[jointext(changed, ", ")]\t[jointext(asked, ", ")]\t[notes]"
		tsv += line
		if(!swapped)
			if(notes == "NODECONSTRUCT")
				refused += "[path]"
			else
				nothing_to_swap += "[path] ([jointext(asked, ", ")])"
		else if(!length(changed))
			no_effect += "[path] ([swapped] swapped)"
		else
			works += "[path]"
		qdel(rped)
		qdel(M)
	var/list/lines = list()
	lines += "machines with boards: [length(works) + length(no_effect) + length(nothing_to_swap) + length(refused)] (+[length(broke)] that didn't build)"
	lines += "WORKS ([length(works)]): parts swapped and the machine changed"
	lines += "NO EFFECT ([length(no_effect)]): parts swapped, nothing about the machine changed"
	for(var/s in no_effect)
		lines += "  [s]"
	lines += "NOTHING TO SWAP ([length(nothing_to_swap)]): no stock parts or cells on its board"
	for(var/s in nothing_to_swap)
		lines += "  [s]"
	lines += "REFUSED ([length(refused)]): NODECONSTRUCT"
	for(var/s in refused)
		lines += "  [s]"
	lines += "DIDN'T BUILD ([length(broke)])"
	for(var/s in broke)
		lines += "  [s]"
	text2file(jointext(tsv, "\n"), RPED_CHECK_DIR + "sweep.tsv")
	lines += ""
	lines += rped_target_checks(spot, tester)
	text2file(jointext(lines, "\n"), RPED_CHECK_DIR + "results.txt")

/// An RPED in the tester's hand holding these, the old one gone.
/proc/rped_check_kit(mob/living/carbon/human/tester, rped_type, list/contents)
	for(var/obj/item/storage/part_replacer/old in tester.held_items)
		qdel(old)
	var/obj/item/storage/part_replacer/R = new rped_type(tester.loc)
	for(var/obj/item/I in R)
		qdel(I)
	for(var/path in contents)
		new path(R)
	tester.put_in_hands(R)
	return R

/proc/rped_check_line(list/counts, ok, text)
	counts[ok ? "pass" : "fail"]++
	return "[ok ? "PASS" : "FAIL"] [text]"

/// The click path a player takes: melee_attack_chain beside it, afterattack from across the room.
/proc/rped_target_checks(turf/spot, mob/living/carbon/human/tester)
	. = list()
	var/list/counts = list("pass" = 0, "fail" = 0)
	var/turf/far = locate(spot.x + 3, spot.y, spot.z)
	tester.forceMove(spot)

	// Best part first: an advanced capacitor ahead of a super one in the RPED, the recharger gets the super
	var/obj/machinery/recharger/charger = new(get_step(spot, EAST))
	var/obj/item/storage/part_replacer/R = rped_check_kit(tester, /obj/item/storage/part_replacer, list(/obj/item/stock_parts/capacitor/adv, /obj/item/stock_parts/capacitor/super))
	charger.panel_open = TRUE
	R.melee_attack_chain(tester, charger)
	var/obj/item/stock_parts/capacitor/fitted = locate() in charger.component_parts
	. += rped_check_line(counts, fitted?.rating == 3, "best part first: recharger got tier [fitted?.rating] with tier 2 and 3 carried")
	qdel(charger)

	// APC: one of the map's, its cover open
	var/obj/machinery/power/apc/A
	for(var/obj/machinery/power/apc/candidate in GLOB.apcs_list)
		if(is_station_level(candidate.z) && candidate.cell && !(candidate.stat & MAINT))
			A = candidate
			break
	if(!A)
		. += rped_check_line(counts, FALSE, "no APC on the map to try")
	else
		var/turf/beside = get_step(A, A.dir) == get_turf(A) ? get_turf(A) : get_turf(A)
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(A, d)
			if(isopenturf(T) && !T.density)
				beside = T
				break
		tester.forceMove(beside)
		var/obj/item/stock_parts/cell/old_cell = A.cell
		R = rped_check_kit(tester, /obj/item/storage/part_replacer, list(/obj/item/stock_parts/cell/bluespace))
		A.opened = 0
		R.melee_attack_chain(tester, A)
		. += rped_check_line(counts, A.cell == old_cell, "APC cover shut: cell left alone")
		A.opened = 1
		R.melee_attack_chain(tester, A)
		. += rped_check_line(counts, istype(A.cell, /obj/item/stock_parts/cell/bluespace) && A.cell.loc == A && (old_cell in R.contents), "APC cover open: bluespace cell in ([A.cell?.name]), old one in the RPED")
		// The bluespace RPED from three tiles: the old cell back in
		var/obj/item/stock_parts/cell/bs_cell = A.cell
		R = rped_check_kit(tester, /obj/item/storage/part_replacer/bluespace, list())
		qdel(old_cell)
		var/obj/item/stock_parts/cell/hyper/hyper = new(R)
		bs_cell.maxcharge = 1 // so the hyper beats it
		var/turf/away = locate(beside.x + (beside.x > A.x ? 2 : -2), beside.y, beside.z) || beside
		tester.forceMove(away)
		R.afterattack(A, tester, FALSE)
		. += rped_check_line(counts, A.cell == hyper, "bluespace RPED from [get_dist(tester, A)] tiles: APC cell swapped")
		var/obj/item/storage/part_replacer/plain = rped_check_kit(tester, /obj/item/storage/part_replacer, list(/obj/item/stock_parts/cell/bluespace))
		plain.afterattack(A, tester, FALSE)
		. += rped_check_line(counts, A.cell == hyper, "plain RPED from a distance: nothing")
		A.opened = 0
		A.update_icon()
		tester.forceMove(spot)

	// Cyborg
	var/mob/living/silicon/robot/borg = new(far)
	tester.forceMove(get_step(far, WEST))
	R = rped_check_kit(tester, /obj/item/storage/part_replacer, list(/obj/item/stock_parts/cell/bluespace))
	var/obj/item/stock_parts/cell/borg_old = borg.cell
	R.melee_attack_chain(tester, borg)
	. += rped_check_line(counts, borg.cell == borg_old, "cyborg cover shut: cell left alone")
	borg.opened = TRUE
	R.melee_attack_chain(tester, borg)
	. += rped_check_line(counts, istype(borg.cell, /obj/item/stock_parts/cell/bluespace) && (borg_old in R.contents), "cyborg cover open: bluespace cell in, old one in the RPED")
	qdel(borg)

	// Exosuit, ready-made: no parts kept, its maintenance protocols off, then on
	var/obj/mecha/working/ripley/ripley = new(far)
	var/drain_before = ripley.normal_step_energy_drain
	var/energy_before = ripley.armor.energy
	R = rped_check_kit(tester, /obj/item/storage/part_replacer, list(/obj/item/stock_parts/cell/bluespace, /obj/item/stock_parts/scanning_module/triphasic, /obj/item/stock_parts/capacitor/quadratic, /obj/item/stock_parts/scanning_module))
	R.melee_attack_chain(tester, ripley)
	. += rped_check_line(counts, !istype(ripley.cell, /obj/item/stock_parts/cell/bluespace), "exosuit, maintenance off: nothing swapped")
	ripley.state = 1
	R.melee_attack_chain(tester, ripley)
	. += rped_check_line(counts, istype(ripley.cell, /obj/item/stock_parts/cell/bluespace) && ripley.cell.loc == ripley, "exosuit, maintenance on: bluespace cell in")
	. += rped_check_line(counts, ripley.rped_scanmod?.rating == 4 && ripley.normal_step_energy_drain == 0 && ripley.step_energy_drain == 0, "exosuit: triphasic scanning module fitted, drain [drain_before] -> [ripley.normal_step_energy_drain] (the tier 1 one carried wasn't: worse than ready-made)")
	. += rped_check_line(counts, ripley.rped_capacitor?.rating == 4 && ripley.armor.energy == energy_before + 20, "exosuit: quadratic capacitor fitted, energy armour [energy_before] -> [ripley.armor.energy]")
	qdel(ripley)

	// Exosuit built from parts: the parts are kept, and a better one swaps in from a distance with the bluespace RPED
	var/obj/mecha/working/ripley/built = new(far)
	var/base_energy = built.armor.energy
	built.CheckParts(list(new /obj/item/stock_parts/scanning_module(null), new /obj/item/stock_parts/capacitor(null)))
	. += rped_check_line(counts, built.rped_scanmod?.rating == 1 && built.rped_capacitor?.rating == 1 && built.normal_step_energy_drain == 15 && built.armor.energy == base_energy + 5, "exosuit built with tier 1 parts keeps them: drain [built.normal_step_energy_drain], energy armour +[built.armor.energy - base_energy]")
	built.state = 1
	tester.forceMove(locate(far.x - 3, far.y, far.z))
	R = rped_check_kit(tester, /obj/item/storage/part_replacer/bluespace, list(/obj/item/stock_parts/scanning_module/phasic, /obj/item/stock_parts/capacitor/super))
	R.afterattack(built, tester, FALSE)
	. += rped_check_line(counts, built.rped_scanmod?.rating == 3 && built.normal_step_energy_drain == 5 && built.rped_capacitor?.rating == 3 && built.armor.energy == base_energy + 15, "bluespace RPED from [get_dist(tester, built)] tiles: tier 3 scanning module and capacitor in, drain [built.normal_step_energy_drain], energy armour +[built.armor.energy - base_energy]")
	. += rped_check_line(counts, length(R.contents) == 2, "the tier 1 parts went back into the RPED ([length(R.contents)] in it)")
	var/obj/item/stock_parts/kept = built.rped_scanmod
	qdel(built)
	. += rped_check_line(counts, QDELETED(kept), "the exosuit's kept parts go with it")
	. += "[counts["pass"]] passed, [counts["fail"]] failed"

#undef RPED_CHECK_DIR
