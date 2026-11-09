// Doctors give blood. Somebody in Medbay who's lost a lot of it (pale: under BLOOD_VOLUME_SAFE, which examine shows) is put on an IV
// drip with a pack of blood their type can take: out of Medbay's freezer crate, into a drip, the drip wheeled over and attached, as a
// doctor does it. Nobody ever was. Bandages and the sleeper stop the bleeding and mend the wounds, but blood only comes back by itself
// slowly, and under BLOOD_VOLUME_OKAY losing it goes on costing breath: patients who'd been patched up still suffocated in Medbay,
// one with 32 brute and 168 suffocation. About one death in twelve across five batches of six shifts looked like that.

/// Short of blood and not about to get it any other way: alive, not in a machine, and the kind of blood a pack holds
/proc/bot_needs_blood(mob/living/carbon/human/H)
	if(!istype(H) || H.stat == DEAD || !isturf(H.loc) || !H.dna?.species || H.dna.species.exotic_blood || (NOBLOOD in H.dna.species.species_traits))
		return FALSE
	return H.blood_volume < BLOOD_VOLUME_SAFE

/proc/bot_on_a_drip(mob/living/carbon/human/H)
	for(var/obj/machinery/iv_drip/D as anything in bot_instances_of(/obj/machinery/iv_drip))
		if(D.attached == H)
			return TRUE
	return FALSE

/// In Medbay, as far as this doctor's concerned: in a Bot Gym arena, the arena
/datum/bot_brain/proc/in_my_medbay(atom/A)
	return gym_run ? get_area(A) == get_area(owner) : bot_in_medbay(A)

/// A pack of blood the patient can take, in Medbay: loose, or in a crate (the freezer). Returns the pack.
/datum/bot_brain/proc/blood_pack_for(mob/living/carbon/human/H)
	var/list/safe = get_safe_blood(H.dna.blood_type)
	// One it's carrying already, from a go that came to nothing (the patient taken to a sleeper meanwhile): doctors used to leave
	// with a new pack each time, 46 taken for 19 given in one batch
	for(var/obj/item/reagent_containers/blood/mine in owner.GetAllContents())
		if((mine.blood_type in safe) && mine.reagents?.total_volume >= 50)
			return mine
	var/obj/item/reagent_containers/blood/best
	var/best_dist
	for(var/obj/item/reagent_containers/blood/B as anything in bot_instances_of(/obj/item/reagent_containers/blood))
		var/turf/where = get_turf(B) //in the freezer its own z is 0
		if(QDELETED(B) || !where || where.z != owner.z || !(B.blood_type in safe) || B.reagents?.total_volume < 50 || !in_my_medbay(B))
			continue
		if(!isturf(B.loc) && !istype(B.loc, /obj/structure/closet))
			continue //in somebody's hands, or a drip already
		if(!knows_of(B))
			continue //where the freezer keeps them, or where it saw one (bot_knowledge.dm)
		var/dist = get_dist(owner, B)
		if(!best || dist < best_dist)
			best = B
			best_dist = dist
	return best

/// An IV drip in Medbay with nobody on it, the nearest to the patient
/datum/bot_brain/proc/free_iv_drip_near(atom/A)
	var/obj/machinery/iv_drip/best
	var/best_dist
	for(var/obj/machinery/iv_drip/D as anything in bot_instances_of(/obj/machinery/iv_drip))
		if(QDELETED(D) || D.attached || D.anchored || D.z != A.z || !isturf(D.loc) || istype(D, /obj/machinery/iv_drip/saline) || !in_my_medbay(D))
			continue
		var/dist = get_dist(A, D)
		if(dist <= 25 && (!best || dist < best_dist))
			best = D
			best_dist = dist
	return best

/datum/bot_goal/give_blood
	lawful = TRUE
	exclusive = TRUE
	doing = "giving somebody blood"
	var/obj/item/reagent_containers/blood/pack
	var/obj/machinery/iv_drip/drip

