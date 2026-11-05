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

/datum/bot_scenario/chat/request/console/cargo_budget
	name = "request console: cargo says when a crate asked for is over budget"
	desc = "The bartender asks Cargo for a Supermatter Shard crate (10,000 credits) at a console, with 2,000 in the budget. The cargo technician says on the channel it came over that it can't afford it yet, and the request reads so on the console. It used to be put aside without a word."
	job = "Cargo Technician"
	to_dept = "Cargo Bay"
	body = "Crate requested: Supermatter Shard Crate (For the engine). It's in the cargo console's requests."
	request_kind = "crate"
	station_wide = TRUE //the cargo budget is the whole station's
	layout = list(
		"##########",
		"#B.....C.#",
		"##########")
	var/datum/supply_order/order
	var/saved_balance

/datum/bot_scenario/chat/request/console/cargo_budget/make_call()
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	saved_balance = budget.account_balance
	budget.account_balance = 2000
	order = new(SSshuttle.supply_packs[/datum/supply_pack/engine/supermatter_shard], visitor.real_name, "Bartender", null, "For the engine", null)
	..()
	request.order = order //read when it's taken up, a moment later

/datum/bot_scenario/chat/request/console/cargo_budget/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!request || world.time < request_made_at() + 10 SECONDS)
		return BOT_GYM_PENDING
	if(request.status == "new" && world.time > request_made_at() + 15 SECONDS)
		fail_reason = "nobody took the request"
		return BOT_GYM_FAIL
	if(request.status == "on it" && world.time > request_made_at() + 20 SECONDS)
		fail_reason = "took it, and said nothing about the budget"
		return BOT_GYM_FAIL
	return (request.status == "can't afford" && bot_transcript_said("credits")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/request/console/cargo_budget/release_run()
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	if(budget && !isnull(saved_balance))
		budget.account_balance = saved_balance
	return ..()

// A crate somewhere with no air (goals/cargo.dm, crate_in_bad_air())

/datum/bot_scenario/duty/crate_in_bad_air
	name = "cargo: a crate left where there's no air is left alone for a while, not asked about every few seconds"
	desc = "A crate that went astray on the way to the bay sits in a pocket with no air, and the cargo technician has no suit. It leaves the crate be. Two cargo technicians used to turn the same crate down 183 times between them in one shift."
	duty_type = /datum/bot_duty/cargo
	job = "Cargo Technician"
	time_limit = 50 SECONDS
	layout = list(
		"#########",
		"#B....#v#",
		"#########")
	var/obj/structure/closet/crate/crate
	var/started

/datum/bot_scenario/duty/crate_in_bad_air/setup()
	crate = new(first_marker("v"))
	place("v", crate)
	GLOB.bot_cargo_strays |= crate

/datum/bot_scenario/duty/crate_in_bad_air/post_spawn()
	started = world.time

/datum/bot_scenario/duty/crate_in_bad_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/asked = 0
	for(var/line in transcript)
		// Each go at it: turned down for the air or, with no cargo bay on the gym's level to take it to, for that
		if(findtext(line, "somewhere I can't breathe") || findtext(line, "unload_crate"))
			asked++
	if(asked > 1)
		fail_reason = "went at the crate [asked] times in [round((world.time - started) / 10)] s"
		return BOT_GYM_FAIL
	return world.time - started > 40 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/crate_in_bad_air/release_run()
	GLOB.bot_cargo_strays -= crate
	return ..()

/// rc-sweep=1: from 2:00 every requests console on the station sends a test message to Cargo Bay, one a second, and the ones that get
/// no answer from the message server are named. On Box Station none could: its map had the bare message server, which calibrates for
/// 15 minutes and isn't linked to the network, where the other maps have the preset.
/datum/bot_shift_check/rc_sweep
	name = "telecomms: every requests console can send (sweep)"
	jobs = list("Cargo Technician", "Quartermaster")
	deadline = 4 MINUTES
	var/swept = FALSE
	var/list/failed = list()
	var/sent = 0
	var/unusable = 0
	var/list/queue
	var/mob/living/carbon/human/tester

/datum/bot_shift_check/rc_sweep/worker()
	if(!world.params["rc-sweep"])
		return null
	return ..()

/datum/bot_shift_check/rc_sweep/poll()
	if(isnull(queue) && shift.elapsed() >= 2 MINUTES)
		queue = list()
		for(var/obj/machinery/requests_console/RC in GLOB.allConsoles)
			if(is_station_level(RC.z) && !(RC.stat & (NOPOWER|BROKEN)) && ckey(RC.department) != "cargobay")
				queue += RC
		sweep_next()
	..()

/// One console a second: a burst of them in one tick is more than the telecomms receivers pass on
/datum/bot_shift_check/rc_sweep/proc/sweep_next()
	if(!length(queue))
		swept = TRUE
		QDEL_NULL(tester)
		shift.note("[name]: [sent] sent, [length(failed)] failed[length(failed) ? ": [english_list(failed)]" : ""], [unusable] the stand-in couldn't use")
		return
	var/obj/machinery/requests_console/RC = queue[1]
	queue.Cut(1, 2)
	if(!tester)
		tester = new(get_turf(RC))
		tester.real_name = "Rhea Tester"
		tester.name = tester.real_name
	tester.forceMove(get_turf(RC))
	RC.to_department = GLOB.req_console_ckey_departments["cargobay"]
	RC.message = "Test from [RC.department]"
	RC.priority = REQ_NORMAL_MESSAGE_PRIORITY
	usr = tester
	RC.Topic(null, list("send" = "1"))
	usr = null
	if(RC.screen == 6) // REQ_SCREEN_SENT
		sent++
	else if(RC.screen == 0 && RC.message)
		unusable++ // its Topic() turned the stand-in away (the console's own checks on who's using it), not a failed send
	else
		failed += "[RC.department] in [get_area_name(RC, TRUE)] (screen [RC.screen])"
	RC.screen = 0
	RC.message = ""
	addtimer(CALLBACK(src, PROC_REF(sweep_next)), 1 SECONDS)

/datum/bot_shift_check/rc_sweep/done()
	return swept && !length(failed)

/datum/bot_shift_check/rc_sweep/progress()
	return swept ? "[sent] sent, [unusable] the stand-in couldn't use, failed: [english_list(failed)]" : "not swept yet"
