// hippie -- the particle accelerator's control console is a tgui window. The buttons go through the console's own Topic(),
// so the wires (a cut interface wire times it out, a cut power or strength wire stops those) and the admin logs are the old
// window's. Bots run the accelerator with part_scan(), strength_change() and toggle_power() and never open it.

// As particle_accelerator.dm has them (it undefines them after particle_control.dm)
#define PA_CONSTRUCTION_PANEL_OPEN 2
#define PA_CONSTRUCTION_COMPLETE   3

/obj/machinery/particle_accelerator/control_box/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(construction_state == PA_CONSTRUCTION_PANEL_OPEN)
		wires.interact(user)
		return
	if(construction_state != PA_CONSTRUCTION_COMPLETE || (stat & (BROKEN|NOPOWER)))
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "particle_accelerator", name, 360, 160, master_ui, state)
		ui.open()

/obj/machinery/particle_accelerator/control_box/ui_data(mob/user)
	var/list/data = list()
	data["assembled"] = assembled
	data["active"] = active
	data["strength"] = strength
	data["max_strength"] = strength_upper_limit
	return data

/obj/machinery/particle_accelerator/control_box/ui_act(action, params)
	if(..())
		return
	// Only what the window offers: the old Topic would switch on an accelerator with no parts found
	if(construction_state != PA_CONSTRUCTION_COMPLETE || (stat & (BROKEN|NOPOWER)))
		return
	switch(action)
		if("scan")
			Topic(null, list("scan" = "1"))
		if("power")
			if(assembled)
				Topic(null, list("togglep" = "1"))
		if("strength_up")
			if(assembled)
				Topic(null, list("strengthup" = "1"))
		if("strength_down")
			if(assembled)
				Topic(null, list("strengthdown" = "1"))
	return TRUE

#undef PA_CONSTRUCTION_PANEL_OPEN
#undef PA_CONSTRUCTION_COMPLETE
