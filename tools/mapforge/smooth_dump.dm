// mapforge side build: dumps what the renderer needs to smooth like the game does, then quits without booting.
// Run by tools/mapforge/smooth_dump.sh. Output: data/mapforge/smoothing.txt
// atom lines:    A <TAB> path <TAB> smoothing_flags <TAB> base_icon_state <TAB> smoothing_groups <TAB> canSmoothWith <TAB> anchored <TAB> can_be_unanchored
// area lines:    R <TAB> path <TAB> area_limited_icon_smoothing
// spawner lines: S <TAB> path <TAB> spawned types, comma separated

/world/New()
	var/out = "data/mapforge/smoothing.txt"
	fdel(out)
	var/list/lines = list()
	for(var/path in typesof(/atom))
		var/atom/A = path
		if(!initial(A.smoothing_flags))
			continue
		var/anch = 1
		var/unanch = 0
		if(ispath(path, /atom/movable))
			var/atom/movable/M = path
			anch = initial(M.anchored)
			unanch = initial(M.can_be_unanchored)
		if(ispath(path, /obj))
			// some swap to a smoothing sheet in Initialize() (fancy tables: smooth_icon)
			var/obj/O = new path(null)
			if("smooth_icon" in O.vars)
				lines += "I\t[path]\t[O.vars["smooth_icon"]]"
			del(O)
		lines +="A\t[path]\t[initial(A.smoothing_flags)]\t[initial(A.base_icon_state)]\t[initial(A.smoothing_groups)]\t[initial(A.canSmoothWith)]\t[anch]\t[unanch]"
	// dense objects (what blocks walking), for mapforge's checks
	for(var/path in typesof(/obj/structure, /obj/machinery))
		var/obj/O = path
		if(initial(O.density))
			lines += "D\t[path]"
	for(var/path in typesof(/area))
		var/area/R = path
		if(initial(R.area_limited_icon_smoothing))
			lines += "R\t[path]\t[initial(R.area_limited_icon_smoothing)]"
	for(var/path in typesof(/obj/effect/spawner/structure))
		var/obj/effect/spawner/structure/S = new path(null)
		var/list/L = list()
		for(var/T in S.spawn_list)
			L += "[T]"
		lines += "S\t[path]\t[L.Join(",")]"
	text2file(lines.Join("\n"), out)
	shutdown()
