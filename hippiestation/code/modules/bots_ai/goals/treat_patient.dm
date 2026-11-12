// Medical-role behavior: a bot doing the Doctor/CMO job notices injured crew while
// wandering and goes to patch them up with whatever's in its first aid kit, instead of
// only ever reacting when it personally gets attacked. Deliberately scoped to actual
// medical jobs, not every bot - a cargo tech stopping to bandage someone would look
// stranger than just leaving it to the people who signed up for it.
/datum/bot_brain/proc/is_medical_job()
	var/role = work_role()
	return role == "Medical Doctor" || role == "Chief Medical Officer" || role == "Geneticist" || role == "Virologist" //goals/quiet_jobs.dm

// Same brute/burn thresholds as a real player would bother stopping for - scrapes and
// bruises get walked past, anything that'll actually kill them eventually doesn't.
/datum/bot_brain/proc/patient_needs_treatment(mob/living/carbon/human/H)
	if(H.stat == DEAD || H.bot_executed)
		return FALSE
	// A traitor doctor out in the open patches up its own side and nobody else: one in a nanosuit put a bruise pack on the cook it was
	// beating, between punches, twice (2026-11-10)
	if(H != owner && gone_loud() && !on_my_side(H))
		return FALSE
	if(!H.handcuffed && (bot_is_wanted(H) || is_type_in_typecache(H.wear_suit, GLOB.bot_contraband)))
		return FALSE //nobody patches up a nuclear operative, or anybody Security's after, until they're in cuffs: a doctor once took
		//an operative's hardsuit off them in the middle of the bridge to get at a cut
	if(sore_at(H))
		return FALSE //they've just been hitting it (bot_reflexes.dm): it keeps clear, and another doctor can see to them. A robust traitor
		//fought two doctors in Medbay, and both went on dragging it to the sleeper between punches.
	if(H.getBruteLoss() > 10 || H.getFireLoss() > 10)
		return TRUE
	if(H.stat == SOFT_CRIT || H.stat == UNCONSCIOUS)
		return TRUE
	return bot_needs_antitox(H)

/datum/bot_brain/proc/patient_injury_score(mob/living/carbon/human/H)
	. = H.getBruteLoss() + H.getFireLoss()
	if(bot_needs_antitox(H))
		. += H.getToxLoss()
	if(H.stat != CONSCIOUS)
		. += 30

/// Poisoned, or sick from radiation, which is the same thing to a body (life.dm: past 500 rads it's toxin damage every few seconds, and
/// it takes hours to wear off by itself), with nothing in them for it yet. Charcoal from the toxin kit keeps them ahead of it. Nobody
/// treated it: on MetaStation with the supermatter running 21 of the crew died of it in one shift, the doctors bandaging scratches.
/proc/bot_needs_antitox(mob/living/carbon/human/H)
	if(H.getToxLoss() <= 20)
		return FALSE
	return !(H.reagents?.has_reagent(/datum/reagent/medicine/charcoal) || H.reagents?.has_reagent(/datum/reagent/medicine/pen_acid) || H.reagents?.has_reagent(/datum/reagent/medicine/potass_iodide))

/// A pill against poison or radiation, wherever on it it's kept: the charcoal out of a toxin kit's pill bottles, pentetic acid, potassium iodide.
/datum/bot_brain/proc/find_antitox_pill()
	for(var/obj/item/reagent_containers/pill/P in owner.GetAllContents(/obj/item/reagent_containers/pill))
		var/datum/reagent/R = P.reagents?.get_master_reagent()
		if(istype(R, /datum/reagent/medicine/charcoal) || istype(R, /datum/reagent/medicine/pen_acid) || istype(R, /datum/reagent/medicine/potass_iodide))
			return P
	return null

// Every /obj/item/stack/medical the bot is carrying, wherever it's stowed (hand, belt,
// first aid kit, backpack) - GetAllContents() walks nested storage same as a player
// digging through their own kit.
/datum/bot_brain/proc/get_medical_supplies()
	return owner.GetAllContents(/obj/item/stack/medical)

// Picks whichever supply matches the patient's WORSE damage type first (a burn victim
// gets ointment before a bruise pack, and vice versa) - same instinct a real doctor
// triaging at a glance would use, rather than blindly grabbing whatever's first in the kit.
//
// through_suit: the wound is under a suit a bandage can't get through (clothing_in_the_way(), below) - only a patch
// will do, which sticks on over anything (pill/patch/attack() never asks can_inject()).
/datum/bot_brain/proc/pick_treatment_item(mob/living/carbon/human/patient, through_suit = FALSE)
	// Poison or radiation the worst of it: a pill, swallowed, whatever they've got on.
	if(bot_needs_antitox(patient) && patient.getToxLoss() >= max(patient.getBruteLoss(), patient.getFireLoss()))
		var/obj/item/reagent_containers/pill/antitox = find_antitox_pill()
		if(antitox)
			return antitox
	var/burn_first = patient.getFireLoss() > patient.getBruteLoss()
	if(through_suit)
		var/obj/item/reagent_containers/pill/patch/brute_patch
		var/obj/item/reagent_containers/pill/patch/burn_patch
		for(var/obj/item/reagent_containers/pill/patch/P in owner.GetAllContents(/obj/item/reagent_containers/pill/patch))
			if(istype(P, /obj/item/reagent_containers/pill/patch/styptic) || istype(P, /obj/item/reagent_containers/pill/patch/synthflesh))
				brute_patch = brute_patch || P
			if(istype(P, /obj/item/reagent_containers/pill/patch/silver_sulf) || istype(P, /obj/item/reagent_containers/pill/patch/synthflesh))
				burn_patch = burn_patch || P
		if(burn_first)
			return (patient.getFireLoss() > 10 ? burn_patch : null) || (patient.getBruteLoss() > 10 ? brute_patch : null)
		return (patient.getBruteLoss() > 10 ? brute_patch : null) || (patient.getFireLoss() > 10 ? burn_patch : null)
	var/list/supplies = get_medical_supplies()
	if(!supplies.len)
		return find_healing_pill()
	var/obj/item/stack/medical/bruise_pack/brute_pick
	var/obj/item/stack/medical/ointment/burn_pick
	for(var/obj/item/stack/medical/M in supplies)
		if(!M.get_amount())
			continue
		if(istype(M, /obj/item/stack/medical/bruise_pack) && !brute_pick)
			brute_pick = M
		else if(istype(M, /obj/item/stack/medical/ointment) && !burn_pick)
			burn_pick = M
	var/obj/item/stack/medical/picked = burn_first ? (burn_pick || brute_pick) : (brute_pick || burn_pick)
	// Only what heals what they've got, aimed where it does. A bruise pack does nothing for a burn and ointment nothing for a cut
	// (stack/medical heal_carbon()), and the aim was at the limb worst off in both together: three bruise packs on a burnt arm was
	// "this isn't doing anything for me", 58 of the 62 self-heals given up that way in a batch.
	if(picked && !aim_for_stack(patient, picked))
		picked = (picked == brute_pick) ? burn_pick : brute_pick
		if(picked && !aim_for_stack(patient, picked))
			picked = null
	return picked || find_healing_pill()

/// The aim on the organic limb worst off in what this stack heals. FALSE if no limb has any of it.
/datum/bot_brain/proc/aim_for_stack(mob/living/carbon/human/patient, obj/item/stack/medical/M)
	var/brute = istype(M, /obj/item/stack/medical/bruise_pack)
	var/obj/item/bodypart/worst
	var/worst_damage = 0
	for(var/obj/item/bodypart/B in patient.bodyparts)
		if(B.status != BODYPART_ORGANIC)
			continue
		var/dam = brute ? B.brute_dam : B.burn_dam
		if(dam > worst_damage)
			worst_damage = dam
			worst = B
	if(!worst)
		return FALSE
	owner.zone_selected = worst.body_zone
	return TRUE

/// A pill or a patch with something healing in it, for when the first aid kit's run out or there never was one (goals/chem_lab.dm).
/datum/bot_brain/proc/find_healing_pill()
	for(var/obj/item/reagent_containers/pill/P in owner.GetAllContents(/obj/item/reagent_containers/pill))
		if(bot_chem_kind_of(P) == "heal")
			return P
	return null

