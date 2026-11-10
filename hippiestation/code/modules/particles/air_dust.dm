// Dust in the air: specks hanging over the floor and wandering about, seen where the light catches them. More of it in
// maintenance, storage, the chapel and the library; none in medical. The air moves it: a running vent blows specks out, a
// scrubber (or a vent siphoning) draws them in, and wind carries them along.
//
// One emitter every AIR_DUST_SPACING tiles each way, held in a floor's vis_contents, covers the square round it. Each has its own
// particle set, so wind over its floor bends the specks already in the air (a new gravity) instead of starting them over.
// Vents and scrubbers hold shared emitters of their own while they run. Everything is drawn on a plane of its own
// (AIR_DUST_PLANE) that a client masks twice: by the floor plane, so there's no dust over space or out past a window, and by the
// game plane turned inside out, so none over a wall or in front of a locker or a person. Under the lighting, so dust in the dark
// can't be seen. High graphics only.

/area
	/// How dusty the air is: AIR_DUST_NONE, AIR_DUST_LIGHT or AIR_DUST_HEAVY
	var/air_dust = AIR_DUST_LIGHT

/area/space
	air_dust = AIR_DUST_NONE

/area/solar
	air_dust = AIR_DUST_NONE

/area/medical
	air_dust = AIR_DUST_NONE

/area/engine/supermatter
	air_dust = AIR_DUST_NONE

/area/maintenance
	air_dust = AIR_DUST_HEAVY

/area/storage
	air_dust = AIR_DUST_HEAVY

/area/quartermaster/warehouse
	air_dust = AIR_DUST_HEAVY

/area/chapel
	air_dust = AIR_DUST_HEAVY

/area/library
	air_dust = AIR_DUST_HEAVY

/area/crew_quarters/abandoned_gambling_den
	air_dust = AIR_DUST_HEAVY

/obj/screen/plane_master/air_dust
	name = "air dust plane master"
	plane = AIR_DUST_PLANE
	blend_mode = BLEND_ADD //dust catching the light adds to it
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/air_dust/backdrop(mob/mymob)
	var/quality = mymob?.client?.prefs ? mymob.client.prefs.graphics_quality() : GRAPHICS_QUALITY_HIGH
	alpha = quality >= GRAPHICS_QUALITY_HIGH ? 255 : 0
	filters = list(
		filter(type = "alpha", render_source = FLOOR_PLANE_RENDER_TARGET),
		filter(type = "alpha", render_source = GAME_PLANE_RENDER_TARGET, flags = MASK_INVERSE))

// ---- The dust over a square of floor

/obj/effect/particle_fx/air_dust
	plane = AIR_DUST_PLANE
	/// The wind it's showing: which way, and how fast its specks go, in pixels a tick (0 in still air)
	var/wind_dir = 0
	var/wind_speed = 0
	/// When the wind it's showing dies down, if none comes before then
	var/wind_until = 0

/obj/effect/particle_fx/air_dust/proc/become(strength)
	// the type in a var of its own: new (a ? b : c) makes the var's own type, a bare /particles, whose specks sit in one white dot
	var/set_type = strength == AIR_DUST_HEAVY ? /particles/fx/air_dust/heavy : /particles/fx/air_dust
	particles = new set_type

/// Wind of a pressure difference over its floor, from SSair. The specks lean into it at once and keep going for a while after it stops,
/// at the strongest the last couple of seconds have had, so a gusty draft doesn't make them flutter.
/obj/effect/particle_fx/air_dust/proc/feel_wind(dir, difference)
	var/speed = difference >= AIR_DUST_WIND_STRONG ? 2 : (difference >= AIR_DUST_WIND_BRISK ? 0.8 : 0.3)
	if(world.time < wind_until && dir == wind_dir && speed < wind_speed)
		speed = wind_speed
	wind_until = world.time + AIR_DUST_WIND_HOLD
	if(!length(GLOB.windy_dust))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sweep_windy_dust)), 1 SECONDS)
	GLOB.windy_dust[src] = TRUE
	blow(dir, speed)

/// Gives its specks a push one way (gravity, held back by friction, so they reach the speed and keep it) and lets new ones in
/// upwind, so they cross the square instead of all leaving it. Direction 0 is still air.
/obj/effect/particle_fx/air_dust/proc/blow(dir, speed)
	if(dir == wind_dir && speed == wind_speed)
		return
	wind_dir = dir
	wind_speed = speed
	var/along_x = (dir & EAST) ? 1 : ((dir & WEST) ? -1 : 0)
	var/along_y = (dir & NORTH) ? 1 : ((dir & SOUTH) ? -1 : 0)
	if(along_x && along_y)
		along_x *= 0.71
		along_y *= 0.71
	var/particles/fx/air_dust/specks = particles
	specks.gravity = list(along_x * speed * AIR_DUST_FRICTION, along_y * speed * AIR_DUST_FRICTION)
	// fast ones live shorter, so they stay in the square's drawing
	specks.lifespan = speed >= 1 ? generator("num", 30, 50) : generator("num", 60, 100)
	var/half = AIR_DUST_SPACING * 16
	var/back = min(speed * 30, half)
	specks.position = generator("box", list(-half - along_x * back, -half - along_y * back, 0), list(half - along_x * back, half - along_y * back, 0))

GLOBAL_LIST_EMPTY(windy_dust)

/// Calms the dust that's had no wind for a while, once a second, for as long as there's any still showing wind
/proc/sweep_windy_dust()
	for(var/obj/effect/particle_fx/air_dust/dust as anything in GLOB.windy_dust)
		if(QDELETED(dust))
			GLOB.windy_dust -= dust
		else if(dust.wind_until <= world.time)
			dust.blow(0, 0)
			GLOB.windy_dust -= dust
	if(length(GLOB.windy_dust))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sweep_windy_dust)), 1 SECONDS)

/obj/effect/particle_fx/air_dust/Destroy()
	GLOB.windy_dust -= src
	return ..()

/turf/open/floor
	/// The dust over the square round this floor, if it's one on the grid that has some
	var/obj/effect/particle_fx/air_dust/air_dust_fx

// A floor laid where there was none gets dust too, if it's on the grid: built, or put back after a breach
/turf/open/floor/Initialize(mapload)
	. = ..()
	if(x % AIR_DUST_SPACING != 2 || y % AIR_DUST_SPACING != 2)
		return
	var/area/A = loc
	if(A.air_dust && is_station_level(z))
		air_dust_fx = new
		air_dust_fx.become(A.air_dust)
		vis_contents += air_dust_fx

/turf/open/floor/Destroy()
	if(air_dust_fx)
		vis_contents -= air_dust_fx
		QDEL_NULL(air_dust_fx)
	return ..()

/turf/open/floor/high_pressure_movements()
	..()
	if(air_dust_fx && pressure_direction && pressure_difference >= AIR_DUST_WIND_PRESSURE)
		air_dust_fx.feel_wind(pressure_direction, pressure_difference)

// ---- Vents and scrubbers moving it

/obj/machinery/atmospherics/components/unary
	/// The air it's moving, as dust, while it runs: "air_dust_vent" blowing out or "air_dust_scrubber" drawing in
	var/dust_flow

/// The shared emitters for a flow: a vent's one, or the eight spokes a scrubber draws specks in along (held straight in the
/// machine's vis_contents: particles in vis_contents nested a level deeper weren't drawn)
/proc/air_dust_flow_fx(kind)
	if(kind == "air_dust_vent")
		return list(particle_fx(kind))
	. = list()
	for(var/dir in GLOB.alldirs)
		. += particle_fx("air_dust_pull[dir]")

/// Shows the dust it moves, or stops: kind is the flow it has now, or null
/obj/machinery/atmospherics/components/unary/proc/set_dust_flow(kind)
	var/area/A = loc?.loc
	if(!A?.air_dust || !is_station_level(z))
		kind = null
	if(kind == dust_flow)
		return
	if(dust_flow)
		vis_contents -= air_dust_flow_fx(dust_flow)
	dust_flow = kind
	if(kind)
		vis_contents += air_dust_flow_fx(kind)

/obj/machinery/atmospherics/components/unary/vent_pump/update_icon_nopipes()
	. = ..()
	var/running = !welded && nodes[1] && on && is_operational()
	set_dust_flow(running ? (pump_direction ? "air_dust_vent" : "air_dust_scrubber") : null) //RELEASING is 1, SIPHONING 0 (vent_pump.dm's own defines)

/obj/machinery/atmospherics/components/unary/vent_scrubber/update_icon_nopipes()
	. = ..()
	set_dust_flow((!welded && nodes[1] && on && is_operational()) ? "air_dust_scrubber" : null)
