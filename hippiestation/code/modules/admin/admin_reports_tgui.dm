// hippie -- the debug and mapping reports in tgui (interfaces/AdminReports.js). Test Areas, Test Atmos Monitoring Consoles, Camera
// Report, the roundstart active turfs, Radio report, the Initialize() log and a map file's report all show their problems the same
// way: grouped, each group a filter with its count, each line with where it is and a jump there. The del() log is a table you can sort.

/// A problems report: groups (id, label, how bad: "bad", "warn", "info") and lines (group, text, detail, where)
/datum/admin_tool_window/report
	interface = "admin_report"
	title = "Report"
	width = 760
	height = 600
	rights = R_ADMIN
	var/summary
	var/list/groups
	var/list/rows
	/// Refs the lines may VV, so the page can't ask for anything else
	var/list/refs

/datum/admin_tool_window/report/setup(list/arguments)
	title = arguments["title"] || title
	summary = arguments["summary"]
	groups = arguments["groups"] || list()
	rows = arguments["rows"] || list()
	refs = list()
	for(var/list/row in rows)
		if(row["ref"])
			refs[row["ref"]] = TRUE

/datum/admin_tool_window/report/ui_data(mob/user)
	return list("summary" = summary, "groups" = groups, "rows" = rows)

/datum/admin_tool_window/report/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("jump")
			var/x = text2num("[params["x"]]")
			var/y = text2num("[params["y"]]")
			var/z = text2num("[params["z"]]")
			if(x && y && z)
				holder.page_holder_link(list("adminplayerobservecoodjump" = "1", "X" = "[x]", "Y" = "[y]", "Z" = "[z]"))
		if("vv")
			if(refs[params["ref"]])
				var/datum/D = locate(params["ref"])
				if(D)
					usr.client.debug_variables(D)
	return TRUE

/// One line of a report: where, if it's somewhere
/proc/admin_report_row(group, text, atom/where, detail)
	var/list/row = list("group" = group, "text" = "[text]")
	if(detail)
		row["detail"] = "[detail]"
	if(where)
		var/turf/T = get_turf(where)
		if(T)
			row["x"] = T.x
			row["y"] = T.y
			row["z"] = T.z
			row["area"] = "[get_area(T)]"
		if(!isturf(where))
			row["ref"] = REF(where)
	return row

/client/proc/open_admin_report(kind, title, summary, list/groups, list/rows)
	holder?.open_admin_tool(kind, /datum/admin_tool_window/report, list("title" = title, "summary" = summary, "groups" = groups, "rows" = rows))

// ---------------------------------------------------------------------------------------------
// Test Areas
// ---------------------------------------------------------------------------------------------

/client/cmd_admin_areatest(on_station)
	if(SSticker.current_state == GAME_STATE_STARTUP)
		to_chat(usr, "Game still loading, please hold!")
		return
	var/where = on_station ? "station z-levels" : "all z-levels"
	message_admins("<span class='adminnotice'>[key_name_admin(usr)] used the Test Areas debug command checking [where].</span>")
	log_admin("[key_name(usr)] used the Test Areas debug command checking [where].")
	var/static/list/station_areas_blacklist = typecacheof(list(/area/holodeck/rec_center, /area/shuttle, /area/engine/supermatter, \
		/area/science/test_area, /area/space, /area/solar, /area/mine, /area/ruin, /area/asteroid))
	// Each area type checked, with a tile of it to jump to
	var/list/checked = list()
	for(var/area/A in world)
		if(checked[A.type])
			continue
		var/turf/T = locate(/turf) in A
		if(on_station && (!T || !is_station_level(T.z) || is_type_in_typecache(A, station_areas_blacklist)))
			continue
		checked[A.type] = T || TRUE
		CHECK_TICK
	var/list/has = list("apc" = list(), "air_alarm" = list(), "rc" = list(), "light" = list(), "switch" = list(), "intercom" = list(), "camera" = list())
	var/list/apc_count = list()
	for(var/obj/machinery/power/apc/APC in GLOB.apcs_list)
		if(APC.area)
			apc_count[APC.area.type]++
			has["apc"][APC.area.type] = TRUE
	for(var/obj/O in GLOB.machines)
		var/kind
		if(istype(O, /obj/machinery/airalarm))
			kind = "air_alarm"
		else if(istype(O, /obj/machinery/requests_console))
			kind = "rc"
		else if(istype(O, /obj/machinery/light))
			kind = "light"
		else if(istype(O, /obj/machinery/light_switch))
			kind = "switch"
		else if(istype(O, /obj/item/radio/intercom))
			kind = "intercom"
		else if(istype(O, /obj/machinery/camera))
			kind = "camera"
		if(kind)
			var/area/A = get_area(O)
			if(A)
				has[kind][A.type] = TRUE
		CHECK_TICK
	var/list/groups = list(
		list("id" = "apc", "label" = "No APC", "level" = "bad"),
		list("id" = "multi_apc", "label" = "More than one APC", "level" = "bad"),
		list("id" = "air_alarm", "label" = "No air alarm", "level" = "warn"),
		list("id" = "light", "label" = "No lights", "level" = "warn"),
		list("id" = "switch", "label" = "No light switch", "level" = "info"),
		list("id" = "rc", "label" = "No requests console", "level" = "info"),
		list("id" = "intercom", "label" = "No intercom", "level" = "info"),
		list("id" = "camera", "label" = "No camera", "level" = "info"),
	)
	// Worst first: the groups' order, then the areas
	var/list/rows = list()
	for(var/list/group in groups)
		var/kind = group["id"]
		for(var/area_type in checked)
			var/turf/T = isturf(checked[area_type]) ? checked[area_type] : null
			var/area/A = area_type
			if(kind == "multi_apc")
				if(apc_count[area_type] > 1)
					rows += list(admin_report_row(kind, initial(A.name), T, "[area_type]: [apc_count[area_type]] APCs"))
			else if(!has[kind][area_type])
				rows += list(admin_report_row(kind, initial(A.name), T, "[area_type]"))
	open_admin_report("areatest", "Test Areas", "[length(checked)] area types on [where]", groups, rows)

