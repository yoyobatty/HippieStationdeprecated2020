// Combat smarts (the plan's apex/combat.dm, M4). Two pieces so far, on the numbers in the meta book (foundation/meta_book.dm):
//
//  - Kiting (mid skill and up): a gun that can fire, against somebody who's only got a melee weapon coming at it. It doesn't stand and trade
//    blows when they reach it: a step back out of their reach, and the gun again. A player with a gun keeps a melee fighter at arm's length.
//  - Choosing its fights (apex): how long it'd take each of them to put the other down, from what they're holding and their armour. If they'd
//    put it down well before it could them, it gets out, brave or not, hurt or not; if it'd put them down well first, it stays in, hurt or
//    not. In between, the usual rules (nerve, how hurt it is: try_run_for_it(), bot_brain.dm).

/// How much faster they'd have to be at putting it down before it gets out, and it at putting them down before it stays in hurt
#define BOT_WITHDRAW_RATIO 1.8
#define BOT_PRESS_RATIO 1.5

/datum/bot_brain
	var/next_kite = 0
	/// The one it's backing off from between decisions (kite_tick()), and which loop is the live one
	var/datum/weakref/kiting_against
	var/kite_chain = 0
	/// The last thing it decided about a fight, and who with, so it's said once
	var/last_estimate
	var/datum/weakref/last_estimate_foe

/// From handle_combat() (bot_brain.dm). TRUE if it stepped back this time.
/datum/bot_brain/proc/try_kite(mob/living/foe)
	if(!foe || !skill_at_least(BOT_SKILL_MID) || get_dist(owner, foe) > BOT_SIGHT_RANGE)
		return FALSE
	var/obj/item/gun/G = find_usable_gun()
	if(!G)
		return FALSE
	var/list/theirs = bot_threat_of(foe)
	if(theirs[2] > 0 || theirs[3])
		return FALSE //they shoot too: that's cover (threat_read.dm), not distance
	if(kiting_against?.resolve() != foe) //backing off between decisions, from the moment they're coming (kite_tick())
		kiting_against = WEAKREF(foe)
		kite_tick(++kite_chain)
	if(world.time < next_kite || get_dist(owner, foe) > 2)
		return FALSE
	var/turf/was = get_turf(owner)
	stop_pursuit()
	step_back_from(foe) //goals/security_tactics.dm: only a step that gets it further off
	if(get_turf(owner) == was)
		return FALSE //backed into a corner: it fights where it is
	next_kite = world.time + max(owner.movement_delay(), 2)
	bot_tally("kited")
	try_attack_from_range(foe) //and the shot, in the same breath: stepping back and firing, the way a player does it
	return TRUE

/// Its combat decisions come once a second, and somebody running at it covers a few tiles in that: between them it keeps backing off at a
/// walk while they're within three tiles, as a player holding the key down does. The shots stay with handle_combat().
/datum/bot_brain/proc/kite_tick(chain)
	if(QDELETED(src) || QDELETED(owner) || chain != kite_chain)
		return
	var/mob/living/foe = kiting_against?.resolve()
	if(!foe || QDELETED(foe) || foe.stat != CONSCIOUS || state != BOT_STATE_COMBAT || attacker != foe || owner.incapacitated() || !isturf(owner.loc) 		|| bot_holds_gun(foe) || !find_usable_gun())
		kiting_against = null
		return
	if(get_dist(owner, foe) <= 3 && !pursuing_kind)
		step_back_from(foe)
	addtimer(CALLBACK(src, PROC_REF(kite_tick), chain), max(owner.movement_delay(), 2))

/// "withdraw", "press", or null for the usual rules (above). Apex only.
/datum/bot_brain/proc/fight_estimate(mob/living/foe)
	if(!foe || !is_apex() || !isliving(foe))
		return null
	var/mine = bot_time_to_down(foe, owner)
	var/theirs = bot_time_to_down(owner, foe)
	. = null
	if(theirs * BOT_WITHDRAW_RATIO < mine)
		. = "withdraw"
	else if(mine * BOT_PRESS_RATIO < theirs)
		. = "press"
	if(. && (. != last_estimate || last_estimate_foe?.resolve() != foe))
		last_estimate = .
		last_estimate_foe = WEAKREF(foe)
		bot_log(src, "COMBAT: [foe] would put me down in [round(theirs, 0.1)] s, me them in [round(mine, 0.1)] s - [. == "withdraw" ? "getting out" : "staying in"]")

#undef BOT_WITHDRAW_RATIO
#undef BOT_PRESS_RATIO

// ---------------------------------------------------------------------------------------------
// The melee meta (apex)
// ---------------------------------------------------------------------------------------------
// On this server a disarm pushes somebody over a quarter of the time, and they're down four seconds (hippiestation species.dm disarm()):
// five free blows with whatever's in the other hand. So against somebody on their feet an apex fighter shoves with its free hand till
// they go down, and hits them with the weapon while they're down. Holding something in the hand it shoves with makes it a blow, not a shove:
// it swaps to the empty hand to shove and back to the weapon to hit, as a player does.

/// From fight_in_reach() (bot_fighting.dm). TRUE if it's handled this click.
/datum/bot_brain/proc/apex_melee(mob/living/target)
	if(!is_apex() || !ishuman(target) || fights_barehanded())
		return FALSE
	var/obj/item/weapon = weapon_to_hand()
	if(target.mobility_flags & MOBILITY_STAND)
		// A shove, with the empty hand
		if(owner.get_active_held_item())
			if(owner.get_inactive_held_item())
				return FALSE //both hands full: the weapon it is
			owner.swap_hand()
		owner.a_intent = INTENT_DISARM
		telemetry_clicked(target)
		owner.UnarmedAttack(target, TRUE)
		bot_log(src, "COMBAT: shoving [target] to put them down")
		return TRUE
	// Down: the weapon, while they're down
	if(weapon)
		owner.a_intent = INTENT_HARM
		telemetry_clicked(target)
		weapon.melee_attack_chain(owner, target)
		bot_log(src, "hitting [target] with [weapon] while they're down")
		return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Strafing (apex)
// ---------------------------------------------------------------------------------------------
// A player shooting at you clicks where they saw you a moment ago: the shot lands almost at once, but on where you were. In a gunfight
// a player who knows it doesn't stand still: a step across the line of fire every third of a second or so, this way then that, so the
// shots coming back are aimed at where they've just left. (A bot shooter aims at where you are now, so it's against players this tells.)

/datum/bot_brain
	var/next_strafe = 0
	/// Which way across it went last, and how many steps that way: two at most, then back, a zig-zag rather than a walk off to one side
	var/strafe_side = 90
	var/strafe_run = 0
	/// The one it's strafing against, while the loop (strafe_tick()) runs, and which loop is the live one
	var/datum/weakref/strafing_against
	var/strafe_chain = 0

/// From handle_combat() (bot_brain.dm), after a shot or while the gun recharges: starts the strafe loop. TRUE if it's strafing.
/datum/bot_brain/proc/try_strafe(mob/living/foe)
	if(!strafe_worth_it(foe))
		return FALSE
	if(strafing_against?.resolve() == foe)
		return TRUE //already at it
	strafing_against = WEAKREF(foe)
	stop_pursuit()
	bot_log(src, "COMBAT: strafing across [foe]'s line of fire")
	bot_tally("strafed")
	strafe_tick(++strafe_chain) //a new foe: the old loop sees it's not the live one and stops
	return TRUE

/datum/bot_brain/proc/strafe_worth_it(mob/living/foe)
	if(dark_spot && world.time < dark_until && get_turf(owner) == dark_spot)
		return FALSE //firing from the dark (foundation/gunfight.dm): a step across their line is a step into the light
	return foe && !QDELETED(foe) && foe.stat == CONSCIOUS && is_apex() && state == BOT_STATE_COMBAT && attacker == foe && bot_holds_gun(foe) 		&& isturf(owner.loc) && get_dist(owner, foe) >= 3 && get_dist(owner, foe) <= BOT_SIGHT_RANGE && !owner.incapacitated()

/// A step across their line every third to half a second, as a player tapping one way and the other, for as long as the gunfight lasts.
/datum/bot_brain/proc/strafe_tick(chain)
	if(QDELETED(src) || QDELETED(owner) || chain != strafe_chain)
		return
	var/mob/living/foe = strafing_against?.resolve()
	if(!strafe_worth_it(foe))
		strafing_against = null
		return
	if(!pursuing_kind) //something else has it walking (a shot it's lining up, a step back): that comes first
		strafe_step(foe)
	addtimer(CALLBACK(src, PROC_REF(strafe_tick), chain), max(owner.movement_delay(), rand(3, 5)))

/datum/bot_brain/proc/strafe_step(mob/living/foe)
	var/toward = get_dir(owner, foe)
	var/turf/here = get_turf(owner)
	if(strafe_run >= 2)
		strafe_side = -strafe_side
		strafe_run = 0
	for(var/side in list(strafe_side, -strafe_side))
		var/turf/T = get_step(here, turn(toward, side))
		if(!T || T.density || isspaceturf(T) || is_blocked_turf(T, TRUE) || bot_turf_is_deadly(T))
			continue
		if(get_dist(T, foe) < 3 || get_dist(T, foe) >= BOT_SIGHT_RANGE || !bot_clear_line(T, foe))
			continue //not into their arms, not out of its own range, and not out of its own line on them
		if(!step(owner, get_dir(here, T)))
			continue
		if(side != strafe_side)
			strafe_side = side
			strafe_run = 0
		strafe_run++
		return TRUE
	return FALSE
