// What a bot knows of where things are (bot_knowledge.dm): where things are kept, and what it has seen, but not what it hasn't.

/datum/bot_scenario/knows_kept_not_unseen
	name = "knowledge: after a screwdriver it goes where one's kept, not for a nearer one dropped out of sight"
	desc = "Bots used to know where every item on the station was. One dropped behind walls since the round began isn't something anybody knows of."
	time_limit = 30 SECONDS
	// the kept one near (arenas run side by side, and another's is a candidate too), the dropped one nearer, behind the wall
	layout = list(
		"#########",
		"#k...B..#",
		"#######.#",
		"#######.#",
		"#....q..#",
		"#########")
	var/obj/item/screwdriver/kept
	var/obj/item/screwdriver/dropped

/datum/bot_scenario/knows_kept_not_unseen/setup()
	kept = new(first_marker("k"))
	place("k", kept)

/datum/bot_scenario/knows_kept_not_unseen/make_goal()
	if(goal_attempts > 1)
		return null
	// dropped after the arena became the "map": nearer as the crow flies, behind the walls
	if(!dropped)
		dropped = new(first_marker("q"))
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	return get

/datum/bot_scenario/knows_kept_not_unseen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	if(dropped in carried)
		return BOT_GYM_FAIL
	return (kept in carried) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/knows_what_it_sees
	name = "knowledge: after a screwdriver it takes the nearer one it can see lying about"
	desc = "Something dropped since the round began is known to whoever sees it."
	time_limit = 20 SECONDS
	layout = list(
		"###############",
		"#k........q..B#",
		"###############")
	var/obj/item/screwdriver/kept
	var/obj/item/screwdriver/dropped

/datum/bot_scenario/knows_what_it_sees/setup()
	kept = new(first_marker("k"))
	place("k", kept)

/datum/bot_scenario/knows_what_it_sees/make_goal()
	if(goal_attempts > 1)
		return null
	if(!dropped)
		dropped = new(first_marker("q"))
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	return get

/datum/bot_scenario/knows_what_it_sees/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	if(kept in carried)
		return BOT_GYM_FAIL
	return (dropped in carried) ? BOT_GYM_PASS : BOT_GYM_PENDING

// Layout letter Y: a YouTool.
/datum/bot_scenario/knows_what_machines_sell
	name = "knowledge: with no screwdriver about, it buys one from the YouTool"
	desc = "Everybody knows what the vending machines sell. Nothing lying about and nothing in a locker isn't the end of it."
	job = "Assistant"
	time_limit = 30 SECONDS
	layout = list(
		"##########",
		"#B......Y#",
		"##########")

/datum/bot_scenario/knows_what_machines_sell/setup()
	for(var/turf/T in markers["Y"])
		place("Y", new /obj/machinery/vending/tool(T))

/datum/bot_scenario/knows_what_machines_sell/post_spawn()
	give_job_id()

/datum/bot_scenario/knows_what_machines_sell/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/knows_what_machines_sell/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/screwdriver) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/knows_what_machines_sell/sold_out
	name = "knowledge: a YouTool it found sold out, it doesn't go back to"
	desc = "What a machine has left is found out at the machine. Sold out of screwdrivers, it goes for the one kept further off, and doesn't walk back to the machine for another look."
	time_limit = 40 SECONDS
	layout = list(
		"#############",
		"#k........BY#",
		"#############")
	var/obj/item/screwdriver/kept

/datum/bot_scenario/knows_what_machines_sell/sold_out/setup()
	. = ..()
	var/obj/machinery/vending/V = locate() in first_marker("Y")
	for(var/datum/data/vending_product/R in V.product_records)
		if(R.product_path == /obj/item/screwdriver)
			R.amount = 0
	kept = new(first_marker("k"))
	place("k", kept)

/datum/bot_scenario/knows_what_machines_sell/sold_out/make_goal()
	if(goal_attempts > 2)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/knows_what_machines_sell/sold_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!(kept in bot.GetAllContents()))
		return BOT_GYM_PENDING
	if(!length(brain.sold_out_seen))
		fail_reason = "went for the kept one without trying the machine beside it"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/knows_kept_not_unseen/take_in_hand
	name = "knowledge: asked to take a screwdriver in hand, it goes where one's kept, not for a nearer one dropped out of sight"
	desc = "The same for an errand that wants the thing in a hand (goals/take_item.dm), as the janitor's mop and the nanite disks do."

/datum/bot_scenario/knows_kept_not_unseen/take_in_hand/make_goal()
	if(goal_attempts > 1)
		return null
	if(!dropped)
		dropped = new(first_marker("q"))
	return new /datum/bot_goal/take_item(/obj/item/screwdriver)

// Layout letter h: a second bot, who's seen the screwdriver.
/datum/bot_scenario/asks_around
	name = "knowledge: knowing of no screwdriver, it asks on the radio and goes where another bot says it saw one"
	desc = "Nothing kept, nothing in sight. It asks \"anyone seen a screwdriver?\", the one who saw one dropped round the corner says where, and it goes and gets it."
	time_limit = 40 SECONDS
	layout = list(
		"###########",
		"#B.......h#",
		"#########.#",
		"#q........#",
		"###########")
	var/obj/item/screwdriver/dropped
	var/mob/living/carbon/human/helper

/datum/bot_scenario/asks_around/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/radio/headset(bot), ITEM_SLOT_EARS)
	helper = second_bot(first_marker("h"), "Helpful Hal")
	helper.equip_to_slot_or_del(new /obj/item/radio/headset(helper), ITEM_SLOT_EARS)
	dropped = new(first_marker("q")) //after the arena became the "map": nobody knows of it but who sees it
	helper.bot_brain?.note_seen(dropped)

/datum/bot_scenario/asks_around/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/asks_around/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (dropped in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/tells_where_to_get
	name = "knowledge: asked \"anyone seen a crowbar?\", it says where there's one"
	desc = "Somebody asks the room. A bot that knows of a crowbar, kept or seen, says where; one that knows of a machine that sells them says that instead."
	layout = list(
		"##########",
		"#B.C...c.#",
		"##########")

/datum/bot_scenario/chat/tells_where_to_get/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Anyone seen a crowbar?"), 2 SECONDS)

/datum/bot_scenario/chat/tells_where_to_get/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in spoken())
		if(findtext(line, "Bot Gym Arena"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

// Layout letter V is a cola machine (bot_gym.dm), which sells bottles of water: /obj/item/reagent_containers/glass/beaker/waterbottle.
/datum/bot_scenario/knows_what_machines_sell/not_bottled_water
	name = "knowledge: a chemist after a beaker doesn't buy bottled water"
	desc = "The game files a bottle of water under beakers. A chemist with no beaker went to the nearest drinks machine and bought one, found it full of water, and gave the brew up: 56 bottles in 12 shifts."
	job = "Chemist"
	time_limit = 15 SECONDS
	layout = list(
		"########",
		"#B....V#",
		"########")

/// A beaker for a fresh brew, as the dispenser steps ask for one. `empty_only` by name: it's part of the fix.
/datum/bot_scenario/knows_what_machines_sell/not_bottled_water/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/reagent_containers/glass/beaker
	get.lawful = TRUE
	if("empty_only" in get.vars)
		get.vars["empty_only"] = TRUE
	return get

/datum/bot_scenario/knows_what_machines_sell/not_bottled_water/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(locate(/obj/item/reagent_containers/glass/beaker/waterbottle) in bot.GetAllContents())
		fail_reason = "bought a bottle of water for a beaker"
		return BOT_GYM_FAIL
	return world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/knows_what_machines_sell/not_bottled_water/empty_one
	name = "knowledge: a chemist after a beaker takes an empty one"
	desc = "A beaker somebody's left half full on the side, and an empty one further off. For a fresh brew it's the empty one: it picked up the nearest, found something in it, and gave the brew up."
	time_limit = 30 SECONDS
	layout = list(
		"#########",
		"#B.h...e#",
		"#########")
	var/obj/item/reagent_containers/glass/beaker/half_full
	var/obj/item/reagent_containers/glass/beaker/empty

/datum/bot_scenario/knows_what_machines_sell/not_bottled_water/empty_one/setup()
	. = ..()
	half_full = new(first_marker("h"))
	half_full.reagents.add_reagent(/datum/reagent/water, 20)
	empty = new(first_marker("e"))

/datum/bot_scenario/knows_what_machines_sell/not_bottled_water/empty_one/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	if(half_full in carried)
		fail_reason = "took the beaker with something in it"
		return BOT_GYM_FAIL
	return (empty in carried) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fetch_past_bad_air
	name = "knowledge: the nearest one being in a room with no air, it goes for the next"
	desc = "A screwdriver three tiles off behind a door, in a room with no air, and another further down the corridor. Any fetch for something in air it can't breathe is turned down, and it turned the whole errand down for the nearest: a doctor after a scalpel never looked at the one on the next table."
	job = "Assistant"
	time_limit = 30 SECONDS
	layout = list(
		"############",
		"#vvD.B....s#",
		"############")
	var/obj/item/screwdriver/airless_one
	var/obj/item/screwdriver/other

/datum/bot_scenario/fetch_past_bad_air/setup()
	airless_one = new(first_marker("v"))
	other = new(first_marker("s"))

/datum/bot_scenario/fetch_past_bad_air/make_goal()
	if(goal_attempts > 2)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/fetch_past_bad_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	if(airless_one in carried)
		fail_reason = "went into the room with no air for it"
		return BOT_GYM_FAIL
	return (other in carried) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/round_parked_mule
	name = "walking: a parked MULE in the way is walked round"
	desc = "Something to fetch straight down the room, a MULE parked on the line to it, and open floor beside. Nobody swaps places with a MULE or pushes one, and the route was planned through it all the same: three walks into it, the errand given up, and the next one planned the same way."
	job = "Assistant"
	time_limit = 30 SECONDS
	layout = list(
		"#########",
		"#B..M..s#",
		"#.......#",
		"#########")
	var/obj/item/screwdriver/wanted
	var/mob/living/simple_animal/bot/mulebot/mule

/datum/bot_scenario/round_parked_mule/setup()
	wanted = new(first_marker("s"))
	mule = place("M", new /mob/living/simple_animal/bot/mulebot(first_marker("M")))
	mule.auto_return = FALSE
	mule.home_destination = null

/datum/bot_scenario/round_parked_mule/make_goal()
	if(goal_attempts > 2)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/round_parked_mule/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("stuck heading to"))
		fail_reason = "walked into the MULE"
		return BOT_GYM_FAIL
	return (wanted in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING
