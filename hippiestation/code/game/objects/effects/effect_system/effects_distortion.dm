#define DISTORTION_MAX_SHOCKWAVES 4 // most shockwaves a player will see at once, so a barrage of explosions doesn't stack up on their screen
#define SHOCKWAVE_MIN_DURATION 6 // deciseconds
#define SHOCKWAVE_MAX_DURATION 24 // deciseconds
#define SHOCKWAVE_MAX_SIZE 28 // most pixels a shockwave can bend the screen
#define GRAVITY_LENS_MIN_RADIUS 4 // tiles, for the smallest singularity
#define GRAVITY_LENS_RADIUS_PER_SIZE 1.6 // tiles of lensing for each stage of singularity size
#define GRAVITY_LENS_SIZE_PER_SIZE 1.2 // pixels of distortion for each stage of singularity size
#define GRAVITY_LENS_MAX_SIZE 14 // most pixels a singularity can bend the screen
#define GRAVITY_LENS_SHIMMER 0.15 // how much the lensing pulses, as a fraction of its strength
#define GRAVITY_LENS_PERIOD 48 // pixels between the rings of distortion. Big, so the rings are broad and fill the disc
#define GRAVITY_LENS_FLOW_TIME 30 // deciseconds for the rings to flow inwards by one period
#define SHOCKWAVE_MIN_PERIOD 16 // pixels between the ripples of a shockwave, for the smallest ones

GLOBAL_VAR_INIT(distortion_counter, 0)
GLOBAL_LIST_EMPTY(distortion_shockwaves) // client = how many shockwaves they're seeing right now
GLOBAL_DATUM(gravity_lens_controller, /datum/gravity_lens_controller)
// The lens is a few ripples stacked on top of each other, a wide one over the whole disc and smaller ones over its core,
// as list(name, share of the radius, share of the strength). Ripples with the same period and falloff are drawn in one pass.
GLOBAL_LIST_INIT(gravity_lens_layers, list(list("gravity_lens_disc", 1, 0.5), list("gravity_lens_mid", 0.6, 0.5), list("gravity_lens_core", 0.3, 0.6)))

/**
  * Screen distortion. The world a player sees is drawn through a few plane masters, and putting a filter on those bends
  * everything on them at once, floors, walls, objects and mobs. The filter positions are in pixels measured from the
  * middle of the player's view, so effects get placed relative to wherever each player is looking.
  *
  * The ripple filter's distortion is size * sin(2 * pi * r) / (2.5 * falloff * r^2 + 1) where r is how many periods
  * inside the outer radius each pixel is. So a tiny period gives a thin ring that dies away in a few pixels, a big
  * period gives broad rings, and a falloff of 0 means the rings never lose strength on the way in.
  */

/// The plane masters that make up the world a player sees, which is what gets distorted: the space and parallax
/// backgrounds, the floor, and, unless background_only is set, everything on top of it and the lighting too.
/proc/distortion_planes(mob/M, background_only = FALSE)
	. = list()
	if(!M || !M.hud_used)
		return
	var/list/planes = list(PLANE_SPACE, PLANE_SPACE_PARALLAX, FLOOR_PLANE)
	if(!background_only)
		planes += list(GAME_PLANE, LIGHTING_PLANE)
	for(var/plane in planes)
		var/obj/screen/plane_master/PM = M.hud_used.plane_masters["[plane]"]
		if(PM)
			. += PM

/// Where something is on a player's screen, in pixels from the middle of their view. Null if it's on another level.
/proc/distortion_offset(client/C, atom/target)
	var/turf/eye_turf = get_turf(C.eye)
	var/turf/target_turf = get_turf(target)
	if(!eye_turf || !target_turf || eye_turf.z != target_turf.z)
		return null
	return list((target_turf.x - eye_turf.x) * world.icon_size, (target_turf.y - eye_turf.y) * world.icon_size)

/// How far from the middle of a player's screen you can see, in turfs.
/proc/distortion_view_reach(client/C)
	var/list/view_size = getviewsize(C.view)
	return max(view_size[1], view_size[2])

/proc/remove_distortion_filter(obj/screen/plane_master/PM, filter_name)
	if(QDELETED(PM))
		return
	var/filter_ref = PM.filters[filter_name]
	if(filter_ref)
		PM.filters -= filter_ref

/**
  * A ring of distortion racing outwards from an explosion across the screens of everyone who can see it.
  *
  * Arguments:
  * * epicenter - where it starts
  * * range - how many turfs out the ring travels
  * * size - the most pixels the ring bends the screen, fading away as it spreads
  */
/proc/screen_shockwave(turf/epicenter, range, size)
	if(!isturf(epicenter) || range < 1 || size <= 0)
		return
	size = min(size, SHOCKWAVE_MAX_SIZE)
	var/duration = clamp(round(range * 1.2), SHOCKWAVE_MIN_DURATION, SHOCKWAVE_MAX_DURATION)
	var/period = SHOCKWAVE_MIN_PERIOD + size * 0.6 // bigger blasts make broader ripples
	for(var/client/C in GLOB.clients)
		var/list/planes = distortion_planes(C.mob)
		if(!planes.len)
			continue
		var/list/offset = distortion_offset(C, epicenter)
		if(!offset)
			continue
		if(max(abs(offset[1]), abs(offset[2])) / world.icon_size > range + distortion_view_reach(C))
			continue // the ring never gets anywhere near their screen
		if(GLOB.distortion_shockwaves[C] >= DISTORTION_MAX_SHOCKWAVES)
			continue
		GLOB.distortion_shockwaves[C]++
		for(var/obj/screen/plane_master/PM in planes)
			var/id = ++GLOB.distortion_counter
			var/filter_name = "shockwave_[id]"
			PM.filters += filter(type = "ripple", name = filter_name, x = offset[1], y = offset[2], size = size, radius = 0, repeat = period, falloff = 1)
			var/filter_ref = PM.filters[filter_name]
			animate(filter_ref, radius = range * world.icon_size, size = 0, time = duration)
			addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(remove_distortion_filter), PM, filter_name), duration + 1)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(end_screen_shockwave), C), duration + 1)

/proc/end_screen_shockwave(client/C)
	if(!GLOB.distortion_shockwaves[C])
		return
	GLOB.distortion_shockwaves[C]--
	if(GLOB.distortion_shockwaves[C] <= 0)
		GLOB.distortion_shockwaves -= C

/// Wakes up the gravity lens controller, which runs for as long as there's a singularity around.
/proc/gravity_lens_wake()
	if(GLOB.gravity_lens_controller)
		return
	GLOB.gravity_lens_controller = new
	START_PROCESSING(SSfastprocess, GLOB.gravity_lens_controller)

/obj/singularity/Initialize(mapload, starting_energy = 50)
	. = ..()
	gravity_lens_wake()

/**
  * Bends the view of everyone near a singularity around it, the way its gravity would bend the light. Only the
  * background is bent, the space and parallax layers and the floor, all in step with each other. Everything on the game
  * plane, which is where the singularity itself is drawn, stays sharp, so the singularity isn't warped by its own lens.
  * Nothing is stored about the players: every couple of ticks each one is checked for the nearest singularity, and the
  * ripple on their screen is created, moved or taken away to match. That also puts it right back if something resets
  * the screen. Nar'Sie and the tesla ball have their own look and are left out.
  */
/datum/gravity_lens_controller
	var/last_phase = 0

/datum/gravity_lens_controller/process()
	var/list/lenses = list()
	for(var/obj/singularity/S in GLOB.singularities)
		if(istype(S, /obj/singularity/narsie) || istype(S, /obj/singularity/energy_ball))
			continue
		lenses += S
	// Where the rings have got to in their flow inwards. When it wraps round the pattern is exactly the same as it
	// was one period ago, so the rings jump back without anyone seeing it.
	var/phase = round(world.time) % GRAVITY_LENS_FLOW_TIME
	var/wrapped = phase < last_phase
	last_phase = phase
	var/flow = phase / GRAVITY_LENS_FLOW_TIME
	for(var/client/C in GLOB.clients)
		update_client(C, lenses, flow, wrapped)
	if(!lenses.len)
		// every screen has just been cleaned up, so there's nothing left to do until the next singularity turns up
		STOP_PROCESSING(SSfastprocess, src)
		GLOB.gravity_lens_controller = null

/datum/gravity_lens_controller/proc/lens_radius(obj/singularity/S)
	return max(GRAVITY_LENS_MIN_RADIUS, S.current_size * GRAVITY_LENS_RADIUS_PER_SIZE)

/datum/gravity_lens_controller/proc/update_client(client/C, list/lenses, flow, wrapped)
	var/list/planes = distortion_planes(C.mob, TRUE)
	if(!planes.len)
		return
	var/obj/singularity/nearest
	var/nearest_distance = INFINITY
	var/list/nearest_offset
	if(lenses.len)
		var/view_reach = distortion_view_reach(C)
		for(var/obj/singularity/S in lenses)
			var/list/offset = distortion_offset(C, S)
			if(!offset)
				continue
			var/distance = max(abs(offset[1]), abs(offset[2])) / world.icon_size
			if(distance > lens_radius(S) + view_reach || distance >= nearest_distance)
				continue // too far for any of the lensing to reach their screen
			nearest = S
			nearest_distance = distance
			nearest_offset = offset
	var/strength
	var/radius
	var/shift
	if(nearest)
		strength = clamp(nearest.current_size * GRAVITY_LENS_SIZE_PER_SIZE, 3, GRAVITY_LENS_MAX_SIZE)
		strength *= 1 + sin(world.time * 15) * GRAVITY_LENS_SHIMMER // slowly pulses
		radius = lens_radius(nearest) * world.icon_size
		shift = GRAVITY_LENS_PERIOD * (1 - flow) // shifting the radius by a period moves the rings inwards by one
	for(var/obj/screen/plane_master/PM in planes)
		for(var/list/layer in GLOB.gravity_lens_layers)
			var/filter_name = layer[1]
			var/filter_ref = PM.filters[filter_name]
			if(!nearest)
				if(filter_ref)
					PM.filters -= filter_ref
				continue
			var/layer_radius = radius * layer[2] + shift
			var/layer_size = strength * layer[3]
			if(filter_ref)
				if(wrapped)
					filter_ref:radius = layer_radius
				animate(filter_ref, x = nearest_offset[1], y = nearest_offset[2], size = layer_size, radius = layer_radius, time = 2)
			else
				PM.filters += filter(type = "ripple", name = filter_name, x = nearest_offset[1], y = nearest_offset[2], size = layer_size, radius = layer_radius, repeat = GRAVITY_LENS_PERIOD, falloff = 0, flags = WAVE_BOUNDED)
