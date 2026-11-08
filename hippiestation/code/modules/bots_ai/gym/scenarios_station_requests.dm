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

/// A Bot Shift drill: somebody with a Common-only headset asks Cargo for silver at Science's requests console, as the user did as the
/// Chief Engineer. Cargo has to order it and bring it round to Science, on a MULE when one's free; the user's silver sat in the bay.
/datum/bot_shift_check/console_crate_delivered
	name = "cargo: a crate asked for at Science's console brought round to Science (drill)"
	jobs = list("Cargo Technician", "Quartermaster")
	deadline = 24 MINUTES
	var/asks_at = 7 MINUTES
	var/asked = FALSE
	var/obj/machinery/requests_console/console
	var/datum/station_request/request
	var/crate_name
	var/obj/structure/closet/crate/sent

/datum/bot_shift_check/console_crate_delivered/poll()
	if(!asked && shift.elapsed() >= asks_at && worker())
		asked = TRUE
		for(var/obj/machinery/requests_console/RC in GLOB.allConsoles)
			if(is_station_level(RC.z) && ckey(RC.department) == "science" && !(RC.stat & (NOPOWER|BROKEN)))
				console = RC
				break
		var/datum/supply_pack/P = SSshuttle.supply_packs[/datum/supply_pack/materials/silver20]
		crate_name = P?.crate_name
		if(console && P)
			var/mob/living/carbon/human/asker = new(get_turf(console))
			asker.real_name = "Ida Asker"
			asker.name = asker.real_name
			asker.equipOutfit(/datum/outfit/job/assistant) //a headset with Common and nothing else
			var/had = length(GLOB.station_requests)
			usr = asker
			console.req_crate(P.type, "For the protolathe", asker)
			usr = null
			if(length(GLOB.station_requests) > had)
				request = GLOB.station_requests[length(GLOB.station_requests)]
		shift.note("[name]: Ida Asker asks Cargo for silver at [console ? "Science's requests console" : "no console (Science hasn't one)"][request ? "" : ", and it didn't go through"]")
	..()

/// The crate, once it's been sent round: where it is. Kept once seen, since it comes off the list of delivered crates when somebody
/// unpacks it.
/datum/bot_shift_check/console_crate_delivered/proc/sent_crate()
	if(sent && !QDELETED(sent))
		return sent
	for(var/obj/structure/closet/crate/C in GLOB.bot_delivered_crates)
		if(!QDELETED(C) && C.name == crate_name)
			sent = C
			return C
	return null

/datum/bot_shift_check/console_crate_delivered/done()
	var/obj/structure/closet/crate/C = sent_crate()
	if(!C || !isturf(C.loc) || !console)
		return FALSE
	return bot_department_of(get_area(C)) == "science" || get_dist(C, console) <= 15

/datum/bot_shift_check/console_crate_delivered/progress()
	if(!asked)
		return "nobody has asked yet"
	if(!request)
		return "the request didn't go through"
	var/obj/structure/closet/crate/C = sent_crate()
	if(C)
		var/where = isturf(C.loc) ? "[get_area_name(C, TRUE)] ([C.x], [C.y])" : "on [C.loc]"
		return "silver sent round, now in [where]"
	var/list/delivery = GLOB.bot_cargo_deliveries[/datum/supply_pack/materials/silver20]
	return "asked: [request.status][request.handler ? " ([request.handler])" : ""], [delivery ? "down to go round to [delivery[1]]" : "not down to go round"]"

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
	var/balance = 2000
	var/pack_type = /datum/supply_pack/engine/supermatter_shard

/datum/bot_scenario/chat/request/console/cargo_budget/make_call()
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	saved_balance = budget.account_balance
	budget.account_balance = balance
	order = new(SSshuttle.supply_packs[pack_type], visitor.real_name, "Bartender", null, "For the engine", null)
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

/// What's on order already is paid for out of the same budget when the shuttle brings it in (goals/orders.dm bot_cargo_spendable())
/datum/bot_scenario/chat/request/console/cargo_budget/on_order
	name = "request console: cargo counts what's on order before it says yes to a crate"
	desc = "The bartender asks Cargo for 20 silver sheets (2,000 credits) at a console. The budget reads 3,000, with two 1,000-credit crates on order and not yet paid for. The cargo technician says it can't afford it yet. It used to say yes on the balance: the silver asked for at Science's console was never ordered, three shifts in six."
	body = "Crate requested: 20 Silver Sheets (For the protolathe). It's in the cargo console's requests."
	balance = 3000
	pack_type = /datum/supply_pack/materials/silver20
	var/list/waiting

/datum/bot_scenario/chat/request/console/cargo_budget/on_order/make_call()
	waiting = list()
	for(var/staple in list(/datum/supply_pack/materials/glass50, /datum/supply_pack/materials/metal50))
		var/datum/supply_order/SO = new(SSshuttle.supply_packs[staple], "Gym Quartermaster", "Quartermaster", null, "Restocking", null)
		SSshuttle.shoppinglist += SO
		waiting += SO
	..()

/datum/bot_scenario/chat/request/console/cargo_budget/on_order/release_run()
	SSshuttle.shoppinglist -= waiting
	return ..()

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

/// A crate asked for at another department's console: answered on a channel the asker hears, and down to go round to them. The user
/// asked Cargo for silver at Science's console as the Chief Engineer: the technician said it was ordered on Supply, which the CE's
/// headset doesn't have, and the crate sat in the bay.
/datum/bot_scenario/chat/request/console/crate_reply
	name = "request console: a crate asked for from another department is answered on Common and set to go round to them"
	desc = "Somebody with a Common-only headset asks Cargo for gold at a console in Science. The technician's answer is on Common, not Supply, and the crate's down to be delivered to Science."
	job = "Cargo Technician"
	to_dept = "Cargo Bay"
	body = "For the protolathe"
	request_kind = "crate"
	time_limit = 20 SECONDS
	layout = list(
		"##########",
		"#B.....C.#",
		"##########")
	var/pack_type

/datum/bot_scenario/chat/request/console/crate_reply/setup()
	arena_area.department = "science"
	var/static/list/packs = list(/datum/supply_pack/materials/uranium20, /datum/supply_pack/materials/plasma20, /datum/supply_pack/materials/plastic50)
	pack_type = packs[(run_index - 1) % length(packs) + 1] //runs side by side share the station's lists

/datum/bot_scenario/chat/request/console/crate_reply/post_spawn()
	..()
	visitor.equip_to_slot_or_del(new /obj/item/radio/headset(visitor), ITEM_SLOT_EARS)

/datum/bot_scenario/chat/request/console/crate_reply/make_call()
	var/datum/supply_pack/P = SSshuttle.supply_packs[pack_type]
	var/datum/station_request/R = new
	R.id = ++GLOB.station_request_count
	R.from_dept = "Science"
	R.to_dept = to_dept
	R.priority = REQ_NORMAL_MESSAGE_PRIORITY
	R.body = body
	R.sender = "[visitor.real_name] (Chief Engineer)"
	R.sender_ref = WEAKREF(visitor)
	R.area_name = get_area_name(visitor, TRUE)
	R.location = get_turf(visitor)
	R.kind = request_kind
	R.order = new /datum/supply_order(P, visitor.real_name, "Chief Engineer", null, body)
	R.time = station_time_timestamp()
	request = R
	GLOB.station_requests += R
	GLOB.station_requests_by_id["[R.id]"] = R
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_STATION_REQUEST, R)

/datum/bot_scenario/chat/request/console/crate_reply/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!request || world.time < request_made_at() + 6 SECONDS)
		return BOT_GYM_PENDING
	var/datum/bot_request/taken
	for(var/datum/bot_request/BR as anything in GLOB.bot_requests)
		if(BR.station_request == request)
			taken = BR
	if(!taken)
		fail_reason = "the request never reached Cargo"
		return BOT_GYM_FAIL
	if(taken.radio_freq != FREQ_COMMON)
		fail_reason = "answered on [GLOB.reverseradiochannels["[taken.radio_freq]"]], which the asker can't hear"
		return BOT_GYM_FAIL
	var/list/delivery = GLOB.bot_cargo_deliveries[pack_type]
	if(!delivery || delivery[1] != "science")
		fail_reason = "the crate's not down to go round to Science"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/request/console/crate_reply/release_run()
	GLOB.bot_cargo_deliveries -= pack_type
	for(var/datum/bot_request/BR as anything in GLOB.bot_requests)
		if(BR.station_request == request)
			GLOB.bot_requests -= BR
	for(var/datum/bot_request/BR as anything in GLOB.bot_cargo_requests)
		if(BR.detail == pack_type)
			GLOB.bot_cargo_requests -= BR
	SSshuttle.shoppinglist.Cut()
	return ..()

/// "Mining, science needs silver" with nobody mining: the technician says so and puts in for a crate, to go round to Science. In the
/// user's round there were no miners and nobody answered it at all.
/datum/bot_scenario/chat/no_miners
	name = "cargo: Mining asked for silver with nobody mining, a technician says so and orders it for whoever's asking"
	desc = "Nobody's on Mining. Somebody says \"Mining, science needs silver\". The cargo technician answers that nobody's mining and puts in for a crate of silver, down to go round to Science."
	job = "Cargo Technician"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	var/pack_type

/datum/bot_scenario/chat/no_miners/post_spawn()
	..()
	var/static/list/packs = list("silver" = /datum/supply_pack/materials/silver20, "gold" = /datum/supply_pack/materials/gold20, "glass" = /datum/supply_pack/materials/glass50)
	var/what = packs[(run_index - 1) % length(packs) + 1] //runs side by side share the station's lists
	pack_type = packs[what]
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Mining, science needs [what]"), 2 SECONDS)

/datum/bot_scenario/chat/no_miners/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(!length(lines))
		if(world.time > start_time + 14 SECONDS)
			fail_reason = "said nothing"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	var/ordered = FALSE
	for(var/datum/bot_request/R as anything in GLOB.bot_cargo_requests)
		if(R.detail == pack_type)
			ordered = TRUE
	var/list/delivery = GLOB.bot_cargo_deliveries[pack_type]
	var/said_nobody = findtext(lowertext(lines[1]), "mining") || findtext(lowertext(lines[1]), "miners")
	if(said_nobody && ordered && delivery && delivery[1] == "science")
		return BOT_GYM_PASS
	fail_reason = "said \"[lines[1]]\"; [ordered ? "ordered" : "nothing ordered"], [delivery ? "for [delivery[1]]" : "for nobody"]"
	return BOT_GYM_FAIL

/datum/bot_scenario/chat/no_miners/release_run()
	GLOB.bot_cargo_deliveries -= pack_type
	for(var/datum/bot_request/R as anything in GLOB.bot_cargo_requests)
		if(R.detail == pack_type)
			GLOB.bot_cargo_requests -= R
	return ..()

/// A crate somebody's waiting for goes out on a MULE: pulled beside it, dragged on, the controls opened with the technician's ID,
/// Science's delivery beacon set and Go pressed; the MULE drops it there. The user ruled it, 2026-11-05: "Cargo orders it and uses
/// the mulebot to deliver it."
/datum/bot_scenario/mule_delivery
	name = "cargo: a crate somebody's waiting for goes out on a MULE to their delivery beacon"
	desc = "A crate of diamonds for Science, a free MULE and Science's delivery beacon at the far end. The cargo technician pulls the crate beside the MULE, loads it, opens its controls with its ID, sets the beacon and sends it; the MULE leaves the crate at the beacon."
	job = "Cargo Technician"
	time_limit = 150 SECONDS //a MULE under a full gym's load is slow
	layout = list(
		"##############",
		"#B.K.Q......Z#",
		"#............#",
		"##############")
	var/obj/structure/closet/crate/crate
	var/mob/living/simple_animal/bot/mulebot/mule
	var/obj/machinery/navbeacon/beacon
	var/beacon_tag
	var/pack_type
	var/rode = FALSE

/datum/bot_scenario/mule_delivery/setup()
	arena_area.department = "science"
	var/static/list/packs = list(/datum/supply_pack/materials/diamond20, /datum/supply_pack/materials/titanium20, /datum/supply_pack/materials/metal50)
	pack_type = packs[(run_index - 1) % length(packs) + 1] //runs side by side share the station's lists
	var/datum/supply_pack/P = SSshuttle.supply_packs[pack_type]
	crate = new /obj/structure/closet/crate(first_marker("K"))
	crate.name = P.crate_name
	mule = new(first_marker("Q"))
	mule.auto_return = FALSE
	mule.home_destination = null
	beacon_tag = "Gym Science [REF(src)]"
	beacon = new(first_marker("Z"))
	beacon.location = beacon_tag
	beacon.codes_txt = "delivery;dir=2"
	beacon.set_codes()
	GLOB.deliverybeacons |= beacon
	GLOB.deliverybeacontags |= beacon_tag
	GLOB.bot_cargo_deliveries[pack_type] = list("science", null)

/datum/bot_scenario/mule_delivery/post_spawn()
	var/obj/item/card/id/card = new(bot)
	card.access = list(ACCESS_CARGO, ACCESS_MAINT_TUNNELS)
	card.registered_name = bot.real_name
	card.assignment = "Cargo Technician"
	bot.equip_to_slot_or_del(card, ITEM_SLOT_ID)

/datum/bot_scenario/mule_delivery/make_goal()
	var/by_mule = text2path("/datum/bot_goal/deliver_crate/by_mule")
	if(by_mule)
		return new by_mule(crate, mule, beacon_tag)
	return new /datum/bot_goal/deliver_crate(crate) //the before build carries it round, if it can

/datum/bot_scenario/mule_delivery/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(crate))
		fail_reason = "the crate's gone"
		return BOT_GYM_FAIL
	if(crate.loc == mule)
		rode = TRUE
		return BOT_GYM_PENDING
	if(rode && isturf(crate.loc) && get_dist(crate, beacon) <= 1)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/mule_delivery/release_run()
	GLOB.bot_cargo_deliveries -= pack_type
	if(beacon)
		GLOB.deliverybeacons -= beacon
		GLOB.deliverybeacontags -= beacon_tag
	return ..()

/// A crate somebody's waiting for is gone for once it's off the MULE (bot_collabs.dm collect_delivery)
/datum/bot_scenario/duty/collect_off_mule
	name = "science: a crate riding a MULE is left till it's set down, then unpacked"
	desc = "Silver for Science is on a MULE. The scientist leaves it be until the MULE sets it down, then opens it and takes the silver out. A scientist used to go for it on its way, lose it, and forget it: the silver sat at Science's delivery windoor for the rest of the shift."
	duty_type = /datum/bot_duty/collect_delivery
	job = "Scientist"
	time_limit = 60 SECONDS
	layout = list(
		"##########",
		"#B....Q..#",
		"##########")
	var/obj/structure/closet/crate/crate
	var/mob/living/simple_animal/bot/mulebot/mule
	var/set_down_at

/datum/bot_scenario/duty/collect_off_mule/setup()
	arena_area.department = "science"
	mule = new(first_marker("Q"))
	mule.auto_return = FALSE
	mule.home_destination = null
	crate = new(get_turf(mule))
	crate.name = "silver sheets crate"
	new /obj/item/stack/sheet/mineral/silver(crate, 20)
	mule.load(crate)
	GLOB.bot_delivered_crates[crate] = list("science", null)

/datum/bot_scenario/duty/collect_off_mule/post_spawn()
	set_down_at = world.time + 12 SECONDS

/datum/bot_scenario/duty/collect_off_mule/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(crate.loc == mule)
		if(istype(brain.current_goal, /datum/bot_goal/unpack_crate))
			fail_reason = "went for the crate while it was still on the MULE"
			return BOT_GYM_FAIL
		if(world.time >= set_down_at)
			// Set down and left, as at a beacon once the MULE's gone home: a crate can't be opened with the MULE stood on it, and its
			// unload() leaves the crate under it
			mule.unload(WEST)
			crate.forceMove(get_step(mule, WEST))
		return BOT_GYM_PENDING
	if(!(crate in GLOB.bot_delivered_crates) && crate.opened)
		return BOT_GYM_PASS
	if(!(crate in GLOB.bot_delivered_crates))
		fail_reason = "the crate came off the list of delivered crates unopened"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/collect_off_mule/release_run()
	GLOB.bot_delivered_crates -= crate
	return ..()

/// A crate's manifest, stamped and left where it'll go back with the shuttle (goals/cargo.dm). Cargo's budget only ever went down, and
/// somebody's silver at Science's console (2000) went unordered with 1958 left in five shifts of six.
/datum/bot_scenario/file_manifest
	name = "cargo: a crate's manifest torn off, stamped and left on its spot"
	desc = "Two crates, each with its shipping manifest on, and the cargo technician has a rubber stamp. It tears the right one's manifest off, stamps it and leaves it where the crate stands, as it does aboard the supply shuttle to send it back for 200 credits. The other's manifest doesn't match its crate and is left on it."
	job = "Cargo Technician"
	time_limit = 40 SECONDS
	layout = list(
		"#########",
		"#B..K.J.#",
		"#########")
	var/obj/structure/closet/crate/crate
	var/obj/structure/closet/crate/wrong_crate
	var/obj/item/paper/fluff/jobs/cargo/manifest/manifest
	var/obj/item/paper/fluff/jobs/cargo/manifest/wrong_manifest

/datum/bot_scenario/file_manifest/setup()
	crate = new(first_marker("K"))
	manifest = new(crate, 1000 + run_index, 0)
	manifest.errors = 0
	crate.manifest = manifest
	crate.update_icon()
	wrong_crate = new(first_marker("J"))
	wrong_manifest = new(wrong_crate, 2000 + run_index, 0)
	wrong_manifest.errors = MANIFEST_ERROR_CONTENTS
	wrong_crate.manifest = wrong_manifest
	wrong_crate.update_icon()

/datum/bot_scenario/file_manifest/post_spawn()
	var/obj/item/stamp/stamp = new(get_turf(bot))
	bot.put_in_hands(stamp)

/datum/bot_scenario/file_manifest/make_goal()
	var/file_manifest = text2path("/datum/bot_goal/file_manifest")
	return file_manifest ? new file_manifest(crate) : null //the before build never touches a manifest

/datum/bot_scenario/file_manifest/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/to_file = text2path("/proc/bot_manifest_to_file")
	if(to_file && call(to_file)(wrong_crate))
		fail_reason = "the wrong manifest counts as one to send back"
		return BOT_GYM_FAIL
	if(wrong_crate.manifest != wrong_manifest || wrong_manifest.is_approved())
		fail_reason = "the wrong manifest was taken off or stamped"
		return BOT_GYM_FAIL
	if(crate.manifest || !manifest.is_approved())
		return BOT_GYM_PENDING
	if(manifest.loc != get_turf(crate))
		fail_reason = "stamped, but left at [manifest.loc] instead of the crate's spot"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// Sending one (goals/station_requests.dm try_console_request()): at a console, the quick request button rather than the radio
/datum/bot_scenario/console_quick_request
	name = "requests console: wanting a doctor at a requests console, it presses the console's Doctor button"
	desc = "A bartender at the Bar's requests console wants a doctor. It presses the console's Doctor quick request, which goes to Medbay tracked on the consoles. The arena isn't on telecomms, so the console can't get it through and the bot calls on the radio after: what's judged is that it tried the console first. Bots never sent anything from a console."
	job = "Bartender"
	time_limit = 15 SECONDS
	layout = list(
		"#######",
		"#B....#",
		"#######")
	var/obj/machinery/requests_console/console
	var/requests_before = 0
	var/asked = FALSE

/datum/bot_scenario/console_quick_request/setup()
	var/turf/T = get_step(first_marker("B"), EAST) //on the floor in front of the wall, as a mapped one is
	console = new(T)
	console.department = "Bar"
	console.name = "Bar Requests Console"
	console.pixel_y = 30
	console.stat &= ~(NOPOWER|BROKEN) //an arena has no APC
	// Medbay's own console is what makes "Medbay" a department to send to. Every station has one; the small test map
	// has no consoles at all, and the request never got past the department check (a full-run flake on testbench).
	if(!GLOB.req_console_ckey_departments["medbay"])
		GLOB.req_console_ckey_departments["medbay"] = "Medbay"

/datum/bot_scenario/console_quick_request/make_goal()
	return null

/datum/bot_scenario/console_quick_request/post_spawn()
	brain.gym_scripted = FALSE //call_for() keeps a scripted bot quiet
	var/mob/living/carbon/human/doctor = stand_in(locate(first_marker("B").x + 4, first_marker("B").y, first_marker("B").z), "Medbay Doctor")
	doctor.mind_initialize()
	doctor.mind.assigned_role = "Medical Doctor" //somebody to hear it, or nobody's asked
	requests_before = length(GLOB.station_requests)

/datum/bot_scenario/console_quick_request/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!asked)
		asked = TRUE
		brain.call_for(/datum/bot_request_kind/medical, "Could use a medic in the Bar.")
		return BOT_GYM_PENDING
	for(var/i in requests_before + 1 to length(GLOB.station_requests))
		var/datum/station_request/R = GLOB.station_requests[i]
		if(R.kind == "Doctor" && R.from_dept == "Bar")
			log_line("sent \"[R.body]\" to [R.to_dept]")
			return BOT_GYM_PASS
	if(length(console.req_notice) && findtext(console.req_notice[1], "Medbay"))
		log_line("pressed the console's Doctor button: [console.req_notice[1]]")
		return BOT_GYM_PASS
	if(bot_transcript_said("called for a medical"))
		fail_reason = "called on the radio without trying the console"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/console_quick_request/release_run()
	if(!QDELETED(console))
		qdel(console)
	return ..()
