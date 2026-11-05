// Bot Gym scenarios for requests consoles (goals/station_requests.dm). A stand-in crew member (C) at the far end sends a
// request to a department from a console beside them; it reaches the bot as a delivered request would (the arena isn't
// on the station's telecomms), and the bot is judged on whether it answers, goes, does the job, and whether the console's
// tracking says so.
//
// Layout letters used here: o blood on the floor, M a mop, U a bucket of water.

/datum/bot_scenario/chat/request/console
	time_limit = 60 SECONDS
	/// The department it's sent to, and what it says (AREA is the arena's name)
	var/to_dept = "Medbay"
	var/body = "A doctor is needed in AREA."
	var/request_kind = "Doctor"
	var/datum/station_request/request

/datum/bot_scenario/chat/request/console/make_call()
	var/datum/station_request/R = new
	R.id = ++GLOB.station_request_count
	R.from_dept = "Bar"
	R.to_dept = to_dept
	R.priority = REQ_NORMAL_MESSAGE_PRIORITY
	R.body = replacetext(body, "AREA", get_area_name(visitor, TRUE))
	R.sender = "[visitor.real_name] (Bartender)"
	R.sender_ref = WEAKREF(visitor)
	R.area_name = get_area_name(visitor, TRUE)
	R.location = get_turf(visitor)
	R.kind = request_kind
	R.time = station_time_timestamp()
	request = R
	GLOB.station_requests += R
	GLOB.station_requests_by_id["[R.id]"] = R
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_STATION_REQUEST, R)

/// The tracking the console shows: on it under this bot's name, then done
/datum/bot_scenario/chat/request/console/proc/tracked(status)
	return request && request.status == status && findtext(request.handler, bot.real_name)

/datum/bot_scenario/chat/request/console/release_run()
	if(request)
		GLOB.station_requests -= request
		GLOB.station_requests_by_id -= "[request.id]"
	return ..()

/// A Bot Shift drill: somebody at a requests console out on the station asks Cargo for a crate of glass. Cargo has to order it,
/// the request it made has to come off the cargo console's list (or it would be ordered twice), and the console's tracking
/// has to read done.
/datum/bot_shift_check/console_crate_request
	name = "cargo: a crate asked for at a requests console ordered (drill)"
	jobs = list("Cargo Technician", "Quartermaster")
	deadline = 16 MINUTES
	var/asks_at = 6 MINUTES
	var/datum/station_request/request
	var/asked = FALSE

/datum/bot_shift_check/console_crate_request/poll()
	if(!asked && shift.elapsed() >= asks_at && worker())
		asked = TRUE
		var/obj/machinery/requests_console/console
		for(var/obj/machinery/requests_console/RC in GLOB.allConsoles)
			if(is_station_level(RC.z) && !(ckey(RC.department) in list("cargobay", "mining")) && !(RC.stat & (NOPOWER|BROKEN)))
				console = RC
				break
		if(console)
			var/mob/living/carbon/human/asker = new(get_turf(console)) // not kept: one blown up was a hard delete
			asker.real_name = "Rhea Asker"
			asker.name = asker.real_name
			asker.equipOutfit(/datum/outfit/job/assistant)
			var/had = length(GLOB.station_requests)
			usr = asker
			console.req_crate(/datum/supply_pack/materials/glass50, "For the windows", asker)
			usr = null
			if(length(GLOB.station_requests) > had)
				request = GLOB.station_requests[length(GLOB.station_requests)]
			shift.note("[name]: Rhea Asker asks Cargo for a crate of glass at the [console.department] requests console[request ? "" : ", and it didn't go through"]")
	..()

/datum/bot_shift_check/console_crate_request/done()
	return request && request.status == "done" && !(request.order in SSshuttle.requestlist)

/datum/bot_shift_check/console_crate_request/progress()
	if(!asked)
		return "nobody has asked yet"
	if(!request)
		return "the request didn't go through"
	return "asked for glass at a console: [request.status][request.handler ? " ([request.handler])" : ""], [(request.order in SSshuttle.requestlist) ? "still" : "no longer"] on the cargo console's list"

/datum/bot_scenario/chat/request/console/medic
	name = "request console: a doctor answers a request for one"
	desc = "The bartender, hurt, sends Medbay a request for a doctor from a console at the far end. The doctor says on the medical channel it's coming, walks over, patches them up, and the request reads done under its name."
	job = "Medical Doctor"
	layout = list(
		"##########",
		"#B.....C.#",
		"##########")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment)

/datum/bot_scenario/chat/request/console/medic/post_spawn()
	..()
	visitor.apply_damage(30, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/chat/request/console/medic/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!request || world.time < request_made_at() + 10 SECONDS)
		return BOT_GYM_PENDING
	if(request.status == "new")
		if(world.time > request_made_at() + 15 SECONDS)
			fail_reason = "nobody took the request"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	if(!findtext(request.handler, bot.real_name))
		fail_reason = "the request isn't under the doctor's name: [request.handler]"
		return BOT_GYM_FAIL
	if(visitor.getBruteLoss() > 10 || !tracked("done"))
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

/datum/bot_scenario/chat/request/console/proc/request_made_at()
	return start_time + 2 SECONDS

/datum/bot_scenario/chat/request/console/security
	name = "request console: an officer answers a request for Security"
	desc = "The bartender sends Security a request from a console at the far end. The officer says on the security channel it's responding, goes there, and the request reads on it and then done under its name."
	job = "Security Officer"
	to_dept = "Security"
	body = "Security is needed in AREA."
	request_kind = "Security"
	layout = list(
		"############",
		"#B.......C.#",
		"############")

/datum/bot_scenario/chat/request/console/security/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!request || world.time < request_made_at() + 10 SECONDS)
		return BOT_GYM_PENDING
	if(request.status == "new")
		if(world.time > request_made_at() + 15 SECONDS)
			fail_reason = "nobody took the request"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	if(!tracked("done"))
		return BOT_GYM_PENDING
	return get_dist(bot, visitor) <= 3 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/request/console/janitor
	name = "request console: the janitor answers a request for cleaning"
	desc = "The bartender, stood by a pool of blood, sends Janitorial a request for cleaning. The janitor says it's coming, fetches the mop and bucket, mops it up, and the request reads done under its name."
	job = "Janitor"
	to_dept = "Janitorial"
	body = "Cleaning is needed in AREA."
	request_kind = "Cleaning"
	time_limit = 90 SECONDS
	layout = list(
		"###########",
		"#BMU...Co.#",
		"###########")

/datum/bot_scenario/chat/request/console/janitor/setup()
	for(var/turf/T in markers["o"])
		place("o", new /obj/effect/decal/cleanable/blood(T))
	for(var/turf/T in markers["M"])
		place("M", new /obj/item/mop(T))
	for(var/turf/T in markers["U"])
		var/obj/item/reagent_containers/glass/bucket/B = new(T)
		B.reagents.add_reagent(/datum/reagent/water, 50)
		place("U", B)

/datum/bot_scenario/chat/request/console/janitor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!request || world.time < request_made_at() + 10 SECONDS)
		return BOT_GYM_PENDING
	if(request.status == "new")
		if(world.time > request_made_at() + 15 SECONDS)
			fail_reason = "nobody took the request"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	for(var/turf/T in arena_area)
		if(brain.turf_has_mess(T))
			return BOT_GYM_PENDING
	return tracked("done") ? BOT_GYM_PASS : BOT_GYM_PENDING
