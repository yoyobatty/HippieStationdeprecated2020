// hippie -- the communications console's window in tgui (tgui-next interfaces/CommsConsole.js): the shuttle, the alert level and
// emergency access, the messages from CentCom, the status displays, and the captain's announcements and messages, written in the
// window instead of input() popups. What doesn't need a text box goes through the console's own Topic(), so the rules stay the old
// window's (who's logged in at what level, swiping a Captain's ID to change the alert, buying a shuttle); the messages keep its
// checks, cooldowns and logs. The AI gets the same window with its own functions, as it had its own menu. Bots don't use the
// window (bots_ai goals/call_shuttle.dm, civilians.dm, repair_damage.dm call the procs).

/obj/machinery/computer/communications/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	add_fingerprint(user)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "comms_console", "Communications Console", 640, 640, master_ui, state)
		ui.open()

/obj/machinery/computer/communications/ui_static_data(mob/user)
	. = list()
	.["reason_min"] = CALL_SHUTTLE_REASON_LENGTH // only above green (requestEvac())
	.["reason_max"] = MAX_CALL_SHUTTLE_REASON_LENGTH
	.["levels"] = list("green" = SEC_LEVEL_GREEN, "blue" = SEC_LEVEL_BLUE)
	.["cross_servers"] = length(CONFIG_GET(keyed_list/cross_server))
	.["can_buy_shuttles"] = !!SSmapping.config.allow_custom_shuttles
	var/list/shuttles = list()
	for(var/shuttle_id in SSmapping.shuttle_templates)
		var/datum/map_template/shuttle/S = SSmapping.shuttle_templates[shuttle_id]
		if(S.can_be_bought && S.credit_cost < INFINITY)
			shuttles += list(list("ref" = REF(S), "name" = S.name, "cost" = S.credit_cost, "desc" = S.description, "prereqs" = S.prerequisites))
	.["shuttles"] = shuttles

/obj/machinery/computer/communications/ui_data(mob/user)
	. = list()
	var/silicon = issilicon(user)
	.["silicon"] = silicon
	.["far"] = !is_station_level(z) && !is_reserved_level(z)
	.["authenticated"] = authenticated
	.["auth_id"] = auth_id
	.["emagged"] = !!(obj_flags & EMAGGED)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	var/list/shuttle = list("mode" = "idle", "eta" = null)
	if(E)
		switch(E.mode)
			if(SHUTTLE_CALL)
				shuttle["mode"] = "called"
			if(SHUTTLE_RECALL)
				shuttle["mode"] = "recalled"
			if(SHUTTLE_DOCKED)
				shuttle["mode"] = "docked"
			if(SHUTTLE_IGNITING)
				shuttle["mode"] = "igniting"
			if(SHUTTLE_ESCAPE)
				shuttle["mode"] = "escaping"
			if(SHUTTLE_STRANDED)
				shuttle["mode"] = "stranded"
			if(SHUTTLE_DISABLED)
				shuttle["mode"] = "disabled"
		if(E.mode in list(SHUTTLE_CALL, SHUTTLE_RECALL, SHUTTLE_DOCKED, SHUTTLE_IGNITING, SHUTTLE_ESCAPE))
			shuttle["eta"] = E.timeLeft()
		// Called only when it's idle: Hippie's requestEvac() refuses one on its way back from a recall, which the old menu offered
		// anyway. An AI can't recall, as before.
		shuttle["can_call"] = E.mode == SHUTTLE_IDLE
		shuttle["can_recall"] = !silicon && E.mode == SHUTTLE_CALL
	shuttle["trace"] = SSshuttle.emergencyCallAmount ? (isarea(SSshuttle.emergencyLastCallLoc) ? format_text(SSshuttle.emergencyLastCallLoc.name) : "untraceable") : null
	.["shuttle"] = shuttle
	.["alert_level"] = get_security_level()
	.["alert_num"] = GLOB.security_level
	.["delta"] = GLOB.security_level == SEC_LEVEL_DELTA
	.["emergency_access"] = !!GLOB.emergency_access
	.["stat_msg1"] = stat_msg1
	.["stat_msg2"] = stat_msg2
	.["can_announce"] = SScommunications.can_announce(user, silicon)
	var/obj/item/circuitboard/computer/communications/CM = circuit
	.["cc_cooldown"] = max(0, round((CM.lastTimeUsed + 600 - world.time) / 10))
	var/datum/bank_account/D = SSeconomy.get_dep_account(ACCOUNT_CAR)
	.["budget"] = D ? D.account_balance : 0
	.["shuttle_purchased"] = !!SSshuttle.shuttle_purchased
	var/list/msgs = list()
	for(var/datum/comm_message/M as anything in messages)
		msgs += list(list(
			"title" = M.title,
			"content" = comm_plain_text(M.content),
			"answers" = M.possible_answers,
			"answered" = M.answered ? M.possible_answers[M.answered] : null,
		))
	.["messages"] = msgs

