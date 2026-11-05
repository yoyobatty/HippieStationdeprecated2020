// TTV bench: what a tank transfer valve comes to on this server's atmos, for a list of mixes, with no bot involved. Each mix is
// built in a real valve out in empty space, the valve is opened, and the size the explosion would have been is read back the
// way the doppler array reads it. The Toxins goal (goals/toxins.dm) mixes the best of what a stock lab can make.
//
// Run it:  tools/bot_gym/run_ttv_bench.sh

/datum/ttv_bench
	var/last_light
	var/last_heavy
	var/last_dev

/datum/ttv_bench/New()
	. = ..()
	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(sense))

/datum/ttv_bench/proc/sense(datum/source, turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
	last_light = orig_light_range
	last_heavy = orig_heavy_range
	last_dev = orig_dev_range

/// Sets a tank's contents to `kpa` at `kelvin`, of the gases and shares given.
/datum/ttv_bench/proc/fill(obj/item/tank/T, list/shares, kelvin, kpa)
	var/datum/gas_mixture/air = T.air_contents
	for(var/gas in air.moles.Copy())
		air.moles[gas] = 0
	air.temperature = kelvin
	var/total = kpa * air.volume / (R_IDEAL_GAS_EQUATION * kelvin)
	var/sum = 0
	for(var/gas in shares)
		sum += shares[gas]
	for(var/gas in shares)
		air.moles[gas] = total * shares[gas] / sum

/datum/ttv_bench/proc/fire(label, list/gases_one, kelvin_one, kpa_one, list/gases_two, kelvin_two, kpa_two)
	var/turf/spot = locate(12, 12, SSmapping.station_start)
	var/obj/item/transfer_valve/valve = new(spot)
	var/obj/item/tank/internals/plasma/one = new(valve)
	var/obj/item/tank/internals/oxygen/two = new(valve)
	fill(one, gases_one, kelvin_one, kpa_one)
	fill(two, gases_two, kelvin_two, kpa_two)
	valve.tank_one = one
	valve.tank_two = two
	last_light = null
	valve.toggle_valve()
	var/started = world.time
	while(!QDELETED(valve) && world.time < started + 90 SECONDS)
		sleep(2)
	var/took = (world.time - started) / 10
	if(isnull(last_light))
		log_world("TTV BENCH: [label] - no explosion in [took] s ([valve.tank_two?.air_contents ? "[round(valve.tank_two.air_contents.return_pressure())] kPa, [round(valve.tank_two.air_contents.temperature)] K" : "gone"])")
		if(!QDELETED(valve))
			qdel(valve)
		return
	var/points = last_light < 10 ? 0 : round(83300 * last_light / (last_light + 3000))
	log_world("TTV BENCH: [label] - light radius [last_light] (heavy [last_heavy], dev [last_dev]) after [took] s: [points] points")
	sleep(10)

/// What's plumbed to each heater and freezer in the lab, for working out where a pump can reach the hot gas.
/proc/ttv_bench_plumbing()
	// Which ports share a pipe, in the lab, and what's between them: what a burn can be plumbed from.
	for(var/obj/machinery/atmospherics/components/trinary/mixer/M in GLOB.machines)
		var/area/A = get_area(M)
		if(!istype(A, /area/science))
			continue
		var/list/sides = list()
		for(var/i in 1 to 3)
			var/datum/pipeline/P = M.parents[i]
			var/list/ports = list()
			for(var/obj/machinery/atmospherics/components/unary/portables_connector/C in M.nodes[i] ? list(M.nodes[i]) : list())
				ports += "[C.x],[C.y]"
			if(P)
				for(var/obj/machinery/atmospherics/components/unary/portables_connector/C in P.other_atmosmch)
					ports |= "[C.x],[C.y]"
			sides += "node[i]: [english_list(ports, "none")]"
		log_world("TTV BENCH: mixer at [M.x],[M.y] dir [M.dir] flipped [M.flipped]: [jointext(sides, "; ")]")
	var/list/lab_ports = list()
	for(var/obj/machinery/atmospherics/components/unary/portables_connector/C in GLOB.machines)
		if(istype(get_area(C), /area/science))
			lab_ports += "[C.x],[C.y] ([get_area_name(C, TRUE)])"
	log_world("TTV BENCH: ports: [english_list(lab_ports, "none")]")
	var/list/gear = list()
	for(var/obj/machinery/portable_atmospherics/P in GLOB.machines)
		if(istype(get_area(P), /area/science))
			gear += "[P.name] [P.x],[P.y]"
	log_world("TTV BENCH: portable: [english_list(gear, "none")]")
	for(var/obj/machinery/mass_driver/D in GLOB.machines)
		if(istype(get_area(D), /area/science))
			log_world("TTV BENCH: driver [D.id] at [D.x],[D.y] dir [D.dir]")
	for(var/obj/machinery/doppler_array/D in GLOB.machines)
		log_world("TTV BENCH: doppler at [D.x],[D.y] dir [D.dir] in [get_area_name(D, TRUE)]")
	for(var/obj/machinery/atmospherics/components/unary/thermomachine/M in GLOB.machines)
		var/area/A = get_area(M)
		if(!istype(A, /area/science))
			continue
		var/list/ports = list()
		var/datum/pipeline/P = M.parents[1]
		for(var/obj/machinery/atmospherics/components/unary/portables_connector/C in M.nodes)
			ports += "[C.x],[C.y]"
		if(P)
			for(var/obj/machinery/atmospherics/components/unary/portables_connector/C in P.other_atmosmch)
				ports += "[C.x],[C.y]"
		log_world("TTV BENCH: [M] at [M.x],[M.y] in [A]: max [M.max_temperature] min [M.min_temperature] on [M.on], ports [english_list(ports, "none")]")

/// The user's route on the station's own burn chamber, no bot: plasma then oxygen in through the inlet port (2 to 1), lit from the
/// ignition button's igniters, the scrubber switched to plasma at the pull heat, a portable pump on the output port filling an emptied
/// tank, and that tank on a valve against cold oxygen. BENCH=chamber_burn; PULL_K= sets the heat it's pulled at.
/datum/ttv_bench/proc/chamber_burn()
	var/obj/machinery/atmospherics/components/unary/outlet_injector/injector
	var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber
	for(var/obj/machinery/atmospherics/components/unary/U in GLOB.machines)
		if(istype(get_area(U), /area/science/mixing/chamber))
			if(istype(U, /obj/machinery/atmospherics/components/unary/outlet_injector))
				injector = U
			else if(istype(U, /obj/machinery/atmospherics/components/unary/vent_scrubber))
				scrubber = U
	if(!injector || !scrubber)
		log_world("TTV BENCH: no chamber here")
		return
	var/obj/machinery/atmospherics/components/unary/portables_connector/inlet = ttv_bench_port_behind(injector)
	var/obj/machinery/atmospherics/components/unary/portables_connector/outlet = ttv_bench_port_behind(scrubber)
	log_world("TTV BENCH: chamber inlet port [inlet?.x],[inlet?.y], outlet port [outlet?.x],[outlet?.y]")
	if(!inlet || !outlet)
		return
	// The scrubber off while it burns: on CO2, as it's mapped, it fills the output line with what's burned
	scrubber.on = FALSE
	var/turf/open/inside = get_turf(injector)
	var/pull_k = text2num(world.params["pull-k"]) || 3000
	var/plasma_kpa = text2num(world.params["plasma-kpa"]) || 150
	// Plasma, then oxygen to half again, the inlet valve shut on each before its canister comes off: what's in the line behind it
	// would go on in after
	for(var/list/fill in list(list(/obj/machinery/portable_atmospherics/canister/toxins, plasma_kpa), list(/obj/machinery/portable_atmospherics/canister/oxygen, plasma_kpa * 1.5)))
		var/path = fill[1]
		var/obj/machinery/portable_atmospherics/canister/C = new path(get_turf(inlet))
		C.connect(inlet)
		ttv_bench_open_line(injector)
		var/started = world.time
		while(inside.return_air().return_pressure() < fill[2] && world.time < started + 3 MINUTES && C.air_contents.return_pressure() > 5)
			sleep(2)
		ttv_bench_shut_line(injector)
		C.disconnect()
		sleep(30)
		log_world("TTV BENCH: chamber at [round(inside.return_air().return_pressure())] kPa after [C.name] ([round((world.time - started) / 10)] s), [round(100 * inside.return_air().moles[/datum/gas/plasma] / max(inside.return_air().total_moles(), 0.001))]% plasma")
		qdel(C)
	// Lit
	for(var/obj/machinery/button/ignition/B in GLOB.machines)
		if(istype(get_area(B), /area/science) && findtext(B.id, "toxmix"))
			var/obj/item/assembly/control/igniter/I = B.device
			if(hascall(B, "setup_device")) // a button's control only takes the button's id on its first press (attack_hand)
				call(B, "setup_device")()
			I.activate()
			log_world("TTV BENCH: pressed [B.id]")
			break
	sleep(30)
	for(var/obj/machinery/igniter/G in GLOB.machines)
		if(istype(get_area(G), /area/science/mixing/chamber))
			var/turf/open/T = get_turf(G)
			var/datum/gas_mixture/here = T.return_air()
			log_world("TTV BENCH: igniter [G.id] on [G.on] nopower [!!(G.stat & NOPOWER)], hotspot [!!T.active_hotspot], its tile [round(here.temperature)] K plasma [round(here.moles[/datum/gas/plasma], 0.1)] oxygen [round(here.moles[/datum/gas/oxygen], 0.1)] mol")
	var/started = world.time
	var/next_note = 0
	var/datum/gas_mixture/air = inside.return_air()
	while(air.temperature < pull_k && world.time < started + 6 MINUTES)
		if(world.time >= next_note)
			next_note = world.time + 10 SECONDS
			log_world("TTV BENCH: chamber [round((world.time - started) / 10)] s: [round(air.temperature)] K, [round(air.return_pressure())] kPa, [round(100 * air.moles[/datum/gas/plasma] / max(air.total_moles(), 0.001))]% plasma")
		sleep(5)
		air = inside.return_air()
	log_world("TTV BENCH: chamber pulled at [round(air.temperature)] K after [round((world.time - started) / 10)] s, [round(air.return_pressure())] kPa, [round(100 * air.moles[/datum/gas/plasma] / max(air.total_moles(), 0.001))]% plasma")
	// The scrubber on plasma only, the pump on the output port with an emptied tank, filling it
	scrubber.filter_types = list(/datum/gas/plasma)
	scrubber.scrubbing = TRUE
	scrubber.on = TRUE
	ttv_bench_open_line(scrubber)
	var/obj/machinery/portable_atmospherics/pump/P = new(get_turf(outlet))
	var/obj/item/tank/internals/plasma/hot = new(P)
	hot.air_contents.moles[/datum/gas/plasma] = 0
	P.holding = hot
	P.connect(outlet)
	P.direction = "in"
	P.pump.target_pressure = ONE_ATMOSPHERE * 25
	P.on = TRUE
	started = world.time
	while(hot.air_contents.return_pressure() < 2450 && world.time < started + 4 MINUTES)
		sleep(5)
	var/datum/gas_mixture/tank_air = hot.air_contents
	log_world("TTV BENCH: hot tank [round(tank_air.return_pressure())] kPa at [round(tank_air.temperature)] K, [round(100 * tank_air.moles[/datum/gas/plasma] / max(tank_air.total_moles(), 0.001))]% plasma, after [round((world.time - started) / 10)] s")
	var/list/shares = list()
	for(var/gas in tank_air.moles)
		if(tank_air.moles[gas] > 0)
			shares[gas] = tank_air.moles[gas]
	fire("the real chamber, pulled at [pull_k] K: [round(tank_air.return_pressure())] kPa at [round(tank_air.temperature)] K, oxygen 1013 kPa at 73 K", shares, tank_air.temperature, tank_air.return_pressure(), list(/datum/gas/oxygen = 1), 73, 1013)

/// The port at the far end of a chamber device's line, past its pump and valve
/proc/ttv_bench_port_behind(obj/machinery/atmospherics/components/unary/U)
	var/list/frontier = list(U)
	var/list/seen = list()
	while(length(frontier))
		var/obj/machinery/atmospherics/components/A = frontier[1]
		frontier.Cut(1, 2)
		if(A in seen)
			continue
		seen += A
		for(var/datum/pipeline/P in A.parents)
			for(var/obj/machinery/atmospherics/components/C in P.other_atmosmch)
				if(istype(C, /obj/machinery/atmospherics/components/unary/portables_connector))
					return C
				if(istype(C, /obj/machinery/atmospherics/components/binary))
					frontier += C
	return null

/// The manual valve on a chamber device's line opened, and its pump set to all it'll do, as anybody working the chamber would
/proc/ttv_bench_open_line(obj/machinery/atmospherics/components/unary/U)
	for(var/datum/pipeline/P in U.parents)
		for(var/obj/machinery/atmospherics/components/binary/pump/G in P.other_atmosmch)
			G.target_pressure = MAX_OUTPUT_PRESSURE
			G.on = TRUE
			for(var/datum/pipeline/Q in G.parents)
				for(var/obj/machinery/atmospherics/components/binary/valve/V in Q.other_atmosmch)
					if(!V.on)
						V.toggle()

/// And shut again: the manual valve closed
/proc/ttv_bench_shut_line(obj/machinery/atmospherics/components/unary/U)
	for(var/datum/pipeline/P in U.parents)
		for(var/obj/machinery/atmospherics/components/binary/pump/G in P.other_atmosmch)
			for(var/datum/pipeline/Q in G.parents)
				for(var/obj/machinery/atmospherics/components/binary/valve/V in Q.other_atmosmch)
					if(V.on)
						V.toggle()

/// The burn chamber's devices and where their pipes lead, a few machines out: for the user's chamber route (2026-11-05)
/proc/ttv_bench_chamber_plumbing()
	var/list/seen = list()
	for(var/obj/machinery/M in GLOB.machines)
		if(!istype(get_area(M), /area/science/mixing/chamber))
			continue
		var/extra = ""
		if(istype(M, /obj/machinery/igniter))
			var/obj/machinery/igniter/I = M
			extra = " id [I.id]"
		else if(istype(M, /obj/machinery/air_sensor))
			var/obj/machinery/air_sensor/S = M
			extra = " id [S.id_tag]"
		else if(istype(M, /obj/machinery/atmospherics/components/unary/outlet_injector))
			var/obj/machinery/atmospherics/components/unary/outlet_injector/J = M
			extra = " id [J.id] on [J.on] rate [J.volume_rate]"
		else if(istype(M, /obj/machinery/atmospherics/components/unary/vent_pump))
			var/obj/machinery/atmospherics/components/unary/vent_pump/V = M
			extra = " id [V.id_tag] on [V.on] dir [V.pump_direction ? "out" : "siphon"] bound [V.pressure_checks]"
		else if(istype(M, /obj/machinery/atmospherics/components/unary/vent_scrubber))
			var/obj/machinery/atmospherics/components/unary/vent_scrubber/S = M
			var/list/gases = list()
			for(var/gas in S.filter_types)
				var/datum/gas/G = gas
				gases += initial(G.id)
			extra = " id [S.id_tag] on [S.on] scrubbing [S.scrubbing] widenet [S.widenet] rate [S.volume_rate] filters [english_list(gases, "none")]"
		else if(istype(M, /obj/machinery/atmospherics/components/binary/pump))
			var/obj/machinery/atmospherics/components/binary/pump/P = M
			extra = " on [P.on] target [P.target_pressure] kPa"
		else if(istype(M, /obj/machinery/airalarm))
			var/obj/machinery/airalarm/AA = M
			extra = " locked [AA.locked] access [english_list(AA.req_access, "none")] / one of [english_list(AA.req_one_access, "none")]"
		log_world("TTV BENCH: chamber [M.type] at [M.x],[M.y][extra]")
		if(istype(M, /obj/machinery/atmospherics/components))
			ttv_bench_walk(M, 0, seen)
	for(var/obj/machinery/button/ignition/B in GLOB.machines)
		if(istype(get_area(B), /area/science))
			log_world("TTV BENCH: ignition button [B.id] at [B.x],[B.y] in [get_area_name(B, TRUE)]")
	for(var/obj/machinery/computer/atmos_control/C in GLOB.machines)
		if(istype(get_area(C), /area/science))
			log_world("TTV BENCH: [C.type] '[C.name]' at [C.x],[C.y]")
	for(var/obj/machinery/airalarm/AA in GLOB.machines)
		if(istype(get_area(AA), /area/science/mixing))
			log_world("TTV BENCH: air alarm at [AA.x],[AA.y] in [get_area_name(AA, TRUE)]: locked [AA.locked] access [english_list(AA.req_access, "none")] / one of [english_list(AA.req_one_access, "none")]")
	for(var/obj/machinery/portable_atmospherics/P in GLOB.machines)
		if(istype(get_area(P), /area/science/mixing) || istype(get_area(P), /area/science/storage))
			log_world("TTV BENCH: portable [P.name] ([P.type]) at [P.x],[P.y] in [get_area_name(P, TRUE)], [round(P.air_contents.return_pressure())] kPa")
	for(var/obj/structure/tank_dispenser/D in world)
		if(istype(get_area(D), /area/science))
			log_world("TTV BENCH: tank dispenser at [D.x],[D.y] in [get_area_name(D, TRUE)]: [D.plasmatanks] plasma, [D.oxygentanks] oxygen")

/// What's on each pipe a component sits on, and on through any filter, mixer, pump or valve, up to three hops
/proc/ttv_bench_walk(obj/machinery/atmospherics/components/A, depth, list/seen)
	if(depth > 3 || (A in seen))
		return
	seen += A
	for(var/i in 1 to length(A.parents))
		var/datum/pipeline/P = A.parents[i]
		if(!P)
			continue
		var/list/on_it = list()
		for(var/obj/machinery/atmospherics/components/C in P.other_atmosmch)
			if(C == A)
				continue
			var/what = "[replacetext("[C.type]", "/obj/machinery/atmospherics/components/", "")] [C.x],[C.y]"
			if(istype(C, /obj/machinery/atmospherics/components/trinary/filter))
				var/obj/machinery/atmospherics/components/trinary/filter/F = C
				what += " filters [F.filter_type] on [F.on]"
			else if(istype(C, /obj/machinery/atmospherics/components/trinary/mixer))
				var/obj/machinery/atmospherics/components/trinary/mixer/X = C
				what += " mixer on [X.on] [X.node1_concentration]/[X.node2_concentration]"
			else if(istype(C, /obj/machinery/atmospherics/components/binary))
				what += " on [C.vars["on"]]"
			on_it += what
		log_world("TTV BENCH: [repeat_string(depth * 2, " ")][A.name] [A.x],[A.y] pipe [i] ([round(P.air?.return_pressure())] kPa): [english_list(on_it, "nothing else")]")
		for(var/obj/machinery/atmospherics/components/C in P.other_atmosmch)
			if(C != A && !istype(C, /obj/machinery/atmospherics/components/unary))
				ttv_bench_walk(C, depth + 1, seen)

/// The players' guide burns 2 parts plasma to 1 of oxygen and pulls it off at 6000-7000 C, which leaves oxygen in it and it goes on
/// burning. A leaner mix burns all its oxygen and stops by itself, hot, and what's left is mostly plasma.
/datum/ttv_bench/proc/guide_recipe()
	for(var/share in list(20, 30, 40, 60, 100))
		var/datum/gas_mixture/burn = new(2500 * 9)
		burn.temperature = 500
		var/total = 2000 * burn.volume / (R_IDEAL_GAS_EQUATION * burn.temperature)
		burn.moles[/datum/gas/plasma] = total * share / (share + 1)
		burn.moles[/datum/gas/oxygen] = total / (share + 1)
		for(var/i in 1 to 600)
			burn.react()
		var/list/left = list()
		var/sum = 0
		for(var/gas in burn.moles)
			if(burn.moles[gas] > 0.01)
				left[gas] = burn.moles[gas]
				sum += burn.moles[gas]
		var/list/names = list()
		for(var/gas in left)
			var/datum/gas/G = gas
			names += "[initial(G.name)] [round(100 * left[gas] / sum)]%"
		log_world("TTV BENCH: [share] to 1 burned out at [round(burn.temperature)] K, [round(burn.return_pressure())] kPa: [english_list(names)]")
		for(var/hot_kpa in list(1013, 2500))
			fire("[share] to 1 burn, [hot_kpa] kPa at [round(burn.temperature)] K, oxygen 1100 kPa at 73 K", left, burn.temperature, hot_kpa, list(/datum/gas/oxygen = 1), 73, 1100)

/// The user's way (2026-11-05): 2 plasma to 1 oxygen burnt in the chamber to about 30,000 K, the plasma filtered off into an emptied
/// canister, a tank emptied and filled from that; an oxygen tank filled from a canister on the freezer, "the colder the better".
/// Filtering is what the guide recipe above lacks: what burns out is mostly CO2, and the filter leaves only the plasma.
/datum/ttv_bench/proc/chamber_recipe()
	// How the chamber's 2:1 gets on, and what's still plasma at each heat
	var/datum/gas_mixture/burn = new(2500 * 9)
	burn.temperature = 500
	var/total = 4500 * burn.volume / (R_IDEAL_GAS_EQUATION * burn.temperature)
	burn.moles[/datum/gas/plasma] = total * 2 / 3
	burn.moles[/datum/gas/oxygen] = total / 3
	var/list/marks = list(3000, 10000, 30000, 60000)
	for(var/i in 1 to 2000)
		burn.react()
		if(length(marks) && burn.temperature >= marks[1])
			log_world("TTV BENCH: chamber 2:1 reached [marks[1]] K after [i] reactions, [round(burn.return_pressure())] kPa, [round(100 * burn.moles[/datum/gas/plasma] / burn.total_moles())]% plasma, [round(burn.moles[/datum/gas/plasma])] mol of it")
			marks.Cut(1, 2)
	log_world("TTV BENCH: chamber 2:1 ended at [round(burn.temperature)] K, [round(100 * burn.moles[/datum/gas/plasma] / max(burn.total_moles(), 0.001))]% plasma")
	var/plasma = list(/datum/gas/plasma = 1)
	var/oxygen = list(/datum/gas/oxygen = 1)
	// A full oxygen canister (4,559 kPa at 293 K) on the freezer: what a tank gets from it, which stops at 1,013 kPa
	for(var/cold_k in list(73, 43, 13, 3))
		var/canister_kpa = 4559 * cold_k / 293
		var/tank_kpa = min(1013, canister_kpa)
		for(var/hot_k in list(3000, 10000, 30000))
			for(var/hot_kpa in list(1013, 2533))
				fire("filtered plasma [hot_kpa] kPa at [hot_k] K, oxygen from the canister [round(tank_kpa)] kPa at [cold_k] K", plasma, hot_k, hot_kpa, oxygen, cold_k, tank_kpa)
		// The same oxygen pumped into the tank by a portable pump, which goes to 2,533
		fire("filtered plasma 2533 kPa at 30000 K, oxygen pumped 2533 kPa at [cold_k] K", plasma, 30000, 2533, oxygen, cold_k, 2533)

/proc/run_ttv_bench()
	ttv_bench_plumbing()
	if(world.params["ttv-bench"] == "plumbing")
		log_world("TTV BENCH: done")
		return
	var/datum/ttv_bench/bench = new
	if(world.params["ttv-bench"] == "chamber_plumbing")
		ttv_bench_chamber_plumbing()
		log_world("TTV BENCH: done")
		return
	if(world.params["ttv-bench"] == "chamber_burn")
		bench.chamber_burn()
		log_world("TTV BENCH: done")
		return
	if(world.params["ttv-bench"] == "chamber")
		bench.chamber_recipe()
		log_world("TTV BENCH: done")
		return
	var/plasma = list(/datum/gas/plasma = 1)
	var/oxygen = list(/datum/gas/oxygen = 1)
	bench.guide_recipe()
	if(world.params["ttv-bench"] == "guide")
		log_world("TTV BENCH: done")
		return
	// Hot plasma on cold oxygen: the heater's limit for each tier of laser, and what the freezer gets down to.
	for(var/hot_k in list(573, 853, 1133, 1413))
		for(var/cold_k in list(73, 58, 43))
			for(var/plasma_kpa in list(1500, 2500))
				bench.fire("plasma [plasma_kpa] kPa at [hot_k] K, oxygen 2500 kPa at [cold_k] K", plasma, hot_k, plasma_kpa, oxygen, cold_k, 2500)
	// Mixed in the hot tank: a little oxygen with the plasma, which burns in the tank while it waits.
	for(var/hot_k in list(573, 853))
		for(var/share in list(0.97, 0.9))
			bench.fire("plasma [share * 100]% with oxygen, 2500 kPa at [hot_k] K, oxygen 2500 kPa at 73 K", list(/datum/gas/plasma = share, /datum/gas/oxygen = 1 - share), hot_k, 2500, oxygen, 73, 2500)
	// Super-saturated: more than 96 oxygen to the plasma makes tritium as it burns, and tritium goes up all at once.
	for(var/hot_k in list(573, 853, 1133))
		for(var/share in list(0.5, 2, 5))
			var/kpa = 2500 * share / 100
			bench.fire("oxygen hot tank at [hot_k] K, 2500 kPa, plasma [kpa] kPa at 293 K", plasma, 293, kpa, oxygen, hot_k, 2500)
	log_world("TTV BENCH: done")
