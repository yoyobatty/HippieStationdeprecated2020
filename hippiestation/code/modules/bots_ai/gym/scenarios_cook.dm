// Bot Gym scenarios for the cook (goals/cook.dm). The cook is handed nothing: its own round has to
// find the ingredients, the machine and the counter.
//
// Layout letters used here: u a microwave, p a food processor, R the produce smartfridge, e an egg box,
// k a locked meat fridge, t the serving table.

/datum/bot_scenario/duty/cook
	duty_type = /datum/bot_duty/cook
	job = "Cook"
	time_limit = 120 SECONDS
	max_goal_attempts = 20
	/// What should end up on the serving table, and how many of them at least.
	var/dish_type
	var/dishes_wanted = 2
	/// What the smartfridge starts with.
	var/list/fridge_stock

/datum/bot_scenario/duty/cook/setup()
	for(var/turf/T in markers["u"])
		place("u", new /obj/machinery/microwave(T))
	for(var/turf/T in markers["p"])
		place("p", new /obj/machinery/processor(T))
	for(var/turf/T in markers["e"])
		place("e", new /obj/item/storage/fancy/egg_box(T))
	for(var/turf/T in markers["k"])
		place("k", new /obj/structure/closet/secure_closet/freezer/meat(T))
	for(var/turf/T in markers["R"])
		var/obj/machinery/smartfridge/fridge = new(T)
		for(var/path in fridge_stock)
			new path(fridge)
		fridge.update_icon()
		place("R", fridge)

/datum/bot_scenario/duty/cook/post_spawn()
	give_job_id(list(ACCESS_KITCHEN))

/datum/bot_scenario/duty/cook/proc/served()
	. = 0
	for(var/turf/T in markers["t"])
		for(var/obj/item/I in T)
			if(istype(I, dish_type))
				.++

/datum/bot_scenario/duty/cook/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return served() >= dishes_wanted ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/cook/boiled_eggs
	name = "cook boils eggs and puts them out"
	desc = "An egg box on the floor, a microwave, a serving table. The cook picks the box up, puts eggs in the microwave one at a time, starts it, waits, and sets the boiled eggs out on the table."
	layout = list(
		"###########",
		"#..u...t..#",
		"#B.e......#",
		"###########")
	dish_type = /obj/item/reagent_containers/food/snacks/boiledegg

/datum/bot_scenario/duty/cook/tater_tots
	name = "cook makes tater tots from the smartfridge"
	desc = "Potatoes in the produce smartfridge and a food processor. The cook takes potatoes out one press at a time, runs them through the processor and puts the tater tots out."
	layout = list(
		"###########",
		"#R.p...t..#",
		"#B........#",
		"###########")
	dish_type = /obj/item/reagent_containers/food/snacks/tatortot
	fridge_stock = list(/obj/item/reagent_containers/food/snacks/grown/potato, /obj/item/reagent_containers/food/snacks/grown/potato, /obj/item/reagent_containers/food/snacks/grown/potato)

/datum/bot_scenario/duty/cook/steak
	name = "cook gets meat from the meat fridge for steak"
	desc = "The meat is in a locked meat fridge. The cook unlocks and opens it with its ID, takes slabs to the microwave, and puts the steaks out."
	layout = list(
		"###########",
		"#k.u...t..#",
		"#B........#",
		"###########")
	dish_type = /obj/item/reagent_containers/food/snacks/meat/steak
