// The space backdrop: the layers of sky a client sees where space shows, and how they slide as the eye moves.
// This is tg's code/_onclick/hud/parallax.dm rewritten (that file is out of the dme). What's different:
//  - the layers come from the round's sky theme (sky_themes.dm) instead of a fixed five
//  - a layer says which Parallax preference and which Graphics quality it needs, where there used to be a count of layers
//  - the sky slides for as long as the eye glides to the next tile (tgstation's pixel_w glide), so the near layers don't step
//  - a layer can repeat at any distance (nebulae are drawn at double size) and can carry shared art that moves by itself (sky.dm)
//  - the whole sky turns with the real sun (SSsun), about the middle of the screen, so the painted sun is where the solars point
//  - in a shuttle's flight the stars stretch into streaks along the heading, the near ones most
//  - a layer can sit turned at an angle of its own (a galaxy's band, at the theme's angle)
// Each layer sits in a holder at the middle of the screen and slides by the holder's transform (slide_to()). BYOND turns each of a
// parent's vis_contents about the child's own middle, so with the slide in pixel_w/pixel_z the turned sky came apart: every layer
// spun where it was. A holder's middle is the screen's, so the sky turns as one picture. (Found on the Paradise port, 2026-11-27.)

/// The sky's turn is animated a quarter at a time (one animate step each), and held at a whole quarter while a shuttle flies
#define SKY_TURN_STEP 90
/// Most steps one turn animation queues. The sun's normal speeds need 25-97 for 12 hours; an admin's fast sun gets this many, and
/// SSparallax.sun_moved() starts it again before they run out
#define SKY_TURN_MAX_STEPS 100
/// How long the sky takes to swing to the nearest quarter turn as a shuttle sets off, and back to its turn after
#define SKY_SNAP_TIME 30
#define SKY_UNSNAP_TIME 30

// How far away each layer is, as the pixels it slides for each tile the eye moves (a tile is 32 pixels). The station's own floor
// slides 32: anything near that sits just outside the hull. Everything beyond the station (stars, clouds, the band, the far things,
// the sun, the other world) is as good as infinitely far and holds still; Lavaland, below, slides a little. The dust is the near
// thing that slides past fast, with a sparser dust between. Under a pixel a step the offsets add up as fractions and the layer
// moves a pixel at a time, gliding with the eye like the rest.
// The far sky held still since 2026-11-28 (Keegan): at 0.06 a tile it never read as parallax, only as the whole sky jumping a
// game pixel every 12-17 tiles and back again flying the other way (filmed: sky_shots.dm `walk`, tools/sky_gen/v2/sky_motion.py).
#define SKY_DEPTH_FAR 0
#define SKY_DEPTH_PLANET 0.15
#define SKY_DEPTH_NEAR_DUST 24
#define SKY_DEPTH_MID_DUST 9
/// Pixels from the middle of the screen Lavaland rests at, on the far side from the sun (it faces the sun, sky_bodies)
#define SKY_PLANET_REST 210

/// Degrees the sky has turned by `time` (clockwise, as Turn() counts), so the painted sun sits at SSsun's azimuth; 0 before the
/// sun is up. Everyone's sky is at the same angle.
/proc/sky_turn_angle(time = world.time)
	var/list/line = SSparallax.turn_line
	var/list/sun = SSparallax.body_places["sun"]
	if(!line || !sun)
		return 0
	return line[1] + line[3] * (time - line[2]) - (90 - arctan(sun[1], sun[2]))

/// The painted sun's bearing on screen at `time`, degrees clockwise from north as SSsun.azimuth counts; null with no sun painted
/proc/sky_sun_bearing(time = world.time)
	var/list/sun = SSparallax.body_places["sun"]
	if(!sun)
		return null
	return SIMPLIFY_DEGREES(90 - arctan(sun[1], sun[2]) + sky_turn_angle(time))

/// How the sky's turn is animated: list(degrees a step, deciseconds a step, steps), enough steps to cover 12 hours but never more
/// than SKY_TURN_MAX_STEPS (a fast sun: sun_moved() starts the turn again before they run out)
/proc/sky_turn_plan()
	var/list/line = SSparallax.turn_line
	var/rate = line ? line[3] : 0
	if(!rate)
		return list(0, 0, 0)
	var/step_time = SKY_TURN_STEP / abs(rate)
	return list(SKY_TURN_STEP * SIGN(rate), step_time, min(ceil(12 HOURS / step_time) + 1, SKY_TURN_MAX_STEPS))

/// The whole quarter turn nearest the sky's angle now: where a shuttle's flight holds the sky
/proc/sky_snap_angle()
	return round(sky_turn_angle(), SKY_TURN_STEP)

/// Sets a sky home turning from where the sky should be by now, or swinging there over `ease`: the player's own (turn_sky()) and a
/// camera picture's (map_view.dm) alike
/proc/sky_turn_home(obj/screen/parallax_home/home, ease = 0)
	var/angle = sky_turn_angle(world.time + ease)
	if(ease)
		animate(home, transform = sky_turned(angle), time = ease, easing = SINE_EASING)
	else
		animate(home, transform = sky_turned(angle), time = 0, flags = ANIMATION_END_NOW)
	var/list/plan = sky_turn_plan()
	for(var/step in 1 to plan[3])
		animate(transform = sky_turned(angle + step * plan[1]), time = plan[2])

/proc/sky_turned(angle)
	var/matrix/M = matrix()
	M.Turn(angle)
	return M

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
	/// While a shuttle flies, the angle the sky is held at (a whole quarter turn, so the flight runs along the art's repeat); null otherwise
	var/parallax_snapped

/// The angle this client's sky is at, or is on its way to
/client/proc/parallax_angle()
	return isnull(parallax_snapped) ? sky_turn_angle() : parallax_snapped

/**
  * What a client has on screen for the sky. Every layer is in its vis_contents instead of on the screen itself: a screen object
  * ignores pixel_w and pixel_z (seen on 516: every planet sat dead centre), something drawn through vis_contents doesn't, and
  * those are what a layer's slide animates. tgstation's arrangement.
  * The sky turns by turning this. Its icon draws nothing (no state of that name) but is a tile's size, so it turns about the
  * middle of a tile: the middle of the screen. Its vis_contents are the layers' holders (/obj/screen/parallax_holder), each a tile
  * the same size in the same place, so each is turned about that same middle. A layer slides in this turned frame.
  */
/obj/screen/parallax_home
	icon = 'hippiestation/icons/effects/sky.dmi'
	icon_state = null
	blend_mode = BLEND_ADD
	plane = PLANE_SPACE_PARALLAX
	screen_loc = "CENTER-7,CENTER-7"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = APPEARANCE_UI & ~PIXEL_SCALE // its turn is the whole sky's: filtered, not nearest-neighbour
	/// A camera picture's sky (map_view.dm): the angle it's held at while the camera's shuttle flies, null while it turns with the sun.
	/// A player's own sky keeps this on the client (parallax_snapped).
	var/view_snap

/obj/screen/parallax_home/Destroy()
	if(src in SSparallax.view_homes) // a camera picture's: its layers are its own (a player's are the client's, parallax_layers_cached)
		SSparallax.view_homes -= src
		var/list/layers = held_layers()
		vis_contents.Cut()
		QDEL_LIST(layers)
	vis_contents.Cut()
	return ..()

/// A client's sky layers and their holders point at each other, which BYOND never frees by itself: they go with the client
/client/Destroy()
	for(var/layer in parallax_animate_timers)
		deltimer(parallax_animate_timers[layer])
	parallax_animate_timers = null
	parallax_layers = null
	QDEL_NULL(parallax_home)
	QDEL_LIST(parallax_layers_cached)
	return ..()

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
		// a sparser dust between the near dust and the stars, so the depth runs on instead of jumping from far to near
		for(var/obj/screen/parallax_layer/dust/near_dust in C.parallax_layers_cached)
			C.parallax_layers_cached += new /obj/screen/parallax_layer/dust/mid
			break
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
	var/list/holders = list()
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		holders += L.holder
	C.parallax_home.vis_contents = holders
	C.screen |= C.parallax_home
	if(isnull(C.parallax_snapped))
		turn_sky(C)
	else
		animate(C.parallax_home, transform = sky_turned(C.parallax_snapped), time = 0, flags = ANIMATION_END_NOW)
	// Kept layers stop where they are, and forgetting the heading has the next update_parallax() send them off again if
	// this eye is in flight too (a new body, a new hud: the old flight's loop would run on forever otherwise)
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		if(L.flight_heading)
			L.come_to_rest(TRUE)
	C.parallax_movedir = 0
	track_parallax_mover(C)
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


/// Has the thing carrying the client's eye update its sky when it moves, now rather than at SSparallax's next pass. A mob
/// moved straight after it logs in (a new ghost sent somewhere, an observer jumping) otherwise keeps the sky of where it
/// spawned: a ghost made in the arrivals shuttle in transit kept flying, and the far bodies stayed laid out for there.
/datum/hud/proc/track_parallax_mover(client/C)
	var/atom/movable/A = C.eye
	if(!istype(A))
		return
	while(ismovable(A.loc))
		A = A.loc
	if(A == C.movingmob)
		return
	if(C.movingmob)
		C.movingmob.client_mobs_in_contents -= C.mob
		UNSETEMPTY(C.movingmob.client_mobs_in_contents)
	LAZYINITLIST(A.client_mobs_in_contents)
	A.client_mobs_in_contents |= C.mob
	C.movingmob = A

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

/// Sets the client's sky turning from where it should be by now, or swinging there over `ease` (after a shuttle flight).
/// One animate step a quarter turn, as many as 12 hours take (sky_turn_plan()), either way round as the sun goes. SSparallax.sun_moved()
/// starts it again whenever the sun's line changes.
/datum/hud/proc/turn_sky(client/C, ease = 0)
	var/obj/screen/parallax_home/home = C?.parallax_home
	if(!home)
		return
	sky_turn_home(home, ease)

// This sets which way the current shuttle is moving (returns true if the shuttle has stopped moving so the caller can append their animation)
// The wind-up and the loop are tgstation's: each layer gets up to its own speed, then loops from a timer of its own. On top of that the
// stars stretch into streaks as they speed up (flight_matrix()), and the sky swings to the nearest quarter turn for the flight, so the
// loop runs along the art's repeat and has no seam. On arrival every layer slows from where it is to a whole repeat and the sky swings
// back to its turn.
/datum/hud/proc/set_parallax_movedir(new_parallax_movedir, skip_windups)
	. = FALSE
	var/client/C = mymob.client
	new_parallax_movedir = new_parallax_movedir || 0 //an area's can be null, the client's starts at 0: the same thing
	if(new_parallax_movedir == C.parallax_movedir)
		if(!new_parallax_movedir && !isnull(C.parallax_snapped)) //layers made again after the flight ended: the sky still turns on
			C.parallax_snapped = null
			turn_sky(C, SKY_UNSNAP_TIME)
		return
	var/animatedir = new_parallax_movedir || C.parallax_movedir

	for(var/layer in C.parallax_animate_timers)
		deltimer(C.parallax_animate_timers[layer])
	C.parallax_animate_timers = list()

	if(new_parallax_movedir && isnull(C.parallax_snapped))
		C.parallax_snapped = sky_snap_angle()
		if(C.parallax_home)
			animate(C.parallax_home, transform = sky_turned(C.parallax_snapped), time = skip_windups ? 0 : SKY_SNAP_TIME, easing = SINE_EASING)
	// The heading in the sky's own frame: the sky is turned clockwise by the held angle, turn() counts the other way
	var/heading = animatedir
	if(!isnull(C.parallax_snapped))
		heading = turn(animatedir, C.parallax_snapped % 360)

	var/longest = 0
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		if(!L.flies())
			continue
		if(!new_parallax_movedir)
			longest = max(longest, L.come_to_rest(skip_windups))
			continue
		var/windup = L.launch(heading, skip_windups)
		longest = max(longest, windup)
		if(windup)
			C.parallax_animate_timers[L] = addtimer(CALLBACK(src, PROC_REF(update_parallax_motionblur), C, L), windup, TIMER_CLIENT_TIME|TIMER_STOPPABLE)

	if(!new_parallax_movedir && !isnull(C.parallax_snapped))
		C.parallax_snapped = null
		turn_sky(C, skip_windups ? 0 : SKY_UNSNAP_TIME)
	C.dont_animate_parallax = world.time + min(longest, PARALLAX_LOOP_TIME)
	C.parallax_movedir = new_parallax_movedir

/// A layer up to speed starts its endless loop
/datum/hud/proc/update_parallax_motionblur(client/C, obj/screen/parallax_layer/L)
	if(!C || QDELETED(L))
		return
	LAZYREMOVE(C.parallax_animate_timers, L)
	if(L.flight_heading)
		L.cruise()

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

	// The layers slide in the turned sky's frame: a step east still slides everything west on screen
	var/matrix/unturn = sky_turned(-C.parallax_angle())

	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		L.update_status(mymob)
		if (L.view_sized != C.view)
			L.update_o(C.view)

		// how far it moves on screen
		var/screen_x
		var/screen_y
		var/new_x
		var/new_y
		if(L.absolute)
			if(force) // laid out from where it rests: that part turns with the sky, the eye's parallax doesn't
				var/list/rest = L.sky_rest()
				screen_x = L.place_x(posobj.x) - rest[1]
				screen_y = L.place_y(posobj.y) - rest[2]
				new_x = rest[1] + unturn.a * screen_x + unturn.b * screen_y
				new_y = rest[2] + unturn.d * screen_x + unturn.e * screen_y
			else
				screen_x = L.place_x(posobj.x) - L.place_x(posobj.x - offset_x)
				screen_y = L.place_y(posobj.y) - L.place_y(posobj.y - offset_y)
		else
			screen_x = -offset_x * L.speed
			screen_y = -offset_y * L.speed
		if(isnull(new_x))
			new_x = L.offset_x + unturn.a * screen_x + unturn.b * screen_y
			new_y = L.offset_y + unturn.d * screen_x + unturn.e * screen_y
		if(!L.absolute)
			// The art repeats every period: go back a whole one where it can't be seen, before the slide starts.
			// A layer at an angle of its own repeats along its own turned axes.
			var/half = L.period / 2
			var/across = new_x
			var/along = new_y
			if(L.angle)
				var/matrix/own = sky_turned(-L.angle)
				across = own.a * new_x + own.b * new_y
				along = own.d * new_x + own.e * new_y
			var/wrap_u = across > half ? -L.period : (across < -half ? L.period : 0)
			var/wrap_v = along > half ? -L.period : (along < -half ? L.period : 0)
			if(wrap_u || wrap_v)
				var/wrap_x = wrap_u
				var/wrap_y = wrap_v
				if(L.angle)
					var/matrix/back = sky_turned(L.angle)
					wrap_x = back.a * wrap_u + back.b * wrap_v
					wrap_y = back.d * wrap_u + back.e * wrap_v
				new_x += wrap_x
				new_y += wrap_y
				L.slide_to(round(L.offset_x + wrap_x, 1), round(L.offset_y + wrap_y, 1))

		L.offset_x = new_x
		L.offset_y = new_y
		// Any move that shows glides with the eye, even the one pixel a far layer moves now and then
		var/drawn_x = round(new_x, 1)
		var/drawn_y = round(new_y, 1)
		if(glide && (drawn_x != L.drawn_x || drawn_y != L.drawn_y))
			L.slide_to(drawn_x, drawn_y, glide_time)
		else
			L.slide_to(drawn_x, drawn_y)

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

/// Degrees (clockwise) the theme's galaxy band sits turned by: its nebula entry with the "band" state, or a band layer's set_angle()
/datum/sky_theme/var/band_angle = 0

/obj/screen/parallax_layer
	icon = 'hippiestation/icons/effects/sky.dmi'
	/// Pixels it slides for each tile the eye moves: the nearer, the more
	var/speed = 1
	/// How fast it streams past in a shuttle's flight (as speed used to be: 1 is a repeat in PARALLAX_LOOP_TIME). The walk's speed
	/// is a distance; a flight is a different scale, and the far stars still have to move
	var/flight_speed = 1
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
	/// How many times longer it's drawn along a shuttle's heading at full speed: stars into streaks, the near ones longest
	var/streak = 1
	/// Degrees it sits turned by (clockwise), on top of the sky's own turn: a galaxy's band at the theme's angle (set_angle())
	var/angle = 0
	/// The heading of the flight it's looping in (in the sky's frame), 0 at rest
	var/flight_heading = 0
	/// REALTIMEOFDAY its wind-up started and how long that takes, and when its loop started (0 while winding up)
	var/flight_start = 0
	var/flight_windup = 0
	var/cruise_start = 0
	blend_mode = BLEND_ADD
	plane = PLANE_SPACE_PARALLAX
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	// Without RESET_TRANSFORM (which every screen object has): a layer turns with the sky holding it. Without PIXEL_SCALE: turned at
	// an odd angle, nearest-pixel drawing stair-stepped the planets' rims and showed lines at the repeats' seams
	appearance_flags = APPEARANCE_UI & ~(RESET_TRANSFORM | PIXEL_SCALE)
	/// Carries the layer at the middle of the screen and slides it by its transform, so the sky's turn swings every layer as one
	var/obj/screen/parallax_holder/holder
	/// Pixels the holder has the layer slid by
	var/drawn_x = 0
	var/drawn_y = 0


/obj/screen/parallax_layer/Initialize(mapload, view)
	. = ..()
	holder = new
	holder.held = src
	holder.layer = layer
	holder.vis_contents += src
	if (!view)
		view = world.view
	update_o(view)

/obj/screen/parallax_layer/Destroy()
	QDEL_NULL(holder)
	return ..()

