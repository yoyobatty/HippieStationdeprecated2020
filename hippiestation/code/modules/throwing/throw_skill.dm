// Throwing: how well somebody throws, and the toss (see throw_flight.dm).
//  - A throw goes where it's aimed only for somebody fit to throw. Drunk, dizzy, confused, jittery, blurred or blind, worn out,
//    throwing with a hurt arm or from the floor, it wanders off the mark, more the further it's thrown. Sober and well it's as before.
//  - The same things take the strength out of it (shorter), and a hulk throws half as far again and faster.
//  - A thrown thing hits as hard as it's going: a running throw harder, by the square root of how much faster than the thing's own
//    throw it went.
//  - On help intent, something that can't hurt anybody (no edge or point, not hot, nothing in it, under 10 throwforce, and none of
//    the things a throw sets off: grenades, restraints, food, bluespace crystals, boomerangs and the like) is tossed: a slower lob
//    that does no harm. The one it's tossed to catches it with a free hand if they're awake, can see and are facing that way (or
//    are right there), unless they're too drunk or shaky; otherwise it lands at their feet. Harm intent throws are as before. A
//    toss goes a whole number of ticks a tile (throw_even_speed()), so it glides evenly, and a pacifist can toss what they can't throw.
//
// Also a tg slip fixed: a thrown open beaker that's caught (throw mode) no longer splashes whoever caught it (reagent_containers.dm).

/// Under this throwforce a thing can be tossed
#define THROW_TOSS_MAX_FORCE 10
/// How fast a toss goes, at most, in tiles a decisecond
#define THROW_TOSS_SPEED 1.5
/// Tiles off the mark a throw can wander, per tile thrown, per point of wobble
#define THROW_WOBBLE_SPREAD 0.35

/// Things a throw sets something off with, or that are thrown at people for what they do: never tossed, whatever the intent
GLOBAL_LIST_INIT(throw_never_tossed, typecacheof(list(
	/obj/item/grenade,
	/obj/item/restraints,
	/obj/item/reagent_containers/food,
	/obj/item/stack/ore/bluespace_crystal,
	/obj/item/stack/sheet/bluespace_crystal,
	/obj/item/boomerang,
	/obj/item/spellpacket,
	/obj/item/holopuck,
	/obj/item/bowling,
	/obj/item/toy/snowball,
	/obj/item/toy/minimeteor,
	/obj/item/toy/snappop,
	/obj/item/toy/balloon,
	/obj/item/shard,
	/obj/item/dice,
)))

/// Whether this can be tossed: nothing about it that a throw would hurt somebody with or set off
/proc/throw_is_harmless(obj/item/I)
	if(!istype(I) || I.throwforce >= THROW_TOSS_MAX_FORCE)
		return FALSE
	if(is_type_in_typecache(I, GLOB.throw_never_tossed))
		return FALSE
	if(I.is_sharp() || is_pointed(I) || can_embed(I) || I.is_hot())
		return FALSE
	if(I.reagents && I.reagents.total_volume)
		return FALSE
	return TRUE

/// How much the throwing arm's hurt: 0 for fine to 1 for useless (or missing)
/mob/living/carbon/proc/throwing_arm_hurt()
	if(active_hand_index > length(hand_bodyparts))
		return 1
	var/obj/item/bodypart/BP = hand_bodyparts[active_hand_index]
	if(!BP || BP.disabled)
		return 1
	if(!BP.max_damage)
		return 0
	return clamp((BP.brute_dam + BP.burn_dam) / BP.max_damage, 0, 1)

/// How unsteady a throw is just now: 0 for steady, about 1 for very drunk, over 1 blind
/mob/living/carbon/proc/throw_wobble()
	. = 0
	if(drunkenness > 20)
		. += min((drunkenness - 20) / 100, 0.6)
	if(dizziness)
		. += clamp(dizziness / 100, 0.1, 0.5)
	if(confused)
		. += 0.3
	if(jitteriness)
		. += clamp(jitteriness / 400, 0.05, 0.3)
	if(eye_blurry)
		. += 0.2
	if(eye_blind || HAS_TRAIT(src, TRAIT_BLIND))
		. += 1
	var/stamina = getStaminaLoss()
	if(stamina > 30)
		. += min((stamina - 30) / 150, 0.45)
	. += throwing_arm_hurt() * 0.4
	if(!(mobility_flags & MOBILITY_STAND))
		. += 0.3

/// How far a throw goes against a fit thrower's: 1 for as far, up to 1.5 for a hulk, down to about a tenth worn out on the floor
/mob/living/carbon/proc/throw_strength()
	. = 1
	if(dna && dna.check_mutation(HULK))
		. *= 1.5
	var/stamina = getStaminaLoss()
	if(stamina > 40)
		. *= 1 - min((stamina - 40) / 120, 0.5)
	. *= 1 - throwing_arm_hurt() * 0.5
	if(!(mobility_flags & MOBILITY_STAND))
		. *= 0.5

/**
 * What a throw from throw_item() comes to. Returns list(target, range, speed, gentle, wild): where it goes (a turf off the mark if
 * it wanders), how far and fast, whether it's a toss, and whether it's thrown wildly (for the message).
 */
/mob/living/carbon/proc/plan_throw(atom/movable/thrown, atom/target)
	var/range = thrown.throw_range
	var/speed = thrown.throw_speed
	if(!GLOB.throw_realism)
		return list(target, range, speed, FALSE, FALSE)
	var/gentle = a_intent == INTENT_HELP && isitem(thrown) && throw_is_harmless(thrown)
	if(gentle)
		speed = throw_even_speed(min(speed, THROW_TOSS_SPEED))
	else if(dna && dna.check_mutation(HULK))
		speed += 1
	range = max(range * throw_strength(), 1)
	var/wobble = throw_wobble()
	var/turf/aim = get_turf(target)
	if(wobble > 0 && aim && aim.z == z)
		var/spread = get_dist(src, aim) * wobble * THROW_WOBBLE_SPREAD
		if(spread >= 0.5)
			var/dx = round((rand() * 2 - 1) * spread, 1)
			var/dy = round((rand() * 2 - 1) * spread, 1)
			if(dx || dy)
				var/turf/off_mark = locate(clamp(aim.x + dx, 1, world.maxx), clamp(aim.y + dy, 1, world.maxy), aim.z)
				if(off_mark)
					target = off_mark
	return list(target, range, speed, gentle, wobble >= 0.5)

/// How hard a thrown thing hits for how fast it was going: 1 as its own throw, 0 for a toss. Only for a throw by somebody: a blast's
/// throws have their own force (throw_as_missile()).
/proc/throw_impact_scale(atom/movable/AM, datum/thrownthing/throwingdatum)
	if(!GLOB.throw_realism || !istype(throwingdatum))
		return 1
	if(throwingdatum.gentle)
		return 0
	if(!ismob(throwingdatum.thrower) || AM.throw_speed <= 0 || throwingdatum.speed == AM.throw_speed)
		return 1
	return clamp(sqrt(throwingdatum.speed / AM.throw_speed), 0.75, 1.4)

/obj/item/throw_impact(atom/hit_atom, datum/thrownthing/throwingdatum)
	var/scale = throw_impact_scale(src, throwingdatum)
	if(scale == 1)
		return ..()
	var/old_throwforce = throwforce
	throwforce = round(old_throwforce * scale)
	. = ..()
	if(!QDELETED(src))
		throwforce = old_throwforce

/mob/living/carbon/hitby(atom/movable/AM, skipcatch, hitpush = TRUE, blocked = FALSE, datum/thrownthing/throwingdatum)
	if(GLOB.throw_realism && isitem(AM) && istype(throwingdatum) && throwingdatum.gentle)
		return toss_received(AM, throwingdatum, skipcatch)
	return ..()

/// A toss reaching somebody: caught if it was for them and they can, otherwise it drops at their feet. Never hurts.
/mob/living/carbon/proc/toss_received(obj/item/I, datum/thrownthing/toss, skipcatch)
	var/for_me = toss.target == src
	if(!skipcatch && for_me && can_catch_toss(toss.thrower))
		if(!get_active_held_item())
			I.attack_hand(src)
		else
			I.pickup(src)
			put_in_inactive_hand(I)
		if(I.loc == src)
			visible_message("<span class='notice'>[src] catches [I].</span>", "<span class='notice'>You catch [I].</span>")
			return TRUE
	var/turf/feet = get_turf(src)
	if(feet && isturf(I.loc))
		I.forceMove(feet)
	if(for_me && stat == CONSCIOUS && length(get_empty_held_indexes()))
		visible_message("<span class='notice'>[I] drops at [src]'s feet.</span>", "<span class='notice'>[I] drops at your feet.</span>")
	return TRUE

/// Whether somebody can catch a toss from `thrower`: awake and free, a hand empty, can see, and looking that way (or right there, or
/// ready to catch), and steady enough not to fumble it
/mob/living/carbon/proc/can_catch_toss(mob/thrower)
	if(stat != CONSCIOUS || restrained() || !(mobility_flags & MOBILITY_MOVE))
		return FALSE
	if(eye_blind || HAS_TRAIT(src, TRAIT_BLIND))
		return FALSE
	if(!length(get_empty_held_indexes()))
		return FALSE
	if(!in_throw_mode && ismob(thrower) && get_dist(src, thrower) > 1 && !(get_dir(src, thrower) & dir))
		return FALSE //never saw it coming
	if(prob(throw_wobble() * 60))
		return FALSE //fumbled
	return TRUE

#undef THROW_TOSS_MAX_FORCE
#undef THROW_TOSS_SPEED
#undef THROW_WOBBLE_SPREAD