// Sent out for more once the current kit runs dry - tries a whole spare first aid kit
// first (any /obj/item/storage/firstaid subtype, wherever one's sitting unattended),
// then falls back to loose bruise packs/ointment directly. Reuses the same generic
// acquire_item_type goal every personal-objective fetch already uses (goals/
// acquire_item_type.dm) via suspend_goal_for() - same suspend/resume dance
// ensure_wrench/ensure_tools use for tools, just for medical supplies instead.
/datum/bot_brain/proc/restock_medical_supplies(antitox = FALSE)
	var/burn_first = owner.getFireLoss() > owner.getBruteLoss()
	// A kit with something in it for cuts or burns: the kinds that have (wound_kit, below), the one for the worse of them first.
	var/list/wanted = antitox ? list(/obj/item/storage/pill_bottle/charcoal, /obj/item/storage/firstaid/toxin) : (burn_first ? list(/obj/item/storage/firstaid/fire, /obj/item/storage/firstaid/regular) : list(/obj/item/storage/firstaid/brute, /obj/item/storage/firstaid/regular))
	if(!antitox)
		wanted += list(/obj/item/storage/firstaid/ancient, /obj/item/storage/firstaid/tactical, burn_first ? /obj/item/storage/firstaid/brute : /obj/item/storage/firstaid/fire, /obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment)
		// And failing those, a patch from a NanoMed on the wall: there's one in most hallways, anybody's card buys from it, and
		// a patch is what it sells for cuts (styptic) and burns (silver sulfadiazine). Somebody hurt with no kit in reach by
		// its own doors gave up on itself with one of those a few steps away: 66 times in twelve shifts.
		if(burn_first)
			wanted += list(/obj/item/reagent_containers/pill/patch/silver_sulf, /obj/item/reagent_containers/pill/patch/styptic)
		else
			wanted += list(/obj/item/reagent_containers/pill/patch/styptic, /obj/item/reagent_containers/pill/patch/silver_sulf)
	for(var/wanted_type in wanted)
		var/datum/bot_goal/acquire_item_type/sub = ispath(wanted_type, /obj/item/storage/firstaid) && !antitox ? new /datum/bot_goal/acquire_item_type/wound_kit() : new()
		sub.item_type = wanted_type
		sub.lawful = TRUE
		if(suspend_goal_for(sub))
			return TRUE
	ask_cargo_for(/datum/supply_pack/medical/supplies, "medical supplies", "medical", /obj/item/storage/firstaid) //bot_collabs.dm
	return FALSE

/// A first-aid kit with something in it for cuts or burns. The nearest kit of any kind was taken (any /obj/item/storage/firstaid), and
/// as often as not it was the oxygen kit (perfluorodecalin and a medipen), the toxin kit, or one already picked over: somebody hurt
/// walked to it, found nothing to put on, and gave itself up, 55 times in twelve shifts. Now it's the kinds that hold bandages or
/// patches, and of those lying about, one that still does.
/datum/bot_goal/acquire_item_type/wound_kit

/datum/bot_goal/acquire_item_type/wound_kit/will_do(obj/item/I)
	if(!..())
		return FALSE
	for(var/obj/item/thing in I.contents)
		if(istype(thing, /obj/item/stack/medical/bruise_pack) || istype(thing, /obj/item/stack/medical/ointment))
			return TRUE
		if(istype(thing, /obj/item/reagent_containers/pill) && bot_chem_kind_of(thing) == "heal") //goals/chem_lab.dm: styptic, silver sulf
			return TRUE
	return FALSE

// Aims at whichever organic limb is currently worst off, instead of always healing
// whatever zone_selected happened to be left on from the last click - heal_carbon()
// (stacks/medical.dm) only ever treats the single currently-selected zone.
/datum/bot_brain/proc/aim_at_worst_wound(mob/living/carbon/human/patient)
	var/obj/item/bodypart/worst
	var/worst_damage = 0
	for(var/obj/item/bodypart/B in patient.bodyparts)
		if(B.status != BODYPART_ORGANIC)
			continue
		var/dam = B.brute_dam + B.burn_dam
		if(dam > worst_damage)
			worst_damage = dam
			worst = B
	if(worst)
		owner.zone_selected = worst.body_zone

/// What the patient has on that a bandage can't get through to the wound being aimed at - their suit, or their
/// headgear for a head wound (human/can_inject()) - or null. A firesuit, a hardsuit, a bio suit: bruise packs and
/// ointment do nothing at all through one, and say so only to whoever is holding them.
/datum/bot_brain/proc/clothing_in_the_way(mob/living/carbon/human/patient)
	var/obj/item/clothing/covering = (owner.zone_selected in list(BODY_ZONE_HEAD, BODY_ZONE_PRECISE_MOUTH, BODY_ZONE_PRECISE_EYES)) ? patient.head : patient.wear_suit
	if(istype(covering) && (covering.clothing_flags & THICKMATERIAL))
		return covering
	return null

/// Gets the patient's suit (or helmet) off so the wound can be reached: a word of warning, then the strip menu, as a
/// doctor does it (stripPanelUnequip() - a few seconds, longer for a hardsuit, and it stops if they walk off). The
/// suit is left at their feet. Never where taking it off would hurt them.
/datum/bot_brain/proc/uncover_patient(mob/living/carbon/human/patient, obj/item/clothing/covering)
	if(!turf_air_is_breathable(get_turf(patient)))
		bot_log(src, "[patient]'s [covering.name] is in the way, but they need it on in here")
		return FALSE
	// A hardsuit's helmet is part of the suit and doesn't come off by itself: the suit comes off, and takes it along.
	var/obj/item/clothing/head/helmet/space/hardsuit/built_in = covering
	if(istype(built_in) && built_in.suit && built_in.suit == patient.wear_suit)
		covering = patient.wear_suit
	var/slot = (covering == patient.head) ? ITEM_SLOT_HEAD : ITEM_SLOT_OCLOTHING
	bot_say(owner, pick("Hold still, [patient.first_name()] - that [covering.name] has to come off.", "I can't treat you through that [covering.name]. Hold still."))
	bot_log(src, "taking [patient]'s [covering.name] off to get at the wound")
	human_pause(patient)
	if(QDELETED(patient) || QDELETED(covering) || !owner.Adjacent(patient))
		return FALSE
	owner.face_atom(patient)
	telemetry_action = "take [covering] off [patient]"
	owner.stripPanelUnequip(covering, patient, slot)
	telemetry_action = null
	if(QDELETED(patient) || QDELETED(covering) || patient.get_item_by_slot(slot) == covering)
		return FALSE
	if(covering in owner.held_items)
		owner.dropItemToGround(covering) //it comes away into the doctor's hand - set down by the patient, not carried off
	// A patient who is one of ours puts it back on once it's over (a hardsuit they were working in).
	var/datum/bot_brain/theirs = patient.bot_brain
	if(theirs)
		theirs.set_aside_clothing = WEAKREF(covering)
		theirs.set_aside_slot = slot
	return TRUE

/datum/bot_brain
	/// A suit or helmet a doctor took off this bot to treat it, and where it was worn - put back on afterwards.
	var/datum/weakref/set_aside_clothing
	var/set_aside_slot
	/// Weakref of a patient -> world.time before which not to try treating them again (treat_patient/on_give_up()).
	var/list/untreatable_patients

/// Puts back on what the doctor took off, if it's still within reach.
/datum/bot_brain/proc/put_clothing_back_on()
	var/obj/item/clothing/covering = set_aside_clothing?.resolve()
	set_aside_clothing = null
	if(!covering || QDELETED(owner) || owner.stat != CONSCIOUS || !isturf(covering.loc) || get_dist(owner, covering) > 1)
		return
	if(owner.get_item_by_slot(set_aside_slot))
		return //put something else on since
	if(wear(covering, set_aside_slot))
		bot_log(src, "put [covering] back on")

// `lawful`: a doctor walks to a patient by doors a doctor's ID opens. One shut in a department it doesn't is asked to
// come to Medbay - a doctor used to take the Engineering airlock apart to get to an engineer with a burn.
/datum/bot_goal/treat_patient
	lawful = TRUE

/// Patient (weakref) -> when they may next be asked over the radio to come to Medbay. Shared, so two doctors don't both ask.
GLOBAL_LIST_EMPTY(bot_patient_summons)

/datum/bot_brain
	/// When this doctor may next ask somebody on the radio to come to Medbay
	var/next_patient_summons = 0

/// Asks a patient the doctor can't get to, to come to Medbay.
/datum/bot_brain/proc/call_patient_in(mob/living/carbon/human/patient)
	var/datum/weakref/ref = WEAKREF(patient)
	if(gym_scripted || GLOB.bot_patient_summons[ref] > world.time)
		return
	// One at a time: a doctor asked five people in two seconds, all on Common (2026-11-10). Whoever's left gets asked on the next go.
	if(world.time < next_patient_summons)
		return
	next_patient_summons = world.time + 20 SECONDS
	GLOB.bot_patient_summons[ref] = world.time + 5 MINUTES
	say_after_typing(";[patient.first_name()], come by Medbay when you can and I'll patch you up.")

/// A doctor is on the way to this bot: it stays where it is for a little, if it was only strolling about.
/datum/bot_brain/proc/wait_for_doctor(datum/bot_brain/doctor)
	if(state != BOT_STATE_WANDER || gym_scripted || holding_duty || owner.stat != CONSCIOUS)
		return
	awaited_doctor = WEAKREF(doctor)
	doctor_wait_until = world.time + 40 SECONDS
	holding_duty = bot_duty_of(/datum/bot_duty/await_doctor)
	if(pursuing_kind == "wander")
		stop_pursuit()

/datum/bot_brain
	var/datum/weakref/awaited_doctor
	var/doctor_wait_until = 0

/// Not a duty anyone goes looking for: it only keeps a patient where they are while the doctor walks over.
/datum/bot_duty/await_doctor
	name = "waiting for the doctor"
	jobs = list()

/datum/bot_duty/await_doctor/keep_holding(datum/bot_brain/bot)
	var/datum/bot_brain/doctor = bot.awaited_doctor?.resolve()
	if(!doctor || world.time > bot.doctor_wait_until)
		return FALSE
	return istype(doctor.current_goal, /datum/bot_goal/treat_patient) && doctor.current_goal.target == bot.owner

/// Who the other doctors are walking to or seeing to now: their treat_patient, or the one parked while they fetch more supplies, which
/// they're coming back to. Every doctor on shift picked the same worst-off patient: 63 of a batch's 274 treatments were a second or third
/// doctor setting out for somebody a colleague already had, and 45 of those got there to find nothing left to do. One in a fight, in
/// cuffs or on the floor isn't seeing to anybody, whatever it still has in mind. Not `exclusive`: that claim is by target whatever the
/// goal, and would turn a doctor away from a prisoner an officer has in hand.
/datum/bot_brain/proc/patients_seen_to()
	var/list/seen = list()
	for(var/datum/bot_brain/other as anything in GLOB.bot_brains)
		if(other == src || QDELETED(other) || other.state != BOT_STATE_GOAL || QDELETED(other.owner) || other.owner.stat != CONSCIOUS || other.owner.incapacitated())
			continue
		var/datum/bot_goal/treat_patient/theirs = other.current_goal
		if(!istype(theirs))
			theirs = other.suspended_goal
		if(istype(theirs) && theirs.target)
			seen[theirs.target] = TRUE
	return seen

/datum/bot_goal/treat_patient/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/called = (world.time < bot.called_patient_until) ? bot.called_patient?.resolve() : null
	var/list/seen_to = bot.patients_seen_to()
	var/list/hurt = list() //patient -> how badly they want seeing to
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == bot.owner || H.z != bot.owner.z)
			continue
		if(bot.gym_run && get_area(H) != get_area(bot.owner))
			continue //a Bot Gym doctor only sees to its own arena's patient
		if(H.stat != CONSCIOUS) //crit/unconscious goes to escort_to_sleeper instead - dragging someone in for a scrape is overkill, but a downed patient needs more than a bandage
			continue
		if(!bot.patient_needs_treatment(H))
			continue
		if(get_dist(bot.owner, H) > 40 && H != called)
			continue
		if(LAZYACCESS(bot.untreatable_patients, WEAKREF(H)) > world.time)
			continue //just tried and got nowhere (on_give_up()) - not straight back to them
		if(seen_to[H] && H != called)
			continue //a colleague has them (patients_seen_to()): this one takes the next worst off. Who asked it to its face still gets seen to
		hurt[H] = bot.patient_injury_score(H) - get_dist(bot.owner, H) + (H == called ? 200 : 0)
	// The worst off there's a way to.
	var/tries = 0
	while(length(hurt) && tries++ < 3)
		var/mob/living/carbon/human/worst
		for(var/mob/living/carbon/human/H as anything in hurt)
			if(!worst || hurt[H] > hurt[worst])
				worst = H
		hurt -= worst
		if(bot.can_walk_lawfully_to(worst))
			target = worst
			worst.bot_brain?.wait_for_doctor(bot)
			return
		LAZYSET(bot.untreatable_patients, WEAKREF(worst), world.time + 2 MINUTES)
		bot.call_patient_in(worst)

/datum/bot_goal/treat_patient/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/treat())

/datum/bot_goal/treat_patient/on_success(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = target
	if(istype(patient) && patient.bot_brain?.set_aside_clothing)
		INVOKE_ASYNC(patient.bot_brain, TYPE_PROC_REF(/datum/bot_brain, put_clothing_back_on))
	bot.continue_medical_round()

/// For the next few minutes this patient is somebody else's problem: nothing the bot had got through to them.
/datum/bot_goal/treat_patient/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.untreatable_patients, WEAKREF(target), world.time + 3 MINUTES)

/datum/bot_strategy/treat/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/treat_patient())

/datum/bot_strategy/treat/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/treat_patient
	// One-shot per strategy attempt, same idea as ensure_wrench's tried_fetch - a
	// station with nothing left to restock from shouldn't burn a fresh suspend cycle
	// (goal_suspend_count) on every single re-check while still treating this patient.
	var/tried_restock = FALSE
	/// Clicks in a row that left the patient no better. A doctor stops and thinks; this used to click on regardless -
	/// 1,410 times in one shift, on an assistant in a firesuit.
	var/useless_clicks = 0
	/// Times the patient had moved on by the time the doctor got to where they were.
	var/chases = 0
	/// Of those, the times they were a long way off by then: the first time it goes on after them, the second time it doesn't.
	var/far_chases = 0

/datum/bot_step/treat_patient/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient) || !bot.patient_needs_treatment(patient))
		return GOAL_STEP_SUCCESS //nothing left to do - either treated already or beyond help
	if(!bot.owner.Adjacent(patient))
		// They've walked on since. A doctor asks them to hold still and goes after them - a couple of times, not
		// round and round the station.
		// Somebody down gets walked up to again as well: dragged a step since, or met across the corner of a table, they were given up
		// on the spot, 31 of the batch's treatments, and nothing in the log to say so.
		// Back from a fetch for more supplies that came to nothing: no walk back over to them with nothing to put on, and no word on the
		// radio that it's on its way. 2 of a batch's 14 treatments taken up again after a kit run came back empty-handed.
		if(tried_restock && !bot.pick_treatment_item(patient))
			bot_log(bot, "out of medical supplies for [patient], and nothing reachable to restock with")
			return GOAL_STEP_FAIL
		// More than a dozen tiles off. The walk was to where they stood when the doctor set out, and somebody on an errand of their own
		// was twenty tiles on by the time it got there; or the doctor had been off for a kit, and took this step up again forty tiles
		// from them. Either way they were given up on the spot: 58 of a batch's 100 treatments given up. The first time, the doctor asks
		// them over the radio to stay where they are, and goes on to where they are now.
		var/dist = get_dist(bot.owner, patient)
		var/far = dist > 12
		if(chases >= 3 || patient.z != bot.owner.z || (far && (far_chases >= 1 || dist > 60)))
			bot_log(bot, "couldn't get beside [patient] ([dist] tiles off[chases >= 3 ? ", after three tries" : ""])")
			return GOAL_STEP_FAIL
		chases++
		if(far)
			far_chases++
			bot_log(bot, "[patient] is [dist] tiles on from where I was headed - going after them")
			patient.bot_brain?.wait_for_doctor(bot) //only strolling about, it waits for the doctor, as when it was first picked (resolve_target())
			// One doctor asks, once a minute at most, and not on top of "come by Medbay" (call_patient_in()): four doctors went after the
			// Warden in the same three seconds, and each would have said it on Common.
			var/datum/weakref/ref = WEAKREF(patient)
			if(patient.stat == CONSCIOUS && !bot.gym_scripted && world.time >= bot.next_patient_summons && !(GLOB.bot_patient_summons[ref] > world.time))
				bot.next_patient_summons = world.time + 20 SECONDS
				GLOB.bot_patient_summons[ref] = world.time + 1 MINUTES
				bot.say_after_typing(";[patient.first_name()], stay where you are a moment, I'm on my way to patch you up.")
		else if(chases == 1 && patient.stat == CONSCIOUS && !bot.gym_scripted && (patient in view(7, bot.owner)))
			bot_say(bot.owner, pick("Hold still a second, [patient.first_name()].", "[patient.first_name()], stay there - let me look at that.", "Wait up, [patient.first_name()]."))
		patient.bot_brain?.hold_still_for(12 SECONDS)
		bot.current_step_index = 1
		addtimer(CALLBACK(src, PROC_REF(go_after), bot, bot.current_goal), 3)
		return GOAL_STEP_PENDING
	bot.aim_at_worst_wound(patient)
	// Under a suit nothing gets through: a patch if there's one in the kit, otherwise the suit comes off.
	var/obj/item/clothing/covering = bot.clothing_in_the_way(patient)
	var/obj/item/I = bot.pick_treatment_item(patient, !!covering)
	if(covering && !I)
		if(!bot.uncover_patient(patient, covering))
			bot_log(bot, "can't get at [patient]'s wounds through [covering]")
			return GOAL_STEP_FAIL
		I = bot.pick_treatment_item(patient)
	if(!I)
		if(!tried_restock)
			tried_restock = TRUE
			if(bot.restock_medical_supplies(bot_needs_antitox(patient)))
				bot_log(bot, "out of medical supplies for [patient] - going to restock")
				return GOAL_STEP_PENDING
		bot_log(bot, "out of medical supplies for [patient], and nothing reachable to restock with")
		return GOAL_STEP_FAIL
	var/hurt_before = patient.getBruteLoss() + patient.getFireLoss() + patient.getToxLoss()
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(bot, "treating [patient] with [I]")
	bot.use_item_on(I, patient)
	if(QDELETED(patient) || !bot.patient_needs_treatment(patient))
		return GOAL_STEP_SUCCESS
	useless_clicks = (patient.getBruteLoss() + patient.getFireLoss() + patient.getToxLoss() < hurt_before) ? 0 : useless_clicks + 1
	if(useless_clicks >= 3)
		bot_log(bot, "nothing I'm doing is helping [patient] - leaving it")
		return GOAL_STEP_FAIL
	addtimer(CALLBACK(src, PROC_REF(continue_treat), bot), CLICK_CD_MELEE)
	return GOAL_STEP_PENDING

/// Back to the walk, towards wherever the patient is now.
/datum/bot_step/treat_patient/proc/go_after(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal)
		return
	bot.run_current_step()

/// Asked to stay put for a moment by somebody who's coming over. Not in a fight, and not with a shuttle to catch.
/datum/bot_brain/proc/hold_still_for(duration)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || !EMERGENCY_IDLE_OR_RECALLED)
		return
	stand_still_until = max(stand_still_until, world.time + duration)

/datum/bot_step/treat_patient/proc/continue_treat(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return //goal moved on (succeeded/failed/replaced) while we were waiting - don't act on stale state
	var/result = execute(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_brain/proc/try_medical_round()
	if(is_medical_job())
		// The prisoner it was called to, down in crit in front of it where Security's keeping them for a doctor: first aid there and then,
		// before anybody further off. They aren't for a sleeper (the dangerous ones don't leave Security), and the round went on down its
		// list past them: a doctor called to a prisoner at -3 by the Brig door went off to drag somebody else to a sleeper, came back to
		// find him held for Security and walked off, and he died at the door (bugs1112base run6, Max Adeyemi and Morgan Vance).
		if(called_patient_kept_down() && assign_goal(new /datum/bot_goal/stabilise()))
			return TRUE
		// The machines first: anybody finished with a sleeper or a cryo cell, dead or patched up, is let out (goals/medical_rounds.dm).
		if(assign_goal(new /datum/bot_goal/empty_machine()))
			return TRUE
		// Priority order matches real triage: revive the dead first (nothing else
		// matters until their heart's beating), then get the incapacitated somewhere
		// that can actually stabilize them, then patch up whoever's just walking
		// around hurt.
		if(assign_goal(new /datum/bot_goal/revive_patient()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/give_blood/urgent())) //goals/give_blood.dm: down, in Medbay and short of blood
			return TRUE
		if(assign_goal(new /datum/bot_goal/escort_to_sleeper()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/operate())) //goals/surgery.dm: the sleepers are full, or there aren't any
			return TRUE
		if(assign_goal(new /datum/bot_goal/stabilise())) //no sleeper and no table for them: kept alive where they lie
			return TRUE
		if(assign_goal(new /datum/bot_goal/treat_patient()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/give_blood())) //goals/give_blood.dm: patched up, but short of blood
			return TRUE
		// Everybody alive seen to: the dead the paddles couldn't help (goals/cloning.dm).
		if(assign_goal(new /datum/bot_goal/clone_body()))
			return TRUE
		// No patient needs attention right now - use the downtime to get medbay's
		// cryo setup in order, same priority a real doctor would use: get gas
		// flowing to the loop first, then get it cold, then make sure there's
		// something to actually heal with once someone's inside.
		if(assign_goal(new /datum/bot_goal/connect_cryo_canister()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/activate_cryo_freezer()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/load_cryo_beaker()))
			return TRUE
	// Chemists have no patient/cryo duties at all, and reach straight here - Doctors/
	// CMOs fall through to this too once medbay's fully caught up, using downtime to
	// keep the medicine supply stocked (goals/synthesize_medicine.dm).
	if(is_chem_producer_job())
		return assign_goal(new /datum/bot_goal/synthesize_medicine())
	return FALSE

// Chains straight into the next medical task instead of waiting out the normal
// wander-cycle pacing (next_medical_check_time, up to 15 real seconds) - a doctor who
// just finished bandaging one patient or wrenching one canister down doesn't wander off
// idly before checking whether there's more to do, they just do the next thing.
// Deferred one tick so state has actually settled back to BOT_STATE_WANDER first -
// assign_goal() refuses outright while state is still BOT_STATE_GOAL, which it still is
// at the exact moment on_success() runs (end_goal() hasn't returned yet).
/datum/bot_brain/proc/continue_medical_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_medical_round)))

// ============================================================
// Revival: the body dragged to a wall-mounted defibrillator, its paddles taken down and wielded, and the patient shocked back to
// life, as a doctor does who isn't wearing a defibrillator of their own.
//
// The paddles reach one tile from their unit and come out of the hands past that (defib.dm check_range()), and they bring nobody
// back who's been dead two minutes (tlimit). A doctor took the paddles at the mount and walked off to the body with them, up to
// sixty tiles: 38 tries in twelve shifts, and not one got as far as a shock. So the body comes to the mount, and only one there's
// still time for: the rest are for the cloner (goals/cloning.dm).
// ============================================================

/// What a tile of the way costs, to the body and back with it in tow, and what the paddles take once there, in deciseconds.
#define BOT_REVIVE_TILE_TIME 3
#define BOT_REVIVE_AT_MOUNT (10 SECONDS)

/datum/bot_brain/proc/find_reachable_defib_mount()
	var/obj/machinery/defibrillator_mount/best
	var/best_dist
	for(var/obj/machinery/defibrillator_mount/M as anything in bot_instances_of(/obj/machinery/defibrillator_mount))
		if(M.z != owner.z || !M.defib || !M.defib.paddles || !M.defib.powered)
			continue
		if(M.defib.paddles.loc != M.defib) //someone else already has the paddles out
			continue
		if(gym_run && get_area(M) != get_area(owner))
			continue
		var/dist = get_dist(owner, M)
		if(dist > 30)
			continue
		if(!best || dist < best_dist)
			best = M
			best_dist = dist
	return best

// Frees BOTH hands (stows what it can, drops the rest) - wielding the paddles needs the
// active hand AND the inactive hand empty, unlike ordinary tool use which only ever
// needed free_hand_for()'s single-hand version.
/datum/bot_brain/proc/free_both_hands()
	for(var/obj/item/I in owner.held_items)
		if(!I)
			continue
		stow_item(I)
		if(I in owner.held_items)
			owner.dropItemToGround(I)

/datum/bot_goal/revive_patient
	exclusive = TRUE //one doctor to a body
	var/obj/machinery/defibrillator_mount/mount

/datum/bot_goal/revive_patient/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/defibrillator_mount/M = bot.find_reachable_defib_mount()
	if(!M)
		return
	var/obj/item/twohanded/shockpaddles/paddles = M.defib.paddles
	var/mob/living/carbon/human/best
	var/best_dist
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.z != bot.owner.z || !isturf(H.loc))
			continue
		if(bot.gym_run && get_area(H) != get_area(bot.owner))
			continue
		if(!paddles.can_defib(H)) //reuses the paddles' own revivability check (time limit, damage caps, brain state, etc) rather than duplicating it
			continue
		if(bot.another_medic_has(H) || LAZYACCESS(bot.unreachable_patients, H) > world.time)
			continue //another doctor has them, or it's just tried
		if(locate(/obj/item/clothing/suit/space) in H.contents)
			continue //"Patient's chest is obscured": the paddles won't go through a space suit
		// Bled out: the paddles would bring them back at fifty under with no blood to live on, and they'd be dead again in twenty
		// seconds (blood.dm takes five or six of health a tick below BLOOD_VOLUME_OKAY). There's no putting blood back inside the
		// two minutes the paddles are good for, so that's a body for the cloner. One who'd been beaten to death was shocked back
		// twenty times in a shift by three doctors in turn, and died twenty times.
		if(H.blood_volume < BLOOD_VOLUME_SAFE && !(NOBLOOD in H.dna?.species?.species_traits))
			continue
		var/dist = get_dist(bot.owner, H)
		if(dist > 60)
			continue
		// Whether there's time: to the body, back to the mount with it, and the paddles on, inside what's left of the two minutes
		if(world.time - H.timeofdeath + (dist + get_dist(H, M)) * BOT_REVIVE_TILE_TIME + BOT_REVIVE_AT_MOUNT > paddles.tlimit)
			continue
		if(!best || dist < best_dist)
			best = H
			best_dist = dist
	if(!best)
		return
	target = best
	mount = M

/datum/bot_goal/revive_patient/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/revive(mount))

/datum/bot_goal/revive_patient/on_success(datum/bot_brain/bot)
	return_paddles(bot)
	bot.continue_medical_round()

/datum/bot_goal/revive_patient/on_give_up(datum/bot_brain/bot)
	return_paddles(bot)
	bot.owner.stop_pulling()
	// Not this one again for a couple of minutes, which for the paddles is for good: the cloner's next (goals/cloning.dm)
	var/mob/living/carbon/human/patient = target
	if(istype(patient) && !QDELETED(patient) && patient.stat == DEAD)
		LAZYSET(bot.unreachable_patients, patient, world.time + 2 MINUTES)

/datum/bot_goal/revive_patient/proc/return_paddles(datum/bot_brain/bot)
	if(!mount || QDELETED(mount) || !mount.defib)
		return
	var/obj/item/twohanded/shockpaddles/paddles = mount.defib.paddles
	if(paddles && paddles.loc == bot.owner)
		if(paddles.wielded)
			paddles.unwield(bot.owner)
		paddles.snap_back()

/datum/bot_strategy/revive
	var/obj/machinery/defibrillator_mount/mount

/datum/bot_strategy/revive/New(obj/machinery/defibrillator_mount/M)
	. = ..()
	mount = M
	var/datum/bot_step/move_to/to_mount = new()
	to_mount.step_target = M
	// To the body, hold of it, to the mount with it, the paddles down, and the shock
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_body(M), to_mount, new /datum/bot_step/grab_paddles(M), new /datum/bot_step/defibrillate())

/datum/bot_strategy/revive/is_feasible(datum/bot_brain/bot)
	return mount && !QDELETED(mount)

/// The body taken hold of, for the mount.
/datum/bot_step/grab_body
	var/obj/machinery/defibrillator_mount/mount

/datum/bot_step/grab_body/New(obj/machinery/defibrillator_mount/M)
	. = ..()
	mount = M

/datum/bot_step/grab_body/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient))
		return GOAL_STEP_FAIL
	if(patient.stat != DEAD)
		return GOAL_STEP_SUCCESS //somebody's brought them round already
	if(!bot.owner.Adjacent(patient))
		return GOAL_STEP_FAIL
	if(bot.owner.pulling == patient)
		return GOAL_STEP_SUCCESS
	if(!patient.can_be_pulled(bot.owner, 0, bot.owner.move_force))
		return GOAL_STEP_FAIL
	bot.owner.start_pulling(patient)
	if(bot.owner.pulling != patient) //start_pulling() returns nothing either way (grab_patient)
		return GOAL_STEP_FAIL
	bot_log(bot, "dragging [patient] to [mount] - dead [round((world.time - patient.timeofdeath) / 10)] s")
	return GOAL_STEP_SUCCESS

/datum/bot_step/grab_paddles
	var/obj/machinery/defibrillator_mount/mount

/datum/bot_step/grab_paddles/New(obj/machinery/defibrillator_mount/M)
	. = ..()
	mount = M

/datum/bot_step/grab_paddles/execute(datum/bot_brain/bot)
	if(!mount || QDELETED(mount) || !mount.defib || !mount.defib.paddles)
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(mount))
		return GOAL_STEP_FAIL
	var/obj/item/twohanded/shockpaddles/paddles = mount.defib.paddles
	if(paddles.loc == bot.owner)
		if(!paddles.wielded)
			paddles.wield(bot.owner)
		return paddles.wielded ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(paddles.loc != mount.defib)
		return GOAL_STEP_FAIL //someone beat us to them
	bot.free_both_hands()
	mount.attack_hand(bot.owner)
	if(paddles.loc != bot.owner)
		return GOAL_STEP_FAIL
	paddles.wield(bot.owner)
	return paddles.wielded ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/defibrillate/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient))
		return GOAL_STEP_FAIL
	if(patient.stat != DEAD)
		return GOAL_STEP_SUCCESS //already revived (by someone/something else)
	if(!bot.owner.Adjacent(patient))
		return GOAL_STEP_FAIL
	bot.owner.stop_pulling() //clear: whoever has hold of the patient gets the shock too (shock_touching())
	var/obj/item/twohanded/shockpaddles/paddles = locate(/obj/item/twohanded/shockpaddles) in bot.owner.held_items
	if(!paddles)
		return GOAL_STEP_FAIL
	if(!paddles.wielded)
		paddles.wield(bot.owner)
		if(!paddles.wielded)
			return GOAL_STEP_FAIL
	bot.owner.a_intent = INTENT_HELP
	bot.owner.zone_selected = BODY_ZONE_CHEST
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(bot, "shocking [patient] with the defibrillator")
	paddles.attack(patient, bot.owner) //yields for real time (do_after chain) - fine, same as climb_structure() elsewhere in this system
	if(QDELETED(patient) || patient.stat == DEAD)
		return GOAL_STEP_FAIL
	bot_tally("revived with the defibrillator")
	return GOAL_STEP_SUCCESS

// ============================================================
// Escort: drag an incapacitated (but alive) patient to the nearest sleeper, or a cryo
// cell if no sleeper's reachable - a bandage doesn't fix someone who's unconscious,
// they need real medical machinery. Sleepers are always preferred since they need no
// setup; a cryo cell is still worth using even with no beaker loaded yet (the
// temperature-induced sleep/stabilization in cryo_cell/process() applies regardless of
// whether a beaker's present - requiring one first used to deadlock escort entirely
// against load_cryo_beaker, which only ever runs when there's nobody to escort).
// Distance is measured from the PATIENT, not the bot, since that's who actually needs
// to end up there.
/// Whether a sleeper or cryo cell is one this bot would go to, or take somebody to: Medbay's - or, for security,
/// the brig infirmary's. The nearest as the crow flies is sometimes the brig's, which anybody else has to break in
/// to reach and is then shut in with: a hurt assistant sat out an evacuation in the Brig that way.
/datum/bot_brain/proc/healing_machine_is_ours(atom/machine)
	var/area/where = get_area(machine)
	if(gym_run)
		return where == get_area(owner)
	if(istype(where, /area/medical))
		return TRUE
	return is_security_job() && istype(where, /area/security)

/// The nearest free sleeper, or cryo cell if there's no sleeper. walking_in: it's going in on its own feet, so only one it can walk to by
/// a lawful route. Hurt crew were sent for the nearest sleeper behind Medbay's doors, found no way in, and gave up (shift fix1109a, 7 times).
/datum/bot_brain/proc/find_reachable_healing_machine(mob/living/patient, walking_in = FALSE)
	for(var/path in list(/obj/machinery/sleeper, /obj/machinery/atmospherics/components/unary/cryo_cell))
		var/list/by_dist = list()
		for(var/obj/machinery/M as anything in bot_instances_of(path))
			if(M.z != owner.z || !healing_machine_is_ours(M))
				continue
			var/obj/machinery/sleeper/S = M
			var/obj/machinery/atmospherics/components/unary/cryo_cell/C = M
			if((istype(S) && S.occupant) || (istype(C) && C.occupant))
				continue
			var/dist = get_dist(patient, M)
			if(dist <= 60)
				by_dist[M] = dist
		sortTim(by_dist, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
		var/tries = 0
		for(var/obj/machinery/M as anything in by_dist)
			if(!walking_in)
				return M
			if(tries++ >= 4)
				break
			if(can_walk_lawfully_to(M))
				return M
	return null

/datum/bot_goal/escort_to_sleeper
	exclusive = TRUE //one doctor to a patient: two went for the same one, and the second found them gone from where they'd lain
	var/atom/machine_target

/datum/bot_goal/escort_to_sleeper/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/best
	var/best_score
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == bot.owner || H.z != bot.owner.z)
			continue
		if(H.stat == CONSCIOUS || H.stat == DEAD)
			continue
		if(get_dist(bot.owner, H) > 60)
			continue
		if(!isturf(H.loc) || (H.pulledby && H.pulledby != bot.owner) || bot.taken_by_another(H))
			continue //in a machine already, being dragged in by somebody, or somebody's on their way
		if(LAZYACCESS(bot.unreachable_patients, H) > world.time)
			continue //just tried, and there was no way to them from here
		if(!bot.patient_needs_treatment(H))
			continue
		// Out cold with nothing wrong (asleep, sedated): a sleeper does nothing for them, and the next doctor round lets them straight
		// out (find_machine_to_empty(), medical_rounds.dm). Somebody asleep on morphine went in and out of one 94 times in four minutes.
		if(bot_sleeper_done_with(H) && !(bot_needs_blood(H) && bot.blood_pack_for(H)))
			continue
		var/score = bot.patient_injury_score(H) - get_dist(bot.owner, H)
		if(!best || score > best_score)
			best = H
			best_score = score
	if(!best)
		return
	// Short of blood, with a pack they can take and a drip free: to the drip, not into a sleeper, which does nothing for blood
	var/atom/M
	if(bot_needs_blood(best) && bot.blood_pack_for(best)) //goals/give_blood.dm
		M = bot.free_iv_drip_near(best, 200)
		if(M && get_dist(best, M) <= 2)
			return //there already: the drip's next (give_blood/urgent)
	if(!M && bot_sleeper_done_with(best))
		return //only short of blood, and no drip for it: not into a sleeper, which would let them out at once
	M = M || bot.find_reachable_healing_machine(best)
	if(!M)
		return
	target = best
	machine_target = M

/datum/bot_goal/escort_to_sleeper/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/escort(machine_target))

/datum/bot_goal/escort_to_sleeper/on_success(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	bot.continue_medical_round()

/datum/bot_goal/escort_to_sleeper/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	// Never got to them: left a couple of minutes for somebody who can be reached (or another doctor). One doctor tried
	// for a patient behind Engineering's doors 23 times in a shift, a route search each time, and saw nobody else.
	var/mob/living/carbon/human/patient = target
	if(istype(patient) && !QDELETED(patient) && !bot.owner.Adjacent(patient))
		LAZYSET(bot.unreachable_patients, patient, world.time + 2 MINUTES)
		bot.cant_reach_casualty(patient) //goals/carry_casualty.dm: somebody who can get to them is asked to bring them out

/datum/bot_brain
	/// Patients it gave up getting to: patient -> world.time it'll try again (escort_to_sleeper)
	var/list/unreachable_patients

/datum/bot_strategy/escort
	var/atom/machine_target

/datum/bot_strategy/escort/New(atom/M)
	. = ..()
	machine_target = M
	var/datum/bot_step/move_to/to_patient = new()
	var/datum/bot_step/move_to/to_machine = new()
	to_machine.step_target = M
	steps = list(to_patient, new /datum/bot_step/grab_patient(), to_machine, new /datum/bot_step/load_patient(M))

/datum/bot_strategy/escort/is_feasible(datum/bot_brain/bot)
	return machine_target && !QDELETED(machine_target)

/datum/bot_step/grab_patient/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient) || patient.stat == DEAD)
		bot_log_verbose(bot, "grab_patient: patient invalid/gone/dead ([patient])")
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(patient))
		bot_log_verbose(bot, "grab_patient: not adjacent - bot @ [bot_coord(get_turf(bot.owner))], patient @ [bot_coord(get_turf(patient))]")
		return GOAL_STEP_FAIL
	if(bot.owner.pulling == patient)
		return GOAL_STEP_SUCCESS
	// In crit: the epinephrine medipen first, as a doctor does before dragging anybody anywhere (the first aid kit has one). A patient
	// brought up from Engineering in crit had run up a hundred of suffocation on the way, and died in the sleeper at the end of it.
	if(patient.health <= 0 && !patient.reagents?.has_reagent(/datum/reagent/medicine/epinephrine))
		for(var/obj/item/reagent_containers/hypospray/medipen/pen in bot.owner.GetAllContents())
			if(pen.reagents?.has_reagent(/datum/reagent/medicine/epinephrine))
				bot_log(bot, "epinephrine into [patient] before moving them")
				bot.use_item_on(pen, patient)
				break
	var/datum/bot_goal/escort_to_sleeper/E = bot.current_goal
	if(istype(E))
		bot.bandage_for_sleeper(patient, E.machine_target)
	if(!patient.can_be_pulled(bot.owner, 0, bot.owner.move_force))
		bot_log_verbose(bot, "grab_patient: [patient].can_be_pulled() refused - anchored=[patient.anchored], throwing=[patient.throwing], patient move_resist=[patient.move_resist], bot move_force=[bot.owner.move_force]")
		return GOAL_STEP_FAIL
	bot.owner.start_pulling(patient)
	// /mob/living/start_pulling() (living.dm) has no explicit "return TRUE" on its
	// success path - it falls through into set_pull_offsets() and implicitly returns
	// null, unlike the base /atom/movable version this codebase's other callers assume.
	// Trusting that return value made this step report FAIL immediately after actually
	// successfully grabbing the patient (confirmed via attack.log: "grabbed ... passive
	// grab" logged the same tick this used to fail) - checking the real post-call state
	// instead of the unreliable return value.
	var/result = (bot.owner.pulling == patient)
	bot_log_verbose(bot, "grab_patient: start_pulling([patient]) -> pulling=[result]")
	return result ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Somebody too far gone for the sleeper (under its min_health it gives nothing but epinephrine, Sleeper.dm chem_allowed()) is
/// bandaged first, the worst wound at a time, until it can take over, as a doctor does before dragging them in. An engineer brought in
/// at -26 had epinephrine twice and suffocated in the sleeper with 91 brute that a bruise pack or two would have seen to.
/datum/bot_brain/proc/bandage_for_sleeper(mob/living/carbon/human/patient, obj/machinery/sleeper/S)
	if(!istype(S) || !istype(patient))
		return
	for(var/i in 1 to 4)
		if(QDELETED(patient) || patient.stat == DEAD || patient.health > S.min_health + 10 || !owner.Adjacent(patient))
			return
		aim_at_worst_wound(patient)
		// Under a firesuit or a hardsuit a bandage does nothing: a patch if there is one, otherwise the suit comes off first, as for any
		// patient (uncover_patient(), which leaves it on where the air would hurt them)
		var/obj/item/clothing/covering = clothing_in_the_way(patient)
		var/obj/item/I = pick_treatment_item(patient, !!covering)
		if(!I && covering && uncover_patient(patient, covering))
			I = pick_treatment_item(patient)
		if(!I)
			return
		bot_log(src, "patching up [patient] with [I] - too far gone for [S] to treat yet")
		use_item_on(I, patient)
		human_pause(patient)

/datum/bot_step/load_patient
	var/atom/machine_target

/datum/bot_step/load_patient/New(atom/M)
	. = ..()
	machine_target = M

/datum/bot_step/load_patient/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient) || QDELETED(machine_target))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(machine_target))
		return GOAL_STEP_FAIL
	if(bot.owner.pulling != patient && !bot.owner.Adjacent(patient))
		return GOAL_STEP_FAIL //lost them somewhere on the way over
	if(istype(machine_target, /obj/machinery/iv_drip)) //brought over for blood: set down beside it, and the drip's next
		bot.owner.stop_pulling()
		bot_log(bot, "brought [patient] to [machine_target] for blood")
		return GOAL_STEP_SUCCESS
	if(istype(machine_target, /obj/machinery/sleeper))
		var/obj/machinery/sleeper/S = machine_target
		if(S.occupant)
			return (S.occupant == patient) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
		// Shut and empty (whoever was in it got out, or was taken out): it's opened first, as a person clicks it open. Dropping a
		// patient on a shut one does nothing at all (close_machine() wants it open), and a doctor tried three times in two seconds
		// and gave up, the patient dying in crit on the floor next to it.
		if(!S.state_open)
			S.open_machine()
		S.MouseDrop_T(patient, bot.owner)
		if(S.occupant != patient)
			bot_log_verbose(bot, "load_patient: MouseDrop_T into [S] didn't take - state_open=[S.state_open], occupant=[S.occupant]")
			return GOAL_STEP_FAIL
		bot_log(bot, "loaded [patient] into [S]")
		var/chem = bot_sleeper_dose(S, patient) //goals/medical_rounds.dm
		if(chem)
			S.inject_chem(chem, bot.owner)
		return GOAL_STEP_SUCCESS
	if(istype(machine_target, /obj/machinery/atmospherics/components/unary/cryo_cell))
		var/obj/machinery/atmospherics/components/unary/cryo_cell/C = machine_target
		if(C.occupant)
			return (C.occupant == patient) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
		// Unlike /obj/machinery/sleeper (state_open = TRUE by default), a cryo cell
		// starts with its door CLOSED (cryo.dm:11) - close_machine() is a no-op unless
		// state_open is already TRUE, so MouseDrop_T() silently did nothing every time
		// without this: the patient never actually got inserted, confirmed in-game (the
		// bot "delivered" the patient but the cell stayed empty).
		if(!C.state_open)
			C.open_machine()
		C.MouseDrop_T(patient, bot.owner)
		if(C.occupant != patient)
			bot_log_verbose(bot, "load_patient: MouseDrop_T into [C] didn't take - state_open=[C.state_open], occupant=[C.occupant]")
			return GOAL_STEP_FAIL
		bot_log(bot, "loaded [patient] into [C]")
		C.on = TRUE
		C.update_icon()
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ============================================================
// Cryo setup: a real medbay's cryo loop needs someone to wrench an oxygen canister onto
// its connector port, turn the freezer on and set it to minimum, and drop a healing
// reagent beaker into each empty cell - none of which happens on its own. Each of the
// three is its own single-purpose goal (one task per trip, same convention as
// everything else in this file), tried only once no patient actually needs attention
// this tick (see try_medical_round() above). Every finder below only looks within a
// modest radius of an actual cryo cell, rather than grabbing the first wrenchable
// canister anywhere on the station regardless of what it's for.
// ============================================================

#define BOT_CRYO_SETUP_RADIUS 15
#define BOT_CRYO_SETUP_REACH 40

/datum/bot_brain/proc/find_disconnected_cryo_canister()
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/cryo_cell))
		if(C.z != owner.z || get_dist(owner, C) > BOT_CRYO_SETUP_REACH + BOT_CRYO_SETUP_RADIUS) //nothing round this one can be in reach: skip the range() scan, 2.5 ms a time
			continue
		for(var/obj/machinery/atmospherics/components/unary/portables_connector/P as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/portables_connector)) //not range(): 2.5 ms a look
			if(P.z != owner.z || P.connected_device || get_dist(P, C) > BOT_CRYO_SETUP_RADIUS)
				continue
			var/obj/machinery/portable_atmospherics/canister/O = locate(/obj/machinery/portable_atmospherics/canister) in P.loc
			if(O && !O.connected_port && get_dist(owner, O) <= BOT_CRYO_SETUP_REACH)
				return O
	return null