/// Slides the layer to x, y pixels from the middle of the screen (in the turned sky's frame), over `time` if it's given
/obj/screen/parallax_layer/proc/slide_to(x, y, time)
	drawn_x = x
	drawn_y = y
	if(time)
		animate(holder, transform = matrix(1, 0, x, 0, 1, y), time = time)
	else
		holder.transform = matrix(1, 0, x, 0, 1, y)

/// Holds one parallax layer in parallax_home's vis_contents (or a camera picture's sky): its transform is the layer's slide. It's a
/// tile like the home, at the same place, so the home's turn goes about the same middle for every holder.
/obj/screen/parallax_holder
	icon = 'hippiestation/icons/effects/sky.dmi'
	icon_state = null
	blend_mode = BLEND_ADD
	plane = PLANE_SPACE_PARALLAX
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = NO_CLIENT_COLOR // turns with the home: no RESET_TRANSFORM
	/// The layer it holds
	var/obj/screen/parallax_layer/held

/obj/screen/parallax_holder/Destroy()
	vis_contents.Cut()
	held = null
	return ..()

/// Tiles the layer's own icon over the view. A layer with no icon state of its own shows shared art instead (set_quality).
/obj/screen/parallax_layer/proc/update_o(view)
	if (!view)
		view = world.view
	view_sized = view
	if(!icon_state)
		return

	var/list/viewscales = getviewsize(view)
	// Out to the view's corners whichever way the sky is turned, and one more each way: a shuttle in flight slides the layer a whole repeat
	var/reach = sqrt(viewscales[1] ** 2 + viewscales[2] ** 2) * world.icon_size / 2
	var/count = ceil(reach / period) + 1
	var/list/new_overlays = new
	for(var/x in -count to count)
		for(var/y in -count to count)
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

/// Shared art for a layer's vis_contents, made to turn, stretch and loop with the layer: as a screen object it would ignore the
/// layer's transform (RESET_TRANSFORM), and so would stand still in a flight and not turn with the sky.
/obj/screen/parallax_layer/proc/carry(list/art)
	for(var/obj/screen/A as anything in art)
		A.appearance_flags &= ~RESET_TRANSFORM
	return art

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
	return PARALLAX_LOOP_TIME / flight_speed * (period / PARALLAX_TILE)

/// Where an absolute layer rests in the sky, seen from where its place_x() and place_y() put it at the middle of the screen: that
/// part of its place turns with the sky, the rest (the eye's parallax) doesn't.
/obj/screen/parallax_layer/proc/sky_rest()
	return list(place_x(world.maxx / 2), place_y(world.maxy / 2))

/// Sits turned by `new_angle` degrees on top of the sky's own turn
/obj/screen/parallax_layer/proc/set_angle(new_angle)
	angle = new_angle
	transform = rest_transform()

/// The layer's transform when nothing moves it: turned by its own angle, if it has one
/obj/screen/parallax_layer/proc/rest_transform()
	return angle ? sky_turned(angle) : matrix()

/// Whether it streams past in a shuttle's flight. Single things stay put (they're gone in transit anyway), and so does a layer at an
/// angle of its own: its repeat isn't along the heading, and something that far off wouldn't move.
/obj/screen/parallax_layer/proc/flies()
	return !absolute && !angle

/// The layer stretched `stretch` times along a heading and moved `shift` pixels back along it. Stretched or not, a shift of a whole
/// (stretched) repeat looks the same as none, so a loop between the two has no seam.
/obj/screen/parallax_layer/proc/flight_matrix(heading, shift, stretch)
	switch(heading)
		if(NORTH)
			return matrix(1, 0, 0, 0, stretch, shift)
		if(SOUTH)
			return matrix(1, 0, 0, 0, stretch, -shift)
		if(EAST)
			return matrix(stretch, 0, shift, 0, 1, 0)
		if(WEST)
			return matrix(stretch, 0, -shift, 0, 1, 0)
	return matrix()

/// One loop at full speed: a stretched repeat, at the speed the wind-up ended on (an eased-in wind-up ends at twice its average)
/obj/screen/parallax_layer/proc/cruise_time()
	return loop_time() * streak / 2

/// Starts it winding up along `heading` (the sky's frame), stretching as it goes. Returns how long until it should cruise(), 0 if it
/// already does (skip_windup: the arrivals shuttle, already under way when you see it).
/obj/screen/parallax_layer/proc/launch(heading, skip_windup)
	flight_heading = heading
	flight_start = REALTIMEOFDAY
	cruise_start = 0
	if(skip_windup)
		flight_windup = 0
		cruise()
		return 0
	flight_windup = loop_time()
	transform = flight_matrix(heading, period, 1)
	animate(src, transform = flight_matrix(heading, 0, streak), time = flight_windup, easing = QUAD_EASING | EASE_IN, flags = ANIMATION_END_NOW)
	// one loop queued behind it, so a late timer doesn't leave it standing
	animate(transform = flight_matrix(heading, period * streak, streak), time = 0)
	animate(transform = flight_matrix(heading, 0, streak), time = cruise_time())
	return flight_windup

/// Loops at full speed until it comes to rest
/obj/screen/parallax_layer/proc/cruise()
	cruise_start = REALTIMEOFDAY
	animate(src, transform = flight_matrix(flight_heading, period * streak, streak), time = 0, loop = -1, flags = ANIMATION_END_NOW)
	animate(transform = flight_matrix(flight_heading, 0, streak), time = cruise_time())

/**
  * Slows it from where it is now (worked out from when its loop started: the server can't see the client's picture) to a stop on a
  * whole repeat, shrinking back as it goes, in PARALLAX_LOOP_TIME. It goes on at the speed it had, as near as a whole repeat allows,
  * where tgstation's jumped back to the start of the loop. Returns how long it takes.
  */
/obj/screen/parallax_layer/proc/come_to_rest(instantly)
	var/heading = flight_heading
	flight_heading = 0
	if(!heading || instantly)
		animate(src, transform = matrix(), time = 0, flags = ANIMATION_END_NOW)
		return 0
	var/now = REALTIMEOFDAY
	var/shift
	var/stretch
	var/speed_now // pixels a decisecond
	if(cruise_start)
		var/loop = cruise_time()
		var/into = MODULUS(now - cruise_start, loop)
		shift = period * streak * (1 - into / loop)
		stretch = streak
		speed_now = period * streak / loop
	else
		var/through = clamp((now - flight_start) / max(flight_windup, 1), 0, 1)
		shift = period * (1 - through ** 2)
		stretch = 1 + (streak - 1) * through ** 2
		speed_now = 2 * period * through / max(flight_windup, 1)
	// Easing out starts at twice the average speed: this far keeps the speed it had
	var/wanted = speed_now * PARALLAX_LOOP_TIME / 2
	var/repeats = round((shift - wanted) / period)
	var/far = shift - repeats * period
	var/near = far - period
	var/travel = (near >= 0 && abs(near - wanted) < abs(far - wanted)) ? near : far
	transform = flight_matrix(heading, shift, stretch)
	animate(src, transform = flight_matrix(heading, shift - travel, 1), time = PARALLAX_LOOP_TIME, easing = QUAD_EASING | EASE_OUT, flags = ANIMATION_END_NOW)
	animate(transform = matrix(), time = 0)
	return PARALLAX_LOOP_TIME

// ---- Stars, far to near

/obj/screen/parallax_layer/stars
	icon_state = "stars_far"
	speed = SKY_DEPTH_FAR
	flight_speed = 0.45
	streak = 2.5
	layer = 4
	/// Its stars' state in sky.dmi, drawn by shared art (SSparallax.star_art()). The layer's own icon_state is cleared for it, so
	/// update_o() tiles nothing of its own.
	var/art_state

/obj/screen/parallax_layer/stars/Initialize(mapload, view)
	art_state = icon_state
	icon_state = null
	return ..()

/obj/screen/parallax_layer/stars/set_quality(quality)
	vis_contents = carry(list(SSparallax.star_art(art_state, layer)))

/obj/screen/parallax_layer/stars/deep
	icon_state = "stars_deep"
	speed = SKY_DEPTH_FAR
	flight_speed = 0.2
	streak = 1.6
	// Drawn after the clouds and the band (3.0x), not under them at 2: BYOND drew the 2x clouds nearest-neighbour, in hard 2x2
	// blocks, whenever these unscaled stars came first on the plane (tools/keybind_check/sky_shots.dm `batch`, 2026-11-28).
	// All of them add their light, so the order doesn't change the picture.
	layer = 3.5
	detail = PARALLAX_MED

/obj/screen/parallax_layer/stars/mid
	icon_state = "stars_mid"
	speed = SKY_DEPTH_FAR
	flight_speed = 0.9
	streak = 4
	layer = 5
	detail = PARALLAX_MED

/// The few bright ones. Some of them twinkle: three groups, each a shared layer that fades in and out at its own pace.
/obj/screen/parallax_layer/stars/near
	icon_state = "stars_near"
	speed = SKY_DEPTH_FAR
	flight_speed = 1.6
	streak = 6
	layer = 7
	detail = PARALLAX_MED

/obj/screen/parallax_layer/stars/near/set_quality(quality)
	var/list/art = list(SSparallax.star_art(art_state, layer))
	for(var/group in 1 to SKY_TWINKLE_GROUPS)
		art += SSparallax.twinkle_art(group, quality >= GRAPHICS_QUALITY_MEDIUM)
	vis_contents = carry(art)

// ---- Nebulae: greyscale clouds from sky_nebula.dmi in the theme's colours, drawn at double size

/obj/screen/parallax_layer/nebula
	icon_state = null
	period = PARALLAX_TILE * SKY_NEBULA_SCALE
	speed = SKY_DEPTH_FAR
	flight_speed = 0.45
	layer = 3
	detail = PARALLAX_HIGH
	/// Which of the theme's clouds this is
	var/index = 1

/// cloud is one of the theme's nebula entries: list(state, colour, alpha, flight speed). The clouds hold still with the rest of the
/// far sky (SKY_DEPTH_FAR), and a shuttle's flight streams them past at their own speeds.
/obj/screen/parallax_layer/nebula/proc/setup(new_index, list/cloud)
	index = new_index
	flight_speed = cloud[4]
	layer = initial(layer) + index * 0.01
	holder.layer = layer
	// Which part of the cloud is overhead changes from round to round, the same for everyone
	var/list/shift = SSparallax.nebula_shifts[index]
	offset_x = shift[1]
	offset_y = shift[2]
	if(index == 1) //the Medium preference gets the theme's main cloud, and so its colour
		detail = PARALLAX_MED
	if(cloud[1] == "band") //a galaxy's band runs along x in its art: the theme turns it
		set_angle(SSparallax.theme.band_angle)
		// Its shift is (along the band, across it): turn it with the band, so the across part lands on the band's normal
		var/matrix/own = sky_turned(angle)
		offset_x = own.a * shift[1] + own.b * shift[2]
		offset_y = own.d * shift[1] + own.e * shift[2]

/obj/screen/parallax_layer/nebula/set_quality(quality)
	vis_contents = carry(list(SSparallax.nebula_art(index)))

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

/// Its sprite in sky_bodies.dmi, drawn by shared art (SSparallax.body_art()). What icon_state the layer was given (a theme's world
/// or galaxy) moves here when it goes on screen, and the layer itself draws nothing.
/obj/screen/parallax_layer/body/var/art_state

/obj/screen/parallax_layer/body/proc/body_art_list()
	if(icon_state)
		art_state = icon_state
		icon_state = null
	return art_state ? list(SSparallax.body_art(art_state, layer)) : list()

/obj/screen/parallax_layer/body/set_quality(quality)
	vis_contents = carry(body_art_list())

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
	speed = SKY_DEPTH_PLANET
	layer = 30
	detail = PARALLAX_MED

/// Off to the side opposite the sun, so a window on that side frames it whatever the eye does (it barely slides), and it's
/// still in the middle of that side when the eye is over SSparallax.planet_x_offset (the station's middle, as tg had it)
/obj/screen/parallax_layer/body/planet/place_x(eye_x)
	return planet_rest()[1] - (eye_x - SSparallax.planet_x_offset) * speed

/obj/screen/parallax_layer/body/planet/place_y(eye_y)
	return planet_rest()[2] - (eye_y - SSparallax.planet_y_offset) * speed

/obj/screen/parallax_layer/body/planet/proc/planet_rest()
	var/list/sun = SSparallax.body_places["sun"]
	if(!sun || (!sun[1] && !sun[2]))
		return list(0, -SKY_PLANET_REST)
	var/away = arctan(-sun[1], -sun[2])
	return list(cos(away) * SKY_PLANET_REST, sin(away) * SKY_PLANET_REST)

/// The lit side toward the sun: the art is backlit from the upper left (SKY_PLANET_BAKE_ANGLE, tools/sky_gen/v2/planets.py), so
/// it turns by that less the sun's bearing. It turns with the sky after that, so the lit side stays on the sun.
/obj/screen/parallax_layer/body/planet/Initialize(mapload, view)
	. = ..()
	face_sun(SKY_PLANET_BAKE_ANGLE)
	SSparallax.planet_layers += src // players' and camera pictures' alike, for the art Lavaland carries (sky_weather.dm)

/obj/screen/parallax_layer/body/planet/Destroy()
	SSparallax.planet_layers -= src
	return ..()

/// Turns a body so its lit side, baked lit from bake_angle (degrees counter-clockwise from screen east), faces the sun
/obj/screen/parallax_layer/body/proc/face_sun(bake_angle = 0)
	var/list/sun = SSparallax.body_places["sun"]
	if(sun && (sun[1] || sun[2]))
		set_angle(bake_angle - arctan(sun[1], sun[2]))

/obj/screen/parallax_layer/body/planet/update_status(mob/M)
	var/turf/T = get_turf(M)
	invisibility = (T && is_station_level(T.z)) ? 0 : INVISIBILITY_ABSTRACT

/// Another world of this system, further off. The theme says which.
/obj/screen/parallax_layer/body/world
	speed = SKY_DEPTH_FAR
	layer = 10
	place = "world"

/obj/screen/parallax_layer/body/world/Initialize(mapload, view)
	. = ..()
	face_sun()

/obj/screen/parallax_layer/body/sun
	icon_state = "sun"
	blend_mode = BLEND_ADD
	speed = SKY_DEPTH_FAR
	layer = 8
	place = "sun"

/obj/screen/parallax_layer/body/galaxy
	icon = 'hippiestation/icons/effects/sky_bodies.dmi' //tools/sky_gen/v2/bodies.py's galaxies
	icon_state = "galaxy"
	speed = SKY_DEPTH_FAR
	layer = 6
	place = "galaxy"

/// Something far beyond this system: a nebula or a quasar (SSparallax.deep_sky). Its art is shared, turned and sized for the round.
/obj/screen/parallax_layer/body/deep
	icon_state = null
	blend_mode = BLEND_ADD
	speed = SKY_DEPTH_FAR
	layer = 5.5
	/// Which of the round's far things it is
	var/index = 1

/obj/screen/parallax_layer/body/deep/proc/setup(new_index)
	index = new_index
	place = "deep[index]"
	layer = initial(layer) + index * 0.01
	holder.layer = layer

/obj/screen/parallax_layer/body/deep/set_quality(quality)
	vis_contents = carry(SSparallax.deep_art(index, quality >= GRAPHICS_QUALITY_MEDIUM))

// ---- Near things

/// Specks of dust close by: they slide past fast, which is what gives a spacewalk its speed
/obj/screen/parallax_layer/dust
	icon_state = "dust"
	speed = SKY_DEPTH_NEAR_DUST
	flight_speed = 5
	streak = 6
	layer = 40
	alpha = 170
	detail = PARALLAX_HIGH
	quality = GRAPHICS_QUALITY_HIGH

/// Sparser dust further out, between the near dust and the stars: the same grit, fainter and from another part of its repeat
/obj/screen/parallax_layer/dust/mid
	speed = SKY_DEPTH_MID_DUST
	flight_speed = 2.5
	streak = 4
	layer = 39
	offset_x = 173
	offset_y = -131

/obj/screen/parallax_layer/dust/mid/Initialize(mapload, view)
	. = ..()
	alpha = 95

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
	vis_contents = carry(list(SSparallax.flyby_art()))

/obj/screen/parallax_layer/flybys/update_status(mob/M)
	var/turf/T = get_turf(M)
	invisibility = (T && is_reserved_level(T.z)) ? INVISIBILITY_ABSTRACT : 0

/obj/screen/parallax_layer/random
	icon = 'icons/effects/parallax.dmi'
	blend_mode = BLEND_OVERLAY
	speed = 6
	flight_speed = 3
	layer = 35
	detail = PARALLAX_HIGH

/obj/screen/parallax_layer/random/space_gas
	icon_state = "space_gas"

/obj/screen/parallax_layer/random/space_gas/Initialize(mapload, view)
	. = ..()
	src.add_atom_colour(SSparallax.random_parallax_color, ADMIN_COLOUR_PRIORITY)

/obj/screen/parallax_layer/random/asteroids
	icon = 'hippiestation/icons/effects/sky_asteroids.dmi' //tools/sky_gen/v2/asteroids.py
	icon_state = "asteroids_0"

/// The field tiles, so it can't turn to the sun like a body: the sheet has it lit from 16 headings, and it takes the nearest
/obj/screen/parallax_layer/random/asteroids/Initialize(mapload, view)
	. = ..()
	var/list/sun = SSparallax.body_places["sun"]
	if(sun && (sun[1] || sun[2]))
		icon_state = "asteroids_[round((arctan(sun[1], sun[2]) + 360) / 22.5, 1) % 16]" //nearest heading
		update_o(view_sized) // the repeats were made from asteroids_0 when ..() tiled it
