// Requests consoles (game/machinery/requests_console_requests.dm): what reaches a department over one is answered the way a
// call on the radio is (bot_requests.dm). A request is read for a call ("a doctor is needed", "hull breach", "Bar, two
// beers"), or failing that taken as one for the department's trade (Medbay a doctor, Janitorial cleaning, Engineering
// repairs). It's made at the console it came from, and the nearest of that trade who's free answers on the department's
// channel and goes there. Security sends the nearest free officer. Cargo puts in a crate that was asked for, and the
// request the console made leaves the cargo console's list.
// The console's tracking follows: "on it" with the bot's name when it takes the call, "done" when it gets there (or, for
// the janitor, who goes for the mop first, when it's there and the mess is gone; for Cargo, when the crate is ordered).

/datum/bot_request
	/// The requests console request this call came from, to keep its tracking
	var/datum/station_request/station_request

GLOBAL_DATUM(bot_station_request_listener, /datum/bot_station_request_listener)

/// Listens for requests going out, from the first bot on (SSdcs isn't up when globals are made)
/proc/bot_listen_for_station_requests()
	if(GLOB.bot_station_request_listener)
		return
	GLOB.bot_station_request_listener = new
	GLOB.bot_station_request_listener.RegisterSignal(SSdcs, COMSIG_GLOB_STATION_REQUEST, TYPE_PROC_REF(/datum/bot_station_request_listener, on_request))

/datum/bot_brain/New()
	. = ..()
	bot_listen_for_station_requests()

/datum/bot_station_request_listener/proc/on_request(datum/source, datum/station_request/R)
	// A moment for somebody to read it, or for it to come over the radio
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_take_up_station_request), R), rand(10, 30))

/// The department's channel, for answering on: the one the console's Topic() put the request out on
/proc/bot_department_freq(dept)
	switch(dept)
		if("medbay", "chiefmedicalofficersdesk", "virology", "genetics", "chemistry")
			return FREQ_MEDICAL
		if("engineering", "chiefengineersdesk", "atmospherics")
			return FREQ_ENGINEERING
		if("security", "headofsecuritysdesk")
			return FREQ_SECURITY
		if("cargobay", "mining")
			return FREQ_SUPPLY
		if("science", "researchdirectorsdesk", "robotics")
			return FREQ_SCIENCE
		if("janitorial", "bar", "kitchen", "hydroponics")
			return FREQ_SERVICE
		if("bridge", "captainsdesk", "headofpersonnelsdesk")
			return FREQ_COMMAND
	return FREQ_COMMON

/// The calls a department's staff would take from a request, read from what it says; the first is its trade's, for a request
/// that names none
/proc/bot_department_request_kinds(dept)
	switch(dept)
		if("medbay", "chiefmedicalofficersdesk", "virology", "genetics", "chemistry")
			return list(/datum/bot_request_kind/medical, /datum/bot_request_kind/cloning)
		if("janitorial")
			return list(/datum/bot_request_kind/janitor)
		if("engineering", "chiefengineersdesk", "atmospherics")
			return list(/datum/bot_request_kind/engineer)
		if("cargobay", "mining")
			return list(null, /datum/bot_request_kind/cargo_order)
		if("bar", "kitchen")
			return list(null, /datum/bot_request_kind/bar_order)
		if("science", "researchdirectorsdesk", "robotics")
			return list(null, /datum/bot_request_kind/research, /datum/bot_request_kind/upgrades)
	return null

/proc/bot_take_up_station_request(datum/station_request/R)
	if(!R || R.status != "new" || !R.location)
		return
	var/dept = ckey(R.to_dept)
	if(dept in list("security", "headofsecuritysdesk"))
		bot_security_take_station_request(R)
		return
	var/list/kinds = bot_department_request_kinds(dept)
	if(!kinds)
		return
	var/lower = lowertext(R.body)
	var/datum/bot_request_kind/kind
	if(R.kind == "crate" && R.order)
		kind = locate(/datum/bot_request_kind/cargo_order) in GLOB.bot_request_kinds
	else
		var/datum/bot_request_kind/read = bot_request_kind_of(lower, FALSE, R.location)
		if(read && (read.type in kinds))
			kind = read
		else if(kinds[1])
			kind = locate(kinds[1]) in GLOB.bot_request_kinds
	if(!kind)
		return
	var/mob/living/asker = R.sender_ref?.resolve()
	var/datum/bot_request/BR = bot_new_request(kind, asker, bot_department_freq(dept), R.location)
	BR.station_request = R
	if(R.kind == "crate" && R.order)
		BR.detail = R.order.pack.type
	else
		kind.read_details(BR, lower)
	bot_offer_request(BR)

/// Who's on it, as the console shows it
/datum/bot_brain/proc/station_request_name()
	return "[owner.real_name] ([work_role()])"

/datum/bot_brain/take_call(datum/bot_request/R)
	. = ..()
	if(!. || !R.station_request || R.station_request.status != "new")
		return
	R.station_request.set_status("on it", station_request_name())
	bot_log(src, "on it: the [R.station_request.from_dept] request \"[R.station_request.body]\"")
	if(!R.kind.walks_there && R.station_request.kind != "crate")
		addtimer(CALLBACK(src, PROC_REF(check_station_request_done), R.station_request, world.time + 5 MINUTES), 5 SECONDS)

