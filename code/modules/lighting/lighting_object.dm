/atom/movable/lighting_object
	name          = ""

	anchored      = TRUE

	icon             = LIGHTING_ICON
	icon_state       = "transparent"
	color            = null //we manually set color in init instead
	plane            = LIGHTING_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	layer            = LIGHTING_LAYER
	invisibility     = INVISIBILITY_LIGHTING

	var/needs_update = FALSE
	var/turf/myturf

/atom/movable/lighting_object/Initialize(mapload)
	. = ..()
	verbs.Cut()
	//We avoid setting this in the base as if we do then the parent atom handling will add_atom_color it and that
	//is totally unsuitable for this object, as we are always changing it's colour manually
	color = LIGHTING_BASE_MATRIX

	myturf = loc
	if (myturf.lighting_object)
		qdel(myturf.lighting_object, force = TRUE)
	myturf.lighting_object = src
	myturf.luminosity = 0
	myturf.lighting_engine_push()

	for(var/turf/open/space/S in RANGE_TURFS(1, src)) //RANGE_TURFS is in code\__HELPERS\game.dm
		// hippie -- next to our (never space) turf, update_starlight() can only switch it on; if it's already on there's
		// nothing to do. Space touching several lit turfs was being redone for each (~75k calls at init)
		if(!GLOB.starlight[S])
			S.update_starlight()

	needs_update = TRUE
	SSlighting.objects_queue += src

/atom/movable/lighting_object/Destroy(var/force)
	if (force)
		SSlighting.objects_queue -= src
		if (loc != myturf)
			var/turf/oldturf = get_turf(myturf)
			var/turf/newturf = get_turf(loc)
			stack_trace("A lighting object was qdeleted with a different loc then it is suppose to have ([COORD(oldturf)] -> [COORD(newturf)])")
		if (isturf(myturf))
			myturf.lighting_object = null
			myturf.luminosity = 1
			myturf.lighting_engine_push()
		myturf = null

		return ..()

	else
		return QDEL_HINT_LETMELIVE

/atom/movable/lighting_object/proc/update()
	if (loc != myturf)
		if (loc)
			var/turf/oldturf = get_turf(myturf)
			var/turf/newturf = get_turf(loc)
			warning("A lighting object realised it's loc had changed in update() ([myturf]\[[myturf ? myturf.type : "null"]]([COORD(oldturf)]) -> [loc]\[[ loc ? loc.type : "null"]]([COORD(newturf)]))!")

		qdel(src, TRUE)
		return

	// To the future coder who sees this and thinks
	// "Why didn't he just use a loop?"
	// Well my man, it's because the loop performed like shit.
	// And there's no way to improve it because
	// without a loop you can make the list all at once which is the fastest you're gonna get.
	// Oh it's also shorter line wise.
	// Including with these comments.

	var/static/datum/lighting_corner/dummy/dummy_lighting_corner = new

	var/datum/lighting_corner/cr = myturf.lighting_corner_SW || dummy_lighting_corner
	var/datum/lighting_corner/cg = myturf.lighting_corner_SE || dummy_lighting_corner
	var/datum/lighting_corner/cb = myturf.lighting_corner_NW || dummy_lighting_corner
	var/datum/lighting_corner/ca = myturf.lighting_corner_NE || dummy_lighting_corner

	draw(cr.cache_r, cr.cache_g, cr.cache_b, cg.cache_r, cg.cache_g, cg.cache_b, cb.cache_r, cb.cache_g, cb.cache_b, ca.cache_r, ca.cache_g, ca.cache_b, 		max(cr.largest_color_luminosity, cg.largest_color_luminosity, cb.largest_color_luminosity, ca.largest_color_luminosity))

/// What update() draws, from the southwest, southeast, northwest and northeast corners' colours and the brightest channel of
/// them all. The lighting engine (lighting_engine.dm) hands it these straight.
/// hippie -- with the engine on, native_draw() makes these same writes itself for most lighting objects, only those that change
/// (native_drawn): a change to what this draws goes there too, and in drawn_from() (tools/lighting_engine/src/engine.rs)
/atom/movable/lighting_object/proc/draw(rr, rg, rb, gr, gg, gb, br, bg, bb, ar, ag, ab, max)
	if (loc != myturf)
		if (loc)
			var/turf/oldturf = get_turf(myturf)
			var/turf/newturf = get_turf(loc)
			warning("A lighting object realised it's loc had changed in update() ([myturf]\[[myturf ? myturf.type : "null"]]([COORD(oldturf)]) -> [loc]\[[ loc ? loc.type : "null"]]([COORD(newturf)]))!")

		qdel(src, TRUE)
		return

	// hippie start -- lighting v2 (lighting_v2.dm): a wall, a closed door or anything else opaque is lit as one face, in its
	// brightest corner's colour, instead of a gradient running diagonally across it from the lit side to the dark one
	if(GLOB.lighting_v2 && myturf?.has_opaque_atom)
		var/face_r = rr
		var/face_g = rg
		var/face_b = rb
		var/face = rr + rg + rb
		if(gr + gg + gb > face)
			face = gr + gg + gb
			face_r = gr
			face_g = gg
			face_b = gb
		if(br + bg + bb > face)
			face = br + bg + bb
			face_r = br
			face_g = bg
			face_b = bb
		if(ar + ag + ab > face)
			face_r = ar
			face_g = ag
			face_b = ab
		rr = face_r
		gr = face_r
		br = face_r
		ar = face_r
		rg = face_g
		gg = face_g
		bg = face_g
		ag = face_g
		rb = face_b
		gb = face_b
		bb = face_b
		ab = face_b
	// hippie end

	#if LIGHTING_SOFT_THRESHOLD != 0
	var/set_luminosity = max > LIGHTING_SOFT_THRESHOLD
	#else
	// Because of floating points™?, it won't even be a flat 0.
	// This number is mostly arbitrary.
	var/set_luminosity = max > 1e-6
	#endif

	if((rr & gr & br & ar) && (rg + gg + bg + ag + rb + gb + bb + ab == 8))
	//anything that passes the first case is very likely to pass the second, and addition is a little faster in this case
		icon_state = "transparent"
		color = null
	else if(!set_luminosity)
		icon_state = "dark"
		color = null
	else
		icon_state = null
		color = list(
			rr, rg, rb, 00,
			gr, gg, gb, 00,
			br, bg, bb, 00,
			ar, ag, ab, 00,
			00, 00, 00, 01
		)

	if(luminosity != set_luminosity) // hippie -- setting it costs as much as the colour, even to what it is; reading it doesn't
		luminosity = set_luminosity

// Variety of overrides so the overlays don't get affected by weird things.

/atom/movable/lighting_object/ex_act(severity)
	return 0

/atom/movable/lighting_object/singularity_act()
	return

/atom/movable/lighting_object/singularity_pull()
	return

/atom/movable/lighting_object/blob_act()
	return

/atom/movable/lighting_object/onTransitZ()
	return

// Override here to prevent things accidentally moving around overlays.
/atom/movable/lighting_object/forceMove(atom/destination, var/no_tp=FALSE, var/harderforce = FALSE)
	if(harderforce)
		. = ..()
