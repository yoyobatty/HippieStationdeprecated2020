// hippie -- the exosuit control console as a tgui window (tgui-next interfaces/MechaControl.js): every exosuit with a tracking beacon as
// a card, its integrity and power as bars, who's in it, where it is and what it has in hand, a message typed in the window, and the EMP
// pulse asking "Sure?" before it goes. The old page was a list of the beacons' text with a popup for the message.

/obj/machinery/computer/mecha/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "mecha_control", name, 520, 600, master_ui, state)
		ui.open()

/obj/machinery/computer/mecha/ui_data(mob/user)
	var/list/mechs = list()
	for(var/obj/mecha/M in GLOB.mechas_list)
		for(var/obj/item/mecha_parts/mecha_tracking/TR in M.trackers)
			if(!TR.in_mecha())
				continue
			var/list/entry = list(
				"ref" = REF(TR),
				"name" = M.name,
				"integrity" = round(M.obj_integrity / M.max_integrity * 100),
				"cell" = M.cell ? round(M.cell.percent()) : null,
				"airtank" = M.internal_tank ? round(M.return_pressure(), 0.1) : null,
				"pilot" = M.occupant ? "[M.occupant]" : null,
				"location" = get_area_name(M, TRUE) || "Unknown",
				"active" = M.selected ? "[M.selected]" : null,
				"recharging" = !!TR.recharging,
				"ai" = !!TR.ai_beacon,
			)
			var/obj/mecha/working/ripley/R = M
			if(istype(R))
				entry["cargo"] = round(length(R.cargo) / R.cargo_capacity * 100)
			mechs += list(entry)
	return list("mechs" = mechs)

/obj/machinery/computer/mecha/ui_act(action, params)
	if(..())
		return
	var/obj/item/mecha_parts/mecha_tracking/TR = locate(params["ref"])
	if(!istype(TR) || !TR.in_mecha())
		return
	switch(action)
		if("message") // the old page's "Send Message", typed in the window
			var/message = stripped_input_text(params["text"], MAX_MESSAGE_LEN)
			var/obj/mecha/M = TR.in_mecha()
			if(message && M)
				M.occupant_message(message)
				log_game("[key_name(usr)] sent [M] the message \"[message]\" from [src] at [AREACOORD(src)]")
		if("shock")
			Topic(null, list("shock" = params["ref"]))
	return TRUE
