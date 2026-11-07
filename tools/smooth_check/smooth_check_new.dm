// Checks the bitmask smoothing against the old corner smoothing's own rules. Not part of the game: tools/smooth_check/run.sh
// Needs data/smooth_check/old_rules.txt and old_areas.txt from smooth_dump_old.dm (built from the code before the port).
// 1. Type pairs: for every rule the old code ran with and every atom type, "smooths with it" is the same under the old
//    typepath lists and the new smoothing groups.
// 2. Every smoothing atom on every z-level: the junction it shows is the one it would get if smoothed now (nothing stale),
//    equals what the old rules give on the live map, and its icon_state exists in its icon.
// 3. A getFlatIcon() of one atom of each type and junction into data/smooth_check/new_flat/, compared with the old ones
//    by tools/smooth_check/compare.py.

#include "tools\smooth_check\stale_scenario.dm"

/proc/smooth_shown(atom/A)
	return sc_shown(A)

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/world/New()
	. = ..()
	spawn(0)
		smooth_check_run()

GLOBAL_LIST_EMPTY(sc_rules) // type -> list(flags, list of types or null)
GLOBAL_LIST_EMPTY(sc_area_limits) // area type -> list of area types

/proc/sc_write(name, list/lines)
	fdel("data/smooth_check/[name].txt")
	text2file(lines.Join("\n"), "data/smooth_check/[name].txt")

/proc/sc_load_rules()
	var/rules_name = world.params["rules"] || "expected_rules" // the old rules with the joining fixes; rules=old_rules for the old ones as they were
	for(var/line in splittext(file2text("data/smooth_check/[rules_name].txt"), "\n"))
		var/list/parts = splittext(line, " | ")
		if(length(parts) < 3)
			continue
		var/type = text2path(parts[1])
		if(!type)
			continue
		var/list/csw = null
		if(parts[3] != "null")
			csw = list()
			for(var/t in splittext(parts[3], ","))
				var/p = text2path(t)
				if(p)
					csw += p
		GLOB.sc_rules[type] = list(text2num(parts[2]), csw)
	for(var/line in splittext(file2text("data/smooth_check/old_areas.txt"), "\n"))
		var/list/parts = splittext(line, " | ")
		if(length(parts) < 2)
			continue
		var/list/limits = list()
		for(var/t in splittext(parts[2], ","))
			limits += text2path(t)
		GLOB.sc_area_limits[text2path(parts[1])] = limits

/// Old: does a rule (flags, typepaths) match atom type B
/proc/sc_old_type_match(atype, list/rule, btype)
	var/list/csw = rule[2]
	if(!csw)
		return btype == atype
	if(rule[1] & 2) // SMOOTH_MORE
		for(var/t in csw)
			if(ispath(btype, t))
				return TRUE
		return FALSE
	return (btype in csw)

/// New: do these parsed canSmoothWith and smoothing_groups lists share a group
/proc/sc_groups_match(list/csw, list/groups)
	if(!csw || !groups)
		return FALSE
	for(var/key in csw)
		if(csw[key] & groups[key])
			return TRUE
	return FALSE

/proc/sc_parse(text)
	if(!text)
		return null
	if(islist(text))
		return text
	var/list/out
	SET_SMOOTHING_GROUPS(text, out)
	return out

/// Old rules on the live map, as a tg junction (diagonal pieces get a D in front)
/proc/sc_old_junction(atom/A)
	var/list/rule = GLOB.sc_rules[A.type]
	if(!rule)
		return "norule"
	if(ismovable(A))
		var/atom/movable/M = A
		if(M.can_be_unanchored && !M.anchored)
			return 0
	var/j = 0
	var/static/list/card = list(NORTH, SOUTH, EAST, WEST)
	for(var/d in card)
		var/r = sc_old_find(A, d, rule)
		if(r)
			j |= d
	var/static/list/diag_dirs = list(NORTHEAST, SOUTHEAST, SOUTHWEST, NORTHWEST)
	var/static/list/diag_bits = list(16, 32, 64, 128)
	for(var/i in 1 to 4)
		var/d = diag_dirs[i]
		if((j & d) == d && sc_old_find(A, d, rule))
			j |= diag_bits[i]
	if((rule[1] & 4) && (j in list(9, 5, 10, 6, 137, 21, 74, 38))) // SMOOTH_DIAGONAL
		return "D[j]"
	return j

/proc/sc_old_find(atom/A, direction, list/rule)
	var/turf/T = get_step(A, direction)
	if(!T)
		return (rule[1] & 8) // SMOOTH_BORDER
	var/area/ta = T.loc
	var/area/sa = get_area(A)
	var/list/lim = GLOB.sc_area_limits[sa.type]
	if(lim && !is_type_in_list(ta, lim))
		return FALSE
	lim = GLOB.sc_area_limits[ta.type]
	if(lim && !is_type_in_list(sa, lim))
		return FALSE
	if(sc_old_type_match(A.type, rule, T.type))
		return TRUE
	for(var/atom/movable/AM as anything in T)
		if(AM.anchored && sc_old_type_match(A.type, rule, AM.type))
			return TRUE
	return FALSE

/proc/sc_shown(atom/A)
	var/state = A.icon_state
	var/base = A.base_icon_state
	if(!base || copytext(state, 1, length(base) + 2) != "[base]-")
		return "state:[state]"
	var/rest = copytext(state, length(base) + 2)
	if(findtext(rest, "-diagonal"))
		return "D[text2num(copytext(rest, 1, findtext(rest, "-diagonal")))]"
	return text2num(rest)

/proc/smooth_check_run()
	UNTIL(SSicon_smooth.initialized)
	sleep(5 SECONDS)
	UNTIL(!length(SSicon_smooth.smooth_queue))
	if(world.params["scenario"])
		stale_scenario_run()
	var/list/stale_types = list()
	// one of every smoothing type made, as a round would make them (catches Initialize() trouble the map never shows)
	var/cz = SSmapping.levels_by_trait(ZTRAIT_CENTCOM)[1]
	var/turf/scratch = locate(3, 3, cz)
	var/turf/scratch2 = locate(5, 3, cz)
	scratch2 = scratch2.ChangeTurf(/turf/open/floor/plating)
	var/spawned = 0
	for(var/path in typesof(/atom))
		var/atom/proto = path
		if(!(initial(proto.smoothing_flags) & USES_SMOOTHING) && !initial(proto.canSmoothWith))
			continue
		spawned++
		if(ispath(path, /turf))
			scratch = scratch.ChangeTurf(path)
		else if(ispath(path, /atom/movable))
			var/atom/movable/M = new path(scratch2)
			if(!QDELETED(M))
				qdel(M)
		CHECK_TICK
	GLOB.scenario_lines += "spawned one of each of [spawned] smoothing types"
	sleep(1 SECONDS)
	UNTIL(!length(SSicon_smooth.smooth_queue))
	sc_load_rules()
	var/list/report = list()
	// 1. type pairs
	var/list/all_types = typesof(/atom)
	var/pair_bad = 0
	for(var/atype in GLOB.sc_rules)
		var/list/rule = GLOB.sc_rules[atype]
		var/atom/proto = atype
		var/list/csw = sc_parse(initial(proto.canSmoothWith))
		var/list/old_only = list()
		var/list/new_only = list()
		for(var/btype in all_types)
			var/atom/bproto = btype
			var/o = sc_old_type_match(atype, rule, btype)
			var/n = sc_groups_match(csw, sc_parse(initial(bproto.smoothing_groups)))
			if(o && !n)
				old_only += "[btype]"
			else if(n && !o)
				new_only += "[btype]"
		if(length(old_only) || length(new_only))
			pair_bad++
			report += "TYPES [atype]: lost [length(old_only)] [jointext(old_only.Copy(1, min(length(old_only), 8) + 1), " ")] | gained [length(new_only)] [jointext(new_only.Copy(1, min(length(new_only), 8) + 1), " ")]"
		CHECK_TICK
	// 2. every smoothing atom
	var/count = 0
	var/stale = 0
	var/differ = 0
	var/missing = 0
	var/list/icon_cache = list()
	var/list/flat_done = list()
	var/list/flat_lines = list()
	fdel("data/smooth_check/new_flat/")
	for(var/z in 1 to world.maxz)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/list/things = list(T)
			for(var/atom/movable/AM as anything in T)
				if(AM.smoothing_flags & USES_SMOOTHING)
					things += AM
			for(var/atom/A as anything in things)
				if(!(A.smoothing_flags & USES_SMOOTHING))
					continue
				count++
				var/shown = sc_shown(A)
				var/list/states = icon_cache["[A.icon]"]
				if(!states)
					states = list()
					for(var/s in icon_states(A.icon))
						states[s] = TRUE
					icon_cache["[A.icon]"] = states
				if(!states[A.icon_state])
					missing++
					report += "MISSING [A.type] at [A.z] [A.x] [A.y]: [A.icon] has no [A.icon_state]"
				var/old = sc_old_junction(A)
				var/key = "[A.type]|[shown]|[A.icon]|[A.color]"
				if(!flat_done[key] && length(flat_done) < 3000)
					flat_done[key] = TRUE
					var/icon/I = getFlatIcon(A, defdir = SOUTH, no_anim = TRUE)
					if(I)
						var/name = "[length(flat_done)]"
						fcopy(I, "data/smooth_check/new_flat/[name].png")
						flat_lines += "[name] | [A.type] | [shown] | [A.icon] | [A.icon_state] | [A.z] [A.x] [A.y] | [A.color]"
				var/before_state = A.icon_state
				A.smooth_icon()
				var/now = sc_shown(A)
				if("[now]" != "[shown]")
					stale++
					stale_types["[A.type]"]++
					report += "STALE [A.type] at [A.z] [A.x] [A.y]: showed [shown] ([before_state]), now [now]"
				if("[old]" != "[now]")
					differ++
					if(differ <= 400)
						var/area/where = get_area(A)
						report += "DIFFERS [A.type] at [A.z] [A.x] [A.y] ([where.type]): old rules [old], new [now]"
		CHECK_TICK
	sc_write("new_report", report)
	sc_write("new_flat", flat_lines)
	for(var/t in stale_types)
		GLOB.scenario_lines += "stale [t]: [stale_types[t]]"
	sc_write("new_scenario", GLOB.scenario_lines)
	sc_write("new_summary", list("smoothing atoms [count], type rules differing [pair_bad], stale [stale], differ from old rules [differ], missing states [missing], flat icons [length(flat_lines)], maxz [world.maxz], map [SSmapping.config?.map_name]", "done"))
	sleep(5)
	del(world)
