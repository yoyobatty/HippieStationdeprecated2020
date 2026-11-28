// The lobby build: Lavaland (its base map, ruins and lava rivers) and the space ruin levels are made after startup, while
// the lobby counts down, instead of before it. They were about 5 of the ~18 seconds a server took to start (2026-11-13).
//
// The levels themselves are still added at startup, as empty space, so world.maxz is final before the lighting and atmos
// engines size themselves to it, and z-level numbers don't move. Nothing on them is initialized at startup (SSatoms skips
// them). After startup lobby_build() loads onto them the way startup did: the map loader with no_changeturf, ruins the same,
// and anything made on them meanwhile waits (/atom/New() asks lobby_build_hold()). When it's all there, everything on them is
// initialized in one go, in startup's order (mobs, objs, areas, turfs), then their powernets, pipes, air and lighting
// objects are set up as SSmachines, SSair and SSlighting set up the rest of the world at startup.
//
// The round doesn't start until it's done (SSticker waits on lobby_build_busy). SSair doesn't fire meanwhile: changes to the
// levels' unready turfs (lava rivers) queue them for air, and their air is only made when they initialize.
//
// World params: lobby-build=off  makes them at startup, as before
//               lobby-build-ticklimit=N  its pace (LOBBY_BUILD_TICKLIMIT)

/// Atoms made on a held level wait for the lobby build instead of initializing (checked in /atom/New())
GLOBAL_REAL_VAR(lobby_build_holding) = FALSE
/// The lobby build is loading maps: areas made now wait too
GLOBAL_REAL_VAR(lobby_build_loading) = FALSE

/datum/controller/subsystem/mapping
	/// Lavaland and the space ruin levels are made after startup
	var/lobby_build_planned = FALSE
	/// z -> TRUE for each level being held for the lobby build, or null
	var/list/lobby_build_levels
	/// What was made on the held levels outside the map loader, and areas the build made
	var/list/lobby_build_pending = list()
	/// The build has been planned and isn't finished: the round waits
	var/lobby_build_busy = FALSE
	/// The empty level Lavaland is built on, or 0
	var/lobby_build_lavaland_z = 0
	/// What happened, for the log and View Variables
	var/lobby_build_status = "not planned"
	/// Seconds each stage took
	var/list/lobby_build_stages = list()
	var/lobby_build_sleep_after = FALSE
	/// What SSair's and SSlighting's can_fire were before the build paused them (null until it has), for lobby_build_finish()
	var/lobby_build_air_could_fire
	var/lobby_build_lighting_could_fire

/datum/controller/subsystem/mapping/var/list/lobby_build_docks = list()

/// The station's escape pods land somewhere random on Lavaland (code/modules/shuttle/emergency.dm). While Lavaland isn't built
/// yet, the dock initializes without its placement (mapload FALSE skips it) and waits; lobby_build_place_docks() places it.
/obj/docking_port/stationary/random/Initialize(mapload)
	if(mapload && SSmapping.lobby_build_busy)
		SSmapping.lobby_build_docks += src
		return ..(FALSE)
	return ..()

/// The waiting random docks, placed as their Initialize() places them at startup
/datum/controller/subsystem/mapping/proc/lobby_build_place_docks()
	for(var/obj/docking_port/stationary/random/dock as anything in lobby_build_docks)
		if(QDELETED(dock))
			continue
		var/list/turfs = get_area_turfs(dock.target_area)
		var/original_len = turfs.len
		var/placed = FALSE
		while(turfs.len)
			var/turf/T = pick(turfs)
			if(T.x < dock.edge_distance || T.y < dock.edge_distance || (world.maxx + 1 - T.x) < dock.edge_distance || (world.maxy + 1 - T.y) < dock.edge_distance)
				turfs -= T
			else
				dock.forceMove(T)
				placed = TRUE
				break
		if(!placed)
			WARNING("docking port '[dock.id]' could not be randomly placed in [dock.target_area]: of [original_len] turfs, none were suitable")
			qdel(dock)
	lobby_build_docks.Cut()

/datum/controller/subsystem/mapping/proc/lobby_build_wanted()
	return world.params["lobby-build"] != "off"

