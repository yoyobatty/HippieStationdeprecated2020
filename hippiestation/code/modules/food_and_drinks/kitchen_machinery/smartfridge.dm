/obj/machinery/smartfridge/drying_rack/update_icon()
	..()
	cut_overlays()
	if(drying)
		icon_state = "drying_rack_on"
	else
		icon_state = initial(icon_state)