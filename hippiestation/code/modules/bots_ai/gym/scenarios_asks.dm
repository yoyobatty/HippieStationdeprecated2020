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
	// A name of its own: the HoP checks Security's records by name, and another arena's "Casey Visitor" was sometimes
	// set to arrest in them - the HoP refused this one as wanted (a full-run flake, every run).
	visitor.real_name = "Hollis Applicant"
	visitor.name = visitor.real_name
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
	// A running timer outlives the arena, and the next arena built on the same turfs reads as inside a cell: Security left anybody
	// standing there alone (brigged_by_another(), goals/security_patrol.dm)
	if(!QDELETED(timer) && timer.timing)
		timer.timer_end(forced = TRUE)
	GLOB.bot_brig_sentences -= timer
	return ..()

/datum/bot_scenario/brigged/trapdoor_open
	name = "brig: a cell whose trapdoor is still open from the last release isn't free"
	desc = "Shift base1108n: on the Hippie map every cell has a trapdoor that opens for two minutes when a sentence ends. The Warden picked Cell 4 a second after its last prisoner went down it, couldn't stand on the open trapdoor to swap with Lane Sorensen, and failed 'isn't inside Cell 4' eleven times before it closed. It takes the next cell."
	layout = list(
		"#############",
		"#BC..i....j.#",
		"####d#####k##",
		"###...###...#",
		"###.ql###..n#",
		"#############")
	var/obj/machinery/door_timer/timer_b
	var/obj/machinery/disposal/trapdoor/trap

/datum/bot_scenario/brigged/trapdoor_open/setup()
	..()
	var/id = "gymcellb[rand(1, 99999)]"
	var/obj/machinery/door/window/brigdoor/door = new(first_marker("k"))
	door.dir = SOUTH
	door.id = id
	place("k", door)
	var/obj/structure/closet/secure_closet/brig/locker_b = new(first_marker("n"))
	locker_b.id = id
	place("n", locker_b)
	timer_b = new(first_marker("j"))
	timer_b.id = id
	timer_b.targets = list(door, locker_b)
	timer_b.stat &= ~BROKEN
	place("j", timer_b)
	trap = new(first_marker("q"))
	place("q", trap)
	trap.open() //the last prisoner's just gone down it

