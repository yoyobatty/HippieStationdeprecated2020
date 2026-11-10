// Shaped explosions, checked and pictured on the real station (run.sh, headless). Not part of the game.
//  - native against DM: the same extra for every tile, at random spots and three sizes, with how long each took
//  - straight line (as before 2026-11-09) against shaped: how many tiles come out a different severity, up and down
//  - named spots dumped for render.py: what's on each tile and its severity both ways

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("explosion-preview" in world.params)
		sleep_offline_after_initializations = FALSE // nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(explosion_preview_run))
	return ..()

/proc/xp_log(text)
	text2file(text, "data/explosion_preview/results.txt")

/proc/explosion_preview_run()
	UNTIL(Master.current_runlevel)
	sleep(5 SECONDS)
	rand_seed(1109)
	var/list/sizes = list("small" = list(1, 2, 4), "medium" = list(2, 4, 8), "maxcap" = list(5, 10, 20))
	var/list/spots = list()
	var/list/station = list()
	for(var/z in SSmapping.levels_by_trait(ZTRAIT_STATION))
		for(var/turf/open/floor/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			if(istype(T.loc, /area/space) || istype(T.loc, /area/shuttle))
				continue
			station += T
	for(var/i in 1 to 150)
		spots += pick(station)
	xp_log("Map: [SSmapping.config.map_name], [length(station)] station floor tiles, [length(spots)] spots")

	// native against DM, and how long each takes
	for(var/size_name in sizes)
		var/list/s = sizes[size_name]
		var/range = max(s[1], s[2], s[3])
		var/native_ms = 0
		var/dm_ms = 0
		var/tiles = 0
		var/differ = 0
		var/differ_spots = 0
		var/native_missing = FALSE
		for(var/turf/T as anything in spots)
			var/list/affected = SSexplosions.GatherSpiralTurfs(range, T)
			var/list/blocks = SSexplosions.CaculateExplosionBlock(affected)
			GLOB.explosion_shape_mode = "native"
			var/start = TICK_USAGE_REAL
			var/list/native = explosion_shape(T, range, blocks)
			native_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			if(!GLOB.explosion_shape_native)
				native_missing = TRUE
			GLOB.explosion_shape_mode = "dm"
			start = TICK_USAGE_REAL
			var/list/in_dm = explosion_shape(T, range, blocks)
			dm_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			var/these = 0
			for(var/turf/A as anything in native)
				tiles++
				if(abs(native[A] - in_dm[A]) > 0.001)
					these++
			differ += these
			if(these)
				differ_spots++
			CHECK_TICK
		xp_log("[size_name] ([range]): [tiles] tiles; [differ] differ between native and DM, at [differ_spots] spots[native_missing ? " (NATIVE MISSING: DM both times)" : ""]; native [round(native_ms / length(spots), 0.01)] ms a blast, DM [round(dm_ms / length(spots), 0.01)] ms")
	GLOB.explosion_shape_mode = "native"

	// straight line against shaped
	for(var/size_name in sizes)
		var/list/s = sizes[size_name]
		var/list/totals = list("line" = list(0, 0, 0), "shaped" = list(0, 0, 0))
		var/up = 0
		var/down = 0
		for(var/turf/T as anything in spots)
			var/list/line = explosion_severity_map(T, s[1], s[2], s[3], "line")
			var/list/shaped = explosion_severity_map(T, s[1], s[2], s[3], "native")
			for(var/turf/A as anything in line)
				var/list/L = totals["line"]
				L[line[A]]++
			for(var/turf/A as anything in shaped)
				var/list/L = totals["shaped"]
				L[shaped[A]]++
			for(var/turf/A as anything in line | shaped)
				var/before = line[A] || 4
				var/after = shaped[A] || 4
				if(after < before)
					up++ //lower is worse: 1 is devastation
				else if(after > before)
					down++
			CHECK_TICK
		var/list/L = totals["line"]
		var/list/S = totals["shaped"]
		xp_log("[size_name] ([s[1]], [s[2]], [s[3]]), tiles hit over [length(spots)] blasts: straight line [L[1]] devastated, [L[2]] heavy, [L[3]] light; shaped [S[1]], [S[2]], [S[3]]. [up] tiles hit harder, [down] less")

	// what a block would have to count for to hit about as many tiles as the straight line did
	for(var/weight in list(1, 1.5, 2, 2.5, 3))
		GLOB.explosion_block_weight = weight
		for(var/size_name in list("medium", "maxcap"))
			var/list/s = sizes[size_name]
			var/list/S = list(0, 0, 0)
			for(var/turf/T as anything in spots)
				var/list/shaped = explosion_severity_map(T, s[1], s[2], s[3], "native")
				for(var/turf/A as anything in shaped)
					S[shaped[A]]++
				CHECK_TICK
			xp_log("block weight [weight], [size_name]: shaped [S[1]] devastated, [S[2]] heavy, [S[3]] light")
	GLOB.explosion_block_weight = text2num(world.params["explosion-block-weight"]) || 1.5

	// named spots for the pictures
	var/list/named = list(
		"Toxins" = /area/science/mixing,
		"Bar" = /area/crew_quarters/bar,
		"Brig" = /area/security/brig,
		"Central hallway" = /area/hallway/primary/central,
		"Engineering" = /area/engine/engineering,
		"Medbay" = /area/medical/medbay/central,
	)
	for(var/name in named)
		var/area/A = locate(named[name]) in GLOB.sortedAreas
		if(!A)
			continue
		var/list/floors = list()
		for(var/turf/open/floor/T in A)
			floors += T
		if(!length(floors))
			continue
		// the floor nearest the middle of the room
		var/sx = 0
		var/sy = 0
		for(var/turf/T as anything in floors)
			sx += T.x
			sy += T.y
		sx /= length(floors)
		sy /= length(floors)
		var/turf/epicenter
		for(var/turf/T as anything in floors)
			if(!epicenter || abs(T.x - sx) + abs(T.y - sy) < abs(epicenter.x - sx) + abs(epicenter.y - sy))
				epicenter = T
		xp_dump(name, epicenter, sizes["medium"])
		xp_dump("[name] maxcap", epicenter, sizes["maxcap"])
	xp_log("done")
	Master.Shutdown()
	qdel(world)

/// What's on a tile, for render.py
/proc/xp_kind(turf/T)
	if(isspaceturf(T))
		return "space"
	if(istype(T, /turf/closed/wall/r_wall))
		return "rwall"
	if(T.density)
		return "wall"
	var/obj/machinery/door/D = locate() in T
	if(D)
		return D.density ? "door_shut" : "door_open"
	if(locate(/obj/structure/window) in T)
		return "window"
	if(locate(/obj/structure/grille) in T)
		return "grille"
	return "floor"

/proc/xp_dump(name, turf/epicenter, list/s)
	var/range = s[3] + 3
	var/list/line = explosion_severity_map(epicenter, s[1], s[2], s[3], "line")
	var/list/shaped = explosion_severity_map(epicenter, s[1], s[2], s[3], "native")
	var/list/rows = list()
	for(var/y in epicenter.y + range to epicenter.y - range step -1)
		var/list/row = list()
		for(var/x in epicenter.x - range to epicenter.x + range)
			var/turf/T = locate(x, y, epicenter.z)
			if(!T)
				row += list(list("none", 0, 0))
				continue
			row += list(list(xp_kind(T), line[T] || 0, shaped[T] || 0))
		rows += list(row)
	var/list/out = list("name" = name, "area" = get_area_name(epicenter, TRUE), "x" = epicenter.x, "y" = epicenter.y, "size" = s, "rows" = rows)
	text2file(json_encode(out), "data/explosion_preview/[replacetext(name, " ", "_")].json")
