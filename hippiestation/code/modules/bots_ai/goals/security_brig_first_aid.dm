// A prisoner who's bleeding is patched up in the cell before the officer leaves them there. Nobody was: a limb with 20 or more brute
// on it bleeds (blood.dm), faster than the blood comes back once it's 30 or 40, and a doctor walks by the doors their ID opens, which
// a cell's aren't. Prisoners brought in at 30 health off a fight died in their cells of blood loss a minute or two later, in normal
// air, one after calling for a janitor about the blood: 4 of the 5 deaths in the Brig in one batch of six shifts, and most of the 9
// in the batch before. Every map here keeps a first aid kit in the Brig. An officer with nothing to patch with takes it on the way
// in, still dragging the prisoner, and treats them in the cell before the cuffs come off; with no kit to be had it tells Medical.

/// How fast they're losing blood, as blood.dm works it out: a little for each limb with 20 brute or more and for what's stuck in
/// them. Past what eating brings back (half a unit a tick, fed) it only goes one way.
/proc/bot_bleed_rate(mob/living/carbon/human/H)
	if(!istype(H) || H.bleedsuppress || (NOBLOOD in H.dna?.species?.species_traits))
		return 0
	. = 0
	for(var/obj/item/bodypart/BP as anything in H.bodyparts)
		. += 0.5 * length(BP.embedded_objects)
		if(BP.brute_dam >= 20)
			. += BP.brute_dam * 0.013

/// Bleeding enough to bleed out where they're left, or short of blood already and still losing it
/proc/bot_bleeding_out(mob/living/carbon/human/H)
	var/rate = bot_bleed_rate(H)
	return rate >= 0.4 || (rate > 0 && H.blood_volume < BLOOD_VOLUME_SAFE)

/datum/bot_goal/brig_prisoner
	/// The Brig's first aid kit, taken on the way in for a prisoner who's bleeding
	var/obj/item/storage/firstaid/first_aid

/datum/bot_brain
	/// Prisoner (weakref) -> when the officer may next go out of its way for a kit for them. Once each: on Hippie Station the only way
	/// to the kit from the locker room was through a maintenance door, the officer went for tools to hack it, that dropped the escort,
	/// the arrest started it again, and round it went 305 times.
	var/list/brig_kit_tried

/// A first aid kit lying about in the Brig (or wherever the cell is), for a prisoner who's bleeding and an officer with nothing on it
/// to patch them with, by doors its ID opens. Null when they aren't bleeding, the officer has something, it's tried once already, or
/// there's no kit to be had.
/datum/bot_brain/proc/brig_first_aid_wanted(mob/living/carbon/human/P, obj/machinery/door_timer/T)
	if(!bot_bleeding_out(P) || pick_treatment_item(P) || !T || LAZYACCESS(brig_kit_tried, WEAKREF(P)) > world.time)
		return null
	LAZYSET(brig_kit_tried, WEAKREF(P), world.time + 2 MINUTES)
	var/area/cell_area = get_area(T)
	var/obj/item/storage/firstaid/best
	var/best_dist
	for(var/obj/item/storage/firstaid/K in range(20, T))
		if(!isturf(K.loc) || !length(K.contents))
			continue
		var/area/A = get_area(K)
		if(A != cell_area && !istype(A, /area/security))
			continue
		var/dist = get_dist(owner, K)
		if(!best || dist < best_dist)
			best = K
			best_dist = dist
	if(best && !can_walk_lawfully_to(best)) //bot_doors.dm
		bot_log(src, "no way to [best] by doors I can open - straight to the cell with [P]")
		return null
	return best

/// On the way to the cell, the prisoner in tow: over to the Brig's first aid kit, if they're bleeding and the officer has nothing to
/// patch them with. Nothing to do otherwise.
/datum/bot_step/move_to/brig_first_aid
	var/datum/bot_goal/brig_prisoner/goal

/datum/bot_step/move_to/brig_first_aid/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G

/datum/bot_step/move_to/brig_first_aid/execute(datum/bot_brain/bot)
	step_target = null
	goal.first_aid = bot.brig_first_aid_wanted(goal.prisoner, goal.cell_timer)
	if(!goal.first_aid)
		return GOAL_STEP_SUCCESS
	bot_log(bot, "[goal.prisoner] is bleeding - taking [goal.first_aid] from the Brig on the way to the cell")
	if(bot.owner.Adjacent(goal.first_aid))
		return GOAL_STEP_SUCCESS
	step_target = goal.first_aid
	return ..()

/datum/bot_step/take_brig_first_aid
	var/datum/bot_goal/brig_prisoner/goal

/datum/bot_step/take_brig_first_aid/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G

/datum/bot_step/take_brig_first_aid/execute(datum/bot_brain/bot)
	var/obj/item/storage/firstaid/K = goal.first_aid
	goal.first_aid = null
	if(K && !QDELETED(K) && isturf(K.loc) && bot.owner.Adjacent(K))
		bot.try_pickup_target(K)
	if(goal.prisoner && bot.owner.pulling != goal.prisoner && bot.owner.Adjacent(goal.prisoner))
		bot.owner.start_pulling(goal.prisoner) //picking it up shouldn't have let go, but in case
	return GOAL_STEP_SUCCESS //the cell comes next either way: without a kit, Medical is told there

/datum/bot_step/process_prisoner
	var/patched = 0
	var/told_medical = FALSE

/// In the cell, before the cuffs come off: a bandage at a time on the worst of it, once they're bleeding badly, until nothing bleeds.
/// TRUE while it's at it.
/datum/bot_brain/proc/patch_up_prisoner(mob/living/carbon/human/P, datum/bot_step/process_prisoner/S)
	if(bot_bleed_rate(P) <= 0 || S.patched >= 8 || (!S.patched && !bot_bleeding_out(P)))
		return FALSE
	aim_at_worst_wound(P) //treat_patient.dm
	var/obj/item/I = pick_treatment_item(P)
	if(!I)
		if(!S.told_medical)
			S.told_medical = TRUE
			bot_log(src, "[P] is bleeding and I've nothing to patch them with")
			bot_say(owner, ":m [P.name] is bleeding in [S.goal.cell_timer.name] in the Brig and I've nothing to patch them up with. Can a doctor come?")
		return FALSE
	S.patched++
	if(S.patched == 1)
		bot_say(owner, pick("Hold still, you're bleeding.", "Let me see to that first.", "You're bleeding everywhere. Hold still."))
	bot_log(src, "patching up [P] with [I] before the cuffs come off")
	use_item_on(I, P)
	return TRUE