// ---------------------------------------------------------------------------------------------
// Test Atmos Monitoring Consoles
// ---------------------------------------------------------------------------------------------

/client/cmd_admin_test_atmos_controllers()
	if(SSticker.current_state == GAME_STATE_STARTUP)
		to_chat(usr, "Game still loading, please hold!")
		return
	message_admins("<span class='adminnotice'>[key_name_admin(usr)] used the Test Atmos Monitor debug command.</span>")
	log_admin("[key_name(usr)] used the Test Atmos Monitor debug command.")
	var/list/groups = list(
		list("id" = "bad", "label" = "Broken", "level" = "bad"),
		list("id" = "ok", "label" = "Working", "level" = "info"),
	)
	var/list/rows = list()
	var/count = 0
	for(var/obj/machinery/computer/atmos_control/tank/console in GLOB.atmos_air_controllers)
		count++
		var/list/wrong = list()
		if(console.input_tag == console.output_tag)
			wrong += "input and output both tagged \"[console.input_tag]\""
		if(!LAZYLEN(console.input_info))
			wrong += "no injector tagged [console.input_tag]"
		if(!LAZYLEN(console.output_info))
			wrong += "no vent tagged [console.output_tag]"
		rows += list(admin_report_row(length(wrong) ? "bad" : "ok", "[console]", console, length(wrong) ? jointext(wrong, "; ") : null))
		CHECK_TICK
	open_admin_report("atmos_consoles", "Atmos monitoring consoles", "[count] tank consoles", groups, rows)

// ---------------------------------------------------------------------------------------------
// Camera Report
// ---------------------------------------------------------------------------------------------

/client/sec_camera_report()
	if(!Master)
		tgui_alert(usr, "Master_controller not found.", "Sec Camera Report")
		return 0
	var/list/cameras = GLOB.cameranet.cameras.Copy()
	var/list/groups = list(
		list("id" = "tag", "label" = "Same c_tag", "level" = "bad"),
		list("id" = "full_overlap", "label" = "Fully overlapping", "level" = "bad"),
		list("id" = "wall", "label" = "Not on a wall", "level" = "bad"),
		list("id" = "overlap", "label" = "Same tile", "level" = "info"),
	)
	var/list/rows = list()
	for(var/i in 1 to length(cameras))
		var/obj/machinery/camera/C1 = cameras[i]
		for(var/j in i + 1 to length(cameras))
			var/obj/machinery/camera/C2 = cameras[j]
			if(C1.c_tag == C2.c_tag)
				rows += list(admin_report_row("tag", "[C1.c_tag]", C1, "also at [AREACOORD(C2)]"))
			if(C1.loc == C2.loc)
				var/full = C1.dir == C2.dir && C1.pixel_x == C2.pixel_x && C1.pixel_y == C2.pixel_y
				rows += list(admin_report_row(full ? "full_overlap" : "overlap", "[C1.c_tag] and [C2.c_tag]", C1, \
					"networks [jointext(C1.network, ", ")] and [jointext(C2.network, ", ")]"))
		var/turf/T = get_step(C1, turn(C1.dir, 180))
		if(!T || !isturf(T) || !T.density)
			if(!(locate(/obj/structure/grille) in T))
				var/window_check = FALSE
				for(var/obj/structure/window/W in T)
					if(W.dir == turn(C1.dir, 180) || (W.dir in list(5, 6, 9, 10)))
						window_check = TRUE
						break
				if(!window_check)
					rows += list(admin_report_row("wall", "[C1.c_tag]", C1, "network [jointext(C1.network, ", ")]"))
		CHECK_TICK
	open_admin_report("cameras", "Camera report", "[length(cameras)] cameras. Same-tile ones can be on purpose.", groups, rows)
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Show Camera Report")

