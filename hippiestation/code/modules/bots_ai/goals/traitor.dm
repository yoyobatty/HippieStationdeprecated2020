// Playing a traitor.
//
// A round with no antagonists has nothing happening in it, and a mode only picks antagonists from players with clients,
// so without this a crew of bots never has one. bot_make_traitors() gives a few of them the real antagonist datum, with
// the game's own objectives, and they go about those the way a player does: get on with the job for a while so nobody
// looks twice, buy what's needed off the uplink hidden in the PDA, and pick a moment. What comes of it is the game's own
// too: a bot seen doing it gets reported and arrested like anybody else (goals/security_patrol.dm).
//
//  - Steal (a named item): breaks in if it has to, takes it, and keeps it on its person.
//  - Kill (assassinate, maroon): an energy sword off the uplink, then it follows the target about until there's nobody
//    else in sight, and does it. A target behind a door the bot's ID doesn't open is waited for, not broken in on.
//  - Escape is what the crew does anyway (goals/evacuate.dm).
//
// Objectives it has no way of doing yet (hijack, download a research disk...) are left alone, as a player leaves the
// hard ones. Being arrested, it doesn't try to escape; a player would.

/// The earliest a traitor starts on its objectives, after arriving.
#define BOT_TRAITOR_SETTLE_IN (8 MINUTES)
/// How long something that didn't work is left before trying again.
#define BOT_TRAITOR_PARK (5 MINUTES)

/datum/bot_brain
	/// Objective -> when it's worth another try.
	var/list/objectives_parked
	/// When a traitor starts on its objectives.
	var/traitor_business_after = 0
	/// Set while the game puts things on this bot, for the telemetry to leave alone.
	var/being_issued_kit = FALSE

/// Whether this job can have a traitor in it, by the mode's own rules (traitor.dm): nobody who'd be looked at closely.
/proc/bot_traitor_job_allowed(job)
	return !(job in list("Cyborg", "AI", "Security Officer", "Warden", "Detective", "Head of Security", "Captain", "Head of Personnel"))

/// Makes `count` of the crew's bots traitors, chosen at random. Returns the ones it made.
/proc/bot_make_traitors(count)
	. = list()
	var/list/candidates = list()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.bot_brain && H.mind && H.stat != DEAD && bot_traitor_job_allowed(H.mind.assigned_role) && !length(H.mind.antag_datums))
			candidates += H
	while(length(candidates) && length(.) < count)
		var/mob/living/carbon/human/H = pick_n_take(candidates)
		H.bot_brain.become_traitor()
		H.bot_brain.traitor_business_after = world.time + BOT_TRAITOR_SETTLE_IN + rand(0, 5 MINUTES)
		bot_log(H.bot_brain, "I'm a traitor: [jointext(H.bot_brain.objective_list(), "; ")]")
		. += H

/// The real antagonist datum, and what it hands out. The game puts a traitor's kit on it (a pinpointer, a folder of
/// documents), which is no more the bot's doing than its uniform: that isn't a robotic tell.
/datum/bot_brain/proc/become_traitor()
	being_issued_kit = TRUE
	. = owner.mind.add_antag_datum(/datum/antagonist/traitor)
	being_issued_kit = FALSE

/datum/bot_brain/proc/objective_list()
	. = list()
	var/datum/antagonist/A = owner.mind?.has_antag_datum(/datum/antagonist/traitor) || ling_datum()
	for(var/datum/objective/O as anything in A?.objectives)
		. += O.explanation_text

/// Whether there's nothing left to do on an objective. The game's own check_completion() won't do for a target: it counts
/// anybody without a client as already gone, and no bot has one.
/datum/bot_brain/proc/objective_finished(datum/objective/O)
	if(istype(O, /datum/objective/assassinate) || istype(O, /datum/objective/maroon))
		var/mob/living/L = O.target?.current
		return !L || L.stat == DEAD
	return O.check_completion()

/// The goal for an objective this bot knows how to go about, or null.
/datum/bot_brain/proc/goal_for_objective(datum/objective/O)
	if(istype(O, /datum/objective/steal))
		var/datum/objective/steal/S = O
		if(!S.steal_target)
			return null
		return new /datum/bot_goal/traitor_steal(S)
	if(istype(O, /datum/objective/assassinate) || istype(O, /datum/objective/maroon))
		return O.target?.current ? new /datum/bot_goal/traitor_kill(O) : null
	return null

/datum/bot_duty/traitor
	name = "the Syndicate's business"
	tier = BOT_DUTY_URGENT //the work tier never comes round for anybody with a job that's never finished
	priority = 8
	interval_min = 300
	interval_max = 900

/datum/bot_duty/traitor/try_start(datum/bot_brain/bot)
	if(!bot.owner.mind?.has_antag_datum(/datum/antagonist/traitor) || world.time < bot.traitor_business_after)
		return FALSE
	var/datum/antagonist/traitor/T = bot.owner.mind.has_antag_datum(/datum/antagonist/traitor)
	for(var/datum/objective/O as anything in T.objectives)
		if(LAZYACCESS(bot.objectives_parked, O) > world.time || bot.objective_finished(O))
			continue
		var/datum/bot_goal/goal = bot.goal_for_objective(O)
		if(goal && bot.assign_goal(goal))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// The uplink
// ---------------------------------------------------------------------------------------------

/// The traitor's uplink, wherever equip_traitor() hid it.
/datum/bot_brain/proc/traitor_uplink()
	for(var/obj/item/I in owner.GetAllContents())
		var/datum/component/uplink/U = I.GetComponent(/datum/component/uplink)
		if(U)
			return U
	return null

/// Unlocks the uplink and buys the thing, a click at a time. TRUE if it's bought.
/datum/bot_brain/proc/buy_from_uplink(item_path)
	var/datum/component/uplink/U = traitor_uplink()
	if(!U)
		return FALSE
	var/obj/item/hideout = U.parent
	if(U.locked)
		telemetry_ui_action(hideout, "open uplink")
		human_pause(hideout)
		U.locked = FALSE
	for(var/category in U.uplink_items)
		for(var/item_name in U.uplink_items[category])
			var/datum/uplink_item/I = U.uplink_items[category][item_name]
			if(I.item != item_path)
				continue
			telemetry_ui_action(hideout, "buy [item_name]")
			human_pause(hideout)
			. = U.MakePurchase(owner, I)
			U.locked = TRUE
			return
	U.locked = TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Stealing
// ---------------------------------------------------------------------------------------------

/// A strategy that breaks a locked thing open and takes this item out of what falls out.
/datum/bot_strategy/brute_force/theft/New(item_type)
	. = ..()
	steps[length(steps)] = new /datum/bot_step/pickup_from_target(item_type)

/datum/bot_goal/traitor_steal
	doing = "on an errand"
	var/datum/objective/steal/objective
	var/item_type

/datum/bot_goal/traitor_steal/New(datum/objective/steal/S)
	. = ..()
	objective = S
	item_type = S.steal_target

/// The nearest one of these on this z-level that isn't on somebody: the thing itself, or whatever it's locked up in.
/datum/bot_goal/traitor_steal/resolve_target(datum/bot_brain/bot)
	var/atom/movable/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		var/atom/movable/holder = bot_outermost_holder(I)
		if(QDELETED(I) || ismob(holder) || !isturf(holder.loc) || holder.z != bot.owner.z)
			continue
		var/dist = get_dist(bot.owner, holder)
		if(!best || dist < best_dist)
			best = holder
			best_dist = dist
	target = best

/datum/bot_goal/traitor_steal/get_strategies(datum/bot_brain/bot)
	if(istype(target, item_type))
		return list(new /datum/bot_strategy/grab_item())
	if(istype(target, /obj/structure/closet))
		var/obj/structure/closet/C = target
		if(!C.locked || C.allowed(bot.owner))
			return list(new /datum/bot_strategy/grab_item_from_locker(item_type))
	return list(new /datum/bot_strategy/brute_force/theft(item_type))

/datum/bot_goal/traitor_steal/on_success(datum/bot_brain/bot)
	bot_log(bot, "got the [objective.targetinfo?.name || item_type]")
	var/obj/item/stolen = bot.find_carried_tool(item_type)
	if(stolen && (stolen in bot.owner.held_items))
		bot.put_away(stolen)

/datum/bot_goal/traitor_steal/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.objectives_parked, objective, world.time + BOT_TRAITOR_PARK)

// ---------------------------------------------------------------------------------------------
// Killing
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/traitor_kill
	lawful = TRUE
	doing = "looking for somebody"
	var/datum/objective/objective
	var/obj/item/melee/transforming/energy/sword/sword

/datum/bot_goal/traitor_kill/New(datum/objective/O)
	. = ..()
	objective = O

/datum/bot_goal/traitor_kill/proc/victim()
	return objective?.target?.current

/datum/bot_goal/traitor_kill/resolve_target(datum/bot_brain/bot)
	var/mob/living/V = victim()
	var/turf/there = get_turf(V)
	if(there && V.stat != DEAD && there.z == bot.owner.z)
		target = V

/datum/bot_goal/traitor_kill/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/traitor_arm(), new /datum/bot_step/paced/stalk(), new /datum/bot_step/paced/strike())
	return list(S)

/datum/bot_goal/traitor_kill/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.objectives_parked, objective, world.time + BOT_TRAITOR_PARK)
	bot.put_sword_away(sword)

/datum/bot_strategy/traitor_kill/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// Off, and back in the bag.
/datum/bot_brain/proc/put_sword_away(obj/item/melee/transforming/energy/sword/sword)
	if(QDELETED(sword) || !is_carried(sword))
		return
	if(sword.active)
		toggle_in_hand(sword)
	if(sword in owner.held_items)
		put_away(sword)

/// A sword on it, off the uplink if it hasn't got one. A traitor with no uplink (or the crystals gone) goes without.
/datum/bot_step/traitor_arm/execute(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	G.sword = bot.find_carried_tool(/obj/item/melee/transforming/energy/sword)
	if(!G.sword && bot.buy_from_uplink(/obj/item/melee/transforming/energy/sword/saber))
		G.sword = bot.find_carried_tool(/obj/item/melee/transforming/energy/sword)
		bot_log(bot, "bought [G.sword || "nothing"] off the uplink")
	if(G.sword && (G.sword in bot.owner.held_items))
		bot.put_away(G.sword) //not walked about with in the open
	return GOAL_STEP_SUCCESS

/// Whether anybody but the target would see what happens next.
/datum/bot_brain/proc/alone_with(mob/living/V)
	for(var/mob/living/L in view(BOT_SIGHT_RANGE, owner))
		if(L != owner && L != V && L.stat == CONSCIOUS && (ishuman(L) || issilicon(L)))
			return FALSE
	return TRUE

/// Follows the target about at a distance, until there's a moment with nobody else in sight.
/datum/bot_step/paced/stalk
	max_clicks = 100
	var/moment_found = FALSE

/datum/bot_step/paced/stalk/start(datum/bot_brain/bot)
	moment_found = FALSE
	return TRUE

/datum/bot_step/paced/stalk/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	var/turf/there = get_turf(V)
	if(!there || V.stat == DEAD || there.z != bot.owner.z)
		return FALSE
	if(bot.owner.Adjacent(V) && bot.alone_with(V))
		moment_found = TRUE
		return FALSE
	if(get_dist(bot.owner, V) > 1 && bot.pursuing_kind != "follow")
		// No way to them (a room this ID doesn't open): that's for another time. Waiting it out at the door is the
		// one thing certain to get noticed.
		if(!bot.can_walk_lawfully_to(V))
			return FALSE
		bot.pursue(V, "follow", force = TRUE)
	else if(get_dist(bot.owner, V) <= 1)
		bot.idle_fidget() //waiting for the room to clear
	wait_for = 20
	return TRUE

/datum/bot_step/paced/stalk/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	return moment_found ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Until they're dead. The sword comes out and on at the last moment; failing a sword, fists.
/datum/bot_step/paced/strike
	max_clicks = 80

/datum/bot_step/paced/strike/start(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	if(!QDELETED(G.sword) && bot.ready_in_hand(G.sword) && !G.sword.active)
		bot.toggle_in_hand(G.sword)
	return TRUE

/datum/bot_step/paced/strike/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	if(QDELETED(V) || V.stat == DEAD)
		return FALSE
	if(!bot.owner.Adjacent(V))
		if(get_dist(bot.owner, V) > BOT_SIGHT_RANGE)
			return FALSE //got away
		bot.combat_chase(V)
		wait_for = 5
		return TRUE
	bot.stop_pursuit()
	if(!QDELETED(G.sword) && (G.sword in bot.owner.held_items))
		bot.use_item_on(G.sword, V, harm = TRUE)
	else
		bot.owner.a_intent = INTENT_HARM
		bot.owner.UnarmedAttack(V, TRUE)
		bot.owner.a_intent = INTENT_HELP
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.try_combat_sidestep(V)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/strike/finish(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	bot.stop_pursuit()
	bot.put_sword_away(G?.sword)
	var/mob/living/V = G?.victim()
	if(V && V.stat == DEAD)
		bot_log(bot, "[V] is dead")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

#undef BOT_TRAITOR_SETTLE_IN
#undef BOT_TRAITOR_PARK
