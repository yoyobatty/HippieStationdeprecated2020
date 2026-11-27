// Swimmers waist deep, things sunk or afloat, and drips after climbing out: what pool water does to what's in it. From Paradise.

/// How far the squash map can move a row of a mob's legs, in pixels. The map is drawn for this
#define POOL_LEG_SQUASH 4
/// How many rows of a mob standing in a pool are under the water. The water sprites are drawn for this
#define POOL_WAIST_ROW 13

/// Shows a mob in a pool waist deep, or all under if lying down, until it leaves the water
/datum/component/pool_submerged
	/// The colours of the pool the mob is in, "pool" or "deep"
	var/look
	/// The back half of the ring of water round the mob's waist, drawn behind it
	var/obj/effect/abstract/waterline/back_ring
	/// The front half, drawn over it
	var/obj/effect/abstract/waterline/front_ring
	/// Their shadow on the pool floor
	var/obj/effect/abstract/waterline/floor_shadow
	/// Where the waves bend them, on the refraction plane, more toward their feet
	var/obj/effect/abstract/waterline/refraction
	/// Their reflection on the water in front of them, from the waist up
	var/obj/effect/abstract/water_reflection/reflection
	/// Leaves them out of the reflection plane's mirror, which would put their reflection a tile too low
	var/obj/effect/abstract/waterline/unmirrored
	/// Is the mob lying down in the water? Then all of it is under, not only its legs
	var/lying = FALSE

/datum/component/pool_submerged/Initialize(look)
	if(!isliving(parent))
		return COMPONENT_INCOMPATIBLE
	var/mob/living/owner = parent
	// Back in the water, so no longer dripping
	qdel(owner.GetComponent(/datum/component/pool_wet))
	back_ring = new(null, "waterline_back")
	back_ring.vis_flags |= VIS_UNDERLAY
	front_ring = new(null, "waterline_front")
	// On the pool floor under the water, so it's tinted with it and the ripples bend it
	floor_shadow = new(null, "swimmer_shadow")
	floor_shadow.vis_flags = VIS_INHERIT_ID
	floor_shadow.plane = POOL_FLOOR_PLANE
	refraction = new(null, "refract_legs")
	refraction.vis_flags = VIS_INHERIT_ID
	refraction.plane = WATER_REFRACT_PLANE
	reflection = new(null, owner, POOL_WAIST_ROW)
	unmirrored = make_unmirrored_block()
	owner.vis_contents += list(back_ring, front_ring, floor_shadow, refraction, reflection, unmirrored)
	// The water rises and falls a little round them
	for(var/obj/effect/abstract/waterline/ring in list(back_ring, front_ring))
		animate(ring, pixel_y = 1, time = 1.6 SECONDS, loop = -1, easing = SINE_EASING)
		animate(pixel_y = -1, time = 1.6 SECONDS, easing = SINE_EASING)
	lying = !!owner.lying
	set_look(look)

/datum/component/pool_submerged/Destroy(force)
	var/mob/living/owner = parent
	owner.vis_contents -= list(back_ring, front_ring, floor_shadow, refraction, reflection, unmirrored)
	reflection.stop_reflecting(owner)
	QDEL_NULL(back_ring)
	QDEL_NULL(front_ring)
	QDEL_NULL(floor_shadow)
	QDEL_NULL(refraction)
	QDEL_NULL(reflection)
	QDEL_NULL(unmirrored)
	owner.remove_filter(list("pool_submerged", "pool_legs_squash"))
	return ..()

/// Lying down or getting up in the water: called from update_mobility() below
/datum/component/pool_submerged/proc/on_resting(now_lying)
	if(now_lying == lying)
		return
	lying = now_lying
	set_look(look)

/mob/living/update_mobility()
	. = ..()
	var/datum/component/pool_submerged/submerged = GetComponent(/datum/component/pool_submerged)
	submerged?.on_resting(!!lying)

/datum/component/pool_submerged/RegisterWithParent()
	RegisterSignal(parent, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))

/datum/component/pool_submerged/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_MOVABLE_MOVED)

