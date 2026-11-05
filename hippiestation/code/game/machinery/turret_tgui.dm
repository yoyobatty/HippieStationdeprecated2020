// Turrets in tgui windows (tgui-next Turrets.js): a portable turret's own settings, and the wall turret control panel with the
// turrets it runs. The old panel told anyone not standing on its own tile they were too far away; now it's the usual reach.
// Changes go through the old Topic(), so locks, logging and the turrets' update stay the same.

/obj/machinery/porta_turret/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "porta_turret", name, 380, 400, master_ui, state)
		ui.open()

/// A turret hides invisible in its cover, which is what's used: reach and sight are judged from the cover
/obj/machinery/porta_turret/ui_status(mob/user, datum/ui_state/state)
	if(cover && !QDELETED(cover))
		return cover.ui_status(user, state)
	return ..()

/obj/machinery/porta_turret/ui_data(mob/user)
	var/list/data = list()
	data["on"] = on
	data["anchored"] = anchored
	data["locked"] = locked
	data["silicon"] = issilicon(user)
	data["manual"] = manual_control
	var/mob/living/silicon/S = user
	data["canHack"] = issilicon(user) && S.hack_software && !manual_control
	data["settings"] = list(
		list("key" = "authweapon", "name" = "Check weapon authorization", "on" = auth_weapons),
		list("key" = "checkrecords", "name" = "Check security records", "on" = check_records),
		list("key" = "shootcrooks", "name" = "Neutralize identified criminals", "on" = criminals),
		list("key" = "shootall", "name" = "Neutralize everyone but Security and Command", "on" = stun_all),
		list("key" = "checkxenos", "name" = "Neutralize unidentified life signs", "on" = check_anomalies),
		list("key" = "checkloyal", "name" = "Neutralize anyone without a mindshield", "on" = shoot_unloyal),
	)
	return data

/obj/machinery/porta_turret/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("power")
			if(locked)
				return
			Topic(null, list("power" = 1))
		if("setting")
			if(locked || !(params["key"] in list("authweapon", "checkrecords", "shootcrooks", "shootall", "checkxenos", "checkloyal")))
				return
			Topic(null, list("operation" = params["key"]))
		if("manual")
			Topic(null, list("operation" = "manual"))
	return TRUE

/obj/machinery/turretid/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "turret_control", "Turret Control ([get_area_name(src, TRUE)])", 380, 420, master_ui, state)
		ui.open()

/obj/machinery/turretid/ui_data(mob/user)
	var/list/data = list()
	var/silicon = issilicon(user) || IsAdminGhost(user)
	data["locked"] = locked && !silicon
	data["silicon"] = silicon
	data["enabled"] = enabled
	data["lethal"] = lethal
	var/list/listed = list()
	for(var/obj/machinery/porta_turret/T in turrets)
		var/status = "Standing by"
		if(T.stat & BROKEN)
			status = "Destroyed"
		else if(!T.powered())
			status = "No power"
		else if(T.raised)
			status = "Deployed"
		listed += list(list("name" = T.name, "status" = status, "bad" = !!(T.stat & BROKEN) || !T.powered()))
	data["turrets"] = listed
	return data

/obj/machinery/turretid/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("power")
			Topic(null, list("toggleOn" = 1))
		if("lethal")
			Topic(null, list("toggleLethal" = 1))
	return TRUE
