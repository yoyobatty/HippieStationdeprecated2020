// Bot Gym scenarios for being asked things (bot_asks.dm): a job called by its title, "wait", "what you in for?", a job nobody's on,
// pleading when arrested, "X is a traitor!", and asking the HoP for access.

/datum/bot_scenario/chat/title_called
	name = "asks: a job called by its title answers"
	desc = "A crew member says \"cap\" to the Captain. That's being called, like a name: it answers."
	job = "Captain"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")

/datum/bot_scenario/chat/title_called/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "cap"), 2 SECONDS)

/datum/bot_scenario/chat/title_called/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return length(spoken()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/nobody_on_it
	name = "asks: a job nobody's on, somebody says so"
	desc = "A crew member calls for the lawyer and there isn't one. Somebody tells them, rather than the call going unanswered."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")

/datum/bot_scenario/chat/nobody_on_it/post_spawn()
	..()
	GLOB.bot_nobody_said -= "Lawyer"
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "lawyer?"), 2 SECONDS)

/datum/bot_scenario/chat/nobody_on_it/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in spoken())
		if(findtext(lowertext(line), "lawyer"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/waits
	name = "asks: told to wait, it stops and listens"
	desc = "The bot is walking off down a corridor. A crew member beside it says its name and \"wait!\". It stops where it is and asks what's up."
	layout = list(
		"#####################",
		"#BC................G#",
		"#####################")
	var/turf/stopped_at
	var/answered_at

/datum/bot_scenario/chat/waits/issue_goal()
	var/datum/bot_goal/walk_up_to/G = new(first_marker("G"))
	brain.gym_scripted = FALSE
	brain.assign_goal(G)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "[bot.first_name()], wait!"), 5)

/datum/bot_scenario/chat/waits/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!answered_at)
		if(!length(spoken()))
			return BOT_GYM_PENDING
		answered_at = world.time
		stopped_at = get_turf(bot)
		return BOT_GYM_PENDING
	if(world.time < answered_at + 4 SECONDS)
		return BOT_GYM_PENDING
	if(get_dist(bot, stopped_at) > 1)
		fail_reason = "walked on [get_dist(bot, stopped_at)] tiles after answering"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/in_for
	name = "asks: a prisoner says what it's in for"
	desc = "Somebody asks a bot in cuffs what it's in for. It says the charge it was brigged on, not \"no idea\"."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")

/datum/bot_scenario/chat/in_for/post_spawn()
	..()
	brain.last_charge = "Theft"
	bot.handcuffed = new /obj/item/restraints/handcuffs(bot)
	bot.update_handcuffed()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "hey [bot.first_name()], what you in for?"), 2 SECONDS)

/datum/bot_scenario/chat/in_for/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in spoken())
		if(findtext(lowertext(line), "theft"))
			return BOT_GYM_PASS
	return length(spoken()) ? BOT_GYM_FAIL : BOT_GYM_PENDING

/datum/bot_scenario/chat/plea
	name = "asks: arrested for hitting a traitor, it's let go on saying so"
	desc = "An officer's arresting a crew member for assault on somebody Security's after. The crew member says the other one's a traitor. The officer drops the charge."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"#########",
		"#B.C.T..#",
		"#########")
	var/mob/living/carbon/human/traitor

/datum/bot_scenario/chat/plea/post_spawn()
	..()
	traitor = stand_in(first_marker("T"), "Max Traitor")
	var/datum/bot_wanted/T = new
	T.crime = "Possession of Dangerous Equipment"
	T.severity = BOT_CRIME_MAJOR
	GLOB.bot_security_wanted[WEAKREF(traitor)] = T
	brain.file_crime(visitor, "Assault", "Punched Max Traitor.", BOT_CRIME_MINOR, traitor)
	brain.begin_arrest(visitor)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "why arrest me? he's a traitor!"), 2 SECONDS)

/datum/bot_scenario/chat/plea/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(visitor.handcuffed && bot_get_wanted_entry(visitor))
		return BOT_GYM_PENDING
	return bot_get_wanted_entry(visitor) ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/chat/plea/release_run()
	GLOB.bot_security_wanted -= WEAKREF(traitor)
	GLOB.bot_security_wanted -= WEAKREF(visitor)
	return ..()

