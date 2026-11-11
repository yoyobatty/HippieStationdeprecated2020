// Grief undo (tgui-next GriefUndo.js): puts a griefed part of the station back the way the map made it. The user's rulings
// (2026-11-07): stock fill only (the station's .dmm, read once, against what's there now; nothing is recorded during the
// round); it puts back structure (walls, floors, windows, grilles, doors, lattices), machines and wiring (APCs, cables,
// pipes, vents, with the power and pipe networks joined up) and air, never items or mobs; a preview first, every changed
// tile ticked and unticked by a click on the map or in the list; aimed at a player (where their round-log lines are from in
// the last minutes), an area, a box or a ticket's place; things that aren't in the map (a plasma tank, a wall built to
// trap someone) are only shown, for the admin to deal with.
//
// What counts as changed on a tile:
// - the turf isn't the map's (a wall dismantled, a floor gone to space), or the map's floor is broken or burnt, or a
//   reinforced wall is half taken apart;
// - a mapped window, grille, lattice, door, cable, pipe, disposal pipe or machine is missing (matched by kind, not exact
//   type: a plain glass window put where a reinforced one was counts as there, so nothing is ever doubled up);
// - one that's there is broken (replaced with a new one), or damaged, welded, electrified, bolted, its wires cut, its
//   breaker off or its bulb out (fixed where it stands);
// - the air is wrong: pressure, heat, a gas that shouldn't be there, a fire.
// Apply does the ticked tiles; Undo takes back the last Apply's new things, turfs and air (fixed things stay fixed).

/// The most turfs one scan looks at
#define GRIEF_UNDO_MAX_TURFS 8000
/// How far around a player's logged actions their scan reaches when their areas are too big
#define GRIEF_UNDO_PLAYER_REACH 7

/// The station's map files as they were loaded at roundstart, read on first use: what each tile started with
GLOBAL_DATUM(stock_map, /datum/stock_map)

/proc/stock_map()
	var/static/reading = FALSE
	if(!GLOB.stock_map)
		if(reading) // someone else's call is reading it (it sleeps)
			UNTIL(GLOB.stock_map)
			return GLOB.stock_map
		reading = TRUE
		GLOB.stock_map = new /datum/stock_map
		reading = FALSE
	return GLOB.stock_map

/datum/stock_map
	/// The station's z levels
	var/z_low = 0
	var/z_high = -1
	/// "z" = list(list(grid set, parsed map)): every block of the map that lands on that level
	var/list/sets_by_z = list()
	/// A window spawner's path = what it makes
	var/list/spawner_lists = list()

/datum/stock_map/New()
	// the same order and offsets as SSmapping.LoadGroup(): each file at x 1, y 1, after the files before it
	var/z = SSmapping.station_start
	z_low = z
	for(var/path in SSmapping.config.GetFullMapPaths())
		var/datum/parsed_map/pm = new(file(path))
		if(!pm.bounds)
			continue
		pm.build_cache(FALSE)
		for(var/datum/grid_set/G as anything in pm.gridSets)
			var/key = "[G.zcrd + z - 1]"
			if(!sets_by_z[key])
				sets_by_z[key] = list()
			sets_by_z[key] += list(list(G, pm))
		z += pm.bounds[MAP_MAXZ] - pm.bounds[MAP_MINZ] + 1
		CHECK_TICK
	z_high = z - 1

/// The map's model for a tile: list(paths, their vars), the area last and the turfs before it; null off the map
/datum/stock_map/proc/model_at(turf/T)
	var/list/sets = sets_by_z["[T.z]"]
	for(var/list/entry as anything in sets)
		var/datum/grid_set/G = entry[1]
		var/datum/parsed_map/pm = entry[2]
		var/list/lines = G.gridLines
		var/row = G.ycrd - T.y + 1 // ycrd is the top line's y
		if(row < 1 || row > lines.len)
			continue
		var/col = T.x - G.xcrd
		if(col < 0)
			continue
		var/line = lines[row]
		var/pos = col * pm.key_len + 1
		if(pos + pm.key_len - 1 > length(line))
			continue
		return pm.modelCache[copytext(line, pos, pos + pm.key_len)]
	return null

/// The areas the station's map puts down, sorted by name (A.z is slow: it looks through the area's turfs)
/datum/stock_map/proc/station_areas()
	var/static/list/cached
	if(cached)
		return cached
	var/list/paths = list()
	for(var/list/entry as anything in flatten_sets())
		var/datum/parsed_map/pm = entry[2]
		for(var/key in pm.modelCache)
			var/list/model = pm.modelCache[key]
			if(!islist(model))
				continue
			var/list/members = model[1]
			if(members.len && ispath(members[members.len], /area))
				paths[members[members.len]] = TRUE
	var/list/found = list()
	for(var/path in paths)
		var/area/A = GLOB.areas_by_type[path]
		if(A && !istype(A, /area/space))
			found[A.name] = A
	cached = list()
	for(var/name in sortList(found))
		cached += found[name]
	return cached

/// Every block of the map, once each map file (for station_areas())
/datum/stock_map/proc/flatten_sets()
	. = list()
	var/list/seen = list()
	for(var/key in sets_by_z)
		for(var/list/entry as anything in sets_by_z[key])
			if(!seen[entry[2]])
				seen[entry[2]] = TRUE
				. += list(entry)

/// What a structure spawner makes, read off one that's made but never initialized
/datum/stock_map/proc/spawner_list(path)
	if(!(path in spawner_lists))
		var/list/made = list()
		if(SSatoms.initialized != INITIALIZATION_INSSATOMS)
			SSatoms.map_loader_begin()
			var/obj/effect/spawner/structure/S = new path(null)
			SSatoms.map_loader_stop()
			if(length(S.spawn_list))
				made = S.spawn_list.Copy()
			qdel(S)
		spawner_lists[path] = made
	return spawner_lists[path]

