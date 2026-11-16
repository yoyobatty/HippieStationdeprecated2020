// Mobs (the system is particle_fx.dm): embers and smoke off someone on fire, the stink of something rotting, acid eating at a
// thing, drops from a wound, dust kicked up running through a dusty place, glints off someone badly irradiated.
// The ones held by a mob go where it goes; the puffs (drips, dust) are left where they were made.

// ---- The sets

/// Embers off someone on fire: fewer than a fire's, close about them
/particles/fx/ember/mob
	height = 128
	count = 12
	spawning = 1
	lifespan = generator("num", 9, 14)
	fade = 6
	position = generator("box", list(-8, -12, 0), list(8, 8, 0))
	velocity = generator("box", list(-0.3, 0.5, 0), list(0.3, 1.5, 0))

/// Stink lines off something rotting (tg's)
/particles/fx/stink
	icon = 'hippiestation/icons/effects/particles/stink.dmi'
	icon_state = list("stink_1" = 1, "stink_2" = 2, "stink_3" = 2)
	count = 7
	spawning = 0.25
	lifespan = 14
	fade = 8
	fadein = 3
	position = generator("box", list(-10, -4, 0), list(10, 8, 0))
	velocity = list(0, 0.2)
	gravity = list(0, 0.02)
	color = "#0bda51"

/// Acid eating at something (tg's goop)
/particles/fx/acid
	icon = 'hippiestation/icons/effects/particles/goop.dmi'
	icon_state = list("goop_1" = 6, "goop_2" = 2, "goop_3" = 1)
	count = 8
	spawning = 0.35
	lifespan = 15
	fade = 9
	fadein = 1
	position = generator("circle", 0, 10)
	gravity = list(0, 0.04)
	color = "#00ea2bc8"

/// Drops falling from a wound
/particles/fx/blood/drip
	count = 3
	spawning = 3
	lifespan = 6
	fade = 1
	position = generator("box", list(-4, -2, 0), list(4, 4, 0))
	velocity = generator("box", list(-0.3, -0.2, 0), list(0.3, 0.2, 0))
	gravity = list(0, -0.45)
	friction = 0

/// Dust kicked up by a running foot
/particles/fx/foot_dust
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 2, "steam_2" = 1)
	count = 2
	spawning = 2
	lifespan = 9
	fade = 6
	position = generator("box", list(-4, -1, 0), list(4, 1, 0))
	velocity = generator("box", list(-0.4, 0.05, 0), list(0.4, 0.4, 0))
	friction = 0.1
	color = "#b8b0a0a8"

/// Glints off someone with a heavy dose of radiation
/particles/fx/rad_glint
	icon_state = list("cross" = 3, "dot" = 2)
	count = 9
	spawning = 0.7
	lifespan = 8
	fade = 4
	fadein = 2
	position = generator("box", list(-9, -13, 0), list(9, 11, 0))
	gradient = list(0, "#d8ff90", 1, "#48e820")
	color = generator("num", 0, 1)

// ---- What gives them off

/mob/living/IgniteMob()
	. = ..()
	if(.)
		vis_contents |= particle_fx("mob_fire")
		vis_contents |= particle_fx("burning_smoke")

/mob/living/ExtinguishMob()
	if(on_fire)
		vis_contents -= particle_fx("mob_fire")
		vis_contents -= particle_fx("burning_smoke")
	return ..()

// Whatever is rotting (a body, gibs) stinks from the first time it gives off miasma, and stops a while after the last: a body
// put in a morgue tray or a bag, or frozen, stops rotting without the rot being taken off it.
/datum/component/rot
	var/stinking = FALSE
	var/last_rotted = 0

/datum/component/rot/process()
	var/atom/movable/thing = parent
	if(!QDELETED(thing))
		last_rotted = world.time
		if(!stinking && ismovable(thing))
			stinking = TRUE
			thing.vis_contents |= particle_fx("stink")
	return ..()

/datum/component/rot/corpse/process()
	. = ..() //reaches the one above only when it's really rotting
	if(stinking && !QDELETED(src) && world.time - last_rotted > 10 SECONDS)
		stop_stinking()

/datum/component/rot/proc/stop_stinking()
	if(!stinking)
		return
	stinking = FALSE
	var/atom/movable/thing = parent
	if(ismovable(thing))
		thing.vis_contents -= particle_fx("stink")

/datum/component/rot/Destroy(force = FALSE, silent = FALSE)
	stop_stinking()
	return ..()

// Acid on a thing fizzes until it's spent
/obj/acid_act(acidpwr, acid_volume)
	. = ..()
	if(. && acid_level)
		vis_contents |= particle_fx("acid")

/obj/acid_processing()
	. = ..()
	if(!.)
		vis_contents -= particle_fx("acid")

// Running through a dusty place (maintenance, storage: the areas with heavy dust in the air) kicks some up, where a player
// is near enough to see it
/mob/living/carbon/human/Moved(atom/OldLoc, Dir, Forced = FALSE)
	. = ..()
	var/turf/open/floor/T = loc
	if(m_intent != MOVE_INTENT_RUN || lying || buckled || !istype(T) || !isturf(OldLoc))
		return
	var/area/A = T.loc
	if(A.air_dust != AIR_DUST_HEAVY || !prob(40))
		return
	if(SSair_dust.watched_cells && !SSair_dust.watched_cells[AIR_DUST_UNSEEN_CELL(T)])
		return
	particle_burst(OldLoc, "foot_dust", 0, -12)

// A dose of radiation heavy enough to mutate shows as glints
/mob/living/carbon/human
	var/rad_glinting = FALSE

/mob/living/carbon/human/handle_mutations_and_radiation()
	. = ..()
	if((radiation > RAD_MOB_MUTATE) == rad_glinting)
		return
	rad_glinting = !rad_glinting
	if(rad_glinting)
		vis_contents |= particle_fx("rad_glint")
	else
		vis_contents -= particle_fx("rad_glint")
