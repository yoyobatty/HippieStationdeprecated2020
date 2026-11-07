// Research experiments (hippiestation/code/modules/research/experiments.dm, the user's on 2026-11-06): a scientist takes the experiment
// scanner every scientist carries out round the station, to the things the experiments want and nobody's scanned yet, and scans
// them. A finished one pays 5,000-15,000 points and halves its related nodes, so the bots' research goes faster for it, as a player's
// would. What it looks for is what a player finds lying about: a cyborg going past, crops left out, ore by the redemption machine,
// an organ out of somebody, a canister of something exotic. Slimes it leaves be, behind their pen glass. Nothing it can't walk to by
// doors its own ID opens.

/// How far it goes for something to scan.
#define BOT_EXPERIMENT_REACH 50

/datum/bot_duty/experiment_rounds
	name = "the research experiments"
	jobs = list("Scientist", "Research Director")
	priority = 12
	interval_min = 900
	interval_max = 1800

/datum/bot_duty/experiment_rounds/try_start(datum/bot_brain/bot)
	var/obj/item/experi_scanner/scanner = bot.find_carried_tool(/obj/item/experi_scanner)
	if(!scanner)
		return FALSE
	var/atom/target = bot.next_experiment_target()
	return target ? bot.assign_goal(new /datum/bot_goal/scan_for_experiment(target)) : FALSE

/// Whether something counts for an experiment that isn't finished and hasn't got it yet.
/proc/bot_experiment_wants(atom/A)
	for(var/datum/science_experiment/E as anything in science_experiments())
		if(E.completed)
			continue
		var/key = E.key_for(A, list(null))
		if(key && !E.done[key])
			return E
	return null

/// The nearest thing worth scanning that it can walk up to.
/datum/bot_brain/proc/next_experiment_target()
	var/list/candidates = list()
	for(var/mob/living/silicon/robot/R in GLOB.silicon_mobs)
		candidates += R
	for(var/obj/mecha/M as anything in bot_instances_of(/obj/mecha))
		candidates += M
	for(var/obj/item/reagent_containers/food/snacks/grown/G as anything in bot_instances_of(/obj/item/reagent_containers/food/snacks/grown))
		candidates += G
	for(var/obj/item/stack/ore/O as anything in bot_instances_of(/obj/item/stack/ore))
		candidates += O
	for(var/obj/item/organ/O as anything in bot_instances_of(/obj/item/organ))
		if(!O.owner)
			candidates += O
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		candidates += C
	var/atom/best
	var/best_dist
	for(var/atom/movable/A as anything in candidates)
		if(QDELETED(A) || !isturf(A.loc) || A.z != owner.z)
			continue
		var/dist = get_dist(owner, A)
		if(dist > BOT_EXPERIMENT_REACH || (best && dist >= best_dist))
			continue
		if(isliving(A))
			var/mob/living/L = A
			if(L.stat == DEAD)
				continue
		if(!bot_experiment_wants(A) || in_bad_air(A) || !can_walk_lawfully_to(A))
			continue
		best = A
		best_dist = dist
	return best

/datum/bot_goal/scan_for_experiment
	doing = "scanning things for the research experiments"
	lawful = TRUE

/datum/bot_goal/scan_for_experiment/New(atom/A)
	. = ..()
	target = A

/datum/bot_goal/scan_for_experiment/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !bot_experiment_wants(target))
		target = null

/datum/bot_goal/scan_for_experiment/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/scan_for_experiment/S = new
	var/datum/bot_step/move_to/to_it = new
	if(ismob(target))
		to_it.step_target = target //it moves: right up to it, a step off is close enough for something living
	S.steps = list(isliving(target) ? to_it : new /datum/bot_step/move_to(), new /datum/bot_step/scan_experiment())
	return list(S)

/// On to the next thing nearby, while it's out with the scanner: five ores on the floor are one trip, not five.
/datum/bot_goal/scan_for_experiment/on_success(datum/bot_brain/bot)
	var/atom/next = bot.next_experiment_target()
	if(next && get_dist(bot.owner, next) <= 15)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/scan_for_experiment(next)))

/datum/bot_strategy/scan_for_experiment/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/scan_experiment/execute(datum/bot_brain/bot)
	var/atom/A = bot.current_goal?.target
	var/obj/item/experi_scanner/scanner = bot.find_carried_tool(/obj/item/experi_scanner)
	if(QDELETED(A) || !scanner || get_dist(bot.owner, A) > 1)
		return GOAL_STEP_FAIL
	var/datum/science_experiment/E = bot_experiment_wants(A)
	if(!E)
		return GOAL_STEP_SUCCESS //somebody's beaten it to it
	if(!bot.ready_in_hand(scanner))
		return GOAL_STEP_FAIL
	bot.human_pause(A)
	bot.owner.face_atom(A)
	bot.telemetry_shortcut("afterattack", scanner, A)
	scanner.afterattack(A, bot.owner, bot.owner.Adjacent(A))
	bot_log(bot, "scanned [A] for [E.name] ([length(E.done)]/[E.required])")
	bot_tally("experiment scans")
	if(E.completed)
		bot_tally("experiments finished")
		bot.say_after_typing(":n [pick("[E.name]'s done, that's [E.reward] points.", "Finished [E.name]: [E.reward] points in the bank.", "[E.name] complete.")]")
	bot.put_away(scanner)
	return GOAL_STEP_SUCCESS

#undef BOT_EXPERIMENT_REACH
