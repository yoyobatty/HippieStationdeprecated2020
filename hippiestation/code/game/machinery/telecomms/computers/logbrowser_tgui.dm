// hippie -- the telecommunications server monitor is a tgui window: the network typed in place, Scan and Flush, the servers
// it found, and a server's traffic and stored logs, each with its speaker, job and class, and the words only if you know
// the language. The buttons go through the console's own Topic(), so scanning and deleting (telecomms access, or an emag)
// are the old window's.

/obj/machinery/computer/telecomms/server/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "telecomms_logs", name, 520, 540, master_ui, state)
		ui.open()

/obj/machinery/computer/telecomms/server/ui_data(mob/user)
	var/list/data = list()
	data["network"] = network
	data["notice"] = temp ? comm_plain_text(temp) : null
	data["failed"] = !!findtext(temp, "FAILED")
	var/list/found = list()
	for(var/obj/machinery/telecomms/server/S in servers)
		found += list(list("name" = S.name, "id" = S.id))
	data["servers"] = found
	data["selected"] = null
	if(screen == 1 && SelectedServer)
		var/traffic = SelectedServer.totaltraffic >= 1024 ? "[round(SelectedServer.totaltraffic / 1024)] Terrabytes" : "[SelectedServer.totaltraffic] Gigabytes"
		var/list/logs = list()
		var/index = 0
		for(var/datum/comm_log_entry/C in SelectedServer.log_entries)
			index++
			logs += list(telecomms_log_entry(C, index, user))
		data["selected"] = list("id" = SelectedServer.id, "traffic" = traffic, "logs" = logs)
	return data

/// One stored log as the old window told it to this reader
/obj/machinery/computer/telecomms/server/proc/telecomms_log_entry(datum/comm_log_entry/C, index, mob/user)
	var/list/entry = list("index" = index, "name" = C.name, "type" = C.input_type)
	if(C.input_type == "Speech File")
		entry["kind"] = "speech"
		var/mobtype = C.parameters["mobtype"]
		var/race
		if(ispath(mobtype, /mob/living/carbon/human) || ispath(mobtype, /mob/living/brain))
			race = "Humanoid"
		else if(ispath(mobtype, /mob/living/simple_animal/slime))
			race = "Slime"
		else if(ispath(mobtype, /mob/living/carbon/monkey))
			race = "Monkey"
		else if(ispath(mobtype, /mob/living/silicon) || C.parameters["job"] == "AI")
			race = "Artificial Life"
		else if(isobj(mobtype))
			race = "Machinery"
		else if(ispath(mobtype, /mob/living/simple_animal))
			race = "Domestic Animal"
		else
			race = "Unidentifiable"
		entry["source"] = C.parameters["name"]
		entry["job"] = C.parameters["job"]
		entry["race"] = race
		var/message = C.parameters["message"]
		var/language = C.parameters["language"]
		if(universal_translate || user.has_language(language))
			entry["message"] = "\"[comm_plain_text(message)]\""
		else
			var/datum/language/D = GLOB.language_datum_instances[language]
			entry["message"] = D ? "\"[comm_plain_text(D.scramble(message))]\"" : "(unintelligible)"
	else if(C.input_type == "Execution Error")
		entry["kind"] = "error"
		entry["message"] = "\"[comm_plain_text(C.parameters["message"])]\""
	else
		entry["kind"] = "other"
		entry["message"] = "(unintelligible)"
	return entry

/obj/machinery/computer/telecomms/server/ui_act(action, params)
	if(..())
		return
	temp = "" // the old window showed each message once
	switch(action)
		if("scan")
			Topic(null, list("operation" = "scan"))
		if("flush")
			Topic(null, list("operation" = "release"))
		if("main")
			Topic(null, list("operation" = "mainmenu"))
		if("view")
			Topic(null, list("viewserver" = "[params["id"]]"))
		if("delete")
			// A log that's there: the old Topic took any number
			var/index = text2num(params["index"])
			if(!SelectedServer || !index || index < 1 || index > length(SelectedServer.log_entries))
				return
			Topic(null, list("delete" = "[index]"))
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
				servers = list()
				temp = "<font color = #336699>- NEW NETWORK TAG SET IN ADDRESS \[[network]\] -</font color>"
	return TRUE
