// The launchpad console's and briefcase remote's windows (tgui-next Launchpad.js) take the target's X and Y and the pad's name
// typed in the window, where the old ones asked in pop-ups. The old manual X/Y set the offset to null when the pop-up was cancelled.

/// A typed X, Y or name for a pad: "set_x", "set_y" or "rename_to"
/proc/launchpad_typed(obj/machinery/launchpad/pad, action, value)
	if(QDELETED(pad))
		return
	switch(action)
		if("set_x", "set_y")
			var/offset = text2num(value)
			if(isnull(offset) || pad.teleporting)
				return
			offset = clamp(round(offset), -pad.range, pad.range)
			if(action == "set_x")
				pad.x_offset = offset
			else
				pad.y_offset = offset
			pad.update_indicator()
		if("rename_to")
			var/new_name = trim(html_encode(value), 15)
			if(new_name)
				pad.display_name = new_name

/// What the grid needs: the signed offsets and how far the pad reaches
/proc/launchpad_grid_data(obj/machinery/launchpad/pad, list/data)
	data["x"] = pad.x_offset
	data["y"] = pad.y_offset
	data["range"] = pad.range
	data["teleporting"] = pad.teleporting

/obj/machinery/computer/launchpad/ui_data(mob/user)
	. = ..()
	if(.["pad_active"])
		launchpad_grid_data(current_pad, .)

/obj/machinery/computer/launchpad/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	if(!(action in list("set_x", "set_y", "rename_to")))
		return ..()
	if(!ui || ui.status != UI_INTERACTIVE)
		return
	add_fingerprint(usr)
	if(screen == "control" && current_pad && !(current_pad.stat & NOPOWER))
		launchpad_typed(current_pad, action, params["value"])
	return TRUE

/obj/item/launchpad_remote/ui_data(mob/user)
	. = ..()
	if(pad && !pad.closed)
		launchpad_grid_data(pad, .)

/obj/item/launchpad_remote/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	if(!(action in list("set_x", "set_y", "rename_to")))
		return ..()
	if(!ui || ui.status != UI_INTERACTIVE)
		return
	if(pad && !pad.closed)
		launchpad_typed(pad, action, params["value"])
	return TRUE
