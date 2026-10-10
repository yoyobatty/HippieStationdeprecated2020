// Bot Gym scenarios for Robotics (goals/robotics.dm).
//
// Layout letters used here: R an exosuit fabricator (it puts what it prints on the tile south of it), e a stack of
// metal, k an empty first-aid kit, a a health analyzer, p a proximity sensor.

/datum/bot_scenario/duty/robotics
	duty_type = /datum/bot_duty/roboticist
	job = "Roboticist"
	time_limit = 180 SECONDS

/datum/bot_scenario/duty/robotics/setup()
	for(var/turf/T in markers["R"])
		place("R", new /obj/machinery/mecha_part_fabricator(T))
	for(var/turf/T in markers["e"])
		place("e", new /obj/item/stack/sheet/metal/fifty(T))
	for(var/turf/T in markers["k"])
		var/obj/item/storage/firstaid/regular/kit = new(T)
		for(var/obj/item/I in kit)
			qdel(I)
		place("k", kit)
	for(var/turf/T in markers["a"])
		place("a", new /obj/item/healthanalyzer(T))
	for(var/turf/T in markers["p"])
		place("p", new /obj/item/assembly/prox_sensor(T))

/datum/bot_scenario/duty/robotics/medibot
	name = "roboticist builds a medibot"
	desc = "A fabricator with nothing in its stores, and on the floor a stack of metal, an empty first-aid kit, a health analyzer and a proximity sensor. The roboticist feeds the machine, prints a robot arm and waits for it, then puts the medibot together a part at a time - each part in hand when it's used."
	layout = list(
		"##########",
		"#B.R.....#",
		"#........#",
		"#e.k.a.p.#",
		"##########")

/datum/bot_scenario/duty/robotics/medibot/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/mob/living/simple_animal/bot/medbot/made = locate() in arena_area
	if(!made || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(world.time - start_time < 20 SECONDS)
		fail_reason = "a medibot in [(world.time - start_time) / 10]s - the arm alone takes 20 to print"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
