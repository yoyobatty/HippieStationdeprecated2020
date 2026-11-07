// Things that happen to a station in a round, done the same way on the old and new smoothing builds, before the
// harness counts every smoothing atom showing something other than what it would get if smoothed now (stale).
// Included by smooth_dump_old.dm and smooth_check_new.dm when the boot params have scenario=1. Each defines
// smooth_shown(atom) (what an atom shows, as a junction). Targets are picked in map order, so both builds hit the same ones.

GLOBAL_LIST_EMPTY(scenario_lines)

/proc/scenario_station_turfs()
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	return block(locate(1, 1, z), locate(world.maxx, world.maxy, z))

/proc/stale_scenario_run()
	var/list/station = scenario_station_turfs()
	// 1. shuttle airlocks go (titanium and plastitanium walls join airlocks)
	var/gone = 0
	for(var/z in 1 to world.maxz)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/obj/machinery/door/airlock/A = locate() in T
			if(!A || !istype(get_area(A), /area/shuttle))
				continue
			if(!(locate(/turf/closed/wall/mineral/titanium) in orange(1, T)) && !(locate(/turf/closed/wall/mineral/plastitanium) in orange(1, T)))
				continue
			qdel(A)
			gone++
			if(gone >= 12)
				break
		if(gone >= 12)
			break
	GLOB.scenario_lines += "removed [gone] shuttle airlocks next to titanium/plastitanium walls"

	// 2. three bombs by reinforced windows
	var/list/windows = list()
	for(var/turf/T as anything in station)
		if(locate(/obj/structure/window/reinforced/fulltile) in T)
			windows += T
	var/bombs = 0
	for(var/i in list(20, round(length(windows) / 2), length(windows) - 20))
		if(i < 1 || i > length(windows))
			continue
		explosion(windows[i], 1, 2, 4, silent = TRUE)
		bombs++
	GLOB.scenario_lines += "[bombs] bombs (1/2/4) by reinforced windows, of [length(windows)]"

	// 3. a reinforced wall half taken apart, then put back
	for(var/turf/closed/wall/r_wall/R in station)
		if(R.type != /turf/closed/wall/r_wall)
			continue
		R.d_state = SUPPORT_LINES
		R.update_icon()
		sleep(3)
		R.d_state = INTACT
		R.update_icon()
		GLOB.scenario_lines += "reinforced wall at [R.x] [R.y] cut and welded back"
		break

	// 4. three windows built in a row in a hallway and wrenched down, as a player does
	var/list/row
	for(var/turf/open/floor/T in station)
		if(!istype(get_area(T), /area/hallway))
			continue
		var/turf/T2 = get_step(T, EAST)
		var/turf/T3 = get_step(T2, EAST)
		if(!isfloorturf(T2) || !isfloorturf(T3))
			continue
		if(is_blocked_turf(T, TRUE) || is_blocked_turf(T2, TRUE) || is_blocked_turf(T3, TRUE))
			continue
		row = list(T, T2, T3)
		break
	var/list/built = list()
	for(var/turf/T as anything in row)
		var/obj/structure/window/W = new /obj/structure/window/fulltile/unanchored(T)
		W.setAnchored(TRUE)
		built += W
	sleep(10)
	UNTIL(!length(SSicon_smooth.smooth_queue))
	sleep(5)
	var/list/shown = list()
	for(var/obj/structure/window/W as anything in built)
		shown += "[smooth_shown(W)]"
	GLOB.scenario_lines += "3 built windows in a row show [shown.Join(", ")] (joined both sides is 12, one side 4 or 8)"

	// let the bombs finish and everything that was asked to smooth do so
	sleep(10 SECONDS)
	UNTIL(!length(SSicon_smooth.smooth_queue))
	sleep(2 SECONDS)
