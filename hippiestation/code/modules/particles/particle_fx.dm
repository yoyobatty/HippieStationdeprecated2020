// Particles: embers over a fire, a shower of sparks, dust off a bullet hole, debris from a blast, breath in the cold, air rushing
// to a breach. BYOND's particle system draws and moves them on each client, so they cost the server nothing once they're set.
//
// They're all extras. The sprites that were there before (the fire, the spark, the impact flash, the blood on the floor) are
// still there and still say what's happening, so nothing here matters to play. That's what lets every particle sit on a plane
// of its own (PARTICLE_PLANE) that a client on Low graphics just doesn't draw.
//
// Two ways to show one:
//   particle_fx(kind)                  the shared emitter of a kind, for a vis_contents: it runs for as long as it's held there
//   new /obj/effect/particle_fx/burst  an emitter of its own on a turf, starting fresh and gone when its particles are

GLOBAL_LIST_EMPTY(particle_fx)

/obj/screen/plane_master/particles
	name = "particle plane master"
	plane = PARTICLE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/particles/backdrop(mob/mymob)
	var/quality = mymob?.client?.prefs ? mymob.client.prefs.graphics_quality() : GRAPHICS_QUALITY_HIGH
	alpha = quality >= GRAPHICS_QUALITY_MEDIUM ? 255 : 0

/obj/effect/particle_fx
	name = ""
	icon = null //nothing of its own to draw: only its particles
	plane = PARTICLE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	vis_flags = NONE //its own plane, not the holder's: /obj/effect inherits the plane by default, which put particles held in vis_contents on the holder's
	anchored = TRUE
	/// How long a burst of this kind takes to be over, in deciseconds
	var/burst_time = 10

/// Becomes an emitter of a kind. The particle sets themselves are one datum per kind, shared by every emitter of it.
/obj/effect/particle_fx/proc/setup(kind)
	var/static/list/sets = list()
	var/set_type
	switch(kind)
		if("ember")
			set_type = /particles/fx/ember
			blend_mode = BLEND_ADD
		if("sparks")
			set_type = /particles/fx/sparks
			blend_mode = BLEND_ADD
			burst_time = 7
		if("impact_glow")
			set_type = /particles/fx/sparks/impact
			blend_mode = BLEND_ADD
			burst_time = 6
		if("impact_dust")
			set_type = /particles/fx/dust
			burst_time = 7
		if("debris")
			set_type = /particles/fx/debris
			burst_time = 12
		if("debris_big")
			set_type = /particles/fx/debris/big
			burst_time = 16
		if("blood")
			set_type = /particles/fx/blood
			burst_time = 6
		if("motes")
			set_type = /particles/fx/motes
			blend_mode = BLEND_ADD
		if("tesla")
			set_type = /particles/fx/tesla
			blend_mode = BLEND_ADD
		if("breath")
			set_type = /particles/fx/puff/breath
			burst_time = 10
		if("vent_puff")
			set_type = /particles/fx/puff
		if("air_dust_vent") //a vent blowing (air_dust.dm)
			set_type = /particles/fx/air_dust/vent
			plane = AIR_DUST_PLANE
		if("air_dust_burn") //dust burning up (air_dust.dm): on this plane, not the dust's, which the fire's own sprite masks
			set_type = /particles/fx/air_dust_burn
			blend_mode = BLEND_ADD
			burst_time = 10
		else
			if(findtext(kind, "air_dust_pull") == 1) //"air_dust_pull" and a direction: one spoke of the specks a scrubber draws in, from that side
				var/static/list/spokes = list(
					"[NORTH]" = /particles/fx/air_dust/pull/north, "[SOUTH]" = /particles/fx/air_dust/pull/south,
					"[EAST]" = /particles/fx/air_dust/pull/east, "[WEST]" = /particles/fx/air_dust/pull/west,
					"[NORTHEAST]" = /particles/fx/air_dust/pull/northeast, "[NORTHWEST]" = /particles/fx/air_dust/pull/northwest,
					"[SOUTHEAST]" = /particles/fx/air_dust/pull/southeast, "[SOUTHWEST]" = /particles/fx/air_dust/pull/southwest)
				set_type = spokes[copytext(kind, 14)]
				plane = AIR_DUST_PLANE
			if(findtext(kind, "gust") == 1) //"gust" and a direction: air rushing that way
				var/dir = text2num(copytext(kind, 5))
				var/particles/fx/gust/wind = new
				var/along_x = (dir & EAST) ? 1 : ((dir & WEST) ? -1 : 0)
				var/along_y = (dir & NORTH) ? 1 : ((dir & SOUTH) ? -1 : 0)
				wind.velocity = generator("box", list(along_x * 5 - 0.6, along_y * 5 - 0.6, 0), list(along_x * 9 + 0.6, along_y * 9 + 0.6, 0))
				wind.scale = list(along_x ? 2.5 : 0.6, along_y ? 2.5 : 0.6)
				particles = wind
				return
	if(!set_type)
		CRASH("no particle set called [kind]")
	if(!sets[set_type])
		sets[set_type] = new set_type
	particles = sets[set_type]

/proc/particle_fx(kind)
	var/obj/effect/particle_fx/F = GLOB.particle_fx[kind]
	if(!F)
		F = new
		F.setup(kind)
		GLOB.particle_fx[kind] = F
	return F

/// One go of a kind at a turf: at_x and at_y move it off the middle of the tile, in pixels.
/obj/effect/particle_fx/burst/Initialize(mapload, kind, at_x = 0, at_y = 0)
	. = ..()
	if(!kind)
		return INITIALIZE_HINT_QDEL
	setup(kind)
	pixel_x = at_x
	pixel_y = at_y
	QDEL_IN(src, burst_time)

// ---- The sets. Times are deciseconds, speeds pixels a decisecond. A set that spawns its whole count at once is a burst.

/particles/fx
	icon = 'hippiestation/icons/effects/particle_fx.dmi'
	icon_state = "dot"
	width = 128
	height = 128

/// Rising off a fire: bright, then orange, then gone
/particles/fx/ember
	height = 160
	count = 10
	spawning = 0.5
	lifespan = 20
	fade = 10
	fadein = 2
	position = generator("box", list(-12, -10, 0), list(12, 6, 0))
	velocity = generator("box", list(-0.4, 0.8, 0), list(0.4, 2, 0))
	drift = generator("vector", list(-0.3, 0), list(0.3, 0.05))
	friction = 0.04
	gradient = list(0, "#fff0b0", 0.4, "#ff9a30", 1, "#8a2000")
	color = 0
	color_change = 0.05
	scale = generator("vector", list(0.9, 0.9), list(1.6, 1.6))

/// Thrown out of a spark and falling, on each tile it crosses
/particles/fx/sparks
	count = 8
	spawning = 8
	lifespan = 5
	fade = 3
	position = generator("circle", 0, 4)
	velocity = generator("circle", 2, 6)
	gravity = list(0, -0.35)
	friction = 0.1
	gradient = list(0, "#ffffff", 0.5, "#ffd24a", 1, "#ff7a1a")
	color = generator("num", 0, 0.4)
	color_change = 0.12
	scale = generator("vector", list(0.4, 0.4), list(0.9, 0.9))

/// Off whatever a laser or an energy bolt hit
/particles/fx/sparks/impact
	count = 9
	spawning = 9
	lifespan = 4
	velocity = generator("circle", 1.5, 4.5)

/// Off whatever a bullet hit
/particles/fx/dust
	icon_state = "puff"
	count = 7
	spawning = 7
	lifespan = 6
	fade = 5
	position = generator("circle", 0, 2)
	velocity = generator("circle", 0.6, 2.4)
	friction = 0.2
	color = "#c9c4bcb0"
	scale = generator("vector", list(0.25, 0.25), list(0.5, 0.5))
	grow = 0.05

/// Thrown from a blast: chips of whatever was there, a few of them still burning
/particles/fx/debris
	icon_state = "chip"
	width = 256
	height = 256
	count = 40
	spawning = 40
	lifespan = 10
	fade = 6
	position = generator("circle", 0, 10)
	velocity = generator("circle", 3, 9)
	friction = 0.08
	gradient = list(0, "#ffd070", 0.25, "#8c8c8c", 1, "#3a3a3a")
	color = generator("num", 0, 1)
	scale = generator("vector", list(0.5, 0.5), list(1.2, 1.2))
	spin = generator("num", -25, 25)

/particles/fx/debris/big
	width = 420
	height = 420
	count = 80
	spawning = 80
	lifespan = 14
	velocity = generator("circle", 5, 14)

/particles/fx/blood
	icon_state = "chip"
	count = 10
	spawning = 10
	lifespan = 5
	fade = 3
	position = generator("circle", 0, 3)
	velocity = generator("circle", 1.5, 4.5)
	friction = 0.18
	color = "#9c0f0f"
	scale = generator("vector", list(0.4, 0.4), list(0.8, 0.8))

/// Drifting up round the supermatter
/particles/fx/motes
	count = 14
	spawning = 0.3
	lifespan = 30
	fade = 12
	fadein = 6
	position = generator("circle", 6, 20)
	velocity = generator("box", list(-0.2, 0.2, 0), list(0.2, 0.7, 0))
	color = "#fff3a0"
	scale = generator("vector", list(1, 1), list(1.7, 1.7))

/// Crackling round a tesla ball
/particles/fx/tesla
	count = 12
	spawning = 2
	lifespan = 4
	fade = 2
	position = generator("circle", 8, 26)
	velocity = generator("circle", 0, 2)
	color = "#bfe6ff"
	scale = generator("vector", list(0.4, 0.4), list(0.9, 0.9))

/// Air let into a room that hasn't much: a vent's puff
/particles/fx/puff
	icon_state = "puff"
	count = 8
	spawning = 1
	lifespan = 10
	fade = 8
	fadein = 1
	position = generator("circle", 0, 5)
	velocity = generator("circle", 0.5, 1.6)
	friction = 0.06
	color = "#ffffffa0"
	scale = generator("vector", list(0.6, 0.6), list(0.9, 0.9))
	grow = 0.08

/// Breath you can see, from the head: one puff
/particles/fx/puff/breath
	count = 4
	spawning = 4
	lifespan = 9
	fade = 7
	position = generator("box", list(-2, 8, 0), list(2, 10, 0))
	velocity = generator("box", list(-0.3, 0.2, 0), list(0.3, 0.6, 0))
	color = "#ffffffa8"
	scale = generator("vector", list(0.5, 0.5), list(0.7, 0.7))
	grow = 0.07

/// Dust hanging in a room's air, over the floor of its emitter (air_dust.dm): one or two specks at a time. They fade in, wander a
/// few pixels and fade out again, faint, some catching more light than others. Each floor has a set of its own, which wind gives
/// a gravity; the drawing is big enough for the wind to carry them a few tiles on
/particles/fx/air_dust
	icon_state = "mote"
	width = 224
	height = 224
	count = 2
	spawning = AIR_DUST_SPAWNING
	lifespan = generator("num", 60, 100)
	fade = 25
	fadein = 25
	position = generator("box", list(-12, -12, 0), list(12, 12, 0))
	velocity = generator("circle", 0.05, 0.12) //a pixel a second, curving: still air, but not stopped
	drift = generator("circle", 0, 0.006)
	friction = AIR_DUST_FRICTION
	gradient = list(0, "#fff3dc2c", 1, "#fff6e878")
	color = generator("num", 0, 1)
	scale = generator("vector", list(0.7, 0.7), list(1.05, 1.05))

/// Dust burning up in a fire or air too hot for it: a spark or two over its floor, gone in a moment
/particles/fx/air_dust_burn
	count = 3
	spawning = 3
	lifespan = generator("num", 5, 9)
	fade = 5
	position = generator("box", list(-12, -12, 0), list(12, 12, 0))
	velocity = generator("box", list(-0.15, 0.1, 0), list(0.15, 0.5, 0))
	gradient = list(0, "#fff4c8", 0.5, "#ffa040", 1, "#a03000")
	color = 0
	color_change = 0.15
	scale = generator("vector", list(0.5, 0.5), list(0.9, 0.9))

