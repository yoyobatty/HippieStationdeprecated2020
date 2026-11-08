// Code sweep - one of everything, to see what breaks.
//
// A Bot Shift or the gym only reaches the code a crew reaches, so a clean runtime log says little: most of the game
// was never run. This runs the rest, once each, in a headless boot, and lists what went wrong:
//   atoms      every /atom/movable made and deleted (tg's create_and_destroy unit test), then the garbage collector
//              is left to say what wouldn't go away
//   turfs      every /turf changed to and back
//   reagents   every reagent metabolised in a body, then splashed on a person, a floor and an object
//   reactions  every chemical reaction set off in a beaker, which also says which ones can't happen
//   crafting   every crafting recipe made from its own ingredients
//   ui         every object's tgui data built for a person standing next to it
//   events     every random event, fired on the live station (not with the others: it wrecks the place)
//   acts       every obj and living mob, a fresh one for each of blasts (3), EMPs (2), fire, acid, a tesla's zap, a shot, a blob,
//              radiation, an emag and a singularity, each timed: the slowest are listed (not with the others: ~150,000 of them)
//   uses       every obj and living mob, a fresh one for each of an empty hand, a crowbar, a wrench, a lit welder, a screwdriver,
//              wirecutters and a multitool in the hand of somebody with all access, and every item picked up and used in the hand;
//              do_after() doesn't wait. Timed like acts (not with the others either: ~90,000)
// reagents, reactions and events are timed too: each sweep's slowest are listed.
//
// Run:      tools/code_sweep/run_code_sweep.sh [atoms,turfs,reagents,reactions,crafting,ui]
// Results:  data/code_sweep/report.txt, and progress.txt with each type as it was reached: the last line is the one to
//           blame when the server goes down mid-sweep (the script notes it, skips it and carries on).
// Boot:     dd.exe hippiestation.dmb -trusted -invisible -params "code-sweep=atoms&timewarp=0"
//           code-sweep-skip=N starts N types into the first sweep given.

#define CODE_SWEEP_DIR "data/code_sweep/"
/// The room everything is made in.
#define CODE_SWEEP_ARENA_SIZE 15

GLOBAL_DATUM(code_sweep, /datum/code_sweep)

/proc/run_code_sweep(kinds)
	Master.sleep_offline_after_initializations = FALSE
	world.sleep_offline = FALSE
	CONFIG_SET(flag/allow_random_events, FALSE)
	GLOB.master_mode = "extended" // data/mode.txt is whatever the last real round left there, and most modes won't start with nobody playing
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	SSticker.can_fire = FALSE //a round that ends reboots the world, and the sweep starts again from nothing
	var/datum/code_sweep/sweep = new(kinds)
	GLOB.code_sweep = sweep
	sweep.run_sweeps()
	GLOB.code_sweep = null
	log_world("CODE SWEEP: done")
	Master.Shutdown()
	qdel(world)

/datum/code_sweep
	var/list/kinds
	var/datum/turf_reservation/reservation
	/// The turf things are made on.
	var/turf/spot
	/// What's being tried right now, for pinning a runtime on it.
	var/current
	var/kind
	/// "file:line" -> list("count", "error", "kinds", "paths")
	var/list/runtime_sites = list()
	var/runtime_count = 0
	/// Sweep -> lines to report: things that aren't runtimes but aren't right.
	var/list/findings = list()
	var/list/tried = list()
	var/started
	var/skip = 0

/datum/code_sweep/New(kinds)
	src.kinds = splittext("[kinds]" == "1" ? "atoms,turfs,reagents,reactions,crafting,ui" : "[kinds]", ",")
	skip = text2num(world.params[CODE_SWEEP_SKIP_PARAMETER]) || 0

/datum/code_sweep/proc/run_sweeps()
	started = REALTIMEOFDAY
	reservation = SSmapping.RequestBlockReservation(CODE_SWEEP_ARENA_SIZE, CODE_SWEEP_ARENA_SIZE)
	if(!reservation)
		log_world("CODE SWEEP: no room for the arena")
		return
	for(var/turf/T as anything in reservation.reserved_turfs)
		T.ChangeTurf(/turf/open/floor/plating)
	spot = locate(reservation.bottom_left_coords[1] + 7, reservation.bottom_left_coords[2] + 7, reservation.bottom_left_coords[3])
	// What the boot and the map left behind isn't the sweep's doing.
	SSgarbage.items = list()
	SSatoms.BadInitializeCalls = list()
	for(var/sweep in kinds)
		kind = sweep
		tried[kind] = 0
		log_world("CODE SWEEP: [kind]")
		call(src, "sweep_[kind]")()
		skip = 0
		clear_arena()
	kind = "garbage"
	current = null
	wait_for_garbage()
	write_report()

/// Notes where the sweep has got to, for when the next thing takes the server down.
/datum/code_sweep/proc/reach(path)
	// Some things end the round just by existing (Nar'Sie, a blob overmind). They're allowed to, but the sweep goes on.
	if(SSticker.force_ending)
		SSticker.force_ending = FALSE
		note("[current] ended the round by being made")
	current = path
	tried[kind]++
	text2file("[kind] [tried[kind]] [path]", "[CODE_SWEEP_DIR]progress.txt")
	if(!(tried[kind] % 500))
		log_world("CODE SWEEP: [kind] [tried[kind]], [path]")
	return tried[kind] > skip

/datum/code_sweep/proc/note(text)
	if(!findings[kind])
		findings[kind] = list()
	findings[kind] += text

/// Called from world/Error() for every runtime during a sweep. Runs inside the error handler: plain list work only.
/datum/code_sweep/proc/note_runtime(exception/E)
	runtime_count++
	var/site = "[E.file]:[E.line]"
	var/list/entry = runtime_sites[site]
	if(!entry)
		entry = list("count" = 0, "error" = "[E.name]", "kinds" = list(), "paths" = list())
		runtime_sites[site] = entry
	entry["count"]++
	var/list/seen_kinds = entry["kinds"]
	seen_kinds[kind] = TRUE
	var/list/paths = entry["paths"]
	if(length(paths) < 12 && !(current in paths))
		paths += current

/// Everything in the room goes, and the floor comes back if something took it.
/datum/code_sweep/proc/clear_arena()
	for(var/turf/T as anything in reservation.reserved_turfs)
		if(!isfloorturf(T))
			T.ChangeTurf(/turf/open/floor/plating)
		for(var/atom/movable/A as anything in T)
			if(!QDELETED(A) && !istype(A, /atom/movable/lighting_object))
				qdel(A, force = TRUE)
		CHECK_TICK

/// A person to use things on.
/datum/code_sweep/proc/make_person()
	return new /mob/living/carbon/human(spot)

// ---------------------------------------------------------------------------------------------
// Atoms
// ---------------------------------------------------------------------------------------------

/// Atoms that can't be made on their own, or that would take the test down with them. Anything else that fails is a finding.
/datum/code_sweep/proc/uncreatable_atoms()
	. = list()
	. += typesof(/atom/movable/lighting_object) //one to a turf, the turf's own
	. += typesof(/obj/screen) //pieces of a client's HUD
	. += typesof(/mob/dead) //a lobby or a ghost has no business here without a client
	. += typesof(/obj/docking_port) //shuttle plumbing
	. += typesof(/obj/singularity) //eats the arena and everything else
	. += typesof(/obj/machinery/doomsday_device)
	. += typesof(/obj/effect/landmark) //the station's own spawn lists; nothing to these but a list entry
	. += typesof(/mob/living/carbon) - typesof(/mob/living/carbon/human) - typesof(/mob/living/carbon/monkey) - typesof(/mob/living/carbon/alien) //template

/datum/code_sweep/proc/sweep_atoms()
	var/list/before = spot.contents.Copy()
	for(var/path in subtypesof(/atom/movable) - uncreatable_atoms())
		if(!reach(path))
			continue
		var/atom/movable/made = new path(spot)
		if(!QDELETED(made))
			qdel(made, force = TRUE)
		made = null
		var/list/left = spot.contents - before
		for(var/atom/movable/A as anything in left)
			qdel(A, force = TRUE)
		left = null
		if(!(tried[kind] % 50))
			clear_arena()
		CHECK_TICK

// ---------------------------------------------------------------------------------------------
// Turfs
// ---------------------------------------------------------------------------------------------

/datum/code_sweep/proc/sweep_turfs()
	var/list/skipped = typesof(/turf/open/space/transit) + typesof(/turf/baseturf_skipover) + /turf/baseturf_bottom
	for(var/path in subtypesof(/turf) - skipped)
		if(!reach(path))
			continue
		spot.ChangeTurf(path)
		spot.ChangeTurf(/turf/open/floor/plating)
		if(!(tried[kind] % 50))
			clear_arena()
		CHECK_TICK

// ---------------------------------------------------------------------------------------------
// Reagents and reactions
// ---------------------------------------------------------------------------------------------

/datum/code_sweep/proc/sweep_reagents()
	for(var/path in subtypesof(/datum/reagent))
		if(!reach(path))
			continue
		var/time = world.time
		var/mark = TICK_USAGE_REAL
		// In the blood.
		var/mob/living/carbon/human/H = make_person()
		H.reagents.add_reagent(path, 30)
		for(var/i in 1 to 4)
			if(QDELETED(H) || !H.reagents)
				break
			H.reagents.metabolize(H, can_overdose = TRUE)
		if(!QDELETED(H))
			qdel(H, force = TRUE)
		// Out of a beaker, every way there is, onto a person, the floor and a thing.
		var/obj/item/reagent_containers/glass/beaker/large/B = new(spot)
		B.reagents.add_reagent(path, 30)
		var/obj/item/toy/crayon/red/thing = new(spot)
		for(var/method in list(TOUCH, VAPOR, INGEST, INJECT, PATCH))
			var/mob/living/carbon/human/target = make_person()
			if(!QDELETED(B))
				B.reagents.reaction(target, method)
			if(!QDELETED(target))
				qdel(target, force = TRUE)
		if(!QDELETED(B))
			B.reagents.reaction(spot, TOUCH)
		if(!QDELETED(B) && !QDELETED(thing))
			B.reagents.reaction(thing, TOUCH)
		if(world.time == time)
			note_cost("[path]", TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark))
		clear_arena()
		CHECK_TICK

/datum/code_sweep/proc/sweep_reactions()
	for(var/path in subtypesof(/datum/chemical_reaction))
		var/datum/chemical_reaction/R = new path
		if(!length(R.required_reagents))
			continue //a template
		if(!reach(path))
			continue
		if(R.required_container)
			continue //a slime core and the like: these want more than a beaker
		var/temperature = R.required_temp ? R.required_temp + (R.is_cold_recipe ? -1 : 1) : T20C
		var/obj/item/reagent_containers/glass/beaker/bluespace/B = new(spot)
		B.reagents.chem_temp = max(temperature, TCMB)
		// What Hippie's chem machines do to a beaker (a pressuriser, a radioactive disintegrator, a centrifuge...).
		B.reagents.chem_pressure = R.pressure_required
		B.reagents.chem_radioactivity = R.radioactivity_required
		B.reagents.chem_bluespaced = R.bluespace_recipe
		B.reagents.chem_centrifuged = R.centrifuge_recipe
		for(var/catalyst in R.required_catalysts)
			B.reagents.add_reagent(catalyst, R.required_catalysts[catalyst], reagtemp = B.reagents.chem_temp, no_react = TRUE)
		for(var/reagent in R.required_reagents)
			B.reagents.add_reagent(reagent, R.required_reagents[reagent] * 5, reagtemp = B.reagents.chem_temp, no_react = TRUE)
		var/time = world.time
		var/mark = TICK_USAGE_REAL
		B.reagents.handle_reactions()
		if(world.time == time)
			note_cost("[path]", TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark))
		var/worked = !length(R.results) //what it makes isn't a reagent: nothing to look for
		for(var/result in R.results)
			if(!QDELETED(B) && B.reagents?.get_reagent_amount(result) > 0)
				worked = TRUE
		if(!worked && !QDELETED(B))
			var/still_there = B.reagents.get_reagent_amount(R.required_reagents[1])
			note("[path] made nothing in a beaker at [round(temperature)] K[still_there ? "" : " (its ingredients went on something else)"]")
		clear_arena()
		CHECK_TICK

// ---------------------------------------------------------------------------------------------
// Crafting
// ---------------------------------------------------------------------------------------------

/datum/code_sweep/proc/sweep_crafting()
	for(var/path in subtypesof(/datum/crafting_recipe))
		var/datum/crafting_recipe/R = new path
		if(!R.result)
			continue
		if(!reach(path))
			continue
		var/mob/living/carbon/human/H = make_person()
		var/datum/component/personal_crafting/crafting = H.GetComponent(/datum/component/personal_crafting) || H.AddComponent(/datum/component/personal_crafting)
		for(var/needed in R.reqs)
			make_ingredient(needed, R.reqs[needed])
		for(var/needed in R.chem_catalysts)
			make_ingredient(needed, R.chem_catalysts[needed])
		for(var/tool in R.tools)
			if(ispath(tool))
				new tool(spot)
			else
				make_tool(tool)
		R.time = 0
		var/outcome = crafting.construct_item(H, R)
		if(outcome)
			note("[path] couldn't be made from what it asks for[outcome]")
		clear_arena()
		CHECK_TICK

/datum/code_sweep/proc/make_ingredient(path, amount)
	if(ispath(path, /datum/reagent))
		var/obj/item/reagent_containers/glass/beaker/bluespace/B = new(spot)
		B.reagents.add_reagent(path, amount, no_react = TRUE)
	else if(ispath(path, /obj/item/stack))
		new path(spot, amount)
	else
		for(var/i in 1 to (amount || 1))
			new path(spot)

/datum/code_sweep/proc/make_tool(behaviour)
	var/static/list/tool_for = list(
		TOOL_CROWBAR = /obj/item/crowbar, TOOL_MULTITOOL = /obj/item/multitool, TOOL_SCREWDRIVER = /obj/item/screwdriver,
		TOOL_WIRECUTTER = /obj/item/wirecutters, TOOL_WRENCH = /obj/item/wrench, TOOL_WELDER = /obj/item/weldingtool/largetank,
		TOOL_ANALYZER = /obj/item/analyzer, TOOL_MINING = /obj/item/pickaxe, TOOL_SHOVEL = /obj/item/shovel)
	var/path = tool_for[behaviour]
	if(path)
		var/obj/item/tool = new path(spot)
		var/obj/item/weldingtool/welder = tool
		if(istype(welder))
			welder.switched_on(null)

// ---------------------------------------------------------------------------------------------
// Machine panels
// ---------------------------------------------------------------------------------------------

/datum/code_sweep/proc/sweep_ui()
	var/mob/living/carbon/human/H = make_person()
	var/list/skipped = uncreatable_atoms() + typesof(/mob)
	for(var/path in subtypesof(/obj) - skipped)
		if(!reach(path))
			continue
		var/obj/made = new path(spot)
		if(!QDELETED(made))
			made.ui_static_data(H)
			if(!QDELETED(made))
				made.ui_data(H)
			if(!QDELETED(made))
				qdel(made, force = TRUE)
		made = null
		if(QDELETED(H) || !isturf(H.loc))
			H = make_person()
		if(!(tried[kind] % 50))
			clear_arena()
			H = make_person()
		CHECK_TICK

// ---------------------------------------------------------------------------------------------
// What the world does to things, timed
// ---------------------------------------------------------------------------------------------

/datum/code_sweep
	/// acts: "path: act" -> ms, for each that took 1 ms or more
	var/list/act_costs = list()
	/// acts: act -> list(ms in all, how many, how many slept)
	var/list/act_totals = list()
	/// acts: "path: act" for each that slept (a do_after, a timer it waited on)
	var/list/act_slept = list()

/// What happens to things in a round without anybody choosing it: blasts, EMPs, fire, acid, a tesla's zap, a shot, a blob, radiation,
/// an emag, a singularity. Each on a fresh one of every obj and living mob, timed: the report lists the slowest, which is what freezes
/// a server when it happens to the wrong thing (a chem dispenser EMP'd by a tesla zap spraying chemicals over 29 tiles took 130 ms,
/// 2026-11-08), and whatever it broke goes in with the runtimes and the garbage like the other sweeps. Only what the act does there
/// and then is timed: an explosion it sets off happens in SSexplosions afterwards.
/datum/code_sweep/proc/sweep_acts()
	var/static/list/acts = list("ex_act 1", "ex_act 2", "ex_act 3", "emp_act heavy", "emp_act light", "fire_act", "acid_act", "tesla", "bullet_act", "blob_act", "rad_act", "emag_act", "singularity_act")
	var/turf/beside = get_step(spot, EAST)
	var/mob/living/carbon/human/H = make_person()
	H.forceMove(beside)
	var/list/before = spot.contents.Copy()
	for(var/path in subtypesof(/obj) + subtypesof(/mob/living) - uncreatable_atoms())
		for(var/act in acts)
			if(!reach("[path]: [act]"))
				continue
			var/atom/movable/made = new path(spot)
			if(QDELETED(made))
				break
			var/time = world.time
			var/mark = TICK_USAGE_REAL
			do_act(made, act, H)
			var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark)
			var/list/totals = act_totals[act]
			if(!totals)
				totals = list(0, 0, 0)
				act_totals[act] = totals
			if(world.time != time)
				totals[3]++
				if(length(act_slept) < 200)
					act_slept += "[path]: [act]"
			else
				totals[1] += ms
				totals[2]++
				if(ms >= 1)
					act_costs["[path]: [act]"] = ms
			if(!QDELETED(made))
				qdel(made, force = TRUE)
			made = null
			for(var/atom/movable/A as anything in spot.contents - before)
				qdel(A, force = TRUE)
			if(QDELETED(H) || H.loc != beside)
				H = make_person()
				H.forceMove(beside)
			if(!(tried[kind] % 50))
				clear_arena()
				H = make_person()
				H.forceMove(beside)
				before = spot.contents.Copy()
			CHECK_TICK

// ---------------------------------------------------------------------------------------------
// What people do to things, timed
// ---------------------------------------------------------------------------------------------

/// Set during the uses sweep: do_after(), do_mob() and do_after_mob() don't wait (code/__HELPERS/mobs.dm)
GLOBAL_VAR_INIT(code_sweep_no_waiting, FALSE)

/datum/code_sweep
	/// Sweep -> list("what: how" -> ms) for each that took 1 ms or more (all but acts, which keep their own)
	var/list/costs = list()
	/// Sweep -> how many slept (waited on something), and the first few
	var/list/sleepers = list()
	/// The use going now and the last one done, for one that sleeps (use_on())
	var/use_serial = 0
	var/use_finished = 0

/datum/code_sweep/proc/note_cost(key, ms)
	if(ms < 1)
		return
	var/list/here = costs[kind]
	if(!here)
		here = list()
		costs[kind] = here
	here[key] = ms

/datum/code_sweep/proc/note_sleeper(key)
	var/list/here = sleepers[kind]
	if(!here)
		here = list()
		sleepers[kind] = here
	here += key

/// A person beside the room's middle, with an ID that opens everything, to use things
/datum/code_sweep/proc/make_user(turf/where)
	var/mob/living/carbon/human/H = new(where)
	var/obj/item/card/id/card = new(H)
	card.access = get_all_accesses() + get_all_centcom_access()
	H.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	return H

/// What a person does with their hands: an empty hand, each of the six tools, and (for an item) picked up and used in the hand. Each on a
/// fresh one of every obj and living mob, timed, with no waiting on do_after(); one that sleeps anyway gets five seconds to finish
/// before the next, so what it does late isn't put down to the next one.
/datum/code_sweep/proc/sweep_uses()
	var/static/list/uses = list("hand", "crowbar", "wrench", "welder", "screwdriver", "wirecutters", "multitool", "in hand")
	var/static/list/tools = list("crowbar" = /obj/item/crowbar, "wrench" = /obj/item/wrench, "welder" = /obj/item/weldingtool/largetank,
		"screwdriver" = /obj/item/screwdriver, "wirecutters" = /obj/item/wirecutters, "multitool" = /obj/item/multitool)
	GLOB.code_sweep_no_waiting = TRUE
	var/turf/beside = get_step(spot, EAST)
	var/mob/living/carbon/human/H = make_user(beside)
	var/list/before = spot.contents.Copy()
	for(var/path in subtypesof(/obj) + subtypesof(/mob/living) - uncreatable_atoms())
		for(var/use in uses)
			if(use == "in hand" && !ispath(path, /obj/item))
				continue
			if(!reach("[path]: [use]"))
				continue
			var/atom/movable/made = new path(spot)
			if(QDELETED(made))
				break
			if(QDELETED(H) || H.loc != beside || H.stat != CONSCIOUS)
				if(!QDELETED(H))
					qdel(H, force = TRUE)
				H = make_user(beside)
			var/obj/item/tool
			if(tools[use])
				var/tool_path = tools[use]
				tool = new tool_path(beside)
				H.put_in_active_hand(tool)
				var/obj/item/weldingtool/welder = tool
				if(istype(welder))
					welder.switched_on(H)
			var/time = world.time
			var/mark = TICK_USAGE_REAL
			var/serial = ++use_serial
			use_on(made, use, H, tool, serial)
			var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark)
			if(use_finished != serial)
				note_sleeper("[path]: [use]")
				var/deadline = world.time + 5 SECONDS
				while(use_finished != serial && world.time < deadline)
					sleep(1)
			else if(world.time == time)
				note_cost("[path]: [use]", ms)
			if(!QDELETED(made))
				qdel(made, force = TRUE)
			made = null
			if(!QDELETED(H))
				for(var/obj/item/held in H.held_items)
					qdel(held, force = TRUE)
			for(var/atom/movable/A as anything in spot.contents - before)
				qdel(A, force = TRUE)
			for(var/atom/movable/A as anything in beside)
				if(A != H && !istype(A, /atom/movable/lighting_object))
					qdel(A, force = TRUE)
			if(!(tried[kind] % 50))
				clear_arena()
				H = make_user(beside)
				before = spot.contents.Copy()
			CHECK_TICK
	GLOB.code_sweep_no_waiting = FALSE

