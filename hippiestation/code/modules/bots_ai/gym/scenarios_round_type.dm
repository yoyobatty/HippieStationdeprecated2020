// Bot Gym scenarios for what the round type's antagonists turned up once bots were playing them (bot_round_type.dm): a team on one side,
// and the guns they carry.

/// A side of its own for these, standing in for the game's teams (the operatives, the cult, the revolution): it's the team the game
/// keeps that on_my_side() (bot_brain.dm) goes by.
/datum/team/bot_gym_side
	name = "the gym's side"

/datum/antagonist/bot_gym_side
	name = "gym side"
	show_in_antagpanel = FALSE
	show_name_in_check_antagonists = FALSE
	var/datum/team/bot_gym_side/side

/datum/antagonist/bot_gym_side/create_team(datum/team/bot_gym_side/new_team)
	side = new_team || new /datum/team/bot_gym_side

/datum/antagonist/bot_gym_side/get_team()
	return side

/// The bot and the griefer on one side.
/datum/bot_scenario/griefed/proc/same_side()
	if(!bot.mind)
		bot.mind_initialize()
	if(!griefer.mind)
		griefer.mind_initialize()
	var/datum/antagonist/bot_gym_side/mine = new
	bot.mind.add_antag_datum(mine)
	griefer.mind.add_antag_datum(new /datum/antagonist/bot_gym_side, mine.side)

/datum/bot_scenario/griefed/teammate_at_work
	name = "teams: one doesn't step in against its own"
	desc = "Its teammate is beating a crewman in front of it. Five operatives killed each other: one saw another sword a crewman, stepped in for the crewman the way the crew do, and the rest joined in."
	layout = list(
		"#################",
		"#...............#",
		"#..B...VC.......#",
		"#...............#",
		"#################")
	time_limit = 20 SECONDS
	var/mob/living/carbon/human/victim
	var/blows = 0

/datum/bot_scenario/griefed/teammate_at_work/post_spawn()
	..()
	brain.nerve = 0.9 //somebody who'd step in for anybody else
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	victim = stand_in(first_marker("V"), "Vic Victim")
	same_side()

/datum/bot_scenario/griefed/teammate_at_work/grief()
	keep_at_it("beat", 15)

/datum/bot_scenario/griefed/teammate_at_work/proc/beat()
	griefer_hand(INTENT_HARM, victim)
	blows++
	return victim.stat == CONSCIOUS

/datum/bot_scenario/griefed/teammate_at_work/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.attacker == griefer || bot_transcript_has("stepping in"))
		fail_reason = "stepped in against its own side"
		return BOT_GYM_FAIL
	return blows >= 5 && world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/teammate_at_work/stray_blow
	name = "teams: a stray blow from its own doesn't start a fight"
	desc = "Its teammate catches it by mistake. It says so, and carries on: nobody turns on their own over that."

/datum/bot_scenario/griefed/teammate_at_work/stray_blow/beat()
	griefer_hand(INTENT_HARM, blows % 2 ? victim : bot)
	blows++
	return victim.stat == CONSCIOUS

/datum/bot_scenario/griefed/teammate_at_work/stray_blow/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.attacker == griefer)
		fail_reason = "turned on its own side over a stray blow"
		return BOT_GYM_FAIL
	return blows >= 6 && world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/op_resists
	name = "operatives: an officer's blow is a fight, not an arrest"
	desc = "Security hits an operative. A crewman goes quietly; an operative fights. Five with submachine guns stood still for the tasers and cuffs, because the bots took any officer's blow for an arrest unless they were a traitor or a revolutionary."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	griefer_name = "Olly Officer"
	griefer_job = "Security Officer"
	time_limit = 12 SECONDS

/datum/bot_scenario/griefed/op_resists/post_spawn()
	..()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	var/datum/bot_nuke_team/team = new
	team.members += brain
	brain.op_team = team

/datum/bot_scenario/griefed/op_resists/grief()
	griefer_hand(INTENT_HARM)

/datum/bot_scenario/griefed/op_resists/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.state == BOT_STATE_COMBAT && brain.attacker == griefer ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/op_resists/release_run()
	brain.op_team = null
	..()

/datum/bot_scenario/op_arms_the_nuke
	name = "operatives: the disk in, the code, the timer, armed"
	desc = "An operative at the nuke with the disk in its bag. None had ever got this far alive, so the panel had never been worked."
	layout = list(
		"########",
		"#B...N.#",
		"########")
	time_limit = 40 SECONDS
	var/obj/machinery/nuclearbomb/syndicate/nuke
	var/obj/item/disk/nuclear/disk
	var/armed = FALSE

/datum/bot_scenario/op_arms_the_nuke/issue_goal()
	return

/datum/bot_scenario/op_arms_the_nuke/post_spawn()
	..()
	nuke = new(first_marker("N"))
	var/datum/bot_nuke_team/team = new
	team.code = nuke.r_code
	team.nuke = nuke
	team.members += brain
	team.leader = brain
	brain.op_team = team
	disk = new(get_turf(bot))
	qdel(disk.GetComponent(/datum/component/stationloving)) //it would take itself back to the station, off the gym's z-level
	if(!SEND_SIGNAL(bot.back, COMSIG_TRY_STORAGE_INSERT, disk, bot, TRUE))
		bot.put_in_inactive_hand(disk)
	brain.assign_goal(new /datum/bot_goal/op_arm(nuke))

/datum/bot_scenario/op_arms_the_nuke/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(nuke.timing)
		armed = TRUE
		nuke.set_active() //and off again: not in the gym
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/op_arms_the_nuke/release_run()
	if(nuke?.timing)
		nuke.set_active()
	brain.op_team = null
	if(disk)
		qdel(disk, TRUE) //a real one won't go otherwise: it puts itself back on the station
	QDEL_NULL(nuke)
	..()

/datum/bot_scenario/reloads
	name = "guns: out of rounds, it reloads from the bag"
	desc = "A submachine gun with an empty magazine and a full one in the bag. Nothing reloaded before: a bot fired one magazine and was done with the gun."
	layout = list(
		"###########",
		"#B.....T..#",
		"###########")
	time_limit = 20 SECONDS
	var/obj/item/gun/ballistic/automatic/c20r/gun
	var/mob/living/carbon/human/target
	var/reloaded = FALSE

/datum/bot_scenario/reloads/issue_goal()
	return

/datum/bot_scenario/reloads/post_spawn()
	..()
	target = stand_in(first_marker("T"), "Terry Target")
	gun = new(get_turf(bot))
	QDEL_LIST(gun.magazine.stored_ammo)
	QDEL_NULL(gun.chambered)
	gun.update_icon()
	bot.put_in_active_hand(gun)
	var/obj/item/storage/backpack/bag = bot.back
	if(!istype(bag) || !SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_INSERT, new /obj/item/ammo_box/magazine/smgm45(get_turf(bot)), bot, TRUE))
		fail_reason = "no bag to put the spare magazine in"
	addtimer(CALLBACK(src, PROC_REF(shoot)), 2 SECONDS)

/datum/bot_scenario/reloads/proc/shoot()
	if(result != BOT_GYM_PENDING)
		return
	if(brain.try_shoot_at(target) && gun.can_shoot())
		reloaded = TRUE
	addtimer(CALLBACK(src, PROC_REF(shoot)), 1 SECONDS)

/datum/bot_scenario/reloads/check()
	if(bot_lost() || fail_reason)
		return BOT_GYM_FAIL
	if(reloaded && gun.magazine?.ammo_count() < gun.magazine?.max_ammo)
		return BOT_GYM_PASS //and it's been firing it since
	return BOT_GYM_PENDING