/datum/bot_scenario/brigged/trapdoor_open/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("can't process them there"))
		fail_reason = "tried the cell with the open trapdoor: [prisoner] wouldn't go in"
		return BOT_GYM_FAIL
	if(timer.timing)
		fail_reason = "brigged them in the cell with the open trapdoor"
		return BOT_GYM_FAIL
	if(!timer_b.timing)
		return BOT_GYM_PENDING
	return (get_turf(prisoner) in bot_get_cell_interior(timer_b)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/brigged/trapdoor_open/release_run()
	if(!QDELETED(timer_b) && timer_b.timing)
		timer_b.timer_end(forced = TRUE)
	GLOB.bot_brig_sentences -= timer_b
	if(trap)
		GLOB.bot_open_trapdoors -= get_turf(trap)
	return ..()

/datum/bot_scenario/set_down_two
	name = "set down: going back for one thing, it doesn't switch to another halfway"
	desc = "Shift base1108n: a botanist with two seed packs set down went back and forth between them for over a minute, going for whichever came into view first each step. It finishes going for the one it set off for."
	layout = list(
		"############",
		"#B...a...b.#",
		"############")
	time_limit = 20 SECONDS
	var/obj/item/near_one
	var/obj/item/far_one

/datum/bot_scenario/set_down_two/post_spawn()
	near_one = new /obj/item/screwdriver(first_marker("a"))
	far_one = new /obj/item/wrench(first_marker("b"))
	// The far one first, as the shift had it: set down earlier, further on
	brain.set_down_items = list(far_one, near_one)
	// What its own brain does between jobs (process(), bot_brain.dm), called here: a gym bot left to its own brain answers the other
	// arenas' calls and requests, and twenty scenarios in the full run timed out
	go_back_tick()

/datum/bot_scenario/set_down_two/proc/go_back_tick()
	if(result != BOT_GYM_PENDING || QDELETED(bot))
		return
	if(brain.set_down_items && brain.state == BOT_STATE_WANDER)
		brain.go_back_for_set_down()
	addtimer(CALLBACK(src, PROC_REF(go_back_tick)), 1)

/datum/bot_scenario/set_down_two/make_goal()
	return null

/datum/bot_scenario/set_down_two/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "back for the wrench"))
			fail_reason = "walked past the screwdriver it was going for, to the wrench that came into view"
			return BOT_GYM_FAIL
		if(findtext(line, "back for the screwdriver"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

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

/datum/bot_scenario/duty/tidies_up
	name = "pursuits: out to keep the station nice, it bins the litter"
	desc = "A bot whose pursuit this part of the shift is keeping the station nice sees a crisp packet on the floor and puts it in the bin."
	duty_type = /datum/bot_duty/tidy_up
	layout = list(
		"#########",
		"#B..j..u#",
		"#########")
	time_limit = 25 SECONDS
	var/obj/item/litter
	var/obj/machinery/disposal/bin/bin

/datum/bot_scenario/duty/tidies_up/setup()
	litter = new /obj/item/trash/chips(first_marker("j"))
	place("j", litter)
	bin = new(first_marker("u"))
	place("u", bin)

/datum/bot_scenario/duty/tidies_up/post_spawn()
	brain.set_pursuit(BOT_PURSUIT_UPKEEP, 10 MINUTES, "the gym")

/datum/bot_scenario/duty/tidies_up/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (litter.loc == bin) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/tidies_up/locked_bin
	name = "pursuits: the nearest bin is through a door it has no access to, so the litter goes in the one it can get to"
	desc = "Keeping the station nice, it picks up a crisp packet. The nearest bin is behind the kitchen door, which its ID doesn't open; the other is a few steps further along the corridor. An assistant set off for the kitchen's bin ten times in a shift, found no way to it, and gave up each time with the rubbish in its hand."
	job = "Assistant"
	layout = list(
		"###########",
		"#u...Bj.Dk#",
		"###########")

/datum/bot_scenario/duty/tidies_up/locked_bin/setup()
	litter = new /obj/item/trash/chips(first_marker("j"))
	place("j", litter)
	bin = new(first_marker("u"))
	place("u", bin)
	place("k", new /obj/machinery/disposal/bin(first_marker("k")))
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_KITCHEN)

/datum/bot_scenario/breaks_out
	name = "prisoner: a traitor in a cell gets its hidden crowbar out and goes at the window"
	desc = "A traitor locked in a cell, with a crowbar hidden up its back that the officer never looked for, and nobody about. It gets the crowbar out and breaks the cell window."
	layout = list(
		"#########",
		"#...i...#",
		"####d####",
		"###.Bw###",
		"###..l###",
		"#########")
	time_limit = 240 SECONDS
	var/obj/machinery/door_timer/timer
	var/obj/structure/window/window

/datum/bot_scenario/breaks_out/issue_goal()
	return

/datum/bot_scenario/breaks_out/setup()
	var/id = "gymcell[rand(1, 99999)]"
	var/obj/machinery/door/window/brigdoor/door = new(first_marker("d"))
	door.dir = SOUTH
	door.id = id
	var/obj/structure/closet/secure_closet/brig/locker = new(first_marker("l"))
	locker.id = id
	timer = new(first_marker("i"))
	timer.id = id
	timer.targets = list(door, locker)
	timer.stat &= ~BROKEN
	window = first_placed("w")

/datum/bot_scenario/breaks_out/post_spawn()
	brain.gym_scripted = FALSE
	brain.bot_traitor = TRUE
	brain.next_escape_try = world.time + 2 SECONDS
	var/obj/item/organ/butt/B = bot.getorgan(/obj/item/organ/butt)
	if(B)
		SEND_SIGNAL(B, COMSIG_TRY_STORAGE_INSERT, new /obj/item/crowbar/red(bot), null, TRUE, TRUE)
	timer.set_timer(10 MINUTES)
	timer.timer_start()

/datum/bot_scenario/breaks_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return QDELETED(window) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Not a test of any one answer: thirty-odd things a player says to somebody stood in front of them, one every few seconds, and
/// whether anything came back before the next. The transcript has each line and its answer, to read; it passes at two in three.
/datum/bot_scenario/chat/sweep
	name = "asks: a sweep of everyday lines, face to face"
	desc = "Hi, how are you, where's the captain, follow me, give me that, thanks, bye: what a player says to somebody stood in front of them. The user's \"bots need to respond to a lot more of my text\"."
	job = "Assistant"
	time_limit = 240 SECONDS
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	var/list/lines = list("hi", "hey", "how are you?", "what are you doing?", "where is the captain?", "can you help me?", "who are you?", "what's your job?", "do you have a crowbar?", "where's medbay?", "thanks", "lol", "are you a traitor?", "nice day isn't it", "i need a doctor", "have you seen the clown?", "what's going on?", "you there?", "excuse me", "sorry", "whats up", "can i have that?", "follow me", "wait here", "come with me", "are you ok?", "do you know where engineering is?", "what do you think of the captain?", "you're cool", "bye")
	var/next_line = 1
	var/list/said_at = list()

/datum/bot_scenario/chat/sweep/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(say_next)), 2 SECONDS)

/datum/bot_scenario/chat/sweep/proc/say_next()
	if(result != BOT_GYM_PENDING || next_line > length(lines))
		return
	said_at += length(transcript)
	visitor_says(lines[next_line++])
	addtimer(CALLBACK(src, PROC_REF(say_next)), 6 SECONDS)

/datum/bot_scenario/chat/sweep/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(next_line <= length(lines) || world.time < start_time + (length(lines) * 6 + 10) SECONDS)
		return BOT_GYM_PENDING
	var/answered = 0
	var/list/missed = list()
	for(var/i in 1 to length(said_at))
		var/first = said_at[i] + 1
		var/last = (i < length(said_at)) ? said_at[i + 1] : length(transcript)
		var/got = FALSE
		for(var/j in first to last)
			if(j <= length(transcript) && findtext(transcript[j], "said \""))
				got = TRUE
				break
		if(got)
			answered++
		else
			missed += lines[i]
	log_line("SWEEP: answered [answered] of [length(said_at)]; nothing back for: [english_list(missed)]")
	return answered * 3 >= length(said_at) * 2 ? BOT_GYM_PASS : BOT_GYM_FAIL

/datum/bot_scenario/sleeper_crit
	name = "medical rounds: somebody in crit goes in a shut sleeper, with epinephrine"
	desc = "Somebody's down in crit on the floor, and the sleeper beside them is shut and empty. The doctor opens it, drags them in, and gives them epinephrine, which holds crit off, not bicaridine or kelotane at random. A shut one used to take nobody, and the patient died on the floor by it."
	job = "Medical Doctor"
	layout = list(
		"#########",
		"#B..C..Y#",
		"#########")
	time_limit = 40 SECONDS
	var/obj/machinery/sleeper/sleeper
	var/mob/living/carbon/human/patient

/datum/bot_scenario/sleeper_crit/setup()
	sleeper = new(first_marker("Y"))
	place("Y", sleeper)

/datum/bot_scenario/sleeper_crit/post_spawn()
	give_job_id(list(ACCESS_MEDICAL))
	sleeper.close_machine() //shut, nobody in it
	patient = stand_in(first_marker("C"), "Drew Patient")
	patient.apply_damage(130, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/sleeper_crit/make_goal()
	return new /datum/bot_goal/escort_to_sleeper()

/datum/bot_scenario/sleeper_crit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(patient.stat == DEAD)
		fail_reason = "the patient died"
		return BOT_GYM_FAIL
	return (sleeper.occupant == patient && patient.reagents.has_reagent(/datum/reagent/medicine/epinephrine)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/sleeper_crit/unreachable_first
	name = "medical rounds: one in crit sealed off where it can't get, another it can: it takes the one it can reach"
	desc = "Two people down in crit: the nearer one sealed in behind walls (Q), the other on the floor by the sleeper. It tries for the nearer one, finds no way, and takes the other to the sleeper. A doctor used to try for the same unreachable patient again and again, 23 times in one shift, and see to nobody else."
	layout = list(
		"##########",
		"#B.....CY#",
		"##########",
		"#Q########",
		"##########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/sealed

/datum/bot_scenario/sleeper_crit/unreachable_first/post_spawn()
	..()
	sealed = stand_in(first_marker("Q"), "Sealed Patient")
	sealed.apply_damage(130, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/red_alert
	name = "security: a nanosuit at large, the HoS and the Captain take the station to red alert"
	desc = "A murderer in a nanosuit is wanted. The Head of Security calls red alert with the Captain: each goes to a keycard device, the HoS presses Red Alert and the Captain swipes inside the two seconds the devices give it. Red is when Space Law allows lethal force, and the comms console only goes to blue."
	job = "Head of Security"
	station_wide = TRUE
	layout = list(
		"###############",
		"#K..B.....C..k#",
		"#.............#",
		"#......N......#",
		"###############")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/captain
	var/mob/living/carbon/human/suspect

/datum/bot_scenario/red_alert/setup()
	for(var/c in list("K", "k"))
		for(var/turf/T in markers[c])
			place(c, new /obj/machinery/keycard_auth(T))

/datum/bot_scenario/red_alert/post_spawn()
	give_job_id(list(ACCESS_KEYCARD_AUTH, ACCESS_HEADS, ACCESS_SECURITY))
	set_security_level(SEC_LEVEL_GREEN)
	captain = second_bot(first_marker("C"), "Cap Tain")
	captain.mind.assigned_role = "Captain"
	suspect = stand_in(first_marker("N"), "Nano Suit")
	suspect.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(suspect), ITEM_SLOT_OCLOTHING)
	brain.file_crime(suspect, "Murder", "Gym.", BOT_CRIME_MAJOR)

/datum/bot_scenario/red_alert/issue_goal()
	var/datum/bot_duty/red_alert/D = bot_duty_of(/datum/bot_duty/red_alert)
	D.try_start(brain)

/datum/bot_scenario/red_alert/check()
	if(bot_lost())
		set_security_level(SEC_LEVEL_GREEN)
		return BOT_GYM_FAIL
	if(GLOB.security_level >= SEC_LEVEL_RED)
		set_security_level(SEC_LEVEL_GREEN) //nothing after this runs at red
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/red_alert/on_timeout()
	set_security_level(SEC_LEVEL_GREEN)
	GLOB.bot_red_alert_plan = null
	return ..()

/datum/bot_scenario/sleeper_crit/medipen
	name = "medical rounds: somebody in crit gets the medipen before they're dragged to the sleeper"
	desc = "The same patient down in crit, further off, and the doctor has the epinephrine medipen out of a first aid kit. It goes in before the drag. One brought up from Engineering in crit ran up a hundred of suffocation on the way and died in the sleeper."
	kit_backpack = list(/obj/item/reagent_containers/hypospray/medipen)
	layout = list(
		"###############",
		"#B.........C.Y#",
		"###############")

/datum/bot_scenario/sleeper_crit/medipen/check()
	if(bot_lost() || patient.stat == DEAD)
		return BOT_GYM_FAIL
	if(sleeper.occupant != patient)
		return BOT_GYM_PENDING
	for(var/line in transcript)
		if(findtext(line, "epinephrine into [patient]"))
			return BOT_GYM_PASS
	fail_reason = "in the sleeper without the medipen first"
	return BOT_GYM_FAIL

/datum/bot_scenario/job_round
	name = "rounds: an engineer goes round the SMES and the power monitor and looks them over"
	desc = "Nothing wrong, nothing asked for: an engineer between jobs walks a round of what matters in Engineering, stopping at each for a look. The user: every job walks a round of what matters every 5-15 minutes, diligent ones more often."
	job = "Station Engineer"
	layout = list(
		"###########",
		"#B...m...s#",
		"#.........#",
		"###########")
	time_limit = 60 SECONDS

/datum/bot_scenario/job_round/setup()
	arena_area.department = "engineering"
	for(var/turf/T in markers["m"])
		place("m", new /obj/machinery/computer/monitor(T))
	for(var/turf/T in markers["s"])
		place("s", new /obj/machinery/power/smes(T))

/datum/bot_scenario/job_round/issue_goal()
	var/datum/bot_duty/job_round/D = bot_duty_of(/datum/bot_duty/job_round)
	D.try_start(brain)

/datum/bot_scenario/job_round/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "goal /datum/bot_goal/job_round succeeded"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// The second half of the sweep: requests, orders and warnings rather than chat.
/datum/bot_scenario/chat/sweep/requests
	name = "asks: a sweep of requests, orders and warnings, face to face"
	desc = "What a player asks or tells somebody stood in front of them: open this, give me your ID, get back to work, watch out, heal me. Read the transcript for whether each answer fits."
	lines = list("can you open this door?", "give me your id", "drop it", "put your hands up", "what's your name?", "who's the captain?", "is the shuttle coming?", "get back to work", "you're fired", "watch out!", "run!", "fire!", "there's a breach!", "someone help", "i need insuls", "got any tools?", "can you fix this?", "heal me please", "i'm hurt", "can you clone me?", "do you know surgery?", "go away", "stop following me", "leave me alone", "shut up", "be quiet", "good morning", "how's the shift going?", "seen anything weird?", "take care")

/datum/bot_scenario/explorer_suit
	name = "pursuits: an explorer takes the explorer suit out of the suit storage and puts it on"
	desc = "Going out on Lavaland, the suit first: out of the mining suit storage unit and on, armour against what's out there. A raid for the lot left it in the bag."
	job = "Assistant"
	layout = list(
		"#######",
		"#B..U.#",
		"#######")
	time_limit = 30 SECONDS

/datum/bot_scenario/explorer_suit/setup()
	for(var/turf/T in markers["U"])
		place("U", new /obj/machinery/suit_storage_unit/mining(T))

/datum/bot_scenario/explorer_suit/make_goal()
	return new /datum/bot_goal/explorer_suit_up(first_placed("U"))

/datum/bot_scenario/explorer_suit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return istype(bot.wear_suit, /obj/item/clothing/suit/hooded/explorer) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/lava_moat
	name = "pursuits: an explorer with lava between it and the ruin gives up on it, not pacing the edge"
	desc = "Out for a ruin on Lavaland, the way to it runs out at a lava river: lava ahead and to the side, one tile back. It tries that and gives the ruin up. Two explorers paced the same two tiles at the edge of a lava river for most of a minute, the best step from each being the other, and one burned to death there."
	job = "Assistant"
	layout = list(
		"##############",
		"#R.......ll###",
		"#........lB###",
		"#........l.###",
		"##############")
	time_limit = 25 SECONDS
	max_goal_attempts = 1
	var/obj/effect/landmark/ruin/ruin
	var/turf/was_at
	var/moves = 0

/datum/bot_scenario/lava_moat/setup()
	for(var/turf/T in markers["l"])
		T.ChangeTurf(/turf/open/lava/smooth)
	ruin = new(first_marker("R"), null)
	place("R", ruin)

/datum/bot_scenario/lava_moat/post_spawn()
	brain.set_pursuit(BOT_PURSUIT_EXPLORE, 10 MINUTES, "the gym")

/datum/bot_scenario/lava_moat/make_goal()
	return new /datum/bot_goal/explore_ruin(ruin)

/datum/bot_scenario/lava_moat/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/T = get_turf(bot)
	if(was_at && T != was_at)
		moves++
	was_at = T
	if(istype(T, /turf/open/lava))
		fail_reason = "walked into the lava"
		return BOT_GYM_FAIL
	if(moves > 8)
		fail_reason = "paced the edge: [moves] steps without getting anywhere"
		return BOT_GYM_FAIL
	return istype(brain.current_goal, /datum/bot_goal/explore_ruin) ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/lava_moat/Destroy()
	QDEL_NULL(ruin)
	return ..()

/datum/bot_scenario/floor_goes
	name = "space: the floor ahead turns to space mid-walk (a shuttle leaving its dock), and it doesn't walk on to it"
	desc = "The bot sets off down a corridor, and the stretch ahead becomes open space while it's on the way, the way a dock does when the shuttle it was walking to leaves. No suit, so it doesn't step out into it: explorers stepped off the mining shuttle that way and drifted off into space."
	layout = list(
		"#############",
		"#B....xx...G#",
		"#############")
	time_limit = 20 SECONDS
	var/went = FALSE

/datum/bot_scenario/floor_goes/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(open_up)), 3)

/datum/bot_scenario/floor_goes/proc/open_up()
	for(var/turf/T in markers["x"])
		T.ChangeTurf(/turf/open/space/basic)
	went = TRUE

/datum/bot_scenario/floor_goes/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(isspaceturf(get_turf(bot)))
		fail_reason = "walked out into the space"
		return BOT_GYM_FAIL
	return (went && world.time > start_time + 15 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/dock_door
	name = "space: an airlock with open space behind it isn't opened without a suit"
	desc = "The way on is through an airlock, and the other side of it has gone to space (the shuttle that was docked there has left). No suit: it doesn't open it. A bot opened the mining dock's door with the shuttle gone and was blown out into space."
	layout = list(
		"###########",
		"#B...Dx..G#",
		"###########")
	time_limit = 20 SECONDS

/datum/bot_scenario/dock_door/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(shuttle_leaves)), 3) //after it has set off, the way planned through the door and the dock

/datum/bot_scenario/dock_door/proc/shuttle_leaves()
	for(var/turf/T in markers["x"])
		T.ChangeTurf(/turf/open/space/basic)

/datum/bot_scenario/dock_door/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(A && !A.density)
		fail_reason = "opened it on to space"
		return BOT_GYM_FAIL
	return world.time > start_time + 15 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/runs_in_thin_air
	name = "survival: out where the air's too thin to breathe, it still runs from what's after it"
	desc = "The air all round is too thin to breathe (Lavaland's is), and something it means to get away from is next to it. It runs anyway: anywhere else is no worse than where it stands. An explorer called out 'Back to the shuttle!' and went nowhere, every place it thought of being air it couldn't breathe, and a goliath beat it to death where it stood."
	layout = list(
		"#############",
		"#...BK......#",
		"#...........#",
		"#############")
	time_limit = 15 SECONDS
	var/mob/living/carbon/human/foe

/datum/bot_scenario/runs_in_thin_air/setup()
	for(var/char in markers)
		for(var/turf/open/F in markers[char])
			F.air.parse_gas_string("o2=6;n2=82;TEMP=293.15")
			F.update_visuals()
			SSair.add_to_active(F)

/datum/bot_scenario/runs_in_thin_air/post_spawn()
	foe = stand_in(first_marker("K"), "Big Beast")
	addtimer(CALLBACK(brain, TYPE_PROC_REF(/datum/bot_brain, run_from), foe, "the gym"), 1 SECONDS)

