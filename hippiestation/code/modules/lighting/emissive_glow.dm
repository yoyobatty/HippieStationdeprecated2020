/**
  * Glowing overlays.
  *
  * A glow is two copies of a sprite: one on the emissive plane, which lets it through the darkness, and one on the emissive
  * bloom plane, which glows round it in its own colours (see emissive_bloom.dm). They're overlays, not vis_contents, so they
  * can't drift away from the thing's own appearance (the APC's lights did, see apc.dm). Every fixture showing the same state
  * shares one cached pair.
  *
  * Sprites with their lights painted in have a "<state>_glow" mask cut out of them at build time (tools/icon_merge/glow.txt).
  * Things that already have their lights as separate states (airlock lights, status display pictures) glow those directly.
  */
GLOBAL_LIST_EMPTY(emissive_glow_overlays)

/**
  * The pair of overlays that make a sprite glow. maptext instead of icon_state makes text glow (status displays).
  *
  * unblockable is for glows on a mob (a held sword, a lit cigarette, a cyborg's eyes). A mob's emissive blocker is a copy of its
  * whole sprite, glow and all, so on the ordinary emissive plane the mob would hide its own glow. The unblockable plane isn't
  * masked by blockers, and the blocker plane has the unblockable glows cut out of it (below), so their bloom survives too.
  */
/proc/emissive_glow(icon, icon_state, dir = SOUTH, alpha = 255, pixel_x = 0, pixel_y = 0, maptext, maptext_width = 32, maptext_height = 32, maptext_y = 0, unblockable = FALSE, color)
	var/key = "[icon]|[icon_state]|[dir]|[alpha]|[pixel_x]|[pixel_y]|[maptext_width]|[maptext_height]|[maptext_y]|[maptext]|[unblockable]|[color]"
	. = GLOB.emissive_glow_overlays[key]
	if(.)
		return
	var/list/pair = list()
	for(var/glow_plane in list(unblockable ? EMISSIVE_UNBLOCKABLE_PLANE : EMISSIVE_PLANE, EMISSIVE_BLOOM_PLANE)) // what glows, and the glow itself
		var/mutable_appearance/glow = mutable_appearance(maptext ? null : icon, maptext ? null : icon_state, FLOAT_LAYER, glow_plane, alpha)
		glow.dir = dir // overlays keep their own dir, they don't follow the thing's
		glow.pixel_x = pixel_x
		glow.pixel_y = pixel_y
		if(maptext)
			glow.maptext = maptext
			glow.maptext_width = maptext_width
			glow.maptext_height = maptext_height
			glow.maptext_y = maptext_y
		if(color)
			glow.color = color
		glow.appearance_flags |= KEEP_APART
		pair += glow
	if(!maptext) // text changes every few seconds on a marquee; only sprites are worth keeping
		GLOB.emissive_glow_overlays[key] = pair
	return pair

/// Blockers don't cover unblockable glows: those are on mobs, whose own blocker would otherwise cut their bloom away
/obj/screen/plane_master/emissive_blocker/Initialize()
	. = ..()
	filters += filter(type = "alpha", render_source = EMISSIVE_UNBLOCKABLE_RENDER_TARGET, flags = MASK_INVERSE)

/atom
	/// The glow overlays set_emissive_glow() put on, so the next call can take them off
	var/list/emissive_glow_shown
	/// How strongly it glows, 0-255: small indicator lights (airlocks, chem dispensers, chargers) glow a bit less than screens
	var/emissive_glow_alpha = 255

/**
  * Makes the thing glow with that state of its icon (or another icon), or stops it glowing with null.
  *
  * The thing gets luminosity 1 while it glows: BYOND draws nothing on a dark tile further off than the viewer's see_in_dark
  * (2 tiles for a human), so without it a glowing wall fixture across a dark room would be as invisible as the rest of it.
  * Safe to call after cut_overlays() took the old glow off.
  */
/atom/proc/set_emissive_glow(icon_state, icon_file = icon, list/extra)
	if(emissive_glow_shown)
		cut_overlay(emissive_glow_shown)
		emissive_glow_shown = null
	if(!icon_state && !extra)
		luminosity = initial(luminosity)
		return
	emissive_glow_shown = list()
	if(icon_state)
		if(ismob(src)) // a mob turns without redrawing: SOUTH follows it, like its other overlays
			emissive_glow_shown += emissive_glow(icon_file, icon_state, SOUTH, emissive_glow_alpha, unblockable = TRUE)
		else
			emissive_glow_shown += emissive_glow(icon_file, icon_state, dir, emissive_glow_alpha)
	if(extra)
		emissive_glow_shown += extra
	add_overlay(emissive_glow_shown)
	luminosity = 1

/// {icon file: {state: "<state>_glow"}}: the states of each sheet that have a glow mask
GLOBAL_LIST_EMPTY(emissive_glow_states)

/// "<state>_glow" if that sheet has a mask for the state, or null
/proc/emissive_glow_state(icon, state)
	if(!icon || !state)
		return null
	var/list/glows = GLOB.emissive_glow_states[icon]
	if(!glows)
		glows = list()
		for(var/each in icon_states(icon))
			if(length(each) > 5 && copytext(each, -5) == "_glow")
				glows[copytext(each, 1, -5)] = each
		GLOB.emissive_glow_states[icon] = glows
	return glows[state]

/// The glow pair for a state's mask, or null when its sheet has none
/proc/emissive_glow_list(icon, state, dir = SOUTH, alpha = 255)
	var/glow = emissive_glow_state(icon, state)
	return glow ? emissive_glow(icon, glow, dir, alpha) : null

/// Glows with "<icon_state>_glow" if its sheet has one, so the glow follows whatever state update_icon() picked: tg sprites mark
/// unpowered, broken and opened with states of their own ("alarmp", "intercom-p"), and those have no mask.
/atom/proc/update_state_glow(list/extra)
	set_emissive_glow(emissive_glow_state(icon, icon_state), icon, extra)

/// flick() for the glow: another state's glow for a moment (the length of the flicked animation), then update_icon() puts the
/// right one back. An overlay can't be flicked, and a button's pressed or denied flick would glow with the idle light otherwise.
/obj/proc/flick_emissive_glow(icon_state, duration)
	set_emissive_glow(icon_state)
	addtimer(CALLBACK(src, PROC_REF(update_icon)), duration, TIMER_UNIQUE | TIMER_OVERRIDE)
