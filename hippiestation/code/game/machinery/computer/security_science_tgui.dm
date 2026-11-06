// Security and science machines moved off their old HTML windows (tgui-next SecurityScience.js): the prisoner
// management console, the AI system integrity restorer, the tachyon-doppler array and the automated announcement
// system. Buttons run each machine's own Topic(); where the old window asked with a pop-up (the card's goal, an implant
// message, the announcement texts) the window sends the value.

// Prisoner management console

/obj/machinery/computer/prisoner/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
											datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "prisoner_console", "Prisoner Management Console", 520, 560, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/prisoner/ui_data(mob/user)
	var/list/data = list()
	data["unlocked"] = screen == 1
	data["card"] = inserted_id ? list("name" = inserted_id.registered_name || inserted_id.name, "points" = inserted_id.points, "goal" = inserted_id.goal) : null
	data["holding_card"] = !!user.is_holding_item_of_type(/obj/item/card/id/prisoner)
	var/list/chems = list()
	for(var/obj/item/implant/chem/C in GLOB.tracked_chem_implants)
		var/turf/T = get_turf(C)
		if((T && T.z != z) || !C.imp_in)
			continue
		chems += list(list("ref" = REF(C), "name" = C.imp_in.name, "units" = C.reagents.total_volume))
	data["chem_implants"] = chems
	var/list/trackers = list()
	for(var/obj/item/implant/tracking/I in GLOB.tracked_implants)
		if(!isliving(I.imp_in))
			continue
		var/turf/T = get_turf(I)
		if(T && T.z != z)
			continue
		var/where = "Unknown"
		var/mob/living/M = I.imp_in
		if(T && is_station_level(T.z) && !isspaceturf(M.loc))
			where = "[get_area(M)]"
		trackers += list(list("ref" = REF(I), "name" = M.name, "location" = where))
	data["tracking_implants"] = trackers
	return data

/// The old Topic's reach check: in hand, beside it on the floor, or a silicon
/obj/machinery/computer/prisoner/proc/tgui_in_reach(mob/user)
	return user.contents.Find(src) || (in_range(src, user) && isturf(loc)) || issilicon(user)

/obj/machinery/computer/prisoner/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("lock")
			Topic(null, list("lock" = "1"))
			return TRUE
		if("insert", "eject", "reset")
			Topic(null, list("id" = action))
			return TRUE
		if("inject")
			var/amount = text2num(params["amount"])
			if(amount in list(1, 5, 10))
				Topic(null, list("inject[amount]" = params["ref"]))
			return TRUE
		if("goal")
			// The old "setgoal" asked with a pop-up
			if(screen != 1 || !inserted_id || !tgui_in_reach(usr))
				return
			var/num = round(text2num(params["goal"]))
			if(num >= 0)
				inserted_id.goal = min(num, 1000) // as the old cap, about 10 minutes
			return TRUE
		if("warn")
			// The old "warn" asked for the message with a pop-up
			if(screen != 1 || !tgui_in_reach(usr))
				return
			var/warning = copytext(sanitize(params["message"]), 1, MAX_MESSAGE_LEN)
			if(!warning)
				return
			var/obj/item/implant/I = locate(params["ref"]) in GLOB.tracked_implants
			if(I && istype(I) && I.imp_in)
				var/mob/living/R = I.imp_in
				to_chat(R, "<span class='italics'>You hear a voice in your head saying: '[warning]'</span>")
				log_directed_talk(usr, R, warning, LOG_SAY, "implant message")
			return TRUE

// AI system integrity restorer

/obj/machinery/computer/aifixer/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
											datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "ai_fixer", "AI System Integrity Restorer", 440, 500, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/aifixer/ui_data(mob/user)
	var/list/data = list()
	data["active"] = active
	if(!occupier)
		data["ai"] = null
		return data
	var/list/laws = list()
	var/datum/ai_laws/L = occupier.laws
	if(L.zeroth)
		laws += list(list("number" = "0", "text" = L.zeroth, "kind" = "zeroth"))
	// Hacked and ion laws get the old window's garbled numbers (ionnum()), kept per law so they don't change each refresh
	var/static/list/garbled = list()
	for(var/law in L.hacked)
		if(length(law))
			if(!garbled[law])
				garbled[law] = ionnum()
			laws += list(list("number" = garbled[law], "text" = law, "kind" = "hacked"))
	for(var/law in L.ion)
		if(length(law))
			if(!garbled[law])
				garbled[law] = ionnum()
			laws += list(list("number" = garbled[law], "text" = law, "kind" = "ion"))
	var/number = 1
	for(var/law in L.inherent + L.supplied)
		if(length(law))
			laws += list(list("number" = "[number]", "text" = law, "kind" = "normal"))
			number++
	data["ai"] = list(
		"name" = occupier.name,
		"integrity" = (occupier.health + 100) / 2,
		"dead" = occupier.stat == DEAD,
		"laws" = laws,
	)
	return data

/obj/machinery/computer/aifixer/ui_act(action, list/params)
	if(..())
		return
	if(action == "fix" && occupier && !active)
		Topic(null, list("fix" = "1"))
		return TRUE

// Tachyon-doppler array

/obj/machinery/doppler_array/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(stat)
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "doppler_array", name, 480, 460, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/doppler_array/ui_data(mob/user)
	var/list/data = list()
	data["facing"] = dir2text(dir)
	data["logs"] = message_log ? message_log.Copy() : list()
	return data

/obj/machinery/doppler_array/research/ui_data(mob/user)
	. = ..()
	if(linked_techweb)
		.["best"] = linked_techweb.largest_bomb_value
		.["cap"] = TECHWEB_BOMB_POINTCAP

/obj/machinery/doppler_array/ui_act(action, list/params)
	if(..())
		return
	if(action == "delete")
		Topic(null, list("delete_log" = "1"))
		return TRUE

// Automated announcement system

/obj/machinery/announcement_system/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
												datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!user.canUseTopic(src, !issilicon(user)))
		return TRUE
	if(stat & BROKEN)
		visible_message("<span class='warning'>[src] buzzes.</span>", "<span class='italics'>You hear a faint buzz.</span>")
		playsound(src.loc, 'sound/machines/buzz-two.ogg', 50, 1)
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "announcement_system", "Automated Announcement Configuration", 460, 300, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/announcement_system/ui_data(mob/user)
	return list("arrival" = arrival, "arrival_on" = arrivalToggle, "newhead" = newhead, "newhead_on" = newheadToggle)

/obj/machinery/announcement_system/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("toggle_arrival")
			Topic(null, list("ArrivalT-Topic" = "1"))
			return TRUE
		if("toggle_newhead")
			Topic(null, list("NewheadT-Topic" = "1"))
			return TRUE
		if("arrival", "newhead")
			// The old window asked for the text with a pop-up; same checks as its Topic
			if(!usr.canUseTopic(src, !issilicon(usr)) || (stat & BROKEN))
				return
			var/text = trim(html_encode(params["text"]), MAX_MESSAGE_LEN)
			if(!text)
				return
			if(action == "arrival")
				arrival = text
			else
				newhead = text
			add_fingerprint(usr)
			return TRUE
