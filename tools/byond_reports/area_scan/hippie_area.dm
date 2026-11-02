// How often the game scans areas in a bot shift, and what the same read costs from a plain list, on real station areas.
// Not part of the game. HARNESS=../area_scan/hippie_area.dm PARAMS="bot-shift=20&bot-crew=fill:20&bot-events=1&bot-quiet=1&timewarp=0" bash tools/byond_reports/ref_stall/hippie_check.sh

GLOBAL_LIST_EMPTY(ac_calls)
GLOBAL_LIST_EMPTY(ac_ms)

/proc/ac_log(text)
	text2file(text, "data/ref_stall.txt")

/proc/ac_note(name, ms)
	if(GLOB.ac_calls && GLOB.ac_ms)
		GLOB.ac_calls[name] += 1
		GLOB.ac_ms[name] += ms

/area/power_change()
	var/t0 = world.tick_usage
	. = ..()
	ac_note("area power_change (scan and every machine's own check)", (world.tick_usage - t0) * world.tick_lag)

/// Machines in each station area, read by the scan and from a plain list of the same machines.
/proc/ac_compare()
	var/list/areas = list()
	for(var/area/A as anything in GLOB.sortedAreas)
		if(A.z && is_station_level(A.z) && length(areas) < 60)
			areas += A
	var/scan_total = 0
	var/plain_total = 0
	var/found = 0
	for(var/area/A as anything in areas)
		var/list/machines = list()
		var/t0 = world.tick_usage
		for(var/obj/machinery/M in A)
			machines += M
		var/t1 = world.tick_usage
		sleep(1)
		var/list/copy = list()
		var/t2 = world.tick_usage
		for(var/obj/machinery/M as anything in machines)
			copy += M
		var/t3 = world.tick_usage
		sleep(1)
		scan_total += (t1 - t0) * world.tick_lag
		plain_total += (t3 - t2) * world.tick_lag
		found += length(machines)
	ac_log("[world.maxx * world.maxy * world.maxz] turfs, [length(areas)] station areas, [found] machines: scan [round(scan_total / length(areas), 0.01)] ms an area, plain list [round(plain_total / length(areas), 0.001)] ms an area")

/proc/ac_run()
	UNTIL(SSticker.initialized)
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	ac_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks")
	var/minutes = 0
	while(TRUE)
		sleep(600)
		minutes++
		if(minutes == 15)
			ac_compare()
		if(!(minutes % 5))
			var/list/lines = list()
			for(var/name in GLOB.ac_calls)
				lines += "[name]: [GLOB.ac_calls[name]] calls, [round(GLOB.ac_ms[name])] ms"
			ac_log("[minutes] minutes in: [jointext(lines, "; ")]")

/world/New()
	. = ..()
	spawn(0)
		ac_run()
