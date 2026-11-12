/mob/living/simple_animal/hostile/retaliate
	var/list/enemies = list() // hippie -- keyed (enemies[mob] = TRUE), so "is this one an enemy" is a lookup and not a walk of the list
	var/next_retaliate = 0 // hippie -- Retaliate() looks around at most once a second

// hippie -- somebody who's been deleted can't be garbage collected for as long as they're on here
/mob/living/simple_animal/hostile/retaliate/Life()
	. = ..()
	if(length(enemies) && prob(5))
		for(var/atom/enemy as anything in enemies.Copy())
			if(QDELETED(enemy))
				enemies -= enemy

/mob/living/simple_animal/hostile/retaliate/Found(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(!L.stat)
			return L
		else
			enemies -= L
	else if(ismecha(A))
		var/obj/mecha/M = A
		if(M.occupant)
			return A

/mob/living/simple_animal/hostile/retaliate/ListTargets()
	if(!enemies.len)
		return list()
	// hippie start -- keep the ones that are enemies by lookup: see &= enemies walked the enemies for every target in view
	. = list()
	for(var/atom/A as anything in ..())
		if(enemies[A])
			. += A
	// hippie end

/mob/living/simple_animal/hostile/retaliate/proc/Retaliate()
	// hippie start -- 2026-11-11 a pile of clown cats under ash drakes left ~600 clowns burning in lava, and the server stood still
	// for 14 s at a time in here. Every hit on any of them looked at all of view() and then handed its whole enemies list to every
	// ally in sight (H.enemies |= enemies: allies x enemies x their enemies). Now: once a second at most (a hit inside that second
	// changes nothing: everyone in view is already an enemy), the mobs in sight from hearers() (as hostile ListTargets() finds
	// them; view() held every item of a 5000-thing pile, each a VM step) and mechs from the mech list, a lookup per mob, and allies
	// are told only about enemies this one didn't know yet.
	if(world.time < next_retaliate)
		return 0
	next_retaliate = world.time + 1 SECONDS
	var/list/fresh = list()
	var/list/allies = list()
	for(var/mob/living/M in hearers(vision_range, src))
		if(M == src || enemies[M])
			continue
		var/same_faction = faction_check_mob(M)
		if(!same_faction || attack_same)
			enemies[M] = TRUE
			fresh += M
		else if(istype(M, /mob/living/simple_animal/hostile/retaliate))
			var/mob/living/simple_animal/hostile/retaliate/H = M
			if(!H.attack_same)
				allies += H
	for(var/obj/mecha/M as anything in GLOB.mechas_list)
		if(M.z != z || get_dist(src, M) > vision_range || !can_see(src, M, vision_range))
			continue
		if(M.occupant && !enemies[M])
			enemies[M] = TRUE
			fresh += M
			if(!enemies[M.occupant])
				enemies[M.occupant] = TRUE
				fresh += M.occupant

	if(length(fresh))
		for(var/mob/living/simple_animal/hostile/retaliate/H as anything in allies)
			var/list/their_enemies = H.enemies
			for(var/atom/A as anything in fresh)
				their_enemies[A] = TRUE
	return 0
	// hippie end

/mob/living/simple_animal/hostile/retaliate/adjustHealth(amount, updating_health = TRUE, forced = FALSE)
	. = ..()
	if(. > 0 && stat == CONSCIOUS)
		Retaliate()
