// Anomalies (the user's ask, 2026-11-12: "full science"): what a scientist does when Central Command announces one.
//
//  - The anomaly's core keeps it going, on a radio frequency and code of its own (effects/anomalies.dm, aSignal). An analyser held to the
//    anomaly reads them out (anomaly/attackby()), a signaller set to the same sends the code, and the anomaly collapses, leaving the core.
//  - The core goes to Science. With the reactive armour shell researched and the materials for it, one is printed and the core goes in it
//    (reactive_armour_shell/attackby()): reactive armour, which goes to Security.
//  - Not the vortex (it eats the floor under whoever goes near) nor the pyroclastic one (fire, and slimes out of it): those are left to
//    burn out on their own, as most players do.

/// Anomalies a scientist goes up to.
GLOBAL_LIST_INIT(bot_anomalies_worth_it, typecacheof(list(/obj/effect/anomaly/flux, /obj/effect/anomaly/grav, /obj/effect/anomaly/bluespace)))

/datum/bot_brain
	var/anomalies_stopped = 0
	var/anomaly_rest_until = 0

/// An anomaly on this level that a scientist would go to, with nobody else already on it.
/datum/bot_brain/proc/anomaly_to_stop()
	for(var/obj/effect/anomaly/A in GLOB.poi_list)
		if(QDELETED(A) || A.z != my_z() || !is_type_in_typecache(A, GLOB.bot_anomalies_worth_it) || !A.aSignal || taken_by_another(A))
			continue
		if(gym_run && get_area(A) != get_area(owner))
			continue
		return A
	return null

/datum/bot_duty/anomaly_response
	name = "dealing with an anomaly"
	jobs = list("Scientist", "Research Director")
	tier = BOT_DUTY_URGENT
	priority = 12
	interval_min = 100
	interval_max = 300

/datum/bot_duty/anomaly_response/try_start(datum/bot_brain/bot)
	if(world.time < bot.anomaly_rest_until || bot.gone_loud())
		return FALSE
	var/obj/effect/anomaly/A = bot.anomaly_to_stop()
	if(A)
		return bot.assign_goal(new /datum/bot_goal/stop_anomaly(A))
	// A core it's carrying: armour of it, if Science can make the shell; otherwise it goes on a Science table for later
	var/obj/item/assembly/signaler/anomaly/core = locate() in bot.owner.GetAllContents(/obj/item/assembly/signaler/anomaly)
	if(core)
		return bot.assign_goal(new /datum/bot_goal/anomaly_armour(core))
	return FALSE

/datum/bot_goal/stop_anomaly
	lawful = TRUE
	exclusive = TRUE
	doing = "dealing with an anomaly"
	var/obj/effect/anomaly/anomaly

/datum/bot_goal/stop_anomaly/New(obj/effect/anomaly/A)
	. = ..()
	anomaly = A
	target = A

/datum/bot_goal/stop_anomaly/resolve_target(datum/bot_brain/bot)
	if(QDELETED(anomaly))
		target = null

/datum/bot_goal/stop_anomaly/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/stop_anomaly/on_give_up(datum/bot_brain/bot)
	bot.anomaly_rest_until = world.time + 2 MINUTES

/datum/bot_goal/stop_anomaly/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	var/mob/living/carbon/human/H = bot.owner
	if(QDELETED(anomaly))
		// Collapsed: the core's where it was, to pick up
		if(step.stage == "signalled")
			for(var/obj/item/assembly/signaler/anomaly/core in range(2, H))
				if(isturf(core.loc))
					bot.anomalies_stopped++
					bot_tally("anomalies stopped")
					bot_log(bot, "ANOMALY: it's down - taking [core]")
					if(!bot.gym_scripted)
						bot_say(H, pick(";Anomaly's down. Got the core.", ";Neutralised the anomaly, bringing the core to Science."))
					return step.fetch(bot, core) == GOAL_STEP_FAIL ? GOAL_STEP_SUCCESS : GOAL_STEP_PENDING
			return GOAL_STEP_SUCCESS
		return GOAL_STEP_FAIL //somebody else, or it burned out
	var/obj/item/analyzer/scanner = locate() in H.GetAllContents(/obj/item/analyzer)
	if(!scanner)
		return get_kit(bot, step, /obj/item/analyzer)
	var/obj/item/assembly/signaler/S
	for(var/obj/item/assembly/signaler/candidate in H.GetAllContents(/obj/item/assembly/signaler))
		if(!istype(candidate, /obj/item/assembly/signaler/anomaly))
			S = candidate
			break
	if(!S)
		return get_kit(bot, step, /obj/item/assembly/signaler)
	switch(step.stage)
		if("start")
			if(!H.Adjacent(anomaly))
				return step.go_to(bot, anomaly)
			if(!bot.ready_in_hand(scanner))
				return GOAL_STEP_FAIL
			bot.use_tool_on(scanner, anomaly) //"...fluctuating along frequency X, code Y"
			step.stage = "read"
			return step.again(bot, 1 SECONDS)
		if("read")
			// What the analyser said, into the signaller, a step back from it, and send
			if(!bot.ready_in_hand(S))
				return GOAL_STEP_FAIL
			bot.telemetry_ui_action(S, "set [format_frequency(anomaly.aSignal.frequency)] / [anomaly.aSignal.code]")
			S.set_frequency(anomaly.aSignal.frequency)
			S.code = anomaly.aSignal.code
			bot.human_pause(S)
			if(QDELETED(anomaly))
				step.stage = "signalled"
				return step.again(bot, 1)
			bot.telemetry_ui_action(S, "send signal")
			usr = H
			S.signal()
			bot_log(bot, "ANOMALY: signalled [anomaly] on [format_frequency(S.frequency)], code [S.code]")
			step.stage = "signalled"
			return step.again(bot, 1 SECONDS)
		if("signalled")
			if(++step.tries > 5)
				return GOAL_STEP_FAIL
			return step.again(bot, 1 SECONDS)
	return GOAL_STEP_FAIL

