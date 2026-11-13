// Realistic explosions: what blasts do to the station's structure (see blast_air.dm; glass is blast_far.dm).
//  - Walls take blast damage that adds up (blast_damage, 100 brings one down) instead of rolling a tier each time: a heavy blast
//    buckles a plain wall and the next one brings it down, a light one dents it, and reinforced walls take well under half. The dents
//    show it, the wall says so when examined, and welding the dents out (help intent, as before) mends it. A devastating blast still
//    takes a wall straight away. Where one comes down, dust and rubble.
//  - An airlock a blast would destroy is often blown off its frame instead: the bare door frame is thrown away from the blast and hits
//    whatever it hits like the slab of metal it is, and the doorway's left open.

/// Blast damage a wall has taken, 100 brings it down. Welding out its dents mends it.
/turf/closed/wall/var/blast_damage = 0

/turf/closed/wall/ex_act(severity, target)
	if(!GLOB.explosion_realism || target == src || severity == EXPLODE_DEVASTATE || severity == EXPLODE_NONE)
		var/turf/was = src
		. = ..()
		if(GLOB.explosion_realism && severity == EXPLODE_DEVASTATE && !isspaceturf(was) && !was.density)
			blast_rubble(was)
		return
	// plain walls (hardness 40) take it all, reinforced (10) 40%
	var/toughness = clamp((hardness + 10) / 50, 0.4, 1.2)
	var/hit = severity == EXPLODE_HEAVY ? rand(60, 90) : rand(10, 25)
	blast_damage += hit * toughness
	if(blast_damage >= 100)
		dismantle_wall(severity == EXPLODE_HEAVY && prob(40), TRUE)
		blast_rubble(src)
		return
	for(var/i in 1 to (severity == EXPLODE_HEAVY ? 3 : 1))
		add_dent(WALL_DENT_HIT)
	if(!density)
		return ..()

/turf/closed/wall/examine(mob/user)
	. = ..()
	if(blast_damage >= 60)
		. += "<span class='warning'>It's buckled and cracked from a blast. It won't take another.</span>"
	else if(blast_damage >= 25)
		. += "<span class='warning'>It's dented and cracked from a blast.</span>"

/turf/closed/wall/try_clean(obj/item/W, mob/user, turf/T)
	. = ..()
	if(. && iswallturf(src) && !LAZYLEN(dent_decals))
		blast_damage = 0

/// Dust and grit where something came down
/proc/blast_rubble(turf/T)
	if(!T || isspaceturf(T) || T.density)
		return
	if(!(locate(/obj/effect/decal/cleanable/dirt) in T))
		new /obj/effect/decal/cleanable/dirt(T)

/obj/machinery/door/airlock/ex_act(severity, target)
	if(GLOB.explosion_realism && !QDELETED(src) && assemblytype && !(resistance_flags & INDESTRUCTIBLE))
		// a door counts a blast a tier harder (/obj/machinery/door/ex_act()), so heavy and devastating both destroy it: often it's
		// blown off its frame instead
		if((severity == EXPLODE_HEAVY && prob(55)) || (severity == EXPLODE_DEVASTATE && prob(35)))
			blow_off()
			return
	return ..()

/// Tears the door out of its frame and throws it away from the blast
/obj/machinery/door/airlock/proc/blow_off()
	var/turf/T = get_turf(src)
	if(!T)
		return
	var/list/details = T.explosion_throw_details //explode() put the way out from the blast here, for the throws
	var/direction = length(details) == 3 ? details[2] : 0
	if(!direction)
		direction = pick(GLOB.alldirs)
	var/obj/structure/door_assembly/A = new assemblytype(T)
	A.name = "blown-off [A.name]"
	A.anchored = FALSE
	A.blown_off = TRUE
	A.obj_integrity = A.max_integrity * 0.4
	A.update_icon()
	if(glass)
		new /obj/item/shard(T)
		new /obj/item/shard(T)
	visible_message("<span class='danger'>[src] is blown off its frame!</span>")
	qdel(src)
	var/distance = rand(2, 5)
	A.throw_at(get_ranged_target_turf(T, direction, distance), distance, 3)

/// A door frame a blast tore out: thrown, it hits people as hard as a slab of metal would
/obj/structure/door_assembly/var/blown_off = FALSE

/obj/structure/door_assembly/throw_impact(atom/hit_atom, datum/thrownthing/throwingdatum)
	. = ..()
	if(!blown_off || !isliving(hit_atom))
		return
	var/mob/living/L = hit_atom
	L.visible_message("<span class='danger'>[src] slams into [L]!</span>", "<span class='userdanger'>[src] slams into you!</span>")
	playsound(L, 'sound/effects/bang.ogg', 50, TRUE)
	L.apply_damage(25, BRUTE, null, L.run_armor_check(null, "melee"))
	L.Knockdown(40)
