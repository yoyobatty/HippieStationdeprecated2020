SUBSYSTEM_DEF(lighting)
	name = "Lighting"
	wait = 2
	init_order = INIT_ORDER_LIGHTING
	flags = SS_TICKER
	var/static/list/sources_queue = list() // List of lighting sources queued for update.
	var/static/list/corners_queue = list() // List of lighting corners queued for update.
	var/static/list/objects_queue = list() // List of lighting objects queued for update.
	/// Whether lights spill bounce light into the shadows around what they light (see LIGHTING_BOUNCE_STRENGTH). Set by the BOUNCE_LIGHTING config.
	var/bounce_lighting = FALSE
	// How bounce light behaves (see the LIGHTING_BOUNCE_ defines they start as). Edit them with View Variables to tune
	// bounce lighting live: vv_edit_var() keeps them in bounds and relights everything.
	/// How much of the light on a lit tile's edge spills across it into a shadowed tile, 0 to 1
	var/bounce_strength = LIGHTING_BOUNCE_STRENGTH
	/// How much of that carries on into each tile further into the shadow, 0 to 0.6
	var/bounce_falloff = LIGHTING_BOUNCE_FALLOFF
	/// How many tiles deep into a shadow the light can spill, 1 to 6
	var/bounce_depth = LIGHTING_BOUNCE_DEPTH
	/// Spill dimmer than this is dropped
	var/bounce_cutoff = LIGHTING_BOUNCE_CUTOFF
	/// How much of what an angled light would light all around it scatters back off what it does light, 0 to 1
	var/cone_scatter = LIGHTING_CONE_SCATTER
	/// How far past its range a light reaches as its falloff eases off, as a multiple of its range, 1 to 2 (see LIGHTING_FALLOFF_TAIL)
	var/falloff_tail = LIGHTING_FALLOFF_TAIL
	/// The number of the latest light source update, which marks the corners and turfs it goes through: see /datum/light_source/proc/update_corners()
	var/lighting_stamp = 0

/datum/controller/subsystem/lighting/stat_entry()
	..("L:[length(sources_queue)]|C:[length(corners_queue)]|O:[length(objects_queue)]")


/datum/controller/subsystem/lighting/Initialize(timeofday)
	if(!initialized)
		bounce_lighting = CONFIG_GET(flag/bounce_lighting)
		if (CONFIG_GET(flag/starlight))
			for(var/I in GLOB.sortedAreas)
				var/area/A = I
				if (A.dynamic_lighting == DYNAMIC_LIGHTING_IFSTARLIGHT)
					A.luminosity = 0

		create_all_lighting_objects()
		if (CONFIG_GET(flag/starlight)) // starlit areas glow throughout, not just at the hull - see update_starlight()
			for(var/area/A as anything in GLOB.sortedAreas)
				if (initial(A.dynamic_lighting) == DYNAMIC_LIGHTING_IFSTARLIGHT)
					for(var/turf/open/space/S in A)
						S.enable_starlight()
		initialized = TRUE

	fire(FALSE, TRUE)

	return ..()

/datum/controller/subsystem/lighting/fire(resumed, init_tick_checks)
	MC_SPLIT_TICK_INIT(3)
	if(!init_tick_checks)
		MC_SPLIT_TICK
	var/list/queue = sources_queue
	var/i = 0
	while(i < length(queue)) //we don't use a for loop here because i cannot be changed during an iteration
		i += 1

		var/datum/light_source/L = queue[i]
		// Destroyed since it was queued up and queued up again, or hard deleted since, leaving a null: there's nothing
		// left to update, and its Destroy() won't be taking it off the queue for us - taken as it had, below, we'd go
		// round on it forever
		if(QDELETED(L))
			queue.Cut(i, i + 1)
			i -= 1
			continue

		L.update_corners()
		if(!QDELETED(L))
			L.needs_update = LIGHTING_NO_UPDATE
		else
			i -= 1 // update_corners() has removed L from the list, move back so we don't overflow or skip the next element

		if(init_tick_checks)
			CHECK_TICK
		else if (MC_TICK_CHECK)
			break
	if (i)
		queue.Cut(1, i+1)
		i = 0

	if(!init_tick_checks)
		MC_SPLIT_TICK

	queue = corners_queue
	i = 0
	while(i < length(queue)) //we don't use a for loop here because i cannot be changed during an iteration
		i += 1

		var/datum/lighting_corner/C = queue[i]
		C.needs_update = FALSE //update_objects() can call qdel if the corner is storing no data
		C.update_objects()

		if(init_tick_checks)
			CHECK_TICK
		else if (MC_TICK_CHECK)
			break
	if (i)
		queue.Cut(1, i+1)
		i = 0


	if(!init_tick_checks)
		MC_SPLIT_TICK

	queue = objects_queue
	for (i in 1 to length(queue))
		var/atom/movable/lighting_object/O = queue[i]

		if (QDELETED(O))
			continue

		O.update()
		O.needs_update = FALSE
		if(init_tick_checks)
			CHECK_TICK
		else if (MC_TICK_CHECK)
			break
	if (i)
		queue.Cut(1, i+1)


/// Turns bounce lighting on or off, relighting everything
/datum/controller/subsystem/lighting/proc/set_bounce_lighting(enabled)
	enabled = !!enabled
	if (enabled == bounce_lighting)
		return
	bounce_lighting = enabled
	relight_all()

/// Makes every light source work its light out afresh
/datum/controller/subsystem/lighting/proc/relight_all()
	for (var/datum/light_source/L)
		if (!QDELETED(L))
			L.force_update()

/// Starts SSlighting.lighting_stamp over, clearing it off every corner and turf it's marked, so nothing looks marked by
/// an update it wasn't. Takes a moment, but only happens every LIGHTING_STAMP_LIMIT light source updates.
/datum/controller/subsystem/lighting/proc/reset_lighting_stamps()
	for (var/datum/lighting_corner/C)
		C.lighting_stamp = 0
		C.bounce_stamp = 0
	for (var/turf/T in world)
		T.lighting_stamp = 0
	lighting_stamp = 1
	return lighting_stamp

/datum/controller/subsystem/lighting/vv_edit_var(var_name, var_value)
	var/relight = bounce_lighting // bounce light's settings only change anything with it on
	switch (var_name)
		// Kept to what the lighting bench's falloff check passes at: any stronger, and light spills out brighter than it
		// went in, or wraps so far around walls undimmed that it glows past a dark band where its source's light ends
		if (NAMEOF(src, bounce_strength))
			var_value = clamp(text2num("[var_value]"), 0, 1)
		if (NAMEOF(src, bounce_falloff)) // 0.75 was fine, until the soft falloff let light reach out a little further
			var_value = clamp(text2num("[var_value]"), 0, 0.6)
		if (NAMEOF(src, bounce_depth))
			var_value = clamp(round(text2num("[var_value]")), 1, 6)
		if (NAMEOF(src, bounce_cutoff))
			var_value = clamp(text2num("[var_value]"), 0.001, 1)
		if (NAMEOF(src, cone_scatter))
			var_value = clamp(text2num("[var_value]"), 0, 1)
		if (NAMEOF(src, falloff_tail))
			var_value = clamp(text2num("[var_value]"), 1, 2)
			relight = TRUE
		else
			return ..()
	. = ..()
	if (. && relight)
		relight_all()

/datum/controller/subsystem/lighting/Recover()
	initialized = SSlighting.initialized
	bounce_lighting = SSlighting.bounce_lighting
	bounce_strength = SSlighting.bounce_strength
	bounce_falloff = SSlighting.bounce_falloff
	bounce_depth = SSlighting.bounce_depth
	bounce_cutoff = SSlighting.bounce_cutoff
	cone_scatter = SSlighting.cone_scatter
	falloff_tail = SSlighting.falloff_tail
	lighting_stamp = SSlighting.lighting_stamp
	..()