/// loadWorld(): Lavaland's level, empty for now
/datum/controller/subsystem/mapping/proc/lobby_build_reserve_lavaland()
	var/datum/space_level/level = add_new_zlevel("Lavaland", ZTRAITS_LAVALAND)
	lobby_build_lavaland_z = level.z_value

/// Initialize(), before the ruins: holds Lavaland's level and the space ruin levels. FALSE if there's nothing to hold.
/datum/controller/subsystem/mapping/proc/lobby_build_hold_levels()
	if(!lobby_build_wanted())
		return FALSE
	var/list/held = new /list(world.maxz)
	var/count = 0
	if(lobby_build_lavaland_z)
		held[lobby_build_lavaland_z] = TRUE
		count++
	for(var/z in levels_by_trait(ZTRAIT_SPACE_RUINS))
		if(!held[z])
			held[z] = TRUE
			count++
	if(!count)
		return FALSE
	lobby_build_levels = held
	lobby_build_planned = TRUE
	lobby_build_busy = TRUE
	lobby_build_holding = TRUE
	lobby_build_status = "waiting for startup to finish ([count] levels held)"
	return TRUE

/// Lavaland's ruins and rivers and the space ruins, as Initialize() made them at startup
/datum/controller/subsystem/mapping/proc/seed_startup_ruins()
	loading_ruins = TRUE
	var/list/lava_ruins = levels_by_trait(ZTRAIT_LAVA_RUINS)
	if (lava_ruins.len)
		seedRuins(lava_ruins, CONFIG_GET(number/lavaland_budget), /area/lavaland/surface/outdoors/unexplored, lava_ruins_templates)
		for (var/lava_z in lava_ruins)
			spawn_rivers(lava_z)

	// Generate deep space ruins
	var/list/space_ruins = levels_by_trait(ZTRAIT_SPACE_RUINS)
	if (space_ruins.len)
		seedRuins(space_ruins, CONFIG_GET(number/space_budget), /area/space, space_ruins_templates)
	loading_ruins = FALSE

/// Whether an atom being made waits for the lobby build (it's on a held level), from /atom/New() while lobby_build_holding
/proc/lobby_build_hold(atom/A)
	var/list/held = SSmapping.lobby_build_levels
	if(!held)
		return FALSE
	if(isarea(A))
		if(!lobby_build_loading)
			return FALSE
	else
		var/turf/T = get_turf(A)
		if(!T || T.z > length(held) || !held[T.z])
			return FALSE
	SSmapping.lobby_build_pending += A
	return TRUE

/// Whether a z-level is being held for the lobby build
/datum/controller/subsystem/mapping/proc/level_held(z)
	var/list/held = lobby_build_levels
	return held && z && z <= length(held) && held[z]

/// How far into a tick (%) the lobby build runs before it lets the MC and everything else in. Over 100, it runs on past the
/// tick's end: each time it stops, the rest of that tick is lost, so fewer, longer turns build faster. 2026-11-14 A/B
/// (tools/boot_bench/lobby_tick_ab.py, 5 boots each): the MC's own pace (it keeps the last quarter of each tick) 10.7 s, 98
/// 10.0 s, 200 9.6 s, 400 8.0 s, 50 18.5 s, 30 28 s once and stuck past 5 minutes once (stoplag only goes on in a tick under 30%). At
/// 400 the lobby ticks ~9 times a second while it builds. World param lobby-build-ticklimit=N overrides it; 0 = the MC's pace.
#define LOBBY_BUILD_TICKLIMIT 400

/// While the lobby build runs: the tick limit its CHECK_TICKs go by, in place of the MC's (0: the MC's)
/datum/controller/master/var/static/build_ticklimit = 0

/// From Master's Initialize(), once startup is done
/datum/controller/subsystem/mapping/proc/start_lobby_build()
	if(!lobby_build_planned || !lobby_build_levels)
		return
	// Nobody may be on yet: the world has to keep ticking until it's done. null, not FALSE: the headless runs Master starts
	// right after this (bot shifts, gym, code sweep...) set FALSE, and the end of the build mustn't put those to sleep.
	if(Master.sleep_offline_after_initializations)
		lobby_build_sleep_after = TRUE
		Master.sleep_offline_after_initializations = null
	INVOKE_ASYNC(src, PROC_REF(lobby_build))

