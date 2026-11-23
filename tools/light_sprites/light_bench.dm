// Light sprites against lighting objects, one boot, a real client: pictures of the same spots each way, then map sending
// (SendMaps) and the client's frames (PresentMon) standing in the bar and running a hallway with a seclite. Objects, sprites,
// then objects again, so drift over the run shows.
// HARNESS=light_bench.dm PARAMS="lighting-lib=hippie_lighting_sprites" tools/light_sprites/run.sh bench
// (the real station: no MAP). Notes in data/lsp_bench.txt, pictures data/previews/lsp_bench_*, frames data/lsp_frames_bench_*.csv

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

GLOBAL_VAR_INIT(lsp_running, FALSE)
GLOBAL_VAR_INIT(lsp_prefix, world.params["lsp-prefix"] || "lsp_fine")

/proc/lsp_log(text)
	text2file(text, "data/keycheck.txt")

/proc/lsp_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/client/New()
	. = ..()
	if(. && !GLOB.lsp_running)
		GLOB.lsp_running = TRUE
		spawn(50)
			lsp_bench(src)

/// SendMaps' figures: name = list(value, calls, unit)
/proc/lsp_sendmaps()
	. = list()
	var/raw = world.Profile(PROFILE_REFRESH, "sendmaps", "json")
	if(!istext(raw) || findtext(raw, "\[") != 1)
		return
	for(var/list/R in json_decode(raw))
		.["[R["name"]]"] = list(R["value"], R["calls"], R["unit"])

/// Starts PresentMon on the client for `seconds` (run.sh does it), measures SendMaps meanwhile, waits for PresentMon to finish
/proc/lsp_measure(label, seconds)
	fdel("data/lsp_pm_done")
	text2file("[label] [seconds]", "data/lsp_pm_start")
	var/list/before = lsp_sendmaps()
	var/drawn_before = SSlighting.sprites_drawn
	var/loaded_before = SSlighting.lightmaps_loaded
	var/engine_before = SSlighting.sprites_engine_ms
	var/rebuilt_before = SSlighting.chunks_rebuilt
	var/rebuild_ms_before = SSlighting.chunks_rebuild_ms
	var/load_before = SSlighting.sprites_load_ms
	var/t0 = world.time
	var/rt0 = REALTIMEOFDAY
	sleep(seconds SECONDS)
	var/list/after = lsp_sendmaps()
	var/ticks = (world.time - t0) / world.tick_lag
	var/deadline = world.time + 20 SECONDS
	while(!fexists("data/lsp_pm_done") && world.time < deadline)
		sleep(2)
	lsp_log("[label]: [ticks] ticks in [(REALTIMEOFDAY - rt0) / 10] s; Lighting cost [round(SSlighting.cost, 0.01)] ms, Light Sprites [round(SSlight_sprites.cost, 0.001)] ms; chunks drawn [SSlighting.sprites_drawn - drawn_before], pictures loaded [SSlighting.lightmaps_loaded - loaded_before], engine [round(SSlighting.sprites_engine_ms - engine_before, 0.1)] ms, fcopy_rsc [round(SSlighting.sprites_load_ms - load_before, 0.1)] ms; chunk overlays rebuilt [SSlighting.chunks_rebuilt - rebuilt_before] in [round(SSlighting.chunks_rebuild_ms - rebuild_ms_before, 0.1)] ms")
	for(var/name in list("SendMaps", "SendMaps: Per client: Map data: Look for movable changes", \
		"SendMaps: Per client: Map data: Look for movable changes: Loop through turfs in range", \
		"SendMaps: Per client: Map data: Look for movable changes: Check HUD/image visual contents", \
		"SendMaps: Per client: Map data: Send obj changes", "SendMaps: Per client: Map data: Send changed turfs", \
		"SendMaps: Per client: Map data: Look for movable changes: Movables examined"))
		var/list/A = after[name]
		if(!A)
			continue
		var/list/B = before[name] || list(0, 0)
		var/dv = A[1] - B[1]
		lsp_log("  [replacetext(name, "SendMaps: Per client: Map data: ", "")]: [A[3] == "s" ? "[round(dv / ticks * 1e6, 0.1)] us" : "[round(dv / ticks, 0.1)]"] a tick")

/// A clear floor near the middle of the first station area of a type
/proc/lsp_spot(area_type)
	for(var/area/A in GLOB.sortedAreas)
		if(!istype(A, area_type))
			continue
		var/list/floors = list()
		var/sum_x = 0
		var/sum_y = 0
		for(var/turf/open/floor/T in A)
			if(!is_station_level(T.z))
				continue
			floors += T
			sum_x += T.x
			sum_y += T.y
		if(length(floors) < 12)
			continue
		var/mid_x = sum_x / length(floors)
		var/mid_y = sum_y / length(floors)
		var/turf/best
		var/best_dist = INFINITY
		for(var/turf/open/floor/T as anything in floors)
			if(T.density || (locate(/obj/structure) in T) || (locate(/obj/machinery) in T))
				continue
			var/dist = (T.x - mid_x) ** 2 + (T.y - mid_y) ** 2
			if(dist < best_dist)
				best_dist = dist
				best = T
		if(best)
			return best

/// A floor beside a working lamp in maintenance
/proc/lsp_lamp_spot(area_type)
	for(var/obj/machinery/light/L in world)
		if(!L.on || !is_station_level(L.z) || !istype(get_area(L), area_type))
			continue
		for(var/turf/open/floor/T in range(2, L))
			if(!T.density && !(locate(/obj/structure) in T) && !(locate(/obj/machinery) in T) && istype(T.loc, area_type))
				return T

/// The longest straight clear run from a turf, as list(direction, steps)
/proc/lsp_run(turf/from)
	var/best_dir = EAST
	var/best = 0
	for(var/d in GLOB.cardinals)
		var/n = 0
		var/turf/T = from
		while(n < 14)
			var/turf/next = get_step(T, d)
			if(!next || next.density || !istype(next, /turf/open/floor))
				break
			var/blocked = FALSE
			for(var/atom/movable/A in next)
				if(A.density)
					blocked = TRUE
					break
			if(blocked)
				break
			T = next
			n++
		if(n > best)
			best = n
			best_dir = d
	return list(best_dir, best)

GLOBAL_VAR_INIT(lsp_walking, FALSE)

/proc/lsp_walk(mob/living/carbon/human/H, turf/from, d, steps)
	set waitfor = FALSE
	GLOB.lsp_walking = TRUE
	H.forceMove(from)
	var/back = turn(d, 180)
	while(GLOB.lsp_walking)
		for(var/i in 1 to steps)
			if(!GLOB.lsp_walking)
				return
			H.set_glide_size(DELAY_TO_GLIDE_SIZE(1.5))
			step(H, d)
			sleep(1.5)
		for(var/i in 1 to steps)
			if(!GLOB.lsp_walking)
				return
			H.set_glide_size(DELAY_TO_GLIDE_SIZE(1.5))
			step(H, back)
			sleep(1.5)

/proc/lsp_bench(client/C)
	fdel("data/keycheck_shot")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	world.Profile(PROFILE_START, "sendmaps")
	lsp_log("hwmode [winget(C, null, "hwmode")], view [C.view], world.fps [world.fps], engine [SSlighting.native_status]")

	var/list/rooms = list(
		"bar" = /area/crew_quarters/bar,
		"medbay" = /area/medical/medbay/central,
		"maintenance" = /area/maintenance,
		"hallway" = /area/hallway/primary/central,
		"engineering" = /area/engine/engineering)
	var/list/spots = list()
	for(var/room in rooms)
		var/turf/T = room == "maintenance" ? lsp_lamp_spot(rooms[room]) : lsp_spot(rooms[room])
		if(T)
			spots[room] = T
			lsp_log("[room]: ([T.x],[T.y],[T.z]) in [get_area(T)]")
	var/turf/hall = spots["hallway"]
	var/list/run = lsp_run(hall)
	lsp_log("hallway run: [dir2text(run[1])] [run[2]] steps")

	var/mob/living/carbon/human/H = new(spots["bar"])
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	var/obj/item/flashlight/seclite/lamp = new(H)

	var/list/order = list("objects" = 0, "fine" = 3, "objects2" = 0)
	if(world.params["lsp-order"])
		order = params2list(world.params["lsp-order"])
		for(var/mode in order)
			order[mode] = text2num(order[mode])
	for(var/mode in order)
		var/why = SSlighting.set_sprites(order[mode])
		lsp_log("== [mode][why ? " (couldn't switch: [why])" : ""]")
		sleep(8 SECONDS)
		for(var/room in spots)
			H.forceMove(spots[room])
			sleep(15)
			lsp_shot("[GLOB.lsp_prefix]_[room]_[mode]")
		// A seclite in the dark: cone edges and the shadows it throws
		if(spots["maintenance"])
			H.forceMove(spots["maintenance"])
			H.put_in_hands(lamp)
			if(!lamp.on)
				lamp.attack_self(H)
			H.setDir(EAST)
			sleep(25)
			lsp_shot("[GLOB.lsp_prefix]_flashlight_[mode]")
			lamp.attack_self(H)
			H.dropItemToGround(lamp)
			lamp.forceMove(H)
		H.forceMove(spots["bar"])
		sleep(3 SECONDS)
		lsp_measure("[mode]_still", 15)
		// Running the hallway with a seclite on: a light that moves every step
		H.put_in_hands(lamp)
		if(!lamp.on)
			lamp.attack_self(H)
		lsp_walk(H, hall, run[1], run[2])
		sleep(2 SECONDS)
		lsp_measure("[mode]_walk", 20)
		GLOB.lsp_walking = FALSE
		lamp.attack_self(H)
		H.dropItemToGround(lamp)
		lamp.forceMove(H)
		sleep(1 SECONDS)
	lsp_log("done")
