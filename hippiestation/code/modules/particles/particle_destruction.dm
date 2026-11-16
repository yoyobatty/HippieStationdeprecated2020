// Things breaking (the system is particle_fx.dm): glass flying from a smashed window, rubble off a wall taken down, chips off
// rock being mined, sparks at a door's wires. All one-off bursts, so a blast taking out a hundred walls at once makes only as
// many as PARTICLE_BURSTS_MAX lets it.

// ---- The sets

/// Bits of a smashed window
/particles/fx/glass_shards
	icon_state = list("dot" = 3, "curl" = 2, "drop" = 2)
	count = 16
	spawning = 16
	lifespan = 9
	fade = 3
	position = generator("circle", 0, 6)
	velocity = generator("circle", 1.5, 6)
	friction = 0.12
	gradient = list(0, "#ffffff", 1, "#a8e0f0")
	color = generator("num", 0, 1)

/// Bits of a wall taken down
/particles/fx/rubble
	icon_state = list("dot" = 3, "curl" = 2)
	count = 16
	spawning = 16
	lifespan = 10
	fade = 3
	position = generator("circle", 0, 10)
	velocity = generator("circle", 1, 5)
	friction = 0.12
	gradient = list(0, "#c8c8c8", 1, "#585858")
	color = generator("num", 0, 1)
	scale = 2

/// And the dust that comes off with them
/particles/fx/rubble_dust
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 1, "steam_2" = 1, "steam_3" = 1)
	count = 6
	spawning = 6
	lifespan = 14
	fade = 9
	position = generator("circle", 0, 10)
	velocity = generator("circle", 0.3, 1.5)
	friction = 0.1
	color = "#b0aca4c0"

/// Chips off rock being dug out
/particles/fx/rubble/rock
	count = 10
	spawning = 10
	gradient = list(0, "#a89880", 1, "#50463c")

// ---- What gives them off

/obj/structure/window/deconstruct(disassembled = TRUE)
	if(!disassembled && !QDELETED(src))
		particle_burst(get_turf(src), "glass_shards")
	return ..()

// A wall taken down by hand or knocked through. One a blast devastates gets none: the blast has its own debris.
/turf/closed/wall/dismantle_wall(devastated = 0, explode = 0)
	if(!devastated)
		particle_burst(src, "rubble")
		particle_burst(src, "rubble_dust")
	return ..()

/turf/closed/mineral/gets_drilled()
	particle_burst(src, "rock_chips")
	return ..()

// A door's wires spark when they're pulsed or cut
/datum/wires/airlock/on_pulse(wire)
	particle_burst(get_turf(holder), "wire_sparks")
	return ..()

/datum/wires/airlock/on_cut(wire, mend)
	if(!mend)
		particle_burst(get_turf(holder), "wire_sparks")
	return ..()
