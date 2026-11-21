// Bot gym scenarios from the 2026-11-21 bot audit, perf area.

/datum/bot_scenario/glance_cap_on_a_pile
	name = "perf: a pile of hundreds of things in sight is taken in up to a cap, not all of it, at every glance"
	desc = "glance_at_items() (bot_knowledge.dm) noted every item in view once a second, ~2 us each: a crate's worth spawned on one tile in sight cost each bot that looked a millisecond or more a second. It takes in at most 300 now, the nearest first."
	time_limit = 20 SECONDS
	layout = list(
		"#########",
		"#B..p..G#",
		"#########")
	var/pile_made = FALSE

/datum/bot_scenario/glance_cap_on_a_pile/make_goal()
	return null //the scenario glances for it

/datum/bot_scenario/glance_cap_on_a_pile/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(pile_made)
		return BOT_GYM_PENDING
	pile_made = TRUE
	// after it arrived: what's laid out before that is the arena's "map" and isn't noted
	var/turf/where = first_marker("p")
	for(var/i in 1 to 1500)
		new /obj/item/paper(where)
	// What it remembers after a while: a full list of things it has seen (bot_knowledge.dm keeps 400)
	brain.seen_items = null
	var/turf/far = first_marker("G")
	for(var/i in 1 to 400)
		brain.note_seen(new /obj/item/paper(far), far)
	brain.next_item_glance = 0
	var/started = TICK_USAGE_REAL
	brain.glance_at_items()
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	var/noted = length(brain.seen_items)
	// The same look a second on: everything in sight is known already
	brain.next_item_glance = 0
	started = TICK_USAGE_REAL
	brain.glance_at_items()
	var/again_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	for(var/i in 1 to 20)
		brain.find_item_goal() //what an idle bot looks for, a quarter of the time it stands about
	log_line("find_item_goal() with the pile in sight: [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / 20, 0.01)] ms a call")
	var/most = ("bot_glance_most" in GLOB.vars) ? GLOB.vars["bot_glance_most"] : null //by name, so a build from before it was added still compiles
	log_line("one glance at 1500 papers on a tile in sight, with 400 things remembered: [round(ms, 0.1)] ms, [noted] things remembered after, the most one glance has found in sight [most || "not counted"]; the same look again: [round(again_ms, 0.1)] ms")
	if(noted > 400)
		fail_reason = "a glance left [noted] things remembered: more than it keeps"
		return BOT_GYM_FAIL
	if(!("bot_glance_most" in GLOB.vars)) //a build from before the cap
		fail_reason = "one glance noted [noted] things from a pile of 1500, with no cap on what it takes in"
		return BOT_GYM_FAIL
	if(most != 301)
		fail_reason = "the cap wasn't reached by a pile of 1500 (the most in one glance: [most || "not counted"])"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/assailant_mark_let_go
	name = "perf: a monkey fed to a slime lets go of the bot when the bot is gibbed"
	desc = "A bot feeding slimes sets itself as the dropped monkey's LAssailant (goals/xenobiology.dm), a plain reference, and a bot gibbed while the monkey was still about was a hard delete (a 30-50 ms freeze). The brain takes itself back out of what it marked when it goes."
	time_limit = 20 SECONDS
	layout = list(
		"#######",
		"#B...G#",
		"#######")
	var/tested = FALSE

/datum/bot_scenario/assailant_mark_let_go/make_goal()
	return null //the scenario does the feeding and the gibbing

/datum/bot_scenario/assailant_mark_let_go/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(tested)
		return BOT_GYM_PENDING
	tested = TRUE
	var/mob/living/carbon/monkey/food = new(first_marker("G"))
	food.LAssailant = bot //what feed_slimes does with the monkey it drops in
	if(hascall(brain, "mark_as_assailant")) //by name, so a build from before it was added still compiles
		call(brain, "mark_as_assailant")(food)
	var/mob/living/carbon/human/body = bot
	qdel(body)
	if(food.LAssailant == body)
		fail_reason = "the monkey still has the gibbed bot as its LAssailant: that's a hard delete for the bot"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Kill mode: what every scenario's step does when its body goes
// ---------------------------------------------------------------------------------------------
// bot-gym-kill=<seconds>: every gym run's bot is killed that long after the run starts, a gib, a qdel, a small blast or a death in turn
// (by the scenario's place in the suite), whatever it was in the middle of. The gym never deletes a bot, so nothing else tests what a click, a
// walk or a goal's step does when it wakes from a pause with nobody there: a runtime in the step's own proc, or a caught exception, or
// (with a gib hunt, tools/gc_hunt/bot_gib_hunt.dm) a hard delete. A run's verdict is meaningless then (the bot died). The result is the
// round log's runtime.log: "runtime error" lines in bots_ai files outside gym/ are uncaught runtimes (a step that no try/catch covers),
// "BOT AI EXCEPTION" lines are caught ones that aren't about a body gone, and "outlived its body" lines are the expected unwinding.
//   NOCOMPILE=1 EXTRA_PARAMS="bot-gym-kill=5" JOBS=8 tools/bot_gym/run_bot_gym.sh all 1
//   python tools/runtime_ledger/ledger.py --ours data/logs/bot_gym/<run>/       (runtimes by file and line; 5 s is mid-errand for most)

/// Seconds after a run starts that its bot is killed, or null
GLOBAL_VAR_INIT(bot_gym_kill_after, text2num(world.params["bot-gym-kill"]))

/// bot-gym-vanish=<seconds>: the same, for what the bot's goal is after: that long in, its target (an item, a machine, a patient...) is deleted,
/// as when somebody picks it up or a bomb takes it. A step that reads the target after that is a caught "BOT AI EXCEPTION" in the round log
/// (the bot is alive, so none of it is "outlived its body"): each one is a goal that doesn't cope with its target going.
GLOBAL_VAR_INIT(bot_gym_vanish_after, text2num(world.params["bot-gym-vanish"]))

/datum/bot_scenario
	var/killed_at
	var/vanished_at

/datum/bot_scenario/tick()
	var/vanish_after = GLOB.bot_gym_vanish_after
	if(vanish_after && !vanished_at && result == BOT_GYM_PENDING && brain && world.time >= start_time + vanish_after SECONDS)
		var/atom/target = brain.current_goal?.target
		if(target && !isturf(target) && target != bot && !QDELETED(target))
			vanished_at = world.time
			qdel(target)
	var/kill_after = GLOB.bot_gym_kill_after
	if(kill_after && !killed_at && result == BOT_GYM_PENDING && bot && !QDELETED(bot) && bot.stat != DEAD && world.time >= start_time + kill_after SECONDS)
		killed_at = world.time
		var/mob/living/carbon/human/body = bot
		switch(suite_index % 4)
			if(0)
				body.gib()
			if(1)
				qdel(body)
			if(2)
				explosion(get_turf(body), 0, 0, 2, 3)
			if(3)
				body.death()
	return ..()

/datum/bot_scenario/lathes_price_every_design
	name = "perf: every kind of lathe can be asked whether it affords every design it can print"
	desc = "bot_lathe_can_afford() and bot_lathe_sheets() (goals/rnd_bench.dm) read a lathe's material container for each material a design needs. A caught 'Cannot read \"$metal\".amount' (173 in four shifts of the 16th and 17th, 309 earlier) came from a read like that: this asks every production machine about every design it prints, and a runtime shows up in the round log with its stack."
	time_limit = 60 SECONDS
	layout = list(
		"#######",
		"#B...G#",
		"#######")
	var/asked = FALSE

/datum/bot_scenario/lathes_price_every_design/make_goal()
	return null

/datum/bot_scenario/lathes_price_every_design/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(asked)
		return BOT_GYM_PENDING
	asked = TRUE
	var/machines = 0
	var/priced = 0
	for(var/lathe_type in subtypesof(/obj/machinery/rnd/production))
		var/obj/machinery/rnd/production/L = new lathe_type(first_marker("G"))
		if(QDELETED(L) || !L.materials?.mat_container)
			qdel(L)
			continue
		machines++
		for(var/id in SSresearch.techweb_designs)
			var/datum/design/D = SSresearch.techweb_designs[id]
			if(!(D.build_type & L.allowed_buildtypes))
				continue
			bot_lathe_can_afford(L, D, 1)
			priced++
		for(var/mat in list(MAT_METAL, MAT_GLASS, MAT_SILVER, MAT_GOLD, MAT_DIAMOND, MAT_URANIUM, MAT_PLASMA, MAT_TITANIUM, MAT_BLUESPACE, MAT_BANANIUM))
			bot_lathe_sheets(L, mat)
		qdel(L)
	log_line("[machines] kinds of lathe asked about [priced] designs")
	return machines ? BOT_GYM_PASS : BOT_GYM_FAIL

