// How often the game scans areas in a bot shift, what each scanning proc costs, and what the same reads cost from a plain list, on real station areas.
// Not part of the game. Needs AT_END=1 so it can wrap procs from any file:
// AT_END=1 SECONDS_LIMIT=1500 HARNESS=../area_scan/hippie_area.dm PARAMS="bot-shift=20&bot-crew=fill:20&bot-events=1&bot-quiet=1&timewarp=0" bash tools/byond_reports/ref_stall/hippie_check.sh
// world.tick_usage measures real CPU under timewarp, so the ms are real. A call that sleeps is counted but not timed.

GLOBAL_LIST_EMPTY(ac_calls)
GLOBAL_LIST_EMPTY(ac_ms)
GLOBAL_LIST_EMPTY(ac_worst_call)
GLOBAL_LIST_EMPTY(ac_tick_at)
GLOBAL_LIST_EMPTY(ac_tick_ms)
GLOBAL_LIST_EMPTY(ac_worst_tick)
GLOBAL_LIST_EMPTY(ac_slept)

/proc/ac_log(text)
	text2file(text, "data/ref_stall.txt")

/proc/ac_start()
	return list(world.tick_usage, world.time)

/proc/ac_stop(name, list/start)
	if(!GLOB.ac_calls || !GLOB.ac_ms)
		return
	GLOB.ac_calls[name] += 1
	if(world.time != start[2])
		GLOB.ac_slept[name] += 1
		return
	var/ms = (world.tick_usage - start[1]) * world.tick_lag
	GLOB.ac_ms[name] += ms
	GLOB.ac_worst_call[name] = max(GLOB.ac_worst_call[name], ms)
	if(GLOB.ac_tick_at[name] != world.time)
		GLOB.ac_tick_at[name] = world.time
		GLOB.ac_tick_ms[name] = 0
	GLOB.ac_tick_ms[name] += ms
	GLOB.ac_worst_tick[name] = max(GLOB.ac_worst_tick[name], GLOB.ac_tick_ms[name])

// Game procs that scan an area
/area/power_change()
	var/list/s = ac_start()
	. = ..()
	ac_stop("area/power_change", s)

/area/set_fire_alarm_effect()
	var/list/s = ac_start()
	. = ..()
	ac_stop("area/set_fire_alarm_effect", s)

/area/unset_fire_alarm_effects()
	var/list/s = ac_start()
	. = ..()
	ac_stop("area/unset_fire_alarm_effects", s)

/area/burglaralert()
	var/list/s = ac_start()
	. = ..()
	ac_stop("area/burglaralert", s)

/obj/machinery/airalarm/apply_danger_level()
	var/list/s = ac_start()
	. = ..()
	ac_stop("airalarm/apply_danger_level", s)

/obj/machinery/power/apc/set_nightshift()
	var/list/s = ac_start()
	. = ..()
	ac_stop("apc/set_nightshift", s)

/obj/machinery/power/apc/energy_fail()
	var/list/s = ac_start()
	. = ..()
	ac_stop("apc/energy_fail", s)

/obj/machinery/power/apc/break_lights()
	var/list/s = ac_start()
	. = ..()
	ac_stop("apc/break_lights", s)

/obj/machinery/light_switch/interact()
	var/list/s = ac_start()
	. = ..()
	ac_stop("light_switch/interact", s)

/mob/living/silicon/ai/start_RestorePowerRoutine()
	var/list/s = ac_start()
	. = ..()
	ac_stop("ai/start_RestorePowerRoutine", s)

/datum/controller/subsystem/job/SendToLateJoin()
	var/list/s = ac_start()
	. = ..()
	ac_stop("SSjob/SendToLateJoin", s)

/datum/controller/subsystem/mapping/generate_station_area_list()
	var/list/s = ac_start()
	. = ..()
	ac_stop("SSmapping/generate_station_area_list (boot)", s)

/obj/docking_port/mobile/getControlConsole()
	var/list/s = ac_start()
	. = ..()
	ac_stop("docking_port/getControlConsole", s)

/obj/docking_port/mobile/supply/buy()
	var/list/s = ac_start()
	. = ..()
	ac_stop("supply/buy", s)

/obj/docking_port/mobile/supply/sell()
	var/list/s = ac_start()
	. = ..()
	ac_stop("supply/sell", s)

/datum/round_event/aurora_caelus/tick()
	var/list/s = ac_start()
	. = ..()
	ac_stop("aurora_caelus/tick", s)

// Bot procs that scan an area
/datum/bot_brain/pick_poi_destination()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/pick_poi_destination", s)

/datum/bot_brain/nearest_spot_in()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/nearest_spot_in", s)

/datum/bot_brain/find_desk_chair()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/find_desk_chair", s)

/datum/bot_brain/pick_departures_spot()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/pick_departures_spot", s)

/datum/bot_brain/shuttle_floor_in_reach()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/shuttle_floor_in_reach", s)

/datum/bot_brain/pick_shuttle_seat()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/pick_shuttle_seat", s)

/datum/bot_brain/cargo_shuttle_floor()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/cargo_shuttle_floor", s)

/datum/bot_brain/crates_on_shuttle()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/crates_on_shuttle", s)

/datum/bot_brain/find_bay_spot()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/find_bay_spot", s)

/datum/bot_brain/crate_to_deliver()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/crate_to_deliver", s)

/datum/bot_brain/way_into()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/way_into", s)

/datum/bot_brain/find_kill_room()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/find_kill_room", s)

/datum/bot_brain/wizard_teleport_in()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/wizard_teleport_in", s)

/datum/bot_brain/directions_for()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/directions_for", s)

/datum/bot_silicon/ai/lock_down_around()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/ai lock_down_around", s)

/datum/bot_cult/rune_spot()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/cult rune_spot", s)

/datum/bot_cult/pick_summoner()
	var/list/s = ac_start()
	. = ..()
	ac_stop("bot/cult pick_summoner", s)

/proc/ac_ms_since(start)
	return (world.tick_usage - start) * world.tick_lag

/// The raw reads, timed on real areas: scans against plain lists of the same things, A.z against contents, `in` against loc, one world pass.
/proc/ac_compare()
	var/list/station = list()
	for(var/area/A as anything in GLOB.sortedAreas)
		if(A.z && is_station_level(A.z) && length(station) < 60)
			station += A

	// Machines, as area/power_change reads them
	var/scan_total = 0
	var/plain_total = 0
	var/found = 0
	for(var/area/A as anything in station)
		var/list/machines = list()
		var/t0 = world.tick_usage
		for(var/obj/machinery/M in A)
			machines += M
		scan_total += ac_ms_since(t0)
		sleep(1)
		var/list/copy = list()
		t0 = world.tick_usage
		for(var/obj/machinery/M as anything in machines)
			copy += M
		plain_total += ac_ms_since(t0)
		sleep(1)
		found += length(machines)
	ac_log("Machines: [length(station)] station areas, [found] machines: scan [round(scan_total / length(station), 0.001)] ms an area, plain list of the machines [round(plain_total / length(station), 0.001)] ms an area")

	// Turfs, as bot wander picks read them, and machines reached through a turf list (what a turf index alone would give)
	scan_total = 0
	plain_total = 0
	var/through_turfs = 0
	var/locate_total = 0
	var/turf_count = 0
	var/list/places = list()
	for(var/name in GLOB.teleportlocs)
		places += GLOB.teleportlocs[name]
	for(var/area/A as anything in places)
		var/list/turfs = list()
		var/t0 = world.tick_usage
		for(var/turf/T in A)
			turfs += T
		scan_total += ac_ms_since(t0)
		sleep(1)
		var/list/copy = list()
		t0 = world.tick_usage
		for(var/turf/T as anything in turfs)
			copy += T
		plain_total += ac_ms_since(t0)
		sleep(1)
		var/list/machines = list()
		t0 = world.tick_usage
		for(var/turf/T as anything in turfs)
			for(var/obj/machinery/M in T)
				machines += M
		through_turfs += ac_ms_since(t0)
		sleep(1)
		t0 = world.tick_usage
		var/turf/spot = locate(/turf/open) in A
		locate_total += ac_ms_since(t0)
		if(!spot)
			ac_log("no open turf found in [A]")
		sleep(1)
		turf_count += length(turfs)
	var/n = max(length(places), 1)
	ac_log("Turfs: [length(places)] teleportlocs areas, [round(turf_count / n)] turfs an area: scan [round(scan_total / n, 0.001)] ms, plain list [round(plain_total / n, 0.001)] ms, machines via the turf list [round(through_turfs / n, 0.001)] ms, locate(/turf/open) in area [round(locate_total / n, 0.0001)] ms")

	// Boot: contents.len and contents\[1] on every area, as generate_station_area_list() and process_teleport_locs() do, against A.z
	var/contents_total = 0
	var/z_total = 0
	var/dynamic_scan = 0
	var/dynamic_areas = 0
	var/dynamic_turfs = 0
	var/starlight_areas = 0
	for(var/area/A as anything in GLOB.sortedAreas)
		var/t0 = world.tick_usage
		var/turf/first = length(A.contents) ? A.contents[1] : null
		contents_total += ac_ms_since(t0)
		t0 = world.tick_usage
		var/z = A.z
		z_total += ac_ms_since(t0)
		if((first ? first.z : 0) != z)
			ac_log("A.z differs from contents\[1]: [A.type] [first ? first.z : 0] vs [z]")
		if(IS_DYNAMIC_LIGHTING(A))
			dynamic_areas++
			t0 = world.tick_usage
			for(var/turf/T in A)
				dynamic_turfs++
			dynamic_scan += ac_ms_since(t0)
		if(initial(A.dynamic_lighting) == DYNAMIC_LIGHTING_IFSTARLIGHT)
			starlight_areas++
		CHECK_TICK
	ac_log("Boot: [length(GLOB.sortedAreas)] areas: contents.len plus contents\[1] on each [round(contents_total)] ms in all, A.z on each [round(z_total, 0.01)] ms; [dynamic_areas] dynamic-lit areas ([dynamic_turfs] turfs), for(turf in area) over them [round(dynamic_scan)] ms; [starlight_areas] starlight areas")
	sleep(1)
	var/t0 = world.tick_usage
	var/world_turfs = 0
	for(var/turf/T in world)
		world_turfs++
	ac_log("One for(turf in world) pass: [world_turfs] turfs, [round(ac_ms_since(t0), 0.1)] ms")
	sleep(1)

	// `T in area` (onCentCom) against T.loc == area
	var/area/A = station[1]
	var/turf/last
	for(var/turf/T in A)
		last = T
	t0 = world.tick_usage
	for(var/i in 1 to 100)
		if(!(last in A))
			ac_log("T in A was false")
	var/in_ms = ac_ms_since(t0) / 100
	t0 = world.tick_usage
	for(var/i in 1 to 100)
		if(last.loc != A)
			ac_log("T.loc == A was false")
	ac_log("T in area [round(in_ms, 0.0001)] ms, T.loc == area [round(ac_ms_since(t0) / 100, 0.0001)] ms ([A.type])")

// The two boot procs as they were before they read A.z, to time against the real ones in the same boot and check they agree.
/proc/ac_old_station_areas()
	var/list/result = list()
	var/list/station_areas_blacklist = typecacheof(list(/area/space, /area/mine, /area/ruin, /area/asteroid/nearstation))
	for(var/area/A in world)
		if (is_type_in_typecache(A, station_areas_blacklist))
			continue
		if (!A.contents.len || !A.unique)
			continue
		var/turf/picked = A.contents[1]
		if (is_station_level(picked.z))
			result += A.type
	return result

/proc/ac_old_teleport_locs()
	var/list/result = list()
	for(var/area/AR as anything in GLOB.sortedAreas)
		if(istype(AR, /area/shuttle) || AR.noteleport)
			continue
		if(result[AR.name])
			continue
		if (!AR.contents.len)
			continue
		var/turf/picked = AR.contents[1]
		if (picked && is_station_level(picked.z))
			result[AR.name] = AR
	sortTim(result, /proc/cmp_text_dsc)
	return result

/proc/ac_same(list/a, list/b, keyed)
	if(length(a) != length(b))
		return FALSE
	for(var/i in 1 to length(a))
		if(a[i] != b[i] || (keyed && a[a[i]] != b[b[i]]))
			return FALSE
	return TRUE

/proc/ac_boot_check()
	var/t0 = world.tick_usage
	var/list/old_station = ac_old_station_areas()
	var/old_station_ms = ac_ms_since(t0)
	sleep(1)
	var/list/saved = GLOB.the_station_areas
	GLOB.the_station_areas = list()
	t0 = world.tick_usage
	SSmapping.generate_station_area_list()
	var/new_station_ms = ac_ms_since(t0)
	var/list/new_station = GLOB.the_station_areas
	GLOB.the_station_areas = saved
	ac_log("generate_station_area_list: before [round(old_station_ms, 0.1)] ms, now [round(new_station_ms, 0.1)] ms, [length(new_station)] areas, [ac_same(old_station, new_station) ? "same result" : "DIFFERENT RESULT"]")
	sleep(1)
	t0 = world.tick_usage
	var/list/old_locs = ac_old_teleport_locs()
	var/old_locs_ms = ac_ms_since(t0)
	sleep(1)
	saved = GLOB.teleportlocs
	GLOB.teleportlocs = list()
	t0 = world.tick_usage
	process_teleport_locs()
	var/new_locs_ms = ac_ms_since(t0)
	var/list/new_locs = GLOB.teleportlocs
	GLOB.teleportlocs = saved
	ac_log("process_teleport_locs: before [round(old_locs_ms, 0.1)] ms, now [round(new_locs_ms, 0.1)] ms, [length(new_locs)] areas, [ac_same(old_locs, new_locs, TRUE) ? "same result" : "DIFFERENT RESULT"]")

/// Wander picks: every pick the new way must be one the old way could make, and come up empty only when the old way would.
/proc/ac_bot_check()
	var/datum/bot_brain/B
	for(var/datum/bot_brain/X as anything in GLOB.bot_brains)
		if(!QDELETED(X) && X.owner && isturf(X.owner.loc))
			B = X
			break
	if(!B)
		ac_log("Wander picks: no bot to check with")
		return
	var/old_ms = 0
	var/new_ms = 0
	var/picks = 0
	var/wrong = 0
	var/empty_wrong = 0
	var/list/places = list()
	for(var/name in GLOB.teleportlocs)
		places += GLOB.teleportlocs[name]
	for(var/area/AR as anything in places)
		var/t0 = world.tick_usage
		var/list/candidates = list()
		var/list/chair_candidates = list()
		for(var/turf/T in AR)
			if(!B.is_wanderable_turf(T))
				continue
			candidates += T
			if(locate(/obj/structure/chair) in T)
				chair_candidates += T
		old_ms += ac_ms_since(t0)
		sleep(1)
		for(var/i in 1 to 20)
			t0 = world.tick_usage
			var/list/turfs = bot_area_turfs(AR)
			var/turf/picked
			var/list/chair_turfs = list()
			if(i % 2)
				for(var/turf/T as anything in turfs)
					if(locate(/obj/structure/chair) in T)
						chair_turfs += T
				picked = B.random_wanderable_turf(chair_turfs, AR)
				if(picked && !(picked in chair_candidates))
					wrong++
				if(!picked && length(chair_candidates))
					empty_wrong++
			if(!picked)
				picked = B.random_wanderable_turf(turfs.Copy(), AR)
				if(picked && !(picked in candidates))
					wrong++
				if(!picked && length(candidates))
					empty_wrong++
			new_ms += ac_ms_since(t0)
			picks++
		CHECK_TICK
	// Department areas: the cached matches against matching every name, as pick_department_biased_area() used to
	var/roles_differ = 0
	var/old_match_ms = 0
	var/new_match_ms = 0
	var/list/keyword_lists = list()
	for(var/role in GLOB.bot_department_keywords)
		keyword_lists += list(list(GLOB.bot_department_keywords[role], null))
	keyword_lists += list(list(GLOB.bot_common_area_keywords, "Maintenance"))
	for(var/list/pair in keyword_lists)
		var/list/keywords = pair[1]
		var/unwanted = pair[2]
		var/t0 = world.tick_usage
		var/list/old_matches = list()
		for(var/area_name in GLOB.teleportlocs)
			if(unwanted && findtext(area_name, unwanted))
				continue
			for(var/keyword in keywords)
				if(findtext(area_name, keyword))
					old_matches += GLOB.teleportlocs[area_name]
					break
		old_match_ms += ac_ms_since(t0)
		t0 = world.tick_usage
		var/list/new_matches = bot_areas_matching(keywords, unwanted)
		new_match_ms += ac_ms_since(t0)
		if(!ac_same(old_matches, new_matches))
			roles_differ++
	ac_log("Department areas for [length(keyword_lists)] keyword lists: matching names [round(old_match_ms / length(keyword_lists), 0.001)] ms, cached [round(new_match_ms / length(keyword_lists), 0.001)] ms, [roles_differ] differ")
	ac_log("Wander picks over [length(places)] areas: old way [round(old_ms / length(places), 0.001)] ms a pick, new way [round(new_ms / picks, 0.001)] ms a pick (cached turfs, first pick of each area reads them), [picks] picks, [wrong] not in the old candidates, [empty_wrong] empty where the old way had some")

/proc/ac_report(minutes)
	var/list/names = GLOB.ac_ms.Copy()
	for(var/name in GLOB.ac_calls)
		if(!(name in names))
			names[name] = 0
	names = sortTim(names, /proc/cmp_numeric_dsc, TRUE)
	ac_log("[minutes] minutes in (calls, ms in all, worst call ms, worst tick ms, slept):")
	for(var/name in names)
		ac_log("  [name]: [GLOB.ac_calls[name]] calls, [round(GLOB.ac_ms[name], 0.1)] ms, worst [round(GLOB.ac_worst_call[name], 0.01)], worst tick [round(GLOB.ac_worst_tick[name], 0.01)][GLOB.ac_slept[name] ? ", [GLOB.ac_slept[name]] slept" : ""]")

/proc/ac_run()
	UNTIL(SSticker.initialized)
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	ac_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks, [world.maxx * world.maxy * world.maxz] turfs")
	ac_report("Boot and round start: 0")
	var/minutes = 0
	while(minutes < 17) // the shift ends the world at 20 minutes, counted from a little before this
		sleep(600)
		minutes++
		if(minutes == 10)
			ac_compare()
			ac_boot_check()
			ac_bot_check()
		if(!(minutes % 5))
			ac_report(minutes)
	ac_report(minutes)
	ac_log("done")

/world/New()
	. = ..()
	spawn(0)
		ac_run()
