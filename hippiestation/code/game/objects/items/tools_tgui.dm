// Blueprints, the camera bug and the RCD's airlock access moved off their old HTML windows (tgui-next Tools.js). Buttons
// run each one's own Topic(); the area name, a pop-up before, comes from the window with the same checks. The camera
// bug's Monitor-view links (Select Camera, Track, the camera names) were missing "src=" and never worked; here they do.

// Blueprints

/obj/item/areaeditor/blueprints/attack_self(mob/user)
	add_fingerprint(user)
	ui_interact(user)

/obj/item/areaeditor/blueprints/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
											datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "blueprints", name, 560, 560, master_ui, state)
		ui.open()

/obj/item/areaeditor/blueprints/ui_static_data(mob/user)
	var/list/wiresets = list()
	for(var/device in GLOB.wire_color_directory)
		var/list/wires = list()
		for(var/color in GLOB.wire_color_directory[device])
			var/wire_name = GLOB.wire_color_directory[device][color]
			if(!findtext(wire_name, WIRE_DUD_PREFIX)) // duds aren't shown, as before
				wires += list(list("color" = color, "name" = wire_name))
		wiresets += list(list("name" = GLOB.wire_name_directory[device], "wires" = wires))
	return list("wiresets" = wiresets, "station" = station_name(), "fluff" = fluffnotice)

/obj/item/areaeditor/blueprints/ui_data(mob/user)
	var/list/data = list()
	var/area/A = get_area(user)
	var/type = get_area_type(A)
	data["area"] = A ? A.name : null
	data["area_type"] = type == AREA_STATION ? "station" : (type == AREA_SPACE ? "space" : "special")
	data["viewing"] = !!viewing
	return data

/obj/item/areaeditor/blueprints/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("create_area")
			Topic(null, list("create_area" = "1"))
			return TRUE
		if("view")
			Topic(null, list("view_blueprints" = "1"))
			return TRUE
		if("hide")
			Topic(null, list("hide_blueprints" = "1"))
			return TRUE
		if("refresh")
			Topic(null, list("refresh" = "1"))
			return TRUE
		if("rename")
			// edit_area() (blueprints.dm) asked for the name with a pop-up
			if(!usr.canUseTopic(src) || in_use)
				return
			var/area/A = get_area(usr)
			if(get_area_type(A) != AREA_STATION)
				return
			var/prevname = "[A.name]"
			var/str = trim(html_encode(params["name"]), MAX_NAME_LEN)
			if(!length(str) || str == prevname)
				return
			rename_area(A, str)
			to_chat(usr, "<span class='notice'>You rename the '[prevname]' to '[str]'.</span>")
			log_game("[key_name(usr)] has renamed [prevname] to [str]")
			A.update_areasize()
			return TRUE

// Camera bug: camera_bug.dm's modes, which it undefines at its end

#define BUGMODE_LIST 0
#define BUGMODE_MONITOR 1
#define BUGMODE_TRACK 2

/obj/item/camera_bug/ui_interact(mob/user = usr, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
								datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "camera_bug", "Camera Bug", 480, 520, master_ui, state)
		ui.open()

/obj/item/camera_bug/ui_data(mob/user)
	var/list/data = list()
	var/list/cameras = get_cameras()
	data["mode"] = track_mode
	data["current"] = current ? current.c_tag : null
	var/list/camera_list = list()
	for(var/entry in cameras)
		var/obj/machinery/camera/C = cameras[entry]
		if(QDELETED(C))
			continue
		camera_list += list(list("ref" = REF(C), "name" = entry, "bugged" = C.bug == src))
	data["cameras"] = camera_list
	if(track_mode == BUGMODE_MONITOR && current)
		var/list/seen = get_seens()
		var/list/report = list()
		for(var/atom/movable/AM in seen)
			if(!(istype(AM, /obj/singularity) || istype(AM, /obj/mecha) || isliving(AM)))
				continue
			var/state = ""
			if(istype(AM, /obj/singularity))
				var/obj/singularity/S = AM
				state = "Stage [round(S.current_size / 2) + 1]"
			else if(isliving(AM))
				var/mob/living/M = AM
				if(!(M.mobility_flags & MOBILITY_STAND))
					state = M.buckled ? "Sitting" : "Laying down"
			report += list(list("ref" = REF(AM), "name" = AM.name, "state" = state))
		data["report"] = report
		data["offline"] = !seen
	if(track_mode == BUGMODE_TRACK && tracking)
		var/obj/machinery/camera/C = last_found ? bugged_cameras[last_found] : null
		data["tracking"] = list(
			"name" = tracked_name,
			"last_found" = last_found,
			"last_cam" = C ? REF(C) : null,
			"bugged" = C ? C.bug == src : FALSE,
			"seconds" = last_found ? round((world.time - last_seen) / 10) : null,
		)
	return data

/obj/item/camera_bug/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("view")
			Topic(null, list("view" = params["ref"]))
			return TRUE
		if("cancel_view")
			Topic(null, list("view" = ""))
			return TRUE
		if("monitor")
			Topic(null, list("monitor" = params["ref"]))
			return TRUE
		if("emp")
			Topic(null, list("emp" = params["ref"]))
			return TRUE
		if("track")
			Topic(null, list("track" = params["ref"]))
			return TRUE
		if("list")
			Topic(null, list("mode" = "[BUGMODE_LIST]"))
			return TRUE

#undef BUGMODE_LIST
#undef BUGMODE_MONITOR
#undef BUGMODE_TRACK

// RCD airlock access

/obj/item/construction/rcd/change_airlock_access(mob/user)
	if(!ishuman(user) && !user.has_unlimited_silicon_privilege)
		return
	ui_interact(user)

/obj/item/construction/rcd/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "rcd_access", "Access Control", 640, 520, master_ui, state)
		ui.open()

/obj/item/construction/rcd/ui_data(mob/user)
	var/list/data = list()
	data["one_access"] = use_one_access
	var/list/regions = list()
	for(var/i in 1 to 7)
		var/list/accesses = list()
		for(var/A in get_region_accesses(i))
			accesses += list(list("id" = A, "name" = get_access_desc(A), "on" = (A in conf_access)))
		regions += list(list("name" = get_region_accesses_name(i), "accesses" = accesses))
	data["regions"] = regions
	data["count"] = length(conf_access)
	return data

/obj/item/construction/rcd/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("access")
			Topic(null, list("access" = "[params["id"]]"))
			return TRUE
		if("one")
			Topic(null, list("access" = "one"))
			return TRUE
		if("clear")
			Topic(null, list("access" = "all"))
			return TRUE
