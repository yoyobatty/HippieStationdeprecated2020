// Eye adaptation. Each player's eyes get used to the dark: in a dim place their lighting is slowly turned up a little, and back
// down quickly in bright light. Every half second the server measures how bright what the player can see looks (the lighting
// engine's lighting_eye(), from the corners as drawn, only what's in sight; or the DM corners round about), eases the exposure
// toward what suits it, and animates the client's lighting plane master's colour there. The light map is multiplied up, so a
// tile with no light on it stays black: dim light gets easier to see, darkness doesn't go away.
//
// Medium graphics and up. Off while something else decides how dark looks (lighting_alpha: night vision, mesons and co.).
// The tone curve on the light map, which keeps bright from flattening out, is in lighting_corner/update_objects() and the
// engine: both in code/__DEFINES/~hippie_defines/lighting_tone.dm.

GLOBAL_VAR_INIT(lighting_tone_knee, LIGHTING_TONE_KNEE)

/obj/screen/plane_master/lighting
	/// What the light map is multiplied by: eye adaptation's exposure, worked out on the server
	var/exposure = 1
	/// The exposure last sent to the client
	var/exposure_shown = 1

SUBSYSTEM_DEF(eye_adapt)
	name = "Eye Adaptation"
	wait = EYE_ADAPT_WAIT
	flags = SS_BACKGROUND | SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	var/list/client/currentrun = list()
	/// The engine can't measure (a library from before lighting_eye()): nobody adapts while it's running
	var/engine_cant = FALSE
	/// Players whose lighting is turned up at the moment, as of the last full pass
	var/adapted = 0
	var/adapting = 0
	/// Exposure changes sent since the round started
	var/sent = 0

/datum/controller/subsystem/eye_adapt/stat_entry(msg)
	return ..("A:[adapted] S:[sent][engine_cant ? " (engine can't measure)" : ""]")

/datum/controller/subsystem/eye_adapt/fire(resumed)
	if(!resumed)
		currentrun = GLOB.clients.Copy()
		adapted = adapting
		adapting = 0
	while(length(currentrun))
		var/client/C = currentrun[length(currentrun)]
		currentrun.len--
		if(C)
			adapt(C)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/eye_adapt/proc/adapt(client/C)
	var/mob/M = C.mob
	var/obj/screen/plane_master/lighting/PM = M?.hud_used?.plane_masters["[LIGHTING_PLANE]"]
	if(!PM)
		return
	var/target = 1
	if(wants_adapting(C, M))
		var/turf/T = get_turf(C.eye)
		var/brightness = T ? eye_brightness(T, C) : -1
		if(brightness >= 0)
			target = clamp(EYE_ADAPT_KEY / max(brightness, 0.01), 1, EYE_ADAPT_MAX)
	var/now = PM.exposure
	if(now != target)
		// Into the dark slowly, back into the light quickly
		var/static/dark_step = 1 - NUM_E ** (-EYE_ADAPT_WAIT / EYE_ADAPT_DARK_TIME)
		var/static/light_step = 1 - NUM_E ** (-EYE_ADAPT_WAIT / EYE_ADAPT_LIGHT_TIME)
		now += (target - now) * (target > now ? dark_step : light_step)
		if(abs(target - now) < EYE_ADAPT_STEP)
			now = target
		PM.exposure = now
	if(now > 1)
		adapting++
	if(now == PM.exposure_shown || (abs(now - PM.exposure_shown) < EYE_ADAPT_STEP && now != target))
		return
	PM.exposure_shown = now
	sent++
	// Parallel, so a skewed or spinning screen (skewium, the floor cluwne) keeps spinning
	animate(PM, color = list(now, 0, 0, 0, now, 0, 0, 0, now, 0, 0, 0), time = EYE_ADAPT_WAIT, flags = ANIMATION_PARALLEL)

/// Whether this player's eyes adjust at all just now
/datum/controller/subsystem/eye_adapt/proc/wants_adapting(client/C, mob/M)
	if((engine_cant && SSlighting.native) || isnewplayer(M))
		return FALSE
	if(M.lighting_alpha != LIGHTING_PLANE_ALPHA_VISIBLE)
		return FALSE
	return !C.prefs || C.prefs.graphics_quality() >= GRAPHICS_QUALITY_MEDIUM

/// How bright what can be seen from a turf looks, 0 to 1, within the client's view; -1 if it can't be told
/datum/controller/subsystem/eye_adapt/proc/eye_brightness(turf/T, client/C)
	var/static/list/view_ranges = list()
	var/view_key = "[C.view]"
	var/list/ranges = view_ranges[view_key]
	if(!ranges)
		var/list/size = getviewsize(C.view)
		ranges = list(round(size[1] / 2), round(size[2] / 2))
		view_ranges[view_key] = ranges
	return eye_brightness_at(T, ranges[1], ranges[2])

/// How bright what can be seen from a turf looks, 0 to 1, up to range_x tiles east and west and range_y north and south; -1 if
/// it can't be told
/datum/controller/subsystem/eye_adapt/proc/eye_brightness_at(turf/T, range_x, range_y)
	if(SSlighting.native)
		var/result
		try
			result = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_eye")(T, range_x, range_y)
		catch(var/exception/error)
			result = "[error]"
		if(!isnum(result) || result < 0)
			engine_cant = TRUE
			log_world("Eye adaptation: the lighting engine can't measure ([result]), off until it can")
			return -1
		return result
	// The DM corners: everything round about with a lighting object, in sight or not
	var/total = 0
	var/counted = 0
	for(var/turf/U as anything in block(locate(max(1, T.x - range_x), max(1, T.y - range_y), T.z), locate(min(world.maxx, T.x + range_x), min(world.maxy, T.y + range_y), T.z)))
		if(!U.lighting_object)
			continue
		var/here = 0
		for(var/datum/lighting_corner/corner as anything in list(U.lighting_corner_NE, U.lighting_corner_SE, U.lighting_corner_SW, U.lighting_corner_NW))
			if(corner)
				here += 0.2126 * corner.cache_r + 0.7152 * corner.cache_g + 0.0722 * corner.cache_b
		total += here / 4
		counted++
	return counted ? total / counted : 1
