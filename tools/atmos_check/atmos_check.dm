// Gas tanks self-test (hippiestation/code/game/machinery/computer/atmos_control.dm), in the real engine on a real map. Not part
// of the game: tools/atmos_check/run_atmos_check.sh
//
// atmos-check=roundstart: every tank console, sensor and monitoring console the map brought, linked as it should be.
// atmos-check=full: that, then the Oxygen tank's console driven through ui_act, and its injector, vent and sensor broken and
// put back the ways a player would (the dropped fitting, a new fitting, a multitool, a new sensor).

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("atmos-check" in world.params)
		sleep_offline_after_initializations = FALSE // nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_atmos_check))
	return ..()

#define ATMOS_CHECK_DIR "data/atmos_check/"

/proc/run_atmos_check()
	sleep(5 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/datum/atmos_check/test = new
	test.check("round started", SSticker.current_state >= GAME_STATE_PLAYING, "state [SSticker.current_state], map [SSmapping.config.map_name]")
	test.roundstart()
	if(world.params["atmos-check"] == "full")
		test.full()
	test.lines += "done: [test.passed] passed, [test.failed] failed"
	text2file(jointext(test.lines, "\n"), "[ATMOS_CHECK_DIR]results_[SSmapping.config.map_name].txt")
	log_world("ATMOS CHECK: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/tgui/atmos_check_stub/New()
	status = UI_INTERACTIVE

/datum/atmos_check
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/mob/living/carbon/human/tester

/datum/atmos_check/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/datum/atmos_check/proc/note(text)
	lines += "     [text]"

/datum/atmos_check/proc/act(datum/D, action, list/params = list())
	var/datum/tgui/atmos_check_stub/stub = new
	usr = tester
	return D.ui_act(action, params, stub, GLOB.default_state)

/datum/atmos_check/proc/where(atom/A)
	return A ? "[A.x],[A.y],[A.z] [get_area_name(A, TRUE)]" : "nowhere"

// ---- what the map brought

/datum/atmos_check/proc/roundstart()
	// each console has its chamber's sensor, and the sensor has every mapped device the console's old tags name (and the
	// old naming's): whatever the map gave the tank is linked
	var/consoles = 0
	for(var/obj/machinery/computer/atmos_control/tank/C in GLOB.atmos_air_controllers)
		var/obj/machinery/air_sensor/S = C.find_sensor()
		var/obj/machinery/atmospherics/components/unary/in_port = S?.get_inlet()
		var/obj/machinery/atmospherics/components/unary/out_port = S?.get_outlet()
		var/mapped_in = atmos_tagged_port(C.input_tag, 1, C.z) || atmos_tagged_port("[C.chamber_id]_in", 1, C.z)
		var/mapped_out = atmos_tagged_port(C.output_tag, 2, C.z) || atmos_tagged_port("[C.chamber_id]_out", 2, C.z)
		var/sensor_mapped = FALSE
		for(var/obj/machinery/air_sensor/any as anything in GLOB.air_sensors)
			if(any.chamber_id == C.chamber_id && any.z == C.z)
				sensor_mapped = TRUE
		var/detail = "chamber [C.chamber_id], sensor [S ? where(S) : "none"], injector [in_port ? in_port.name : "none"][mapped_in ? "" : " (none mapped)"], vent [out_port ? out_port.name : "none"][mapped_out ? "" : " (none mapped)"]"
		var/ok = (S || !sensor_mapped) && (!mapped_in || in_port == mapped_in) && (!mapped_out || out_port == mapped_out)
		if(is_station_level(C.z))
			consoles++
		check("roundstart: [C.name] at [where(C)] has what its map gave it", ok, detail)
		if(is_station_level(C.z) && !(S && in_port && out_port))
			note("this map gives that tank: sensor [sensor_mapped ? "yes" : "NO"], injector [mapped_in ? "yes" : "NO"], vent [mapped_out ? "yes" : "NO"]")
	note("[consoles] tank consoles on the station")
	for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
		var/list/chamber = atmos_closed_chamber(get_turf(S), 1000)
		note("sensor [S.name] ([S.chamber_id]) at [where(S)]: input [S.get_inlet() ? "yes" : "no"], output [S.get_outlet() ? "yes" : "no"], closed chamber [chamber ? "[length(chamber)] tiles" : "no (open to space or over 1000 tiles)"]")
		if(is_station_level(S.z) && (S.get_inlet() || S.get_outlet()))
			check("roundstart: [S.name]'s tank links up by itself if rebuilt (closed, at most 64 tiles)", chamber && length(chamber) <= 64, chamber ? "[length(chamber)] tiles" : "not closed")
	for(var/obj/machinery/computer/atmos_control/C in GLOB.atmos_air_controllers)
		if(istype(C, /obj/machinery/computer/atmos_control/tank))
			continue
		// a row it can't read is a fault, unless the map's meter isn't on a pipe
		var/list/data = C.ui_data(null)
		var/list/missing = list()
		var/list/unpiped = list()
		for(var/list/row in data["chambers"])
			if(row["present"])
				continue
			var/obj/machinery/meter/M = row["kind"] == "loop" ? C.find_meter(row["id"]) : null
			if(M && !M.target)
				unpiped += row["name"]
			else
				missing += row["name"]
		check("roundstart: monitoring console at [where(C)] reads everything it lists", !length(missing), "[length(data["chambers"])] shown, missing: [english_list(missing, "none")][length(unpiped) ? ", meter on no pipe in the map: [english_list(unpiped)]" : ""]")

// ---- a player's ways, on the Oxygen tank

/datum/atmos_check/proc/full()
	var/obj/machinery/computer/atmos_control/tank/C = locate(/obj/machinery/computer/atmos_control/tank/oxygen_tank) in GLOB.atmos_air_controllers
	var/obj/machinery/air_sensor/S = C?.find_sensor()
	if(!S || !S.get_inlet() || !S.get_outlet())
		check("full: an Oxygen tank to work on", FALSE)
		return
	var/turf/tank_floor = get_turf(S)
	tester = new /mob/living/carbon/human(get_turf(C))
	tester.status_flags |= GODMODE
	// a new sensor's chamber picker starts on the tank it's put down in, going by the tank's mapped devices
	check("put down in the Oxygen tank, a new sensor's picker starts on it", atmos_chamber_here(tank_floor) == "o2", "[atmos_chamber_here(tank_floor)]")
	check("put down outside any tank, it guesses nothing", isnull(atmos_chamber_here(get_turf(C))), "[atmos_chamber_here(get_turf(C))]")

	// the console drives the devices at once, no radio
	var/obj/machinery/atmospherics/components/unary/outlet_injector/injector = S.get_inlet()
	var/obj/machinery/atmospherics/components/unary/vent_pump/vent = S.get_outlet()
	var/list/data = C.ui_data(tester)
	var/list/air = data["air"]
	check("console reads the tank", air["present"] && air["pressure"] > 100 && length(air["gases"]), "[air["pressure"]] kPa, [length(air["gases"])] gases")
	var/was_on = injector.on
	act(C, "input")
	check("Input toggles the injector at once", injector.on == !was_on, "[was_on] -> [injector.on]")
	act(C, "input")
	act(C, "rate", list("rate" = 37))
	check("Rate sets the injector", injector.volume_rate == 37, "[injector.volume_rate]")
	act(C, "rate", list("rate" = "max"))
	check("Rate max", injector.volume_rate == MAX_TRANSFER_RATE, "[injector.volume_rate]")
	act(C, "rate", list("rate" = 99999))
	check("Rate is capped", injector.volume_rate == MAX_TRANSFER_RATE, "[injector.volume_rate]")
	act(C, "rate", list("rate" = "junk"))
	check("Rate ignores junk", injector.volume_rate == MAX_TRANSFER_RATE, "[injector.volume_rate]")
	var/vent_was_on = vent.on
	act(C, "output")
	check("Output toggles the vent at once", vent.on == !vent_was_on, "[vent_was_on] -> [vent.on]")
	act(C, "pressure", list("pressure" = 1234))
	check("Pressure sets the vent", vent.internal_pressure_bound == 1234, "[vent.internal_pressure_bound]")
	act(C, "pressure", list("pressure" = -50))
	check("Pressure floors at 0", vent.internal_pressure_bound == 0, "[vent.internal_pressure_bound]")
	act(C, "pressure", list("pressure" = 99999))
	check("Pressure is capped", vent.internal_pressure_bound == MAX_OUTPUT_PRESSURE, "[vent.internal_pressure_bound]")
	data = C.ui_data(tester)
	var/list/out_data = data["output"]
	check("window shows the vent's new settings", out_data["pressure"] == MAX_OUTPUT_PRESSURE && out_data["on"] == !!vent.on)

	// the vent really runs on the new setting (the idle registry is woken): shut, the pipe drains; opened to the top, it fills
	if(vent.on)
		act(C, "output")
	sleep(4 SECONDS)
	var/datum/gas_mixture/pipe_air = vent.airs[1]
	var/before = pipe_air.return_pressure()
	act(C, "output")
	act(C, "pressure", list("pressure" = "max"))
	sleep(6 SECONDS)
	pipe_air = vent.airs[1]
	var/after = pipe_air.return_pressure()
	check("opened from the console, the vent siphons the tank into its pipe", after > before + 50 || after > MAX_OUTPUT_PRESSURE - 100, "pipe [round(before, 0.1)] -> [round(after, 0.1)] kPa")
	act(C, "pressure", list("pressure" = 4000))

	// the injector breaks: its fitting, wrenched back down, links again
	var/injector_type = injector.type
	var/injector_dir = injector.dir
	var/turf/injector_floor = get_turf(injector)
	var/turf/vent_floor = get_turf(vent)
	injector.deconstruct(FALSE)
	var/obj/item/pipe/fitting = locate() in injector_floor
	check("a broken injector drops its fitting", fitting && fitting.pipe_type == injector_type, fitting ? "[fitting.pipe_type]" : "none")
	data = C.ui_data(tester)
	check("the window says no injector", isnull(data["input"]))
	var/obj/item/wrench/W = new(tester)
	if(fitting)
		fitting.wrench_act(tester, W)
	injector = S.get_inlet()
	check("the fitting wrenched back down links again", injector && injector.type == injector_type && get_turf(injector) == injector_floor, injector ? "[injector.type]" : "none")

	// replaced with a new one from a pipe dispenser: links with the sensor of its closed chamber
	if(injector)
		qdel(injector)
	var/obj/item/pipe/directional/new_fitting = new(injector_floor, /obj/machinery/atmospherics/components/unary/outlet_injector, injector_dir)
	new_fitting.wrench_act(tester, W)
	injector = S.get_inlet()
	check("a new injector in the tank links by itself", injector && injector.type == /obj/machinery/atmospherics/components/unary/outlet_injector, injector ? "[injector.type]" : "none")
	if(injector)
		check("it runs as fast as the mapped one", injector.volume_rate == MAX_TRANSFER_RATE, "[injector.volume_rate]")
		act(C, "input")
		check("and the console drives it", injector.on, "[injector.on]")

	// the same for the vent: a room's vent, set up as a tank outlet and let go by the air alarm
	var/vent_dir = vent.dir
	qdel(vent)
	var/obj/item/pipe/directional/vent_fitting = new(vent_floor, /obj/machinery/atmospherics/components/unary/vent_pump, vent_dir)
	vent_fitting.wrench_act(tester, W)
	vent = S.get_outlet()
	check("a new vent in the tank links by itself", vent && vent.type == /obj/machinery/atmospherics/components/unary/vent_pump, vent ? "[vent.type]" : "none")
	if(vent)
		var/area/A = get_area(vent)
		check("it siphons to the pipe as a tank outlet", vent.pump_direction == 0 && vent.pressure_checks == 2 && vent.internal_pressure_bound == MAX_OUTPUT_PRESSURE, "direction [vent.pump_direction], checks [vent.pressure_checks], bound [vent.internal_pressure_bound]")
		check("and the room's air alarm lets it go", !vent.frequency && !vent.radio_connection && !A.air_vent_names[vent.id_tag], "frequency [vent.frequency], in [A.name]'s list [!!A.air_vent_names[vent.id_tag]]")

	// a multitool: a device outside any closed chamber, linked by hand both ways
	var/turf/open/outside = get_turf(C)
	var/obj/item/pipe/directional/far_fitting = new(outside, /obj/machinery/atmospherics/components/unary/outlet_injector, SOUTH)
	far_fitting.wrench_act(tester, W)
	var/obj/machinery/atmospherics/components/unary/outlet_injector/far = locate() in outside
	check("an injector outside the tank doesn't link by itself", far && !atmos_port_sensor(far), far ? "linked to [atmos_port_sensor(far)]" : "not built")
	var/obj/item/multitool/M = new(tester)
	tester.forceMove(get_turf(S))
	S.multitool_act(tester, M)
	check("multitool on the sensor saves it", M.buffer == S)
	if(far)
		far.multitool_act(tester, M)
		check("then on an injector links it", S.get_inlet() == far && M.buffer == S)
		check("and takes the old one off", injector && !atmos_port_sensor(injector))
		M.buffer = null
		injector.multitool_act(tester, M)
		check("multitool on the injector saves it", M.buffer == injector)
		S.multitool_act(tester, M)
		check("then on the sensor links it", S.get_inlet() == injector && M.buffer == S)
		M.atmos_buffer(far)
		qdel(far)
		check("a deleted device leaves the buffer", isnull(M.buffer))

	// clearing a sensor's links (multitool twice), and a sensor put down again
	M.atmos_buffer(S)
	S.multitool_act(tester, M) // no client: the Clear prompt answers with its first button
	check("multitool twice on the sensor clears its links", !S.get_inlet() && !S.get_outlet())
	S.autolink(tester)
	check("a sensor finds its chamber's devices again", S.get_inlet() == injector && S.get_outlet() == vent)

	// the sensor is lost: the console says so, and a new one for the chamber takes over by itself
	qdel(S)
	data = C.ui_data(tester)
	check("the window says no sensor", !data["sensor"] && isnull(data["input"]))
	var/list/choices = atmos_sensor_chamber_choices(tank_floor.z)
	check("a new sensor can be for the Oxygen tank", choices["Oxygen Supply"] == "o2", "[length(choices)] choices")
	check("or a tank of the player's own", choices["BZ Supply"] == "gas_bz", "[choices["BZ Supply"]]")
	check("the Oxygen tank, having lost its sensor, is listed first", length(choices) && choices[1] == "Oxygen Supply", "first: [length(choices) ? choices[1] : "none"]")
	var/obj/item/air_sensor/sensor_item = new(tester)
	var/obj/machinery/autolathe/lathe = new(outside)
	check("the gas sensor is in the autolathe", lathe.stored_research.isDesignResearchedID("air_sensor"))
	qdel(lathe)
	sensor_item.wrench_act(tester, W)
	check("a sensor in hand isn't put down", sensor_item.loc == tester)
	var/obj/machinery/air_sensor/new_sensor = new(tank_floor, "o2")
	new_sensor.autolink(tester)
	check("a new Oxygen sensor takes the tank's injector and vent", new_sensor.get_inlet() == injector && new_sensor.get_outlet() == vent)
	data = C.ui_data(tester)
	check("the console finds it with nothing pressed", data["sensor"] && data["input"] && data["output"])
	sensor_item.forceMove(tank_floor)
	sensor_item.wrench_act(tester, W)
	check("a second sensor isn't put on the same tile", !QDELETED(sensor_item) && sensor_item.loc == tank_floor)

	// a tank console of the player's own, and one with nothing to connect to
	var/obj/machinery/computer/atmos_control/tank/built = new(outside)
	data = built.ui_data(tester)
	check("a new tank console isn't connected", isnull(data["chamber"]) && !data["sensor"])
	act(built, "input")
	act(built, "pressure", list("pressure" = 10))
	check("and its controls do nothing", vent?.internal_pressure_bound == MAX_OUTPUT_PRESSURE)
	built.chamber_id = "o2" // what Reconnect sets
	data = built.ui_data(tester)
	check("connected to the Oxygen tank, it drives it", data["sensor"] && data["input"])
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(3, 3)
	var/turf/far_turf = locate(R.bottom_left_coords[1] + 1, R.bottom_left_coords[2] + 1, R.bottom_left_coords[3])
	var/obj/machinery/computer/atmos_control/tank/lonely = new(far_turf)
	lonely.reconnect(tester)
	data = lonely.ui_data(tester)
	check("Reconnect with no sensors on the z level is harmless", isnull(data["chamber"]))

	// the monitoring console shows a chamber of a player's own
	var/obj/machinery/air_sensor/bz = new(outside, "gas_bz")
	var/obj/machinery/computer/atmos_control/monitor
	for(var/obj/machinery/computer/atmos_control/candidate in GLOB.atmos_air_controllers)
		if(!istype(candidate, /obj/machinery/computer/atmos_control/tank) && candidate.z == bz.z)
			monitor = candidate
			break
	if(monitor)
		var/found = FALSE
		for(var/list/row in monitor.ui_data(tester)["chambers"])
			if(row["id"] == "gas_bz" && row["present"])
				found = TRUE
		check("the monitoring console lists a new chamber", found)
	qdel(bz)
	qdel(built)
	qdel(lonely)