/datum/controller/subsystem/mapping/proc/lobby_build_stage(name, start)
	lobby_build_stages[name] = (REALTIMEOFDAY - start) / 10
	return REALTIMEOFDAY

/// What the lobby build's stages hand on to each other
/datum/lobby_build_work
	/// REALTIMEOFDAY when the build began, and when the stage under way did
	var/started
	var/stage
	var/started_time
	/// Its tick limit (LOBBY_BUILD_TICKLIMIT, or lobby-build-ticklimit)
	var/pace
	/// The held levels (z -> TRUE), and what waited for the build outside the map loader
	var/list/held
	var/list/pending
	var/list/turfs = list()
	var/list/mobs = list()
	var/list/objs = list()
	var/list/held_areas = list()
	var/list/cables = list()
	var/list/atmos_machines = list()

/// The build, a stage at a time. A runtime error part way only ends the proc it happens in, as at startup: in an atom's Initialize()
/// or a ruin that won't load, the stage goes on without it; in a stage's own code, that stage stops there and the rest still run.
/// However it went, lobby_build_finish() puts air and lighting back and lets the round start (without that the lobby would wait at 0
/// forever) and tells admins of any runtime. Not try/catch around it all: that made every runtime anywhere under it, one bad atom on
/// Lavaland included, stop the whole build, leaving the levels' things uninitialized (canisters with no air runtimed every air tick),
/// and one in the map loader left SSatoms at map_loader_begin(), so nothing made for the rest of the round initialized
/// (tools/review_smoke, lobby_* steps, 2026-11-28).
/datum/controller/subsystem/mapping/proc/lobby_build()
	var/runtimes_before = GLOB.total_runtimes
	var/datum/lobby_build_work/W = new
	W.started = REALTIMEOFDAY
	W.stage = W.started
	W.started_time = world.time
	var/list/failed = list()
	if(!lobby_build_begin(W))
		failed += "start"
	if(!lobby_build_load(W))
		failed += "maps"
	// Everything is there. From here on, what's made on these levels initializes as it's made. The levels stay held for
	// ChangeTurf() until the lighting pass (it leaves their lighting to it, as at startup).
	lobby_build_loading = FALSE
	loading_ruins = FALSE
	lobby_build_atoms_back()
	W.held = lobby_build_levels
	W.pending = lobby_build_pending
	lobby_build_holding = FALSE
	lobby_build_pending = list()
	if(!lobby_build_gather(W))
		failed += "gathering"
	if(!lobby_build_atoms(W))
		failed += "atoms"
	if(!lobby_build_networks(W))
		failed += "powernets and pipes"
	if(!lobby_build_air(W))
		failed += "air"
	if(!lobby_build_lighting(W))
		failed += "lighting"
	lobby_build_finish(W, failed, GLOB.total_runtimes - runtimes_before)

/// SSatoms as the lobby has it. A runtime between a map load's map_loader_begin() and _stop(), or in InitializeAtoms()'s own code,
/// leaves it as it was then: InitializeAtoms() would then do nothing, and nothing made after would initialize
/datum/controller/subsystem/mapping/proc/lobby_build_atoms_back()
	if(SSatoms.initialized != INITIALIZATION_INNEW_REGULAR)
		log_world("Lobby build: SSatoms was left at [SSatoms.initialized] part way, put back to [INITIALIZATION_INNEW_REGULAR]")
		SSatoms.initialized = INITIALIZATION_INNEW_REGULAR

