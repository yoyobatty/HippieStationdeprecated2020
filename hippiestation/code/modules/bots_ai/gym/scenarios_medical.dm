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

// ---------------------------------------------------------------------------------------------
// The defibrillator on the wall (goals/treat_patient.dm). Layout letter K: the mount. C: the body.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/revive
	name = "doctor drags somebody just dead to the defibrillator on the wall and shocks them back"
	desc = "The paddles reach a tile from the mount. The doctor took them down and set off for the body with them, they came out of its hands on the second step, and in twelve shifts nobody was ever shocked. The body's brought to the mount."
	job = "Medical Doctor"
	time_limit = 60 SECONDS
	max_goal_attempts = 1
	layout = list(
		"############",
		"#B....C...K#",
		"############")
	var/mob/living/carbon/human/patient

/datum/bot_scenario/revive/setup()
	for(var/turf/T in markers["K"])
		place("K", new /obj/machinery/defibrillator_mount/loaded(T))

/datum/bot_scenario/revive/post_spawn()
	patient = stand_in(first_marker("C"), "Pat Patient")
	patient.adjustOxyLoss(200)
	patient.death()

/datum/bot_scenario/revive/make_goal()
	return new /datum/bot_goal/revive_patient()

/datum/bot_scenario/revive/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(patient))
		fail_reason = "the patient's gone"
		return BOT_GYM_FAIL
	return patient.stat != DEAD ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/revive/too_late
	name = "doctor leaves somebody dead too long for the defibrillator to the cloner"
	desc = "Dead a minute and fifty seconds, with the paddles good for two minutes: no time to drag them over. It tried anyway, a dozen times a body."
	time_limit = 15 SECONDS

/datum/bot_scenario/revive/too_late/post_spawn()
	..()
	patient.timeofdeath = world.time - 110 SECONDS

/datum/bot_scenario/revive/too_late/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.pulling == patient || (locate(/obj/item/twohanded/shockpaddles) in bot.held_items) || bot_transcript_said("bot_strategy/revive"))
		fail_reason = "set about reviving somebody there was no time for"
		return BOT_GYM_FAIL
	return world.time > start_time + 8 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/revive/kept_alive
	name = "somebody shocked back is kept alive after"
	desc = "The paddles bring somebody back at fifty under, too far gone to breathe. A doctor shocked them, went on to the next patient, and they were dead again in twenty seconds: one body was shocked back twenty times in a shift."
	time_limit = 90 SECONDS
	max_goal_attempts = 6
	var/back_at = 0

/datum/bot_scenario/revive/kept_alive/make_goal()
	if(back_at)
		brain.try_medical_round() //what a doctor's round goes on to
		return null
	return ..()

/datum/bot_scenario/revive/kept_alive/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(patient))
		fail_reason = "the patient's gone"
		return BOT_GYM_FAIL
	if(!back_at)
		if(patient.stat != DEAD)
			back_at = world.time
		return BOT_GYM_PENDING
	var/list/in_them = list()
	for(var/datum/reagent/R as anything in patient.reagents.reagent_list)
		in_them += "[R.name] [round(R.volume, 0.1)]"
	if(!(round((world.time - back_at) / 10) % 5))
		log_line("[round((world.time - back_at) / 10)]s after the shock: health [round(patient.health, 0.1)], suffocation [round(patient.getOxyLoss(), 0.1)], missed breaths [patient.losebreath], heart [patient.undergoing_cardiac_arrest() ? "stopped" : "beating"], in [patient.loc], [length(in_them) ? jointext(in_them, ", ") : "nothing in them"]")
	if(patient.stat == DEAD)
		fail_reason = "dead again [round((world.time - back_at) / 10)] s after the shock"
		return BOT_GYM_FAIL
	return world.time > back_at + 45 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/revive/bled_out
	name = "doctor leaves somebody who bled to death to the cloner"
	desc = "Just dead, with less than half their blood left. The paddles bring them back with nothing to live on and they're dead again in twenty seconds: one body was shocked back twenty times in a shift."
	time_limit = 15 SECONDS

/datum/bot_scenario/revive/bled_out/post_spawn()
	..()
	patient.blood_volume = 250

/datum/bot_scenario/revive/bled_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.pulling == patient || (locate(/obj/item/twohanded/shockpaddles) in bot.held_items) || bot_transcript_said("bot_strategy/revive"))
		fail_reason = "set about shocking back somebody with no blood to live on"
		return BOT_GYM_FAIL
	return world.time > start_time + 8 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/first_aid
	name = "a doctor with no sleeper and no table for somebody in crit keeps them alive where they lie"
	desc = "Somebody suffocating in crit, and nothing in the room to put them in or on. Doctors only took such a patient to a sleeper or the operating table, and with neither there walked on: one lay at Medbay's door for three and a half minutes and died. CPR, at the least."
	job = "Medical Doctor"
	griefer_job = "Assistant"
	griefer_name = "Pat Patient"
	time_limit = 90 SECONDS
	layout = list(
		"#########",
		"#B....C.#",
		"#########")
	var/down = FALSE

/datum/bot_scenario/griefed/first_aid/grief()
	griefer.adjustOxyLoss(165) //past breathing for themselves: at twenty-five under they come round on their own
	griefer.updatehealth()
	griefer.update_stat()
	down = TRUE
	brain.try_medical_round()

/datum/bot_scenario/griefed/first_aid/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!down)
		return BOT_GYM_PENDING
	if(griefer.stat == DEAD)
		fail_reason = "the patient died"
		return BOT_GYM_FAIL
	return griefer.health > griefer.crit_threshold ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Somebody down where no doctor can get to them (goals/carry_casualty.dm). C: the casualty. G: Medbay's door.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/duty/carry_casualty
	name = "a colleague brings somebody down in the department out to Medbay, after the doctor says it can't get in"
	desc = "An engineer out cold on the engine room floor, and a doctor who's said on the radio it can't get to them. They lay there until they died, with the department walking past. Somebody who can get to them takes hold, drags them to Medbay's door and tells the doctors."
	duty_type = /datum/bot_duty/bring_casualty_out
	job = "Station Engineer"
	time_limit = 40 SECONDS
	layout = list(
		"##############",
		"#B..C.......G#",
		"##############")
	var/mob/living/carbon/human/casualty

/datum/bot_scenario/duty/carry_casualty/post_spawn()
	casualty = stand_in(first_marker("C"), "Cas Casualty")
	casualty.adjustOxyLoss(130)
	casualty.updatehealth()
	casualty.update_stat()
	brain.gym_medbay_spot = first_marker("G")
	bot_note_stranded(casualty)

/datum/bot_scenario/duty/carry_casualty/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(casualty) || casualty.stat == DEAD)
		fail_reason = "the casualty died"
		return BOT_GYM_FAIL
	if(casualty.stat == CONSCIOUS)
		fail_reason = "the casualty came round: nothing tried"
		return BOT_GYM_FAIL
	return (get_dist(casualty, first_marker("G")) <= 1 && bot.pulling != casualty) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/carry_casualty/on_their_feet
	name = "somebody hurt but on their feet isn't dragged off to Medbay"
	desc = "The doctor couldn't get to them, and they're still standing: they can walk there. Nobody takes hold of them."
	time_limit = 15 SECONDS

/datum/bot_scenario/duty/carry_casualty/on_their_feet/post_spawn()
	casualty = stand_in(first_marker("C"), "Cas Casualty")
	casualty.adjustBruteLoss(40)
	brain.gym_medbay_spot = first_marker("G")
	bot_note_stranded(casualty)

/datum/bot_scenario/duty/carry_casualty/on_their_feet/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.pulling == casualty || get_dist(casualty, first_marker("C")) > 0)
		fail_reason = "dragged off somebody who could walk"
		return BOT_GYM_FAIL
	return world.time > start_time + 8 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/asks_for_casualty
	name = "a doctor that can't get to somebody down asks for them to be brought out"
	desc = "Somebody out cold and badly hurt behind a door the doctor's ID doesn't open, and nobody's called. It gave up on getting to them and said nothing, again and again, until they died where they lay. It says so now, and they go on the list of people to be brought out to Medbay."
	job = "Medical Doctor"
	griefer_job = "Station Engineer"
	griefer_name = "Cas Casualty"
	time_limit = 20 SECONDS
	layout = list(
		"###########",
		"#B.T..D.C.#",
		"###########")

/datum/bot_scenario/griefed/asks_for_casualty/setup()
	for(var/turf/T in markers["T"])
		place("T", new /obj/structure/table/optable(T))
	for(var/turf/T in markers["D"])
		for(var/obj/machinery/door/airlock/A in T)
			A.req_access = list(ACCESS_ENGINE_EQUIP)

/datum/bot_scenario/griefed/asks_for_casualty/grief()
	griefer.adjustBruteLoss(90)
	griefer.Unconscious(180 SECONDS)
	brain.assign_goal(new /datum/bot_goal/operate())

/datum/bot_scenario/griefed/asks_for_casualty/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return GLOB.bot_stranded_casualties[WEAKREF(griefer)] ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/asks_for_casualty/release_run()
	GLOB.bot_stranded_casualties -= WEAKREF(griefer)
	return ..()

// Layout letter N: a NanoMed, as on a hallway wall.
/datum/bot_scenario/self_patch
	name = "somebody hurt with no first aid in reach buys a patch from the NanoMed on the wall"
	desc = "Cut about, nothing on it to treat itself with and no kit it can get to, and a NanoMed down the corridor that sells patches to anybody. It gave up on itself."
	job = "Assistant"
	time_limit = 60 SECONDS
	max_goal_attempts = 2
	layout = list(
		"#########",
		"#B.....N#",
		"#########")

/datum/bot_scenario/self_patch/setup()
	for(var/turf/T in markers["N"])
		place("N", new /obj/machinery/vending/wallmed(T))

/datum/bot_scenario/self_patch/post_spawn()
	give_job_id()
	bot.apply_damage(45, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/self_patch/make_goal()
	return new /datum/bot_goal/self_heal()

/datum/bot_scenario/self_patch/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	// The patch on, and the styptic in it at work
	return (bot.reagents.has_reagent(/datum/reagent/medicine/styptic_powder) || bot.getBruteLoss() < 35) ? BOT_GYM_PASS : BOT_GYM_PENDING

// From the user's Captain round (2026-11-10)

/// The only doctor hacked into the Courtroom and the Brig for patients and left both bolted open. Medical asks Security or the AI to open up.
/datum/bot_scenario/no_hacking_security
	name = "doctor: a patient behind a Security door, it asks to be let in rather than hacking it"
	desc = "A casualty lies behind a door that only opens for Security, and an officer's about. The doctor has the tools to hack it, but asks on the radio to be let in instead."
	job = "Medical Doctor"
	layout = list(
		"##########",
		"#sB.D.C..#",
		"#O########",
		"##########")
	kit_backpack = list(/obj/item/screwdriver, /obj/item/multitool, /obj/item/wirecutters, /obj/item/clothing/gloves/color/yellow)
	time_limit = 25 SECONDS
	var/mob/living/carbon/human/patient

/datum/bot_scenario/no_hacking_security/setup()
	var/obj/machinery/door/airlock/A = locate() in first_marker("D")
	if(A)
		A.req_access = list(ACCESS_BRIG)
		A.req_one_access = null
	place("s", new /obj/machinery/sleeper(first_marker("s")))

/datum/bot_scenario/no_hacking_security/post_spawn()
	give_job_id(list(ACCESS_MEDICAL))
	patient = stand_in(first_marker("C"), "Pat Prisoner")
	patient.apply_damage(130, BRUTE, BODY_ZONE_CHEST)
	var/mob/living/carbon/human/officer = stand_in(first_marker("O"), "Sam Officer")
	officer.mind_initialize()
	officer.mind.assigned_role = "Security Officer"

/datum/bot_scenario/no_hacking_security/make_goal()
	return new /datum/bot_goal/escort_to_sleeper()

/datum/bot_scenario/no_hacking_security/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("trying to hack it"))
		fail_reason = "hacked its way into Security"
		return BOT_GYM_FAIL
	return bot_transcript_said("asking to be let in") ? BOT_GYM_PASS : BOT_GYM_PENDING

