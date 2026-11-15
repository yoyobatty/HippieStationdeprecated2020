// Atmos A/B scenes (tools/atmos_ab/ab.py): small seeded atmos scenes on a testkit server. ab.py runs the same scenes on two
// servers (A and B, different world params or vars) and prints what each cost and how the air came out, side by side.
//
// Scenes (atmos_ab_scene(scene, seconds, seed)):
//   calm     the testbench station's own air, pipes, vents and scrubbers, with "people" breathing on fixed tiles
//   release  2000 mol of N2O let out in a closed room
//   fire     plasma over a third of a room, lit
//   breach   two rooms joined by a doorway, a hole to space in the far one
// The rooms are built afresh in reserved space every run, so runs start the same. Each returns the time SSair spent by stage
// (ms per game second) and samples of the air every quarter of the scene.

#ifdef TESTKIT_BUILD

#define ATMOS_AB_W 24
#define ATMOS_AB_H 14

GLOBAL_DATUM(atmos_ab_reservation, /datum/turf_reservation)
GLOBAL_LIST_EMPTY(atmos_ab_station)

/// Runs one scene and returns what came of it
/proc/atmos_ab_scene(scene = "calm", seconds = 20, seed = 1)
	seconds = text2num("[seconds]") || 20
	seed = text2num("[seed]") || 1
	var/started = REALTIMEOFDAY
	rand_seed(seed)
	var/list/turf/open/watched
	var/list/turf/open/breathers
	if(scene == "calm")
		watched = atmos_ab_station_turfs()
		breathers = list()
		for(var/i in 1 to min(40, length(watched)))
			breathers += watched[rand(1, length(watched))]
	else
		watched = atmos_ab_room(scene == "breach")
		sleep(2 SECONDS) // the new room's air settles in
		atmos_ab_set_off(scene, watched)
		watched = atmos_ab_floors() // the hole is space now

	// Timing: the atmos bench's stage timers, and the tile engine's own counters
	var/list/stage_before = GLOB.atmos_bench_stage_ms.Copy()
	var/list/engine_before = list(SSair.tile_engine_pack_ms, SSair.tile_engine_native_ms, SSair.tile_engine_apply_ms)
	var/list/parts_before = SSair.tile_engine_apply_parts.Copy()
	var/fires_before = SSair.times_fired
	GLOB.atmos_bench_recording = TRUE
	var/list/samples = list(atmos_ab_sample(watched, 0))
	var/start = world.time
	var/next_sample = 1
	while(world.time - start < seconds SECONDS)
		if(breathers)
			for(var/turf/open/T as anything in breathers) // half a litre of air in, a bit less out, each tick of the loop
				if(isopenturf(T))
					var/datum/gas_mixture/breath = T.remove_air(0.02)
					if(breath)
						breath.moles[/datum/gas/oxygen] = 0
						T.assume_air(breath)
						T.air_update_turf()
		sleep(5)
		if(world.time - start >= next_sample * seconds SECONDS / 4)
			samples += list(atmos_ab_sample(watched, round((world.time - start) / 10, 0.1)))
			next_sample++
	GLOB.atmos_bench_recording = FALSE
	var/game_seconds = max(0.1, (world.time - start) / 10)

	var/list/ms = list()
	for(var/stage in GLOB.atmos_bench_stage_ms)
		ms[stage] = round((GLOB.atmos_bench_stage_ms[stage] - (stage_before[stage] || 0)) / game_seconds, 0.001)
	ms["engine: packing"] = round((SSair.tile_engine_pack_ms - engine_before[1]) / game_seconds, 0.001)
	ms["engine: native"] = round((SSair.tile_engine_native_ms - engine_before[2]) / game_seconds, 0.001)
	ms["engine: following up"] = round((SSair.tile_engine_apply_ms - engine_before[3]) / game_seconds, 0.001)
	for(var/part in SSair.tile_engine_apply_parts)
		ms["follow-up: [part]"] = round((SSair.tile_engine_apply_parts[part] - (parts_before[part] || 0)) / game_seconds, 0.001)
	return list(
		"scene" = scene,
		"seed" = seed,
		"game_seconds" = game_seconds,
		"fires" = SSair.times_fired - fires_before,
		"real_seconds" = round((REALTIMEOFDAY - started) / 10, 0.1),
		"engine" = SSair.tile_engine ? "engine" : "linda",
		"ms_per_s" = ms,
		"samples" = samples,
	)

