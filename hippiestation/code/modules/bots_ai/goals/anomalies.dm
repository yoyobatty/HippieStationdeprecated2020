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

// ---------------------------------------------------------------------------------------------
// Space vines
// ---------------------------------------------------------------------------------------------
//
// The Spacevine event grows a vine in a hallway and it spreads from there, some of it worse than a nuisance: hardened vines stand
// across a corridor (density), some drink the oxygen out of a room, some set off a small blast where they spread. Among players it's
// whoever's about with something sharp: the botanist, the janitor, an assistant with a hatchet, an engineer with the axe, and once it's
// all over the halls the officers too. Nobody on the bot crew ever did anything about it (batches show the event is one of the likelier
// at twenty crew: weight 15, from ten players).
//
//  - One who sees them calls it in on the radio, once in a while.
//  - Botanists, janitors and engineers take it on as their business; others by temperament, and everybody once it's grown.
//  - A few at a time, each with the heaviest thing they carry (a vine has 50 integrity, and a sharp edge counts four times over:
//    attacked_by() in spacevine.dm), working along from the nearest vine to the next.
//  - Not Hydroponics' own: that's the botanist's garden.

/// How many bots go at the vines at once.
#define BOT_VINE_CUTTERS 4
/// And how far off they'll go for one.
#define BOT_VINE_RANGE 45
/// Once they're this many, everybody's business.
#define BOT_VINE_EVERYBODYS 25
/// Officers join in at this many.
#define BOT_VINE_OFFICERS 8

/// When somebody last called vines in on the radio.
GLOBAL_VAR_INIT(bot_vines_called_at, -10000)
/// Area -> when somebody last saw vines there. Nobody goes for vines they've not seen or been told of: a bot in Cargo doesn't know the
/// halls in Medbay have them, any more than a person does.
GLOBAL_LIST_EMPTY(bot_vine_reports)
/// How long a sighting stands for.
#define BOT_VINE_KNOWN_FOR (15 MINUTES)

/datum/bot_brain
	/// Not before this, after a go at the vines that came to nothing.
	var/vine_rest_until = 0
	var/next_vine_look = 0
	/// Vines cut this round.
	var/vines_cut = 0

/// The look round the room (bot_witness.dm), and then a look for vines in sight.
/datum/bot_brain/keep_an_eye_out()
	. = ..()
	if(world.time >= next_vine_look && !gym_scripted)
		next_vine_look = world.time + 8 SECONDS
		notice_vines()

/// Vines in sight: they're known to be there, in this room, for a while (the radio call comes with whoever goes to cut them).
/datum/bot_brain/proc/notice_vines()
	if(!length(bot_instances_of(/obj/structure/spacevine)))
		return
	for(var/obj/structure/spacevine/V in view(BOT_SIGHT_RANGE, owner))
		if(bot_vine_worth_cutting(V))
			GLOB.bot_vine_reports[get_area(V)] = world.time
			return

/// Whether anybody's seen vines in this room lately.
/proc/bot_vines_known_in(area/A)
	var/at = GLOB.bot_vine_reports[A]
	return at && world.time < at + BOT_VINE_KNOWN_FOR

/// A vine somebody's business to cut: aboard, and not the botanist's own garden.
/proc/bot_vine_worth_cutting(obj/structure/spacevine/V)
	if(QDELETED(V) || !isturf(V.loc))
		return FALSE
	if(!is_station_level(V.z) && !istype(get_area(V), /area/bot_gym))
		return FALSE
	return !istype(get_area(V), /area/hydroponics)

/// Whether this bot takes the vines on: its job, then its temperament, then how bad it's got.
/datum/bot_brain/proc/cares_about_vines(count)
	var/role = work_role()
	if(role in list("Botanist", "Janitor", "Station Engineer", "Chief Engineer", "Atmospheric Technician"))
		return TRUE
	if(is_security_job())
		return count >= BOT_VINE_OFFICERS
	return diligence >= 0.6 || count >= BOT_VINE_EVERYBODYS