/// An analyser or a signaller for the job: off the lab's shelves or anywhere its doors let it.
/datum/bot_goal/stop_anomaly/proc/get_kit(datum/bot_brain/bot, datum/bot_step/staged/step, path)
	if(++step.tries > 4)
		return GOAL_STEP_FAIL
	var/datum/bot_goal/acquire_item_type/fetch = new
	fetch.item_type = path
	fetch.lawful = TRUE
	return bot.suspend_goal_for(fetch) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// The core to reactive armour: a shell off Science's protolathe if it's researched and the silo can cover it, the core in it, and the
/// armour to Security (goals/rnd_analysis.dm's hand-outs). With no shell to be had, the core's left on a table in Science.
/datum/bot_goal/anomaly_armour
	lawful = TRUE
	doing = "seeing to an anomaly core"
	var/obj/item/assembly/signaler/anomaly/core

/datum/bot_goal/anomaly_armour/New(obj/item/assembly/signaler/anomaly/C)
	. = ..()
	core = C

/datum/bot_goal/anomaly_armour/resolve_target(datum/bot_brain/bot)
	target = QDELETED(core) ? null : bot.find_science_protolathe() //goals/xeno_extracts.dm

/datum/bot_goal/anomaly_armour/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/anomaly_armour/on_give_up(datum/bot_brain/bot)
	bot.anomaly_rest_until = world.time + 5 MINUTES

/datum/bot_goal/anomaly_armour/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	var/mob/living/carbon/human/H = bot.owner
	var/obj/machinery/rnd/production/protolathe/P = target
	if(QDELETED(core) || QDELETED(P))
		return GOAL_STEP_FAIL
	var/obj/item/reactive_armour_shell/shell = locate() in H.GetAllContents(/obj/item/reactive_armour_shell)
	if(!shell)
		shell = locate() in get_turf(P)
		if(shell)
			return step.fetch(bot, shell)
		var/datum/design/D = SSresearch.techweb_design_by_id("reactive_armour")
		if(step.stage == "start" && D && P.stored_research?.researched_designs["reactive_armour"] && P.check_mat(D, 1))
			step.stage = "printing"
			return bot.suspend_goal_for(new /datum/bot_goal/print_design/for_anomaly(P, D, 1)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if(step.stage == "printing" && ++step.tries < 6)
			return step.again(bot, 2 SECONDS) //on the lathe's tile in a moment
		// No shell to be had: the core on a Science table for when there is
		for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
			if(T.z == bot.my_z() && bot.in_science_rooms(T) && bot.can_walk_lawfully_to(T))
				if(!H.Adjacent(T))
					return step.go_to(bot, T)
				if(!bot.ready_in_hand(core))
					return GOAL_STEP_FAIL
				H.transferItemToLoc(core, get_turf(T))
				bot_log(bot, "ANOMALY: left [core] in [get_area_name(T)] - no reactive armour shell to be had")
				return GOAL_STEP_SUCCESS
		return GOAL_STEP_FAIL
	if(!bot.ready_in_hand(shell))
		return GOAL_STEP_FAIL
	bot.use_tool_on(core, shell) //reactive_armour_shell/attackby(): the shell and the core become the armour
	var/obj/item/clothing/suit/armor/reactive/armour = locate() in H.GetAllContents(/obj/item/clothing/suit/armor/reactive)
	if(!armour)
		armour = locate() in get_turf(H)
	if(!armour)
		return GOAL_STEP_FAIL
	armour.bot_handout_for = /area/security
	bot_log(bot, "ANOMALY: made [armour] - it's for Security")
	bot_tally("reactive armour made")
	return GOAL_STEP_SUCCESS

/datum/bot_goal/print_design/for_anomaly
	doing = "printing a reactive armour shell"
	chain_duty = null

/datum/bot_goal/print_design/for_anomaly/on_success(datum/bot_brain/bot)
	return

/datum/bot_goal/print_design/for_anomaly/on_give_up(datum/bot_brain/bot)
	return
