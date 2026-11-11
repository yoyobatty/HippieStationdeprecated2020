// What the pipes in Hippie Station's cryo room (Medbay) carry for overlays, and what they're joined to. Not part of the game.
//   MAP=hippiestation tools/smooth_check/run.sh build pipecheck tools/smooth_check/pipe_check.dm && MAP=hippiestation tools/smooth_check/run.sh run pipecheck
// Writes data/smooth_check/pipe_summary.txt.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/world/New()
	. = ..()
	spawn(0)
		pipe_check_run()

/proc/pipe_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	CONFIG_SET(flag/allow_random_events, FALSE)
	SSticker.start_immediately = TRUE //SSair only joins the pipes up once the round starts
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(10 SECONDS)
	var/list/lines = list()
	// Does copying .appearance keep the dir? An image() made with a dir, and a mutable_appearance given one
	var/static/image/bro = new()
	var/image/I = image('icons/obj/atmospherics/pipes/manifold.dmi', "pipe-2", dir = EAST)
	bro.appearance = I
	lines += "image(dir = EAST): its own dir [I.dir], copied appearance's dir [bro.dir]"
	var/mutable_appearance/MA = mutable_appearance('icons/obj/atmospherics/pipes/manifold.dmi', "pipe-2")
	MA.dir = EAST
	bro.appearance = MA
	lines += "mutable_appearance, dir set to EAST: copied appearance's dir [bro.dir]"
	var/image/J = image('icons/obj/atmospherics/pipes/manifold.dmi', "pipe-2")
	J.dir = WEST
	bro.appearance = J
	lines += "image(), dir set to WEST after: copied appearance's dir [bro.dir]"
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	for(var/y in list(114, 113))
		for(var/x in 144 to 147)
			var/turf/T = locate(x, y, z)
			for(var/obj/machinery/atmospherics/pipe/P in T)
				var/list/nodes = list()
				for(var/i in 1 to length(P.nodes))
					var/obj/machinery/atmospherics/N = P.nodes[i]
					nodes += N ? "[dir2text(get_dir(P, N))]" : "-"
				var/list/ovs = list()
				for(var/mutable_appearance/M as anything in P.overlays)
					ovs += "[M.icon_state]:[M.dir]"
				lines += "([x],[y]) [P.type] dir=[P.dir] icon_state='[P.icon_state]' nodes=[nodes.Join(",")] overlays=[ovs.Join(" ")]"
	// The whole station: how many pipes have nothing joined at all, and where
	var/total = 0
	var/loose = 0
	var/list/loose_areas = list()
	for(var/obj/machinery/atmospherics/pipe/P in GLOB.machines)
		if(P.z != z)
			continue
		total++
		var/joined = FALSE
		for(var/N in P.nodes)
			if(N)
				joined = TRUE
				break
		if(!joined)
			loose++
			var/area/A = get_area(P)
			loose_areas["[A?.name]"]++
	lines += "station pipes: [total], with nothing joined: [loose]"
	var/list/top = list()
	for(var/name in loose_areas)
		top += "[name]=[loose_areas[name]]"
	lines += "by area: [top.Join(", ")]"
	lines += "SSair initialized=[SSair.initialized] atmos_machinery=[length(SSair.atmos_machinery)]"
	lines += "done"
	text2file(lines.Join("\n"), "data/smooth_check/pipe_summary.txt")
