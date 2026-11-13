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
	brain.traitor_plan = BOT_TRAITOR_RAMPAGE //a rampage is done in a suit; a hit list isn't (below)

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

/// The user's ruling (2026-11-10): hit-list traitors buy stealth gear. All three traitors in their Captain round were in suits.
/datum/bot_scenario/duty/traitor/hit_list_shop
	name = "robust: a traitor with a hit list buys an emag and a pistol, not a nanosuit"
	desc = "A robust traitor on the hit-list plan goes shopping. It comes away with an emag and a pistol, and no nanosuit."
	time_limit = 40 SECONDS
	layout = list(
		"#####",
		"#B..#",
		"#####")

/datum/bot_scenario/duty/traitor/hit_list_shop/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_ROBUST)
	brain.traitor_plan = BOT_TRAITOR_HIT_LIST

/datum/bot_scenario/duty/traitor/hit_list_shop/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.nanosuit_on() || brain.find_carried_tool(/obj/item/storage/box/syndie_kit/nanosuit))
		fail_reason = "bought a nanosuit"
		return BOT_GYM_FAIL
	if(!brain.traitor_shopped)
		return BOT_GYM_PENDING
	return (brain.find_carried_tool(/obj/item/card/emag) && brain.find_carried_tool(/obj/item/gun/ballistic/automatic/pistol)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/robust_nowhere_quiet
	name = "robust: with nowhere quiet to get to, it doesn't ask again every tick"
	desc = "Shift base1108n: a suited traitor shut in the Armory had no way out to the maintenance tunnels, and looked for somewhere to lay low four times a second for minutes on end, stood still. It gets on with something else and looks again later."
	time_limit = 30 SECONDS
	layout = list(
		"######",
		"#B...#",
		"######")

/datum/bot_scenario/duty/traitor/robust_nowhere_quiet/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_ROBUST)
	brain.traitor_shopped = TRUE

/datum/bot_scenario/duty/traitor/robust_nowhere_quiet/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/asked = 0
	for(var/line in transcript)
		if(findtext(line, "couldn't find a target for /datum/bot_goal/lay_low"))
			asked++
	if(asked > 3)
		fail_reason = "looked for somewhere to lay low [asked] times in [DisplayTimeText(world.time - start_time)]"
		return BOT_GYM_FAIL
	return world.time > start_time + 20 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

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

/// round-20.48.49: the Captain killed twenty of the crew, the heads among them, and the three left alive (a bartender, a cargo tech and
/// an assistant) went about their shift for the last ten minutes with no shuttle called. Here the same on its own: the Captain alive and
/// wanted for murder (shut in a cupboard, out of the way), five of the crew dead, the Head of Security among them with his ID on, a comms
/// console, and a bartender left to it, with nothing scripted: its own duties, on their own time.
/datum/bot_scenario/griefed/rogue_captain_stand_in
	name = "rogue Captain: with the heads dead and a third of the crew, a crewman takes a head's ID and calls the shuttle"
	job = "Bartender"
	griefer_job = "Captain"
	griefer_name = "Mika Roguecap"
	time_limit = 180 SECONDS
	station_wide = TRUE //"a third of the crew dead" counts every human on the server, and the shift's end is everybody's
	layout = list(
		"#############",
		"#B..H.AAAA.K#",
		"#############",
		"#C###########",
		"#############")
	var/old_shift_end
	var/last_said

/datum/bot_scenario/griefed/rogue_captain_stand_in/setup()
	for(var/turf/T in markers["K"])
		place("K", new /obj/machinery/computer/communications(T))
	var/list/dead = list()
	for(var/turf/T in markers["H"])
		var/mob/living/carbon/human/hos = new(T)
		hos.equipOutfit(/datum/outfit/bot_gym)
		hos.mind_initialize()
		hos.mind.assigned_role = "Head of Security"
		var/obj/item/card/id/C = new(T)
		C.access = list(ACCESS_HEADS)
		hos.equip_to_slot_if_possible(C, ITEM_SLOT_ID, FALSE, TRUE, TRUE)
		dead += hos
	for(var/turf/T in markers["A"])
		var/mob/living/carbon/human/H = new(T)
		H.equipOutfit(/datum/outfit/bot_gym)
		H.mind_initialize()
		H.mind.assigned_role = "Assistant"
		dead += H
	for(var/mob/living/carbon/human/H as anything in dead)
		place("A", H)
		H.status_flags |= GODMODE
		H.death()

/datum/bot_scenario/griefed/rogue_captain_stand_in/post_spawn()
	..()
	give_job_id(list())
	brain.gym_scripted = FALSE //its own duties, as in a round
	// Not the gym's "never": a shift end far off, so only the dead can be the reason
	old_shift_end = GLOB.bot_shift_ends_at
	GLOB.bot_shift_ends_at = world.time + 1 HOURS

/datum/bot_scenario/griefed/rogue_captain_stand_in/grief()
	var/datum/bot_wanted/W = new
	W.crime = "Murder"
	W.severity = BOT_CRIME_MURDER
	W.time_reported = world.time
	W.kill_on_sight = TRUE
	GLOB.bot_security_wanted[WEAKREF(griefer)] = W

/datum/bot_scenario/griefed/rogue_captain_stand_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/atom/card = brain.find_head_card()
	var/said = "state=[brain.state] goal=[brain.current_goal?.type] up_to_no_good=[brain.up_to_no_good()] reason=[brain.reason_to_call_shuttle()] head_standing=[brain.head_still_standing()] card=[card] loud=[brain.gone_loud()]"
	if(said != last_said)
		last_said = said
		log_line(said)
	if(brain.shuttle_calls || istype(brain.current_goal, /datum/bot_goal/borrow_head_card) || istype(brain.current_goal, /datum/bot_goal/call_shuttle))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/rogue_captain_stand_in/release_run()
	GLOB.bot_shift_ends_at = old_shift_end
	bot_clear_wanted(griefer)
	return ..()

/// round-20.48.49: a third of the crew dead, and the Head of Personnel ate some carrot fries, did a cargo round and swapped jokes for
/// three minutes before the Captain got to him, with the shuttle never called. Here a head on a long errand with five of the crew lying
/// dead: it drops the errand for the comms console, which is right beside where it starts.
/datum/bot_scenario/griefed/head_drops_errand_for_shuttle
	name = "a third of the crew dead: a head on an errand drops it to call the shuttle"
	job = "Head of Personnel"
	time_limit = 90 SECONDS
	station_wide = TRUE //"a third of the crew dead" counts every human on the server, and the shift's end is everybody's
	layout = list(
		"##################################################################",
		"##K###############################################################",
		"#B...AAAAA.....................................................Q.#",
		"##################################################################",
		"#C################################################################",
		"##################################################################")
	var/old_shift_end
	var/datum/bot_goal/walk_up_to/errand

/datum/bot_scenario/griefed/head_drops_errand_for_shuttle/setup()
	for(var/turf/T in markers["K"])
		place("K", new /obj/machinery/computer/communications(T))
	for(var/turf/T in markers["A"])
		var/mob/living/carbon/human/H = new(T)
		H.equipOutfit(/datum/outfit/bot_gym)
		H.mind_initialize()
		H.mind.assigned_role = "Assistant"
		place("A", H)
		H.status_flags |= GODMODE
		H.death()

/datum/bot_scenario/griefed/head_drops_errand_for_shuttle/post_spawn()
	..()
	give_job_id(list(ACCESS_HEADS))
	brain.gym_scripted = FALSE
	old_shift_end = GLOB.bot_shift_ends_at
	GLOB.bot_shift_ends_at = world.time + 1 HOURS //not the gym's "never": only the dead can be the reason

/datum/bot_scenario/griefed/head_drops_errand_for_shuttle/grief()
	brain.drop_goals("gym")
	brain.state = BOT_STATE_WANDER
	errand = new(first_marker("Q"))
	brain.assign_goal(errand)
	log_line("sent to the far end: [brain.current_goal == errand ? "yes" : "no ([brain.current_goal?.type])"]")
	brain.my_duties(BOT_DUTY_URGENT)
	brain.duty_next_check[bot_duty_of(/datum/bot_duty/call_shuttle)] = world.time //due now: whether it waits for the errand is the test

/datum/bot_scenario/griefed/head_drops_errand_for_shuttle/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!errand)
		return BOT_GYM_PENDING
	if(istype(brain.current_goal, /datum/bot_goal/call_shuttle) || brain.shuttle_calls)
		var/far = get_dist(bot, first_marker("Q"))
		log_line("calling the shuttle [far] tiles from the errand's end")
		if(far <= 2)
			fail_reason = "walked the errand out first"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/head_drops_errand_for_shuttle/release_run()
	GLOB.bot_shift_ends_at = old_shift_end
	return ..()

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
	var/datum/antagonist/traitor/T = bot.mind.has_antag_datum(/datum/antagonist/traitor)
	T?.objectives.Cut() //the game's random ones can want it loud (hijack, a glorious death, the Captain), which is another test
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

/datum/bot_scenario/griefed/officer/pair_waits
	name = "security: two officers waiting on a nanosuit stand their ground instead of pacing"
	desc = "Shift base1108n: an officer waiting for backup on a traitor in a nanosuit paced the same three tiles of a crowded Brig corridor for sixteen minutes, matching the suit's distance to the tile every time it shifted a step inside the Armory. Out of reach is a band, not a line: they should only move when it really comes at them or gets away."
	time_limit = 40 SECONDS
	layout = list(
		"####################",
		"#B.................#",
		"#O.......YZ......C.#",
		"#..................#",
		"####################")
	var/mob/living/carbon/human/partner
	var/moves = 0
	var/closest = 99

/datum/bot_scenario/griefed/officer/pair_waits/grief()
	..()
	partner = second_bot(first_marker("O"), "Officer O")
	partner.mind.assigned_role = "Security Officer"
	partner.bot_brain.register_security()
	partner.put_in_hands(new /obj/item/gun/energy/e_gun/advtaser(partner))
	partner.put_in_hands(new /obj/item/restraints/handcuffs(partner))
	partner.bot_brain.begin_arrest(griefer)
	stand_in(first_marker("Y"), "Bystander Y")
	stand_in(first_marker("Z"), "Bystander Z")
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	RegisterSignal(partner, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	keep_at_it("shift_about", 1 SECONDS)

/// The suit shifts a tile towards them and back, in plain sight, as Kit Brannigan did in the Armory
/datum/bot_scenario/griefed/officer/pair_waits/proc/shift_about()
	var/turf/C = first_marker("C")
	var/turf/T = (griefer.x >= C.x) ? locate(C.x - 1, C.y, C.z) : C
	if(T && !T.density)
		griefer.forceMove(T)
	return TRUE

/// Steps either officer takes once they've had ten seconds to get into place
/datum/bot_scenario/griefed/officer/pair_waits/proc/stepped(atom/movable/mover)
	SIGNAL_HANDLER
	if(world.time > start_time + 12 SECONDS)
		moves++

/datum/bot_scenario/griefed/officer/pair_waits/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!partner)
		return BOT_GYM_PENDING
	if(QDELETED(partner))
		return BOT_GYM_FAIL
	closest = min(closest, get_dist(bot, griefer), get_dist(partner, griefer))
	if(closest < 4)
		fail_reason = "an officer went within [closest] tiles of the suit with only two of them"
		return BOT_GYM_FAIL
	if(moves > 4)
		fail_reason = "the two of them paced while waiting: [moves] steps after getting into place"
		return BOT_GYM_FAIL
	return world.time > start_time + 32 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/pair_waits/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(partner)
		UnregisterSignal(partner, COMSIG_MOVABLE_MOVED)
	return ..()

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

