// Snapshot of the old corner smoothing, for checking the bitmask port against it. Not part of the game: tools/smooth_check/run.sh
// Writes data/smooth_check/old_*.txt: every smoothing atom (where it is, what it shows, what it would show if smoothed now),
// the canSmoothWith rules each type really runs with, area limits, and a getFlatIcon() of one atom of each type and shape.

#include "tools\smooth_check\stale_scenario.dm"

/proc/smooth_shown(atom/A)
	return sd_shown(A)

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/world/New()
	. = ..()
	spawn(0)
		smooth_dump_run()

/proc/sd_write(name, list/lines)
	fdel("data/smooth_check/[name].txt")
	text2file(lines.Join("\n"), "data/smooth_check/[name].txt")

/// tg junction bits: N 1, S 2, E 4, W 8, NE 16, SE 32, SW 64, NW 128
/proc/sd_old_to_junction(adj)
	. = 0
	if(adj & N_NORTH)
		. |= 1
	if(adj & N_SOUTH)
		. |= 2
	if(adj & N_EAST)
		. |= 4
	if(adj & N_WEST)
		. |= 8
	if(adj & N_NORTHEAST)
		. |= 16
	if(adj & N_SOUTHEAST)
		. |= 32
	if(adj & N_SOUTHWEST)
		. |= 64
	if(adj & N_NORTHWEST)
		. |= 128

/// What the atom shows now, read back from its corner overlays: a junction, "D" in front for a diagonal corner piece
/proc/sd_shown(atom/A)
	var/nw = A.top_left_corner
	var/ne = A.top_right_corner
	if(!nw)
		return "none"
	if(copytext(nw, 1, 3) == "d-")
		var/static/list/diag = list("d-se-0" = 1|8, "d-sw-0" = 1|4, "d-ne-0" = 2|8, "d-nw-0" = 2|4, "d-se-1" = 1|8|128, "d-sw-1" = 1|4|16, "d-ne-1" = 2|8|64, "d-nw-1" = 2|4|32)
		return "D[diag[ne]]"
	var/sw = A.bottom_right_corner // the old code keeps the 3- corner in bottom_right_corner and the 4- in bottom_left_corner
	var/se = A.bottom_left_corner
	. = 0
	var/static/list/bits = list(
		"1-f" = 1|8|128, "1-nw" = 1|8, "1-n" = 1, "1-w" = 8, "1-i" = 0,
		"2-f" = 1|4|16, "2-ne" = 1|4, "2-n" = 1, "2-e" = 4, "2-i" = 0,
		"3-f" = 2|8|64, "3-sw" = 2|8, "3-s" = 2, "3-w" = 8, "3-i" = 0,
		"4-f" = 2|4|32, "4-se" = 2|4, "4-s" = 2, "4-e" = 4, "4-i" = 0)
	. = bits[nw] | bits[ne] | bits[sw] | bits[se]

/// What it would show if smoothed right now
/proc/sd_now(atom/A)
	var/adj = calculate_adjacencies(A)
	var/j = sd_old_to_junction(adj)
	if(A.smooth & SMOOTH_DIAGONAL)
		var/static/list/diagonals = list(1|8, 1|4, 2|8, 2|4, 1|8|128, 1|4|16, 2|8|64, 2|4|32)
		if(j in diagonals)
			return "D[j]"
	return j

/proc/sd_csw(atom/A)
	if(!A.canSmoothWith)
		return "null"
	var/list/out = list()
	for(var/t in A.canSmoothWith)
		out += "[t]"
	return out.Join(",")

/proc/smooth_dump_run()
	UNTIL(SSicon_smooth.initialized)
	sleep(5 SECONDS)
	UNTIL(!length(SSicon_smooth.smooth_queue))
	if(world.params["scenario"])
		stale_scenario_run()
	var/list/stale_types = list()
	var/list/atoms = list("z x y | type | smooth | icon | icon_state | shown | now | anchored | area | underlays")
	var/list/rules = list()
	var/list/flat_done = list()
	var/list/flat_lines = list()
	var/stale = 0
	var/count = 0
	fdel("data/smooth_check/old_flat/")
	for(var/z in 1 to world.maxz)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/list/things = list(T)
			for(var/atom/movable/AM as anything in T)
				if(AM.smooth)
					things += AM
			for(var/atom/A as anything in things)
				if(!A.smooth)
					continue
				count++
				var/shown = sd_shown(A)
				var/now = sd_now(A)
				if("[shown]" != "[now]" && !(shown == "none" && now == 0))
					stale++
					stale_types["[A.type]"]++
					if(stale <= 60)
						GLOB.scenario_lines += "STALE [A.type] at [A.z] [A.x] [A.y]: shows [shown], should be [now]"
				var/anch = ismovable(A) ? "[A:anchored]" : "-"
				var/area/AR = get_area(A)
				atoms += "[A.z] [A.x] [A.y] | [A.type] | [A.smooth & ~SMOOTH_QUEUED] | [A.icon] | [A.icon_state] | [shown] | [now] | [anch] | [AR.type] | [length(A.underlays)]"
				var/rule = "[A.type] | [A.smooth & ~SMOOTH_QUEUED] | [sd_csw(A)]"
				rules[rule] = TRUE
				var/key = "[A.type]|[shown]|[A.icon]|[A.icon_state]|[A.color]"
				if(!flat_done[key] && length(flat_done) < 3000)
					flat_done[key] = TRUE
					var/icon/I = getFlatIcon(A, defdir = SOUTH, no_anim = TRUE)
					if(I)
						var/name = "[length(flat_done)]"
						fcopy(I, "data/smooth_check/old_flat/[name].png")
						flat_lines += "[name] | [A.type] | [shown] | [A.icon] | [A.icon_state] | [A.z] [A.x] [A.y] | [A.color]"
		CHECK_TICK
	// one of every smoothing type, on a scratch tile at CentCom's edge, for the rule it really runs with after Initialize()
	var/list/typerules = list("type | smooth | canSmoothWith | icon | icon_state")
	var/cz = SSmapping.levels_by_trait(ZTRAIT_CENTCOM)[1]
	var/turf/scratch = locate(3, 3, cz)
	var/turf/scratch2 = locate(5, 3, cz)
	scratch2 = scratch2.ChangeTurf(/turf/open/floor/plating)
	for(var/path in typesof(/atom))
		var/atom/proto = path
		if(!initial(proto.smooth))
			continue
		try
			if(ispath(path, /turf))
				var/turf/T = scratch.ChangeTurf(path)
				scratch = T
				typerules += "[path] | [T.smooth & ~SMOOTH_QUEUED] | [sd_csw(T)] | [T.icon] | [T.icon_state]"
			else if(ispath(path, /atom/movable))
				var/atom/movable/M = new path(scratch2)
				typerules += "[path] | [M.smooth & ~SMOOTH_QUEUED] | [sd_csw(M)] | [M.icon] | [M.icon_state]"
				if(!QDELETED(M))
					qdel(M)
		catch(var/exception/e)
			typerules += "[path] | ERROR [e] | | |"
		CHECK_TICK
	sd_write("old_typerules", typerules)
	var/list/types = list()
	for(var/path in typesof(/atom))
		types += "[path]"
	sd_write("old_types", types)
	var/list/areas = list()
	for(var/area/AR in world)
		if(AR.canSmoothWithAreas)
			var/list/names = list()
			for(var/t in AR.canSmoothWithAreas)
				names += "[t]"
			areas += "[AR.type] | [names.Join(",")]"
	sd_write("old_atoms", atoms)
	sd_write("old_rules", rules)
	sd_write("old_areas", areas)
	sd_write("old_flat", flat_lines)
	for(var/t in stale_types)
		GLOB.scenario_lines += "stale [t]: [stale_types[t]]"
	sd_write("old_scenario", GLOB.scenario_lines)
	sd_write("old_summary", list("smoothing atoms [count], stale [stale], rules [length(rules)], flat icons [length(flat_lines)], maxz [world.maxz], map [SSmapping.config?.map_name]", "done"))
	sleep(5)
	del(world)
