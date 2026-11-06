// The grid check event, looked at (HARNESS=grid_check.dm tools/power_check/run.sh <label>). Not part of the game.
// Runs the real event on the real station, then: every machine in a room it blacked out should say it has no power while the outage
// lasts, a machine built in one of those rooms mid-outage too, every light there should be off or on emergency power, and once the
// power is back everything that had power before should have it again and every light that was on should be on. It also times what
// the outage costs SSmachines and SSlighting against the same stretch before it.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/gc_log(text)
	text2file(text, "data/update_check.txt")

/world/New()
	. = ..()
	spawn(0)
		grid_check_run()

/proc/gc_station_machines()
	. = list()
	for(var/obj/machinery/M in GLOB.machines)
		if(M.z && is_station_level(M.z) && isturf(M.loc) && !istype(M, /obj/machinery/power/apc))
			. += M

/proc/gc_cost(datum/controller/subsystem/SS, seconds)
	var/start = SS.total_ms
	sleep(seconds SECONDS)
	return round((SS.total_ms - start) / seconds, 0.1)

/proc/grid_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	CONFIG_SET(flag/allow_random_events, FALSE)
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(15 SECONDS)
	var/list/machines = gc_station_machines()
	var/list/was_powered = list()
	var/list/was_on = list()
	for(var/obj/machinery/M as anything in machines)
		was_powered[M] = !(M.stat & NOPOWER)
		if(istype(M, /obj/machinery/light))
			var/obj/machinery/light/L = M
			was_on[M] = L.on
	var/machines_before = gc_cost(SSmachines, 10)
	var/lighting_before = gc_cost(SSlighting, 10)
	gc_log("round state [SSticker.current_state], [length(machines)] station machines; before the outage: Machines [machines_before] ms a second, Lighting [lighting_before]")

	for(var/datum/round_event_control/grid_check/C in SSevents.control)
		C.runEvent()
	var/list/obj/machinery/power/apc/failing = list()
	deadline = world.time + 20 SECONDS
	while(!length(failing) && world.time < deadline)
		sleep(1 SECONDS)
		for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
			if(A.failure_timer && A.area)
				failing += A
	if(!length(failing))
		gc_log("the grid check failed no APCs")
		gc_log("done")
		return
	sleep(3 SECONDS) // a couple of their process() ticks
	for(var/obj/machinery/power/apc/A as anything in failing)
		A.failure_timer = 15 // 30 seconds of outage from here, the same for every room
	var/list/area/dark = list()
	for(var/obj/machinery/power/apc/A as anything in failing)
		dark[A.area] = TRUE
	var/machines_during = gc_cost(SSmachines, 10)
	var/lighting_during = gc_cost(SSlighting, 10)
	gc_log("[length(failing)] APCs failed; during the outage: Machines [machines_during] ms a second, Lighting [lighting_during]")

	var/in_dark = 0
	var/says_powered = 0
	var/lit = 0
	var/emergency = 0
	var/list/examples = list()
	for(var/obj/machinery/M as anything in machines)
		if(QDELETED(M) || !dark[get_area(M)] || (M.stat & BROKEN))
			continue
		in_dark++
		if(M.use_power && !(M.stat & NOPOWER) && !istype(M, /obj/machinery/light)) // lights never set NOPOWER: their power_change() doesn't call the parent
			says_powered++
			if(length(examples) < 5)
				examples += "[M.type] in [get_area_name(M)]"
		if(istype(M, /obj/machinery/light))
			var/obj/machinery/light/L = M
			if(L.on)
				lit++
			if(L.emergency_mode)
				emergency++
	gc_log("in the dark rooms: [in_dark] machines, [says_powered] SAY THEY HAVE POWER[length(examples) ? " ([jointext(examples, "; ")])" : ""]; lights: [lit] STILL ON, [emergency] on emergency power")

	// Built mid-outage, in a dark room
	var/obj/machinery/power/apc/some = failing[1]
	var/turf/open/floor/spot
	for(var/turf/open/floor/F in get_area_turfs(some.area.type))
		if(!is_blocked_turf(F, TRUE))
			spot = F
			break
	if(spot)
		var/obj/machinery/vending/cola/V = new(spot)
		gc_log("a vending machine built in [some.area.name] mid-outage: [(V.stat & NOPOWER) ? "no power, as it should" : "SAYS IT HAS POWER"]")
		qdel(V)

	deadline = world.time + 90 SECONDS
	while(world.time < deadline)
		var/still = FALSE
		for(var/obj/machinery/power/apc/A as anything in failing)
			if(A.failure_timer)
				still = TRUE
				break
		if(!still)
			break
		sleep(1 SECONDS)
	sleep(8 SECONDS)
	var/no_power = 0
	var/dark_lights = 0
	examples = list()
	for(var/obj/machinery/M as anything in machines)
		if(QDELETED(M) || (M.stat & BROKEN))
			continue
		if(was_powered[M] && (M.stat & NOPOWER))
			no_power++
			if(length(examples) < 5)
				examples += "[M.type] in [get_area_name(M)]"
		if(was_on[M])
			var/obj/machinery/light/L = M
			if(!L.on)
				dark_lights++
	gc_log("power back: [no_power] machines STILL WITHOUT POWER[length(examples) ? " ([jointext(examples, "; ")])" : ""], [dark_lights] lights that were on STILL OFF")
	gc_log("done")
