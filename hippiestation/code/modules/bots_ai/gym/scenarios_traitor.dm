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
