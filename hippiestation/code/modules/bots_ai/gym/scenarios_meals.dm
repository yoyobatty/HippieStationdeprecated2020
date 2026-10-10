// Bot Gym scenarios for eating and drinking (goals/eat_and_drink.dm). The bot starts hungry and is
// handed nothing: the duty has to find the food.
//
// Layout letters used here: N a snack machine, H a hot drinks machine, t a table (the dish is put on it).

/datum/bot_scenario/duty/meal
	duty_type = /datum/bot_duty/eat_when_hungry
	job = "Assistant"
	time_limit = 60 SECONDS
	/// Nutrition the bot starts on - under 200 is properly hungry.
	var/start_nutrition = 150

/datum/bot_scenario/duty/meal/setup()
	for(var/turf/T in markers["N"])
		place("N", new /obj/machinery/vending/snack(T))
	for(var/turf/T in markers["H"])
		place("H", new /obj/machinery/vending/coffee(T))

/datum/bot_scenario/duty/meal/post_spawn()
	give_job_id()
	bot.set_nutrition(start_nutrition)

/// Litter still in the bot's hands.
/datum/bot_scenario/duty/meal/proc/holding_rubbish()
	for(var/obj/item/I in bot.held_items)
		if(istype(I, /obj/item/trash))
			return TRUE
	return FALSE

/datum/bot_scenario/duty/meal/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.meals_eaten || brain.state != BOT_STATE_WANDER || brain.current_goal)
		return BOT_GYM_PENDING
	if(holding_rubbish())
		fail_reason = "finished eating and is still holding the wrapper"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/meal/snack_machine
	name = "hungry bot buys a snack and eats it"
	desc = "Properly hungry, with a snack machine down the corridor. It walks over, pays for something, eats it a bite at a time, and gets rid of the wrapper."
	layout = list(
		"#########",
		"#B.....N#",
		"#########")

/datum/bot_scenario/duty/meal/from_pocket
	name = "hungry bot eats what's in its pocket"
	desc = "Hungry, with a snack already in the bag and a machine further off. It eats the one it has rather than buying another."
	layout = list(
		"#########",
		"#B.....N#",
		"#########")
	kit_backpack = list(/obj/item/reagent_containers/food/snacks/candy)

/datum/bot_scenario/duty/meal/from_pocket/check()
	. = ..()
	if(. == BOT_GYM_PASS && get_dist(bot, first_marker("B")) > 1)
		fail_reason = "walked to the machine with food in its bag"
		return BOT_GYM_FAIL

/datum/bot_scenario/duty/meal/off_the_counter
	name = "hungry bot takes a dish off the counter"
	desc = "A burger left out on a table. It picks it up and eats it rather than going to a machine."
	layout = list(
		"#########",
		"#B...t.N#",
		"#########")
	var/obj/item/reagent_containers/food/snacks/dish

/datum/bot_scenario/duty/meal/off_the_counter/setup()
	..()
	dish = new /obj/item/reagent_containers/food/snacks/burger/plain(first_marker("t"))

/datum/bot_scenario/duty/meal/off_the_counter/check()
	. = ..()
	if(. == BOT_GYM_PASS && !QDELETED(dish) && isturf(dish.loc))
		fail_reason = "ate something else and left the dish on the table"
		return BOT_GYM_FAIL

/datum/bot_scenario/duty/meal/not_raw
	name = "hungry bot doesn't eat raw ingredients"
	desc = "Hungry, with nothing to hand but a raw tomato and a slab of meat. It leaves them alone."
	layout = list(
		"#######",
		"#B....#",
		"#######")
	kit_backpack = list(/obj/item/reagent_containers/food/snacks/grown/tomato, /obj/item/reagent_containers/food/snacks/meat/slab)
	time_limit = 20 SECONDS

/datum/bot_scenario/duty/meal/not_raw/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.meals_eaten || !(locate(/obj/item/reagent_containers/food/snacks/grown/tomato) in bot.GetAllContents()))
		fail_reason = "ate the raw ingredients"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/meal/not_raw/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/duty/meal/coffee
	name = "bot has a coffee from the machine"
	desc = "Free time and a hot drinks machine nearby. It buys one, drinks it a gulp at a time, and doesn't keep the empty cup."
	duty_type = /datum/bot_duty/have_a_drink
	start_nutrition = 350
	layout = list(
		"#########",
		"#B.....H#",
		"#########")
	time_limit = 120 SECONDS

/datum/bot_scenario/duty/meal/coffee/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.drinks_drunk || brain.state != BOT_STATE_WANDER || brain.current_goal)
		return BOT_GYM_PENDING
	for(var/obj/item/reagent_containers/food/drinks/D in bot.GetAllContents())
		if(!D.reagents?.total_volume)
			fail_reason = "kept the empty cup"
			return BOT_GYM_FAIL
	return BOT_GYM_PASS
