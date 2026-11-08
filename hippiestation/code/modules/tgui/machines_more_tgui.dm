// hippie -- more machines off their old HTML windows (interfaces/MachinesMore.js): an exosuit's maintenance and access panels (the ID
// card swiped on it), the telepad control console, a gas analyzer's scan history, the prototype cloning console and the bluespace
// artillery control. Buttons go through each one's own Topic() where it had one; numbers typed in the window are clamped as the old
// prompts' answers were.

// ---------------------------------------------------------------------------------------------
// An exosuit's maintenance and access panels
// ---------------------------------------------------------------------------------------------

/obj/mecha
	var/datum/exosuit_maint_window/maint_window

/obj/mecha/output_maintenance_dialog(obj/item/card/id/id_card, mob/user)
	exosuit_maint_open(id_card, user, "maint")

/obj/mecha/output_access_dialog(obj/item/card/id/id_card, mob/user)
	exosuit_maint_open(id_card, user, "access")

/obj/mecha/proc/exosuit_maint_open(obj/item/card/id/id_card, mob/user, screen)
	if(!id_card || !user)
		return
	if(!maint_window)
		maint_window = new(src)
	maint_window.card_ref = WEAKREF(id_card)
	maint_window.screen = screen
	maint_window.ui_interact(user)
	SStgui.update_uis(maint_window)

/obj/mecha/Destroy()
	QDEL_NULL(maint_window)
	return ..()

/datum/exosuit_maint_window
	var/obj/mecha/mech
	var/datum/weakref/card_ref
	var/screen = "maint"

/datum/exosuit_maint_window/New(obj/mecha/M)
	mech = M

/datum/exosuit_maint_window/Destroy()
	SStgui.close_uis(src)
	mech = null
	return ..()

/datum/exosuit_maint_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "exosuit_maint", "[mech.name] maintenance", 420, 480, master_ui, state)
		ui.open()

/datum/exosuit_maint_window/ui_status(mob/user, datum/ui_state/state)
	if(!mech || !in_range(mech, user) || user.incapacitated())
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/exosuit_maint_window/ui_data(mob/user)
	var/obj/item/card/id/card = card_ref?.resolve()
	. = list()
	.["screen"] = screen
	.["name"] = mech.name
	.["paint"] = mech.mecha_ui_paint()
	.["can_edit_access"] = !!mech.add_req_access
	.["can_maint"] = !!mech.maint_access
	.["maint_on"] = mech.state > 0
	.["pressure"] = mech.internal_tank_valve
	var/list/required = list()
	for(var/a in mech.operation_req_access)
		required += list(list("id" = a, "name" = get_access_desc(a)))
	.["required"] = required
	var/list/on_card = list()
	if(card)
		for(var/a in card.access)
			if(a in mech.operation_req_access)
				continue
			var/a_name = get_access_desc(a)
			if(a_name)
				on_card += list(list("id" = a, "name" = a_name))
	.["on_card"] = on_card

/datum/exosuit_maint_window/ui_act(action, list/params)
	if(..())
		return
	var/obj/item/card/id/card = card_ref?.resolve()
	switch(action)
		if("access")
			if(mech.add_req_access && card)
				screen = "access"
		if("back")
			screen = "maint"
		if("maint")
			mech.Topic(null, list("maint_access" = "1", "id_card" = REF(card)))
		if("pressure")
			// Set Cabin Air Pressure, typed in the window
			var/value = text2num(params["value"])
			if(mech.state >= 1 && value)
				mech.internal_tank_valve = value
				to_chat(usr, "The internal pressure valve has been set to [mech.internal_tank_valve]kPa.")
		if("add")
			mech.Topic(null, list("add_req_access" = "[text2num(params["id"])]", "id_card" = REF(card)))
		if("remove")
			// The old Topic() removed the code from "add_req_access" (not there), so Delete never worked
			if(mech.add_req_access && card)
				mech.operation_req_access -= text2num(params["id"])
		if("finish")
			mech.add_req_access = 0
			screen = "maint"
	return TRUE

// ---------------------------------------------------------------------------------------------
// The telepad control console
// ---------------------------------------------------------------------------------------------

/obj/machinery/computer/telescience/interact(mob/user)
	ui_interact(user)

/obj/machinery/computer/telescience/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "telescience", name, 460, 560, master_ui, state)
		ui.open()

/obj/machinery/computer/telescience/ui_data(mob/user)
	. = list()
	.["telepad"] = !!telepad
	if(!telepad)
		in_use = 0
		return
	.["message"] = comm_plain_text(temp_msg)
	.["gps"] = inserted_gps ? inserted_gps.name : null
	.["rotation"] = rotation
	.["angle"] = angle
	.["power"] = power
	.["sector"] = z_co
	.["crystals"] = length(crystals)
	.["max_crystals"] = max_crystals
	.["maintenance"] = !!telepad.panel_open
	.["teleporting"] = !!teleporting
	var/list/powers = list()
	for(var/i in 1 to length(power_options))
		powers += list(list("index" = i, "power" = power_options[i], "usable" = length(crystals) + telepad.efficiency >= i))
	.["powers"] = powers
	if(last_tele_data)
		.["last"] = list("x" = last_tele_data.src_x, "y" = last_tele_data.src_y, "time" = round(last_tele_data.time, 0.1))

/obj/machinery/computer/telescience/ui_act(action, list/params)
	if(..())
		return
	if(!telepad)
		return
	switch(action)
		// The old prompts' answers, clamped and rounded as they were
		if("rotation")
			var/value = text2num(params["value"])
			if(!isnull(value))
				rotation = round(clamp(value, -900, 900), 0.01)
		if("angle")
			var/value = text2num(params["value"])
			if(!isnull(value))
				angle = clamp(round(value, 0.1), 1, 9999)
		if("sector")
			var/value = text2num(params["value"])
			if(!isnull(value))
				z_co = clamp(round(value), 1, 10)
		if("power")
			Topic(null, list("setpower" = "[text2num(params["index"])]"))
		if("send")
			Topic(null, list("send" = "1"))
		if("receive")
			Topic(null, list("receive" = "1"))
		if("recalibrate")
			Topic(null, list("recal" = "1"))
		if("eject")
			Topic(null, list("eject" = "1"))
		if("eject_gps")
			Topic(null, list("ejectGPS" = "1"))
	return TRUE

// ---------------------------------------------------------------------------------------------
// A gas analyzer's scan history
// ---------------------------------------------------------------------------------------------

/obj/item/analyzer
	var/datum/analyzer_history_window/history_window

/obj/item/analyzer/show_scan_history(mob/user)
	if(!history_window)
		history_window = new(src)
	history_window.ui_interact(user)

/obj/item/analyzer/Topic(href, href_list)
	. = ..()
	SStgui.update_uis(history_window)

/datum/analyzer_history_window
	var/obj/item/analyzer/analyzer

/datum/analyzer_history_window/New(obj/item/analyzer/A)
	analyzer = A

/datum/analyzer_history_window/Destroy()
	SStgui.close_uis(src)
	analyzer = null
	return ..()

/obj/item/analyzer/Destroy()
	QDEL_NULL(history_window)
	return ..()

/datum/analyzer_history_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "analyzer_history", "[analyzer.name] scan history", 640, 480, master_ui, state)
		ui.open()

