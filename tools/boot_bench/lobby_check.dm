// Lobby build check (hippiestation/code/controllers/subsystem/lobby_build.dm): once Lavaland and the space ruin levels are
// built after startup, everything on them has to be as startup would have left it. Run with lobby-build=off too: the same
// checks then cover startup's own build, for comparison.
//
// Run:      tools/boot_bench/run_lobby_check.sh   (OFF=1 for the startup build)
// Results:  data/lobby_check/results.txt

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("lobby-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_lobby_check))
	return ..()

#define LOBBY_CHECK_DIR "data/lobby_check/"

/datum/lobby_check
	var/list/lines = list()
	var/passed = 0
	var/failed = 0

/datum/lobby_check/proc/check(name, ok, detail = "")
	if(ok)
		passed++
		lines += "PASS [name][detail ? ": [detail]" : ""]"
	else
		failed++
		lines += "FAIL [name][detail ? ": [detail]" : ""]"

/proc/run_lobby_check()
	var/datum/lobby_check/C = new
	var/began = REALTIMEOFDAY
	UNTIL(Master.current_runlevel || REALTIMEOFDAY > began + 1200)
	var/build_wait_start = REALTIMEOFDAY
	UNTIL(!SSmapping.lobby_build_busy || REALTIMEOFDAY > build_wait_start + 1800)
	C.lines += "lobby build: [SSmapping.lobby_build_status], waited [(REALTIMEOFDAY - build_wait_start) / 10]s after startup"
	C.check("build finished", !SSmapping.lobby_build_busy)
	sleep(5 SECONDS) // smoothing, lighting and air settle

	var/list/levels = list()
	if(SSmapping.lobby_build_lavaland_z)
		levels += SSmapping.lobby_build_lavaland_z
	else
		levels += SSmapping.levels_by_trait(ZTRAIT_MINING)
	var/list/space_levels = SSmapping.levels_by_trait(ZTRAIT_SPACE_RUINS)
	levels |= space_levels
	C.lines += "levels checked: [jointext(levels, ", ")] (lavaland [jointext(SSmapping.levels_by_trait(ZTRAIT_MINING), ",")])"

	var/uninit = 0
	var/list/uninit_types = list()
	var/turfs = 0
	var/things = 0
	var/dynamic = 0
	var/lit = 0
	var/push_wrong = 0
	var/open_no_air = 0
	var/open_no_adjacent = 0
	var/open_turfs = 0
	var/smooth_checked = 0
	var/smooth_changed = 0
	var/list/smooth_changed_types = list()
	var/cables = 0
	var/cables_no_net = 0
	var/pipes = 0
	var/pipes_no_net = 0
	var/mobs = 0
	var/list/type_counts = list()
	for(var/z in levels)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			turfs++
			if(!(T.flags_1 & INITIALIZED_1))
				uninit++
				uninit_types[T.type]++
			var/area/A = T.loc
			if(IS_DYNAMIC_LIGHTING(A) && IS_DYNAMIC_LIGHTING(T))
				dynamic++
				if(T.lighting_object)
					lit++
			if(SSlighting.native_flags_ready && T.lighting_engine_pushed != T.lighting_engine_flags())
				push_wrong++
			if(isopenturf(T) && !isspaceturf(T) && !T.blocks_air)
				open_turfs++
				var/turf/open/O = T
				if(!O.air)
					open_no_air++
				// What it has against what working them out again gives
				var/list/had = O.atmos_adjacent_turfs ? O.atmos_adjacent_turfs.Copy() : list()
				O.ImmediateCalculateAdjacentTurfs()
				var/list/now = O.atmos_adjacent_turfs || list()
				if(length(had) != length(now) || length(had - now))
					open_no_adjacent++
			if(T.smoothing_flags && (T.flags_1 & INITIALIZED_1))
				var/before = "[T.icon_state]|[T.smoothing_junction]"
				T.smooth_icon()
				smooth_checked++
				if("[T.icon_state]|[T.smoothing_junction]" != before)
					smooth_changed++
					smooth_changed_types[T.type]++
			for(var/atom/movable/AM as anything in T)
				if(istype(AM, /atom/movable/lighting_object))
					continue
				things++
				type_counts[AM.type]++
				if(!(AM.flags_1 & INITIALIZED_1))
					uninit++
					uninit_types[AM.type]++
				if(ismob(AM))
					mobs++
				if(istype(AM, /obj/structure/cable))
					cables++
					var/obj/structure/cable/W = AM
					if(!W.powernet)
						cables_no_net++
				if(istype(AM, /obj/machinery/atmospherics/pipe))
					pipes++
					var/obj/machinery/atmospherics/pipe/P = AM
					if(!P.parent)
						pipes_no_net++
			CHECK_TICK
	var/list/worst = list()
	for(var/t in uninit_types)
		worst += "[t] x[uninit_types[t]]"
	C.lines += "[turfs] turfs, [things] things, [mobs] mobs, [open_turfs] open turfs, [dynamic] dynamically lit turfs"
	C.check("everything initialized", !uninit, "[uninit] not: [jointext(worst.Copy(1, min(6, length(worst) + 1)), ", ")]")
	C.check("lighting objects on lit turfs", lit == dynamic, "[lit] of [dynamic]")
	C.check("lighting engine told of every turf", !push_wrong, "[push_wrong] wrong")
	C.check("open turfs have air", !open_no_air, "[open_no_air] of [open_turfs] without")
	C.check("open turfs know their neighbours", !open_no_adjacent, "[open_no_adjacent] differ when worked out again")
	var/list/smooth_types = list()
	for(var/t in smooth_changed_types)
		smooth_types += "[t] x[smooth_changed_types[t]]"
	C.check("smoothing settled", !smooth_changed, "[smooth_changed] of [smooth_checked] changed when redone: [jointext(smooth_types.Copy(1, min(6, length(smooth_types) + 1)), ", ")]")
	C.check("cables in powernets", !cables_no_net, "[cables_no_net] of [cables] without")
	C.check("pipes in pipenets", !pipes_no_net, "[pipes_no_net] of [pipes] without")
	C.check("Lavaland has its things", things > 2000 && mobs > 10, "[things] things, [mobs] mobs")
	for(var/dock in list("mining_away", "laborcamp_away", "whiteship_lavaland"))
		C.check("dock [dock] registered", !!SSshuttle.getDock(dock))
	// The escape pods' random landing spots, placed once Lavaland is there
	var/list/lavaland_levels = SSmapping.levels_by_trait(ZTRAIT_MINING)
	var/pods = 0
	var/pods_off = 0
	for(var/obj/docking_port/stationary/random/R in SSshuttle.stationary)
		pods++
		if(!(R.z in lavaland_levels))
			pods_off++
	C.check("escape pod landing spots on Lavaland", pods && !pods_off, "[pods - pods_off] of [pods]")
	var/area_missing = 0
	for(var/area/A in GLOB.sortedAreas)
		if(!A.z || !(A.z in levels))
			continue
		var/list/in_z = SSmapping.areas_in_z["[A.z]"]
		if(!(A in in_z))
			area_missing++
	C.check("areas registered on their level", !area_missing, "[area_missing] missing")
	var/active_held = 0
	for(var/turf/T as anything in SSair.active_turfs)
		if(T.z in levels)
			active_held++
	C.lines += "active air turfs on the levels: [active_held]"

	// Air neighbours everywhere else (the station's are set up by SSair at startup): worked out again, nothing changes
	var/elsewhere_checked = 0
	var/elsewhere_differ = 0
	var/list/elsewhere_at = list()
	for(var/z in 1 to world.maxz)
		if(z in levels)
			continue
		for(var/turf/open/O in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			if(isspaceturf(O) || O.blocks_air)
				continue
			elsewhere_checked++
			var/list/had = O.atmos_adjacent_turfs ? O.atmos_adjacent_turfs.Copy() : list()
			var/had_super = O.atmos_supeconductivity
			O.ImmediateCalculateAdjacentTurfs()
			var/list/now = O.atmos_adjacent_turfs || list()
			if(length(had) != length(now) || length(had - now) || had_super != O.atmos_supeconductivity)
				elsewhere_differ++
				if(length(elsewhere_at) < 5)
					var/list/inside = list()
					for(var/atom/movable/AM as anything in O)
						inside += "[AM.type]"
					var/list/gained = list()
					for(var/turf/G in now - had)
						gained += "+[G.x],[G.y]"
					for(var/turf/L in had - now)
						gained += "-[L.x],[L.y]"
					elsewhere_at += "[O.x],[O.y],[O.z] [O.type] {[jointext(inside, " ")]} [jointext(gained, " ")] super [had_super]->[O.atmos_supeconductivity]"
		CHECK_TICK
	C.check("air neighbours on the other levels", !elsewhere_differ, "[elsewhere_differ] of [elsewhere_checked] differ when worked out again[length(elsewhere_at) ? " (at [jointext(elsewhere_at, " ")])" : ""]")

	// Lighting settled: every light on these levels worked out again from scratch, and no lighting object there changes
	var/list/drawn = list()
	for(var/z in levels)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/atom/movable/lighting_object/O = T.lighting_object
			if(O)
				drawn[O] = "[O.icon_state]|[islist(O.color) ? jointext(O.color, ",") : O.color]"
		CHECK_TICK
	var/relit = 0
	for(var/datum/light_source/L)
		if(L.source_turf && (L.source_turf.z in levels))
			L.force_update()
			relit++
	var/settle_start = REALTIMEOFDAY
	sleep(1 SECONDS)
	UNTIL((!length(SSlighting.sources_queue) && !length(SSlighting.corners_queue) && !length(SSlighting.objects_queue)) || REALTIMEOFDAY > settle_start + 600)
	sleep(1 SECONDS)
	var/redrawn = 0
	var/list/redrawn_at = list()
	for(var/atom/movable/lighting_object/O as anything in drawn)
		if(QDELETED(O))
			continue
		if(drawn[O] != "[O.icon_state]|[islist(O.color) ? jointext(O.color, ",") : O.color]")
			redrawn++
			if(length(redrawn_at) < 5)
				redrawn_at += "[O.x],[O.y],[O.z]"
	C.check("lighting settled", !redrawn, "[redrawn] of [length(drawn)] lighting objects changed when [relit] lights were worked out again[length(redrawn_at) ? " (at [jointext(redrawn_at, " ")])" : ""]")

	// The round starts once it's done
	SSticker.start_immediately = TRUE
	var/start_wait = REALTIMEOFDAY
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING || REALTIMEOFDAY > start_wait + 1200)
	C.check("round started", SSticker.current_state >= GAME_STATE_PLAYING, "after [(REALTIMEOFDAY - start_wait) / 10]s")

	var/list/top = list()
	for(var/t in type_counts)
		top += list(list(t, type_counts[t]))
	C.lines.Insert(1, "[C.passed] passed, [C.failed] failed")
	text2file(jointext(C.lines, "\n"), "[LOBBY_CHECK_DIR]results.txt")
	var/list/count_lines = list()
	for(var/t in type_counts)
		count_lines += "[t]\t[type_counts[t]]"
	text2file(jointext(count_lines, "\n"), "[LOBBY_CHECK_DIR]type_counts.txt")
	log_world("LOBBY CHECK: done, [C.passed] passed, [C.failed] failed")
	Master.Shutdown()
	qdel(world)

#undef LOBBY_CHECK_DIR
