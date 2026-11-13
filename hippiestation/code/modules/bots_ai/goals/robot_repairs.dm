// Robotics repairs (the user's ask, 2026-11-12: "full science", Robotics: "repair borgs and mechs").
//
//  - A cyborg that's been knocked about comes to Robotics and says so on the radio (silicon.dm, seek_repairs()), and a roboticist takes a
//    lit welder to it: thirty off its dents a go (robot/attackby()). Its burns aren't done: the wires only come out from under the cover
//    with its cell out (wiresexposed), which shuts it down, and a player does that only for a borg that's gone quiet anyway.
//  - An exosuit left in Robotics, or anywhere its doors let it reach, gets the welder too: ten a go (mecha/attackby()).

/// Dents in a cyborg worth a roboticist's welder.
#define BOT_BORG_DENTED 20

/datum/bot_brain
	var/robots_repaired = 0
	var/robot_repair_rest_until = 0

/// Something of Robotics' to weld: a dented cyborg that's come in or is nearby, or a damaged exosuit nobody's in.
/datum/bot_brain/proc/robot_needing_repair()
	for(var/mob/living/silicon/robot/R in GLOB.silicon_mobs)
		if(R.stat == DEAD || R.z != my_z() || R.getBruteLoss() < BOT_BORG_DENTED || taken_by_another(R))
			continue
		if(gym_run ? get_area(R) != get_area(owner) : !(in_robotics(R) || get_dist(R, owner) <= 7))
			continue
		if(can_walk_lawfully_to(R))
			return R
	for(var/obj/mecha/M in GLOB.mechas_list)
		if(QDELETED(M) || M.occupant || M.z != my_z() || M.obj_integrity >= M.max_integrity * 0.8 || taken_by_another(M))
			continue
		if(gym_run ? get_area(M) != get_area(owner) : !in_robotics(M))
			continue
		if(can_walk_lawfully_to(M))
			return M
	return null

/datum/bot_duty/repair_robots
	name = "repairing cyborgs and exosuits"
	jobs = list("Roboticist", "Research Director")
	tier = BOT_DUTY_URGENT
	priority = 8
	interval_min = 100
	interval_max = 300

/datum/bot_duty/repair_robots/try_start(datum/bot_brain/bot)
	if(world.time < bot.robot_repair_rest_until || bot.gone_loud())
		return FALSE
	var/atom/A = bot.robot_needing_repair()
	return A ? bot.assign_goal(new /datum/bot_goal/repair_robot(A)) : FALSE

/datum/bot_goal/repair_robot
	lawful = TRUE
	exclusive = TRUE
	doing = "welding a cyborg or an exosuit back into shape"

/datum/bot_goal/repair_robot/New(atom/A)
	. = ..()
	target = A

/datum/bot_goal/repair_robot/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/repair_robot/on_give_up(datum/bot_brain/bot)
	bot.robot_repair_rest_until = world.time + 2 MINUTES

/datum/bot_goal/repair_robot/proc/still_damaged()
	var/mob/living/silicon/robot/R = target
	if(istype(R))
		return R.stat != DEAD && R.getBruteLoss() > 0
	var/obj/mecha/M = target
	return istype(M) && !QDELETED(M) && M.obj_integrity < M.max_integrity

/// Dents in a cyborg, or the armour an exosuit's lost.
/datum/bot_goal/repair_robot/proc/damage_left()
	var/mob/living/silicon/robot/R = target
	if(istype(R))
		return R.getBruteLoss()
	var/obj/mecha/M = target
	return istype(M) ? M.max_integrity - M.obj_integrity : 0

/datum/bot_goal/repair_robot/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	var/mob/living/carbon/human/H = bot.owner
	if(QDELETED(target))
		return GOAL_STEP_FAIL
	if(!still_damaged())
		bot.robots_repaired++
		bot_tally("robots repaired")
		bot_log(bot, "ROBOTICS: [target] is fixed up")
		if(!bot.gym_scripted && prob(40))
			bot_say(H, pick("There, good as new.", "That's the dents out.", "All patched up."))
		return GOAL_STEP_SUCCESS
	var/obj/item/weldingtool/W = locate() in H.GetAllContents(/obj/item/weldingtool)
	if(!W)
		if(++step.tries > 4)
			return GOAL_STEP_FAIL
		var/datum/bot_goal/acquire_item_type/fetch = new
		fetch.item_type = /obj/item/weldingtool
		fetch.lawful = TRUE
		return bot.suspend_goal_for(fetch) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	if(!H.Adjacent(target))
		return step.go_to(bot, target)
	if(!W.isOn())
		if(!W.get_fuel())
			return GOAL_STEP_FAIL
		bot.toggle_in_hand(W)
		return step.again(bot, 5)
	if(!bot.ready_in_hand(W))
		return GOAL_STEP_FAIL
	H.face_atom(target)
	var/before = damage_left()
	bot.use_tool_on(W, target) //robot/attackby() or mecha/attackby(): the welder on it, not on harm
	if(before == damage_left() && ++step.tries > 8)
		return GOAL_STEP_FAIL
	return step.again(bot, 1 SECONDS)

#undef BOT_BORG_DENTED

// ---------------------------------------------------------------------------------------------
// The cyborg's side
// ---------------------------------------------------------------------------------------------

/datum/bot_silicon/borg
	var/next_repair_call = 0
	var/turf/repair_spot

/// Badly dented: to Robotics, a word on the radio on the way, and it waits there till a roboticist's welder has been over it. TRUE while
/// that's what it's doing.
/datum/bot_silicon/borg/proc/seek_repairs()
	var/mob/living/silicon/robot/R = owner
	if(R.getBruteLoss() < R.maxHealth * 0.3)
		repair_spot = null
		return FALSE
	if(!repair_spot || repair_spot.z != R.z)
		var/list/spots = bot_borg_post_turfs(/area/science/robotics, R.z)
		repair_spot = length(spots) ? pick(spots) : null
	if(!repair_spot)
		return FALSE
	if(world.time >= next_repair_call)
		next_repair_call = world.time + 3 MINUTES
		note("going to Robotics for repairs ([round(R.getBruteLoss())] brute)")
		say_it(";Robotics, [R.name] here. I've taken a beating, coming to you for repairs.")
	if(istype(get_area(R), /area/science/robotics))
		return TRUE //there: waiting on the welder
	if(!length(route) && !go_to(repair_spot))
		return FALSE
	keep_walking()
	return TRUE
