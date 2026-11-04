// hippie -- the T-ray view. The old one flashed what was under the floor for 0.8 seconds out of every 2, and not at all in the dark.
// This one holds it steady, lifts it out of the dark, reaches 7 tiles from a scanner and 5 from goggles or a hardsuit helmet, marks
// live cables and loose ends, shows anything stashed under the floor, and can be told to show only cables, pipes or disposals.

#define T_RAY_REFRESH 10 // deciseconds between looks, besides one every step the viewer takes
#define T_RAY_ALPHA 128 // the half see-through copy of what's under the floor, as it always was
#define T_RAY_STASH_ALPHA 200 // something hidden that isn't wiring or plumbing, so it stands out
#define T_RAY_GLOW_ALPHA 190 // how much of the dark the copy lifts, out of 255
#define T_RAY_RANGE_SCANNER 7
#define T_RAY_RANGE_WORN 5
#define T_RAY_LIVE_GLOW "#FFE04A"
#define T_RAY_STASH_OUTLINE "#FFB000"
#define T_RAY_END_CENTRE 16 // a loose end in the middle of the tile, next to the four direction bits
#define T_RAY_END_LAYER (WIRE_LAYER + 0.05) // above the cables and pipes, under anything lying on the floor
#define T_RAY_CRAWLER_LAYER (WIRE_LAYER + 0.04)
#define T_RAY_GOGGLE_MODE "t-ray" // MODE_TRAY in engine_goggles.dm, which #undefs it

#define T_RAY_SHOW_ALL "everything"
#define T_RAY_SHOW_CABLES "cables"
#define T_RAY_SHOW_PIPES "pipes"
#define T_RAY_SHOW_DISPOSALS "disposals"

GLOBAL_LIST_INIT(t_ray_filters, list(T_RAY_SHOW_ALL, T_RAY_SHOW_CABLES, T_RAY_SHOW_PIPES, T_RAY_SHOW_DISPOSALS))
/// Type -> which filter it belongs to. The station's other underfloor fittings show only with everything, and anything else under
/// the floor (no entry here) is a stash: shown only with everything, and made to stand out.
GLOBAL_LIST_INIT(t_ray_kinds, t_ray_kind_cache())
/// Mob -> its /datum/t_ray_view
GLOBAL_LIST_EMPTY(t_ray_views)

/proc/t_ray_kind_cache()
	. = list()
	for(var/path in typesof(/obj/structure/cable, /obj/machinery/power/terminal, /obj/structure/cable_bridge))
		.[path] = T_RAY_SHOW_CABLES
	for(var/path in typesof(/obj/machinery/atmospherics, /obj/machinery/duct))
		.[path] = T_RAY_SHOW_PIPES
	for(var/path in typesof(/obj/structure/disposalpipe, /obj/structure/disposalconstruct))
		.[path] = T_RAY_SHOW_DISPOSALS
	for(var/path in typesof(/obj/machinery/navbeacon, /obj/machinery/magnetic_module, /obj/machinery/bluespace_beacon))
		.[path] = T_RAY_SHOW_ALL

/// Starts the T-ray view a source gives the mob holding or wearing it, or keeps it going. Sources call it again as they process.
/proc/t_ray_view_start(mob/viewer, obj/item/source)
	if(!ismob(viewer) || !viewer.client || !source.t_ray_range(viewer))
		return
	var/datum/t_ray_view/V = GLOB.t_ray_views[viewer]
	if(!V)
		V = new(viewer)
	if(!(source in V.sources))
		V.sources += source
		V.refresh()

/proc/t_ray_view_stop(mob/viewer, obj/item/source)
	if(!ismob(viewer))
		return
	var/datum/t_ray_view/V = GLOB.t_ray_views[viewer]
	if(V && (source in V.sources))
		V.sources -= source
		V.refresh()

