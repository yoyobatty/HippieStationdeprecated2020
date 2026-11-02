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

/proc/run_ttv_bench()
	ttv_bench_plumbing()
	if(world.params["ttv-bench"] == "plumbing")
		log_world("TTV BENCH: done")
		return
	var/datum/ttv_bench/bench = new
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
