// Door seals check: what shut doors do with the air on their tiles, on the real map (door_seals.dm).
// Run it:   tools/atmos_bench/run_atmos_bench.sh door-check
// and with EXTRA_PARAMS="door-seals=off" for how it was before. Use a config without bots (config=data/bench_config), as
// bots open doors.

/proc/atmos_bench_door_check(z)
	. = list("", "Door seals check ([GLOB.door_seals ? "on" : "OFF: shut doors cut their tiles off, as before"])")
	. += door_check_sweep(z)

	// Doors to try: an airlock in a corridor between two rooms, one with space outside, and a tile with an airlock and a firelock
	var/list/obj/machinery/door/airlock/corridor = list()
	var/obj/machinery/door/airlock/exterior
	var/obj/machinery/door/airlock/shared
	var/obj/machinery/door/airlock/glass_door
	for(var/obj/machinery/door/airlock/door in GLOB.airlocks)
		var/turf/open/floor/spot = door.loc
		if(door.z != z || !istype(spot) || istype(spot.loc, /area/shuttle))
			continue
		var/doors_here = 0
		var/firelock_here = FALSE
		for(var/obj/machinery/door/other in spot)
			doors_here++
			if(istype(other, /obj/machinery/door/firedoor) && other.seals_shut)
				firelock_here = TRUE
		var/list/sides = door_check_sides(spot)
		if(length(sides) != 2)
			continue
		var/turf/first = get_step(spot, sides[1])
		var/turf/second = get_step(spot, sides[2])
		if(firelock_here && doors_here == 2 && !shared && istype(first, /turf/open/floor) && istype(second, /turf/open/floor))
			shared = door
		if(doors_here != 1)
			continue
		if(!exterior && (isspaceturf(first) != isspaceturf(second)))
			exterior = door
		if((length(corridor) < 3 || (!glass_door && door.glass)) && istype(first, /turf/open/floor) && istype(second, /turf/open/floor) && !(locate(/obj/machinery/door) in first) && !(locate(/obj/machinery/door) in second))
			if(min(door_check_room_size(first, spot), door_check_room_size(second, spot)) >= (length(corridor) < 3 ? 25 : 12))
				var/far_enough = TRUE
				var/list/picked_doors = corridor.Copy()
				if(glass_door)
					picked_doors += glass_door
				for(var/obj/machinery/door/airlock/picked as anything in picked_doors)
					if(get_dist(picked, door) < 20)
						far_enough = FALSE
				if(far_enough)
					if(length(corridor) < 3)
						corridor += door
					else
						glass_door = door
	if(length(corridor) < 3)
		. += "  only [length(corridor)] corridor airlocks found, needs 3"
		return

	. += door_check_trapped(corridor[1])
	. += door_check_burst(corridor[2])
	if(exterior)
		. += door_check_exterior(exterior)
	else
		. += "  no airlock with space on one side"
	if(shared)
		. += door_check_shared(shared)
	else
		. += "  no tile with an airlock and a firelock"
	. += door_check_fire(corridor[3])
	if(glass_door)
		. += door_check_fire(glass_door)
	else
		. += "  no glass corridor airlock"
	. += door_check_sweep(z)

