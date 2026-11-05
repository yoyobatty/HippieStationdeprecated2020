// The labor camp teleporter console's window (tgui-next LaborCamp.js) takes the prisoner's point goal typed in the window,
// where the old one asked in a pop-up. Same rules: 0 means the default goal, 1000 at most.

/obj/machinery/computer/gulag_teleporter_computer/ui_data(mob/user)
	. = ..()
	.["default_goal"] = default_goal

/obj/machinery/computer/gulag_teleporter_computer/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	if(action != "set_goal" || isnull(params["value"]))
		return ..()
	if(!ui || ui.status != UI_INTERACTIVE)
		return
	add_fingerprint(usr)
	if(!allowed(usr))
		to_chat(usr, "<span class='warning'>Access denied.</span>")
		return
	var/new_goal = text2num(params["value"])
	if(!id || isnull(new_goal))
		return
	if(!new_goal)
		new_goal = default_goal
	id.goal = clamp(round(new_goal), 0, 1000)
	return TRUE
