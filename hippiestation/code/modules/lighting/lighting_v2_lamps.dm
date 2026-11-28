// Lighting v2, the lamps: a softer falloff and richer warm/cool tints.
//
// Falloff: tg's light falls off in a straight line, so a room's lamps add up to full almost everywhere in it and the room reads
// as one flat sheet of light. light_v2_falloff() is a softened inverse square instead: bright under the lamp, a quicker drop,
// a long soft tail out to where the light reaches. Rooms keep pools of light round their lamps. Starlight keeps its own curve
// (falloff_at_coord() leaves lights below the floor alone). v2 sheets are cached under keys of their own ("-v2").
//
// Tints: an area's lamp_colour (lamp_mood.dm) is pushed further from white, so a warm bar and a cold medbay read as such.

GLOBAL_VAR_INIT(lighting_v2_falloff, world.params["lighting-v2"] != "0")

/// How sharply the light drops off near the lamp: 1 / (1 + K d^2), rescaled to reach 0 at the light's reach. Sheets are cached
/// under it, so light_v2_set_falloff_k() can try others live
GLOBAL_VAR_INIT(light_v2_falloff_k, 6)
/// How much further from white an area's lamp tint goes
#define LIGHT_V2_LAMP_SATURATE 1.7

/// The light at `distance` (a fraction of the range, the light's height in it) with a soft tail of `tail`
/proc/light_v2_falloff(distance, tail)
	var/reach = tail > 1 ? LIGHTING_TAIL_END(tail) : 1
	var/d = distance / reach
	if(d >= 1)
		return 0
	var/k = GLOB.light_v2_falloff_k
	var/floor = 1 / (1 + k)
	. = (1 / (1 + k * d * d) - floor) / (1 - floor)
	if(tail > 1 && . < LIGHTING_TAIL_CUTOFF)
		return 0

/proc/light_v2_set_falloff_k(k)
	GLOB.light_v2_falloff_k = k
	if(GLOB.lighting_v2_falloff)
		return light_v2_relight_all()

/// Falloff on or off: every light works out its sheet again and relights
/proc/light_v2_set_falloff(on)
	on = !!on
	if(GLOB.lighting_v2_falloff == on)
		return 0
	GLOB.lighting_v2_falloff = on
	return light_v2_relight_all()

/proc/light_v2_relight_all()
	. = 0
	for(var/datum/light_source/L)
		L.sheet = null
		L.force_update()
		.++
		CHECK_TICK

// ---- Tints

/// Fixtures' strength with v2 on: overlapping lamps no longer add up to full everywhere, so a room keeps its pools of light
GLOBAL_VAR_INIT(light_v2_lamp_power, 0.45)
/// Small bulbs' strength with v2 on: maintenance has one bulb in a long run, nothing overlaps, so it keeps most of its light
GLOBAL_VAR_INIT(light_v2_bulb_power, 0.8)

/obj/machinery/light
	/// The area's lamp tint this fixture took (lamp_mood.dm), to swap for the richer one and back
	var/v2_mood_colour
	/// bulb_power as it was before v2 scaled it
	var/v2_base_power

/obj/machinery/light/Initialize(mapload)
	. = ..()
	v2_base_power = bulb_power
	if(GLOB.lighting_v2)
		bulb_power = v2_base_power * v2_power_scale()
	var/area/A = get_area(src)
	if(A?.lamp_colour && bulb_colour == A.lamp_colour)
		v2_mood_colour = A.lamp_colour
		if(GLOB.lighting_v2)
			bulb_colour = light_v2_richer(v2_mood_colour)

/// How much of its strength this fixture keeps with v2 on
/obj/machinery/light/proc/v2_power_scale()
	return istype(src, /obj/machinery/light/small) ? GLOB.light_v2_bulb_power : GLOB.light_v2_lamp_power

/proc/light_v2_richer(colour)
	var/list/rgb = rgb2num(colour)
	for(var/i in 1 to 3)
		rgb[i] = clamp(round(255 - (255 - rgb[i]) * LIGHT_V2_LAMP_SATURATE), 0, 255)
	return rgb(rgb[1], rgb[2], rgb[3])

/// Tints and strength of every fixture, v2 on or off (or GLOB.light_v2_lamp_power changed)
/proc/light_v2_set_tints(on)
	. = 0
	for(var/obj/machinery/light/L in GLOB.machines)
		var/changed = FALSE
		if(L.v2_mood_colour)
			var/want = on ? light_v2_richer(L.v2_mood_colour) : L.v2_mood_colour
			if(L.bulb_colour != want)
				L.bulb_colour = want
				changed = TRUE
		if(!isnull(L.v2_base_power))
			var/power = on ? L.v2_base_power * L.v2_power_scale() : L.v2_base_power
			if(L.bulb_power != power)
				L.bulb_power = power
				changed = TRUE
		if(changed)
			L.update(FALSE)
			.++
		CHECK_TICK

/proc/light_v2_set_lamp_power(power)
	GLOB.light_v2_lamp_power = power
	return light_v2_set_tints(GLOB.lighting_v2)

// ---- Lava (plan C3): tg lights it a flat yellow two tiles out. With v2 it's an orange glow a tile further, and every third tile
// each way carries a slow-breathing pool of light (light_glow.dm "lava1".."lava3"), so a lava field's shores flicker warm. Lava
// of another colour (plasma) keeps its colour and only reaches further.

#define LIGHT_V2_LAVA_COLOUR "#F2752E"
#define LIGHT_V2_LAVA_RANGE 3
#define LIGHT_V2_LAVA_POWER 0.8

/turf/open/lava
	/// The breathing pool it carries, if it's one of every third tile
	var/obj/effect/light_glow/v2_lava_pool

/turf/open/lava/Initialize(mapload)
	if(GLOB.lighting_v2)
		light_v2_lava_light(TRUE, FALSE)
	. = ..()

/// Sets the tile's light (and its pool) for v2 on or off. relight: the light is lit already and needs set_light() to change.
/turf/open/lava/proc/light_v2_lava_light(on, relight = TRUE)
	var/colour = initial(light_color)
	var/range = initial(light_range)
	var/power = initial(light_power)
	if(on)
		if(colour == LIGHT_COLOR_LAVA)
			colour = LIGHT_V2_LAVA_COLOUR
			power = LIGHT_V2_LAVA_POWER
		if(range)
			range = max(range, LIGHT_V2_LAVA_RANGE)
	if(relight)
		set_light(range, power, colour)
		update_lava_glow()
	else
		light_range = range
		light_power = power
		light_color = colour
	var/obj/effect/light_glow/pool = (on && range && !(x % 3) && !(y % 3)) ? light_glow("lava[1 + ((x / 3 + y / 3) % 3)]") : null
	if(pool == v2_lava_pool)
		return
	if(v2_lava_pool)
		vis_contents -= v2_lava_pool
	v2_lava_pool = pool
	if(pool)
		vis_contents += pool

/// Every lava tile's light and pool for v2 on or off. The count it changed.
/proc/light_v2_set_lava(on)
	. = 0
	for(var/z in 1 to world.maxz)
		for(var/turf/open/lava/L in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			L.light_v2_lava_light(on)
			.++
			CHECK_TICK

/// Every opaque tile's lighting object drawn again: one face with v2 on, a gradient with it off (lighting_object.dm draw())
/proc/light_v2_redraw_walls()
	. = 0
	for(var/z in 1 to world.maxz)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			if(T.has_opaque_atom && T.lighting_object)
				SSlighting.objects_queue += T.lighting_object
				.++
			CHECK_TICK

/// The server side of v2
/proc/lighting_v2_set_server(on)
	contact_shadows_set(on)
	light_v2_set_tints(on)
	light_v2_set_falloff(on)
	light_v2_refresh_starlight()
	light_v2_set_lava(on)
	light_v2_redraw_walls()

#undef LIGHT_V2_LAVA_COLOUR
#undef LIGHT_V2_LAVA_RANGE
#undef LIGHT_V2_LAVA_POWER

#undef LIGHT_V2_LAMP_SATURATE
