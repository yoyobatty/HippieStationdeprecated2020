// The planes pool water is drawn with, and the switch that turns them on only for players near a pool: each costs a full screen
// pass every frame, even with no water on screen. From Paradise (pool-water); here the filters are plain lists, set when the
// water effects come on and cleared when they go off.

/obj/screen/plane_master
	/// Are this plane's filters part of the water effects, which are off for players away from water?
	var/water_effect = FALSE
	/// Is this plane only there for the water effects, so it's see-through while they're off?
	var/water_effect_only = FALSE
	/// Is this plane taken off the screen while the water effects are off, to save its full screen pass?
	var/water_effect_removable = FALSE

/// The filters this plane has while the water effects are on
/obj/screen/plane_master/proc/water_filters()
	return null

/// Turns this plane's part of the water effects on or off
/obj/screen/plane_master/proc/set_water_effects(on)
	if(water_effect)
		filters = on ? water_filters() : null
	if(water_effect_only)
		alpha = on ? 255 : 0

/obj/screen/plane_master/water_mask
	name = "water mask plane master"
	plane = WATER_MASK_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_MASK_RENDER_TARGET

/obj/screen/plane_master/water_ripple
	name = "water ripple plane master"
	plane = WATER_RIPPLE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_RIPPLE_RENDER_TARGET

/obj/screen/plane_master/water_mirror
	name = "water mirror plane master"
	plane = WATER_MIRROR_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_MIRROR_RENDER_TARGET

/// The waves over whatever is under the water, used to bend it on the game world plane
/obj/screen/plane_master/water_refract
	name = "water refraction plane master"
	plane = WATER_REFRACT_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_REFRACT_RENDER_TARGET
	water_effect = TRUE
	water_effect_only = TRUE

/obj/screen/plane_master/water_refract/water_filters()
	// Only in the water, so the pool's near edge over a swimmer's legs isn't bent; the ripple map, only where those things are
	return list(
		filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET),
		filter(type = "layer", render_source = WATER_RIPPLE_RENDER_TARGET, blend_mode = BLEND_INSET_OVERLAY),
	)

/// Where things in the water are, for the reflection plane to leave out. The tile mirror would put their reflection too low, so
/// each has its own /obj/effect/abstract/water_reflection
/obj/screen/plane_master/water_unmirrored
	name = "water unmirrored plane master"
	plane = WATER_UNMIRRORED_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_UNMIRRORED_RENDER_TARGET
	water_effect = TRUE
	water_effect_only = TRUE

/// How much of a mirror the water is: wave sides sloping away from the viewer reflect, the others show the floor
/obj/screen/plane_master/water_fresnel
	name = "water fresnel plane master"
	plane = WATER_FRESNEL_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_FRESNEL_RENDER_TARGET
	water_effect = TRUE
	water_effect_only = TRUE

/obj/screen/plane_master/water_fresnel/water_filters()
	// Mirror strength is 0.55 + 1.5 * the slope up the screen, away from the viewer.
	// The ripple map's green is 0.502 + 0.498 * the slope down the screen
	return list(
		filter(type = "layer", render_source = WATER_RIPPLE_RENDER_TARGET),
		filter(type = "color", color = list(0, 0, 0, 0, 0, 0, 0, -3.012, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2.062)),
	)

/// Reflections of things in the water, see /obj/effect/abstract/water_reflection
/obj/screen/plane_master/water_self_reflection
	name = "water self reflection plane master"
	plane = WATER_SELF_REFLECTION_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_SELF_REFLECTION_RENDER_TARGET
	water_effect = TRUE
	water_effect_only = TRUE

/// Puts the reflections back over swimmers' legs and sunk things, which the game world plane draws over the water
/obj/screen/plane_master/water_over
	name = "water over plane master"
	plane = WATER_OVER_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	water_effect = TRUE
	water_effect_only = TRUE
	water_effect_removable = TRUE

/obj/screen/plane_master/water_over/water_filters()
	return list(
		filter(type = "layer", render_source = WATER_REFLECTION_RENDER_TARGET),
		// Only where something is under the water, more the deeper it is
		filter(type = "alpha", render_source = WATER_REFRACT_RENDER_TARGET),
		// And only over the things themselves. The water round them has its reflections already
		filter(type = "alpha", render_source = GAME_PLANE_RENDER_TARGET),
	)

/obj/screen/plane_master/pool_floor
	name = "pool floor plane master"
	plane = POOL_FLOOR_PLANE
	appearance_flags = PLANE_MASTER
	water_effect = TRUE

/obj/screen/plane_master/pool_floor/water_filters()
	// The floor bends under the ripples
	return list(filter(type = "displace", render_source = WATER_RIPPLE_RENDER_TARGET, size = POOL_REFRACTION))

