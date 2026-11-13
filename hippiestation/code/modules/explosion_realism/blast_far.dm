// Realistic explosions: the pressure past the damage (see blast_air.dm). A blast's pressure breaks glass well past where it does any
// other harm (here out to 1.5 times the light range), so out there windows go (plain glass nearly always, reinforced only on the
// inner part, plasma never),
// light tubes and bulbs burst, and glass tables, mirrors and display cases crack or break. Window glass is thrown on, away from the
// blast, as the shards it is.

/// Works out which tiles past the damage the pressure reaches, for SSexplosions to break their glass: the same shaped sums as the
/// blast's own, out to `far_range`, a few hundred tiles at a time over the next ticks. explode() did this itself, and a maxcap's sums
/// out there took it from 9 to over 50 ms: six maxcaps on one tile froze the server for half a second. The glass now breaks a tick
/// or two after the blast, as the pressure gets out there. The same ring set off twice in a tick (a pile) is done once.
/proc/blast_far_ring(turf/epicenter, edge, far_range)
	set waitfor = FALSE
	var/static/last_key
	var/key = "[epicenter.x],[epicenter.y],[epicenter.z],[edge],[far_range],[world.time]"
	if(key == last_key)
		return
	last_key = key
	SSexplosions.far_pending++
	try
		blast_far_ring_sums(epicenter, edge, far_range)
	catch(var/exception/E)
		stack_trace("blast_far_ring at [AREACOORD(epicenter)]: [E]")
	SSexplosions.far_pending--

/proc/blast_far_ring_sums(turf/epicenter, edge, far_range)
	var/list/affected = SSexplosions.GatherSpiralTurfs(far_range, epicenter)
	var/list/start = blast_thin_air_start(epicenter)
	var/list/blocks = list()
	var/i = 0
	for(var/turf/T as anything in affected)
		var/block = T.density ? T.explosion_block : 0
		for(var/obj/O in T)
			var/b = O.explosion_block
			block += b == EXPLOSION_BLOCK_PROC ? O.GetExplosionBlock() : b
		if(start)
			block += blast_thin_air_cost_at(T, start[1], start[2])
		blocks[T] = block
		if(!(++i % 200))
			CHECK_TICK
	var/list/shape = explosion_shape(epicenter, far_range, blocks)
	CHECK_TICK
	var/x0 = epicenter.x
	var/y0 = epicenter.y
	var/span = max(far_range - edge, 1)
	i = 0
	for(var/turf/T as anything in affected)
		var/dist = cheap_hypotenuse(T.x, T.y, x0, y0)
		if(shape)
			dist += shape[T]
		if(dist >= edge && dist < far_range)
			var/strength = clamp((far_range - dist) / span, 0, 1)
			var/list/had = SSexplosions.farturf[T]
			if(!had || had[1] < strength)
				SSexplosions.farturf[T] = list(strength, epicenter)
		if(!(++i % 500))
			CHECK_TICK

/// What the pressure does to a tile past the damage. `strength` is 1 at the inner edge (where the light damage ends) down to 0 at the
/// far edge; `epicenter` is what the shards are thrown away from.
/proc/blast_far(turf/T, strength, turf/epicenter)
	// a few seconds' deafness for anyone out here without ear protection (the ringing is blast_hear()'s)
	for(var/mob/living/carbon/C in T)
		if(!(C.status_flags & GODMODE) && C.get_ear_protection() < 1)
			C.adjustEarDamage(1 + 3 * strength, 2 + 4 * strength)
	for(var/obj/O in T)
		if(QDELETED(O))
			continue
		if(istype(O, /obj/structure/window) || istype(O, /obj/machinery/door/window))
			// plain glass (25 or 50) breaks right out to the edge, reinforced (100 behind a quarter off for bomb armour) on the inner
			// 40%, cracked further out; plasma never
			blast_damage_obj(O, 40 + 160 * strength, strength * 1.5, epicenter)
		else if(istype(O, /obj/machinery/light))
			var/obj/machinery/light/L = O
			if(L.status != LIGHT_BROKEN && L.status != LIGHT_EMPTY && prob(25 + 60 * strength))
				L.break_light_tube()
		else if(istype(O, /obj/structure/table/glass) || istype(O, /obj/structure/displaycase))
			if(prob(20 + 60 * strength))
				blast_damage_obj(O, 40 + 80 * strength, strength, epicenter)
		else if(istype(O, /obj/structure/mirror))
			var/obj/structure/mirror/M = O
			if(!M.broken && prob(30 + 60 * strength))
				M.obj_break("bomb")
