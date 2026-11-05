// The teleporter control console's tgui window (tgui-next Teleporter.js): the beacons, tracking implants or gate stations it can
// lock onto are listed in the window, where the old one asked in a pop-up. Changing the regime and calibrating go through the old
// Topic(), so its checks and the calibration timer stay the same.

/obj/machinery/computer/teleporter/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "teleporter", name, 470, 460, master_ui, state)
		ui.open()

/// Name -> what the console can lock onto in its regime, as the old pop-up listed them
/obj/machinery/computer/teleporter/proc/teleport_choices()
	var/list/L = list()
	var/list/areaindex = list()
	if(!power_station)
		return L
	if(regime_set == "Teleporter")
		for(var/obj/item/beacon/R in GLOB.teleportbeacons)
			if(is_eligible(R))
				if(R.renamed)
					L[avoid_assoc_duplicate_keys("[R.name] ([get_area(R)])", areaindex)] = R
				else
					var/area/A = get_area(R)
					L[avoid_assoc_duplicate_keys(A.name, areaindex)] = R
		for(var/obj/item/implant/tracking/I in GLOB.tracked_implants)
			if(!I.imp_in || !isliving(I.loc) || !I.allow_teleport)
				continue
			var/mob/living/M = I.loc
			if(M.stat == DEAD && M.timeofdeath + I.lifespan_postmortem < world.time)
				continue
			if(is_eligible(I))
				L[avoid_assoc_duplicate_keys("[M.real_name] ([get_area(M)])", areaindex)] = I
	else
		for(var/obj/machinery/teleport/station/R in power_station.linked_stations)
			if(is_eligible(R) && R.teleporter_hub)
				var/area/A = get_area(R)
				L[avoid_assoc_duplicate_keys(A.name, areaindex)] = R
	return L

/obj/machinery/computer/teleporter/ui_data(mob/user)
	var/list/data = list()
	data["station"] = !!power_station
	data["hub"] = !!(power_station && power_station.teleporter_hub)
	data["regime"] = regime_set
	data["calibrating"] = !!calibrating
	data["calibrated"] = !!(power_station && power_station.teleporter_hub && (power_station.teleporter_hub.calibrated || power_station.teleporter_hub.accuracy >= 3))
	data["engaged"] = !!(power_station && power_station.engaged)
	var/area/target_area = target ? get_area(target) : null
	data["target"] = target_area ? "[target_area.name]" : null
	var/list/choices = list()
	var/list/L = data["hub"] ? teleport_choices() : list()
	for(var/name in L)
		var/atom/A = L[name]
		var/is_target = (A == target) || (regime_set == "Gate" && istype(A, /obj/machinery/teleport/station) && A:teleporter_hub == target)
		choices += list(list("name" = name, "implant" = istype(A, /obj/item/implant), "current" = is_target))
	data["choices"] = choices
	return data

/obj/machinery/computer/teleporter/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("regime")
			Topic(null, list("regimeset" = 1))
			return TRUE
		if("calibrate")
			Topic(null, list("calibrate" = 1))
			return TRUE
		if("target")
			if(!check_hub_connection())
				say("Error: Unable to detect hub.")
				return
			if(calibrating)
				say("Error: Calibration in progress. Stand by.")
				return
			var/list/L = teleport_choices()
			var/atom/movable/picked = L[params["name"]]
			if(!picked)
				return
			power_station.engaged = 0
			power_station.teleporter_hub.update_icon()
			power_station.teleporter_hub.calibrated = 0
			if(regime_set == "Teleporter")
				target = picked
				var/turf/T = get_turf(target)
				log_game("[key_name(usr)] has set the teleporter target to [target] at [AREACOORD(T)]")
				return TRUE
			// A gate: lock onto the other station's hub and wake that end up, as the old pop-up did
			var/obj/machinery/teleport/station/target_station = picked
			if(!target_station.teleporter_hub)
				return
			var/turf/station_turf = get_turf(target_station)
			log_game("[key_name(usr)] has set the teleporter target to [target_station] at [AREACOORD(station_turf)]")
			target = target_station.teleporter_hub
			target_station.linked_stations |= power_station
			target_station.stat &= ~NOPOWER
			target_station.teleporter_hub.stat &= ~NOPOWER
			target_station.teleporter_hub.update_icon()
			if(target_station.teleporter_console)
				target_station.teleporter_console.stat &= ~NOPOWER
				target_station.teleporter_console.update_icon()
			return TRUE
