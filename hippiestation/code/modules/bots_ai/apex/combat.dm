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
	/// The last thing it decided about a fight, and who with, so it's said once
	var/last_estimate
	var/datum/weakref/last_estimate_foe

/// From handle_combat() (bot_brain.dm). TRUE if it stepped back this time.
/datum/bot_brain/proc/try_kite(mob/living/foe)
	if(!foe || world.time < next_kite || !skill_at_least(BOT_SKILL_MID) || get_dist(owner, foe) > 2)
		return FALSE
	var/obj/item/gun/G = find_usable_gun()
	if(!G)
		return FALSE
	var/list/theirs = bot_threat_of(foe)
	if(theirs[2] > 0 || theirs[3])
		return FALSE //they shoot too: that's cover (threat_read.dm), not distance
	var/turf/was = get_turf(owner)
	stop_pursuit()
	step_back_from(foe) //goals/security_tactics.dm: only a step that gets it further off
	if(get_turf(owner) == was)
		return FALSE //backed into a corner: it fights where it is
	next_kite = world.time + max(owner.movement_delay(), 2)
	bot_tally("kited")
	try_attack_from_range(foe) //and the shot, in the same breath: stepping back and firing, the way a player does it
	return TRUE

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
