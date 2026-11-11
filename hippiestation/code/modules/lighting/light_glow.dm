// Lights that move, and the finish on the lighting as a whole.
//
// A fire's light flickers, a tripped fire alarm's pulses, the supermatter's throbs. None of that goes through the lighting engine:
// changing a real light's power several times a second would have it recalculated each time, for everyone, seen or not. It's a
// soft pool of light instead (/obj/effect/light_glow), one object for the whole server per kind, animated once on the clients
// and held in the vis_contents of whatever gives the light off. The pools are drawn on a hidden plane of their own, and each
// client's lighting plane adds that plane into itself before it darkens the screen. So a pool lights what's in view like any
// light does, can't shine onto what the client can't see, and a client on Low graphics just doesn't add it.
//
// The lighting plane's other filters are put on here too, in the order they have to go: pools in, then the soft blur, then the
// emissive and space cut-outs (which have to stay sharp, and stay fully cut).

#define LIGHT_GLOW_SIZE 224 // the sprite's, tools/light_gen/light_gen.py

GLOBAL_LIST_EMPTY(light_glows)

/obj/screen/plane_master/light_glow
	name = "light glow plane master"
	plane = LIGHT_GLOW_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = LIGHT_GLOW_RENDER_TARGET

/obj/effect/light_glow
	name = ""
	icon = 'hippiestation/icons/effects/light_glow.dmi'
	icon_state = "soft"
	plane = LIGHT_GLOW_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM // a fire is tinted, faded and turned: its light isn't
	vis_flags = NONE //its own plane, not the holder's: /obj/effect inherits the plane by default, which drew the pools on the game plane
	anchored = TRUE
	pixel_x = (32 - LIGHT_GLOW_SIZE) / 2
	pixel_y = (32 - LIGHT_GLOW_SIZE) / 2

/// Runs through the alphas for good, taking times[i] deciseconds to reach alphas[i].
/obj/effect/light_glow/proc/pulse(list/alphas, list/times, easing = LINEAR_EASING)
	alpha = alphas[length(alphas)]
	animate(src, alpha = alphas[1], time = times[1], loop = -1, easing = easing)
	for(var/i in 2 to length(alphas))
		animate(alpha = alphas[i], time = times[i], easing = easing)

/**
  * The shared pool of light of a kind: add it to the vis_contents of what gives the light off.
  * fire1 to fire3 flicker out of step with each other, alarm pulses once a second, supermatter throbs slowly.
  * The alphas are low on purpose: these go on top of a real light, and are only the part of it that moves.
  */
/proc/light_glow(kind)
	var/obj/effect/light_glow/G = GLOB.light_glows[kind]
	if(G)
		return G
	G = new
	switch(kind)
		if("fire1")
			G.color = "#ff9a3c"
			G.pulse(list(95, 55, 110, 70, 120, 50, 100, 65), list(2, 1.5, 2.5, 1, 2, 1.5, 3, 2))
		if("fire2")
			G.color = "#ffa648"
			G.pulse(list(60, 115, 75, 100, 50, 90, 120), list(1.5, 2.5, 2, 1, 2, 3, 1.5))
		if("fire3")
			G.color = "#ff8c30"
			G.pulse(list(105, 65, 90, 55, 115, 80), list(3, 2, 1.5, 2.5, 2, 1))
		if("alarm")
			G.color = "#ff3a2a"
			G.pulse(list(130, 15), list(5, 5), SINE_EASING)
		if("supermatter")
			G.color = "#ffe46b"
			G.transform = matrix(1.25, 0, 0, 0, 1.25, 0)
			G.pulse(list(120, 35), list(13, 13), SINE_EASING)
	GLOB.light_glows[kind] = G
	return G

// ---- What pulses

/obj/effect/hotspot/Initialize(mapload, starting_volume, starting_temperature)
	. = ..()
	// One fire in four carries a pool: they overlap for tiles around, and a big fire is hundreds of these
	if(!(x % 2) && !(y % 2))
		vis_contents += light_glow("fire[1 + ((x / 2 + y / 2) % 3)]")

/obj/machinery/firealarm/update_fire_light(fire)
	..()
	if(fire)
		vis_contents |= light_glow("alarm")
	else
		vis_contents -= light_glow("alarm")

/obj/machinery/power/supermatter_crystal/Initialize()
	. = ..()
	vis_contents += light_glow("supermatter")

