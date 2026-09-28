
/atom
	var/light_power = 1 // Intensity of the light.
	var/light_range = 0 // Range in tiles of the light.
	var/light_color     // Hexadecimal RGB string representing the colour of the light.
	/// What direction our angled light is pointed. NONE for omnidirectional lights.
	var/light_dir = NONE
	/// How many degrees of a circle should our light show. 360 is all of it (omnidirectional), 180 is a half-circle cone, etc.
	var/light_angle = 360
	/// Whether our angled light points the way we're facing - or whoever's holding or wearing us is - instead of light_dir.
	/// Lying loose, we keep pointing where we were left facing.
	var/light_follows_facing = FALSE
	/// The height of the light source on the pseudo-z-axis. The larger this is, the dimmer/softer the light starts out.
	var/light_height = LIGHTING_HEIGHT
	/// Whether our light spills into the shadows around what it lights, when bounce lighting is on (see LIGHTING_BOUNCE_STRENGTH)
	var/light_bounce = TRUE
	/// Whether our light eases off softly past its range, rather than falling off in a straight line to it (see LIGHTING_FALLOFF_TAIL)
	var/light_falloff_tail = TRUE

	var/tmp/datum/light_source/light // Our light source. Don't fuck with this directly unless you have a good reason!
	var/tmp/list/light_sources       // Any light sources that are "inside" of us, for example, if src here was a mob that's carrying a flashlight, that flashlight's light source would be part of this list.

// The proc you should always use to set the light of this atom.
// Nonesensical value for l_color default, so we can detect if it gets set to null.
#define NONSENSICAL_VALUE -99999
/atom/proc/set_light(var/l_range, var/l_power, var/l_color = NONSENSICAL_VALUE, l_on, l_angle, l_dir, l_height)
	if(l_range > 0 && l_range < MINIMUM_USEFUL_LIGHT_RANGE)
		l_range = MINIMUM_USEFUL_LIGHT_RANGE	//Brings the range up to 1.4, which is just barely brighter than the soft lighting that surrounds players.
	if (!isnull(l_power))
		light_power = l_power

	if (!isnull(l_range))
		light_range = l_range

	if (l_color != NONSENSICAL_VALUE)
		light_color = l_color

	if (!isnull(l_angle))
		light_angle = l_angle

	if (!isnull(l_dir))
		light_dir = l_dir

	if (!isnull(l_height))
		light_height = l_height

	//if(!isnull(l_on))
	//	light_on = l_on

	SEND_SIGNAL(src, COMSIG_ATOM_SET_LIGHT, l_range, l_power, l_color, l_on)

	update_light()

#undef NONSENSICAL_VALUE

// Will update the light (duh).
// Creates or destroys it if needed, makes it update values, makes sure it's got the correct source turf...
/atom/proc/update_light()
	set waitfor = FALSE
	if (QDELETED(src))
		return

	if (!light_power || light_range <= 0) // We won't emit light anyways, destroy the light source.
		QDEL_NULL(light)
	else
		if (!ismovable(loc)) // We choose what atom should be the top atom of the light here.
			. = src
		else
			. = loc

		if (light) // Update the light or create it if it does not exist.
			light.update(.)
		else
			light = new/datum/light_source(src, .)

/// Called by setDir() when we turn: re-aims the angled lights that point the way we face.
/atom/proc/update_facing_lights()
	for (var/datum/light_source/L as anything in light_sources)
		if (L.top_atom == src && L.source_atom.light_follows_facing && L.light_angle < 360)
			L.update()

// If we have opacity, make sure to tell (potentially) affected light sources.
/atom/movable/Destroy()
	var/turf/T = loc
	. = ..()
	if (opacity && istype(T))
		var/old_has_opaque_atom = T.has_opaque_atom
		T.recalc_atom_opacity()
		if (old_has_opaque_atom != T.has_opaque_atom)
			T.reconsider_lights()

// Should always be used to change the opacity of an atom.
// It notifies (potentially) affected light sources so they can update (if needed).
/atom/proc/set_opacity(var/new_opacity)
	if (new_opacity == opacity)
		return

	opacity = new_opacity
	var/turf/T = loc
	if (!isturf(T))
		return

	if (new_opacity == TRUE)
		T.has_opaque_atom = TRUE
		T.reconsider_lights()
	else
		var/old_has_opaque_atom = T.has_opaque_atom
		T.recalc_atom_opacity()
		if (old_has_opaque_atom != T.has_opaque_atom)
			T.reconsider_lights()


/atom/movable/Moved(atom/OldLoc, Dir)
	. = ..()
	var/datum/light_source/L
	var/thing
	for (thing in light_sources) // Cycle through the light sources on this atom and tell them to update.
		L = thing
		L.source_atom.update_light()

/atom/vv_edit_var(var_name, var_value)
	switch (var_name)
		if ("light_range")
			set_light(l_range=var_value)
			datum_flags |= DF_VAR_EDITED
			return TRUE

		if ("light_power")
			set_light(l_power=var_value)
			datum_flags |= DF_VAR_EDITED
			return TRUE

		if ("light_color")
			set_light(l_color=var_value)
			datum_flags |= DF_VAR_EDITED
			return TRUE

	return ..()


/atom/proc/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = LIGHT_COLOR_WHITE, _duration = FLASH_LIGHT_DURATION, _reset_lighting = TRUE)
	return

/turf/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = LIGHT_COLOR_WHITE, _duration = FLASH_LIGHT_DURATION, _reset_lighting = TRUE)
	if(!_duration)
		stack_trace("Lighting FX obj created on a turf without a duration")
	new /obj/effect/dummy/lighting_obj (src, _color, _range, _power, _duration)

/obj/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = LIGHT_COLOR_WHITE, _duration = FLASH_LIGHT_DURATION, _reset_lighting = TRUE)
	var/temp_color
	var/temp_power
	var/temp_range
	if(!_reset_lighting) //incase the obj already has a lighting color that you don't want cleared out after, ie computer monitors.
		temp_color = light_color
		temp_power = light_power
		temp_range = light_range
	set_light(_range, _power, _color)
	addtimer(CALLBACK(src, TYPE_PROC_REF(/atom, set_light), _reset_lighting ? initial(light_range) : temp_range, _reset_lighting ? initial(light_power) : temp_power, _reset_lighting ? initial(light_color) : temp_color), _duration, TIMER_OVERRIDE|TIMER_UNIQUE)

/mob/living/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = LIGHT_COLOR_WHITE, _duration = FLASH_LIGHT_DURATION, _reset_lighting = TRUE)
	mob_light(_color, _range, _power, _duration)

/mob/living/proc/mob_light(_color, _range, _power, _duration)
	var/obj/effect/dummy/lighting_obj/moblight/mob_light_obj = new (src, _color, _range, _power, _duration)
	return mob_light_obj

