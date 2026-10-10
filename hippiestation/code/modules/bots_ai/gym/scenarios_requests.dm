// Bot Gym scenarios for calls for help (bot_requests.dm). A stand-in crew member (C) does the calling, out loud
// from down the corridor; the bot is given no goal and judged on whether it answers and what it then does.
//
// Layout letters used here: o blood on the floor, M a mop, U a bucket of water.

/datum/bot_scenario/chat/request
	time_limit = 60 SECONDS
	/// What the visitor says, two seconds in.
	var/call_line
	/// The kind of call that is - the bot's reply has to be one of its acknowledgements.
	var/kind_type
	var/done_at

/datum/bot_scenario/chat/request/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(make_call)), 2 SECONDS)

/datum/bot_scenario/chat/request/proc/make_call()
	visitor_says(replacetext(call_line, "NAME", bot.first_name()))

/// The verdict once the job is done: a pass if the bot said it was coming. It gets a few seconds after finishing
/// to have said so - down a short corridor it's there before it has finished typing.
/datum/bot_scenario/chat/request/proc/verdict(done, unspoken_reason)
	if(!done)
		return BOT_GYM_PENDING
	if(acknowledged())
		return BOT_GYM_PASS
	if(!done_at)
		done_at = world.time
	if(world.time - done_at < 6 SECONDS)
		return BOT_GYM_PENDING
	fail_reason = unspoken_reason
	return BOT_GYM_FAIL

/// Whether the bot has said it's coming.
/datum/bot_scenario/chat/request/proc/acknowledged()
	var/datum/bot_request_kind/kind = locate(kind_type) in GLOB.bot_request_kinds
	for(var/line in spoken())
		if(line in kind.ack_lines)
			return TRUE
	return FALSE

/datum/bot_scenario/chat/request/medic
	name = "call: doctor answers a call for a medic"
	desc = "A hurt crew member down the corridor shouts for a doctor. The doctor says it's coming, walks over and patches them up - it had no other reason to: nobody handed it a patient."
	job = "Medical Doctor"
	layout = list(
		"##########",
		"#B.....C.#",
		"##########")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment)
	call_line = "I need a doctor over here!"
	kind_type = /datum/bot_request_kind/medical

/datum/bot_scenario/chat/request/medic/post_spawn()
	..()
	visitor.apply_damage(30, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/chat/request/medic/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return verdict(visitor.getBruteLoss() <= 10, "treated them without a word about being on its way")

/datum/bot_scenario/chat/request/janitor
	name = "call: janitor answers a call about a mess"
	desc = "A crew member stood by a pool of blood asks for the janitor. The janitor says it's coming, fetches the mop and bucket first, and mops it up."
	job = "Janitor"
	layout = list(
		"###########",
		"#BMU...Co.#",
		"###########")
	time_limit = 90 SECONDS
	call_line = "Janitor, can you clean this up please?"
	kind_type = /datum/bot_request_kind/janitor

/datum/bot_scenario/chat/request/janitor/setup()
	for(var/turf/T in markers["o"])
		place("o", new /obj/effect/decal/cleanable/blood(T))
	for(var/turf/T in markers["M"])
		place("M", new /obj/item/mop(T))
	for(var/turf/T in markers["U"])
		var/obj/item/reagent_containers/glass/bucket/B = new(T)
		B.reagents.add_reagent(/datum/reagent/water, 50)
		place("U", B)

/datum/bot_scenario/chat/request/janitor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/turf/T in arena_area)
		if(brain.turf_has_mess(T))
			return BOT_GYM_PENDING
	return verdict(TRUE, "mopped it up without a word about being on its way")

/datum/bot_scenario/chat/request/summons
	name = "call: comes over when asked for by name"
	desc = "A crew member down the corridor calls the bot by name and asks it to come over. It says it's coming, and does - whatever its job."
	job = "Assistant"
	layout = list(
		"##########",
		"#B.....C.#",
		"##########")
	time_limit = 30 SECONDS
	call_line = "NAME, can you come over here a second?"
	kind_type = /datum/bot_request_kind/summons

