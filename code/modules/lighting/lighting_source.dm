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
	/// How far past our range our light reaches, as a multiple of it: see LIGHTING_FALLOFF_TAIL
	var/light_tail = 1
	/// How far our light reaches, in whole tiles: our range, stretched by light_tail
	var/light_reach = 0
	/// Our light sheet, as get_sheet() last looked it up: dropped whenever anything it depends on changes
	var/list/sheet

	// Variables for keeping track of the colour.
	var/lum_r
	var/lum_g
	var/lum_b

	// The lumcount values used to apply the light.
	var/tmp/applied_lum_r
	var/tmp/applied_lum_g
	var/tmp/applied_lum_b

	var/list/datum/lighting_corner/effect_str     // List used to store how much we're affecting corners.
	/// Like effect_str, for the corners only our bounce light reaches (see get_bounce_corners()). Never shares a corner with it.
	var/list/datum/lighting_corner/bounce_str

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
	light_angle = source_atom.light_angle
	light_dir = get_light_dir()
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
// A light source that's been destroyed is done with: queued up again, it'd light up again as a ghost of itself.
#define EFFECT_UPDATE(level)                \
	if (QDELETED(src))                      \
		return;                             \
	if (needs_update == LIGHTING_NO_UPDATE) \
		SSlighting.sources_queue += src; \
	if (needs_update < level)               \
		needs_update            = level;    \


/// Which way our angled light points: NONE if we light all around us.
/datum/light_source/proc/get_light_dir()
	if (source_atom.light_angle >= 360)
		return NONE
	if (!source_atom.light_follows_facing)
		return source_atom.light_dir
	// Held or worn, we point the way our holder faces. A lamp that's part of what it's on - a mech's headlights, a
	// borg's headlamp - points the way that faces. Lying loose, we keep pointing where we were left.
	if (top_atom != source_atom || !isitem(source_atom) || !light_dir)
		return top_atom.dir
	return light_dir

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
// You will NEED to call this before you use LUM_FALLOFF, or work out what to give ADD_CORNER_LUM
#define SETUP_CORNERS_CACHE(lighting_source)                                    \
	var/_turf_x = lighting_source.source_turf.x;                                \
	var/_turf_y = lighting_source.source_turf.y;                                \
	var/list/_sheet = get_sheet();                                              \
	var/_range_offset = lighting_source.light_reach + 0.5 + 1;                 \
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

// Adds light to a lighting corner, and queues it up to be drawn again. A macro, not a proc, as it's needed for every
// corner a light reaches, every time the light changes. Needs `var/list/_corners_queue = SSlighting.corners_queue` first.
// If you're wondering what's with the backslashes, the backslashes cause BYOND to not automatically end the line.
// As such this all gets counted as a single line.
// The braces and semicolons are there to be able to do this on a single line.
#define ADD_CORNER_LUM(C, DR, DG, DB) \
	if (DR || DG || DB) { \
		C.lum_r += DR; \
		C.lum_g += DG; \
		C.lum_b += DB; \
		if (!C.needs_update) { \
			C.needs_update = TRUE; \
			_corners_queue += C; \
		} \
	}

// Like ADD_CORNER_LUM, for bounce light
#define ADD_CORNER_BOUNCE(C, DR, DG, DB) \
	if (DR || DG || DB) { \
		C.bounce_r += DR; \
		C.bounce_g += DG; \
		C.bounce_b += DB; \
		if (!C.needs_update) { \
			C.needs_update = TRUE; \
			_corners_queue += C; \
		} \
	}

/// Returns a list of lists, indexed with ints, that can be read to get the lighting multiplier at any one point.
/datum/light_source/proc/get_sheet()
	if(sheet)
		return sheet
	var/range = max(1, light_range)
	var/key = "[range]-[light_dir]-[light_angle]-[light_height]-[light_tail]"
	var/list/hand_back = GLOB.lighting_sheets[key]
	if(!hand_back)
		hand_back = generate_sheet(range, light_dir, light_angle, light_height, light_tail, light_reach)
		GLOB.lighting_sheets[key] = hand_back
	sheet = hand_back
	return hand_back

/**
 * For an angled light: like get_sheet(), but lighting all around it too, with the light that scatters back off what it
 * lights - SSlighting.cone_scatter of what it'd light all around it - wherever that's brighter than its cone. It's only
 * drawn, as bounce light, and only with bounce lighting on: see update_corners().
 */
