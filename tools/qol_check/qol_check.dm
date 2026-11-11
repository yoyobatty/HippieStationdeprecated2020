// Machine and item interaction checks (container_qol.dm and later ones), headless. Not part of the game.
// Run: tools/qol_check/run_qol_check.sh   Results: data/qol_check/results.txt

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("qol-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_qol_check))
	return ..()

/proc/run_qol_check()
	sleep(5 SECONDS)
	fdel("data/qol_check/")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	try
		var/turf/T = get_turf(pick(SSjob.latejoin_trackers))
		var/mob/living/carbon/human/H = new(T)
		var/list/tests = list(
			/obj/machinery/atmospherics/components/unary/cryo_cell,
			/obj/machinery/biogenerator,
			/obj/machinery/reagentgrinder,
			/obj/machinery/chem_master,
			/obj/machinery/chem_heater,
		)
		for(var/path in tests)
			var/turf/spot = get_step(H, EAST)
			var/obj/machinery/M = new path(spot)
			var/obj/item/reagent_containers/glass/beaker/first = new(H)
			H.put_in_active_hand(first)
			M.attackby(first, H)
			var/loaded_first = M.vars["beaker"] == first
			var/obj/item/reagent_containers/glass/beaker/large/second = new(H)
			H.put_in_active_hand(second)
			M.attackby(second, H)
			var/swapped = M.vars["beaker"] == second && (first in H.held_items)
			H.dropItemToGround(first)
			M.AltClick(H)
			var/ejected = !M.vars["beaker"] && (second in H.held_items)
			var/ok = loaded_first && swapped && ejected
			if(ok)
				passed++
			else
				failed++
			lines += "[ok ? "PASS" : "FAIL"] [path]: loaded [loaded_first], swapped [swapped], Alt-click ejected [ejected]"
			H.dropItemToGround(second)
			qdel(M)
			qdel(first)
			qdel(second)
		// Somewhere with room, off the arrivals shuttle's seats: the puller, the tile below them, and either side of that, all clear.
		for(var/turf/open/floor/F in range(8, H))
			var/turf/B = get_step(F, SOUTH)
			var/turf/E = B ? get_step(B, EAST) : null
			var/turf/W = B ? get_step(B, WEST) : null
			var/clear = TRUE
			for(var/turf/spot in list(F, B, E, W))
				if(!isopenturf(spot) || is_blocked_turf(spot, TRUE) || (locate(/obj/structure/chair) in spot) || (locate(/obj/machinery) in spot))
					clear = FALSE
					break
			if(clear)
				H.forceMove(F)
				break
		var/turf/below = get_step(H, SOUTH)
		// Somebody pulled up to a sleeper, and a click on it: they go in.
		var/obj/machinery/sleeper/S = new(get_step(below, EAST))
		var/mob/living/carbon/human/patient = new(below)
		H.start_pulling(patient)
		S.attack_hand(H)
		sleep(5)
		var/in_sleeper = S.occupant == patient
		if(in_sleeper)
			passed++
		else
			failed++
		lines += "[in_sleeper ? "PASS" : "FAIL"] a click on a sleeper while pulling somebody puts them in (occupant [S.occupant || "none"])"
		// And a chair: they're buckled into it.
		var/obj/structure/chair/chair = new(get_step(below, WEST)) //beside them, and in the puller's reach
		var/mob/living/carbon/human/sitter = new(below)
		H.start_pulling(sitter)
		var/took = chair.buckle_pulled(H)
		sleep(5)
		var/buckled = sitter.buckled == chair
		if(!buckled)
			lines += "     buckle_pulled [took]; adjacent puller-chair [chair.Adjacent(H)], sitter-chair [sitter.Adjacent(chair)], sitter buckled to [sitter.buckled || "nothing"], lying [sitter.lying], anchored [sitter.anchored], incapacitated puller [H.incapacitated()], chair dir [chair.dir]"
		if(buckled)
			passed++
		else
			failed++
		lines += "[buckled ? "PASS" : "FAIL"] a click on a chair while pulling somebody buckles them in (puller [COORD(H)], them [COORD(sitter)] [below.type] [below.density], chair [COORD(chair)], pulling [H.pulling])"
	catch(var/exception/e)
		failed++
		lines += "FAIL exception: [e] at [e.file]:[e.line]"
	lines += "[passed] passed, [failed] failed"
	text2file(jointext(lines, "\n"), "data/qol_check/results.txt")
	Master.Shutdown()
	qdel(world)
