// Bot Gym scenarios for cold air (bot_cold.dm).

/datum/bot_scenario/cold_room_trip
	name = "cold room: fetches the meat from the kitchen's cold room"
	desc = "Past the door the air is the kitchen cold room's, -80 C and otherwise fine, and there's a slab of meat at the far end. A cook goes in for it, the way a cook does."
	job = "Cook"
	layout = list(
		"##########",
		"#B...D..G#",
		"##########")
	time_limit = 30 SECONDS

/datum/bot_scenario/cold_room_trip/setup()
	var/turf/door = first_marker("D")
	for(var/turf/open/floor/F in range(10, door))
		if(F.x > door.x && F.y == door.y && get_area(F) == arena_area)
			F.air.parse_gas_string(KITCHEN_COLDROOM_ATMOS)
			F.update_visuals()
			SSair.add_to_active(F)
	place("m", new /obj/item/reagent_containers/food/snacks/meat/slab(first_marker("G")))

/datum/bot_scenario/cold_room_trip/make_goal()
	var/obj/item/meat = first_placed("m")
	return (QDELETED(meat) || !isturf(meat.loc)) ? null : new /datum/bot_goal/take_item/exact(meat)

/datum/bot_scenario/cold_room_trip/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/meat = first_placed("m")
	return (!QDELETED(meat) && (meat in bot.GetAllContents())) ? BOT_GYM_PASS : BOT_GYM_PENDING