/datum/code_sweep/proc/use_on(atom/movable/A, use, mob/living/carbon/human/H, obj/item/tool, serial)
	set waitfor = FALSE
	switch(use)
		if("hand")
			A.attack_hand(H)
		if("in hand")
			var/obj/item/I = A
			if(H.put_in_active_hand(I))
				I.attack_self(H)
		else
			if(!QDELETED(tool) && tool.loc == H)
				tool.melee_attack_chain(H, A)
	use_finished = serial

/datum/code_sweep/proc/do_act(atom/movable/A, act, mob/living/carbon/human/H)
	switch(act)
		if("ex_act 1")
			A.ex_act(EXPLODE_DEVASTATE)
		if("ex_act 2")
			A.ex_act(EXPLODE_HEAVY)
		if("ex_act 3")
			A.ex_act(EXPLODE_LIGHT)
		if("emp_act heavy")
			A.emp_act(EMP_HEAVY)
		if("emp_act light")
			A.emp_act(EMP_LIGHT)
		if("fire_act")
			A.fire_act(1000, 500)
		if("acid_act")
			A.acid_act(50, 50)
		if("tesla") // what tesla_zap() does to what it hits; the machines' own blast left out, the arena is needed for the next one
			if(isliving(A))
				var/mob/living/L = A
				L.electrocute_act(30, H, 1, tesla_shock = TRUE)
			else if(isobj(A))
				var/obj/O = A
				O.tesla_act(20000, TESLA_OBJ_DAMAGE | TESLA_MOB_DAMAGE, list())
		if("bullet_act")
			var/obj/item/projectile/beam/laser/P = new(get_turf(A))
			P.firer = H
			A.bullet_act(P, BODY_ZONE_CHEST)
			if(!QDELETED(P))
				qdel(P)
		if("blob_act")
			A.blob_act(null)
		if("rad_act")
			A.rad_act(2000)
		if("emag_act")
			A.emag_act(H)
		if("singularity_act")
			A.singularity_act()

// ---------------------------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------------------------

/// Random events only come up by chance, and rarely the rare ones. Each gets ten seconds on the real station, one
/// after the other, so this comes last and what it leaves of the place isn't to be relied on.
/datum/code_sweep/proc/sweep_events()
	for(var/datum/round_event_control/E as anything in SSevents.control)
		if(!reach(E.type))
			continue
		var/time = world.time
		var/mark = TICK_USAGE_REAL
		E.runEvent()
		if(world.time == time)
			note_cost("[E.type]", TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark))
		sleep(10 SECONDS)

// ---------------------------------------------------------------------------------------------
// The garbage collector's say
// ---------------------------------------------------------------------------------------------

