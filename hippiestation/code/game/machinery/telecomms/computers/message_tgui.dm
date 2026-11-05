// hippie -- the message monitor console is a tgui window: the server, its power and the login on top, with the decryption key typed
// in place, then the PDA message logs, the requests console logs, a message sent as anybody (the old "admin message") and the key's
// change, each a tab, with the emagged and brute-forcing screen as it was. The buttons go through the console's own Topic(), but the
// key, the new key and the custom message's fields, which were popups there and are that Topic()'s branches here with typed text.

// The screens, as message.dm numbers them (its defines are undefined at the end of it)
#define MSGMON_MAIN 0
#define MSGMON_LOGS 1
#define MSGMON_HACKED 2
#define MSGMON_CUSTOM 3
#define MSGMON_REQUESTS 4
#define MSGMON_LOG_SHOWN 300

/obj/machinery/computer/message_monitor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "message_monitor", name, 700, 640, master_ui, state)
		ui.open()

/obj/machinery/computer/message_monitor/proc/msgmon_server_down()
	return !linkedServer || (linkedServer.stat & (NOPOWER|BROKEN))

/obj/machinery/computer/message_monitor/ui_data(mob/user)
	var/list/data = list()
	// What the old window worked out each time it was drawn
	if(hacking || (obj_flags & EMAGGED))
		screen = MSGMON_HACKED
	else if(!auth || msgmon_server_down())
		if(msgmon_server_down())
			message = noserver
		screen = MSGMON_MAIN
	data["screen"] = screen
	data["notice"] = comm_plain_text(message)
	data["server"] = linkedServer ? linkedServer.name : null
	data["server_down"] = msgmon_server_down()
	data["server_on"] = linkedServer ? !!linkedServer.on : FALSE
	data["auth"] = auth
	data["hacked"] = hacking || (obj_flags & EMAGGED)
	data["silicon"] = issilicon(user)
	var/mob/living/silicon/S = user
	data["can_hack"] = istype(S) && S.hack_software && !hacking
	if(!auth || msgmon_server_down())
		return data
	switch(screen)
		if(MSGMON_LOGS)
			var/list/logs = list()
			var/total = length(linkedServer.pda_msgs)
			for(var/i in total to max(1, total - MSGMON_LOG_SHOWN + 1) step -1) //newest first
				var/datum/data_pda_msg/M = linkedServer.pda_msgs[i]
				logs += list(list("ref" = REF(M), "sender" = M.sender, "recipient" = M.recipient, "message" = comm_plain_text(M.message), "photo" = !!M.picture))
			data["logs"] = logs
			data["total"] = total
		if(MSGMON_REQUESTS)
			var/list/logs = list()
			var/total = length(linkedServer.rc_msgs)
			for(var/i in total to max(1, total - MSGMON_LOG_SHOWN + 1) step -1)
				var/datum/data_rc_msg/R = linkedServer.rc_msgs[i]
				logs += list(list("ref" = REF(R), "from" = R.send_dpt, "to" = R.rec_dpt, "message" = comm_plain_text(R.message), "stamp" = comm_plain_text(R.stamp), "id_auth" = comm_plain_text(R.id_auth), "priority" = comm_plain_text(R.priority)))
			data["requests"] = logs
			data["total"] = total
		if(MSGMON_CUSTOM)
			data["custom"] = list(
				"sender" = html_decode(customsender),
				"job" = html_decode(customjob),
				"recipient" = customrecepient ? "[customrecepient.owner] ([customrecepient.ownjob])" : null,
				"message" = html_decode(custommessage),
			)
			var/list/pdas = list()
			for(var/obj/item/pda/P in sortNames(get_viewable_pdas()))
				pdas += list(list("ref" = REF(P), "name" = "[P.owner] ([P.ownjob])"))
			data["pdas"] = pdas
	return data

/obj/machinery/computer/message_monitor/ui_act(action, params)
	if(..())
		return
	var/mob/user = usr
	message = defaultmsg // each message once, as the old window showed it
	switch(action)
		if("login") // the Topic() branch, with the typed key
			if(msgmon_server_down())
				message = noserver
			else if(!auth)
				var/dkey = trim("[params["key"]]")
				if(dkey)
					if(linkedServer.decryptkey == dkey)
						auth = TRUE
					else
						message = incorrectkey
		if("logout")
			if(auth)
				Topic(null, list("auth" = "1"))
		if("power")
			Topic(null, list("active" = "1"))
		if("link")
			Topic(null, list("find" = "1"))
		if("tab")
			var/static/list/tabs = list("main" = "back", "logs" = "view_logs", "requests" = "view_requests", "custom" = "msg")
			if(tabs[params["tab"]])
				Topic(null, list(tabs[params["tab"]] = "1"))
		if("delete_log")
			Topic(null, list("delete_logs" = params["ref"]))
		if("delete_request")
			Topic(null, list("delete_requests" = params["ref"]))
		if("clear_logs")
			Topic(null, list("clear_logs" = "1"))
		if("clear_requests")
			Topic(null, list("clear_requests" = "1"))
		if("hack")
			Topic(null, list("hack" = "1"))
		if("set_key") // the Topic() branch, with the typed keys
			if(msgmon_server_down())
				message = noserver
			else if(auth)
				var/dkey = stripped_input_text(params["old"])
				if(dkey)
					if(linkedServer.decryptkey == dkey)
						var/newkey = trim("[params["new"]]")
						if(length(newkey) <= 3)
							message = "<span class='notice'>NOTICE: Decryption key too short!</span>"
						else if(length(newkey) > 16)
							message = "<span class='notice'>NOTICE: Decryption key too long!</span>"
						else
							linkedServer.decryptkey = newkey
							message = "<span class='notice'>NOTICE: Decryption key set.</span>"
					else
						message = incorrectkey
		if("custom") // the custom message's fields: the Topic() branches, with the typed text
			if(!auth || msgmon_server_down() || screen != MSGMON_CUSTOM)
				return
			switch(params["field"])
				if("sender")
					customsender = stripped_input_text(params["value"]) || customsender
				if("job")
					customjob = stripped_input_text(params["value"]) || customjob
				if("message")
					custommessage = stripped_input_text(params["value"]) || custommessage
				if("recipient")
					var/obj/item/pda/P = locate(params["value"]) in get_viewable_pdas()
					customrecepient = P
		if("custom_send")
			if(auth && screen == MSGMON_CUSTOM)
				Topic(null, list("select" = "Send"))
				if(message == defaultmsg)
					message = "<span class='notice'>NOTICE: Message sent.</span>"
		if("custom_reset")
			if(auth && screen == MSGMON_CUSTOM)
				Topic(null, list("select" = "Reset"))
	if(user)
		SStgui.update_uis(src)
	return TRUE

#undef MSGMON_MAIN
#undef MSGMON_LOGS
#undef MSGMON_HACKED
#undef MSGMON_CUSTOM
#undef MSGMON_REQUESTS
#undef MSGMON_LOG_SHOWN
