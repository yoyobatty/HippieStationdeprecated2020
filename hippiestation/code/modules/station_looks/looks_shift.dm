// Shift time: when the shift starts, which sets the station clock and how the lamps look. Every round gets one.
// The tints are slight, as lamp_mood.dm's are: the station should read as lit differently, not as coloured.

/datum/station_look/shift
	slot = LOOK_SLOT_SHIFT
	/// When the station clock starts, as list(earliest, latest) in minutes past midnight (over 1440 runs into the next day). Null leaves it
	var/list/clock
	/// The station's lamps take this colour multiplied in, or null for none
	var/lamp_tint
	/// ...and this much of their power
	var/lamp_power = 1
	/// Lamps on night lighting take this colour multiplied in, or null to keep tg's
	var/night_tint

/datum/station_look/shift/apply(at_start)
	..()
	if(clock)
		set_station_clock(rand(clock[1], clock[2]))
	if(lamp_tint || lamp_power != 1 || night_tint)
		SSstation_looks.lamp_tint = lamp_tint
		SSstation_looks.lamp_power = lamp_power
		SSstation_looks.night_tint = night_tint
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(refresh_station_lamps))

/datum/station_look/shift/remove()
	..()
	if(lamp_tint || lamp_power != 1 || night_tint)
		SSstation_looks.lamp_tint = null
		SSstation_looks.lamp_power = 1
		SSstation_looks.night_tint = null
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(refresh_station_lamps))

/// Sets the station clock to read this many minutes past midnight now, to the nearest five.
/proc/set_station_clock(minutes)
	var/target = (round(minutes, 5) MINUTES) % (24 HOURS)
	var/passed = SSticker.HasRoundStarted() ? (world.time - SSticker.round_start_time) * SSticker.station_time_rate_multiplier : 0
	SSticker.gametime_offset = ((target - passed) % (24 HOURS) + 24 HOURS) % (24 HOURS)

/// Every station lamp works its look out again, after the shift time's tint changed.
/proc/refresh_station_lamps()
	for(var/obj/machinery/light/L as anything in station_lamps())
		if(!QDELETED(L))
			L.refresh_look()
		CHECK_TICK

/datum/station_look/shift/day
	id = "day"
	name = "Day shift"
	weight = 35
	clock = list(600, 900)

/datum/station_look/shift/morning
	id = "morning"
	name = "Morning shift"
	weight = 20
	clock = list(460, 570)
	lamp_tint = "#FFF0DA"
	news = "Morning shift."

/// The halls and public rooms on night lighting all round (SSnightshift, nightshift.dm), cooler than tg's
/datum/station_look/shift/night
	id = "night"
	name = "Night shift"
	weight = 30
	clock = list(1260, 1560)
	night_tint = "#CAD8FF"
	news = "Night shift: halls and public rooms on night lighting."
	/// Whether SSnightshift was firing before, to leave it as it was
	var/nightshift_fired

/datum/station_look/shift/night/apply(at_start)
	..()
	nightshift_fired = SSnightshift.can_fire
	SSnightshift.nightshift_end_time = 24 HOURS //the night lasts the round, whatever the clock says
	SSnightshift.can_fire = TRUE //so red alert still brings the lights up
	SSnightshift.update_nightshift(TRUE, FALSE)

/datum/station_look/shift/night/remove()
	..()
	SSnightshift.nightshift_end_time = initial(SSnightshift.nightshift_end_time)
	SSnightshift.can_fire = nightshift_fired
	SSnightshift.update_nightshift(FALSE, FALSE)

/datum/station_look/shift/power_saving
	id = "power_saving"
	name = "Power-saving"
	weight = 15
	lamp_tint = "#FFEED5" //halfway to white: dimmed lamps, not orange rooms (user, 2026-11-11)
	lamp_power = 0.8
	news = "Power-saving order in force: lamps dimmed."
