// Particles: embers over a fire, a shower of sparks, dust off a bullet hole, debris from a blast, breath in the cold, air rushing
// to a breach. BYOND's particle system draws and moves them on each client, so they cost the server nothing once they're set.
//
// They're all extras. The sprites that were there before (the fire, the spark, the impact flash, the blood on the floor) are
// still there and still say what's happening, so nothing here matters to play. That's what lets every particle sit on a plane
// of its own (PARTICLE_PLANE) that a client on Low graphics just doesn't draw.
//
// The sprites are tg's particle sheets (hippiestation/icons/effects/particles/, from tgstation 8ae7ebcf): a few hard pixels
// each, coloured and scaled by the sets here. The sets that tg has (embers, sparks, smoke, steam, breath) start from tg's.
//
// Two ways to show one:
//   particle_fx(kind)                  the shared emitter of a kind, for a vis_contents: it runs for as long as it's held there
//   new /obj/effect/particle_fx/burst  an emitter of its own on a turf, starting fresh and gone when its particles are

GLOBAL_LIST_EMPTY(particle_fx)
/// Bursts in the world now: past PARTICLE_BURSTS_MAX no more are made
GLOBAL_VAR_INIT(particle_bursts, 0)

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
	blend_mode = BLEND_OVERLAY //its own, whatever holds it: a fire is drawn added to the floor, and its smoke mustn't be
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | PIXEL_SCALE
	vis_flags = NONE //its own plane, not the holder's: /obj/effect inherits the plane by default, which put particles held in vis_contents on the holder's
	anchored = TRUE
	/// How long a burst of this kind takes to be over, in deciseconds
	var/burst_time = 10

/// Each kind: its particle set and how long a burst of it lasts (a burst's particles all live one tick longer than that, so none
/// has died and been let go a second time before the emitter is gone)
GLOBAL_LIST_INIT(particle_fx_kinds, list(
	"ember" = list(/particles/fx/ember, 0),
	"sparks" = list(/particles/fx/sparks, 8),
	"impact_red" = list(/particles/fx/sparks/impact, 5),
	"impact_blue" = list(/particles/fx/sparks/impact/blue, 5),
	"impact_green" = list(/particles/fx/sparks/impact/green, 5),
	"impact_purple" = list(/particles/fx/sparks/impact/purple, 5),
	"impact_ion" = list(/particles/fx/sparks/impact/ion, 5),
	"impact_dust" = list(/particles/fx/dust, 8),
	"impact_chips" = list(/particles/fx/chips, 5),
	"debris" = list(/particles/fx/debris, 11),
	"debris_big" = list(/particles/fx/debris/big, 15),
	"debris_burning" = list(/particles/fx/debris_burning, 13),
	"debris_burning_big" = list(/particles/fx/debris_burning/big, 17),
	"blast_smoke" = list(/particles/fx/blast_smoke, 15),
	"blast_smoke_big" = list(/particles/fx/blast_smoke/big, 21),
	"blood" = list(/particles/fx/blood, 6),
	"motes" = list(/particles/fx/motes, 0),
	"tesla" = list(/particles/fx/tesla, 0),
	"breath" = list(/particles/fx/breath, 11),
	"vent_puff" = list(/particles/fx/puff, 0),
	// particle_smoke.dm
	"ember_hot" = list(/particles/fx/ember/hot, 0),
	"ember_tritium" = list(/particles/fx/ember/tritium, 0),
	"fire_smoke" = list(/particles/fx/fire_smoke, 0),
	"burning_smoke" = list(/particles/fx/burning_smoke, 0),
	"cig_smoke" = list(/particles/fx/cig_smoke, 12),
	"vape_cloud" = list(/particles/fx/cig_smoke/vape, 15),
	"cook_steam" = list(/particles/fx/cook_steam, 0),
	"grill_smoke" = list(/particles/fx/cook_steam/grill, 0),
	"shower_steam" = list(/particles/fx/shower_steam, 0),
	"shower_drops" = list(/particles/fx/shower_drops, 0),
	"gas_wisp" = list(/particles/fx/gas_wisp, 0),
	"gas_wisp_plasma" = list(/particles/fx/gas_wisp/plasma, 0),
	"gas_wisp_tritium" = list(/particles/fx/gas_wisp/tritium, 0),
	"gas_burst" = list(/particles/fx/gas_burst, 11),
	// particle_tools.dm
	"welding" = list(/particles/fx/sparks/welding, 0),
	"weld_sparks" = list(/particles/fx/sparks/weld_burst, 6),
	"water_mist" = list(/particles/fx/water_mist, 6),
	"muzzle_smoke" = list(/particles/fx/muzzle_smoke, 9),
	"break_smoke" = list(/particles/fx/break_smoke, 15),
	// particle_mobs.dm
	"mob_fire" = list(/particles/fx/ember/mob, 0),
	"stink" = list(/particles/fx/stink, 0),
	"acid" = list(/particles/fx/acid, 0),
	"blood_drip" = list(/particles/fx/blood/drip, 5),
	"foot_dust" = list(/particles/fx/foot_dust, 8),
	"rad_glint" = list(/particles/fx/rad_glint, 0),
	// particle_destruction.dm
	"glass_shards" = list(/particles/fx/glass_shards, 8),
	"rubble" = list(/particles/fx/rubble, 9),
	"rubble_dust" = list(/particles/fx/rubble_dust, 13),
	"rock_chips" = list(/particles/fx/rubble/rock, 9),
	"wire_sparks" = list(/particles/fx/sparks/wire, 5),
	"air_dust_vent" = list(/particles/fx/air_dust/vent, 0), //a vent blowing (air_dust.dm)
	"air_dust_burn" = list(/particles/fx/air_dust_burn, 8), //dust burning up (air_dust.dm): on this plane, not the dust's, which the fire's own sprite masks
	"air_dust_pull[NORTH]" = list(/particles/fx/air_dust/pull/north, 0), //"air_dust_pull" and a direction: one spoke of the specks a scrubber draws in, from that side
	"air_dust_pull[SOUTH]" = list(/particles/fx/air_dust/pull/south, 0),
	"air_dust_pull[EAST]" = list(/particles/fx/air_dust/pull/east, 0),
	"air_dust_pull[WEST]" = list(/particles/fx/air_dust/pull/west, 0),
	"air_dust_pull[NORTHEAST]" = list(/particles/fx/air_dust/pull/northeast, 0),
	"air_dust_pull[NORTHWEST]" = list(/particles/fx/air_dust/pull/northwest, 0),
	"air_dust_pull[SOUTHEAST]" = list(/particles/fx/air_dust/pull/southeast, 0),
	"air_dust_pull[SOUTHWEST]" = list(/particles/fx/air_dust/pull/southwest, 0)))

/// Becomes an emitter of a kind. The particle sets themselves are one datum per kind, shared by every emitter of it.
/obj/effect/particle_fx/proc/setup(kind)
	var/static/list/sets = list()
	if(findtext(kind, "gust") == 1) //"gust" and a direction: air rushing that way, streaks lying along it
		var/dir = text2num(copytext(kind, 5))
		var/particles/fx/gust/wind = new
		var/along_x = (dir & EAST) ? 1 : ((dir & WEST) ? -1 : 0)
		var/along_y = (dir & NORTH) ? 1 : ((dir & SOUTH) ? -1 : 0)
		wind.velocity = generator("box", list(along_x * 5 - 0.6, along_y * 5 - 0.6, 0), list(along_x * 9 + 0.6, along_y * 9 + 0.6, 0))
		wind.rotation = !along_x ? 0 : (!along_y ? 90 : (along_x == along_y ? 45 : -45)) //the streak sprite stands upright
		particles = wind
		return
	var/list/how = GLOB.particle_fx_kinds[kind]
	if(!how)
		CRASH("no particle set called [kind]")
	var/set_type = how[1]
	if(how[2])
		burst_time = how[2]
	if(findtext(kind, "air_dust_vent") == 1 || findtext(kind, "air_dust_pull") == 1)
		plane = AIR_DUST_PLANE
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

/obj/effect/particle_fx/Destroy()
	particles = null
	return ..()

/// One go of a kind at a turf, unless there are PARTICLE_BURSTS_MAX about already (a pile of things all going off)
/proc/particle_burst(turf/T, kind, at_x = 0, at_y = 0)
	if(T && GLOB.particle_bursts < PARTICLE_BURSTS_MAX)
		new /obj/effect/particle_fx/burst(T, kind, at_x, at_y)

/// One go of a kind at a turf: at_x and at_y move it off the middle of the tile, in pixels.
/// With PARTICLE_BURSTS_MAX of them about already it isn't made: particle_burst() checks that before making one at all.
/obj/effect/particle_fx/burst
	var/counted = FALSE

/obj/effect/particle_fx/burst/Initialize(mapload, kind, at_x = 0, at_y = 0)
	. = ..()
	if(!kind || GLOB.particle_bursts >= PARTICLE_BURSTS_MAX)
		return INITIALIZE_HINT_QDEL
	GLOB.particle_bursts++
	counted = TRUE
	setup(kind)
	pixel_x = at_x
	pixel_y = at_y
	QDEL_IN(src, burst_time)

/obj/effect/particle_fx/burst/Destroy()
	if(counted)
		GLOB.particle_bursts--
		counted = FALSE
	return ..()

// ---- The sets. Times are deciseconds, speeds pixels a decisecond. A set that spawns its whole count at once is a burst: its
// particles all live the same time, one tick more than the kind's burst time above.
// They're kept sharp: plain colours (not added to the floor's), and every sprite at its own size or twice it, never turned
// and never growing, since a sprite of a few pixels drawn at any other size or angle is a smudge. Sizes vary by the sprite.

/particles/fx
	icon = 'hippiestation/icons/effects/particles/generic.dmi'
	icon_state = "dot"
	width = 128
	height = 128

/// Rising off a fire: bright, then orange, then gone (tg's embers, fewer: a big fire is many of these)
/particles/fx/ember
	icon_state = list("dot" = 3, "cross" = 2, "curl" = 2)
	height = 192
	count = 24
	spawning = 1
	lifespan = generator("num", 18, 30)
	fade = 10
	fadein = 1
	position = generator("box", list(-16, -14, 0), list(16, 10, 0))
	velocity = generator("box", list(-0.3, 0.6, 0), list(0.3, 1.8, 0))
	drift = generator("vector", list(-0.25, 0), list(0.25, 0.05))
	friction = 0.03
	gradient = list(0, "#fce6b6", 0.35, "#fbaf4d", 1, "#fd481c")
	color = 0
	color_change = 0.04

/// Thrown out of a spark and falling, on each tile it crosses: white hot, cooling to orange
/particles/fx/sparks
	icon_state = list("dot" = 3, "cross" = 2, "curl" = 2)
	count = 16
	spawning = 16
	lifespan = 9
	fade = 4
	position = generator("circle", 0, 3)
	velocity = generator("circle", 2, 7)
	gravity = list(0, -0.45)
	friction = 0.08
	gradient = list(0, "#ffffff", 0.4, "#fce6b6", 0.7, "#fbaf4d", 1, "#fd481c")
	color = generator("num", 0, 0.3)
	color_change = 0.09

/// Off whatever a laser or an energy bolt hit, in the beam's colour: this one a red laser's
/particles/fx/sparks/impact
	icon_state = list("dot" = 2, "cross" = 1)
	count = 10
	spawning = 10
	lifespan = 6
	fade = 3
	velocity = generator("circle", 1.5, 5)
	gravity = list(0, -0.2)
	gradient = list(0, "#ffffff", 0.4, "#ff9a80", 1, "#e81010")
	color_change = 0.14

/particles/fx/sparks/impact/blue
	gradient = list(0, "#ffffff", 0.4, "#9ad0ff", 1, "#2060ff")

/particles/fx/sparks/impact/green
	gradient = list(0, "#ffffff", 0.4, "#a8ffa0", 1, "#10c828")

/particles/fx/sparks/impact/purple
	gradient = list(0, "#ffffff", 0.4, "#e4a8ff", 1, "#9828e8")

/particles/fx/sparks/impact/ion
	gradient = list(0, "#ffffff", 0.4, "#c0f4ff", 1, "#40c0ff")

/// Off whatever a bullet hit: a puff of dust
/particles/fx/dust
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 1, "steam_2" = 1, "steam_3" = 1)
	count = 3
	spawning = 3
	lifespan = 9
	fade = 6
	position = generator("circle", 0, 2)
	velocity = generator("circle", 0.3, 1.2)
	friction = 0.15
	color = "#c9c4bcd8"

/// And the chips knocked out of it
/particles/fx/chips
	icon_state = list("dot" = 3, "curl" = 1)
	count = 6
	spawning = 6
	lifespan = 6
	fade = 2
	position = generator("circle", 0, 2)
	velocity = generator("circle", 2, 5)
	friction = 0.15
	gradient = list(0, "#f0e8d8", 1, "#807870")
	color = generator("num", 0, 1)

/// Thrown from a blast: chips of whatever was there, hot at first
/particles/fx/debris
	icon_state = list("dot" = 3, "cross" = 1, "curl" = 2)
	width = 256
	height = 256
	count = 40
	spawning = 40
	lifespan = 12
	fade = 5
	position = generator("circle", 0, 10)
	velocity = generator("circle", 3, 10)
	friction = 0.08
	gradient = list(0, "#ffd070", 0.3, "#b0b0b0", 1, "#484848")
	color = generator("num", 0, 0.5)
	color_change = 0.06
	scale = 2

/particles/fx/debris/big
	width = 420
	height = 420
	count = 80
	spawning = 80
	lifespan = 16
	velocity = generator("circle", 5, 15)

/// And the bits of it still burning (tg's ash sprites)
/particles/fx/debris_burning
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("ash_1" = 2, "ash_2" = 2, "ash_3" = 1)
	width = 256
	height = 256
	count = 9
	spawning = 9
	lifespan = 14
	fade = 6
	position = generator("circle", 0, 8)
	velocity = generator("circle", 2, 7)
	friction = 0.1

/particles/fx/debris_burning/big
	width = 420
	height = 420
	count = 20
	spawning = 20
	lifespan = 18
	velocity = generator("circle", 3, 11)

/// The smoke a blast leaves for a moment: thin enough to see through
/particles/fx/blast_smoke
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("smoke_1" = 1, "smoke_2" = 1, "smoke_3" = 2)
	width = 256
	height = 256
	count = 16
	spawning = 16
	lifespan = 16
	fade = 10
	position = generator("circle", 0, 14)
	velocity = generator("circle", 0.5, 3.5)
	friction = 0.12
	color = "#ffffffb8"

/particles/fx/blast_smoke/big
	width = 420
	height = 420
	count = 34
	spawning = 34
	lifespan = 22
	fade = 14
	position = generator("circle", 0, 30)
	velocity = generator("circle", 1, 5)

/// Sprayed from a wound: drops
/particles/fx/blood
	icon_state = list("dot" = 3, "curl" = 2)
	count = 14
	spawning = 14
	lifespan = 7
	fade = 2
	position = generator("circle", 0, 3)
	velocity = generator("circle", 1.5, 5)
	friction = 0.16
	gradient = list(0, "#c41818", 1, "#7a0c0c")
	color = generator("num", 0, 1)

/// Drifting up round the supermatter
/particles/fx/motes
	icon_state = list("cross" = 2, "dot" = 3)
	height = 160
	count = 30
	spawning = 0.8
	lifespan = 30
	fade = 12
	fadein = 5
	position = generator("circle", 12, 28)
	velocity = generator("box", list(-0.2, 0.2, 0), list(0.2, 0.8, 0))
	gradient = list(0, "#fff8c0", 1, "#ffc040")
	color = generator("num", 0, 1)

/// Crackling round a tesla ball
/particles/fx/tesla
	icon_state = list("cross" = 2, "dot" = 2, "curl" = 1)
	count = 20
	spawning = 4
	lifespan = 4
	fade = 2
	position = generator("circle", 6, 28)
	velocity = generator("circle", 0, 3)
	gradient = list(0, "#ffffff", 1, "#8fd0ff")
	color = generator("num", 0, 1)

/// Air let into a room that hasn't much: a vent's puff (tg's steam)
/particles/fx/puff
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 1, "steam_2" = 1, "steam_3" = 2)
	count = 14
	spawning = 1.5
	lifespan = 10
	fade = 7
	fadein = 1
	position = generator("circle", 0, 5)
	velocity = generator("circle", 0.8, 2.6)
	friction = 0.06
	color = "#ffffffc0"

/// Breath you can see, at the mouth: one puff (tg's breath fog, with its steam sprites: the chill ones don't show over a lit floor)
/particles/fx/breath
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 2, "steam_2" = 2, "steam_3" = 1)
	count = 2
	spawning = 2
	lifespan = 12
	fade = 7
	fadein = 1
	position = generator("box", list(-1, -1, 0), list(1, 1, 0))
	velocity = generator("box", list(-0.2, 0.15, 0), list(0.2, 0.5, 0))
	friction = 0.05
	color = "#fcffffd0"

/// Dust hanging in a room's air, over the floor of its emitter (air_dust.dm): one or two specks at a time. They fade in, wander a
/// few pixels and fade out again, faint, some catching more light than others. Each floor has a set of its own, which wind gives
/// a gravity; the drawing is big enough for the wind to carry them a few tiles on
/particles/fx/air_dust
	icon_state = list("dot" = 3, "curl" = 1)
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
	gradient = list(0, "#fff3dc58", 1, "#fff6e8c0")
	color = generator("num", 0, 1)

