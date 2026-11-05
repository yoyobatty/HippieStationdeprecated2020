// Laptop and tablet programs on the tgui-next look (tgui-next Ntos*.js): what they type goes in the window, where the old
// pages asked in pop-ups. Each override only takes the actions that carry a typed value and leaves the rest to the program.

/// The window's own check, for overrides that answer an action without calling the program's ui_act
/datum/computer_file/program/proc/ntos_window_ok(datum/tgui/ui)
	return ui && ui.status == UI_INTERACTIVE && computer

// NTNet Relay Chat: messages and the nickname typed in the window

/datum/computer_file/program/chatclient/ui_data(mob/user)
	. = ..()
	if(islist(.))
		.["username"] = username

/datum/computer_file/program/chatclient/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	if(isnull(params["text"]) || !(action in list("PRG_speak", "PRG_changename")))
		return ..()
	if(!ntos_window_ok(ui))
		return 1
	var/mob/living/user = usr
	switch(action)
		if("PRG_speak")
			var/message = reject_bad_text(params["text"])
			if(!message || !channel)
				return 1
			channel.add_message(message, username)
			user.log_talk(message, LOG_CHAT, tag="as [username] to channel [channel.title]")
		if("PRG_changename")
			var/newname = sanitize(params["text"])
			if(!newname)
				return 1
			if(channel)
				channel.add_status_message("[username] is now known as [newname].")
			username = newname
	return 1

// ID Card Modification: every department's accesses listed at once, the jobs always there, the name and a custom
// assignment typed in the window, and grant or revoke a whole department. A head of staff only touches their own departments'
// accesses (the old program listed only those but took any access the page sent).

/datum/computer_file/program/card_mod/ui_data(mob/user)
	show_assignments = TRUE
	reg_ids = list(1, 2, 3, 4, 5, 6, 7)
	return ..()

/// Whether this access can be changed from here: anything for an ID changer, their departments' for a head
/datum/computer_file/program/card_mod/proc/ntos_access_ok(access)
	if(is_centcom)
		return (access in get_all_centcom_access())
	if(!(access in get_all_accesses()))
		return FALSE
	if(!minor && !target_dept)
		return TRUE
	for(var/region in region_access)
		if(access in get_region_accesses(region))
			return TRUE
	return FALSE

/datum/computer_file/program/card_mod/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	var/typed = (action == "PRG_edit" && !isnull(params["value"])) || (action == "PRG_assign" && params["assign_target"] == "Custom" && !isnull(params["value"]))
	if(!typed && action != "PRG_region" && action != "PRG_access")
		return ..()
	if(!ntos_window_ok(ui))
		return 1
	var/obj/item/computer_hardware/card_slot/card_slot = computer.all_components[MC_CARD]
	var/obj/item/card/id/id_card = card_slot ? card_slot.stored_card : null
	if(!id_card || !authorized())
		return 1
	switch(action)
		if("PRG_access")
			if(!ntos_access_ok(text2num(params["access_target"])))
				return 1
			return ..()
		if("PRG_region")
			var/region = text2num(params["region"])
			if((minor || target_dept) && !(region in region_access))
				return 1
			var/list/accesses = get_region_accesses(region)
			if(text2num(params["allowed"]))
				id_card.access |= accesses
			else
				id_card.access -= accesses
		if("PRG_edit")
			if(minor)
				return 1
			var/temp_name = reject_bad_name(params["value"])
			if(temp_name)
				id_card.registered_name = temp_name
			else
				computer.visible_message("<span class='notice'>[computer] buzzes rudely.</span>")
		if("PRG_assign")
			if(minor)
				return 1
			var/temp_t = reject_bad_text(params["value"], 45)
			if(temp_t)
				id_card.assignment = temp_t
	id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")
	return 1
