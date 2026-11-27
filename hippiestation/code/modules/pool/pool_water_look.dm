// How pool water looks, from Paradise (pool-water, 2026-11-26): an edge where the pool meets dry land, the water darker the
// further it is from the edge, light dancing on the pool floor and shafts of it through the water, glints, foam and bubbles,
// waves (pool_waves.dm) that bend the floor and what's under the water, reflections of the room in the surface, swimmers
// waist deep and things sinking or floating (pool_swimmers.dm), rings and splashes when anything goes in, and wet footprints
// after. Drained, a pool is its edge and floor. The controller's chemicals and blood tint the surface (set_pool_tint()).

/turf/open/pool
	icon = POOL_WATER_ICON
	icon_state = "coping1-255"
	base_icon_state = "coping1"
	plane = WATER_EDGE_PLANE
	smoothing_flags = SMOOTH_BITMASK
	smoothing_groups = SMOOTH_GROUP_POOL_WATER
	canSmoothWith = SMOOTH_GROUP_POOL_WATER
	/// Pool colours: "pool", or "deep" for darker water
	var/water_look = "pool"
	/// The pool's edge: "coping", "deck", "rock" or "sand". Each has its own pool floor
	var/edge_style = "coping"
	/// Which of the edge style's three versions this tile draws, so a long edge doesn't repeat
	var/edge_variant = 1
	/// The surface, reflection mask and near edge for the current edges, swapped when they change
	var/list/pool_edge_overlays
	/// The darkening for how far the tile is from dry land, swapped when land nearby changes
	var/mutable_appearance/pool_depth_underlay
	/// The light on the pool floor, swapped when the depth changes
	var/mutable_appearance/pool_caustics
	/// Everything drawn only while there's water in the pool: rays, glints, foam, bubbles and the reflection's maps
	var/list/pool_water_overlays
	/// The waves of the pool this tile is part of
	var/datum/pool_waves/waves
	/// The colour the controller's chemicals or blood give the surface, or null for clear water
	var/pool_tint

/turf/open/pool/Initialize(mapload)
	edge_variant = (x * 7 + y * 11) % 5 % 3 + 1
	base_icon_state = "[edge_style][edge_variant]"
	icon_state = "[base_icon_state]-255"
	. = ..()
	water_effect_count(src, 1)
	underlays += get_pool_appearance(GLOB.pool_edge_floors[edge_style], POOL_FLOOR_PLANE)
	set_pool_edge_overlays(smoothing_junction || 255)
	update_depth()
	if(filled)
		add_water_overlays()
		join_pool_waves()
	// Water made after the map loaded makes the water round it redo its edges and depth, and puts what's here in it
	if(!mapload)
		resmooth_pool_around()
		for(var/mob/living/wader in src)
			make_waist_deep(wader)
		for(var/obj/item/sinking in src)
			sink_item(sinking)

/turf/open/pool/Destroy(force)
	water_effect_count(src, -1)
	waves?.remove_tile(src)
	resmooth_pool_around()
	// Anyone or anything here is out of the water now, though it didn't move. Checked once the turf has changed
	for(var/mob/living/wader in src)
		var/datum/component/pool_submerged/submerged = wader.GetComponent(/datum/component/pool_submerged)
		if(submerged)
			addtimer(CALLBACK(submerged, TYPE_PROC_REF(/datum/component/pool_submerged, check_water)), 0)
	for(var/obj/item/sinking in src)
		var/datum/component/pool_sunk/sunk = sinking.GetComponent(/datum/component/pool_sunk)
		if(sunk)
			addtimer(CALLBACK(sunk, TYPE_PROC_REF(/datum/component/pool_sunk, check_water)), 0)
	return ..()

/turf/open/pool/Entered(atom/movable/AM, atom/OldLoc)
	. = ..()
	if(!filled)
		return
	ripple_from(AM, OldLoc)
	make_waist_deep(AM)
	// Something thrown is only flying over until it lands, see hitby()
	if(isitem(AM) && !AM.throwing)
		sink_item(AM, splash = !isnull(OldLoc) && !istype(OldLoc, /turf/open/pool))