// ---------------------------------------------------------------------------------------------
// The roundstart active turfs
// ---------------------------------------------------------------------------------------------

/client/cmd_show_at_list()
	var/list/rows = list()
	for(var/turf/T in GLOB.active_turfs_startlist)
		rows += list(admin_report_row("turf", "[T]", T, "[T.type]"))
	open_admin_report("at_list", "Roundstart active turfs", "Turfs with air moving when the round started. Live ones are SSair's active_turfs.", \
		list(list("id" = "turf", "label" = "Active at roundstart", "level" = "warn")), rows)
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Show Roundstart Active Turfs")

// ---------------------------------------------------------------------------------------------
// Radio report
// ---------------------------------------------------------------------------------------------

/client/radio_report()
	var/list/groups = list()
	var/list/rows = list()
	for(var/fq in SSradio.frequencies)
		var/datum/radio_frequency/frequency = SSradio.frequencies[fq]
		var/label = "[format_frequency(text2num(fq))]"
		groups += list(list("id" = "[fq]", "label" = label, "level" = frequency ? "info" : "bad"))
		if(!frequency)
			rows += list(admin_report_row("[fq]", "Frequency missing its datum"))
			continue
		for(var/filter in frequency.devices)
			var/list/devices = frequency.devices[filter]
			if(!devices)
				rows += list(admin_report_row("[fq]", "[filter]: no device list"))
				continue
			for(var/device in devices)
				rows += list(admin_report_row("[fq]", "[device]", isatom(device) ? device : null, "filter [filter]"))
	open_admin_report("radio", "Radio report", "[length(groups)] frequencies", groups, rows)
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Show Radio Report")

// ---------------------------------------------------------------------------------------------
// The Initialize() log
// ---------------------------------------------------------------------------------------------

/client/cmd_display_init_log()
	var/list/rows = list()
	for(var/line in splittext(SSatoms.InitLog(), "\n"))
		if(length(trim(line)))
			rows += list(admin_report_row("line", line))
	open_admin_report("init_log", "Initialize() log", "Things that didn't handle Initialize() properly", \
		list(list("id" = "line", "label" = "Problems", "level" = "warn")), rows)

// ---------------------------------------------------------------------------------------------
// A map file's report (verify.dm)
// ---------------------------------------------------------------------------------------------

/datum/map_report/show_to(client/C)
	if(!C?.holder)
		return
	var/list/groups = list(
		list("id" = "path", "label" = "Bad paths", "level" = "bad"),
		list("id" = "key", "label" = "Bad keys", "level" = "warn"),
	)
	var/list/rows = list()
	for(var/path in bad_paths)
		var/list/keys = bad_paths[path]
		rows += list(admin_report_row("path", "[path]", null, "used in [length(keys)]: [keys.Join(", ")]"))
	for(var/key in bad_keys)
		var/list/messages = bad_keys[key]
		rows += list(admin_report_row("key", "[key]", null, messages.Join("; ")))
	var/list/state = list()
	if(crashed)
		state += "validation crashed, check the runtime log"
	if(!loadable)
		state += "not loadable: some tiles are missing their turf or area"
	C.open_admin_report("map_report_[tag]", "Map report", "[original_path][length(state) ? " - [state.Join("; ")]" : ""]", groups, rows)

// ---------------------------------------------------------------------------------------------
// The del() log
// ---------------------------------------------------------------------------------------------

/client/cmd_display_del_log()
	holder?.open_admin_tool("del_log", /datum/admin_tool_window/del_log)

/datum/admin_tool_window/del_log
	interface = "admin_del_log"
	title = "qdel() log"
	width = 860
	height = 600
	rights = NONE

/datum/admin_tool_window/del_log/ui_data(mob/user)
	var/list/items = list()
	for(var/path in SSgarbage.items)
		var/datum/qdel_item/I = SSgarbage.items[path]
		items += list(list("path" = "[path]", "qdels" = I.qdels, "destroy_ms" = I.destroy_time, "failures" = I.failures, \
			"hard" = I.hard_deletes, "hard_ms" = I.hard_delete_time, "slept" = I.slept_destroy, "no_force" = I.no_respect_force, \
			"no_hint" = I.no_hint))
	return list("items" = items)
