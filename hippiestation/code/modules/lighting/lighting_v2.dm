// Lighting v2: the finish on the light map (2026-11-20, data/previews/lighting_v2/PLAN.md).
//
// The light map darkens the screen by multiplying, so on its own it can only take light away: a lamp never looks brighter than
// the floor's own colour, and the dark is dead black. Here each client also gets a hidden plane made of three copies:
//  - the light map's brightest parts (over LIGHT_V2_BLOOM_THRESHOLD), so lit floors glow out past their edges into the dark;
//  - the glowing sprites (the emissive plane) at a fraction of their colour, a wide soft glow round lamps, screens, lava, fire;
//  - the dark's own tint, where the light map is black, so the dark is a deep blue-black instead of nothing.
// The plane is blurred once and added to the screen through the emissive bloom plane (additive, no client colour). It's all on
// the client: nothing on the server changes when it's on, and Low graphics leaves it off.
//
// World param lighting-v2=0 starts with it off; lighting_v2_set(on) flips it for everyone (before/after pictures in one boot).

GLOBAL_VAR_INIT(lighting_v2, world.params["lighting-v2"] != "0")

/// Turns lighting v2 on or off for everyone, at once
/proc/lighting_v2_set(on)
	GLOB.lighting_v2 = !!on
	for(var/client/C as anything in GLOB.clients)
		var/datum/hud/H = C.mob?.hud_used
		if(!H)
			continue
		var/obj/screen/plane_master/lighting/L = H.plane_masters["[LIGHTING_PLANE]"]
		if(L)
			L.filter_quality = null //rebuild
		H.plane_masters_update()
	lighting_v2_set_server(GLOB.lighting_v2)
	return GLOB.lighting_v2

/proc/wants_lighting_v2(mob/mymob)
	return GLOB.lighting_v2 && (!mymob?.client?.prefs || mymob.client.prefs.graphics_quality() >= GRAPHICS_QUALITY_MEDIUM)

// ---- The light map is copied from the lighting plane

/obj/screen/plane_master/lighting
	render_target = LIGHTING_RENDER_TARGET //no "*": it still draws

// ---- The hidden glow plane

/obj/screen/plane_master/light_v2_glow
	name = "light v2 glow plane master"
	plane = LIGHT_V2_GLOW_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = PLANE_MASTER|NO_CLIENT_COLOR
	render_target = LIGHT_V2_GLOW_RENDER_TARGET

/obj/screen/plane_master/light_v2_glow/Initialize()
	. = ..()
	filters = list(filter(type = "blur", size = LIGHT_V2_GLOW_BLUR))

/obj/screen/plane_master/light_v2_glow/backdrop(mob/mymob)
	. = ..()
	if(!mymob?.client)
		return
	if(wants_lighting_v2(mymob))
		mymob.client.screen |= GLOB.light_v2_relays
		mymob.client.screen |= GLOB.light_v2_dark_fill
		addtimer(CALLBACK(src, PROC_REF(kick), 0), 13 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)
	else
		mymob.client.screen -= GLOB.light_v2_relays
		mymob.client.screen -= GLOB.light_v2_dark_fill

/// A filtered copy of render targets made of copies draws nothing until its filters are taken off and put back, a while after it's
/// on screen (reference: BYOND render/animate traps). Taken off, then put back 2 s later.
/obj/screen/plane_master/light_v2_glow/proc/kick(stage)
	if(QDELETED(src))
		return
	if(!stage)
		filters = list()
		addtimer(CALLBACK(src, PROC_REF(kick), 1), 2 SECONDS)
	else
		filters = list(filter(type = "blur", size = LIGHT_V2_GLOW_BLUR))

/// A copy of a render target onto the glow plane, through a colour matrix
/obj/screen/light_v2_relay
	name = ""
	plane = LIGHT_V2_GLOW_PLANE
	screen_loc = "1,1" // a copy is drawn from the object's bottom-left corner (see /obj/screen/space_unlit_relay)
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = PASS_MOUSE | NO_CLIENT_COLOR | KEEP_TOGETHER
	blend_mode = BLEND_ADD

/obj/screen/light_v2_relay/New(loc, source)
	..()
	render_source = source

/// Where nothing is drawn the screen is the map's own black: this is the dark's tint there instead, so a dark tile that's drawn
/// (tinted by the relay above) and one that isn't meet without a seam
/obj/screen/light_v2_dark_fill
	name = ""
	icon = 'icons/mob/screen_gen.dmi'
	icon_state = "flash"
	screen_loc = "CENTER"
	transform = matrix(200, 0, 0, 0, 200, 0) // a transform past the screen's edges doesn't move the view; a big icon would
	plane = LIGHT_V2_DARK_FILL_PLANE
	color = LIGHT_V2_DARK_FILL_COLOUR
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = NO_CLIENT_COLOR

GLOBAL_DATUM_INIT(light_v2_dark_fill, /obj/screen/light_v2_dark_fill, new)

/obj/screen/plane_master/light_v2_dark_fill
	name = "light v2 dark fill plane master"
	plane = LIGHT_V2_DARK_FILL_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = PLANE_MASTER|NO_CLIENT_COLOR

/obj/screen/plane_master/light_v2_dark_fill/Initialize()
	. = ..()
	filters += filter(type = "alpha", render_source = PLANE_SPACE_RENDER_TARGET, flags = MASK_INVERSE) // space shows the sky, not the dark

GLOBAL_LIST_INIT(light_v2_relays, light_v2_make_relays())

/proc/light_v2_make_relays()
	. = list()
	. += new /obj/screen/light_v2_relay(null, LIGHTING_RENDER_TARGET)
	. += new /obj/screen/light_v2_relay(null, EMISSIVE_RENDER_TARGET)
	. += new /obj/screen/light_v2_relay(null, EMISSIVE_UNBLOCKABLE_RENDER_TARGET)
	. += new /obj/screen/light_v2_relay(null, LIGHTING_RENDER_TARGET)
	light_v2_tune(LIGHT_V2_BLOOM_THRESHOLD, LIGHT_V2_BLOOM_STRENGTH, LIGHT_V2_EMISSIVE_SPREAD, LIGHT_V2_DARK_TINT, .)

/// Sets the copies' colour matrices: the light map's bloom (above `threshold`, times `strength`), the glowing sprites' wide glow
/// (`spread`) and the dark's tint (list(r, g, b), 0-1). Tunable live; every client has the same shared copies.
/proc/light_v2_tune(threshold, strength, spread, list/tint, list/relays = GLOB.light_v2_relays)
	var/k = strength
	var/cut = -k * threshold
	var/obj/screen/light_v2_relay/R = relays[1]
	R.color = list(k,0,0,0, 0,k,0,0, 0,0,k,0, 0,0,0,1, cut,cut,cut,0)
	var/s = spread
	for(var/i in 2 to 3)
		R = relays[i]
		R.color = list(s,0,0,0, 0,s,0,0, 0,0,s,0, 0,0,0,1, 0,0,0,0)
	var/r = tint[1] / 3
	var/g = tint[2] / 3
	var/b = tint[3] / 3
	R = relays[4]
	R.color = list(-r,-g,-b,0, -r,-g,-b,0, -r,-g,-b,0, 0,0,0,1, tint[1],tint[2],tint[3],0)
	var/obj/screen/light_v2_dark_fill/fill = GLOB.light_v2_dark_fill
	if(fill)
		fill.color = rgb(round(tint[1] * 255), round(tint[2] * 255), round(tint[3] * 255))
	return TRUE

// ---- Added to the screen with the emissive bloom (additive, already above the lighting plane)

/obj/screen/plane_master/emissive_bloom
	/// Whether the v2 glow plane is layered in
	var/light_v2_on = FALSE

/obj/screen/plane_master/emissive_bloom/backdrop(mob/mymob)
	. = ..()
	var/want = wants_lighting_v2(mymob)
	if(want != light_v2_on)
		light_v2_filters(want)
		if(want) // the same trap as the glow plane's kick(): its filters off and on again once the copies are up
			addtimer(CALLBACK(src, PROC_REF(light_v2_kick), 0), 13 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)

/obj/screen/plane_master/emissive_bloom/proc/light_v2_kick(stage)
	if(QDELETED(src) || !light_v2_on)
		return
	if(!stage)
		filters = list()
		addtimer(CALLBACK(src, PROC_REF(light_v2_kick), 1), 2 SECONDS)
	else
		light_v2_filters(TRUE)

/obj/screen/plane_master/emissive_bloom/proc/light_v2_filters(want)
	light_v2_on = want
	filters = list()
	filters += filter(type = "alpha", render_source = EMISSIVE_BLOCKER_RENDER_TARGET, flags = MASK_INVERSE)
	filters += filter(type = "bloom", threshold = COLOR_BLACK, size = EMISSIVE_BLOOM_SIZE, offset = EMISSIVE_BLOOM_OFFSET, alpha = EMISSIVE_BLOOM_ALPHA)
	filters += filter(type = "alpha", render_source = EMISSIVE_RENDER_TARGET, flags = MASK_INVERSE)
	filters += filter(type = "alpha", render_source = EMISSIVE_UNBLOCKABLE_RENDER_TARGET, flags = MASK_INVERSE)
	if(want)
		filters += filter(type = "layer", render_source = LIGHT_V2_GLOW_RENDER_TARGET, blend_mode = BLEND_ADD)
		// the sky is far away: no lamp's halo or glow may spill onto space seen past a window or breach
		filters += filter(type = "alpha", render_source = PLANE_SPACE_RENDER_TARGET, flags = MASK_INVERSE)
