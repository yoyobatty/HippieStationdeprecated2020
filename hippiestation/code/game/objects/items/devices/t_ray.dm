// hippie -- the T-ray view. The old one flashed what was under the floor for 0.8 seconds out of every 2, and not at all in the dark.
// This one holds it steady, glows faintly in the dark, reaches 7 tiles from a scanner and 5 from goggles or a hardsuit helmet, marks
// live cables, shows anything stashed under the floor, and can be told to show only cables, pipes or disposals.

#define T_RAY_REFRESH 10 // deciseconds between looks, besides one every step the viewer takes
#define T_RAY_ALPHA 128 // the half see-through copy of what's under the floor, as it always was
#define T_RAY_STASH_ALPHA 200 // something hidden that isn't wiring or plumbing, so it stands out
// The glow in the dark: added over the darkness, out of 255, before it fades with distance and with the light on the tile
#define T_RAY_GLOW_LIVE 140 // a cable with power in it: the one thing down there that would give off light
#define T_RAY_GLOW_FAINT 45 // pipes, disposals and dead cables
#define T_RAY_GLOW_STASH 90
#define T_RAY_GLOW_BLUR 1 // pixels, so it's a soft glow and not a sharp cut-out
#define T_RAY_LIT 0.6 // a tile this lit or more has no glow at all: in a lit room the copies look as they always did
#define T_RAY_RANGE_SCANNER 7
#define T_RAY_RANGE_WORN 5
#define T_RAY_LIVE_GLOW "#FFE04A"
#define T_RAY_STASH_OUTLINE "#FFB000"
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

/// The T-ray's glow in the dark: added over the darkness, blurred soft, and kept off the mobs and items lying on top (the emissive
/// blockers), so a pipe doesn't glow through the person standing on it. Blurred before it's masked, so the edge of somebody's sprite
/// stays sharp.
/obj/screen/plane_master/t_ray_glow
	name = "T-ray glow plane master"
	plane = T_RAY_GLOW_PLANE
	appearance_flags = PLANE_MASTER|NO_CLIENT_COLOR
	blend_mode = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/t_ray_glow/Initialize()
	. = ..()
	filters += filter(type = "blur", size = T_RAY_GLOW_BLUR)
	filters += filter(type = "alpha", render_source = EMISSIVE_BLOCKER_RENDER_TARGET, flags = MASK_INVERSE)

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

/// How dark a tile is for the T-ray's glow, from none in a lit room to all of it in a black one. In quarters, so a flickering light
/// doesn't set it going.
/// get_lumcount()'s sum without the list it builds for every call, which was most of the cost of a look.
/proc/t_ray_darkness(turf/T)
	if(!T.lighting_object)
		return 0
	var/lum = 0
	var/datum/lighting_corner/C = T.lighting_corner_NE
	if(C)
		lum += C.lum_r + C.lum_g + C.lum_b
	C = T.lighting_corner_SE
	if(C)
		lum += C.lum_r + C.lum_g + C.lum_b
	C = T.lighting_corner_SW
	if(C)
		lum += C.lum_r + C.lum_g + C.lum_b
	C = T.lighting_corner_NW
	if(C)
		lum += C.lum_r + C.lum_g + C.lum_b
	return round(clamp(1 - (lum / 12) / T_RAY_LIT, 0, 1), 0.25)

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
  * see-through where it lies, the same as the old flash, but held steady. Live cables glow, and anything hidden that isn't wiring or
  * plumbing (a floor safe, a smuggler's satchel, a pressure plate, something crawling in the vents) is drawn stronger with a gold rim.
  *
  * In the dark each copy has a glow: the same picture, blurred and faint, added over the darkness on a plane above the lighting, so
  * only the thing itself shows and the floor round it stays dark. Live cables glow warmest, pipes, disposals and dead cables barely,
  * it fades with distance to nothing at the edge of the T-ray's reach, and with the light on the tile, so a lit room looks as it
  * always did. (A first try lifted the lighting off the copies instead, on the emissive plane: that lit the floor under them too, a
  * sharp cut-out brighter than a lit room.)
  *
  * It takes a full look every second, and on each step looks only at the strip of tiles that came into reach (0.5 ms against 0.07 ms
  * in a busy hallway at range 7). Only the images of things that changed are rebuilt.
  *
  * The viewer's see_in_dark is raised to the T-ray's reach while it's up. BYOND draws nothing at all on an unlit tile past
  * see_in_dark, images included, so without it the glows on dark tiles more than two away never showed. The lighting plane still
  * darkens those tiles as before, so the room looks no different: only the T-ray's glow comes through.
  */
/datum/t_ray_view
	var/mob/viewer
	var/client/viewer_client
	/// The items giving this view. Each is asked every look whether it still does.
	var/list/sources = list()
	/// Thing -> list(its appearance, whether it's live, turf, list of images, its glows (image -> strength), how dark its tile is, the glow
	/// strength last set)
	var/list/shown = list()
	/// Turf -> how dark it is, for the look under way
	var/list/dark_cache = list()
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

/// A full look at everything in reach: what's new, what's changed and what's gone. About 0.5 ms at range 7 in a busy hallway.
/datum/t_ray_view/proc/look()
	var/list/now = list()
	dark_cache = list()
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
	shine()

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
	dark_cache = list()
	for(var/turf/T as anything in strip)
		for(var/obj/O in T)
			if(O.level == 1)
				consider(O, shown, everything)
	shine()

/// Whether one thing under the floor is shown and how. Its entry goes into now, rebuilt if it changed since it was last shown.
/datum/t_ray_view/proc/consider(obj/O, list/now, everything)
	var/kind = GLOB.t_ray_kinds[O.type]
	if(!everything && (!kind || !showing[kind]))
		return
	if(O.invisibility != INVISIBILITY_MAXIMUM && !HAS_TRAIT(O, TRAIT_T_RAY_VISIBLE))
		return
	var/live = (kind == T_RAY_SHOW_CABLES && t_ray_live(O)) ? TRUE : FALSE
	var/turf/T = O.loc
	var/list/entry = shown[O]
	if(!entry || entry[1] != O.appearance || entry[2] != live || entry[3] != T)
		var/list/glows = list()
		var/outline
		if(live)
			outline = filter(type = "drop_shadow", x = 0, y = 0, size = 3, offset = 1, color = T_RAY_LIVE_GLOW)
		else if(!kind)
			outline = filter(type = "outline", size = 1, color = T_RAY_STASH_OUTLINE)
		var/list/images = copy_of(O, T, kind ? T_RAY_ALPHA : T_RAY_STASH_ALPHA, outline, null, glows, live ? T_RAY_GLOW_LIVE : (kind ? T_RAY_GLOW_FAINT : T_RAY_GLOW_STASH))
		entry = replace(entry, list(O.appearance, live, T, images, glows, 0, -1))
	entry[6] = darkness_at(T)
	now[O] = entry
	// Anything crawling through the vents and pipes under the floor
	if(kind == T_RAY_SHOW_PIPES && length(O.contents))
		for(var/mob/living/crawler in O.contents)
			if(crawler == viewer)
				continue
			var/list/crawler_entry = shown[crawler]
			if(!crawler_entry || crawler_entry[1] != crawler.appearance || crawler_entry[3] != T)
				var/list/crawler_glows = list()
				var/list/crawler_images = copy_of(crawler, T, T_RAY_STASH_ALPHA, filter(type = "outline", size = 1, color = T_RAY_STASH_OUTLINE), T_RAY_CRAWLER_LAYER, crawler_glows, T_RAY_GLOW_STASH)
				crawler_entry = replace(crawler_entry, list(crawler.appearance, 0, T, crawler_images, crawler_glows, 0, -1))
			crawler_entry[6] = darkness_at(T)
			now[crawler] = crawler_entry

/// Swaps a thing's old images for new ones on the client.
/datum/t_ray_view/proc/replace(list/old_entry, list/new_entry)
	if(old_entry)
		viewer_client.images -= old_entry[4]
	var/list/images = new_entry[4]
	viewer_client.images += images
	built += images.len
	return new_entry

/// How dark the tile a thing lies on is, from the cache for this look.
/datum/t_ray_view/proc/darkness_at(turf/T)
	. = dark_cache[T]
	if(isnull(.))
		. = t_ray_darkness(T)
		dark_cache[T] = .

/// Sets every glow from what's glowing, how far off it is and how dark its tile is.
/datum/t_ray_view/proc/shine()
	var/turf/centre = get_turf(viewer)
	if(!centre)
		return
	var/reach = range + 1
	for(var/thing in shown)
		var/list/entry = shown[thing]
		var/strength = entry[6] ? entry[6] * clamp(1 - get_dist(entry[3], centre) / reach, 0, 1) : 0
		if(strength == entry[7]) // as it was: in a lit room, always
			continue
		entry[7] = strength
		var/list/glows = entry[5]
		for(var/image/glow as anything in glows)
			var/alpha = round(glows[glow] * strength, 4)
			if(glow.alpha != alpha)
				glow.alpha = alpha

/// A half see-through copy of something where it lies, and its glow: the same picture, faint and soft, added over the darkness.
/datum/t_ray_view/proc/copy_of(atom/movable/thing, turf/T, alpha, outline, layer, list/glows, glow_strength)
	var/mutable_appearance/copy = new(thing)
	copy.alpha = alpha
	copy.dir = thing.dir
	copy.invisibility = 0
	if(!copy.icon_state && istype(thing, /obj/item/pressure_plate)) // a hidden plate blanks its own sprite
		copy.icon_state = initial(thing.icon_state)
	if(layer)
		copy.layer = layer
	if(outline)
		copy.filters = outline
	var/image/plain = image(loc = T)
	plain.appearance = copy
	var/image/glow = image(loc = T)
	glow.appearance = copy
	glow.plane = T_RAY_GLOW_PLANE
	glow.alpha = 0
	glows[glow] = glow_strength
	return list(plain, glow)

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
#undef T_RAY_GLOW_LIVE
#undef T_RAY_GLOW_FAINT
#undef T_RAY_GLOW_STASH
#undef T_RAY_GLOW_BLUR
#undef T_RAY_LIT
#undef T_RAY_RANGE_SCANNER
#undef T_RAY_RANGE_WORN
#undef T_RAY_LIVE_GLOW
#undef T_RAY_STASH_OUTLINE
#undef T_RAY_CRAWLER_LAYER
#undef T_RAY_GOGGLE_MODE
#undef T_RAY_SHOW_ALL
#undef T_RAY_SHOW_CABLES
#undef T_RAY_SHOW_PIPES
#undef T_RAY_SHOW_DISPOSALS