/// What a mapped thing is matched by on its tile: its kind, and its direction or layer where a tile can hold several
/proc/grief_undo_key(path, dir, layer)
	var/static/list/kinds = list()
	if(!dir) // a map's "dir = 0" comes out as SOUTH
		dir = SOUTH
	if(ispath(path, /obj/structure/window))
		var/obj/structure/window/W = path
		return initial(W.fulltile) ? "window full" : "window [dir]"
	if(ispath(path, /obj/structure/grille))
		return "grille"
	if(ispath(path, /obj/structure/lattice))
		return "lattice"
	if(ispath(path, /obj/structure/cable))
		return "cable [layer]"
	if(ispath(path, /obj/machinery/door/airlock))
		return "airlock"
	if(ispath(path, /obj/machinery/door/firedoor/border_only))
		return "firedoor [dir]"
	if(ispath(path, /obj/machinery/door/firedoor))
		return "firedoor"
	if(ispath(path, /obj/machinery/door/window))
		return "windoor [dir]"
	if(ispath(path, /obj/machinery/door/poddoor))
		return "poddoor"
	if(ispath(path, /obj/machinery/atmospherics))
		var/obj/machinery/atmospherics/A = path
		// a straight pipe running north-south is the same pipe either way round. The pipe turns itself NORTH or EAST when
		// it's made, but a map's dir is set after that, so mapped ones can be either.
		if((initial(A.pipe_flags) & PIPING_CARDINAL_AUTONORMALIZE) && (dir == SOUTH || dir == WEST))
			dir = turn(dir, 180)
		return "[path] [dir] [layer]"
	if(ispath(path, /obj/structure/disposalpipe))
		return "disposal [dir]"
	// anything else by its family: /obj/machinery/computer/x matches any computer, so a rebuilt one counts as there
	. = kinds[path]
	if(.)
		return
	var/list/parts = splittext("[path]", "/")
	var/depth = 4 // "", "obj", "machinery", "computer"
	if(parts.len > 4 && (parts[3] in list("machinery", "structure")) && (parts[4] in list("power", "door", "atmospherics")))
		depth = 5
	. = jointext(parts.Copy(1, min(parts.len, depth) + 1), "/")
	kinds[path] = .

/// A mapped thing's key, from its path and the map's vars for it
/proc/grief_undo_key_of_path(path, list/attrs)
	var/obj/O = path
	var/dir = attrs?["dir"]
	if(isnull(dir))
		dir = initial(O.dir)
	var/layer
	if(ispath(path, /obj/structure/cable))
		var/obj/structure/cable/C = path
		layer = attrs?["cable_layer"] || initial(C.cable_layer)
	else if(ispath(path, /obj/machinery/atmospherics))
		var/obj/machinery/atmospherics/A = path
		layer = attrs?["piping_layer"] || initial(A.piping_layer)
	return grief_undo_key(path, dir, layer)

/proc/grief_undo_key_of(obj/O)
	var/layer
	if(istype(O, /obj/structure/cable))
		var/obj/structure/cable/C = O
		layer = C.cable_layer
	else if(istype(O, /obj/machinery/atmospherics))
		var/obj/machinery/atmospherics/A = O
		layer = A.piping_layer
	return grief_undo_key(O.type, O.dir, layer)

/// Whether a mapped thing is one grief undo puts back: structure, machines and wiring, nothing that moves about the round
/proc/grief_undo_restorable(path)
	var/static/list/kinds = typecacheof(list(/obj/structure/window, /obj/structure/grille, /obj/structure/lattice, /obj/structure/cable,
		/obj/structure/disposalpipe, /obj/structure/plasticflaps, /obj/machinery))
	// engines and their parts (a new crystal or generator is a new engine), the nuke, things hauled about, item holders
	var/static/list/never = typecacheof(list(/obj/machinery/portable_atmospherics, /obj/machinery/power/supermatter_crystal,
		/obj/machinery/nuclearbomb, /obj/machinery/gravity_generator, /obj/machinery/the_singularitygen, /obj/machinery/field,
		/obj/machinery/power/emitter, /obj/machinery/power/rad_collector, /obj/machinery/power/port_gen, /obj/machinery/shieldgen,
		/obj/machinery/power/tesla_coil, /obj/machinery/power/grounding_rod, /obj/machinery/syndicatebomb,
		/obj/machinery/suit_storage_unit, /obj/machinery/smartfridge, /obj/machinery/particle_accelerator,
		/obj/machinery/power/generator, /obj/machinery/atmospherics/components/binary/circulator))
	if(!kinds[path] || never[path])
		return FALSE
	var/obj/O = path
	return initial(O.anchored)

/// Made after the round started (built, or brought in), not by the map or at roundstart (turret covers, the AI's spare
/// core, what spawners put down): only these fixed-down things are listed as added
/obj/var/tmp/made_in_round = FALSE

/obj/structure/Initialize(mapload)
	. = ..()
	if(!mapload && SSticker.round_start_time && world.time > SSticker.round_start_time + 10 SECONDS)
		made_in_round = TRUE

/obj/machinery/Initialize(mapload)
	. = ..()
	if(!mapload && SSticker.round_start_time && world.time > SSticker.round_start_time + 10 SECONDS)
		made_in_round = TRUE

/obj/item/tank/Initialize(mapload)
	. = ..()
	if(!mapload && SSticker.round_start_time && world.time > SSticker.round_start_time + 10 SECONDS)
		made_in_round = TRUE

