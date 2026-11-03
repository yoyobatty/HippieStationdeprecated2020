// Fighting: what a bot does once a fight is on (handle_combat(), bot_brain.dm). It used to be fists and a sidestep.
//
//  - It reaches for the heaviest thing on it or within arm's reach, and a dropped weapon doesn't stay dropped.
//  - On this server a disarm is the strongest thing in a melee (a quarter of them put somebody on the floor for 4 seconds,
//    species/disarm()), so a good third of its clicks are disarms, more against somebody armed. Anybody down gets kicked:
//    kicks never miss.
//  - Out of reach, a gun if it has one, and sometimes whatever's in its hand gets thrown.
//  - Somebody with a fire axe, against bare hands, is run away from, sooner the less nerve it has.

/// Force at which something in somebody's hand is a reason to run from them.
#define BOT_FIGHT_DANGEROUS_FORCE 15

/datum/bot_brain
	/// When it next looks for something to hit with.
	var/next_weapon_reach = 0

/// How hard this hits in a bot's hands.
/proc/bot_weapon_force(obj/item/I)
	if(I.item_flags & (NOBLUDGEON|ABSTRACT))
		return 0
	var/obj/item/twohanded/fireaxe/axe = I
	return istype(axe) ? axe.force_wielded : I.force

/// Gets something to hit with into its hands: from the bag, or within arm's reach. Nobody in a fight leaves a toolbox in
/// their backpack, or steps over the crowbar they just knocked out of somebody's hand.
/datum/bot_brain/proc/reach_for_weapon()
	if(world.time < next_weapon_reach)
		return
	next_weapon_reach = world.time + 4 SECONDS
	var/obj/item/melee/transforming/energy/sword/sword = find_carried_tool(/obj/item/melee/transforming/energy/sword)
	if(sword)
		if(!sword.active)
			INVOKE_ASYNC(src, PROC_REF(toggle_in_hand), sword)
		return
	if(weapon_to_hand())
		return
	breach_kit_cache = null
	var/obj/item/best
	var/best_force = BOT_COMBAT_WEAPON_FORCE - 1
	for(var/atom/source in get_breach_kit())
		var/obj/item/I = source
		if(!istype(I) || QDELETED(I) || istype(I, /obj/item/gun))
			continue
		if(!is_carried(I) && (!isturf(I.loc) || get_dist(owner, I) > 1))
			continue
		var/force = bot_weapon_force(I)
		if(force > best_force)
			best = I
			best_force = force
	if(!best)
		return
	bot_log(src, "reaching for [best]")
	if(istype(best, /obj/item/twohanded/fireaxe) && is_carried(best))
		INVOKE_ASYNC(src, PROC_REF(ready_fireaxe))
	else if(is_carried(best))
		ready_in_hand(best)
	else
		INVOKE_ASYNC(src, PROC_REF(take_back), best)

/// One click at somebody within reach.
/datum/bot_brain/proc/fight_in_reach(mob/living/target)
	owner.changeNext_move(CLICK_CD_MELEE)
	owner.face_atom(target)
	var/obj/item/weapon = fights_barehanded() ? null : weapon_to_hand() //goals/robust.dm
	var/intent = pick_combat_intent(target)
	if(weapon && (intent != INTENT_DISARM || !target.get_active_held_item())) //anything in hand is swung, unless what they're holding wants knocking away
		owner.a_intent = INTENT_HARM
		telemetry_clicked(target)
		weapon.melee_attack_chain(owner, target)
		bot_log(src, "hitting [target] with [weapon]")
		return
	owner.a_intent = intent
	telemetry_clicked(target)
	owner.UnarmedAttack(target, TRUE)
	bot_log(src, "attacking [target] ([owner.a_intent])")

/// Shoves as often as blows, the way a player on this server fights. Anybody on the floor just gets the boot.
/datum/bot_brain/proc/pick_combat_intent(mob/living/target)
	if(!(target.mobility_flags & MOBILITY_STAND))
		return INTENT_HARM
	if(plays_robust()) //goals/robust.dm: 91% of the clicks of the player it's modelled on were on harm
		return prob(10) ? INTENT_DISARM : INTENT_HARM
	var/obj/item/theirs = target.get_active_held_item()
	if(theirs && prob(theirs.force >= BOT_COMBAT_WEAPON_FORCE ? 60 : 40))
		return INTENT_DISARM
	return prob(35) ? INTENT_DISARM : INTENT_HARM

/// Whether it's worth seeing this one through to the end: they've got a real weapon, they're a killer or wrecking the place,
/// it isn't a person at all, or this bot is in real trouble.
/datum/bot_brain/proc/fight_is_serious(mob/living/foe)
	if(!ishuman(foe) || owner.health < owner.maxHealth * 0.4)
		return TRUE
	var/obj/item/theirs = foe.get_active_held_item()
	if(theirs?.force >= 10)
		return TRUE
	var/datum/bot_wanted/W = bot_get_wanted_entry(foe)
	return W && W.severity >= BOT_CRIME_MAJOR

