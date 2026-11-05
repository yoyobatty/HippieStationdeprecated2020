// hippie -- the requests console is a tgui window: its messages with Reply, tabs to ask a department for help or supplies or
// to tell it something, the three emergency calls, and on an announcement console a station-wide announcement. A message
// is written in the window, not a popup, and swiping an ID or a stamp on the console authenticates it as before.
// Buttons go through the console's own Topic() where they didn't ask anything.

// As requests_console.dm has them (it undefines them at its end)
#define REQ_TGUI_SCREEN_MAIN 0
#define REQ_TGUI_SCREEN_SENT 6
#define REQ_TGUI_SCREEN_ERR 7
#define REQ_TGUI_SCREEN_VIEW_MSGS 8
#define REQ_TGUI_SCREEN_AUTHENTICATE 9
#define REQ_TGUI_SCREEN_ANNOUNCE 10

/obj/machinery/requests_console
	/// The messages as the window shows them, oldest first; `messages` keeps the old HTML
	var/list/message_entries = list()

/obj/machinery/requests_console/createmessage(source, source_department, message, msgVerified, msgStamped, priority, radio_freq)
	. = ..()
	message_entries += list(list(
		"from" = source_department || source || "unknown",
		"reply" = (source_department && GLOB.req_console_ckey_departments[ckey(source_department)]) ? ckey(source_department) : null,
		"time" = station_time_timestamp(),
		"body" = comm_plain_text(message),
		"verified" = msgVerified ? comm_plain_text(msgVerified) : null,
		"stamped" = msgStamped ? comm_plain_text(msgStamped) : null,
		"priority" = priority,
		"request" = (GLOB.station_request_sending && ckey(GLOB.station_request_sending.to_dept) == ckey(department)) ? GLOB.station_request_sending.id : null,
	))

/obj/machinery/requests_console/ui_static_data(mob/user)
	var/list/data = list()
	// The crates Cargo can be asked for, as the cargo request console offers them
	var/list/packs = list()
	for(var/path in SSshuttle.supply_packs)
		var/datum/supply_pack/pack = SSshuttle.supply_packs[path]
		if(pack.hidden || pack.contraband || pack.DropPodOnly || (pack.special && !pack.special_enabled))
			continue
		packs += list(list("id" = "[path]", "name" = pack.name, "cost" = pack.cost, "group" = pack.group))
	data["packs"] = packs
	var/list/quick = list()
	for(var/name in GLOB.req_quick_requests)
		var/list/info = GLOB.req_quick_requests[name]
		if(GLOB.req_console_ckey_departments[ckey(info[1])] && ckey(info[1]) != ckey(department))
			quick += list(list("name" = name, "department" = info[1], "icon" = info[3], "priority" = info[4]))
	data["quick"] = quick
	data["cargo"] = !!GLOB.req_console_ckey_departments["cargobay"]
	return data

/obj/machinery/requests_console/proc/req_status_entry(datum/station_request/R)
	if(!R)
		return null
	return list("id" = R.id, "status" = R.status, "handler" = R.handler, "time" = R.handled_time)

/obj/machinery/requests_console/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(open || !user?.client)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		// It opens onto the messages: read, as the old messages screen counted it
		if(screen == REQ_TGUI_SCREEN_MAIN)
			req_mark_read()
		ui = new(user, src, ui_key, "requests_console", "[department] Requests Console", 580, 560, master_ui, state)
		ui.open()

/// The department's consoles stop flashing, as the old messages screen did on showing
/obj/machinery/requests_console/proc/req_mark_read()
	for(var/obj/machinery/requests_console/Console in GLOB.allConsoles)
		if(Console.department == department)
			Console.newmessagepriority = REQ_NO_NEW_MESSAGE
			Console.update_icon()

/obj/machinery/requests_console/proc/req_departments(list/departments)
	var/list/out = list()
	for(var/name in departments)
		if(name != department)
			out += list(list("name" = name, "key" = ckey(name)))
	return out

