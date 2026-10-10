// Bot Gym scenarios for the janitor (goals/janitor.dm). Nothing is handed to the bot: its own rounds
// have to find the mess, the mop and the water.
//
// Layout letters used here: o blood on the floor, M a mop, U a bucket, K a water tank, J a JaniDrobe,
// I a floor tile under a dead light.

/datum/bot_scenario/duty/janitor
	duty_type = /datum/bot_duty/janitor
	job = "Janitor"
	time_limit = 90 SECONDS
	max_goal_attempts = 20
	/// Units of water the bucket starts with.
	var/bucket_water = 50

/datum/bot_scenario/duty/janitor/setup()
	for(var/turf/T in markers["o"])
		place("o", new /obj/effect/decal/cleanable/blood(T))
	for(var/turf/T in markers["M"])
		place("M", new /obj/item/mop(T))
	for(var/turf/T in markers["U"])
		var/obj/item/reagent_containers/glass/bucket/B = new(T)
		if(bucket_water)
			B.reagents.add_reagent(/datum/reagent/water, bucket_water)
		place("U", B)
	for(var/turf/T in markers["K"])
		place("K", new /obj/structure/reagent_dispensers/watertank(T))
	for(var/turf/T in markers["J"])
		place("J", new /obj/machinery/vending/wardrobe/jani_wardrobe(T))

/datum/bot_scenario/duty/janitor/post_spawn()
	give_job_id(list(ACCESS_JANITOR))

/// Messes left in the arena, by the janitor's own idea of a mess.
/datum/bot_scenario/duty/janitor/proc/messes_left()
	. = 0
	for(var/turf/T in arena_area)
		if(brain.turf_has_mess(T))
			.++

/datum/bot_scenario/duty/janitor/proc/went_over()
	if(bot.IsKnockdown() || bot.IsParalyzed() || !(bot.mobility_flags & MOBILITY_STAND))
		fail_reason = "slipped on its own wet floor"
		return TRUE
	return FALSE

/datum/bot_scenario/duty/janitor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(went_over())
		return BOT_GYM_FAIL
	return messes_left() ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/duty/janitor/mops_blood
	name = "janitor mops up blood"
	desc = "Three pools of blood down a corridor, a mop and a bucket of water by the door. The janitor picks both up, wets the mop in the bucket and mops each pool - mop in hand, and walking, since it has no galoshes."
	layout = list(
		"###########",
		"#BMU.o.oo.#",
		"###########")

/datum/bot_scenario/duty/janitor/fills_bucket
	name = "janitor fills an empty bucket first"
	desc = "The same, but the bucket is empty and there's a water tank in the room: fill the bucket at the tank, then wet the mop from it."
	layout = list(
		"###########",
		"#BMU.o.o..#",
		"#K........#",
		"###########")
	bucket_water = 0
	time_limit = 120 SECONDS

/datum/bot_scenario/duty/janitor/galoshes
	name = "janitor puts on galoshes from the JaniDrobe"
	desc = "A JaniDrobe in the room. Before anything else the janitor buys galoshes and puts them on, bagging its own shoes - then mops at a run, and takes the light replacer while it's there."
	layout = list(
		"###########",
		"#BMU.o.o..#",
		"#J........#",
		"###########")
	time_limit = 120 SECONDS

/datum/bot_scenario/duty/janitor/galoshes/check()
	. = ..()
	if(. != BOT_GYM_PASS)
		return
	if(!istype(bot.shoes, /obj/item/clothing/shoes/galoshes))
		fail_reason = "never put the galoshes on"
		return BOT_GYM_FAIL
	if(!(locate(/obj/item/clothing/shoes/sneakers) in bot.GetAllContents()))
		fail_reason = "its own shoes aren't in the bag"
		return BOT_GYM_FAIL
	if(!(locate(/obj/item/lightreplacer) in bot.GetAllContents()))
		fail_reason = "left the light replacer in the machine"
		return BOT_GYM_FAIL

/datum/bot_scenario/duty/janitor/dead_light
	name = "janitor replaces a dead light tube"
	desc = "A burnt-out tube on the wall and a light replacer in the bag. The janitor walks over and swaps it with the replacer in hand."
	layout = list(
		"#########",
		"#B....I.#",
		"#########")
	kit_backpack = list(/obj/item/lightreplacer)
	time_limit = 40 SECONDS
	var/obj/machinery/light/fixture

/datum/bot_scenario/duty/janitor/dead_light/setup()
	..()
	fixture = new(first_marker("I"))
	fixture.setDir(NORTH)
	fixture.status = LIGHT_BURNED
	fixture.update()

/datum/bot_scenario/duty/janitor/dead_light/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(fixture))
		fail_reason = "the light fixture is gone"
		return BOT_GYM_FAIL
	return fixture.status == LIGHT_OK ? BOT_GYM_PASS : BOT_GYM_PENDING
