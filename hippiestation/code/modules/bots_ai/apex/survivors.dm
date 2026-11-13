// Defenders (the plan's M6), the surviving half; the stopping half is apex/defenders.dm. The user's ruling, 2026-11-13: both, full depth.
// On a shift gone bad (goals/massacre.dm: three of the crew dead and the killer still about) the crew already panic and group up. Two
// kinds of player do more than that:
//  - The timid one, on its own with the killer in sight, doesn't cross open floor looking for company: it gets into the nearest locker the
//    killer can't see, away from them, shuts itself in and keeps still a minute or two, or until the word is they've been caught. Then it
//    comes out.
//  - The brave one with nothing to fight with gets something: a toolbox, failing that an extinguisher. Armed, the crew's own rule takes
//    over (look_out_for_trouble(), bot_witness.dm): somebody who's been hurting people is gone for on sight.

/// Below this nerve it hides rather than looks for company
#define BOT_HIDE_NERVE 0.45
/// How long it stays shut in
#define BOT_HIDE_MIN (60 SECONDS)
#define BOT_HIDE_MAX (150 SECONDS)
/// At or above this nerve, and a robust player or better, it arms itself
#define BOT_VIGILANTE_NERVE 0.7

/datum/bot_brain
	/// The locker it's hiding in (hide_in_locker), and until when it stays
	var/obj/structure/closet/hiding_spot
	var/hide_until = 0
	/// Not again until then, once it's come out
	var/next_hide = 0
	var/next_vigilante_arm = 0
	/// Which of the weapons below it's looking for next (it goes down the list as it fails to find one)
	var/vigilante_pick = 1

/// What a vigilante arms itself with, best first: things lying about the station, not the armory
GLOBAL_LIST_INIT(bot_vigilante_weapons, list(/obj/item/storage/toolbox, /obj/item/extinguisher, /obj/item/crowbar))

/datum/bot_brain/proc/hidden()
	return hiding_spot && owner.loc == hiding_spot

/// Somebody who'd hide rather than group up: timid, and nobody who's after anybody itself
/datum/bot_brain/proc/would_hide()
	return nerve < BOT_HIDE_NERVE && !is_security_job() && !bot_traitor && !op_team && !bot_wizard && !gone_loud() && !greytider

/// The locker to hide in: one in sight it can get into, nobody in it, further from the killer than from itself, and best out of the
/// killer's sight and well away from them.
/datum/bot_brain/proc/hiding_locker(mob/living/killer)
	var/list/they_see = list()
	for(var/turf/T in view(BOT_SIGHT_RANGE, killer))
		they_see[T] = TRUE
	var/obj/structure/closet/best
	var/best_score
	var/area/here = get_area(owner)
	var/list/in_sight = view(BOT_SIGHT_RANGE, owner)
	for(var/obj/structure/closet/C in range(12, owner)) //the room it's in, which it knows, and whatever else it can see
		if(get_area(C) != here && !(C in in_sight))
			continue
		if(C.anchored || C.welded || !isturf(C.loc) || istype(C, /obj/structure/closet/body_bag) || (C.locked && !C.allowed(owner)))
			continue
		if(locate(/mob/living) in C)
			continue //somebody's in it
		var/to_it = get_dist(owner, C)
		var/from_killer = get_dist(killer, C)
		if(from_killer <= 2 || from_killer < to_it)
			continue //towards them, not away
		var/score = from_killer * 2 - to_it + (they_see[get_turf(C)] ? 0 : 10)
		if(!best || score > best_score)
			best = C
			best_score = score
	return best

/// While it's hiding (the duty below asks): TRUE to stay put. Out it comes once its time's up or the killer's been dealt with (the radio
/// says so: massacre_killer() goes by the bodies and the records, not by where they are).
/datum/bot_brain/proc/keep_hiding()
	if(!hidden())
		hiding_spot = null
		return FALSE
	var/mob/living/carbon/human/killer = massacre_killer()
	if(killer && killer != owner && world.time < hide_until && state != BOT_STATE_COMBAT)
		return TRUE
	bot_log(src, killer ? "been in [hiding_spot] long enough - having a look" : "[hiding_spot]: it's over, coming out")
	bot_tally("came out of hiding")
	next_hide = world.time + 1 MINUTES
	hiding_spot = null
	INVOKE_ASYNC(owner, TYPE_VERB_REF(/mob/living, resist)) //a shut locker opens from the inside
	return FALSE

/datum/bot_duty/hide_from_killer
	name = "hiding from a killer"
	tier = BOT_DUTY_URGENT
	priority = 61 //before looking for company (group_up, 60)
	interval_min = 10
	interval_max = 20