/obj/machinery/requests_console/ui_data(mob/user)
	var/list/data = list()
	data["department"] = department
	data["screen"] = screen
	data["silent"] = silent
	data["emergency"] = emergency
	data["announcement_console"] = announcementConsole
	data["hacked"] = hackState
	data["new_priority"] = newmessagepriority
	var/list/entries = list()
	for(var/i in length(message_entries) to 1 step -1)
		var/list/entry = message_entries[i]
		var/list/shown = entry.Copy()
		shown["tracking"] = req_status_entry(GLOB.station_requests_by_id["[entry["request"]]"])
		entries += list(shown)
	data["messages"] = entries
	// What this department has asked for, newest first
	var/list/sent = list()
	for(var/i in length(GLOB.station_requests) to 1 step -1)
		var/datum/station_request/R = GLOB.station_requests[i]
		if(R.from_dept != department)
			continue
		sent += list(list("id" = R.id, "to" = R.to_dept, "body" = R.body, "time" = R.time, "kind" = R.kind, "tracking" = req_status_entry(R)))
		if(length(sent) >= 10)
			break
	data["sent"] = sent
	data["notice"] = req_notice
	data["assistance"] = req_departments(GLOB.req_console_assistance)
	data["supplies"] = req_departments(GLOB.req_console_supplies)
	data["information"] = req_departments(GLOB.req_console_information)
	data["to_department"] = to_department
	data["priority"] = priority
	data["message"] = message ? comm_plain_text(message) : ""
	data["verified"] = msgVerified ? comm_plain_text(msgVerified) : null
	data["stamped"] = msgStamped ? comm_plain_text(msgStamped) : null
	data["announce_auth"] = announceAuth || IsAdminGhost(user)
	return data

/obj/machinery/requests_console/ui_act(action, params)
	if(..())
		return
	req_notice = null
	switch(action)
		if("screen")
			var/to_screen = text2num(params["screen"])
			if(!(to_screen in list(REQ_TGUI_SCREEN_MAIN, 1, 2, 3, REQ_TGUI_SCREEN_VIEW_MSGS, REQ_TGUI_SCREEN_ANNOUNCE)))
				return
			if(to_screen == REQ_TGUI_SCREEN_ANNOUNCE && !announcementConsole)
				return
			if(to_screen == REQ_TGUI_SCREEN_MAIN)
				announceAuth = FALSE // as the old main menu did on showing
			if(to_screen == REQ_TGUI_SCREEN_VIEW_MSGS || to_screen == REQ_TGUI_SCREEN_MAIN)
				req_mark_read()
			Topic(null, list("setScreen" = "[to_screen]"))
		if("write")
			// The old Topic asked for the message in a popup; here it's written next, on the screen that waits for an ID or stamp
			var/key = ckey(params["department"])
			if(!GLOB.req_console_ckey_departments[key])
				return
			var/wanted_priority = text2num(params["priority"])
			if(wanted_priority == REQ_EXTREME_MESSAGE_PRIORITY && !hackState) // only rewired consoles offer it
				return
			to_department = GLOB.req_console_ckey_departments[key]
			priority = clamp(wanted_priority, REQ_NORMAL_MESSAGE_PRIORITY, REQ_EXTREME_MESSAGE_PRIORITY)
			message = ""
			msgVerified = ""
			msgStamped = ""
			screen = REQ_TGUI_SCREEN_AUTHENTICATE
		if("set_message")
			if(screen == REQ_TGUI_SCREEN_AUTHENTICATE)
				message = stripped_input_text(params["text"], MAX_MESSAGE_LEN) || ""
		if("send")
			if(screen == REQ_TGUI_SCREEN_AUTHENTICATE && message)
				req_send()
		if("quick")
			req_quick(params["name"], usr)
		if("crate")
			req_crate(text2path(params["id"]), params["reason"], usr)
		if("request_status")
			// The receiving department, at any of its consoles: on it, with who, or done
			var/datum/station_request/R = GLOB.station_requests_by_id["[params["id"]]"]
			var/new_status = params["status"]
			if(!R || ckey(R.to_dept) != ckey(department) || !(new_status in list("on it", "done")))
				return
			var/who = req_who(usr) || usr.name
			R.set_status(new_status, who)
			log_game("[key_name(usr)] marked the request from [R.from_dept] to [R.to_dept] \"[R.body]\" [new_status] at [src].")
		if("set_announcement")
			if(screen == REQ_TGUI_SCREEN_ANNOUNCE)
				message = reject_bad_text(stripped_input_text(params["text"], MAX_MESSAGE_LEN)) || ""
		if("announce")
			// The old Topic took it from anyone who sent the link: it's for whoever swiped a card that can
			if(screen == REQ_TGUI_SCREEN_ANNOUNCE && message && (announceAuth || IsAdminGhost(usr)))
				Topic(null, list("sendAnnouncement" = "1"))
		if("emergency")
			var/kind = text2num(params["kind"])
			if(kind in list(1, 2, 3))
				Topic(null, list("emergency" = "[kind]"))
		if("silent")
			Topic(null, list("setSilent" = silent ? "0" : "1"))
	add_fingerprint(usr)
	return TRUE

#undef REQ_TGUI_SCREEN_MAIN
#undef REQ_TGUI_SCREEN_SENT
#undef REQ_TGUI_SCREEN_ERR
#undef REQ_TGUI_SCREEN_VIEW_MSGS
#undef REQ_TGUI_SCREEN_AUTHENTICATE
#undef REQ_TGUI_SCREEN_ANNOUNCE
