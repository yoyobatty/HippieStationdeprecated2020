// Bot Gym scenarios for human-like behaviour (bot_human.dm). Each one reproduces something that
// looked robotic in a real round's telemetry. Every scenario also fails on the forbidden tells
// (tool not in hand, teleported items, ...), see /datum/bot_scenario/var/forbidden_tells.

/datum/bot_scenario/jaws_from_backpack
	name = "jaws of life drawn from the backpack"
	desc = "A locked, powered airlock and no access. The jaws of life start in the backpack and must be drawn into the hand before prying (a real round used them off the belt 28 times)."
	layout = list(
		"#########",
		"#B..D..G#",
		"#########")
	kit_backpack = list(/obj/item/crowbar/power)

/datum/bot_scenario/jaws_from_backpack/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/locker_take_only_gloves
	name = "locker: take the gloves, leave the toolbox"
	desc = "Sent for insulated gloves; the locker also holds a toolbox. A person takes what they came for (a real round's bot took the toolbox too)."
	layout = list(
		"#########",
		"#B...L..#",
		"#########")
	time_limit = 30 SECONDS

/datum/bot_scenario/locker_take_only_gloves/setup()
	var/obj/structure/closet/C = first_placed("L")
	new /obj/item/clothing/gloves/color/yellow(C)
	new /obj/item/storage/toolbox/electrical(C)

/datum/bot_scenario/locker_take_only_gloves/make_goal()
	return new /datum/bot_goal/acquire_tool(/obj/item/clothing/gloves/color/yellow)

/datum/bot_scenario/locker_take_only_gloves/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/obj/item/storage/toolbox/T = locate() in bot.GetAllContents()
	if(T)
		fail_reason = "took the toolbox as well"
		return BOT_GYM_FAIL
	if(locate(/obj/item/clothing/gloves/color/yellow) in bot.GetAllContents())
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/three_airlocks
	name = "three airlocks in a row, human pace"
	desc = "Walk through three consecutive airlocks without stopping dead at each (a real round had 21 door stops) or freezing 3s+."
	layout = list(
		"###########",
		"#B.D.D.D.G#",
		"###########")
	time_limit = 20 SECONDS
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "idle_3s")
