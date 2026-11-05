// hippie -- a mech's own menu (View Stats) as a tgui window (tgui-next interfaces/Exosuit.js), redesigned where it helps (the user's
// ruling, 2026-11-05): integrity, power and air as bars, internal damage as warnings with what can be done about them, the equipment
// with what each piece is doing and its own controls, and the radio, permissions and cabin settings as buttons. The old page was a
// green terminal that reloaded itself every second.
// Each piece of equipment draws its own controls in get_equip_info() as links to its Topic(); they're read off it here and become the
// window's buttons, so every drill, sleeper and gun keeps what it had. Every button goes through the same Topic() the page's did.

/obj/mecha/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.contained_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "exosuit", name, 560, 640, master_ui, state)
		ui.open()

/// The links in some HTML of the old page's, as buttons: list(list("label", "target", "query")). Not "src": tgui's own act() sends that.
/proc/mecha_ui_links(html)
	. = list()
	if(!istext(html))
		return
	var/static/regex/link = regex(@#<a href=['"]\?src=(\[0x[0-9a-fA-F]+\]);([^'"]*)['"]>(.*?)</a>#, "gi")
	var/at = 1
	while(link.Find(html, at))
		var/label = trim(comm_plain_text(link.group[3]))
		if(label)
			. += list(list("label" = label, "target" = link.group[1], "query" = link.group[2]))
		at = link.next
	return

/// The same HTML with its links taken out and the rest as text: what a piece of equipment says about itself
/proc/mecha_ui_text(html, name)
	if(!istext(html))
		return ""
	var/static/regex/link = regex(@#<a [^>]*>.*?</a>#, "gi")
	var/text = comm_plain_text(link.Replace(html, ""))
	text = replacetext(text, ascii2text(160), " ")
	if(name)
		text = replacetext(text, name, "")
	var/static/regex/junk = regex(@#[\s\-|*]+$|^[\s\-|*]+#, "g")
	return trim(junk.Replace(text, ""))

/obj/mecha/ui_data(mob/user)
	var/list/data = list()
	data["name"] = name
	data["integrity"] = round(obj_integrity / max_integrity * 100)
	data["cell"] = cell ? round(cell.percent()) : null
	data["has_tank"] = !!internal_tank
	data["internal_air"] = !!use_internal_tank
	if(internal_tank)
		var/datum/gas_mixture/tank_air = internal_tank.return_air()
		data["tank_pressure"] = round(tank_air.return_pressure(), 0.1)
		data["tank_temperature"] = round(tank_air.temperature - T0C)
		data["cabin_pressure"] = round(return_pressure(), 0.1)
		data["cabin_temperature"] = round(return_temperature() - T0C)
		data["cabin_high"] = return_pressure() > WARNING_HIGH_PRESSURE
		data["port"] = !!internal_tank.connected_port
		data["port_here"] = !!(locate(/obj/machinery/atmospherics/components/unary/portables_connector) in loc)
		data["valve"] = internal_tank_valve
	var/static/list/damage_names = list(
		"[MECHA_INT_FIRE]" = "Internal fire",
		"[MECHA_INT_TEMP_CONTROL]" = "Life support malfunction",
		"[MECHA_INT_TANK_BREACH]" = "Gas tank breach",
		"[MECHA_INT_CONTROL_LOST]" = "Coordination system calibration failure",
		"[MECHA_INT_SHORT_CIRCUIT]" = "Short circuit",
	)
	var/list/damage = list()
	for(var/flag in damage_names)
		if(internal_damage & text2num(flag))
			damage += damage_names[flag]
	data["damage"] = damage
	data["control_lost"] = !!(internal_damage & MECHA_INT_CONTROL_LOST)
	data["lights"] = !!lights
	data["dna_lock"] = dna_lock
	data["can_dna"] = iscarbon(occupant)
	var/list/modes = list()
	if(thrusters_action.owner)
		modes += list(list("name" = "Thrusters", "on" = !!thrusters_active))
	if(defense_action.owner)
		modes += list(list("name" = "Defence mode", "on" = !!defence_mode))
	if(overload_action.owner)
		modes += list(list("name" = "Leg actuators overload", "on" = !!leg_overload_mode))
	if(zoom_action.owner)
		modes += list(list("name" = "Zoom", "on" = !!zoom_mode))
	if(phasing_action.owner)
		modes += list(list("name" = "Phase modulator", "on" = !!phasing))
	if(smoke_action.owner)
		modes += list(list("name" = "Smoke charges", "value" = smoke))
	if(switch_damtype_action.owner)
		modes += list(list("name" = "Damage type", "value" = damtype))
	data["modes"] = modes
	data["radio"] = radio ? list("mic" = !!radio.broadcasting, "speaker" = !!radio.listening, "frequency" = format_frequency(radio.frequency)) : null
	data["id_upload"] = !!add_req_access
	data["maint_access"] = !!maint_access
	data["maintenance"] = state
	var/list/kit = list()
	for(var/obj/item/mecha_parts/mecha_equipment/W in equipment)
		var/info = W.get_equip_info()
		var/list/links = list()
		for(var/list/L in mecha_ui_links(info))
			if(findtext(L["query"], "select_equip"))
				continue //the window's own Select
			links += list(L)
		kit += list(list(
			"ref" = REF(W),
			"name" = W.name,
			"selected" = selected == W,
			"selectable" = !!W.selectable,
			"ready" = !!W.equip_ready,
			"status" = mecha_ui_text(info, W.name),
			"links" = links,
		))
	data["equipment"] = kit
	data["cargo"] = mecha_ui_cargo()
	data["slots"] = max_equip - length(equipment)
	data["max_equip"] = max_equip
	return data

/obj/mecha/ui_act(action, params)
	if(..())
		return
	var/mob/living/U = usr
	if(U != occupant)
		return
	switch(action)
		if("select")
			Topic(null, list("select_equip" = params["ref"]))
		if("detach")
			var/obj/item/mecha_parts/mecha_equipment/W = locate(params["ref"]) in equipment
			if(W)
				W.Topic(null, list("detach" = "1"))
		if("link") // a piece of equipment's own control, or this mech's
			var/datum/D = locate(params["target"])
			if(D != src && !(D in equipment))
				return
			D.Topic(null, params2list(params["query"]))
		if("mic")
			Topic(null, list("rmictoggle" = "1"))
		if("speaker")
			Topic(null, list("rspktoggle" = "1"))
		if("frequency")
			var/by = text2num(params["by"])
			if(by in list(-10, -2, 2, 10))
				Topic(null, list("rfreq" = "[by]"))
		if("id_upload")
			Topic(null, list("toggle_id_upload" = "1"))
		if("maint_access")
			Topic(null, list("toggle_maint_access" = "1"))
		if("port")
			if(internal_tank)
				Topic(null, list("toggle_port_connection" = "1"))
		if("dna_lock")
			Topic(null, list("dna_lock" = "1"))
		if("dna_reset")
			Topic(null, list("reset_dna" = "1"))
		if("recalibrate")
			if(internal_damage & MECHA_INT_CONTROL_LOST)
				Topic(null, list("repair_int_control_lost" = "1"))
		if("internals") // the Toggle Internal Airtank Usage button
			internals_action?.Activate()
		if("lights") // the Toggle Lights button
			lights_action?.Activate()
		if("unload") // a Ripley's "Unload"
			Topic(null, list("drop_from_cargo" = params["ref"]))
		if("rename") // "Change exosuit name", typed in the window
			var/new_name = stripped_input_text(params["name"], MAX_NAME_LEN)
			if(new_name && !U.incapacitated())
				name = new_name
	return TRUE

/// What's in its cargo hold, for one that has one: list("items", "capacity"), or null
/obj/mecha/proc/mecha_ui_cargo()
	return null

/obj/mecha/working/ripley/mecha_ui_cargo()
	var/list/items = list()
	for(var/obj/O in cargo)
		items += list(list("ref" = REF(O), "name" = O.name))
	return list("items" = items, "capacity" = cargo_capacity)

/// Hippie's locker mech has a hold too (makeshift/lockermech.dm): the window missed it, and its Unload links went with the old page
/obj/mecha/makeshift/mecha_ui_cargo()
	var/list/items = list()
	for(var/obj/O in cargo)
		items += list(list("ref" = REF(O), "name" = O.name))
	return list("items" = items, "capacity" = cargo_capacity)
