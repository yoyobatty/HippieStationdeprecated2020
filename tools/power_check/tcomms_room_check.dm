// The telecomms server room's own nitrogen, looked at (HARNESS=tcomms_room_check.dm tools/power_check/run.sh <label>). Not part of the game.
// On the Hippie map (2026-11-13): the airlock's air tank is now a cold nitrogen tank, a vent off its pipe tops the server room up, a tiny fan
// on the computer-room door keeps the nitrogen in, and the room's fire alarms no longer trip on its cold. Checks the roundstart state, then
// lets half the room's gas out and watches the vent put it back, then lets nearly all of it out.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/tc_log(text)
	text2file(text, "data/update_check.txt")

/world/New()
	. = ..()
	spawn(0)
		tcomms_room_check_run()

/proc/tc_room_turfs()
	. = list()
	var/area/A = GLOB.areas_by_type[/area/tcommsat/server]
	for(var/turf/open/T in A)
		. += T

/proc/tc_room_line(label)
	var/list/turfs = tc_room_turfs()
	var/moles = 0
	var/pressure = 0
	var/temperature = 0
	var/n2 = 0
	for(var/turf/open/T as anything in turfs)
		var/datum/gas_mixture/G = T.air
		moles += G.total_moles()
		pressure += G.return_pressure()
		temperature += G.temperature
		n2 += G.moles[/datum/gas/nitrogen] || 0
	var/n = max(length(turfs), 1)
	tc_log("[label]: [length(turfs)] tiles, pressure [round(pressure / n, 0.1)] kPa, temperature [round(temperature / n, 0.1)] K, [round(moles)] mol ([round(moles ? n2 / moles * 100 : 0)]% N2)")
	return pressure / n

/proc/tc_check(ok, text)
	tc_log("[ok ? "PASS" : "FAIL"] [text]")

/proc/tcomms_room_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	CONFIG_SET(flag/allow_random_events, FALSE)
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(20 SECONDS)
	tc_log("round state [SSticker.current_state], map [SSmapping.config?.map_name]")

	var/obj/machinery/atmospherics/components/unary/tank/nitrogen/cold/tank = locate() in world
	tc_check(tank, "cold nitrogen tank on the map[tank ? " at [AREACOORD(tank)]" : ""]")
	if(tank)
		var/datum/gas_mixture/G = tank.airs[1]
		tc_log("    tank: [round(G.return_pressure())] kPa, [round(G.temperature, 0.1)] K, connected [!!tank.nodes[1]], network pressure [tank.parents[1] ? round(tank.parents[1].air.return_pressure()) : "none"]")
		tc_check(G.temperature < 100, "tank is cold")
	var/obj/machinery/atmospherics/components/unary/tank/air/air_tank = locate() in GLOB.areas_by_type[/area/construction]
	tc_check(!air_tank, "no air tank left in the construction room")

	var/obj/machinery/atmospherics/components/unary/vent_pump/vent = locate() in GLOB.areas_by_type[/area/tcommsat/server]
	tc_check(vent, "vent in the server room[vent ? " at [AREACOORD(vent)]" : ""]")
	if(vent)
		tc_log("    vent: on [vent.on], direction [vent.pump_direction], checks [vent.pressure_checks], bound [vent.external_pressure_bound] kPa, connected [!!vent.nodes[1]], same network as the tank [tank && vent.parents[1] == tank.parents[1]]")
		tc_check(vent.on && vent.nodes[1] && tank && vent.parents[1] == tank.parents[1], "vent is on and fed from the tank")

	var/obj/machinery/door/airlock/inner
	var/obj/machinery/door/airlock/outer
	for(var/obj/machinery/door/airlock/D in GLOB.airlocks)
		if(D.id_tag == "tcomm_airlock_interior")
			inner = D
		else if(D.id_tag == "tcomm_airlock_exterior")
			outer = D
	var/turf/open/fan_turf = inner && get_turf(inner)
	var/obj/structure/fans/tiny/fan = fan_turf && (locate() in fan_turf)
	tc_check(fan, "tiny fan on the computer-room door[fan ? " at [AREACOORD(fan)]" : ""]")
	if(fan_turf)
		var/list/adj = fan_turf.atmos_adjacent_turfs
		tc_check(!length(adj), "the fan's tile shares air with nothing ([length(adj)] neighbours)")
	var/turf/open/chamber = outer && get_step(outer, EAST)
	if(chamber)
		tc_log("    chamber [COORD(chamber)]: [chamber.type], [round(chamber.air.return_pressure(), 0.1)] kPa, [round(chamber.air.temperature, 0.1)] K")

	var/area/server = GLOB.areas_by_type[/area/tcommsat/server]
	tc_check(!server.fire, "server room fire alert is off after 20 s of round")
	var/alarms = 0
	for(var/obj/machinery/firealarm/F in server)
		alarms++
		tc_check(!(F.flags_1 & ATMOS_IS_PROCESSING_1), "fire alarm [COORD(F)] isn't watching the air")
	tc_log("    [alarms] fire alarms in the server room")

	var/start = tc_room_line("roundstart")
	// let half of it out
	for(var/turf/open/T as anything in tc_room_turfs())
		T.air.remove_ratio(0.5)
		T.air_update_turf()
	tc_room_line("half let out")
	for(var/i in 1 to 6)
		sleep(10 SECONDS)
		tc_room_line("  +[i * 10] s")
	var/after_half = tc_room_line("after a minute")
	tc_check(after_half >= start * 0.9, "half the gas back within a minute (start [round(start, 0.1)] kPa)")

	// nearly all of it
	for(var/turf/open/T as anything in tc_room_turfs())
		T.air.remove_ratio(0.97)
		T.air_update_turf()
	tc_room_line("97% let out")
	for(var/i in 1 to 12)
		sleep(10 SECONDS)
		tc_room_line("  +[i * 10] s")
	var/after_all = tc_room_line("after two minutes")
	tc_check(after_all >= start * 0.9, "nearly empty room back within two minutes")
	tc_check(!server.fire, "server room fire alert still off")
	if(tank)
		var/datum/gas_mixture/G = tank.airs[1]
		tc_log("    tank now: [round(G.return_pressure())] kPa, [round(G.temperature, 0.1)] K")
	tc_log("done")
