// Smoke and steam (the system is particle_fx.dm): smoke off a fire and off things that burn, embers coloured by the fire,
// cigarette and vape smoke, shower and kitchen steam, gas coming out of an open canister.
// None of it blocks sight or does anything: chemical smoke is still its own thing.

// ---- The sets

/// Embers off a fire hot enough to burn white and blue
/particles/fx/ember/hot
	gradient = list(0, "#ffffff", 0.35, "#c8e4ff", 1, "#5a9cff")

/// Embers off a tritium fire
/particles/fx/ember/tritium
	gradient = list(0, "#f0ffd0", 0.35, "#9cff60", 1, "#28c040")

/// Smoke rising off a fire, thin enough to see through (tg's smoke)
/particles/fx/fire_smoke
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("smoke_1" = 1, "smoke_2" = 1, "smoke_3" = 2)
	height = 192
	count = 6
	spawning = 0.25
	lifespan = 24
	fade = 12
	fadein = 4
	position = generator("box", list(-14, -4, 0), list(14, 12, 0))
	velocity = generator("box", list(-0.25, 0.7, 0), list(0.25, 1.4, 0))
	drift = generator("vector", list(-0.15, 0), list(0.15, 0.03))
	friction = 0.02
	color = "#ffffffa8"

/// Smoke off one thing that's burning
/particles/fx/burning_smoke
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("smoke_1" = 1, "smoke_2" = 1, "smoke_3" = 2)
	count = 5
	spawning = 0.35
	lifespan = 16
	fade = 9
	fadein = 2
	position = generator("box", list(-6, 0, 0), list(6, 8, 0))
	velocity = generator("box", list(-0.2, 0.6, 0), list(0.2, 1.2, 0))
	drift = generator("vector", list(-0.1, 0), list(0.1, 0.02))
	color = "#ffffffb0"

/// A wisp off a lit cigarette (tg's, as a puff left in the air every couple of seconds)
/particles/fx/cig_smoke
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 2, "steam_2" = 1, "steam_3" = 1)
	count = 2
	spawning = 2
	lifespan = 13
	fade = 8
	fadein = 1
	position = generator("box", list(-1, 0, 0), list(1, 2, 0))
	velocity = generator("box", list(-0.15, 0.3, 0), list(0.15, 0.6, 0))
	drift = generator("vector", list(-0.05, 0), list(0.05, 0.01))
	friction = 0.04
	color = "#d0d0d0b0"

/// A vape's cloud: more of it, whiter
/particles/fx/cig_smoke/vape
	icon_state = list("steam_1" = 1, "steam_2" = 2, "steam_3" = 2)
	count = 6
	spawning = 6
	lifespan = 16
	fade = 10
	position = generator("circle", 0, 3)
	velocity = generator("box", list(-0.6, 0.1, 0), list(0.6, 0.7, 0))
	color = "#ffffffc8"

/// Steam off something cooking
/particles/fx/cook_steam
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 1, "steam_2" = 1, "steam_3" = 2)
	count = 5
	spawning = 0.3
	lifespan = 16
	fade = 10
	fadein = 2
	position = generator("box", list(-6, 4, 0), list(6, 10, 0))
	velocity = generator("box", list(-0.15, 0.4, 0), list(0.15, 0.8, 0))
	drift = generator("vector", list(-0.05, 0), list(0.05, 0.01))
	color = "#ffffffb0"

/// Smoke off a grill with something on it
/particles/fx/cook_steam/grill
	icon_state = list("smoke_1" = 1, "smoke_2" = 1, "smoke_3" = 2)
	color = "#ffffff98"

/// Steam filling a hot shower
/particles/fx/shower_steam
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 1, "steam_2" = 1, "steam_3" = 2)
	count = 8
	spawning = 0.5
	lifespan = 18
	fade = 11
	fadein = 3
	position = generator("box", list(-12, -8, 0), list(12, 12, 0))
	velocity = generator("box", list(-0.15, 0.3, 0), list(0.15, 0.7, 0))
	color = "#ffffffa0"

/// Water falling from a shower head (tg's droplets)
/particles/fx/shower_drops
	icon_state = list("dot" = 2, "drop" = 1)
	width = 48
	height = 64
	count = 12
	spawning = 1.5
	lifespan = 8
	fade = 3
	position = generator("box", list(-9, 0, 0), list(9, 16, 0))
	velocity = list(0, -1)
	gravity = list(0, -0.5)
	color = "#8cc8ff"

/// Gas coming out of an open canister
/particles/fx/gas_wisp
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 1, "steam_2" = 1, "steam_3" = 2)
	count = 7
	spawning = 0.5
	lifespan = 14
	fade = 9
	fadein = 1
	position = generator("box", list(-3, 6, 0), list(3, 10, 0))
	velocity = generator("box", list(-1.2, 0.2, 0), list(1.2, 1.4, 0))
	friction = 0.08
	color = "#ffffffb8"

/particles/fx/gas_wisp/plasma
	color = "#e070ffc0"

/particles/fx/gas_wisp/tritium
	color = "#80ff80c0"

/// All a canister's gas let go at once as it breaks
/particles/fx/gas_burst
	icon = 'hippiestation/icons/effects/particles/smoke.dmi'
	icon_state = list("steam_1" = 1, "steam_2" = 1, "steam_3" = 2)
	count = 14
	spawning = 14
	lifespan = 12
	fade = 8
	position = generator("circle", 0, 4)
	velocity = generator("circle", 1, 4.5)
	friction = 0.12
	color = "#ffffffc0"

// ---- What gives them off

/// Picks its embers: blue-white when it's that hot, green over tritium, orange otherwise. From update_color(), every few ticks.
/obj/effect/hotspot/proc/update_embers()
	var/kind = "ember"
	if(temperature >= PARTICLE_FIRE_HOT)
		kind = "ember_hot"
	else
		var/turf/open/T = loc
		if(istype(T) && T.air && T.air.moles[/datum/gas/tritium] >= 0.5)
			kind = "ember_tritium"
	if(kind == ember_kind)
		return
	vis_contents -= particle_fx(ember_kind)
	vis_contents += particle_fx(kind)
	ember_kind = kind

/obj/effect/hotspot/update_color()
	. = ..()
	if(ember_kind)
		update_embers()

// A thing that's caught fire smokes until it's put out or burnt up
/obj/fire_act(exposed_temperature, exposed_volume)
	. = ..()
	if(. == 1 && (resistance_flags & ON_FIRE)) //1 is tg's "it has just caught"
		vis_contents |= particle_fx("burning_smoke")

/obj/extinguish()
	if(resistance_flags & ON_FIRE)
		vis_contents -= particle_fx("burning_smoke")
	return ..()

/// A puff of smoke where it is: at the smoker's mouth if it's in it, by their hand if it's held, over it on the floor
/obj/item/clothing/mask/proc/puff_smoke(kind)
	if(isturf(loc))
		particle_burst(loc, kind, pixel_x, pixel_y + 2)
		return
	var/mob/living/carbon/smoker = loc
	if(!istype(smoker) || !isturf(smoker.loc))
		return
	var/side = (smoker.dir & EAST) ? 1 : ((smoker.dir & WEST) ? -1 : 0)
	if(smoker.wear_mask == src && !smoker.lying)
		particle_burst(smoker.loc, kind, side ? side * 7 : ((smoker.dir & SOUTH) ? 3 : 0), 5)
	else
		particle_burst(smoker.loc, kind, side ? side * 6 : 7, -4)

/obj/item/clothing/mask/cigarette/process()
	. = ..()
	if(!QDELETED(src) && lit)
		puff_smoke("cig_smoke")

/obj/item/clothing/mask/vape/process()
	. = ..()
	var/mob/living/carbon/smoker = loc
	if(!QDELETED(src) && reagents?.total_volume && istype(smoker) && smoker.wear_mask == src)
		puff_smoke("vape_cloud")

// A running shower drips, and steams when it's set to boiling
/obj/machinery/shower/handle_mist()
	. = ..()
	if(on)
		vis_contents |= particle_fx("shower_drops")
	else
		vis_contents -= particle_fx("shower_drops")
	if(on && current_temperature == "boiling") //SHOWER_BOILING, defined in shower.dm
		vis_contents |= particle_fx("shower_steam")
	else
		vis_contents -= particle_fx("shower_steam")

// The kitchen: a microwave, a fryer and a grill at work
/obj/machinery/microwave/update_icon()
	. = ..()
	if(operating)
		vis_contents |= particle_fx("cook_steam")
	else
		vis_contents -= particle_fx("cook_steam")

/obj/machinery/deepfryer/process()
	. = ..()
	if(frying && !(stat & (NOPOWER|BROKEN)))
		vis_contents |= particle_fx("cook_steam")
	else
		vis_contents -= particle_fx("cook_steam")

/obj/machinery/grill/process()
	. = ..()
	if(grilled_item && grill_fuel)
		vis_contents |= particle_fx("grill_smoke")
	else
		vis_contents -= particle_fx("grill_smoke")

// A canister with its valve open into the room: its gas shows coming out while there's pressure behind it
/obj/machinery/portable_atmospherics/canister
	var/obj/effect/particle_fx/wisp_fx

/obj/machinery/portable_atmospherics/canister/process_atmos()
	. = ..()
	var/obj/effect/particle_fx/now
	if(valve_open && !holding && !(stat & BROKEN) && air_contents.return_pressure() > ONE_ATMOSPHERE * 1.2)
		now = particle_fx(gas_type == /datum/gas/plasma ? "gas_wisp_plasma" : (gas_type == /datum/gas/tritium ? "gas_wisp_tritium" : "gas_wisp"))
	if(now == wisp_fx)
		return
	if(wisp_fx)
		vis_contents -= wisp_fx
	wisp_fx = now
	if(now)
		vis_contents += now

/obj/machinery/portable_atmospherics/canister/canister_break()
	if(air_contents.total_moles() > 1)
		particle_burst(get_turf(src), "gas_burst")
	return ..()
