// The Station Looks admin window (interfaces/StationLooks.js): this round's looks by slot, each with its weight. Click one to
// force it, ban it out of re-rolls, or re-roll a slot or the lot. Works in the lobby and later: a look forced mid-round goes on
// at once and takes the one it replaces off.

GLOBAL_DATUM(station_looks_window, /datum/station_looks_window)

/client/proc/cmd_admin_station_looks()
	set category = "Special Verbs"
	set name = "Station Looks"
	set desc = "Force, ban or re-roll this round's station looks: sky, shift time, extras, history."
	if(!check_rights(R_FUN))
		return
	if(!GLOB.station_looks_window)
		GLOB.station_looks_window = new
	GLOB.station_looks_window.ui_interact(usr)

/datum/station_looks_window

/datum/station_looks_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "station_looks", "Station Looks", 420, 600, master_ui, state)
		ui.open()

/datum/station_looks_window/ui_status(mob/user, datum/ui_state/state)
	return check_rights_for(user.client, R_FUN) ? UI_INTERACTIVE : UI_CLOSE

/datum/station_looks_window/ui_data(mob/user)
	var/datum/controller/subsystem/station_looks/S = SSstation_looks
	var/list/slots = list()
	var/static/list/slot_names = list(LOOK_SLOT_SKY = "Sky", LOOK_SLOT_SHIFT = "Shift time", LOOK_SLOT_EXTRA = "Extras", LOOK_SLOT_HISTORY = "History")
	for(var/slot in GLOB.station_look_slots)
		var/list/looks = list()
		for(var/id in S.looks)
			var/datum/station_look/L = S.looks[id]
			if(L.slot != slot)
				continue
			looks += list(list(
				"id" = id,
				"name" = L.name,
				"weight" = S.look_weight(L),
				"picked" = (id in S.picked[slot]),
				"banned" = !!S.banned[id],
				"on" = L.active))
		if(!length(looks))
			continue
		var/list/rule = GLOB.station_look_slots[slot]
		slots += list(list(
			"id" = slot,
			"name" = slot_names[slot],
			"most" = rule[1],
			"none" = S.none_weight(slot),
			"locked" = S.slot_locked(slot),
			"looks" = looks))
	return list(
		"started" = S.applied,
		"notes" = S.notes_text(),
		"slots" = slots)

/datum/station_looks_window/ui_act(action, list/params)
	if(..() || !check_rights(R_FUN))
		return
	var/datum/controller/subsystem/station_looks/S = SSstation_looks
	var/what
	switch(action)
		if("force")
			var/datum/station_look/L = S.looks[params["id"]]
			if(!L || !S.force(L.id))
				return
			what = "[(L.id in S.picked[L.slot]) ? "forced" : "took off"] [L.name]"
		if("ban")
			var/datum/station_look/L = S.looks[params["id"]]
			if(!L)
				return
			if(S.banned[L.id])
				S.banned -= L.id
				what = "let [L.name] back into re-rolls"
			else
				S.banned[L.id] = TRUE
				what = "banned [L.name] from re-rolls"
		if("reroll")
			var/slot = params["slot"]
			if(!(slot in GLOB.station_look_slots) || !S.roll_slot(slot))
				return
			what = "re-rolled the [slot] look"
		if("reroll_all")
			for(var/slot in GLOB.station_look_slots)
				S.roll_slot(slot)
			what = "re-rolled the station looks"
		else
			return
	message_admins("[key_name_admin(usr)] [what]: [S.summary()].")
	log_admin("[key_name(usr)] [what]: [S.summary()].")
	return TRUE
