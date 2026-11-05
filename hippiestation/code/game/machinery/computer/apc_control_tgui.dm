// hippie -- the power flow control console is a tgui window. The buttons go through the console's own Topic(), so logging
// in, the activity log, and reaching an APC (it unlocks, says so, and its own window opens) are the old window's. The
// filters are worked in the window, so typing in them no longer fills the log.

/obj/machinery/computer/apc_control/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(authenticated)
		operator = user // the old window took whoever had it open as the operator, for the log and the APC's own window
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "apc_control", name, 640, 580, master_ui, state)
		ui.open()

/obj/machinery/computer/apc_control/ui_data(mob/user)
	var/list/data = list()
	data["authenticated"] = authenticated
	data["auth_id"] = auth_id
	data["emagged"] = !!(obj_flags & EMAGGED)
	data["checking_logs"] = checking_logs
	data["active"] = active_apc ? REF(active_apc) : null
	if(!authenticated)
		return data
	if(checking_logs)
		var/list/entries = list()
		for(var/entry in logs)
			entries += comm_plain_text(entry)
		data["logs"] = entries
		return data
	var/list/apcs = list()
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(!check_apc(APC))
			continue
		apcs += list(list(
			"ref" = REF(APC),
			"name" = "[APC]",
			"area" = get_area_name(APC.area, TRUE),
			"charge" = APC.cell ? round(APC.cell.percent()) : null,
			"cell" = APC.cell ? "[DisplayEnergy(APC.cell.charge)] / [DisplayEnergy(APC.cell.maxcharge)]" : null,
			"charging" = APC.charging,
			"load" = DisplayPower(APC.lastused_total),
			"equipment" = APC.equipment,
			"lighting" = APC.lighting,
			"environ" = APC.environ,
			"responds" = !APC.aidisabled && !APC.panel_open,
		))
	data["apcs"] = apcs
	return data

/obj/machinery/computer/apc_control/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("log_in")
			if(!authenticated)
				operator = usr // the old window's login went in the log as "[NULL OPERATOR]"
			Topic(null, list("authenticate" = "1"))
		if("log_out")
			Topic(null, list("log_out" = "1"))
		if("access")
			// Only the APCs the window lists; the old Topic took any APC it was sent
			var/obj/machinery/power/apc/APC = locate(params["ref"]) in GLOB.apcs_list
			if(!authenticated || !APC || !check_apc(APC))
				return
			Topic(null, list("access_apc" = REF(APC)))
		if("check_logs")
			if(authenticated)
				Topic(null, list("check_logs" = "1"))
		if("check_apcs")
			if(authenticated)
				Topic(null, list("check_apcs" = "1"))
		if("restore_logging")
			if(obj_flags & EMAGGED)
				Topic(null, list("restore_logging" = "1"))
		if("clear_logs")
			// The old Topic cleared them for anyone who sent the link; only the emagged console offers it
			if(obj_flags & EMAGGED)
				Topic(null, list("clear_logs" = "1"))
	return TRUE
