// Because we can control each corner of every lighting object.
// And corners get shared between multiple turfs (unless you're on the corners of the map, then 1 corner doesn't).

/datum/lighting_corner
	var/list/datum/light_source/affecting // Light sources affecting us.

	var/x = 0
	var/y = 0
	var/z = 0

	var/turf/master_NE
	var/turf/master_SE
	var/turf/master_SW
	var/turf/master_NW

	//"raw" color values, changed by the light sources affecting us (see ADD_CORNER_LUM)
	var/lum_r = 0
	var/lum_g = 0
	var/lum_b = 0

	//bounce light on top of that (see /datum/light_source/proc/get_bounce_corners()), changed likewise (ADD_CORNER_BOUNCE).
	//It's only drawn: get_lumcount() and the like go by lum_r and co. alone
	var/bounce_r = 0
	var/bounce_g = 0
	var/bounce_b = 0

	//true color values, guaranteed to be between 0 and 1
	var/cache_r = LIGHTING_SOFT_THRESHOLD
	var/cache_g = LIGHTING_SOFT_THRESHOLD
	var/cache_b = LIGHTING_SOFT_THRESHOLD

	///the maximum of lum_r, lum_g, and lum_b. if this is > 1 then the three cached color values are divided by this
	var/largest_color_luminosity = 0

	///whether we are to be added to SSlighting's corners_queue list for an update
	var/needs_update = FALSE

	// Scratch space for whichever light source is working its light out at the moment: see /datum/light_source/proc/update_corners()
	/// The number of the last light source update to go through us: marks us as gone through, with no list to look us up in
	var/tmp/lighting_stamp = 0
	/// That light source's falloff multiplier here, if it lights us directly
	var/tmp/lighting_level = 0
	/// The number of the last light source update to work out its bounce light here
	var/tmp/bounce_stamp = 0
	/// That bounce light's falloff multiplier here
	var/tmp/bounce_level = 0

// Takes as an argument the coords to use as the bottom left (south west) of our corner.
/datum/lighting_corner/New(x, y, z)
	. = ..()

	src.x = x + 0.5
	src.y = y + 0.5
	src.z = z

	// Take a set of coords and build out the turfs adjacent to us in a clockwise loop.
	var/turf/process_next = locate(x, y, z)
	if(process_next)
		master_SW = process_next
		process_next.lighting_corner_NE = src
		process_next = get_step(process_next, NORTH)
	else
		process_next = locate(x, y + 1, z)

	if(process_next)
		master_NW = process_next
		process_next.lighting_corner_SE = src
		process_next = get_step(process_next, EAST)
	else
		process_next = locate(x + 1, y + 1, z)

	if(process_next)
		master_NE = process_next
		process_next.lighting_corner_SW = src
		process_next = get_step(process_next, SOUTH)
	else
		process_next = locate(x + 1, y, z)

	if(process_next)
		master_SE = process_next
		process_next.lighting_corner_NW = src

/datum/lighting_corner/proc/vis_update()
	var/thing
	var/datum/light_source/L
	for (thing in affecting)
		L = thing
		L.vis_update()

/datum/lighting_corner/proc/full_update()
	var/thing
	var/datum/light_source/L
	for (thing in affecting)
		L = thing
		L.recalc_corner(src)

/datum/lighting_corner/proc/update_objects()
	// Cache these values ahead of time so 4 individual lighting objects don't all calculate them individually.
	var/lum_r = src.lum_r
	var/lum_g = src.lum_g
	var/lum_b = src.lum_b
	// What gets drawn includes the bounce light, which fills in the dark rather than brightening what's already lit:
	// lit rooms keep their pools of light, while their shadows soften.
	if (bounce_r || bounce_g || bounce_b)
		lum_r += bounce_r * clamp(1 - lum_r, 0, 1)
		lum_g += bounce_g * clamp(1 - lum_g, 0, 1)
		lum_b += bounce_b * clamp(1 - lum_b, 0, 1)
	var/largest_color_luminosity = max(lum_r, lum_g, lum_b) // Scale it so one of them is the strongest lum, if it is above 1.
	. = 1 // factor
	if (largest_color_luminosity > 1)
		. = 1 / largest_color_luminosity

	var/old_r = cache_r
	var/old_g = cache_g
	var/old_b = cache_b

	#if LIGHTING_SOFT_THRESHOLD != 0
	else if (largest_color_luminosity < LIGHTING_SOFT_THRESHOLD)
		. = 0 // 0 means soft lighting.

	cache_r = round(lum_r * ., LIGHTING_ROUND_VALUE) || LIGHTING_SOFT_THRESHOLD
	cache_g = round(lum_g * ., LIGHTING_ROUND_VALUE) || LIGHTING_SOFT_THRESHOLD
	cache_b = round(lum_b * ., LIGHTING_ROUND_VALUE) || LIGHTING_SOFT_THRESHOLD
	#else
	cache_r = round(lum_r * ., LIGHTING_ROUND_VALUE)
	cache_g = round(lum_g * ., LIGHTING_ROUND_VALUE)
	cache_b = round(lum_b * ., LIGHTING_ROUND_VALUE)
	#endif

	src.largest_color_luminosity = round(largest_color_luminosity, LIGHTING_ROUND_VALUE)

	if(old_r == cache_r && old_g == cache_g && old_b == cache_b)
		if (!LAZYLEN(affecting)) // no light affects us any more
			qdel(src, force = TRUE)
		return

	var/atom/movable/lighting_object/lighting_object = master_NE?.lighting_object
	if (lighting_object && !lighting_object.needs_update)
		lighting_object.needs_update = TRUE
		SSlighting.objects_queue += lighting_object

	lighting_object = master_SE?.lighting_object
	if (lighting_object && !lighting_object.needs_update)
		lighting_object.needs_update = TRUE
		SSlighting.objects_queue += lighting_object

	lighting_object = master_SW?.lighting_object
	if (lighting_object && !lighting_object.needs_update)
		lighting_object.needs_update = TRUE
		SSlighting.objects_queue += lighting_object

	lighting_object = master_NW?.lighting_object
	if (lighting_object && !lighting_object.needs_update)
		lighting_object.needs_update = TRUE
		SSlighting.objects_queue += lighting_object

	if (!LAZYLEN(affecting))
		qdel(src, force = TRUE)

/datum/lighting_corner/dummy/New()
	return

/datum/lighting_corner/Destroy(force)
	if (!force)
		return QDEL_HINT_LETMELIVE

	var/thing
	var/datum/light_source/L
	for (thing in affecting)
		L = thing
		LAZYREMOVE(L.effect_str, src)
		LAZYREMOVE(L.bounce_str, src)
	affecting = null

	if (master_NE)
		master_NE.lighting_corner_SW = null
		master_NE.lighting_corners_initialised = FALSE
	if (master_SE)
		master_SE.lighting_corner_NW = null
		master_SE.lighting_corners_initialised = FALSE
	if (master_SW)
		master_SW.lighting_corner_NE = null
		master_SW.lighting_corners_initialised = FALSE
	if (master_NW)
		master_NW.lighting_corner_SE = null
		master_NW.lighting_corners_initialised = FALSE
	if (needs_update)
		SSlighting.corners_queue -= src

	return ..()
