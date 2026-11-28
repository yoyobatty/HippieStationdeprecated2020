// Lighting v2, space: starlight in the sky theme's colour comes in further through windows and breaches, and over Lavaland
// (which the station orbits: the planet sits behind the station on every station level, SSparallax.planet_x/y_offset) the
// light from below is warmed by the planet's glow.
//
// Everything goes through /turf/open/space/set_light(): every way starlight is lit or recoloured (enable_starlight(),
// set_starlight(), Aurora Caelus) passes the theme's colour there, and the space tile adds its own range and warmth.

/// Extra reach of starlight from a space tile that touches a floor (a window's tile, or a breach)
#define LIGHT_V2_STARLIGHT_WINDOW_RANGE 1.5
/// Lavaland's glow from below
#define LIGHT_V2_PLANET_GLOW "#ff7a3c"
/// How much of the starlight is the planet's, right over its middle
#define LIGHT_V2_PLANET_MIX 0.3
/// Starlight indoors is pale: the theme's colour (saturated, made for the sky) moved this far toward a cool grey, so a window
/// lights a hall softly instead of staining it pink next to v2's dimmer lamps
#define LIGHT_V2_STARLIGHT_GREY "#a8b0c4"
#define LIGHT_V2_STARLIGHT_PALE 0.45
/// The planet's disc as the station sees it, tiles: sky_bodies.dmi planet_lava is ~210 x 116 px, and its layer moves 3 px a tile
#define LIGHT_V2_PLANET_RX 35
#define LIGHT_V2_PLANET_RY 19

#define V2_NO_COLOUR -99999 // set_light()'s "colour not given" (NONSENSICAL_VALUE, lighting_atom.dm)

/turf/open/space
	/// Starlight that came in recoloured by light_v2_starlight(): the colour it was given, to give it again on a refresh
	var/v2_star_colour

/turf/open/space/set_light(l_range, l_power, l_color = V2_NO_COLOUR, l_on, l_angle, l_dir, l_height)
	if(GLOB.starlight[src] && l_range && l_color != V2_NO_COLOUR)
		v2_star_colour = l_color
		if(GLOB.lighting_v2)
			var/list/tuned = light_v2_starlight(l_range, l_color)
			l_range = tuned[1]
			l_color = tuned[2]
	return ..()

/// The starlight this space tile gives off: list(range, colour)
/turf/open/space/proc/light_v2_starlight(range, colour)
	. = list(range, colour ? light_v2_mix(colour, LIGHT_V2_STARLIGHT_GREY, LIGHT_V2_STARLIGHT_PALE) : colour)
	for(var/turf/T as anything in RANGE_TURFS(1, src))
		if(!isspaceturf(T) && !T.density) // a window's tile or a breach: the light comes on in
			.[1] = range + LIGHT_V2_STARLIGHT_WINDOW_RANGE
			break
	if(!is_station_level(z))
		return
	var/dx = (x - SSparallax.planet_x_offset) / LIGHT_V2_PLANET_RX
	var/dy = (y - SSparallax.planet_y_offset) / LIGHT_V2_PLANET_RY
	var/over = 1 - (dx * dx + dy * dy)
	if(over > 0)
		.[2] = light_v2_mix(.[2], LIGHT_V2_PLANET_GLOW, LIGHT_V2_PLANET_MIX * min(1, over * 1.5))

/proc/light_v2_mix(a, b, t)
	var/list/x = rgb2num(a)
	var/list/y = rgb2num(b)
	return rgb(round(x[1] + (y[1] - x[1]) * t), round(x[2] + (y[2] - x[2]) * t), round(x[3] + (y[3] - x[3]) * t))

/// Every starlit tile works its light out again (v2 on or off, or the tiles round it changed)
/proc/light_v2_refresh_starlight(list/turfs)
	. = 0
	for(var/turf/open/space/S as anything in (turfs || GLOB.starlight))
		if(!GLOB.starlight[S])
			continue
		S.set_light(GLOB.starlight_range, GLOB.starlight_power, S.v2_star_colour || GLOB.starlight_color)
		.++
		CHECK_TICK

/// A breach opening or a window going: the space round it may reach in now
/turf/AfterChange(flags, oldType)
	. = ..()
	if(!GLOB.lighting_v2)
		return
	var/list/space = list()
	for(var/turf/open/space/S in RANGE_TURFS(1, src))
		if(GLOB.starlight[S])
			space += S
	if(length(space)) // a moment later: AfterChange() runs in signal handlers that mustn't sleep, and the refresh may
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(light_v2_refresh_starlight), space), 1)

#undef LIGHT_V2_STARLIGHT_WINDOW_RANGE
#undef LIGHT_V2_PLANET_GLOW
#undef LIGHT_V2_PLANET_MIX
#undef LIGHT_V2_STARLIGHT_GREY
#undef LIGHT_V2_STARLIGHT_PALE
#undef LIGHT_V2_PLANET_RX
#undef LIGHT_V2_PLANET_RY
#undef V2_NO_COLOUR
