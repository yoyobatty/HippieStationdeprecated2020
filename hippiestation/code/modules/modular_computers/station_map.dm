// Station Map: a top-down map of the station (tgui-next StationMap.js), each room coloured by the layer picked: its air
// (vacuum, toxins, heat, cold, pressure, oxygen; read only from turfs that start with ordinary air, so rooms airless or
// cold by design don't read as faults), its APC (charge, channels) or its alarms (fire, atmos, power); click a room for
// its readings. View only. An NTOS app for engineering and atmospherics (preinstalled on engineering
// consoles, on NTNet for the rest) and an AI verb. The user's rulings, 2026-11-06.
//
// The floor plan is read once per level and kept: each row as runs of "code*length", where code is the room's number
// times two, plus one for a wall. A wall knocked down later still shows; the readings are always live.

/// z -> the plan: list("rows", "areas" (names), "x0", "y0", "width", "height"), plus "samples" (turfs to read the air from)
GLOBAL_LIST_EMPTY(station_map_plans)

/proc/station_map_plan(z)
	var/list/plan = GLOB.station_map_plans["[z]"]
	if(plan)
		return plan
	var/list/area_index = list() // area -> number
	var/list/area_names = list()
	var/list/samples = list() // number -> open turfs
	var/min_x = world.maxx
	var/min_y = world.maxy
	var/max_x = 0
	var/max_y = 0
	var/list/codes = new /list(world.maxy, world.maxx)
	for(var/y in 1 to world.maxy)
		for(var/x in 1 to world.maxx)
			var/turf/T = locate(x, y, z)
			var/area/A = T.loc
			if(istype(A, /area/space) || istype(A, /area/shuttle) || istype(T, /turf/open/space))
				continue
			var/number = area_index[A]
			if(!number)
				area_names += A.name
				number = area_names.len
				area_index[A] = number
				samples += list(list())
			codes[y][x] = number * 2 + (isclosedturf(T) ? 1 : 0)
			// The air is read only where the station keeps it: turfs built with ordinary air. Airless plating, burn
			// chambers, tank floors, cold server rooms and solars start otherwise, and read as they're meant to be.
			if(isopenturf(T) && T.initial_gas_mix == OPENTURF_DEFAULT_ATMOS)
				var/list/open = samples[number]
				open += T
			min_x = min(min_x, x)
			min_y = min(min_y, y)
			max_x = max(max_x, x)
			max_y = max(max_y, y)
		CHECK_TICK
	// Up to three turfs a room to read its air from, spread across it
	for(var/i in 1 to samples.len)
		var/list/open = samples[i]
		var/list/picked = list()
		if(open.len)
			picked |= open[1]
			picked |= open[round((open.len + 1) / 2)]
			picked |= open[open.len]
		samples[i] = picked
	var/list/rows = list()
	if(max_x)
		for(var/y in max_y to min_y step -1) // top row first, as the map is drawn
			var/list/runs = list()
			var/run_code = -1
			var/run_length = 0
			for(var/x in min_x to max_x)
				var/code = codes[y][x] || 0
				if(code == run_code)
					run_length++
					continue
				if(run_length)
					runs += "[run_code]*[run_length]"
				run_code = code
				run_length = 1
			if(run_length)
				runs += "[run_code]*[run_length]"
			rows += runs.Join(",")
	plan = list(
		"rows" = rows,
		"areas" = area_names,
		"x0" = min_x,
		"y0" = max_y,
		"width" = max_x ? max_x - min_x + 1 : 0,
		"height" = max_x ? max_y - min_y + 1 : 0,
		"samples" = samples,
		"index" = area_index,
	)
	GLOB.station_map_plans["[z]"] = plan
	return plan

/// What the window gets once: the plan without the turfs
/proc/station_map_static(z)
	var/list/plan = station_map_plan(z)
	var/list/levels = list()
	for(var/level in SSmapping.levels_by_trait(ZTRAIT_STATION))
		levels += level
	return list(
		"rows" = plan["rows"],
		"areas" = plan["areas"],
		"width" = plan["width"],
		"height" = plan["height"],
		"x0" = plan["x0"],
		"y0" = plan["y0"],
		"z" = z,
		"levels" = levels,
	)

/// The readings, room by room, in the plan's order
/proc/station_map_readings(z)
	var/list/plan = station_map_plan(z)
	var/list/index = plan["index"]
	var/list/samples = plan["samples"]
	var/list/apcs = list()
	for(var/obj/machinery/power/apc/apc in GLOB.apcs_list)
		if(apc.area && index[apc.area])
			apcs[apc.area] = apc
	// Rooms with an air alarm: the ones the station keeps breathable (solars, tanks and burn chambers have none)
	var/list/alarmed = list()
	for(var/obj/machinery/airalarm/alarm in GLOB.machines)
		var/area/A = get_area(alarm)
		if(A && index[A])
			alarmed[A] = TRUE
	var/list/rooms = new /list(length(plan["areas"]))
	for(var/area/A in index)
		var/number = index[A]
		var/list/room = list()
		// The air: the worst of a few turfs
		var/low_pressure
		var/high_pressure
		var/low_temp
		var/high_temp
		var/plasma = 0
		var/co2 = 0
		var/low_o2
		for(var/turf/open/T in samples[number])
			var/datum/gas_mixture/air = T.return_air()
			if(!air)
				continue
			var/pressure = air.return_pressure()
			var/temperature = air.return_temperature()
			var/total = air.total_moles()
			low_pressure = isnull(low_pressure) ? pressure : min(low_pressure, pressure)
			high_pressure = isnull(high_pressure) ? pressure : max(high_pressure, pressure)
			low_temp = isnull(low_temp) ? temperature : min(low_temp, temperature)
			high_temp = isnull(high_temp) ? temperature : max(high_temp, temperature)
			if(total > 0)
				plasma = max(plasma, pressure * air.moles[/datum/gas/plasma] / total)
				co2 = max(co2, pressure * air.moles[/datum/gas/carbon_dioxide] / total)
				var/o2 = pressure * air.moles[/datum/gas/oxygen] / total
				low_o2 = isnull(low_o2) ? o2 : min(low_o2, o2)
			else
				low_o2 = 0
		if(!isnull(low_pressure))
			room["p"] = round(low_pressure, 0.1)
			room["pmax"] = round(high_pressure, 0.1)
			room["t"] = round(low_temp, 0.1)
			room["tmax"] = round(high_temp, 0.1)
			room["plasma"] = round(plasma, 0.01)
			room["co2"] = round(co2, 0.01)
			room["o2"] = round(low_o2, 0.1)
		room["air_alarm"] = !!alarmed[A]
		// The alarms
		room["fire"] = !!A.fire
		room["atmos"] = !!A.atmosalm
		room["power_alarm"] = !A.poweralm
		// The APC
		room["needs_power"] = A.requires_power && !A.always_unpowered
		var/obj/machinery/power/apc/apc = apcs[A]
		if(apc)
			room["apc"] = TRUE
			room["broken"] = !!(apc.stat & (BROKEN|MAINT))
			room["breaker"] = !!apc.operating
			room["charge"] = apc.cell ? round(apc.cell.percent()) : null
			room["charging"] = apc.charging
		room["equip"] = !!A.power_equip
		room["light"] = !!A.power_light
		room["environ"] = !!A.power_environ
		rooms[number] = room
	return rooms

// The NTOS app

/datum/computer_file/program/station_map
	filename = "stationmap"
	filedesc = "Station Map"
	program_icon_state = "power_monitor"
	extended_desc = "A map of the station's rooms by their air, power and alarms."
	transfer_access = ACCESS_ENGINE
	required_access = ACCESS_ENGINE
	requires_ntnet = TRUE
	network_destination = "station map"
	usage_flags = PROGRAM_ALL
	size = 5
	tgui_id = "ntos_station_map"
	ui_x = 920
	ui_y = 700
	available_on_ntnet = TRUE
	var/z_level

/// Engineering or atmospherics
/datum/computer_file/program/station_map/can_run(mob/user, loud = 0, access_to_check, transfer = 0)
	if(access_to_check)
		return ..()
	if(..(user, FALSE, ACCESS_ENGINE, transfer))
		return TRUE
	return ..(user, loud, ACCESS_ATMOSPHERICS, transfer)

/datum/computer_file/program/station_map/proc/map_z()
	var/list/levels = SSmapping.levels_by_trait(ZTRAIT_STATION)
	if(!z_level || !(z_level in levels))
		z_level = levels.len ? levels[1] : 1
	return z_level

/datum/computer_file/program/station_map/ui_static_data(mob/user)
	return station_map_static(map_z())

/datum/computer_file/program/station_map/ui_data(mob/user)
	var/list/data = get_header_data()
	data["rooms"] = station_map_readings(map_z())
	return data

/datum/computer_file/program/station_map/ui_act(action, list/params)
	if(..())
		return TRUE
	if(action == "level")
		var/level = text2num(params["z"])
		if(level in SSmapping.levels_by_trait(ZTRAIT_STATION))
			z_level = level
			update_static_data(usr)
		return TRUE

/obj/machinery/modular_computer/console/preset/engineering/install_programs()
	..()
	var/obj/item/computer_hardware/hard_drive/hard_drive = cpu.all_components[MC_HDD]
	hard_drive.store_file(new /datum/computer_file/program/station_map())

// The AI's

/datum/station_map_view
	var/mob/living/silicon/ai/owner
	var/z_level

/datum/station_map_view/New(mob/living/silicon/ai/new_owner)
	owner = new_owner

/datum/station_map_view/Destroy()
	owner = null
	return ..()

/datum/station_map_view/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "station_map", "Station Map", 920, 680, master_ui, state)
		ui.open()

/datum/station_map_view/ui_status(mob/user, datum/ui_state/state)
	if(user != owner || owner.stat == DEAD)
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/station_map_view/proc/map_z()
	var/list/levels = SSmapping.levels_by_trait(ZTRAIT_STATION)
	if(!z_level || !(z_level in levels))
		z_level = levels.len ? levels[1] : 1
	return z_level

/datum/station_map_view/ui_static_data(mob/user)
	return station_map_static(map_z())

/datum/station_map_view/ui_data(mob/user)
	return list("rooms" = station_map_readings(map_z()))

/datum/station_map_view/ui_act(action, list/params)
	if(..())
		return TRUE
	if(action == "level")
		var/level = text2num(params["z"])
		if(level in SSmapping.levels_by_trait(ZTRAIT_STATION))
			z_level = level
			update_static_data(usr)
		return TRUE

/mob/living/silicon/ai
	var/datum/station_map_view/station_map_view

/mob/living/silicon/ai/verb/station_map()
	set category = "AI Commands"
	set name = "Station Map"
	set desc = "The station's rooms by their air, power and alarms"
	if(stat == DEAD)
		return
	if(!station_map_view)
		station_map_view = new(src)
	station_map_view.ui_interact(src)

/mob/living/silicon/ai/Destroy()
	QDEL_NULL(station_map_view)
	return ..()
