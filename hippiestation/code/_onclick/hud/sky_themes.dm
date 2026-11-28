// The skies a round can have. SSparallax picks one before anyone connects (sky.dm) and everyone gets the same.
//
// A nebula entry is list(state, colour, alpha, flight speed):
//   state    a cloud in sky_nebula.dmi: billow1-6, veil1-2, haze (tools/sky_gen/v2/nebula.py, three tones packed in R, G, B), or the
//            older greyscale cloud1-3, wisp1-2, haze1-2. The galaxy's band is the theme's band var, not an entry
//   colour   a hex tint, or for the packed states a 9-number colour matrix: body, crest and core tones (nebula.py dm prints them).
//            Clouds are added to the sky, so two colours that overlap mix like light: red on blue gives magenta
//   alpha    how strong, 0-255
//   speed    how fast it streams past in a shuttle's flight (1: a repeat in PARALLAX_LOOP_TIME). Walking, every cloud holds still with
//            the rest of the far sky (parallax.dm SKY_DEPTH_FAR): no drift of their own
// The first entry is the one the Medium parallax preference shows, so put the theme's main cloud first.
// tools/sky_gen/sky_gen.py preview reads the entries out of this file: keep each one on a line of its own.

/datum/sky_theme
	var/name = "Open space"
	/// Chance of this sky against the others
	var/weight = 10
	var/list/nebula = list()
	/// Tints every star layer, for a sky with a cast to it. Null leaves the stars their own colours
	var/star_tint
	/// The galaxy in view, an icon state of icons/effects/parallax.dmi, or none
	var/galaxy
	/// The other world of this system, an icon state of sky_bodies.dmi, or none. Lavaland is always there: the station orbits it
	var/neighbour
	/// The colour of the sun, if this sky has one in view
	var/sun
	/// A field of asteroids drifting close by
	var/asteroids = FALSE
	/// The colour of the light space gives off (hulls, windows, breaches): the sky's own cast. Null is the usual COLOR_STARLIGHT
	var/starlight
	/// The galaxy's own band across the sky (sky_band.dmi, coloured bulge to arms with its dark rift): list(tint, alpha), or null
	/// for none. New() adds it to the nebula entries; the round turns it to a slant clear of the sun (sky.dm pick_band)
	var/list/band = list("#ffffff", 220)

/datum/sky_theme/New()
	..()
	if(band)
		nebula += list(list("band", band[1], band[2], 0.2))

/// Every layer of this sky for one client, in no order: each layer knows its own depth.
/datum/sky_theme/proc/build_layers()
	. = list()
	for(var/index in 1 to length(nebula))
		var/obj/screen/parallax_layer/nebula/cloud = new
		cloud.setup(index, nebula[index])
		. += cloud
	for(var/type in list(/obj/screen/parallax_layer/stars/deep, /obj/screen/parallax_layer/stars, /obj/screen/parallax_layer/stars/mid, /obj/screen/parallax_layer/stars/near))
		var/obj/screen/parallax_layer/stars = new type
		stars.color = star_tint
		. += stars
	if(galaxy)
		var/obj/screen/parallax_layer/body/galaxy/far_galaxy = new
		far_galaxy.icon_state = galaxy
		. += far_galaxy
	if(sun)
		var/obj/screen/parallax_layer/body/sun/near_star = new
		near_star.color = sun
		. += near_star
	if(neighbour)
		var/obj/screen/parallax_layer/body/world/other_world = new
		other_world.icon_state = neighbour
		. += other_world
	for(var/index in 1 to length(SSparallax.deep_sky)) //the round's far things, whatever the theme
		var/obj/screen/parallax_layer/body/deep/far_thing = new
		far_thing.setup(index)
		. += far_thing
	. += new /obj/screen/parallax_layer/body/planet
	. += new /obj/screen/parallax_layer/flybys
	. += new /obj/screen/parallax_layer/near_weather // sky_weather.dm
	if(SSparallax.random_layer)
		. += new SSparallax.random_layer
	. += new /obj/screen/parallax_layer/dust

/datum/sky_theme/ember
	name = "Ember Reach"
	nebula = list(
		list("billow1", list(0.499, 0.0867, 0.0434, 0.922, 0.607, 0.26, 0.922, 0.882, 0.795), 255, 0.45),
		list("veil1", list(0.306, 0.108, 0.0432, 0.306, 0.216, 0.108, 0.0696, 0.0144, 0.0192), 255, 0.55),
		list("haze", list(0.0528, 0.012, 0.0624, 0.0696, 0.0192, 0.0096, 0.306, 0.127, 0.0576), 255, 0.35))
	neighbour = "world_redrock"
	sun = "#ffd2a8"
	starlight = "#f08a6c"
	band = list("#ffe2c8", 185)

/datum/sky_theme/glacier
	name = "Glacier Drift"
	nebula = list(
		list("billow2", list(0.048, 0.214, 0.517, 0.347, 0.827, 0.941, 0.797, 0.915, 0.941), 255, 0.45),
		list("veil2", list(0.215, 0.389, 0.431, 0.179, 0.206, 0.431, 0.0169, 0.0507, 0.108), 255, 0.55),
		list("haze", list(0.0295, 0.0886, 0.157, 0.0197, 0.118, 0.182, 0.182, 0.354, 0.492), 255, 0.35))
	neighbour = "world_ice"
	galaxy = "galaxy3"
	starlight = "#6cb6f5"
	band = list("#d8ecff", 220)

/datum/sky_theme/violet
	name = "Violet Deep"
	nebula = list(
		list("billow3", list(0.262, 0.0424, 0.509, 0.902, 0.205, 0.545, 0.902, 0.821, 0.87), 255, 0.42),
		list("veil1", list(0.101, 0.175, 0.243, 0.147, 0.132, 0.243, 0.0305, 0.00953, 0.0534), 255, 0.58),
		list("haze", list(0.0336, 0.0096, 0.0672, 0.0576, 0.012, 0.048, 0.192, 0.115, 0.306), 255, 0.35))
	neighbour = "world_rock"
	sun = "#d8dcff"
	starlight = "#a97cf5"
	band = list("#e8dcff", 185)

/datum/sky_theme/verdant
	name = "Verdant Shoal"
	nebula = list(
		list("billow4", list(0.0252, 0.303, 0.233, 0.151, 0.763, 0.53, 0.804, 0.763, 0.504), 255, 0.45),
		list("veil1", list(0.163, 0.192, 0.104, 0.192, 0.151, 0.0723, 0.00452, 0.0316, 0.0271), 255, 0.55),
		list("haze", list(0.00572, 0.04, 0.0553, 0.00763, 0.0458, 0.0267, 0.061, 0.198, 0.153), 255, 0.35))
	neighbour = "world_jungle"
	galaxy = "galaxy4"
	starlight = "#62d9b4"
	band = list("#dcffe8", 185)

/datum/sky_theme/gold
	name = "Gilded Band"
	nebula = list(
		list("billow6", list(0.385, 0.214, 0.0378, 0.804, 0.656, 0.353, 0.804, 0.776, 0.694), 255, 0.40),
		list("veil2", list(0.125, 0.233, 0.365, 0.189, 0.325, 0.431, 0.0169, 0.044, 0.0812), 255, 0.48),
		list("haze", list(0.0969, 0.0646, 0.0277, 0.0277, 0.06, 0.0969, 0.443, 0.332, 0.185), 255, 0.35))
	band = list("#ffe6b0", 250)
	sun = "#fff0c8"
	asteroids = TRUE
	starlight = "#f2cf86"

/datum/sky_theme/rose
	name = "Rose Nursery"
	nebula = list(
		list("billow5", list(0.554, 0.0969, 0.346, 0.882, 0.422, 0.664, 0.882, 0.83, 0.858), 255, 0.42),
		list("billow3", list(0.066, 0.152, 0.447, 0.244, 0.447, 0.647, 0.589, 0.619, 0.647), 255, 0.52),
		list("veil2", list(0.314, 0.256, 0.285, 0.314, 0.17, 0.246, 0.0591, 0.0197, 0.0517), 255, 0.58))
	neighbour = "world_ocean"
	starlight = "#f08ac2"
	band = list("#ffdcec", 220)

/// The old look: black, a faint band, a galaxy. Likelier than any one of the others, so the rich skies stay an occasion
/datum/sky_theme/quiet
	name = "Quiet Black"
	weight = 20
	nebula = list(
		list("haze", list(0.0418, 0.068, 0.146, 0.0314, 0.0523, 0.105, 0.235, 0.277, 0.403), 255, 0.35),
		list("veil2", list(0.0847, 0.108, 0.175, 0.0614, 0.076, 0.14, 0.0175, 0.0234, 0.0468), 255, 0.40))
	band = list("#c8d4f0", 150)
	galaxy = "galaxy"
	asteroids = TRUE

/datum/sky_theme/quiet/New()
	. = ..()
	galaxy = pick("galaxy", "galaxy2", "galaxy3", "galaxy4")
