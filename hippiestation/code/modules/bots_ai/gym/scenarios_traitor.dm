// Bot Gym scenarios for playing a traitor (goals/traitor.dm). The bot gets the real antagonist datum, with objectives
// replaced by the one the scenario is about, and is driven by its duty like any other.

/datum/bot_scenario/duty/traitor
	duty_type = /datum/bot_duty/traitor
	job = "Assistant"
	time_limit = 90 SECONDS
	var/datum/antagonist/traitor/antag

/datum/bot_scenario/duty/traitor/post_spawn()
	..()
	give_job_id(list())
	antag = brain.become_traitor() //no PDA on a gym bot: the uplink goes in a pen
	antag.objectives.Cut()

/datum/bot_scenario/duty/traitor/proc/set_steal_objective(item_type)
	var/datum/objective/steal/S = new
	S.owner = bot.mind
	S.steal_target = item_type
	S.explanation_text = "Steal [item_type]"
	antag.objectives += S

/datum/bot_scenario/duty/traitor/proc/set_kill_objective(mob/living/carbon/human/victim)
	var/datum/objective/assassinate/A = new
	A.owner = bot.mind
	if(!victim.mind)
		victim.mind_initialize()
	A.target = victim.mind
	A.explanation_text = "Assassinate [victim.real_name]"
	antag.objectives += A

/datum/bot_scenario/duty/traitor/steal_loose
	name = "traitor steals what's lying about"
	desc = "The objective is a hand teleporter, sitting on the floor across the room. The traitor walks over and pockets it."
	layout = list(
		"########",
		"#B....I#",
		"########")

/datum/bot_scenario/duty/traitor/steal_loose/setup()
	for(var/turf/T in markers["I"])
		place("I", new /obj/item/hand_tele(T))

/datum/bot_scenario/duty/traitor/steal_loose/post_spawn()
	..()
	set_steal_objective(/obj/item/hand_tele)

/datum/bot_scenario/duty/traitor/steal_loose/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/hand_tele) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/steal_locked
	name = "traitor breaks a locker open for it"
	desc = "The objective is locked in a captain's locker, and the bot's ID doesn't open that. There's a fire axe on the floor. It breaks the locker with something heavy and takes what it came for, and nothing else."
	layout = list(
		"#########",
		"#B.A...L#",
		"#########")

/datum/bot_scenario/duty/traitor/steal_locked/setup()
	for(var/turf/T in markers["L"])
		var/obj/structure/closet/secure_closet/S = new(T)
		S.req_access = list(ACCESS_CAPTAIN)
		S.locked = TRUE
		new /obj/item/hand_tele(S)
		place("L", S)
	for(var/turf/T in markers["A"])
		place("A", new /obj/item/twohanded/fireaxe(T))

/datum/bot_scenario/duty/traitor/steal_locked/post_spawn()
	..()
	set_steal_objective(/obj/item/hand_tele)

/datum/bot_scenario/duty/traitor/steal_locked/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/hand_tele) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/kill_alone
	name = "traitor kills a target with nobody watching"
	desc = "The target is alone in the room. The traitor buys a sword off the uplink, walks up, and doesn't stop until they're dead, then puts it away."
	layout = list(
		"#########",
		"#B.....V#",
		"#########")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/duty/traitor/kill_alone/post_spawn()
	..()
	victim = stand_in(first_marker("V"), "Vic Tim")
	set_kill_objective(victim)

/datum/bot_scenario/duty/traitor/kill_alone/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(victim) || victim.stat != DEAD || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	var/obj/item/melee/transforming/energy/sword/S = brain.find_carried_tool(/obj/item/melee/transforming/energy/sword)
	if(!S)
		fail_reason = "killed them, but never bought a sword"
		return BOT_GYM_FAIL
	if(S.active)
		fail_reason = "left the sword on"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// Everything a traitor's objective can be shut away in, one scenario each.
/datum/bot_scenario/duty/traitor/steal_full_bag
	name = "traitor makes room in the bag for what it stole"
	desc = "The bag is full of what a bot picks up on its rounds. The objective goes in it all the same, and something else comes out, so the hand's free and it isn't set down the next time the hand's wanted."
	layout = list(
		"########",
		"#B....I#",
		"########")

/datum/bot_scenario/duty/traitor/steal_full_bag/setup()
	for(var/turf/T in markers["I"])
		place("I", new /obj/item/areaeditor/blueprints(T))

/datum/bot_scenario/duty/traitor/steal_full_bag/post_spawn()
	..()
	var/obj/item/storage/bag = bot.get_item_by_slot(ITEM_SLOT_BACK)
	for(var/i in 1 to 7)
		SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_INSERT, new /obj/item/stack/sheet/metal(bot.loc), bot, TRUE, TRUE)
	set_steal_objective(/obj/item/areaeditor/blueprints)

/datum/bot_scenario/duty/traitor/steal_full_bag/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/stolen = locate(/obj/item/areaeditor/blueprints) in bot.get_item_by_slot(ITEM_SLOT_BACK)
	return stolen ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/steal_emag_locker
	name = "traitor scrambles a locker's lock with the emag"
	desc = "The objective's in a locker its ID doesn't open, and there's no fire axe in the room. It buys an emag off the uplink, and the lock's scrambled, not smashed."
	layout = list(
		"#########",
		"#B.....Q#",
		"#########")