/// The directions an underfloor run ends in with nothing joined on, as direction bits plus T_RAY_END_CENTRE.
/proc/t_ray_loose_ends(obj/O)
	if(istype(O, /obj/structure/cable))
		var/obj/structure/cable/C = O
		var/links = C.linked_dirs
		if(links & (links - 1)) // two or more ways out: the middle of a run
			return 0
		for(var/obj/thing in C.loc) // a run ending at a machine, a grille or a bridge ends where it should
			if(GLOB.wire_node_generating_types[thing.type])
				return 0
			if(istype(thing, /obj/machinery) && !istype(thing, /obj/machinery/door) && !istype(thing, /obj/machinery/atmospherics) && !istype(thing, /obj/machinery/duct) && !istype(thing, /obj/machinery/navbeacon) && !istype(thing, /obj/machinery/magnetic_module))
				return 0
		return T_RAY_END_CENTRE
	if(istype(O, /obj/machinery/atmospherics))
		var/obj/machinery/atmospherics/A = O
		if(!A.device_type || istype(A, /obj/machinery/atmospherics/pipe/layer_manifold))
			return 0
		var/list/nodes = A.nodes
		var/joined = 0
		for(var/node in nodes)
			if(node)
				joined++
		if(joined >= A.device_type)
			return 0
		// The open side: a way out with nothing joined on the next tile. Pumps and filters order their nodes their own way.
		. = 0
		var/ways = A.GetInitDirections()
		for(var/direction in GLOB.cardinals)
			if(!(ways & direction))
				continue
			var/turf/next = get_step(A, direction)
			var/found = FALSE
			for(var/obj/machinery/atmospherics/node in nodes)
				if(node.loc == next)
					found = TRUE
					break
			if(!found)
				. |= direction
		return . || T_RAY_END_CENTRE
	if(istype(O, /obj/structure/disposalpipe))
		var/obj/structure/disposalpipe/P = O
		. = 0
		for(var/direction in GLOB.cardinals)
			if(!(P.dpdir & direction))
				continue
			var/joined = FALSE
			var/back = turn(direction, 180)
			for(var/obj/structure/disposalpipe/next in get_step(P, direction))
				if(next.dpdir & back)
					joined = TRUE
					break
			if(!joined)
				. |= direction
		if(istype(P, /obj/structure/disposalpipe/trunk))
			var/obj/structure/disposalpipe/trunk/trunk = P
			if(!trunk.linked)
				. |= T_RAY_END_CENTRE
		return
	return 0

/// A cable or terminal with power on it.
/proc/t_ray_live(obj/O)
	var/datum/powernet/net
	if(istype(O, /obj/structure/cable))
		var/obj/structure/cable/C = O
		net = C.powernet
	else if(istype(O, /obj/machinery/power))
		var/obj/machinery/power/P = O
		net = P.powernet
	return net && net.avail > 0

/**
  * What one player sees through their T-ray scanners, goggles and helmets: every hidden thing under the floor in reach drawn half
  * see-through where it lies, the same as the old flash, but held steady. Each copy has a twin on the emissive plane, which lifts the
  * dark from it the way a lit screen does, so the wiring of a blacked-out room shows. Live cables glow, the open ends of cables, pipes
  * and disposals get a red dot, and anything hidden that isn't wiring or plumbing (a floor safe, a smuggler's satchel, a pressure
  * plate, something crawling in the vents) is drawn stronger with a gold rim.
  *
  * It takes a full look every second, and on each step looks only at the strip of tiles that came into reach (0.7 ms against 0.05 ms
  * in a busy hallway at range 7). Only the images of things that changed are rebuilt.
  *
  * The viewer's see_in_dark is raised to the T-ray's reach while it's up. BYOND draws nothing at all on an unlit tile past
  * see_in_dark, images included, so without it the copies on dark tiles more than two away never showed, emissive or not. The
  * lighting plane still darkens those tiles as before, so the room looks no different: only the T-ray's copies come through.
  */
/datum/t_ray_view
	var/mob/viewer
	var/client/viewer_client
	/// The items giving this view. Each is asked every look whether it still does.
	var/list/sources = list()
	/// Thing -> list(its appearance, state number, turf, list of images)
	var/list/shown = list()
	var/range = 0
	/// The range the viewer's sight was last widened to
	var/sight_range = 0
	/// Filter -> TRUE, for every filter one of the sources is set to
	var/list/showing = list()
	var/refresh_timer
	/// Images built since the view started, for the self-test: a still view should stop building any
	var/built = 0

/datum/t_ray_view/New(mob/viewer)
	src.viewer = viewer
	viewer_client = viewer.client
	GLOB.t_ray_views[viewer] = src
	RegisterSignal(viewer, COMSIG_MOVABLE_MOVED, PROC_REF(viewer_moved))
	RegisterSignal(viewer, list(COMSIG_PARENT_QDELETING, COMSIG_MOB_LOGOUT), PROC_REF(viewer_gone))
	RegisterSignal(viewer, COMSIG_MOB_UPDATE_SIGHT, PROC_REF(widen_sight))

