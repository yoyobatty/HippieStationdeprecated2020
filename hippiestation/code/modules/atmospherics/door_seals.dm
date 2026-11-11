// A shut door's tile keeps sharing air with one side.
//
// A full-tile door used to cut its tile off on every side once it shut, so the tile kept whatever air it had at that moment.
// The room got scrubbed but the doorway didn't, a pipe that burst under a shut door put all its gas on that one tile, and
// opening the door let it all out at once. Now a shut door blocks air on every side but one, the way thin firelocks and
// windoors only block their own edge, and its tile stays part of that side's air: scrubbed, filled and burnt along with it.
// Opening the door then moves only what really differs between the two sides, and no gas is made or lost.
//
// - The side is picked when the door shuts: the one with the higher pressure, since that's where the tile's air came from,
//   and it means an exterior airlock keeps the room's air rather than space's. Another shut door's tile is only taken when
//   there's nothing else, and then this tile shares through that one with whatever it shares with. Ties go north, south,
//   east, west.
// - The tile keeps its side while the door stays shut, since changing sides would carry a tile's worth of air across. It
//   picks again only when that side stops being a way through (a wall built there, a window put up).
// - Two tiles share air when either one picked the other (seal_passes()), which comes out the same from both sides. Each
//   shut tile picks one side, so shut tiles hang off one room and never join two.
// - The turf holds the side (seal_dir), so an airlock and a firelock on the same tile agree on it.
// - No flames sit on a shut door's tile: its air burns along with the room's, but the door isn't in the fire, so a shut
//   airlock holds a fire back as it always has. A fire already there goes out.

/// -params "door-seals=off": a shut door cuts its tile off on every side, as it used to (for comparing)
GLOBAL_VAR_INIT(door_seals, world.params["door-seals"] != "off")

/turf
	/// With a full-tile door shut here, the direction this tile still shares air in. 0 with none shut, SEAL_PENDING while
	/// there's no side to share with.
	var/seal_dir = 0

/obj
	/// A full-tile door: shut, it blocks air on every side but its tile's seal_dir. Wants CanAtmosPass = ATMOS_PASS_PROC.
	var/seals_shut = FALSE

/obj/machinery/door
	seals_shut = TRUE
	CanAtmosPass = ATMOS_PASS_PROC

/obj/machinery/door/window
	seals_shut = FALSE // holds its own edge (windowdoor.dm)

/obj/machinery/door/firedoor/border_only
	seals_shut = FALSE // holds its own edge (firedoor.dm)

/obj/structure/mineral_door
	seals_shut = TRUE
	CanAtmosPass = ATMOS_PASS_PROC

/obj/structure/inflatable/door
	seals_shut = TRUE
	CanAtmosPass = ATMOS_PASS_PROC

/obj/CanAtmosPass(turf/T)
	if(seals_shut && density)
		return seal_passes(loc, T)
	return ..()

/// Whether air goes between `here`, a tile with a shut full-tile door, and `there` next to it: only if one of the two picked
/// the other as the side it shares air with
/proc/seal_passes(turf/here, turf/there)
	if(!isturf(here) || !isturf(there) || here == there)
		return FALSE
	var/dir = get_dir(here, there)
	return here.seal_dir == dir || there.seal_dir == REVERSE_DIR(dir)

/// Something here changed. If it was a door shutting, the tile picks its side as its neighbours are worked out.
/turf/air_update_turf(update = FALSE, remove = FALSE)
	if(update && !seal_dir && GLOB.door_seals)
		seal_dir = SEAL_PENDING
	. = ..()
	if(remove && seal_dir > 0 && !blocks_air)
		SSair.add_to_active(src) // a shut door's tile still shares air with its side, so it isn't put to sleep like a cut-off one

/turf/open/hotspot_expose(exposed_temperature, exposed_volume, soh)
	if(seal_dir)
		return // a shut door here: no flames on it
	return ..()

/obj/effect/hotspot/process()
	var/turf/location = loc
	if(isturf(location) && location.seal_dir)
		qdel(src) // its door shut on it, or it was put straight on a shut door
		return
	return ..()

/// Whether a full-tile door is shut here
/turf/proc/seal_shut()
	for(var/obj/O in contents)
		if(O.seals_shut && O.density && !QDELETED(O))
			return TRUE
	return FALSE

/// Whether air could go between this tile and the one `dir` of it, leaving out the shut doors on either
/turf/proc/seal_side_open(dir)
	var/turf/open/T = get_step(src, dir)
	if(!istype(T) || T.blocks_air || blocks_air)
		return FALSE
	for(var/obj/O in contents)
		if(!(O.seals_shut && O.density) && !CANATMOSPASS(O, T))
			return FALSE
	for(var/obj/O in T.contents)
		if(!(O.seals_shut && O.density) && !CANATMOSPASS(O, src))
			return FALSE
	return TRUE

/// Works out which side this tile shares air with while a door on it is shut (ImmediateCalculateAdjacentTurfs() calls it
/// whenever seal_dir is set). A side it already has is kept while it's still a way through.
/turf/proc/update_seal()
	if(blocks_air || !seal_shut())
		seal_dir = 0
		return
	if(seal_dir > 0 && seal_side_open(seal_dir))
		return
	seal_dir = SEAL_PENDING
	var/best_dir = 0
	var/best_unshut = FALSE
	var/best_pressure = 0
	for(var/dir in GLOB.cardinals)
		if(!seal_side_open(dir))
			continue
		var/turf/open/T = get_step(src, dir)
		if(T.seal_dir == REVERSE_DIR(dir))
			continue // it shares air through this tile already, and taking it as well would shut the two off together
		var/datum/gas_mixture/side_air = T.air
		if(!side_air)
			return // the map's still loading: SSair's setup works it out
		var/unshut = !T.seal_shut()
		var/pressure = side_air.return_pressure()
		if(!best_dir || (unshut && !best_unshut) || (unshut == best_unshut && pressure > best_pressure))
			best_dir = dir
			best_unshut = unshut
			best_pressure = pressure
	if(best_dir)
		seal_dir = best_dir
