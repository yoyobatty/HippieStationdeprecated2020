// Bot Gym scenarios for the bar: the bartender mixing (goals/bartender.dm) and a customer drinking
// what's been poured (goals/eat_and_drink.dm).
//
// Layout letters used here: O a Booze-O-Mat, b the booze dispenser, s the soda dispenser, t the bar top.

/datum/bot_scenario/duty/bar
	duty_type = /datum/bot_duty/bartender
	job = "Bartender"
	time_limit = 90 SECONDS
	max_goal_attempts = 20

/datum/bot_scenario/duty/bar/setup()
	for(var/turf/T in markers["O"])
		place("O", new /obj/machinery/vending/boozeomat(T))
	for(var/turf/T in markers["b"])
		place("b", new /obj/machinery/chem_dispenser/drinks/beer(T))
	for(var/turf/T in markers["s"])
		place("s", new /obj/machinery/chem_dispenser/drinks(T))

/datum/bot_scenario/duty/bar/post_spawn()
	give_job_id(list(ACCESS_BAR))

/// Filled glasses on the bar top.
/datum/bot_scenario/duty/bar/proc/poured()
	. = list()
	for(var/turf/T in markers["t"])
		for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G in T)
			if(G.reagents.total_volume)
				. += G

/datum/bot_scenario/duty/bar/mixes_a_drink
	name = "bartender mixes a drink and puts it on the bar"
	desc = "A Booze-O-Mat, the two dispensers and a bar top. The bartender gets a glass, pours the spirit at one machine and the mixer at the other - glass in, button, glass out each time - and sets the drink down on the bar."
	layout = list(
		"###########",
		"#O.b.s.t..#",
		"#B........#",
		"###########")

/datum/bot_scenario/duty/bar/mixes_a_drink/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G as anything in poured())
		if(G.reagents.total_volume < 25)
			fail_reason = "put out a glass with only [G.reagents.total_volume]u in it"
			return BOT_GYM_FAIL
		if(length(G.reagents.reagent_list) != 1)
			fail_reason = "the glass holds [length(G.reagents.reagent_list)] separate things - it never mixed into a drink"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/bar/customer
	name = "customer has the drink that's out on the bar"
	desc = "A gin and tonic on the bar and a machine further off. The bot walks to the bar, picks the glass up, drinks it a gulp at a time and puts the empty back on the bar."
	duty_type = /datum/bot_duty/have_a_drink
	job = "Assistant"
	layout = list(
		"###########",
		"#B...t...V#",
		"###########")
	time_limit = 120 SECONDS
	var/obj/item/reagent_containers/food/drinks/drinkingglass/glass

/datum/bot_scenario/duty/bar/customer/setup()
	..()
	glass = new(first_marker("t"))
	glass.reagents.add_reagent(/datum/reagent/consumable/ethanol/gintonic, 30)

/datum/bot_scenario/duty/bar/customer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.drinks_drunk || brain.state != BOT_STATE_WANDER || brain.current_goal)
		return BOT_GYM_PENDING
	if(QDELETED(glass) || glass.reagents.total_volume)
		fail_reason = "had a drink, but not the one on the bar"
		return BOT_GYM_FAIL
	if(!isturf(glass.loc) || !(locate(/obj/structure/table) in glass.loc))
		fail_reason = "walked off with the empty glass"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
