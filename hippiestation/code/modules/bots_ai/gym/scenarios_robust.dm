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
	if(!brain.plays_robust() || brain.traitor_plan != BOT_TRAITOR_CORNERED || brain.threats_made != 1)
		expect(FALSE, "turned hostile, on whoever comes for it")
		return
	brain.traitor_plan = BOT_TRAITOR_UNDERCOVER
	brain.temper = 0.9
	brain.turn_hostile()
	expect(brain.traitor_plan == BOT_TRAITOR_HIT_LIST, "turned hostile on whoever comes for it, and a hothead on Security and the heads too")

/datum/bot_scenario/griefed/bug/exposed/quiet_plans
	name = "traitor plans: most stay quiet, and the hotheads and the robust go loud from the start"
	desc = "The user's ruling: most traitors do their objectives by stealth. An even-tempered one plans to stay undercover, a hothead or a robust player plans to go loud."

/datum/bot_scenario/griefed/bug/exposed/quiet_plans/grief()
	brain.become_traitor()
	brain.set_playstyle(BOT_STYLE_NORMAL)
	var/list/wrong = list()
	brain.temper = 0.5
	brain.pick_traitor_plan()
	if(brain.traitor_plan != BOT_TRAITOR_UNDERCOVER)
		wrong += "an even-tempered traitor went loud"
	brain.temper = 0.9
	brain.pick_traitor_plan()
	if(brain.traitor_plan == BOT_TRAITOR_UNDERCOVER)
		wrong += "a hothead stayed undercover"
	brain.temper = 0.5
	brain.set_playstyle(BOT_STYLE_ROBUST)
	brain.pick_traitor_plan()
	if(brain.traitor_plan == BOT_TRAITOR_UNDERCOVER)
		wrong += "a robust player stayed undercover"
	expect(!length(wrong), length(wrong) ? jointext(wrong, "; ") : "even-tempered undercover, hothead and robust loud")

/// A suited suspect stood still, and one officer: what matters here is how it goes about it.
/datum/bot_scenario/griefed/officer
	job = "Security Officer"
	griefer_job = "Assistant"
	time_limit = 90 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded, /obj/item/gun/energy/e_gun/advtaser)
	layout = list(
		"###########",
		"#B.......C#",
		"###########")

/datum/bot_scenario/griefed/officer/grief()
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(griefer.loc)
	griefer.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	brain.file_crime(griefer, "Murder", "Gym.", BOT_CRIME_MURDER)
	brain.begin_arrest(griefer)

/datum/bot_scenario/griefed/officer/release_run()
	bot_clear_wanted(griefer)
	return ..()

/datum/bot_scenario/griefed/officer/range
	name = "security: a nanosuit gets shot from range by three officers and cuffed once it's down, not rushed"
	desc = "Seven to ten hits stam-crit even a suit. Three officers together stop short, call it in and keep shooting, and only walk up once they're on the floor."
	layout = list(
		"###########",
		"#B.......C#",
		"#O........#",
		"#P........#",
		"###########")
	var/closest_while_up = 99

/datum/bot_scenario/griefed/officer/range/grief()
	..()
	for(var/marker in list("O", "P"))
		var/mob/living/carbon/human/H = second_bot(first_marker(marker), "Officer [marker]")
		H.mind.assigned_role = "Security Officer"
		H.bot_brain.register_security()
		H.put_in_hands(new /obj/item/gun/energy/e_gun/advtaser(H))
		H.put_in_hands(new /obj/item/restraints/handcuffs(H))
		H.bot_brain.begin_arrest(griefer)

/datum/bot_scenario/griefed/officer/alone
	name = "security: one officer on its own against a nanosuit holds back and waits for two more"
	desc = "The user's ruling: gather first and go in together. On its own it keeps out of reach, fires nothing to draw the suit, and calls the others to it. One at a time, officers walked into reach and died one after another."
	time_limit = 15 SECONDS
	layout = list(
		"##################",
		"#B..............C#",
		"##################")
	var/closest = 99

/datum/bot_scenario/griefed/officer/alone/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	closest = min(closest, get_dist(bot, griefer))
	if(bot_transcript_said("firing"))
		fail_reason = "fired at the suit on its own"
		return BOT_GYM_FAIL
	if(closest < 6)
		fail_reason = "went within [closest] tiles of the suit on its own"
		return BOT_GYM_FAIL
	return (world.time > start_time + 10 SECONDS && bot_transcript_said("holding back from")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/range/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(griefer.handcuffed)
		if(!bot_transcript_said("firing"))
			fail_reason = "cuffed them without a shot"
			return BOT_GYM_FAIL
		if(closest_while_up < 2)
			fail_reason = "walked into arm's reach while they were up"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	if(!brain.is_subdued(griefer))
		closest_while_up = min(closest_while_up, get_dist(bot, griefer))
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/falls_back
	name = "security: an officer who's badly hurt falls back from a nanosuit"
	desc = "It used to stand there with a baton until it died."
	time_limit = 30 SECONDS

/datum/bot_scenario/griefed/officer/falls_back/grief()
	..()
	bot.adjustBruteLoss(80)

/datum/bot_scenario/griefed/officer/falls_back/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("falling back from") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/surgeon
	name = "surgery: with no sleeper, a doctor gets the tools, tables the patient and tends the wounds"
	desc = "Somebody out cold and badly hurt, no sleeper in the room, and an operating table. The tools are on the floor. It collects them, drags the patient over, and works through the procedure with the right tool at each step."
	job = "Medical Doctor"
	griefer_job = "Assistant"
	griefer_name = "Pat Patient"
	time_limit = 120 SECONDS
	layout = list(
		"###########",
		"#Bs.r.h.c.#",
		"#...C...T.#",
		"###########")

/datum/bot_scenario/griefed/surgeon/setup()
	for(var/turf/T in markers["s"])
		place("s", new /obj/item/scalpel(T))
	for(var/turf/T in markers["r"])
		place("r", new /obj/item/retractor(T))
	for(var/turf/T in markers["h"])
		place("h", new /obj/item/hemostat(T))
	for(var/turf/T in markers["c"])
		place("c", new /obj/item/cautery(T))
	for(var/turf/T in markers["T"])
		place("T", new /obj/structure/table/optable(T))

/datum/bot_scenario/griefed/surgeon/grief()
	griefer.adjustBruteLoss(90)
	griefer.Unconscious(180 SECONDS)
	brain.assign_goal(new /datum/bot_goal/operate())

/datum/bot_scenario/griefed/surgeon/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(griefer.stat == DEAD)
		fail_reason = "the patient died"
		return BOT_GYM_FAIL
	if(griefer.getBruteLoss() < 15 && bot_transcript_said("finished operating"))
		return (locate(/obj/structure/table/optable) in griefer.loc) ? BOT_GYM_PASS : BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/bug/exposed/suit_shuttle
	name = "security: a suit at large and four of the crew dead is reason to call the shuttle early"
	desc = "The user's ruling: with a nanosuit nobody's stopped and several dead, the Captain or acting captain calls the shuttle. Not for the suit alone, and not for the dead alone."

/datum/bot_scenario/griefed/bug/exposed/suit_shuttle/grief()
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(griefer.loc)
	griefer.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	brain.file_crime(griefer, "Murder", "Gym.", BOT_CRIME_MURDER)
	GLOB.bot_dead_crew_counted_at = world.time + 1 MINUTES //the count's set by hand here: other arenas' bodies don't come into it
	GLOB.bot_dead_crew = 0
	var/before = bot_unstoppable_suit()
	GLOB.bot_dead_crew = 4
	var/after = bot_unstoppable_suit()
	GLOB.bot_dead_crew_counted_at = 0
	bot_clear_wanted(griefer)
	expect(!before && after, "not for the suit alone ([before]), and for the suit with four dead ([after])")

/datum/bot_scenario/griefed/officer/range/emp
	name = "security: the Warden, with the others there, throws an EMP grenade at a nanosuit from range"
	desc = "An EMP drains the suit. With three of them together, the Warden throws the armory's EMP grenade from range, not with a colleague next to the suit."
	job = "Warden"
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/grenade/empgrenade, /obj/item/gun/energy/e_gun/advtaser)

/datum/bot_scenario/griefed/officer/range/emp/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("EMP grenade at") ? BOT_GYM_PASS : BOT_GYM_PENDING