/// However the stages went: the levels let go, air and lighting back on, the round let start, admins told of any runtime
/datum/controller/subsystem/mapping/proc/lobby_build_finish(datum/lobby_build_work/W, list/failed, runtimes)
	lobby_build_levels = null
	lobby_build_loading = FALSE
	lobby_build_holding = FALSE
	if(!isnull(lobby_build_lighting_could_fire))
		SSlighting.can_fire = lobby_build_lighting_could_fire
	if(!isnull(lobby_build_air_could_fire))
		SSair.can_fire = lobby_build_air_could_fire
	lobby_build_atoms_back()
	Master.build_ticklimit = 0
	repopulate_sorted_areas()
	lobby_build_place_docks()
	lobby_build_path_engine_afresh()
	lobby_build_busy = FALSE
	var/took = (REALTIMEOFDAY - W.started) / 10
	var/list/parts = list()
	for(var/name in lobby_build_stages)
		parts += "[name] [lobby_build_stages[name]]s"
	lobby_build_status = "done in [took]s: [length(W.turfs)] turfs, [length(W.mobs) + length(W.objs)] things[length(failed) ? ", stopped part way in [jointext(failed, ", ")]" : ""]"
	log_world("Lobby build: [lobby_build_status] ([jointext(parts, ", ")]; [round((world.time - W.started_time) / world.tick_lag)] ticks, pace [W.pace > 0 ? W.pace : "MC"])")
	if(length(failed) || runtimes > 0)
		var/msg = "Lobby build: [runtimes] runtime error\s while it built Lavaland and the space ruins[length(failed) ? ", stopped part way in [jointext(failed, ", ")]" : ""]. They may be missing or broken in places this round: see the runtime log."
		log_world(msg)
		message_admins(msg)
	// Only if nothing has wanted the world awake since (a headless run sets FALSE): a Bot Shift on a map with Lavaland used to
	// fall asleep here, before its round started, and never woke (2026-11-16, every full-station shift stalled after this line)
	if(lobby_build_sleep_after && isnull(Master.sleep_offline_after_initializations))
		Master.sleep_offline_after_initializations = TRUE
		if(!length(GLOB.clients) && !CONFIG_GET(flag/resume_after_initializations))
			world.sleep_offline = TRUE

/// The map loader's no_changeturf turfs never told the station picture they'd changed: if the path engine has kept one already,
/// it starts again (the held levels' turfs as they were before the build may be in it)
/datum/controller/subsystem/mapping/proc/lobby_build_path_engine_afresh()
	if(GLOB.station_picture_kept)
		path_engine_setup()

// The stages, in order. Each returns TRUE when it gets to its end (one stopped by a runtime returns null).

/// The pace set, and air and lighting paused
/datum/controller/subsystem/mapping/proc/lobby_build_begin(datum/lobby_build_work/W)
	lobby_build_status = "building"
	W.pace = LOBBY_BUILD_TICKLIMIT
	if(!isnull(world.params["lobby-build-ticklimit"]))
		W.pace = text2num(world.params["lobby-build-ticklimit"])
	if(W.pace > 0)
		Master.build_ticklimit = W.pace
	// Neither works on these levels until they're set up, as at startup: air on unready turfs, and lights before the lighting
	// engine knows which of their turfs are opaque (a lava light would shine through the rock)
	lobby_build_air_could_fire = SSair.can_fire
	SSair.can_fire = FALSE
	lobby_build_lighting_could_fire = SSlighting.can_fire
	SSlighting.can_fire = FALSE
	return TRUE

/// Lavaland's map, its ruins and rivers, and the space ruins
/datum/controller/subsystem/mapping/proc/lobby_build_load(datum/lobby_build_work/W)
	W.stage = REALTIMEOFDAY
	lobby_build_loading = TRUE
	if(lobby_build_lavaland_z)
		var/datum/parsed_map/lavaland = new(file("_maps/map_files/Mining/Lavaland.dmm"))
		if(!lavaland.bounds || !lavaland.load(1, 1, lobby_build_lavaland_z, no_changeturf = TRUE))
			var/msg = "RED ALERT! Lavaland failed to load in the lobby build. Yell at your server host!"
			to_chat(world, "<span class='boldannounce'>[msg]</span>")
			log_world(msg)
		W.stage = lobby_build_stage("Lavaland", W.stage)
	seed_startup_ruins()
	W.stage = lobby_build_stage("ruins", W.stage)
	return TRUE