/datum/bot_scenario/griefed/surgeon/full_bag
	name = "surgery: with its hands, pockets and bag full, a doctor makes room for the tools"
	desc = "The same, late in a shift: a bag with no room left, something in each pocket and each hand. A tool left in the hand was what it put down to pick the next one up, and no operation got past fetching the tools."

/datum/bot_scenario/griefed/surgeon/full_bag/grief()
	var/obj/item/storage/bag = bot.get_item_by_slot(ITEM_SLOT_BACK)
	for(var/i in 1 to 7) //not sheets: a stack put in a bag joins the one that's in it
		SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_INSERT, new /obj/item/extinguisher(bot.loc), bot, TRUE, TRUE)
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!bot.get_item_by_slot(slot))
			bot.equip_to_slot_or_del(new /obj/item/lighter(bot), slot)
	bot.put_in_hands(new /obj/item/stock_parts/cell/high(bot.loc))
	bot.put_in_hands(new /obj/item/toy/plush/carpplushie(bot.loc))
	..()

/datum/bot_scenario/griefed/surgeon/tools_back
	name = "surgery: the tools go back on the table when the operation's done"
	desc = "The same, with the tools on tables as they are in Surgery. There's one set, and a doctor kept what it had picked up in its bag: the next doctor with somebody to operate on knew of no scalpel."

/datum/bot_scenario/griefed/surgeon/tools_back/setup()
	..()
	for(var/char in list("s", "r", "h", "c"))
		for(var/turf/T in markers[char])
			place(char, new /obj/structure/table(T))

/datum/bot_scenario/griefed/surgeon/tools_back/check()
	. = ..()
	if(. != BOT_GYM_PASS)
		return
	for(var/char in list("s", "r", "h", "c"))
		for(var/obj/item/I in placed[char])
			if(is_type_in_list(I, GLOB.bot_surgery_tools) && !(isturf(I.loc) && (locate(/obj/structure/table) in I.loc)))
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

/datum/bot_scenario/duty/armory_opens
	name = "security: at red alert with a nanosuit loose, the Warden opens the armory and an officer arms up from it"
	desc = "The user's ruling: open the Armory. The Warden opens the armory door and holds it, says so on the radio, and an officer with no armory access of its own walks in for a laser."
	duty_type = /datum/bot_duty/open_armory
	job = "Warden"
	station_wide = TRUE //the alert level is the whole station's
	layout = list(
		"############",
		"#B.O...Dl..#",
		"#K##########",
		"############")
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/officer
	var/mob/living/carbon/human/suspect

/datum/bot_scenario/duty/armory_opens/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_ARMORY)
	A.req_access_txt = "[ACCESS_ARMORY]"
	for(var/turf/T in markers["l"])
		place("l", new /obj/item/gun/energy/laser(T))

/datum/bot_scenario/duty/armory_opens/post_spawn()
	var/obj/item/card/id/C = bot.get_idcard(TRUE)
	if(!C)
		C = new /obj/item/card/id(bot)
		bot.equip_to_slot_or_del(C, ITEM_SLOT_ID)
	C.access |= list(ACCESS_ARMORY, ACCESS_SECURITY, ACCESS_BRIG)
	officer = second_bot(first_marker("O"), "Officer Oakes")
	officer.mind.assigned_role = "Security Officer"
	officer.bot_brain.register_security()
	suspect = stand_in(first_marker("K"), "Nano Suit")
	suspect.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(suspect), ITEM_SLOT_OCLOTHING)
	brain.file_crime(suspect, "Murder", "Gym.", BOT_CRIME_MURDER)
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(set_security_level), SEC_LEVEL_RED)

/datum/bot_scenario/duty/armory_opens/check()
	if(bot_lost() || QDELETED(officer))
		return BOT_GYM_FAIL
	if(bot_armory_open_for_security() && officer.bot_brain.state == BOT_STATE_WANDER && !officer.bot_brain.current_goal)
		var/datum/bot_duty/arm_up/D = bot_duty_of(/datum/bot_duty/arm_up)
		D.try_start(officer.bot_brain) //a scripted bot doesn't look for its own duties
	return (locate(/obj/item/gun/energy/laser) in officer.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/armory_opens/release_run()
	bot_clear_wanted(suspect)
	GLOB.bot_armory_open_until = 0
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(set_security_level), SEC_LEVEL_GREEN)
	return ..()

/datum/bot_scenario/duty/traitor/robust_shop/watched
	name = "robust: doesn't change into the nanosuit with somebody watching"
	desc = "The same traitor about to buy its nanosuit, with a crewman stood watching. The suit doesn't come out until they've gone. A cook put one on in the hallway outside the HoP's office, stripping in front of an assistant, and Security had his name on the radio within a second."
	layout = list(
		"#######",
		"#B..W.#",
		"#######")
	var/mob/living/carbon/human/onlooker

/datum/bot_scenario/duty/traitor/robust_shop/watched/setup()
	for(var/turf/T in markers["W"])
		onlooker = new(T)
		place("W", onlooker)
		onlooker.equipOutfit(/datum/outfit/bot_gym)

/datum/bot_scenario/duty/traitor/robust_shop/watched/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(onlooker_leaves)), 6 SECONDS)

/datum/bot_scenario/duty/traitor/robust_shop/watched/proc/onlooker_leaves()
	if(QDELETED(onlooker))
		return
	log_line("the onlooker leaves")
	qdel(onlooker)
	onlooker = null

/datum/bot_scenario/duty/traitor/robust_shop/watched/check()
	if(brain.nanosuit_on() && onlooker)
		fail_reason = "put the suit on with somebody watching"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/duty/armory_opens/ordered
	name = "security: a nanosuit loose a minute and no red alert, the Head of Security orders the armory open anyway"
	desc = "The user's ruling: if red isn't up a minute after a suit is seen, the HoS or the Captain orders the armory opened anyway. Red alert takes two heads at two devices: in a played round only one got there, the armory stayed shut, and five officers died to a nanosuit with tasers in their hands."
	layout = list(
		"############",
		"#B.O...Dl..#",
		"#KH#########",
		"############")
	time_limit = 100 SECONDS
	var/mob/living/carbon/human/hos

/datum/bot_scenario/duty/armory_opens/ordered/post_spawn()
	var/obj/item/card/id/C = bot.get_idcard(TRUE)
	if(!C)
		C = new /obj/item/card/id(bot)
		bot.equip_to_slot_or_del(C, ITEM_SLOT_ID)
	C.access |= list(ACCESS_ARMORY, ACCESS_SECURITY, ACCESS_BRIG)
	officer = second_bot(first_marker("O"), "Officer Oakes")
	officer.mind.assigned_role = "Security Officer"
	officer.bot_brain.register_security()
	hos = second_bot(first_marker("H"), "Head Hos")
	hos.mind.assigned_role = "Head of Security"
	hos.bot_brain.register_security()
	suspect = stand_in(first_marker("K"), "Nano Suit")
	suspect.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(suspect), ITEM_SLOT_OCLOTHING)
	brain.file_crime(suspect, "Murder", "Gym.", BOT_CRIME_MURDER)
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(set_security_level), SEC_LEVEL_GREEN) //no red alert: that's the point

/datum/bot_scenario/duty/armory_opens/ordered/check()
	if(QDELETED(hos))
		return BOT_GYM_FAIL
	var/order_type = text2path("/datum/bot_duty/order_armory") //only there with the fix
	if(order_type && hos.bot_brain.state == BOT_STATE_WANDER && !hos.bot_brain.current_goal)
		var/datum/bot_duty/D = bot_duty_of(order_type)
		D?.try_start(hos.bot_brain) //a scripted bot doesn't look for its own duties
	return ..()

