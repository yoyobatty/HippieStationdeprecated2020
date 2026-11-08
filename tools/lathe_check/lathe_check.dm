// Lathe groups self-test (hippiestation/code/modules/research/design_groups.dm), headless.
//
// Run:      tools/lathe_check/run_lathe_check.sh   (builds its own copy, so hippiestation.dmb is left alone)
// Results:  data/lathe_check/results.txt (PASS/FAIL lines) and data/lathe_check/groups.tsv (every design's group on each machine).
//
// Every protolathe and imprinter design has one home that isn't "Misc", every machine's window data names its grouping, the
// static data carries the groups, and a player's remembered category and hide toggle come back.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("lathe-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_lathe_check))
	return ..()

#define LATHE_CHECK_DIR "data/lathe_check/"

/proc/run_lathe_check()
	sleep(5 SECONDS)
	fdel(LATHE_CHECK_DIR)
	while(!SSresearch.initialized)
		sleep(1 SECONDS)
	var/list/lines = list()
	var/list/tsv = list("id\tname\tmachine\tgroup\ttg categories\tdepartments")
	var/passed = 0
	var/failed = 0
	var/list/counts = list("lathe" = list(), "board" = list())
	var/list/misc = list()
	for(var/id in SSresearch.techweb_designs)
		var/datum/design/D = SSresearch.techweb_designs[id]
		if(D.build_type & PROTOLATHE)
			var/G = D.lathe_group()
			counts["lathe"][G] = (counts["lathe"][G] || 0) + 1
			tsv += "[id]\t[D.name]\tprotolathe\t[G]\t[jointext(D.category, ",")]\t[D.departmental_flags]"
			if(G == "Misc")
				misc += "protolathe [id]"
		if(D.build_type & IMPRINTER)
			var/G = D.board_group()
			counts["board"][G] = (counts["board"][G] || 0) + 1
			tsv += "[id]\t[D.name]\timprinter\t[G]\t[jointext(D.category, ",")]\t[D.departmental_flags]"
			if(G == "Misc")
				misc += "imprinter [id]"
	for(var/kind in counts)
		var/list/C = counts[kind]
		var/list/parts = list()
		for(var/G in C)
			parts += "[G] [C[G]]"
		lines += "INFO [kind] groups: [jointext(parts, ", ")]"
	if(length(misc))
		failed++
		lines += "FAIL designs with no home (Misc): [jointext(misc, "; ")]"
	else
		passed++
		lines += "PASS every protolathe and imprinter design has a home"

	var/list/S = rd_ui_static_data()
	var/list/designs = S["designs"]
	var/list/crowbar = designs["crowbar"]
	if(crowbar && crowbar["lathe"] == "Tools" && isnull(crowbar["board"]))
		passed++
		lines += "PASS static data carries the groups (crowbar: Tools)"
	else
		failed++
		lines += "FAIL static data crowbar: [crowbar ? json_encode(crowbar) : "missing"]"

	var/turf/T = locate(world.maxx / 2, world.maxy / 2, SSmapping.station_start)
	var/list/machines = list(
		/obj/machinery/rnd/production/protolathe = "lathe",
		/obj/machinery/rnd/production/circuit_imprinter = "board",
		/obj/machinery/rnd/production/techfab/department/medical = "lathe,board",
		/obj/machinery/autolathe = "autolathe",
	)
	var/mob/living/carbon/human/H = new(T)
	H.ckey = "lathecheck" // no client: lathe_panel_prefs goes by ckey alone
	for(var/path in machines)
		var/obj/machinery/M = new path(T)
		var/list/data = M.ui_data(H)
		var/grouping = islist(data["grouping"]) ? jointext(data["grouping"], ",") : "[data["grouping"]]"
		if(grouping == machines[path] && islist(data["panel_prefs"]))
			passed++
			lines += "PASS [path] lists by [grouping]"
		else
			failed++
			lines += "FAIL [path] grouping [grouping], prefs [json_encode(data["panel_prefs"])]"
		qdel(M)

	lathe_panel_pref_set(H, "lathe", "Medical")
	lathe_panel_pref_set(H, "hide", "1")
	lathe_panel_pref_set(H, "bogus", "x")
	var/list/prefs = lathe_panel_prefs(H)
	if(prefs["lathe"] == "Medical" && prefs["hide"] == 1 && !("bogus" in prefs))
		passed++
		lines += "PASS remembered: lathe Medical, hide on, unknown keys refused"
	else
		failed++
		lines += "FAIL prefs [json_encode(prefs)]"
	H.ckey = null
	qdel(H)

	lines.Insert(1, "[passed] passed, [failed] failed")
	text2file(jointext(lines, "\n"), "[LATHE_CHECK_DIR]results.txt")
	text2file(jointext(tsv, "\n"), "[LATHE_CHECK_DIR]groups.tsv")
	log_world("LATHE CHECK: done, [passed] passed, [failed] failed")
	Master.Shutdown()
	qdel(world)

#undef LATHE_CHECK_DIR
