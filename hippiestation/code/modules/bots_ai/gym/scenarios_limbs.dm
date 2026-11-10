// Bot Gym scenarios for a bot that's lost an arm: the hand it has (bot_human.dm use_a_working_hand()), and the arm put back on
// (goals/limb_replacement.dm). Layout letters: O an operating table, t a table with the surgery tools on it, a the arm.

/// The surgery tools on the table at "t", and an operating table at "O".
/datum/bot_scenario/proc/surgery_room()
	var/turf/tray = first_marker("t")
	for(var/path in list(/obj/item/scalpel, /obj/item/hemostat, /obj/item/retractor, /obj/item/cautery))
		place("s", new path(tray))
	place("O", new /obj/structure/table/optable(first_marker("O")))

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

/datum/bot_scenario/doctor_puts_arm_back
	name = "limbs: a doctor puts an arm back on somebody waiting on the operating table"
	desc = "Somebody's lost their right arm and lies on the operating table with it beside them. A doctor takes the tools off the tray, then the arm, and does the prosthetic replacement: incision, clamps, retractor, the arm."
	job = "Medical Doctor"
	layout = list(
		"########",
		"#B.t.O.#",
		"#......#",
		"########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/patient

/datum/bot_scenario/doctor_puts_arm_back/setup()
	surgery_room()

/datum/bot_scenario/doctor_puts_arm_back/post_spawn()
	patient = stand_in(first_marker("O"), "Arm Lessly")
	var/obj/item/bodypart/arm = patient.get_bodypart(BODY_ZONE_R_ARM)
	arm.drop_limb() //on to the table, under them
	patient.set_resting(TRUE, TRUE)
	var/obj/structure/table/optable/table = first_placed("O")
	table.check_patient()

/datum/bot_scenario/doctor_puts_arm_back/make_goal()
	return new /datum/bot_goal/operate/limb(patient)

/datum/bot_scenario/doctor_puts_arm_back/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return patient.get_bodypart(BODY_ZONE_R_ARM) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/one_arm_to_medbay
	name = "limbs: an arm gone, it takes the arm to the operating table and the doctor puts it back on"
	desc = "A bot's lost its right arm, which is lying a couple of tiles off. It picks the arm up, climbs on to the operating table, lies down and calls for somebody, and the doctor in the room comes with the tools and puts it back on."
	job = "Assistant"
	layout = list(
		"#########",
		"#B.a.O.t#",
		"#.....C.#",
		"#########")
	time_limit = 120 SECONDS
	var/mob/living/carbon/human/doctor
	var/obj/item/bodypart/arm

/datum/bot_scenario/one_arm_to_medbay/setup()
	surgery_room()

/datum/bot_scenario/one_arm_to_medbay/post_spawn()
	arm = bot.get_bodypart(BODY_ZONE_R_ARM)
	arm.drop_limb()
	arm.forceMove(first_marker("a"))
	brain.gym_scripted = FALSE //it calls for somebody (call_for())
	doctor = second_bot(first_marker("C"), "Doc Tor")
	doctor.mind.assigned_role = "Medical Doctor"

/datum/bot_scenario/one_arm_to_medbay/make_goal()
	var/obj/structure/table/optable/table = first_placed("O")
	return (bot.get_bodypart(BODY_ZONE_R_ARM) || QDELETED(arm)) ? null : new /datum/bot_goal/get_limb_back(BODY_ZONE_R_ARM, arm, table)

/datum/bot_scenario/one_arm_to_medbay/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot.get_bodypart(BODY_ZONE_R_ARM) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/limb_call_not_taken_unreachable
	name = "limbs: a doctor with no way to the operating table doesn't take the call for an arm"
	desc = "A bot's on the operating table with its arm beside it and calls for somebody. The only doctor is behind a door their ID doesn't open: they said they were coming, and never could."
	job = "Assistant"
	layout = list(
		"#########",
		"#B.a.O.t#",
		"#.......#",
		"####D####",
		"#...C...#",
		"#########")
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/doctor
	var/obj/item/bodypart/arm

/datum/bot_scenario/limb_call_not_taken_unreachable/setup()
	surgery_room()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/limb_call_not_taken_unreachable/post_spawn()
	arm = bot.get_bodypart(BODY_ZONE_R_ARM)
	arm.drop_limb()
	arm.forceMove(first_marker("a"))
	brain.gym_scripted = FALSE
	doctor = second_bot(first_marker("C"), "Doc Locked")
	doctor.mind.assigned_role = "Medical Doctor"

/datum/bot_scenario/limb_call_not_taken_unreachable/make_goal()
	var/obj/structure/table/optable/table = first_placed("O")
	return (bot.get_bodypart(BODY_ZONE_R_ARM) || QDELETED(arm)) ? null : new /datum/bot_goal/get_limb_back(BODY_ZONE_R_ARM, arm, table)

/datum/bot_scenario/limb_call_not_taken_unreachable/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/called = FALSE
	for(var/line in transcript)
		if(findtext(line, "taking a limb call"))
			fail_reason = "the doctor behind the locked door took the call"
			return BOT_GYM_FAIL
		if(findtext(line, "called for a limb"))
			called = TRUE
	return (called && world.time > start_time + 30 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/robot_arm_from_robotics
	name = "limbs: an arm burnt away, Robotics prints a robot arm and puts it on"
	desc = "A bot's right arm is gone with nothing left of it. It lies on Robotics' operating table and asks for a robot arm; the roboticist gets the tools, feeds the fabricator its metal, prints the arm and fits it."
	job = "Assistant"
	layout = list(
		"###########",
		"#B...O.t..#",
		"#.........#",
		"#.R....C..#",
		"#e........#",
		"###########")
	time_limit = 150 SECONDS
	var/mob/living/carbon/human/roboticist

/datum/bot_scenario/robot_arm_from_robotics/setup()
	surgery_room()
	place("R", new /obj/machinery/mecha_part_fabricator(first_marker("R")))
	place("e", new /obj/item/stack/sheet/metal/fifty(first_marker("e")))

/datum/bot_scenario/robot_arm_from_robotics/post_spawn()
	var/obj/item/bodypart/arm = bot.get_bodypart(BODY_ZONE_R_ARM)
	arm.drop_limb()
	qdel(arm) //burnt to nothing
	brain.gym_scripted = FALSE
	roboticist = second_bot(first_marker("C"), "Robo Ticist")
	roboticist.mind.assigned_role = "Roboticist"

/datum/bot_scenario/robot_arm_from_robotics/make_goal()
	var/obj/structure/table/optable/table = first_placed("O")
	return bot.get_bodypart(BODY_ZONE_R_ARM) ? null : new /datum/bot_goal/get_limb_back(BODY_ZONE_R_ARM, null, table)

/datum/bot_scenario/robot_arm_from_robotics/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/bodypart/arm = bot.get_bodypart(BODY_ZONE_R_ARM)
	return (arm?.status == BODYPART_ROBOTIC) ? BOT_GYM_PASS : BOT_GYM_PENDING
