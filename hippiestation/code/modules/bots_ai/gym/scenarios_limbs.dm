// Bot Gym scenarios for a bot that's lost an arm (bot_human.dm use_a_working_hand()).

/datum/bot_scenario/one_arm_picks_up
	name = "hands: an arm gone, the other one picks things up"
	desc = "A bot's right arm is gone and it's switched to that hand, with a wrench in the left. It's sent for a matter bin a few tiles off: it switches to the hand it has, puts the wrench away and picks the bin up."
	job = "Assistant"
	layout = list(
		"#######",
		"#B...G#",
		"#######")
	time_limit = 20 SECONDS

/datum/bot_scenario/one_arm_picks_up/setup()
	place("m", new /obj/item/stock_parts/matter_bin(first_marker("G")))

/datum/bot_scenario/one_arm_picks_up/post_spawn()
	var/obj/item/bodypart/arm = bot.get_bodypart(BODY_ZONE_R_ARM)
	arm?.drop_limb()
	qdel(arm)
	bot.put_in_hand(new /obj/item/wrench(bot), 1)
	bot.swap_hand(2)

/datum/bot_scenario/one_arm_picks_up/make_goal()
	var/obj/item/bin = first_placed("m")
	return (QDELETED(bin) || !isturf(bin.loc)) ? null : new /datum/bot_goal/take_item/exact(bin)

/datum/bot_scenario/one_arm_picks_up/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/bin = first_placed("m")
	return (!QDELETED(bin) && (bin in bot.held_items)) ? BOT_GYM_PASS : BOT_GYM_PENDING
