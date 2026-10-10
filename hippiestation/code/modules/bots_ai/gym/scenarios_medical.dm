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
