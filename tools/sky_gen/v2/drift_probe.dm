// Not part of the game: included only by tools/sky_gen/v2/drift_check.py's side build.
// /proc/sky_drift_probe(rounds) re-rolls the sky `rounds` times (SSparallax.PreInit(), as a round start does) and, for each,
// makes the real layers (theme.build_layers()) and reports every one that sits at a place of its own (the absolute layers:
// sun, other world, Lavaland, galaxy, far things) with the eye over the station's middle:
//   place  where update_parallax() would put it on screen with the sky unturned (place_x/place_y)
//   rest   its sky_rest(): the part of the place that turns with the sky
//   core   the radius holding most of its light (the numbers sky.dm's placement keeps apart)
// plus the round's band (angle, offset along its normal), starting angle and turn rate.

/proc/sky_drift_probe(rounds = 40)
	var/list/out = list()
	var/eye_x = SSparallax.planet_x_offset
	var/eye_y = SSparallax.planet_y_offset
	for(var/round in 1 to rounds)
		SSparallax.PreInit()
		var/datum/sky_theme/theme = SSparallax.theme
		var/list/things = list()
		for(var/obj/screen/parallax_layer/L as anything in theme.build_layers())
			if(L.absolute && !istype(L, /obj/screen/parallax_layer/flybys))
				var/name
				var/core
				if(istype(L, /obj/screen/parallax_layer/body/planet))
					name = "planet"
					core = SKY_PLANET_CORE
				else if(istype(L, /obj/screen/parallax_layer/body/deep))
					var/obj/screen/parallax_layer/body/deep/D = L
					var/list/far_thing = SSparallax.deep_sky[D.index]
					name = "deep[D.index]"
					core = SSparallax.deep_core(far_thing[1]) * far_thing[3]
				else if(istype(L, /obj/screen/parallax_layer/body))
					var/obj/screen/parallax_layer/body/B = L
					name = B.place
					core = list("sun" = SKY_SUN_CORE, "world" = SKY_WORLD_CORE, "galaxy" = SKY_GALAXY_CORE)[B.place] || 40
				if(name)
					things[name] = list("place" = list(L.place_x(eye_x), L.place_y(eye_y)), "rest" = L.sky_rest(), "core" = core, "angle" = L.angle)
			qdel(L)
		var/band = null
		if(SSparallax.has_band())
			band = list("angle" = theme.band_angle, "offset" = SSparallax.band_offset, "period" = PARALLAX_TILE * SKY_NEBULA_SCALE)
		var/list/line = SSparallax.turn_line
		out += list(list("theme" = "[theme.type]", "things" = things, "band" = band,
			"start_angle" = sky_turn_angle(), "turn_per_minute" = line ? line[3] * (1 MINUTES) : 0))
	return json_encode(out) //as text: the testkit flattens lists this deep