/datum/bot_scenario/runs_in_thin_air/make_goal()
	return null //running is the job

/datum/bot_scenario/runs_in_thin_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("can't breathe and I'm not suited up"))
		fail_reason = "wouldn't run anywhere it couldn't breathe"
		return BOT_GYM_FAIL
	// Where it runs to is a pick of the spots about (scored on getting away), so in an arena this size it can be only a few tiles.
	return (get_dist(bot, foe) >= 2 && bot_transcript_said("trying /datum/bot_strategy/run_from")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/runs_in_thin_air/not_into_it
	name = "survival: running from something in good air, it runs where the air's good, not into the bad"
	desc = "Something it means to get away from is next to it. The far end of the corridor, past a door, has air too thin to breathe. It runs the other way: picking the far end got the run refused, and it went nowhere."
	layout = list(
		"###############",
		"#..BK..Dyyyyyy#",
		"###############")
	time_limit = 25 SECONDS //it starts at once; under a full run's load the walk to a spot takes longer than 15

/datum/bot_scenario/runs_in_thin_air/not_into_it/setup()
	for(var/turf/open/F in markers["y"])
		F.air.parse_gas_string("o2=6;n2=82;TEMP=293.15")
		F.update_visuals()
		SSair.add_to_active(F)

/datum/bot_scenario/space_suit_up
	name = "pursuits: suiting up for a space ruin, it takes the suit, helmet and mask from the unit and puts the jetpack on"
	desc = "Off to a space ruin: the suit, the helmet and the mask out of EVA's suit storage and on, the tank where it can reach it, the backpack down by the unit, and a jetpack on the back, switched on."
	job = "Assistant"
	layout = list(
		"########",
		"#B..U.j#",
		"########")
	time_limit = 30 SECONDS
	kit_backpack = list(/obj/item/tank/internals/emergency_oxygen) //as a crew member's survival box has

/datum/bot_scenario/space_suit_up/setup()
	for(var/turf/T in markers["U"])
		place("U", new /obj/machinery/suit_storage_unit/standard_unit(T))
	for(var/turf/T in markers["j"])
		place("j", new /obj/item/tank/jetpack/carbondioxide(T))

/datum/bot_scenario/space_suit_up/make_goal()
	return new /datum/bot_goal/space_suit_up(first_placed("U"))

/datum/bot_scenario/space_suit_up/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/tank/jetpack/J = brain.worn_jetpack()
	if(brain.in_plain_space_suit() && J?.on && brain.eva_tank() && brain.stashed_bag?.resolve())
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/space_suit_up/cased
	name = "pursuits: suiting up for a space ruin, the jetpack's in a case behind a windoor, as on Meta, and it opens the case"
	desc = "Meta keeps its jetpacks on a rack behind a windoor. No route reaches through it: it walks up to the windoor, opens it, and takes the jetpack. Explorers on Meta never found one."

/datum/bot_scenario/space_suit_up/cased/setup()
	for(var/turf/T in markers["U"])
		place("U", new /obj/machinery/suit_storage_unit/standard_unit(T))
	for(var/turf/T in markers["j"])
		place("j", new /obj/structure/rack(T))
		place("j", new /obj/item/tank/jetpack/carbondioxide(T))
		var/obj/machinery/door/window/W = new(T)
		W.setDir(WEST)
		place("j", W)

/datum/bot_scenario/spoil_handed_in
	name = "pursuits: back from a ruin with a first-aid kit, an assistant leaves it on Medbay's desk"
	desc = "The user's ruling: what's brought back is kept, given to whoever needs it, or sold. A medkit's Medbay's: it goes on the desk with a word on the radio. (In the gym the arena's table stands in for the desk.)"
	job = "Assistant"
	layout = list(
		"#########",
		"#B.....t#",
		"#########")
	time_limit = 20 SECONDS
	var/obj/item/storage/firstaid/kit

/datum/bot_scenario/spoil_handed_in/post_spawn()
	kit = new /obj/item/storage/firstaid/regular(bot)
	bot.put_in_hands(kit)

/datum/bot_scenario/spoil_handed_in/make_goal()
	var/atom/where = brain.spoil_destination(kit)
	return where ? new /datum/bot_goal/deliver_spoil(kit, where) : null

/datum/bot_scenario/spoil_handed_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (get_turf(kit) == first_marker("t")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/red_alert/call_comes_in
	name = "security: a call for help on the way to the keycard device doesn't stop red alert"
	desc = "The same red alert, and a crewman shouts for Security as the Head of Security sets off for the device. It goes on to the device: in a played round the HoS answered a call sixteen seconds in, the Captain was left stood at the other one, and red alert never went up."
	layout = list(
		"###################################",
		"#K..............................B.#",
		"#k.C..............................#",
		"#................N................#",
		"###################################")
	var/mob/living/carbon/human/shouter
	var/called = FALSE

/datum/bot_scenario/red_alert/call_comes_in/post_spawn()
	..()
	shouter = stand_in(locate(bot.x + 1, bot.y - 2, bot.z), "Shou Ter") //behind it, thirty tiles from the devices

/datum/bot_scenario/red_alert/call_comes_in/check()
	if(!called && istype(brain.current_goal, /datum/bot_goal/red_alert))
		called = TRUE
		log_line("a call for help, with the HoS [get_dist(bot, brain.current_goal.target)] tiles off its device")
		brain.on_heard_security_call(shouter, "Help! Security!", FREQ_COMMON)
	if(istype(brain.current_goal, /datum/bot_goal/respond_to_call))
		fail_reason = "dropped the keycard device to answer the call"
		set_security_level(SEC_LEVEL_GREEN)
		GLOB.bot_red_alert_plan = null
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/hop_card_back
	name = "hopping: the wait at the HoP's door over, it goes back for its card a couple of tiles off"
	desc = "The bot has left its ID out for the HoP and been pushed two tiles along by somebody else come to wait at the door. Nobody came: it goes back and picks the card up before it leaves. Two bots walked off from their cards that way in a played round, and a doctor spent the shift locked out of Medbay."
	job = "Assistant"
	layout = list(
		"#######",
		"#B....#",
		"#######")
	time_limit = 25 SECONDS
	var/obj/item/card/id/card
	var/moved = FALSE

/datum/bot_scenario/hop_card_back/post_spawn()
	card = give_job_id(list())

/datum/bot_scenario/hop_card_back/make_goal()
	return new /datum/bot_goal/job_transfer/access(list(ACCESS_EVA), "EVA")

/datum/bot_scenario/hop_card_back/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!moved)
		var/datum/bot_step/paced/await_transfer/S = brain.current_strategy?.steps?[brain.current_step_index]
		if(isturf(card.loc) && istype(S))
			S.give_up_at = world.time //nobody came
			bot.forceMove(locate(bot.x + 2, bot.y, bot.z)) //shoved along by the next one to wait there
			moved = TRUE
			log_line("card down at [bot_coord(card)], bot pushed along to [bot_coord(bot)], the wait's over")
		return BOT_GYM_PENDING
	return bot.get_idcard(FALSE) == card ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/sleeper_crit/bandaged
	name = "medical rounds: somebody too far gone for the sleeper is bandaged before going in"
	desc = "The same, with the patient deeper in crit than the sleeper treats (it gives nothing but epinephrine under its min_health), and bruise packs in the doctor's bag. The doctor bandages them until the sleeper can take over, then puts them in. Patients used to go in as they were, get epinephrine, and suffocate in it."
	kit_backpack = list(/obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/bruise_pack)

/datum/bot_scenario/sleeper_crit/bandaged/post_spawn()
	..()
	patient.apply_damage(20, BRUTE, BODY_ZONE_L_ARM) //-50: below the sleeper's -25

/datum/bot_scenario/sleeper_crit/bandaged/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(patient.stat == DEAD)
		fail_reason = "the patient died"
		return BOT_GYM_FAIL
	if(sleeper.occupant != patient)
		return BOT_GYM_PENDING
	if(patient.health <= sleeper.min_health)
		fail_reason = "put in the sleeper at [round(patient.health)] health, where it can only give epinephrine"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/sleeper_crit/bandaged/suited
	name = "medical rounds: somebody too far gone for the sleeper, in a firesuit, has it taken off and is bandaged"
	desc = "The same, the patient in an emergency firesuit, which a bruise pack doesn't get through. The doctor takes the suit off, bandages them and puts them in. It used to give up on the bandaging and put them in as they were."

/datum/bot_scenario/sleeper_crit/bandaged/suited/post_spawn()
	..()
	patient.equip_to_slot_or_del(new /obj/item/clothing/suit/fire/firefighter(patient), ITEM_SLOT_OCLOTHING)

/datum/bot_scenario/give_blood
	name = "medical rounds: somebody pale from losing blood is put on a drip with blood they can take"
	desc = "A patient's lost a lot of blood (pale skin). The doctor opens the freezer crate, takes an O- pack, puts it on an IV drip, wheels the drip over and attaches it, stays while it goes in, and takes the needle out once they've their colour back. Nobody was ever given blood, and patched-up patients suffocated in Medbay from what they'd lost."
	job = "Medical Doctor"
	layout = list(
		"##########",
		"#B..K..I.#",
		"#....C...#",
		"##########")
	time_limit = 60 SECONDS
	var/obj/machinery/iv_drip/drip
	var/mob/living/carbon/human/patient
	var/given = FALSE

/datum/bot_scenario/give_blood/setup()
	var/obj/structure/closet/crate/freezer/crate = new(first_marker("K"))
	place("K", crate)
	new /obj/item/reagent_containers/blood/OMinus(crate)
	drip = new(first_marker("I"))
	place("I", drip)

/datum/bot_scenario/give_blood/post_spawn()
	give_job_id(list(ACCESS_MEDICAL))
	patient = stand_in(first_marker("C"), "Pale Patient")
	patient.blood_volume = 350

/datum/bot_scenario/give_blood/make_goal()
	var/path = text2path("/datum/bot_goal/give_blood") // by name: a build without it has no such goal
	return path ? new path() : null

/datum/bot_scenario/give_blood/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(drip.attached == patient)
		given = TRUE
		return BOT_GYM_PENDING
	if(!given)
		return BOT_GYM_PENDING
	if(patient.blood_volume < BLOOD_VOLUME_SAFE && drip.beaker?.reagents?.total_volume)
		fail_reason = "took them off the drip at [round(patient.blood_volume)] blood with some left in the pack"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS //on it, then off it once they'd had enough
