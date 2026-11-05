// hippie -- the power flow control console is a tgui window. The buttons go through the console's own Topic(), so logging
// in, the activity log, and reaching an APC (it unlocks, says so, and its own window opens) are the old window's. The
// filters are worked in the window, so typing in them no longer fills the log.
//
// In a grid failure (the Grid Check event times every APC out for one to four minutes) the console keeps going on a backup
// cell, and Reset all APCs brings them back one after another, nearest first, over 15 seconds.

#define APC_RESET_TIME (15 SECONDS)

/obj/machinery/computer/apc_control
	/// Running on its backup cell: its room's APC is down in a grid failure
	var/backup_power = FALSE
	/// The APCs still to come back in a reset, nearest first; null when there's no reset going
	var/list/resetting
	var/reset_total = 0
	var/reset_done = 0
	/// Where the last one to come back was
	var/reset_last

/obj/machinery/computer/apc_control/power_change()
	. = ..()
	backup_power = FALSE
	if(!(stat & NOPOWER) || (stat & BROKEN))
		return
	// Only a grid failure: a smashed, emptied or switched-off APC still takes it down
	var/area/room = get_area(src)
	var/obj/machinery/power/apc/local = room?.get_apc()
	if(local?.failure_timer && local.operating && !(local.stat & (BROKEN|MAINT)))
		stat &= ~NOPOWER
		backup_power = TRUE
		set_light(brightness_on)
		update_icon()

/// The reset is the Chief Engineer's: anyone else with engine access still reaches the APCs one at a time
/obj/machinery/computer/apc_control/proc/can_reset_grid(mob/user)
	var/obj/item/card/id/ID = user?.get_idcard(TRUE)
	return istype(ID) && (ACCESS_CE in ID.access)

/obj/machinery/computer/apc_control/proc/start_reset()
	if(resetting)
		return
	var/list/down = list()
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(check_apc(APC) && APC.failure_timer)
			down[APC] = get_dist(src, APC)
	if(!length(down))
		return
	sortTim(down, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
	resetting = list()
	for(var/APC in down)
		resetting += APC
	reset_total = length(resetting)
	reset_done = 0
	reset_last = null
	log_activity("began resetting [reset_total] APCs after a grid failure")
	log_game("[key_name(usr)] began resetting [reset_total] APCs from [src] at [AREACOORD(src)].")
	playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, FALSE)
	say("Grid reset started: [reset_total] APC\s.")
	INVOKE_ASYNC(src, PROC_REF(run_reset))

/// One APC every 15 seconds / however many there are, so the station comes back outward from here
/obj/machinery/computer/apc_control/proc/run_reset()
	var/started = world.time
	while(length(resetting))
		// Each one at its share of the 15 seconds from the start, so ticks rounding the waits don't add up
		sleep(max(0, started + APC_RESET_TIME * (reset_done + 1) / reset_total - world.time))
		if(QDELETED(src))
			return
		if(stat & (BROKEN|NOPOWER))
			log_activity("grid reset cut off with [length(resetting)] APC\s to go")
			resetting = null
			return
		var/obj/machinery/power/apc/APC = resetting[1]
		resetting.Cut(1, 2)
		reset_done++
		if(QDELETED(APC) || !APC.failure_timer)
			continue
		APC.failure_timer = 0
		APC.update_icon()
		APC.update()
		reset_last = get_area_name(APC.area, TRUE)
		playsound(APC, 'sound/machines/terminal_on.ogg', 40, FALSE)
		playsound(src, "terminal_type", 25, FALSE)
		SStgui.update_uis(src)
	resetting = null
	log_activity("reset [reset_total] APC\s")
	playsound(src, 'sound/machines/ping.ogg', 50, FALSE)
	say("Grid reset complete.")
	SStgui.update_uis(src)

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
	data["backup_power"] = backup_power
	data["resetting"] = !!resetting
	data["reset_done"] = reset_done
	data["reset_total"] = reset_total
	data["reset_last"] = reset_last
	if(!authenticated)
		return data
	if(checking_logs)
		var/list/entries = list()
		for(var/entry in logs)
			entries += comm_plain_text(entry)
		data["logs"] = entries
		return data
	var/list/apcs = list()
	var/down = 0
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(!check_apc(APC))
			continue
		if(APC.failure_timer)
			down++
		apcs += list(list(
			"failed" = !!APC.failure_timer,
			"dist" = get_dist(src, APC),
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
	data["down"] = down
	data["can_reset"] = can_reset_grid(user)
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
		if("reset_all")
			if(!authenticated || resetting)
				return
			if(!can_reset_grid(usr))
				to_chat(usr, "<span class='warning'>Resetting the grid needs the Chief Engineer's ID.</span>")
				playsound(src, 'sound/machines/terminal_prompt_deny.ogg', 50, FALSE)
				return
			start_reset()
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

#undef APC_RESET_TIME