/// What it'd cut a vine with: the best edge or the heaviest thing it's carrying (a vine has 50 integrity, and a sharp edge or a flame does
/// four times what's rolled, attacked_by() in spacevine.dm). Not a gun, a bag, a stack, or anything the Syndicate gave it: an agent
/// doesn't get the sword out for the gardening.
/datum/bot_brain/proc/vine_cutter()
	var/obj/item/best
	var/best_score = 4
	for(var/obj/item/I in owner.GetAllContents())
		if(istype(I, /obj/item/gun) || istype(I, /obj/item/stack) || istype(I, /obj/item/storage/backpack) || HAS_TRAIT(I, TRAIT_NODROP) || is_type_in_typecache(I, GLOB.bot_contraband))
			continue
		if(I.loc == owner && !(I in owner.held_items))
			continue //worn
		var/score = I.force * ((I.is_sharp() || I.damtype == BURN) ? 4 : 1)
		if(score > best_score)
			best = I
			best_score = score
	return best

/// Bots on the vines now (in the Bot Gym only the arena's own).
/datum/bot_brain/proc/vine_cutters_busy()
	. = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B == src || !istype(B.current_goal, /datum/bot_goal/cut_vines))
			continue
		if(gym_run && B.gym_run != gym_run)
			continue
		.++

/// The nearest vine within `range` of it that's worth cutting and it can get to, other than `not`. Null if none.
/datum/bot_brain/proc/vine_near(range, obj/structure/spacevine/not, reach_check = TRUE)
	var/list/found = list() //vine -> how far off
	for(var/obj/structure/spacevine/V as anything in bot_instances_of(/obj/structure/spacevine))
		if(V == not || !bot_vine_worth_cutting(V) || V.z != owner.z)
			continue
		var/dist = get_dist(owner, V)
		if(dist > range || (gym_run && get_area(V) != get_area(owner)) || taken_by_another(V))
			continue
		if(reach_check && !bot_vines_known_in(get_area(V)))
			continue //not seen, nor heard of: only what's a step or two on from the one it's cutting is known
		found[V] = dist
	var/tries = 0
	while(length(found) && tries++ < 6)
		var/obj/structure/spacevine/nearest
		for(var/obj/structure/spacevine/V as anything in found)
			if(!nearest || found[V] < found[nearest])
				nearest = V
		found -= nearest
		if(!reach_check || gym_run || found[nearest] <= 1 || can_walk_lawfully_to(nearest))
			return nearest
	return null

/// From a bot that's looked at the vines: it says so on the radio, unless somebody's just done.
/datum/bot_brain/proc/call_in_vines(obj/structure/spacevine/V, count)
	if(world.time < GLOB.bot_vines_called_at + 4 MINUTES || count < 3 || !can_radio())
		return
	GLOB.bot_vines_called_at = world.time
	var/where = get_area_name(V, TRUE)
	bot_say(owner, ";[pick("Space vines in [where]!", "There's vines growing in [where], somebody cut them back before they spread!", "[capitalize(where)] is full of vines!")]")

/datum/bot_duty/cut_vines
	name = "cutting back the vines"
	tier = BOT_DUTY_URGENT //the work tier comes after the department rounds, which a botanist or an engineer never runs out of
	priority = 5
	interval_min = 150
	interval_max = 400

/datum/bot_duty/cut_vines/try_start(datum/bot_brain/bot)
	var/list/vines = bot_instances_of(/obj/structure/spacevine)
	if(!length(vines) || !length(GLOB.bot_vine_reports) || world.time < bot.vine_rest_until || bot.gone_loud() || bot.owner.incapacitated())
		return FALSE
	if(!bot.cares_about_vines(length(vines)) || bot.vine_cutters_busy() >= BOT_VINE_CUTTERS)
		return FALSE
	var/obj/structure/spacevine/V = bot.vine_near(BOT_VINE_RANGE)
	if(!V)
		return FALSE
	if(!bot.vine_cutter())
		bot.vine_rest_until = world.time + 3 MINUTES //nothing to cut with
		return FALSE
	if(!bot.assign_goal(new /datum/bot_goal/cut_vines(V)))
		return FALSE
	bot.call_in_vines(V, length(vines))
	return TRUE

/datum/bot_goal/cut_vines
	lawful = TRUE
	exclusive = TRUE
	doing = "cutting back the space vines"

/datum/bot_goal/cut_vines/New(obj/structure/spacevine/V)
	. = ..()
	target = V

/datum/bot_goal/cut_vines/resolve_target(datum/bot_brain/bot)
	if(!bot_vine_worth_cutting(target))
		target = bot.vine_near(BOT_VINE_RANGE, null, FALSE) //it's gone since: the next one

/datum/bot_goal/cut_vines/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/cut_vines())
	return list(S)

/datum/bot_goal/cut_vines/on_give_up(datum/bot_brain/bot)
	bot.vine_rest_until = world.time + 3 MINUTES

/// Swings at the vine in front of it, and on to the next within a few steps, until none's left near or it's had enough.
/datum/bot_step/paced/cut_vines
	max_clicks = 120
	var/obj/structure/spacevine/vine
	/// Hit, and not cut yet.
	var/struck = FALSE
	var/cut = 0

/datum/bot_step/paced/cut_vines/start(datum/bot_brain/bot)
	vine = bot.current_goal?.target
	struck = FALSE
	cut = 0
	return istype(vine) && !QDELETED(vine)

/datum/bot_step/paced/cut_vines/do_click(datum/bot_brain/bot)
	if(!bot_vine_worth_cutting(vine))
		if(struck && QDELETED(vine))
			cut++
		struck = FALSE
		vine = bot.vine_near(3, null, FALSE) //on along the run of them
		bot.current_goal.target = vine //the goal doesn't hold on to the one that's gone
		if(!vine)
			return FALSE
	var/obj/item/tool = bot.vine_cutter()
	if(!tool || !bot.ready_in_hand(tool))
		bot_log(bot, "nothing to cut the vines with")
		return FALSE
	if(!bot.owner.Adjacent(vine))
		if(bot.pursuing_kind != "follow" || bot.pursue_target != vine)
			if(!bot.pursue(vine, "follow", force = TRUE))
				return FALSE
		wait_for = 5
		return TRUE
	if(bot.pursuing_kind)
		bot.stop_pursuit()
	bot.owner.face_atom(vine)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(tool, vine, TRUE)
	struck = TRUE
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/cut_vines/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	if(struck && QDELETED(vine))
		cut++
	if(!cut)
		bot_log(bot, "couldn't get the vines apart")
		return GOAL_STEP_FAIL
	bot.vines_cut += cut
	bot_tally("vines cut back")
	bot_log(bot, "cut back [cut] vine\s")
	return GOAL_STEP_SUCCESS

#undef BOT_VINE_KNOWN_FOR
#undef BOT_VINE_CUTTERS
#undef BOT_VINE_RANGE
#undef BOT_VINE_EVERYBODYS
#undef BOT_VINE_OFFICERS

// ---------------------------------------------------------------------------------------------
// A rogue vending machine (the Brand Intelligence event)
// ---------------------------------------------------------------------------------------------
//
// One machine goes rogue and shouts its marketing at the crew, and every few seconds another catches it (the ones it's got hold of throw
// what they sell at whoever's in view). When every machine on the station has, most of them get up and walk: a mimic apiece, 12 damage
// a hit. It's over the moment the first one's put down, so the crew's one job is that machine, in the first eight minutes. Nobody did it:
// in a forced-event Bot Shift (antags audit, 2026-11-21) 17 of 33 crew were dead in ten minutes of mimics, a bar, a lab and the Brig full of
// them, with their tasers firing at them.
//
// Only the one the event started with shouts the event's lines, so whoever hears it (in earshot, with it in sight) knows which it is, and says
// so on the radio: everybody with a headset knows then. Security, engineers, the janitor and anybody with nerve go and smash it with the
// heaviest thing they carry. Shutting it up at the panel would be quicker, and it's what a player with a screwdriver and a multitool does,
// but the wire's colour is something they learn by pulsing the lot, and a toolbox needs no learning.

/// The machines somebody's heard shouting and called in (REF -> TRUE), so each is called in once.
GLOBAL_LIST_EMPTY(bot_rampant_known)
/// How many go at it at once.
#define BOT_RAMPANT_CUTTERS 3

/datum/bot_brain
	/// Until when it knows which machine it is, and which (a weakref): from hearing it, or off the radio.
	var/rampant_known_until = 0
	var/datum/weakref/rampant_ref

