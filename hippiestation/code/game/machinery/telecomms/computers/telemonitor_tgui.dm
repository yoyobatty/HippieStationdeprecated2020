// hippie -- the telecommunications monitor is a tgui window: the network typed in place, Probe and Flush, the machines it
// found with whether each is on, and a machine's links. The buttons go through the console's own Topic(), so probing
// (machines within 25 tiles on that network) and the messages are the old window's.

/obj/machinery/computer/telecomms/monitor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "telecomms_monitor", name, 480, 460, master_ui, state)
		ui.open()

/obj/machinery/computer/telecomms/monitor/ui_data(mob/user)
	var/list/data = list()
	data["network"] = network
	data["notice"] = temp ? comm_plain_text(temp) : null
	data["failed"] = !!findtext(temp, "FAILED")
	var/list/machines = list()
	for(var/obj/machinery/telecomms/T in machinelist)
		machines += list(telecomms_monitor_entry(T))
	data["machines"] = machines
	data["selected"] = null
	if(screen == 1 && SelectedMachine)
		var/list/links = list()
		for(var/obj/machinery/telecomms/T in SelectedMachine.links)
			if(!T.hide)
				links += list(telecomms_monitor_entry(T))
		data["selected"] = list("name" = SelectedMachine.name, "id" = SelectedMachine.id, "on" = SelectedMachine.on, "links" = links)
	return data

/obj/machinery/computer/telecomms/monitor/proc/telecomms_monitor_entry(obj/machinery/telecomms/T)
	return list("name" = T.name, "id" = T.id, "on" = T.on, "buffered" = (T in machinelist))

/obj/machinery/computer/telecomms/monitor/ui_act(action, params)
	if(..())
		return
	temp = "" // the old window showed each message once
	switch(action)
		if("probe")
			Topic(null, list("operation" = "probe"))
		if("flush")
			Topic(null, list("operation" = "release"))
		if("main")
			Topic(null, list("operation" = "mainmenu"))
		if("view")
			Topic(null, list("viewmachine" = "[params["id"]]"))
		if("network")
			// Typed in the window: the old Topic asked in a popup, with the same rules after
			var/newnet = stripped_input_text(params["network"], MAX_MESSAGE_LEN)
			if(!newnet)
				return
			add_fingerprint(usr)
			if(length(newnet) > 15)
				temp = "<font color = #D70B00>- FAILED: NETWORK TAG STRING TOO LENGHTLY -</font color>"
			else
				network = newnet
				screen = 0
				machinelist = list()
				temp = "<font color = #336699>- NEW NETWORK TAG SET IN ADDRESS \[[network]\] -</font color>"
	return TRUE
