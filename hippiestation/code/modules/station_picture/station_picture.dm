// The station picture: one native copy of what each tile is like for getting about, shared by whatever native code needs it, kept
// up to date by the hooks below. The path engine (bot_path_engine.dm, tools/path_engine/src/picture.rs) is the first to use it: it
// keeps each tile's kind between searches and only asks DM about tiles it doesn't know, or that changed since it was told.
//
// A tile is only kept when its answer can't depend on who's asking or change without one of the hooks below hearing of it: a dense
// turf, or open floor with nothing on it but things from station_picture_inert (items, decals, pipes, cables, things on the wall,
// seats) and nobody sat in a seat. Anything else (a door, a window, a table, a machine, a locker, fire, a pool, a hazard) is asked
// about every time, as it always was. So what has to be heard of is only: something that isn't inert arriving, leaving, being
// made or going dense; somebody sitting down or getting up; the turf changing; a tile becoming a hazard or stopping being one.
//
// World param: path-picture=on (the default), off (the path engine asks about every tile, as before 2026-11-09), or check (it asks
// about every tile and counts where the picture would have answered differently: data/path_engine_check.txt).

/// Turfs changed since the path engine was last told (it's told before each search and each round of one)
GLOBAL_LIST_EMPTY(station_picture_dirty)
/// TRUE while something keeps a picture: until then the hooks don't bother
GLOBAL_VAR_INIT(station_picture_kept, FALSE)

/// What can be on a tile without ever being in anybody's way, or turning into something that is. A tile with only these on it has
/// the same answer for every bot and every search.
GLOBAL_LIST_INIT(station_picture_inert, station_picture_inert_types())

/proc/station_picture_inert_types()
	var/list/inert = typecacheof(list(
		/obj/item,
		/obj/effect/decal,
		/obj/effect/landmark,
		/obj/effect/temp_visual,
		/obj/effect/hotspot,
		/obj/effect/particle_effect/smoke,
		/obj/effect/particle_effect/sparks,
		/obj/effect/particle_effect/water,
		/obj/effect/abstract/proximity_checker,
		/obj/effect/dummy/lighting_obj,
		/obj/effect/overlay/vis,
		/obj/structure/cable,
		/obj/structure/disposalpipe,
		/obj/structure/lattice,
		/obj/structure/sign,
		/obj/structure/chair,
		/obj/structure/bed, // a roller bed goes dense with somebody on it: a seated mob is never inert (below)
		/obj/structure/extinguisher_cabinet,
		/obj/structure/fireaxecabinet,
		/obj/structure/noticeboard,
		/obj/machinery/atmospherics/pipe,
		/obj/machinery/atmospherics/components/unary/vent_pump,
		/obj/machinery/atmospherics/components/unary/vent_scrubber,
		/obj/machinery/light,
		/obj/machinery/light_switch,
		/obj/machinery/firealarm,
		/obj/machinery/airalarm,
		/obj/machinery/power/apc,
		/obj/machinery/camera,
		/obj/machinery/status_display,
		/obj/machinery/newscaster,
		/obj/machinery/requests_console,
		/obj/machinery/button,
		/obj/machinery/door_timer,
		/obj/machinery/holopad,
		/obj/machinery/navbeacon,
		/obj/machinery/power/terminal,
		/obj/machinery/conveyor,
	))
	// and out again: kinds that can go dense where they stand
	for(var/type in typesof(/obj/item/powersink, /obj/item/target, /obj/item/mine, /obj/item/storage/pod, /obj/item/storage/secure/safe, \
		/obj/item/gps/computer, /obj/effect/temp_visual/drakewall, /obj/effect/temp_visual/bfs))
		inert -= type
	return inert

/// Whether a movable arriving at, leaving or appearing on a tile could change what the tile allows
/proc/station_picture_matters(atom/movable/AM)
	if(isobj(AM))
		return !GLOB.station_picture_inert[AM.type] || AM.density
	if(ismob(AM))
		var/mob/M = AM
		return M.buckled || istype(M, /mob/living/simple_animal/bot/mulebot) // a parked MULE fills its tile (bot_parked_mule())
	return FALSE

/proc/station_picture_changed(turf/T)
	if(GLOB.station_picture_kept && isturf(T))
		GLOB.station_picture_dirty[T] = TRUE

/// A list of turfs (like GLOB.bot_hazard_turfs) is being replaced: the ones joining or leaving it have changed
/proc/station_picture_list_changed(list/before, list/after)
	if(!GLOB.station_picture_kept)
		return
	var/list/dirty = GLOB.station_picture_dirty
	for(var/turf/T as anything in before)
		if(!after[T])
			dirty[T] = TRUE
	for(var/turf/T as anything in after)
		if(!before[T])
			dirty[T] = TRUE

/// Hands the changed turfs to the path engine and starts afresh. Before each search and each round of one.
/proc/station_picture_flush()
	var/list/dirty = GLOB.station_picture_dirty
	if(length(dirty))
		call_ext(GLOB.path_engine_lib, "byond:path_dirty")(dirty)
		dirty.Cut()

// The hooks

/turf/Entered(atom/movable/AM, atom/OldLoc)
	. = ..()
	if(GLOB.station_picture_kept && station_picture_matters(AM))
		GLOB.station_picture_dirty[src] = TRUE

/turf/Exited(atom/movable/AM, atom/newloc)
	. = ..()
	if(GLOB.station_picture_kept && station_picture_matters(AM))
		GLOB.station_picture_dirty[src] = TRUE

// Made on the spot: BYOND doesn't call Entered() for that (a deleted one goes through Exited(), in moveToNullspace())
/obj/Initialize(mapload)
	. = ..()
	if(GLOB.station_picture_kept && isturf(loc) && station_picture_matters(src))
		GLOB.station_picture_dirty[loc] = TRUE

/turf/ChangeTurf(path, list/new_baseturfs, flags)
	. = ..()
	if(GLOB.station_picture_kept)
		station_picture_changed(.)

// A shuttle docking or leaving: its floor, walls and airlocks are moved in by the shuttle code (onShuttleMove()), not ChangeTurf() or
// Entered(), so the picture went on showing the dock as it was. The mining shuttle came back and nobody could path aboard it: the mech
// miner and the miner on foot both gave up the ride (Bot Shift, 2026-11-12).
/turf/afterShuttleMove(turf/oldT, rotation)
	. = ..()
	if(GLOB.station_picture_kept)
		station_picture_changed(src)
		station_picture_changed(oldT)

/atom/movable/buckle_mob(mob/living/M, force = FALSE, check_loc = TRUE)
	. = ..()
	if(GLOB.station_picture_kept)
		station_picture_changed(get_turf(src))
		station_picture_changed(get_turf(M))

/atom/movable/unbuckle_mob(mob/living/buckled_mob, force = FALSE)
	. = ..()
	if(GLOB.station_picture_kept)
		station_picture_changed(get_turf(src))
		station_picture_changed(get_turf(buckled_mob))
