// Medical windows redone (tgui-next Cryo.js, CrewConsole.js, OperatingComputer.js): the cryo cell's beaker in its reagents'
// colours, as chemistry's windows draw them (chemistry_tgui.dm), and the crew monitor's station map.

/obj/machinery/atmospherics/components/unary/cryo_cell/ui_data(mob/user)
	. = ..()
	.["beakerContents"] = beaker ? tgui_reagent_list(beaker.reagents) : list()
	.["beakerColor"] = beaker ? tgui_reagent_mix_color(beaker.reagents) : null
	.["beakerVolume"] = beaker ? beaker.reagents.total_volume : 0
	.["beakerMaxVolume"] = beaker ? beaker.volume : 0

// The crew monitor's map: the user's z-level as rows of characters (. space, # wall, _ floor), cropped to where there's
// anything but space, worked out once a level and kept. The window draws it and puts each person's dot on it.

GLOBAL_LIST_EMPTY(crew_monitor_maps)

/proc/crew_monitor_map(z)
	if(GLOB.crew_monitor_maps["[z]"])
		return GLOB.crew_monitor_maps["[z]"]
	var/minx = world.maxx
	var/miny = world.maxy
	var/maxx = 1
	var/maxy = 1
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(isspaceturf(T))
			continue
		minx = min(minx, T.x)
		miny = min(miny, T.y)
		maxx = max(maxx, T.x)
		maxy = max(maxy, T.y)
	var/list/rows = list()
	if(maxx >= minx)
		for(var/y in maxy to miny step -1)
			var/list/row = list()
			for(var/x in minx to maxx)
				var/turf/T = locate(x, y, z)
				if(isspaceturf(T))
					row += "."
				else if(isclosedturf(T))
					row += "#"
				else
					row += "_"
			rows += row.Join()
	var/list/map = list("minx" = minx, "maxy" = maxy, "rows" = rows)
	GLOB.crew_monitor_maps["[z]"] = map
	return map

/datum/crewmonitor/ui_interact(mob/user, ui_key = "crew", datum/tgui/ui = null, force_open = FALSE, \
							datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "crew", "Crew Monitor", 1180, 720, master_ui, state)
		ui.open()

/datum/crewmonitor/ui_static_data(mob/user)
	var/turf/T = get_turf(user)
	return list("map" = T ? crew_monitor_map(T.z) : null)
