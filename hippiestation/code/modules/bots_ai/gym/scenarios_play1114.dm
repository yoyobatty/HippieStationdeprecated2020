// Bot Gym scenarios from the user's Captain round of 2026-11-14 (round-01.12.53): a body Security walked away from, and a lost ID nobody
// replaced.

// ---------------------------------------------------------------------------------------------
// A body found by an officer with something else on (bot_playstyles.dm see_to_body())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/body_found/officer_busy
	name = "bodies: an officer on an errand who comes across a body brings it to Medbay"
	desc = "A Security Officer walking somewhere comes across a body. A body's Security's business: it puts the errand off and drags the body to Medbay's door. The Warden found the user's Captain dead in the Brig, said so on the radio, and went back to shutting the armory shutters (round-01.12.53)."
	job = "Security Officer"
	layout = list(
		"############",
		"#B..K.....G#",
		"#M.........#",
		"############")

/datum/bot_scenario/body_found/officer_busy/make_goal()
	var/datum/bot_goal/gym_reach/G = new
	G.target = first_marker("G")
	return G

/datum/bot_scenario/body_found/officer_busy/post_spawn()
	..()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.register_security()
	brain.diligence = 0 //not the conscientious sort: it's the job that makes it see to the body
	if("body_carry_bias" in brain.vars)
		brain.vars["body_carry_bias"] = 0

/datum/bot_scenario/body_found/officer_busy/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(get_dist(bot, body) <= 4)
		brain.look_round_the_room() //what keep_an_eye_out() does every few seconds off the gym, on an errand or not (bot_witness.dm)
	if(get_dist(body, first_marker("M")) > 1 || bot.pulling == body)
		if(get_dist(bot, first_marker("G")) <= 1 && bot.pulling != body)
			fail_reason = "walked past the body to where it was going"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// A new ID (bot_hopping.dm consider_new_id())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/hop_new_id
	name = "asks: somebody who's lost their ID asks the HoP, and gets a new card in their name and job"
	desc = "The Captain, with no ID, asks the HoP for a new one. The HoP knows the face against the manifest, takes a blank from the box of spare IDs, makes it out at the ID console in the Captain's name with the Captain's access, and brings it over. The user's Captain lost his card to a blast and asked the HoP five times; the HoP did EVA access and told him he shouldn't be in the office (round-01.12.53)."
	job = "Head of Personnel"
	time_limit = 60 SECONDS
	layout = list(
		"##########",
		"#B.....I.#",
		"#..C...X.#",
		"##########")
	var/datum/data/record/manifest_entry

/datum/bot_scenario/chat/hop_new_id/setup()
	place("I", new /obj/machinery/computer/card(first_marker("I")))
	place("X", new /obj/item/storage/box/ids(first_marker("X")))

/datum/bot_scenario/chat/hop_new_id/post_spawn()
	..()
	give_job_id(list(ACCESS_CHANGE_IDS, ACCESS_HEADS, ACCESS_HOP))
	brain.gym_scripted = FALSE //its duties run, as they would at its desk
	visitor.real_name = "Hollis Lostcard"
	visitor.name = visitor.real_name
	var/obj/item/card/id/worn = visitor.get_idcard(FALSE)
	if(worn)
		qdel(worn)
	manifest_entry = new
	manifest_entry.fields["name"] = visitor.real_name
	manifest_entry.fields["rank"] = "Captain"
	GLOB.data_core.general += manifest_entry
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "HOP, I lost my ID, I need a new one. I'm the captain"), 2 SECONDS)

/datum/bot_scenario/chat/hop_new_id/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/card/id/card in range(1, visitor))
		if(card.registered_name != visitor.real_name)
			continue
		if(card.assignment != "Captain" || !(ACCESS_CAPTAIN in card.access))
			fail_reason = "made the card out as [card.assignment], [length(card.access)] accesses"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	for(var/obj/item/card/id/card in visitor.GetAllContents())
		if(card.registered_name == visitor.real_name)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/hop_new_id/on_timeout()
	fail_reason = "no card for them: [length(spoken()) ? "said [jointext(spoken(), " / ")]" : "said nothing"]"
	return BOT_GYM_FAIL

/datum/bot_scenario/chat/hop_new_id/release_run()
	if(manifest_entry)
		GLOB.data_core.general -= manifest_entry
		manifest_entry = null
	..()
