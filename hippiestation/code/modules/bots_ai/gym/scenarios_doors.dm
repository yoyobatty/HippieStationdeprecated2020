// Bot Gym scenarios for doors and getting past people (bot_doors.dm, the seated-crew check in
// bot_pathing_permissive.dm). Each is something from a station shift's evacuation drill.
//
// Layout letters used here: k floor with a door button on the wall beside it, c a chair with somebody sat in it.

/datum/bot_scenario/door_button
	job = "Assistant"
	time_limit = 40 SECONDS
	/// The id the door and its button share.
	var/door_id

/datum/bot_scenario/door_button/setup()
	door_id = "gym_foyer_[REF(src)]"
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_MEDICAL)
	A.id_tag = door_id
	for(var/turf/T in markers["k"])
		var/obj/machinery/button/door/B = new(T)
		B.name = "Exit Button"
		B.id = door_id
		B.normaldoorcontrol = TRUE
		place("k", B)

/datum/bot_scenario/door_button/check_success_conditions()
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(QDELETED(A) || A.panel_open || (A.stat & BROKEN))
		return "the door was forced, not opened with its button"
	return null

/datum/bot_scenario/door_button/beside_the_door
	name = "visitor lets itself out with the exit button"
	desc = "Shut in a department whose doors want its access, with the exit button on the wall beside them. A person presses the button and walks out - no tools, no hacking (a real shift's assistant stood at Medbay's doors until the shuttle left without it)."
	layout = list(
		"###########",
		"#B.k.D...G#",
		"###########")

/datum/bot_scenario/door_button/across_the_room
	name = "exit button a few steps from the door"
	desc = "The same, with the button across the room from the door: the bot walks over to it, presses it, and goes through before the door shuts again."
	layout = list(
		"##########",
		"#k.......#",
		"#........#",
		"#B....D.G#",
		"##########")

/datum/bot_scenario/door_button/wrong_side
	name = "the button on the far side is no use from outside"
	desc = "The door's button is inside the room and the bot is outside, on an everyday errand. It can't reach through the door for it, so it doesn't get in - and doesn't take the door apart either."
	layout = list(
		"###########",
		"#B...D.k.G#",
		"###########")
	time_limit = 20 SECONDS

/datum/bot_scenario/door_button/wrong_side/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE
	return G

/datum/bot_scenario/door_button/wrong_side/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(get_turf(bot) == first_marker("G"))
		fail_reason = "got through a door it has no access to and no button for"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/door_button/wrong_side/on_timeout()
	var/problem = check_success_conditions()
	if(problem)
		fail_reason = problem
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/hemmed_in
	name = "hemmed in by tables on an everyday errand"
	desc = "In a corner with a table on each open side - where an earlier errand's climb left it - and now only on ordinary business, which doesn't climb furniture. It comes back over a table all the same rather than standing there (a real shift's Quartermaster stood in a corner of Technical Storage for six minutes). The tables are still in one piece afterwards."
	layout = list(
		"#######",
		"#Bt...#",
		"#t...G#",
		"#######")
	time_limit = 30 SECONDS

/datum/bot_scenario/hemmed_in/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE
	return G

/datum/bot_scenario/hemmed_in/check_success_conditions()
	for(var/obj/structure/table/T as anything in placed["t"])
		if(QDELETED(T))
			return "broke a table to get out"
	return null

/datum/bot_scenario/seated_in_the_way
	name = "walks round somebody sat in the way"
	desc = "The straight line to the goal runs through a chair with somebody sat in it. There's no swapping places with a seated person: the bot goes round by the free tiles rather than walking into them (a real shift's doctor bumped a row of seated passengers until the shuttle left)."
	layout = list(
		"#########",
		"#B..c..G#",
		"#.......#",
		"#########")
	time_limit = 15 SECONDS

/datum/bot_scenario/seated_in_the_way/setup()
	var/turf/T = first_marker("c")
	var/obj/structure/chair/C = new(T)
	place("c", C)
	var/mob/living/carbon/human/sitter = stand_in(T, "Sam Sitter")
	C.buckle_mob(sitter, TRUE)

/datum/bot_scenario/open_door
	job = "Assistant"
	time_limit = 20 SECONDS

/// The door wants an access the bot hasn't got, and somebody has left it standing open.
/datum/bot_scenario/open_door/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_TOX)
	A.autoclose = FALSE
	INVOKE_ASYNC(A, TYPE_PROC_REF(/obj/machinery/door/airlock, open))

/datum/bot_scenario/open_door/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE
	return G

/datum/bot_scenario/open_door/not_followed_in
	name = "doesn't stroll in through a door somebody left open"
	desc = "A lab door the bot's ID doesn't open is standing open, and the bot is on an everyday errand to the other side with the run of a big room behind it. It doesn't go in: the door would shut behind it and it couldn't get out again (a real shift's assistant spent the rest of it in the Toxins launch room that way)."
	layout = list(
		"################",
		"#B.........#...#",
		"#..........#...#",
		"#..........D..G#",
		"#..........#...#",
		"#..........#...#",
		"#..........#...#",
		"################")

/datum/bot_scenario/open_door/not_followed_in/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(bot.x >= A.x)
		fail_reason = "walked in through a door its ID doesn't open"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/open_door/not_followed_in/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/open_door/way_out
	name = "shut in: leaves by a door somebody left open"
	desc = "The other way round: the bot is in a small room whose door its ID doesn't open, and the door is standing open. That's its way out, and it takes it."
	layout = list(
		"################",
		"#...#..........#",
		"#B..D.........G#",
		"#...#..........#",
		"################")

/datum/bot_scenario/shutter_way_out
	name = "shut in behind a shutter: uses the button on its side"
	desc = "A small room closed off by a blast door, with the door's button on the wall inside. The bot presses it once, waits for the door, and walks out - it doesn't press again and shut itself back in (a real shift's engineer sat out the evacuation in secure storage)."
	job = "Station Engineer"
	layout = list(
		"###########",
		"#B.k.H...G#",
		"###########")
	time_limit = 40 SECONDS

/datum/bot_scenario/shutter_way_out/setup()
	var/door_id = "gym_shutter_[REF(src)]"
	for(var/turf/T in markers["H"])
		var/obj/machinery/door/poddoor/P = new(T)
		P.id = door_id
		place("H", P)
	for(var/turf/T in markers["k"])
		var/obj/machinery/button/door/B = new(T)
		B.name = "Blast Door Control"
		B.id = door_id
		place("k", B)

/datum/bot_scenario/shutter_way_out/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE
	return G
