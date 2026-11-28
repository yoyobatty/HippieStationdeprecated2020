/turf/proc/get_rgb_lumcount(var/minlum = 0, var/maxlum = 1, var/r_mul = 1, var/g_mul = 1, var/b_mul = 1)
	if (!lighting_object)
		return 1

	var/totallums = 0
	if (SSlighting.native) // the engine keeps the corners: NE, SE, SW, NW, each light r, g, b, bounce (3), colour (3), brightest (lighting_engine lib.rs lighting_corners)
		var/list/native_corners = list()
		call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_corners")(src, native_corners)
		for (var/at in list(1, 11, 21, 31))
			if (at + 2 > length(native_corners))
				break
			totallums += (native_corners[at] * r_mul) + (native_corners[at + 1] * g_mul) + (native_corners[at + 2] * b_mul)
	else
		var/datum/lighting_corner/L
		for (var/thing in get_lighting_corners())
			L = thing
			totallums += (L.lum_r * r_mul) + (L.lum_b * b_mul) + (L.lum_g * g_mul)

	totallums /= 12 // 4 corners, each with 3 channels, get the average.

	totallums = (totallums - minlum) / (maxlum - minlum)

	return CLAMP01(totallums)