/datum/bot_scenario/chat/request/summons/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return verdict(get_dist(bot, visitor) <= 1 && brain.state == BOT_STATE_WANDER, "came over without a word")

/datum/bot_scenario/chat/request/just_talk
	name = "call: talk about a doctor isn't a call for one"
	desc = "A crew member down the corridor mentions what the doctor told them. Nobody asked for anything: the doctor stays where it is."
	job = "Medical Doctor"
	layout = list(
		"##########",
		"#B.....C.#",
		"##########")
	time_limit = 15 SECONDS
	call_line = "The doctor told me to drink more water."
	kind_type = /datum/bot_request_kind/medical

/datum/bot_scenario/chat/request/just_talk/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(acknowledged() || get_turf(bot) != first_marker("B"))
		fail_reason = "took a remark for a call"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/request/just_talk/on_timeout()
	return BOT_GYM_PASS

/// Whether the bot has said something that starts with these words.
/datum/bot_scenario/proc/bot_said_starting(start)
	for(var/line in transcript)
		var/at = findtext(line, "said \"")
		if(at && findtext(line, start, at + 6, at + 7 + length(start)))
			return TRUE
	return FALSE

/datum/bot_scenario/duty/bar/order
	name = "call: bartender mixes what was asked for"
	desc = "A customer at the bar asks for a black russian. The bartender says it's coming, mixes that - vodka at one machine, kahlua at the other - and says whose it is when it's on the bar."
	layout = list(
		"###########",
		"#O.b.s.t..#",
		"#B.....C..#",
		"###########")
	time_limit = 120 SECONDS
	var/mob/living/carbon/human/customer

/datum/bot_scenario/duty/bar/order/post_spawn()
	..()
	customer = stand_in(first_marker("C"), "Casey Customer")
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/duty/bar/order/proc/ask()
	if(result != BOT_GYM_PENDING || QDELETED(customer))
		return
	log_line("customer: \"Can I get a black russian please?\"")
	customer.say("Can I get a black russian please?")

/datum/bot_scenario/duty/bar/order/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!bot_said_starting("Black russian for Casey"))
		return BOT_GYM_PENDING
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G as anything in poured())
		if(G.reagents.has_reagent(/datum/reagent/consumable/ethanol/black_russian))
			return BOT_GYM_PASS
	fail_reason = "said the black russian was on the bar, and it isn't"
	return BOT_GYM_FAIL

/datum/bot_scenario/chat/let_out
	name = "call: opens the door for somebody shut in"
	desc = "Somebody is shut in a room whose door only this bot's ID opens, and has asked over the radio to be let out. The bot says it's coming, walks to the door and opens it."
	job = "Medical Doctor"
	layout = list(
		"############",
		"#B.....D.C.#",
		"############")
	time_limit = 40 SECONDS
	var/opened = FALSE

/datum/bot_scenario/chat/let_out/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_MEDICAL)

/datum/bot_scenario/chat/let_out/post_spawn()
	..()
	give_job_id(list(ACCESS_MEDICAL))
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/let_out/proc/ask()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	log_line("visitor (over the radio): \"Can somebody let me out? Door won't open for me.\"")
	var/datum/bot_request_kind/kind = locate(/datum/bot_request_kind/let_out) in GLOB.bot_request_kinds
	var/datum/bot_request/R = bot_new_request(kind, visitor, null, visitor)
	R.detail = list(first_placed("D"))
	bot_offer_request(R)

/datum/bot_scenario/chat/let_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(!A.density)
		opened = TRUE
	if(!opened)
		return BOT_GYM_PENDING
	var/datum/bot_request_kind/kind = locate(/datum/bot_request_kind/let_out) in GLOB.bot_request_kinds
	for(var/line in spoken())
		if(line in kind.ack_lines)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING
