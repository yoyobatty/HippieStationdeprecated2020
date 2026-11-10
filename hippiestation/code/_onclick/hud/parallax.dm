// The space backdrop: the layers of sky a client sees where space shows, and how they slide as the eye moves.
// This is tg's code/_onclick/hud/parallax.dm rewritten (that file is out of the dme). What's different:
//  - the layers come from the round's sky theme (sky_themes.dm) instead of a fixed five
//  - a layer says which Parallax preference and which Graphics quality it needs, where there used to be a count of layers
//  - the sky slides for as long as the eye glides to the next tile (tgstation's pixel_w glide), so the near layers don't step
//  - a layer can repeat at any distance (nebulae are drawn at double size) and can carry shared art that moves by itself (sky.dm)

/client
	var/list/parallax_layers
	var/list/parallax_layers_cached
	var/atom/movable/movingmob
	var/turf/previous_turf
	var/dont_animate_parallax //world.time of when we can state animate()ing parallax again
	var/last_parallax_shift //world.time of last update
	var/parallax_throttle = 0 //ds between updates
	var/parallax_movedir = 0
	/// The Parallax preference in use: a layer shows if its detail is this or lower in detail (PARALLAX_INSANE the most)
	var/parallax_detail = PARALLAX_HIGH
	/// Layer to the timer that starts its loop once it's up to speed (shuttles in flight)
	var/list/parallax_animate_timers
	/// The sky theme the cached layers were made for
	var/datum/sky_theme/parallax_theme
	/// The one sky object on this client's screen: the layers are drawn through it
	var/obj/screen/parallax_home/parallax_home

/**
  * What a client has on screen for the sky. Every layer is in its vis_contents instead of on the screen itself: a screen object
  * ignores pixel_w and pixel_z (seen on 516: every planet sat dead centre), something drawn through vis_contents doesn't, and
  * those are what a layer's slide animates. tgstation's arrangement.
  */
/obj/screen/parallax_home
	icon = null
	blend_mode = BLEND_ADD
	plane = PLANE_SPACE_PARALLAX
	screen_loc = "CENTER-7,CENTER-7"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/datum/hud/proc/create_parallax(mob/viewmob)
	var/mob/screenmob = viewmob || mymob
	var/client/C = screenmob.client
	if (!apply_parallax_pref(viewmob)) //don't want shit computers to crash when specing someone with insane parallax, so use the viewer's pref
		return

	var/datum/sky_theme/theme = SSparallax.theme
	if(!length(C.parallax_layers_cached) || C.parallax_theme != theme)
		if(length(C.parallax_layers_cached))
			C.parallax_home?.vis_contents.Cut()
			QDEL_LIST(C.parallax_layers_cached)
		C.parallax_layers_cached = theme.build_layers()
		C.parallax_theme = theme

	var/quality = C.prefs ? C.prefs.graphics_quality() : GRAPHICS_QUALITY_HIGH
	C.parallax_layers = list()
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers_cached)
		if(C.parallax_detail > L.detail || quality < L.quality)
			continue
		L.set_quality(quality)
		C.parallax_layers += L

	if(!C.parallax_home)
		C.parallax_home = new
	C.parallax_home.vis_contents = C.parallax_layers
	C.screen |= C.parallax_home
	var/obj/screen/plane_master/PM = screenmob.hud_used.plane_masters["[PLANE_SPACE]"]
	if(screenmob != mymob)
		C.screen -= locate(/obj/screen/plane_master/parallax_white) in C.screen
		C.screen += PM
	PM.color = list(
		0, 0, 0, 0,
		0, 0, 0, 0,
		0, 0, 0, 0,
		1, 1, 1, 1,
		0, 0, 0, 0
		)


/datum/hud/proc/remove_parallax(mob/viewmob)
	var/mob/screenmob = viewmob || mymob
	var/client/C = screenmob.client
	C.screen -= C.parallax_home
	var/obj/screen/plane_master/PM = screenmob.hud_used.plane_masters["[PLANE_SPACE]"]
	if(screenmob != mymob)
		C.screen -= locate(/obj/screen/plane_master/parallax_white) in C.screen
		C.screen += PM
	PM.color = initial(PM.color)
	C.parallax_layers = null

/datum/hud/proc/apply_parallax_pref(mob/viewmob)
	var/mob/screenmob = viewmob || mymob
	var/client/C = screenmob.client
	var/pref = C.prefs?.parallax
	if(isnull(pref))
		pref = PARALLAX_HIGH
	if(pref == PARALLAX_DISABLE)
		return FALSE
	C.parallax_detail = pref
	switch(pref)
		if(PARALLAX_INSANE)
			C.parallax_throttle = FALSE
		if(PARALLAX_MED)
			C.parallax_throttle = PARALLAX_DELAY_MED
		if(PARALLAX_LOW)
			C.parallax_throttle = PARALLAX_DELAY_LOW
		else
			C.parallax_throttle = PARALLAX_DELAY_DEFAULT
	return TRUE

/datum/hud/proc/update_parallax_pref(mob/viewmob)
	remove_parallax(viewmob)
	create_parallax(viewmob)
	// New layers start in the middle of the screen: forgetting the last turf has update_parallax() put every one where it goes
	// (the planet, the nebulae's shift for the round) instead of waiting for the eye to move
	if(mymob.client)
		mymob.client.previous_turf = null
	update_parallax()

// This sets which way the current shuttle is moving (returns true if the shuttle has stopped moving so the caller can append their animation)
// The wind-up and the loop are tgstation's: each layer gets up to its own speed, then loops from a timer of its own.
/datum/hud/proc/set_parallax_movedir(new_parallax_movedir, skip_windups)
	. = FALSE
	var/client/C = mymob.client
	if(new_parallax_movedir == C.parallax_movedir)
		return
	var/animatedir = new_parallax_movedir || C.parallax_movedir

	for(var/layer in C.parallax_animate_timers)
		deltimer(C.parallax_animate_timers[layer])
	C.parallax_animate_timers = list()

	var/longest = 0
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		var/matrix/away = L.one_repeat_away(animatedir)
		var/loop_time = L.loop_time()
		if(!new_parallax_movedir) //stopping: every layer comes to rest at the same moment
			loop_time = PARALLAX_LOOP_TIME
		longest = max(longest, loop_time)

		if(skip_windups)
			update_parallax_motionblur(C, L, new_parallax_movedir, away)
			continue

		L.transform = away
		animate(L, transform = matrix(), time = loop_time, easing = QUAD_EASING | (new_parallax_movedir ? EASE_IN : EASE_OUT), flags = ANIMATION_END_NOW)
		if(!new_parallax_movedir)
			continue
		//queue up another animate so lag doesn't create a shutter
		animate(transform = away, time = 0)
		animate(transform = matrix(), time = loop_time / 2)
		C.parallax_animate_timers[L] = addtimer(CALLBACK(src, PROC_REF(update_parallax_motionblur), C, L, new_parallax_movedir, away), loop_time, TIMER_CLIENT_TIME|TIMER_STOPPABLE)

	C.dont_animate_parallax = world.time + min(longest, PARALLAX_LOOP_TIME)
	C.parallax_movedir = new_parallax_movedir

/datum/hud/proc/update_parallax_motionblur(client/C, obj/screen/parallax_layer/L, new_parallax_movedir, matrix/away)
	if(!C || QDELETED(L))
		return
	LAZYREMOVE(C.parallax_animate_timers, L)
	if(!new_parallax_movedir)
		animate(L, transform = matrix(), time = 0, flags = ANIMATION_END_NOW)
		return
	// The wind-up eased in, so it ended at twice its average speed: the loop keeps that speed by taking half the time
	animate(L, transform = away, time = 0, loop = -1, flags = ANIMATION_END_NOW)
	animate(transform = matrix(), time = L.loop_time() / 2)

/datum/hud/proc/update_parallax()
	var/client/C = mymob.client
	if(!C) // hippie -- an observer looking through a client-less mob's hud (a bot crew member)
		return
	var/turf/posobj = get_turf(C.eye)
	if(!posobj)
		return
	var/area/areaobj = posobj.loc

	// Update the movement direction of the parallax if necessary (for shuttles)
	set_parallax_movedir(areaobj.parallax_movedir, FALSE)

	var/force
	if(!C.previous_turf || (C.previous_turf.z != posobj.z))
		C.previous_turf = posobj
		force = TRUE

	if (!force && world.time < C.last_parallax_shift+C.parallax_throttle)
		return

	//Doing it this way prevents parallax layers from "jumping" when you change Z-Levels.
	var/offset_x = posobj.x - C.previous_turf.x
	var/offset_y = posobj.y - C.previous_turf.y

	if(!offset_x && !offset_y && !force)
		return

	C.previous_turf = posobj
	C.last_parallax_shift = world.time

	// The sky slides for as long as the eye takes to glide to its new tile, so the two move as one
	var/atom/movable/eye = C.eye
	var/glide_size = istype(eye) ? eye.glide_size : mymob.glide_size
	var/glide_time = glide_size ? round(world.icon_size / glide_size * world.tick_lag, world.tick_lag) : 0
	var/largest_change = max(abs(offset_x), abs(offset_y))
	// Not for a jump (a teleport, a camera switch), not in a moving shuttle (the layers are looping), not while they wind down
	var/glide = glide_time && !force && !areaobj.parallax_movedir && C.dont_animate_parallax <= world.time && largest_change <= (glide_time / world.tick_lag) + 1

	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		L.update_status(mymob)
		if (L.view_sized != C.view)
			L.update_o(C.view)

		var/new_x
		var/new_y
		if(L.absolute)
			new_x = L.place_x(posobj.x)
			new_y = L.place_y(posobj.y)
		else
			new_x = L.offset_x - offset_x * L.speed
			new_y = L.offset_y - offset_y * L.speed
			// The art repeats every period: go back a whole one where it can't be seen, before the slide starts
			var/half = L.period / 2
			var/wrap_x = new_x > half ? -L.period : (new_x < -half ? L.period : 0)
			var/wrap_y = new_y > half ? -L.period : (new_y < -half ? L.period : 0)
			if(wrap_x || wrap_y)
				new_x += wrap_x
				new_y += wrap_y
				L.pixel_w = round(L.offset_x + wrap_x, 1)
				L.pixel_z = round(L.offset_y + wrap_y, 1)

		L.offset_x = new_x
		L.offset_y = new_y
		// Less than a pixel isn't worth an animation
		if(glide && largest_change * L.speed > 1)
			animate(L, pixel_w = round(new_x, 1), pixel_z = round(new_y, 1), time = glide_time)
		else
			L.pixel_w = round(new_x, 1)
			L.pixel_z = round(new_y, 1)

/atom/movable/proc/update_parallax_contents()
	if(length(client_mobs_in_contents))
		for(var/thing in client_mobs_in_contents)
			var/mob/M = thing
			if(M && M.client && M.hud_used && length(M.client.parallax_layers))
				M.hud_used.update_parallax()

/mob/proc/update_parallax_teleport()	//used for arrivals shuttle
	if(client && client.eye && hud_used && length(client.parallax_layers))
		var/area/areaobj = get_area(client.eye)
		hud_used.set_parallax_movedir(areaobj.parallax_movedir, TRUE)

/obj/screen/parallax_layer
	icon = 'hippiestation/icons/effects/sky.dmi'
	/// Pixels it slides for each tile the eye moves: the nearer, the more
	var/speed = 1
	var/offset_x = 0
	var/offset_y = 0
	var/view_sized
	/// Sits at one place in the sky (see place_x) instead of repeating across it
	var/absolute = FALSE
	/// How far apart its art repeats on screen, in pixels
	var/period = PARALLAX_TILE
	/// The lowest Parallax preference that still shows it. PARALLAX_LOW: always, short of Disabled
	var/detail = PARALLAX_LOW
	/// The lowest Graphics quality that shows it
	var/quality = GRAPHICS_QUALITY_LOW
	blend_mode = BLEND_ADD
	plane = PLANE_SPACE_PARALLAX
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT


/obj/screen/parallax_layer/Initialize(mapload, view)
	. = ..()
	if (!view)
		view = world.view
	update_o(view)

/// Tiles the layer's own icon over the view. A layer with no icon state of its own shows shared art instead (set_quality).
/obj/screen/parallax_layer/proc/update_o(view)
	if (!view)
		view = world.view
	view_sized = view
	if(!icon_state)
		return

	var/list/viewscales = getviewsize(view)
	// one more each way than the view needs: a shuttle in flight slides the layer a whole repeat
	var/countx = ceil((viewscales[1] * world.icon_size / 2) / period) + 1
	var/county = ceil((viewscales[2] * world.icon_size / 2) / period) + 1
	var/list/new_overlays = new
	for(var/x in -countx to countx)
		for(var/y in -county to county)
			if(x == 0 && y == 0)
				continue
			var/mutable_appearance/texture_overlay = mutable_appearance(icon, icon_state)
			texture_overlay.transform = matrix(1, 0, x*period, 0, 1, y*period)
			new_overlays += texture_overlay
	cut_overlays()
	add_overlay(new_overlays)

/obj/screen/parallax_layer/proc/update_status(mob/M)
	return

/// The client's Graphics quality, each time the layer goes on screen: which shared art it carries (moving or still).
/obj/screen/parallax_layer/proc/set_quality(quality)
	return

/// Where an absolute layer sits, in pixels from the middle of the screen, with the eye at this map x.
/obj/screen/parallax_layer/proc/place_x(eye_x)
	return -(eye_x - SSparallax.planet_x_offset) * speed

/obj/screen/parallax_layer/proc/place_y(eye_y)
	return -(eye_y - SSparallax.planet_y_offset) * speed

/// The layer one repeat of its art back along a shuttle's heading: where a loop of the flight starts from.
/obj/screen/parallax_layer/proc/one_repeat_away(dir)
	switch(dir)
		if(NORTH)
			return matrix(1, 0, 0, 0, 1, period)
		if(SOUTH)
			return matrix(1, 0, 0, 0, 1, -period)
		if(EAST)
			return matrix(1, 0, period, 0, 1, 0)
		if(WEST)
			return matrix(1, 0, -period, 0, 1, 0)
	return matrix()

/// How long one repeat takes to pass in a shuttle at full speed.
/obj/screen/parallax_layer/proc/loop_time()
	return PARALLAX_LOOP_TIME / speed * (period / PARALLAX_TILE)

// ---- Stars, far to near

/obj/screen/parallax_layer/stars
	icon_state = "stars_far"
	speed = 0.6
	layer = 4

/obj/screen/parallax_layer/stars/deep
	icon_state = "stars_deep"
	speed = 0.3
	layer = 2
	detail = PARALLAX_MED

/obj/screen/parallax_layer/stars/mid
	icon_state = "stars_mid"
	speed = 1
	layer = 5
	detail = PARALLAX_MED

/// The few bright ones. Some of them twinkle: three groups, each a shared layer that fades in and out at its own pace.
/obj/screen/parallax_layer/stars/near
	icon_state = "stars_near"
	speed = 1.6
	layer = 7
	detail = PARALLAX_MED

/obj/screen/parallax_layer/stars/near/set_quality(quality)
	var/list/groups = list()
	for(var/group in 1 to SKY_TWINKLE_GROUPS)
		groups += SSparallax.twinkle_art(group, quality >= GRAPHICS_QUALITY_MEDIUM)
	vis_contents = groups

// ---- Nebulae: greyscale clouds from sky_nebula.dmi in the theme's colours, drawn at double size

/obj/screen/parallax_layer/nebula
	icon_state = null
	period = PARALLAX_TILE * SKY_NEBULA_SCALE
	speed = 0.45
	layer = 3
	detail = PARALLAX_HIGH
	/// Which of the theme's clouds this is
	var/index = 1

/// cloud is one of the theme's nebula entries: list(state, colour, alpha, speed, minutes to drift one repeat, "x,y" heading)
/obj/screen/parallax_layer/nebula/proc/setup(new_index, list/cloud)
	index = new_index
	speed = cloud[4]
	layer = initial(layer) + index * 0.01
	// Which part of the cloud is overhead changes from round to round, the same for everyone
	var/list/shift = SSparallax.nebula_shifts[index]
	offset_x = shift[1]
	offset_y = shift[2]
	if(index == 1) //the Medium preference gets the theme's main cloud, and so its colour
		detail = PARALLAX_MED

/obj/screen/parallax_layer/nebula/set_quality(quality)
	vis_contents = list(SSparallax.nebula_art(index, quality >= GRAPHICS_QUALITY_MEDIUM))

// ---- Single things: the planet below, another world, the sun, a galaxy. Each sits at one place in the sky.

/obj/screen/parallax_layer/body
	icon = 'hippiestation/icons/effects/sky_bodies.dmi'
	blend_mode = BLEND_OVERLAY
	absolute = TRUE
	detail = PARALLAX_HIGH
	/// Which of SSparallax.body_places it sits at: pixels from the middle of the screen, seen from the middle of the map
	var/place

/obj/screen/parallax_layer/body/update_o(view)
	view_sized = view || world.view //one of it: nothing to tile

/obj/screen/parallax_layer/body/place_x(eye_x)
	var/list/shift = SSparallax.body_places[place]
	return shift[1] - (eye_x - world.maxx / 2) * speed

/obj/screen/parallax_layer/body/place_y(eye_y)
	var/list/shift = SSparallax.body_places[place]
	return shift[2] - (eye_y - world.maxy / 2) * speed

/// Seen from the station and from open space, not from a shuttle in flight
/obj/screen/parallax_layer/body/update_status(mob/M)
	var/turf/T = get_turf(M)
	invisibility = (T && is_reserved_level(T.z)) ? INVISIBILITY_ABSTRACT : 0

/// The planet the station orbits: Lavaland. Sits where tg's planet did (SSparallax.planet_x_offset), whatever the theme.
/obj/screen/parallax_layer/body/planet
	icon_state = "planet_lava"
	speed = 3
	layer = 30
	detail = PARALLAX_MED

/obj/screen/parallax_layer/body/planet/place_x(eye_x)
	return -(eye_x - SSparallax.planet_x_offset) * speed

/obj/screen/parallax_layer/body/planet/place_y(eye_y)
	return -(eye_y - SSparallax.planet_y_offset) * speed

/obj/screen/parallax_layer/body/planet/update_status(mob/M)
	var/turf/T = get_turf(M)
	invisibility = (T && is_station_level(T.z)) ? 0 : INVISIBILITY_ABSTRACT

/// Another world of this system, further off. The theme says which.
/obj/screen/parallax_layer/body/world
	speed = 1.2
	layer = 10
	place = "world"

/obj/screen/parallax_layer/body/sun
	icon_state = "sun"
	blend_mode = BLEND_ADD
	speed = 0.4
	layer = 8
	place = "sun"

/obj/screen/parallax_layer/body/galaxy
	icon = 'icons/effects/parallax.dmi'
	icon_state = "galaxy"
	speed = 0.5
	layer = 6
	place = "galaxy"

// ---- Near things

/// Specks of dust close by: they slide past fast, which is what gives a spacewalk its speed
/obj/screen/parallax_layer/dust
	icon_state = "dust"
	speed = 5
	layer = 40
	alpha = 170
	detail = PARALLAX_HIGH
	quality = GRAPHICS_QUALITY_HIGH

/// Comets, shooting stars and far-off ships cross this one (SSparallax.launch_flyby). Everyone's shows the same shared object.
/obj/screen/parallax_layer/flybys
	icon_state = null
	speed = 0.8
	layer = 20
	absolute = TRUE //held to the middle of the screen: a fly-by's path is laid out round it, so everyone gets it in view
	detail = PARALLAX_HIGH
	quality = GRAPHICS_QUALITY_HIGH

/obj/screen/parallax_layer/flybys/place_x(eye_x)
	return 0

/obj/screen/parallax_layer/flybys/place_y(eye_y)
	return 0

/obj/screen/parallax_layer/flybys/set_quality(quality)
	vis_contents = list(SSparallax.flyby_art())

/obj/screen/parallax_layer/flybys/update_status(mob/M)
	var/turf/T = get_turf(M)
	invisibility = (T && is_reserved_level(T.z)) ? INVISIBILITY_ABSTRACT : 0

/obj/screen/parallax_layer/random
	icon = 'icons/effects/parallax.dmi'
	blend_mode = BLEND_OVERLAY
	speed = 3
	layer = 35
	detail = PARALLAX_HIGH

/obj/screen/parallax_layer/random/space_gas
	icon_state = "space_gas"

/obj/screen/parallax_layer/random/space_gas/Initialize(mapload, view)
	. = ..()
	src.add_atom_colour(SSparallax.random_parallax_color, ADMIN_COLOUR_PRIORITY)

/obj/screen/parallax_layer/random/asteroids
	icon_state = "asteroids"
