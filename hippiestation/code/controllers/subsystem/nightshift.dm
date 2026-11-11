// Night lighting dims the halls and the public rooms only. A department working through the night keeps its lights up,
// and so does anyone's workplace: tg dimmed every room on the station, operating tables and all. The Night shift station
// look (station_looks/looks_shift.dm) runs on this.

/// Areas that go onto night lighting: the halls and the rooms anyone walks into
GLOBAL_LIST_INIT(night_lit_areas, typecacheof(list(
	/area/hallway,
	/area/crew_quarters/dorms,
	/area/crew_quarters/locker,
	/area/crew_quarters/toilet,
	/area/crew_quarters/fitness,
	/area/crew_quarters/cafeteria,
	/area/crew_quarters/lounge,
	/area/crew_quarters/bar,
	/area/crew_quarters/theatre,
	/area/chapel/main,
	/area/library,
	/area/storage/primary,
	/area/storage/art,
	/area/hippie/pool)))

/datum/controller/subsystem/nightshift/update_nightshift(active, announce = TRUE)
	nightshift_active = active
	if(announce)
		if (active)
			announce("Good evening, crew. To reduce power consumption and stimulate the circadian rhythms of some species, the lights in the halls and public rooms have been dimmed for the night.")
		else
			announce("Good morning, crew. As it is now day time, the lights in the halls and public rooms have been restored to their former brightness.")
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(APC.area && (APC.area.type in GLOB.the_station_areas) && is_type_in_typecache(APC.area, GLOB.night_lit_areas))
			APC.set_nightshift(active)
			CHECK_TICK
