// The parts of the sky that move by themselves, and the round's choice of sky.
//
// A parallax layer (parallax.dm) belongs to one client, and all it does is slide as that client's eye moves. Anything that moves
// by itself is a /obj/screen/sky_art instead: one object for the whole server, held in the vis_contents of every client's layer of
// that kind. Its animation is started once and everyone sees the same thing at the same moment: stars twinkling, a nebula
// drifting, a comet crossing. The art is drawn by tools/sky_gen/sky_gen.py.

/obj/screen/sky_art
	icon = 'hippiestation/icons/effects/sky.dmi'
	blend_mode = BLEND_ADD
	plane = PLANE_SPACE_PARALLAX
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	/// How many times its sprite's size it's drawn
	var/scale = 1

/// Repeats the art round the middle copy. Two each way covers a view 30 tiles across with a shuttle's slide on top.
/obj/screen/sky_art/proc/tile(reach = 2)
	transform = matrix(scale, 0, 0, 0, scale, 0)
	var/list/tiles = list()
	for(var/x in -reach to reach)
		for(var/y in -reach to reach)
			if(x == 0 && y == 0)
				continue
			var/mutable_appearance/copy = mutable_appearance(icon, icon_state)
			copy.transform = matrix(1, 0, x * PARALLAX_TILE, 0, 1, y * PARALLAX_TILE)
			tiles += copy
	cut_overlays()
	add_overlay(tiles)

/// Slides the art one repeat along a heading (list(x, y), each -1, 0 or 1) every `time`, for good. The art repeats, so the loop has no seam.
/obj/screen/sky_art/proc/drift(list/heading, time)
	var/repeat = PARALLAX_TILE * scale
	transform = matrix(scale, 0, -heading[1] * repeat, 0, scale, -heading[2] * repeat)
	animate(src, transform = matrix(scale, 0, 0, 0, scale, 0), time = time, loop = -1)

/// Fades between full and faint and back every 2 * half, for good.
/obj/screen/sky_art/proc/twinkle(half)
	animate(src, alpha = 45, time = half, loop = -1, easing = SINE_EASING)
	animate(alpha = 255, time = half, easing = SINE_EASING)

/// Brightens and dims unevenly, for good: a quasar's core. The steps are uneven so the loop (22 seconds) doesn't show.
/obj/screen/sky_art/proc/flicker()
	animate(src, alpha = 255, time = 30, loop = -1, easing = SINE_EASING)
	animate(alpha = 170, time = 45, easing = SINE_EASING)
	animate(alpha = 235, time = 20, easing = SINE_EASING)
	animate(alpha = 140, time = 60, easing = SINE_EASING)
	animate(alpha = 215, time = 25, easing = SINE_EASING)
	animate(alpha = 160, time = 40, easing = SINE_EASING)

/// The one thing crossing the sky at the moment, if anything is. Its sprites point east.
/obj/screen/sky_art/flyby
	icon = 'hippiestation/icons/effects/sky_flyby.dmi'
	icon_state = "meteor"
	alpha = 0
	layer = 20

/// The sprite turned to a heading (degrees clockwise from east, as Turn() counts) and moved to a place.
/obj/screen/sky_art/flyby/proc/placed(heading, x, y)
	var/matrix/M = matrix()
	M.Turn(heading)
	M.Translate(x, y)
	return M

/// kind is an icon state of sky_flyby.dmi. forced_time is for tests: how long the crossing takes, instead of the kind's own pace.
/obj/screen/sky_art/flyby/proc/launch(kind, forced_time)
	icon_state = kind
	var/heading = rand(0, 359)
	var/along_x = cos(heading)
	var/along_y = -sin(heading)
	// the line it flies passes this far to one side of the middle of the screen
	var/miss = rand(-150, 150)
	var/mid_x = -along_y * miss
	var/mid_y = along_x * miss
	var/half_length
	var/time
	var/bright = 255
	switch(kind)
		if("meteor") //a short streak somewhere in view, gone in under a second
			var/along = rand(-180, 180)
			mid_x += along_x * along
			mid_y += along_y * along
			half_length = rand(90, 150)
			time = rand(5, 9)
		if("comet") //edge to edge, taking about a minute
			half_length = 470
			time = rand(450, 800)
			bright = 230
		else //a ship
			half_length = 470
			time = rand(350, 600)
			bright = 210
	if(forced_time)
		time = forced_time
	var/from_x = mid_x - along_x * half_length
	var/from_y = mid_y - along_y * half_length
	var/to_x = mid_x + along_x * half_length
	var/to_y = mid_y + along_y * half_length
	// In at the start and out at the end over a fifth of the way each, in one sequence: fading and moving are the same steps
	alpha = 0
	transform = placed(heading, from_x, from_y)
	animate(src, alpha = bright, transform = placed(heading, from_x + (to_x - from_x) * 0.2, from_y + (to_y - from_y) * 0.2), time = time * 0.2, flags = ANIMATION_END_NOW)
	animate(transform = placed(heading, from_x + (to_x - from_x) * 0.8, from_y + (to_y - from_y) * 0.8), time = time * 0.6)
	animate(alpha = 0, transform = placed(heading, to_x, to_y), time = time * 0.2)

/datum/controller/subsystem/parallax
	/// This round's sky (sky_themes.dm)
	var/datum/sky_theme/theme
	/// The shared art made so far, by name
	var/list/sky_art = list()
	var/obj/screen/sky_art/flyby/flyby
	var/next_flyby = 0
	/// Where the single things sit this round: name to list(x, y), pixels from the middle of the screen seen from the middle of the map
	var/list/body_places = list()
	/// Which part of each of the theme's nebula clouds is overhead this round: one list(x, y) in pixels for each
	var/list/nebula_shifts = list()
	/// The far things in this round's sky, whatever its theme: list(icon state of sky_deep.dmi, degrees turned, size, speed) each.
	/// Where each sits is body_places["deep1"] and on
	var/list/deep_sky = list()

//These are cached per client so needs to be done asap so people joining at roundstart do not miss these.
/datum/controller/subsystem/parallax/PreInit()
	. = ..()
	var/list/themes = list()
	for(var/path in subtypesof(/datum/sky_theme))
		var/datum/sky_theme/T = path
		themes[path] = initial(T.weight)
	var/picked = pickweight(themes)
	set_theme(new picked)

/datum/controller/subsystem/parallax/Initialize(timeofday)
	// The starlight for the theme PreInit() picked: the globals set_starlight() works on don't exist yet at PreInit
	apply_starlight()
	return ..()

/// Space lights hulls, windows and breaches in the sky's colour. Aurora Caelus and Nar'Sie fade back to this base (space.dm).
/// Space turfs lit after this take the colour as they light; the ones already lit are recoloured.
/datum/controller/subsystem/parallax/proc/apply_starlight()
	if(!GLOB.starlight_object)
		return //before the globals: Initialize() does it
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(set_base_starlight), theme.starlight || COLOR_STARLIGHT)

/// Changes the sky for everyone, there and then.
/datum/controller/subsystem/parallax/proc/set_theme(datum/sky_theme/new_theme)
	theme = new_theme
	random_layer = theme.asteroids ? /obj/screen/parallax_layer/random/asteroids : null
	apply_starlight()
	// The sun to one side, the other world and the galaxy well away from it and from each other
	var/sun_bearing = rand(0, 359)
	var/world_bearing = sun_bearing + rand(110, 180)
	var/galaxy_bearing = world_bearing + rand(70, 110)
	body_places = list(
		"sun" = list(cos(sun_bearing) * 170, sin(sun_bearing) * 170),
		"world" = list(cos(world_bearing) * 130, sin(world_bearing) * 130),
		"galaxy" = list(cos(galaxy_bearing) * 120, sin(galaxy_bearing) * 120))
	pick_deep_sky(list(sun_bearing, world_bearing, galaxy_bearing))
	nebula_shifts = list()
	var/half_repeat = PARALLAX_TILE * SKY_NEBULA_SCALE / 2
	for(var/cloud in theme.nebula)
		nebula_shifts += list(list(rand(-half_repeat, half_repeat), rand(-half_repeat, half_repeat)))
	for(var/name in sky_art)
		qdel(sky_art[name])
	sky_art = list()
	for(var/client/C as anything in GLOB.clients)
		if(C.mob?.hud_used)
			C.mob.hud_used.update_parallax_pref(C.mob) //the layers were made for the old theme: this makes them again

/// The round's far things: mostly one, sometimes two or none, each turned and sized its own way and set at a bearing clear of
/// the sun, the other world, the galaxy and each other, round an oval a little wider than it is tall.
/datum/controller/subsystem/parallax/proc/pick_deep_sky(list/taken)
	deep_sky = list()
	// kind = list(smallest, largest) size, in hundredths: the hourglass and the remnant are wide, so they're kept smaller
	var/static/list/sizes = list("nebula_ring" = list(70, 95), "nebula_bipolar" = list(55, 80), "nebula_remnant" = list(55, 80), "quasar" = list(75, 100))
	var/list/kinds = sizes.Copy()
	for(var/index in 1 to pick(0, 1, 1, 1, 2, 2))
		var/kind = pick_n_take(kinds)
		var/bearing
		var/best_gap = -1
		for(var/attempt in 1 to 24)
			var/maybe = rand(0, 359)
			var/gap = 180
			for(var/other in taken)
				gap = min(gap, abs(((maybe - other) % 360 + 540) % 360 - 180))
			if(gap > best_gap)
				best_gap = gap
				bearing = maybe
			if(gap >= 60)
				break
		taken += bearing
		var/reach = rand(75, 100) / 100
		var/list/size = sizes[kind]
		body_places["deep[index]"] = list(cos(bearing) * 210 * reach, sin(bearing) * 160 * reach)
		deep_sky += list(list(kind, rand(0, 359), rand(size[1], size[2]) / 100, rand(25, 35) / 100))

/// The art of one far thing, in a list for a layer's vis_contents: its sprite, and for a quasar its jets and its core. The
/// jets run and the core flickers unless it's for Low graphics.
/datum/controller/subsystem/parallax/proc/deep_art(index, moving)
	var/list/far_thing = deep_sky[index]
	var/kind = far_thing[1]
	var/list/states = list(kind)
	if(kind == "quasar")
		states += moving ? "quasar_jets" : "quasar_jets_still"
		states += "quasar_core"
	var/matrix/turned = matrix(far_thing[3], 0, 0, 0, far_thing[3], 0)
	turned.Turn(far_thing[2])
	. = list()
	for(var/state in states)
		var/name = "deep [index] [state][moving ? "" : " still"]"
		var/obj/screen/sky_art/A = sky_art[name]
		if(!A)
			A = new
			A.icon = 'hippiestation/icons/effects/sky_deep.dmi'
			A.icon_state = state
			A.layer = 5.5 + index * 0.01 + length(.) * 0.001
			A.transform = turned
			if(moving && state == "quasar_core")
				A.flicker()
			sky_art[name] = A
		. += A

/// One of the theme's nebula clouds, in its colour: the one that drifts, or the one that stays put for Low graphics.
/datum/controller/subsystem/parallax/proc/nebula_art(index, moving)
	var/name = "nebula [index][moving ? "" : " still"]"
	var/obj/screen/sky_art/A = sky_art[name]
	if(A)
		return A
	var/list/cloud = theme.nebula[index]
	A = new
	A.icon = 'hippiestation/icons/effects/sky_nebula.dmi'
	A.icon_state = cloud[1]
	A.color = cloud[2]
	A.alpha = cloud[3]
	A.layer = 3 + index * 0.01
	A.scale = SKY_NEBULA_SCALE
	A.tile()
	if(moving && cloud[5])
		A.drift(cloud[6], cloud[5] MINUTES)
	sky_art[name] = A
	return A

/// One group of the stars that twinkle: fading in and out, or steady for Low graphics.
/datum/controller/subsystem/parallax/proc/twinkle_art(group, moving)
	var/name = "twinkle [group][moving ? "" : " still"]"
	var/obj/screen/sky_art/A = sky_art[name]
	if(A)
		return A
	A = new
	A.icon_state = "twinkle[group]"
	A.color = theme.star_tint
	A.layer = 7.1
	A.tile()
	if(moving)
		A.twinkle(9 + group * 4) //each group at its own pace, so they never all fade together
	else
		A.alpha = 200
	sky_art[name] = A
	return A

/datum/controller/subsystem/parallax/proc/flyby_art()
	if(!flyby)
		flyby = new
		next_flyby = world.time + rand(SKY_FLYBY_MIN, SKY_FLYBY_MAX) / 2
	return flyby

/// Sends something across the sky. Nothing to send it across until a client with High graphics has looked up.
/datum/controller/subsystem/parallax/proc/launch_flyby(kind)
	next_flyby = world.time + rand(SKY_FLYBY_MIN, SKY_FLYBY_MAX)
	if(!flyby)
		return
	flyby.launch(kind || pickweight(list("meteor" = 7, "comet" = 1, "ship" = 2)))

/datum/controller/subsystem/parallax/fire(resumed = 0)
	if(!resumed && flyby && world.time >= next_flyby)
		launch_flyby()
	..()