/// Every shut door's tile on the z-level: does it share air with one side, and nothing it shouldn't?
/proc/door_check_sweep(z)
	var/shut = 0
	var/sharing = 0
	var/list/cut_off = list()
	var/list/joined = list()
	var/list/wrong = list()
	var/stale = 0
	var/cut_off_could = 0
	var/list/spots = list()
	for(var/obj/machinery/door/door in GLOB.airlocks)
		if(door.z == z && isopenturf(door.loc) && door.seals_shut && door.density)
			spots[door.loc] = TRUE
	for(var/turf/open/spot as anything in spots)
		shut++
		if(spot.seal_dir > 0)
			sharing++
		else
			var/why = door_check_why_cut_off(spot)
			if(findtext(why, "open?") || findtext(why, "picked"))
				cut_off.Insert(1, "([spot.x],[spot.y]) [why]") // could share and doesn't: these first
				cut_off_could++
			else
				cut_off += "([spot.x],[spot.y]) [why]"
		for(var/turf/open/neighbour as anything in spot.atmos_adjacent_turfs)
			var/dir = get_dir(spot, neighbour)
			if(spot.seal_dir != dir && neighbour.seal_dir != REVERSE_DIR(dir))
				joined += "([spot.x],[spot.y]) [dir2text(dir)]"
		if(length(atmos_bench_wrong_connections(spot)))
			wrong += "([spot.x],[spot.y])"
		if(spot.seal_dir > 0)
			var/turf/open/side = get_step(spot, spot.seal_dir)
			if(abs(spot.air.return_pressure() - side.air.return_pressure()) > 5)
				stale++
	. = list("  [shut] tiles with a shut door: [sharing] share air with a side, [length(cut_off)] cut off ([GLOB.door_seals ? cut_off_could : "all"] that COULD share), [length(joined)] JOINED to a side they didn't pick, [length(wrong)] with WRONG connections, [stale] more than 5 kPa off their side")
	if(length(cut_off))
		. += "    cut off: [jointext(cut_off.Copy(1, min(length(cut_off), 12) + 1), "\n      ")]"
	if(length(joined))
		. += "    joined: [jointext(joined.Copy(1, min(length(joined), 12) + 1), " ")]"
	if(length(wrong))
		. += "    wrong: [jointext(wrong.Copy(1, min(length(wrong), 12) + 1), " ")]"

/// What's on each side of a shut door's tile that has no side to share air with
/proc/door_check_why_cut_off(turf/open/spot)
	var/list/sides = list()
	for(var/dir in GLOB.cardinals)
		var/turf/T = get_step(spot, dir)
		var/what
		if(!isopenturf(T) || T.blocks_air)
			what = "wall"
		else if(!spot.seal_side_open(dir))
			var/list/blockers = list()
			for(var/obj/O in spot.contents + T.contents)
				if(!(O.seals_shut && O.density) && !CANATMOSPASS(O, O.loc == spot ? T : spot))
					blockers += "[O.type]"
			what = "blocked by [jointext(blockers, "+")]"
		else if(T.seal_dir == REVERSE_DIR(dir))
			what = "shut door that picked this"
		else
			what = "open?"
		sides += "[copytext(dir2text(dir), 1, 2)]:[what]"
	return "\[[jointext(sides, ", ")]\]"

/// Directions from `spot` with open floor or space, leaving out what isn't air at all
/proc/door_check_sides(turf/open/spot)
	. = list()
	for(var/dir in GLOB.cardinals)
		var/turf/T = get_step(spot, dir)
		if(isopenturf(T) && !T.blocks_air)
			. += dir

/// The tiles sharing air with `start` within `reach` of it, without going through `skip`
/proc/door_check_region(turf/open/start, turf/skip, reach = 12)
	var/list/found = list(start)
	var/list/seen = list()
	seen[start] = TRUE
	var/i = 1
	while(i <= length(found))
		var/turf/open/T = found[i++]
		for(var/turf/open/N as anything in T.atmos_adjacent_turfs)
			if(N == skip || seen[N] || get_dist(N, start) > reach)
				continue
			seen[N] = TRUE
			found += N
	return found

/// Tiles without doors near `start`, so both ways of running this pick the same doors
/proc/door_check_room_size(turf/open/start, turf/skip)
	. = 0
	for(var/turf/T as anything in door_check_region(start, skip))
		if(!(locate(/obj/machinery/door) in T))
			.++

/proc/door_check_plasma(list/turfs)
	. = 0
	for(var/turf/open/T as anything in turfs)
		. += T.air.moles[/datum/gas/plasma] || 0

/proc/door_check_scrub(list/turfs)
	for(var/turf/open/T as anything in turfs)
		var/datum/gas_mixture/air = T.return_air()
		if(air.moles[/datum/gas/plasma])
			air.moles[/datum/gas/plasma] = 0
			air.garbage_collect()
			SSair.add_to_active(T)

/proc/door_check_add_plasma(turf/open/T, amount)
	var/datum/gas_mixture/air = T.return_air()
	air.assert_gas(/datum/gas/plasma)
	air.moles[/datum/gas/plasma] += amount
	SSair.add_to_active(T)