/datum/analyzer_history_window/ui_status(mob/user, datum/ui_state/state)
	if(!analyzer || !user.canUseTopic(analyzer, BE_CLOSE, FALSE, NO_TK))
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/analyzer_history_window/ui_data(mob/user)
	// Each reading's change against the previous reading of the same place, newest first (show_scan_history()'s table)
	var/list/rows = list()
	var/list/last_by_key = list()
	for(var/list/entry in analyzer.scan_history)
		var/list/previous = last_by_key[entry["key"]]
		last_by_key[entry["key"]] = entry
		var/list/gases = list()
		var/list/composition = entry["composition"]
		for(var/gas in composition)
			if(composition[gas] >= 0.1)
				gases += list(list("name" = gas, "percent" = round(composition[gas], 0.1)))
		rows.Insert(1, list(list("stamp" = entry["stamp"], "label" = entry["label"], "pressure" = round(entry["pressure"], 0.01), \
			"kelvin" = round(entry["temperature"], 0.1), "celsius" = round(entry["temperature"] - T0C, 0.1), "moles" = round(entry["moles"], 0.01), \
			"gases" = gases, "d_pressure" = previous ? round(entry["pressure"] - previous["pressure"], 0.01) : null, \
			"d_temperature" = previous ? round(entry["temperature"] - previous["temperature"], 0.01) : null)))
	return list("rows" = rows)

/datum/analyzer_history_window/ui_act(action, list/params)
	if(..())
		return
	if(action == "clear")
		analyzer.Topic(null, list("clear_history" = "1"))
		return TRUE

// ---------------------------------------------------------------------------------------------
// The prototype cloning console
// ---------------------------------------------------------------------------------------------

/obj/machinery/computer/prototype_cloning/interact(mob/user)
	user.set_machine(src)
	add_fingerprint(user)
	updatemodules(TRUE)
	ui_interact(user)

/obj/machinery/computer/prototype_cloning/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "prototype_cloning", "Prototype Cloning System Control", 420, 360, master_ui, state)
		ui.open()

/obj/machinery/computer/prototype_cloning/ui_data(mob/user)
	. = list()
	.["status"] = comm_plain_text(temp)
	.["scanner"] = !isnull(scanner)
	.["pods"] = LAZYLEN(pods)
	if(scanner)
		var/mob/living/occupant = get_mob_or_brainmob(scanner.occupant)
		.["occupant"] = occupant ? occupant.real_name : null
		.["loading"] = !!loading
		.["scan_status"] = comm_plain_text(scantemp)
		.["locked"] = !!scanner.locked

/obj/machinery/computer/prototype_cloning/ui_act(action, list/params)
	if(..())
		return
	if(action in list("clone", "lock", "refresh"))
		Topic(null, list("[action]" = "1"))
		return TRUE

// ---------------------------------------------------------------------------------------------
// The bluespace artillery control (away missions)
// ---------------------------------------------------------------------------------------------

/obj/machinery/artillerycontrol/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "artillery_control", "Bluespace Artillery Control", 420, 560, master_ui, state)
		ui.open()

/obj/machinery/artillerycontrol/ui_static_data(mob/user)
	var/list/areas = list()
	for(var/name in GLOB.teleportlocs)
		areas += name
	return list("areas" = sortList(areas))

/obj/machinery/artillerycontrol/ui_data(mob/user)
	return list("reload" = reload, "reload_cooldown" = reload_cooldown)

/obj/machinery/artillerycontrol/ui_act(action, list/params)
	if(..())
		return
	if(action == "fire")
		artillery_fire(usr, "[params["area"]]")
		return TRUE

/// The old Topic()'s strike, with the area picked in the window, not a list prompt
/obj/machinery/artillerycontrol/proc/artillery_fire(mob/user, area_name)
	var/area/thearea = GLOB.teleportlocs[area_name]
	if(!thearea || user.stat || user.restrained() || reload < reload_cooldown)
		return
	if(!(user.contents.Find(src) || (in_range(src, user) && isturf(loc)) || issilicon(user)))
		return
	priority_announce("Bluespace artillery fire detected. Brace for impact.")
	message_admins("[ADMIN_LOOKUPFLW(user)] has launched an artillery strike.")
	var/list/L = list()
	for(var/turf/T in get_area_turfs(thearea.type))
		L += T
	if(!L.len)
		return
	explosion(pick(L), explosiondev, explosionmed, explosionlight)
	reload = 0
