// Grief undo self-test (hippiestation/code/modules/admin/grief_undo.dm), headless, in the real engine on the real map.
//
// Run:      tools/grief_check/run_grief_check.sh   (builds its own copy; MAP=hippiestation for the Hippie map)
// Results:  data/grief_check/results.txt, one PASS/FAIL line per check.
//
// Picks real mapped things on the station and griefs them the way players do: a wall dismantled, a floor pulled up to
// space, a window and its grille smashed away, an airlock torn out, another welded, bolted, electrified and its wires
// cut, the APC broken, a cable cut, a pipe and a vent taken out, a bulb broken, plasma let into a room; then a canister
// and a girder left behind. The scan has to find every one; Apply has to put them back, joined to the power and pipe
// networks, without doubling anything, and leave the canister and girder alone (they're only shown); Undo has to take the
// new things away again; and a scan of a player's logged spots has to cover their tiles.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("grief-selftest" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_grief_selftest))
	return ..()

#define GRIEF_CHECK_DIR "data/grief_check/"

/proc/run_grief_selftest()
	sleep(5 SECONDS)
	fdel(GRIEF_CHECK_DIR)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(12 SECONDS) // past roundstart, so what the test leaves counts as made this round (made_in_round)
	var/datum/grief_selftest/test = new
	try
		test.run_all()
	catch(var/exception/e)
		test.check("ran to the end", FALSE, "[e] at [e.file]:[e.line]")
	text2file(jointext(test.lines, "\n"), "[GRIEF_CHECK_DIR]results.txt")
	log_world("GRIEF CHECK: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/grief_selftest
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/datum/stock_map/SM
	/// Tiles already used, so no two griefs share one
	var/list/used = list()

/datum/grief_selftest/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/datum/grief_selftest/proc/note(text)
	lines += "     [text]"

/// A station tile that matches the map now, isn't near one already used, and passes a test
/datum/grief_selftest/proc/clean(turf/T)
	if(!T || T.z < SM.z_low || T.z > SM.z_high)
		return FALSE
	for(var/turf/U as anything in used)
		if(U.z == T.z && abs(U.x - T.x) <= 2 && abs(U.y - T.y) <= 2)
			return FALSE
	var/list/model = SM.model_at(T)
	if(!model)
		return FALSE
	var/datum/grief_undo/G = new
	var/datum/grief_tile/tile = G.compare(T, model, SM)
	qdel(G)
	return !tile

/datum/grief_selftest/proc/use(turf/T)
	used += T
	return T

/datum/grief_selftest/proc/stock_has(turf/T, path)
	var/list/model = SM.model_at(T)
	for(var/p in model[1])
		if(ispath(p, path))
			return TRUE
	return FALSE

/datum/grief_selftest/proc/run_all()
	check("round started", SSticker.current_state >= GAME_STATE_PLAYING, "state [SSticker.current_state]")
	var/began = REALTIMEOFDAY
	SM = stock_map()
	check("map read", length(SM.sets_by_z) > 0, "[(REALTIMEOFDAY - began) / 10] s, levels [SM.z_low]-[SM.z_high], [length(SM.station_areas())] areas")

	// the reader lines up with the world: most station turfs are the map's turf
	var/same = 0
	var/total = 0
	for(var/turf/T in block(locate(1, 1, SM.z_low), locate(world.maxx, world.maxy, SM.z_low)))
		var/list/model = SM.model_at(T)
		if(!model)
			continue
		var/list/members = model[1]
		var/stock = members[members.len - 1]
		total++
		if(T.type == stock || (isspaceturf(T) && ispath(stock, /turf/open/space)))
			same++
	check("map lines up with the world", total && same / total > 0.97, "[same] of [total] turfs are the map's")

	// a scan of the whole station level at roundstart: what's already different (the baseline)
	began = REALTIMEOFDAY
	var/datum/grief_undo/base = new
	var/list/everything = list()
	for(var/turf/T in block(locate(1, 1, SM.z_low), locate(world.maxx, world.maxy, SM.z_low)))
		if(SM.model_at(T) && !isspaceturf(T))
			everything += T
	everything.Cut(min(everything.len, 8000) + 1)
	base.scan(everything, "baseline")
	var/work = 0
	var/list/kinds = list()
	var/list/added = list()
	var/added_count = 0
	for(var/key in base.tiles)
		var/datum/grief_tile/G = base.tiles[key]
		if(G.has_work())
			work++
			for(var/what in G.describe())
				kinds[what]++
		for(var/datum/weakref/W as anything in G.adds)
			var/obj/O = W.resolve()
			if(O)
				added["[O.type]"]++
				added_count++
	check("roundstart scan is quiet", work < everything.len * 0.03, "[work] of [everything.len] tiles flagged at roundstart, [(REALTIMEOFDAY - began) / 10] s")
	check("roundstart shows few added things", added_count < everything.len * 0.02, "[added_count] shown")
	var/shown = 0
	for(var/what in kinds)
		if(shown++ < 12)
			note("roundstart: [what] x[kinds[what]]")
	shown = 0
	for(var/what in added)
		if(shown++ < 12)
			note("roundstart added: [what] x[added[what]]")
	// the first few tiles where a mapped pipe or pump reads as gone: the map's keys next to what's there
	shown = 0
	for(var/key in base.tiles)
		var/datum/grief_tile/G = base.tiles[key]
		var/pipe_gone = FALSE
		for(var/list/M as anything in G.missing)
			if(ispath(M[1], /obj/machinery/atmospherics))
				pipe_gone = TRUE
		if(!pipe_gone || shown++ >= 4)
			continue
		for(var/list/M as anything in G.missing)
			note("[key] map: [M[1]] [json_encode(M[2])] key=[grief_undo_key_of_path(M[1], M[2])]")
		for(var/obj/machinery/atmospherics/A in G.turf())
			note("[key] now: [A.type] dir=[A.dir] layer=[A.piping_layer] key=[grief_undo_key_of(A)]")
	qdel(base)

	grief_and_fix()
	player_scan()

/datum/grief_selftest/proc/grief_and_fix()
	var/list/turf/griefed = list()
	var/list/expect = list() // turf = what the scan should say, part of it

	// a wall dismantled to plating
	var/turf/wall
	var/wall_type
	for(var/turf/closed/wall/W in block(locate(1, 1, SM.z_low), locate(world.maxx, world.maxy, SM.z_low)))
		if(clean(W) && ((isopenturf(get_step(W, NORTH)) && isopenturf(get_step(W, SOUTH))) || (isopenturf(get_step(W, EAST)) && isopenturf(get_step(W, WEST)))))
			wall = use(W)
			wall_type = W.type
			break
	check("found a wall", wall, "[wall_type]")
	if(wall)
		wall = wall.ChangeTurf(/turf/open/floor/plating)
		griefed += wall
		expect[wall] = "where"

	// a floor pulled up to space, one with decals on it if the map has one
	var/turf/floor
	var/floor_decals = FALSE
	for(var/pass in 1 to 2)
		for(var/turf/open/floor/plasteel/F in block(locate(1, 1, SM.z_low), locate(world.maxx, world.maxy, SM.z_low)))
			if((pass == 2 || stock_has(F, /obj/effect/turf_decal)) && clean(F) && !(locate(/obj) in F))
				floor = use(F)
				floor_decals = pass == 1
				break
		if(floor)
			break
	check("found a floor", floor, floor_decals ? "with decals" : "no decals")
	if(floor)
		floor = floor.ScrapeAway(2) // tile then plating
		if(!isspaceturf(floor))
			floor = floor.ChangeTurf(/turf/open/space)
		griefed += floor
		expect[floor] = "where"

	// a window and its grille smashed away
	var/turf/window_turf
	for(var/obj/structure/window/W in world)
		var/turf/T = W.loc
		if(W.fulltile && istype(T) && (locate(/obj/structure/grille) in T) && clean(T))
			window_turf = use(T)
			break
	check("found a window", window_turf)
	if(window_turf)
		for(var/obj/structure/window/W in window_turf)
			qdel(W)
		for(var/obj/structure/grille/G in window_turf)
			qdel(G)
		griefed += window_turf
		expect[window_turf] = "gone"

	// an airlock torn out, and another welded, bolted, electrified and cut
	var/turf/door_turf
	var/door_type
	var/obj/machinery/door/airlock/hacked
	for(var/obj/machinery/door/airlock/A in GLOB.airlocks)
		var/turf/T = A.loc
		if(!istype(T) || A.locked || A.welded || !clean(T))
			continue
		if(!door_turf)
			door_turf = use(T)
			door_type = A.type
		else if(!hacked)
			hacked = A
			use(T)
			break
	check("found two airlocks", door_turf && hacked)
	if(door_turf)
		for(var/obj/machinery/door/airlock/A in door_turf)
			qdel(A)
		griefed += door_turf
		expect[door_turf] = "gone"
	if(hacked)
		hacked.welded = TRUE
		hacked.bolt()
		hacked.set_electrified(MACHINE_ELECTRIFIED_PERMANENT)
		hacked.wires.cut(hacked.wires.wires[1])
		griefed += hacked.loc
		expect[hacked.loc] = "welded"

	// the APC broken
	var/obj/machinery/power/apc/apc
	var/area/apc_area
	for(var/obj/machinery/power/apc/P in GLOB.apcs_list)
		if(clean(P.loc) && P.terminal && P.cell)
			apc = P
			apc_area = P.area
			use(P.loc)
			break
	check("found an APC", apc)
	var/turf/apc_turf = apc?.loc
	if(apc)
		apc.set_broken()
		griefed += apc_turf
		expect[apc_turf] = "broken"

	// a cable cut out of the middle of a run
	var/turf/cable_turf
	var/obj/structure/cable/cable_left
	var/obj/structure/cable/cable_right
	for(var/obj/structure/cable/C in GLOB.cable_list)
		var/turf/T = C.loc
		if(!istype(T) || C.linked_dirs != (EAST|WEST) || (locate(/obj/machinery/power) in T) || !clean(T))
			continue
		var/obj/structure/cable/L = locate() in get_step(T, WEST)
		var/obj/structure/cable/R = locate() in get_step(T, EAST)
		if(L && R && L.cable_layer == C.cable_layer && R.cable_layer == C.cable_layer)
			cable_turf = use(T)
			cable_left = L
			cable_right = R
			break
	check("found a cable run", cable_turf)
	if(cable_turf)
		for(var/obj/structure/cable/C in cable_turf)
			qdel(C)
		griefed += cable_turf
		expect[cable_turf] = "gone"

	// a pipe and a vent taken out
	var/turf/pipe_turf
	var/obj/machinery/atmospherics/pipe_a
	var/obj/machinery/atmospherics/pipe_b
	for(var/obj/machinery/atmospherics/pipe/simple/P in world)
		var/turf/T = P.loc
		if(!istype(T) || !P.nodes[1] || !P.nodes[2] || length(T.contents) > 3 || !clean(T))
			continue
		var/count = 0
		for(var/obj/machinery/atmospherics/A in T)
			count++
		if(count != 1)
			continue
		pipe_turf = use(T)
		pipe_a = P.nodes[1]
		pipe_b = P.nodes[2]
		break
	check("found a pipe", pipe_turf)
	if(pipe_turf)
		for(var/obj/machinery/atmospherics/A in pipe_turf)
			qdel(A)
		griefed += pipe_turf
		expect[pipe_turf] = "gone"
	var/turf/vent_turf
	for(var/obj/machinery/atmospherics/components/unary/vent_pump/V in world)
		var/turf/T = V.loc
		if(istype(T) && V.nodes[1] && clean(T))
			vent_turf = use(T)
			break
	check("found a vent", vent_turf)
	if(vent_turf)
		for(var/obj/machinery/atmospherics/components/unary/vent_pump/V in vent_turf)
			qdel(V)
		griefed += vent_turf
		expect[vent_turf] = "gone"

	// a bulb broken
	var/obj/machinery/light/light
	for(var/obj/machinery/light/L in GLOB.machines)
		if(istype(L.loc, /turf) && L.status == 0 && clean(L.loc))
			light = L
			use(L.loc)
			break
	check("found a light", light)
	if(light)
		light.break_light_tube(TRUE)
		griefed += light.loc
		expect[light.loc] = "bulb out"

	// plasma let into a room, and a canister and a girder left behind
	var/turf/open/gas_turf
	var/turf/open/junk_turf
	for(var/turf/open/floor/plasteel/F in block(locate(1, 1, SM.z_low), locate(world.maxx, world.maxy, SM.z_low)))
		if(!clean(F) || (locate(/obj) in F))
			continue
		if(!gas_turf)
			gas_turf = use(F)
		else
			junk_turf = use(F)
			break
	check("found floors for gas and junk", gas_turf && junk_turf)
	if(gas_turf)
		SSair.remove_from_active(gas_turf)
		gas_turf.air.moles[/datum/gas/plasma] = 40
		griefed += gas_turf
		expect[gas_turf] = "in the air"
	var/obj/canister
	var/obj/girder
	if(junk_turf)
		canister = new /obj/machinery/portable_atmospherics/canister/toxins(junk_turf)
		girder = new /obj/structure/girder(junk_turf)
		griefed += junk_turf

	// the scan: every grief found
	var/datum/grief_undo/undo = new
	var/list/area_turfs = list()
	for(var/turf/T as anything in griefed)
		for(var/turf/U as anything in RANGE_TURFS(1, T))
			area_turfs[U] = TRUE
	var/list/scan_turfs = list()
	for(var/turf/T as anything in area_turfs)
		scan_turfs += T
	undo.scan(scan_turfs, "test")
	for(var/turf/T as anything in expect)
		var/datum/grief_tile/G = undo.tiles["[T.x],[T.y],[T.z]"]
		var/said = G ? jointext(G.describe(), "; ") : "nothing"
		check("scan finds [expect[T]] at [T.x],[T.y]", G && findtext(said, expect[T]), said)
	var/datum/grief_tile/junk = junk_turf ? undo.tiles["[junk_turf.x],[junk_turf.y],[junk_turf.z]"] : null
	check("scan shows the canister and girder", junk && length(junk.adds) == 2 && !junk.has_work(), junk ? "[length(junk.adds)] shown, work [!!junk.has_work()]" : "tile not listed")
	var/list/data = undo.ui_data(null)
	check("window data", length(data["rows"]) >= expect.len && length(data["adds"]) >= 2, "[length(data["rows"])] rows, [length(data["adds"])] added")

	// a click on the map unticks a tile and ticks it again
	if(wall)
		var/datum/grief_tile/G = undo.tiles["[wall.x],[wall.y],[wall.z]"]
		undo.InterceptClickOn(null, "left=1", wall)
		var/off = G && !G.ticked
		undo.InterceptClickOn(null, "left=1", wall)
		check("click on the map ticks a tile", off && G.ticked)

	// Apply
	var/began = REALTIMEOFDAY
	undo.apply(null)
	note(undo.message)
	sleep(3 SECONDS) // the pipe rebuild queue
	check("apply ran", findtext(undo.message, "Applied"), "[(REALTIMEOFDAY - began) / 10] s")
	if(wall)
		var/turf/T = locate(wall.x, wall.y, wall.z)
		check("wall back", T.type == wall_type, "[T.type]")
	if(floor)
		var/turf/T = locate(floor.x, floor.y, floor.z)
		check("floor back", istype(T, /turf/open/floor/plasteel), "[T.type]")
		if(floor_decals)
			check("floor's decals back", length(T.GetComponents(/datum/component/decal)), "[length(T.GetComponents(/datum/component/decal))] decals")
		var/turf/open/OT = T
		check("floor has air", istype(OT) && OT.air && OT.air.return_pressure() > 80, "[istype(OT) && OT.air ? round(OT.air.return_pressure()) : "none"] kPa")
	if(window_turf)
		var/windows = 0
		for(var/obj/structure/window/W in window_turf)
			windows++
		var/grilles = 0
		for(var/obj/structure/grille/G in window_turf)
			grilles++
		check("window and grille back, once each", windows == 1 && grilles == 1, "[windows] windows, [grilles] grilles")
	if(door_turf)
		var/obj/machinery/door/airlock/A = locate() in door_turf
		check("airlock back", A && A.type == door_type && (A.flags_1 & INITIALIZED_1), "[A?.type]")
	if(hacked)
		check("hacked airlock fixed", !hacked.welded && !hacked.locked && hacked.secondsElectrified == MACHINE_NOT_ELECTRIFIED && !length(hacked.wires.cut_wires), "welded [hacked.welded], bolted [hacked.locked], electrified [hacked.secondsElectrified], cut [length(hacked.wires.cut_wires)]")
	if(apc_turf)
		var/count = 0
		var/obj/machinery/power/apc/new_apc
		for(var/obj/machinery/power/apc/P in apc_turf)
			count++
			new_apc = P
		check("APC replaced, once", count == 1 && new_apc != apc && !(new_apc.stat & BROKEN), "[count] APCs")
		if(new_apc)
			check("new APC runs its area", new_apc.area == apc_area && apc_area.power_equip && new_apc.cell && new_apc.terminal?.powernet, "same area [new_apc.area == apc_area], equipment powered [apc_area.power_equip], cell [!!new_apc.cell], terminal net [!!new_apc.terminal?.powernet]")
	if(cable_turf)
		var/obj/structure/cable/C = locate() in cable_turf
		check("cable back and joined", C && C.powernet && C.powernet == cable_left.powernet && C.powernet == cable_right.powernet, "[C ? "dirs [C.linked_dirs]" : "no cable"]")
	if(pipe_turf)
		var/obj/machinery/atmospherics/pipe/simple/P = locate() in pipe_turf
		check("pipe back and joined", P && P.parent && P.nodes[1] && P.nodes[2] && P.parent == pipe_a.returnPipenet(P) && P.parent == pipe_b.returnPipenet(P), "[P ? "nodes [!!P.nodes[1]] [!!P.nodes[2]], parent [!!P.parent]" : "no pipe"]")
	if(vent_turf)
		var/obj/machinery/atmospherics/components/unary/vent_pump/V = locate() in vent_turf
		check("vent back and joined", V && V.nodes[1] && V.parents[1], "[V ? "node [!!V.nodes[1]], net [!!V.parents[1]]" : "no vent"]")
	if(light)
		check("bulb back", light.status == 0)
	if(gas_turf)
		check("plasma gone", !gas_turf.air.moles[/datum/gas/plasma], "[gas_turf.air.moles[/datum/gas/plasma]] mol")
	check("canister and girder left alone", canister && !QDELETED(canister) && girder && !QDELETED(girder))

	// a second scan finds nothing left to do, and a second Apply makes nothing
	var/left = 0
	var/list/left_what = list()
	for(var/key in undo.tiles)
		var/datum/grief_tile/G = undo.tiles[key]
		if(G.has_work())
			left++
			left_what += "[key]: [jointext(G.describe(), "; ")]"
	check("nothing left after Apply", !left, jointext(left_what, " | "))
	var/made_before = length(undo.last_apply?["made"])
	var/list/saved = undo.last_apply
	undo.apply(null)
	check("second Apply does nothing", findtext(undo.message, "Nothing ticked") || !length(undo.last_apply?["made"]), undo.message)
	undo.last_apply = saved
	note("first Apply made [made_before] things")

	// Undo takes the new things away and puts the griefed turfs back
	undo.undo(null)
	note(undo.message)
	if(gas_turf) // before it spreads
		check("undo: plasma back", gas_turf.air.moles[/datum/gas/plasma] >= 39, "[gas_turf.air.moles[/datum/gas/plasma]] mol")
	sleep(1 SECONDS)
	if(wall)
		var/turf/T = locate(wall.x, wall.y, wall.z)
		check("undo: wall gone again", T.type == /turf/open/floor/plating, "[T.type]")
	if(window_turf)
		check("undo: window gone again", !(locate(/obj/structure/window) in window_turf))
	if(door_turf)
		check("undo: airlock gone again", !(locate(/obj/machinery/door/airlock) in door_turf))

	// and Apply again leaves it all right
	undo.rescan()
	undo.apply(null)
	sleep(2 SECONDS)
	left = 0
	left_what = list()
	for(var/key in undo.tiles)
		var/datum/grief_tile/G = undo.tiles[key]
		if(G.has_work())
			left++
			left_what += "[key]: [jointext(G.describe(), "; ")]"
	check("Apply after Undo fixes it again", !left && findtext(undo.message, "Applied"), "[undo.message] [jointext(left_what, " | ")]")
	qdel(undo)

/// A player's logged spots: their tiles are scanned and marked near
/datum/grief_selftest/proc/player_scan()
	var/turf/spot
	for(var/turf/closed/wall/W in block(locate(1, 1, SM.z_low), locate(world.maxx, world.maxy, SM.z_low)))
		if(clean(W))
			spot = use(W)
			break
	if(!spot)
		check("found a wall for the player scan", FALSE)
		return
	spot = spot.ChangeTurf(/turf/open/floor/plating)
	var/list/entry = new /list(RL_LEN)
	entry[RL_ID] = ++GLOB.round_log_total
	entry[RL_TIME] = world.time
	entry[RL_CAT] = "Game"
	entry[RL_TEXT] = "griefertest deconstructed a wall"
	entry[RL_CKEY] = "griefertest"
	entry[RL_X] = spot.x
	entry[RL_Y] = spot.y
	entry[RL_Z] = spot.z
	GLOB.round_log += list(entry)
	var/datum/grief_undo/undo = new
	undo.scan_player("griefertest", 10)
	var/datum/grief_tile/G = undo.tiles["[spot.x],[spot.y],[spot.z]"]
	check("player scan finds their wall", G && G.turf_path && G.near, "[undo.source]; [G ? jointext(G.describe(), "; ") : "not found"]")
	var/near = 0
	for(var/key in undo.tiles)
		var/datum/grief_tile/T = undo.tiles[key]
		if(T.near)
			near++
	note("player scan: [undo.selection.len] tiles looked at, [length(undo.tiles)] listed, [near] near their spot")
	undo.scan_player("nobodyatall", 10)
	check("player scan with nothing logged says so", !length(undo.tiles) && findtext(undo.message, "Nothing logged"), undo.message)
	qdel(undo)

#undef GRIEF_CHECK_DIR
