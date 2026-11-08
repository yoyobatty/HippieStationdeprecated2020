// Chemistry check (tools/chem_check/run_chem_check.sh): reactions exactly, and chem dispensers EMP'd as a tesla zap does it, timed.
//
// 1 600 fixed mixes of the dispensers' chemicals (and sugar, water, fuel), added one at a time (each reacting) or all at once, at
//   150-700 K, every fifth in a mob: what's left of each written to data/chem_exact.txt. Two builds' files are the same when their
//   reactions are (diff them: the runner takes another worktree to build, say HEAD's). The mixes that make foam or smoke have no
//   atom to make it at: about 13 runtimes in spread_foam() and smoke set_up(), the same in any build.
// 2 24 chem dispensers EMP'd on Runtime Station, the same chemicals each build: the time each took, the worst, and the procs in it
//   (data/chem_emp_check.txt). Before 2026-11-08's fixes: 130 ms each, the worst 524 ms; after: 34 ms, 131 ms.
/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("chem-emp-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_chem_emp_check))
	return ..()

/proc/run_chem_emp_check()
	sleep(5 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	// Reactions exactly: fixed mixes, results written out, compared between builds
	var/list/exact = list()
	var/obj/machinery/chem_dispenser/source = new(locate(1, 1, 1))
	var/list/pool = source.dispensable_reagents.Copy() + source.emagged_reagents + list(/datum/reagent/consumable/sugar, /datum/reagent/water, /datum/reagent/fuel)
	qdel(source)
	var/mob/living/carbon/human/subject = new(locate(2, 2, 1))
	for(var/case in 1 to 600)
		rand_seed(case)
		var/in_mob = (case % 5 == 0)
		var/datum/reagents/holder = in_mob ? subject.reagents : new /datum/reagents(1000)
		if(in_mob)
			holder.clear_reagents()
		holder.chem_temp = pick(150, 300, 300, 450, 700)
		var/batched = (case % 2 == 0)
		if(batched)
			ENABLE_BITFIELD(holder.flags, NO_REACT)
		// some from a short list, so the same ones go in again and again (recipes needing more of one); some at other temperatures
		var/list/from = (case % 7 == 0) ? pool.Copy(1, 5) : pool
		var/other_temps = (case % 3 == 0)
		for(var/i in 1 to rand(4, 16))
			holder.add_reagent(pick(from), rand(1, 30), null, other_temps ? pick(150, 300, 450, 700) : holder.chem_temp)
		if(batched)
			DISABLE_BITFIELD(holder.flags, NO_REACT)
			holder.handle_reactions()
		var/list/contents = list()
		for(var/datum/reagent/R as anything in holder.reagent_list)
			contents += "[R.type]=[round(R.volume, 0.0001)]"
		exact += "[case]: [holder.chem_temp] [jointext(contents, " ")]"
		if(!in_mob)
			qdel(holder)
	fdel("data/chem_exact.txt")
	text2file(jointext(exact, "\n"), "data/chem_exact.txt")
	rand_seed(7)
	var/list/floors = list()
	for(var/turf/open/floor/F in GLOB.station_turfs)
		if(!F.density && !(locate(/obj/machinery) in F))
			floors += F
	var/list/spots = list()
	var/turf/same = pick(floors)
	for(var/i in 1 to 24)
		spots += world.params["chem-same-spot"] ? same : pick(floors) // chem-same-spot=1: one dispenser after another in one place, as a tesla zaps the same one
	var/list/lines = list()
	var/total = 0
	var/worst = 0
	var/timer_total = 0
	var/piles = 0
	var/most_reagents = 0
	var/list/emp_procs = list()
	for(var/i in 1 to length(spots))
		var/turf/T = spots[i]
		var/dispenser_type = text2path(world.params["chem-type"]) || /obj/machinery/chem_dispenser
		var/obj/machinery/chem_dispenser/D = new dispenser_type(T)
		sleep(world.tick_lag)
		var/timer_before = SStimer.total_ms
		rand_seed(1000 + i)
		var/mark = TICK_USAGE_REAL
		D.emp_act(EMP_LIGHT)
		var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark)
		if(SSprofiler?.engine == "hippie")
			var/list/ran = SSprofiler.recent(ms + 1)
			for(var/name in ran)
				emp_procs[name] += ran[name]
		sleep(world.tick_lag * 3) // the piles' colours, one tick on
		timer_total += SStimer.total_ms - timer_before
		total += ms
		worst = max(worst, ms)
		for(var/obj/effect/decal/cleanable/chempile/C in range(4, T))
			piles++
			if(world.params["chem-same-spot"] && i == length(spots))
				most_reagents = max(most_reagents, length(C.reagents?.reagent_list))
		qdel(D)
	lines += "[length(spots)] chem dispensers EMP'd: [round(total, 0.1)] ms in all, [round(total / length(spots), 0.1)] ms each, the worst [round(worst, 0.1)] ms; SStimer over the next ticks [round(timer_total, 0.1)] ms; [piles] piles about[most_reagents ? ", the most chemicals in one at the end [most_reagents]" : ""]"
	sortTim(emp_procs, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	var/list/top = list()
	for(var/name in emp_procs)
		top += "[name] [round(emp_procs[name] * 1000)]"
		if(length(top) >= 16)
			break
	lines += "in the EMPs (ms): [jointext(top, ", ")]"
	text2file(jointext(lines, "\n"), "data/chem_emp_check.txt")
	log_world("CHEM EMP CHECK: done")
	Master.Shutdown()
	qdel(world)
