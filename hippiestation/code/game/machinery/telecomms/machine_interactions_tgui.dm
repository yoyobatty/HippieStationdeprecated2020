// hippie -- a telecomms machine's multitool menu is a tgui window: power, the identification string and network typed in place, the
// relay's and the bus's own settings, the machines it's linked to with Unlink, the frequencies it filters with remove and add, and
// the multitool's buffer (store this machine, link to the one stored, flush). The buttons go through the machine's own Topic() but
// the ID, network and frequencies, which were popups there and are that Topic()'s branches here with typed text. A multitool in
// hand (or being a silicon) is still what opens it.

/obj/machinery/telecomms/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!tcomms_tool_ok(user))
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "telecomms_machine", "[name] Access", 460, 560, master_ui, state)
		ui.open()

/// A multitool in the active hand, or a silicon: what the old window and its Topic() asked for
/obj/machinery/telecomms/proc/tcomms_tool_ok(mob/user)
	return issilicon(user) || istype(user?.get_active_held_item(), /obj/item/multitool)

/// A typed frequency as the old window read one: "145.9" or "1459" both mean 145.9 GHz
/proc/tcomms_typed_frequency(text)
	var/newfreq = text2num("[text]")
	if(!newfreq)
		return null
	if(findtext(num2text(newfreq), "."))
		newfreq *= 10 // shift the decimal one place
	return round(newfreq)

/// The machine's own settings, for the window: list(list("key", "name", "value")), the relay's and the bus's
/obj/machinery/telecomms/proc/tcomms_options()
	return list()

/obj/machinery/telecomms/relay/tcomms_options()
	return list(list("key" = "broadcast", "name" = "Broadcasting", "on" = broadcasting), list("key" = "receive", "name" = "Receiving", "on" = receiving))

/obj/machinery/telecomms/ui_data(mob/user)
	var/list/data = list()
	data["notice"] = comm_plain_text(temp)
	data["toggled"] = toggled
	data["working"] = on && toggled
	data["id"] = id
	data["network"] = network
	data["prefab"] = length(autolinkers) > 0
	data["hidden"] = hide
	data["options"] = tcomms_options()
	var/obj/machinery/telecomms/bus/B = src
	data["bus"] = istype(B)
	data["change_frequency"] = istype(B) ? B.change_frequency : 0
	var/list/links_out = list()
	var/i = 0
	for(var/obj/machinery/telecomms/T in links)
		i++
		if(T.hide && !hide)
			continue
		links_out += list(list("index" = i, "name" = T.name, "id" = T.id))
	data["links"] = links_out
	var/list/freqs = list()
	for(var/x in freq_listening)
		freqs += list(list("value" = x, "name" = format_frequency(x)))
	data["frequencies"] = freqs
	var/obj/item/multitool/P = get_multitool(user)
	data["has_multitool"] = !!P
	var/obj/machinery/telecomms/T = P?.buffer
	data["buffer"] = istype(T) ? "[T.name] ([T.id])" : null
	data["buffer_is_this"] = T == src
	return data

/obj/machinery/telecomms/ui_act(action, params)
	if(..())
		return
	var/mob/user = usr
	if(!tcomms_tool_ok(user))
		return
	temp = "" // each message once, as the old window showed it
	switch(action)
		if("toggle")
			Topic(null, list("input" = "toggle"))
		if("id") // the Topic() branch, with the typed ID
			var/newid = reject_bad_text(stripped_input_text(params["value"]))
			if(newid && canAccess(user))
				id = newid
				temp = "<font color = #666633>-% New ID assigned: \"[id]\" %-</font>"
		if("network") // likewise: a new network breaks every link
			var/newnet = stripped_input_text(params["value"])
			if(newnet && newnet != network && canAccess(user))
				if(length(newnet) > 15)
					temp = "<font color = #666633>-% Too many characters in new network tag %-</font>"
				else
					for(var/obj/machinery/telecomms/T in links)
						T.links.Remove(src)
					network = newnet
					links = list()
					temp = "<font color = #666633>-% New network tag assigned: \"[network]\" %-</font>"
		if("add_freq") // likewise
			var/newfreq = tcomms_typed_frequency(params["value"])
			if(newfreq && canAccess(user))
				if(newfreq == FREQ_SYNDICATE)
					temp = "<font color = #FF0000>-% Error: Interference preventing filtering frequency: \"[newfreq] GHz\" %-</font>"
				else if(!(newfreq in freq_listening) && newfreq < 10000)
					freq_listening.Add(newfreq)
					temp = "<font color = #666633>-% New frequency filter assigned: \"[newfreq] GHz\" %-</font>"
		if("delete_freq")
			var/x = text2num("[params["value"]]")
			if(x in freq_listening)
				Topic(null, list("delete" = "[x]"))
		if("unlink")
			Topic(null, list("unlink" = "[text2num("[params["index"]]")]"))
		if("link")
			Topic(null, list("link" = "1"))
		if("buffer")
			Topic(null, list("buffer" = "1"))
		if("flush")
			Topic(null, list("flush" = "1"))
		if("option") // the relay's switches
			if(params["key"] in list("broadcast", "receive"))
				Topic(null, list(params["key"] = "1"))
		if("change_freq") // the bus's, with the typed frequency (blank to turn it off)
			var/obj/machinery/telecomms/bus/B = src
			if(istype(B) && canAccess(user))
				var/newfreq = tcomms_typed_frequency(params["value"])
				if(newfreq)
					if(newfreq < 10000)
						B.change_frequency = newfreq
						temp = "<font color = #666633>-% New frequency to change to assigned: \"[newfreq] GHz\" %-</font>"
				else
					B.change_frequency = 0
					temp = "<font color = #666633>-% Frequency changing deactivated %-</font>"
	return TRUE
