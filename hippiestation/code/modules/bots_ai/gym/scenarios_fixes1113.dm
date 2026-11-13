// Bot Gym: the user's playtest, 2026-11-13 (round-11.07.04). They were fighting the nanosuit traitor, smashed two windows chasing it, and
// lost the fight. Two officers cuffed them in crit for Vandalism and walked off; the keep-clear Security called for the nanosuit kept the
// doctor away; the crew walked past them saying "help".
//
// Layout letters used here: C the one lying there, M the arena's stand-in for Medbay's lobby, O a second officer.

/datum/bot_scenario/downed_vandal
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	time_limit = 40 SECONDS
	layout = list(
		"##############",
		"#B.O.C......M#",
		"#............#",
		"##############")
	var/mob/living/carbon/human/downed
	var/mob/living/carbon/human/other

/datum/bot_scenario/downed_vandal/make_goal()
	return null

/datum/bot_scenario/downed_vandal/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.register_security()
	downed = stand_in(first_marker("C"), "Mika Downed")
	downed.adjustBruteLoss(80) //sawn up, as the user was
	downed.adjustOxyLoss(max(downed.health + 1, 0)) //and into crit: the limbs cap what brute alone does; the user was at -1.2
	brain.file_crime(downed, "Vandalism", "Gym.", BOT_CRIME_MINOR)
	if("gym_medbay_spot" in brain.vars)
		brain.vars["gym_medbay_spot"] = first_marker("M")

/datum/bot_scenario/downed_vandal/release_run()
	bot_clear_wanted(downed)
	return ..()

/datum/bot_scenario/downed_vandal/proc/seen_to()
	return get_dist(downed, first_marker("M")) <= 1 || bot_transcript_said("needs a doctor") || bot_transcript_said("Medical,")

/// Two officers on the one cuffing, as in the round
/datum/bot_scenario/downed_vandal/two
	name = "brig: two officers cuff somebody lying in crit for a minor charge, and they don't leave them there"
	desc = "The user, at -1 health after losing to the nanosuit, was cuffed for Vandalism by two officers at once, and both said they were bringing them to the brig and walked off to other things. Somebody cuffed in crit goes to Medbay (security_medevac.dm), or Medical is called to them."

/datum/bot_scenario/downed_vandal/two/post_spawn()
	..()
	other = second_bot(first_marker("O"), "Officer Other")
	other.mind.assigned_role = "Security Officer"
	other.bot_brain.register_security()
	other.equip_to_slot_or_del(new /obj/item/restraints/handcuffs(other), ITEM_SLOT_BACKPACK)
	if("gym_medbay_spot" in other.bot_brain.vars)
		other.bot_brain.vars["gym_medbay_spot"] = first_marker("M")
	brain.begin_arrest(downed)
	other.bot_brain.begin_arrest(downed)

/datum/bot_scenario/downed_vandal/two/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return seen_to() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/downed_vandal/one
	name = "brig: an officer cuffs somebody lying in crit for a minor charge, and takes them to Medbay"
	desc = "The same with one officer."

/datum/bot_scenario/downed_vandal/one/post_spawn()
	..()
	brain.begin_arrest(downed)

/datum/bot_scenario/downed_vandal/one/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return seen_to() ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Into crit: brute as from a weapon, oxy for the rest (the limbs cap what brute alone does)
/proc/bot_gym_into_crit(mob/living/carbon/human/H)
	H.adjustBruteLoss(80)
	H.adjustOxyLoss(max(H.health + 1, 0))

// ---------------------------------------------------------------------------------------------
// Going back for a prisoner left lying (goals/security_custody.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/duty/loose_prisoner
	name = "brig: an officer goes back for somebody it cuffed and left lying in crit, and gets them to Medbay"
	desc = "The user's round: cuffed at -1 health, and both officers walked off on other errands (one fetching more cuffs: the escort was turned down while that was being weighed up, and never asked again). An officer remembers who it's cuffed, and goes back for them."
	job = "Security Officer"
	time_limit = 30 SECONDS
	layout = list(
		"##############",
		"#B...C......M#",
		"#............#",
		"##############")
	var/mob/living/carbon/human/downed

/datum/bot_scenario/duty/loose_prisoner/New()
	..()
	duty_type = text2path("/datum/bot_duty/loose_prisoner")

/datum/bot_scenario/duty/loose_prisoner/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.register_security()
	downed = stand_in(first_marker("C"), "Mika Downed")
	bot_gym_into_crit(downed)
	brain.file_crime(downed, "Vandalism", "Gym.", BOT_CRIME_MINOR)
	downed.handcuffed = new /obj/item/restraints/handcuffs(downed)
	downed.update_handcuffed()
	if("my_prisoners" in brain.vars)
		brain.vars["my_prisoners"] = list(WEAKREF(downed))
	if("gym_medbay_spot" in brain.vars)
		brain.vars["gym_medbay_spot"] = first_marker("M")

/datum/bot_scenario/duty/loose_prisoner/release_run()
	bot_clear_wanted(downed)
	return ..()

/datum/bot_scenario/duty/loose_prisoner/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return get_dist(downed, first_marker("M")) <= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/loose_prisoner/someone_elses
	name = "brig: an officer comes across somebody cuffed lying in crit, cuffed by somebody else, and gets them to Medbay"
	desc = "The same prisoner, cuffed by another officer who's gone: any officer who sees them lying there sees to them."

/datum/bot_scenario/duty/loose_prisoner/someone_elses/post_spawn()
	..()
	if("my_prisoners" in brain.vars)
		brain.vars["my_prisoners"] = null

// ---------------------------------------------------------------------------------------------
// Vandalism while fighting a nanosuit (bot_witness.dm bot_after_a_valid())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/suit_window
	job = "Assistant"
	time_limit = 8 SECONDS
	layout = list(
		"##############",
		"#B..v...w....#",
		"#.......k....#",
		"##############")
	var/with_suit = TRUE
	var/mob/living/carbon/human/vandal
	var/mob/living/carbon/human/suit
	var/smashed = 0

/datum/bot_scenario/suit_window/make_goal()
	return null

/datum/bot_scenario/suit_window/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	vandal = stand_in(first_marker("v"), "[with_suit ? "Fay Fighter" : "Pat Plain"] [run_index]") //the records go by name: one each
	if(with_suit)
		suit = stand_in(first_marker("k"), "Nano Nick")
		suit.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(suit), ITEM_SLOT_OCLOTHING)

/datum/bot_scenario/suit_window/release_run()
	bot_clear_wanted(vandal)
	return ..()

/datum/bot_scenario/suit_window/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/structure/window/W = locate() in first_marker("w")
	if(W && smashed < 3)
		smashed++
		bot_note_vandalism(vandal, W) //a swing at the window, as attackby() reports it
	if(with_suit && bot_transcript_said("called in Fay Fighter"))
		fail_reason = "called them in for the window"
		return BOT_GYM_FAIL
	if(!with_suit && bot_transcript_said("called in Pat Plain"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/suit_window/on_timeout()
	if(!with_suit)
		fail_reason = "never called in somebody smashing a window"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/suit_window/fighting
	name = "witness: somebody smashing a window with a nanosuit in front of them isn't called in for vandalism"
	desc = "The user chased a nanosuit and broke two windows getting at it, and was called in for Vandalism and arrested lying in crit. The crew fight a nanosuit by any means (the user's ruling, 2026-11-09): what breaks getting at one is the fight."

/datum/bot_scenario/suit_window/plain
	name = "witness: somebody smashing a window with no nanosuit about is called in, as ever"
	desc = "The same with no suit: it's vandalism."
	with_suit = FALSE

// ---------------------------------------------------------------------------------------------
// No minor arrests with a nanosuit loose (security_patrol.dm begin_arrest())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/minor_waits
	name = "security: with a nanosuit loose in the room, an officer leaves a vandal for later"
	desc = "Two officers came for the user lying in crit for Vandalism with a nanosuit in the room. The suit's the business; a broken window can wait."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	time_limit = 8 SECONDS
	layout = list(
		"##############",
		"#B..v......k.#",
		"##############")
	var/mob/living/carbon/human/vandal
	var/mob/living/carbon/human/suit

/datum/bot_scenario/minor_waits/make_goal()
	return null

/datum/bot_scenario/minor_waits/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.register_security()
	vandal = stand_in(first_marker("v"), "Mika Chaser")
	suit = stand_in(first_marker("k"), "Nano Nick")
	suit.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(suit), ITEM_SLOT_OCLOTHING)
	brain.file_crime(suit, "Murder", "Gym.", BOT_CRIME_MURDER)
	brain.file_crime(vandal, "Vandalism", "Gym.", BOT_CRIME_MINOR)
	brain.begin_arrest(vandal)

/datum/bot_scenario/minor_waits/release_run()
	bot_clear_wanted(vandal)
	bot_clear_wanted(suit)
	return ..()

/datum/bot_scenario/minor_waits/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(vandal.handcuffed || brain.arrest_suspect == vandal)
		fail_reason = "went to arrest the vandal with the suit right there"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/minor_waits/on_timeout()
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Keep-clear lifted once the suit's seen elsewhere (security_tactics.dm bot_told_to_keep_clear())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/keep_clear_moves
	name = "keep clear: a room kept clear for a nanosuit isn't once it's been seen somewhere else"
	desc = "The user lay in crit in a room Security had said to keep clear of for a nanosuit; the suit moved on and was seen two rooms away, and the doctor called to the user still wouldn't go in. Kept clear for the suit, the room stops being once it's been seen elsewhere since."
	job = "Assistant"
	time_limit = 5 SECONDS
	layout = list(
		"#######",
		"#B..k.#",
		"#######")
	var/mob/living/carbon/human/suit
	var/stage = 0

/datum/bot_scenario/keep_clear_moves/make_goal()
	return null

/datum/bot_scenario/keep_clear_moves/post_spawn()
	suit = stand_in(first_marker("k"), "Nano Nick")
	GLOB.bot_keep_clear[arena_area] = world.time + 2 MINUTES
	if("bot_keep_clear_for" in GLOB.vars)
		var/list/kept_for = GLOB.vars["bot_keep_clear_for"]
		kept_for[arena_area] = WEAKREF(suit)

/datum/bot_scenario/keep_clear_moves/release_run()
	GLOB.bot_keep_clear -= arena_area
	if("bot_keep_clear_for" in GLOB.vars)
		var/list/kept_for = GLOB.vars["bot_keep_clear_for"]
		var/list/sightings = GLOB.vars["bot_suit_sightings"]
		kept_for -= arena_area
		sightings -= REF(suit)
	return ..()

/datum/bot_scenario/keep_clear_moves/check()
	var/turf/T = first_marker("k")
	if(stage == 0)
		if(!bot_told_to_keep_clear(T))
			fail_reason = "not kept clear to begin with"
			return BOT_GYM_FAIL
		stage = 1
		var/area/elsewhere = locate(/area/hallway/primary/central) in GLOB.sortedAreas
		if("bot_suit_sightings" in GLOB.vars)
			var/list/sightings = GLOB.vars["bot_suit_sightings"]
			sightings[REF(suit)] = list(elsewhere || GLOB.areas_by_type[/area/space], world.time)
		return BOT_GYM_PENDING
	if(bot_told_to_keep_clear(T))
		fail_reason = "still kept clear with the suit seen somewhere else"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Help, from somebody down (goals/carry_casualty.dm heard_cry_for_help())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/cry_for_help
	name = "aid: somebody lying in crit asks a crewman for help, and is taken to Medbay"
	desc = "The user, cuffed and in crit, said help to three bots in maintenance, and they walked on. Somebody down asking for help gets taken to Medbay's door by whoever's free."
	job = "Assistant"
	time_limit = 30 SECONDS
	layout = list(
		"##############",
		"#B.C........M#",
		"#............#",
		"##############")
	var/mob/living/carbon/human/downed
	var/said = FALSE

/datum/bot_scenario/cry_for_help/make_goal()
	return null

/datum/bot_scenario/cry_for_help/post_spawn()
	downed = stand_in(first_marker("C"), "Mika Downed")
	bot_gym_into_crit(downed)
	if("gym_medbay_spot" in brain.vars)
		brain.vars["gym_medbay_spot"] = first_marker("M")

/datum/bot_scenario/cry_for_help/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!said)
		said = TRUE
		log_line("Mika Downed says help (stat [downed.stat], health [downed.health])")
		downed.say("help")
		return BOT_GYM_PENDING
	return get_dist(downed, first_marker("M")) <= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// The radio as it is (bot_radio.dm)
// ---------------------------------------------------------------------------------------------

/// A crewman sees somebody smashing a window and calls it in. O is an officer walled off where it can't see, brought over later.
/datum/bot_scenario/radio_call
	job = "Assistant"
	time_limit = 20 SECONDS
	layout = list(
		"##############",
		"#B..v......w.#",
		"#............#",
		"##############",
		"#O############",
		"##############")
	var/radio_down = TRUE
	var/mob/living/carbon/human/vandal
	var/mob/living/carbon/human/officer
	var/smashed = 0
	var/called_at = 0
	var/officer_came = FALSE

/datum/bot_scenario/radio_call/setup()
	if("radio_down" in arena_area.vars)
		arena_area.vars["radio_down"] = radio_down

/datum/bot_scenario/radio_call/make_goal()
	return null

/datum/bot_scenario/radio_call/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	vandal = stand_in(first_marker("v"), "Mika Chaser [run_index]") //its own name: the same call from another run's arena is kept back as a repeat
	officer = second_bot(first_marker("O"), "Officer Oakes")
	officer.mind.assigned_role = "Security Officer"
	officer.bot_brain.register_security()

/datum/bot_scenario/radio_call/release_run()
	bot_clear_wanted(vandal)
	return ..()

/datum/bot_scenario/radio_call/proc/smash()
	var/obj/structure/window/W = locate() in first_marker("w")
	if(W && smashed < 3)
		smashed++
		bot_note_vandalism(vandal, W) //a swing at the window, as attackby() reports it
	if(!called_at && bot_transcript_said("called in Mika Chaser"))
		called_at = world.time

/datum/bot_scenario/radio_call/down
	name = "radio: with telecomms down, a crewman's call about somebody smashing the place up puts nothing on the record, till it tells an officer to their face"
	desc = "The user wrecked Telecomms and not one crew bot's radio line got out after, but a crewman's call about their window-smashing still went on their record and two officers arrested them for it. Now the call does what it does only if it gets out; failing that, the next officer close enough to talk to is told."

/datum/bot_scenario/radio_call/down/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	smash()
	if(!called_at)
		return BOT_GYM_PENDING
	if(world.time < called_at + 4 SECONDS)
		if(bot_get_wanted_entry(vandal))
			fail_reason = "on the record from a radio call that never got out"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	if(!officer_came)
		officer_came = TRUE
		log_line("the officer comes over")
		var/turf/T = get_step(bot, EAST)
		officer.forceMove(T && !T.density ? T : get_step(bot, SOUTH))
		return BOT_GYM_PENDING
	return bot_get_wanted_entry(vandal) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/radio_call/up
	name = "radio: with telecomms working, the same call puts them on the record"
	desc = "The same with the radio up: on the record from the call."
	radio_down = FALSE
	time_limit = 10 SECONDS

/datum/bot_scenario/radio_call/up/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	smash()
	return bot_get_wanted_entry(vandal) ? BOT_GYM_PASS : BOT_GYM_PENDING
