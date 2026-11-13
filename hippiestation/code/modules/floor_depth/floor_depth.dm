/*
 * Floor depth: where a floor tile came off, the plating shows a step below the floor round it.
 *
 * Floor tiles are a raised floor over the plating. A hole's plating, with whatever lies flat on it or runs under the floor there
 * (pipes, cables, disposals, blood), moves to its own plane under the floor plane. So do pictures of what's under each tile next
 * to a hole: the plating carrying on, the hidden pipes and cables there, in the tile's shade. That plane is drawn as it always
 * was, so clicks land where things really are, and a second plane on top draws the holes again with depth, cut to their shape:
 *  - a dark fill, which is what shows where the far rim is a wall (walls go down to the plating);
 *  - the plane, a little smaller round the middle of the screen, so the plating slides under the near rims as the camera moves
 *    and the far side of each hole shows what's under the tile beside it (holes near the edge of the screen look deepest, like
 *    looking down into them from the middle);
 * and a third plane adds a soft shadow from the rims.
 * All of it is drawn by the client from relays (screen objects showing another plane), so the server does nothing per frame.
 * Mobs and items stay at floor height: nothing jumps when someone steps into a hole.
 * Players can turn it off in the Display preferences (FLOOR_DEPTH_DISABLED).
 */

/turf
	/// Plating that lost its tile this round: drawn a step lower than the floor (floor_depth.dm)
	var/floor_sunken = FALSE
	/// A tile beside a hole: copies of what's hidden under it, in its vis_contents on the depth plane, with the plating and
	/// the tile's shade in its underlays (floor_depth.dm). An empty list when nothing's hidden there
	var/list/floor_under

/turf/open/floor/plating
	/// Plating, rather than ground: rock, sand, snow and the like under a floor were never a step below it
	var/can_sink = TRUE

/turf/open/floor/plating/asteroid
	can_sink = FALSE
/turf/open/floor/plating/ashplanet
	can_sink = FALSE
/turf/open/floor/plating/beach
	can_sink = FALSE
/turf/open/floor/plating/dirt
	can_sink = FALSE
/turf/open/floor/plating/ice
	can_sink = FALSE
/turf/open/floor/plating/ironsand
	can_sink = FALSE
/turf/open/floor/plating/snowed
	can_sink = FALSE
/turf/open/floor/plating/lavaland_baseturf
	can_sink = FALSE
/turf/open/floor/plating/foam
	can_sink = FALSE

/// Off: no new holes sink, and players' screens don't draw the depth planes (an admin's switch through View Variables, and the
/// cost bench's A/B). Off by default (2026-11-11). Turned on mid-round, a player's screen picks it up when their HUD is next set up
GLOBAL_VAR_INIT(floor_depth_on, FALSE)
/// How many holes and tiles showing what's under them there are: none, and turf changes needn't look round for them
GLOBAL_VAR_INIT(floor_depth_holes, 0)
GLOBAL_VAR_INIT(floor_depth_unders, 0)

/// A hole's shape, on the mask plane
GLOBAL_DATUM_INIT(floor_depth_mask_square, /mutable_appearance, mutable_appearance('icons/effects/alphacolors.dmi', "", TURF_LAYER, FLOOR_DEPTH_MASK_PLANE))
/// The plating under a tile
GLOBAL_DATUM_INIT(floor_depth_under_plating, /mutable_appearance, make_floor_depth_under_plating())
/// The tile's shade over what's under it
GLOBAL_DATUM_INIT(floor_depth_under_shade, /mutable_appearance, make_floor_depth_under_shade())

/proc/make_floor_depth_under_plating()
	var/turf/open/floor/plating/P = /turf/open/floor/plating
	return mutable_appearance(initial(P.icon), initial(P.icon_state), TURF_LAYER, FLOOR_DEPTH_PLANE)

/proc/make_floor_depth_under_shade()
	var/mutable_appearance/shade = mutable_appearance('icons/effects/alphacolors.dmi', "", WIRE_TERMINAL_LAYER + 0.01, FLOOR_DEPTH_PLANE)
	shade.color = "#000000"
	shade.alpha = 110
	return shade

/atom/movable
	/// The plane this was on before it went down into a hole's plating, to go back to when it leaves (floor_depth.dm)
	var/floor_depth_from = 0

