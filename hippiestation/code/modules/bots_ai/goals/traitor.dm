// Playing a traitor.
//
// A round with no antagonists has nothing happening in it, and a mode only picks antagonists from players with clients,
// so without this a crew of bots never has one. bot_make_traitors() gives a few of them the real antagonist datum, with
// the game's own objectives, and they go about those the way a player does: get on with the job for a while so nobody
// looks twice, buy what's needed off the uplink hidden in the PDA, and pick a moment. What comes of it is the game's own
// too: a bot seen doing it gets reported and arrested like anybody else (goals/security_patrol.dm).
//
//  - First, an emag off the uplink, the same as most players' first buy: a door or a locker its ID doesn't open is a swipe
//    of the card, and a door done that way stays open behind it.
//  - Steal (a named item): breaks in if it has to, takes it, and keeps it in the bag, whatever has to come out to fit it.
//  - Kill (assassinate, maroon): an energy sword off the uplink, then it follows the target about until there's a moment,
//    and does it. The first try wants nobody else in sight. Every try that comes to nothing makes it less fussy, and with
//    the shuttle on its way it takes what it can get.
//  - Escape is what the crew does anyway (goals/evacuate.dm).
//
// Objectives it has no way of doing yet (hijack, download a research disk...) are left alone, as a player leaves the
// hard ones. Being arrested, it doesn't try to escape; a player would.

/// How long something that didn't work is left before trying again.
#define BOT_TRAITOR_PARK (2 MINUTES)
/// How long it stays on somebody's heels, waiting for its moment.
#define BOT_STALK_TIME (150 SECONDS)

/datum/bot_brain
	/// Objective -> when it's worth another try.
	var/list/objectives_parked
	/// When a traitor starts on its objectives.
	var/traitor_business_after = 0
	/// Set while the game puts things on this bot, for the telemetry to leave alone.
	var/being_issued_kit = FALSE
	/// Whether it's been through the uplink yet.
	var/traitor_shopped = FALSE
	/// How many times it's stood beside somebody and never got its moment.
	var/failed_goes = 0

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
		. += H

/// The real antagonist datum, and what it hands out. The game puts a traitor's kit on it (a pinpointer, a folder of
/// documents), which is no more the bot's doing than its uniform: that isn't a robotic tell.
/datum/bot_brain/proc/become_traitor()
	being_issued_kit = TRUE
	. = owner.mind.add_antag_datum(/datum/antagonist/traitor)
	being_issued_kit = FALSE

/// However it came about (the round type, an admin's traitor panel, bot_make_traitors()), a bot given the role plays it.
/datum/antagonist/traitor/on_gain()
	. = ..()
	var/mob/living/carbon/human/H = owner?.current
	if(!istype(H) || !H.bot_brain || H.bot_brain.bot_traitor)
		return
	H.bot_brain.bot_traitor = TRUE
	if(!H.bot_brain.gym_run) //a Bot Gym scenario sets out what it's testing
		H.bot_brain.pick_traitor_plan() //goals/robust.dm
	bot_log(H.bot_brain, "I'm a traitor: [jointext(H.bot_brain.objective_list(), "; ")]")

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
		if(plays_robust())
			return null //next_victim() has them at the top of its list, goals/robust.dm
		return O.target?.current ? new /datum/bot_goal/traitor_kill(O) : null
	if(istype(O, /datum/objective/download))
		return new /datum/bot_goal/traitor_download(O) //goals/traitor_objectives.dm
	return null

/datum/bot_duty/traitor
	name = "the Syndicate's business"
	tier = BOT_DUTY_URGENT //the work tier never comes round for anybody with a job that's never finished
	priority = 8
	interval_min = 300
	interval_max = 900

/datum/bot_duty/traitor/next_look(datum/bot_brain/bot)
	return bot.gone_loud() ? 30 : ..()

/datum/bot_duty/traitor/try_start(datum/bot_brain/bot)
	var/datum/antagonist/traitor/T = bot.owner.mind?.has_antag_datum(/datum/antagonist/traitor)
	if(!T)
		return FALSE
	if(bot.gone_loud() && !bot.plays_robust()) //goals/robust.dm: undercover until it's caught
		bot.turn_hostile()
	if(!EMERGENCY_IDLE_OR_RECALLED)
		bot.consider_going_out_swinging() //goals/robust.dm
	if(world.time < bot.traitor_business_after && EMERGENCY_IDLE_OR_RECALLED && !bot.gone_loud()) //there's no settling in with the shuttle on its way
		return FALSE
	bot.try_codewords()
	if(!bot.traitor_shopped)
		bot.traitor_shopped = TRUE
		if(bot.assign_goal(new /datum/bot_goal/traitor_shop()))
			return TRUE
		if(bot.plays_robust() && !bot.nanosuit_on())
			bot.traitor_shopped = FALSE //somebody watching and nowhere out of sight to go: the suit another time
	if(bot.plays_robust())
		return bot.robust_business() //goals/robust.dm
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
			var/obj/item/at_feet = locate(item_path) in get_turf(owner) //both hands full, and that's where it lands
			if(at_feet)
				try_pickup_target(at_feet)
			return
	U.locked = TRUE
	return FALSE