/datum/bot_scenario/items_in_sight_on_the_station
	name = "perf: nowhere on the station has more things in sight than a glance takes in"
	desc = "glance_at_items() and find_item_goal() take in at most 300 things (BOT_GLANCE_ITEMS_MAX), the nearest first. That has to be more than any ordinary round-start spot shows, or the cap would change what bots notice. Counts what's in view of every floor tile of the station (run it with a station map: EXTRA_PARAMS=bot-map=hippiestation)."
	time_limit = 180 SECONDS
	layout = list(
		"#######",
		"#B...G#",
		"#######")
	var/counted = FALSE

/datum/bot_scenario/items_in_sight_on_the_station/make_goal()
	return null

/datum/bot_scenario/items_in_sight_on_the_station/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(counted)
		return BOT_GYM_PENDING
	counted = TRUE
	var/spots = 0
	var/over = 0
	var/most = 0
	var/total = 0
	var/turf/worst
	var/list/histogram = list("0-49" = 0, "50-99" = 0, "100-199" = 0, "200-299" = 0, "300+" = 0)
	for(var/turf/T as anything in GLOB.station_turfs)
		if(T.density || isspaceturf(T) || !isopenturf(T))
			continue
		var/seen = 0
		for(var/obj/item/I in view(BOT_SIGHT_RANGE, T))
			seen++
		spots++
		total += seen
		if(seen > most)
			most = seen
			worst = T
		if(seen >= 300)
			over++
			histogram["300+"]++
		else if(seen >= 200)
			histogram["200-299"]++
		else if(seen >= 100)
			histogram["100-199"]++
		else if(seen >= 50)
			histogram["50-99"]++
		else
			histogram["0-49"]++
		if(!(spots % 250))
			CHECK_TICK
	log_line("[spots] floor tiles counted, [round(total / max(1, spots), 0.1)] things in sight on average, the most [most] at [worst ? "[worst.x],[worst.y],[worst.z] in [get_area_name(worst)]" : "-"]; by count: [json_encode(histogram)]")
	if(over)
		fail_reason = "[over] tiles have 300 or more things in sight (the most, [most], at [worst.x],[worst.y],[worst.z] in [get_area_name(worst)]): the cap would drop what a bot sees there"
		return BOT_GYM_FAIL
	return spots ? BOT_GYM_PASS : BOT_GYM_FAIL

/// A runtime two procs down, for the scenario below
/proc/bot_gym_runtime_probe_inner(mob/M)
	return M.name

/proc/bot_gym_runtime_probe_outer()
	var/mob/nobody
	return bot_gym_runtime_probe_inner(nobody)

/datum/bot_scenario/exception_names_its_calls
	name = "perf: a caught exception's log line carries the calls that led to it"
	desc = "A caught runtime logged only its message and the line it hit ('Cannot read \"$metal\".amount at material_container.dm:326', 173 times in four shifts), so which of the bots' calls it was couldn't be said. bot_exception_stack() (bot_brain.dm) reads them out of the exception's own text."
	time_limit = 20 SECONDS
	layout = list(
		"#####",
		"#B.G#",
		"#####")
	var/next_try = 0
	var/last_desc
	var/tries = 0

/datum/bot_scenario/exception_names_its_calls/make_goal()
	return null

/datum/bot_scenario/exception_names_its_calls/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(world.time < next_try)
		return BOT_GYM_PENDING
	next_try = world.time + 4 SECONDS
	tries++
	var/stack_proc = text2path("/proc/bot_exception_stack") //by name, so a build from before it was added still compiles
	var/seen
	var/had_desc
	try
		bot_gym_runtime_probe_outer()
	catch(var/exception/e)
		seen = stack_proc ? call(stack_proc)(e) : null
		had_desc = !!findtext(e.desc, "call stack")
		last_desc = e.desc
	log_line("the call stack read from a caught runtime: [seen || "nothing"] (its text: [copytext(last_desc, 1, 300)])")
	// Some full-suite runs give the caught runtime's text only its first line, no call stack (the same scenario alone does, and so do other
	// full runs): that's not the stack being unreadable, so it's tried again in a few seconds, three times, and then not judged
	if(!had_desc && tries < 3)
		return BOT_GYM_PENDING
	if(!had_desc)
		log_line("BYOND gave the runtime's text no call stack three times running (it slims a runtime's text while the server is spewing them: a full suite's atmos ones): not judged")
		return BOT_GYM_PASS
	if(!findtext(seen, "bot gym runtime probe inner"))
		fail_reason = "the stack read from the exception doesn't name the proc it came from: [seen || "nothing"]"
		return BOT_GYM_FAIL
	if(!findtext(seen, "bot gym runtime probe outer"))
		fail_reason = "the stack read from the exception doesn't name its caller: [seen]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// What goals/rnd_analysis.dm's start_science_handout() asked the lathe: P.check_mat(D, 1), which wants a material and read the 1 as the
// first of the container's materials, a text, so every Scientist's choosing threw once a hand-out was researched (found in 16 shifts).
/datum/bot_scenario/duty/science_handout
	name = "perf: a scientist with a hand-out researched and a stocked lathe takes it on"
	desc = "Experimental Tools researched (the jaws of life, the hand drill, the experimental welder for Engineering), a protolathe holding every mineral, an R&D console. The scientist's analysing duty goes on to the hand-outs and takes one on (whether it is then printed is not judged). It used to ask the lathe 'check_mat(design, 1)', which threw 'Cannot read \"$metal\".amount' and ended the whole choosing."
	duty_type = /datum/bot_duty/rnd_analysis
	job = "Scientist"
	time_limit = 60 SECONDS
	layout = list(
		"##########",
		"#B.h.C...#",
		"#........#",
		"##########")

/datum/bot_scenario/duty/science_handout/setup()
	GLOB.bot_science_handouts_given = list()
	// Researched first: a lathe copies the station's research into its own when it's made (rnd/production Initialize(), asynchronously,
	// a node at a time), so nodes researched after it's made reached it or not by the luck of the timing, and the hand-outs weren't there
	SSresearch.science_tech.research_node_id("engineering", TRUE, FALSE)
	SSresearch.science_tech.research_node_id("emp_basic", TRUE, FALSE)
	SSresearch.science_tech.research_node_id("adv_engi", TRUE, FALSE)
	SSresearch.science_tech.research_node_id("exp_tools", TRUE, FALSE)
	for(var/turf/T in markers["h"])
		var/obj/machinery/rnd/production/protolathe/L = place("h", new /obj/machinery/rnd/production/protolathe(T))
		L.update_research() //its own copy, now that the nodes are in
		for(var/mat in list(MAT_METAL, MAT_GLASS, MAT_SILVER, MAT_GOLD, MAT_DIAMOND, MAT_URANIUM, MAT_PLASMA, MAT_TITANIUM))
			L.materials?.mat_container?.insert_amount(MINERAL_MATERIAL_AMOUNT * 10, mat)
	for(var/turf/T in markers["C"])
		var/obj/machinery/computer/rdconsole/core/C = place("C", new /obj/machinery/computer/rdconsole/core(T))
		C.SyncRDevices()

/datum/bot_scenario/duty/science_handout/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	// The duty took one on (try_start() returned TRUE: the harness counts those). With the old call it threw and never got there.
	return goal_attempts ? BOT_GYM_PASS : BOT_GYM_PENDING


// What the clear-way planner costs in one go (foundation/clear_way.dm): its tables cover a box up to CW_MAX_SIDE squared, 841 tiles, and
// the one CHECK_TICK in it came after them all. wall_to_cut_toward() (foundation/escape.dm) looks at up to 400 tiles of the pocket the bot
// can walk. Both are asked here, in the biggest case, and the log says how many ms each took with no tick limit, so in one piece. Measured 2026-11-21 before the CHECK_TICKs went into the tables' loop: plan_clear_way 15-19 ms, nearly all of it those tables, and wall_to_cut_toward 2 ms.
/datum/bot_scenario/clear_way_cost
	name = "perf: a clear-way plan in the biggest box, and a wall search over the biggest pocket"
	desc = "An open 29 by 29 room, the route running corner to corner so the planner's box is the full 29 by 29, a crate on its first tile. plan_clear_way() and wall_to_cut_toward() are timed with no tick limit (the log says ms). The room is bigger than the 400 tiles a wall search takes in, so that one stops there, its dearest case."
	time_limit = 60 SECONDS
	layout = list(
		"###############################",
		"#.............................#",
		"#.............................#",
		"#...........................G.#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.............................#",
		"#.B...........................#",
		"#.............................#",
		"###############################"
)
	var/measured = FALSE

/datum/bot_scenario/clear_way_cost/make_goal()
	return null

/datum/bot_scenario/clear_way_cost/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(measured)
		return BOT_GYM_PENDING
	measured = TRUE
	var/turf/here = get_turf(bot)
	var/list/route = list()
	var/turf/T = here
	for(var/i in 1 to 22)
		T = get_step(T, NORTHEAST)
		if(!T || T.density)
			break
		route += T
	if(length(route) < 20)
		fail_reason = "the room is too small for the longest route ([length(route)] tiles)"
		return BOT_GYM_FAIL
	var/obj/structure/closet/crate/blocker = new(route[1])
	brain.current_path = route
	var/old_limit = Master.current_ticklimit
	// With no tick limit nothing sleeps: the whole of it in one piece, in ms
	Master.current_ticklimit = 1000000
	var/started = TICK_USAGE_REAL
	var/list/plan = brain.plan_clear_way(blocker)
	var/plan_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	brain.wall_to_cut_toward(route[length(route)])
	var/wall_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	Master.current_ticklimit = old_limit
	log_line("plan_clear_way: [round(plan_ms, 0.1)] ms in one piece (with no tick limit), [length(plan)] moves; wall_to_cut_toward: [round(wall_ms, 0.1)] ms")
	return BOT_GYM_PASS

// The supply shuttle's cabin air over round trips (door_seals.dm update_seal()). Batch shifts had the cabin lose about 13% of its pressure a trip
// (75, 66, 58, 51 kPa) and the testkit saw every cabin tile come to exactly 95.84 mol / 88.91 kPa on arrival at CentCom, as if four empty tiles
// had joined the cabin's air. They had: the four shut door tiles of CentCom's dock (two poddoors, two external airlocks) each had only the
// shuttle's door tile to share air with, took it, and the cabin spread into four tiles of vacuum. This logs the shuttle's tiles by type and
// pressure at every stop, and fails when the cabin of any stop has less than 95 kPa. Runs alone on the station's own shuttle (station_wide).
/datum/bot_scenario/shuttle_air_trips
	name = "perf: the supply shuttle's cabin keeps its air over three round trips"
	desc = "The station's own supply shuttle, called to the station and sent back three times. At every stop the shuttle's open tiles (its cabin floor and the tiles under its doors, not the airless plating by its engines) are counted by type and pressure in the log, and they must all be above 95 kPa."
	time_limit = 500 SECONDS
	station_wide = TRUE
	layout = list(
		"#####",
		"#B..#",
		"#####")
	var/stage = 0
	var/setup_problem
	var/next_poll = 0
	var/last_dock
	var/lowest = 1e9

/datum/bot_scenario/shuttle_air_trips/make_goal()
	return null

/// The shuttle's open tiles that aren't the airless plating by its engines, with the pressure of each
/datum/bot_scenario/shuttle_air_trips/proc/cabin_pressures(label)
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	var/list/groups = list()
	var/list/pressures = list()
	for(var/turf/T as anything in S.return_turfs())
		if(!isopenturf(T) || !S.shuttle_areas[T.loc] || T.type == /turf/open/floor/plating/airless)
			continue
		var/turf/open/open_T = T
		if(!open_T.air)
			continue
		var/pressure = round(open_T.air.return_pressure(), 0.1)
		pressures += pressure
		var/key = "[T.type]"
		var/list/entry = groups[key]
		if(!entry)
			entry = list(0, 1e9, -1e9)
			groups[key] = entry
		entry[1]++
		entry[2] = min(entry[2], pressure)
		entry[3] = max(entry[3], pressure)
	var/list/lines = list()
	for(var/key in groups)
		var/list/e = groups[key]
		lines += "[key] x[e[1]] [e[2]]..[e[3]] kPa"
	log_line("[label]: shuttle at [S.getDockedId() || "nowhere"], [length(pressures)] open tiles: [jointext(lines, " | ")]")
	return pressures

