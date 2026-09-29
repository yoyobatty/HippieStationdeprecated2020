// Backpack air scrubber: a worn portable scrubber for atmos techs. Switched on, it draws the air around it through its
// filters every couple of seconds, and keeps what it catches (plasma, CO2, N2O and the like) in an internal tank. When the
// tank's full it shuts itself off: empty it by using it on a canister, portable pump or scrubber, or a gas tank (which it
// only fills to a safe pressure), or vent it where you stand. Its gas spills if it's destroyed.

/obj/item/scrubber_pack
	name = "backpack air scrubber"
	desc = "A backpack-mounted air scrubber. Worn and switched on, it filters toxic gases out of the air around you and stores them in its tank. Empty it into a canister or gas tank."
	icon = 'hippiestation/icons/obj/dept_gear.dmi'
	icon_state = "scrubberpack"
	item_state = "scrubberpack"
	alternate_worn_icon = 'hippiestation/icons/mob/dept_gear_worn.dmi'
	w_class = WEIGHT_CLASS_BULKY
	slot_flags = ITEM_SLOT_BACK
	actions_types = list(/datum/action/item_action/toggle_scrubber_pack)
	max_integrity = 200
	armor = list("melee" = 0, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0, "fire" = 100, "acid" = 30)
	resistance_flags = FIRE_PROOF
	/// Whether the fans are running
	var/on = FALSE
	/// What it has caught so far
	var/datum/gas_mixture/air_contents
	/// Litres of the tank the caught gas is kept in
	var/volume = 70
	/// It switches itself off once its tank reaches this
	var/max_pressure = 60 * ONE_ATMOSPHERE
	/// Litres of the surrounding air drawn through the filters each time it processes (every 2 seconds)
	var/volume_rate = 1000
	/// Gases it filters out, the portable scrubber's defaults
	var/list/scrubbing = list(/datum/gas/plasma, /datum/gas/carbon_dioxide, /datum/gas/nitrous_oxide, /datum/gas/bz, /datum/gas/nitryl, /datum/gas/tritium, /datum/gas/hypernoblium, /datum/gas/water_vapor)

/datum/action/item_action/toggle_scrubber_pack
	name = "Toggle Air Scrubber"

/obj/item/scrubber_pack/Initialize()
	. = ..()
	air_contents = new(volume)
	air_contents.temperature = T20C

/obj/item/scrubber_pack/Destroy()
	STOP_PROCESSING(SSobj, src)
	var/turf/T = get_turf(src)
	if(T && air_contents?.total_moles())
		T.assume_air(air_contents.remove_ratio(1))
		T.air_update_turf(FALSE, FALSE)
	air_contents = null
	return ..()

/obj/item/scrubber_pack/item_action_slot_check(slot, mob/user)
	return slot == ITEM_SLOT_BACK

/obj/item/scrubber_pack/ui_action_click(mob/user)
	toggle_power(user)

/obj/item/scrubber_pack/attack_self(mob/user)
	ui_interact(user)

/obj/item/scrubber_pack/AltClick(mob/user)
	if(user.canUseTopic(src, BE_CLOSE, NO_DEXTERY, FALSE))
		ui_interact(user)

/obj/item/scrubber_pack/proc/toggle_power(mob/user)
	if(!on && air_contents.return_pressure() >= max_pressure)
		if(user)
			to_chat(user, "<span class='warning'>[src]'s tank is full. Empty it first.</span>")
		return
	on = !on
	if(on)
		START_PROCESSING(SSobj, src)
	else
		STOP_PROCESSING(SSobj, src)
	if(user)
		to_chat(user, "<span class='notice'>You switch [src] [on ? "on" : "off"].</span>")
	playsound(src, 'sound/machines/click.ogg', 30, TRUE)
	update_icon()

/obj/item/scrubber_pack/update_icon()
	icon_state = on ? "scrubberpack_on" : "scrubberpack"
	item_state = icon_state
	if(ismob(loc))
		var/mob/M = loc
		M.update_inv_back()
	for(var/datum/action/A as anything in actions)
		A.UpdateButtonIcon()

/obj/item/scrubber_pack/process()
	if(!on)
		return PROCESS_KILL
	var/turf/open/T = get_turf(src)
	if(!istype(T))
		return
	scrub(T.return_air())
	T.air_update_turf(FALSE, FALSE)

/// Pulls volume_rate litres of the mix through the filters, keeping what they catch; the portable scrubber's scrub()
/obj/item/scrubber_pack/proc/scrub(datum/gas_mixture/mixture)
	if(air_contents.return_pressure() >= max_pressure)
		on = FALSE
		STOP_PROCESSING(SSobj, src)
		update_icon()
		playsound(src, 'sound/machines/twobeep.ogg', 40, TRUE)
		audible_message("<span class='notice'>[src] beeps: its tank is full.</span>", null, 3)
		return
	var/transfer_moles = min(1, volume_rate / mixture.volume) * mixture.total_moles()
	var/datum/gas_mixture/filtering = mixture.remove(transfer_moles)
	if(!filtering)
		return
	var/datum/gas_mixture/filtered = new
	filtered.temperature = filtering.temperature
	for(var/gas in filtering.moles & scrubbing)
		filtered.add_gas(gas)
		filtered.moles[gas] = filtering.moles[gas]
		filtering.moles[gas] = 0
	filtering.garbage_collect()
	air_contents.merge(filtered)
	mixture.merge(filtering)

/obj/item/scrubber_pack/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It's switched [on ? "on" : "off"]. Its tank is at [round(air_contents.return_pressure())] kPa, [round(fill_fraction() * 100)]% full.</span>"
	var/list/contents = describe_contents()
	if(length(contents))
		. += "<span class='notice'>It holds [english_list(contents)].</span>"
	. += "<span class='notice'>Alt-click it to set its filters or vent it.</span>"

/obj/item/scrubber_pack/proc/fill_fraction()
	return clamp(air_contents.return_pressure() / max_pressure, 0, 1)

/// "12.3 mol of Plasma", for each gas in the tank
/obj/item/scrubber_pack/proc/describe_contents()
	. = list()
	var/list/names = GLOB.meta_gas_info[META_GAS_NAME]
	for(var/gas, amount in air_contents.moles)
		if(amount >= 0.1)
			. += "[round(amount, 0.1)] mol of [names[gas]]"

// Emptying it: use it on a canister or portable pump/scrubber (everything goes in) or on a gas tank (filled to a safe pressure)
/obj/item/scrubber_pack/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag)
		return
	var/datum/gas_mixture/destination
	var/target_pressure
	if(istype(target, /obj/machinery/portable_atmospherics))
		var/obj/machinery/portable_atmospherics/P = target
		destination = P.air_contents
	else if(istype(target, /obj/item/tank))
		var/obj/item/tank/tank = target
		destination = tank.air_contents
		target_pressure = TANK_LEAK_PRESSURE * 0.9 // a gas tank starts leaking at 30 atmospheres
	if(!destination)
		return
	if(!air_contents.total_moles())
		to_chat(user, "<span class='warning'>[src]'s tank is empty.</span>")
		return
	to_chat(user, "<span class='notice'>You connect [src]'s outlet to [target] and start emptying it...</span>")
	if(!do_after(user, 2 SECONDS, target = target))
		return
	var/list/moved = describe_contents()
	if(target_pressure)
		if(!air_contents.pump_gas_to(destination, target_pressure))
			to_chat(user, "<span class='warning'>[target] is already at [round(destination.return_pressure())] kPa, as full as [src] will fill it.</span>")
			return
	else
		destination.merge(air_contents.remove_ratio(1))
	var/obj/filled = target
	filled.update_icon()
	playsound(src, 'sound/effects/spray.ogg', 20, TRUE)
	to_chat(user, "<span class='notice'>You empty [air_contents.total_moles() ? "some of " : ""][src]'s tank into [target].</span>")
	investigate_log("[key_name(user)] emptied [src] ([english_list(moved)]) into [target] at [AREACOORD(target)].", INVESTIGATE_ATMOS)

/obj/item/scrubber_pack/proc/vent(mob/user)
	var/turf/T = get_turf(src)
	if(!T || !air_contents.total_moles())
		return
	var/list/vented = describe_contents()
	T.assume_air(air_contents.remove_ratio(1))
	T.air_update_turf(FALSE, FALSE)
	playsound(T, 'sound/effects/spray.ogg', 40, TRUE)
	user.visible_message("<span class='warning'>[user] vents [src]'s tank!</span>", "<span class='notice'>You vent [src]'s tank.</span>")
	investigate_log("[key_name(user)] vented [src] ([english_list(vented)]) at [AREACOORD(T)].", INVESTIGATE_ATMOS)
	log_game("[key_name(user)] vented a backpack air scrubber ([english_list(vented)]) at [AREACOORD(T)].")

/obj/item/scrubber_pack/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.inventory_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "scrubber_pack", name, 400, 460, master_ui, state)
		ui.open()

/obj/item/scrubber_pack/ui_data(mob/user)
	var/list/data = list()
	data["on"] = on
	data["pressure"] = round(air_contents.return_pressure())
	data["max_pressure"] = round(max_pressure)
	data["fill"] = fill_fraction()
	var/list/names = GLOB.meta_gas_info[META_GAS_NAME]
	var/list/ids = GLOB.meta_gas_info[META_GAS_ID]
	data["contents"] = list()
	for(var/gas, amount in air_contents.moles)
		if(amount >= 0.1)
			data["contents"] += list(list("gas_id" = ids[gas], "gas_name" = names[gas], "moles" = round(amount, 0.1)))
	data["filter_types"] = list()
	for(var/path in ids)
		data["filter_types"] += list(list("gas_id" = ids[path], "gas_name" = names[path], "enabled" = (path in scrubbing)))
	return data

/obj/item/scrubber_pack/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("power")
			toggle_power(usr)
			. = TRUE
		if("toggle_filter")
			var/path = gas_id2path(params["val"])
			if(path)
				scrubbing ^= path
				. = TRUE
		if("vent")
			if(alert(usr, "Vent everything in [src]'s tank where you stand?", name, "Vent", "Cancel") != "Vent")
				return
			if(!usr.canUseTopic(src, BE_CLOSE))
				return
			vent(usr)
			. = TRUE

// A closer look (examine it twice): how to use it
/obj/item/scrubber_pack/examine_more(mob/user)
	. = ..()
	. += "<span class='notice'>Use it in hand to switch it on or off. While it's on, it draws in the air around you every couple of seconds and keeps whatever its filters catch in its tank, leaving the rest.</span>"
	. += "<span class='notice'>When the tank's full it switches itself off. Empty it by using it on a canister, portable pump or scrubber, or a gas tank (which it only fills to a safe pressure), or vent it where you stand from its screen.</span>"
	. += "<span class='notice'>If it's destroyed, everything in its tank spills out.</span>"