/// Whether something that isn't in the map is worth showing: what griefers bring, wherever it came from, and anything
/// fixed down that was built this round
/proc/grief_undo_notable(obj/O)
	var/static/list/dangerous = typecacheof(list(/obj/item/transfer_valve, /obj/item/grenade, /obj/item/bombcore,
		/obj/item/assembly_holder, /obj/item/restraints/legcuffs/beartrap, /obj/effect/mine))
	var/static/list/loose = typecacheof(list(/obj/machinery/portable_atmospherics/canister, /obj/structure/reagent_dispensers,
		/obj/machinery/syndicatebomb, /obj/machinery/power/emitter, /obj/machinery/field/generator, /obj/machinery/the_singularitygen,
		/obj/machinery/power/supermatter_crystal))
	if(dangerous[O.type] || loose[O.type])
		return TRUE
	if(istype(O, /obj/item/tank))
		var/obj/item/tank/tank = O
		return O.made_in_round || tank.air_contents?.moles[/datum/gas/plasma] > 0.1
	if(isitem(O) || istype(O, /obj/effect))
		return FALSE
	return (istype(O, /obj/structure) || istype(O, /obj/machinery)) && O.anchored && O.made_in_round

/// A short name for a path, for the window: its name
/proc/grief_undo_name(path)
	var/atom/A = path
	return initial(A.name) || "[path]"

/// One tile that differs from the map
/datum/grief_tile
	var/x
	var/y
	var/z
	var/area_name
	var/ticked = TRUE
	/// Within reach of the player's logged actions (a player scan)
	var/near = FALSE
	/// The map's turf to put back, and its vars; turf_why says what's wrong
	var/turf_path
	var/list/turf_attrs
	var/turf_why
	/// list(list(path, vars)): mapped things that are gone
	var/list/missing = list()
	/// list(list(weakref, list(what's wrong))): there, fixed where they stand
	var/list/fixes = list()
	/// list(list(weakref, path, vars, why)): there but broken, swapped for new ones
	var/list/replace = list()
	/// The map's decals (put back with a turf) and airlock helpers (with a door)
	var/list/decals = list()
	var/list/helpers = list()
	/// What's wrong with the air, or null
	var/air_why
	/// Weakrefs to things here that aren't in the map
	var/list/adds = list()

/datum/grief_tile/proc/turf()
	return locate(x, y, z)

/// Something to put back or fix (not just added things to look at)
/datum/grief_tile/proc/has_work()
	return turf_path || length(missing) || length(fixes) || length(replace) || air_why

/// What the window lists for it
/datum/grief_tile/proc/describe()
	. = list()
	if(turf_path)
		. += turf_why
	var/list/counted = list()
	for(var/list/M as anything in missing)
		counted[grief_undo_name(M[1])]++
	for(var/name in counted)
		. += "[name][counted[name] > 1 ? " x[counted[name]]" : ""] gone"
	for(var/list/R as anything in replace)
		. += "[grief_undo_name(R[2])] [R[4]]"
	for(var/list/F as anything in fixes)
		var/datum/weakref/W = F[1]
		var/obj/O = W.resolve()
		if(O)
			. += "[O.name] [jointext(F[2], ", ")]"
	if(air_why)
		. += air_why

/client/var/datum/grief_undo/grief_undo

/client/proc/cmd_grief_undo()
	set name = "Grief Undo"
	set category = "Admin"
	set desc = "Put a griefed part of the station back the way the map made it."
	if(!check_rights(R_ADMIN))
		return
	open_grief_undo()

/// The window; with a place to scan: "here", "area" (an area), "player" (a ckey), "point" (list(x, y, z))
/client/proc/open_grief_undo(mode, target)
	if(!holder)
		return
	if(!grief_undo)
		grief_undo = new
		grief_undo.owner = src
	if(!GLOB.stock_map)
		to_chat(src, "<span class='notice'>Reading the station's map...</span>", confidential = TRUE)
		stock_map()
	grief_undo.ui_interact(mob)
	switch(mode)
		if("here")
			grief_undo.scan_area(get_area(mob))
		if("area")
			grief_undo.scan_area(target)
		if("player")
			grief_undo.scan_player(target)
		if("point")
			var/list/P = target
			var/turf/T = islist(P) ? locate(P[1], P[2], P[3]) : null
			if(T)
				grief_undo.scan_area(get_area(T), "around [AREACOORD(T)]")

/datum/grief_undo
	var/client/owner
	/// What's scanned, for the window
	var/source = ""
	var/list/turf/selection = list()
	/// "x,y,z" = /datum/grief_tile
	var/list/tiles = list()
	/// The player scan's ckey and minutes
	var/player_ckey = ""
	var/minutes = 15
	/// Refill the air
	var/do_air = TRUE
	/// Clicks on the map tick tiles
	var/click_ticks = TRUE
	/// Picking a box: 0 no, 1 the first corner, 2 the second
	var/box_step = 0
	var/turf/box_first
	/// The preview's images on the admin's screen
	var/list/image/shown = list()
	var/show_preview = TRUE
	/// The last Apply, for Undo: list("what", created weakrefs, turfs list(x, y, z, type, baseturfs), air list(turf, mix))
	var/list/last_apply
	/// What the last scan or action said
	var/message

/datum/grief_undo/Destroy()
	clear_preview()
	if(owner?.click_intercept == src)
		owner.click_intercept = null
	owner = null
	selection = null
	tiles = null
	last_apply = null
	return ..()

/datum/grief_undo/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "grief_undo", "Grief Undo", 980, 700, master_ui, state)
		ui.open()
	take_clicks()

/datum/grief_undo/ui_close(mob/user)
	clear_preview()
	box_step = 0
	if(owner?.click_intercept == src)
		owner.click_intercept = null

/datum/grief_undo/proc/take_clicks()
	if(owner && (click_ticks || box_step) && !owner.click_intercept)
		owner.click_intercept = src

// Scanning

/datum/grief_undo/proc/station_turf(turf/T)
	var/datum/stock_map/SM = stock_map()
	return T && T.z >= SM.z_low && T.z <= SM.z_high

/datum/grief_undo/proc/scan_area(area/A, label)
	if(!istype(A))
		return
	var/list/turfs = list()
	for(var/turf/T in A)
		if(station_turf(T))
			turfs += T
	if(!turfs.len)
		message = "[A.name] isn't on the station's map."
		SStgui.update_uis(src)
		return
	scan(turfs, label || A.name)

