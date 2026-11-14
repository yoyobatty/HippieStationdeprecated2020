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

/// From Master's Initialize(), once startup is done
/datum/controller/subsystem/mapping/proc/start_lobby_build()
	if(!lobby_build_planned || !lobby_build_levels)
		return
	// Nobody may be on yet: the world has to keep ticking until it's done
	if(Master.sleep_offline_after_initializations)
		lobby_build_sleep_after = TRUE
		Master.sleep_offline_after_initializations = FALSE
	INVOKE_ASYNC(src, PROC_REF(lobby_build))

/datum/controller/subsystem/mapping/proc/lobby_build_stage(name, start)
	lobby_build_stages[name] = (REALTIMEOFDAY - start) / 10
	return REALTIMEOFDAY

/datum/controller/subsystem/mapping/proc/lobby_build()
	var/started = REALTIMEOFDAY
	var/stage = started
	lobby_build_status = "building"
	// Neither works on these levels until they're set up, as at startup: air on unready turfs, and lights before the lighting
	// engine knows which of their turfs are opaque (a lava light would shine through the rock)
	var/air_could_fire = SSair.can_fire
	SSair.can_fire = FALSE
	var/lighting_could_fire = SSlighting.can_fire
	SSlighting.can_fire = FALSE

	lobby_build_loading = TRUE
	if(lobby_build_lavaland_z)
		var/datum/parsed_map/lavaland = new(file("_maps/map_files/Mining/Lavaland.dmm"))
		if(!lavaland.bounds || !lavaland.load(1, 1, lobby_build_lavaland_z, no_changeturf = TRUE))
			var/msg = "RED ALERT! Lavaland failed to load in the lobby build. Yell at your server host!"
			to_chat(world, "<span class='boldannounce'>[msg]</span>")
			log_world(msg)
		stage = lobby_build_stage("Lavaland", stage)
	seed_startup_ruins()
	stage = lobby_build_stage("ruins", stage)
	lobby_build_loading = FALSE

	// Everything is there. From here on, what's made on these levels initializes as it's made. The levels stay held for
	// ChangeTurf() until the lighting pass below (it leaves their lighting to it, as at startup).
	var/list/held = lobby_build_levels
	var/list/pending = lobby_build_pending
	lobby_build_holding = FALSE
	lobby_build_pending = list()

	var/list/turfs = list()
	var/list/mobs = list()
	var/list/objs = list()
	var/list/areas = list()
	var/list/cables = list()
	var/list/atmos_machines = list()
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
	var/list/held_areas = list()
	for(var/atom/A as anything in pending)
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
	stage = lobby_build_stage("gathering", stage)

	// Startup's order: BYOND's world loop gives mobs, objs, areas, then turfs
	SSatoms.InitializeAtoms(mobs + objs + held_areas + turfs)
	stage = lobby_build_stage("atoms", stage)

	// (areas put themselves in areas_in_z as they initialize, as at startup)
	SSmachines.setup_template_powernets(cables)
	SSair.setup_template_machinery(atmos_machines)
	stage = lobby_build_stage("powernets and pipes", stage)

	// What initializing queued for these levels' turfs, as SSair's startup takes it (process_adjacent_rebuild(TRUE)): walls
	// and space work out their neighbours now, the rest is left to the pass below, and the wakes are dropped (startup clears
	// active_turfs before it). Left in the queue, every turf here would be worked out twice and woken once SSair fires again.
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
	for(var/turf/T as anything in turfs)
		if(T.blocks_air || isspaceturf(T))
			continue
		T.Initalize_Atmos(fired)
		CHECK_TICK
	stage = lobby_build_stage("air", stage)

	// Lighting objects, as create_all_lighting_objects() made them at startup: no light here has been worked out yet
	// (SSlighting is paused), so there's nothing for them to take up until it is. And the lighting engine told of every turf:
	// native_ready() left these levels out, and the engine starts every turf at 0, so one never told anything and still 0
	// needn't be sent.
	for(var/turf/T as anything in turfs)
		var/area/A = T.loc
		if(IS_DYNAMIC_LIGHTING(A) && IS_DYNAMIC_LIGHTING(T) && !T.lighting_object)
			new /atom/movable/lighting_object(T)
		if(T.lighting_engine_pushed == -1 && !T.lighting_engine_flags())
			T.lighting_engine_pushed = 0
		else
			T.lighting_engine_push()
		CHECK_TICK
	stage = lobby_build_stage("lighting", stage)

	lobby_build_levels = null
	SSlighting.can_fire = lighting_could_fire
	SSair.can_fire = air_could_fire

	repopulate_sorted_areas()
	lobby_build_place_docks()
	lobby_build_busy = FALSE
	var/took = (REALTIMEOFDAY - started) / 10
	var/list/parts = list()
	for(var/name in lobby_build_stages)
		parts += "[name] [lobby_build_stages[name]]s"
	lobby_build_status = "done in [took]s: [length(turfs)] turfs, [length(mobs) + length(objs)] things"
	log_world("Lobby build: [lobby_build_status] ([jointext(parts, ", ")])")
	if(lobby_build_sleep_after)
		Master.sleep_offline_after_initializations = TRUE
		if(!length(GLOB.clients))
			world.sleep_offline = TRUE
