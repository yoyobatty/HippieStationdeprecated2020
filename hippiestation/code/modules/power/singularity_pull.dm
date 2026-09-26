#define SINGULARITY_PULL_BASE_CHANCE 0.2 // chance per fast tick (0.2 seconds) that something in range is pulled a step closer
#define SINGULARITY_PULL_CHANCE_PER_SIZE 0.05 // extra chance for each stage of singularity size
#define SINGULARITY_PULL_NEARNESS_BONUS 0.35 // extra chance for things right next to it, fading to nothing at the edge of its reach
#define SINGULARITY_PULL_MAX_CHANCE 0.95
#define SINGULARITY_PULL_MOB_FACTOR 0.6 // people are pulled less hard than things, so they've got a chance to run

/**
  * Pulling things towards a singularity, quickly.
  *
  * A singularity's process only runs every two seconds and each run moved everything in range a single step, so the
  * pull crawled along at about half a turf a second. Running the whole scan more often would cost far too much, since
  * it looks at every turf and every atom in range and gives them all their special effects too. So the slow scan stays
  * as it is but now also notes everything that can be pulled in pull_targets, and a light loop that runs five times a
  * second just steps those towards the singularity. Things pulled from further out or that have just come into range are
  * picked up by the next scan.
  */
/obj/singularity
	var/list/pull_targets // what the last scan found that can be pulled, for the fast loop
	var/datum/singularity_puller/puller

/obj/singularity/Destroy()
	if(puller)
		STOP_PROCESSING(SSfastprocess, puller)
		puller.singularity = null
		puller = null
	pull_targets = null
	return ..()

/// Called by the scan with everything it found that can be pulled. Starts the fast loop if there's anything to do.
/obj/singularity/proc/set_pull_targets(list/targets)
	pull_targets = targets
	if(!targets.len)
		return
	if(!puller)
		puller = new(src)
	START_PROCESSING(SSfastprocess, puller)

/// One step of the fast loop: pulls a share of the targets a step closer. The nearer and the bigger the singularity, the harder the pull.
/obj/singularity/proc/fast_pull()
	if(QDELETED(src) || !isturf(loc) || !pull_targets || !pull_targets.len)
		return FALSE
	var/size_chance = SINGULARITY_PULL_BASE_CHANCE + current_size * SINGULARITY_PULL_CHANCE_PER_SIZE
	for(var/thing in pull_targets)
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
	return TRUE

/datum/singularity_puller
	var/obj/singularity/singularity

/datum/singularity_puller/New(obj/singularity/S)
	singularity = S

/datum/singularity_puller/process()
	if(!singularity || !singularity.fast_pull())
		STOP_PROCESSING(SSfastprocess, src)
