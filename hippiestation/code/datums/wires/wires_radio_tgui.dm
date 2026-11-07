// The radio and the wiring panel redone (tgui-next Radio.js, Wires.js): the radio as a handset with a backlit display,
// tuning buttons, switches and channel keys; the wires as a maintenance panel with each wire drawn as a cable. Same data
// and actions as before; only the windows' sizes change here, for the new layouts.

/obj/item/radio/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.inventory_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/height = 214
		if(subspace_transmission)
			height += 30 + 38 * CEILING(max(channels.len, 1) / 3, 1)
		ui = new(user, src, ui_key, "radio", name, 400, height, master_ui, state)
		ui.open()

/datum/wires/ui_interact(mob/user, ui_key = "wires", datum/tgui/ui = null, force_open = FALSE, \
							datum/tgui/master_ui = null, datum/ui_state/state = GLOB.physical_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/list/status = get_status()
		ui = new(user, src, ui_key, "wires", "[holder.name] Wires", 460, 92 + wires.len * 33 + length(status) * 20, master_ui, state)
		ui.open()
