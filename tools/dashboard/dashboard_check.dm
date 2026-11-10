// Dashboard check (check.sh, headless): with no admin connected to make a link, this makes one when the dashboard starts and writes it to
// data/dashboard_check/link.txt for the script. Only in the check's own build (it's not in hippiestation.dme). Not part of the game.

/datum/controller/subsystem/dashboard/Initialize(start_timeofday)
	. = ..()
	if(("dashboard-check" in world.params) && can_fire)
		var/token = call_ext(DASHBOARD_LIB, "dashboard_token")("check", "3600")
		text2file("http://127.0.0.1:[port]/?t=[token]", "data/dashboard_check/link.txt")
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(dashboard_check_boom)), 60 SECONDS)

/// Something for the alerts feed: a small explosion beside somebody on the crew, a minute in
/proc/dashboard_check_boom()
	for(var/mob/living/carbon/human/H in GLOB.mob_living_list)
		if(H.mind?.assigned_role && H.stat != DEAD && is_station_level(H.z))
			explosion(get_turf(H), 1, 2, 4, adminlog = TRUE)
			return
