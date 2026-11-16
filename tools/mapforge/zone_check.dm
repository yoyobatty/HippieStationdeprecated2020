// mapforge in-engine check of a built zone. Not part of the game.
// Run through tools/mapforge/run_zone_check.sh, which builds its own dmb and boots the preview map headless.
// World param mapforge-zone=x1,y1,x2,y2 (z = station). Starts the round, waits for air to settle, then reports
// per area: APC and mains, lights, vents/scrubbers on a pipenet, open pipe ends, air pressure and temperature,
// disposal bins on a trunk, and the powernet each APC sits on.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/mf_log(text)
	text2file(text, "data/update_check.txt")

/world/New()
	. = ..()
	spawn(0)
		mf_run()

/proc/mf_zone_turfs()
	var/list/c = splittext(world.params["mapforge-zone"] || "0,0,0,0", ",")
	var/z = SSmapping.station_start
	return block(locate(text2num(c[1]), text2num(c[2]), z), locate(text2num(c[3]), text2num(c[4]), z))

/proc/mf_report(label)
	var/list/turfs = mf_zone_turfs()
	var/list/areas = list()
	for(var/turf/T in turfs)
		areas[T.loc] = TRUE
	var/open_ends = 0
	var/list/open_where = list()
	var/vents = 0
	var/vents_dead = 0
	var/list/dead_where = list()
	var/bins = 0
	var/bins_bad = 0
	for(var/turf/T in turfs)
		for(var/obj/machinery/atmospherics/A in T)
			for(var/i in 1 to A.device_type)
				if(!A.nodes[i])
					open_ends++
					if(length(open_where) < 10)
						open_where += "[A.x],[A.y] [A.type]"
			if(istype(A, /obj/machinery/atmospherics/components/unary/vent_pump) || istype(A, /obj/machinery/atmospherics/components/unary/vent_scrubber))
				vents++
				var/obj/machinery/atmospherics/components/unary/U = A
				var/datum/pipeline/P = U.parents[1]
				if(!P || length(P.members) < 3)
					vents_dead++
					if(length(dead_where) < 10)
						dead_where += "[A.x],[A.y]"
		for(var/obj/machinery/disposal/bin/B in T)
			bins++
			if(!B.trunk)
				bins_bad++
	for(var/turf/T in turfs)
		for(var/obj/machinery/computer/rdconsole/C in T)
			mf_log("[label] R&D console [C.x],[C.y] [C.type]: analyzer [C.linked_destroy ? "linked" : "-"], protolathe [C.linked_lathe ? "linked" : "-"], imprinter [C.linked_imprinter ? "linked" : "-"]")
	for(var/turf/T in turfs)
		for(var/obj/machinery/computer/mech_bay_power_console/C in T)
			mf_log("[label] link: mech bay console [C.x],[C.y] port [C.recharge_port ? "linked" : "MISSING"]")
		for(var/obj/machinery/computer/operating/C in T)
			mf_log("[label] link: operating computer [C.x],[C.y] table [C.table ? "linked" : "MISSING"]")
		for(var/obj/machinery/computer/nanite_chamber_control/C in T)
			mf_log("[label] link: nanite console [C.x],[C.y] chamber [C.chamber ? "linked" : "MISSING"]")
		for(var/obj/machinery/rnd/experimentor/X in T)
			mf_log("[label] link: experimentor [X.x],[X.y] console [X.linked_console ? "linked" : "MISSING"]")
		for(var/obj/machinery/computer/camera_advanced/xenobio/C in T)
			mf_log("[label] link: slime console [C.x],[C.y] recycler [C.connected_recycler ? "linked" : "MISSING"]")
		for(var/obj/machinery/mecha_part_fabricator/F in T)
			var/turf/out = get_step(F, F.dir)
			mf_log("[label] link: exosuit fab [F.x],[F.y] prints onto [out.x],[out.y] [(locate(/obj/machinery/conveyor) in out) ? "(a conveyor)" : ""]")
	mf_log("[label] pipes: [open_ends] open ends [jointext(open_where, " | ")]; [vents] vents+scrubbers, [vents_dead] not on a network [jointext(dead_where, " ")]; [bins] disposal bins, [bins_bad] without a trunk")
	for(var/area/A in areas)
		if(istype(A, /area/space) || istype(A, /area/maintenance))
			continue
		var/obj/machinery/power/apc/apc = A.get_apc()
		var/lights = 0
		var/lights_on = 0
		var/floors = 0
		var/low = 0
		var/high = 0
		var/tmin = 1e9
		var/tmax = 0
		for(var/turf/T in turfs)
			if(T.loc != A)
				continue
			for(var/obj/machinery/light/L in T)
				lights++
				if(L.on)
					lights_on++
			if(isopenturf(T) && !isspaceturf(T))
				var/datum/gas_mixture/G = T.return_air()
				if(G)
					floors++
					var/p = G.return_pressure()
					if(p < 90)
						low++
					if(p > 115)
						high++
					tmin = min(tmin, G.temperature)
					tmax = max(tmax, G.temperature)
		var/net = "none"
		if(apc?.terminal?.powernet)
			var/datum/powernet/PN = apc.terminal.powernet
			var/smes = 0
			for(var/obj/machinery/power/smes/S in PN.nodes)
				smes++
			net = "[length(PN.nodes)] nodes, [smes] SMES, avail [round(PN.avail)]"
		mf_log("[label] [A.name]: APC [apc ? "[apc.x],[apc.y] mains [apc.main_status] cell [apc.cell ? round(apc.cell.percent()) : -1]% equip [apc.equipment] light [apc.lighting] env [apc.environ]" : "NONE"]; powernet [net]; lights [lights_on]/[lights]; air [floors] tiles, [low] under 90 kPa, [high] over 115, [round(tmin - T0C)]..[round(tmax - T0C)] C")

/proc/mf_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	CONFIG_SET(flag/allow_random_events, FALSE)
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	mf_log("map [SSmapping.config.map_name] [SSmapping.config.map_file], round state [SSticker.current_state]")
	sleep(10 SECONDS)
	mf_report("start")
	sleep(text2num(world.params["mapforge-wait"] || "90") SECONDS)
	mf_report("later")
	// the real lighting, for the renderer to shade pictures with (lighting_bench.dm's snapshot: each lit tile's corners)
	var/lname = world.params["mapforge-name"]
	if(lname)
		lighting_bench_snapshot(SSmapping.station_start, "data/mapforge/light_[lname].txt")
		mf_log("lighting snapshot data/mapforge/light_[lname].txt")
	mf_log("done")