/// A cuffed traitor in crit was kept by the Brig door for Medical. The doctor got there, found "nobody" to treat because an engineer was
/// holding him and the Head of Security had him, and went; he suffocated a minute later.
/datum/bot_scenario/patient/held_for_security
	name = "doctor: a casualty in cuffs that somebody's holding for Security still gets seen to"
	desc = "A cuffed prisoner lies in crit, held by a crew member waiting for Security. The doctor sees to them anyway: somebody holding them isn't somebody treating them."
	layout = list(
		"#########",
		"#B..CH..#",
		"#########")
	kit_backpack = list(/obj/item/reagent_containers/hypospray/medipen, /obj/item/reagent_containers/hypospray/medipen)
	time_limit = 25 SECONDS
	var/mob/living/carbon/human/holder

/datum/bot_scenario/patient/held_for_security/post_spawn()
	..()
	patient.apply_damage(100, BRUTE, BODY_ZONE_CHEST)
	patient.handcuffed = new /obj/item/restraints/handcuffs(patient)
	patient.update_handcuffed()
	holder = stand_in(first_marker("H"), "Bailey Holder")
	holder.start_pulling(patient)

/datum/bot_scenario/patient/held_for_security/make_goal()
	return new /datum/bot_goal/stabilise()

/datum/bot_scenario/patient/held_for_security/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("goal /datum/bot_goal/stabilise succeeded") || patient.reagents.has_reagent(/datum/reagent/medicine/epinephrine))
		return BOT_GYM_PASS
	if(bot_transcript_said("couldn't find a target for /datum/bot_goal/stabilise"))
		fail_reason = "found nobody to treat"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/// Two of the crew came out of the cloning pod at 60 cloning damage and went straight back to their killer. The user's ruling: into cryo.
/datum/bot_scenario/duty/clone_to_cryo
	name = "cloned: out of the pod with cloning damage, it gets into a cryo cell"
	desc = "The bot is fresh out of the cloning pod with 60 cloning damage and its things on. A cryo cell with cryoxadone in its beaker stands across the room. It gets in."
	job = "Station Engineer"
	layout = list(
		"########",
		"#B....y#",
		"########")
	time_limit = 25 SECONDS
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_scenario/duty/clone_to_cryo/setup()
	duty_type = text2path("/datum/bot_duty/clone_recovery") // by name: a build without the fix has no such duty
	cell = new(first_marker("y"))
	place("y", cell)
	cell.beaker = new /obj/item/reagent_containers/glass/beaker/large(cell)
	cell.beaker.reagents.add_reagent(/datum/reagent/medicine/cryoxadone, 50)

/datum/bot_scenario/duty/clone_to_cryo/post_spawn()
	..()
	brain.nerve = 0.5
	bot.adjustCloneLoss(60)

/datum/bot_scenario/duty/clone_to_cryo/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot.loc == cell ? BOT_GYM_PASS : BOT_GYM_PENDING

/// An engineer at -0.3 climbed out of a sleeper two seconds after being given saline, to hold a traitor for Security, and suffocated.
/datum/bot_scenario/stays_in_sleeper
	name = "hurt: badly hurt in a sleeper, it stays put rather than getting up for a job"
	desc = "The bot lies in a sleeper at 30 health, with medicine in it. It's handed an errand (a toolbox across the room). It stays in the sleeper."
	job = "Station Engineer"
	layout = list(
		"#########",
		"#sB....T#",
		"#########")
	time_limit = 12 SECONDS
	var/obj/machinery/sleeper/sleeper

/datum/bot_scenario/stays_in_sleeper/setup()
	sleeper = new(first_marker("s"))
	place("s", sleeper)

/datum/bot_scenario/stays_in_sleeper/post_spawn()
	brain.nerve = 0.5
	bot.apply_damage(70, BRUTE, BODY_ZONE_CHEST)
	bot.reagents.add_reagent(/datum/reagent/medicine/bicaridine, 10)
	sleeper.close_machine(bot)

/datum/bot_scenario/stays_in_sleeper/make_goal()
	var/obj/item/storage/toolbox/T = locate() in first_marker("T")
	return T ? new /datum/bot_goal/take_item/exact(T) : null

/datum/bot_scenario/stays_in_sleeper/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.loc != sleeper)
		fail_reason = "got out of the sleeper at [round(bot.health)] health"
		return BOT_GYM_FAIL
	return world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING
