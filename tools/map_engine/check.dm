// Native map parser check: every .dmm under _maps is parsed by DM (reader.dm) and by hippie_map.dll, and everything the
// parse makes is compared: key length, bounds (also measured only, and cropped), grid_models, the coordinate blocks, the
// model cache with and without no_changeturf, and the bad paths map verification finds. Also times both.
//
// Run:      tools/map_engine/run_check.sh
// Results:  data/map_engine_check/results.txt

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("map-engine-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_map_engine_check))
	return ..()

#define MAP_CHECK_DIR "data/map_engine_check/"

/proc/map_check_files(dir)
	. = list()
	for(var/entry in flist(dir))
		if(copytext(entry, -1) == "/")
			. += map_check_files("[dir][entry]")
		else if(copytext(entry, -4) == ".dmm")
			. += "[dir][entry]"

/// Null when a and b are the same, or where they first differ
/proc/map_check_diff(a, b, where)
	if(islist(a) || islist(b))
		if(!islist(a) || !islist(b))
			return "[where]: list vs not a list"
		var/list/la = a
		var/list/lb = b
		if(la.len != lb.len)
			return "[where]: length [la.len] vs [lb.len]"
		for(var/i in 1 to la.len)
			var/ka = la[i]
			var/kb = lb[i]
			. = map_check_diff(ka, kb, "[where]\[[i]\]")
			if(.)
				return
			if(!isnum(ka) && !isnull(ka))
				. = map_check_diff(la[ka], lb[kb], "[where]\[[ka]\]")
				if(.)
					return
		return null
	if(isfile(a) || isfile(b))
		return (isfile(a) && isfile(b) && "[a]" == "[b]") ? null : "[where]: file [a] vs [b]"
	if(a != b)
		return "[where]: [isnull(a) ? "null" : "[a]"] vs [isnull(b) ? "null" : "[b]"]"
	return null

/proc/map_check_parse(path, native, measure = FALSE, list/crop = null)
	GLOB.map_engine_off = !native
	if(crop)
		. = new /datum/parsed_map(file(path), crop[1], crop[2], crop[3], crop[4], measure)
	else
		. = new /datum/parsed_map(file(path), measureOnly = measure)
	GLOB.map_engine_off = FALSE

/proc/run_map_engine_check()
	sleep(2 SECONDS)
	fdel(MAP_CHECK_DIR)
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	if(!map_engine_lib())
		lines += "FAIL no usable hippie_map library"
		failed++
	var/list/files = map_check_files("_maps/")
	var/dm_us = 0
	var/native_us = 0
	var/native_parse_us = 0
	var/list/slowest = list()
	var/dm_measure_us = 0
	var/native_measure_us = 0
	for(var/path in files)
		var/list/problems = list()

		rustg_time_reset("mapcheck")
		var/datum/parsed_map/old = map_check_parse(path, FALSE)
		old.build_cache(FALSE)
		dm_us += rustg_time_microseconds("mapcheck")
		rustg_time_reset("mapcheck")
		var/datum/parsed_map/new_map = map_check_parse(path, TRUE)
		var/parse_part = rustg_time_microseconds("mapcheck")
		native_parse_us += parse_part
		new_map.build_cache(FALSE)
		native_us += rustg_time_microseconds("mapcheck")
		var/list/timing = list("[path]", parse_part, rustg_time_microseconds("mapcheck"))
		slowest += list(timing)
		if(!new_map.native_split)
			problems += "not parsed natively"

		var/list/checks = list(
			"key_len" = list(old.key_len, new_map.key_len),
			"bounds" = list(old.bounds, new_map.bounds),
			"parsed_bounds" = list(old.parsed_bounds, new_map.parsed_bounds),
			"original_path" = list(old.original_path, new_map.original_path),
			"grid_models" = list(old.grid_models, new_map.grid_models),
			"modelCache" = list(old.modelCache, new_map.modelCache),
		)
		for(var/name in checks)
			var/list/pair = checks[name]
			var/diff = map_check_diff(pair[1], pair[2], name)
			if(diff)
				problems += diff

		if(length(old.gridSets) != length(new_map.gridSets))
			problems += "gridSets: [length(old.gridSets)] vs [length(new_map.gridSets)]"
		else
			for(var/i in 1 to length(old.gridSets))
				var/datum/grid_set/a = old.gridSets[i]
				var/datum/grid_set/b = new_map.gridSets[i]
				var/diff = map_check_diff(list(a.xcrd, a.ycrd, a.zcrd, a.gridLines), list(b.xcrd, b.ycrd, b.zcrd, b.gridLines), "gridSets\[[i]\]")
				if(diff)
					problems += diff
					break

		// no_changeturf's cache, and the bad paths verification finds
		old.modelCache = null
		new_map.modelCache = null
		var/list/old_bad = list()
		var/list/new_bad = list()
		var/diff = map_check_diff(old.build_cache(TRUE, old_bad), new_map.build_cache(TRUE, new_bad), "modelCache(no_changeturf)")
		if(diff)
			problems += diff
		diff = map_check_diff(old_bad, new_bad, "bad_paths")
		if(diff)
			problems += diff

		// Measured only, as every map template is at init
		rustg_time_reset("mapcheck")
		var/datum/parsed_map/old_measure = map_check_parse(path, FALSE, TRUE)
		dm_measure_us += rustg_time_microseconds("mapcheck")
		rustg_time_reset("mapcheck")
		var/datum/parsed_map/new_measure = map_check_parse(path, TRUE, TRUE)
		native_measure_us += rustg_time_microseconds("mapcheck")
		diff = map_check_diff(old_measure.bounds, new_measure.bounds, "measured bounds")
		if(diff)
			problems += diff
		diff = map_check_diff(old_measure.key_len, new_measure.key_len, "measured key_len")
		if(diff)
			problems += diff

		// Cropped, as the repair map generator loads them
		if(old.bounds)
			var/list/crop = list(2, max(2, old.bounds[MAP_MAXX] - 3), 3, max(3, old.bounds[MAP_MAXY] - 2))
			var/datum/parsed_map/old_crop = map_check_parse(path, FALSE, FALSE, crop)
			var/datum/parsed_map/new_crop = map_check_parse(path, TRUE, FALSE, crop)
			diff = map_check_diff(old_crop.bounds, new_crop.bounds, "cropped bounds")
			if(diff)
				problems += diff
			if(length(old_crop.gridSets) != length(new_crop.gridSets))
				problems += "cropped gridSets: [length(old_crop.gridSets)] vs [length(new_crop.gridSets)]"
			qdel(old_crop)
			qdel(new_crop)

		if(length(problems))
			failed++
			lines += "FAIL [path]: [jointext(problems, "; ")]"
		else
			passed++
		qdel(old)
		qdel(new_map)
		qdel(old_measure)
		qdel(new_measure)
		CHECK_TICK

	for(var/probe in list("_maps/map_files/HippieStation/hippiestation.dmm", "_maps/map_files/Mining/Lavaland.dmm"))
		rustg_time_reset("mapprobe")
		var/raw = call_ext(map_engine_lib(), "map_parse")(probe, "0", "", "", "", "")
		var/t_dll = rustg_time_microseconds("mapprobe")
		rustg_time_reset("mapprobe")
		var/list/decoded = json_decode(raw)
		var/t_json = rustg_time_microseconds("mapprobe")
		lines += "probe [probe]: DLL [round(t_dll / 1000, 0.1)] ms, json_decode [round(t_json / 1000, 0.1)] ms, [length(raw)] chars, [length(decoded["models"])] models"
	// The loader's shortcut for plain turf-and-area tiles: each map loaded onto a fresh level with and without it, as startup
	// loads them (no_changeturf), and every tile compared
	for(var/load_path in list("_maps/map_files/HippieStation/hippiestation.dmm", "_maps/map_files/Mining/Lavaland.dmm", "_maps/map_files/MetaStation/MetaStation.dmm", "_maps/RandomRuins/SpaceRuins/TheDerelict.dmm", "_maps/RandomRuins/LavaRuins/lavaland_surface_seed_vault.dmm"))
		if(!fexists(load_path))
			lines += "FAIL load [load_path]: no such map"
			failed++
			continue
		var/list/pictures = list()
		var/list/took = list()
		for(var/shortcut in list(FALSE, TRUE))
			map_loader_simple_tiles = shortcut
			var/datum/space_level/level = SSmapping.add_new_zlevel("map check [shortcut]", list(ZTRAIT_AWAY = TRUE))
			var/datum/parsed_map/loading = new(file(load_path))
			rustg_time_reset("mapload")
			loading.load(1, 1, level.z_value, cropMap = TRUE, no_changeturf = TRUE)
			took += round(rustg_time_microseconds("mapload") / 1000)
			var/list/picture = list()
			for(var/turf/T as anything in block(locate(1, 1, level.z_value), locate(world.maxx, world.maxy, level.z_value)))
				var/list/inside = list()
				for(var/atom/movable/AM as anything in T)
					inside += "[AM.type]"
				picture += "[T.type]|[T.loc.type]|[T.name]|[T.icon_state]|[T.dir]|[jointext(inside, ",")]"
			pictures += list(picture)
			qdel(loading)
		map_loader_simple_tiles = TRUE
		var/list/a = pictures[1]
		var/list/b = pictures[2]
		var/differ = 0
		var/first = ""
		for(var/i in 1 to min(length(a), length(b)))
			if(a[i] != b[i])
				differ++
				if(!first)
					first = " (tile [i]: [a[i]] vs [b[i]])"
		if(differ || length(a) != length(b))
			failed++
			lines += "FAIL load [load_path]: [differ] tiles differ[first]"
		else
			passed++
			lines += "load [load_path]: same, [length(a)] tiles, [took[2]] ms with the shortcut, [took[1]] ms without (without loaded first)"
		CHECK_TICK

	lines.Insert(1, "[passed] passed, [failed] failed of [length(files)] maps")
	lines.Insert(2, "parse + model cache: DM [round(dm_us / 1000)] ms, native [round(native_us / 1000)] ms")
	lines.Insert(3, "native parse part (DLL + json_decode + objects): [round(native_parse_us / 1000)] ms")
	sortTim(slowest, GLOBAL_PROC_REF(cmp_map_check_slow))
	for(var/i in 1 to min(8, length(slowest)))
		var/list/entry = slowest[i]
		lines += "slow: [entry[1]] parse [round(entry[2] / 1000, 0.1)] ms, with cache [round(entry[3] / 1000, 0.1)] ms"
	lines.Insert(4, "measure only: DM [round(dm_measure_us / 1000)] ms, native [round(native_measure_us / 1000)] ms")
	text2file(jointext(lines, "\n"), "[MAP_CHECK_DIR]results.txt")
	log_world("MAP ENGINE CHECK: done, [passed] passed, [failed] failed")
	Master.Shutdown()
	qdel(world)

/proc/cmp_map_check_slow(list/a, list/b)
	return b[3] - a[3]

#undef MAP_CHECK_DIR
