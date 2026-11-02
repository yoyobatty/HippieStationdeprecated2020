// Playing a changeling. The real antagonist datum, with the game's own objectives, gone about with the same buttons a player has
// (try_to_sting(), changeling_power.dm).
//
//  - It gets on with its job for a while, then goes looking for somebody on their own, with an arm blade grown at the last moment.
//  - Once they're down it takes a kill grip, which is what Absorb DNA asks for, and that's fifteen seconds of holding still: long
//    enough to get caught at it, the way it is for anybody.
//  - Beaten down itself, it goes into Reviving Stasis, plays dead, and gets back up when that's ready.
//  - Kill objectives go the same way, and steal objectives go through the traitor's goal. Those it has no way of doing yet are
//    left alone, as with traitors (goals/traitor.dm).

/// The earliest a changeling starts feeding, after arriving.
#define BOT_LING_SETTLE_IN (6 MINUTES)
/// Between one and the next: people notice a crew that thins out all at once.
#define BOT_LING_DIGEST (4 MINUTES)
#define BOT_LING_PARK (3 MINUTES)
/// How far it'll go after somebody.
#define BOT_LING_RANGE 60

/datum/bot_brain
	/// Set when it's a changeling, so process() needn't look it up every second.
	var/is_changeling = FALSE
	/// People it's absorbed.
	var/absorbed = 0

/// Makes `count` of the crew's bots changelings, chosen at random. Returns the ones it made.
/proc/bot_make_changelings(count)
	. = list()
	var/list/candidates = list()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.bot_brain && H.mind && H.stat != DEAD && bot_traitor_job_allowed(H.mind.assigned_role) && !H.mind.special_role)
			candidates += H
	while(length(candidates) && length(.) < count)
		var/mob/living/carbon/human/H = pick_n_take(candidates)
		H.bot_brain.become_changeling()
		H.bot_brain.traitor_business_after = world.time + BOT_LING_SETTLE_IN + rand(0, 4 MINUTES)
		bot_log(H.bot_brain, "I'm a changeling: [jointext(H.bot_brain.objective_list(), "; ")]")
		. += H

/datum/bot_brain/proc/become_changeling()
	being_issued_kit = TRUE
	var/datum/antagonist/changeling/ling = owner.mind.add_antag_datum(/datum/antagonist/changeling)
	being_issued_kit = FALSE
	ling.purchase_power("Arm Blade") //off the Cellular Emporium, with the points it starts with
	is_changeling = TRUE

/datum/bot_brain/proc/ling_datum()
	return owner.mind?.has_antag_datum(/datum/antagonist/changeling)

/datum/bot_brain/proc/ling_power(power_type)
	var/datum/antagonist/changeling/ling = ling_datum()
	return ling && (locate(power_type) in ling.purchasedpowers)

/// The button for a power. Whatever it asks for (chemicals, a grip) it checks for itself.
/datum/bot_brain/proc/ling_use(power_type, mob/living/target)
	var/datum/action/changeling/P = ling_power(power_type)
	P?.try_to_sting(owner, target)

/// Grows the blade on a free hand.
/datum/bot_brain/proc/ling_grow_blade()
	if(locate(/obj/item/melee/arm_blade) in owner.held_items)
		return
	if(owner.get_active_held_item())
		make_hand_free()
		if(owner.get_active_held_item())
			owner.swap_hand()
		if(owner.get_active_held_item())
			put_away(owner.get_active_held_item())
	ling_use(/datum/action/changeling/weapon/arm_blade)

/datum/bot_brain/proc/ling_retract_blade()
	var/obj/item/melee/arm_blade/blade = locate() in owner.held_items
	if(!blade)
		return
	if(owner.get_active_held_item() != blade)
		owner.swap_hand()
	ling_use(/datum/action/changeling/weapon/arm_blade)

/// Somebody to feed on, that it can walk to: the nearest few, and not Security while there's anybody else.
/datum/bot_brain/proc/find_prey()
	var/datum/antagonist/changeling/ling = ling_datum()
	var/list/options = list() //mob -> how far off
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H == owner || !H.mind || H.stat == DEAD || H.z != owner.z || H.mind.has_antag_datum(/datum/antagonist/changeling))
			continue
		var/dist = get_dist(owner, H)
		if(dist > BOT_LING_RANGE || !ling.can_absorb_dna(H, FALSE))
			continue
		options[H] = dist + ((H.mind.assigned_role in GLOB.security_positions) ? BOT_LING_RANGE : 0)
	var/tries = 0
	while(length(options) && tries++ < 4)
		var/mob/living/carbon/human/nearest
		for(var/mob/living/carbon/human/H as anything in options)
			if(!nearest || options[H] < options[nearest])
				nearest = H
		options -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
	return null

/datum/bot_duty/changeling
	name = "the hive's business"
	priority = 30
	interval_min = 300
	interval_max = 900

/datum/bot_duty/changeling/applies_to(datum/bot_brain/bot)
	return TRUE //a mid-round changeling's the same bot it always was: worked out in try_start()

/datum/bot_duty/changeling/try_start(datum/bot_brain/bot)
	if(!bot.is_changeling || world.time < bot.traitor_business_after)
		return FALSE
	var/datum/antagonist/changeling/ling = bot.ling_datum()
	for(var/datum/objective/O as anything in ling?.objectives)
		if(LAZYACCESS(bot.objectives_parked, O) > world.time || bot.objective_finished(O))
			continue
		var/datum/bot_goal/goal
		if(istype(O, /datum/objective/absorb) || istype(O, /datum/objective/absorb_most))
			var/mob/living/carbon/human/prey = bot.find_prey()
			if(prey)
				goal = new /datum/bot_goal/traitor_kill/ling(O, prey)
		else if(istype(O, /datum/objective/assassinate) || istype(O, /datum/objective/maroon))
			if(O.target?.current)
				goal = new /datum/bot_goal/traitor_kill/ling(O, O.target.current)
		else
			goal = bot.goal_for_objective(O)
		if(goal && bot.assign_goal(goal))
			return TRUE
	return FALSE

