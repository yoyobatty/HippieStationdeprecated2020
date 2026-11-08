// What the RPED works on besides machines built from a board (the user's ruling, 2026-11-08): an APC's cell with its cover open, a
// cyborg's cell with its cover open, and an exosuit's cell, scanning module and capacitor with its maintenance protocols on. The same
// rules as a machine: the best part it carries that beats what's in, the old part back into the RPED, a bluespace one from a distance.
//
// tg's exosuit used its scanning module and capacitor up when it was built (CheckParts()), so there was nothing to swap later: it keeps
// them now, out of the world like a machine's component_parts.

/// The RPED's hook: null when the RPED has no business with it (the attack goes on as normal), anything else when it's been dealt
/// with. `from_range` is a bluespace RPED used from across the room.
/atom/proc/rped_exchange(mob/user, obj/item/storage/part_replacer/rped, from_range)
	return null

/obj/item/storage/part_replacer/pre_attack(atom/target, mob/living/user, params)
	var/obj/machinery/M = target
	if(!(istype(M) && M.component_parts) && user.Adjacent(target) && !isnull(target.rped_exchange(user, src, FALSE)))
		return FALSE
	return ..()

/obj/item/storage/part_replacer/afterattack(atom/target, mob/living/user, proximity_flag, params)
	var/obj/machinery/M = target
	if(!proximity_flag && works_from_distance && !(istype(M) && M.component_parts) && !isnull(target.rped_exchange(user, src, TRUE)))
		user.Beam(target, icon_state = "rped_upgrade", time = 5)
		return
	return ..()

/// The best part of a kind it carries, if it beats `current` (anything does when there's nothing in). Of two cells that rate the same,
/// the fuller; `min_charge` (a fraction) leaves out cells flatter than that: a cyborg or an exosuit can't run on a flat one, where an
/// APC on the grid charges its own.
/obj/item/storage/part_replacer/proc/best_part_over(kind, obj/item/current, min_charge = 0)
	var/obj/item/best
	for(var/obj/item/part in contents)
		if(!istype(part, kind))
			continue
		var/obj/item/stock_parts/cell/C = part
		if(istype(C) && min_charge && C.charge < C.maxcharge * min_charge)
			continue
		if(!best || part.get_part_rating() > best.get_part_rating())
			best = part
		else if(istype(C) && part.get_part_rating() == best.get_part_rating())
			var/obj/item/stock_parts/cell/B = best
			if(C.charge > B.charge)
				best = part
	if(best && (!current || best.get_part_rating() > current.get_part_rating()))
		return best

/// Takes `new_part` out into `holder` and puts `old_part` (if any) in its place, or at the user's feet if there's no room.
/obj/item/storage/part_replacer/proc/swap_part(obj/item/old_part, obj/item/new_part, atom/holder, mob/user)
	if(!SEND_SIGNAL(src, COMSIG_TRY_STORAGE_TAKE, new_part, holder))
		return FALSE
	if(old_part && !SEND_SIGNAL(src, COMSIG_TRY_STORAGE_INSERT, old_part, null, TRUE, TRUE))
		old_part.forceMove(user?.drop_location() || holder.drop_location())
	if(old_part)
		to_chat(user, "<span class='notice'>[capitalize(old_part.name)] replaced with [new_part.name].</span>")
	else
		to_chat(user, "<span class='notice'>[capitalize(new_part.name)] fitted.</span>")
	return TRUE

/proc/rped_cell_line(obj/item/stock_parts/cell/C)
	return C ? "[C.name] ([DisplayEnergy(C.maxcharge)])" : "no cell"

// ---------------------------------------------------------------------------------------------
// APCs
// ---------------------------------------------------------------------------------------------

/obj/machinery/power/apc/rped_exchange(mob/user, obj/item/storage/part_replacer/rped, from_range)
	if(!opened)
		to_chat(user, "<span class='notice'>[src] has [rped_cell_line(cell)]. Open its cover to swap it.</span>")
		return TRUE
	if(stat & MAINT) // no electronics: nothing to plug a cell into
		to_chat(user, "<span class='warning'>[src] has no connector for a power cell.</span>")
		return TRUE
	var/obj/item/stock_parts/cell/better = rped.best_part_over(/obj/item/stock_parts/cell, cell)
	if(!better)
		to_chat(user, "<span class='notice'>[src] has [rped_cell_line(cell)]. [rped] has nothing better.</span>")
		return TRUE
	var/obj/item/stock_parts/cell/old = cell
	if(!rped.swap_part(old, better, src, user))
		return TRUE
	old?.update_icon()
	cell = better
	chargecount = 0
	charging = 0 // APC_NOT_CHARGING, apc.dm's own define
	update_icon()
	rped.play_rped_sound()
	return TRUE

// ---------------------------------------------------------------------------------------------
// Cyborgs
// ---------------------------------------------------------------------------------------------

/mob/living/silicon/robot/rped_exchange(mob/user, obj/item/storage/part_replacer/rped, from_range)
	if(user.a_intent == INTENT_HARM)
		return null
	if(!opened)
		to_chat(user, "<span class='notice'>[src] has [rped_cell_line(cell)]. Open its cover to swap it.</span>")
		return TRUE
	var/obj/item/stock_parts/cell/better = rped.best_part_over(/obj/item/stock_parts/cell, cell, 0.1)
	if(!better)
		to_chat(user, "<span class='notice'>[src] has [rped_cell_line(cell)]. [rped] has nothing better.</span>")
		return TRUE
	var/obj/item/stock_parts/cell/old = cell
	if(!rped.swap_part(old, better, src, user))
		return TRUE
	old?.update_icon()
	cell = better
	update_icons()
	diag_hud_set_borgcell()
	rped.play_rped_sound()
	return TRUE

// ---------------------------------------------------------------------------------------------
// Exosuits
// ---------------------------------------------------------------------------------------------

/obj/mecha
	/// The scanning module it was built with (or was fitted since), out of the world: it sets normal_step_energy_drain.
	var/obj/item/stock_parts/scanning_module/rped_scanmod
	/// The capacitor, likewise: rating x 5 energy armour.
	var/obj/item/stock_parts/capacitor/rped_capacitor

/obj/mecha/CheckParts(list/parts_list)
	var/obj/item/stock_parts/scanning_module/SM = locate() in parts_list
	var/obj/item/stock_parts/capacitor/CP = locate() in parts_list
	var/sm_type = SM?.type
	var/cp_type = CP?.type
	..() // tg's puts their effect in and deletes them
	if(sm_type)
		rped_scanmod = new sm_type(null)
	if(cp_type)
		rped_capacitor = new cp_type(null)

/obj/mecha/Destroy()
	QDEL_NULL(rped_scanmod)
	QDEL_NULL(rped_capacitor)
	return ..()

/// Fits a scanning module: tg's sum from CheckParts(). An exosuit that came without one (a ready-made one) only takes one that beats
/// the drain it already has.
/obj/mecha/proc/rped_fit_scanmod(obj/item/stock_parts/scanning_module/SM)
	var/old_normal = normal_step_energy_drain
	normal_step_energy_drain = 20 - (5 * SM.rating)
	if(step_energy_drain == old_normal)
		step_energy_drain = normal_step_energy_drain
	rped_scanmod = SM
	SM.moveToNullspace()

/obj/mecha/proc/rped_fit_capacitor(obj/item/stock_parts/capacitor/CP)
	armor = armor.modifyRating(energy = (CP.rating - (rped_capacitor?.rating || 0)) * 5)
	rped_capacitor = CP
	CP.moveToNullspace()

/obj/mecha/rped_exchange(mob/user, obj/item/storage/part_replacer/rped, from_range)
	if(!state)
		to_chat(user, "<span class='notice'>[src] has [rped_cell_line(cell)][rped_scanmod ? ", \a [rped_scanmod]" : ""][rped_capacitor ? ", \a [rped_capacitor]" : ""]. Turn its maintenance protocols on to swap parts.</span>")
		return TRUE
	var/swapped = 0
	var/obj/item/stock_parts/cell/better_cell = rped.best_part_over(/obj/item/stock_parts/cell, cell, 0.1)
	if(better_cell)
		var/obj/item/stock_parts/cell/old = cell
		if(rped.swap_part(old, better_cell, src, user))
			cell = better_cell
			log_message("Powercell replaced by RPED", LOG_MECHA)
			swapped++
	var/obj/item/stock_parts/scanning_module/better_scan = rped.best_part_over(/obj/item/stock_parts/scanning_module, rped_scanmod)
	if(better_scan && (rped_scanmod || 20 - (5 * better_scan.rating) < normal_step_energy_drain))
		var/obj/item/old = rped_scanmod
		if(rped.swap_part(old, better_scan, src, user))
			rped_fit_scanmod(better_scan)
			swapped++
	var/obj/item/stock_parts/capacitor/better_cap = rped.best_part_over(/obj/item/stock_parts/capacitor, rped_capacitor)
	if(better_cap)
		var/obj/item/old = rped_capacitor
		if(rped.swap_part(old, better_cap, src, user))
			rped_fit_capacitor(better_cap)
			swapped++
	if(swapped)
		rped.play_rped_sound()
	else
		to_chat(user, "<span class='notice'>[rped] has nothing better for [src].</span>")
	return TRUE
