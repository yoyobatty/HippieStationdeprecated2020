// Bot Gym scenarios for the robust playstyle and what the crew does about it (goals/robust.dm).

/datum/bot_scenario/duty/traitor/robust_shop
	name = "robust: the uplink goes on a nanosuit, and the bag and ID go back on after"
	desc = "Everything comes off when a nanosuit goes on. A player has their bag, belt and PDA back on within seconds, and so does this."
	time_limit = 60 SECONDS
	layout = list(
		"#####",
		"#B..#",
		"#####")

/datum/bot_scenario/duty/traitor/robust_shop/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_ROBUST)

/datum/bot_scenario/duty/traitor/robust_shop/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/clothing/suit/space/hardsuit/nano/N = brain.nanosuit_on()
	if(!N || !brain.traitor_shopped || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(!bot.wear_id)
		fail_reason = "left its ID on the floor"
		return BOT_GYM_FAIL
	return bot.back ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/robust_kill
	name = "robust: jumps the gap in strength mode and doesn't wait for the room to clear"
	desc = "A suited traitor and somebody it's been told to kill, with a third person watching. It goes straight for them, in the open, and it uses the jump."
	time_limit = 60 SECONDS
	layout = list(
		"###########",
		"#B.......V#",
		"#.......W.#",
		"###########")
	var/mob/living/carbon/human/victim
	var/mob/living/carbon/human/onlooker

/datum/bot_scenario/duty/traitor/robust_kill/setup()
	for(var/turf/T in markers["V"])
		victim = new(T)
		place("V", victim)
		victim.equipOutfit(/datum/outfit/bot_gym)
	for(var/turf/T in markers["W"])
		onlooker = new(T)
		place("W", onlooker)
		onlooker.equipOutfit(/datum/outfit/bot_gym)

/datum/bot_scenario/duty/traitor/robust_kill/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_ROBUST)
	brain.traitor_shopped = TRUE
	set_kill_objective(victim)
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(bot.loc)
	brain.being_issued_kit = TRUE
	bot.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	brain.being_issued_kit = FALSE
	N.shutdown = FALSE //the boot takes half a minute, and that isn't what this is about
	N.toggle_mode("strength", TRUE)

/datum/bot_scenario/duty/traitor/robust_kill/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(victim.stat != DEAD)
		return BOT_GYM_PENDING
	if(!brain.suit_jumps)
		fail_reason = "killed them, but walked the whole way"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/stand_in
	name = "with the heads all dead, a crewman takes an ID off a body and calls the shuttle"
	desc = "The console only takes a head's ID, and the only one left is on the Captain's corpse. The shift's over either way: somebody has to do it."
	duty_type = /datum/bot_duty/stand_in_for_command
	job = "Assistant"
	time_limit = 60 SECONDS
	layout = list(
		"##########",
		"#B..H...K#",
		"##########")
	var/mob/living/carbon/human/body

/datum/bot_scenario/duty/stand_in/setup()
	GLOB.bot_shift_ends_at = world.time
	for(var/turf/T in markers["K"])
		place("K", new /obj/machinery/computer/communications(T))
	for(var/turf/T in markers["H"])
		body = new(T)
		place("H", body)
		body.equipOutfit(/datum/outfit/bot_gym)
		var/obj/item/card/id/C = new(T)
		C.access = list(ACCESS_HEADS)
		body.equip_to_slot_if_possible(C, ITEM_SLOT_ID, FALSE, TRUE, TRUE)
		body.status_flags |= GODMODE
		body.death()

/datum/bot_scenario/duty/stand_in/post_spawn()
	..()
	give_job_id(list())

/datum/bot_scenario/duty/stand_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.shuttle_calls)
		return BOT_GYM_PENDING
	return brain.state == BOT_STATE_WANDER ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/confession
	name = "somebody saying they're the traitor gets taken at their word"
	desc = "In a played round a traitor told the bots to their faces, twice, and said they'd killed the Captain. Nobody batted an eye."
	griefer_job = "Assistant"
	time_limit = 10 SECONDS
	layout = list(
		"#########",
		"#..B.C..#",
		"#########")

/datum/bot_scenario/griefed/confession/grief()
	griefer.say("I'm traitor")

/datum/bot_scenario/griefed/confession/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_get_wanted_entry(griefer) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/confession/release_run()
	bot_clear_wanted(griefer)
	return ..()

/// A suited traitor, on a floor with somebody else, for what it says and who it'll go for.
/datum/bot_scenario/griefed/bug/exposed
	griefer_job = "Assistant"

/datum/bot_scenario/griefed/bug/exposed/proc/suit_up()
	brain.become_traitor()
	brain.set_playstyle(BOT_STYLE_ROBUST)
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(bot.loc)
	brain.being_issued_kit = TRUE
	bot.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	brain.being_issued_kit = FALSE

/datum/bot_scenario/griefed/bug/exposed/drops_the_act
	name = "exposed traitor: no crying for Security in a Syndicate suit"
	desc = "Everything an innocent bot says when it's attacked goes through one proc. Once the whole station knows, a threat comes out instead."

/datum/bot_scenario/griefed/bug/exposed/drops_the_act/grief()
	if(brain.gone_loud())
		expect(FALSE, "not exposed yet")
		return
	suit_up()
	if(!brain.gone_loud())
		expect(FALSE, "exposed once it's got the suit on")
		return
	bot_say(bot, ";Security! [griefer.name] is attacking me!")
	expect(brain.threats_made == 1, "said something hostile instead")

/datum/bot_scenario/griefed/bug/exposed/truce
	name = "exposed traitors: a truce keeps two of them off each other, and the first blow ends it"
	desc = "Usually there's no trust between traitors. When there is, it's staying out of each other's way, and it doesn't survive being hit."

/datum/bot_scenario/griefed/bug/exposed/truce/grief()
	suit_up()
	griefer.mind_initialize()
	griefer.mind.assigned_role = "Assistant"
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(griefer.loc)
	griefer.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	GLOB.bot_traitor_pacts[bot_pact_key(bot, griefer)] = 1
	if(brain.next_victim(null) == griefer)
		expect(FALSE, "left alone under a truce")
		return
	log_line("left alone under a truce: yes")
	brain.break_pact_with(griefer)
	expect(brain.next_victim(null) == griefer, "fair game once it's broken")

/datum/bot_scenario/griefed/bug/exposed/codewords
	name = "traitors: the code words make a team, a player's as well as a bot's"
	desc = "Rare, and only for the odd traitor who'd try them. Somebody says the phrase, it answers with the response, and that's a team."

/datum/bot_scenario/griefed/bug/exposed/codewords/grief()
	brain.become_traitor()
	brain.uses_codewords = TRUE
	if(!GLOB.syndicate_code_phrase)
		GLOB.syndicate_code_phrase = list("gym phrase")
		GLOB.syndicate_code_response = list("gym response")
	griefer.mind_initialize()
	griefer.say("[GLOB.syndicate_code_phrase[1]]")
	sleep(5)
	if(GLOB.bot_traitor_pacts[bot_pact_key(bot, griefer)])
		expect(FALSE, "a crewman who says the word by accident means nothing")
		return
	log_line("a crewman who says the word by accident means nothing: yes")
	griefer.mind.add_antag_datum(/datum/antagonist/traitor)
	griefer.say("[GLOB.syndicate_code_phrase[1]]")
	sleep(5)
	expect(GLOB.bot_traitor_pacts[bot_pact_key(bot, griefer)] == 2, "a traitor who says it makes a team")

/datum/bot_scenario/griefed/bug/exposed/caught
	name = "undercover traitor: caught, it turns on them"
	desc = "Half of them never buy the suit. Nobody's any the wiser until Security wants them for something serious, and then the act's over."

/datum/bot_scenario/griefed/bug/exposed/caught/grief()
	brain.become_traitor()
	brain.traitor_plan = BOT_TRAITOR_UNDERCOVER
	if(brain.gone_loud())
		expect(FALSE, "still undercover")
		return
	brain.file_crime(bot, "Murder", "Gym.", BOT_CRIME_MAJOR)
	if(!brain.gone_loud())
		expect(FALSE, "exposed once it's wanted")
		return
	brain.turn_hostile()
	bot_clear_wanted(bot)
	expect(brain.plays_robust() && brain.traitor_plan == BOT_TRAITOR_HIT_LIST && brain.threats_made == 1, "turned hostile")
