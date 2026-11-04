// Bot Gym scenarios for medical work (goals/treat_patient.dm, goals/self_heal.dm). The patient (C) is
// a stand-in crew member with nobody driving it.

/datum/bot_scenario/patient
	job = "Medical Doctor"
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/patient
	/// What the patient is wearing over the wounds, if anything.
	var/suit_type

/datum/bot_scenario/patient/post_spawn()
	patient = stand_in(first_marker("C"), "Pat Patient")
	if(suit_type)
		patient.equip_to_slot_or_del(new suit_type(patient), ITEM_SLOT_OCLOTHING)
	patient.apply_damage(30, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/patient/make_goal()
	return new /datum/bot_goal/treat_patient()

/datum/bot_scenario/patient/proc/patched_up()
	return patient.getBruteLoss() <= 10 && patient.getFireLoss() <= 10

/datum/bot_scenario/patient/firesuit
	name = "doctor treats a patient in a firesuit"
	desc = "The patient is hurt under an emergency firesuit, which no bandage gets through (a real shift's doctor clicked a bruise pack on one 1,410 times). The doctor takes the suit off them the way a player does, then patches them up."
	layout = list(
		"#########",
		"#B..C...#",
		"#########")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment)
	suit_type = /obj/item/clothing/suit/fire

/datum/bot_scenario/patient/firesuit/post_spawn()
	..()
	patient.apply_damage(20, BURN, BODY_ZONE_L_ARM)

/datum/bot_scenario/patient/firesuit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!patched_up())
		return BOT_GYM_PENDING
	if(patient.wear_suit)
		fail_reason = "healed them with the firesuit still on - that shouldn't be possible with a bruise pack"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/patient/patch_through_suit
	name = "doctor sticks a patch on over a firesuit"
	desc = "Same patient, but the doctor's kit has styptic patches, which work over anything. It uses one and leaves the suit where it is."
	layout = list(
		"#########",
		"#B..C...#",
		"#########")
	kit_backpack = list(/obj/item/reagent_containers/pill/patch/styptic, /obj/item/reagent_containers/pill/patch/styptic, /obj/item/stack/medical/bruise_pack)
	suit_type = /obj/item/clothing/suit/fire

/datum/bot_scenario/patient/patch_through_suit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!patient.wear_suit)
		fail_reason = "took the suit off with patches in the bag"
		return BOT_GYM_FAIL
	return patched_up() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/patient/plain
	name = "doctor bandages a hurt crew member"
	desc = "The ordinary case, which had no scenario: walk over, bruise pack on the worst wound until they're patched up."
	layout = list(
		"#########",
		"#B..C...#",
		"#########")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack)
	time_limit = 30 SECONDS

/datum/bot_scenario/patient/plain/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return patched_up() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/back_from_the_dead
	name = "revived bot gets going again"
	desc = "A bot dies and is brought back. It used to stand where it was revived for the rest of the shift - its brain stopped for good the moment it died."
	layout = list(
		"#########",
		"#B.....G#",
		"#########")
	time_limit = 30 SECONDS
	var/revived = FALSE

/datum/bot_scenario/back_from_the_dead/issue_goal()
	if(revived)
		..()

/datum/bot_scenario/back_from_the_dead/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(kill_bot)), 1 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(revive_bot)), 5 SECONDS)

/datum/bot_scenario/back_from_the_dead/proc/kill_bot()
	if(!QDELETED(bot))
		bot.death()

/datum/bot_scenario/back_from_the_dead/proc/revive_bot()
	if(QDELETED(bot))
		return
	bot.revive(full_heal = TRUE)
	revived = TRUE
	log_line("revived")

/datum/bot_scenario/back_from_the_dead/check()
	if(!bot || QDELETED(bot))
		fail_reason = "bot was destroyed"
		return BOT_GYM_FAIL
	if(!revived)
		return BOT_GYM_PENDING
	if(!(brain.datum_flags & DF_ISPROCESSING))
		fail_reason = "revived, but its brain was never started again"
		return BOT_GYM_FAIL
	return get_turf(bot) == first_marker("G") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/patient/walked_on
	name = "doctor goes after a patient who walked on"
	desc = "The patient strolls off down the corridor while the doctor is on its way over. The doctor doesn't give up at the spot where they were: it goes after them and patches them up (a real shift's doctor wrote off three walking patients in a row)."
	layout = list(
		"##############",
		"#B....C....j.#",
		"##############")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment)

/datum/bot_scenario/patient/walked_on/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(stroll_off)), 8)

/datum/bot_scenario/patient/walked_on/proc/stroll_off()
	if(result != BOT_GYM_PENDING || QDELETED(patient))
		return
	log_line("patient: walks on down the corridor")
	walk_to(patient, first_marker("j"), 0, 3)

/datum/bot_scenario/patient/walked_on/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return patched_up() ? BOT_GYM_PASS : BOT_GYM_PENDING

/// A body nobody's defibrillating, on a real scanner, console and pod. The patient is a bot itself, or there's nothing to come back.
/datum/bot_scenario/patient/cloning
	name = "doctor clones somebody, and they get their things back"
	desc = "The patient's dead with no paddles in the room. The doctor drags the body to the scanner, scans it, starts the pod, and opens the scanner again. The same bot climbs out with its brain and its name, and takes its ID and clothes back off its old body."
	layout = list(
		"#############",
		"#B.........C#",
		"#...........#",
		"#....QKZ....#",
		"#############")
	time_limit = 7 MINUTES
	var/datum/bot_brain/patient_brain
	var/obj/item/card/id/patient_id

/datum/bot_scenario/patient/cloning/setup()
	for(var/turf/T in markers["Q"])
		place("Q", new /obj/machinery/dna_scannernew(T))
	for(var/turf/T in markers["Z"])
		place("Z", new /obj/machinery/clonepod(T))
	for(var/turf/T in markers["K"])
		place("K", new /obj/machinery/computer/cloning(T))

/datum/bot_scenario/patient/cloning/post_spawn()
	..()
	give_job_id(list(ACCESS_MEDICAL))
	patient.mind_initialize()
	patient.mind.assigned_role = "Assistant"
	patient_brain = new(patient)
	patient.key = "bot-pat-patient"
	patient_id = new(patient)
	patient_id.registered_name = patient.real_name
	patient.equip_to_slot_or_del(patient_id, ITEM_SLOT_ID)
	patient.death()

/datum/bot_scenario/patient/cloning/make_goal()
	return new /datum/bot_goal/clone_body()

/datum/bot_scenario/patient/cloning/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/mob/living/carbon/human/clone = patient_brain.owner
	if(clone == patient || !isturf(clone.loc) || clone.stat != CONSCIOUS)
		return BOT_GYM_PENDING
	if(clone.real_name != "Pat Patient" || clone.mind != patient_brain.owner.mind || patient.bot_brain)
		fail_reason = "came out as [clone.real_name], with the brain in the wrong place"
		return BOT_GYM_FAIL
	var/obj/machinery/dna_scannernew/S = first_placed("Q")
	if(!S.state_open || S.occupant)
		fail_reason = "the body was left shut in the scanner"
		return BOT_GYM_FAIL
	if(clone.wear_id != patient_id || !clone.w_uniform)
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

/datum/bot_scenario/patient/poisoned
	name = "doctor gives a poisoned patient charcoal from the toxin kit"
	desc = "The patient has 40 toxin damage, what radiation sickness does, and not a scratch. The doctor feeds them a charcoal pill out of the pill bottle in its bag. Doctors used to see to brute and burn and nothing else: 21 of a crew died of radiation in one shift."
	layout = list(
		"#########",
		"#B..C...#",
		"#########")
	kit_backpack = list(/obj/item/storage/pill_bottle/charcoal)
	time_limit = 40 SECONDS

/datum/bot_scenario/patient/poisoned/post_spawn()
	patient = stand_in(first_marker("C"), "Pat Patient")
	patient.adjustToxLoss(40)

/datum/bot_scenario/patient/poisoned/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return patient.reagents?.has_reagent(/datum/reagent/medicine/charcoal) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/emergency_internals
	name = "an assistant where the air's gone puts the mask on and opens the tank"
	desc = "No oxygen in the room. An assistant, no space job, has the survival box's mask and tank in its bag: it puts the mask on and breathes from the tank. Only the jobs that go out into space used to: officers in a Brig whose air had gone suffocated with full tanks in their bags."
	layout = list(
		"#########",
		"#...B...#",
		"#########")
	job = "Assistant"
	kit_backpack = list(/obj/item/clothing/mask/breath, /obj/item/tank/internals/emergency_oxygen)
	time_limit = 30 SECONDS

/datum/bot_scenario/emergency_internals/issue_goal()
	return

/datum/bot_scenario/emergency_internals/post_spawn()
	..()
	brain.gym_scripted = FALSE //a scripted bot minds no air but a space job's
	for(var/turf/open/T in arena_area)
		T.air.moles[/datum/gas/oxygen] = 0
		T.air_update_turf()

/datum/bot_scenario/emergency_internals/check()
	if(bot_lost() || bot.getOxyLoss() > 60)
		return BOT_GYM_FAIL
	return bot.internal ? BOT_GYM_PASS : BOT_GYM_PENDING