/datum/bot_scenario/chat/accused
	name = "asks: a hunter officer believes \"X is a traitor!\" and goes for them"
	desc = "A crew member tells a hunter-minded officer Max is a traitor. It believes it, files it and goes to arrest Max."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"#########",
		"#B.C...M#",
		"#########")
	var/mob/living/carbon/human/max

/datum/bot_scenario/chat/accused/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_HUNTER)
	max = stand_in(first_marker("M"), "Max Adeyemi")
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Max is a traitor!"), 2 SECONDS)

/datum/bot_scenario/chat/accused/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (brain.arrest_suspect == max || max.handcuffed) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/accused/release_run()
	GLOB.bot_security_wanted -= WEAKREF(max)
	return ..()

/datum/bot_scenario/chat/hop_access
	name = "asks: the HoP asks what the access is for, then says to leave the card"
	desc = "A crew member asks the HoP for more access. It asks what for; told genetics, it agrees and says to put the ID on its desk."
	job = "Head of Personnel"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	var/asked_why = FALSE

/datum/bot_scenario/chat/hop_access/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "hop, can I get a lot more access?"), 2 SECONDS)

/datum/bot_scenario/chat/hop_access/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(!asked_why && length(lines))
		asked_why = TRUE
		addtimer(CALLBACK(src, PROC_REF(visitor_says), "for genetics, I'm cloning people"), 2 SECONDS)
	for(var/list/pending as anything in GLOB.bot_access_pending)
		var/datum/weakref/ref = pending[1]
		if(ref.resolve() == visitor)
			return length(lines) >= 2 ? BOT_GYM_PASS : BOT_GYM_PENDING
	return BOT_GYM_PENDING

/datum/bot_scenario/sleeper_check
	name = "medical rounds: a body left in a sleeper is taken out"
	desc = "Somebody died in a sleeper and is still in it. A doctor going round the machines opens it, so the body can go for cloning. In a played round two bodies stayed in Medbay's sleepers all shift with two doctors on."
	job = "Medical Doctor"
	layout = list(
		"#######",
		"#B...Y#",
		"#######")
	time_limit = 20 SECONDS
	var/obj/machinery/sleeper/sleeper
	var/mob/living/carbon/human/patient

/datum/bot_scenario/sleeper_check/setup()
	sleeper = new(first_marker("Y")) //S is space
	place("Y", sleeper)

/datum/bot_scenario/sleeper_check/post_spawn()
	give_job_id(list(ACCESS_MEDICAL))
	patient = stand_in(get_turf(sleeper), "Drew Patient")
	patient.death()
	sleeper.close_machine(patient)

/datum/bot_scenario/sleeper_check/make_goal()
	return new /datum/bot_goal/empty_machine()

/datum/bot_scenario/sleeper_check/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (!sleeper.occupant && isturf(patient.loc)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/brigged
	name = "brig: a prisoner's things go in the locker, and they go in orange"
	desc = "An officer brigs somebody it's cuffed. Everything but their clothes goes in the cell's locker (bag, ID, headset, gloves, what's in their hands and what a thorough officer finds hidden up their back), and they're put in the prison jumpsuit and shoes, then uncuffed and the timer started."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"#########",
		"#BC..i..#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/prisoner
	var/obj/machinery/door_timer/timer
	var/obj/structure/closet/secure_closet/brig/locker
	var/obj/item/hidden

/datum/bot_scenario/brigged/setup()
	var/id = "gymcell[rand(1, 99999)]"
	var/obj/machinery/door/window/brigdoor/door = new(first_marker("d"))
	door.dir = SOUTH
	door.id = id
	place("d", door)
	locker = new(first_marker("l"))
	locker.id = id
	place("l", locker)
	timer = new(first_marker("i"))
	timer.id = id
	timer.targets = list(door, locker)
	timer.stat &= ~BROKEN
	place("i", timer)

/datum/bot_scenario/brigged/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.strictness = 0.8 //a thorough one
	prisoner = stand_in(first_marker("C"), "Pat Prisoner")
	var/obj/item/card/id/card = new(prisoner)
	card.registered_name = prisoner.real_name
	prisoner.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	prisoner.equip_to_slot_or_del(new /obj/item/radio/headset(prisoner), ITEM_SLOT_EARS)
	prisoner.equip_to_slot_or_del(new /obj/item/clothing/gloves/color/yellow(prisoner), ITEM_SLOT_GLOVES)
	prisoner.put_in_hands(new /obj/item/screwdriver(prisoner))
	var/obj/item/organ/butt/B = prisoner.getorgan(/obj/item/organ/butt)
	hidden = new /obj/item/lighter(prisoner)
	if(B)
		SEND_SIGNAL(B, COMSIG_TRY_STORAGE_INSERT, hidden, null, TRUE, TRUE)
	prisoner.handcuffed = new /obj/item/restraints/handcuffs(prisoner)
	prisoner.update_handcuffed()
	var/datum/bot_wanted/W = new
	W.crime = "Assault"
	W.severity = BOT_CRIME_MINOR
	GLOB.bot_security_wanted[WEAKREF(prisoner)] = W

/datum/bot_scenario/brigged/make_goal()
	var/datum/bot_goal/brig_prisoner/G = new()
	G.prisoner = prisoner
	return G

/datum/bot_scenario/brigged/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!timer.timing)
		return BOT_GYM_PENDING
	var/list/kept = list()
	for(var/obj/item/I in list(prisoner.back, prisoner.wear_id, prisoner.ears, prisoner.gloves) + prisoner.held_items)
		kept += I.name
	if(hidden.loc != locker && !(hidden in locker.contents))
		kept += "the hidden [hidden.name] ([hidden.loc])"
	if(!istype(prisoner.w_uniform, /obj/item/clothing/under/rank/prisoner))
		kept += "their own jumpsuit"
	if(length(kept))
		fail_reason = "the prisoner still has [english_list(kept)]"
		return BOT_GYM_FAIL
	return prisoner.handcuffed ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/brigged/release_run()
	GLOB.bot_security_wanted -= WEAKREF(prisoner)
	return ..()

/datum/bot_scenario/barefoot_glass
	name = "barefoot: it walks round broken glass, not over it"
	desc = "A bot with no shoes on goes down a room with broken glass across the straight way. It goes round. Barefoot bots used to walk straight over it and cut their feet."
	layout = list(
		"##########",
		"#B..hh..G#",
		"#........#",
		"##########")
	time_limit = 20 SECONDS
	var/stepped_on_glass = FALSE

/datum/bot_scenario/barefoot_glass/setup()
	for(var/turf/T in markers["h"])
		place("h", new /obj/item/shard(T))

/datum/bot_scenario/barefoot_glass/post_spawn()
	qdel(bot.shoes)
	bot_refresh_hazards() //the glass on the map before it sets off: a scripted gym bot doesn't redraw it, the station's bots do

/datum/bot_scenario/barefoot_glass/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(locate(/obj/item/shard) in get_turf(bot))
		fail_reason = "walked over the glass barefoot"
		return BOT_GYM_FAIL
	return get_turf(bot) == first_marker("G") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/finds_shoes
	name = "barefoot: it finds some shoes and puts them on"
	desc = "A bot that's lost its shoes (cloned, stripped) sees a pair on the floor and puts them on."
	duty_type = /datum/bot_duty/find_shoes
	layout = list(
		"#########",
		"#B....o.#",
		"#########")
	time_limit = 25 SECONDS

/datum/bot_scenario/duty/finds_shoes/setup()
	place("o", new /obj/item/clothing/shoes/sneakers/black(first_marker("o")))

/datum/bot_scenario/duty/finds_shoes/post_spawn()
	qdel(bot.shoes)

/datum/bot_scenario/duty/finds_shoes/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot.shoes ? BOT_GYM_PASS : BOT_GYM_PENDING
