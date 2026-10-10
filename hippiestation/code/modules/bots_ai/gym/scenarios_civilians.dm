// Bot Gym scenarios for the civilian and command jobs (goals/civilians.dm).
//
// Layout letters used here: C a stand-in crew member, h a chair, K a communications console, d the nuclear disk
// on a table, Q a morgue drawer (opening towards the bot's side), y a body.

/datum/bot_scenario/chat/mime_answers
	name = "mime answers with a gesture"
	desc = "A crew member asks the mime how it's doing, by name. A mime can't speak: the answer comes as a gesture, not as nothing at all."
	job = "Mime"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")

/datum/bot_scenario/chat/mime_answers/post_spawn()
	..()
	bot.mind.miming = TRUE
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/mime_answers/proc/ask()
	visitor_says("Hey [bot.first_name()], how are you?")

/datum/bot_scenario/chat/mime_answers/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "mimed it instead"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/civilian
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/visitor

/datum/bot_scenario/duty/civilian/post_spawn()
	var/turf/T = first_marker("C")
	if(T)
		visitor = stand_in(T, "Casey Visitor")

/datum/bot_scenario/duty/civilian/clown
	name = "clown puts on a show for a passer-by"
	desc = "Somebody stood nearby, a bike horn in the bag. The clown gets the horn out, honks it and tells a joke or two - horn in hand, a couple of seconds between turns - and puts it away again."
	duty_type = /datum/bot_duty/perform
	job = "Clown"
	layout = list(
		"########",
		"#B...C.#",
		"########")
	kit_backpack = list(/obj/item/bikehorn)

/datum/bot_scenario/duty/civilian/clown/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.shows_put_on || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(world.time - start_time < 5 SECONDS)
		fail_reason = "a whole act in [(world.time - start_time) / 10]s"
		return BOT_GYM_FAIL
	if(locate(/obj/item/bikehorn) in bot.held_items)
		fail_reason = "left holding the horn"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/civilian/mime
	name = "mime performs for a passer-by"
	desc = "Somebody stood nearby. The mime goes through a few bits of its act - the wall, the rope - as emotes, a couple of seconds apart, without a word."
	duty_type = /datum/bot_duty/perform
	job = "Mime"
	layout = list(
		"########",
		"#B...C.#",
		"########")

/datum/bot_scenario/duty/civilian/mime/post_spawn()
	..()
	bot.mind.miming = TRUE

/datum/bot_scenario/duty/civilian/mime/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.shows_put_on || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(world.time - start_time < 5 SECONDS)
		fail_reason = "a whole act in [(world.time - start_time) / 10]s"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/civilian/desk
	name = "head of personnel sits down at the desk"
	desc = "An office with a chair in it. The Head of Personnel walks over, sits down and stays sat - it doesn't get straight back up to wander."
	duty_type = /datum/bot_duty/desk
	job = "Head of Personnel"
	layout = list(
		"########",
		"#B.....#",
		"#....h.#",
		"########")
	var/sat_at

/datum/bot_scenario/duty/civilian/desk/setup()
	for(var/turf/T in markers["h"])
		place("h", new /obj/structure/chair/office(T))

/datum/bot_scenario/duty/civilian/desk/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!bot.buckled)
		if(sat_at)
			fail_reason = "got up again after [(world.time - sat_at) / 10]s"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	if(!sat_at)
		sat_at = world.time
	return (world.time - sat_at >= 15 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/civilian/disk
	name = "captain secures the nuclear disk"
	desc = "The disk is on a table across the room. The captain walks over, picks it up and puts it away on their person - not left in a hand."
	duty_type = /datum/bot_duty/captain
	job = "Captain"
	layout = list(
		"########",
		"#B....d#",
		"########")

/datum/bot_scenario/duty/civilian/disk/setup()
	for(var/turf/T in markers["d"])
		place("d", new /obj/structure/table(T))
		// Off the station's own level the real thing sends itself home (/datum/component/stationloving), out of the arena.
		var/obj/item/disk/nuclear/disk = new(null)
		qdel(disk.GetComponent(/datum/component/stationloving))
		STOP_PROCESSING(SSobj, disk)
		disk.forceMove(T)
		place("d", disk)

/datum/bot_scenario/duty/civilian/disk/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/disk/nuclear/disk = locate() in bot.GetAllContents()
	if(!disk || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(disk in bot.held_items)
		fail_reason = "has the disk but is carrying it about in a hand"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/civilian/announce
	name = "captain says a word to the crew"
	desc = "A communications console across the room and nothing said yet this shift. The captain walks to it and makes one announcement, taking as long over it as it takes to type."
	duty_type = /datum/bot_duty/captain
	job = "Captain"
	layout = list(
		"########",
		"#B....K#",
		"########")

/datum/bot_scenario/duty/civilian/announce/setup()
	GLOB.bot_captain_greeted = FALSE
	for(var/turf/T in markers["K"])
		place("K", new /obj/machinery/computer/communications(T))

/datum/bot_scenario/duty/civilian/announce/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!GLOB.bot_captain_greeted || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(world.time - start_time < 4 SECONDS)
		fail_reason = "walked over and announced in [(world.time - start_time) / 10]s"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/civilian/morgue
	name = "chaplain takes a body to the morgue"
	desc = "Somebody long dead on the floor and an empty morgue drawer. The chaplain takes hold of the body, drags it to the drawer, slides the tray out, moves the body onto it and shuts it - and isn't shut in with it."
	duty_type = /datum/bot_duty/morgue
	job = "Chaplain"
	layout = list(
		"#########",
		"#B..y...#",
		"#......Q#",
		"#.......#",
		"#########")
	time_limit = 90 SECONDS
	var/mob/living/carbon/human/body

/datum/bot_scenario/duty/civilian/morgue/setup()
	for(var/turf/T in markers["Q"])
		var/obj/structure/bodycontainer/morgue/M = new(T)
		M.setDir(WEST)
		place("Q", M)

/datum/bot_scenario/duty/civilian/morgue/post_spawn()
	body = stand_in(first_marker("y"), "Dee Parted")
	body.death()
	body.timeofdeath = world.time - 10 MINUTES

/datum/bot_scenario/duty/civilian/morgue/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/structure/bodycontainer/morgue/M = first_placed("Q")
	if(bot.loc == M)
		fail_reason = "shut itself in the drawer"
		return BOT_GYM_FAIL
	if(QDELETED(body) || body.loc != M || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	return BOT_GYM_PASS