/datum/bot_scenario/duty/armory_opens/ordered/release_run()
	if("bot_armory_ordered_until" in GLOB.vars)
		GLOB.vars["bot_armory_ordered_until"] = 0
	return ..()

// ---------------------------------------------------------------------------------------------
// The crew against a nanosuit (goals/fight_the_suit.dm). The user's ruling: anybody, any time, by any means.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/suit
	time_limit = 20 SECONDS
	var/fought_for = 0

/datum/bot_scenario/griefed/suit/post_spawn()
	..()
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(griefer.loc)
	griefer.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)

/datum/bot_scenario/griefed/suit/proc/punch(mob/living/at)
	griefer_hand(INTENT_HARM, at)
	return TRUE

/datum/bot_scenario/griefed/suit/proc/ran()
	return bot_transcript_has("run_from") || bot_transcript_has("running for it")

/datum/bot_scenario/griefed/suit/hit_by_one
	name = "nanosuit: hit by one, even somebody with no nerve stands and fights"
	desc = "Robust traitors killed six to nine at a time while the crew ran, because anybody under 0.7 nerve ran from a suit straight away. Now they fight it, and only run once they're badly hurt."
	layout = list(
		"######################",
		"#.CB.................#",
		"######################")

/datum/bot_scenario/griefed/suit/hit_by_one/post_spawn()
	..()
	brain.nerve = 0.2

/datum/bot_scenario/griefed/suit/hit_by_one/grief()
	keep_at_it("punch_bot", 20)

/datum/bot_scenario/griefed/suit/hit_by_one/proc/punch_bot()
	return punch(bot)

/datum/bot_scenario/griefed/suit/hit_by_one/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(ran() && bot.health > bot.maxHealth * brain.health_to_run_at())
		fail_reason = "ran from it before it was hurt"
		return BOT_GYM_FAIL
	if(brain.state == BOT_STATE_COMBAT && brain.attacker == griefer)
		fought_for++
	return fought_for >= 6 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/suit/beating_somebody
	name = "nanosuit: beating somebody, a bystander with no nerve grabs the toolbox and goes in"
	desc = "The same coward who gets out of a fist fight goes for a suit: the toolbox a few tiles off first, then into it."
	layout = list(
		"#################",
		"#...............#",
		"#.T.B...VC......#",
		"#...............#",
		"#################")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/griefed/suit/beating_somebody/post_spawn()
	..()
	victim = stand_in(first_marker("V"), "Vic Victim")
	brain.nerve = 0.1

/datum/bot_scenario/griefed/suit/beating_somebody/grief()
	keep_at_it("beat", 15)

/datum/bot_scenario/griefed/suit/beating_somebody/proc/beat()
	punch(victim)
	return victim.stat == CONSCIOUS

/datum/bot_scenario/griefed/suit/beating_somebody/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(ran())
		fail_reason = "ran from it"
		return BOT_GYM_FAIL
	var/armed = locate(/obj/item/storage/toolbox) in bot.held_items
	return (armed && brain.state == BOT_STATE_COMBAT && brain.attacker == griefer) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/suit/knocked_down
	name = "nanosuit: knocked down, the crew keep at it until it's cuffed or dead"
	desc = "Crew stop when somebody's on the floor. A suit's up again in seconds: a captain knocked one down, stopped to hold it for Security, and was back fighting it every second after."
	layout = list(
		"##########",
		"#.BC.....#",
		"##########")
	kit_backpack = list(/obj/item/extinguisher)
	var/down_at = 0

/datum/bot_scenario/griefed/suit/knocked_down/post_spawn()
	..()
	brain.nerve = 0.5

/datum/bot_scenario/griefed/suit/knocked_down/grief()
	keep_at_it("punch_back", 20)

/datum/bot_scenario/griefed/suit/knocked_down/proc/punch_back()
	if(griefer.stat == CONSCIOUS && !brain.is_subdued(griefer))
		punch(bot)
	return TRUE

/datum/bot_scenario/griefed/suit/knocked_down/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(griefer.stat == DEAD)
		return BOT_GYM_PASS
	if(!down_at && brain.state == BOT_STATE_COMBAT && brain.attacker == griefer && ++fought_for >= 2)
		griefer.Paralyze(10 SECONDS) //the suit's armour shrugs off an extinguisher: knock it down for it, the way a bola or a stunprod would
		down_at = world.time
		log_line("the suit's down")
	if(!down_at)
		return BOT_GYM_PENDING
	if(brain.state != BOT_STATE_COMBAT || brain.attacker != griefer)
		fail_reason = "stopped once it was down"
		return BOT_GYM_FAIL
	return world.time >= down_at + 4 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/suit/in_sight
	name = "nanosuit: just stood there, wanted or not, the crew goes for it"
	desc = "Nobody hurt yet and nothing on the records. It's Syndicate gear in plain sight: they call it in and go for it."
	layout = list(
		"#############",
		"#.B....C....#",
		"#############")

/datum/bot_scenario/griefed/suit/in_sight/post_spawn()
	..()
	brain.nerve = 0.4

/datum/bot_scenario/griefed/suit/in_sight/grief()
	brain.look_out_for_trouble() //a scripted bot doesn't look round by itself (keep_an_eye_out())

/datum/bot_scenario/griefed/suit/in_sight/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(ran())
		fail_reason = "ran from it"
		return BOT_GYM_FAIL
	return (brain.state == BOT_STATE_COMBAT && brain.attacker == griefer) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/range/holds_fire
	name = "security: crew fighting a nanosuit up close, the officers don't shoot into them"
	desc = "Officers shot a cargo tech who was beating on a suit, twice with a disabler and twice with a laser, from across the room. The line to the suit was clear, but a shot that goes wide hits whoever's next to it. Three officers, the ones who'd shoot it from range (security: a nanosuit gets shot from range...)."
	time_limit = 15 SECONDS
	layout = list(
		"###########",
		"#B.......C#",
		"#O.......V#",
		"#P........#",
		"###########")
	var/mob/living/carbon/human/crewman

/datum/bot_scenario/griefed/officer/range/holds_fire/post_spawn()
	..()
	crewman = stand_in(first_marker("V"), "Cargo Cass")

/datum/bot_scenario/griefed/officer/range/holds_fire/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("firing"))
		fail_reason = "shot with Cargo Cass right beside the suit"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/range/holds_fire/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/officer/alone/gives_it_a_rest
	name = "security: an officer that gives up waiting on a nanosuit doesn't start the same arrest over at once"
	desc = "Shift batch ask1 run8: officers waiting on two more for a suit gave the arrest up after five minutes and started it again the same moment, seven times running, saying \"Couldn't bring them in\" on the radio every time and pacing two Brig tiles for half an hour."
	time_limit = 45 SECONDS
	var/gave_up_at = 0

/datum/bot_scenario/griefed/officer/alone/gives_it_a_rest/grief()
	..()
	brain.arrest_started = world.time - 290 SECONDS //the five minutes nearly up (BOT_ARREST_MAX_DURATION, goals/security_patrol.dm)
	brain.gym_scripted = FALSE //on patrol between arrests, eyes open (try_spot_wanted()), as in a round

/datum/bot_scenario/griefed/officer/alone/gives_it_a_rest/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/arrests = 0
	for(var/line in transcript)
		if(findtext(line, "moving to arrest"))
			arrests++
		if(!gave_up_at && findtext(line, "took too long"))
			gave_up_at = world.time
			var/turf/near = locate(bot.x + 5, bot.y, bot.z) //in plain sight, as the suit in the Brig was
			if(near && !near.density)
				griefer.forceMove(near)
	if(arrests > 1)
		fail_reason = "started the same arrest again after giving it up"
		return BOT_GYM_FAIL
	return (gave_up_at && world.time > gave_up_at + 20 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING
