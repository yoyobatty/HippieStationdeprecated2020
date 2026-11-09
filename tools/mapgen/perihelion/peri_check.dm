// Perihelion map self-test. Not part of the game.
// HARNESS=../mapgen/perihelion/peri_check.dm EXTRA_PARAMS="bot-map=perihelion" WAIT_SECONDS=900 bash tools/power_check/run.sh <label>
// Starts the round, waits, then reports power (APCs, SMES, solars), air on station turfs and whether every shuttle fits its dock.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/pc_log(text)
	text2file(text, "data/update_check.txt")

/world/New()
	. = ..()
	spawn(0)
		peri_check_run()

/proc/peri_check_power(label)
	var/apcs = 0
	var/no_main = 0
	var/low_cell = 0
	var/list/no_main_names = list()
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(!A.z || !is_station_level(A.z))
			continue
		apcs++
		if(A.main_status == 0)
			no_main++
			if(length(no_main_names) < 8)
				no_main_names += A.area ? A.area.name : "?"
		if(A.cell && A.cell.charge < A.cell.maxcharge * 0.2)
			low_cell++
	var/list/smes_lines = list()
	for(var/obj/machinery/power/smes/S in GLOB.machines)
		if(!S.z || !is_station_level(S.z))
			continue
		smes_lines += "[get_area_name(S)] [round(100 * S.charge / S.capacity)]% in [round(S.input_available)] out [round(S.output_used)]"
	var/solar_gen = 0
	var/panels = 0
	for(var/obj/machinery/power/solar_control/C in GLOB.machines)
		if(!C.z || !is_station_level(C.z))
			continue
		solar_gen += C.lastgen
		panels += length(C.connected_panels)
	var/areas_without = 0
	var/list/without = list()
	for(var/area/A in GLOB.sortedAreas)
		if(!A.requires_power || A.always_unpowered || A.z != SSmapping.station_start)
			continue
		if(!A.get_apc() && A.contents.len)
			areas_without++
			if(length(without) < 8)
				without += A.name
	pc_log("[label] power: [apcs] station APCs, [no_main] with no mains[length(no_main_names) ? " ([jointext(no_main_names, ", ")])" : ""], [low_cell] cells under 20%; solars [panels] panels [round(solar_gen)] W; areas with no APC [areas_without] [jointext(without, ", ")]")
	pc_log("[label] SMES: [jointext(smes_lines, " | ")]")

/proc/peri_check_nets(label)
	var/list/nets = list()
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(!A.z || !is_station_level(A.z))
			continue
		var/datum/powernet/P = A.terminal?.powernet
		var/key = P ? "\ref[P]" : "none"
		if(!nets[key])
			nets[key] = list()
		nets[key] += A
	for(var/key in nets)
		var/list/L = nets[key]
		var/obj/machinery/power/apc/first = L[1]
		var/datum/powernet/P = first.terminal?.powernet
		var/smes = 0
		var/list/smes_names = list()
		if(P)
			for(var/obj/machinery/power/smes/S in P.nodes)
				smes++
				smes_names += "[get_area_name(S)] [S.x],[S.y]"
		var/list/names = list()
		for(var/obj/machinery/power/apc/A as anything in L)
			if(length(names) < 10)
				names += "[A.area?.name] ([A.x],[A.y])"
		pc_log("[label] net [key]: [length(L)] APCs, avail [P ? round(P.avail) : 0], load [P ? round(P.load) : 0], [smes] SMES [jointext(smes_names, "; ")]; [length(L) < 30 ? jointext(names, ", ") : ""]")

GLOBAL_LIST_EMPTY(peri_cable_turfs)
/proc/peri_cables_note()
	for(var/obj/structure/cable/C in GLOB.cable_list)
		if(C.z && is_station_level(C.z) && C.cable_layer == CABLE_LAYER_2)
			GLOB.peri_cable_turfs[get_turf(C)] = TRUE

/proc/peri_cables_missing(label)
	var/list/gone = list()
	var/list/present = list()
	for(var/obj/structure/cable/C in GLOB.cable_list)
		if(C.z && is_station_level(C.z) && C.cable_layer == CABLE_LAYER_2)
			present[get_turf(C)] = TRUE
	for(var/turf/T in GLOB.peri_cable_turfs)
		if(!present[T])
			gone += "[T.x],[T.y] [T.type] [get_area_name(T)]"
	pc_log("[label] cables gone: [length(gone)]: [jointext(gone.Copy(1, min(length(gone), 25) + 1), " | ")]")

/proc/peri_check_air(label)
	var/total = 0
	var/low = 0
	var/high = 0
	var/space = 0
	var/list/bad_areas = list()
	for(var/area/A in GLOB.sortedAreas)
		if(!A.requires_power || A.z != SSmapping.station_start || istype(A, /area/space) || istype(A, /area/solar))
			continue
		for(var/turf/open/floor/T in A)
			if(isspaceturf(T))
				space++
				continue
			var/datum/gas_mixture/G = T.return_air()
			if(!G)
				continue
			total++
			var/p = G.return_pressure()
			if(p < 80)
				low++
				bad_areas[A.name] = (bad_areas[A.name] || 0) + 1
			else if(p > 130)
				high++
				bad_areas[A.name] = (bad_areas[A.name] || 0) + 1
	var/list/worst = list()
	for(var/n in bad_areas)
		worst += "[n] [bad_areas[n]]"
	pc_log("[label] air: [total] station floor turfs, [low] under 80 kPa, [high] over 130 kPa, [space] space turfs in station areas; [jointext(worst.Copy(1, min(length(worst), 12) + 1), ", ")]")

/proc/peri_check_docks()
	var/list/pairs = list("emergency" = "emergency_home", "supply" = "supply_home", "mining" = "mining_home", "laborcamp" = "laborcamp_home", "arrivals" = "arrivals_stationary")
	for(var/sid in pairs)
		var/obj/docking_port/mobile/M = SSshuttle.getShuttle(sid)
		var/obj/docking_port/stationary/S = SSshuttle.getDock(pairs[sid])
		if(!M || !S)
			pc_log("dock [sid] -> [pairs[sid]]: shuttle [M ? "found" : "MISSING"], dock [S ? "found" : "MISSING"]")
			continue
		var/docked = M.get_docked()
		pc_log("dock [sid] -> [pairs[sid]]: can dock = [M.canDock(S)], docked at [docked ? "[docked:id]" : "nowhere"] ([M.x],[M.y])")
	var/pods = 0
	for(var/obj/docking_port/mobile/pod/P in SSshuttle.mobile)
		if(is_station_level(P.z))
			pods++
	pc_log("escape pods at the station: [pods]")

/proc/peri_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	CONFIG_SET(flag/allow_random_events, FALSE)
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	pc_log("map [SSmapping.config.map_name], round state [SSticker.current_state]")
	sleep(20 SECONDS)
	peri_check_power("start")
	peri_check_nets("start")
	peri_cables_note()
	peri_check_air("start")
	peri_check_docks()
	// send the supply and emergency shuttles here and see them dock
	var/obj/docking_port/mobile/supply = SSshuttle.getShuttle("supply")
	if(supply)
		supply.request(SSshuttle.getDock("supply_home"))
	SSshuttle.emergency?.request(null, 0.1)
	sleep(4 MINUTES)
	peri_check_power("4 min")
	peri_check_air("4 min")
	peri_check_docks()
	sleep(4 MINUTES)
	peri_check_power("8 min")
	peri_check_nets("8 min")
	peri_cables_missing("8 min")
	peri_check_air("8 min")
	pc_log("done")