/// A word with the PDA, somewhere it won't be read over the shoulder.
/datum/bot_goal/traitor_shop
	doing = "checking my messages"

/datum/bot_goal/traitor_shop/resolve_target(datum/bot_brain/bot)
	// Somewhere nobody's looking, for one about to change into a nanosuit. A cook bought one and put it on in the hallway outside the
	// HoP's office, stripping in front of an assistant, and Security had his name on the radio within a second.
	if(bot.plays_robust() && !bot.nanosuit_on() && bot.watched_by_anyone())
		target = bot.quiet_spot() //goals/robust.dm: or nowhere just now, and the duty looks again later
		return
	target = bot.owner

/datum/bot_goal/traitor_shop/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_shop/S = new
	S.steps = target == bot.owner ? list(new /datum/bot_step/traitor_shop()) : list(new /datum/bot_step/move_to(), new /datum/bot_step/traitor_shop())
	return list(S)

/// Anybody up and able to see it from where they stand, crew or silicon: what a traitor waits for an empty corridor for.
/datum/bot_brain/proc/watched_by_anyone()
	for(var/mob/living/L in view(BOT_SIGHT_RANGE, owner))
		if(L == owner || L.stat != CONSCIOUS || !(ishuman(L) || issilicon(L)) || is_blind(L))
			continue
		return TRUE
	return FALSE

/datum/bot_strategy/traitor_shop/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/traitor_shop/execute(datum/bot_brain/bot)
	if(bot.hijack_objective() && !bot.find_carried_tool(/obj/item/melee/transforming/energy/sword) && bot.buy_from_uplink(/obj/item/melee/transforming/energy/sword/saber))
		var/obj/item/sword = bot.find_carried_tool(/obj/item/melee/transforming/energy/sword) //a shuttle full of people to get through (goals/traitor_objectives.dm)
		bot_log(bot, "bought [sword || "nothing"] off the uplink")
		bot.put_away(sword)
	if(bot.plays_robust())
		if(!bot.nanosuit_on() && bot.watched_by_anyone())
			bot.traitor_shopped = FALSE //somebody's turned up: another spot, another go
			return GOAL_STEP_FAIL
		if(bot.buy_nanosuit()) //goals/robust.dm
			bot.put_on_nanosuit()
		return GOAL_STEP_SUCCESS
	if(!bot.find_carried_tool(/obj/item/card/emag) && bot.buy_from_uplink(/obj/item/card/emag))
		var/obj/item/card/emag/E = bot.find_carried_tool(/obj/item/card/emag)
		bot_log(bot, "bought [E || "nothing"] off the uplink")
		bot.put_away(E)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Stealing
// ---------------------------------------------------------------------------------------------

/// A strategy that breaks a locked thing open and takes this item out of what falls out.
/datum/bot_strategy/brute_force/theft/New(item_type)
	. = ..()
	steps[length(steps)] = new /datum/bot_step/pickup_from_target(item_type)

/// A locked locker, and a card that scrambles the lock.
/datum/bot_strategy/emag_theft/New(item_type)
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/swipe_emag(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(item_type))

/datum/bot_strategy/emag_theft/is_feasible(datum/bot_brain/bot)
	return bot.find_carried_tool(/obj/item/card/emag)

/datum/bot_step/swipe_emag/execute(datum/bot_brain/bot)
	var/obj/structure/closet/C = bot.current_goal?.target
	var/obj/item/card/emag/E = bot.find_carried_tool(/obj/item/card/emag)
	if(!E || !istype(C) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	bot.use_item_on(E, C, harm = TRUE) //on help intent a locker only reads it as a card it doesn't know
	bot.put_away(E)
	return C.locked ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/// A display case, which takes no card. It goes off when it breaks, so it's done quickly, with the sword if there is one.
/datum/bot_strategy/smash_theft/New(item_type)
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/smash_open(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(item_type))

/datum/bot_strategy/smash_theft/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/paced/smash_open
	max_clicks = 30
	var/obj/item/weapon

/datum/bot_step/paced/smash_open/start(datum/bot_brain/bot)
	var/obj/structure/displaycase/case = bot.current_goal?.target
	if(!istype(case) || !bot.owner.Adjacent(case))
		return FALSE
	var/obj/item/melee/transforming/energy/sword/S = bot.find_carried_tool(/obj/item/melee/transforming/energy/sword)
	if(!S && bot.buy_from_uplink(/obj/item/melee/transforming/energy/sword/saber))
		S = bot.find_carried_tool(/obj/item/melee/transforming/energy/sword)
	if(S && bot.ready_in_hand(S))
		if(!S.active)
			bot.toggle_in_hand(S)
		weapon = S
	else
		weapon = bot.ready_fireaxe()
	return !!weapon

/datum/bot_step/paced/smash_open/do_click(datum/bot_brain/bot)
	var/obj/structure/displaycase/case = bot.current_goal?.target
	if(!istype(case) || QDELETED(case) || case.broken || !bot.owner.Adjacent(case) || !(weapon in bot.owner.held_items))
		return FALSE
	bot.use_item_on(weapon, case, harm = TRUE)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/smash_open/finish(datum/bot_brain/bot)
	var/obj/structure/displaycase/case = bot.current_goal?.target
	if(istype(weapon, /obj/item/melee/transforming/energy/sword))
		bot.put_sword_away(weapon)
	else
		bot.stow_or_drop(weapon)
	return istype(case) && case.broken ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Out of a smart fridge the way anybody gets anything out of one: there's no lock on it to break.
/datum/bot_strategy/fridge_theft/New(item_type)
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/release_from_fridge(item_type))

/datum/bot_strategy/fridge_theft/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/release_from_fridge
	var/item_type

/datum/bot_step/release_from_fridge/New(item_type)
	. = ..()
	src.item_type = item_type

/datum/bot_step/release_from_fridge/execute(datum/bot_brain/bot)
	var/obj/machinery/smartfridge/fridge = bot.current_goal?.target
	if(!istype(fridge) || !bot.owner.Adjacent(fridge))
		return GOAL_STEP_FAIL
	bot.human_pause(fridge)
	var/obj/item/I = locate(item_type) in fridge
	if(QDELETED(fridge) || !I || !bot.owner.Adjacent(fridge))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(fridge)
	bot.telemetry_ui_action(fridge, "release [I.name]")
	if(bot.owner.get_active_held_item() && bot.owner.get_inactive_held_item())
		bot.put_away(bot.owner.get_active_held_item(), allow_equip = FALSE)
	return bot.owner.put_in_hands(I) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Whether something's on a person, in a pocket or a bag, whatever they're lying in at the time.
/proc/bot_on_somebody(atom/movable/A)
	while(A && !isturf(A))
		if(ismob(A))
			return TRUE
		A = A.loc
	return FALSE

/// What's not coming out of the bag to make room.
/datum/bot_brain/proc/keeps_in_bag(obj/item/I)
	if(istype(I, /obj/item/card/emag) || istype(I, /obj/item/melee/transforming/energy/sword) || istype(I, /obj/item/tank) || istype(I, /obj/item/storage/box/survival) || I.GetComponent(/datum/component/uplink))
		return TRUE
	var/datum/antagonist/traitor/T = owner.mind?.has_antag_datum(/datum/antagonist/traitor) || null //it's 0 for anybody else, and 0?.objectives throws
	for(var/datum/objective/steal/S in T?.objectives)
		if(S.steal_target && istype(I, S.steal_target))
			return TRUE
	return FALSE

/// Into the bag. A bag a bot's had all shift is full of what it found on its rounds, and something stolen and left in the hand got
/// set down the first time the hand was wanted: two traitors took the blueprints and finished the round with nothing to show for it.
/datum/bot_brain/proc/stash_stolen(obj/item/I)
	if(!I || !(I in owner.held_items) || put_away(I))
		return
	var/obj/item/storage/bag = owner.get_item_by_slot(ITEM_SLOT_BACK)
	if(!istype(bag))
		return
	for(var/size in WEIGHT_CLASS_GIGANTIC to WEIGHT_CLASS_TINY step -1)
		for(var/obj/item/junk in bag)
			if(junk.w_class != size || keeps_in_bag(junk) || !SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_TAKE, junk, owner.drop_location()))
				continue
			bot_log(src, "taking [junk] out of the bag to make room for [I]")
			if(put_away(I))
				return