/// Everything on the held levels, and what waited that the turfs don't hold
/datum/controller/subsystem/mapping/proc/lobby_build_gather(datum/lobby_build_work/W)
	W.stage = REALTIMEOFDAY
	var/list/held = W.held
	var/list/turfs = W.turfs
	var/list/mobs = W.mobs
	var/list/objs = W.objs
	var/list/areas = list()
	var/list/cables = W.cables
	var/list/atmos_machines = W.atmos_machines
	for(var/z in 1 to length(held))
		if(!held[z])
			continue
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			turfs += T
			areas[T.loc] = TRUE
			for(var/atom/movable/AM as anything in T)
				if(ismob(AM))
					mobs += AM
					continue
				objs += AM
				if(istype(AM, /obj/structure/cable))
					cables += AM
				else if(istype(AM, /obj/machinery/atmospherics))
					atmos_machines += AM
		CHECK_TICK
	// What waited that the turfs don't hold: areas the build made, things inside other things
	var/list/held_areas = W.held_areas
	for(var/atom/A as anything in W.pending)
		if(QDELETED(A) || (A.flags_1 & INITIALIZED_1))
			continue
		if(isarea(A))
			held_areas += A
			areas[A] = TRUE
		else if(!isturf(A) && !isturf(A.loc))
			if(ismob(A))
				mobs += A
			else
				objs += A
	W.stage = lobby_build_stage("gathering", W.stage)
	return TRUE

/// Everything gathered initialized, in startup's order: BYOND's world loop gives mobs, objs, areas, then turfs
/datum/controller/subsystem/mapping/proc/lobby_build_atoms(datum/lobby_build_work/W)
	W.stage = REALTIMEOFDAY
	SSatoms.InitializeAtoms(W.mobs + W.objs + W.held_areas + W.turfs)
	W.stage = lobby_build_stage("atoms", W.stage)
	return TRUE

/// (areas put themselves in areas_in_z as they initialize, as at startup)
/datum/controller/subsystem/mapping/proc/lobby_build_networks(datum/lobby_build_work/W)
	W.stage = REALTIMEOFDAY
	SSmachines.setup_template_powernets(W.cables)
	SSair.setup_template_machinery(W.atmos_machines)
	W.stage = lobby_build_stage("powernets and pipes", W.stage)
	return TRUE

/datum/controller/subsystem/mapping/proc/lobby_build_air(datum/lobby_build_work/W)
	W.stage = REALTIMEOFDAY
	// What initializing queued for these levels' turfs, as SSair's startup takes it (process_adjacent_rebuild(TRUE)): walls
	// and space work out their neighbours now, the rest is left to the pass below, and the wakes are dropped (startup clears
	// active_turfs before it). Left in the queue, every turf here would be worked out twice and woken once SSair fires again.
	var/list/held = W.held
	var/list/rebuild = SSair.adjacent_rebuild
	var/list/kept = list()
	var/held_count = length(held)
	for(var/turf/T as anything in rebuild)
		if(T.z && T.z <= held_count && held[T.z])
			if(T.blocks_air || isspaceturf(T))
				T.ImmediateCalculateAdjacentTurfs()
			continue
		kept[T] = rebuild[T]
	SSair.adjacent_rebuild = kept

	// Air, as SSair's setup_allturfs() did it for the rest of the world
	var/fired = SSair.times_fired
	for(var/turf/T as anything in W.turfs)
		if(T.blocks_air || isspaceturf(T))
			continue
		T.Initalize_Atmos(fired)
		CHECK_TICK
	W.stage = lobby_build_stage("air", W.stage)
	return TRUE

/// Lighting objects, as create_all_lighting_objects() made them at startup: no light here has been worked out yet (SSlighting is
/// paused), so there's nothing for them to take up until it is. And the lighting engine told of every turf: native_ready() left
/// these levels out, and the engine starts every turf at 0, so one never told anything and still 0 needn't be sent.
/datum/controller/subsystem/mapping/proc/lobby_build_lighting(datum/lobby_build_work/W)
	W.stage = REALTIMEOFDAY
	for(var/turf/T as anything in W.turfs)
		var/area/A = T.loc
		if(IS_DYNAMIC_LIGHTING(A) && IS_DYNAMIC_LIGHTING(T) && !T.lighting_object)
			new /atom/movable/lighting_object(T)
		if(T.lighting_engine_pushed == -1 && !T.lighting_engine_flags())
			T.lighting_engine_pushed = 0
		else
			T.lighting_engine_push()
		CHECK_TICK
	W.stage = lobby_build_stage("lighting", W.stage)
	return TRUE

#undef LOBBY_BUILD_TICKLIMIT
