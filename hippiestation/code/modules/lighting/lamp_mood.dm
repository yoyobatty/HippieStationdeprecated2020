// Mood by place: an area can give its lamps a colour and a strength of their own, so the bar is warm, medbay is a cold white
// and maintenance is dim and amber. The tints are slight: a room should read as lit differently, not as coloured.
// A fixture mapped or built with a colour of its own keeps it, and night shift and emergency lighting still take over as before.

/area
	/// The colour of this area's lamps, for fixtures that are plain white. Null leaves them white
	var/lamp_colour
	/// How strong its lamps are next to the usual (1)
	var/lamp_power = 1

/obj/machinery/light/Initialize(mapload)
	var/area/A = get_area(src)
	if(A)
		if(A.lamp_colour && bulb_colour == "#FFFFFF")
			bulb_colour = A.lamp_colour
		bulb_power *= A.lamp_power
		// A tube in seven down in maintenance is on its way out (light_glow.dm)
		if(mapload && istype(A, /area/maintenance) && prob(14))
			wear_tube()
	. = ..()
	// Built after the round's shift time went on: it takes it too (station_looks/looks_lamps.dm). LateInitialize() lights it
	if(SSstation_looks.applied && (SSstation_looks.lamp_tint || SSstation_looks.night_tint) && z && is_station_level(z))
		refresh_look(FALSE)

// Clean and clinical
/area/medical
	lamp_colour = "#EAF5FF"

/area/medical/morgue
	lamp_colour = "#DCEBFF"
	lamp_power = 0.85

/area/science
	lamp_colour = "#F0EEFF"

/area/bridge
	lamp_colour = "#ECF2FF"

/area/ai_monitored
	lamp_colour = "#E6F0FF"

/area/tcommsat
	lamp_colour = "#E6F0FF"

/area/security
	lamp_colour = "#F1F4FF"

// Working light
/area/engine
	lamp_colour = "#FFF3DC"

/area/quartermaster
	lamp_colour = "#FFF1D6"

/area/storage
	lamp_colour = "#FFF3DC"

/area/janitor
	lamp_colour = "#FFF3DC"

/area/hydroponics
	lamp_colour = "#F4FFE6"

// Somewhere to sit down
/area/crew_quarters
	lamp_colour = "#FFEBD0"

/area/crew_quarters/bar
	lamp_colour = "#FFDDB0"
	lamp_power = 0.9

/area/crew_quarters/theatre
	lamp_colour = "#FFDDB0"

/area/crew_quarters/kitchen
	lamp_colour = "#FFF6E6"

/area/crew_quarters/toilet
	lamp_colour = "#F2F8FF"

/area/library
	lamp_colour = "#FFE6C4"
	lamp_power = 0.9

/area/chapel
	lamp_colour = "#FFE2B8"
	lamp_power = 0.85

/area/lawoffice
	lamp_colour = "#FFE6C4"

// Nobody's meant to be here
/area/maintenance
	lamp_colour = "#FFD9A6"
	lamp_power = 0.8