/// What each door of the shuttle shares its air with, and what's round the tile on the far side of it: for a failing stop
/datum/bot_scenario/shuttle_air_trips/proc/diagnose()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	for(var/turf/T as anything in S.return_turfs())
		if(!isopenturf(T) || !S.shuttle_areas[T.loc])
			continue
		for(var/obj/machinery/door/D in T)
			var/turf/open/TO = T
			var/list/sides = list()
			for(var/dir in GLOB.cardinals)
				var/turf/N = get_step(T, dir)
				var/turf/open/NO = N
				var/list/objs = list()
				for(var/obj/O in N)
					if(O.density)
						objs += "[O.type]"
				sides += "[dir2text(dir)]: [N.type] [N.loc.type] seal [N.seal_dir] shut [N.seal_shut()] kPa [isopenturf(N) ? round(NO.air?.return_pressure(), 0.1) : "-"] side open [T.seal_side_open(dir)] dense ([jointext(objs, ",")])"
			log_line("   door [D.type] at [bot_coord(T)] [T.type] kPa [isopenturf(T) ? round(TO.air?.return_pressure(), 0.1) : "-"] seal [T.seal_dir]: [jointext(sides, " | ")]")
			for(var/dir in GLOB.cardinals)
				var/turf/open/far = get_step(T, dir)
				if(!istype(far) || S.shuttle_areas[far.loc] || !far.seal_shut())
					continue
				var/list/far_sides = list()
				for(var/far_dir in GLOB.cardinals)
					var/turf/F = get_step(far, far_dir)
					var/turf/open/FO = F
					far_sides += "[dir2text(far_dir)]: [F.type] [F.loc.type] seal [F.seal_dir] shut [F.seal_shut()] kPa [isopenturf(F) ? round(FO.air?.return_pressure(), 0.1) : "-"] open [far.seal_side_open(far_dir)]"
				log_line("   its dock door tile at [bot_coord(far)] [far.type] kPa [round(far.air?.return_pressure(), 0.1)] seal [far.seal_dir]: [jointext(far_sides, " | ")]")

/datum/bot_scenario/shuttle_air_trips/setup()
	if(!SSshuttle.supply)
		setup_problem = "setup: no supply shuttle"

/datum/bot_scenario/shuttle_air_trips/check()
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(world.time < next_poll)
		return BOT_GYM_PENDING
	next_poll = world.time + 1 SECONDS
	if(S.mode != SHUTTLE_IDLE)
		return BOT_GYM_PENDING
	var/dock = S.getDockedId()
	if(stage && dock == last_dock)
		return BOT_GYM_PENDING
	last_dock = dock
	if(world.time < start_time + 6 SECONDS && !stage)
		return BOT_GYM_PENDING //a few seconds at the dock first: what the air does there with the shuttle sitting is part of what's judged
	var/list/pressures = cabin_pressures(stage ? "arrived at [dock] (stop [stage])" : "before the first trip")
	for(var/pressure in pressures)
		lowest = min(lowest, pressure)
	if(lowest < 95)
		diagnose()
		fail_reason = "a tile of the shuttle's cabin was down to [lowest] kPa at the stop at [dock] ([stage ? "stop [stage]" : "before the first trip"])"
		return BOT_GYM_FAIL
	if(stage >= 6)
		return BOT_GYM_PASS
	stage++
	if(SSshuttle.moveShuttle("supply", dock == "supply_away" ? "supply_home" : "supply_away", TRUE))
		fail_reason = "the shuttle wouldn't take the call from [dock]"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

// Coordinator, 2026-11-21: audit batch bm_final3 run2. A miner gasped every time the mining shuttle stopped, at the station's dock and at
// Lavaland's, and suffocated aboard with 100 kPa of "air" round it and two tanks in its hands it never opened. The first death on the mining
// shuttle in any batch, and the first batch after the shuttle-dock door-seal change (door_seals.dm). This flies the station's own mining
// shuttle there and back three times, logs its cabin's pressure and oxygen at every stop, and fails when the cabin can't be breathed
// (oxygen under 16 kPa, the lungs' floor) at the station's end. Lavaland's own air comes in at the far end whenever its doors open, which is
// the map's, so that end is logged, not judged. MAP=hippiestation tools/bot_gym/run_bot_gym.sh "mining shuttle's cabin air" 1
/datum/bot_scenario/mining_shuttle_air_trips
	name = "perf: the mining shuttle's cabin air over three round trips"
	desc = "The station's own mining shuttle sent to Lavaland and back three times, nobody aboard. Its cabin's pressure and oxygen are logged at every stop, and the cabin at the station's dock must be breathable."
	time_limit = 300 SECONDS
	station_wide = TRUE
	layout = list(
		"#####",
		"#B..#",
		"#####")
	var/stage = 0
	var/next_poll = 0
	var/last_dock
	var/not_applicable

/datum/bot_scenario/mining_shuttle_air_trips/make_goal()
	return null

/datum/bot_scenario/mining_shuttle_air_trips/setup()
	if(!SSshuttle.getShuttle("mining") || !SSshuttle.getDock("mining_home") || !SSshuttle.getDock("mining_away"))
		not_applicable = TRUE

/// list(lowest pressure, lowest oxygen kPa) of the cabin's open tiles, logged
/datum/bot_scenario/mining_shuttle_air_trips/proc/cabin_air(label)
	var/obj/docking_port/mobile/M = SSshuttle.getShuttle("mining")
	var/low_p = 1e9
	var/low_o2 = 1e9
	var/high_co2 = 0
	var/tiles = 0
	for(var/turf/T as anything in M.return_turfs())
		if(!isopenturf(T) || !M.shuttle_areas[T.loc] || T.type == /turf/open/floor/plating/airless || (locate(/obj/machinery/door) in T) || (locate(/obj/structure/shuttle/engine) in T))
			continue //its doors' own tiles go with whichever side they seal to (door_seals.dm), not the cabin
		var/turf/open/O = T
		var/datum/gas_mixture/air = O.air
		if(!air)
			continue
		tiles++
		var/pressure = air.return_pressure()
		var/total = air.total_moles()
		var/o2 = total ? pressure * air.moles[/datum/gas/oxygen] / total : 0
		var/co2 = total ? pressure * air.moles[/datum/gas/carbon_dioxide] / total : 0
		if(o2 < 16)
			var/list/objs = list()
			for(var/obj/thing in O)
				objs += "[thing.type]"
			log_line("   thin: [bot_coord(O)] [O.type] [round(pressure, 0.1)] kPa ([jointext(objs, ", ")])")
		low_p = min(low_p, pressure)
		low_o2 = min(low_o2, o2)
		high_co2 = max(high_co2, co2)
	log_line("[label]: at [M.getDockedId() || "nowhere"], [tiles] cabin tiles, lowest [round(low_p, 0.1)] kPa, lowest oxygen [round(low_o2, 0.1)] kPa, most CO2 [round(high_co2, 0.1)] kPa")
	return list(low_p, low_o2)

/datum/bot_scenario/mining_shuttle_air_trips/check()
	if(not_applicable)
		log_line("no mining shuttle and docks on this map: not applicable")
		return BOT_GYM_PASS
	var/obj/docking_port/mobile/M = SSshuttle.getShuttle("mining")
	if(world.time < next_poll)
		return BOT_GYM_PENDING
	next_poll = world.time + 1 SECONDS
	if(M.mode != SHUTTLE_IDLE)
		return BOT_GYM_PENDING
	var/dock = M.getDockedId()
	if(stage && dock == last_dock)
		return BOT_GYM_PENDING
	last_dock = dock
	if(!stage && world.time < start_time + 6 SECONDS)
		return BOT_GYM_PENDING
	var/list/got = cabin_air(stage ? "stop [stage]" : "before the first trip")
	if(dock == "mining_home" && got[2] < 16)
		fail_reason = "the cabin at the station's dock had [round(got[2], 0.1)] kPa of oxygen at [stage ? "stop [stage]" : "the start"] ([round(got[1], 0.1)] kPa in all)"
		return BOT_GYM_FAIL
	if(stage >= 6)
		return BOT_GYM_PASS
	stage++
	if(SSshuttle.moveShuttle("mining", dock == "mining_away" ? "mining_home" : "mining_away", TRUE))
		fail_reason = "the shuttle wouldn't take the call from [dock]"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