/datum/bot_goal/traitor_steal
	doing = "on an errand"
	breaks_in = TRUE
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
		if(QDELETED(I) || bot_on_somebody(I) || !isturf(holder.loc) || holder.z != bot.owner.z || istype(holder, /obj/structure/safe)) //nobody here cracks a safe
			continue
		var/dist = get_dist(bot.owner, holder)
		if(!best || dist < best_dist)
			best = holder
			best_dist = dist
	target = best

/datum/bot_goal/traitor_steal/get_strategies(datum/bot_brain/bot)
	// The thing, or the box it's in (the medal's in a locked one): the box goes in the bag, and it can be got into later.
	if(isitem(target))
		return list(new /datum/bot_strategy/grab_item())
	if(istype(target, /obj/structure/closet))
		var/obj/structure/closet/C = target
		if(!C.locked || C.allowed(bot.owner))
			return list(new /datum/bot_strategy/grab_item_from_locker(item_type))
		return list(new /datum/bot_strategy/emag_theft(item_type), new /datum/bot_strategy/brute_force/theft(item_type))
	if(istype(target, /obj/structure/displaycase))
		return list(new /datum/bot_strategy/smash_theft(item_type))
	if(istype(target, /obj/machinery/smartfridge))
		return list(new /datum/bot_strategy/fridge_theft(item_type))
	if(istype(target, /obj/machinery/suit_storage_unit))
		return list(new /datum/bot_strategy/raid_ssu())
	return list(new /datum/bot_strategy/brute_force/theft(item_type))

/datum/bot_goal/traitor_steal/on_success(datum/bot_brain/bot)
	bot_log(bot, "got the [objective.targetinfo?.name || item_type]")
	var/obj/item/held = isitem(target) && (target in bot.owner.held_items) ? target : null
	bot.stash_stolen(held || bot.find_carried_tool(item_type))

/datum/bot_goal/traitor_steal/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.objectives_parked, objective, world.time + BOT_TRAITOR_PARK)

// ---------------------------------------------------------------------------------------------
// Killing
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/traitor_kill
	lawful = TRUE
	breaks_in = TRUE
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

/// How many people it'll do this in front of. Nobody, to start with. A round runs out, though, and so does its patience.
/datum/bot_brain/proc/witnesses_it_can_stand()
	. = min(failed_goes, 3)
	if(!EMERGENCY_IDLE_OR_RECALLED)
		. += 2

/// Whether this is as good a moment as it's going to get: few enough watching, an officer counting double.
/datum/bot_brain/proc/good_moment_with(mob/living/V)
	var/can_stand = witnesses_it_can_stand()
	var/watching = 0
	for(var/mob/living/L in view(BOT_SIGHT_RANGE, owner))
		if(L == owner || L == V || L.stat != CONSCIOUS || !(ishuman(L) || issilicon(L)))
			continue
		watching += (L.mind?.assigned_role in GLOB.security_positions) ? 2 : 1
		if(watching > can_stand)
			return FALSE
	return TRUE

/// Follows the target about at a distance, until there's a moment.
/datum/bot_step/paced/stalk
	var/moment_found = FALSE
	/// Whether it got to them, and there just wasn't one.
	var/waited = FALSE
	var/give_up_at = 0

/datum/bot_step/paced/stalk/start(datum/bot_brain/bot)
	moment_found = FALSE
	waited = FALSE
	give_up_at = world.time + BOT_STALK_TIME
	return TRUE

/datum/bot_step/paced/stalk/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	var/turf/there = get_turf(V)
	if(!there || V.stat == DEAD || there.z != bot.owner.z || world.time > give_up_at)
		return FALSE
	if(!isturf(V.loc)) //in a cloning pod, a sleeper, a locker: nobody can reach in there, and it needs another time
		return FALSE
	if(bot.owner.Adjacent(V) && bot.good_moment_with(V))
		moment_found = TRUE
		return FALSE
	if(get_dist(bot.owner, V) > 1 && bot.pursuing_kind != "follow")
		// No way to them (a room this ID doesn't open): that's for another time. Waiting it out at the door is the
		// one thing certain to get noticed.
		if(!bot.can_walk_lawfully_to(V))
			return FALSE
		bot.pursue(V, "follow", force = TRUE)
	else if(get_dist(bot.owner, V) <= 1)
		waited = TRUE
		bot.idle_fidget() //waiting for the room to clear
	wait_for = 20
	return TRUE

/datum/bot_step/paced/stalk/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	if(moment_found)
		return GOAL_STEP_SUCCESS
	if(waited)
		bot.failed_goes++
	return GOAL_STEP_FAIL

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
	if(QDELETED(V) || V.stat == DEAD || !isturf(V.loc))
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

#undef BOT_TRAITOR_PARK
#undef BOT_STALK_TIME