/obj/screen/plane_master/water_edge
	name = "water edge plane master"
	plane = WATER_EDGE_PLANE
	appearance_flags = PLANE_MASTER

/obj/screen/plane_master/water_rays
	name = "water rays plane master"
	plane = WATER_RAYS_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	blend_mode = BLEND_ADD
	water_effect = TRUE
	water_effect_removable = TRUE
	water_effect_only = TRUE

/obj/screen/plane_master/water_rays/water_filters()
	// Shafts of light only show in the water
	return list(filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET))

/obj/screen/plane_master/water_reflection
	name = "water reflection plane master"
	plane = WATER_REFLECTION_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	water_effect = TRUE
	water_effect_removable = TRUE
	water_effect_only = TRUE
	// Read by the water over plane
	render_target = WATER_REFLECTION_RENDER_TARGET

/obj/screen/plane_master/water_reflection/water_filters()
	return list(
		// A copy of the world: walls, machines, items and mobs
		filter(type = "layer", render_source = GAME_PLANE_RENDER_TARGET),
		// Lit screens and lamps, added on so they reflect as bright spots
		filter(type = "layer", render_source = EMISSIVE_RENDER_TARGET, blend_mode = BLEND_ADD),
		// Not what's in the water. It has its own reflection at its waterline, or none if it's on the bottom
		filter(type = "alpha", render_source = WATER_UNMIRRORED_RENDER_TARGET, flags = MASK_INVERSE),
		// A reflection is a little darker and bluer than the thing itself
		filter(type = "color", color = list(0.78, 0, 0, 0, 0, 0.8, 0, 0, 0, 0, 0.86, 0, 0, 0, 0, 0.9, 0.02, 0.04, 0.08, 0)),
		// Each water tile shows the tile above it upside down
		filter(type = "displace", render_source = WATER_MIRROR_RENDER_TARGET, size = POOL_MIRROR_REACH),
		// After the mirror, since these reflections are already flipped and in place
		filter(type = "layer", render_source = WATER_SELF_REFLECTION_RENDER_TARGET),
		// Then the waves bend it
		filter(type = "displace", render_source = WATER_RIPPLE_RENDER_TARGET, size = POOL_REFLECTION_RIPPLE),
		// A reflection only shows where there is water under it
		filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET),
		// And only as much as the water is a mirror there
		filter(type = "alpha", render_source = WATER_FRESNEL_RENDER_TARGET),
		// Bright things in it, like lamps, glow
		filter(type = "bloom", threshold = "#A0A0A0", size = 3, offset = 1, alpha = 170),
	)

/// Darkens the sides of the waves facing away from a light up and to the left. Under the lighting plane, so a dark room or a
/// coloured lamp changes it too
/obj/screen/plane_master/water_relief_shade
	name = "water relief shade plane master"
	plane = WATER_RELIEF_SHADE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	blend_mode = BLEND_MULTIPLY
	water_effect = TRUE
	water_effect_removable = TRUE
	water_effect_only = TRUE

/obj/screen/plane_master/water_relief_shade/water_filters()
	// 1 + 0.18 * (how much it faces the light), so lit sides come out white and the multiply leaves them alone.
	// Blue darkens less, so shade goes deeper blue, not grey
	return list(
		filter(type = "layer", render_source = WATER_RIPPLE_RENDER_TARGET),
		filter(type = "color", color = list(-0.216, -0.216, -0.144, 0, -0.288, -0.288, -0.192, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1.252, 1.252, 1.168, 0)),
		filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET),
	)

/obj/screen/plane_master/water_relief_light
	name = "water relief light plane master"
	plane = WATER_RELIEF_LIGHT_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	blend_mode = BLEND_ADD
	water_effect = TRUE
	water_effect_removable = TRUE
	water_effect_only = TRUE
	// The specular plane uses it to find the sides of the waves that catch the light
	render_target = WATER_RELIEF_LIGHT_RENDER_TARGET

/obj/screen/plane_master/water_relief_light/water_filters()
	// Pale light, as strong as 0.18 * (how much it faces the light)
	return list(
		filter(type = "layer", render_source = WATER_RIPPLE_RENDER_TARGET),
		filter(type = "color", color = list(0, 0, 0, -0.216, 0, 0, 0, -0.288, 0, 0, 0, 0, 0, 0, 0, 0, 0.85, 0.97, 1, 0.252)),
		filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET),
	)

/// Glints in the colour of the light on the water, drawn over the lighting by the above lighting plane
/obj/screen/plane_master/water_specular
	name = "water specular plane master"
	plane = WATER_SPECULAR_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_SPECULAR_RENDER_TARGET
	water_effect = TRUE
	water_effect_only = TRUE

/obj/screen/plane_master/water_specular/water_filters()
	return list(
		// The light on each pixel, minus dim light so only well lit water glints
		filter(type = "layer", render_source = LIGHTING_RENDER_TARGET),
		filter(type = "color", color = list(1.4, 0, 0, 0, 0, 1.4, 0, 0, 0, 0, 1.4, 0, 0, 0, 0, 1, -0.35, -0.35, -0.35, 0)),
		// Only on wave sides facing the light, and only on water. 4 * face - 0.08 keeps it to the steeper part of each face
		filter(type = "alpha", render_source = WATER_RELIEF_LIGHT_RENDER_TARGET),
		filter(type = "color", color = list(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 4, 0, 0, 0, -0.08)),
		filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET),
		// Not over things in or beside the water, since it's drawn over the whole world
		filter(type = "alpha", render_source = GAME_PLANE_RENDER_TARGET, flags = MASK_INVERSE),
		// The brightest glints glow a little
		filter(type = "bloom", threshold = "#D0D0D0", size = 2, offset = 0, alpha = 120),
	)

/// Adds the water's glints over the lighting, while the water effects are on
/obj/screen/water_glint_relay
	screen_loc = "SOUTHWEST"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	plane = ABOVE_LIGHTING_PLANE
	layer = ABOVE_LIGHTING_LAYER + 0.05
	blend_mode = BLEND_ADD
	render_source = WATER_SPECULAR_RENDER_TARGET
	appearance_flags = PASS_MOUSE | NO_CLIENT_COLOR

/obj/screen/plane_master/water_edge_band
	name = "water edge band plane master"
	plane = WATER_EDGE_BAND_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_EDGE_BAND_RENDER_TARGET
	water_effect = TRUE
	water_effect_only = TRUE

/obj/screen/plane_master/water_edge_band/water_filters()
	// The water mask blurred and inverted: a band along each edge, gone a few pixels in. 0.9 * (1 - water)
	return list(
		filter(type = "layer", render_source = WATER_MASK_RENDER_TARGET),
		filter(type = "blur", size = 4),
		filter(type = "color", color = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -0.9, 1, 1, 1, 0.9)),
	)

/obj/screen/plane_master/water_foam_drive
	name = "water foam drive plane master"
	plane = WATER_FOAM_DRIVE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = WATER_FOAM_DRIVE_RENDER_TARGET
	water_effect = TRUE
	water_effect_only = TRUE

/obj/screen/plane_master/water_foam_drive/water_filters()
	// White where a wave is steep and faces the light, nothing on calm water. 6.5 * (how much it faces the light) - 3. And the
	// band along the water's edges, where it always laps a little
	return list(
		filter(type = "layer", render_source = WATER_RIPPLE_RENDER_TARGET),
		filter(type = "color", color = list(0, 0, 0, -7.8, 0, 0, 0, -10.4, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 6.1)),
		filter(type = "layer", render_source = WATER_EDGE_BAND_RENDER_TARGET),
	)

/// Foam flecks are drawn all over the water and only show where the foam drive plane lets them
/obj/screen/plane_master/water_foam
	name = "water foam plane master"
	plane = WATER_FOAM_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	water_effect = TRUE
	water_effect_only = TRUE
	water_effect_removable = TRUE

/obj/screen/plane_master/water_foam/water_filters()
	return list(
		// Foam rides the waves
		filter(type = "displace", render_source = WATER_RIPPLE_RENDER_TARGET, size = POOL_REFRACTION),
		filter(type = "alpha", render_source = WATER_FOAM_DRIVE_RENDER_TARGET),
		filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET),
	)

/obj/screen/plane_master/water_shine
	name = "water shine plane master"
	plane = WATER_SHINE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	water_effect = TRUE
	water_effect_removable = TRUE

/obj/screen/plane_master/water_shine/water_filters()
	return list(
		// Glints bend with the waves and rings
		filter(type = "displace", render_source = WATER_RIPPLE_RENDER_TARGET, size = POOL_REFRACTION),
		// Ripples and glints only show over water
		filter(type = "alpha", render_source = WATER_MASK_RENDER_TARGET),
		// And the brightest glints glow a little
		filter(type = "bloom", threshold = "#F2F2F2", size = 1, offset = 0, alpha = 110),
	)

// The game world bends where the water's over it (swimmers' legs, sunk things), while the water effects are on
/obj/screen/plane_master/game_world/backdrop(mob/mymob)
	. = ..()
	if(mymob?.hud_used?.water_effects_on)
		filters += filter(type = "displace", render_source = WATER_REFRACT_RENDER_TARGET, size = POOL_REFRACTION)

// ---- Only near water

/datum/hud
	/// Are the water effects on for this hud? The watcher below turns them on near a pool
	var/water_effects_on = FALSE
	/// The glints over the lighting, on screen while the water effects are on
	var/obj/screen/water_glint_relay/water_glints