/datum/bot_goal/give_blood/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient
	var/best_dist
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == bot.owner || H.z != bot.owner.z || !bot_needs_blood(H) || !bot.in_my_medbay(H) || bot_on_a_drip(H))
			continue
		if(bot.gym_run && get_area(H) != get_area(bot.owner))
			continue
		var/dist = get_dist(bot.owner, H)
		if(dist <= 30 && (!patient || dist < best_dist))
			patient = H
			best_dist = dist
	if(!patient)
		return
	pack = bot.blood_pack_for(patient)
	if(!pack)
		bot_log_verbose(bot, "give_blood: no pack [patient] ([patient.dna.blood_type]) can take in Medbay")
		return
	drip = bot.free_iv_drip_near(patient)
	if(!drip)
		bot_log_verbose(bot, "give_blood: no free IV drip near [patient]")
		return
	if(!bot.can_walk_lawfully_to(patient) || (!(pack in bot.owner.GetAllContents()) && !bot.can_walk_lawfully_to(isturf(pack.loc) ? pack : pack.loc)))
		bot_log_verbose(bot, "give_blood: no way to [patient] or the blood (MetaStation keeps it in Virology)")
		return
	target = patient

/datum/bot_goal/give_blood/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/give_blood/S = new
	var/datum/bot_step/move_to/to_drip = new
	to_drip.step_target = drip
	S.steps = list(new /datum/bot_step/take_blood_pack(src), to_drip, new /datum/bot_step/load_iv_drip(src), new /datum/bot_step/move_to(), new /datum/bot_step/attach_iv_drip(src))
	if(!(pack in bot.owner.GetAllContents()))
		var/datum/bot_step/move_to/to_pack = new
		to_pack.step_target = isturf(pack.loc) ? pack : pack.loc
		S.steps.Insert(1, to_pack)
	return list(S)

/datum/bot_goal/give_blood/on_give_up(datum/bot_brain/bot)
	if(bot.owner.pulling == drip)
		bot.owner.stop_pulling()

/datum/bot_strategy/give_blood/is_feasible(datum/bot_brain/bot)
	var/datum/bot_goal/give_blood/G = bot.current_goal
	return istype(G) && G.target && !QDELETED(G.pack) && !QDELETED(G.drip)

/// Out of the freezer (opened if it's shut) and into a hand
/datum/bot_step/take_blood_pack
	var/datum/bot_goal/give_blood/goal

/datum/bot_step/take_blood_pack/New(datum/bot_goal/give_blood/G)
	. = ..()
	goal = G

/datum/bot_step/take_blood_pack/execute(datum/bot_brain/bot)
	var/obj/item/reagent_containers/blood/B = goal.pack
	if(QDELETED(B))
		return GOAL_STEP_FAIL
	if(B in bot.owner.GetAllContents())
		return GOAL_STEP_SUCCESS
	var/obj/structure/closet/C = B.loc
	if(istype(C))
		if(!bot.owner.Adjacent(C) || !bot.open_closet(C)) //bot_items.dm: what's in it comes out onto its tile
			return GOAL_STEP_FAIL
	if(!isturf(B.loc))
		return GOAL_STEP_FAIL
	// Both hands full (a doctor with a welder and a multitool, and no room in the bag): one put down, as anybody does
	if(bot.owner.get_active_held_item() && bot.owner.get_inactive_held_item())
		bot.stow_or_drop(bot.owner.get_active_held_item())
	if(!bot.try_pickup_target(B))
		return GOAL_STEP_FAIL
	bot_log(bot, "took [B] ([B.blood_type]) for [goal.target]")
	return GOAL_STEP_SUCCESS

/// The pack into the drip, the drip set to give, and taken by the stand to wheel it over
/datum/bot_step/load_iv_drip
	var/datum/bot_goal/give_blood/goal

/datum/bot_step/load_iv_drip/New(datum/bot_goal/give_blood/G)
	. = ..()
	goal = G

/datum/bot_step/load_iv_drip/execute(datum/bot_brain/bot)
	var/obj/machinery/iv_drip/D = goal.drip
	var/obj/item/reagent_containers/blood/B = goal.pack
	if(QDELETED(D) || QDELETED(B) || D.attached || !bot.owner.Adjacent(D))
		return GOAL_STEP_FAIL
	usr = bot.owner
	if(D.beaker && D.beaker != B)
		D.eject_beaker() //what was on it: an empty pack, a beaker
	if(!D.beaker)
		bot.ready_in_hand(B)
		bot.use_item_on(B, D)
	if(D.beaker != B)
		usr = null
		return GOAL_STEP_FAIL
	if(!D.mode) //taking blood: the other way round
		D.toggle_mode()
	usr = null
	bot.owner.start_pulling(D)
	return bot.owner.pulling == D ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Beside the patient: the drip let go of and attached (iv_drip/MouseDrop(), the drag a person does), and the patient asked to stay put
/datum/bot_step/attach_iv_drip
	var/datum/bot_goal/give_blood/goal
	var/done_by = 0

/datum/bot_step/attach_iv_drip/New(datum/bot_goal/give_blood/G)
	. = ..()
	goal = G

/datum/bot_step/attach_iv_drip/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = goal.target
	var/obj/machinery/iv_drip/D = goal.drip
	bot.owner.stop_pulling()
	if(QDELETED(patient) || QDELETED(D) || patient.stat == DEAD || !isturf(patient.loc) || !bot.owner.Adjacent(patient))
		bot_log_verbose(bot, "attach_iv_drip: [patient] gone, dead, in a machine or out of reach")
		return GOAL_STEP_FAIL
	if(!D.Adjacent(patient))
		step_towards(D, patient) //the stand trails a tile behind on the way over: nudged up beside them
	if(!D.Adjacent(patient) || !bot.owner.Adjacent(D))
		bot_log_verbose(bot, "attach_iv_drip: the stand at [bot_coord(get_turf(D))] isn't beside both [patient] at [bot_coord(get_turf(patient))] and me")
		return GOAL_STEP_FAIL
	bot.human_pause(patient)
	usr = bot.owner
	D.MouseDrop(patient)
	usr = null
	if(D.attached != patient)
		bot_log_verbose(bot, "attach_iv_drip: [D] didn't take - beaker [D.beaker], attached [D.attached], [patient] has_dna [patient.has_dna()]")
		return GOAL_STEP_FAIL
	bot_log(bot, "put [patient] on [D] with [goal.pack]")
	bot_tally("given blood")
	patient.bot_brain?.hold_still_for(90 SECONDS) //treat_patient.dm
	if(!bot.gym_scripted)
		bot_say(bot.owner, pick("You've lost a lot of blood, [patient.first_name()]. Stay put while this goes in.", "Hold still, [patient.first_name()] - you need some blood back.", "Don't wander off with that in your arm, [patient.first_name()]."))
	done_by = world.time + 60 SECONDS
	addtimer(CALLBACK(src, PROC_REF(check_drip), bot), 2 SECONDS)
	return GOAL_STEP_PENDING

/// Stays by them while it goes in, and takes the needle out once the pack's run dry or they've their colour back: walking off with
/// it in tears it out (iv_drip/process()).
/datum/bot_step/attach_iv_drip/proc/check_drip(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return
	var/mob/living/carbon/human/patient = goal.target
	var/obj/machinery/iv_drip/D = goal.drip
	if(QDELETED(D) || QDELETED(patient) || D.attached != patient)
		bot.advance_goal_step(TRUE) //taken off, or torn out, already
		return
	if(world.time < done_by && D.beaker?.reagents?.total_volume && patient.blood_volume < BLOOD_VOLUME_SAFE)
		patient.bot_brain?.hold_still_for(10 SECONDS)
		addtimer(CALLBACK(src, PROC_REF(check_drip), bot), 2 SECONDS)
		return
	if(bot.owner.Adjacent(patient))
		usr = bot.owner
		D.MouseDrop(patient) //attached: this takes it off
		usr = null
		bot_log(bot, "took [patient] off [D]")
		if(!bot.gym_scripted)
			bot_say(bot.owner, pick("There you go, [patient.first_name()].", "That's you done. Take it easy.", "All done - you should feel better soon."))
	bot.advance_goal_step(TRUE)