// Where a thrown thing comes down
/turf/open/pool/hitby(atom/movable/AM, skipcatch, hitpush, blocked, datum/thrownthing/throwingdatum)
	. = ..()
	// A throw can land twice, so skip things already sunk
	if(filled && isitem(AM) && AM.loc == src && !AM.GetComponent(/datum/component/pool_sunk))
		sink_item(AM, splash = TRUE)

/// Fills or drains how the pool looks: the water's surface, light, waves and reflections come and go, and so does whatever
/// is shown in the water
/turf/open/pool/proc/set_pool_filled(now_filled)
	set_pool_edge_overlays(smoothing_junction || 255)
	update_depth()
	if(now_filled)
		add_water_overlays()
		if(!waves)
			join_pool_waves()
		for(var/mob/living/wader in src)
			make_waist_deep(wader)
		for(var/obj/item/sinking in src)
			sink_item(sinking)
		return
	if(pool_water_overlays)
		cut_overlay(pool_water_overlays)
		pool_water_overlays = null
	waves?.remove_tile(src)
	for(var/mob/living/wader in src)
		qdel(wader.GetComponent(/datum/component/pool_submerged))
	for(var/obj/item/sinking in src)
		qdel(sinking.GetComponent(/datum/component/pool_sunk))

/// Tints the water's surface, for the controller's chemicals or blood
/turf/open/pool/proc/set_pool_tint(new_tint)
	if(new_tint == pool_tint)
		return
	pool_tint = new_tint
	set_pool_edge_overlays(smoothing_junction || 255)

/// Pool edge styles, and the pool bottom drawn under each
GLOBAL_LIST_INIT(pool_edge_floors, list(
	"coping" = "floor_tiles",
	"deck" = "floor_tiles",
	"rock" = "floor_stones",
	"sand" = "floor_sand",
))

/// Colour and alpha of the light on the pool floor for each look
GLOBAL_LIST_INIT(pool_caustic_colours, list(
	"pool" = list("#B0FCF0", 255),
	"deep" = list("#BEEBFF", 255),
))

/// How much of the light on the pool floor is left under 0, 1, 2 and 3 tiles of water
GLOBAL_LIST_INIT(pool_caustic_fade, list(1, 0.86, 0.72, 0.6))

/// Colour and alpha of the water's surface for each look
GLOBAL_LIST_INIT(pool_surface_colours, list(
	"pool" = list("#00BAC4", 100),
	"deep" = list("#3478BE", 125),
))

/// Gets a pool sprite appearance, made once and shared by every tile
/proc/get_pool_appearance(state, plane = FLOAT_PLANE, layer = FLOAT_LAYER, colour = null, alpha = 255)
	var/static/list/made = list()
	var/key = "[state]|[plane]|[layer]|[colour]|[alpha]"
	. = made[key]
	if(!.)
		var/mutable_appearance/appearance = mutable_appearance(POOL_WATER_ICON, state, layer, plane)
		appearance.color = colour
		appearance.alpha = alpha
		made[key] = appearance
		. = appearance

/// Gets a pool sprite state as an icon for filters, made once
/proc/get_pool_filter_icon(state)
	var/static/list/made = list()
	. = made[state]
	if(!.)
		. = made[state] = icon(POOL_WATER_ICON, state)

/// Adds what only shows with water in the pool: shafts of light, glints, foam flecks, bubbles, and the reflection's mirror map
/// and flat water for the waves to be drawn over
/turf/open/pool/proc/add_water_overlays()
	if(pool_water_overlays)
		cut_overlay(pool_water_overlays)
	var/list/light = GLOB.pool_caustic_colours[water_look]
	var/tile = "[x % 4][3 - y % 4]"
	pool_water_overlays = list(
		// Shafts of light down through the water
		get_pool_appearance("rays_[tile]", WATER_RAYS_PLANE, FLOAT_LAYER, light[1], light[2]),
		// Glints, repeating every 4x4 tiles
		get_pool_appearance("sparkle_[tile]", WATER_SHINE_PLANE),
		// Foam flecks, which only show at the water's edges and on steep waves
		get_pool_appearance("foam_[tile]", WATER_FOAM_PLANE),
		// Each tile mirrors the one above it into the water
		get_pool_appearance("mirror_map", WATER_MIRROR_PLANE),
		// Flat water for the waves to be drawn over
		get_pool_appearance("wave_flat", WATER_RIPPLE_PLANE),
	)
	// Fades the reflection with height, as a mask over the tile north of this one
	var/static/mutable_appearance/mirror_fade
	if(!mirror_fade)
		mirror_fade = mutable_appearance(POOL_WATER_ICON, "mirror_fade", FLOAT_LAYER, WATER_UNMIRRORED_PLANE)
		mirror_fade.pixel_y = world.icon_size
	pool_water_overlays += mirror_fade
	// Bubbles rise now and then on a few tiles
	if((x * 13 + y * 7) % 17 == 0)
		pool_water_overlays += get_pool_appearance("bubbles_[(x + y) % 3 + 1]", WATER_SHINE_PLANE)
	add_overlay(pool_water_overlays)

/// Sets the water surface, reflection mask and near edge to match this tile's edges
/turf/open/pool/proc/set_pool_edge_overlays(junction)
	if(pool_edge_overlays)
		cut_overlay(pool_edge_overlays)
		pool_edge_overlays = null
	var/list/new_overlays = list()
	if(filled)
		var/list/surface = GLOB.pool_surface_colours[water_look]
		var/surface_colour = pool_tint ? BlendRGB(surface[1], pool_tint, 0.6) : surface[1]
		// Over the pool floor and under mobs, who get their own water from the waist down
		new_overlays += get_pool_appearance("[base_icon_state]_water-[junction]", FLOAT_PLANE, FLOAT_LAYER, surface_colour, surface[2] + (pool_tint ? 40 : 0))
		new_overlays += get_pool_appearance("[base_icon_state]_water-[junction]", WATER_MASK_PLANE)
	// With dry land south, the near edge is drawn over anyone in the pool so their legs don't show over it
	if(!(junction & SOUTH))
		new_overlays += get_pool_appearance("[base_icon_state]_lip-[junction]", GAME_PLANE, ABOVE_MOB_LAYER + 0.01)
	add_overlay(new_overlays)
	pool_edge_overlays = new_overlays

/turf/open/pool/set_smoothed_icon_state(new_junction)
	. = ..()
	set_pool_edge_overlays(new_junction)
	update_depth()

/// Shades the water deeper the farther each corner is from dry land, and dims the floor light to match
/turf/open/pool/proc/update_depth()
	// Corners in the order the sprites are named: north west, north east, south west, south east
	var/static/list/corner_x = list(-1, 1, -1, 1)
	var/static/list/corner_y = list(1, 1, -1, -1)
	var/list/depths = list(POOL_MAX_DEPTH, POOL_MAX_DEPTH, POOL_MAX_DEPTH, POOL_MAX_DEPTH)
	for(var/turf/T as anything in RANGE_TURFS(POOL_MAX_DEPTH, src))
		if(istype(T, /turf/open/pool))
			continue
		var/dx = T.x - x
		var/dy = T.y - y
		for(var/i in 1 to 4)
			// Tiles from this corner to the near side of that tile, worked out in half tiles
			var/reach = (max(abs(2 * dx - corner_x[i]), abs(2 * dy - corner_y[i])) - 1) / 2
			if(reach < depths[i])
				depths[i] = reach
	var/mutable_appearance/new_underlay = get_pool_appearance("depth-[depths[1]][depths[2]][depths[3]][depths[4]]", POOL_FLOOR_PLANE)
	if(!filled)
		new_underlay = null
	if(new_underlay != pool_depth_underlay)
		if(pool_depth_underlay)
			underlays -= pool_depth_underlay
		if(new_underlay)
			underlays += new_underlay
		pool_depth_underlay = new_underlay
	// Light on the floor, fainter in deeper water. An overlay, so it's drawn over the depth's darkening
	var/depth = clamp(round((depths[1] + depths[2] + depths[3] + depths[4]) / 4, 1), 0, POOL_MAX_DEPTH)
	var/list/light = GLOB.pool_caustic_colours[water_look]
	var/mutable_appearance/new_caustics = filled ? get_pool_appearance("caustics_[x % 4][3 - y % 4]", POOL_FLOOR_PLANE, FLOAT_LAYER, light[1], round(light[2] * GLOB.pool_caustic_fade[depth + 1])) : null
	if(new_caustics != pool_caustics)
		if(pool_caustics)
			cut_overlay(pool_caustics)
		if(new_caustics)
			add_overlay(new_caustics)
		pool_caustics = new_caustics

