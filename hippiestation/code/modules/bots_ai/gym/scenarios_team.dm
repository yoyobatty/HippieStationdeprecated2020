// Bot Gym scenarios for repairs as a team (goals/team_repairs.dm). Reached by name where the fix adds something, so a build
// without it compiles for the A/B.

/// A bot that runs its own duties, its next look at each due now, with a helper's or a shirker's temperament.
/datum/bot_scenario/proc/free_with_traits(datum/bot_brain/B, sociability, diligence)
	B.gym_scripted = FALSE
	B.greytider = FALSE //rolled for two assistants in three: one's never a helper
	B.playstyle = BOT_STYLE_NORMAL //a role-hopper off covering for a doctor isn't an assistant any more
	B.standing_in_for = null
	B.sociability = sociability
	B.diligence = diligence
	B.duties = null //worked out again from the traits just set
	B.my_duties(BOT_DUTY_WORK)
	for(var/D in B.duty_next_check)
		B.duty_next_check[D] = world.time + 1 SECONDS

/datum/bot_scenario/team_hull
	name = "team: a helpful assistant patches a hole in the hull"
	desc = "An assistant who's sociable and diligent, suited up with rods and floor tiles in the bag, in a room with a hole to space. Nobody tells it to: it patches the hole, as an engineer would. Repairs are a team job (the user's ruling, 2026-11-11)."
	job = "Assistant"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/stack/rods/ten, /obj/item/stack/tile/plasteel)
	layout = list(
		"#########",
		"#B......#",
		"#.......#",
		"#....S..#",
		"#.......#",
		"#########")
	var/turf/hole
	var/helper_traits = 0.8

/datum/bot_scenario/team_hull/issue_goal()
	return

/datum/bot_scenario/team_hull/setup()
	hole = first_marker("S")
	bot_note_breach(hole)

/datum/bot_scenario/team_hull/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(bot), ITEM_SLOT_MASK)
	bot.equip_to_slot_or_del(new /obj/item/clothing/suit/space/eva(bot), ITEM_SLOT_OCLOTHING)
	bot.equip_to_slot_or_del(new /obj/item/clothing/head/helmet/space/eva(bot), ITEM_SLOT_HEAD)
	var/obj/item/tank/internals/emergency_oxygen/T = new(bot)
	bot.equip_to_slot_or_del(T, ITEM_SLOT_SUITSTORE)
	bot.internal = T
	free_with_traits(brain, helper_traits, helper_traits)

/datum/bot_scenario/team_hull/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return istype(hole, /turf/open/space) ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/team_hull/shirker
	name = "team: an assistant who isn't the helping sort leaves the hole to Engineering"
	desc = "The same, with an assistant who's neither sociable nor diligent: it's not its job, and it leaves it."
	time_limit = 25 SECONDS
	helper_traits = 0.3

/datum/bot_scenario/team_hull/shirker/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!istype(hole, /turf/open/space))
		fail_reason = "patched it"
		return BOT_GYM_FAIL
	return world.time - start_time >= 20 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/team_fire
	name = "team: a helpful assistant who sees a fire gets an extinguisher and puts it out"
	desc = "A fire at the far end of the room, an extinguisher cabinet by the door. A sociable, diligent assistant fights it from a safe distance, as an engineer does, where it used to only shout about it."
	job = "Assistant"
	time_limit = 45 SECONDS
	layout = list(
		"##############",
		"#E...........#",
		"#B...........#",
		"#............#",
		"##############")

/datum/bot_scenario/team_fire/issue_goal()
	return

/datum/bot_scenario/team_fire/post_spawn()
	free_with_traits(brain, 0.8, 0.8)
	for(var/turf/open/T in range(1, locate(bot.x + 10, bot.y, bot.z)))
		T.air.moles[/datum/gas/plasma] = 15
		T.air.moles[/datum/gas/oxygen] = 30
		T.air_update_turf()
		T.hotspot_expose(1000, 500)

/datum/bot_scenario/team_fire/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("going to put out the fire") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/team_call
	name = "team: a call for engineers brings every free engineer and a helpful assistant"
	desc = "Somebody shouts that there's a hull breach and they need engineers. Both engineers set off, and so does the sociable, diligent assistant; the assistant who isn't the helping sort stays put. It used to be the nearest engineer alone."
	job = "Station Engineer"
	time_limit = 15 SECONDS
	layout = list(
		"###########",
		"#B.E.....C#",
		"#.........#",
		"#.h.a.....#",
		"###########")
	var/mob/living/carbon/human/engineer_two
	var/mob/living/carbon/human/helper
	var/mob/living/carbon/human/shirker
	var/datum/bot_request/request

/datum/bot_scenario/chat/team_call/post_spawn()
	..()
	// All idle (scripted: no errands of their own to be busy with), so all free.
	engineer_two = second_bot(first_marker("E"), "Engi Two")
	engineer_two.mind.assigned_role = "Station Engineer"
	helper = second_bot(first_marker("h"), "Hal Helper")
	helper.mind.assigned_role = "Assistant"
	helper.bot_brain.greytider = FALSE
	helper.bot_brain.sociability = 0.8
	helper.bot_brain.diligence = 0.8
	shirker = second_bot(first_marker("a"), "Sid Shirker")
	shirker.mind.assigned_role = "Assistant"
	shirker.bot_brain.greytider = FALSE
	shirker.bot_brain.sociability = 0.3
	shirker.bot_brain.diligence = 0.3
	addtimer(CALLBACK(src, PROC_REF(make_call)), 2 SECONDS)

/datum/bot_scenario/chat/team_call/proc/make_call()
	visitor_says("Hull breach in here, we need engineers!")

/datum/bot_scenario/chat/team_call/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_request_kind/engineer/K = locate() in GLOB.bot_request_kinds
	if(!request)
		request = bot_open_request_from(visitor, K)
		return BOT_GYM_PENDING
	if(world.time - start_time < 8 SECONDS)
		return BOT_GYM_PENDING
	var/list/took = ("takers" in request.vars) ? request.vars["takers"] : list(request.taken_by?.owner?.real_name)
	log_line("took the call: [jointext(took, ", ")]")
	if(shirker.real_name in took)
		fail_reason = "the assistant who isn't the helping sort went"
		return BOT_GYM_FAIL
	if(!(bot.real_name in took) || !(engineer_two.real_name in took) || !(helper.real_name in took))
		fail_reason = "only [jointext(took, ", ")] went"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/team_fetch
	name = "team: a helpful assistant brings metal to where an engineer is patching a hole"
	desc = "An engineer sets about a hole in the floor with nothing in its bag; the only metal in reach is across the room. A sociable, diligent assistant with metal in its bag takes it over and leaves it by the hole for the engineer, and says so."
	job = "Station Engineer"
	time_limit = 40 SECONDS
	layout = list(
		"###############",
		"#B.....S.....q#",
		"#.............#",
		"#.......h.....#",
		"###############")
	var/turf/hole
	var/mob/living/carbon/human/helper

/datum/bot_scenario/team_fetch/setup()
	hole = first_marker("S")
	bot_note_breach(hole)
	new /obj/item/stack/sheet/metal/ten(first_marker("q"))

/datum/bot_scenario/team_fetch/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(bot), ITEM_SLOT_MASK)
	bot.equip_to_slot_or_del(new /obj/item/clothing/suit/space/eva(bot), ITEM_SLOT_OCLOTHING)
	bot.equip_to_slot_or_del(new /obj/item/clothing/head/helmet/space/eva(bot), ITEM_SLOT_HEAD)
	var/obj/item/tank/internals/emergency_oxygen/T = new(bot)
	bot.equip_to_slot_or_del(T, ITEM_SLOT_SUITSTORE)
	bot.internal = T
	helper = second_bot(first_marker("h"), "Hal Helper")
	helper.mind.assigned_role = "Assistant"
	helper.equip_to_slot_or_del(new /obj/item/stack/sheet/metal/ten(helper), ITEM_SLOT_BACKPACK)
	free_with_traits(helper.bot_brain, 0.8, 0.8)

/datum/bot_scenario/team_fetch/make_goal()
	return new /datum/bot_goal/patch_hull(hole)

/datum/bot_scenario/team_fetch/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("by the work at") ? BOT_GYM_PASS : BOT_GYM_PENDING
