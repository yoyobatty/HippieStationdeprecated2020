// The skies a round can have. SSparallax picks one before anyone connects (sky.dm) and everyone gets the same.
//
// A nebula entry is list(state, colour, alpha, speed, minutes, heading):
//   state    a greyscale cloud in sky_nebula.dmi: cloud1-3 (billows), wisp1-2 (strands), haze1-2 (a faint wash), band (a galaxy's band)
//   colour   what it's tinted. Clouds are added to the sky, so two colours that overlap mix like light: red on blue gives magenta
//   alpha    how strong, 0-255
//   speed    pixels it slides per tile walked. Stars run from 0.3 (deep) to 1.6 (near), so a cloud under 0.6 sits among the far stars
//   minutes  how long it takes to drift one repeat of its art (960 pixels), 0 to stay put
//   heading  which way it drifts: list(x, y), each -1, 0 or 1
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
	. += new /obj/screen/parallax_layer/body/planet
	. += new /obj/screen/parallax_layer/flybys
	if(SSparallax.random_layer)
		. += new SSparallax.random_layer
	. += new /obj/screen/parallax_layer/dust

/datum/sky_theme/ember
	name = "Ember Reach"
	nebula = list(
		list("cloud1", "#c2381f", 235, 0.45, 40, list(1, 0)),
		list("wisp1", "#ff9a3c", 120, 0.55, 55, list(0, 1)),
		list("haze1", "#3a1030", 200, 0.35, 0, list(0, 0)))
	neighbour = "world_redrock"
	sun = "#ffd2a8"

/datum/sky_theme/glacier
	name = "Glacier Drift"
	nebula = list(
		list("cloud2", "#1f6fc2", 240, 0.45, 45, list(-1, 0)),
		list("wisp2", "#7fe6ff", 105, 0.55, 60, list(0, -1)),
		list("haze2", "#0c2440", 220, 0.35, 0, list(0, 0)))
	neighbour = "world_ice"
	galaxy = "galaxy3"

/datum/sky_theme/violet
	name = "Violet Deep"
	nebula = list(
		list("cloud3", "#7a2bd0", 225, 0.42, 50, list(0, 1)),
		list("cloud1", "#d0358f", 175, 0.52, 38, list(1, 0)),
		list("wisp1", "#9fb4ff", 80, 0.58, 60, list(-1, 0)))
	neighbour = "world_rock"
	sun = "#d8dcff"

/datum/sky_theme/verdant
	name = "Verdant Shoal"
	nebula = list(
		list("cloud2", "#17a58a", 225, 0.45, 45, list(1, 0)),
		list("wisp1", "#a8ff9a", 70, 0.55, 55, list(0, 1)),
		list("haze1", "#062a3a", 225, 0.35, 0, list(0, 0)))
	neighbour = "world_jungle"
	galaxy = "galaxy4"

/datum/sky_theme/gold
	name = "Gilded Band"
	nebula = list(
		list("band", "#d9a760", 230, 0.40, 0, list(0, 0)),
		list("haze2", "#3a2410", 200, 0.35, 0, list(0, 0)))
	sun = "#fff0c8"
	asteroids = TRUE

/datum/sky_theme/rose
	name = "Rose Nursery"
	nebula = list(
		list("cloud1", "#d04a8a", 225, 0.42, 45, list(0, -1)),
		list("cloud3", "#2f6fe0", 200, 0.52, 36, list(1, 0)),
		list("wisp2", "#ffd0e8", 75, 0.58, 60, list(0, 1)))
	neighbour = "world_ocean"

/// The old look: black, a faint band, a galaxy. Likelier than any one of the others, so the rich skies stay an occasion
/datum/sky_theme/quiet
	name = "Quiet Black"
	weight = 20
	nebula = list(
		list("haze1", "#101a38", 180, 0.35, 0, list(0, 0)),
		list("band", "#8f9fc8", 90, 0.40, 0, list(0, 0)))
	galaxy = "galaxy"
	asteroids = TRUE

/datum/sky_theme/quiet/New()
	..()
	galaxy = pick("galaxy", "galaxy2", "galaxy3", "galaxy4")
