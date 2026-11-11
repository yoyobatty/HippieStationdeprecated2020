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
	catch(var/exception/e)
		failed++
		lines += "FAIL exception: [e] at [e.file]:[e.line]"
	lines += "[passed] passed, [failed] failed"
	text2file(jointext(lines, "\n"), "data/qol_check/results.txt")
	Master.Shutdown()
	qdel(world)
