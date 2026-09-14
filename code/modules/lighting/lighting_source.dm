// This is where the fun begins.
// These are the main datums that emit light.

/// Cached global list of generated lighting falloff sheets. See: /datum/light_source/proc/get_sheet()
GLOBAL_LIST_EMPTY(lighting_sheets)

/datum/light_source
	var/atom/top_atom        // The atom we're emitting light from (for example a mob if we're from a flashlight that's being held).
	var/atom/source_atom     // The atom that we belong to.

	var/turf/source_turf     // The turf under the above.
	var/turf/pixel_turf      // The turf the top_atom appears to over.
	var/light_power    // Intensity of the emitter light.
	var/light_range      // The range of the emitted light.
	var/light_color    // The colour of the light, string, decomposed by parse_light_color()
	/// What direction our angled light is pointed. NONE for omnidirectional lights.
	var/light_dir = NONE
	/// How many degrees of a circle should our light show. 360 is all of it, 180 is half, etc.
	var/light_angle = 360
	/// The height of the light. The larger this is, the dimmer we'll start.
	var/light_height = LIGHTING_HEIGHT

	// Variables for keeping track of the colour.
	var/lum_r
	var/lum_g
	var/lum_b

	// The lumcount values used to apply the light.
	var/tmp/applied_lum_r
	var/tmp/applied_lum_g
	var/tmp/applied_lum_b

	var/list/datum/lighting_corner/effect_str     // List used to store how much we're affecting corners.
	var/list/turf/affecting_turfs

	var/applied = FALSE // Whether we have applied our light yet or not.

	var/needs_update = LIGHTING_NO_UPDATE    // Whether we are queued for an update.

// Thanks to Lohikar for flinging this tiny bit of code at me, increasing my brain cell count from 1 to 2 in the process.
// This macro will only offset up to 1 tile, but anything with a greater offset is an outlier and probably should handle its own lighting offsets.
// Anything pixelshifted 16px or more will be considered on the next tile.
#define GET_APPROXIMATE_PIXEL_DIR(PX, PY) ((!(PX) ? 0 : ((PX >= 16 ? EAST : (PX <= -16 ? WEST : 0)))) | (!PY ? 0 : (PY >= 16 ? NORTH : (PY <= -16 ? SOUTH : 0))))
#define UPDATE_APPROXIMATE_PIXEL_TURF var/_mask = GET_APPROXIMATE_PIXEL_DIR(top_atom.pixel_x, top_atom.pixel_y); pixel_turf = _mask ? (get_step(source_turf, _mask) || source_turf) : source_turf

/datum/light_source/New(var/atom/owner, var/atom/top)
	source_atom = owner // Set our new owner.
	LAZYADD(source_atom.light_sources, src)
	top_atom = top
	if (top_atom != source_atom)
		LAZYADD(top_atom.light_sources, src)

	source_turf = top_atom
	UPDATE_APPROXIMATE_PIXEL_TURF

	light_power = source_atom.light_power
	light_range = source_atom.light_range
	light_color = source_atom.light_color
	light_dir = source_atom.light_dir
	light_angle = source_atom.light_angle
	light_height = source_atom.light_height

	PARSE_LIGHT_COLOR(src)

	update()

/datum/light_source/Destroy(force)
	remove_lum()
	if (source_atom)
		LAZYREMOVE(source_atom.light_sources, src)

	if (top_atom)
		LAZYREMOVE(top_atom.light_sources, src)

	if (needs_update)
		SSlighting.sources_queue -= src

	. = ..()

// Yes this doesn't align correctly on anything other than 4 width tabs.
// If you want it to go switch everybody to elastic tab stops.
// Actually that'd be great if you could!
#define EFFECT_UPDATE(level)                \
	if (needs_update == LIGHTING_NO_UPDATE) \
		SSlighting.sources_queue += src; \
	if (needs_update < level)               \
		needs_update            = level;    \


// This proc will cause the light source to update the top atom, and add itself to the update queue.
/datum/light_source/proc/update(var/atom/new_top_atom)
	// This top atom is different.
	if (new_top_atom && new_top_atom != top_atom)
		if(top_atom != source_atom && top_atom.light_sources) // Remove ourselves from the light sources of that top atom.
			LAZYREMOVE(top_atom.light_sources, src)

		top_atom = new_top_atom

		if (top_atom != source_atom)
			LAZYADD(top_atom.light_sources, src) // Add ourselves to the light sources of our new top atom.

	EFFECT_UPDATE(LIGHTING_CHECK_UPDATE)

// Will force an update without checking if it's actually needed.
/datum/light_source/proc/force_update()
	EFFECT_UPDATE(LIGHTING_FORCE_UPDATE)

// Will cause the light source to recalculate turfs that were removed or added to visibility only.
/datum/light_source/proc/vis_update()
	EFFECT_UPDATE(LIGHTING_VIS_UPDATE)

// This exists so we can cache the vars used in this macro, and save MASSIVE time :)
// Most of this is saving off datum var accesses, tho some of it does actually cache computation
// You will NEED to call this before you call APPLY_CORNER
#define SETUP_CORNERS_CACHE(lighting_source)                                    \
	var/_turf_x = lighting_source.source_turf.x;                                \
	var/_turf_y = lighting_source.source_turf.y;                                \
	var/list/_sheet = get_sheet();                                              \
	var/_range_offset = ceil(lighting_source.light_range) + 0.5 + 1;      \
	var/_light_power = lighting_source.light_power;                            \
	var/_applied_lum_r = lighting_source.applied_lum_r;                        \
	var/_applied_lum_g = lighting_source.applied_lum_g;                        \
	var/_applied_lum_b = lighting_source.applied_lum_b;                        \
	var/_lum_r = lighting_source.lum_r;                                        \
	var/_lum_g = lighting_source.lum_g;                                        \
	var/_lum_b = lighting_source.lum_b;

#define SETUP_CORNERS_REMOVAL_CACHE(lighting_source)    \
	var/_applied_lum_r = lighting_source.applied_lum_r; \
	var/_applied_lum_g = lighting_source.applied_lum_g; \
	var/_applied_lum_b = lighting_source.applied_lum_b;

// Read out of our source's light sheet, a lookup table of offsets -> the luminosity to use.
#define LUM_FALLOFF(C) _sheet[C.x - _turf_x + _range_offset][C.y - _turf_y + _range_offset]

// Macro that applies light to a new corner.
// It is a macro in the interest of speed, yet not having to copy paste it.
// If you're wondering what's with the backslashes, the backslashes cause BYOND to not automatically end the line.
// As such this all gets counted as a single line.
// The braces and semicolons are there to be able to do this on a single line.
#define APPLY_CORNER(C)                      \
	. = LUM_FALLOFF(C);                      \
	. *= _light_power;                       \
	var/OLD = effect_str[C];                 \
	effect_str[C] = .;                       \
                                             \
	C.update_lumcount                        \
	(                                        \
		(. * _lum_r) - (OLD * _applied_lum_r), \
		(. * _lum_g) - (OLD * _applied_lum_g), \
		(. * _lum_b) - (OLD * _applied_lum_b)  \
	);

#define REMOVE_CORNER(C)                     \
	. = -effect_str[C];                      \
	C.update_lumcount                        \
	(                                        \
		. * _applied_lum_r,                   \
		. * _applied_lum_g,                   \
		. * _applied_lum_b                    \
	);

/// Returns a list of lists, indexed with ints, that can be read to get the lighting multiplier at any one point.
/datum/light_source/proc/get_sheet()
	var/range = max(1, light_range)
	var/key = "[range]-[light_dir]-[light_angle]-[light_height]"
	var/list/hand_back = GLOB.lighting_sheets[key]
	if(!hand_back)
		hand_back = generate_sheet(range, light_dir, light_angle, light_height)
		GLOB.lighting_sheets[key] = hand_back
	return hand_back

/// Returns a list of lists that encodes the light falloff of our source.
/// Takes anything that impacts our generation as input. This function should be "pure" - no side effects or reads from the source object.
/datum/light_source/proc/generate_sheet(range, center_dir, angle, height)
	var/list/encode = list()
	var/bound_range = ceil(range)

	// Corners are placed at 0.5 offsets, so our coords need to reflect that.
	for(var/x in (-bound_range - 0.5) to (bound_range + 0.5))
		var/list/row = list()
		for(var/y in (-bound_range - 0.5) to (bound_range + 0.5))
			row += falloff_at_coord(x, y, range, center_dir, angle, height)
		encode += list(row)
	return encode

/// Calculate the angle produced by a pair of x and y deltas.
/proc/delta_to_angle(x, y)
	if(!y)
		return (x >= 0) ? 90 : 270
	. = arctan(x/y)
	if(y < 0)
		. += 180
	else if(x < 0)
		. += 360

/// Takes x/y offsets from the source as input, alongside our source's range.
/// Returns a value between 0 and 1, 0 being dark on that tile, 1 being fully lit.
/datum/light_source/proc/falloff_at_coord(x, y, range, center_dir, angle, height)
	var/range_divisor = max(1, range)

	var/multiplier = 1 - CLAMP01(sqrt(x ** 2 + y ** 2 + height) / range_divisor)
	if(angle >= 360 || angle <= 0 || center_dir == NONE)
		return multiplier

	// Turn our positional offset into an angle.
	var/coord_angle = delta_to_angle(x, y)
	// Get the difference between the angle we want, and the angle we have.
	var/center_angle = dir2angle(center_dir)
	var/angle_delta = abs(center_angle - coord_angle)
	// Normalize the angle delta to be between 0 and 180, instead of 0 and 360.
	if(angle_delta > 180)
		angle_delta = 180 - (angle_delta - 180)
	// Allow angle deltas up to angle / 2. Past that, start dimming, with 30 degrees past as the "fully dark" point.
	return max(multiplier * (1 - max(angle_delta - (angle / 2), 0) / 30), 0)

/datum/light_source/proc/remove_lum()
	applied = FALSE
	var/thing
	for (thing in affecting_turfs)
		var/turf/T = thing
		LAZYREMOVE(T.affecting_lights, src)

	affecting_turfs = null

	SETUP_CORNERS_REMOVAL_CACHE(src)
	var/datum/lighting_corner/C
	for (thing in effect_str)
		C = thing
		REMOVE_CORNER(C)

		LAZYREMOVE(C.affecting, src)

	effect_str = null

/datum/light_source/proc/recalc_corner(var/datum/lighting_corner/C)
	SETUP_CORNERS_CACHE(src)
	LAZYINITLIST(effect_str)
	if (effect_str[C]) // Already have one.
		REMOVE_CORNER(C)
		effect_str[C] = 0

	APPLY_CORNER(C)
	UNSETEMPTY(effect_str)


/datum/light_source/proc/update_corners()
	var/update = FALSE
	var/atom/source_atom = src.source_atom

	if (QDELETED(source_atom))
		qdel(src)
		return

	if (source_atom.light_power != light_power)
		light_power = source_atom.light_power
		update = TRUE

	if (source_atom.light_range != light_range)
		light_range = source_atom.light_range
		update = TRUE

	if (!top_atom)
		top_atom = source_atom
		update = TRUE

	if (!light_range || !light_power)
		qdel(src)
		return

	if (isturf(top_atom))
		if (source_turf != top_atom)
			source_turf = top_atom
			UPDATE_APPROXIMATE_PIXEL_TURF
			update = TRUE
	else if (top_atom.loc != source_turf)
		source_turf = top_atom.loc
		UPDATE_APPROXIMATE_PIXEL_TURF
		update = TRUE

	if (!isturf(source_turf))
		if (applied)
			remove_lum()
		return

	if (light_range && light_power && !applied)
		update = TRUE

	if (source_atom.light_color != light_color)
		light_color = source_atom.light_color
		PARSE_LIGHT_COLOR(src)
		update = TRUE

	else if (applied_lum_r != lum_r || applied_lum_g != lum_g || applied_lum_b != lum_b)
		update = TRUE

	if (source_atom.light_dir != light_dir)
		light_dir = source_atom.light_dir
		update = TRUE

	if (source_atom.light_angle != light_angle)
		light_angle = source_atom.light_angle
		update = TRUE

	if (source_atom.light_height != light_height)
		light_height = source_atom.light_height
		update = TRUE

	if (update)
		needs_update = LIGHTING_CHECK_UPDATE
		applied = TRUE
	else if (needs_update == LIGHTING_CHECK_UPDATE)
		return //nothing's changed

	var/list/datum/lighting_corner/corners = list()
	var/list/turf/turfs                    = list()
	var/thing
	var/datum/lighting_corner/C
	var/turf/T

	if (source_turf)
		var/oldlum = source_turf.luminosity
		source_turf.luminosity = ceil(light_range)
		for(T in view(ceil(light_range), source_turf))
			if((!IS_DYNAMIC_LIGHTING(T) && !T.light_sources) || IS_OPAQUE_TURF(T))
				continue
			if (!T.lighting_corners_initialised)
				T.generate_missing_corners()
			for (thing in T.get_lighting_corners())
				C = thing
				corners[C] = 0
			turfs += T
		source_turf.luminosity = oldlum

	LAZYINITLIST(affecting_turfs)
	var/list/L = turfs - affecting_turfs // New turfs, add us to the affecting lights of them.
	affecting_turfs += L
	for (thing in L)
		T = thing
		LAZYADD(T.affecting_lights, src)

	L = affecting_turfs - turfs // Now-gone turfs, remove us from the affecting lights.
	affecting_turfs -= L
	for (thing in L)
		T = thing
		LAZYREMOVE(T.affecting_lights, src)

	SETUP_CORNERS_CACHE(src)
	LAZYINITLIST(effect_str)
	if (needs_update == LIGHTING_VIS_UPDATE)
		for (thing in  corners - effect_str) // New corners
			C = thing
			LAZYADD(C.affecting, src)
			APPLY_CORNER(C)
	else
		L = corners - effect_str
		for (thing in L) // New corners
			C = thing
			LAZYADD(C.affecting, src)
			APPLY_CORNER(C)

		for (thing in corners - L) // Existing corners
			C = thing
			APPLY_CORNER(C)

	L = effect_str - corners
	for (thing in L) // Old, now gone, corners.
		C = thing
		REMOVE_CORNER(C)
		LAZYREMOVE(C.affecting, src)
	effect_str -= L

	applied_lum_r = lum_r
	applied_lum_g = lum_g
	applied_lum_b = lum_b

	UNSETEMPTY(effect_str)
	UNSETEMPTY(affecting_turfs)

#undef EFFECT_UPDATE
#undef LUM_FALLOFF
#undef REMOVE_CORNER
#undef APPLY_CORNER
#undef SETUP_CORNERS_CACHE
#undef SETUP_CORNERS_REMOVAL_CACHE