/// Everything deleted so far has gone through the collector's queues, or been hard deleted.
/datum/code_sweep/proc/wait_for_garbage()
	SSgarbage.collection_timeout[GC_QUEUE_CHECK] = 10 SECONDS
	log_world("CODE SWEEP: waiting on the garbage collector, [length(SSgarbage.queues[GC_QUEUE_CHECK])] in the queue")
	var/deadline = world.time + 20 MINUTES
	sleep(15 SECONDS)
	while(world.time < deadline && (length(SSgarbage.queues[GC_QUEUE_CHECK]) || length(SSgarbage.queues[GC_QUEUE_HARDDELETE])))
		SSgarbage.next_fire = 1
		sleep(5 SECONDS)

/datum/code_sweep/proc/write_report()
	var/list/lines = list()
	lines += "CODE SWEEP took [round((REALTIMEOFDAY - started) / 600, 0.1)] minutes"
	for(var/sweep in tried)
		lines += "  [sweep]: [tried[sweep]] tried"
	if(length(act_totals))
		lines += ""
		lines += "ACTS, timed (ms; only what happened there and then, the ones that slept left out)"
		for(var/act in act_totals)
			var/list/totals = act_totals[act]
			lines += "  [act]: [totals[2]] done, [round(totals[1], 0.1)] ms in all[totals[3] ? ", [totals[3]] slept" : ""]"
		var/list/slowest = act_costs.Copy()
		sortTim(slowest, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		var/over_10 = 0
		var/over_50 = 0
		for(var/key in slowest)
			if(slowest[key] >= 10)
				over_10++
			if(slowest[key] >= 50)
				over_50++
		lines += "  [over_10] took 10 ms or more, [over_50] 50 ms or more. The slowest:"
		var/shown = 0
		for(var/key in slowest)
			lines += "    [round(slowest[key], 0.1)] ms  [key]"
			if(++shown >= 60)
				break
		if(length(act_slept))
			lines += "  Slept (not timed): [jointext(act_slept, ", ")]"
	for(var/sweep in costs)
		var/list/slowest = costs[sweep]
		sortTim(slowest, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		lines += ""
		lines += "SLOWEST in [sweep] ([length(slowest)] took 1 ms or more; ms, only what happened there and then)"
		var/shown = 0
		for(var/key in slowest)
			lines += "    [round(slowest[key], 0.1)] ms  [key]"
			if(++shown >= 40)
				break
		var/list/slept = sleepers[sweep]
		if(length(slept))
			lines += "  [length(slept)] slept (not timed): [jointext(slept.Copy(1, min(length(slept), 60) + 1), ", ")]"
	lines += ""
	lines += "RUNTIMES: [runtime_count] at [length(runtime_sites)] places"
	var/list/ranked = list()
	for(var/site in runtime_sites)
		var/list/entry = runtime_sites[site]
		ranked += list(list(entry["count"], site, entry))
	sortTim(ranked, GLOBAL_PROC_REF(cmp_code_sweep_count))
	for(var/list/row as anything in ranked)
		var/list/entry = row[3]
		var/list/seen_kinds = entry["kinds"]
		lines += "[row[1]] x [row[2]] ([jointext(seen_kinds, ",")]): [entry["error"]]"
		lines += "    [jointext(entry["paths"], " ")]"
	for(var/sweep in findings)
		lines += ""
		lines += "FINDINGS in [sweep]: [length(findings[sweep])]"
		lines += findings[sweep]
	lines += ""
	lines += "GARBAGE (path: failed to delete softly / qdel()s; no qdel hint; ignored force; slept in Destroy())"
	for(var/path in SSgarbage.items)
		var/datum/qdel_item/item = SSgarbage.items[path]
		if(item.failures || item.no_hint || item.no_respect_force || item.slept_destroy)
			lines += "[item.name]: [item.failures]/[item.qdels]; no hint [item.no_hint]; ignored force [item.no_respect_force]; slept [item.slept_destroy]"
	lines += ""
	lines += "INITIALIZE (bits: 1 qdel'd before Initialize, 2 no Initialize, 4 slept, 8 no hint)"
	for(var/path in SSatoms.BadInitializeCalls)
		lines += "[path]: [SSatoms.BadInitializeCalls[path]]"
	lines += ""
	text2file(jointext(lines, "\n"), "[CODE_SWEEP_DIR]report.txt")

/proc/cmp_code_sweep_count(list/a, list/b)
	return b[1] - a[1]

#undef CODE_SWEEP_ARENA_SIZE