/datum/hud/Destroy()
	QDEL_NULL(water_glints)
	return ..()

/datum/hud/proc/set_water_effects(on)
	water_effects_on = on
	var/client/viewer = mymob?.client
	for(var/plane in plane_masters)
		var/obj/screen/plane_master/master = plane_masters[plane]
		if(!master.water_effect)
			continue
		master.set_water_effects(on)
		if(on && master.water_effect_removable)
			viewer?.screen |= master
	if(!water_glints)
		water_glints = new
	if(on)
		viewer?.screen |= water_glints
	else
		viewer?.screen -= water_glints
		remove_water_planes()
	// The game world bends under the water, while there's water about
	var/obj/screen/plane_master/game_world = plane_masters["[GAME_PLANE]"]
	game_world?.backdrop(mymob)

/// Takes the shown water planes off the player's screen, since each costs a full screen pass every frame
/datum/hud/proc/remove_water_planes()
	var/client/viewer = mymob?.client
	if(!viewer)
		return
	for(var/plane in plane_masters)
		var/obj/screen/plane_master/master = plane_masters[plane]
		if(master.water_effect_removable)
			viewer.screen -= master

/// Pool water tiles per map chunk, a list of counts for each z-level, like heat_haze.dm's
GLOBAL_LIST_EMPTY(water_effect_chunks)
GLOBAL_DATUM(water_effects_watcher, /datum/water_effects_watcher)

#define WATER_EFFECT_CHUNK 16

/proc/water_effect_count(turf/T, change)
	if(!T?.z)
		return
	if(GLOB.water_effect_chunks.len < T.z)
		GLOB.water_effect_chunks.len = T.z
	var/list/counts = GLOB.water_effect_chunks[T.z]
	var/wide = CEILING(world.maxx / WATER_EFFECT_CHUNK, 1)
	if(!counts)
		counts = new /list(wide * CEILING(world.maxy / WATER_EFFECT_CHUNK, 1))
		GLOB.water_effect_chunks[T.z] = counts
	var/index = round((T.x - 1) / WATER_EFFECT_CHUNK) + round((T.y - 1) / WATER_EFFECT_CHUNK) * wide + 1
	counts[index] = max(0, counts[index] + change)
	if(change > 0 && !GLOB.water_effects_watcher)
		GLOB.water_effects_watcher = new

/// Is there pool water in T's chunk or the ones round it? That reaches a little past a player's screen, so the effects are on
/// before any water comes into view.
/proc/water_effects_near(turf/T)
	if(!T || GLOB.water_effect_chunks.len < T.z)
		return FALSE
	var/list/counts = GLOB.water_effect_chunks[T.z]
	if(!counts)
		return FALSE
	var/wide = CEILING(world.maxx / WATER_EFFECT_CHUNK, 1)
	var/high = counts.len / wide
	var/cx = round((T.x - 1) / WATER_EFFECT_CHUNK)
	var/cy = round((T.y - 1) / WATER_EFFECT_CHUNK)
	for(var/y in max(cy - 1, 0) to min(cy + 1, high - 1))
		for(var/x in max(cx - 1, 0) to min(cx + 1, wide - 1))
			if(counts[x + y * wide + 1])
				return TRUE
	return FALSE

#undef WATER_EFFECT_CHUNK

/// Turns the water effects on for players near water and off for everyone else, once a second
/datum/water_effects_watcher

/datum/water_effects_watcher/New()
	START_PROCESSING(SSprocessing, src)

/datum/water_effects_watcher/process()
	for(var/client/C as anything in GLOB.clients)
		var/datum/hud/hud = C.mob?.hud_used
		if(!hud)
			continue
		var/near = !!water_effects_near(get_turf(C.eye))
		if(near != hud.water_effects_on)
			hud.set_water_effects(near)
		else if(!near)
			// Showing the hud again puts every plane master back on the screen
			hud.remove_water_planes()

// A new hud starts with the effects off: its water planes come off the screen at once, not a second later
/datum/hud/plane_masters_update()
	. = ..()
	if(!water_effects_on)
		for(var/plane in plane_masters)
			var/obj/screen/plane_master/master = plane_masters[plane]
			if(master.water_effect)
				master.set_water_effects(FALSE)
		remove_water_planes()

// ---- Filters by name, as tg has them later

/// Takes the filters with these names off
/atom/movable/proc/remove_filter(name_or_names)
	if(!filter_data)
		return
	var/list/names = islist(name_or_names) ? name_or_names : list(name_or_names)
	var/found = FALSE
	for(var/name in names)
		if(filter_data[name])
			filter_data -= name
			found = TRUE
	if(found)
		update_filters()