/// A scuffle between crew is over once one side has plainly lost. Two of them kicked a cook to death in a bar over a
/// quarrel, twenty seconds from the first shove: he'd been on the floor for most of it. That's for somebody out to kill.
/datum/bot_brain/proc/fight_is_won(mob/living/foe)
	if(fight_is_serious(foe) || up_to_no_good() && istype(current_goal, /datum/bot_goal/traitor_kill))
		return FALSE
	if(foe.health > foe.maxHealth * 0.6)
		return FALSE
	if(prob(50))
		bot_say(owner, pick("Stay down.", "Had enough?", "That'll teach you.", "Stay out of my way.", "Don't try that again."))
	LAZYREMOVE(grudges, WEAKREF(foe))
	trouble_until = 0
	return TRUE

/// Whether foe is holding something this bot has no answer to.
/datum/bot_brain/proc/outmatched_by(mob/living/foe)
	var/obj/item/theirs = foe?.get_active_held_item()
	if(!theirs || theirs.force < BOT_FIGHT_DANGEROUS_FORCE)
		return FALSE
	var/obj/item/mine = owner.get_active_held_item()
	return !mine || mine.force * 2 <= theirs.force

/// Share of its health at which this bot stops fighting and runs: the less nerve, the sooner.
/datum/bot_brain/proc/health_to_run_at()
	if(plays_robust()) //goals/robust.dm: it goes while there's still time, and it means to come back
		return 0.5
	return BOT_COMBAT_RUN_AT + (0.5 - nerve) * 0.5

/// Somebody out of reach and still a threat: shot if it has a gun, or sometimes pelted with what's in its hand.
/datum/bot_brain/proc/try_attack_from_range(mob/living/target)
	var/dist = get_dist(owner, target)
	if(bot_wizard && dist <= BOT_SIGHT_RANGE && (wizard_escape() || wizard_cast_at(target))) //goals/wizard.dm
		return TRUE
	if(dist < 2 || dist > BOT_SIGHT_RANGE)
		return FALSE
	if(try_shoot_at(target))
		return TRUE
	return dist <= 4 && try_throw_at(target)

/datum/bot_brain/proc/try_shoot_at(mob/living/target)
	if(world.time < next_taser_time)
		return FALSE
	var/obj/item/gun/G = find_carried_tool(/obj/item/gun)
	if(!G || !G.can_shoot() || !has_clear_shot(target) || !ready_in_hand(G))
		return FALSE
	owner.a_intent = INTENT_HARM
	owner.face_atom(target)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
	bot_log(src, "firing [G] at [target] (dist [get_dist(owner, target)])")
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), target, owner, FALSE, null)
	return TRUE

/datum/bot_brain/proc/try_throw_at(mob/living/target)
	var/obj/item/I = owner.get_active_held_item()
	if(!I || I.throwforce < 10 || HAS_TRAIT(I, TRAIT_NODROP) || !prob(20 + temper * 30) || !has_clear_shot(target))
		return FALSE
	owner.face_atom(target)
	owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(src, "throwing [I] at [target]")
	owner.throw_item(target)
	return TRUE

// ---------------------------------------------------------------------------------------------
// Getting away
// ---------------------------------------------------------------------------------------------

/// Off out of the way of somebody, as far off as it can think of, by the doors it can open.
/datum/bot_goal/run_from
	lawful = TRUE
	never_rests = TRUE
	doing = "getting away from somebody"
	var/datum/weakref/foe_ref

/datum/bot_goal/run_from/New(atom/foe)
	. = ..()
	foe_ref = WEAKREF(foe)

/datum/bot_goal/run_from/resolve_target(datum/bot_brain/bot)
	var/atom/foe = foe_ref?.resolve()
	var/best_score
	for(var/i in 1 to 5)
		var/turf/T = bot.gym_run ? bot.pick_local_destination() : (bot.pick_poi_destination() || bot.pick_local_destination())
		if(!T)
			continue
		var/score = (foe ? get_dist(T, foe) : 0) - get_dist(T, bot.owner) / 2
		if(!target || score > best_score)
			target = T
			best_score = score

/datum/bot_goal/run_from/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/run_from/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/datum/bot_strategy/run_from/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Drops what it's doing and goes. TRUE if it's on its way.
/datum/bot_brain/proc/run_from(atom/foe, reason)
	if(state == BOT_STATE_ARREST || owner.incapacitated())
		return FALSE
	bot_log(src, "getting away from [foe] ([reason])")
	bot_tally("ran")
	state_before_combat = null
	drop_goals(reason)
	return assign_goal(new /datum/bot_goal/run_from(foe))

#undef BOT_FIGHT_DANGEROUS_FORCE