/datum/light_source/proc/get_scatter_sheet()
	var/range = max(1, light_range)
	var/scatter = SSlighting.cone_scatter
	var/key = "[range]-[light_dir]-[light_angle]-[light_height]-[light_tail]-scatter[scatter]"
	var/list/hand_back = GLOB.lighting_sheets[key]
	if(!hand_back)
		var/list/cone = get_sheet()
		var/list/all_around = generate_sheet(range, NONE, 360, light_height, light_tail, light_reach)
		hand_back = list()
		for(var/i in 1 to length(cone))
			var/list/cone_row = cone[i]
			var/list/all_around_row = all_around[i]
			var/list/row = list()
			for(var/j in 1 to length(cone_row))
				row += max(cone_row[j], all_around_row[j] * scatter)
			hand_back += list(row)
		GLOB.lighting_sheets[key] = hand_back
	return hand_back

/// Returns a list of lists that encodes the light falloff of our source, out to `reach` tiles from it.
/// Takes anything that impacts our generation as input. This function should be "pure" - no side effects or reads from the source object.
/datum/light_source/proc/generate_sheet(range, center_dir, angle, height, tail, reach)
	var/list/encode = list()

	// Corners are placed at 0.5 offsets, so our coords need to reflect that.
	for(var/x in (-reach - 0.5) to (reach + 0.5))
		var/list/row = list()
		for(var/y in (-reach - 0.5) to (reach + 0.5))
			row += falloff_at_coord(x, y, range, center_dir, angle, height, tail)
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

/**
 * Takes x/y offsets from the source as input, alongside our source's range.
 * Returns a value between 0 and 1, 0 being dark on that tile, 1 being fully lit.
 *
 * The light falls off in a straight line, as tgstation's does - until `2 - tail` of the way out to our range, where it
 * eases off along a curve instead, one that carries on smoothly from that line and levels off to nothing at `tail` times
 * our range. So light fades out softly, without the hard edge at its range a straight line runs into. With a tail of 1,
 * it's tgstation's straight line all the way. See LIGHTING_FALLOFF_TAIL.
 *
 * With a tail, what's left of the light too dim to show (LIGHTING_TAIL_CUTOFF) is dropped: only a sliver of the curve,
 * but a whole ring of corners, all the way around, at the far edge of where the light reaches.
 */
/datum/light_source/proc/falloff_at_coord(x, y, range, center_dir, angle, height, tail)
	var/range_divisor = max(1, range)

	// How far out we are, as a fraction of our range
	var/distance = sqrt(x ** 2 + y ** 2 + height) / range_divisor
	var/multiplier
	if(distance <= 2 - tail)
		multiplier = 1 - CLAMP01(distance)
	else if(distance < tail)
		// The curve: a parabola touching the straight line where it takes over, and flat when it reaches 0
		multiplier = (tail - distance) ** 2 / (4 * (tail - 1))
	else
		multiplier = 0
	if(angle >= 360 || angle <= 0 || center_dir == NONE)
		return (tail > 1 && multiplier < LIGHTING_TAIL_CUTOFF) ? 0 : multiplier

	// Turn our positional offset into an angle, as seen from LIGHTING_CONE_SETBACK behind us: so the cone takes in the
	// tile we're on and a little to our sides, rather than starting from a point and leaving us half in the dark.
	var/center_angle = dir2angle(center_dir)
	var/coord_angle = delta_to_angle(x + sin(center_angle) * LIGHTING_CONE_SETBACK, y + cos(center_angle) * LIGHTING_CONE_SETBACK)
	// Get the difference between the angle we want, and the angle we have.
	var/angle_delta = abs(center_angle - coord_angle)
	// Normalize the angle delta to be between 0 and 180, instead of 0 and 360.
	if(angle_delta > 180)
		angle_delta = 180 - (angle_delta - 180)
	// Allow angle deltas up to angle / 2. Past that, start dimming, with 30 degrees past as the "fully dark" point.
	. = max(multiplier * (1 - max(angle_delta - (angle / 2), 0) / 30), 0)
	if(tail > 1 && . < LIGHTING_TAIL_CUTOFF)
		return 0

/datum/light_source/proc/remove_lum()
	applied = FALSE
	SETUP_CORNERS_REMOVAL_CACHE(src)
	var/list/_corners_queue = SSlighting.corners_queue
	var/strength
	var/delta_r
	var/delta_g
	var/delta_b
	for (var/datum/lighting_corner/C as anything in effect_str)
		strength = -effect_str[C]
		delta_r = strength * _applied_lum_r
		delta_g = strength * _applied_lum_g
		delta_b = strength * _applied_lum_b
		ADD_CORNER_LUM(C, delta_r, delta_g, delta_b)
		LAZYREMOVE(C.affecting, src)
	effect_str = null

	for (var/datum/lighting_corner/C as anything in bounce_str)
		strength = -bounce_str[C]
		delta_r = strength * _applied_lum_r
		delta_g = strength * _applied_lum_g
		delta_b = strength * _applied_lum_b
		ADD_CORNER_BOUNCE(C, delta_r, delta_g, delta_b)
		LAZYREMOVE(C.affecting, src)
	bounce_str = null

/datum/light_source/proc/recalc_corner(var/datum/lighting_corner/C)
	if (LAZYACCESS(bounce_str, C)) // only our bounce light reaches it, and that's left as it is
		return
	SETUP_CORNERS_CACHE(src)
	var/list/_corners_queue = SSlighting.corners_queue
	LAZYINITLIST(effect_str)
	var/strength = effect_str[C]
	var/delta_r
	var/delta_g
	var/delta_b
	if (strength) // Already have one: take it away, to give it back below
		delta_r = -strength * _applied_lum_r
		delta_g = -strength * _applied_lum_g
		delta_b = -strength * _applied_lum_b
		ADD_CORNER_LUM(C, delta_r, delta_g, delta_b)
		effect_str[C] = 0

	var/old = effect_str[C]
	strength = LUM_FALLOFF(C)
	strength *= _light_power
	effect_str[C] = strength
	delta_r = (strength * _lum_r) - (old * _applied_lum_r)
	delta_g = (strength * _lum_g) - (old * _applied_lum_g)
	delta_b = (strength * _lum_b) - (old * _applied_lum_b)
	ADD_CORNER_LUM(C, delta_r, delta_g, delta_b)
	UNSETEMPTY(effect_str)


/**
 * Works our light out afresh, where anything about it has changed: lights up what we can see, and takes our light off
 * what we no longer light.
 *
 * Every corner and turf we go through gets marked with the number of this update (their lighting_stamp and co.), so
 * we can keep plain lists of them, without the same corner turning up twice, and tell whether we've been through one
 * without having to look it up in a list. Every corner is shared by 4 turfs, and a light goes through dozens of them
 * every time it changes, so this is what most of our time goes on.
 */
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
		sheet = null
		update = TRUE

	if (!top_atom)
		top_atom = source_atom
		update = TRUE

	if (light_range <= 0 || !light_power)
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

	if (!applied)
		update = TRUE

	if (source_atom.light_color != light_color)
		light_color = source_atom.light_color
		PARSE_LIGHT_COLOR(src)
		update = TRUE

	else if (applied_lum_r != lum_r || applied_lum_g != lum_g || applied_lum_b != lum_b)
		update = TRUE

	if (source_atom.light_angle != light_angle)
		light_angle = source_atom.light_angle
		sheet = null
		update = TRUE

	var/new_dir = get_light_dir()
	if (new_dir != light_dir)
		light_dir = new_dir
		sheet = null
		update = TRUE

	if (source_atom.light_height != light_height)
		light_height = source_atom.light_height
		sheet = null
		update = TRUE

	var/tail = source_atom.light_falloff_tail ? SSlighting.falloff_tail : 1
	if (tail != light_tail)
		light_tail = tail
		sheet = null
		update = TRUE

	if (update)
		needs_update = LIGHTING_CHECK_UPDATE
		applied = TRUE
	else if (needs_update == LIGHTING_CHECK_UPDATE)
		return //nothing's changed

	light_reach = ceil(max(1, light_range) * LIGHTING_TAIL_END(light_tail))
	// Only what we can see has changed, not us: what we already light, we light as before
	var/vis_only = needs_update == LIGHTING_VIS_UPDATE
	var/bounces = SSlighting.bounce_lighting && source_atom.light_bounce && light_power > 0
	var/stamp = ++SSlighting.lighting_stamp
	if (stamp >= LIGHTING_STAMP_LIMIT)
		stamp = SSlighting.reset_lighting_stamps()
	SETUP_CORNERS_CACHE(src)
	var/list/_corners_queue = SSlighting.corners_queue

	// An angled light also lights what it can see around it, with the light that scatters back off what it lights, drawn
	// as bounce light wherever that's brighter than its cone: see get_scatter_sheet()
	var/list/spill_sheet = _sheet // what our bounce light spills from
	var/scatters = FALSE
	var/scatter_cutoff
	if (bounces && light_dir && SSlighting.cone_scatter > 0)
		spill_sheet = get_scatter_sheet()
		scatters = TRUE
		scatter_cutoff = SSlighting.bounce_cutoff

	// Corners we can see but don't reach (past our range, or outside our cone) are left to our bounce light, which may
	// well spill onto them - claimed as direct light, they'd stay dark with bounce light all around them. Likewise tiles
	// we see but don't light at all don't stop it spilling into them.
	var/list/datum/lighting_corner/reached = list() // the corners we light directly, each with its lighting_level
	var/list/datum/lighting_corner/bounced // the corners only our bounce light reaches, each with its bounce_level
	var/list/turf/lit // the turfs with a corner we light, directly or with scattered light, each marked with our stamp
	if (bounces)
		bounced = list()
		lit = list()
	var/datum/lighting_corner/C
	var/level
	var/scatter_level

// Goes through CORNER, one of the corners of a turf we can see, the first time we come to it: marks it, and sorts it
// into the corners we reach, those our scattered light reaches, and those we don't
#define GATHER_CORNER(CORNER) \
	C = CORNER; \
	if (C && C.lighting_stamp != stamp) { \
		C.lighting_stamp = stamp; \
		level = LUM_FALLOFF(C); \
		if (scatters) { \
			scatter_level = spill_sheet[C.x - _turf_x + _range_offset][C.y - _turf_y + _range_offset]; \
			if (level > 0 && level >= scatter_level) { \
				C.lighting_level = level; \
				reached += C; \
			} else { \
				C.lighting_level = 0; \
				if (scatter_level >= scatter_cutoff) { \
					C.bounce_stamp = stamp; \
					C.bounce_level = scatter_level; \
					bounced += C; \
				} \
			} \
		} else if (level > 0) { \
			C.lighting_level = level; \
			reached += C; \
		} else { \
			C.lighting_level = 0; \
		} \
	}
// Whether we light CORNER of a turf we've just gone through the corners of, directly or with scattered light
#define LIGHTS_CORNER(CORNER) (CORNER && (CORNER.lighting_level > 0 || CORNER.bounce_stamp == stamp))

	var/oldlum = source_turf.luminosity
	// Lights up our surroundings so view() sees them. That lights a circle, and view() takes a square: the square's
	// corners only count as visible if some other light happens to light them. That's fine for our direct light, which
	// doesn't reach them anyway - but bounce light would take them for shadows, and spill into them depending on
	// which lights around here worked their light out first. So bouncing, light the whole square.
	source_turf.luminosity = bounces ? ceil(light_reach * 1.5) : light_reach
	for (var/turf/T in view(light_reach, source_turf))
		if ((!IS_DYNAMIC_LIGHTING(T) && !T.light_sources) || IS_OPAQUE_TURF(T))
			continue
		if (!T.lighting_corners_initialised)
			T.generate_missing_corners()
		GATHER_CORNER(T.lighting_corner_NE)
		GATHER_CORNER(T.lighting_corner_SE)
		GATHER_CORNER(T.lighting_corner_SW)
		GATHER_CORNER(T.lighting_corner_NW)
		if (bounces && (LIGHTS_CORNER(T.lighting_corner_NE) || LIGHTS_CORNER(T.lighting_corner_SE) || LIGHTS_CORNER(T.lighting_corner_SW) || LIGHTS_CORNER(T.lighting_corner_NW)))
			T.lighting_stamp = stamp
			lit += T
	source_turf.luminosity = oldlum

