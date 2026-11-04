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

/datum/bot_scenario/puts_self_out
	name = "on fire: stop, drop and roll"
	desc = "A bot catches fire. It rolls on the floor until it's out, rather than walking on until it burns to death and lighting everyone it passes."
	layout = list(
		"#####",
		"#B..#",
		"#####")
	time_limit = 20 SECONDS

/datum/bot_scenario/puts_self_out/post_spawn()
	..()
	bot.adjust_fire_stacks(8)
	bot.IgniteMob()

/datum/bot_scenario/puts_self_out/issue_goal()
	return

/datum/bot_scenario/puts_self_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot.on_fire ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/fights_back
	time_limit = 25 SECONDS
	var/mob/living/carbon/human/assailant

/datum/bot_scenario/fights_back/issue_goal()
	return

/datum/bot_scenario/fights_back/post_spawn()
	..()
	assailant = stand_in(first_marker("C"), "Casey Assailant")
	addtimer(CALLBACK(src, PROC_REF(start_fight)), 2 SECONDS)

/datum/bot_scenario/fights_back/proc/start_fight()
	log_combat(assailant, bot, "punched")

/datum/bot_scenario/fights_back/with_a_toolbox
	name = "fight: swings what's in its hand, not its fists"
	desc = "Attacked with a toolbox in hand, the bot hits back with the toolbox."
	layout = list(
		"######",
		"#BC..#",
		"######")
	var/obj/item/storage/toolbox/mechanical/box

/datum/bot_scenario/fights_back/with_a_toolbox/post_spawn()
	..()
	box = new(bot)
	bot.put_in_hands(box)

/datum/bot_scenario/fights_back/with_a_toolbox/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "hitting [assailant] with"))
			return BOT_GYM_PASS
		if(findtext(line, "attacking [assailant]"))
			fail_reason = "punched them with a toolbox in its hand"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fights_back/runs_when_losing
	name = "fight: runs for it when it's losing"
	desc = "Badly hurt and attacked, the bot shouts for help and leaves the fight rather than standing and trading blows."
	layout = list(
		"######",
		"#BC..#",
		"######")

/datum/bot_scenario/fights_back/runs_when_losing/post_spawn()
	..()
	bot.adjustBruteLoss(90)

/datum/bot_scenario/fights_back/runs_when_losing/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "disengaging from [assailant]: running for it"))
			return BOT_GYM_PASS
		if(findtext(line, "attacking [assailant]"))
			fail_reason = "stayed and fought at [bot.health] health"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/// Plasma and oxygen on these tiles, and a light put to them.
/datum/bot_scenario/proc/start_fire(list/turf/open/tiles, plasma = 3)
	for(var/turf/open/T as anything in tiles)
		T.air.assert_gases(/datum/gas/plasma, /datum/gas/oxygen)
		T.air.moles[/datum/gas/plasma] = plasma
		T.air.moles[/datum/gas/oxygen] = 20
		T.air_update_turf()
		T.hotspot_expose(1000, 500)

/datum/bot_scenario/walks_out_of_the_flames
	name = "on fire in the flames: an engineer in its hardsuit walks out, then rolls"
	desc = "An engineer in the engineering hardsuit, which keeps out no heat, catches fire standing in a fire. It gets out of the flames and then puts itself out. One in a player's fire stood burning in the flames for fourteen seconds, went back in for an extinguisher, and died."
	layout = list(
		"##############################",
		"#............................#",
		"#.....................B......#",
		"#............................#",
		"##############################")
	job = "Station Engineer"
	time_limit = 40 SECONDS

/datum/bot_scenario/walks_out_of_the_flames/issue_goal()
	return

/datum/bot_scenario/walks_out_of_the_flames/post_spawn()
	..()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	var/obj/item/clothing/suit/space/hardsuit/engine/suit = new(bot)
	bot.equip_to_slot_or_del(suit, ITEM_SLOT_OCLOTHING)
	suit.ToggleHelmet()
	var/turf/start = first_marker("B")
	start_fire(list(start, get_step(start, EAST), get_step(start, NORTH), get_step(start, SOUTH)), 2) //the fire's to one side, as a fire is
	bot.adjust_fire_stacks(8)
	bot.IgniteMob()

/datum/bot_scenario/walks_out_of_the_flames/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/open/T = get_turf(bot)
	return (bot.on_fire || T.active_hotspot) ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/firelock_on_a_fire
	name = "firelock shut on a fire: an engineer doesn't prise it open"
	desc = "The way to where it's going is through a shut firelock with a fire behind it. An engineer with a crowbar, and no heat protection, leaves it shut. One prised two open on its way into a burning engineering bay, and died in there."
	layout = list(
		"###########",
		"#B..F....G#",
		"###########")
	job = "Station Engineer"
	kit_hands = list(/obj/item/crowbar)
	time_limit = 15 SECONDS

/datum/bot_scenario/firelock_on_a_fire/post_spawn()
	..()
	keep_burning()

/datum/bot_scenario/firelock_on_a_fire/proc/keep_burning()
	var/turf/door = first_marker("F")
	var/list/turf/open/fire = list()
	for(var/turf/open/T in block(locate(door.x + 1, door.y, door.z), get_turf(first_marker("G"))))
		if(!T.active_hotspot)
			fire += T
	start_fire(fire, 5)

/datum/bot_scenario/firelock_on_a_fire/check()
	var/obj/machinery/door/firedoor/F = first_placed("F")
	if(QDELETED(F) || !F.density)
		fail_reason = "the firelock was opened on the fire"
		return BOT_GYM_FAIL
	if(bot_lost())
		return BOT_GYM_FAIL
	keep_burning()
	return world.time >= start_time + 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING
