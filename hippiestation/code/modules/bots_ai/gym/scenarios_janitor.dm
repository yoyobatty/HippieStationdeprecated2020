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

/datum/bot_scenario/duty/janitor/water_it_can_reach
	name = "janitor fills its bucket where it can get to"
	desc = "The bucket's empty. The nearer water tank is behind a door the janitor's ID doesn't open; the other is down the corridor. It goes to the one down the corridor, without first trying the door."
	layout = list(
		"###############",
		"#KD.BMU.o.o..K#",
		"###############")
	bucket_water = 0
	time_limit = 120 SECONDS

/datum/bot_scenario/duty/janitor/water_it_can_reach/setup()
	..()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/duty/janitor/water_it_can_reach/check()
	for(var/line in transcript)
		if(findtext(line, "giving up on /datum/bot_goal/fill_bucket"))
			fail_reason = "went for the water behind the locked door first"
			return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/duty/janitor/bucket_off_head
	name = "janitor wets the mop with its hands full and keeps the water in the bucket"
	desc = "Bucket of water in one hand, the light replacer in the other, the mop in its bag, and blood down the corridor. Getting the mop out to wet it, it put the bucket away on its head, water and all, and had none left to mop with."
	layout = list(
		"###########",
		"#B...o.o..#",
		"###########")
	kit_backpack = list(/obj/item/mop)

/datum/bot_scenario/duty/janitor/bucket_off_head/post_spawn()
	..()
	var/obj/item/reagent_containers/glass/bucket/B = new(bot)
	B.reagents.add_reagent(/datum/reagent/water, 50)
	bot.put_in_active_hand(B)
	bot.put_in_inactive_hand(new /obj/item/lightreplacer(bot))

/datum/bot_scenario/duty/janitor/bucket_off_head/check()
	if(istype(bot?.head, /obj/item/reagent_containers/glass/bucket))
		fail_reason = "put the bucket on its head"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/duty/janitor/no_water
	name = "janitor with no water to be had leaves the mess, and doesn't give it up again and again"
	desc = "A mop, an empty bucket and blood, and the only water tank behind a door its ID doesn't open. It took up each mess, gave it up for want of water, and took up the next: 29 times in one shift. It leaves them until there's water."
	layout = list(
		"#############",
		"#KD.BMU.o.o.#",
		"#############")
	bucket_water = 0
	time_limit = 30 SECONDS

/datum/bot_scenario/duty/janitor/no_water/setup()
	..()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/duty/janitor/no_water/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "no water for the mop bucket"))
			fail_reason = "took up a mess with no water to be had"
			return BOT_GYM_FAIL
	return world.time > start_time + 25 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/janitor/mop_out_of_reach
	name = "janitor with the only mop behind a door it can't open leaves the mess, and doesn't give it up again and again"
	desc = "The mop's behind a door its ID doesn't open, as when it's left in the Brig. It took up each mess, set off for the mop, found no way there and gave the mess up, then took up the next."
	layout = list(
		"#############",
		"#MD.BU.o.o..#",
		"#############")
	time_limit = 30 SECONDS

/datum/bot_scenario/duty/janitor/mop_out_of_reach/setup()
	..()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/duty/janitor/mop_out_of_reach/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "nowhere to get a mop"))
			fail_reason = "took up a mess with no mop it could get to"
			return BOT_GYM_FAIL
	return world.time > start_time + 25 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/janitor/bucket_out_of_reach
	name = "janitor with the only bucket behind a door it can't open leaves the mess, and doesn't give it up again and again"
	desc = "A dry mop to hand and blood about, and the bucket behind a door its ID doesn't open. It took up each mess, set off for the bucket, found no way there and gave the mess up."
	layout = list(
		"#############",
		"#UD.BM.o.o.K#",
		"#############")
	bucket_water = 0
	time_limit = 30 SECONDS

/datum/bot_scenario/duty/janitor/bucket_out_of_reach/setup()
	..()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/duty/janitor/bucket_out_of_reach/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "nowhere to get a bucket"))
			fail_reason = "took up a mess with no bucket it could get to"
			return BOT_GYM_FAIL
	return world.time > start_time + 25 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

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
