// Dust in the air: specks hanging over the floor and wandering about, seen where the light catches them. More of it in
// maintenance, storage, the chapel and the library; none in medical. The air moves it: a running vent blows specks out, a
// scrubber (or a vent siphoning) draws them in, and wind carries them along. It needs air to hang in, and burns up in a fire.
//
// One floor in each little square of the station (AIR_DUST_CELL_LIGHT tiles a side, AIR_DUST_CELL_HEAVY where it's dusty, the
// floor picked at random so they don't line up) holds an emitter in its vis_contents that lets specks go over that floor alone,
// so they're spread out evenly and none start in a wall or over a table. Each has its own particle set, so wind over its floor
// bends the specks already in the air (a new gravity) instead of starting them over. SSair_dust looks at each now and then:
// with something standing on its floor (anything solid, a table, a machine, a locker) or air too thin to hold dust, it lets no
// more go and the ones in the air settle; a fire or air too hot burns them up at once, and none come back for a while. Floors
// the map gave air of their own (the mix and burn chambers, the gas tanks, telecomms) never hold any.
// Vents and scrubbers hold shared emitters of their own while they run, a scrubber drawing in only from sides that are open
// floor. Everything is drawn on a plane of its own (AIR_DUST_PLANE) that a client masks twice: by the floor plane, so there's
// no dust over space or out past a window, and by the game plane turned inside out, so none over a wall or in front of a
// locker or a person. Under the lighting, so dust in the dark can't be seen. High graphics only.

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

// ---- Keeping it up: what's on each dust floor, its air, and the wind dying down

SUBSYSTEM_DEF(air_dust)
	name = "Air dust"
	wait = 1 SECONDS
	flags = SS_NO_INIT | SS_BACKGROUND
	priority = FIRE_PRIORITY_VIS
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	/// Every floor's dust emitter
	var/list/seeds = list()
	/// Vents and scrubbers running where there's dust, as keys
	var/list/flows = list()
	/// Dust showing wind, as keys
	var/list/windy = list()
	/// Where the looks have got to in seeds and flows, and how many are left this time round
	var/seed_at = 1
	var/flow_at = 1
	var/seeds_left = 0
	var/flows_left = 0
	/// The squares of the map (AIR_DUST_UNSEEN_CELL()) a player can see into or is about to, as keys, worked out at each fire
	/// from SSlighting.eyes. Dust outside them isn't looked at. Null when everything is (SSlighting.defer_unseen off).
	var/list/watched_cells

/datum/controller/subsystem/air_dust/stat_entry(msg)
	return ..("S:[length(seeds)] F:[length(flows)] W:[length(windy)]")

/datum/controller/subsystem/air_dust/fire(resumed)
	if(!resumed)
		// Calms the dust that's had no wind for a while
		for(var/obj/effect/particle_fx/air_dust/dust as anything in windy)
			if(dust.wind_until <= world.time)
				dust.blow(0, 0)
				windy -= dust
		seeds_left = CEILING(length(seeds) / AIR_DUST_CHECK_FIRES, 1)
		flows_left = CEILING(length(flows) / AIR_DUST_CHECK_FIRES, 1)
		// Dust nobody is near isn't looked at. It's only ever seen, so what's on its floor and how its air is can wait until a
		// player is within a screen and a bit of it, as a light's update does (SSlighting.eyes, /datum/light_source/proc/can_wait_unseen()).
		// Its turn still comes round every AIR_DUST_CHECK_FIRES fires, so it's looked at within that long of a player coming
		// near: no later than dust in plain view learns of a change. A fire still burns it up at once (hotspot/Initialize() below).
		watched_cells = null
		if(SSlighting.defer_unseen)
			watched_cells = list()
			for(var/turf/eye as anything in SSlighting.eyes)
				var/reach = SSlighting.eyes[eye] + AIR_DUST_UNSEEN_MARGIN
				for(var/cell_y in (max(eye.y - reach, 1) >> 3) to (min(eye.y + reach, world.maxy) >> 3))
					for(var/cell_x in (max(eye.x - reach, 1) >> 3) to (min(eye.x + reach, world.maxx) >> 3))
						watched_cells["[cell_x]|[cell_y]|[eye.z]"] = TRUE
	var/list/watched = watched_cells
	while(seeds_left > 0 && length(seeds))
		if(seed_at > length(seeds))
			seed_at = 1
		var/obj/effect/particle_fx/air_dust/dust = seeds[seed_at++]
		seeds_left--
		if(!watched || watched[dust.dust_cell])
			dust.check()
		if(MC_TICK_CHECK)
			return
	while(flows_left > 0 && length(flows))
		if(flow_at > length(flows))
			flow_at = 1
		var/obj/machinery/atmospherics/components/unary/U = flows[flow_at++]
		flows_left--
		var/turf/where = U.loc
		if(!watched || !isturf(where) || watched[AIR_DUST_UNSEEN_CELL(where)])
			U.update_dust_flow()
		if(MC_TICK_CHECK)
			return

/// Something on a floor that dust doesn't hang over: anything solid, or a table, a machine, a chair or the like standing on it.
/// Not what's under the floor (pipes, wires, a vent) or hung on a wall, and not a mob or an item.
/proc/air_dust_blocked(turf/T)
	for(var/obj/O in T)
		if(O.density)
			return TRUE
		if((isstructure(O) || ismachinery(O)) && O.layer >= LOW_OBJ_LAYER && O.layer < WALL_OBJ_LAYER && abs(O.pixel_x) < 16 && abs(O.pixel_y) < 16)
			return TRUE
	return FALSE

/// Whether a floor's air keeps dust: not too thin, not too hot, no fire. Read straight off the turf, not with return_air(),
/// which marks the air as handed out and has the tile engine send it again.
/proc/air_dust_air_ok(turf/open/T)
	if(T.active_hotspot)
		return FALSE
	var/datum/gas_mixture/G = T.air
	return !G || (G.temperature < AIR_DUST_BURN_TEMPERATURE && G.return_pressure() >= AIR_DUST_MIN_PRESSURE)

/// Whether a floor is the one in its square of the dust grid (cell tiles a side) that holds dust. Each square's floor is picked at
/// random the first time it's asked about, for each size of square and each z-level.
/proc/air_dust_picked(x, y, z, cell)
	var/static/list/grids = list()
	var/list/picks = grids["[cell] [z]"]
	var/columns = CEILING(world.maxx / cell, 1)
	if(!picks)
		picks = new /list(columns * CEILING(world.maxy / cell, 1))
		grids["[cell] [z]"] = picks
	var/square = round((x - 1) / cell) + round((y - 1) / cell) * columns + 1
	if(square > length(picks))
		picks.len = square
	if(!picks[square])
		picks[square] = rand(1, cell * cell)
	return picks[square] == ((x - 1) % cell) + ((y - 1) % cell) * cell + 1

// ---- The dust over a floor

/obj/effect/particle_fx/air_dust
	plane = AIR_DUST_PLANE
	/// The floor it's over
	var/turf/open/floor/home
	/// Its own set of specks, kept while it shows none
	var/particles/fx/air_dust/specks
	/// Burnt up: none again before this
	var/burnt_until = 0
	/// The wind it's showing: which way, and how fast its specks go, in pixels a tick (0 in still air)
	var/wind_dir = 0
	var/wind_speed = 0
	/// When the wind it's showing dies down, if none comes before then
	var/wind_until = 0
	/// The square of the map its floor is in (AIR_DUST_UNSEEN_CELL()), for SSair_dust.watched_cells
	var/dust_cell

/obj/effect/particle_fx/air_dust/Destroy()
	SSair_dust.seeds -= src
	SSair_dust.windy -= src
	home = null
	particles = null
	specks = null
	return ..()

/// Looks at its floor: lets specks go, lets them settle, or burns them up
/obj/effect/particle_fx/air_dust/proc/check()
	var/turf/open/floor/T = home
	var/datum/gas_mixture/G = T.air
	if(T.active_hotspot || G?.temperature >= AIR_DUST_BURN_TEMPERATURE)
		burn_up()
		return
	if(world.time < burnt_until)
		return
	if((!G || G.return_pressure() >= AIR_DUST_MIN_PRESSURE) && !air_dust_blocked(T))
		if(!particles)
			specks.spawning = AIR_DUST_SPAWNING
			particles = specks
		else if(!specks.spawning)
			specks.spawning = AIR_DUST_SPAWNING
	else if(particles)
		if(specks.spawning)
			specks.spawning = 0 //no more: the ones in the air see out their time
		else
			particles = null //settling since the last look, AIR_DUST_CHECK_FIRES seconds ago: longer than a speck lives

/// Burns its specks up: they flare and are gone, and none come back for AIR_DUST_BURNT_FOR
/obj/effect/particle_fx/air_dust/proc/burn_up()
	burnt_until = world.time + AIR_DUST_BURNT_FOR
	if(!particles)
		return
	particles = null
	new /obj/effect/particle_fx/burst(home, "air_dust_burn")

/// Wind of a pressure difference over its floor, from SSair. The specks lean into it at once and keep going for a while after it stops,
/// at the strongest the last couple of seconds have had, so a gusty draft doesn't make them flutter.
/obj/effect/particle_fx/air_dust/proc/feel_wind(dir, difference)
	var/speed = difference >= AIR_DUST_WIND_STRONG ? 2 : (difference >= AIR_DUST_WIND_BRISK ? 0.8 : 0.3)
	if(world.time < wind_until && dir == wind_dir && speed < wind_speed)
		speed = wind_speed
	wind_until = world.time + AIR_DUST_WIND_HOLD
	SSair_dust.windy[src] = TRUE
	blow(dir, speed)

/// Gives its specks a push one way (gravity, held back by friction, so they reach the speed and keep it). They still start over
/// its own floor, and fly on over the next ones. Direction 0 is still air.
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
	specks.gravity = list(along_x * speed * AIR_DUST_FRICTION, along_y * speed * AIR_DUST_FRICTION)
	// fast ones live shorter, so they stay in its drawing
	specks.lifespan = speed >= 1 ? generator("num", 30, 50) : generator("num", 60, 100)

/turf/open/floor
	/// The dust over this floor, if it's the one in its square of the grid that has some
	var/obj/effect/particle_fx/air_dust/air_dust_fx

// A floor laid where there was none gets dust too, if it's the one in its square: built, or put back after a breach
/turf/open/floor/Initialize(mapload)
	. = ..()
	var/area/A = loc
	if(!A.air_dust || initial_gas_mix != OPENTURF_DEFAULT_ATMOS || !is_station_level(z))
		return
	if(!air_dust_picked(x, y, z, A.air_dust == AIR_DUST_HEAVY ? AIR_DUST_CELL_HEAVY : AIR_DUST_CELL_LIGHT))
		return
	var/obj/effect/particle_fx/air_dust/dust = new
	dust.home = src
	dust.dust_cell = AIR_DUST_UNSEEN_CELL(src)
	dust.specks = new /particles/fx/air_dust
	air_dust_fx = dust
	vis_contents += dust
	SSair_dust.seeds += dust
	if(!air_dust_blocked(src) && air_dust_air_ok(src))
		dust.particles = dust.specks

/turf/open/floor/Destroy()
	if(air_dust_fx)
		vis_contents -= air_dust_fx
		QDEL_NULL(air_dust_fx)
	return ..()

/turf/open/floor/high_pressure_movements()
	..()
	if(air_dust_fx && pressure_direction && pressure_difference >= AIR_DUST_WIND_PRESSURE)
		air_dust_fx.feel_wind(pressure_direction, pressure_difference)

// A fire burns up the dust on its floor at once, and stops a vent or scrubber there moving any
/obj/effect/hotspot/Initialize(mapload, starting_volume, starting_temperature)
	. = ..()
	var/turf/open/floor/T = loc
	if(!istype(T))
		return
	T.air_dust_fx?.burn_up()
	for(var/obj/machinery/atmospherics/components/unary/U in T)
		if(U.dust_flow)
			U.update_dust_flow()

// ---- Vents and scrubbers moving it

/obj/machinery/atmospherics/components/unary
	/// The air it's moving, as dust, while it runs: "air_dust_vent" blowing out or "air_dust_scrubber" drawing in
	var/dust_flow
	/// The shared emitters it holds for that now: none while the air over it can't hold dust
	var/list/dust_shown
	/// The emitters for its flow with the air fine: a scrubber's spokes are worked out again once a while (AIR_DUST_SPOKES_FOR),
	/// since what's round it seldom changes and looking at all eight sides is most of SSair_dust's work
	var/list/dust_flow_emitters
	var/dust_flow_emitters_until = 0

/obj/machinery/atmospherics/components/unary/Destroy()
	SSair_dust.flows -= src
	dust_shown = null
	dust_flow_emitters = null
	return ..()

/// Runs or stops: kind is the flow it has now, or null
/obj/machinery/atmospherics/components/unary/proc/set_dust_flow(kind)
	var/area/A = loc?.loc
	if(!A?.air_dust || !is_station_level(z))
		kind = null
	if(kind == dust_flow)
		return
	dust_flow = kind
	dust_flow_emitters_until = 0
	if(kind)
		SSair_dust.flows[src] = TRUE
	else
		SSair_dust.flows -= src
	update_dust_flow()

/// The shared emitters for its flow as things are: a vent's one, or a scrubber's spokes from each side that's open floor with
/// nothing on it (held straight in the machine's vis_contents: particles in vis_contents nested a level deeper weren't drawn)
/obj/machinery/atmospherics/components/unary/proc/dust_flow_fx()
	var/turf/open/T = loc
	if(!dust_flow || !istype(T) || air_dust_blocked(T) || !air_dust_air_ok(T))
		return null
	if(world.time < dust_flow_emitters_until)
		return dust_flow_emitters
	dust_flow_emitters_until = world.time + AIR_DUST_SPOKES_FOR
	if(dust_flow == "air_dust_vent")
		dust_flow_emitters = list(particle_fx(dust_flow))
		return dust_flow_emitters
	var/static/list/spoke_kinds
	if(!spoke_kinds)
		spoke_kinds = list()
		for(var/dir in GLOB.alldirs)
			spoke_kinds["[dir]"] = "air_dust_pull[dir]"
	dust_flow_emitters = null
	for(var/dir in GLOB.alldirs)
		var/turf/open/floor/side = get_step(T, dir)
		if(istype(side) && !air_dust_blocked(side))
			LAZYADD(dust_flow_emitters, particle_fx(spoke_kinds["[dir]"]))
	return dust_flow_emitters

/// Shows the dust it moves as things are now: when it starts or stops, when a fire starts over it, and now and then from SSair_dust
/obj/machinery/atmospherics/components/unary/proc/update_dust_flow()
	var/list/now = dust_flow_fx()
	if(now == dust_shown || (length(now) == length(dust_shown) && !length(now - dust_shown)))
		return
	if(dust_shown)
		vis_contents -= dust_shown
	dust_shown = now
	if(now)
		vis_contents += now

/obj/machinery/atmospherics/components/unary/vent_pump/update_icon_nopipes()
	. = ..()
	var/running = !welded && nodes[1] && on && is_operational()
	set_dust_flow(running ? (pump_direction ? "air_dust_vent" : "air_dust_scrubber") : null) //RELEASING is 1, SIPHONING 0 (vent_pump.dm's own defines)

/obj/machinery/atmospherics/components/unary/vent_scrubber/update_icon_nopipes()
	. = ..()
	set_dust_flow((!welded && nodes[1] && on && is_operational()) ? "air_dust_scrubber" : null)
