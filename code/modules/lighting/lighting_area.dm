/area
	luminosity           = TRUE
	var/dynamic_lighting = DYNAMIC_LIGHTING_ENABLED
	///When not dynamically lit, glow the starlight color instead of plain white (tgstation's base_lighting_color = COLOR_STARLIGHT)
	var/uses_starlight = FALSE
	///Our current starlight-tinted fullbright overlay, if we have one
	var/mutable_appearance/starlight_effect

///Lights the whole area up, for when it isn't dynamically lit
/area/proc/add_fullbright()
	if(!uses_starlight || !CONFIG_GET(flag/starlight))
		add_overlay(/obj/effect/fullbright)
		return
	// Can't mirror the starlight render target like space turfs do - render_source doesn't work in area overlays (as tg
	// found) - so set_starlight() swaps this overlay by hand when the color changes
	starlight_effect = make_area_starlight(GLOB.starlight_color)
	add_overlay(starlight_effect)
	GLOB.starlit_areas |= src

/area/proc/remove_fullbright()
	cut_overlay(/obj/effect/fullbright)
	if(starlight_effect)
		cut_overlay(starlight_effect)
		starlight_effect = null
		GLOB.starlit_areas -= src

/area/proc/starlight_changed(star_color)
	if(!starlight_effect)
		return
	cut_overlay(starlight_effect)
	starlight_effect = make_area_starlight(star_color)
	add_overlay(starlight_effect)

/area/proc/set_dynamic_lighting(var/new_dynamic_lighting = DYNAMIC_LIGHTING_ENABLED)
	if (new_dynamic_lighting == dynamic_lighting)
		return FALSE

	dynamic_lighting = new_dynamic_lighting

	if (IS_DYNAMIC_LIGHTING(src))
		remove_fullbright()
		for (var/turf/T in src)
			if (IS_DYNAMIC_LIGHTING(T))
				T.lighting_build_overlay()

	else
		add_fullbright()
		for (var/turf/T in src)
			if (T.lighting_object)
				T.lighting_clear_overlay()

	return TRUE

/area/vv_edit_var(var_name, var_value)
	switch(var_name)
		if("dynamic_lighting")
			set_dynamic_lighting(var_value)
			return TRUE
	return ..()