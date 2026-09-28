/mob/living/simple_animal/hostile/retaliate
	var/list/enemies = list()

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
	var/list/see = ..()
	see &= enemies // Remove all entries that aren't in enemies
	return see

/mob/living/simple_animal/hostile/retaliate/proc/Retaliate()
	var/list/around = view(src, vision_range)
	// hippie -- one pass and one faction check per mob: this checked each mob's faction twice, then walked the whole
	// view again for allies. With a crowd of retaliators every hit on any of them paid for all of that.
	var/list/allies = list()
	for(var/atom/movable/A in around)
		if(A == src)
			continue
		if(isliving(A))
			var/mob/living/M = A
			var/same_faction = faction_check_mob(M)
			if(!same_faction || attack_same)
				enemies |= M
			if(same_faction && !attack_same && istype(M, /mob/living/simple_animal/hostile/retaliate))
				var/mob/living/simple_animal/hostile/retaliate/H = M
				if(!H.attack_same)
					allies += H
		else if(ismecha(A))
			var/obj/mecha/M = A
			if(M.occupant)
				enemies |= M
				enemies |= M.occupant

	for(var/mob/living/simple_animal/hostile/retaliate/H as anything in allies)
		H.enemies |= enemies
	return 0

/mob/living/simple_animal/hostile/retaliate/adjustHealth(amount, updating_health = TRUE, forced = FALSE)
	. = ..()
	if(. > 0 && stat == CONSCIOUS)
		Retaliate()