/// Dust burning up in a fire or air too hot for it: a spark or two over its floor, gone in a moment
/particles/fx/air_dust_burn
	count = 3
	spawning = 3
	lifespan = 9
	fade = 5
	position = generator("box", list(-12, -12, 0), list(12, 12, 0))
	velocity = generator("box", list(-0.15, 0.1, 0), list(0.15, 0.5, 0))
	gradient = list(0, "#fce6b6", 0.5, "#fbaf4d", 1, "#fd481c")
	color = 0
	color_change = 0.15

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

/// Air on its way to a breach, in streaks: setup() gives a copy of this its direction and lays the streaks along it
/particles/fx/gust
	icon_state = list("drop" = 3, "dot" = 1)
	count = 16
	spawning = 2
	lifespan = 6
	fade = 3
	position = generator("box", list(-16, -16, 0), list(16, 16, 0))
	color = "#f4f8fc"

// ---- What gives them off

/obj/effect/hotspot
	/// The embers it gives off, if it's one that does: update_embers() (particle_smoke.dm) picks them by its heat and what burns
	var/ember_kind

/obj/effect/hotspot/Initialize(mapload, starting_volume, starting_temperature)
	. = ..()
	// Merged flames bring their own smoke, embers and glow (merged_flames.dm): these are for a fire drawn the old way only
	if(!flames_merged && !(x % 2) && !(y % 2)) //one fire in four, the ones that carry a pool of light (light_glow.dm): a big fire is hundreds of these
		ember_kind = "ember"
		vis_contents += particle_fx("ember")
		vis_contents += particle_fx("fire_smoke")
		update_embers()

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

// A bullet's hit is dust and chips; a beam's is sparks of its colour
/obj/effect/temp_visual/impact_effect
	var/particle_kind = "impact_dust"

/obj/effect/temp_visual/impact_effect/red_laser
	particle_kind = "impact_red"

/obj/effect/temp_visual/impact_effect/blue_laser
	particle_kind = "impact_blue"

/obj/effect/temp_visual/impact_effect/green_laser
	particle_kind = "impact_green"

/obj/effect/temp_visual/impact_effect/purple_laser
	particle_kind = "impact_purple"

/obj/effect/temp_visual/impact_effect/ion
	particle_kind = "impact_ion"

/obj/effect/temp_visual/impact_effect/Initialize(mapload, x, y)
	. = ..()
	if(isturf(loc))
		new /obj/effect/particle_fx/burst(loc, particle_kind, x, y)
		if(particle_kind == "impact_dust")
			new /obj/effect/particle_fx/burst(loc, "impact_chips", x, y)

/datum/controller/subsystem/explosions/explode(atom/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range, adminlog, ignorecap, flame_range, silent, smoke, atom/explosion_cause)
	var/turf/middle = get_turf(epicenter)
	if(middle && (devastation_range || heavy_impact_range || light_impact_range))
		var/size = (heavy_impact_range >= 2 || light_impact_range >= 5) ? "_big" : ""
		new /obj/effect/particle_fx/burst(middle, "blast_smoke[size]")
		new /obj/effect/particle_fx/burst(middle, "debris[size]")
		new /obj/effect/particle_fx/burst(middle, "debris_burning[size]")
	return ..()

/mob/living/add_splatter_floor(turf/T, small_drip)
	..()
	if(get_blood_id() == /datum/reagent/blood)
		particle_burst(T || get_turf(src), small_drip ? "blood_drip" : "blood")

/obj/machinery/power/supermatter_crystal/Initialize()
	. = ..()
	vis_contents += particle_fx("motes")

/obj/singularity/energy_ball/Initialize(mapload, starting_energy = 50, is_miniball = FALSE)
	. = ..()
	vis_contents += particle_fx("tesla")

// Breath shows in air under two degrees: a freezer, a room open to space. On internals it's the tank's air that's breathed, so a
// spacesuit shows none. Each breath is a puff left in the air where it was breathed, not an emitter on the mob: someone walking
// on leaves it behind, where one held in their vis_contents was carried along with them. It starts at the mouth, on the side
// they face.
/mob/living/carbon/human/check_breath(datum/gas_mixture/breath)
	. = ..()
	if(breath && stat != DEAD && isturf(loc) && breath.temperature < T0C + 2 && breath.total_moles() > 0)
		if(lying)
			new /obj/effect/particle_fx/burst(loc, "breath")
		else
			new /obj/effect/particle_fx/burst(loc, "breath", (dir & EAST) ? 5 : ((dir & WEST) ? -5 : 0), 7)

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
