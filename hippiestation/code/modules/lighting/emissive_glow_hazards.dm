// Signs and hazards that glow in the dark (see emissive_glow.dm): bar signs, holosigns, lava, the supermatter, the tesla ball and
// the singularity. Masks are in tools/icon_merge/glow.txt.

// Softer: at full strength a bar sign's letters blur together and the tesla ball's arcs bloom into one white blob
/obj/structure/sign/barsign
	emissive_glow_alpha = EMISSIVE_GLOW_SIGN

/obj/singularity/energy_ball
	emissive_glow_alpha = EMISSIVE_GLOW_SIGN

/obj/structure/sign/barsign/set_sign(datum/barsign/sign)
	. = ..()
	update_state_glow()

// Holograms are all light
/obj/structure/holosign/Initialize()
	. = ..()
	set_emissive_glow(icon_state)

// Lava is lit through: the whole tile, so the rock at its edges too, with a halo in the lava's light colour where it meets the
// floor round it. An overlay of its own: a turf's luminosity belongs to the lighting, so set_emissive_glow() isn't for turfs.
/turf/open/lava/Initialize(mapload)
	. = ..()
	add_overlay(emissive_glow('icons/effects/alphacolors.dmi', "white", color = light_color || LIGHT_COLOR_LAVA))

// The crystal is all light, brighter sprite and all when it's running hot
/obj/machinery/power/supermatter_crystal/Initialize()
	. = ..()
	set_emissive_glow(icon_state)

/obj/machinery/power/supermatter_crystal/process_atmos()
	var/was = icon_state
	. = ..()
	if(icon_state != was && !QDELETED(src))
		set_emissive_glow(icon_state)

/obj/singularity/energy_ball/Initialize(mapload, starting_energy = 50, is_miniball = FALSE)
	. = ..()
	set_emissive_glow(icon_state)

/obj/singularity/Initialize(mapload, starting_energy = 50)
	. = ..()
	if(!istype(src, /obj/singularity/energy_ball))
		update_state_glow()

// Each size is another sprite in another sheet
/obj/singularity/expand(force_size = 0)
	. = ..()
	if(!istype(src, /obj/singularity/energy_ball))
		update_state_glow()
