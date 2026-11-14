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
/turf/open/lava
	/// The glow overlay pair it has on: a smoothed tile's changes with the sprite smoothing picks
	var/list/lava_glow

/turf/open/lava/Initialize(mapload)
	. = ..()
	update_lava_glow()

/// Plain lava glows over the whole tile. A smoothed tile draws a rim of rock where it meets the floor round it, and only its molten
/// part glows ("<state>_glow", glow.txt): the whole tile glowing lit the rim and the bloom drew a glowing line along every edge of
/// a lava field, rock and all (round-16.29.52).
/turf/open/lava/proc/update_lava_glow()
	var/list/glow
	if(smoothing_flags & SMOOTH_BORDER)
		glow = emissive_glow(icon, "[icon_state]_glow")
	else
		glow = emissive_glow('icons/effects/alphacolors.dmi', "white", color = light_color || LIGHT_COLOR_LAVA)
	if(glow ~= lava_glow)
		return
	if(lava_glow)
		cut_overlay(lava_glow)
	lava_glow = glow
	add_overlay(glow)

/turf/open/lava/set_smoothed_icon_state(new_junction)
	. = ..()
	update_lava_glow()

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
