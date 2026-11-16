// Tools and machines (the system is particle_fx.dm): sparks off a weld, mist off an extinguisher's spray, smoke at a gun's
// muzzle, a flash at an emitter's, exhaust from a shuttle's engines, specks falling into a singularity, a machine breaking.

// ---- The sets

/// Sparks off a weld, for as long as it goes on
/particles/fx/sparks/welding
	count = 14
	spawning = 2
	lifespan = 7
	fade = 3
	position = generator("circle", 0, 2)
	velocity = generator("circle", 1.5, 5)
	gradient = list(0, "#ffffff", 0.3, "#c8e4ff", 0.6, "#fce6b6", 1, "#fd481c")

/// And off a weld done in one touch
/particles/fx/sparks/weld_burst
	count = 10
	spawning = 10
	lifespan = 7
	fade = 3
	velocity = generator("circle", 1.5, 5)
	gradient = list(0, "#ffffff", 0.3, "#c8e4ff", 0.6, "#fce6b6", 1, "#fd481c")

/// Off a wire cut or pulsed: a few blue-white ones (particle_destruction.dm)
/particles/fx/sparks/wire
	count = 6
	spawning = 6
	lifespan = 6
	fade = 3
	velocity = generator("circle", 1, 4)
	gradient = list(0, "#ffffff", 0.5, "#a8dcff", 1, "#fce6b6")

/// Spray off an extinguisher's water as it flies, on each tile it crosses
/particles/fx/water_mist
	icon_state = list("dot" = 3, "curl" = 2, "drop" = 1)
	count = 6
	spawning = 6
	lifespan = 7
	fade = 3
	position = generator("circle", 0, 6)
	velocity = generator("circle", 0.3, 1.6)
	gravity = list(0, -0.15)
	gradient = list(0, "#ffffff", 1, "#8cc8ff")
	color = generator("num", 0, 1)

/// Smoke at the muzzle of a gun that fires bullets
/particles/fx/muzzle_smoke
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 2, "steam_2" = 1, "steam_3" = 1)
	count = 3
	spawning = 3
	lifespan = 10
	fade = 7
	position = generator("circle", 0, 2)
	velocity = generator("box", list(-0.4, 0, 0), list(0.4, 0.7, 0))
	friction = 0.1
	color = "#d8d8d8b8"

/// Smoke out of a machine as it breaks
/particles/fx/break_smoke
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("smoke_1" = 1, "smoke_2" = 1, "smoke_3" = 2)
	count = 5
	spawning = 5
	lifespan = 16
	fade = 10
	position = generator("circle", 0, 5)
	velocity = generator("box", list(-0.4, 0.3, 0), list(0.4, 1.1, 0))
	friction = 0.05
	color = "#ffffffb8"

/// A shuttle engine's exhaust: exhaust_fx() gives a copy of this its direction
/particles/fx/exhaust
	icon_state = list("dot" = 3, "cross" = 1, "curl" = 2)
	width = 160
	height = 160
	count = 32
	spawning = 4
	lifespan = 8
	fade = 4
	gradient = list(0, "#ffffff", 0.3, "#a8dcff", 0.7, "#fbaf4d", 1, "#fd481c")
	color = 0
	color_change = 0.12

/// Specks falling in to a singularity from one side: /obj/singularity/proc/update_pull_fx() aims each
/particles/fx/pull
	icon_state = list("dot" = 3, "curl" = 2, "cross" = 1)
	count = 6
	spawning = 0.5
	lifespan = 14
	fade = 3
	fadein = 3
	gradient = list(0, "#ffe8c0", 0.6, "#ff9040", 1, "#c01800")
	color = 0
	color_change = 0.07

// ---- What gives them off

// Welding: sparks at whatever's being welded for as long as it takes, or one shower for a weld with no wait
/obj/item/weldingtool/use_tool(atom/target, mob/living/user, delay, amount = 0, volume = 0, datum/callback/extra_checks)
	var/turf/at = get_turf(target)
	if(!at || !isOn())
		return ..()
	if(!delay)
		. = ..()
		if(.)
			particle_burst(at, "weld_sparks")
		return
	var/obj/effect/particle_fx/sparks = new(at)
	sparks.setup("welding")
	. = ..() //waits out the weld
	qdel(sparks)

// An extinguisher's water leaves mist on each tile it crosses
/obj/effect/particle_effect/water/Move(turf/newloc)
	. = ..()
	if(. && isturf(loc))
		particle_burst(loc, "water_mist")

// A gun that fires bullets smokes at the muzzle, unless it's silenced
/obj/item/gun/ballistic/shoot_live_shot(mob/living/user, pointblank = 0, mob/pbtarget = null, message = 1)
	. = ..()
	var/turf/at = get_turf(user)
	if(suppressed || !at)
		return
	var/facing = user.dir
	particle_burst(at, "muzzle_smoke", ((facing & EAST) ? 14 : ((facing & WEST) ? -14 : 0)), ((facing & NORTH) ? 14 : ((facing & SOUTH) ? -14 : 0)))

// An emitter flashes green at its muzzle with each shot
/obj/machinery/power/emitter/fire_beam(mob/user)
	. = ..()
	particle_burst(get_turf(src), "impact_green", ((dir & EAST) ? 14 : ((dir & WEST) ? -14 : 0)), ((dir & NORTH) ? 14 : ((dir & SOUTH) ? -14 : 0)))

// A machine breaking throws sparks and a little smoke
/obj/machinery/obj_break(damage_flag)
	. = ..()
	if(. && isturf(loc))
		particle_burst(loc, "sparks")
		particle_burst(loc, "break_smoke")

// Shuttle engines burn from the warm-up before a jump until the jump is nearly over (the same moments the engine sounds play:
// the arrivals and emergency shuttles). The exhaust goes out the way the engine faces; one shared emitter for each direction.
/proc/exhaust_fx(dir)
	var/obj/effect/particle_fx/F = GLOB.particle_fx["exhaust[dir]"]
	if(!F)
		F = new
		var/particles/fx/exhaust/burn = new
		var/along_x = (dir & EAST) ? 1 : ((dir & WEST) ? -1 : 0)
		var/along_y = (dir & NORTH) ? 1 : ((dir & SOUTH) ? -1 : 0)
		burn.position = generator("box", list(along_x * 12 - (along_x ? 2 : 9), along_y * 12 - (along_y ? 2 : 9), 0), list(along_x * 12 + (along_x ? 2 : 9), along_y * 12 + (along_y ? 2 : 9), 0))
		burn.velocity = generator("box", list(along_x * 4 - 0.4, along_y * 4 - 0.4, 0), list(along_x * 8 + 0.4, along_y * 8 + 0.4, 0))
		F.particles = burn
		GLOB.particle_fx["exhaust[dir]"] = F
	return F

/obj/structure/shuttle/engine/propulsion
	var/obj/effect/particle_fx/exhaust

/obj/structure/shuttle/engine/propulsion/proc/set_exhaust(burning)
	var/obj/effect/particle_fx/now = burning ? exhaust_fx(dir) : null
	if(now == exhaust)
		return
	if(exhaust)
		vis_contents -= exhaust
	exhaust = now
	if(now)
		vis_contents += now

/obj/structure/shuttle/engine/propulsion/setDir(newdir)
	. = ..()
	if(exhaust) //the shuttle turned as it jumped
		set_exhaust(TRUE)

/obj/docking_port/mobile/hyperspace_sound(phase, list/areas)
	for(var/obj/structure/shuttle/engine/propulsion/engine in engine_list)
		engine.set_exhaust(phase != HYPERSPACE_END)
	return ..()

// A singularity draws specks in from eight sides, from further out the bigger it is. The emitters are its own, made again when
// it changes size. It's drawn from its corner (pixel_x and pixel_y put its middle on its tile), so each emitter is moved back.
/obj/singularity
	var/list/pull_fx
	var/pull_size = 0

/obj/singularity/proc/update_pull_fx()
	if(pull_size == current_size || istype(src, /obj/singularity/energy_ball))
		return
	pull_size = current_size
	if(pull_fx)
		vis_contents -= pull_fx
		QDEL_LIST(pull_fx)
	pull_fx = list()
	var/reach = 16 * current_size + 36 //where the specks start, in pixels from its middle
	var/spread = reach * 0.3
	for(var/dir in GLOB.alldirs)
		var/along_x = (dir & EAST) ? 1 : ((dir & WEST) ? -1 : 0)
		var/along_y = (dir & NORTH) ? 1 : ((dir & SOUTH) ? -1 : 0)
		if(along_x && along_y)
			along_x *= 0.71
			along_y *= 0.71
		var/particles/fx/pull/specks = new
		specks.width = reach * 2 + 96
		specks.height = reach * 2 + 96
		specks.count = 4 + current_size
		specks.position = generator("box", list(along_x * reach - spread, along_y * reach - spread, 0), list(along_x * reach + spread, along_y * reach + spread, 0))
		// in to the middle over their fourteen ticks, a little faster or slower
		specks.velocity = generator("box", list(-along_x * reach / 12, -along_y * reach / 12, 0), list(-along_x * reach / 16, -along_y * reach / 16, 0))
		var/obj/effect/particle_fx/emitter = new
		emitter.particles = specks
		emitter.pixel_x = -pixel_x
		emitter.pixel_y = -pixel_y
		pull_fx += emitter
	vis_contents += pull_fx

/obj/singularity/Initialize(mapload, starting_energy = 50)
	. = ..()
	update_pull_fx()

/obj/singularity/expand(force_size = 0)
	. = ..()
	update_pull_fx()

/obj/singularity/Destroy()
	if(pull_fx)
		vis_contents -= pull_fx
		QDEL_LIST(pull_fx)
	return ..()