/datum/bot_goal/answer_call/on_success(datum/bot_brain/bot)
	. = ..()
	if(request.station_request && request.station_request.status != "done")
		request.station_request.set_status("done", bot.station_request_name())
		bot_log(bot, "done: the [request.station_request.from_dept] request")

/// A call it bears in mind rather than walks to (the janitor goes for the mop and bucket first): done once it's there and
/// nothing's left to clean round the spot
/datum/bot_brain/proc/check_station_request_done(datum/station_request/R, give_up_at)
	if(QDELETED(owner) || !R || R.status == "done" || world.time > give_up_at)
		return
	var/turf/there = R.location
	if(there && get_dist(owner, there) <= 3 && owner.z == there.z)
		var/messy = FALSE
		for(var/turf/T in range(3, there))
			if(turf_has_mess(T))
				messy = TRUE
				break
		if(!messy)
			R.set_status("done", station_request_name())
			bot_log(src, "done: the [R.from_dept] request")
			return
	addtimer(CALLBACK(src, PROC_REF(check_station_request_done), R, give_up_at), 5 SECONDS)

/// A crate the budget doesn't cover: says so to whoever asked, on the channel they asked over, and the console's request reads "can't
/// afford" until it's ordered. It used to be put to one side without a word: the user asked for a Supermatter Shard (10,000 credits) at
/// the Chief Engineer's desk, and the cargo technician went for a snack. Whether the budget grows enough to order it is the cargo
/// round's (bot_next_cargo_request(), goals/orders.dm).
/datum/bot_request_kind/cargo_order/attend(datum/bot_brain/bot, datum/bot_request/R)
	. = ..()
	var/datum/supply_pack/P = SSshuttle.supply_packs[R.detail]
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	if(!P || !budget || P.cost <= budget.account_balance)
		return
	bot_log(bot, "can't afford [P.name] ([P.cost] credits, [budget.account_balance] in the budget)")
	if(R.station_request && R.station_request.status != "done")
		R.station_request.set_status("can't afford", bot.station_request_name())

/// The answer to an order: the budget, when it doesn't cover it, in place of "on it - ordering now"
/datum/bot_request_kind/cargo_order/ack_for(datum/bot_brain/bot, datum/bot_request/R)
	var/datum/supply_pack/P = SSshuttle.supply_packs[R.detail]
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	if(!P || !budget || P.cost <= budget.account_balance)
		return ..()
	var/mob/living/asker = R.caller_ref?.resolve()
	return "[asker ? "[asker.first_name()], the" : "The"] [lowertext(P.name)] is [P.cost] credits and Cargo's got [budget.account_balance]. I'll put it in once we can afford it."

/// The crate a request asked for has been ordered (goals/cargo.dm): the request the console made comes off the cargo console's
/// list, where it would otherwise wait to be ordered a second time
/proc/bot_station_request_ordered(datum/bot_request/asked, datum/supply_order/order, datum/bot_brain/bot)
	var/datum/station_request/R = asked?.station_request
	if(!R)
		return
	if(R.order)
		SSshuttle.requestlist -= R.order
		if(R.order.reason)
			order.reason = R.order.reason
	R.set_status("done", bot.station_request_name())

// ---------------------------------------------------------------------------------------------
// Security
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/respond_to_call
	/// The requests console request this answers, if it came from one
	var/datum/station_request/station_request

/// The nearest officer free to drop what they're doing goes to the console it came from, as for a call for help on the radio
/proc/bot_security_take_station_request(datum/station_request/R)
	var/turf/there = R.location
	var/mob/living/asker = R.sender_ref?.resolve()
	var/datum/bot_brain/best
	var/best_dist
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B) || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || !B.is_security_job() || B.goal_chain_pending || !B.can_drop_for_call())
			continue
		if(B.owner.z != there.z || B.owner.handcuffed)
			continue
		if(B.gym_run && (!asker || get_area(asker) != get_area(B.owner)))
			continue //a Bot Gym bot only hears its own arena
		var/dist = get_dist(B.owner, there)
		if(!best || dist < best_dist)
			best = B
			best_dist = dist
	if(!best)
		return
	if(best.state == BOT_STATE_GOAL)
		best.abandon_goals_for_arrest()
	var/datum/bot_goal/respond_to_call/G = new()
	G.caller_turf = there
	G.caller_name = asker ? asker.name : R.from_dept
	G.station_request = R
	if(!best.assign_goal(G))
		return
	R.set_status("on it", best.station_request_name())
	bot_log(best, "on it: the [R.from_dept] request \"[R.body]\"")
	best.say_after_typing(":s Responding to [R.from_dept]'s request in [R.area_name || get_area_name(there, TRUE)].")

/datum/bot_goal/respond_to_call/on_success(datum/bot_brain/bot)
	. = ..()
	if(station_request && station_request.status != "done")
		station_request.set_status("done", bot.station_request_name())
		bot_log(bot, "done: the [station_request.from_dept] request")
