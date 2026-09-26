#define THERMAL_REFRESH_TIME 5 // deciseconds between updates of the heat map
#define THERMAL_MIN_PRESSURE 5 // kPa. Air thinner than this has no meaningful temperature, so those turfs aren't drawn
#define THERMAL_WALL_THRESHOLD 8 // kelvin a wall or other solid turf has to be from room temperature before it's drawn, or every wall would be tinted
#define THERMAL_ALPHA_BASE 90 // opacity of a room temperature turf
#define THERMAL_ALPHA_EXTREME 235 // opacity of a turf far from room temperature
#define THERMAL_ALPHA_RANGE 300 // how far from room temperature, in kelvin, a turf has to be to get the extreme opacity
#define THERMAL_MOB_ALPHA 210
#define THERMAL_DOOR_ALPHA 200
#define THERMAL_GLOW_BASE 3 // opacity of the glow at room temperature, which is almost nothing
#define THERMAL_GLOW_MAX 235 // opacity of the glow at the extremes
#define THERMAL_GLOW_CURVE 2 // how sharply the glow climbs away from room temperature. 1 is a straight line, 2 or more keeps it low until things are well off room temperature
#define THERMAL_GLOW_HEAT_RANGE 250 // how far above room temperature, in kelvin, things have to be to glow at full strength
#define THERMAL_GLOW_COLD_PEAK 3.15 // kelvin, which is -270C. The glow is at full strength here on the cold side, and stays there for anything colder
#define THERMAL_BLOOM_THRESHOLD "#080808" // how bright a pixel of the glow has to be to bloom. Low, so the subtle glow at room temperature still shows
#define THERMAL_BLOOM_SIZE 4 // blur of the glow in pixels
#define THERMAL_BLOOM_OFFSET 2 // how far the glow grows out from the bright parts before it's blurred

/// The heat map colors, as list(temperature in kelvin, red, green, blue). Anything between two of them is blended, anything past the ends gets the end color.
GLOBAL_LIST_INIT(thermal_gradient, list(
	list(150, 70, 70, 255), // deep space cold
	list(250, 30, 100, 255), // freezing
	list(273, 0, 200, 255), // cold
	list(293, 40, 200, 90), // comfortable
	list(313, 130, 220, 40), // warm
	list(333, 255, 230, 40), // hot
	list(373, 255, 140, 20), // boiling
	list(500, 255, 50, 20), // fire
	list(800, 255, 40, 160), // very hot
	list(1500, 255, 255, 255))) // white hot

/// Colors already worked out, by temperature rounded to the nearest few kelvin
GLOBAL_LIST_EMPTY(thermal_color_cache)

/**
  * The heat map color for a temperature, as a color matrix that turns anything into that flat color and keeps its opacity.
  * Cached, since a few hundred turfs ask for these several times a second.
  */
/proc/thermal_color(temperature)
	var/step = temperature < 400 ? 2 : 10 // fine steps where people live, rough ones where things are on fire
	var/key = round(temperature, step)
	var/list/cached = GLOB.thermal_color_cache["[key]"]
	if(cached)
		return cached
	var/list/gradient = GLOB.thermal_gradient
	var/list/low = gradient[1]
	var/list/high = gradient[gradient.len]
	var/red = high[2]
	var/green = high[3]
	var/blue = high[4]
	if(key <= low[1])
		red = low[2]
		green = low[3]
		blue = low[4]
	else if(key < high[1])
		for(var/i in 1 to gradient.len - 1)
			var/list/a = gradient[i]
			var/list/b = gradient[i + 1]
			if(key >= a[1] && key <= b[1])
				var/blend = (key - a[1]) / (b[1] - a[1])
				red = a[2] + (b[2] - a[2]) * blend
				green = a[3] + (b[3] - a[3]) * blend
				blue = a[4] + (b[4] - a[4]) * blend
				break
	cached = list(0,0,0, 0,0,0, 0,0,0, red / 255, green / 255, blue / 255)
	GLOB.thermal_color_cache["[key]"] = cached
	return cached

/**
  * What temperature to show for a closed door: the most extreme air temperature next to it, on either side. A closed door blocks air, so
  * its own tile says little, but the tiles either side of it say what's on the other side. Null if there's no air next to it at all.
  */
/proc/thermal_door_temperature(obj/machinery/door/D)
	var/turf/T = get_turf(D)
	if(!T)
		return null
	var/best_temperature
	var/best_deviation = -1
	for(var/direction in GLOB.cardinals)
		var/turf/open/neighbor = get_step(T, direction)
		if(!istype(neighbor) || !neighbor.air || neighbor.air.return_pressure() < THERMAL_MIN_PRESSURE)
			continue
		var/deviation = abs(neighbor.air.temperature - T20C)
		if(deviation > best_deviation)
			best_deviation = deviation
			best_temperature = neighbor.air.temperature
	return best_temperature

/// What temperature to show for a turf, or null if it isn't worth drawing.
/proc/thermal_turf_temperature(turf/T)
	if(isspaceturf(T))
		return null
	if(isopenturf(T))
		var/obj/machinery/door/D = locate(/obj/machinery/door) in T
		if(D && D.density) // a closed door's own tile shows what's on either side of it instead
			var/door_temperature = thermal_door_temperature(D)
			if(!isnull(door_temperature))
				return door_temperature
		var/turf/open/O = T
		if(!O.air || O.air.return_pressure() < THERMAL_MIN_PRESSURE)
			return null
		return O.air.temperature
	if(abs(T.temperature - T20C) < THERMAL_WALL_THRESHOLD)
		return null
	return T.temperature

/**
  * How strongly something glows at a temperature, as an opacity. Room temperature has almost no glow, and it climbs along a curve
  * towards both ends of the spectrum, reaching full strength about THERMAL_GLOW_HEAT_RANGE above room temperature on the hot side
  * and at THERMAL_GLOW_COLD_PEAK, -270C, on the cold side. The colder or hotter something is, the more it stands out.
  */
/proc/thermal_glow_alpha(temperature)
	var/deviation = temperature - T20C
	var/strength
	if(deviation >= 0)
		strength = clamp(deviation / THERMAL_GLOW_HEAT_RANGE, 0, 1)
	else
		strength = clamp(-deviation / (T20C - THERMAL_GLOW_COLD_PEAK), 0, 1)
	strength = strength ** THERMAL_GLOW_CURVE
	return round(THERMAL_GLOW_BASE + (THERMAL_GLOW_MAX - THERMAL_GLOW_BASE) * strength)

/**
  * The plane the glow of the heat map is drawn on. It adds itself over everything below, dark rooms included, and blooms, so hot spots
  * glow and spill light onto their surroundings. How strongly each thing glows is set by its own opacity, see thermal_glow_alpha().
  *
  * A world /image's own mouse_opacity is ignored by the click system: a click on one resolves against whatever atom it's attached
  * to (here, the turf, mob or door it's drawn at), not the image. That was making thermal vision steal clicks meant for items sitting
  * on a tile, since the image renders above them. The documented fix is different: a PLANE_MASTER atom's own mouse_opacity, set to
  * MOUSE_OPACITY_TRANSPARENT, makes its whole plane click-through regardless of what's on it. Each part of the heat map gets its own
  * plane just so this can be set without affecting anything else that shares ABOVE_LIGHTING_PLANE.
  */
/obj/screen/plane_master/thermal_glow
	name = "thermal glow plane master"
	plane = THERMAL_GLOW_PLANE
	appearance_flags = PLANE_MASTER|NO_CLIENT_COLOR
	blend_mode = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/thermal_glow/Initialize()
	. = ..()
	filters += filter(type = "bloom", threshold = THERMAL_BLOOM_THRESHOLD, size = THERMAL_BLOOM_SIZE, offset = THERMAL_BLOOM_OFFSET)

/// The plain, non-glowing part of the heat map. See the docs on thermal_glow above for why this needs its own plane.
/obj/screen/plane_master/thermal_tint
	name = "thermal tint plane master"
	plane = THERMAL_TINT_PLANE
	appearance_flags = PLANE_MASTER|NO_CLIENT_COLOR
	blend_mode = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/**
  * A heat map over everything a player can see, working in the dark: every turf with air in it is tinted by its temperature, walls
  * and other solid turfs only when they're well off room temperature (which shows heat leaking through windows and walls), and every
  * living thing is drawn as a silhouette colored by its body temperature.
  *
  * Everything is drawn twice. The tint is drawn plain and added to the picture on a plane above the lighting, so it shows up in the
  * dark. The glow is a copy on its own blooming plane, and its opacity follows thermal_glow_alpha(), so it's barely there at room
  * temperature and strongest at both extremes, without changing how visible the tint is.
  *
  * Only that one player sees the images. It keeps them between updates and just recolors them, adding and dropping them as the
  * view changes, and updates a couple of times a second.
  */
/datum/thermal_vision
	var/mob/viewer
	var/client/viewer_client
	var/list/turf_images = list() // turf = list(tint image, glow image)
	var/list/mob_images = list() // living mob = list(tint image, glow image)
	var/list/door_images = list() // closed door = list(tint image, glow image)
	var/refresh_timer

/datum/thermal_vision/New(mob/viewer)
	src.viewer = viewer
	viewer_client = viewer.client
	refresh()

/datum/thermal_vision/Destroy()
	deltimer(refresh_timer)
	clear_images()
	viewer = null
	viewer_client = null
	return ..()

/datum/thermal_vision/proc/clear_images()
	if(viewer_client)
		for(var/turf/T in turf_images)
			viewer_client.images -= turf_images[T]
		for(var/mob/living/L in mob_images)
			viewer_client.images -= mob_images[L]
		for(var/obj/machinery/door/D in door_images)
			viewer_client.images -= door_images[D]
	turf_images.Cut()
	mob_images.Cut()
	door_images.Cut()

/// Colors a tint and glow pair for a temperature. The tint is added to the picture above the lighting, and the glow goes on the blooming plane.
/datum/thermal_vision/proc/style_pair(list/pair, temperature, tint_alpha, layer_offset = 0)
	var/image/tint = pair[1]
	var/image/glow = pair[2]
	var/list/color = thermal_color(temperature)
	tint.plane = THERMAL_TINT_PLANE
	tint.layer = THERMAL_TINT_PLANE + layer_offset
	tint.color = color
	tint.alpha = tint_alpha
	glow.plane = THERMAL_GLOW_PLANE
	glow.layer = THERMAL_GLOW_PLANE + layer_offset
	glow.color = color
	glow.alpha = thermal_glow_alpha(temperature)

/datum/thermal_vision/proc/refresh()
	refresh_timer = null
	if(QDELETED(viewer) || !viewer.client || viewer.client != viewer_client)
		qdel(src)
		return
	var/list/view_size = getviewsize(viewer_client.view)
	var/radius = CEILING(max(view_size[1], view_size[2]) / 2, 1)

	var/list/seen_turfs = list()
	for(var/turf/T in view(radius, viewer))
		var/temperature = thermal_turf_temperature(T)
		if(isnull(temperature))
			continue
		seen_turfs[T] = TRUE
		var/list/pair = turf_images[T]
		if(!pair)
			pair = list(image('icons/turf/overlays.dmi', T, "greenOverlay"), image('icons/turf/overlays.dmi', T, "greenOverlay"))
			turf_images[T] = pair
			viewer_client.images += pair
		style_pair(pair, temperature, THERMAL_ALPHA_BASE + (THERMAL_ALPHA_EXTREME - THERMAL_ALPHA_BASE) * clamp(abs(temperature - T20C) / THERMAL_ALPHA_RANGE, 0, 1))
	for(var/turf/T in turf_images.Copy()) // copied, since it's being removed from
		if(!seen_turfs[T])
			viewer_client.images -= turf_images[T]
			turf_images -= T

	var/list/seen_mobs = list()
	for(var/mob/living/L in view(radius, viewer))
		if(L == viewer)
			continue
		seen_mobs[L] = TRUE
		var/list/pair = mob_images[L]
		if(!pair)
			pair = list(image(loc = L), image(loc = L))
			mob_images[L] = pair
			viewer_client.images += pair
		for(var/image/I in pair)
			I.appearance = L.appearance // the silhouette follows whatever the mob is currently wearing and doing
		style_pair(pair, L.bodytemperature, THERMAL_MOB_ALPHA, 0.1)
	for(var/mob/living/L in mob_images.Copy())
		if(!seen_mobs[L])
			viewer_client.images -= mob_images[L]
			mob_images -= L

	// Closed doors glow with the temperature on either side of them
	var/list/seen_doors = list()
	for(var/obj/machinery/door/D in view(radius, viewer))
		if(!D.density)
			continue
		var/door_temperature = thermal_door_temperature(D)
		if(isnull(door_temperature))
			continue
		seen_doors[D] = TRUE
		var/list/pair = door_images[D]
		if(!pair)
			pair = list(image(loc = D), image(loc = D))
			door_images[D] = pair
			viewer_client.images += pair
		for(var/image/I in pair)
			I.appearance = D.appearance
		style_pair(pair, door_temperature, THERMAL_DOOR_ALPHA, 0.05)
	for(var/obj/machinery/door/D in door_images.Copy())
		if(!seen_doors[D])
			viewer_client.images -= door_images[D]
			door_images -= D

	refresh_timer = addtimer(CALLBACK(src, PROC_REF(refresh)), THERMAL_REFRESH_TIME, TIMER_STOPPABLE)