/datum/bot_scenario/duty/traitor/steal_emag_locker/setup()
	for(var/turf/T in markers["Q"])
		var/obj/structure/closet/secure_closet/S = new(T)
		S.req_access = list(ACCESS_CAPTAIN)
		S.locked = TRUE
		new /obj/item/hand_tele(S)
		place("Q", S)

/datum/bot_scenario/duty/traitor/steal_emag_locker/post_spawn()
	..()
	set_steal_objective(/obj/item/hand_tele)

/datum/bot_scenario/duty/traitor/steal_emag_locker/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/hand_tele) in bot.GetAllContents()) && brain.find_carried_tool(/obj/item/card/emag) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/steal_case
	name = "traitor smashes a display case"
	desc = "The objective is in a display case, which takes no card and no key. It breaks the glass with the sword, and takes it."
	layout = list(
		"#########",
		"#B.....Q#",
		"#########")

/datum/bot_scenario/duty/traitor/steal_case/setup()
	for(var/turf/T in markers["Q"])
		var/obj/structure/displaycase/case = new(T)
		case.alert = FALSE
		case.showpiece = new /obj/item/hand_tele(case)
		place("Q", case)

/datum/bot_scenario/duty/traitor/steal_case/post_spawn()
	..()
	set_steal_objective(/obj/item/hand_tele)

/datum/bot_scenario/duty/traitor/steal_case/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/hand_tele) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/steal_fridge
	name = "traitor takes it out of the smart fridge"
	desc = "The objective's in a smart fridge. It comes out with the button, like anything else in there. Nothing gets broken."
	layout = list(
		"#########",
		"#B.....Q#",
		"#########")

/datum/bot_scenario/duty/traitor/steal_fridge/setup()
	for(var/turf/T in markers["Q"])
		var/obj/machinery/smartfridge/extract/fridge = new(T)
		new /obj/item/slime_extract/grey(fridge)
		place("Q", fridge)

/datum/bot_scenario/duty/traitor/steal_fridge/post_spawn()
	..()
	set_steal_objective(/obj/item/slime_extract)

/datum/bot_scenario/duty/traitor/steal_fridge/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/slime_extract) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/steal_box
	name = "traitor takes the whole locked box"
	desc = "The objective is locked in a lockbox on the floor. A player picks up the box, and so does it, with nothing broken."
	layout = list(
		"#########",
		"#B.....Q#",
		"#########")

/datum/bot_scenario/duty/traitor/steal_box/setup()
	for(var/turf/T in markers["Q"])
		var/obj/item/storage/lockbox/medal/box = new(T)
		place("Q", box)

/datum/bot_scenario/duty/traitor/steal_box/post_spawn()
	..()
	set_steal_objective(/obj/item/clothing/accessory/medal/gold/captain)

/datum/bot_scenario/duty/traitor/steal_box/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/clothing/accessory/medal/gold/captain) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/through_a_door
	name = "traitor swipes through a door to its target"
	desc = "The target's on the other side of an airlock the bot's ID doesn't open. The emag goes through it, the door stays open and broken, and the target's dead."
	layout = list(
		"#########",
		"#B..D..V#",
		"#########")
	time_limit = 120 SECONDS
	var/mob/living/carbon/human/victim

/datum/bot_scenario/duty/traitor/through_a_door/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/duty/traitor/through_a_door/post_spawn()
	..()
	victim = stand_in(first_marker("V"), "Vic Tim")
	set_kill_objective(victim)

/datum/bot_scenario/duty/traitor/through_a_door/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(QDELETED(victim) || victim.stat != DEAD)
		return BOT_GYM_PENDING
	if(QDELETED(A) || !(A.obj_flags & EMAGGED))
		fail_reason = "got to them, but not with the card"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/traitor/runs_out_of_patience
	name = "traitor that's been waiting strikes in front of one witness"
	desc = "The same witness as the scenario below, but this one has already stood beside its target through two tries that came to nothing. One onlooker doesn't stop it now."
	layout = list(
		"#########",
		"#B....VC#",
		"#########")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/duty/traitor/runs_out_of_patience/post_spawn()
	..()
	victim = stand_in(first_marker("V"), "Vic Tim")
	stand_in(first_marker("C"), "Casey Witness")
	set_kill_objective(victim)
	brain.failed_goes = 2

/datum/bot_scenario/duty/traitor/runs_out_of_patience/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return victim.stat == DEAD ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/waits_for_witness
	name = "traitor doesn't strike in front of a witness"
	desc = "The target is standing beside somebody else, and neither of them moves. The traitor closes in and doesn't touch them. Passing means the target is unhurt after 25 seconds."
	layout = list(
		"#########",
		"#B....VC#",
		"#########")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/duty/traitor/waits_for_witness/post_spawn()
	..()
	victim = stand_in(first_marker("V"), "Vic Tim")
	stand_in(first_marker("C"), "Casey Witness")
	set_kill_objective(victim)

/datum/bot_scenario/duty/traitor/waits_for_witness/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(victim.health < victim.maxHealth)
		fail_reason = "attacked with a witness standing right there"
		return BOT_GYM_FAIL
	return world.time > start_time + 25 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING
