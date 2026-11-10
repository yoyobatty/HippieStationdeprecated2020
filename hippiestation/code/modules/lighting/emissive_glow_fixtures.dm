// Doors and wall fixtures that glow in the dark (see emissive_glow.dm). Masks are in tools/icon_merge/glow.txt.

// Airlocks: the bolt, emergency, deny and opening/closing lights, and the green arrows of an unrestricted side
/obj/machinery/door/airlock
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/door/airlock/proc/airlock_glow(mutable_appearance/lights_overlay)
	var/list/arrows
	if(unres_sides && hasPower())
		arrows = list()
		var/arrow_icon = 'icons/obj/doors/airlocks/station/overlays.dmi'
		if(unres_sides & NORTH)
			arrows += emissive_glow(arrow_icon, "unres_n", SOUTH, emissive_glow_alpha, 0, 32)
		if(unres_sides & SOUTH)
			arrows += emissive_glow(arrow_icon, "unres_s", SOUTH, emissive_glow_alpha, 0, -32)
		if(unres_sides & EAST)
			arrows += emissive_glow(arrow_icon, "unres_e", SOUTH, emissive_glow_alpha, 32, 0)
		if(unres_sides & WEST)
			arrows += emissive_glow(arrow_icon, "unres_w", SOUTH, emissive_glow_alpha, -32, 0)
	set_emissive_glow(lights_overlay?.icon_state, overlays_file, arrows)

// Indicator lights and small panels glow less than screens (requests consoles, newscasters, status displays stay full)
/obj/machinery/airalarm
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/button
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/light_switch
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/flasher
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/turretid
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/camera
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/airlock_sensor
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/embedded_controller
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/doorButtons
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/keycard_auth
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/item/radio/intercom
	emissive_glow_alpha = EMISSIVE_GLOW_INDICATOR

/obj/machinery/airalarm/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/button/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/light_switch/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/flasher/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/requests_console/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/newscaster/update_icon()
	. = ..()
	update_state_glow(icon_state == "newscaster_normal" && alert ? emissive_glow(icon, "newscaster_alert") : null)

/obj/machinery/turretid/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/camera/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/airlock_sensor/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/embedded_controller/radio/airlock_controller/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/embedded_controller/radio/simple_vent_controller/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/doorButtons/access_button/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/doorButtons/airlock_controller/update_icon()
	. = ..()
	update_state_glow()

/obj/machinery/keycard_auth/triggerEvent(source)
	. = ..()
	update_state_glow()

/obj/machinery/keycard_auth/eventTriggered()
	. = ..()
	update_state_glow()

// Intercoms are items, so they'd carry an emissive blocker that hides their own glow
/obj/item/radio/intercom
	blocks_emissive = FALSE

/obj/item/radio/intercom/Initialize(mapload, ndir, building)
	. = ..()
	update_state_glow()

/obj/item/radio/intercom/process()
	var/was = icon_state
	. = ..()
	if(icon_state != was)
		update_state_glow()

// Status displays and door timers: the pictures and the scrolling text
/obj/machinery/status_display/remove_display()
	. = ..()
	emissive_glow_text = null
	set_emissive_glow(null)

/obj/machinery/status_display/set_picture(state)
	. = ..()
	emissive_glow_text = null
	set_emissive_glow(state)

/obj/machinery/status_display/update_display(line1, line2)
	. = ..()
	glow_maptext()

/obj/machinery
	/// The text glow_maptext() last made glow; a display re-sends the same text every couple of seconds
	var/emissive_glow_text

/// The display's text, glowing: a copy of its maptext on the glow planes
/obj/machinery/proc/glow_maptext()
	if(maptext == emissive_glow_text && emissive_glow_shown)
		return
	emissive_glow_text = maptext
	if(!maptext)
		set_emissive_glow(null)
		return
	set_emissive_glow(null, icon, emissive_glow(null, null, SOUTH, 255, 0, 0, maptext, maptext_width, maptext_height, maptext_y))

/obj/machinery/door_timer/update_icon()
	. = ..()
	if((stat & NOPOWER) || (!maptext && !(stat & BROKEN)))
		emissive_glow_text = null
		set_emissive_glow(null)

/obj/machinery/door_timer/set_picture(state)
	. = ..()
	emissive_glow_text = null
	set_emissive_glow(state, 'icons/obj/status_display.dmi')

/obj/machinery/door_timer/update_display(line1, line2)
	. = ..()
	glow_maptext()