/// The station's open turfs with air, in a fixed order
/proc/atmos_ab_station_turfs()
	if(length(GLOB.atmos_ab_station))
		return GLOB.atmos_ab_station
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(!isspaceturf(T) && T.air && istype(T.loc, /area) && !istype(T.loc, /area/space))
			GLOB.atmos_ab_station += T
	return GLOB.atmos_ab_station

/// Builds the room afresh: ATMOS_AB_W x ATMOS_AB_H of floor in indestructible walls. `split` puts a wall down the middle with
/// a two-tile doorway. Returns the floors.
/proc/atmos_ab_room(split)
	var/datum/turf_reservation/R = GLOB.atmos_ab_reservation
	if(!R)
		R = SSmapping.RequestBlockReservation(ATMOS_AB_W + 2, ATMOS_AB_H + 2)
		GLOB.atmos_ab_reservation = R
	var/list/low = R.bottom_left_coords
	var/list/high = R.top_right_coords
	var/middle_x = low[1] + round(ATMOS_AB_W / 2)
	var/door_y = low[2] + round(ATMOS_AB_H / 2)
	for(var/turf/T as anything in R.reserved_turfs)
		for(var/atom/movable/AM as anything in T.contents.Copy())
			if(!istype(AM, /atom/movable/lighting_object) && !isobserver(AM))
				qdel(AM, force = TRUE)
		var/edge = T.x == low[1] || T.x == high[1] || T.y == low[2] || T.y == high[2]
		var/wall = edge || (split && T.x == middle_x && T.y != door_y && T.y != door_y + 1)
		T.ChangeTurf(wall ? /turf/closed/indestructible/riveted : /turf/open/floor/plasteel)
		if(!wall)
			var/turf/open/F = T
			var/datum/gas_mixture/air = F.return_air() // marks it touched, so the tile engine is sent the new air
			air.parse_gas_string(OPENTURF_DEFAULT_ATMOS) // the same air every run, whatever the last run left
			F.air_update_turf()
	return atmos_ab_floors()

/// The room's open turfs (floors, and the hole once it's there), bottom row first
/proc/atmos_ab_floors()
	. = list()
	var/datum/turf_reservation/R = GLOB.atmos_ab_reservation
	for(var/turf/open/T in R.reserved_turfs)
		. += T

/// The event the scene is about
/proc/atmos_ab_set_off(scene, list/turf/open/floors)
	var/list/low = GLOB.atmos_ab_reservation.bottom_left_coords
	var/x0 = low[1]
	var/y0 = low[2]
	var/z = low[3]
	switch(scene)
		if("release")
			var/turf/open/T = locate(x0 + 3, y0 + round(ATMOS_AB_H / 2), z)
			T.atmos_spawn_air("n2o=2000;TEMP=293.15")
		if("fire") // as the atmos bench lights its fire: plasma and oxygen on a 5 by 5 patch, then a spark
			var/turf/open/spark = locate(x0 + 4, y0 + round(ATMOS_AB_H / 2), z)
			for(var/turf/open/floor/F in range(2, spark))
				var/datum/gas_mixture/fire_air = F.return_air()
				fire_air.assert_gases(/datum/gas/plasma, /datum/gas/oxygen)
				fire_air.moles[/datum/gas/plasma] += 60
				fire_air.moles[/datum/gas/oxygen] += 40
				fire_air.temperature = 1000 // lit all over: a spark alone can fizzle out in a room this small
				SSair.add_to_active(F)
			spark.hotspot_expose(1000, CELL_VOLUME)
		if("breach")
			var/turf/T = locate(x0 + ATMOS_AB_W - 1, y0 + round(ATMOS_AB_H / 2), z)
			T.ChangeTurf(/turf/open/space)

