// More machines and structures that glow in the dark (see emissive_glow.dm): the engines, atmospherics, science, the kitchen,
// the morgue. Masks are in tools/icon_merge/glow.txt; lights drawn as overlays of their own glow as they are.

// ---- Engines

/obj/machinery/power/emitter
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR
	/// The icon, state and dir the glow was last looked up for. An emitter that isn't welded down calls update_icon() from every
	/// process(), five times a second, to set the same unlit state again: the glow is looked up only when one of them has changed.
	var/glow_made_icon
	var/glow_made_state
	var/glow_made_dir

/obj/machinery/power/emitter/update_icon()
	. = ..()
	if(glow_made_state == icon_state && glow_made_dir == dir && glow_made_icon == icon)
		return
	glow_made_icon = icon
	glow_made_state = icon_state
	glow_made_dir = dir
	update_state_glow()

/obj/machinery/power/rad_collector
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/power/rad_collector/update_icon()
	. = ..()
	set_emissive_glow(active && !(stat & (NOPOWER|BROKEN)) ? "on" : null)

// Its lights are overlays: warming up, holding a field, how much power it has
/obj/machinery/field/generator/update_icon()
	. = ..()
	var/list/lights = list()
	if(warming_up)
		lights += emissive_glow(icon, "+a[warming_up]")
	if(LAZYLEN(fields))
		lights += emissive_glow(icon, "+on")
	if(power_level)
		lights += emissive_glow(icon, "+p[power_level]")
	set_emissive_glow(null, icon, length(lights) ? lights : null)

/obj/structure/particle_accelerator/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/particle_accelerator/control_box/update_icon()
	. = ..()
	update_state_glow()

// Running, it set states its sheet doesn't have ("shield_wall_gen_on"), so an active generator drew nothing at all: the sheet's
// own on and off sprites instead, and the arcs glow
/obj/machinery/power/shieldwallgen/process()
	. = ..()
	if(icon_state == "shield_wall_gen_on")
		icon_state = "Shield_Gen +a"
	else if(icon_state == "shield_wall_gen")
		icon_state = "Shield_Gen"
	update_state_glow()

// ---- Atmospherics

// The pressure light; update_icon() only redraws when the reading changes
/obj/machinery/portable_atmospherics/canister
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/portable_atmospherics/canister/update_icon()
	var/was = update
	. = ..()
	if(update == was && emissive_glow_shown)
		return
	var/light
	if(!(stat & BROKEN))
		if(update & (1<<3)) // CANISTER_UPDATE_LOW etc., which canister.dm undefines after itself
			light = "can-o0"
		else if(update & (1<<4)) // MEDIUM
			light = "can-o1"
		else if(update & (1<<5)) // FULL
			light = "can-o2"
		else if(update & (1<<6)) // DANGER
			light = "can-o3"
	set_emissive_glow(light)

/obj/machinery/portable_atmospherics/pump
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/portable_atmospherics/pump/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/portable_atmospherics/scrubber
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/portable_atmospherics/scrubber/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/portable_atmospherics/scrubber/huge/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/space_heater/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/atmospherics/components/unary/thermomachine
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/atmospherics/components/unary/thermomachine/update_icon()
	. = ..()
	update_state_glow()

// ---- Science and medical

/obj/machinery/rnd/production
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/rnd/production/update_icon()
	. = ..()
	if(stat & (NOPOWER|BROKEN))
		set_emissive_glow(null)
	else
		update_state_glow()

/obj/machinery/teleport/hub/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/teleport/station
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/teleport/station/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/gateway/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/gateway/centerstation/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/gateway/centeraway/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/doppler_array
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/doppler_array/update_icon()
	. = ..()
	update_state_glow()

// Its status lamp is an overlay; running, the chamber glows too
/obj/machinery/nanite_chamber
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/nanite_chamber/update_icon()
	. = ..()
	var/lamp
	if(!(stat & (MAINT|NOPOWER|BROKEN)) && !panel_open)
		lamp = (busy || locked) ? "red" : "green"
	update_state_glow(lamp ? emissive_glow(icon, lamp, SOUTH, emissive_glow_alpha) : null)

// The body status lamps (and the lit panel round them)
/obj/structure/bodycontainer/morgue
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/structure/bodycontainer/morgue/update_icon()
	. = ..()
	update_state_glow()

// A structure isn't redrawn at roundstart the way a powered machine is
/obj/structure/bodycontainer/morgue/Initialize()
	. = ..()
	update_state_glow()

/obj/structure/bodycontainer/crematorium/update_icon()
	. = ..()
	update_state_glow()

// ---- Kitchen, cargo, telecomms

/obj/machinery/microwave/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/grill/update_icon()
	. = ..()
	update_state_glow()

// The status lights along its top, while it heats; it's switched on and off from its window, without a redraw
/obj/machinery/chem_heater
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/chem_heater/proc/heater_glow()
	if(on && !(stat & (NOPOWER|BROKEN)))
		update_state_glow()
	else
		set_emissive_glow(null)

/obj/machinery/chem_heater/update_icon()
	. = ..()
	heater_glow()

/obj/machinery/chem_heater/ui_act(action, params)
	. = ..()
	heater_glow()

/obj/machinery/autolathe
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/autolathe/update_icon()
	. = ..()
	if(stat & (NOPOWER|BROKEN))
		set_emissive_glow(null)
	else
		update_state_glow()

/obj/machinery/recycler
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/recycler/update_icon()
	. = ..()
	update_state_glow()

// Its arrival and new-head lights are overlays
/obj/machinery/announcement_system
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/announcement_system/update_icon()
	. = ..()
	var/list/lights
	if(is_operational() && !panel_open)
		lights = list()
		if(arrivalToggle)
			lights += emissive_glow(icon, "Light_Green", SOUTH, emissive_glow_alpha)
		if(newheadToggle)
			lights += emissive_glow(icon, "Light_Pink", SOUTH, emissive_glow_alpha)
	update_state_glow(length(lights) ? lights : null)

// ---- Security

/obj/machinery/porta_turret
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/porta_turret/update_icon()
	. = ..()
	update_state_glow()

// ---- Botany: the tray's warning lamps (water, nutrients, health, pests, ready to harvest)

/obj/machinery/hydroponics
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/hydroponics/update_icon()
	. = ..()
	if(!myseed || istype(src, /obj/machinery/hydroponics/soil))
		set_emissive_glow(null)
		return
	var/list/lamps = list()
	var/tray_icon = 'icons/obj/hydroponics/equipment.dmi'
	if(waterlevel <= 10)
		lamps += emissive_glow(tray_icon, "over_lowwater3", SOUTH, emissive_glow_alpha)
	if(nutrilevel <= 2)
		lamps += emissive_glow(tray_icon, "over_lownutri3", SOUTH, emissive_glow_alpha)
	if(plant_health <= (myseed.endurance / 2))
		lamps += emissive_glow(tray_icon, "over_lowhealth3", SOUTH, emissive_glow_alpha)
	if(weedlevel >= 5 || pestlevel >= 5 || toxic >= 40)
		lamps += emissive_glow(tray_icon, "over_alert3", SOUTH, emissive_glow_alpha)
	if(harvest)
		lamps += emissive_glow(tray_icon, "over_harvest3", SOUTH, emissive_glow_alpha)
	set_emissive_glow(null, icon, length(lamps) ? lamps : null)
