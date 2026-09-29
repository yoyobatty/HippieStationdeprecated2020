#define FLING_STEP_DELAY 2 //deciseconds a flung decal takes to cross one tile

/obj/effect/decal/cleanable
	var/random_jitter = FALSE //randomly flip, rotate and nudge on spawn so repeated decals don't look stamped onto the floor

/obj/effect/decal/cleanable/Initialize(mapload, list/datum/disease/diseases)
	. = ..()
	if(random_jitter && . != INITIALIZE_HINT_QDEL)
		var/matrix/M = matrix()
		if(prob(50))
			M.Scale(-1, 1)
		M.Turn(pick(0, 90, 180, 270))
		transform = M
		pixel_x += rand(-4, 4)
		pixel_y += rand(-4, 4)

/// Flings this decal `distance` tiles along `direction`, hopping through the air in a spinning arc.
/// Calls on_fling_trail() on every tile it passes after the first, and on_fling_blocked() if a wall stops it.
/// On mapload it just slides into place instantly.
/obj/effect/decal/cleanable/proc/fling(direction, distance, mapload = FALSE, list/datum/disease/diseases)
	set waitfor = FALSE
	if(!direction || distance < 1 || !isturf(loc))
		return
	var/airborne = !mapload && has_gravity()
	var/matrix/landed_transform = transform
	if(airborne)
		start_fling_arc(distance)
	if(!mapload)
		set_glide_size(DELAY_TO_GLIDE_SIZE(FLING_STEP_DELAY))
	var/stopped_early = FALSE
	for(var/i in 1 to distance)
		if(i > 1)
			on_fling_trail(mapload, diseases)
		var/turf/next = get_step(src, direction)
		if(!next || !step(src, direction))
			if(isclosedturf(next))
				on_fling_blocked(next, diseases)
			stopped_early = TRUE
			break
		if(!mapload)
			sleep(FLING_STEP_DELAY)
			if(QDELETED(src))
				return
	if(airborne)
		if(stopped_early) //cut the arc short and drop straight down
			animate(src, pixel_z = 0, transform = landed_transform, time = FLING_STEP_DELAY, easing = SINE_EASING | EASE_IN)
		layer = initial(layer)

/// Starts the hop and tumble for a fling of `distance` tiles. The spin ends on the decal's current transform.
/obj/effect/decal/cleanable/proc/start_fling_arc(distance)
	var/flight_time = distance * FLING_STEP_DELAY
	var/matrix/landed_transform = transform
	var/quarter_turns = distance * 2
	var/spin = pick(-90, 90)
	var/matrix/spun = matrix(landed_transform)
	spun.Turn(-spin * quarter_turns)
	transform = spun
	layer = ABOVE_MOB_LAYER //it's in the air, so draw it over people
	animate(src, pixel_z = 4 + distance * 6, time = flight_time / 2, easing = SINE_EASING | EASE_OUT)
	animate(pixel_z = 0, time = flight_time / 2, easing = SINE_EASING | EASE_IN)
	animate(pixel_z = 2, time = 1, easing = SINE_EASING | EASE_OUT) //little bounce as it lands
	animate(pixel_z = 0, time = 1, easing = SINE_EASING | EASE_IN)
	//quarter turns, since animate() takes the short way round between two rotations
	for(var/turns_left in quarter_turns - 1 to 0 step -1)
		var/matrix/M = matrix(landed_transform)
		M.Turn(-spin * turns_left)
		if(turns_left == quarter_turns - 1)
			animate(src, transform = M, time = flight_time / quarter_turns, flags = ANIMATION_PARALLEL)
		else
			animate(transform = M, time = flight_time / quarter_turns)

/// Called on each tile a flung decal leaves behind, after the first.
/obj/effect/decal/cleanable/proc/on_fling_trail(mapload, list/datum/disease/diseases)
	return

/// Called when a flung decal is stopped by a wall.
/obj/effect/decal/cleanable/proc/on_fling_blocked(turf/closed/wall, list/datum/disease/diseases)
	return

/obj/effect/decal/cleanable/blood/gibs/on_fling_trail(mapload, list/datum/disease/diseases)
	var/turf/T = loc
	T.add_blood_DNA(return_blood_DNA(), diseases) //finds or makes a splatter here and gives it our DNA

/obj/effect/decal/cleanable/blood/gibs/on_fling_blocked(turf/closed/wall, list/datum/disease/diseases)
	new /obj/effect/decal/cleanable/blood/wall_splatter(loc, diseases, get_dir(loc, wall), return_blood_DNA())

/obj/effect/decal/cleanable/xenoblood
	random_jitter = TRUE

/obj/effect/decal/cleanable/xenoblood/xgibs/on_fling_trail(mapload, list/datum/disease/diseases)
	new /obj/effect/decal/cleanable/xenoblood/xsplatter(loc)

/obj/effect/decal/cleanable/robot_debris
	random_jitter = TRUE

/obj/effect/decal/cleanable/robot_debris/on_fling_trail(mapload, list/datum/disease/diseases)
	if(prob(40))
		new /obj/effect/decal/cleanable/oil/streak(loc)
	else if(prob(10) && !mapload)
		var/datum/effect_system/spark_spread/s = new /datum/effect_system/spark_spread
		s.set_up(3, 1, src)
		s.start()

#undef FLING_STEP_DELAY