/// One look at the air over the watched turfs
/proc/atmos_ab_sample(list/turf/open/turfs, t)
	var/mol = 0
	var/kpa = 0
	var/kpa_min = INFINITY
	var/low = 0
	var/n2o_tiles = 0
	var/burning = 0
	var/hottest = 0
	var/plasma = 0
	var/windy = 0
	var/count = 0
	for(var/turf/open/T as anything in turfs)
		if(!isopenturf(T) || isspaceturf(T))
			continue
		var/datum/gas_mixture/air = T.air
		if(!air)
			continue
		count++
		var/total = air.total_moles()
		mol += total
		var/pressure = air.return_pressure()
		kpa += pressure
		kpa_min = min(kpa_min, pressure)
		if(pressure < 20)
			low++
		var/list/moles = air.moles
		if(moles[/datum/gas/nitrous_oxide] >= 1)
			n2o_tiles++
		plasma += moles[/datum/gas/plasma]
		if(T.active_hotspot)
			burning++
		hottest = max(hottest, air.temperature)
		if(T.pressure_difference)
			windy++
	return list(
		"t" = t,
		"mol" = round(mol, 0.1),
		"kpa_mean" = round(count ? kpa / count : 0, 0.01),
		"kpa_min" = round(count ? kpa_min : 0, 0.01),
		"under_20kpa" = low,
		"n2o_tiles" = n2o_tiles,
		"burning" = burning,
		"hottest_k" = round(hottest, 0.1),
		"plasma_mol" = round(plasma, 0.1),
		"windy" = windy,
	)

#undef ATMOS_AB_W
#undef ATMOS_AB_H

#endif

#ifdef TESTKIT_BUILD
/// Over `fires` SSair fires: which machine types ran process_atmos() and how often a fire, and how many of the runs found
/// their turf's pressure within 1 kPa of where a vent wants it (a top-up)
/proc/atmos_ab_awake(fires = 40)
	var/list/runs = list()
	spawn(0) // people breathing, as in the calm scene
		var/list/turf/open/station = atmos_ab_station_turfs()
		var/list/turf/open/breathers = list()
		rand_seed(1)
		for(var/i in 1 to 40)
			breathers += station[rand(1, length(station))]
		var/until = world.time + fires * 6
		while(world.time < until)
			for(var/turf/open/T as anything in breathers)
				var/datum/gas_mixture/breath = T.remove_air(0.02)
				if(breath)
					breath.moles[/datum/gas/oxygen] = 0
					T.assume_air(breath)
					T.air_update_turf()
			sleep(5)
	var/list/worked = list()
	var/start = SSair.times_fired
	var/list/obj/machinery/last
	while(SSair.times_fired - start < fires)
		var/seen = SSair.times_fired
		if(last) // the ones that ran in the fire just gone: did they move gas (update_parents())?
			for(var/obj/machinery/atmospherics/M in last)
				if(M.atmos_ab_moved_at == seen - 1) // stamped during the fire just gone, before times_fired went up
					worked["[M.type]"] += 1
		last = SSair.atmos_awake.Copy()
		for(var/obj/machinery/M as anything in last)
			if(M)
				runs["[M.type]"] += 1
		while(SSair.times_fired == seen)
			sleep(1)
	for(var/k in runs)
		runs[k] = "[round(runs[k] / fires, 0.1)] ran, [round(worked[k] / fires, 0.1)] moved gas"
	return runs

/obj/machinery/atmospherics
	var/tmp/atmos_ab_moved_at = 0

/obj/machinery/atmospherics/components/update_parents()
	atmos_ab_moved_at = SSair.times_fired
	return ..()
#endif
