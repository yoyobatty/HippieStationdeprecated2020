// hippie -- more gadgets as tgui windows (tgui-next interfaces/Gadgets.js):
//  - the implant pad: the implant's own read-out, and Eject
//  - the hand teleporter: the teleporters it can lock on to, live or not, the dangerous random jump, and how many portals are open,
//    in place of a pick-from-a-list popup
//  - safes: the dial as a dial, turned a notch or five either way, Open, and what's inside once it's open
//  - the destination tagger: the destinations as a grid of buttons, the one it's set to lit
//  - secure briefcases and wall safes: the keypad as a keypad
// Every button but the hand teleporter's goes through the old window's own Topic(); the teleporter's popup was all one proc, so what
// it did after the pick is here.

// The implant pad

/obj/item/implantpad/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.assembly_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "implant_pad", name, 380, 420, master_ui, state)
		ui.open()

/obj/item/implantpad/ui_data(mob/user)
	return list(
		"case" = !QDELETED(case),
		"implant" = case?.imp ? "[case.imp]" : null,
		"info" = istype(case?.imp, /obj/item/implant) ? case.imp.get_data() : null,
	)

/obj/item/implantpad/ui_act(action, params)
	if(..())
		return
	if(action == "eject")
		AltClick(usr)
	return TRUE

// The hand teleporter

/obj/item/hand_tele/attack_self(mob/user)
	ui_interact(user)

/obj/item/hand_tele/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "hand_teleporter", name, 360, 360, master_ui, state)
		ui.open()

/// Where it can lock on to: each teleporter computer's target, by name, as the old list had it
/obj/item/hand_tele/proc/tele_destinations()
	. = list()
	for(var/obj/machinery/computer/teleporter/com in GLOB.machines)
		if(com.target)
			var/area/A = get_area(com.target)
			if(!A || A.noteleport)
				continue
			var/live = com.power_station && com.power_station.teleporter_hub && com.power_station.engaged
			.["[A] ([live ? "Active" : "Inactive"])"] = com.target

/// Whether the old popup's "is malfunctioning" holds here
/obj/item/hand_tele/proc/tele_blocked(mob/user)
	var/turf/here = get_turf(user)
	var/area/A = here?.loc
	return !here || A.noteleport || is_away_level(here.z) || !isturf(user.loc)

/obj/item/hand_tele/ui_data(mob/user)
	var/list/places = list()
	var/list/destinations = tele_destinations()
	for(var/name in destinations)
		places += list(list("name" = name, "ref" = REF(destinations[name]), "active" = !!findtext(name, "(Active)")))
	return list(
		"destinations" = places,
		"portals" = length(active_portal_pairs),
		"max_portals" = max_portal_pairs,
		"blocked" = tele_blocked(user),
	)

/obj/item/hand_tele/ui_act(action, params)
	if(..())
		return
	if(action != "portal")
		return
	var/mob/user = usr
	var/atom/T
	if(params["ref"] == "random") // the old list's "None (Dangerous)": anywhere close by that isn't at the level's edge
		var/list/turfs = list()
		for(var/turf/near in urange(10, get_turf(user), orange = 1))
			if(near.x > world.maxx - 8 || near.x < 8 || near.y > world.maxy - 8 || near.y < 8)
				continue
			var/area/A = near.loc
			if(!A.noteleport)
				turfs += near
		if(length(turfs))
			T = pick(turfs)
	else
		var/list/destinations = tele_destinations()
		for(var/name in destinations)
			if(REF(destinations[name]) == params["ref"])
				T = destinations[name]
				break
	if(!T)
		return
	tele_open_portal(user, T)
	return TRUE

/// What the old popup did once a destination was picked
/obj/item/hand_tele/proc/tele_open_portal(mob/user, atom/T)
	if(user.get_active_held_item() != src || user.incapacitated())
		return
	if(active_portal_pairs.len >= max_portal_pairs)
		user.show_message("<span class='notice'>\The [src] is recharging!</span>")
		return
	var/area/A = get_area(T)
	if(A.noteleport || tele_blocked(user))
		to_chat(user, "<span class='notice'>\The [src] is malfunctioning.</span>")
		return
	var/turf/current_location = get_turf(user)
	user.show_message("<span class='notice'>Locked In.</span>", 2)
	var/list/obj/effect/portal/created = create_portal_pair(current_location, get_teleport_turf(get_turf(T)), src, 300, 1, null, atmos_link_override)
	if(!(LAZYLEN(created) == 2))
		return
	try_move_adjacent(created[1])
	active_portal_pairs[created[1]] = created[2]
	var/obj/effect/portal/c1 = created[1]
	var/obj/effect/portal/c2 = created[2]
	investigate_log("was used by [key_name(user)] at [AREACOORD(user)] to create a portal pair with destinations [AREACOORD(c1)] and [AREACOORD(c2)].", INVESTIGATE_PORTAL)
	add_fingerprint(user)

// Safes

/obj/structure/safe/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "safe", name, 340, 440, master_ui, state)
		ui.open()

/obj/structure/safe/ui_data(mob/user)
	var/list/inside = list()
	if(open)
		for(var/i in length(contents) to 1 step -1)
			var/obj/item/I = contents[i]
			if(istype(I))
				inside += list(list("ref" = REF(I), "name" = I.name))
	return list(
		"open" = open,
		"dial" = dial,
		"contents" = inside,
		"stethoscope" = user.is_holding_item_of_type(/obj/item/clothing/neck/stethoscope),
		"broken" = explosion_count > 2,
	)

/obj/structure/safe/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("open")
			Topic(null, list("open" = "1"))
		if("turn") // a notch at a time, as the old - and + were, so the tumblers are heard on the way
			var/by = round(text2num(params["by"]))
			var/key = by > 0 ? "increment" : "decrement"
			for(var/i in 1 to min(abs(by), 10))
				Topic(null, list("[key]" = "1"))
		if("retrieve")
			Topic(null, list("retrieve" = params["ref"]))
	return TRUE

// The destination tagger

/obj/item/destTagger/attack_self(mob/user)
	if(!locked_destination)
		ui_interact(user)

/// What its Topic() opens again after a pick: the window, not the old page over it
/obj/item/destTagger/openwindow(mob/user)
	ui_interact(user)

/obj/item/destTagger/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.inventory_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "destination_tagger", name, 460, 340, master_ui, state)
		ui.open()

/obj/item/destTagger/ui_data(mob/user)
	return list("destinations" = GLOB.TAGGERLOCATIONS, "current" = currTag)

/obj/item/destTagger/ui_act(action, params)
	if(..() || locked_destination)
		return
	if(action == "tag")
		var/n = text2num(params["index"])
		if(n >= 1 && n <= length(GLOB.TAGGERLOCATIONS)) // the old page's Topic() took any number at all
			Topic(null, list("nextTag" = "[n]"))
	return TRUE

// Secure briefcases and wall safes

/obj/item/storage/secure/attack_self(mob/user)
	ui_interact(user)

/obj/item/storage/secure/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "secure_storage", name, 310, 380, master_ui, state)
		ui.open()

/obj/item/storage/secure/ui_data(mob/user)
	var/locked = SEND_SIGNAL(src, COMSIG_IS_STORAGE_LOCKED)
	return list(
		"locked" = !!locked,
		"display" = locked ? code : "*****",
		"code_set" = !!l_set,
		"memory_error" = !!l_setshort,
	)

/obj/item/storage/secure/ui_act(action, params)
	if(..())
		return
	if(action == "key" && (params["key"] in list("1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "R", "E")))
		Topic(null, list("type" = params["key"]))
	return TRUE