/// So the check decides when it opens and shuts
/proc/door_check_hold(obj/machinery/door/door)
	door.autoclose = FALSE
	door.welded = FALSE
	if(istype(door, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/airlock = door
		airlock.locked = FALSE
		airlock.emergency = FALSE
	door.safe = FALSE

/proc/door_check_open(obj/machinery/door/door)
	if(istype(door, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/airlock = door
		airlock.open(2)
	else
		door.open()
	sleep(1 SECONDS)

/proc/door_check_shut(obj/machinery/door/door)
	if(istype(door, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/airlock = door
		airlock.close(2)
	else
		door.close()
	sleep(1 SECONDS)

/proc/door_check_side_text(turf/open/spot)
	if(spot.seal_dir > 0)
		return "shares air [dir2text(spot.seal_dir)]"
	return "cut off"

/proc/door_check_where(atom/A)
	return "([A.x],[A.y]) in [get_area_name(A, TRUE)]"

/// Plasma on the doorway when it shuts, both sides scrubbed, then opened
/proc/door_check_trapped(obj/machinery/door/airlock/door)
	var/turf/open/spot = door.loc
	door_check_hold(door)
	door_check_open(door)
	var/list/sides = door_check_sides(spot)
	var/list/near = door_check_region(get_step(spot, sides[1]), spot) | door_check_region(get_step(spot, sides[2]), spot)
	near -= spot
	. = list("", "  Plasma in a doorway when it shuts: airlock at [door_check_where(door)]")
	door_check_add_plasma(spot, 3000)
	sleep(2 SECONDS)
	door_check_shut(door)
	. += "    shut with [round(door_check_plasma(list(spot)))] mol of plasma on its tile, which [door_check_side_text(spot)]"
	for(var/i in 1 to 30)
		door_check_scrub(near)
		sleep(1 SECONDS)
	door_check_scrub(near)
	. += "    both sides scrubbed for 30 s: [round(door_check_plasma(list(spot)), 0.1)] mol left on the door's tile"
	door_check_open(door)
	sleep(5 SECONDS)
	. += "    opened, 5 s on: [round(door_check_plasma(near + spot), 0.1)] mol of plasma about the doorway"
	door_check_shut(door)

/// A pipe bursts under a shut door
/proc/door_check_burst(obj/machinery/door/airlock/door)
	var/turf/open/spot = door.loc
	door_check_hold(door)
	door_check_open(door)
	var/list/sides = door_check_sides(spot)
	var/list/near = door_check_region(get_step(spot, sides[1]), spot) | door_check_region(get_step(spot, sides[2]), spot)
	near -= spot
	door_check_shut(door)
	. = list("", "  A pipe bursts under a shut airlock at [door_check_where(door)], which [door_check_side_text(spot)]")
	var/datum/gas_mixture/burst = new
	burst.assert_gas(/datum/gas/plasma)
	burst.moles[/datum/gas/plasma] = 3000
	burst.temperature = T20C
	spot.assume_air(burst)
	SSair.add_to_active(spot)
	sleep(10 SECONDS)
	. += "    10 s on: [round(door_check_plasma(list(spot)))] mol of the 3000 still on the door's tile, [round(door_check_plasma(near))] in the rooms"
	for(var/i in 1 to 30)
		door_check_scrub(near)
		sleep(1 SECONDS)
	door_check_scrub(near)
	. += "    rooms scrubbed for 30 s: [round(door_check_plasma(list(spot)), 0.1)] mol left on the door's tile"
	door_check_open(door)
	sleep(5 SECONDS)
	. += "    opened, 5 s on: [round(door_check_plasma(near + spot), 0.1)] mol of plasma about the doorway"
	door_check_shut(door)

/// An airlock with space on one side keeps the room's air
/proc/door_check_exterior(obj/machinery/door/airlock/door)
	var/turf/open/spot = door.loc
	door_check_hold(door)
	if(!door.density)
		door_check_shut(door)
	var/turf/open/room
	for(var/dir in door_check_sides(spot))
		var/turf/T = get_step(spot, dir)
		if(!isspaceturf(T))
			room = T
	. = list("", "  Airlock with space outside at [door_check_where(door)]: its tile [door_check_side_text(spot)][spot.seal_dir > 0 ? (isspaceturf(get_step(spot, spot.seal_dir)) ? " (SPACE)" : " (the room)") : ""], [round(spot.air.return_pressure(), 0.1)] kPa against the room's [round(room.air.return_pressure(), 0.1)] kPa")

/// An airlock and a firelock on one tile agree on the side
/proc/door_check_shared(obj/machinery/door/airlock/door)
	var/turf/open/spot = door.loc
	var/obj/machinery/door/firedoor/firelock = locate() in spot
	door_check_hold(door)
	door_check_hold(firelock)
	if(!door.density)
		door_check_shut(door)
	if(!firelock.density)
		door_check_shut(firelock)
	. = list("", "  Airlock and firelock on one tile at [door_check_where(door)]")
	. += "    both shut: [length(spot.atmos_adjacent_turfs)] sides sharing air, [door_check_side_text(spot)]"
	door_check_open(door)
	. += "    airlock open, firelock shut: [length(spot.atmos_adjacent_turfs)] sides, [door_check_side_text(spot)]"
	door_check_open(firelock)
	. += "    both open: [length(spot.atmos_adjacent_turfs)] sides, [door_check_side_text(spot)]"
	door_check_shut(door)
	door_check_shut(firelock)
	. += "    both shut again: [length(spot.atmos_adjacent_turfs)] sides, [door_check_side_text(spot)]"

/// A plasma fire on the side a shut airlock's tile shares air with
/proc/door_check_fire(obj/machinery/door/airlock/door)
	var/turf/open/spot = door.loc
	door_check_hold(door)
	if(!door.density)
		door_check_shut(door)
	var/list/sides = door_check_sides(spot)
	var/fire_dir = spot.seal_dir > 0 ? spot.seal_dir : sides[1]
	var/far_dir = (fire_dir == sides[1]) ? sides[2] : sides[1]
	var/turf/open/fire_side = get_step(spot, fire_dir)
	var/list/far = door_check_region(get_step(spot, far_dir), spot, 6) - door_check_region(get_step(spot, fire_dir), spot) // not what the fire's side reaches round another way
	var/integrity = door.obj_integrity
	for(var/turf/open/floor/F in range(2, fire_side))
		if(F == spot)
			continue
		var/datum/gas_mixture/fire_air = F.return_air()
		fire_air.assert_gases(/datum/gas/plasma, /datum/gas/oxygen)
		fire_air.moles[/datum/gas/plasma] += 60
		fire_air.moles[/datum/gas/oxygen] += 40
		SSair.add_to_active(F)
	fire_side.hotspot_expose(1000, CELL_VOLUME)
	var/turf/open/behind = get_step(spot, far_dir)
	var/hottest = 0
	var/behind_hottest = 0
	var/far_hottest = 0
	var/turf/far_hottest_at = behind
	var/burnt_ticks = 0
	for(var/i in 1 to 45)
		sleep(1 SECONDS)
		hottest = max(hottest, spot.air.temperature)
		behind_hottest = max(behind_hottest, behind.air.temperature)
		if(spot.active_hotspot)
			burnt_ticks++
		for(var/turf/open/T as anything in far)
			if(T.air.temperature > far_hottest)
				far_hottest = T.air.temperature
				far_hottest_at = T
	. = list("", "  Plasma fire [dir2text(fire_dir)] of a shut [door.glass ? "glass " : ""]airlock at [door_check_where(spot)], whose tile [door_check_side_text(spot)]")
	. += "    45 s: door's tile up to [round(hottest - T0C)] C, on fire [burnt_ticks] of 45 s; airlock [QDELETED(door) ? "DESTROYED" : "at [round(door.obj_integrity)] of [round(integrity)]"]; the tile behind it up to [round(behind_hottest - T0C)] C, anywhere within 6 behind it [round(far_hottest - T0C)] C (at ([far_hottest_at.x],[far_hottest_at.y]))"
