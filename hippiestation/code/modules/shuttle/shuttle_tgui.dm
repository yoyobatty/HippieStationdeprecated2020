// The shuttle console (every shuttle that uses /obj/machinery/computer/shuttle: ferry, mining, labor, syndicate, pods)
// and the mass driver console moved to tgui (tgui-next ShuttleConsole.js). Buttons run the console's own Topic(), so
// each subtype's rules (challenge timer, one-way pods, labor camp checks, access) still apply.

/obj/machinery/computer/shuttle/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
											datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/obj/docking_port/mobile/M = SSshuttle.getShuttle(shuttleId)
		ui = new(user, src, ui_key, "shuttle_console", M ? M.name : "Shuttle", 400, 210, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/shuttle/ui_data(mob/user)
	var/list/data = list()
	var/obj/docking_port/mobile/M = SSshuttle.getShuttle(shuttleId)
	data["found"] = !!M
	data["status"] = M ? M.getStatusText() : "Missing"
	data["moving"] = M ? (M.mode != SHUTTLE_IDLE) : FALSE
	data["authorized"] = allowed(user)
	data["emagged"] = !!(obj_flags & EMAGGED)
	data["admin_controlled"] = !!admin_controlled
	var/list/destinations = list()
	if(M)
		var/list/options = params2list(possible_destinations)
		var/obj/docking_port/stationary/here = M.get_docked()
		for(var/obj/docking_port/stationary/S in SSshuttle.stationary)
			if(!options.Find(S.id))
				continue
			if(!M.check_dock(S, silent = TRUE))
				continue
			destinations += list(list("id" = S.id, "name" = S.name, "here" = (S == here)))
	data["destinations"] = destinations
	return data

/obj/machinery/computer/shuttle/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("move")
			Topic(null, list("move" = params["id"]))
			return TRUE
		if("request")
			Topic(null, list("request" = "1"))
			return TRUE

// Mass driver console

/obj/machinery/computer/pod/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!allowed(user))
		to_chat(user, "<span class='warning'>Access denied.</span>")
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "mass_driver_console", title, 420, connected ? 290 : 130, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/pod/ui_data(mob/user)
	var/list/data = list()
	data["connected"] = !!connected
	data["timing"] = timing
	data["time"] = time
	data["power"] = connected ? connected.power : 0
	data["power_levels"] = list(0.25, 0.5, 1, 2, 4, 8, 16)
	var/door_open = null
	for(var/obj/machinery/door/poddoor/D in range(range, src))
		if(D.id == id)
			door_open = !D.density
			break
	data["door_open"] = door_open
	return data

/obj/machinery/computer/pod/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("power")
			Topic(null, list("power" = params["level"]))
			return TRUE
		if("timer")
			Topic(null, list("time" = timing ? "0" : "1"))
			return TRUE
		if("time")
			var/target = text2num(params["time"])
			if(!isnull(target))
				Topic(null, list("tp" = "[round(target) - time]"))
			return TRUE
		if("fire")
			// alarm() sleeps between the doors and the driver
			INVOKE_ASYNC(src, PROC_REF(pod_topic), usr, list("alarm" = "1"))
			return TRUE
		if("test")
			Topic(null, list("drive" = "1"))
			return TRUE
		if("door")
			Topic(null, list("door" = "1"))
			return TRUE

/obj/machinery/computer/pod/proc/pod_topic(mob/user, list/href_list)
	usr = user
	Topic(null, href_list)
