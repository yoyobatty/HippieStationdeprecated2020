// hippie -- the robotics control console is a tgui window: the cyborgs on this level that the user may control, in groups by the AI
// they're slaved to, each with its status, cell and module, and Lockdown or Release and Destroy (each asked twice in the page, in
// place of the old popup), Hack for a silicon with the software and Convert for a servant AI; then the drones, with Destroy. Lockdown
// and Destroy are the old Topic()'s branches without the popup (the page asks first); the rest go through Topic().

/obj/machinery/computer/robotics/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "robotics_console", "Robotics Control Console", 480, 600, master_ui, state)
		ui.open()

/obj/machinery/computer/robotics/ui_data(mob/user)
	var/list/data = list()
	data["access"] = allowed(user)
	var/mob/living/silicon/S = user
	var/list/groups = list()
	for(var/mob/living/silicon/robot/R in GLOB.silicon_mobs)
		var/turf/where = get_turf(R)
		if(!can_control(user, R) || !where || where.z != z)
			continue
		var/group = R.connected_ai ? "Slaved to [R.connected_ai]" : "Independent"
		var/status = "Normal"
		if(R.stat)
			status = "Not responding"
		else if(!(R.mobility_flags & MOBILITY_MOVE))
			status = "Locked down"
		var/unit = list(
			"ref" = REF(R),
			"name" = R.name,
			"status" = status,
			"locked" = !!R.lockcharge,
			"cell" = (R.mobility_flags & MOBILITY_MOVE) ? (R.cell ? R.cell.percent() : -1) : null,
			"module" = R.module ? "[R.module.name] Module" : "No module",
			"can_hack" = ((istype(S) && user != R && S.hack_software && !is_servant_of_ratvar(S)) || IsAdminGhost(user)) && !R.emagged,
			"can_convert" = istype(S) && user != R && is_servant_of_ratvar(S) && !is_servant_of_ratvar(R),
		)
		if(!groups[group])
			groups[group] = list()
		groups[group] += list(unit)
	var/list/cyborgs = list()
	for(var/group in sortList(groups))
		cyborgs += list(list("name" = group, "units" = groups[group]))
	data["cyborgs"] = cyborgs
	var/list/drones = list()
	for(var/mob/living/simple_animal/drone/D in GLOB.drones_list)
		var/turf/where = get_turf(D)
		if(D.hacked || !where || where.z != z)
			continue
		drones += list(list("ref" = REF(D), "name" = D.name, "status" = D.stat ? "Not responding" : "Normal"))
	data["drones"] = drones
	return data

/obj/machinery/computer/robotics/ui_act(action, params)
	if(..())
		return
	var/mob/user = usr
	switch(action)
		if("lockdown") // the Topic() branch, confirmed in the page
			var/mob/living/silicon/robot/R = locate(params["ref"]) in GLOB.silicon_mobs
			if(!allowed(user))
				to_chat(user, "<span class='danger'>Access Denied.</span>")
			else if(can_control(user, R))
				message_admins("<span class='notice'>[ADMIN_LOOKUPFLW(user)] [!R.lockcharge ? "locked down" : "released"] [ADMIN_LOOKUPFLW(R)]!</span>")
				log_game("[key_name(user)] [!R.lockcharge ? "locked down" : "released"] [key_name(R)]!")
				R.SetLockdown(!R.lockcharge)
				to_chat(R, "[!R.lockcharge ? "<span class='notice'>Your lockdown has been lifted!" : "<span class='alert'>You have been locked down!"]</span>")
				if(R.connected_ai)
					to_chat(R.connected_ai, "[!R.lockcharge ? "<span class='notice'>NOTICE - Cyborg lockdown lifted" : "<span class='alert'>ALERT - Cyborg lockdown detected"]: <a href='?src=[REF(R.connected_ai)];track=[html_encode(R.name)]'>[R.name]</a></span><br>")
		if("destroy") // likewise
			var/mob/living/silicon/robot/R = locate(params["ref"]) in GLOB.silicon_mobs
			if(!allowed(user))
				to_chat(user, "<span class='danger'>Access Denied.</span>")
			else if(can_control(user, R))
				var/turf/T = get_turf(R)
				message_admins("<span class='notice'>[ADMIN_LOOKUPFLW(user)] detonated [key_name_admin(R, R.client)] at [ADMIN_VERBOSEJMP(T)]!</span>")
				log_game("\<span class='notice'>[key_name(user)] detonated [key_name(R)]!</span>")
				if(R.connected_ai)
					to_chat(R.connected_ai, "<br><br><span class='alert'>ALERT - Cyborg detonation detected: [R.name]</span><br>")
				R.self_destruct()
		if("hack")
			Topic(null, list("magbot" = params["ref"]))
		if("convert")
			Topic(null, list("convert" = params["ref"]))
		if("destroy_drone")
			var/mob/living/simple_animal/drone/D = locate(params["ref"]) in GLOB.drones_list
			if(D)
				Topic(null, list("killdrone" = params["ref"]))
	return TRUE
