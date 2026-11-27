#define SINGULARITY_PULL_BASE_CHANCE 0.2 // chance per fast tick (0.2 seconds) that something in range is pulled a step closer
#define SINGULARITY_PULL_CHANCE_PER_SIZE 0.05 // extra chance for each stage of singularity size
#define SINGULARITY_PULL_NEARNESS_BONUS 0.35 // extra chance for things right next to it, fading to nothing at the edge of its reach
#define SINGULARITY_PULL_MAX_CHANCE 0.95
#define SINGULARITY_PULL_MOB_FACTOR 0.6 // people are pulled less hard than things, so they've got a chance to run
#define SINGULARITY_PULL_SHARES 9 // SSfastprocess fires ten times between two singularity fires, nine shares leaves room to catch up

/**
  * Pulling things towards a singularity, quickly and without freezing the server.
  *
  * A singularity's process only runs every two seconds. eat() eats what's in reach at once and queues every other turf in
  * range in pull_queue. A light loop on SSfastprocess, five times a second, gives a share of the queue its pull effects
  * (stopping early when the tick is full) and notes what can be pulled in pull_targets, then steps those towards the
  * singularity. Done all in one go, a stage six scan took most of a second and starved the MC, so input wasn't read.
  */
/obj/singularity
	var/list/pull_queue // turfs still to be pulled on before the next eat()
	var/pull_share = 0 // how many turfs of the queue to pull on each fast fire
	var/list/pull_targets // what the queue's pulls found that can be pulled, for the fast loop
	var/datum/singularity_puller/puller

/obj/singularity/Destroy()
	if(puller)
		STOP_PROCESSING(SSfastprocess, puller)
		puller.singularity = null
		puller = null
	pull_queue = null
	pull_targets = null
	return ..()

/// Called by eat() once the queue is filled. Starts the fast loop if there's anything to do.
/obj/singularity/proc/start_pull_loop()
	if(!pull_queue.len)
		return
	pull_share = CEILING(pull_queue.len / SINGULARITY_PULL_SHARES, 1)
	if(!puller)
		puller = new(src)
	START_PROCESSING(SSfastprocess, puller)

/// Eats or pulls on one turf and everything on it.
/obj/singularity/proc/eat_turf(turf/T)
	if(!isturf(loc))
		return
	if(get_dist(T, src) > consume_range)
		T.singularity_pull(src, current_size)
	else
		consume(T)
	for(var/thing in T)
		if(thing == src)
			continue
		var/atom/movable/X = thing
		if(QDELETED(X)) // something pulled or eaten earlier on this tile can delete a later one, like stacks merging
			continue
		if(get_dist(X, src) > consume_range)
			X.singularity_pull(src, current_size)
			if(!QDELETED(X) && !X.anchored && !istype(X, /obj/effect)) // after its own pull effects, since a window is let go by them
				pull_targets += X
		else
			consume(X)
		if(!isturf(loc))
			return

/// Pulls on one share of the queue. Stops early if the tick is full, what's left is picked up on the next fire.
/obj/singularity/proc/pull_some()
	var/done = 0
	while(pull_queue && pull_queue.len && done < pull_share && !TICK_CHECK)
		var/turf/T = pull_queue[pull_queue.len]
		pull_queue.len--
		if(T)
			eat_turf(T)
		done++

/// One step of the fast loop: pulls a share of the targets a step closer. The nearer and the bigger the singularity, the harder the pull.
/obj/singularity/proc/fast_pull()
	if(!pull_targets || !pull_targets.len)
		return
	var/size_chance = SINGULARITY_PULL_BASE_CHANCE + current_size * SINGULARITY_PULL_CHANCE_PER_SIZE
	for(var/thing in pull_targets)
		if(TICK_CHECK)
			return
		var/atom/movable/X = thing
		if(QDELETED(X) || X.anchored || X.throwing || !isturf(X.loc))
			continue
		var/dist = get_dist(X, src)
		if(dist < 1 || dist > grav_pull)
			continue
		var/chance = size_chance + (1 - dist / grav_pull) * SINGULARITY_PULL_NEARNESS_BONUS
		if(isliving(X))
			var/mob/living/L = X
			if(L.buckled || L.mob_negates_gravity())
				continue
			chance *= SINGULARITY_PULL_MOB_FACTOR
		if(prob(min(chance, SINGULARITY_PULL_MAX_CHANCE) * 100))
			step_towards(X, src) // running into the singularity is what gets it consumed

/// Whether the fast loop still has work.
/obj/singularity/proc/fast_fire()
	if(QDELETED(src) || !isturf(loc))
		return FALSE
	pull_some()
	fast_pull()
	return (pull_queue && pull_queue.len) || (pull_targets && pull_targets.len)

/datum/singularity_puller
	var/obj/singularity/singularity

/datum/singularity_puller/New(obj/singularity/S)
	singularity = S

/datum/singularity_puller/process()
	if(!singularity || !singularity.fast_fire())
		STOP_PROCESSING(SSfastprocess, src)

// Something already flying at the singularity isn't thrown at it again: each throw_at() is a new thrownthing and a move
// at once, and a stage four or bigger singularity rethrew every loose item in range every two seconds.
/obj/item/singularity_pull(obj/singularity/S, current_size)
	if(current_size < STAGE_FOUR)
		return ..()
	SEND_SIGNAL(src, COMSIG_ATOM_SING_PULL, S, current_size)
	if(throwing && throwing.target == S)
		return
	throw_at(S, 14, 3, spin = TRUE) // spins on its way in (Paradise 24f91e81a2)

/mob/living/singularity_pull(obj/singularity/S, current_size)
	if(current_size >= STAGE_SIX && throwing && throwing.target == S)
		SEND_SIGNAL(src, COMSIG_ATOM_SING_PULL, S, current_size)
		return
	return ..()

#undef SINGULARITY_PULL_BASE_CHANCE
#undef SINGULARITY_PULL_CHANCE_PER_SIZE
#undef SINGULARITY_PULL_NEARNESS_BONUS
#undef SINGULARITY_PULL_MAX_CHANCE
#undef SINGULARITY_PULL_MOB_FACTOR
#undef SINGULARITY_PULL_SHARES