/obj/machinery/computer/communications/ui_act(action, list/params)
	if(..())
		return
	if(!is_station_level(z) && !is_reserved_level(z)) //Can only use in transit and on SS13, as Topic() has it
		to_chat(usr, "<span class='boldannounce'>Unable to establish a connection</span>: \black You're too far away from the station!")
		return
	var/silicon = issilicon(usr)
	switch(action)
		if("login")
			Topic(null, list("operation" = "login"))
		if("logout")
			Topic(null, list("operation" = "logout"))
		if("call_shuttle")
			if(silicon)
				Topic(null, list("operation" = "ai-callshuttle2", "call" = params["reason"]))
			else
				Topic(null, list("operation" = "callshuttle2", "call" = params["reason"]))
		if("recall_shuttle")
			if(!silicon)
				Topic(null, list("operation" = "cancelshuttle2"))
		if("alert")
			var/level = text2num(params["level"])
			if(silicon)
				Topic(null, list("operation" = "ai-securitylevel", "newalertlevel" = "[level]"))
			else if(authenticated == 2)
				// The old menu's steps: pick the level, then swipe a Captain's ID (the one in hand) to confirm it
				Topic(null, list("operation" = "securitylevel", "newalertlevel" = "[level]"))
				Topic(null, list("operation" = "swipeidseclevel"))
		if("emergency_access")
			if(!silicon && authenticated != 2) // the old menu only offered it to the Captain's login, but never checked
				return
			if(silicon)
				Topic(null, list("operation" = GLOB.emergency_access ? "ai-disableemergency" : "ai-enableemergency"))
			else
				Topic(null, list("operation" = GLOB.emergency_access ? "disableemergency" : "enableemergency"))
		if("status")
			var/display = params["display"]
			if(display == "message")
				stat_msg1 = reject_bad_text(params["line1"], 40)
				stat_msg2 = reject_bad_text(params["line2"], 40)
			if(display in list("blank", "shuttle", "message"))
				Topic(null, list("operation" = "setstat", "statdisp" = display))
			else if(display == "alert" && (params["picture"] in list("default", "redalert", "lockdown", "biohazard")))
				Topic(null, list("operation" = "setstat", "statdisp" = "alert", "alert" = params["picture"]))
		if("answer")
			var/datum/comm_message/M = comm_message_at(params["index"])
			var/answer = text2num(params["answer"])
			if(!M || M.answered || !answer || answer > length(M.possible_answers))
				return
			M.answered = answer
			log_game("[key_name(usr)] answered [M.title] comm message. Answer : [M.answered]")
			M.answer_callback?.InvokeAsync()
		if("delete")
			var/datum/comm_message/M = comm_message_at(params["index"])
			if(!M || (!silicon && !authenticated))
				return
			if(currmsg == M)
				currmsg = null
			if(aicurrmsg == M)
				aicurrmsg = null
			messages -= M
		if("announce")
			if(!silicon && authenticated != 2)
				return
			comm_announce(usr, params["text"], silicon)
		if("message_centcom")
			if(silicon || !authenticated)
				return
			if(obj_flags & EMAGGED)
				comm_send(usr, "syndicate", params["text"])
			else
				comm_send(usr, "centcom", params["text"])
		if("message_allies")
			if(silicon || authenticated != 2 || !length(CONFIG_GET(keyed_list/cross_server)))
				return
			comm_send(usr, "allies", params["text"])
		if("nuke_request")
			if(silicon || authenticated != 2)
				return
			comm_send(usr, "nuke", params["text"])
		if("restore_backup")
			if(!silicon && (obj_flags & EMAGGED))
				Topic(null, list("operation" = "RestoreBackup"))
		if("buy_shuttle")
			if(!silicon && authenticated == 2)
				Topic(null, list("operation" = "buyshuttle", "chosen_shuttle" = params["ref"]))
	return TRUE

/// A message's HTML (CentCom's reports have line breaks and bold in them) as plain text with its line breaks, for the window.
/proc/comm_plain_text(html)
	var/static/regex/line_break = regex("<br\\s*/?>|</p>|</li>", "gi")
	var/static/regex/tag = regex("<\[^>]*>", "g")
	return html_decode(tag.Replace(line_break.Replace("[html]", "\n"), ""))

/obj/machinery/computer/communications/proc/comm_message_at(index)
	index = text2num(index)
	if(!index || index < 1 || index > length(messages))
		return null
	return messages[index]

/// make_announcement() with the text from the window, not an input() popup.
/obj/machinery/computer/communications/proc/comm_announce(mob/living/user, text, silicon)
	if(!SScommunications.can_announce(user, silicon))
		to_chat(user, "<span class='alert'>Intercomms recharging. Please stand by.</span>")
		return
	var/input = trim(stripped_input_text(text))
	if(!input || !user.canUseTopic(src, !silicon))
		return
	playsound(src, 'sound/machines/terminal_prompt.ogg', 50, FALSE)
	SScommunications.make_announcement(user, silicon, input)
	deadchat_broadcast(" made a priority announcement from <span class='name'>[get_area_name(user, TRUE)]</span>.", "<span class='name'>[user.real_name]</span>", user)

/// The text of a box in the window, cleaned as stripped_input() cleans it.
/proc/stripped_input_text(text, max_length = MAX_MESSAGE_LEN, multiline = FALSE)
	if(!istext(text))
		return null
	if(multiline)
		return trim(html_encode(text), max_length)
	return trim(html_encode(replacetext(text, "\n", " ")), max_length)

/// The Topic() branches that sent a message off the station, each with its cooldown, checks and logs, but with the text from the window.
/obj/machinery/computer/communications/proc/comm_send(mob/living/user, where, text)
	var/obj/item/circuitboard/computer/communications/CM = circuit
	if(!checkCCcooldown())
		to_chat(user, "<span class='warning'>Arrays recycling. Please stand by.</span>")
		playsound(src, 'sound/machines/terminal_prompt_deny.ogg', 50, FALSE)
		return
	var/input = stripped_input_text(text, MAX_MESSAGE_LEN, where == "allies")
	if(!input || !(user in view(1, src)))
		return
	switch(where)
		if("centcom")
			playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, FALSE)
			CentCom_announce(input, user)
			to_chat(user, "<span class='notice'>Message transmitted to Central Command.</span>")
			user.log_talk(input, LOG_SAY, tag="CentCom announcement")
			deadchat_broadcast(" has messaged CentCom, \"[input]\" at <span class='name'>[get_area_name(user, TRUE)]</span>.", "<span class='name'>[user.real_name]</span>", user)
		if("syndicate")
			playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, FALSE)
			Syndicate_announce(input, user)
			to_chat(user, "<span class='danger'>SYSERR @l(19833)of(transmit.dm): !@$ MESSAGE TRANSMITTED TO SYNDICATE COMMAND.</span>")
			user.log_talk(input, LOG_SAY, tag="Syndicate announcement")
			deadchat_broadcast(" has messaged the Syndicate, \"[input]\" at <span class='name'>[get_area_name(user, TRUE)]</span>.", "<span class='name'>[user.real_name]</span>", user)
		if("allies")
			playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, FALSE)
			send2otherserver("[station_name()]", input, "Comms_Console")
			minor_announce(input, title = "Outgoing message to allied station")
			user.log_talk(input, LOG_SAY, tag="message to the other server")
			message_admins("[ADMIN_LOOKUPFLW(user)] has sent a message to the other server.")
			deadchat_broadcast(" has sent an outgoing message to the other station(s).</span>", "<span class='bold'>[user.real_name]", user)
		if("nuke")
			Nuke_request(input, user)
			to_chat(user, "<span class='notice'>Request sent.</span>")
			user.log_message("has requested the nuclear codes from CentCom with reason \"[input]\"", LOG_SAY)
			priority_announce("The codes for the on-station nuclear self-destruct have been requested by [user]. Confirmation or denial of this request will be sent shortly.", "Nuclear Self Destruct Codes Requested", 'hippiestation/sound/pyko/commandreport.ogg') // pykoai, as in Topic()
	CM.lastTimeUsed = world.time
