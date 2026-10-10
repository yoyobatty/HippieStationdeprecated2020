// Bot Gym scenarios for the solars (goals/solars.dm). The PDA light in the same file has none: an arena has no
// dynamic lighting, so nowhere in the gym is ever dark - it's checked on the station (bot_shift.dm).
//
// Layout letters used here: = plating with a cable on it (the legend's own); the solar console, a tracker and a
// panel are put on the first three of those.

/datum/bot_scenario/duty/solars
	name = "engineer sets a solar array tracking"
	desc = "A solar console wired to a tracker and a panel, and switched to nothing. The engineer walks up, presses Refresh so the console finds what's on its wiring, then Auto - two presses, a moment apart."
	duty_type = /datum/bot_duty/solars
	job = "Station Engineer"
	layout = list(
		"##########",
		"#B...===.#",
		"##########")
	time_limit = 40 SECONDS

/datum/bot_scenario/duty/solars/setup()
	var/list/wired = markers["="]
	if(length(wired) < 3)
		return
	// Nearest the bot first: the console has to be the one it can walk up to.
	var/turf/start = first_marker("B")
	var/list/by_distance = list()
	for(var/turf/T in wired)
		var/at = 1
		for(var/turf/other in by_distance)
			if(get_dist(start, T) < get_dist(start, other))
				break
			at++
		by_distance.Insert(at, T)
	var/obj/machinery/power/solar_control/console = place("console", new /obj/machinery/power/solar_control(by_distance[1]))
	var/obj/machinery/power/tracker/tracker = place("tracker", new /obj/machinery/power/tracker(by_distance[2]))
	var/obj/machinery/power/solar/panel = place("panel", new /obj/machinery/power/solar(by_distance[3]))
	// One circuit for the three of them, whatever the arena's loose cables made of themselves.
	var/datum/powernet/net = new
	for(var/obj/machinery/power/M in list(console, tracker, panel))
		if(M.powernet)
			M.disconnect_from_network()
		net.add_machine(M)

/datum/bot_scenario/duty/solars/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/power/solar_control/C = first_placed("console")
	if(!C || C.track != SOLAR_TRACK_AUTO || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(!C.connected_tracker || !length(C.connected_panels))
		fail_reason = "set to auto without finding its tracker and panels first"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