/// Makes nearby pool water redo its edges and depth after this tile becomes or stops being water
/turf/open/pool/proc/resmooth_pool_around()
	for(var/turf/open/pool/W in RANGE_TURFS(POOL_MAX_DEPTH, src))
		if(W != src)
			QUEUE_SMOOTH(W)
			W.update_depth()

/// Joins this tile to the waves of the pool beside it, or starts new ones
/turf/open/pool/proc/join_pool_waves()
	var/datum/pool_waves/joined
	for(var/direction in GLOB.cardinals)
		var/turf/open/pool/beside = get_step(src, direction)
		if(!istype(beside) || !beside.waves)
			continue
		// This tile joins two pools into one
		joined = joined ? joined.merge(beside.waves) : beside.waves
	if(!joined)
		joined = new
	joined.add_tile(src)

/// Stirs the water here by `amount`, out of 1
/turf/open/pool/proc/stir_water(amount)
	waves?.stir(amount)

/// How long a ring of waves takes to cross a tile
#define WAVE_RING_TILE_TIME (0.9 SECONDS)

/// Sends a ring of waves out from this tile, bounces it off the dry edges beside it, and lifts things afloat nearby.
/// small - a smaller ring, from a step or a small thing landing
/// offset_x, offset_y - how many pixels right and up of the tile's middle the ring starts
/turf/open/pool/proc/make_wave_ring(small = FALSE, offset_x = 0, offset_y = 0)
	var/ring_type = small ? /obj/effect/temp_visual/ripple_wave/small : /obj/effect/temp_visual/ripple_wave
	var/echo_type = small ? /obj/effect/temp_visual/ripple_wave/small/echo : /obj/effect/temp_visual/ripple_wave/echo
	var/obj/effect/temp_visual/ripple_wave/ring = new ring_type(src)
	ring.pixel_x += offset_x
	ring.pixel_y += offset_y
	for(var/direction in GLOB.cardinals)
		var/turf/beside = get_step(src, direction)
		if(!beside || istype(beside, /turf/open/pool))
			continue
		// As far from the edge on that side as the ring is on this one
		var/obj/effect/temp_visual/ripple_wave/echo = new echo_type(beside)
		echo.pixel_x += (direction & (EAST | WEST)) ? -offset_x : offset_x
		echo.pixel_y += (direction & (NORTH | SOUTH)) ? -offset_y : offset_y
	var/reach = small ? 1 : 2
	for(var/datum/component/pool_sunk/afloat as anything in GLOB.pool_things_afloat)
		var/atom/movable/thing = afloat.parent
		if(thing.z != z || !isturf(thing.loc))
			continue
		var/away = get_dist(src, thing)
		// Not things on this tile, like whatever just landed and made the ring
		if(away >= 1 && away <= reach)
			addtimer(CALLBACK(afloat, TYPE_PROC_REF(/datum/component/pool_sunk, ride_wave)), away * WAVE_RING_TILE_TIME)

#undef WAVE_RING_TILE_TIME

/// Spreads ripples out from where a mob stepped into the water, with a splash if it came in from dry land
/turf/open/pool/proc/ripple_from(atom/movable/splasher, atom/old_loc)
	if(!isliving(splasher))
		return
	// Wading on. Someone waist deep leaves a wake, anyone else sends out a small ring
	if(!isturf(old_loc) || istype(old_loc, /turf/open/pool))
		stir_water(0.03)
		if(!splasher.GetComponent(/datum/component/pool_submerged))
			new /obj/effect/temp_visual/ripple_wave/small(src)
		return
	// Stepping in from dry land: a ring round their waist, a splash and a big ring of waves
	stir_water(0.2)
	new /obj/effect/temp_visual/water_ripple/waist(src)
	new /obj/effect/temp_visual/water_ripple/waist/back(src)
	new /obj/effect/temp_visual/water_splash(src)
	make_wave_ring()

/// Things that float on a pool instead of sinking
GLOBAL_LIST_INIT(pool_floaters, typecacheof(list(/obj/item/toy/beach_ball, /obj/item/bikehorn/rubberducky, /obj/item/toy/poolnoodle)))

/// Puts an item in the pool under the water, or afloat on it. With `splash` it has just hit the water, so it splashes, sends
/// out rings and goes under or bobs up
/turf/open/pool/proc/sink_item(obj/item/sinking, splash = FALSE)
	if(!filled || sinking.loc != src)
		return
	var/datum/component/pool_sunk/in_water = sinking.GetComponent(/datum/component/pool_sunk)
	if(!in_water)
		// A few things float
		in_water = sinking.AddComponent(/datum/component/pool_sunk, water_look, is_type_in_typecache(sinking, GLOB.pool_floaters), splash)
	if(!splash || !in_water)
		return
	// Where it meets the water. Bigger things make more of a splash
	var/list/meets = in_water.meets_water_at()
	var/big = sinking.w_class >= WEIGHT_CLASS_BULKY
	stir_water(big ? 0.12 : 0.06)
	var/splash_type = big ? /obj/effect/temp_visual/water_splash : /obj/effect/temp_visual/water_splash/small
	var/ring_type = big ? /obj/effect/temp_visual/water_ripple/item/big : /obj/effect/temp_visual/water_ripple/item
	for(var/obj/effect/temp_visual/effect as anything in list(new splash_type(src), new ring_type(src)))
		effect.pixel_x += meets[1]
		effect.pixel_y += meets[2]
	make_wave_ring(!big, meets[1], meets[2])
	// A second, smaller ring follows the first
	addtimer(CALLBACK(src, PROC_REF(make_wave_ring), TRUE, meets[1], meets[2]), 0.35 SECONDS)
	playsound(src, 'sound/effects/slosh.ogg', big ? 30 : 15, TRUE)

/// Makes a mob standing in a pool look waist deep in it
/turf/open/pool/proc/make_waist_deep(atom/movable/wader)
	if(filled && isliving(wader) && wader.loc == src && !(wader.movement_type & FLYING) && !wader.GetComponent(/datum/component/pool_submerged))
		wader.AddComponent(/datum/component/pool_submerged, water_look)

// ---- Reflections and the bits drawn with things in the water

/// Reflection of something standing or floating in water, flipped at its waterline. Goes in its vis_contents
/obj/effect/abstract/water_reflection
	plane = WATER_SELF_REFLECTION_PLANE
	invisibility = 0
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	// Its own plane, not its owner's (an /obj/effect in vis_contents inherits its holder's plane by default)
	vis_flags = NONE
	// The copy already has the thing's colour and transform
	appearance_flags = KEEP_APART | RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	/// TRUE if this set the thing's render_target, so it clears it again
	var/made_render_target = FALSE