/datum/t_ray_view/Destroy()
	deltimer(refresh_timer)
	clear()
	if(viewer)
		UnregisterSignal(viewer, list(COMSIG_MOVABLE_MOVED, COMSIG_PARENT_QDELETING, COMSIG_MOB_LOGOUT, COMSIG_MOB_UPDATE_SIGHT))
		if(GLOB.t_ray_views[viewer] == src)
			GLOB.t_ray_views -= viewer
		if(sight_range && !QDELETED(viewer))
			range = 0
			viewer.update_sight()
	viewer = null
	viewer_client = null
	sources = null
	return ..()

/datum/t_ray_view/proc/viewer_gone()
	qdel(src)

/// Carbons send this at the end of update_sight(), once their eyes and glasses have set see_in_dark.
/datum/t_ray_view/proc/widen_sight()
	if(range && viewer.see_in_dark < range)
		viewer.see_in_dark = range

/datum/t_ray_view/proc/viewer_moved(datum/source, atom/old_loc)
	if(!range || !viewer_client)
		return
	var/turf/old_turf = get_turf(old_loc)
	var/turf/new_turf = get_turf(viewer)
	if(!old_turf || !new_turf || old_turf.z != new_turf.z || get_dist(old_turf, new_turf) > 1)
		look()
	else if(old_turf != new_turf)
		look_edge(old_turf, new_turf)

/datum/t_ray_view/proc/clear()
	if(viewer_client)
		for(var/thing in shown)
			var/list/entry = shown[thing]
			viewer_client.images -= entry[4]
	shown = list()

/// Asks the sources what they still give, then looks.
/datum/t_ray_view/proc/refresh()
	deltimer(refresh_timer)
	refresh_timer = null
	if(QDELETED(viewer) || !viewer.client)
		qdel(src)
		return
	if(viewer.client != viewer_client)
		clear()
		viewer_client = viewer.client
	range = 0
	showing = list()
	for(var/obj/item/source as anything in sources.Copy())
		var/reach = QDELETED(source) ? 0 : source.t_ray_range(viewer)
		if(!reach)
			sources -= source
			continue
		range = max(range, reach)
		showing[source.t_ray_filter || T_RAY_SHOW_ALL] = TRUE
	if(!range)
		qdel(src)
		return
	refresh_timer = addtimer(CALLBACK(src, PROC_REF(refresh)), T_RAY_REFRESH, TIMER_STOPPABLE)
	if(sight_range != range)
		sight_range = range
		viewer.update_sight()
	look()

/// A full look at everything in reach: what's new, what's changed and what's gone. About 0.7 ms at range 7 in a busy hallway.
/datum/t_ray_view/proc/look()
	var/list/now = list()
	var/turf/centre = get_turf(viewer)
	if(centre)
		var/everything = showing[T_RAY_SHOW_ALL]
		for(var/obj/O in range(range, centre))
			if(O.level == 1)
				consider(O, now, everything)
	for(var/thing in shown)
		if(!now[thing])
			var/list/entry = shown[thing]
			viewer_client.images -= entry[4]
	shown = now

/// One step: drops what's gone out of reach and looks only at the strip of tiles that came into it. The full look every second
/// catches anything that changed in between.
/datum/t_ray_view/proc/look_edge(turf/old_turf, turf/new_turf)
	var/list/gone = list()
	for(var/thing in shown)
		var/list/entry = shown[thing]
		if(get_dist(entry[3], new_turf) > range)
			gone += thing
			viewer_client.images -= entry[4]
	shown -= gone
	var/list/strip = list()
	var/z = new_turf.z
	var/dx = new_turf.x - old_turf.x
	var/dy = new_turf.y - old_turf.y
	if(dx)
		var/x = new_turf.x + dx * range
		if(x >= 1 && x <= world.maxx)
			strip += block(locate(x, max(1, new_turf.y - range), z), locate(x, min(world.maxy, new_turf.y + range), z))
	if(dy)
		var/y = new_turf.y + dy * range
		if(y >= 1 && y <= world.maxy)
			strip |= block(locate(max(1, new_turf.x - range), y, z), locate(min(world.maxx, new_turf.x + range), y, z))
	var/everything = showing[T_RAY_SHOW_ALL]
	for(var/turf/T as anything in strip)
		for(var/obj/O in T)
			if(O.level == 1)
				consider(O, shown, everything)

/// Whether one thing under the floor is shown and how. Its entry goes into now, rebuilt if it changed since it was last shown.
/datum/t_ray_view/proc/consider(obj/O, list/now, everything)
	var/kind = GLOB.t_ray_kinds[O.type]
	if(!everything && (!kind || !showing[kind]))
		return
	var/hidden = O.invisibility == INVISIBILITY_MAXIMUM || HAS_TRAIT(O, TRAIT_T_RAY_VISIBLE)
	var/ends = kind ? t_ray_loose_ends(O) : 0
	if(!hidden && !ends)
		return
	var/live = hidden && kind == T_RAY_SHOW_CABLES && t_ray_live(O)
	var/turf/T = O.loc
	var/state = hidden + live * 2 + ends * 4
	var/list/entry = shown[O]
	if(!entry || entry[1] != O.appearance || entry[2] != state || entry[3] != T)
		var/list/images = list()
		if(hidden)
			var/glow
			if(live)
				glow = filter(type = "drop_shadow", x = 0, y = 0, size = 3, offset = 1, color = T_RAY_LIVE_GLOW)
			else if(!kind)
				glow = filter(type = "outline", size = 1, color = T_RAY_STASH_OUTLINE)
			images += copy_of(O, T, kind ? T_RAY_ALPHA : T_RAY_STASH_ALPHA, glow)
		if(ends)
			images += end_markers(O, T, ends)
		entry = replace(entry, list(O.appearance, state, T, images))
	now[O] = entry
	// Anything crawling through the vents and pipes under the floor
	if(hidden && kind == T_RAY_SHOW_PIPES && length(O.contents))
		for(var/mob/living/crawler in O.contents)
			if(crawler == viewer)
				continue
			var/list/crawler_entry = shown[crawler]
			if(!crawler_entry || crawler_entry[1] != crawler.appearance || crawler_entry[3] != T)
				var/list/crawler_images = copy_of(crawler, T, T_RAY_STASH_ALPHA, filter(type = "outline", size = 1, color = T_RAY_STASH_OUTLINE), T_RAY_CRAWLER_LAYER)
				crawler_entry = replace(crawler_entry, list(crawler.appearance, 0, T, crawler_images))
			now[crawler] = crawler_entry

/// Swaps a thing's old images for new ones on the client.
/datum/t_ray_view/proc/replace(list/old_entry, list/new_entry)
	if(old_entry)
		viewer_client.images -= old_entry[4]
	var/list/images = new_entry[4]
	viewer_client.images += images
	built += images.len
	return new_entry

/// A half see-through copy of something where it lies, and its twin on the emissive plane that shows it in the dark.
/datum/t_ray_view/proc/copy_of(atom/movable/thing, turf/T, alpha, glow, layer)
	var/mutable_appearance/copy = new(thing)
	copy.alpha = alpha
	copy.dir = thing.dir
	copy.invisibility = 0
	if(!copy.icon_state && istype(thing, /obj/item/pressure_plate)) // a hidden plate blanks its own sprite
		copy.icon_state = initial(thing.icon_state)
	if(layer)
		copy.layer = layer
	if(glow)
		copy.filters = glow
	var/image/plain = image(loc = T)
	plain.appearance = copy
	copy.plane = EMISSIVE_PLANE
	copy.alpha = T_RAY_GLOW_ALPHA
	var/image/lit = image(loc = T)
	lit.appearance = copy
	return list(plain, lit)

/// A red dot at each open end, at the edge of the tile it runs off or in the middle, and its twin to show it in the dark.
/datum/t_ray_view/proc/end_markers(obj/O, turf/T, ends)
	. = list()
	for(var/bit in list(NORTH, SOUTH, EAST, WEST, T_RAY_END_CENTRE))
		if(!(ends & bit))
			continue
		var/image/mark = image('hippiestation/icons/effects/t_ray.dmi', T, "end", T_RAY_END_LAYER)
		mark.plane = GAME_PLANE
		mark.pixel_x = O.pixel_x + (bit == EAST ? 12 : (bit == WEST ? -12 : 0))
		mark.pixel_y = O.pixel_y + (bit == NORTH ? 12 : (bit == SOUTH ? -12 : 0))
		var/image/lit = image(loc = T)
		lit.appearance = mark.appearance
		lit.plane = EMISSIVE_PLANE
		. += mark
		. += lit

// The sources

/obj/item
	/// What this item's T-ray shows (T_RAY_SHOW_*). Null for anything that isn't a T-ray.
	var/t_ray_filter

/// How far this item's T-ray reaches for this mob right now, or 0.
/obj/item/proc/t_ray_range(mob/viewer)
	return 0

/obj/item/proc/t_ray_filter_text()
	return t_ray_filter == T_RAY_SHOW_ALL ? "everything under the floor" : "[t_ray_filter] only"

/obj/item/proc/cycle_t_ray_filter(mob/user)
	var/list/filters = GLOB.t_ray_filters
	t_ray_filter = filters[(filters.Find(t_ray_filter) % filters.len) + 1]
	to_chat(user, "<span class='notice'>You set [src] to show [t_ray_filter_text()].</span>")
	playsound(src, 'sound/machines/click.ogg', 15, TRUE)
	var/datum/t_ray_view/V = GLOB.t_ray_views[user]
	if(V)
		V.refresh()

/// Alt-click on a T-ray, or on its action button: the next filter. FALSE when it isn't one, or out of reach.
/obj/item/proc/t_ray_alt_click(mob/user)
	if(!t_ray_filter || !isliving(user) || user.incapacitated() || (loc != user && !user.canUseTopic(src, BE_CLOSE)))
		return FALSE
	cycle_t_ray_filter(user)
	return TRUE

/obj/screen/movable/action_button/Click(location, control, params)
	var/list/modifiers = params2list(params)
	if(modifiers["alt"] && !modifiers["shift"] && !modifiers["ctrl"] && istype(linked_action, /datum/action/item_action) && can_use(usr))
		var/obj/item/I = linked_action.target
		if(istype(I) && I.t_ray_alt_click(usr))
			return TRUE
	return ..()

// The handheld scanner, and the one built into engineering cyborgs

/obj/item/t_scanner
	t_ray_filter = T_RAY_SHOW_ALL
	var/t_ray_told = FALSE

/obj/item/t_scanner/adv_mining_scanner // only shares the type: it scans rock
	t_ray_filter = null

/obj/item/t_scanner/t_ray_range(mob/viewer)
	return (on && t_ray_filter && loc == viewer) ? T_RAY_RANGE_SCANNER : 0

/obj/item/t_scanner/scan()
	t_ray_view_start(loc, src)

/obj/item/t_scanner/toggle_on()
	. = ..()
	if(!t_ray_filter)
		return
	if(on)
		t_ray_view_start(loc, src)
	else
		t_ray_view_stop(loc, src)

/obj/item/t_scanner/attack_self(mob/user)
	. = ..()
	if(on && t_ray_filter && !t_ray_told)
		t_ray_told = TRUE
		to_chat(user, "<span class='notice'>[src] is showing [t_ray_filter_text()]. Alt-click it to change that.</span>")

/obj/item/t_scanner/equipped(mob/user, slot)
	. = ..()
	if(on && t_ray_filter)
		t_ray_view_start(user, src)

/obj/item/t_scanner/dropped(mob/user)
	. = ..()
	t_ray_view_stop(user, src)

/obj/item/t_scanner/AltClick(mob/user)
	if(!t_ray_alt_click(user))
		return ..()

/obj/item/t_scanner/examine(mob/user)
	. = ..()
	if(t_ray_filter)
		. += "<span class='notice'>It's set to show [t_ray_filter_text()]. Alt-click it to change that.</span>"

// A cyborg's update_sight() never reaches the base proc that sends COMSIG_MOB_UPDATE_SIGHT
/mob/living/silicon/robot/update_sight()
	. = ..()
	var/datum/t_ray_view/V = GLOB.t_ray_views[src]
	if(V?.range && see_in_dark < V.range)
		see_in_dark = V.range

// Engineering scanner goggles and the optical T-ray scanner, in T-ray mode

/obj/item/clothing/glasses/meson/engine
	t_ray_filter = T_RAY_SHOW_ALL

/obj/item/clothing/glasses/meson/engine/shuttle
	t_ray_filter = null

/obj/item/clothing/glasses/meson/engine/t_ray_range(mob/living/carbon/human/viewer)
	return (mode == T_RAY_GOGGLE_MODE && t_ray_filter && ishuman(viewer) && viewer.glasses == src) ? T_RAY_RANGE_WORN : 0

/obj/item/clothing/glasses/meson/engine/process()
	if(mode != T_RAY_GOGGLE_MODE)
		return ..()
	if(ishuman(loc))
		t_ray_view_start(loc, src)

/obj/item/clothing/glasses/meson/engine/toggle_mode(mob/user, voluntary)
	. = ..()
	if(mode == T_RAY_GOGGLE_MODE)
		t_ray_view_start(loc, src)
	else
		t_ray_view_stop(loc, src)

/obj/item/clothing/glasses/meson/engine/equipped(mob/user, slot)
	. = ..()
	if(slot == ITEM_SLOT_EYES && mode == T_RAY_GOGGLE_MODE)
		t_ray_view_start(user, src)

/obj/item/clothing/glasses/meson/engine/dropped(mob/user)
	. = ..()
	t_ray_view_stop(user, src)

/obj/item/clothing/glasses/meson/engine/AltClick(mob/user)
	if(!t_ray_alt_click(user))
		return ..()

/obj/item/clothing/glasses/meson/engine/examine(mob/user)
	. = ..()
	if(t_ray_filter)
		. += "<span class='notice'>Its T-ray mode is set to show [t_ray_filter_text()]. Alt-click it to change that.</span>"

// Engineering, atmospherics and the Chief Engineer's hardsuit helmets get a T-ray of their own

/datum/action/item_action/toggle_t_ray
	name = "Toggle T-ray Scanner"
	desc = "See the wiring and pipes under the floor. Alt-click to choose what it shows."
	icon_icon = 'icons/obj/device.dmi'
	button_icon_state = "t-ray0"

/obj/item/clothing/head/helmet/space/hardsuit/engine
	actions_types = list(/datum/action/item_action/toggle_helmet_light, /datum/action/item_action/toggle_t_ray)
	t_ray_filter = T_RAY_SHOW_ALL
	var/t_ray_on = FALSE

/obj/item/clothing/head/helmet/space/hardsuit/engine/ui_action_click(mob/user, action)
	if(istype(action, /datum/action/item_action/toggle_t_ray))
		toggle_t_ray(user)
		return
	return ..()

/obj/item/clothing/head/helmet/space/hardsuit/engine/proc/toggle_t_ray(mob/user)
	t_ray_on = !t_ray_on
	to_chat(user, "<span class='notice'>You switch [src]'s T-ray scanner [t_ray_on ? "on. It's showing [t_ray_filter_text()]; alt-click the button to change that" : "off"].</span>")
	playsound(src, 'sound/machines/click.ogg', 15, TRUE)
	for(var/datum/action/item_action/toggle_t_ray/A in actions)
		A.button_icon_state = t_ray_on ? "t-ray1" : "t-ray0"
		A.UpdateButtonIcon()
	if(t_ray_on)
		t_ray_view_start(user, src)
	else
		t_ray_view_stop(user, src)

/obj/item/clothing/head/helmet/space/hardsuit/engine/t_ray_range(mob/living/carbon/human/viewer)
	return (t_ray_on && ishuman(viewer) && viewer.head == src) ? T_RAY_RANGE_WORN : 0

/obj/item/clothing/head/helmet/space/hardsuit/engine/process()
	. = ..()
	if(t_ray_on && ishuman(loc))
		t_ray_view_start(loc, src)

/obj/item/clothing/head/helmet/space/hardsuit/engine/equipped(mob/user, slot)
	. = ..()
	if(slot == ITEM_SLOT_HEAD && t_ray_on)
		t_ray_view_start(user, src)

/obj/item/clothing/head/helmet/space/hardsuit/engine/dropped(mob/user)
	. = ..()
	t_ray_view_stop(user, src)

/obj/item/clothing/head/helmet/space/hardsuit/engine/AltClick(mob/user)
	if(!t_ray_alt_click(user))
		return ..()

/obj/item/clothing/head/helmet/space/hardsuit/engine/examine(mob/user)
	. = ..()
	. += "<span class='notice'>Its T-ray scanner is [t_ray_on ? "on" : "off"], set to show [t_ray_filter_text()]. Alt-click it to change that.</span>"

#undef T_RAY_REFRESH
#undef T_RAY_ALPHA
#undef T_RAY_STASH_ALPHA
#undef T_RAY_GLOW_ALPHA
#undef T_RAY_RANGE_SCANNER
#undef T_RAY_RANGE_WORN
#undef T_RAY_LIVE_GLOW
#undef T_RAY_STASH_OUTLINE
#undef T_RAY_END_CENTRE
#undef T_RAY_END_LAYER
#undef T_RAY_CRAWLER_LAYER
#undef T_RAY_GOGGLE_MODE
#undef T_RAY_SHOW_ALL
#undef T_RAY_SHOW_CABLES
#undef T_RAY_SHOW_PIPES
#undef T_RAY_SHOW_DISPOSALS