/datum/grief_undo/proc/scan_box(turf/a, turf/b)
	if(!station_turf(a) || !station_turf(b) || a.z != b.z)
		message = "Both corners on one station level."
		return
	var/list/turfs = block(locate(min(a.x, b.x), min(a.y, b.y), a.z), locate(max(a.x, b.x), max(a.y, b.y), a.z))
	scan(turfs, "Box [abs(a.x - b.x) + 1]x[abs(a.y - b.y) + 1] at [a.x],[a.y]")

/// Where a player's round-log lines (not their talk) were in the last minutes: their areas, or around those spots if
/// the areas are too big
/datum/grief_undo/proc/scan_player(player_ckey, minutes = src.minutes)
	src.player_ckey = ckey(player_ckey)
	src.minutes = clamp(round(text2num("[minutes]") || 15), 1, 180)
	var/static/list/talk = list("Say", "Whisper", "Emote", "Dead chat", "PDA", "Chat", "Comment", "Radio", "OOC", "Admin", "Admin (private)", "Asay")
	var/since = world.time - src.minutes MINUTES
	var/list/points = list()
	var/list/areas = list()
	var/list/log = GLOB.round_log
	for(var/i in log.len to 1 step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CKEY] != src.player_ckey || !entry[RL_Z] || (entry[RL_CAT] in talk))
			continue
		var/turf/T = locate(entry[RL_X], entry[RL_Y], entry[RL_Z])
		if(!station_turf(T))
			continue
		points[T] = TRUE
		areas[T.loc] = TRUE
	if(!points.len)
		selection = list()
		tiles = list()
		source = "[src.player_ckey], last [src.minutes] min"
		message = "Nothing logged for [src.player_ckey] on the station in the last [src.minutes] minutes."
		refresh_preview()
		SStgui.update_uis(src)
		return
	var/list/turfs = list()
	for(var/area/A as anything in areas)
		for(var/turf/T in A)
			if(station_turf(T))
				turfs[T] = TRUE
	if(turfs.len > GRIEF_UNDO_MAX_TURFS)
		turfs = list()
		for(var/turf/P as anything in points)
			for(var/turf/T as anything in RANGE_TURFS(GRIEF_UNDO_PLAYER_REACH, P))
				turfs[T] = TRUE
	scan(turfs, "[src.player_ckey], last [src.minutes] min: [areas.len] area[areas.len == 1 ? "" : "s"], [points.len] spot[points.len == 1 ? "" : "s"]")
	for(var/key in tiles)
		var/datum/grief_tile/G = tiles[key]
		for(var/turf/P as anything in points)
			if(P.z == G.z && abs(P.x - G.x) <= 3 && abs(P.y - G.y) <= 3)
				G.near = TRUE
				break
	SStgui.update_uis(src)

/datum/grief_undo/proc/scan(list/turfs, label)
	source = label
	message = null
	if(turfs.len > GRIEF_UNDO_MAX_TURFS)
		turfs.Cut(GRIEF_UNDO_MAX_TURFS + 1)
		message = "Only the first [GRIEF_UNDO_MAX_TURFS] tiles were looked at."
	selection = list()
	for(var/turf/T as anything in turfs)
		selection += T
	tiles = list()
	var/datum/stock_map/SM = stock_map()
	for(var/turf/T as anything in selection)
		var/list/model = SM.model_at(T)
		if(model)
			var/datum/grief_tile/G = compare(T, model, SM)
			if(G)
				tiles["[T.x],[T.y],[T.z]"] = G
		CHECK_TICK
	refresh_preview()
	SStgui.update_uis(src)

/// What's different about one tile, or null if nothing is
/datum/grief_undo/proc/compare(turf/T, list/model, datum/stock_map/SM)
	if(istype(T.loc, /area/shuttle)) // a shuttle docked over the map's space or dock: not the station's
		return null
	var/list/members = model[1]
	var/list/attrs = model[2]
	var/datum/grief_tile/G = new
	G.x = T.x
	G.y = T.y
	G.z = T.z
	var/area/A = T.loc
	G.area_name = A.name

	// the turf: the top one of the map's pile, just before the area
	var/top = members.len - 1
	var/stock_turf = top >= 1 ? members[top] : null
	if(ispath(stock_turf, /turf))
		if(!(T.type == stock_turf || (isspaceturf(T) && ispath(stock_turf, /turf/open/space))))
			G.turf_path = stock_turf
			G.turf_attrs = attrs[top]
			G.turf_why = "[grief_undo_name(stock_turf)] where [T.name] is"
		else if(isfloorturf(T))
			var/turf/open/floor/F = T
			var/list/stock_vars = attrs[top]
			var/stock_state = stock_vars?["icon_state"]
			var/mapped_damaged = stock_vars?["broken"] || stock_vars?["burnt"] || (stock_state && ((stock_state in F.broken_states) || (stock_state in F.burnt_states)))
			if((F.broken || F.burnt) && !mapped_damaged)
				G.turf_path = stock_turf
				G.turf_attrs = attrs[top]
				G.turf_why = "floor [F.broken ? "broken" : "burnt"]"
		else if(istype(T, /turf/closed/wall/r_wall))
			var/turf/closed/wall/r_wall/R = T
			if(R.d_state != INTACT)
				G.turf_path = stock_turf
				G.turf_attrs = attrs[top]
				G.turf_why = "reinforced wall half taken apart"

	// what the map put here, by key
	var/list/want = list()
	var/locked_helper = FALSE
	var/abandoned = FALSE
	for(var/i in 1 to members.len - 1)
		var/path = members[i]
		if(ispath(path, /turf) || !ispath(path, /obj))
			continue
		if(ispath(path, /obj/effect/turf_decal))
			G.decals += list(list(path, attrs[i]))
			continue
		if(ispath(path, /obj/effect/mapping_helpers/airlock))
			G.helpers += list(list(path, attrs[i]))
			if(ispath(path, /obj/effect/mapping_helpers/airlock/locked))
				locked_helper = TRUE
			if(ispath(path, /obj/effect/mapping_helpers/airlock/abandoned))
				abandoned = TRUE
			continue
		if(ispath(path, /obj/effect/spawner/structure))
			for(var/made in SM.spawner_list(path))
				var/key = grief_undo_key_of_path(made, null)
				if(!want[key])
					want[key] = list()
				want[key] += list(list(made, list()))
			continue
		if(ispath(path, /obj/effect))
			continue
		var/key = grief_undo_key_of_path(path, attrs[i])
		if(!want[key])
			want[key] = list()
		want[key] += list(list(path, attrs[i]))

	// what's here now, by key
	var/list/have = list()
	for(var/obj/O in T)
		if(istype(O, /obj/effect) && !istype(O, /obj/effect/mine))
			continue
		var/key = grief_undo_key_of(O)
		if(!have[key])
			have[key] = list()
		have[key] += O

	for(var/key in want)
		var/list/cur = have[key]
		for(var/list/S as anything in want[key])
			var/restorable = grief_undo_restorable(S[1])
			if(length(cur))
				var/obj/O = cur[1]
				cur.Cut(1, 2)
				if(restorable && !(abandoned && istype(O, /obj/machinery/door)))
					check_damage(G, O, S, locked_helper || S[2]?["locked"])
			else if(restorable)
				G.missing += list(S)

	for(var/key in have)
		for(var/obj/O as anything in have[key])
			if(grief_undo_notable(O))
				G.adds += WEAKREF(O)

	// the air, on a floor the map has a floor
	if(!G.turf_path && isopenturf(T) && !isspaceturf(T))
		G.air_why = air_problem(T)

	if(!G.has_work() && !length(G.adds))
		return null
	return G

