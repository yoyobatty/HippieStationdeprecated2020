// Bot Gym scenarios for disposals (goals/disposals.dm). The arena gets real pipe: a bin with a trunk under it, straight pipe, and
// an outlet on a trunk where it comes out.

/// A run of disposal pipe along a row, from a bin at `from` to an outlet at `dest` that throws things `outlet_dir`. The pipes go
/// in first so the bin and the outlet find their trunks. The bin is ready to go at once and flushes every ten seconds, not every
/// minute.
/datum/bot_scenario/proc/lay_disposals(turf/from, turf/dest, outlet_dir)
	var/d = get_dir(from, dest)
	var/obj/structure/disposalpipe/trunk/start = new(from)
	start.setDir(d)
	start.dpdir = d
	var/turf/at = get_step(from, d)
	while(at && at != dest)
		var/obj/structure/disposalpipe/segment/S = new(at)
		S.setDir(d)
		S.dpdir = d | turn(d, 180)
		at = get_step(at, d)
	var/obj/structure/disposalpipe/trunk/end = new(dest)
	end.setDir(turn(d, 180))
	end.dpdir = turn(d, 180)
	var/obj/machinery/disposal/bin/B = new(from)
	var/obj/structure/disposaloutlet/O = new(dest)
	O.setDir(outlet_dir)
	O.target = get_ranged_target_turf(O, outlet_dir, 10)
	start.getlinked()
	end.getlinked()
	B.full_pressure = TRUE
	B.pressure_charging = FALSE
	B.flush_every_ticks = 5
	B.update_icon()
	place("n", B)
	place("o", O)
	return B

/datum/bot_scenario/disposals_shut_in
	name = "disposals: shut in, it gets out by the bin"
	desc = "Shut in a small room whose door it has no access for, and it's been asking a while. There's a disposal bin in the room that comes out in the next room. It climbs in, waits for the flush and comes out the other side."
	job = "Assistant"
	layout = list(
		"###########",
		"#B.n#.o...#",
		"#...D.....#",
		"###########")
	time_limit = 100 SECONDS

/datum/bot_scenario/disposals_shut_in/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)
	lay_disposals(first_marker("n"), first_marker("o"), EAST)

/datum/bot_scenario/disposals_shut_in/post_spawn()
	brain.gym_scripted = FALSE //left to itself, as on the station: a scripted bot between goals does nothing
	brain.gym_asks_out = TRUE
	brain.shut_in_since = world.time - 10 MINUTES //it's been asking a while
	brain.next_shut_in_look = 0

/datum/bot_scenario/disposals_shut_in/make_goal()
	return null

/datum/bot_scenario/disposals_shut_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/door = first_marker("D")
	if(isturf(bot.loc) && bot.x > door.x)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/disposals_shut_in/into_space
	name = "disposals: shut in, it won't take a bin that empties into space"
	desc = "The same room, but the bin's pipe comes out into space. It stays put and keeps asking to be let out."
	layout = list(
		"###########",
		"#B.n#.oSSS#",
		"#...D.SSSS#",
		"###########")
	time_limit = 40 SECONDS

/datum/bot_scenario/disposals_shut_in/into_space/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/disposal/bin/B = first_placed("n")
	if(!isturf(bot.loc) || bot.loc == B)
		fail_reason = "got into a bin that comes out in space"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/disposals_shut_in/into_space/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/disposals_prank
	name = "disposals: a greytider puts somebody it beat in the bin"
	desc = "A greytider has just won a fight; whoever it beat is out cold two tiles away, with a bin nearby that comes out across the room. It drags them over, stuffs them in and pulls the handle."
	job = "Assistant"
	layout = list(
		"############",
		"#B.C..n...o#",
		"############")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/victim

/datum/bot_scenario/disposals_prank/setup()
	lay_disposals(first_marker("n"), first_marker("o"), EAST)

/datum/bot_scenario/disposals_prank/post_spawn()
	victim = stand_in(first_marker("C"), "Casey Visitor")
	victim.Unconscious(2 MINUTES)
	brain.greytider = TRUE
	brain.beaten_foe = WEAKREF(victim)
	brain.beaten_foe_at = world.time

/datum/bot_scenario/disposals_prank/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/stuff_in_bin")) //only there with the change
	if(!D)
		log_line("there's no such duty")
	else if(!D.try_start(brain)) //a scripted bot doesn't look for its own duties
		log_line("the duty didn't start")
	return null

/datum/bot_scenario/disposals_prank/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(victim))
		fail_reason = "the visitor's gone"
		return BOT_GYM_FAIL
	var/obj/machinery/disposal/bin/B = first_placed("n")
	if(istype(victim.loc, /obj/structure/disposalholder) || (isturf(victim.loc) && victim.x > B.x + 1) || (victim.loc == B && B.flush))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/disposals_shut_in/no_air
	name = "disposals: shut in with the air gone, it gets out by the bin"
	desc = "The same room with the air gone out of it, and the bot on its emergency tank. It turned the bin down as somewhere it couldn't breathe, which was the room it was stood in."
	time_limit = 100 SECONDS

/datum/bot_scenario/disposals_shut_in/no_air/setup()
	..()
	var/turf/door = first_marker("D")
	for(var/turf/open/floor/F in arena_area)
		if(F.x < door.x)
			F.air.parse_gas_string("TEMP=2.7")
			F.update_visuals()
			SSair.add_to_active(F)

/datum/bot_scenario/disposals_shut_in/no_air/post_spawn()
	..()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(bot), ITEM_SLOT_MASK)
	bot.equip_to_slot_or_del(new /obj/item/tank/internals/emergency_oxygen/engi(bot), ITEM_SLOT_LPOCKET)
