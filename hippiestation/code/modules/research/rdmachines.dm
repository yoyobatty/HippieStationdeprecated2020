// An experiment that deleted what it was testing (a grenade going off in it) still had it put out on the floor afterwards, deleted:
// it and the beakers in it were hard deletes (105 ms, stress bench 2026-11-08)
/obj/machinery/rnd/experimentor/ejectItem(delete = FALSE)
	if(QDELETED(loaded_item))
		loaded_item = null
		return
	return ..()

/// What a lathe's tank will take: the reagents some design its kind prints asks for (reagents_list), keyed by allowed_buildtypes.
/// Anything went in before, so silver or gold from the dispenser sat in the tank doing nothing. R&D's metal comes from mining
/// (the user's ruling, 2026-11-11).
GLOBAL_LIST_EMPTY(lathe_reagents_by_buildtype)

/obj/machinery/rnd/production/proc/usable_reagents()
	var/key = "[allowed_buildtypes]"
	var/list/usable = GLOB.lathe_reagents_by_buildtype[key]
	if(!usable)
		usable = list()
		for(var/id in SSresearch.techweb_designs)
			var/datum/design/D = SSresearch.techweb_designs[id]
			if(D.build_type & allowed_buildtypes)
				for(var/R in D.reagents_list)
					usable[R] = TRUE
		GLOB.lathe_reagents_by_buildtype[key] = usable
	return usable

/obj/machinery/rnd/production/attackby(obj/item/O, mob/user, params)
	if(panel_open || !istype(O, /obj/item/reagent_containers))
		return ..()
	if(istype(O, /obj/item/reagent_containers/food/snacks/solid_reagent))
		to_chat(user, "<span class='warning'>Reagents must be processed into sheets or ingots.</span>")
		return TRUE
	var/obj/item/reagent_containers/C = O
	if(!C.is_drainable() && !istype(C, /obj/item/reagent_containers/syringe) && !istype(C, /obj/item/reagent_containers/dropper))
		return ..()
	if(!C.reagents?.total_volume)
		to_chat(user, "<span class='warning'>[C] is empty.</span>")
		return TRUE
	pour_usable(C, user)
	return TRUE

/// Pours in what a design here could use, up to the container's transfer amount, and leaves the rest in it.
/obj/machinery/rnd/production/proc/pour_usable(obj/item/reagent_containers/C, mob/user)
	var/list/usable = usable_reagents()
	var/left = C.amount_per_transfer_from_this
	var/before = reagents.total_volume
	var/refused = FALSE
	for(var/datum/reagent/R in C.reagents.reagent_list.Copy())
		if(!usable[R.type])
			refused = TRUE
			continue
		if(left <= 0 || reagents.total_volume >= reagents.maximum_volume)
			continue
		var/amount = min(R.volume, left)
		C.reagents.trans_id_to(src, R.type, amount)
		left -= amount
	var/moved = reagents.total_volume - before
	if(moved > 0)
		to_chat(user, "<span class='notice'>You transfer [round(moved, 0.1)] unit\s to [src].</span>")
	else if(!refused)
		to_chat(user, "<span class='warning'>[src] is full.</span>")
	if(refused)
		to_chat(user, "<span class='warning'>Reagents must be processed into sheets or ingots.</span>")
	update_research_ui()

/// The lathe's window shows the tank: refresh it after a pour.
/obj/machinery/rnd/production/proc/update_research_ui()
	SStgui.update_uis(src)
	if(linked_console)
		SStgui.update_uis(linked_console)
