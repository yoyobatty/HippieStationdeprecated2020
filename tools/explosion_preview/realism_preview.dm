// Realistic explosions (hippiestation/code/modules/explosion_realism/), checked and pictured on the real station (run_realism.sh,
// headless). Not part of the game.
//  - pictures: rooms with realism off and on, a sealed closet, a bomb outside the hull, a room let down to 30 kPa
//  - totals: tiles hit at 150 random spots, off against on, and what working it out costs
//  - live: real bombs in the closet, the bar and outside the hull, with what they did to the air, the glass and the lights

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("explosion-realism-preview" in world.params)
		sleep_offline_after_initializations = FALSE // nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(xr_run))
	return ..()

/proc/xr_run()
	UNTIL(Master.current_runlevel)
	sleep(5 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	if(SSticker.current_state < GAME_STATE_PLAYING)
		xp_log("The round never started")
		xp_log("done")
		return
	sleep(5 SECONDS)
	rand_seed(1113)
	var/list/sizes = list("minibomb" = list(1, 2, 4), "medium" = list(2, 4, 8), "maxcap" = list(5, 10, 20))
	xp_log("Map: [SSmapping.config.map_name]. Realism is [GLOB.explosion_realism ? "on" : "off"] on this server.")

	// pictures
	var/list/named = list(
		"Toxins" = /area/science/mixing,
		"Bar" = /area/crew_quarters/bar,
		"Central hallway" = /area/hallway/primary/central,
		"Medbay" = /area/medical/medbay/central,
	)
	var/list/middles = list()
	for(var/name in named)
		var/turf/T = xr_middle(locate(named[name]) in GLOB.sortedAreas)
		if(!T)
			xp_log("No [name] on this map")
			continue
		middles[name] = T
		xr_dump(name, T, sizes["medium"])
	if(middles["Bar"])
		xr_dump("Bar maxcap", middles["Bar"], sizes["maxcap"])
	var/turf/closet = xr_find_closet()
	if(closet)
		xr_dump("Sealed closet minibomb", closet, sizes["minibomb"])
		xr_dump("Sealed closet medium", closet, sizes["medium"])
	var/turf/outside = xr_find_outside()
	if(outside)
		xr_dump("Outside the hull", outside, sizes["medium"])
	if(middles["Medbay"])
		var/area/medbay = get_area(middles["Medbay"])
		xr_scale_air(medbay, 0.3)
		xr_dump("Medbay at 30 kPa", middles["Medbay"], sizes["medium"])
		xr_scale_air(medbay, 1 / 0.3)

	// totals
	var/list/station = list()
	for(var/z in SSmapping.levels_by_trait(ZTRAIT_STATION))
		for(var/turf/open/floor/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			if(istype(T.loc, /area/space) || istype(T.loc, /area/shuttle))
				continue
			station += T
	var/list/spots = list()
	for(var/i in 1 to 150)
		spots += pick(station)
	for(var/size_name in sizes)
		var/list/s = sizes[size_name]
		var/list/off = list(0, 0, 0, 0)
		var/list/on = list(0, 0, 0, 0)
		var/off_ms = 0
		var/on_ms = 0
		for(var/turf/T as anything in spots)
			var/start = TICK_USAGE_REAL
			var/list/before = explosion_severity_map(T, s[1], s[2], s[3], "native", FALSE)
			off_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			start = TICK_USAGE_REAL
			var/list/after = explosion_severity_map(T, s[1], s[2], s[3], "native", TRUE)
			on_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			for(var/turf/A as anything in before)
				off[before[A]]++
			for(var/turf/A as anything in after)
				on[after[A]]++
			CHECK_TICK
		// where the time goes, with realism on
		var/air_ms = 0
		var/block_ms = 0
		var/room_ms = 0
		var/shape_ms = 0
		for(var/turf/T as anything in spots)
			var/start = TICK_USAGE_REAL
			var/list/real = explosion_realism_ranges(T, s[1], s[2], s[3], 0)
			room_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			var/reach = max(real[1], real[2], real[3], real[5])
			var/list/affected = SSexplosions.GatherSpiralTurfs(reach, T)
			start = TICK_USAGE_REAL
			var/was_realism = GLOB.explosion_realism
			GLOB.explosion_realism = FALSE
			var/list/blocks = SSexplosions.CaculateExplosionBlock(affected)
			GLOB.explosion_realism = was_realism
			block_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			start = TICK_USAGE_REAL
			GLOB.explosion_realism = TRUE
			SSexplosions.CaculateExplosionBlock(affected)
			GLOB.explosion_realism = was_realism
			air_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			start = TICK_USAGE_REAL
			explosion_shape(T, reach, blocks)
			shape_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			CHECK_TICK
		var/n = length(spots)
		xp_log("[size_name] cost with realism, a blast: ranges and room [round(room_ms / n, 0.01)] ms, blocks [round(block_ms / n, 0.01)] ms, blocks with the air on the way [round(air_ms / n, 0.01)] ms, shape [round(shape_ms / n, 0.01)] ms")
		xp_log("[size_name] ([s[1]], [s[2]], [s[3]]) at [length(spots)] spots: off [off[1]] devastated, [off[2]] heavy, [off[3]] light; on [on[1]], [on[2]], [on[3]], and [on[4]] glass only. Worked out in [round(off_ms / length(spots), 0.01)] ms off, [round(on_ms / length(spots), 0.01)] ms on")

	// live
	if(closet)
		xr_live("Sealed closet minibomb", closet, sizes["minibomb"])
	if(middles["Bar"])
		xr_live("Bar medium", middles["Bar"], sizes["medium"])
	if(outside)
		xr_live("Outside the hull medium", outside, sizes["medium"])
	if(middles["Central hallway"])
		xr_people("Central hallway medium, people standing east, lying west", middles["Central hallway"], sizes["medium"])
	if(middles["Medbay"])
		xr_grenade("Medbay minibomb (a real one)", middles["Medbay"])
	for(var/hallway in list(/area/hallway/primary/port, /area/hallway/primary/starboard, /area/hallway/primary/fore, /area/hallway/primary/aft))
		var/turf/T = xr_middle(locate(hallway) in GLOB.sortedAreas)
		if(T)
			xr_doors("[get_area_name(T, TRUE)] medium, airlocks 2-3 tiles off", T, sizes["medium"])
			break
	xr_pile()
	xp_log("done")
	Master.Shutdown()
	qdel(world)

/// The floor nearest the middle of an area
/proc/xr_middle(area/A)
	if(!A)
		return null
	var/list/floors = list()
	for(var/turf/open/floor/T in A)
		floors += T
	if(!length(floors))
		return null
	var/sx = 0
	var/sy = 0
	for(var/turf/T as anything in floors)
		sx += T.x
		sy += T.y
	sx /= length(floors)
	sy /= length(floors)
	var/turf/middle
	for(var/turf/T as anything in floors)
		if(!middle || abs(T.x - sx) + abs(T.y - sy) < abs(middle.x - sx) + abs(middle.y - sy))
			middle = T
	return middle

/// How many tiles of air are joined to a turf, counting up to `most`
/proc/xr_room_size(turf/start, most)
	var/list/reached = list()
	reached[start] = TRUE
	var/list/room = list(start)
	var/at = 1
	while(at <= length(room) && length(room) < most)
		var/turf/T = room[at++]
		for(var/turf/A as anything in T.atmos_adjacent_turfs)
			if(!reached[A])
				reached[A] = TRUE
				room += A
	return length(room)

/// A small sealed room with air in it: the station area whose middle is joined to the fewest tiles of air, 6 at least
/proc/xr_find_closet()
	var/turf/best
	var/best_size = INFINITY
	for(var/area/A in GLOB.sortedAreas)
		if(!(A.z in SSmapping.levels_by_trait(ZTRAIT_STATION)) || istype(A, /area/space) || istype(A, /area/shuttle))
			continue
		var/turf/T = xr_middle(A)
		if(!T || blast_air_factor(T) < 0.95)
			continue
		var/size = xr_room_size(T, 60)
		if(size >= 6 && size < best_size)
			best = T
			best_size = size
	if(best)
		xp_log("Sealed closet: [get_area_name(best, TRUE)] at [best.x],[best.y], [best_size] tiles of air")
	return best

/// Space just outside a window of the station, nearest the middle of the station
/proc/xr_find_outside()
	var/list/zs = SSmapping.levels_by_trait(ZTRAIT_STATION)
	if(!length(zs))
		return null
	var/turf/middle = xr_middle(locate(/area/hallway/primary/central) in GLOB.sortedAreas)
	var/turf/best
	for(var/turf/open/space/S in block(locate(1, 1, zs[1]), locate(world.maxx, world.maxy, zs[1])))
		if(!istype(S.loc, /area/space))
			continue
		var/by_window = FALSE
		for(var/direction in GLOB.cardinals)
			var/turf/next = get_step(S, direction)
			if(next && (locate(/obj/structure/window) in next))
				by_window = TRUE
				break
		if(!by_window)
			continue
		var/open_space = 0 //really outside: mostly space round it, not a pocket of it inside the station
		for(var/turf/open/space/near in range(2, S))
			open_space++
		if(open_space < 12)
			continue
		if(!best || !middle || get_dist(S, middle) < get_dist(best, middle))
			best = S
	if(best)
		xp_log("Outside the hull: [best.x],[best.y], next to [get_area_name(get_step(best, get_dir(best, middle)), TRUE)]")
	return best

/// Scales all the air in an area, every gas
/proc/xr_scale_air(area/A, factor)
	for(var/turf/open/T in A)
		if(!T.air)
			continue
		for(var/gas in T.air.moles)
			T.air.moles[gas] *= factor

/// Realism off against on, for render.py
/proc/xr_dump(name, turf/epicenter, list/s)
	var/list/real = explosion_realism_ranges(epicenter, s[1], s[2], s[3], 0)
	var/range = max(s[3], real[5]) + 2
	var/list/off = explosion_severity_map(epicenter, s[1], s[2], s[3], "native", FALSE)
	var/list/on = explosion_severity_map(epicenter, s[1], s[2], s[3], "native", TRUE)
	var/list/counts_off = list(0, 0, 0, 0)
	var/list/counts_on = list(0, 0, 0, 0)
	for(var/turf/T as anything in off)
		counts_off[off[T]]++
	for(var/turf/T as anything in on)
		counts_on[on[T]]++
	var/list/rows = list()
	for(var/y in epicenter.y + range to epicenter.y - range step -1)
		var/list/row = list()
		for(var/x in epicenter.x - range to epicenter.x + range)
			var/turf/T = locate(x, y, epicenter.z)
			if(!T)
				row += list(list("none", 0, 0))
				continue
			row += list(list(xp_kind(T), off[T] || 0, on[T] || 0))
		rows += list(row)
	var/note = "air x[round(real[6], 0.01)], room x[round(real[7], 0.01)], ranges ([round(real[1], 0.1)], [round(real[2], 0.1)], [round(real[3], 0.1)]), glass to [round(real[5], 0.1)]"
	xp_log("[name] ([get_area_name(epicenter, TRUE)], [epicenter.x],[epicenter.y]), ([s[1]], [s[2]], [s[3]]): [note]. Off [counts_off[1]]/[counts_off[2]]/[counts_off[3]], on [counts_on[1]]/[counts_on[2]]/[counts_on[3]] and [counts_on[4]] glass only")
	var/list/out = list("name" = name, "area" = get_area_name(epicenter, TRUE), "x" = epicenter.x, "y" = epicenter.y, "size" = s, "rows" = rows,
		"titles" = list("Realism off", "Realism on"), "note" = note)
	text2file(json_encode(out), "data/explosion_preview/[replacetext(name, " ", "_")].json")

/// A real bomb: what it did to the air, the glass and the lights, by the ring each was in
/proc/xr_live(name, turf/epicenter, list/s)
	var/list/predicted = explosion_severity_map(epicenter, s[1], s[2], s[3], null, TRUE)
	var/list/glass = list() //window or light -> ring
	for(var/turf/T as anything in predicted)
		for(var/obj/O in T)
			if(istype(O, /obj/structure/window) || istype(O, /obj/machinery/light))
				glass[O] = predicted[T]
	var/datum/gas_mixture/air = epicenter.return_air()
	var/before = "[round(air.return_pressure(), 0.1)] kPa, [round(air.temperature, 0.1)] K"
	var/list/room_turfs = list()
	for(var/turf/open/T in range(3, epicenter))
		if(T.air && !isspaceturf(T))
			room_turfs += T
	var/start = TICK_USAGE_REAL
	explosion(epicenter, s[1], s[2], s[3], 0, adminlog = FALSE)
	var/took = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	UNTIL(!SSexplosions.is_exploding())
	sleep(2 SECONDS)
	var/after = "nothing left"
	var/pressure = 0
	var/temperature = 0
	var/n = 0
	for(var/turf/open/T in room_turfs)
		if(QDELETED(T) || !T.air || isspaceturf(T))
			continue
		pressure += T.air.return_pressure()
		temperature += T.air.temperature
		n++
	if(n)
		after = "[round(pressure / n, 0.1)] kPa, [round(temperature / n, 0.1)] K over [n] tiles within 3"
	var/list/windows = list(0, 0, 0, 0)
	var/list/windows_gone = list(0, 0, 0, 0)
	var/list/lights = list(0, 0, 0, 0)
	var/list/lights_gone = list(0, 0, 0, 0)
	for(var/obj/O as anything in glass)
		var/ring = glass[O]
		if(istype(O, /obj/machinery/light))
			lights[ring]++
			var/obj/machinery/light/L = O
			if(QDELETED(L) || L.status == LIGHT_BROKEN || L.status == LIGHT_EMPTY)
				lights_gone[ring]++
		else
			windows[ring]++
			if(QDELETED(O))
				windows_gone[ring]++
	xp_log("Live [name] at [epicenter.x],[epicenter.y]: explode() took [round(took, 0.01)] ms. Air at the middle before [before]; 2 s after [after].")
	xp_log("  Windows broken, devastated/heavy/light/glass-only rings: [windows_gone[1]] of [windows[1]], [windows_gone[2]] of [windows[2]], [windows_gone[3]] of [windows[3]], [windows_gone[4]] of [windows[4]]")
	xp_log("  Lights broken by ring: [lights_gone[1]] of [lights[1]], [lights_gone[2]] of [lights[2]], [lights_gone[3]] of [lights[3]], [lights_gone[4]] of [lights[4]]")

/// What a blast did to a person, for the log
/proc/xr_person(mob/living/carbon/human/H)
	if(QDELETED(H))
		return "gibbed"
	var/list/bits = list()
	bits += H.stat == DEAD ? "dead" : "[round(H.health)] hp"
	var/obj/item/organ/ears/E = H.getorganslot(ORGAN_SLOT_EARS)
	if(E && E.ear_damage > UNHEALING_EAR_DAMAGE)
		bits += "eardrums burst"
	else if(E && E.deaf)
		bits += "deaf [E.deaf]"
	var/datum/status_effect/blast_lung/B = H.has_status_effect(/datum/status_effect/blast_lung)
	if(B)
		bits += "blast lung [round(B.severity)]"
	var/embedded = 0
	for(var/obj/item/bodypart/BP as anything in H.bodyparts)
		embedded += length(BP.embedded_objects)
	if(embedded)
		bits += "[embedded] embedded"
	if(H.blast_dulled_until > world.time)
		bits += "hearing dulled"
	return jointext(bits, ", ")

/proc/xr_human(turf/T, lying)
	var/mob/living/carbon/human/H = new(T)
	if(lying)
		H.Knockdown(2 MINUTES)
	return H

/// People in a line each side of a blast: standing to the east, lying to the west
/proc/xr_people(name, turf/epicenter, list/s)
	var/list/standing = list()
	var/list/lying = list()
	for(var/d in 1 to 10)
		var/turf/east = locate(epicenter.x + d, epicenter.y, epicenter.z)
		var/turf/west = locate(epicenter.x - d, epicenter.y, epicenter.z)
		if(east && !east.density)
			standing["[d]"] = xr_human(east, FALSE)
		if(west && !west.density)
			lying["[d]"] = xr_human(west, TRUE)
	sleep(1 SECONDS)
	explosion(epicenter, s[1], s[2], s[3], 0, adminlog = FALSE)
	UNTIL(!SSexplosions.is_exploding())
	sleep(3 SECONDS)
	xp_log("Live [name] at [epicenter.x],[epicenter.y], ([s[1]], [s[2]], [s[3]]):")
	for(var/d in 1 to 10)
		xp_log("  [d] tiles: standing [standing["[d]"] ? xr_person(standing["[d]"]) : "-"] | lying [lying["[d]"] ? xr_person(lying["[d]"]) : "-"]")
	var/walls = 0
	var/dented = 0
	for(var/turf/closed/wall/W in range(10, epicenter))
		walls++
		if(W.blast_damage)
			dented++
	xp_log("  [dented] of [walls] walls within 10 hold blast damage")
	for(var/d in standing)
		if(!QDELETED(standing[d]))
			qdel(standing[d])
	for(var/d in lying)
		if(!QDELETED(lying[d]))
			qdel(lying[d])

/// A real syndicate minibomb with people round it: fragments
/proc/xr_grenade(name, turf/epicenter)
	var/list/people = list()
	for(var/turf/open/T in view(6, epicenter)) //in the open, where fragments can get to them
		var/d = get_dist(T, epicenter)
		if(d >= 3 && d <= 6 && !T.density && prob(40) && length(people) < 14)
			people += xr_human(T, FALSE)
	var/airlocks_before = 0
	for(var/obj/machinery/door/airlock/A in range(6, epicenter))
		airlocks_before++
	sleep(1 SECONDS)
	var/obj/item/grenade/syndieminibomb/G = new(epicenter)
	var/thrown_before = GLOB.blast_fragments_thrown
	var/hit_before = GLOB.blast_fragments_hit
	G.prime()
	xp_log("  fragments thrown [GLOB.blast_fragments_thrown - thrown_before], hit someone [GLOB.blast_fragments_hit - hit_before]; people standing: [xr_count_standing(people)]")

	UNTIL(!SSexplosions.is_exploding())
	sleep(3 SECONDS)
	var/fragments = 0
	for(var/obj/item/blast_fragment/F in range(16, epicenter))
		fragments++
	var/hit = 0
	var/embedded = 0
	for(var/mob/living/carbon/human/H as anything in people)
		if(QDELETED(H))
			continue
		var/these = 0
		for(var/obj/item/bodypart/BP as anything in H.bodyparts)
			for(var/obj/item/blast_fragment/F in BP.embedded_objects)
				these++
		if(these)
			hit++
		embedded += these
	var/airlocks_after = 0
	for(var/obj/machinery/door/airlock/A in range(6, epicenter))
		airlocks_after++
	var/blown = 0
	for(var/obj/structure/door_assembly/A in range(12, epicenter))
		if(A.blown_off)
			blown++
	xp_log("Live [name] at [epicenter.x],[epicenter.y]: [length(people)] people 3-6 tiles off, [hit] with fragments in them ([embedded] fragments); [fragments] fragments on the floor within 16. Airlocks within 6: [airlocks_before] before, [airlocks_after] after, [blown] blown-off doors lying about")
	for(var/mob/living/carbon/human/H as anything in people)
		xp_log("  [get_dist(H, epicenter)] tiles: [xr_person(H)]")
		if(!QDELETED(H))
			qdel(H)

/// A pile of minibombs on one tile, one set off: does the server keep up
/proc/xr_pile()
	var/turf/spot
	for(var/area/A in GLOB.sortedAreas)
		if(istype(A, /area/maintenance) && (A.z in SSmapping.levels_by_trait(ZTRAIT_STATION)))
			spot = xr_middle(A)
			if(spot)
				break
	if(!spot)
		xp_log("No maintenance for the pile")
		return
	for(var/i in 1 to 150)
		new /obj/item/grenade/syndieminibomb(spot)
	sleep(1 SECONDS)
	var/real_start = REALTIMEOFDAY
	var/game_start = world.time
	var/obj/item/grenade/syndieminibomb/G = locate() in spot
	G.prime()
	var/longest = 0
	var/last = REALTIMEOFDAY
	while(SSexplosions.is_exploding() || REALTIMEOFDAY - real_start < 20)
		sleep(world.tick_lag)
		var/now = REALTIMEOFDAY
		longest = max(longest, now - last)
		last = now
		if(now - real_start > 600)
			break
	var/left = 0
	for(var/obj/item/grenade/syndieminibomb/B in range(3, spot))
		left++
	xp_log("Pile: 150 minibombs at [get_area_name(spot, TRUE)] [spot.x],[spot.y]: done in [(REALTIMEOFDAY - real_start) / 10] s real, [(world.time - game_start) / 10] s game time; longest gap between ticks [longest * 100] ms; [left] left unexploded; [GLOB.blast_dust_clouds] dust clouds, [length(GLOB.blast_flashes)] flashes about; fragments this second [GLOB.blast_fragment_count]")

/// Airlocks round a blast: how many are blown off their frames, and where the frames land
/proc/xr_doors(name, turf/epicenter, list/s)
	var/list/doors = list()
	for(var/turf/open/T in range(3, epicenter))
		var/d = get_dist(T, epicenter)
		if(d >= 2 && !T.density && !(locate(/obj/machinery/door) in T) && length(doors) < 12)
			doors += new /obj/machinery/door/airlock(T)
	sleep(1 SECONDS)
	explosion(epicenter, s[1], s[2], s[3], 0, adminlog = FALSE)
	UNTIL(!SSexplosions.is_exploding())
	sleep(3 SECONDS)
	var/standing = 0
	for(var/obj/machinery/door/airlock/A as anything in doors)
		if(!QDELETED(A))
			standing++
	var/list/landed = list()
	for(var/obj/structure/door_assembly/A in range(12, epicenter))
		if(A.blown_off)
			landed += "[get_dist(A, epicenter)]"
	xp_log("Live [name] at [epicenter.x],[epicenter.y]: [length(doors)] airlocks, [standing] still there, [length(landed)] blown off and landed at [jointext(landed, ", ")] tiles out")

/proc/xr_count_standing(list/people)
	. = 0
	for(var/mob/living/L as anything in people)
		if(!QDELETED(L) && L.density)
			.++