/datum/bot_duty/hide_from_killer/try_start(datum/bot_brain/bot)
	if(bot.hidden())
		if(bot.keep_hiding())
			bot.holding_duty = src
		return FALSE
	if(world.time < bot.next_hide || !bot.would_hide() || bot.state == BOT_STATE_COMBAT || istype(bot.current_goal, /datum/bot_goal/hide_in_locker))
		return FALSE
	if(bot.owner.handcuffed || !isturf(bot.owner.loc))
		return FALSE
	var/mob/living/carbon/human/killer = bot.massacre_killer()
	if(!killer || killer == bot.owner || !(killer in view(BOT_SIGHT_RANGE, bot.owner)))
		return FALSE //only with them in sight: anywhere else, safety's in numbers (group_up)
	if(bot.with_company(killer))
		return FALSE
	var/obj/structure/closet/C = bot.hiding_locker(killer)
	if(!C)
		return FALSE
	var/datum/bot_goal/hide_in_locker/G = new()
	G.locker = C
	G.killer = WEAKREF(killer)
	bot_log(bot, "HIDING: [killer] is right there and I'm on my own - into [C]")
	return bot.assign_goal(G)

/datum/bot_duty/hide_from_killer/keep_holding(datum/bot_brain/bot)
	return bot.keep_hiding()

/datum/bot_goal/hide_in_locker
	doing = "hiding"
	braves_bad_air = TRUE //it's going nowhere
	var/obj/structure/closet/locker
	var/datum/weakref/killer

/datum/bot_goal/hide_in_locker/resolve_target(datum/bot_brain/bot)
	target = QDELETED(locker) ? null : locker

/datum/bot_goal/hide_in_locker/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/hide_in_locker/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/get_in_locker())
	return list(S)

/datum/bot_strategy/hide_in_locker/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Open it, step in, shut it on itself: a locker closes on whoever's stood in it (closet close(), take_contents()).
/datum/bot_step/paced/get_in_locker
	max_clicks = 8

/datum/bot_step/paced/get_in_locker/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/hide_in_locker/G = bot.current_goal
	var/obj/structure/closet/C = istype(G) ? G.locker : null
	if(QDELETED(C) || !isturf(C.loc) || bot.owner.loc == C)
		return FALSE
	if(bot.owner.get_active_held_item() && !bot.owner.get_inactive_held_item())
		bot.owner.swap_hand() //an empty hand to shut it with: a full one puts what it's holding in
	if(get_turf(bot.owner) == get_turf(C))
		if(C.opened)
			bot.use_atom(C)
		return TRUE
	if(!bot.owner.Adjacent(C))
		return FALSE
	if(!C.opened)
		bot.use_atom(C)
		return TRUE
	step_towards(bot.owner, C)
	return TRUE

/datum/bot_step/paced/get_in_locker/finish(datum/bot_brain/bot)
	var/datum/bot_goal/hide_in_locker/G = bot.current_goal
	if(!istype(G) || bot.owner.loc != G.locker)
		return GOAL_STEP_FAIL
	bot.hiding_spot = G.locker
	bot.hide_until = world.time + rand(BOT_HIDE_MIN, BOT_HIDE_MAX)
	bot.holding_duty = bot_duty_of(/datum/bot_duty/hide_from_killer)
	bot_log(bot, "HIDING: shut in [G.locker]")
	bot_tally("hid in a locker")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Vigilantes
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/vigilante_arm_up
	name = "arming up against a killer"
	tier = BOT_DUTY_URGENT
	priority = 59
	interval_min = 30
	interval_max = 60

/datum/bot_duty/vigilante_arm_up/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_vigilante_arm || bot.nerve < BOT_VIGILANTE_NERVE || !bot.skill_at_least(BOT_SKILL_MID) || bot.is_security_job())
		return FALSE
	if(bot.bot_traitor || bot.op_team || bot.bot_wizard || bot.gone_loud() || bot.state == BOT_STATE_COMBAT || bot.badly_hurt() || bot.has_a_weapon())
		return FALSE
	var/mob/living/carbon/human/killer = bot.massacre_killer()
	if(!killer || killer == bot.owner)
		return FALSE
	bot.next_vigilante_arm = world.time + 2 MINUTES
	var/list/weapons = GLOB.bot_vigilante_weapons
	if(bot.vigilante_pick > length(weapons))
		bot.vigilante_pick = 1
	var/obj/item/want = weapons[bot.vigilante_pick++]
	var/datum/bot_goal/acquire_item_type/G = new()
	G.item_type = want
	G.lawful = TRUE
	if(!bot.assign_goal(G))
		return FALSE
	bot_log(bot, "VIGILANTE: [killer] is killing people and I've nothing to fight with - getting \a [initial(want.name)]")
	bot_tally("vigilantes armed up")
	if(prob(50))
		bot_say(bot.owner, pick("I'm not waiting for Security.", "Right. Something to hit them with.", "Not without a fight."))
	return TRUE

#undef BOT_HIDE_NERVE
#undef BOT_HIDE_MIN
#undef BOT_HIDE_MAX
#undef BOT_VIGILANTE_NERVE