/// A mapped thing that's still here: broken (swap it), or wrong in a way that can be fixed where it stands
/datum/grief_undo/proc/check_damage(datum/grief_tile/G, obj/O, list/S, keep_bolts)
	var/broken
	if(istype(O, /obj/structure/grille/broken))
		if(!ispath(S[1], /obj/structure/grille/broken)) // mapped broken: leave it
			broken = "broken"
	else if(ismachinery(O))
		var/obj/machinery/M = O
		if(M.stat & BROKEN)
			broken = "broken"
		else if(istype(M, /obj/machinery/door/airlock) && (M.obj_flags & EMAGGED))
			broken = "emagged"
		else if(istype(M, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/P = M
			if(P.obj_flags & EMAGGED)
				broken = "emagged"
			else if(P.opened == 2) // APC_COVER_REMOVED
				broken = "cover torn off"
			else if(!P.cell)
				broken = "no cell"
	if(broken)
		G.replace += list(list(WEAKREF(O), S[1], S[2], broken))
		return
	var/list/why = list()
	var/stock_integrity = S[2]?["obj_integrity"]
	if(O.obj_integrity < min(O.max_integrity, isnum(stock_integrity) ? stock_integrity : INFINITY))
		why += "damaged"
	if(istype(O, /obj/machinery/door))
		var/obj/machinery/door/D = O
		if(D.welded)
			why += "welded"
	if(istype(O, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/AL = O
		if(AL.secondsElectrified != MACHINE_NOT_ELECTRIFIED)
			why += "electrified"
		if(length(AL.wires?.cut_wires))
			why += "wires cut"
		if(AL.locked && !keep_bolts)
			why += "bolted"
	if(istype(O, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/P = O
		if(!P.operating)
			why += "breaker off"
		if(!P.lighting || !P.equipment || !P.environ)
			why += "channel off"
		if(length(P.wires?.cut_wires))
			why += "wires cut"
	if(istype(O, /obj/machinery/light))
		var/obj/machinery/light/L = O
		var/obj/machinery/light/stock_light = S[1]
		var/stock_status = S[2]?["status"]
		if(isnull(stock_status))
			stock_status = ispath(stock_light, /obj/machinery/light) ? initial(stock_light.status) : 0
		if(L.status != 0 && stock_status == 0) // LIGHT_OK; the map has some fixtures empty or broken on purpose
			why += "bulb out"
	if(why.len)
		G.fixes += list(list(WEAKREF(O), why))

/// What's wrong with a floor's air next to what the turf starts with, or null
/datum/grief_undo/proc/air_problem(turf/open/T)
	if(locate(/obj/effect/hotspot) in T)
		return "on fire"
	var/datum/gas_mixture/air = T.air
	if(!air)
		return null
	var/datum/gas_mixture/stock = new
	stock.copy_from_turf(T)
	var/pressure = air.return_pressure()
	var/stock_pressure = stock.return_pressure()
	. = null
	var/list/have = air.moles
	var/list/should = stock.moles
	for(var/gas in have)
		if(!should[gas] && have[gas] > 0.5)
			. = "[GLOB.meta_gas_info[META_GAS_NAME][gas]] in the air"
			break
	if(.)
		qdel(stock)
		return
	if(stock_pressure > 10 && pressure < stock_pressure * 0.75)
		. = "air thin ([round(pressure)] kPa)"
	else if(pressure > max(stock_pressure * 1.25, stock_pressure + 20))
		. = "air too thick ([round(pressure)] kPa)"
	else if(air.temperature > max(stock.temperature + 30, 340))
		. = "hot ([round(air.temperature - T0C)] C)"
	else if(air.temperature < stock.temperature - 40 && stock_pressure > 10)
		. = "cold ([round(air.temperature - T0C)] C)"
	qdel(stock)

// The preview: a tint on every changed tile, and what'll be put back drawn faintly where it goes

/datum/grief_undo/proc/clear_preview()
	if(owner && shown.len)
		owner.images -= shown
	shown.Cut()

/datum/grief_undo/proc/refresh_preview()
	clear_preview()
	if(!owner || !show_preview)
		return
	for(var/key in tiles)
		var/datum/grief_tile/G = tiles[key]
		var/turf/T = G.turf()
		if(!T)
			continue
		if(G.has_work())
			var/image/tint = image('icons/turf/overlays.dmi', T, (G.turf_path || length(G.missing) || length(G.replace) || length(G.fixes)) ? "greenOverlay" : "blueOverlay")
			tint.plane = ABOVE_LIGHTING_PLANE
			tint.alpha = G.ticked ? 110 : 25
			tint.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
			shown += tint
			if(G.ticked)
				if(G.turf_path)
					shown += ghost(G.turf_path, G.turf_attrs, T)
				for(var/list/M as anything in G.missing)
					shown += ghost(M[1], M[2], T)
		if(length(G.adds))
			var/image/mark = image('icons/turf/overlays.dmi', T, "redOverlay")
			mark.plane = ABOVE_LIGHTING_PLANE
			mark.alpha = 70
			mark.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
			shown += mark
	owner.images += shown

/datum/grief_undo/proc/ghost(path, list/attrs, turf/T)
	var/atom/A = path
	var/image/I = image(initial(A.icon), T, attrs?["icon_state"] || initial(A.icon_state), initial(A.layer), attrs?["dir"] || initial(A.dir))
	I.plane = ABOVE_LIGHTING_PLANE
	I.alpha = 130
	I.pixel_x = attrs?["pixel_x"] || initial(A.pixel_x)
	I.pixel_y = attrs?["pixel_y"] || initial(A.pixel_y)
	if(attrs?["color"])
		I.color = attrs["color"]
	I.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	return I

/// A click on the map while the window's open: a box corner, or a changed tile ticked or unticked. Other clicks go on.
/datum/grief_undo/proc/InterceptClickOn(mob/user, params, atom/object)
	var/list/modifiers = params2list(params)
	if(!modifiers["left"] || modifiers["shift"] || modifiers["ctrl"] || modifiers["alt"])
		return FALSE
	var/turf/T = get_turf(object)
	if(!T)
		return FALSE
	if(box_step == 1)
		box_first = T
		box_step = 2
		message = "Box: first corner [T.x],[T.y]. Click the other corner."
		SStgui.update_uis(src)
		return TRUE
	if(box_step == 2)
		box_step = 0
		var/turf/first = box_first
		box_first = null
		if(!click_ticks && owner.click_intercept == src)
			owner.click_intercept = null
		scan_box(first, T)
		SStgui.update_uis(src)
		return TRUE
	if(!click_ticks)
		return FALSE
	var/datum/grief_tile/G = tiles["[T.x],[T.y],[T.z]"]
	if(!G || !G.has_work())
		return FALSE
	G.ticked = !G.ticked
	refresh_preview()
	SStgui.update_uis(src)
	return TRUE

// Apply and Undo

/datum/grief_undo/proc/ticked_tiles()
	. = list()
	for(var/key in tiles)
		var/datum/grief_tile/G = tiles[key]
		if(G.ticked && G.has_work())
			. += G

/datum/grief_undo/proc/apply(mob/user)
	var/list/work = ticked_tiles()
	if(!work.len)
		message = "Nothing ticked."
		return
	if(SSatoms.initialized != INITIALIZATION_INNEW_REGULAR)
		message = "A map is loading. Try again in a moment."
		return
	var/list/created = list()
	var/list/turf_record = list()
	var/list/air_record = list()
	var/list/turf/changed_turfs = list()
	var/list/turf/air_turfs = list()
	var/fixed = 0
	var/replaced = 0

	// fixes first, and broken things out of the way of their new ones
	var/list/replacements = list() // list(turf, path, vars)
	for(var/datum/grief_tile/G as anything in work)
		for(var/list/F as anything in G.fixes)
			var/datum/weakref/FW = F[1]
			var/obj/O = FW.resolve()
			if(O && !QDELETED(O))
				fix(O, F[2])
				fixed++
		for(var/list/R as anything in G.replace)
			var/datum/weakref/RW = R[1]
			var/obj/O = RW.resolve()
			if(O && !QDELETED(O))
				qdel(O)
			replacements += list(list(G.turf(), R[2], R[3]))
			replaced++

	// everything new is made the way the map loader makes it: vars from the map, initialized together afterwards
	SSatoms.map_loader_begin()
	try
		for(var/datum/grief_tile/G as anything in work)
			var/turf/T = G.turf()
			if(G.turf_path)
				turf_record += list(list(T.x, T.y, T.z, T.type, islist(T.baseturfs) ? T.baseturfs.Copy() : T.baseturfs))
				var/old_type = T.type
				var/list/stock_attrs = G.turf_attrs || list()
				world.preloader_setup(stock_attrs, G.turf_path)
				var/turf/W = T.ChangeTurf(G.turf_path, null, CHANGETURF_DEFER_CHANGE | CHANGETURF_FORCEOP)
				if(GLOB.use_preloader && W)
					world.preloader_load(W)
				if(W)
					W.assemble_baseturfs(stock_attrs["baseturfs"] || initial(W.baseturfs))
					W.AfterChange(CHANGETURF_IGNORE_AIR | CHANGETURF_RECALC_ADJACENT, old_type)
					changed_turfs += W
					created += W
					for(var/list/D as anything in G.decals)
						created += make(D[1], D[2], W)
			var/door_made = FALSE
			for(var/list/M as anything in G.missing)
				var/atom/made = make(M[1], M[2], T)
				created += made
				if(istype(made, /obj/machinery/door/airlock))
					door_made = TRUE
			for(var/list/R as anything in replacements)
				if(R[1] == T)
					var/atom/made = make(R[2], R[3], T)
					created += made
					if(istype(made, /obj/machinery/door/airlock))
						door_made = TRUE
			if(door_made)
				for(var/list/H as anything in G.helpers)
					created += make(H[1], H[2], T)
	catch(var/exception/e)
		SSatoms.map_loader_stop()
		GLOB.use_preloader = FALSE
		message = "Apply stopped: [e] at [e.file]:[e.line]"
		stack_trace("grief undo apply: [e]")
		return
	SSatoms.map_loader_stop()
	created -= null
	SSatoms.InitializeAtoms(created)

	// join the new wiring and piping up, the way a player's would be
	var/list/cables = list()
	for(var/atom/A as anything in created)
		if(QDELETED(A))
			continue
		if(istype(A, /obj/structure/cable))
			cables += A
		else if(istype(A, /obj/machinery/atmospherics))
			var/obj/machinery/atmospherics/AM = A
			AM.atmosinit()
			for(var/obj/machinery/atmospherics/N in AM.pipeline_expansion())
				N.atmosinit()
				if(N.returnPipenet(AM))
					N.addMember(AM)
				else // its network went with what was griefed and hasn't been rebuilt yet
					SSair.add_to_rebuild_queue(N)
			SSair.add_to_rebuild_queue(AM)
		if(isobj(A) || isturf(A))
			QUEUE_SMOOTH(A)
			QUEUE_SMOOTH_NEIGHBORS(A)
	SSmachines.setup_template_powernets(cables)
	for(var/atom/A as anything in created)
		if(QDELETED(A))
			continue
		if(istype(A, /obj/machinery/power) && !istype(A, /obj/machinery/power/apc))
			var/obj/machinery/power/P = A
			if(!P.powernet)
				P.connect_to_network()
		if(istype(A, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/APC = A
			if(APC.terminal && !APC.terminal.powernet)
				APC.terminal.connect_to_network()

	// the air: every ticked open tile back to what it starts with, fires out
	if(do_air)
		for(var/datum/grief_tile/G as anything in work)
			var/turf/open/T = G.turf()
			if(istype(T) && !isspaceturf(T) && T.air && (G.air_why || (T in changed_turfs)))
				air_turfs += T
		for(var/turf/open/T as anything in air_turfs)
			var/datum/gas_mixture/before = new
			before.copy_from(T.air)
			air_record += list(list(T, before))
			for(var/obj/effect/hotspot/H in T)
				qdel(H)
			T.air.copy_from_turf(T)
			T.update_visuals()
			SSair.add_to_active(T, TRUE)

	var/list/made_refs = list()
	for(var/atom/A as anything in created)
		if(!QDELETED(A) && !isturf(A))
			made_refs += WEAKREF(A)
	var/summary = "[work.len] tile[work.len == 1 ? "" : "s"]: [changed_turfs.len] turf[changed_turfs.len == 1 ? "" : "s"], [made_refs.len] thing[made_refs.len == 1 ? "" : "s"] made, [replaced] replaced, [fixed] fixed, [air_turfs.len] air"
	last_apply = list("what" = "[source]: [summary]", "made" = made_refs, "turfs" = turf_record, "air" = air_record)
	message = "Applied. [summary]."
	log_admin("[key_name(user)] used grief undo on [source]: [summary]")
	message_admins("[key_name_admin(user)] used grief undo on [source]: [summary]")
	rescan()

/// Fixes something where it stands
/datum/grief_undo/proc/fix(obj/O, list/why)
	O.obj_integrity = O.max_integrity
	if(istype(O, /obj/machinery/door))
		var/obj/machinery/door/D = O
		D.welded = FALSE
	if(istype(O, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/AL = O
		if(AL.secondsElectrified != MACHINE_NOT_ELECTRIFIED)
			AL.set_electrified(MACHINE_NOT_ELECTRIFIED)
		if(AL.wires)
			for(var/wire in AL.wires.cut_wires.Copy())
				AL.wires.cut(wire) // mends it, with whatever mending it does
		if(AL.locked && ("bolted" in why))
			AL.unbolt()
	if(istype(O, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/P = O
		if(P.wires)
			for(var/wire in P.wires.cut_wires.Copy())
				P.wires.cut(wire)
		P.operating = TRUE
		if(!P.lighting)
			P.lighting = 3
		if(!P.equipment)
			P.equipment = 3
		if(!P.environ)
			P.environ = 3
		P.update()
	if(istype(O, /obj/machinery/light))
		var/obj/machinery/light/L = O
		L.status = 0 // LIGHT_OK
		L.switchcount = 0
		L.update()
	if(istype(O, /obj/structure/window))
		var/obj/structure/window/W = O
		W.update_nearby_icons()
	O.update_icon()

/// Makes a mapped thing on a tile with the map's vars, uninitialized (between map_loader_begin() and _stop())
/datum/grief_undo/proc/make(path, list/attrs, turf/T)
	world.preloader_setup(attrs || list(), path)
	var/atom/A = new path(T)
	if(GLOB.use_preloader && A)
		world.preloader_load(A)
	return A

/datum/grief_undo/proc/undo(mob/user)
	if(!last_apply)
		message = "Nothing to undo."
		return
	var/list/record = last_apply
	last_apply = null
	var/removed = 0
	for(var/datum/weakref/W as anything in record["made"])
		var/atom/A = W.resolve()
		if(A && !QDELETED(A))
			qdel(A)
			removed++
	var/turfs = 0
	for(var/list/R as anything in record["turfs"])
		var/turf/T = locate(R[1], R[2], R[3])
		if(!T)
			continue
		var/old_type = T.type
		var/turf/W = T.ChangeTurf(R[4], R[5], CHANGETURF_FORCEOP | CHANGETURF_DEFER_CHANGE)
		W?.AfterChange(CHANGETURF_IGNORE_AIR | CHANGETURF_RECALC_ADJACENT, old_type)
		turfs++
	var/airs = 0
	for(var/list/R as anything in record["air"])
		var/turf/open/T = R[1]
		var/datum/gas_mixture/before = R[2]
		if(istype(T) && T.air)
			T.air.copy_from(before)
			T.update_visuals()
			SSair.add_to_active(T, TRUE)
			airs++
	var/summary = "[removed] removed, [turfs] turf[turfs == 1 ? "" : "s"] put back, [airs] air"
	message = "Undone. [summary]."
	log_admin("[key_name(user)] undid a grief undo ([record["what"]]): [summary]")
	message_admins("[key_name_admin(user)] undid a grief undo ([record["what"]]): [summary]")
	rescan()

/datum/grief_undo/proc/rescan()
	if(!selection?.len)
		return
	var/list/keep_unticked = list()
	var/list/keep_near = list()
	for(var/key in tiles)
		var/datum/grief_tile/G = tiles[key]
		if(!G.ticked)
			keep_unticked[key] = TRUE
		if(G.near)
			keep_near[key] = TRUE
	var/list/turfs = list()
	for(var/turf/T as anything in selection)
		turfs += T
	var/said = message
	scan(turfs, source)
	message = said
	for(var/key in tiles)
		var/datum/grief_tile/G = tiles[key]
		if(keep_unticked[key])
			G.ticked = FALSE
		if(keep_near[key])
			G.near = TRUE
	refresh_preview()

// The window

/datum/grief_undo/ui_data(mob/user)
	var/list/rows = list()
	var/list/air_rows = list() // after the rest: a gas leak shouldn't bury a missing wall
	var/list/adds = list()
	var/restore = 0
	var/air = 0
	var/ticked = 0
	for(var/key in tiles)
		var/datum/grief_tile/G = tiles[key]
		if(G.has_work())
			var/air_only = !(G.turf_path || length(G.missing) || length(G.replace) || length(G.fixes))
			var/list/row = list(
				"key" = key,
				"x" = G.x,
				"y" = G.y,
				"area" = G.area_name,
				"ticked" = G.ticked,
				"near" = G.near,
				"what" = G.describe(),
				"air_only" = air_only,
			)
			if(air_only)
				air_rows += list(row)
			else
				rows += list(row)
			if(G.ticked)
				ticked++
			if(G.air_why)
				air++
			if(!air_only)
				restore++
		for(var/datum/weakref/W as anything in G.adds)
			var/obj/O = W.resolve()
			if(O && !QDELETED(O) && get_turf(O) == G.turf())
				adds += list(list("ref" = REF(O), "name" = O.name, "x" = G.x, "y" = G.y, "area" = G.area_name, "type" = "[O.type]"))
	var/list/area_names = list()
	for(var/area/A as anything in GLOB.stock_map?.station_areas())
		area_names |= A.name
	return list(
		"source" = source,
		"scanned" = !!selection?.len,
		"turfs" = selection?.len || 0,
		"rows" = rows + air_rows,
		"adds" = adds,
		"restore" = restore,
		"air" = air,
		"ticked" = ticked,
		"do_air" = do_air,
		"click_ticks" = click_ticks,
		"show_preview" = show_preview,
		"box_step" = box_step,
		"player_ckey" = player_ckey,
		"minutes" = minutes,
		"undo" = last_apply ? last_apply["what"] : null,
		"message" = message,
		"areas" = area_names,
	)

/datum/grief_undo/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_ADMIN))
		return
	var/mob/user = usr
	switch(action)
		if("here")
			scan_area(get_area(user))
		if("area")
			var/datum/stock_map/SM = stock_map()
			for(var/area/A as anything in SM.station_areas())
				if(A.name == params["name"])
					scan_area(A)
					break
		if("box")
			box_step = box_step ? 0 : 1
			message = box_step ? "Box: click the first corner on the map." : null
			if(box_step && owner.click_intercept != src)
				if(owner.click_intercept)
					message = "Another tool has the map's clicks (buildmode?). Close it first."
					box_step = 0
				else
					owner.click_intercept = src
		if("player")
			scan_player(params["ckey"], params["minutes"])
		if("rescan")
			rescan()
		if("tick")
			var/datum/grief_tile/G = tiles[params["key"]]
			if(G)
				G.ticked = !G.ticked
				refresh_preview()
		if("tick_all")
			var/on = !!text2num("[params["on"]]")
			for(var/key in tiles)
				var/datum/grief_tile/G = tiles[key]
				G.ticked = on
			refresh_preview()
		if("tick_near")
			for(var/key in tiles)
				var/datum/grief_tile/G = tiles[key]
				G.ticked = G.near
			refresh_preview()
		if("jump")
			var/datum/grief_tile/G = tiles[params["key"]]
			if(G)
				owner.jumptocoord(G.x, G.y, G.z)
		if("toggle_air")
			do_air = !do_air
		if("toggle_clicks")
			click_ticks = !click_ticks
			if(click_ticks)
				take_clicks()
			else if(!box_step && owner.click_intercept == src)
				owner.click_intercept = null
		if("toggle_preview")
			show_preview = !show_preview
			refresh_preview()
		if("apply")
			apply(user)
		if("undo")
			undo(user)
		if("add_jump", "add_vv", "add_delete")
			var/obj/O = locate(params["ref"])
			if(!istype(O) || QDELETED(O))
				return TRUE
			switch(action)
				if("add_jump")
					var/turf/T = get_turf(O)
					if(T)
						owner.jumptocoord(T.x, T.y, T.z)
				if("add_vv")
					owner.debug_variables(O)
				if("add_delete")
					var/turf/T = get_turf(O)
					log_admin("[key_name(user)] deleted [O] ([O.type]) at [AREACOORD(T)] from grief undo")
					message_admins("[key_name_admin(user)] deleted [O] ([O.type]) at [ADMIN_VERBOSEJMP(T)] from grief undo")
					qdel(O)
		if("player_menu")
			return player_menu_act(user, params)
	return TRUE

#undef GRIEF_UNDO_MAX_TURFS
#undef GRIEF_UNDO_PLAYER_REACH
