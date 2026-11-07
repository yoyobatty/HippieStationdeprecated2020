// Lint fix self-test: each gameplay fix from the first dreamchecker pass, driven in the real engine.
// Only in a side build, so hippiestation.dmb is left alone:
//   cp hippiestation.dme lintfix.mdme && printf '#include "tools\\lint\\lint_fix_selftest.dm"\r\n' >> lintfix.mdme
//   dm.exe lintfix.mdme && dd.exe lintfix.mdme.dmb 45411 -trusted -invisible -params "lint-fix-test=1"
// Results in data/lint_fix_test/results.txt, one PASS/FAIL line per check. 63ab92c2 (before the fixes): 12 of 28.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("lint-fix-test" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_lint_fix_test))
	return ..()

/proc/run_lint_fix_test()
	world.sleep_offline = FALSE
	sleep(5 SECONDS)
	fdel("data/lint_fix_test/")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	var/datum/lint_fix_test/test = new
	test.run_all()
	text2file(jointext(test.lines, "\n"), "data/lint_fix_test/results.txt")
	log_world("LINT FIX TEST: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/nanite_program/lint_probe
	var/errors = 0

/datum/nanite_program/lint_probe/software_error(type)
	errors++

/datum/lint_fix_test
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/x0
	var/y0
	var/z0

/datum/lint_fix_test/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/datum/lint_fix_test/proc/spot(dx, dy)
	return locate(x0 + dx, y0 + dy, z0)

/datum/lint_fix_test/proc/build_room()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(40, 30)
	if(!R)
		return FALSE
	x0 = R.bottom_left_coords[1] + 2
	y0 = R.bottom_left_coords[2] + 2
	z0 = R.bottom_left_coords[3]
	var/area/test_area = new /area/bot_gym
	for(var/x in x0 to x0 + 30)
		for(var/y in y0 to y0 + 20)
			var/turf/T = locate(x, y, z0)
			var/area/old_area = T.loc
			old_area.contents -= T
			test_area.contents += T
			T.change_area(old_area, test_area)
			if(x == x0 || x == x0 + 30 || y == y0 || y == y0 + 20)
				T.ChangeTurf(/turf/closed/indestructible/riveted, flags = CHANGETURF_IGNORE_AIR)
			else
				var/turf/open/floor/F = T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
				F.air.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
				F.update_visuals()
	return TRUE

/datum/lint_fix_test/proc/run_all()
	if(!build_room())
		lines += "FAIL couldn't reserve space"
		return
	var/runtimes_before = GLOB.total_runtimes
	var/list/tests = list(
		"type2parent", "manifold", "singularity", "dusting", "disposal", "table", "nanites",
		"vegetarian", "soulflare", "repeaterang", "ripley", "gremlin", "airlock_examine")
	for(var/name in tests)
		try
			call(src, "test_[name]")()
		catch(var/exception/e)
			check("[name] ran without a runtime", FALSE, "[e] at [e.file]:[e.line]")
	check("no uncaught runtimes during the test", GLOB.total_runtimes == runtimes_before, "[GLOB.total_runtimes - runtimes_before] new")
	lines += "[passed] passed, [failed] failed"

/datum/lint_fix_test/proc/test_type2parent()
	check("type2parent(/mob) is /atom/movable", type2parent(/mob) == /atom/movable, "[type2parent(/mob)]")
	check("type2parent(/turf) is /atom", type2parent(/turf) == /atom, "[type2parent(/turf)]")

/datum/lint_fix_test/proc/test_manifold()
	var/obj/machinery/atmospherics/pipe/layer_manifold/M = new(spot(2, 2))
	M.setDir(WEST)
	M.SetInitDirections()
	check("west-facing layer manifold opens east and west", M.initialize_directions == (EAST|WEST), "[M.initialize_directions]")
	M.setDir(SOUTH)
	M.SetInitDirections()
	check("south-facing layer manifold opens north and south", M.initialize_directions == (NORTH|SOUTH), "[M.initialize_directions]")
	qdel(M)

/datum/lint_fix_test/proc/test_singularity()
	var/turf/C = spot(20, 10)
	var/obj/singularity/S = new(C)
	STOP_PROCESSING(SSobj, S)
	// a live field generator on the side of each strip, 2 tiles out
	var/list/side = list("[NORTH]" = list(1, 2), "[SOUTH]" = list(1, -2), "[EAST]" = list(2, 1), "[WEST]" = list(-2, 1))
	for(var/d in list(NORTH, SOUTH, EAST, WEST))
		var/list/o = side["[d]"]
		check("singularity sees open ground to the [dir2text(d)]", S.check_turfs_in(d, 2) == 1)
		var/obj/machinery/field/generator/G = new(locate(C.x + o[1], C.y + o[2], C.z))
		G.active = 2
		check("singularity sees a field beside its [dir2text(d)] strip", S.check_turfs_in(d, 2) == 0)
		qdel(G)
	qdel(S)

/datum/lint_fix_test/proc/test_dusting()
	var/mob/living/carbon/human/H = new(spot(2, 4))
	var/obj/item/storage/toolbox/mechanical/box = new(spot(2, 4))
	H.put_in_hands(box)
	var/obj/item/implant/dusting/D = new
	D.implant(H, null, TRUE)
	D.activate("death")
	check("dusting implant destroys what its host carries at once", QDELETED(box))

/datum/lint_fix_test/proc/test_disposal()
	var/mob/living/carbon/human/U = new(spot(4, 4))
	var/obj/machinery/disposal/bin/B = new(spot(5, 4))
	var/obj/item/storage/backpack/P = new(spot(4, 4))
	var/obj/item/a = new /obj/item/stack/sheet/metal(P)
	var/obj/item/b = new /obj/item/screwdriver(P)
	var/datum/component/storage/STR = P.GetComponent(/datum/component/storage)
	B.storage_contents_dump_act(STR, U)
	check("a bag dumped into a disposal bin empties into it", a.loc == B && b.loc == B, "[a.loc], [b.loc]")

/datum/lint_fix_test/proc/test_table()
	var/mob/living/carbon/human/U = new(spot(7, 4))
	var/mob/living/carbon/human/P = new(spot(7, 5))
	var/obj/structure/table/T = new(spot(8, 5))
	P.pass_flags |= PASSGLASS
	T.tablepush(U, P)
	check("a mob with other pass flags can be slammed onto a table", P.loc == T.loc, "[P.loc]")
	check("PASSTABLE taken back off after the slam", !(P.pass_flags & PASSTABLE))

/datum/lint_fix_test/proc/test_nanites()
	var/reacted = 0
	for(var/i in 1 to 200)
		var/datum/nanite_program/lint_probe/N = new
		N.program_flags = NANITE_EMP_IMMUNE
		N.on_shock(10)
		if(N.errors || QDELETED(N))
			reacted++
	check("an EMP-proof nanite program still reacts to shocks", reacted > 20, "[reacted] of 200")
	reacted = 0
	for(var/i in 1 to 200)
		var/datum/nanite_program/lint_probe/N = new
		N.program_flags = NANITE_SHOCK_IMMUNE
		N.on_shock(10)
		if(N.errors || QDELETED(N))
			reacted++
	check("a shock-proof nanite program ignores shocks", reacted == 0, "[reacted] of 200")

/datum/lint_fix_test/proc/test_vegetarian()
	var/mob/living/carbon/human/H = new(spot(10, 4))
	H.add_quirk(/datum/quirk/vegetarian, FALSE)
	var/disliked = H.dna.species.disliked_food & MEAT
	H.remove_quirk(/datum/quirk/vegetarian)
	check("vegetarian quirk dislikes meat while it lasts", disliked)
	check("a human stops disliking meat when the quirk goes", !(H.dna.species.disliked_food & MEAT), "[H.dna.species.disliked_food]")

/datum/lint_fix_test/proc/test_soulflare()
	var/mob/living/carbon/human/U = new(spot(12, 4))
	var/mob/living/carbon/human/V = new(spot(13, 4))
	U.mind_initialize()
	U.mind.AddSpell(new /obj/effect/proc_holder/spell/targeted/trigger/soulflare(null))
	V.adjustOxyLoss(120)
	var/stat_before = V.stat
	var/obj/effect/proc_holder/spell/targeted/inflict_handler/soulflare/S = new(null)
	S.cast(list(V), U)
	check("soulflare finishes off a target in crit", stat_before != DEAD && V.stat == DEAD, "stat [stat_before] -> [V.stat], health [V.health]")

/datum/lint_fix_test/proc/test_repeaterang()
	var/obj/item/boomerang/repeat/R = new(spot(15, 4))
	var/ok = TRUE
	var/err
	try
		R.throw_at(spot(15, 8), 3, 1, callback = null, quickstart = FALSE)
	catch(var/exception/e)
		ok = FALSE
		err = "[e]"
	check("a repeaterang takes a throw with named arguments (blasts, mech launchers)", ok, err)

/datum/lint_fix_test/proc/test_ripley()
	var/obj/mecha/working/ripley/M = new(spot(18, 15))
	var/obj/item/mecha_parts/mecha_equipment/ripleyupgrade/K = new(spot(18, 15))
	var/energy = M.armor.energy
	var/ok = TRUE
	var/err
	try
		K.attach(M)
	catch(var/exception/e)
		ok = FALSE
		err = "[e] at [e.file]:[e.line]"
	var/obj/mecha/working/ripley/mkii/N = locate() in spot(18, 15)
	check("ripley upgrade kit fits without a runtime", ok, err)
	check("the old ripley is replaced by the MK-II", QDELETED(M) && N)
	check("the MK-II keeps the old ripley's energy armour", N && N.armor.energy == energy, "[N?.armor.energy] vs [energy]")

/datum/lint_fix_test/proc/test_gremlin()
	var/turf/open/T = spot(24, 15)
	new /mob/living/simple_animal/hostile/gremlin(T)
	var/datum/reagent/water/W = new
	W.reaction_turf(T, 10)
	var/count = 0
	for(var/mob/living/simple_animal/hostile/gremlin/G in T)
		count++
	check("water splashed on a gremlin's floor splits it", count == 2, "[count]")

/datum/lint_fix_test/proc/test_airlock_examine()
	var/mob/living/silicon/robot/borg = new(spot(27, 15))
	var/obj/machinery/door/airlock/A = new(spot(27, 16))
	A.stat |= NOPOWER
	var/text = jointext(A.examine(borg), " ")
	check("a cyborg is shown the shift-click hint on an unpowered, unbroken airlock", findtext(text, "Shift-click"))