/obj/machinery/vending/speak(message)
	. = ..()
	bot_vending_spoke(src)

/// A vending machine's spoken: if it's the event's, and a bot's in earshot with it in sight, that bot knows which it is and calls it out.
/proc/bot_vending_spoke(obj/machinery/vending/V)
	if(!length(GLOB.bot_brains) || QDELETED(V) || !V.shoot_inventory)
		return
	if(GLOB.bot_rampant_known[REF(V)])
		return
	var/is_the_one = FALSE
	for(var/datum/round_event/brand_intelligence/E in SSevents.running)
		if(E.originMachine == V)
			is_the_one = TRUE
	if(!is_the_one)
		return
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H) || H.stat != CONSCIOUS || get_dist(H, V) > 7 || !(V in view(7, H)))
			continue
		GLOB.bot_rampant_known[REF(V)] = TRUE
		B.report_rampant_machine(V)
		return

/// It heard the origin shout: it's that one, and the radio says so.
/datum/bot_brain/proc/report_rampant_machine(obj/machinery/vending/V)
	rampant_known_until = world.time + 20 MINUTES
	rampant_ref = WEAKREF(V)
	bot_log(src, "[V] is shouting about marketing: that's the one that's gone rogue")
	bot_tally("rogue machines called in")
	if(!can_radio())
		return
	var/where = get_area_name(V, TRUE)
	bot_say(owner, ";[pick("The [V.name] in [where] has gone rogue, it's the one shouting! Smash it!", "[capitalize(where)], the [V.name]! It's the one that's infecting the others, put it down!", "It's the [V.name] in [where]! Somebody smash it before it gets them all!")]")
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B != src && !QDELETED(B.owner) && B.owner.stat != DEAD && B.can_radio() && (!gym_run || B.gym_run == gym_run))
			B.rampant_known_until = world.time + 20 MINUTES //heard it on the radio
			B.rampant_ref = rampant_ref

/// The machine it knows about, if it's still going.
/datum/bot_brain/proc/rampant_machine()
	RETURN_TYPE(/obj/machinery/vending)
	if(world.time >= rampant_known_until)
		return null
	var/datum/weakref/ref = rampant_ref
	var/obj/machinery/vending/V = ref?.resolve()
	if(QDELETED(V) || V.shut_up || !V.shoot_inventory || !isturf(V.loc))
		return null
	if(!(is_station_level(V.z) || gym_run))
		return null
	if(gym_run && get_area(V) != get_area(owner))
		return null
	return V

/// Who goes: the people whose job it is to put down what's loose, then anybody with the nerve.
/datum/bot_brain/proc/cares_about_rampant_machine()
	var/role = work_role()
	if(is_security_job() || (role in GLOB.engineering_positions) || role == "Janitor")
		return TRUE
	return nerve >= 0.5

/datum/bot_brain/proc/rampant_machine_cutters()
	. = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B == src || !istype(B.current_goal, /datum/bot_goal/silence_machine))
			continue
		if(gym_run && B.gym_run != gym_run)
			continue
		.++

/datum/bot_duty/silence_machine
	name = "putting down a rogue vending machine"
	tier = BOT_DUTY_URGENT
	priority = 14
	interval_min = 30
	interval_max = 80
	interrupts = TRUE

/// Not out of a fight, or off a life.
/datum/bot_duty/silence_machine/proc/wants_to(datum/bot_brain/bot)
	if(bot.gone_loud() || bot.owner.incapacitated() || bot.state == BOT_STATE_COMBAT || bot.state == BOT_STATE_ARREST || !bot.rampant_machine())
		return FALSE
	if(!bot.cares_about_rampant_machine() || bot.rampant_machine_cutters() >= BOT_RAMPANT_CUTTERS || !bot.vine_cutter())
		return FALSE
	return TRUE

/datum/bot_duty/silence_machine/should_interrupt(datum/bot_brain/bot)
	if(istype(bot.current_goal, /datum/bot_goal/silence_machine) || istype(bot.current_goal, /datum/bot_goal/run_from) || istype(bot.current_goal, /datum/bot_goal/seek_air) \
		|| istype(bot.current_goal, /datum/bot_goal/revive_patient) || istype(bot.current_goal, /datum/bot_goal/escort_to_sleeper) || istype(bot.current_goal, /datum/bot_goal/evacuate))
		return FALSE
	return wants_to(bot)

/datum/bot_duty/silence_machine/try_start(datum/bot_brain/bot)
	if(!wants_to(bot))
		return FALSE
	var/obj/machinery/vending/V = bot.rampant_machine()
	if(!V || !(bot.gym_run || bot.can_walk_lawfully_to(V)))
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/silence_machine(V))

/datum/bot_brain/proc/put_down_rampant_machine()
	var/obj/machinery/vending/V = rampant_machine()
	if(!V || gone_loud() || owner.incapacitated() || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST)
		return FALSE
	if(!cares_about_rampant_machine() || rampant_machine_cutters() >= BOT_RAMPANT_CUTTERS || !vine_cutter())
		return FALSE
	return assign_goal(new /datum/bot_goal/silence_machine(V))

/datum/bot_goal/silence_machine
	lawful = TRUE
	doing = "putting down a rogue vending machine"

/datum/bot_goal/silence_machine/New(obj/machinery/vending/V)
	. = ..()
	target = V

/datum/bot_goal/silence_machine/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !bot.rampant_machine())
		target = null

/datum/bot_goal/silence_machine/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/smash_machine())
	return list(S)

/// Hits it with the heaviest thing it has until it's wrecked (a vending machine's 250 integrity takes a toolbox twenty swings, an axe a dozen).
/datum/bot_step/paced/smash_machine
	max_clicks = 90
	var/obj/machinery/vending/machine

/datum/bot_step/paced/smash_machine/start(datum/bot_brain/bot)
	machine = bot.current_goal?.target
	return istype(machine) && !QDELETED(machine)

/datum/bot_step/paced/smash_machine/do_click(datum/bot_brain/bot)
	if(QDELETED(machine) || machine.shut_up)
		return FALSE
	var/obj/item/tool = bot.vine_cutter()
	if(!tool || !bot.ready_in_hand(tool))
		return FALSE
	if(!bot.owner.Adjacent(machine))
		if(bot.pursuing_kind != "follow" || bot.pursue_target != machine)
			if(!bot.pursue(machine, "follow", force = TRUE))
				return FALSE
		wait_for = 5
		return TRUE
	if(bot.pursuing_kind)
		bot.stop_pursuit()
	bot.owner.face_atom(machine)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(tool, machine, TRUE)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/smash_machine/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	if(QDELETED(machine) || machine.shut_up)
		bot_tally("rogue machines put down")
		bot_log(bot, "put the rogue machine down")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

#undef BOT_RAMPANT_CUTTERS

// ---------------------------------------------------------------------------------------------
// What an officer shoots an animal with
// ---------------------------------------------------------------------------------------------

// A stun does nothing to a mimic, a carp or a spider (a taser's electrode, a disabler's stamina), and an officer attacked by one fired the
// first gun it found, the hybrid taser, at it: 21 of the 31 shots at the vending machines that got up in a Bot Shift were electrodes. Loose
// creatures that had been called in were already shot with a lethal setting (goals/sabotage_slimes.dm); one that attacks the officer,
// and so takes the ordinary fight, wasn't.

/datum/bot_brain
	/// Until when it's been shooting an animal with a lethal setting, which it puts back to stun once it's been that long since (a later fight
	/// with somebody on the crew would otherwise start with the laser: try_shoot_at() fires the gun as it was left).
	var/animal_shooting_until = 0

/datum/bot_brain/proc/stun_again_after_animals()
	if(QDELETED(src) || QDELETED(owner) || owner.stat == DEAD || world.time < animal_shooting_until || !is_security_job())
		return
	ready_nonlethal_gun()

/datum/bot_brain/try_shoot_at(mob/living/target)
	if(!isanimal(target) || isslime(target))
		return ..()
	var/obj/item/gun/G = ready_lethal_gun() || slime_gun() //a laser, an e-gun on its kill setting, anything firing bullets
	if(!G)
		return FALSE //nothing it carries does it harm from here: its hands then
	if(world.time < next_taser_time || !has_clear_shot(target) || !ready_in_hand(G))
		return FALSE
	owner.a_intent = INTENT_HARM
	owner.face_atom(target)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + shot_interval(G) //foundation/gunfight.dm
	bot_log(src, "firing [G] at [target] (dist [get_dist(owner, target)]): a stun does nothing to that")
	animal_shooting_until = world.time + 15 SECONDS
	addtimer(CALLBACK(src, PROC_REF(stun_again_after_animals)), 16 SECONDS)
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), target, owner, FALSE, null)
	keep_firing_on(target, "combat")
	return TRUE

// The announcement tells the whole station what kind of machine it began with ("the origin is believed to be a Booze-O-Mat"), and a person
// goes and stands by the ones of that name for a while, listening for the one that shouts. Only the bots with the job of putting it down
// (the same ones), a few at a time, and only while it's going and nobody's found it.

/// What the announcement called the origin, and when.
GLOBAL_VAR(bot_rampant_suspect)
GLOBAL_VAR_INIT(bot_rampant_announced_at, -10000)
/// How long it listens at one.
#define BOT_RAMPANT_LISTEN (30 SECONDS)
/// How many go round the candidates at once.
#define BOT_RAMPANT_LISTENERS 3

/datum/round_event/brand_intelligence/announce(fake)
	. = ..()
	if(!fake && originMachine)
		GLOB.bot_rampant_suspect = originMachine.name
		GLOB.bot_rampant_announced_at = world.time

/datum/bot_brain
	/// Machines it's listened at: REF -> not again before.
	var/list/rampant_checked

/// Whether the event's still going with its machine standing, and nobody on the crew's found which it is.
/proc/bot_rampant_hunt_on(datum/bot_brain/asking)
	if(!GLOB.bot_rampant_suspect || world.time > GLOB.bot_rampant_announced_at + 20 MINUTES || asking.rampant_machine())
		return FALSE
	for(var/datum/round_event/brand_intelligence/E in SSevents.running)
		if(!QDELETED(E.originMachine) && !E.originMachine.shut_up)
			return TRUE
	return FALSE

/// The nearest machine of the name the announcement gave that it hasn't listened at lately, and can get to.
/datum/bot_brain/proc/rampant_candidate()
	RETURN_TYPE(/obj/machinery/vending)
	var/list/found = list() //machine -> how far off
	for(var/obj/machinery/vending/V as anything in bot_instances_of(/obj/machinery/vending))
		if(QDELETED(V) || V.name != GLOB.bot_rampant_suspect || V.z != owner.z || !isturf(V.loc) || LAZYACCESS(rampant_checked, REF(V)) > world.time)
			continue
		if(gym_run && get_area(V) != get_area(owner))
			continue
		found[V] = get_dist(owner, V)
	var/tries = 0
	while(length(found) && tries++ < 5)
		var/obj/machinery/vending/nearest
		for(var/obj/machinery/vending/V as anything in found)
			if(!nearest || found[V] < found[nearest])
				nearest = V
		found -= nearest
		if(gym_run || can_walk_lawfully_to(nearest))
			return nearest
	return null

/datum/bot_brain/proc/rampant_listeners()
	. = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B == src || !istype(B.current_goal, /datum/bot_goal/listen_at_machine))
			continue
		if(gym_run && B.gym_run != gym_run)
			continue
		.++

/datum/bot_duty/listen_for_rogue_machine
	name = "listening for the rogue vending machine"
	tier = BOT_DUTY_URGENT
	priority = 13
	interval_min = 50
	interval_max = 120

/datum/bot_duty/listen_for_rogue_machine/try_start(datum/bot_brain/bot)
	if(!GLOB.bot_rampant_suspect || bot.gone_loud() || bot.owner.incapacitated() || !bot.cares_about_rampant_machine() || !bot_rampant_hunt_on(bot))
		return FALSE
	if(bot.rampant_listeners() >= BOT_RAMPANT_LISTENERS)
		return FALSE
	var/obj/machinery/vending/V = bot.rampant_candidate()
	return V ? bot.assign_goal(new /datum/bot_goal/listen_at_machine(V)) : FALSE

/datum/bot_goal/listen_at_machine
	lawful = TRUE
	doing = "listening for the rogue vending machine"

/datum/bot_goal/listen_at_machine/New(obj/machinery/vending/V)
	. = ..()
	target = V

/datum/bot_goal/listen_at_machine/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/listen_at_machine/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/listen_at_machine())
	return list(S)

/// Stands there for a while, and says nothing: if it's the one, the machine's own shout does the rest (bot_vending_spoke()).
/datum/bot_step/paced/listen_at_machine
	max_clicks = 40
	var/until = 0

/datum/bot_step/paced/listen_at_machine/start(datum/bot_brain/bot)
	until = world.time + BOT_RAMPANT_LISTEN
	return !QDELETED(bot.current_goal?.target)

/datum/bot_step/paced/listen_at_machine/do_click(datum/bot_brain/bot)
	if(world.time >= until || bot.rampant_machine() || !bot_rampant_hunt_on(bot))
		return FALSE
	bot.idle_fidget()
	wait_for = 20
	return TRUE

/datum/bot_step/paced/listen_at_machine/finish(datum/bot_brain/bot)
	var/obj/machinery/vending/V = bot.current_goal?.target
	if(V)
		LAZYSET(bot.rampant_checked, REF(V), world.time + 5 MINUTES)
	return GOAL_STEP_SUCCESS

/// It heard it shout: that's the one, and it goes straight at it, not when its next look at its duties comes round (or, by the time it
/// does, the engineer's wandered off from the machine and the mimics are out).
/datum/bot_goal/listen_at_machine/on_success(datum/bot_brain/bot)
	if(bot.rampant_machine())
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, put_down_rampant_machine)))

#undef BOT_RAMPANT_LISTEN
#undef BOT_RAMPANT_LISTENERS

// ---------------------------------------------------------------------------------------------
// "Steal 28 moles of plasma (full tank)": filling a tank from a canister
// ---------------------------------------------------------------------------------------------
//
// goals/traitor.dm goes for a tank that already has the 28 moles in it, and there's hardly ever one lying about: the plasma tanks in
// Toxins are filled to three atmospheres, about 8 moles. A player takes a plasma tank to a plasma canister, puts it in, sets the release
// pressure to the top, opens the valve and waits: a 70 litre tank at a canister's 1013 kPa holds nearly 29 moles.

/// Moles the objective asks for, and a little over it to be sure of it.
#define BOT_PLASMA_FILL_MOLES 28
#define BOT_PLASMA_FILL_ENOUGH 28.5

/// The nearest plasma canister on its level with plasma enough in it and nothing plugged into it, where it can go.
/datum/bot_brain/proc/plasma_canister()
	var/obj/machinery/portable_atmospherics/canister/best
	var/best_dist
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(QDELETED(C) || C.z != owner.z || C.holding || (gym_run && get_area(C) != get_area(owner)))
			continue
		var/datum/gas_mixture/air = C.air_contents
		if(!air || air.moles[/datum/gas/plasma] < BOT_PLASMA_FILL_MOLES * 3)
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/// The plasma tank it's carrying with the most in it.
/datum/bot_brain/proc/carried_plasma_tank()
	var/obj/item/tank/internals/plasma/best
	for(var/obj/item/tank/internals/plasma/T in owner.GetAllContents())
		if(!best || T.air_contents.moles[/datum/gas/plasma] > best.air_contents.moles[/datum/gas/plasma])
			best = T
	return best

/// The goal for a "28 moles of plasma" objective with no full tank about: fill one. Null for any other objective, and where there's
/// no plasma canister to fill it from.
/datum/bot_brain/proc/plasma_fill_goal(datum/objective/steal/S)
	if(!istype(S.targetinfo, /datum/objective_item/steal/plasma) || !plasma_canister())
		return null
	return new /datum/bot_goal/traitor_fill_plasma(S)

/datum/bot_goal/traitor_fill_plasma
	doing = "on an errand"
	breaks_in = TRUE
	var/datum/objective/steal/objective

/datum/bot_goal/traitor_fill_plasma/New(datum/objective/steal/S)
	. = ..()
	objective = S

/datum/bot_goal/traitor_fill_plasma/resolve_target(datum/bot_brain/bot)
	target = bot.plasma_canister()