/// Puts the water over the mob's legs in the colours of the pool it's in
/datum/component/pool_submerged/proc/set_look(new_look)
	look = new_look
	var/mob/living/owner = parent
	// No ring round the waist of someone lying under the water
	back_ring.alpha = lying ? 0 : 255
	front_ring.alpha = lying ? 0 : 255
	// The waves bend all of someone lying under the water, and only the legs of someone standing in it
	refraction.icon_state = lying ? "refract_all" : "refract_legs"
	// And someone under the water isn't reflected on top of it
	if(lying)
		owner.vis_contents -= reflection
	else
		owner.vis_contents |= reflection
	if(lying)
		// Fully under the water, so no leg squash
		owner.remove_filter("pool_legs_squash")
		owner.add_filter("pool_submerged", 20, list("type" = "layer", "icon" = get_pool_filter_icon("sunk_[look]"), "blend_mode" = BLEND_INSET_OVERLAY))
		return
	// Drawn over the mob's own pixels only, so the tile round it isn't tinted twice
	owner.add_filter("pool_submerged", 20, list("type" = "layer", "icon" = get_pool_filter_icon("submerged_[look]"), "blend_mode" = BLEND_INSET_OVERLAY))
	// Legs look a little shorter through the water. The map leaves the mob alone above its waist
	owner.add_filter("pool_legs_squash", 21, list("type" = "displace", "icon" = get_pool_filter_icon("submerged_squash"), "size" = POOL_LEG_SQUASH))

/datum/component/pool_submerged/proc/on_moved(atom/movable/source, atom/old_loc, direction)
	SIGNAL_HANDLER // COMSIG_MOVABLE_MOVED
	if(!check_water())
		return
	// A wake on the water they just left
	if(direction && istype(old_loc, /turf/open/pool))
		new /obj/effect/temp_visual/water_wake(old_loc, direction)

/// Matches the look to the water the mob is in, when it moves or the water under it changes.
/// Returns FALSE, and removes this, if the mob isn't in pool water any more
/datum/component/pool_submerged/proc/check_water()
	var/atom/movable/owner = parent
	var/turf/open/pool/pool = owner.loc
	if(!istype(pool) || !pool.filled)
		// Out onto the floor: dripping and wet footprints for a while
		if(isturf(owner.loc))
			owner.AddComponent(/datum/component/pool_wet)
		qdel(src)
		return FALSE
	if(pool.water_look != look)
		set_look(pool.water_look)
	return TRUE

#undef POOL_LEG_SQUASH
#undef POOL_WAIST_ROW

/// How far a floating thing rises and falls on a calm pool, in pixels
#define POOL_FLOAT_BOB 2
/// How many pixels lower a thing on the pool's bottom is drawn
#define POOL_SUNK_DROP 2
/// Waterline row of the floater sprites, from the bottom. They're moved to each thing's own waterline
#define POOL_FLOAT_SPRITE_LINE 16

/// Everything floating on a pool right now, for rings of waves to lift as they pass
GLOBAL_LIST_EMPTY(pool_things_afloat)

/// Finds a floating thing's waterline, near the bottom of its sprite. Worked out once for each sprite.
/// Returns "x" and "y", how far to move its water sprites to that line,
/// and "across", how wide it is there, rounded up to the even widths its ring comes in
/proc/get_float_line(obj/item/floater)
	var/static/list/float_lines = list()
	var/key = "[floater.icon]|[floater.icon_state]"
	var/list/float_line = float_lines[key]
	if(float_line)
		return float_line
	var/icon/sprite = icon(floater.icon, floater.icon_state, SOUTH, 1)
	var/height = sprite.Height()
	var/width = sprite.Width()
	// Its lowest and highest rows with anything drawn on them
	var/list/row_left = list()
	var/list/row_right = list()
	var/bottom = 0
	var/top = 0
	for(var/y in 1 to height)
		for(var/x in 1 to width)
			if(!sprite.GetPixel(x, y))
				continue
			if(!row_left["[y]"])
				row_left["[y]"] = x
			row_right["[y]"] = x
		if(!row_left["[y]"])
			continue
		if(!bottom)
			bottom = y
		top = y
	// Nothing drawn at all: as if it filled the middle of its tile
	if(!bottom)
		float_line = list("x" = 0, "y" = 0, "across" = 16)
		float_lines[key] = float_line
		return float_line
	// The highest row that's under the water, and how wide the thing is there
	var/wet_row = bottom + clamp(round((top - bottom + 1) * 0.3, 1), 2, 7) - 1
	var/left = row_left["[wet_row]"]
	var/right = row_right["[wet_row]"]
	var/across = clamp(CEILING(right - left + 1, 2), 4, 26)
	float_line = list("x" = round((left + right) / 2 - (width + 1) / 2, 1), "y" = wet_row - POOL_FLOAT_SPRITE_LINE, "across" = across)
	float_lines[key] = float_line
	return float_line

/// Shows an item in a pool sunk under the water or floating on it, until it leaves the water
/datum/component/pool_sunk
	/// The colours of the pool the item is in, "pool" or "deep"
	var/look
	/// Does the item float on the water instead of lying under it?
	var/floating = FALSE
	/// The item's pixel_z and pixel_w from before it went in the water
	var/old_pixel_z = 0
	var/old_pixel_w = 0
	/// Everything in the item's vis_contents while it's in the water
	var/list/obj/effect/abstract/waterline/parts = list()
	/// The halves of the ring of water round a floating thing
	var/list/obj/effect/abstract/waterline/rings = list()
	/// Where the waves bend the item, on the refraction plane
	var/obj/effect/abstract/waterline/refraction
	/// A floating thing's reflection, from its waterline up
	var/obj/effect/abstract/water_reflection/reflection
	/// A floating thing's waterline, see get_float_line()
	var/list/float_line

/datum/component/pool_sunk/Initialize(look, floating = FALSE, landing = FALSE)
	if(!isitem(parent))
		return COMPONENT_INCOMPATIBLE
	var/obj/item/sunk = parent
	src.floating = floating
	old_pixel_z = sunk.pixel_z
	old_pixel_w = sunk.pixel_w
	if(floating)
		float_line = get_float_line(sunk)
		add_floating_parts()
		GLOB.pool_things_afloat += src
	else
		// All of it is under the water, so the waves bend all of it
		refraction = add_part("refract_all", WATER_REFRACT_PLANE)
	// Left out of the reflection plane's mirror, which would put its reflection a tile too low
	parts += make_unmirrored_block()
	sunk.vis_contents += parts
	set_look(look)
	if(landing)
		land()
	else if(floating)
		bob()
	else
		sunk.pixel_z = old_pixel_z - POOL_SUNK_DROP

/datum/component/pool_sunk/Destroy(force)
	var/obj/item/sunk = parent
	GLOB.pool_things_afloat -= src
	sunk.vis_contents -= parts
	rings.Cut()
	refraction = null
	reflection?.stop_reflecting(sunk)
	reflection = null
	QDEL_LIST(parts)
	sunk.remove_filter(list("pool_sunk", "pool_afloat"))
	// Back to where it was drawn before, which stops it bobbing too
	animate(sunk, pixel_z = old_pixel_z, pixel_w = old_pixel_w, time = 0.1 SECONDS)
	return ..()

/datum/component/pool_sunk/RegisterWithParent()
	RegisterSignal(parent, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))

/datum/component/pool_sunk/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_MOVABLE_MOVED)

/// Adds a sprite drawn with the item, on the item's plane unless given another
/datum/component/pool_sunk/proc/add_part(state, plane)
	var/obj/effect/abstract/waterline/part = new(null, state)
	if(plane)
		part.vis_flags = VIS_INHERIT_ID
		part.plane = plane
	parts += part
	return part

/// Adds a floating thing's ring, refraction, small waves, shadow and reflection, all at its waterline
/datum/component/pool_sunk/proc/add_floating_parts()
	var/across = float_line["across"]
	var/line_x = float_line["x"]
	var/line_y = float_line["y"]
	// The ring of water round it, half behind and half in front
	var/obj/effect/abstract/waterline/back_ring = add_part("floater_ring_[across]_back")
	back_ring.vis_flags |= VIS_UNDERLAY
	rings = list(back_ring, add_part("floater_ring_[across]_front"))
	for(var/obj/effect/abstract/waterline/ring as anything in rings)
		ring.pixel_x = line_x
		ring.pixel_y = line_y
	// The waves bend the part of it that's under the water
	refraction = add_part("refract_float", WATER_REFRACT_PLANE)
	refraction.pixel_y = line_y
	// Small waves spreading out from it, on the hidden ripple plane. The sprite is 3x3 tiles
	var/obj/effect/abstract/waterline/small_waves = add_part("float", WATER_RIPPLE_PLANE)
	small_waves.icon = 'hippiestation/icons/effects/water_ripple_wave.dmi'
	small_waves.pixel_x = line_x - 32
	small_waves.pixel_y = line_y - 32
	// Its shadow on the pool floor, down and to the right of it like a swimmer's
	var/obj/effect/abstract/waterline/shadow = add_part("floater_shadow", POOL_FLOOR_PLANE)
	shadow.pixel_x = line_x + 3
	shadow.pixel_y = line_y - 5
	// The sprite is 18 pixels wide
	shadow.transform = matrix(across / 18 + 0.1, 0, 0, 0, across / 18 + 0.1, 0)
	// Its reflection, flipped at its waterline
	reflection = new(null, parent, line_y + POOL_FLOAT_SPRITE_LINE)
	parts += reflection

/// Draws the water over the item in the colours of the pool it's in
/datum/component/pool_sunk/proc/set_look(new_look)
	look = new_look
	var/obj/item/sunk = parent
	// Drawn over the item's own pixels only, so the tile round it isn't tinted twice
	if(floating)
		sunk.add_filter("pool_afloat", 20, list("type" = "layer", "icon" = get_pool_filter_icon("floater_under_[look]"), "y" = float_line["y"], "blend_mode" = BLEND_INSET_OVERLAY))
	else
		sunk.add_filter("pool_sunk", 20, list("type" = "layer", "icon" = get_pool_filter_icon("sunk_[look]"), "blend_mode" = BLEND_INSET_OVERLAY))

/// Returns list(x, y), where the item meets the water in pixels from its tile's middle, for splashes and rings
/datum/component/pool_sunk/proc/meets_water_at()
	var/obj/item/sunk = parent
	if(floating)
		return list(sunk.pixel_x + float_line["x"], sunk.pixel_y + float_line["y"])
	return list(sunk.pixel_x, sunk.pixel_y)

/// Plays the item hitting the water: a floater dips and bobs back up, anything else sinks
/datum/component/pool_sunk/proc/land()
	var/obj/item/sunk = parent
	if(floating)
		// Dips, pops up and settles. The ring and the waterline filter move the other way, so the water stays put
		var/line_y = float_line["y"]
		animate(sunk, pixel_z = old_pixel_z - 4, time = 0.15 SECONDS, easing = QUAD_EASING | EASE_OUT, flags = ANIMATION_PARALLEL)
		animate(pixel_z = old_pixel_z + 3, time = 0.3 SECONDS, easing = SINE_EASING)
		animate(pixel_z = old_pixel_z, time = 0.35 SECONDS, easing = SINE_EASING)
		animate(sunk.get_filter("pool_afloat"), y = line_y + 4, time = 0.15 SECONDS, easing = QUAD_EASING | EASE_OUT)
		animate(y = line_y - 3, time = 0.3 SECONDS, easing = SINE_EASING)
		animate(y = line_y, time = 0.35 SECONDS, easing = SINE_EASING)
		for(var/obj/effect/abstract/waterline/ring as anything in rings)
			animate(ring, pixel_y = line_y + 4, time = 0.15 SECONDS, easing = QUAD_EASING | EASE_OUT)
			animate(pixel_y = line_y - 3, time = 0.3 SECONDS, easing = SINE_EASING)
			animate(pixel_y = line_y, time = 0.35 SECONDS, easing = SINE_EASING)
		addtimer(CALLBACK(src, PROC_REF(bob)), 0.8 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)
		return
	// The water closes over it from the bottom up as it goes under
	sunk.add_filter("pool_sunk", 20, list("type" = "layer", "icon" = get_pool_filter_icon("sunk_[look]"), "y" = -26, "blend_mode" = BLEND_INSET_OVERLAY))
	animate(sunk.get_filter("pool_sunk"), y = 0, time = 0.45 SECONDS, easing = QUAD_EASING | EASE_OUT)
	// Sinks, rocking side to side on the way down
	animate(sunk, pixel_z = old_pixel_z - POOL_SUNK_DROP, time = 0.7 SECONDS, easing = SINE_EASING | EASE_OUT, flags = ANIMATION_PARALLEL)
	animate(sunk, pixel_w = old_pixel_w + 2, time = 0.2 SECONDS, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(pixel_w = old_pixel_w - 1.5, time = 0.25 SECONDS, easing = SINE_EASING)
	animate(pixel_w = old_pixel_w + 1, time = 0.25 SECONDS, easing = SINE_EASING)
	animate(pixel_w = old_pixel_w, time = 0.2 SECONDS, easing = SINE_EASING)
	// The waves bend it more the deeper it gets
	refraction.alpha = 0
	animate(refraction, alpha = 255, time = 0.6 SECONDS)
	// And bubbles come up from where it went
	var/obj/effect/temp_visual/sink_bubbles/bubbles = new(sunk.loc)
	bubbles.pixel_x += sunk.pixel_x
	bubbles.pixel_y += sunk.pixel_y

/// Bobs a floating thing up and down and side to side, at a random pace so floaters don't move together
/datum/component/pool_sunk/proc/bob()
	var/obj/item/floater = parent
	var/turf/open/pool/pool = floater.loc
	// Higher on a pool with its wave machine running
	var/rise = POOL_FLOAT_BOB
	if(istype(pool) && pool.waves)
		rise += round(4 * pool.waves.rest_energy(), 1)
	var/pace = rand(14, 20)
	animate(floater, pixel_z = old_pixel_z + rise, time = pace, loop = -1, easing = SINE_EASING)
	animate(pixel_z = old_pixel_z, time = pace, easing = SINE_EASING)
	animate(floater, pixel_w = old_pixel_w + 1, time = pace * 1.3, loop = -1, easing = SINE_EASING, flags = ANIMATION_PARALLEL)
	animate(pixel_w = old_pixel_w - 1, time = pace * 1.3, easing = SINE_EASING)
	// The water rises and falls a little round it
	var/line_y = float_line["y"]
	for(var/obj/effect/abstract/waterline/ring as anything in rings)
		animate(ring, pixel_y = line_y + 1, time = 1.6 SECONDS, loop = -1, easing = SINE_EASING)
		animate(pixel_y = line_y - 1, time = 1.6 SECONDS, easing = SINE_EASING)

/// Lifts a floating thing as a ring of waves passes under it, then goes back to bobbing
/datum/component/pool_sunk/proc/ride_wave()
	if(!floating)
		return
	var/obj/item/floater = parent
	animate(floater, pixel_z = old_pixel_z + 4, time = 0.25 SECONDS, easing = SINE_EASING | EASE_OUT)
	animate(pixel_z = old_pixel_z - 1, time = 0.3 SECONDS, easing = SINE_EASING)
	animate(pixel_z = old_pixel_z, time = 0.25 SECONDS, easing = SINE_EASING)
	addtimer(CALLBACK(src, PROC_REF(bob)), 0.8 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)

/datum/component/pool_sunk/proc/on_moved(atom/movable/source, atom/old_loc, direction)
	SIGNAL_HANDLER // COMSIG_MOVABLE_MOVED
	check_water()

/// Matches the look to the water the item is in, or removes this once it's out of pool water
/datum/component/pool_sunk/proc/check_water()
	var/atom/movable/sunk = parent
	var/turf/open/pool/pool = sunk.loc
	// Thrown out of the water, it's in the air until it lands
	if(!istype(pool) || !pool.filled || sunk.throwing)
		qdel(src)
		return
	if(pool.water_look != look)
		set_look(pool.water_look)

#undef POOL_FLOAT_BOB
#undef POOL_SUNK_DROP
#undef POOL_FLOAT_SPRITE_LINE

/// Drips and wet footprints for a little while after someone climbs out of a pool
/datum/component/pool_wet
	/// The drips falling off them, in their vis_contents
	var/obj/effect/abstract/pool_drips/drips
	/// How many more steps leave wet footprints
	var/wet_steps = 6
	/// Timer for when they're dry
	var/dry_timer

/datum/component/pool_wet/Initialize()
	if(!isliving(parent))
		return COMPONENT_INCOMPATIBLE
	drips = new
	var/atom/movable/wetted = parent
	wetted.vis_contents += drips
	dry_timer = addtimer(CALLBACK(src, PROC_REF(dry)), 12 SECONDS, TIMER_STOPPABLE)

/datum/component/pool_wet/Destroy(force)
	deltimer(dry_timer)
	var/atom/movable/wetted = parent
	wetted.vis_contents -= drips
	QDEL_NULL(drips)
	return ..()

/datum/component/pool_wet/RegisterWithParent()
	RegisterSignal(parent, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))

/datum/component/pool_wet/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_MOVABLE_MOVED)

/datum/component/pool_wet/proc/on_moved(atom/movable/source, atom/old_loc, direction)
	SIGNAL_HANDLER // COMSIG_MOVABLE_MOVED
	if(!wet_steps || !direction || !isturf(source.loc) || istype(source.loc, /turf/open/pool))
		return
	wet_steps--
	new /obj/effect/temp_visual/wet_footprints(source.loc, direction)

/datum/component/pool_wet/proc/dry()
	qdel(src)

/// Holds the drips falling off someone wet
/obj/effect/abstract/pool_drips
	invisibility = 0
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	vis_flags = VIS_INHERIT_PLANE | VIS_INHERIT_ID

/obj/effect/abstract/pool_drips/Initialize(mapload)
	. = ..()
	particles = new /particles/water_drip

/obj/effect/abstract/pool_drips/Destroy()
	QDEL_NULL(particles)
	return ..()
