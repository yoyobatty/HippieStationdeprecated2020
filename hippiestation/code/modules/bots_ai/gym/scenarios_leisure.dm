// Bot Gym scenarios for free time (goals/leisure.dm). A Bot Gym bot has every pastime going
// (bot_brain.has_habit()), and is handed nothing: the duty has to start it.
//
// Layout letters used here: Y a cigarette machine, i a corgi that stays put, A an arcade machine.

/datum/bot_scenario/duty/leisure
	job = "Assistant"
	time_limit = 60 SECONDS

/datum/bot_scenario/duty/leisure/setup()
	for(var/turf/T in markers["Y"])
		place("Y", new /obj/machinery/vending/cigarette(T))
	for(var/turf/T in markers["A"])
		place("A", new /obj/machinery/computer/arcade/battle(T))
	for(var/turf/T in markers["i"])
		var/mob/living/simple_animal/pet/dog/corgi/dog = new(T)
		dog.stop_automated_movement = TRUE
		dog.wander = FALSE
		place("i", dog)

/datum/bot_scenario/duty/leisure/post_spawn()
	give_job_id()

/// Smoking properly: a lit cigarette in the mouth, and the pack and lighter put away again with the lighter out.
/datum/bot_scenario/duty/leisure/proc/judge_smoke()
	var/obj/item/clothing/mask/cigarette/cig = bot.wear_mask
	if(!istype(cig) || !cig.lit || brain.state != BOT_STATE_WANDER || brain.current_goal)
		return BOT_GYM_PENDING
	for(var/obj/item/I in bot.held_items)
		if(istype(I, /obj/item/lighter) || istype(I, /obj/item/storage/fancy/cigarettes))
			fail_reason = "lit up and is still holding [I]"
			return BOT_GYM_FAIL
	var/obj/item/lighter/lighter = locate() in bot.GetAllContents()
	if(lighter?.lit)
		fail_reason = "put the lighter away still burning"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/leisure/smoke
	name = "smoker lights a cigarette"
	desc = "A pack and a lighter in the bag. One out of the pack into the mouth, lighter on, held to it, lighter off, both put away."
	duty_type = /datum/bot_duty/smoke
	layout = list(
		"#######",
		"#B....#",
		"#######")
	kit_backpack = list(/obj/item/storage/fancy/cigarettes, /obj/item/lighter/greyscale)

/datum/bot_scenario/duty/leisure/smoke/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return judge_smoke()

/datum/bot_scenario/duty/leisure/buy_smokes
	name = "smoker with nothing to smoke buys a pack"
	desc = "No cigarettes and no lighter, and a cigarette machine down the corridor. It buys a pack and a lighter, then lights up."
	duty_type = /datum/bot_duty/smoke
	layout = list(
		"#########",
		"#B.....Y#",
		"#########")

/datum/bot_scenario/duty/leisure/buy_smokes/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return judge_smoke()

/datum/bot_scenario/duty/leisure/pet
	name = "animal lover pets the dog"
	desc = "A corgi down the corridor. The bot walks over and makes a fuss of it - a few help-intent clicks, not a dozen in a second."
	duty_type = /datum/bot_duty/pet_animal
	layout = list(
		"#########",
		"#B....i.#",
		"#########")
	time_limit = 30 SECONDS

/datum/bot_scenario/duty/leisure/pet/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/mob/living/simple_animal/dog = first_placed("i")
	if(QDELETED(dog) || dog.stat == DEAD || dog.health < dog.maxHealth)
		fail_reason = "hurt the dog"
		return BOT_GYM_FAIL
	return (brain.animals_petted && brain.state == BOT_STATE_WANDER) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/leisure/arcade
	name = "gamer plays a game on the arcade machine"
	desc = "An arcade machine down the corridor. The bot walks over and plays Space Villain through to the end, a move every second or two, and takes the prize if it wins."
	duty_type = /datum/bot_duty/play_arcade
	layout = list(
		"#########",
		"#B.....A#",
		"#########")
	time_limit = 300 SECONDS

/datum/bot_scenario/duty/leisure/arcade/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.arcade_games_played || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	var/obj/machinery/computer/arcade/battle/machine = first_placed("A")
	if(QDELETED(machine) || !machine.gameover)
		fail_reason = "walked away from a game in progress"
		return BOT_GYM_FAIL
	if(end_time || world.time - start_time < 15 SECONDS)
		fail_reason = "finished a whole game in [(world.time - start_time) / 10]s"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
