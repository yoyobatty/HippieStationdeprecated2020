// Contact shadows (lighting v2): a floor tile is a little darker along each wall it touches, darkest under the wall above it
// (whose face we see). One overlay a tile from hippiestation/icons/effects/contact_shadow.dmi (tools/lighting_v2/contact_shadow.py),
// picked by which of the 8 tiles round it are walls. It sits on the floor, under everything on it, and the light map darkens it
// like the floor: in the dark it's invisible, under a lamp it's where the wall meets the floor.
//
// Station and mining levels get them once at round start; a turf change looks at that tile and the 8 round it again a moment later.
// Only turfs count, not airlocks or machines: what opens, closes or moves would have the floors round it flicker.

GLOBAL_VAR_INIT(contact_shadows_on, FALSE)
/// mask -> the overlay
GLOBAL_LIST_EMPTY(contact_shadow_overlays)
/// Turfs to look at again
GLOBAL_LIST_EMPTY(contact_shadow_dirty)
GLOBAL_VAR_INIT(contact_shadow_flush_queued, FALSE)

/turf/open
	/// The contact_shadow.dmi mask this floor wears, 0 if none
	var/contact_shadow = 0

/// A turf whose sides cast a contact shadow on the floor beside it
#define CASTS_CONTACT_SHADOW(T) (isclosedturf(T) && T.opacity)
/// A floor that takes one
#define TAKES_CONTACT_SHADOW(T) (istype(T, /turf/open/floor) || istype(T, /turf/open/indestructible))

/turf/open/proc/contact_shadow_mask()
	if(!TAKES_CONTACT_SHADOW(src))
		return 0
	var/turf/T
	. = 0
	T = locate(x, y + 1, z)
	if(CASTS_CONTACT_SHADOW(T))
		. |= 1
	T = locate(x, y - 1, z)
	if(CASTS_CONTACT_SHADOW(T))
		. |= 2
	T = locate(x + 1, y, z)
	if(CASTS_CONTACT_SHADOW(T))
		. |= 4
	T = locate(x - 1, y, z)
	if(CASTS_CONTACT_SHADOW(T))
		. |= 8
	// a diagonal only where neither wall beside it is there (contact_shadow.py canonical())
	if(!(. & 5))
		T = locate(x + 1, y + 1, z)
		if(CASTS_CONTACT_SHADOW(T))
			. |= 16
	if(!(. & 9))
		T = locate(x - 1, y + 1, z)
		if(CASTS_CONTACT_SHADOW(T))
			. |= 32
	if(!(. & 6))
		T = locate(x + 1, y - 1, z)
		if(CASTS_CONTACT_SHADOW(T))
			. |= 64
	if(!(. & 10))
		T = locate(x - 1, y - 1, z)
		if(CASTS_CONTACT_SHADOW(T))
			. |= 128

/proc/contact_shadow_overlay(mask)
	var/key = "[mask]"
	. = GLOB.contact_shadow_overlays[key]
	if(!.)
		var/mutable_appearance/MA = mutable_appearance('hippiestation/icons/effects/contact_shadow.dmi', key, TURF_LAYER + 0.01, FLOOR_PLANE)
		MA.appearance_flags = RESET_COLOR | RESET_ALPHA | KEEP_APART
		MA.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		GLOB.contact_shadow_overlays[key] = MA
		. = MA

/// Puts on the right shadow (or none when off)
/turf/open/proc/update_contact_shadow()
	var/mask = GLOB.contact_shadows_on ? contact_shadow_mask() : 0
	if(mask == contact_shadow)
		return
	if(contact_shadow)
		cut_overlay(contact_shadow_overlay(contact_shadow))
	contact_shadow = mask
	if(mask)
		add_overlay(contact_shadow_overlay(mask))

/// Every station and mining level's floors, on or off
/proc/contact_shadows_set(on)
	GLOB.contact_shadows_on = !!on
	var/list/levels = SSmapping.levels_by_trait(ZTRAIT_STATION) | SSmapping.levels_by_trait(ZTRAIT_MINING)
	. = 0
	for(var/z in levels)
		for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/had = T.contact_shadow
			T.update_contact_shadow()
			if(T.contact_shadow != had)
				.++
			CHECK_TICK

/turf/AfterChange(flags, oldType)
	. = ..()
	if(!GLOB.contact_shadows_on)
		return
	var/list/dirty = GLOB.contact_shadow_dirty
	dirty[src] = TRUE
	for(var/dir in GLOB.alldirs)
		var/turf/T = get_step(src, dir)
		if(T)
			dirty[T] = TRUE
	if(!GLOB.contact_shadow_flush_queued)
		GLOB.contact_shadow_flush_queued = TRUE
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(contact_shadow_flush)), 1)

/proc/contact_shadow_flush()
	GLOB.contact_shadow_flush_queued = FALSE
	var/list/dirty = GLOB.contact_shadow_dirty
	GLOB.contact_shadow_dirty = list()
	for(var/turf/open/T in dirty)
		T.update_contact_shadow()

/// Round start: after the lighting is up (SSlighting.Initialize)
/datum/controller/subsystem/lighting/Initialize(timeofday)
	. = ..()
	if(GLOB.lighting_v2)
		var/started = REALTIMEOFDAY
		var/n = contact_shadows_set(TRUE)
		log_world("Lighting v2: [n] contact shadows in [(REALTIMEOFDAY - started) / 10] s")
		light_v2_refresh_starlight() // the planet's place is picked by now (SSparallax)

#undef CASTS_CONTACT_SHADOW
#undef TAKES_CONTACT_SHADOW