/// Blown out of a running vent: quick at the grille, slowing over a couple of tiles and left to hang
/particles/fx/air_dust/vent
	count = 9
	spawning = 0.15
	lifespan = generator("num", 40, 60)
	fadein = 4
	position = generator("circle", 0, 5)
	velocity = generator("circle", 1.5, 2)
	friction = 0.03

/// Drawn in to a scrubber from one side (setup() aims each spoke's), fading as they reach it
/particles/fx/air_dust/pull
	width = 160
	height = 160
	count = 3
	spawning = 0.06
	lifespan = generator("num", 48, 56)
	fadein = 8
	fade = 14
	drift = generator("circle", 0, 0.004)
	friction = 0

// One spoke from each side, AIR_DUST_PULL_REACH (40) pixels out, heading in. Written out, since generators made while the map
// loads (a scrubber's first spoke) drew nothing on the client

/particles/fx/air_dust/pull/north
	position = generator("box", list(-10, 30, 0), list(10, 50, 0))
	velocity = generator("box", list(-0.08, -0.93, 0), list(0.08, -0.57, 0))

/particles/fx/air_dust/pull/south
	position = generator("box", list(-10, -50, 0), list(10, -30, 0))
	velocity = generator("box", list(-0.08, 0.57, 0), list(0.08, 0.93, 0))

/particles/fx/air_dust/pull/east
	position = generator("box", list(30, -10, 0), list(50, 10, 0))
	velocity = generator("box", list(-0.93, -0.08, 0), list(-0.57, 0.08, 0))

/particles/fx/air_dust/pull/west
	position = generator("box", list(-50, -10, 0), list(-30, 10, 0))
	velocity = generator("box", list(0.57, -0.08, 0), list(0.93, 0.08, 0))

/particles/fx/air_dust/pull/northeast
	position = generator("box", list(18.4, 18.4, 0), list(38.4, 38.4, 0))
	velocity = generator("box", list(-0.683, -0.683, 0), list(-0.381, -0.381, 0))

/particles/fx/air_dust/pull/northwest
	position = generator("box", list(-38.4, 18.4, 0), list(-18.4, 38.4, 0))
	velocity = generator("box", list(0.381, -0.683, 0), list(0.683, -0.381, 0))

/particles/fx/air_dust/pull/southeast
	position = generator("box", list(18.4, -38.4, 0), list(38.4, -18.4, 0))
	velocity = generator("box", list(-0.683, 0.381, 0), list(-0.381, 0.683, 0))

/particles/fx/air_dust/pull/southwest
	position = generator("box", list(-38.4, -38.4, 0), list(-18.4, -18.4, 0))
	velocity = generator("box", list(0.381, 0.381, 0), list(0.683, 0.683, 0))

/// Air on its way to a breach: setup() gives a copy of this its direction
/particles/fx/gust
	count = 9
	spawning = 1.2
	lifespan = 6
	fade = 3
	position = generator("box", list(-16, -16, 0), list(16, 16, 0))
	color = "#dfe6eec0"

// ---- What gives them off

/obj/effect/hotspot/Initialize(mapload, starting_volume, starting_temperature)
	. = ..()
	if(!(x % 2) && !(y % 2)) //one fire in four, the ones that carry a pool of light (light_glow.dm): a big fire is hundreds of these
		vis_contents += particle_fx("ember")

// A spark leaves a shower on each tile it leaves, and on the one it ends on. Each shower is a burst of its own on the floor. An
// emitter carried by the spark would drag its particles along: they're drawn relative to the emitter, so a shower that had fallen
// from the spark moved a tile with it at each step.
/obj/effect/particle_effect/sparks/Move()
	var/turf/from = loc
	var/whole_step = !moving_diagonally //a diagonal step is two Move()s inside this one: the burst goes where the whole step began
	. = ..()
	if(whole_step && loc != from && isturf(from))
		new /obj/effect/particle_fx/burst(from, "sparks")

/obj/effect/particle_effect/sparks/Destroy()
	if(isturf(loc))
		new /obj/effect/particle_fx/burst(loc, "sparks")
	return ..()

/obj/effect/temp_visual/impact_effect/Initialize(mapload, x, y)
	. = ..()
	if(isturf(loc))
		new /obj/effect/particle_fx/burst(loc, icon_state == "impact_bullet" ? "impact_dust" : "impact_glow", x, y)

/datum/controller/subsystem/explosions/explode(atom/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range, adminlog, ignorecap, flame_range, silent, smoke, atom/explosion_cause)
	var/turf/middle = get_turf(epicenter)
	if(middle && (devastation_range || heavy_impact_range || light_impact_range))
		new /obj/effect/particle_fx/burst(middle, (heavy_impact_range >= 2 || light_impact_range >= 5) ? "debris_big" : "debris")
	return ..()

/mob/living/add_splatter_floor(turf/T, small_drip)
	..()
	if(!small_drip && get_blood_id() == /datum/reagent/blood)
		new /obj/effect/particle_fx/burst(T || get_turf(src), "blood")

/obj/machinery/power/supermatter_crystal/Initialize()
	. = ..()
	vis_contents += particle_fx("motes")

/obj/singularity/energy_ball/Initialize(mapload, starting_energy = 50, is_miniball = FALSE)
	. = ..()
	vis_contents += particle_fx("tesla")

// Breath shows in air under two degrees: a freezer, a room open to space. On internals it's the tank's air that's breathed, so a
// spacesuit shows none. Each breath is a puff left in the air where it was breathed, not an emitter on the mob: someone walking
// on leaves it behind, where one held in their vis_contents was carried along with them.
/mob/living/carbon/human/check_breath(datum/gas_mixture/breath)
	. = ..()
	if(breath && stat != DEAD && isturf(loc) && breath.temperature < T0C + 2 && breath.total_moles() > 0)
		new /obj/effect/particle_fx/burst(loc, "breath")

// A vent pushing a lot of air into a room at once (vent_pump.dm calls this): the room's being filled back up.
/obj/machinery/atmospherics/components/unary/vent_pump
	var/puff_until = 0

/obj/machinery/atmospherics/components/unary/vent_pump/proc/puff()
	if(puff_until > world.time)
		return
	puff_until = world.time + 2 SECONDS
	vis_contents |= particle_fx("vent_puff")
	addtimer(CALLBACK(src, PROC_REF(end_puff)), 2 SECONDS)

/obj/machinery/atmospherics/components/unary/vent_pump/proc/end_puff()
	if(puff_until <= world.time)
		vis_contents -= particle_fx("vent_puff")

// Air rushing to a breach: tiles with wind strong enough to shove things show it, in the wind's direction. They're swept off
// again together, once a second, by one timer for all of them.
GLOBAL_LIST_EMPTY(gusting_turfs)

/turf/open
	var/obj/effect/particle_fx/gust_fx
	var/gust_until = 0

/turf/open/high_pressure_movements()
	..()
	if(pressure_difference < PARTICLE_GUST_PRESSURE || !pressure_direction)
		return
	gust_until = world.time + 1.2 SECONDS
	var/obj/effect/particle_fx/wind = particle_fx("gust[pressure_direction]")
	if(gust_fx == wind)
		return
	if(gust_fx)
		vis_contents -= gust_fx
	else
		if(length(GLOB.gusting_turfs) >= PARTICLE_GUST_TILES)
			return
		if(!length(GLOB.gusting_turfs))
			addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sweep_gusts)), 1 SECONDS)
		GLOB.gusting_turfs += src
	gust_fx = wind
	vis_contents += wind

/proc/sweep_gusts()
	for(var/turf/open/T as anything in GLOB.gusting_turfs)
		if(T.gust_until > world.time)
			continue
		T.vis_contents -= T.gust_fx
		T.gust_fx = null
		GLOB.gusting_turfs -= T
	if(length(GLOB.gusting_turfs))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sweep_gusts)), 1 SECONDS)