// ---- Worn tubes: a few of the lamps down in maintenance sputter now and then. These do go dark for real, which is the point of
// them, so it's the fixture's own flicker(), kept rare: one tube on the whole station every half minute or so. With more than
// twenty worn (Tired wiring, station_looks/looks_wiring.dm) they come round faster, so each still sputters about as often.
// A new tube in the fitting is a sound one (fresh_tube() in station_looks/looks_lamps.dm).

GLOBAL_LIST_EMPTY(worn_lights)

/obj/machinery/light
	/// A worn tube, one of GLOB.worn_lights
	var/worn = FALSE

/obj/machinery/light/proc/wear_tube()
	if(worn)
		return
	worn = TRUE
	if(!length(GLOB.worn_lights))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sputter_worn_light)), rand(20 SECONDS, 40 SECONDS))
	GLOB.worn_lights += src

/obj/machinery/light/Destroy()
	GLOB.worn_lights -= src
	GLOB.buzzing_lights -= src
	return ..()

/proc/sputter_worn_light()
	if(!length(GLOB.worn_lights))
		return //the next worn tube built starts it again
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sputter_worn_light)), rand(20 SECONDS, 40 SECONDS) / max(1, length(GLOB.worn_lights) / 20))
	var/obj/machinery/light/L = pick(GLOB.worn_lights)
	L.sputter()

/obj/machinery/light/proc/sputter()
	set waitfor = FALSE
	if(!on || status != LIGHT_OK || flickering)
		return
	var/switched = switchcount
	flicker(rand(2, 4) * 2) //an even count: it ends lit
	while(flickering && !QDELETED(src))
		sleep(5)
	switchcount = switched //sputtering isn't switching: it doesn't bring the tube any nearer burning out
	if(tired && !QDELETED(src) && on && status == LIGHT_OK && prob(LOOK_TIRED_BURNOUT)) //a tired one does go in the end
		burn_out()
		update(FALSE)

// ---- Each client's lighting plane

/obj/screen/plane_master/lighting
	/// The Graphics quality its filters were last put on for
	var/filter_quality

/obj/screen/plane_master/lighting/Initialize()
	. = ..()
	build_filters(GRAPHICS_QUALITY_HIGH)

/obj/screen/plane_master/lighting/backdrop(mob/mymob)
	. = ..()
	var/quality = mymob?.client?.prefs ? mymob.client.prefs.graphics_quality() : GRAPHICS_QUALITY_HIGH
	if(quality != filter_quality)
		build_filters(quality)

/obj/screen/plane_master/lighting/proc/build_filters(quality)
	filter_quality = quality
	filters = list()
	if(quality >= GRAPHICS_QUALITY_MEDIUM)
		filters += filter(type = "layer", render_source = LIGHT_GLOW_RENDER_TARGET, blend_mode = BLEND_ADD)
		// The finish: light and shadow meet over a couple of pixels, where they used to meet on a tile's edge
		filters += filter(type = "blur", size = LIGHTING_SOFTEN_SIZE)
	// tg's three, from code/_onclick/hud/plane_master.dm: what glows and where space shows are cut out of the darkness
	filters += filter(type="alpha", render_source=EMISSIVE_RENDER_TARGET, flags=MASK_INVERSE)
	filters += filter(type="alpha", render_source=EMISSIVE_UNBLOCKABLE_RENDER_TARGET, flags=MASK_INVERSE)
	filters += filter(type="alpha", render_source=SPACE_UNLIT_MASK_RENDER_TARGET, flags=MASK_INVERSE)

// ---- The finish on what's lit: a soft halo round the brightest things on screen. The plates tgstation composes its screen from
// aren't in this codebase, so there's no finished picture to bloom; the floor and the game world are bloomed each on their own,
// before the lighting plane darkens them.

/proc/wants_scene_bloom(mob/mymob)
	return !mymob?.client?.prefs || mymob.client.prefs.graphics_quality() >= GRAPHICS_QUALITY_MEDIUM

/obj/screen/plane_master/floor/backdrop(mob/mymob)
	. = ..()
	if(wants_scene_bloom(mymob))
		filters += SCENE_BLOOM

/obj/screen/plane_master/game_world/backdrop(mob/mymob)
	. = ..()
	if(wants_scene_bloom(mymob))
		filters += SCENE_BLOOM

#undef LIGHT_GLOW_SIZE