/obj/effect/abstract/water_reflection/Initialize(mapload, atom/movable/reflected, waterline)
	. = ..()
	if(!reflected)
		return INITIALIZE_HINT_QDEL
	// Things with an emissive blocker already have a render target; it's used as it is
	if(!reflected.render_target)
		reflected.render_target = REF(reflected)
		made_render_target = TRUE
	render_source = reflected.render_target
	// Darker, bluer and a bit see-through. Alpha is in the matrix, BYOND ignores alpha while colour is a matrix
	color = list(0.78, 0, 0, 0, 0, 0.8, 0, 0, 0, 0, 0.86, 0, 0, 0, 0, 0.9, 0.02, 0.04, 0.08, 0)
	// Flipped at the waterline, `waterline` pixels up from the bottom of the sprite
	transform = matrix(1, 0, 0, 0, -1, 2 * waterline - world.icon_size)

/// Takes back the render_target this gave the thing, once it's out of the water
/obj/effect/abstract/water_reflection/proc/stop_reflecting(atom/movable/reflected)
	if(made_render_target && reflected && reflected.render_target == REF(reflected))
		reflected.render_target = null

/// A water sprite drawn with something in the pool, in its vis_contents
/obj/effect/abstract/waterline
	icon = POOL_WATER_ICON
	invisibility = 0
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	// On its owner's plane, and clicks on it go to its owner
	vis_flags = VIS_INHERIT_PLANE | VIS_INHERIT_ID

/obj/effect/abstract/waterline/Initialize(mapload, state)
	. = ..()
	icon_state = state

/// Makes a block for a thing's vis_contents that keeps it out of the reflection plane's mirror
/proc/make_unmirrored_block()
	var/obj/effect/abstract/waterline/block = new(null, "mask")
	block.vis_flags = VIS_INHERIT_ID
	block.plane = WATER_UNMIRRORED_PLANE
	return block

// ---- Rings, splashes, wakes and footprints

/// A ring spreading out on water where something touched it
/obj/effect/temp_visual/water_ripple
	icon = POOL_WATER_ICON
	icon_state = "ripple"
	layer = ABOVE_MOB_LAYER + 0.05
	duration = 0.9 SECONDS
	randomdir = FALSE
	// At the feet of whoever made it
	pixel_y = -6
	/// Size it grows to before it's gone, 1 is a tile across
	var/final_scale = 1.15

/obj/effect/temp_visual/water_ripple/Initialize(mapload)
	. = ..()
	transform = matrix(0.3, 0, 0, 0, 0.3, 0)
	animate(src, transform = matrix(final_scale, 0, 0, 0, final_scale, 0), alpha = 0, time = duration, easing = SINE_EASING | EASE_OUT)

/// Smaller ring where an item lands in the water. On the shine plane, so it's cut to the water and under the thing that made it
/obj/effect/temp_visual/water_ripple/item
	plane = WATER_SHINE_PLANE
	pixel_y = 0
	final_scale = 0.75

/// Ring for something big
/obj/effect/temp_visual/water_ripple/item/big
	final_scale = 1.1

/// The half of a ripple round a mob's waist that's in front of it
/obj/effect/temp_visual/water_ripple/waist
	icon_state = "ripple_front"
	layer = MOB_LAYER + 0.02
	// Puts the middle of the ring at the mob's waist
	pixel_y = -4

/// The half behind the mob
/obj/effect/temp_visual/water_ripple/waist/back
	icon_state = "ripple_back"
	layer = MOB_LAYER - 0.02

/// A ring of waves on the hidden ripple plane, which bends the floor, reflections and glints as it spreads
/obj/effect/temp_visual/ripple_wave
	icon = 'hippiestation/icons/effects/water_ripple_wave.dmi'
	icon_state = "wave"
	plane = WATER_RIPPLE_PLANE
	duration = 1.1 SECONDS
	randomdir = FALSE
	// The sprite is 3x3 tiles with the touch in the middle
	pixel_x = -32
	pixel_y = -32

/// A smaller ring, from a step or something small landing
/obj/effect/temp_visual/ripple_wave/small

/obj/effect/temp_visual/ripple_wave/small/Initialize(mapload)
	. = ..()
	transform = matrix(0.6, 0, 0, 0, 0.6, 0)

/// A fainter ring bounced back off the water's edge, see make_wave_ring()
/obj/effect/temp_visual/ripple_wave/echo
	alpha = 150

/obj/effect/temp_visual/ripple_wave/small/echo
	alpha = 150

/// Bubbles coming up where something has just sunk
/obj/effect/temp_visual/sink_bubbles
	icon = POOL_WATER_ICON
	icon_state = "sink_bubbles"
	plane = WATER_SHINE_PLANE
	duration = 1.7 SECONDS
	randomdir = FALSE

/// Droplets thrown up when someone jumps into the water
/obj/effect/temp_visual/water_splash
	icon = null
	layer = ABOVE_MOB_LAYER + 0.06
	randomdir = FALSE
	/// The droplets it throws up
	var/splash_type = /particles/water_splash

/// The few droplets from something small landing in the water
/obj/effect/temp_visual/water_splash/small
	splash_type = /particles/water_splash/small

/obj/effect/temp_visual/water_splash/Initialize(mapload)
	. = ..()
	particles = new splash_type
	// One burst, then the droplets already in the air fall back
	addtimer(CALLBACK(src, PROC_REF(stop_spawning)), 0.1 SECONDS)

/obj/effect/temp_visual/water_splash/Destroy()
	QDEL_NULL(particles)
	return ..()

/obj/effect/temp_visual/water_splash/proc/stop_spawning()
	particles?.spawning = 0

/// V wake of foam and waves left on the tile someone waded out of
/obj/effect/temp_visual/water_wake
	icon = POOL_WATER_ICON
	icon_state = "wake"
	// On the shine plane, so it's cut to the water and lies on top of it
	plane = WATER_SHINE_PLANE
	duration = 1.6 SECONDS
	randomdir = FALSE

/obj/effect/temp_visual/water_wake/Initialize(mapload, direction)
	. = ..()
	setDir(direction)
	// The waves are an overlay, so they turn with the wake
	var/static/mutable_appearance/waves
	if(!waves)
		waves = mutable_appearance('hippiestation/icons/effects/water_ripple_wave.dmi', "wake", FLOAT_LAYER, WATER_RIPPLE_PLANE)
		// The sprite is 3x3 tiles with this tile in the middle
		waves.pixel_x = -32
		waves.pixel_y = -32
	add_overlay(waves)
	animate(src, alpha = 0, transform = matrix(1.25, 0, 0, 0, 1.25, 0), time = duration, easing = SINE_EASING | EASE_OUT)

/// Wet footprints left by someone who's just climbed out of the water. They dry up.
/obj/effect/temp_visual/wet_footprints
	icon = POOL_WATER_ICON
	icon_state = "wet_footprints"
	layer = LOW_OBJ_LAYER
	duration = 8 SECONDS
	randomdir = FALSE

/obj/effect/temp_visual/wet_footprints/Initialize(mapload, direction)
	. = ..()
	setDir(direction)
	animate(src, alpha = 0, time = duration, easing = SINE_EASING | EASE_IN)

/// Droplets thrown up when something goes into the water. The splash effect stops it after one burst
/particles/water_splash
	icon = POOL_WATER_ICON
	icon_state = "droplet"
	width = 96
	height = 96
	count = 16
	spawning = 16
	lifespan = 0.7 SECONDS
	fade = 0.3 SECONDS
	position = generator("box", list(-6, -6), list(6, -2))
	velocity = generator("box", list(-16, 26), list(16, 46))
	gravity = list(0, -90)

/// A few droplets from something small landing in the water
/particles/water_splash/small
	count = 6
	spawning = 6
	position = generator("box", list(-3, -5), list(3, -2))
	velocity = generator("box", list(-10, 18), list(10, 32))

/// Drips falling off someone who's just climbed out of the water
/particles/water_drip
	icon = POOL_WATER_ICON
	icon_state = "drip"
	width = 64
	height = 64
	count = 6
	spawning = 0.25
	lifespan = 0.5 SECONDS
	fade = 0.2 SECONDS
	position = generator("box", list(-6, -6), list(6, 6))
	velocity = list(0, -12)
	gravity = list(0, -60)