/datum/bot_goal/traitor_fill_plasma/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/fill_plasma/S = new
	S.steps = list(new /datum/bot_step/get_plasma_tank(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/fill_plasma_tank())
	return list(S)

/datum/bot_goal/traitor_fill_plasma/on_success(datum/bot_brain/bot)
	var/obj/item/tank/internals/plasma/T = bot.carried_plasma_tank()
	bot_log(bot, "filled [T] with plasma")
	bot.stash_stolen(T)
	if(objective && !objective.check_completion())
		bot_log(bot, "that's no good for the job: leaving it a while")
		LAZYSET(bot.objectives_parked, objective, world.time + 5 MINUTES)

/datum/bot_goal/traitor_fill_plasma/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.objectives_parked, objective, world.time + 2 MINUTES)

/datum/bot_strategy/fill_plasma/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// A plasma tank to fill: the one it's got, or the nearest lying about (Toxins' storage), fetched once.
/datum/bot_step/get_plasma_tank
	var/fetched = FALSE

/datum/bot_step/get_plasma_tank/execute(datum/bot_brain/bot)
	if(bot.carried_plasma_tank())
		return GOAL_STEP_SUCCESS
	if(fetched)
		return GOAL_STEP_FAIL
	fetched = TRUE
	bot_log(bot, "getting a plasma tank to fill")
	var/datum/bot_goal/acquire_item_type/G = new()
	G.item_type = /obj/item/tank/internals/plasma
	return bot.suspend_goal_for(G) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// At the canister: the tank in, the release pressure to the top, the valve open, and a wait until it's full or it's stopped rising;
/// then the valve shut and the tank out again.
/datum/bot_step/paced/fill_plasma_tank
	max_clicks = 6
	var/obj/machinery/portable_atmospherics/canister/can
	var/obj/item/tank/internals/plasma/tank
	var/last_moles = 0
	var/last_rise = 0
	var/until = 0

/datum/bot_step/paced/fill_plasma_tank/start(datum/bot_brain/bot)
	can = bot.current_goal?.target
	tank = bot.carried_plasma_tank()
	if(!istype(can) || QDELETED(can) || !tank || can.holding || !bot.owner.Adjacent(can))
		return FALSE
	if(!bot.ready_in_hand(tank))
		return FALSE
	bot.use_tool_on(tank, can) //in, the way a player clicks the canister with the tank in hand
	if(can.holding != tank)
		bot_log(bot, "[can] wouldn't take [tank]")
		return FALSE
	can.release_pressure = can.can_max_release_pressure
	can.valve_open = TRUE
	can.update_icon()
	last_moles = tank.air_contents.moles[/datum/gas/plasma]
	last_rise = world.time
	until = world.time + 90 SECONDS
	bot_log(bot, "filling [tank] from [can], [round(last_moles, 0.1)] moles to start")
	return TRUE

/datum/bot_step/paced/fill_plasma_tank/do_click(datum/bot_brain/bot)
	if(QDELETED(can) || QDELETED(tank) || can.holding != tank || world.time >= until || !bot.owner.Adjacent(can))
		return FALSE
	var/moles = tank.air_contents.moles[/datum/gas/plasma]
	if(moles >= BOT_PLASMA_FILL_ENOUGH)
		return FALSE
	if(moles > last_moles + 0.05)
		last_moles = moles
		last_rise = world.time
	else if(world.time >= last_rise + 8 SECONDS)
		return FALSE //as far as it goes
	wait_for = 10
	return TRUE

/datum/bot_step/paced/fill_plasma_tank/finish(datum/bot_brain/bot)
	if(!QDELETED(can))
		can.valve_open = FALSE
		if(can.holding == tank)
			can.replace_tank(bot.owner, TRUE) //back out, into its hands
		can.update_icon()
	if(QDELETED(tank))
		return GOAL_STEP_FAIL
	if(tank.loc != bot.owner)
		bot.owner.put_in_hands(tank)
	var/moles = tank.air_contents.moles[/datum/gas/plasma]
	bot_log(bot, "[tank] has [round(moles, 0.1)] moles of plasma in it")
	return (tank.loc == bot.owner && moles >= BOT_PLASMA_FILL_MOLES) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_PLASMA_FILL_MOLES
#undef BOT_PLASMA_FILL_ENOUGH