#undef GATHER_CORNER
#undef LIGHTS_CORNER

	// Our direct light: onto the corners we reach, then off those we no longer do
	var/old
	var/strength
	var/delta_r
	var/delta_g
	var/delta_b
	LAZYINITLIST(effect_str)
	var/list/datum/lighting_corner/effect = effect_str
	for (var/datum/lighting_corner/corner as anything in reached)
		old = effect[corner]
		if (isnull(old))
			LAZYADD(corner.affecting, src)
			old = 0
		else if (vis_only)
			continue
		strength = corner.lighting_level * _light_power
		effect[corner] = strength
		delta_r = (strength * _lum_r) - (old * _applied_lum_r)
		delta_g = (strength * _lum_g) - (old * _applied_lum_g)
		delta_b = (strength * _lum_b) - (old * _applied_lum_b)
		ADD_CORNER_LUM(corner, delta_r, delta_g, delta_b)

	var/list/datum/lighting_corner/gone
	for (var/datum/lighting_corner/corner as anything in effect)
		if (corner.lighting_stamp != stamp || corner.lighting_level <= 0)
			strength = -effect[corner]
			delta_r = strength * _applied_lum_r
			delta_g = strength * _applied_lum_g
			delta_b = strength * _applied_lum_b
			ADD_CORNER_LUM(corner, delta_r, delta_g, delta_b)
			LAZYREMOVE(corner.affecting, src)
			LAZYADD(gone, corner)
	if (gone)
		effect -= gone

	// Bounce light. Always worked out afresh: unlike our direct light, it changes when anything nearby opens or closes.
	// A corner moving between effect_str and bounce_str briefly has us in its affecting list twice or not at all, which
	// the adding and removing here and above evens out.
	if (bounces)
		get_bounce_corners(lit, spill_sheet, _turf_x, _turf_y, _range_offset, stamp, bounced)
	if (bounce_str || length(bounced))
		LAZYINITLIST(bounce_str)
		var/list/datum/lighting_corner/bounce = bounce_str
		for (var/datum/lighting_corner/corner as anything in bounced)
			old = bounce[corner]
			if (isnull(old))
				LAZYADD(corner.affecting, src)
				old = 0
			strength = corner.bounce_level * _light_power
			bounce[corner] = strength
			delta_r = (strength * _lum_r) - (old * _applied_lum_r)
			delta_g = (strength * _lum_g) - (old * _applied_lum_g)
			delta_b = (strength * _lum_b) - (old * _applied_lum_b)
			ADD_CORNER_BOUNCE(corner, delta_r, delta_g, delta_b)

		gone = null
		for (var/datum/lighting_corner/corner as anything in bounce)
			if (corner.bounce_stamp != stamp)
				strength = -bounce[corner]
				delta_r = strength * _applied_lum_r
				delta_g = strength * _applied_lum_g
				delta_b = strength * _applied_lum_b
				ADD_CORNER_BOUNCE(corner, delta_r, delta_g, delta_b)
				LAZYREMOVE(corner.affecting, src)
				LAZYADD(gone, corner)
		if (gone)
			bounce -= gone
		UNSETEMPTY(bounce_str)

	applied_lum_r = lum_r
	applied_lum_g = lum_g
	applied_lum_b = lum_b

	UNSETEMPTY(effect_str)

/**
 * Bounce lighting: works out where our light spills into the shadows around what it lights directly.
 *
 * Every shadowed tile beside one we light - a tile we can't see that isn't opaque - gets a share of the light on the
 * edge between them, and passes a share of its own on to the shadowed tiles beside it, a few tiles deep (see
 * LIGHTING_BOUNCE_STRENGTH and co., tunable live on SSlighting). So light wraps softly around corners and out of doorways, instead of stopping dead
 * where our line of sight ends, but never goes through walls or closed doors: it only spreads between tiles that share
 * an edge. Going by the edge, not the whole lit tile, it only ever fades going into a shadow: light falling off steeply
 * across a tile, as it does near the end of our range, can't spill back out brighter than it arrived.
 *
 * Arguments:
 * * lit_turfs - the turfs we light directly, or scatter light onto, each marked with our stamp
 * * sheet, turf_x, turf_y, range_offset - our light sheet and where it sits, to read it as LUM_FALLOFF() does. For an
 *   angled light, its scatter sheet (see get_scatter_sheet()), so what it scatters spills on too
 * * stamp - the number of this update of ours: see update_corners()
 * * bounced - the corners only our bounce light reaches: those our scattered light reaches so far. Every other corner
 *   our bounce light reaches gets added, each marked with our stamp and its falloff multiplier, as on the sheet, in its
 *   bounce_level.
 */
/datum/light_source/proc/get_bounce_corners(list/turf/lit_turfs, list/sheet, turf_x, turf_y, range_offset, stamp, list/datum/lighting_corner/bounced)
	var/list/turf/spill = list() // shadowed turf -> falloff multiplier of the light spilling into it
	var/list/turf/frontier = list() // turfs spilled into in the last round, which spill on in the next
	var/turf/neighbour
	var/level
	// Read once: SSlighting's are what View Variables tunes live (see /datum/controller/subsystem/lighting/vv_edit_var())
	var/strength = SSlighting.bounce_strength
	var/falloff = SSlighting.bounce_falloff
	var/cutoff = SSlighting.bounce_cutoff

// (These are written out four times over rather than looping over directions: they run four times for every tile a light reaches.)
// Whether our light can spill into TURF: one we don't light directly, that doesn't block light, and is lit dynamically.
// Only dynamically lit turfs, never space (which update_corners() counts as lit only once it has starlight of its own):
// space gains and loses starlight as the station around it is built and broken, without telling the lights nearby,
// so spill that went by it would go stale - at roundstart, starlight spilled through space that had yet to light up.
#define CAN_SPILL_INTO(TURF) (TURF && TURF.lighting_stamp != stamp && !IS_OPAQUE_TURF(TURF) && IS_DYNAMIC_LIGHTING(TURF))
// Spills out of LIT, a tile we light, into the turf DIR of it, if our light can spill there: a share of the light on the
// edge between them, the dimmer of its corners (DX1, DY1 and DX2, DY2 from LIT's centre) on the sheet. Most tiles we
// light have no shadow beside them, so most never need the sheet read.
#define SPILL_OUT_OF(LIT, DIR, DX1, DY1, DX2, DY2) \
	neighbour = get_step(LIT, DIR); \
	if (CAN_SPILL_INTO(neighbour)) { \
		level = min(sheet[LIT.x - turf_x + range_offset + (DX1)][LIT.y - turf_y + range_offset + (DY1)], \
			sheet[LIT.x - turf_x + range_offset + (DX2)][LIT.y - turf_y + range_offset + (DY2)]) * strength; \
		if (level >= cutoff && level > spill[neighbour]) { \
			spill[neighbour] = level; \
			frontier[neighbour] = TRUE; \
		} \
	}
// Spills `level` on from SHADOWED into the turf DIR of it, if our light can spill there and it isn't brighter already
#define SPILL_ON(SHADOWED, DIR) \
	neighbour = get_step(SHADOWED, DIR); \
	if (CAN_SPILL_INTO(neighbour) && level > spill[neighbour]) { \
		spill[neighbour] = level; \
		frontier[neighbour] = TRUE; \
	}

	// Out of the tiles we light, into the shadowed tiles beside them
	for (var/turf/lit as anything in lit_turfs)
		if (!IS_DYNAMIC_LIGHTING(lit)) // space, as above
			continue
		SPILL_OUT_OF(lit, NORTH, -0.5, 0.5, 0.5, 0.5)
		SPILL_OUT_OF(lit, SOUTH, -0.5, -0.5, 0.5, -0.5)
		SPILL_OUT_OF(lit, EAST, 0.5, -0.5, 0.5, 0.5)
		SPILL_OUT_OF(lit, WEST, -0.5, -0.5, -0.5, 0.5)

	// On into the shadows, dimming as it goes
	for (var/depth in 2 to SSlighting.bounce_depth)
		var/list/turf/spilling = frontier
		frontier = list()
		for (var/turf/shadowed as anything in spilling)
			level = spill[shadowed] * falloff
			if (level < cutoff)
				continue
			SPILL_ON(shadowed, NORTH)
			SPILL_ON(shadowed, SOUTH)
			SPILL_ON(shadowed, EAST)
			SPILL_ON(shadowed, WEST)

#undef CAN_SPILL_INTO
#undef SPILL_OUT_OF
#undef SPILL_ON

	// A shadowed tile's spill lights its corners, bar those on its edges with the tiles we light, which we light directly -
	// or scatter light onto, where the brighter of the two goes
	var/datum/lighting_corner/corner
#define BOUNCE_ONTO(CORNER) \
	corner = CORNER; \
	if (corner && (corner.lighting_stamp != stamp || corner.lighting_level <= 0)) { \
		if (corner.bounce_stamp != stamp) { \
			corner.bounce_stamp = stamp; \
			corner.bounce_level = level; \
			bounced += corner; \
		} else if (level > corner.bounce_level) { \
			corner.bounce_level = level; \
		} \
	}
	for (var/turf/shadowed as anything in spill)
		if (!shadowed.lighting_corners_initialised)
			shadowed.generate_missing_corners()
		level = spill[shadowed]
		BOUNCE_ONTO(shadowed.lighting_corner_NE)
		BOUNCE_ONTO(shadowed.lighting_corner_SE)
		BOUNCE_ONTO(shadowed.lighting_corner_SW)
		BOUNCE_ONTO(shadowed.lighting_corner_NW)
#undef BOUNCE_ONTO

#undef EFFECT_UPDATE
#undef LUM_FALLOFF
#undef ADD_CORNER_LUM
#undef ADD_CORNER_BOUNCE
#undef SETUP_CORNERS_CACHE
#undef SETUP_CORNERS_REMOVAL_CACHE
