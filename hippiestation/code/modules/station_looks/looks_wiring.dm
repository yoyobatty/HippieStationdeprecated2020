// Tired wiring: the station is overdue for an electrical service. One tube in ten out of maintenance has gone yellow, half
// of those sputter and in the end burn out (the janitor's work), a lamp in each hall hums, and one department's lighting
// breakers have tripped, so it starts on emergency lights: about ten minutes of red from the fittings' own cells, then dark,
// until someone sets the lighting back to auto at its APCs.
// What it did is kept on the lamps and APCs themselves (looks_lamps.dm), not here, so nothing it touched is held from deletion.

/obj/machinery/power/apc
	/// What the lighting was set to before Tired wiring tripped it, or null if it didn't
	var/look_tripped_from

/datum/station_look/tired_wiring
	id = "tired_wiring"
	name = "Tired wiring"
	slot = LOOK_SLOT_EXTRA
	/// The department whose breakers tripped this time
	var/department
	/// The departments that can trip: name -> its areas
	var/static/list/departments = list(
		"Science" = list(/area/science),
		"Cargo" = list(/area/quartermaster),
		"Medbay" = list(/area/medical),
		"Engineering" = list(/area/engine),
		"Service" = list(/area/crew_quarters/bar, /area/crew_quarters/kitchen, /area/hydroponics))

/datum/station_look/tired_wiring/news_line()
	return "Wiring overdue for service: lighting breakers tripped in [department || "one department"]."

/datum/station_look/tired_wiring/apply(at_start)
	..()
	department = pick(departments)
	INVOKE_ASYNC(src, PROC_REF(wear_station))

/datum/station_look/tired_wiring/proc/wear_station()
	var/yellowed = 0
	var/list/hall_lamps = list() //hallway area -> its lamps, the yellowed ones first
	for(var/obj/machinery/light/L as anything in station_lamps())
		if(QDELETED(L) || L.status != LIGHT_OK || L.worn || L.yellowed)
			continue
		var/area/A = get_area(L)
		if(!A || !(A.type in GLOB.the_station_areas) || istype(A, /area/maintenance))
			continue
		if(prob(10))
			if(!L.look_base)
				L.refresh_look(FALSE)
			if(L.plain_lamp())
				L.yellowed = TRUE
				L.refresh_look()
				yellowed++
				if(prob(50))
					L.tired = TRUE
					L.wear_tube()
		if(istype(A, /area/hallway))
			var/list/lamps = hall_lamps[A]
			if(!lamps)
				lamps = list()
				hall_lamps[A] = lamps
			if(L.yellowed)
				lamps.Insert(1, L)
			else
				lamps += L
		CHECK_TICK
	for(var/area/A as anything in hall_lamps)
		var/list/lamps = hall_lamps[A]
		var/obj/machinery/light/L = lamps[1]
		if(!L.yellowed)
			L = pick(lamps)
		L.start_buzz()
	var/tripped = 0
	var/list/areas = typecacheof(departments[department])
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(!APC.area || !(APC.area.type in GLOB.the_station_areas) || !is_type_in_typecache(APC.area, areas))
			continue
		if((APC.stat & BROKEN) || APC.lighting < 2)
			continue
		APC.look_tripped_from = APC.lighting
		APC.lighting = 0
		APC.update()
		APC.update_icon()
		tripped++
	log_game("Tired wiring: [yellowed] tubes yellowed, [length(hall_lamps)] humming, [tripped] APCs in [department] with their lighting tripped")

/datum/station_look/tired_wiring/remove()
	..()
	department = null
	INVOKE_ASYNC(src, PROC_REF(unwear_station))

/datum/station_look/tired_wiring/proc/unwear_station()
	for(var/obj/machinery/light/L as anything in station_lamps())
		if(L.buzzing)
			L.stop_buzz()
		if(L.tired)
			L.tired = FALSE
			L.worn = FALSE
			GLOB.worn_lights -= L
		if(L.yellowed)
			L.yellowed = FALSE
			L.refresh_look()
		CHECK_TICK
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(isnull(APC.look_tripped_from))
			continue
		if(APC.lighting == 0) //still tripped: nobody's set it since
			APC.lighting = APC.look_tripped_from
			APC.update()
			APC.update_icon()
		APC.look_tripped_from = null
