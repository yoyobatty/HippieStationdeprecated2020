// Machines that glow in the dark (see emissive_glow.dm). Masks are in tools/icon_merge/glow.txt; the ore redemption machine's
// hook is in its own Hippie file, which replaces tg's update_icon() whole.

/obj/machinery/vending/update_icon()
	. = ..()
	update_state_glow()

// Indicator lights and glass fronts glow less than screens; disposal bins least
/obj/machinery/chem_dispenser
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/recharger
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/cell_charger
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/disposal/bin
	emissive_glow_alpha = EMISSIVE_GLOW_FAINT

/obj/machinery/power/smes
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/telecomms
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/holopad
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/smartfridge
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/dna_scannernew
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/smartfridge/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/telecomms/update_icon()
	. = ..()
	update_state_glow()

// Calls the one above, then cuts every overlay for its calibration light
/obj/machinery/telecomms/message_server/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/recharger/update_icon(using_power = 0, scan)
	. = ..()
	update_state_glow()

/obj/machinery/holopad/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/dna_scannernew/update_icon()
	. = ..()
	update_state_glow()

// The pod sets its sprite straight from wherever cloning starts and ends, without update_icon()
/obj/machinery/clonepod/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/clonepod/process()
	var/was = icon_state
	. = ..()
	if(icon_state != was)
		update_state_glow()

/obj/machinery/chem_dispenser/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/chem_master/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/computer/pandemic/update_icon()
	. = ..()
	update_state_glow(wait && !(stat & BROKEN) ? emissive_glow(icon, "waitlight") : null)

// The tube's liquid, lit while it runs: its whole cover glows, so a patient shows through it in the dark
/obj/machinery/atmospherics/components/unary/cryo_cell/update_icon()
	. = ..()
	set_emissive_glow(null, icon, icon_state == "pod-on" ? emissive_glow(icon, "cover-on") : null)

/obj/machinery/power/smes/update_icon()
	. = ..()
	if((stat & BROKEN) || panel_open)
		set_emissive_glow(null)
		return
	var/list/lights = list()
	lights += emissive_glow(icon, outputting ? "smes-op1" : "smes-op0", SOUTH, emissive_glow_alpha)
	if(inputting)
		lights += emissive_glow(icon, "smes-oc1", SOUTH, emissive_glow_alpha)
	else if(input_attempt)
		lights += emissive_glow(icon, "smes-oc0", SOUTH, emissive_glow_alpha)
	var/charge_level = chargedisplay()
	if(charge_level > 0)
		lights += emissive_glow(icon, "smes-og[charge_level]", SOUTH, emissive_glow_alpha)
	set_emissive_glow(null, icon, lights)

/obj/machinery/cell_charger/update_icon()
	. = ..()
	if(!charging || (stat & (BROKEN|NOPOWER)))
		set_emissive_glow(null)
		return
	set_emissive_glow(null, icon, emissive_glow(icon, "ccharger-o[chargelevel]", SOUTH, emissive_glow_alpha)) // the charge lights; "ccharger-on" is its wires

/obj/machinery/disposal/bin/update_icon()
	. = ..()
	if(stat & (BROKEN|NOPOWER) || panel_open)
		set_emissive_glow(null)
		return
	// The lamps only: the ready and charging overlays carry the vent panel too, so they glow by their masks
	var/list/lights = list()
	var/list/lamp
	if(contents.len && (lamp = emissive_glow_list(icon, "dispover-full", SOUTH, emissive_glow_alpha)))
		lights += lamp
	if(pressure_charging)
		lamp = emissive_glow_list(icon, "dispover-charge", SOUTH, emissive_glow_alpha)
	else if(full_pressure)
		lamp = emissive_glow_list(icon, "dispover-ready", SOUTH, emissive_glow_alpha)
	else
		lamp = null
	if(lamp)
		lights += lamp
	set_emissive_glow(null, icon, length(lights) ? lights : null)

// The UV lamps while it cleans
/obj/machinery/suit_storage_unit/update_icon()
	. = ..()
	if(!uv)
		set_emissive_glow(null)
		return
	set_emissive_glow(null, icon, emissive_glow(icon, uv_super ? "super" : (occupant ? "uvhuman" : "uv")))