/datum/bot_goal/traitor_kill/ling
	var/mob/living/carbon/human/prey

/datum/bot_goal/traitor_kill/ling/New(datum/objective/O, mob/living/carbon/human/H)
	. = ..(O)
	prey = H

/datum/bot_goal/traitor_kill/ling/victim()
	return prey

/datum/bot_goal/traitor_kill/ling/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/paced/stalk(), new /datum/bot_step/paced/strike/ling(), new /datum/bot_step/paced/ling_absorb())
	return list(S)

/datum/bot_goal/traitor_kill/ling/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.objectives_parked, objective, world.time + BOT_LING_PARK)
	bot.ling_retract_blade()
	bot.owner.stop_pulling()

/datum/bot_goal/traitor_kill/ling/on_success(datum/bot_brain/bot)
	bot.traitor_business_after = world.time + BOT_LING_DIGEST + rand(0, 3 MINUTES)

/// Until they're down: it wants them in one piece.
/datum/bot_step/paced/strike/ling

/datum/bot_step/paced/strike/ling/start(datum/bot_brain/bot)
	bot.ling_grow_blade()
	return TRUE

/datum/bot_step/paced/strike/ling/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	if(QDELETED(V) || V.stat != CONSCIOUS)
		return FALSE
	if(!bot.owner.Adjacent(V))
		if(get_dist(bot.owner, V) > BOT_SIGHT_RANGE)
			return FALSE //got away
		bot.combat_chase(V)
		wait_for = 5
		return TRUE
	bot.stop_pursuit()
	var/obj/item/melee/arm_blade/blade = locate() in bot.owner.held_items
	if(blade)
		bot.use_item_on(blade, V, harm = TRUE)
	else
		bot.owner.a_intent = INTENT_HARM
		bot.owner.UnarmedAttack(V, TRUE)
		bot.owner.a_intent = INTENT_HELP
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.try_combat_sidestep(V)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/strike/ling/finish(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	bot.stop_pursuit()
	bot.ling_retract_blade()
	var/mob/living/V = G?.victim()
	if(V && V.stat != CONSCIOUS)
		bot_log(bot, "[V] is down")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

/// A pull, tightened twice to a kill grip a few seconds at a time, and then the proboscis.
/datum/bot_step/paced/ling_absorb
	max_clicks = 20
	var/started = FALSE
	var/grips = 0

/datum/bot_step/paced/ling_absorb/start(datum/bot_brain/bot)
	started = FALSE
	grips = 0
	return TRUE

/datum/bot_step/paced/ling_absorb/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	var/datum/antagonist/changeling/ling = bot.ling_datum()
	if(QDELETED(V) || !ling || bot.owner.stat != CONSCIOUS)
		return FALSE
	if(started)
		if(!ling.isabsorbing)
			return FALSE
		wait_for = 1 SECONDS
		return TRUE
	if(!bot.owner.Adjacent(V))
		if(get_dist(bot.owner, V) > BOT_SIGHT_RANGE)
			return FALSE
		bot.combat_chase(V)
		wait_for = 5
		return TRUE
	bot.stop_pursuit()
	if(bot.owner.pulling != V || bot.owner.grab_state <= GRAB_NECK)
		if(grips++ > 6)
			return FALSE
		bot.owner.a_intent = INTENT_GRAB
		INVOKE_ASYNC(V, TYPE_PROC_REF(/mob/living, grabbedby), bot.owner)
		wait_for = 35
		return TRUE
	started = TRUE
	bot_log(bot, "absorbing [V]")
	INVOKE_ASYNC(bot, TYPE_PROC_REF(/datum/bot_brain, ling_use), /datum/action/changeling/absorbDNA, V)
	wait_for = 1 SECONDS
	return TRUE

/datum/bot_step/paced/ling_absorb/finish(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	bot.owner.a_intent = INTENT_HELP
	bot.owner.stop_pulling()
	if(V && HAS_TRAIT(V, TRAIT_HUSK))
		bot.absorbed++
		bot_tally("absorbed")
		bot_log(bot, "absorbed [V]")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

/// Beaten into crit or killed outright, it drops into stasis, and gets up when that's ready. It costs 15 chemicals: without them
/// it's as dead as anybody until they've built up. Stasis ends when it says so, so it's a look a second.
/datum/bot_brain/proc/mind_stasis()
	var/datum/action/changeling/fakedeath/P = ling_power(/datum/action/changeling/fakedeath)
	if(!P || (owner.stat == CONSCIOUS && !HAS_TRAIT_FROM(owner, TRAIT_FAKEDEATH, "changeling")))
		return
	if(P.revive_ready)
		bot_log(src, "up again")
		bot_tally("rose from stasis")
		INVOKE_ASYNC(P, TYPE_PROC_REF(/datum/action/changeling, try_to_sting), owner)
		return
	if(!HAS_TRAIT_FROM(owner, TRAIT_FAKEDEATH, "changeling"))
		INVOKE_ASYNC(P, TYPE_PROC_REF(/datum/action/changeling, try_to_sting), owner)

#undef BOT_LING_SETTLE_IN
#undef BOT_LING_DIGEST
#undef BOT_LING_PARK
#undef BOT_LING_RANGE