/// Whether this goes down with the plating in a hole: what's under the floor, and what lies flat on it (not machines)
/atom/movable/proc/floor_depth_sinks()
	return FALSE

/obj/floor_depth_sinks()
	return level == 1 || (plane == FLOOR_PLANE && !ismachinery(src)) || istype(src, /obj/effect/decal/cleanable)

/atom/movable/proc/floor_depth_sink()
	if(plane == FLOOR_DEPTH_PLANE)
		return
	floor_depth_from = plane
	plane = FLOOR_DEPTH_PLANE

/atom/movable/proc/floor_depth_rise()
	if(plane == FLOOR_DEPTH_PLANE)
		plane = floor_depth_from || initial(plane)
	floor_depth_from = 0

/// After a turf change: plating that just lost its tile sinks, with what's on it
/turf/open/floor/plating/AfterChange(flags, oldType)
	if(GLOB.floor_depth_on && can_sink && ispath(oldType, /turf/open/floor) && !ispath(oldType, /turf/open/floor/plating))
		var/turf/open/floor/old_floor = oldType
		if(initial(old_floor.floor_tile))
			floor_sunken = TRUE
			plane = FLOOR_DEPTH_PLANE
			underlays += GLOB.floor_depth_mask_square
			GLOB.floor_depth_holes++
	. = ..() // levelupdate() in here shows the pipes and cables, which look at floor_sunken
	if(floor_sunken)
		for(var/atom/movable/AM as anything in src)
			if(AM.floor_depth_sinks())
				AM.floor_depth_sink()

/// Any turf change: the tiles round it may have a hole beside them now, or no longer. They're looked at a moment later, all
/// at once: a blast spreading outwards would otherwise build each ring's pictures just before blowing that ring away too
/turf/AfterChange(flags, oldType)
	. = ..()
	if(GLOB.floor_depth_holes || GLOB.floor_depth_unders)
		var/list/dirty = GLOB.floor_depth_dirty
		if(!dirty[src]) // a keyed lookup, not "in" (a walk of the list); TRUE (rebuild) is kept
			dirty[src] = FALSE
		for(var/dir in GLOB.alldirs)
			var/turf/T = get_step(src, dir)
			if(T && !dirty[T])
				dirty[T] = FALSE
		floor_depth_queue_flush()

/// Turfs to look at again: turf = TRUE to rebuild its pictures whatever (something hidden under it went)
GLOBAL_LIST_EMPTY(floor_depth_dirty)
GLOBAL_VAR_INIT(floor_depth_flush_queued, FALSE)

/proc/floor_depth_queue_flush()
	if(GLOB.floor_depth_flush_queued)
		return
	GLOB.floor_depth_flush_queued = TRUE
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(floor_depth_flush)), 1)

/proc/floor_depth_flush()
	GLOB.floor_depth_flush_queued = FALSE
	var/list/dirty = GLOB.floor_depth_dirty
	GLOB.floor_depth_dirty = list()
	for(var/turf/T as anything in dirty)
		T.floor_depth_refresh(dirty[T])

/// Shows what's under this tile on the depth plane when there's a hole beside it, and stops when there isn't. Left alone when
/// that hasn't changed, unless rebuild (something hidden under it went)
/turf/proc/floor_depth_refresh(rebuild = FALSE)
	var/show = FALSE
	if(intact && !floor_sunken && isfloorturf(src))
		for(var/dir in GLOB.alldirs)
			var/turf/T = get_step(src, dir)
			if(T?.floor_sunken)
				show = TRUE
				break
	if(!rebuild && show == !isnull(floor_under))
		return
	if(floor_under)
		floor_depth_clear_under()
	if(show)
		underlays += GLOB.floor_depth_under_plating
		underlays += GLOB.floor_depth_under_shade
		// The hidden pipes, cables and disposals, each a copy in vis_contents: as an overlay or underlay a copy is drawn in the
		// turf's dir whatever its own (an east-west pipe came out north-south), and a vis_contents object keeps its own
		floor_under = list()
		for(var/obj/O in src)
			if(O.level != 1 || O.invisibility != INVISIBILITY_MAXIMUM || QDELING(O))
				continue
			var/obj/effect/abstract/floor_depth_under/copy = new(null)
			copy.appearance = O.appearance
			copy.dir = O.dir // not carried by an appearance set on an atom
			copy.plane = FLOOR_DEPTH_PLANE
			copy.invisibility = 0
			copy.alpha = 255 // hidden pipes are drawn faint
			copy.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
			floor_under += copy
		vis_contents += floor_under
		GLOB.floor_depth_unders++

/turf/proc/floor_depth_clear_under()
	underlays -= GLOB.floor_depth_under_plating
	underlays -= GLOB.floor_depth_under_shade
	vis_contents -= floor_under
	QDEL_LIST(floor_under)
	floor_under = null
	GLOB.floor_depth_unders--

/// A copy of something hidden under a tile beside a hole, shown in the tile's vis_contents on the depth plane
/obj/effect/abstract/floor_depth_under
	name = "under the floor"

/turf/open/floor/plating/Entered(atom/movable/AM)
	. = ..()
	if(floor_sunken && AM.floor_depth_sinks())
		AM.floor_depth_sink()

/turf/open/floor/plating/Exited(atom/movable/Obj, atom/newloc)
	. = ..()
	if(floor_sunken && Obj.floor_depth_from)
		Obj.floor_depth_rise()

/// A tile going back on, or anything else replacing the plating: what was down in the hole comes back up
/turf/open/floor/plating/Destroy(force)
	if(floor_sunken)
		GLOB.floor_depth_holes--
		for(var/atom/movable/AM as anything in src)
			if(AM.floor_depth_from)
				AM.floor_depth_rise()
	return ..()

/turf/Destroy(force)
	if(floor_under)
		floor_depth_clear_under()
	return ..()

/// Made down in a hole (a cable laid, blood spilt): Entered() isn't called for something made in place
/obj/Initialize(mapload)
	. = ..()
	if(!mapload)
		var/turf/T = loc
		if(isturf(T) && T.floor_sunken && floor_depth_sinks())
			floor_depth_sink()

/// Something hidden under a tile beside a hole is gone: so is its picture
/obj/Destroy(force)
	if(level == 1 && GLOB.floor_depth_unders)
		var/turf/T = loc
		if(isturf(T) && T.floor_under)
			GLOB.floor_depth_dirty[T] = TRUE
			floor_depth_queue_flush()
	return ..()

// Screen side

/// The plane masters that must turn, skew or bend along with the floor's when something does that to a player's view (drugs):
/// the plating's and the holes' shapes. Never the drawing or shadow planes: they're made from those planes' render targets,
/// which already carry the turn, and turning them as well turns the holes twice (floor_depth_shots.dm, depth_rot_*)
/proc/floor_depth_world_planes(mob/M)
	. = list()
	if(!M?.hud_used)
		return
	for(var/plane in list(FLOOR_DEPTH_PLANE, FLOOR_DEPTH_MASK_PLANE))
		var/obj/screen/plane_master/PM = M.hud_used.plane_masters["[plane]"]
		if(PM)
			. += PM

/// The holes' shapes, which cut the depth drawing to them. Not drawn
/obj/screen/plane_master/floor_depth_mask
	name = "floor depth mask plane master"
	plane = FLOOR_DEPTH_MASK_PLANE
	appearance_flags = PLANE_MASTER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = FLOOR_DEPTH_MASK_RENDER_TARGET

/// The holes' plating and what's under the tiles beside them, drawn as it always was (under the plane that draws it with depth)
/obj/screen/plane_master/floor_depth
	name = "sunken plating plane master"
	plane = FLOOR_DEPTH_PLANE
	appearance_flags = PLANE_MASTER
	blend_mode = BLEND_OVERLAY
	render_target = FLOOR_DEPTH_RENDER_TARGET

/obj/screen/plane_master/floor_depth/backdrop(mob/mymob)
	filters = list()
	if(istype(mymob) && mymob.eye_blurry)
		filters += GAUSSIAN_BLUR(clamp(mymob.eye_blurry*0.1,0.6,3))

/// Blurred eyes blur the plating in the holes too, as they do the floor
/mob/update_eye_blur()
	. = ..()
	if(client && hud_used)
		var/obj/screen/plane_master/floor_depth/PM = hud_used.plane_masters["[FLOOR_DEPTH_PLANE]"]
		PM?.backdrop(src)

/// Draws the holes again with depth, cut to their shape. Hidden for a player who turned it off
/obj/screen/plane_master/floor_depth_draw
	name = "floor depth plane master"
	plane = FLOOR_DEPTH_DRAW_PLANE
	appearance_flags = PLANE_MASTER
	blend_mode = BLEND_OVERLAY
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/floor_depth_draw/Initialize()
	. = ..()
	filters += filter(type = "alpha", render_source = FLOOR_DEPTH_MASK_RENDER_TARGET)

/obj/screen/plane_master/floor_depth_draw/backdrop(mob/mymob)
	var/client/C = istype(mymob) && mymob.client
	if(!C)
		return
	var/obj/screen/plane_master/floor_depth_shadow/shadow = mymob.hud_used?.plane_masters["[FLOOR_DEPTH_SHADOW_PLANE]"]
	if(!GLOB.floor_depth_on || (C.prefs && (C.prefs.hippie_toggles & FLOOR_DEPTH_DISABLED)))
		Hide()
		shadow?.Hide()
		C.screen -= GLOB.floor_depth_relays
	else
		Show()
		shadow?.Show()
		C.screen |= GLOB.floor_depth_relays

/// The rims' shadow: the floor in black on this plane, blurred, cut to the holes
/obj/screen/plane_master/floor_depth_shadow
	name = "floor depth shadow plane master"
	plane = FLOOR_DEPTH_SHADOW_PLANE
	appearance_flags = PLANE_MASTER
	blend_mode = BLEND_OVERLAY
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	show_alpha = 90

/obj/screen/plane_master/floor_depth_shadow/Initialize()
	. = ..()
	alpha = show_alpha
	filters += filter(type = "blur", size = 1.5)
	filters += filter(type = "alpha", render_source = FLOOR_DEPTH_MASK_RENDER_TARGET)

/// One layer of the depth drawing: a copy of another plane
/obj/screen/floor_depth_relay
	name = "floor depth"
	plane = FLOOR_DEPTH_DRAW_PLANE
	// The copy is drawn from this object's bottom-left corner (as with the unlit space relay, plane_master.dm), and a transform
	// scales it round its middle, which is the middle of the screen
	screen_loc = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = PASS_MOUSE | NO_CLIENT_COLOR | KEEP_TOGETHER

/obj/screen/floor_depth_relay/New(loc, source, scale = 1, new_color, new_layer, new_plane = FLOOR_DEPTH_DRAW_PLANE)
	..()
	render_source = source
	if(scale != 1)
		transform = matrix(scale, 0, 0, 0, scale, 0)
	color = new_color
	layer = new_layer
	plane = new_plane

GLOBAL_LIST_INIT(floor_depth_relays, make_floor_depth_relays())

/// scale: how much smaller the depth plane is drawn. crisp: scaled without smoothing (every 40th pixel dropped), which keeps the
/// pixel art sharp, rather than a little soft
/proc/make_floor_depth_relays(scale = FLOOR_DEPTH_SCALE, crisp = TRUE)
	. = list()
	// A hidden copy of the depth plane for the smaller drawing to come from. A scaled relay straight off a plane that BYOND draws
	// moves that plane itself a few pixels on the screen (seen on 516: the whole floor slid off the walls); a copy rendered to a
	// * target is never drawn, so there's nothing for it to move
	var/obj/screen/floor_depth_relay/copy = new(null, FLOOR_DEPTH_RENDER_TARGET, 1, null, 0)
	copy.render_target = "*floor_depth_copy"
	. += copy
	// The dark fill, the holes' own shape: what's left showing where the far rim is a wall
	. += new /obj/screen/floor_depth_relay(null, FLOOR_DEPTH_MASK_RENDER_TARGET, 1, "#262626", 1)
	// The plating and what's under the tiles, slid towards the middle of the screen
	var/obj/screen/floor_depth_relay/below = new(null, "*floor_depth_copy", scale, "#e8e8e8", 2)
	if(crisp)
		below.appearance_flags |= PIXEL_SCALE
	. += below
	// The rims' shadow: the floor in black, which its plane master blurs into the holes
	. += new /obj/screen/floor_depth_relay(null, FLOOR_PLANE_RENDER_TARGET, 1, list(0,0,0, 0,0,0, 0,0,0, 0,0,0), 1, FLOOR_DEPTH_SHADOW_PLANE)