/datum/bot_brain/proc/find_unset_cryo_freezer()
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/cryo_cell))
		if(C.z != owner.z || get_dist(owner, C) > BOT_CRYO_SETUP_REACH + BOT_CRYO_SETUP_RADIUS)
			continue
		for(var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/F as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/thermomachine/freezer))
			if(F.z != owner.z || get_dist(F, C) > BOT_CRYO_SETUP_RADIUS)
				continue
			if(F.on && F.target_temperature <= F.min_temperature + 5)
				continue //already on and cold enough
			if(get_dist(owner, F) <= BOT_CRYO_SETUP_REACH)
				return F
	return null

/datum/bot_brain/proc/find_empty_cryo_cell()
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/cryo_cell))
		if(C.z != owner.z || C.beaker || C.occupant)
			continue
		if(get_dist(owner, C) <= BOT_CRYO_SETUP_REACH)
			return C
	return null

// Prefers an already-mixed cryoxadone/clonexadone/pyroxadone beaker (the actual "cryo
// chemical" family - medicine_reagents.dm/medicine.dm) if one's sitting out somewhere
// reachable, same as a doctor grabbing the pre-made batch off the apothecary shelf
// instead of synthesizing more. Falls back to any beaker with something in it if none
// of those specifically exist yet - still better than an empty cell, just less
// effective. Doesn't synthesize cryoxadone itself (stable_plasma + acetone + mutagen at
// a chem dispenser) - that's a chemist's job, not folded into doctor behavior here.
/datum/bot_brain/proc/find_reachable_healing_beaker()
	glance_at_items()
	var/obj/item/reagent_containers/glass/fallback
	for(var/obj/item/reagent_containers/glass/B as anything in bot_instances_of(/obj/item/reagent_containers/glass))
		if(!isturf(B.loc) || B.anchored || !knows_of(B)) //what it knows of (bot_knowledge.dm)
			continue
		if(!B.reagents || !B.reagents.total_volume)
			continue
		var/turf/T = get_turf(B)
		if(!T || T.z != owner.z)
			continue
		// Medbay's own, and one there's a way to. Any beaker anywhere used to do: a doctor spent the shift setting off
		// for whatever was sitting on a bench in Toxins, behind doors its ID doesn't open.
		if(!is_medbay_chemistry(B) || !can_walk_lawfully_to(B))
			continue
		if(B.reagents.has_reagent(/datum/reagent/medicine/cryoxadone) || B.reagents.has_reagent(/datum/reagent/medicine/clonexadone) || B.reagents.has_reagent(/datum/reagent/medicine/pyroxadone))
			return B
		if(!fallback)
			fallback = B
	return fallback

#undef BOT_CRYO_SETUP_RADIUS
#undef BOT_CRYO_SETUP_REACH

// Medbay's own housekeeping, all three of the cryo goals: done by the doors a doctor's ID opens, or left. A doctor
// after a beaker for the cryo tubes used to go through maintenance hacking doors for one - and died on an
// electrified one.
/datum/bot_goal/connect_cryo_canister
	lawful = TRUE
	var/obj/machinery/portable_atmospherics/canister/canister

/datum/bot_goal/connect_cryo_canister/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/C = bot.find_disconnected_cryo_canister()
	if(!C)
		return
	target = C
	canister = C

/datum/bot_goal/connect_cryo_canister/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/connect_canister(canister))

/datum/bot_goal/connect_cryo_canister/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/connect_canister
	var/obj/machinery/portable_atmospherics/canister/canister

/datum/bot_strategy/connect_canister/New(obj/machinery/portable_atmospherics/canister/C)
	. = ..()
	canister = C
	steps = list(new /datum/bot_step/ensure_wrench(), new /datum/bot_step/move_to(), new /datum/bot_step/wrench_canister(C))

/datum/bot_strategy/connect_canister/is_feasible(datum/bot_brain/bot)
	return canister && !QDELETED(canister)

/datum/bot_step/ensure_wrench
	var/tried_fetch = FALSE

/datum/bot_step/ensure_wrench/execute(datum/bot_brain/bot)
	if(bot.can_eventually_provide_tool(/obj/item/wrench)) //hand drill counts - see bot_tool_transform_pairs
		return GOAL_STEP_SUCCESS
	if(!tried_fetch)
		tried_fetch = TRUE
		if(bot.seek_tool_for_obstacle(/obj/item/wrench))
			return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/datum/bot_step/wrench_canister
	var/obj/machinery/portable_atmospherics/canister/canister

/datum/bot_step/wrench_canister/New(obj/machinery/portable_atmospherics/canister/C)
	. = ..()
	canister = C

/datum/bot_step/wrench_canister/execute(datum/bot_brain/bot)
	if(!canister || QDELETED(canister) || canister.connected_port)
		return GOAL_STEP_SUCCESS //already connected, by us or someone else
	if(!bot.owner.Adjacent(canister))
		return GOAL_STEP_FAIL
	var/obj/item/wrench/W = bot.find_or_transform_tool(/obj/item/wrench)
	if(!W)
		return GOAL_STEP_FAIL
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(W, canister)
	bot_log(bot, "wrenched [canister] onto its connector port")
	return canister.connected_port ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_goal/activate_cryo_freezer
	lawful = TRUE
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer

/datum/bot_goal/activate_cryo_freezer/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/F = bot.find_unset_cryo_freezer()
	if(!F)
		return
	target = F
	freezer = F

/datum/bot_goal/activate_cryo_freezer/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/activate_freezer(freezer))

/datum/bot_goal/activate_cryo_freezer/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/activate_freezer
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer

/datum/bot_strategy/activate_freezer/New(obj/machinery/atmospherics/components/unary/thermomachine/freezer/F)
	. = ..()
	freezer = F
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/set_freezer_cold(F))

/datum/bot_strategy/activate_freezer/is_feasible(datum/bot_brain/bot)
	return freezer && !QDELETED(freezer)

/datum/bot_step/set_freezer_cold
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer

/datum/bot_step/set_freezer_cold/New(obj/machinery/atmospherics/components/unary/thermomachine/freezer/F)
	. = ..()
	freezer = F

/datum/bot_step/set_freezer_cold/execute(datum/bot_brain/bot)
	if(!freezer || QDELETED(freezer))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(freezer))
		return GOAL_STEP_FAIL
	freezer.on = TRUE
	freezer.target_temperature = freezer.min_temperature
	freezer.use_power = ACTIVE_POWER_USE
	freezer.update_icon()
	bot_log(bot, "activated [freezer] and set it to minimum temperature")
	return GOAL_STEP_SUCCESS

/datum/bot_goal/load_cryo_beaker
	lawful = TRUE
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_goal/load_cryo_beaker/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/unary/cryo_cell/C = bot.find_empty_cryo_cell()
	if(!C)
		return
	var/obj/item/reagent_containers/glass/B = bot.find_reachable_healing_beaker()
	if(!B)
		return
	cell = C
	target = B

/datum/bot_goal/load_cryo_beaker/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/deliver_beaker(cell))

/datum/bot_goal/load_cryo_beaker/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/deliver_beaker
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_strategy/deliver_beaker/New(obj/machinery/atmospherics/components/unary/cryo_cell/C)
	. = ..()
	cell = C
	var/datum/bot_step/move_to/to_cell = new()
	to_cell.step_target = C
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pickup_item(), to_cell, new /datum/bot_step/load_beaker(C))

/datum/bot_strategy/deliver_beaker/is_feasible(datum/bot_brain/bot)
	return cell && !QDELETED(cell)

/datum/bot_step/load_beaker
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_step/load_beaker/New(obj/machinery/atmospherics/components/unary/cryo_cell/C)
	. = ..()
	cell = C

/datum/bot_step/load_beaker/execute(datum/bot_brain/bot)
	if(!cell || QDELETED(cell) || cell.beaker || cell.occupant)
		return GOAL_STEP_SUCCESS //already sorted, by us or someone else
	if(!bot.owner.Adjacent(cell))
		return GOAL_STEP_FAIL
	var/obj/item/reagent_containers/glass/B = bot.current_goal?.target
	if(!istype(B) || QDELETED(B))
		bot_log_verbose(bot, "load_beaker: target invalid/gone ([B])")
		return GOAL_STEP_FAIL
	// try_pickup_target()/stow_item() (bot_items.dm) prefer real storage (a pocket/
	// backpack) over the hand, so B.loc is very often the BAG, not bot.owner directly,
	// right after a successful pickup - checking that exact equality failed every
	// delivery that stowed rather than held (confirmed in-game: "picked up the beaker"
	// logged fine, then this step failed the very next tick). GetAllContents() walks
	// nested storage the same way get_medical_supplies() above already does; use_item_on()
	// itself already knows how to pull a stowed item into hand regardless.
	if(!(B in bot.owner.GetAllContents()) && (!isturf(B.loc) || B.loc != get_turf(bot.owner)))
		bot_log_verbose(bot, "load_beaker: [B] is no longer with us (loc=[B.loc])")
		return GOAL_STEP_FAIL
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(B, cell)
	bot_log(bot, "loaded [B] into [cell]")
	return cell.beaker ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ============================================================
// First aid on the spot. Somebody in crit went to a sleeper if one was free, on to the operating table if they were cut or burnt
// enough and not in cuffs, and otherwise nowhere: treat_patient is for people on their feet. A traitor beaten down in the Bar,
// cuffed and carried to Medbay's door, lay there three and a half minutes with three doctors on shift and died of it. What a
// doctor does for somebody like that is what anybody can: the epinephrine pen out of the first-aid kit, something on the wounds,
// and CPR, which gives back seven of suffocation a go against the two or three they lose in that time.
// ============================================================

/// Whether there's anything this bot can do for somebody in crit, here and now.
/datum/bot_brain/proc/first_aid_for(mob/living/carbon/human/H)
	if(!H.reagents?.has_reagent(/datum/reagent/medicine/epinephrine))
		for(var/obj/item/reagent_containers/hypospray/medipen/pen in owner.GetAllContents())
			if(pen.reagents?.has_reagent(/datum/reagent/medicine/epinephrine))
				return pen
	// Short of blood: the saline pen (prototype_chems.dm), which stands in for it until a drip's on them
	if(bot_needs_blood(H) && !H.reagents?.has_reagent(/datum/reagent/medicine/salglu_solution))
		for(var/obj/item/reagent_containers/hypospray/medipen/pen in owner.GetAllContents())
			if(pen.reagents?.has_reagent(/datum/reagent/medicine/salglu_solution))
				return pen
	if(H.getBruteLoss() + H.getFireLoss() > 20)
		var/obj/item/I = pick_treatment_item(H, !!clothing_in_the_way(H))
		if(I)
			return I
	if(H.getOxyLoss() > 0 && !owner.is_mouth_covered() && !H.is_mouth_covered())
		return H //CPR
	return null

/// Another medic seeing to them, holding them or on the way: a doctor leaves them to it. Security holding a prisoner by the Brig door for
/// Medical, or somebody holding a downed traitor for Security, is no reason to walk off. A doctor reached a cuffed traitor kept by the Brig
/// door, found nobody to treat because an engineer was holding him and the Head of Security had him, and went; he suffocated (2026-11-10).
/datum/bot_brain/proc/another_medic_has(mob/living/carbon/human/H)
	if(H.pulledby && H.pulledby != owner && bot_is_medic(H.pulledby))
		return TRUE
	if(!taken_by_another(H))
		return FALSE
	var/datum/bot_brain/other = GLOB.bot_work_claims[REF(H)]
	return !other || bot_is_medic(other.owner)

/// Kept for a doctor by Security: an officer keeping a prisoner just inside Security's door, or staying with one it has brought to
/// Medbay (brig_care, medevac: goals/security_medevac.dm), and not walking them anywhere just now. The officer's goal claims them, so
/// nobody carries them off or takes them over; it's no claim on their treatment.
/datum/bot_brain/proc/kept_for_a_doctor(mob/living/carbon/human/H)
	if(!taken_by_another(H))
		return FALSE
	var/datum/bot_brain/keeper = GLOB.bot_work_claims[REF(H)]
	if(bot_is_medic(keeper.owner) || (keeper.pursuing_kind == "goal" && H.pulledby == keeper.owner))
		return FALSE
	var/datum/bot_goal/kept = (keeper.current_goal?.target == H) ? keeper.current_goal : keeper.suspended_goal
	return istype(kept, /datum/bot_goal/brig_prisoner/brig_care) || istype(kept, /datum/bot_goal/brig_prisoner/medevac)

/// Another doctor at them already where they lie (stabilise). For anybody else its claim says so; for somebody Security's keeping for
/// a doctor the claim is the officer's (kept_for_a_doctor()).
/datum/bot_brain/proc/stabilised_by_another(mob/living/carbon/human/H)
	for(var/datum/bot_brain/other as anything in GLOB.bot_brains)
		if(other == src || QDELETED(other) || QDELETED(other.owner) || other.owner.stat != CONSCIOUS)
			continue
		var/datum/bot_goal/stabilise/theirs = other.current_goal
		if(istype(theirs) && theirs.target == H)
			return TRUE
	return FALSE

/// The patient it was called to (bot_request_kind/medical/attend()), down in crit a few steps off, and kept there by Security for a doctor
/datum/bot_brain/proc/called_patient_kept_down()
	var/mob/living/carbon/human/called = (world.time < called_patient_until) ? called_patient?.resolve() : null
	if(!istype(called) || called.stat == DEAD || called.stat == CONSCIOUS || called.health > called.crit_threshold || get_dist(owner, called) > 7)
		return FALSE
	return kept_for_a_doctor(called)

/datum/bot_goal/stabilise
	lawful = TRUE
	exclusive = TRUE //one to a casualty
	doing = "keeping somebody alive"

/datum/bot_goal/stabilise/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/best
	var/best_score
	var/mob/living/carbon/human/called = (world.time < bot.called_patient_until) ? bot.called_patient?.resolve() : null
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == bot.owner || H.z != bot.owner.z || H.stat == CONSCIOUS || H.stat == DEAD || !isturf(H.loc) || H.health > H.crit_threshold)
			continue
		if(bot.gym_run && get_area(H) != get_area(bot.owner))
			continue
		if(!bot.patient_needs_treatment(H) || get_dist(bot.owner, H) > 40)
			continue //nobody Security's after until they're in cuffs, as for any patient
		if(bot.another_medic_has(H) || LAZYACCESS(bot.unreachable_patients, H) > world.time)
			continue
		if(bot.kept_for_a_doctor(H) && bot.stabilised_by_another(H))
			continue //another doctor's at them already: the claim on them is the officer's, so it doesn't say so
		if(!bot.first_aid_for(H))
			continue
		// The one it was called to before anybody it wasn't, as treat_patient's resolve_target() has it
		var/score = bot.patient_injury_score(H) + H.getOxyLoss() - get_dist(bot.owner, H) + (H == called ? 200 : 0)
		if(!best || score > best_score)
			best = H
			best_score = score
	if(!best)
		return
	if(!bot.can_walk_lawfully_to(best))
		LAZYSET(bot.unreachable_patients, best, world.time + 2 MINUTES)
		bot.cant_reach_casualty(best) //goals/carry_casualty.dm
		return
	target = best
	// Security keeping them for a doctor: the officer's goal claims them, which is what keeps a sleeper run or a carry out of Security
	// off a prisoner who stays in it. Taken as a claim on their first aid it turned the doctor away ("already being seen to - leaving
	// stabilise to them"), 14 times in three batches of twelve shifts at a prisoner down in crit, and four of those prisoners died where
	// they lay within the minute (bugs1112b run9 Sam Delacroix, bugs1112a run8 Val Castillo and run12 Corey Ishikawa, bugs1112base run6
	// Morgan Vance). Not exclusive then: the officer's claim stays as it is, and a second doctor is kept off by stabilised_by_another().
	exclusive = !bot.kept_for_a_doctor(best)

/datum/bot_goal/stabilise/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/stabilise/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/stabilise())
	return list(S)

/datum/bot_strategy/stabilise/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_goal/stabilise/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_goal/stabilise/on_give_up(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = target
	if(istype(patient) && !QDELETED(patient))
		LAZYSET(bot.unreachable_patients, patient, world.time + 2 MINUTES)

/// The pen, the dressings, then CPR for as long as it's doing any good.
/datum/bot_step/paced/stabilise
	max_clicks = 12
	var/mob/living/carbon/human/patient
	var/breaths = 0
	var/did_something = FALSE

/datum/bot_step/paced/stabilise/start(datum/bot_brain/bot)
	patient = bot.current_goal?.target
	return istype(patient) && !QDELETED(patient) && bot.owner.Adjacent(patient)

/datum/bot_step/paced/stabilise/do_click(datum/bot_brain/bot)
	if(QDELETED(patient) || patient.stat == DEAD || patient.stat == CONSCIOUS || patient.health > patient.crit_threshold || !isturf(patient.loc) || !bot.owner.Adjacent(patient))
		return FALSE
	var/atom/with = bot.first_aid_for(patient)
	if(!with)
		return FALSE
	if(with == patient)
		if(breaths >= 40)
			return FALSE
		if(!breaths)
			bot_log(bot, "CPR on [patient], who's at [round(patient.health)]")
		breaths++
		did_something = TRUE
		bot.owner.face_atom(patient)
		bot.telemetry_clicked(patient)
		INVOKE_ASYNC(bot.owner, TYPE_PROC_REF(/mob/living/carbon/human, do_cpr), patient) //what a help-intent click on somebody in crit does
		wait_for = 35 //it takes three seconds, stood still
		return TRUE
	bot.aim_at_worst_wound(patient)
	bot_log(bot, "[with] for [patient], down at [round(patient.health)] with nowhere to take them")
	did_something = TRUE
	bot.use_item_on(with, patient)
	return TRUE

/datum/bot_step/paced/stabilise/finish(datum/bot_brain/bot)
	if(!did_something)
		return GOAL_STEP_FAIL
	if(!QDELETED(patient) && patient.stat != DEAD)
		bot_log(bot, "[patient] is at [round(patient.health)] after first aid[breaths ? ", [breaths] goes of CPR" : ""]")
		bot_tally("given first aid where they lay")
	return GOAL_STEP_SUCCESS
