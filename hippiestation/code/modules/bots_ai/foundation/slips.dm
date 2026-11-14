// Slips, used (the user, 2026-11-13, after their Captain round, round-17.21.40: they went at the crew with slips, "a gap, bots don't do
// it"). A banana peel or a bar of soap puts whoever runs on to it on the floor for a few seconds, and a player who knows the game keeps
// one about them: dropped underfoot with somebody on their heels, or thrown down in front of somebody coming at them. That's a robust
// player's trick, so it's mid skill and up (foundation/skill.dm), and the clown and the greytide, who carry peels for the fun of it.
//
//  - Getting away (run_from, bot_fighting.dm): somebody after it a few tiles back, coming its way, and it drops the thing on the tile it's
//    leaving, in their path.
//  - In a fight (handle_combat(), bot_brain.dm): somebody coming at it to hit it, a few tiles off, and it throws the thing down on the
//    tile in front of them.
//  - Keeping one: those that would, pick one up when they see it lying about (is_useful_item(), bot_items.dm).
// Nobody slips on what they can see coming and walk over (galoshes, or walking: water only), so not on somebody in galoshes.

/datum/bot_brain
	/// Not another slip laid before this
	var/next_slip_trap = 0
	/// It looked through what it carries for a slip and found none: not again before this (it's asked a step at a time on the run)
	var/no_slip_until = 0

/// The sort to use a slip: a robust player's trick, and the clown's and the greytide's whatever their skill.
/datum/bot_brain/proc/uses_slips()
	return skill_at_least(BOT_SKILL_MID) || owner.mind?.assigned_role == "Clown" || greytider

/// Something it carries that puts people down: a peel, a bar of soap.
/datum/bot_brain/proc/carried_slip()
	if(world.time < no_slip_until)
		return null
	for(var/obj/item/I in owner.GetAllContents())
		if(I.datum_components && I.GetComponent(/datum/component/slippery))
			return I
	no_slip_until = world.time + 10 SECONDS
	return null

/// Whether `M` would go down on it: on their feet, no galoshes, not flying.
/proc/bot_slips_on_peel(mob/living/M)
	if(!istype(M) || M.stat != CONSCIOUS || !(M.mobility_flags & MOBILITY_STAND) || !(M.status_flags & CANKNOCKDOWN) || M.is_flying())
		return FALSE
	var/mob/living/carbon/human/H = M
	if(istype(H))
		var/obj/item/clothing/shoes/S = H.shoes
		if(istype(S) && (S.clothing_flags & NOSLIP))
			return FALSE
	return TRUE

/// Running from `foe`: they're a few tiles behind and on its line, so the slip goes down where it stands, for them to run on to. TRUE if
/// it's dropped one.
/datum/bot_brain/proc/try_slip_trap(mob/living/foe)
	if(world.time < next_slip_trap || !uses_slips() || !bot_slips_on_peel(foe) || owner.incapacitated() || !isturf(owner.loc))
		return FALSE
	var/dist = get_dist(owner, foe)
	if(dist < 1 || dist > 4 || !carried_slip() || !(foe in view(BOT_SIGHT_RANGE, owner)))
		return FALSE
	var/turf/here = get_turf(owner)
	if(locate(/obj/item) in here)
		for(var/obj/item/I in here)
			if(I.datum_components && I.GetComponent(/datum/component/slippery))
				return FALSE //one's down here already
	// Coming its way: the tile here is on their way to it, more or less
	if(!bot_clear_line(get_turf(foe), owner))
		return FALSE
	var/obj/item/slip = carried_slip()
	if(!slip)
		return FALSE
	next_slip_trap = world.time + 8 SECONDS
	INVOKE_ASYNC(src, PROC_REF(drop_slip), slip, foe)
	return TRUE

/datum/bot_brain/proc/drop_slip(obj/item/slip, mob/living/foe)
	if(!(slip in owner.held_items) && !ready_in_hand(slip))
		return
	owner.dropItemToGround(slip)
	bot_log(src, "COMBAT: dropped [slip] in [foe]'s way at [bot_coord(get_turf(slip))]")
	bot_tally("slips laid")

/// In a fight, somebody coming at it to hit it from a few tiles off: the slip thrown down in front of them. TRUE if it's thrown one.
/datum/bot_brain/proc/try_slip_throw(mob/living/foe)
	if(world.time < next_slip_trap || !uses_slips() || !bot_slips_on_peel(foe) || owner.incapacitated() || bot_holds_gun(foe))
		return FALSE
	var/dist = get_dist(owner, foe)
	if(dist < 2 || dist > 4 || !has_clear_shot(foe))
		return FALSE
	var/turf/in_front = get_step(foe, get_dir(foe, owner))
	if(!isopenturf(in_front) || in_front.density || is_blocked_turf(in_front, TRUE) || get_turf(owner) == in_front)
		return FALSE
	var/obj/item/slip = carried_slip()
	if(!slip)
		return FALSE
	next_slip_trap = world.time + 8 SECONDS
	INVOKE_ASYNC(src, PROC_REF(throw_slip), slip, foe, in_front)
	return TRUE

/datum/bot_brain/proc/throw_slip(obj/item/slip, mob/living/foe, turf/at)
	if(!ready_in_hand(slip) || owner.get_active_held_item() != slip)
		return
	owner.face_atom(at)
	owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(src, "COMBAT: throwing [slip] down in front of [foe], at [bot_coord(at)]")
	bot_tally("slips thrown")
	owner.throw_item(at)

/// One kept about it, by those that would (is_useful_item(), bot_items.dm): not a second.
/datum/bot_brain/proc/wants_slip(obj/item/I)
	if(!I.datum_components || !I.GetComponent(/datum/component/slippery) || !uses_slips() || !(bot_traitor || greytider || owner.mind?.assigned_role == "Clown" || playstyle == BOT_STYLE_ROBUST || playstyle == BOT_STYLE_HUNTER))
		return FALSE
	no_slip_until = 0 //it may have one by now
	return !carried_slip()
