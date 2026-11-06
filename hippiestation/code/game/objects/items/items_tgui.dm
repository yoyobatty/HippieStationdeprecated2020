// The tank transfer valve and the cyborg frame's debug window moved off their old HTML windows (tgui-next Items.js). The
// buttons run each one's own Topic(); the frame's name and master AI, which were pop-ups, come from the window, with
// the same checks.

// Tank transfer valve: both tanks with what's in them, the device on the valve, and the valve

/obj/item/transfer_valve/attack_self(mob/user)
	ui_interact(user)

/obj/item/transfer_valve/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "transfer_valve", name, 460, 420, master_ui, state)
		ui.open()

/obj/item/transfer_valve/proc/tgui_tank(obj/item/tank/T)
	if(!T)
		return null
	return list(
		"name" = T.name,
		"pressure" = round(T.air_contents.return_pressure(), 0.1),
		"temperature" = round(T.air_contents.temperature, 0.1),
		"gases" = tgui_gas_list(T.air_contents),
	)

/obj/item/transfer_valve/ui_data(mob/user)
	var/list/data = list()
	data["tank_one"] = tgui_tank(tank_one)
	data["tank_two"] = tgui_tank(tank_two)
	data["device"] = attached_device ? attached_device.name : null
	data["valve_open"] = valve_open
	return data

/obj/item/transfer_valve/ui_act(action, list/params)
	if(..())
		return
	var/static/list/hrefs = list("remove_one" = "tankone", "remove_two" = "tanktwo", "valve" = "open", \
		"configure" = "device", "remove_device" = "rem_device")
	if(hrefs[action])
		Topic(null, list("[hrefs[action]]" = "1"))
		return TRUE

// Cyborg frame: the boot debug a multitool opens on a finished endoskeleton

/obj/item/robot_suit/Interact(mob/user)
	ui_interact(user)

/obj/item/robot_suit/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
								datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "cyborg_frame", "Cyborg Boot Debug", 420, 260, master_ui, state)
		ui.open()

/obj/item/robot_suit/ui_data(mob/user)
	var/list/data = list()
	data["name"] = created_name
	data["master"] = forced_ai ? forced_ai.name : null
	var/list/ais = list()
	for(var/mob/living/silicon/ai/A in active_ais())
		ais += list(list("ref" = REF(A), "name" = A.name))
	data["ais"] = ais
	data["lawsync"] = lawsync
	data["aisync"] = aisync
	data["locomotion"] = locomotion
	data["panel_locked"] = panel_locked
	var/mob/living/L = user
	var/obj/item/held = istype(L) ? L.get_active_held_item() : null
	data["multitool"] = held?.tool_behaviour == TOOL_MULTITOOL
	return data

/// The old Topic's checks: awake, beside it, a multitool in hand
/obj/item/robot_suit/proc/tgui_can_debug(mob/user)
	if(user.incapacitated() || !Adjacent(user))
		return FALSE
	var/mob/living/L = user
	var/obj/item/held = istype(L) ? L.get_active_held_item() : null
	if(held?.tool_behaviour != TOOL_MULTITOOL)
		to_chat(user, "<span class='warning'>You need a multitool!</span>")
		return FALSE
	return TRUE

/obj/item/robot_suit/ui_act(action, list/params)
	if(..())
		return
	var/static/list/hrefs = list("lawsync" = "Law", "aisync" = "AI", "locomotion" = "Loco", "panel" = "Panel")
	if(hrefs[action])
		Topic(null, list("[hrefs[action]]" = "1"))
		return TRUE
	switch(action)
		if("name")
			if(!tgui_can_debug(usr))
				return
			var/new_name = reject_bad_name(params["name"], TRUE)
			created_name = new_name || ""
			add_fingerprint(usr)
			return TRUE
		if("master")
			if(!tgui_can_debug(usr))
				return
			forced_ai = null
			for(var/mob/living/silicon/ai/A in active_ais())
				if(REF(A) == params["ref"])
					forced_ai = A
			add_fingerprint(usr)
			return TRUE
