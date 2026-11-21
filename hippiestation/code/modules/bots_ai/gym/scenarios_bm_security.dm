// Bot gym scenarios from the 2026-11-21 bot audit, security area.
//
// What a scenario refers to that only the fix adds is reached by name (GLOB.vars["bot_cell_waiting"], case.vars["passed_over"]), so the
// "before" build of ab_gym.sh compiles and the scenario fails there on what the bots do, not on a missing symbol.

/// A cell's queue entry as the fix keeps it, put in by hand: REF(prisoner) -> list(weakref, first turned away, last asked about)
/datum/bot_scenario/brigged/proc/queue_for_a_cell(mob/living/carbon/human/P, how_long)
	var/list/line = GLOB.vars["bot_cell_waiting"]
	if(islist(line))
		line[REF(P)] = list(WEAKREF(P), world.time - how_long, world.time)

/// Brigged, with the only cell already taken by somebody (its timer running, and the door shut on nobody in particular).
/datum/bot_scenario/brigged/full_brig
	name = "brig: with every cell full, somebody held for vandalism who's waited a while is let off with a warning"
	desc = "Shift batches play1114b and gen1116f: a fifth of the arrests waited more than three minutes for a cell, the longest twenty, cuffed on a hallway floor. A lenient officer with a prisoner held for something that isn't violence, who has waited four minutes for a cell and none's free, walks up, says so and takes the cuffs off, rather than going round the same full brig for ever."
	time_limit = 45 SECONDS

/datum/bot_scenario/brigged/full_brig/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_NORMAL) //not a paranoid one: eight minutes
	brain.strictness = 0.3 //a lenient one
	var/datum/bot_wanted/W = bot_get_wanted_entry(prisoner)
	W.crime = "Vandalism"
	W.severity = BOT_CRIME_MINOR
	timer.set_timer(10 MINUTES)
	timer.timer_start() //the one cell there is, taken
	queue_for_a_cell(prisoner, 4 MINUTES)

/datum/bot_scenario/brigged/full_brig/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!prisoner.handcuffed && !bot_is_wanted(prisoner))
		return BOT_GYM_PASS
	fail_reason = "the prisoner's still [prisoner.handcuffed ? "cuffed" : "free but wanted"] with no cell to go in"
	return BOT_GYM_PENDING

/// The same wait for a strict officer: not long enough for them yet.
/datum/bot_scenario/brigged/full_brig/strict
	name = "brig: with every cell full, a strict officer keeps the same prisoner cuffed a while longer"
	desc = "Four minutes isn't a long wait to a strict officer: the prisoner stays held for a cell (the control for the lenient one)."
	time_limit = 20 SECONDS

/datum/bot_scenario/brigged/full_brig/strict/post_spawn()
	..()
	brain.strictness = 0.9

/datum/bot_scenario/brigged/full_brig/strict/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!prisoner.handcuffed)
		fail_reason = "let the prisoner go after only four minutes of waiting"
		return BOT_GYM_FAIL
	return world.time - start_time > 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Violence is never let off for want of room, however long they've waited.
/datum/bot_scenario/brigged/full_brig/violent
	name = "brig: with every cell full, somebody held for assault isn't let off however long they've waited"
	desc = "A lenient officer, ten minutes of waiting, and the charge is assault: they stay cuffed."
	time_limit = 20 SECONDS

/datum/bot_scenario/brigged/full_brig/violent/post_spawn()
	..()
	var/datum/bot_wanted/W = bot_get_wanted_entry(prisoner)
	W.crime = "Assault"
	W.severity = BOT_CRIME_MINOR
	queue_for_a_cell(prisoner, 10 MINUTES)

/datum/bot_scenario/brigged/full_brig/violent/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!prisoner.handcuffed)
		fail_reason = "let somebody held for assault go for want of a cell"
		return BOT_GYM_FAIL
	return world.time - start_time > 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Two cuffed prisoners, one cell free: the one held for worse, who's been waiting, goes in first, not the one brought in last.
/datum/bot_scenario/brigged/first_in_line
	name = "brig: a cell that comes free goes to the one who's waited and is held for worse, not whoever's brought in next"
	desc = "Shift batch play1114b run2: a prisoner waited twenty minutes for a cell while three came free, each taken by somebody arrested after him. An officer with a fresh arrest at the door and a cuffed man held for major vandalism who's been turned away for two minutes: the cell is his."
	layout = list(
		"#########",
		"#Y......#",
		"#CB..i..#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/waiting

/datum/bot_scenario/brigged/first_in_line/post_spawn()
	..()
	waiting = stand_in(first_marker("Y"), "Wendy Waiting")
	waiting.equip_to_slot_or_del(new /obj/item/card/id(waiting), ITEM_SLOT_ID)
	waiting.handcuffed = new /obj/item/restraints/handcuffs(waiting)
	waiting.update_handcuffed()
	var/datum/bot_wanted/W = new
	W.crime = "Major Vandalism"
	W.severity = BOT_CRIME_MAJOR
	GLOB.bot_security_wanted[WEAKREF(waiting)] = W
	queue_for_a_cell(waiting, 2 MINUTES)

/datum/bot_scenario/brigged/first_in_line/make_goal()
	var/datum/bot_goal/brig_prisoner/G = new()
	G.prisoner = goal_attempts <= 1 ? prisoner : waiting //the fresh arrest first, and then whoever's next for the cell
	return G

/datum/bot_scenario/brigged/first_in_line/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!timer.timing)
		return BOT_GYM_PENDING
	var/datum/weakref/ref = GLOB.bot_brig_sentences[timer]
	var/who = ref?.resolve()
	if(who == waiting)
		return BOT_GYM_PASS
	fail_reason = "the cell went to [who ? who : "somebody"] with [waiting] still waiting for it"
	return BOT_GYM_FAIL

/datum/bot_scenario/brigged/first_in_line/release_run()
	GLOB.bot_security_wanted -= WEAKREF(waiting)
	var/list/line = GLOB.vars["bot_cell_waiting"]
	if(islist(line))
		line -= REF(waiting)
		line -= REF(prisoner)
	return ..()

/// The Warden gets to the cell for a lifer with nothing to cuff them with: it says so and the case goes to the next officer, instead of the
/// same duty sending it back every few seconds for the rest of the shift.
/datum/bot_scenario/brigged/perma_collect/no_cuffs
	name = "brig: a Warden with no cuffs who can't take a lifer out of the cell passes the case on"
	desc = "Shift batch play1114b: collect_prisoner ran 88, 71, 55 and 47 times a shift for one capital prisoner, the Warden walking to the cell, starting nothing and wandering off, and one lifer waited fourteen minutes for another officer to happen by. When the arrest doesn't start the officer notes why and hands the case on."
	kit_backpack = list()
	time_limit = 30 SECONDS

/datum/bot_scenario/brigged/perma_collect/no_cuffs/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/passed = case.vars["passed_over"]
	if(length(passed))
		return BOT_GYM_PASS
	fail_reason = "went to the cell and started nothing, and didn't hand the case on"
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Lethal force: armed isn't dangerous until they use it
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal
	name = "security: an officer doesn't go lethal on a vandal with a fire axe who hasn't hurt anybody"
	desc = "Shift batches play1114b run12 and gen1116f run11: an officer went \"lethal, armed and dangerous\" on an assistant and a chemist arrested for vandalism, who were holding the fire axe they were smashing windows with, and put seven and eleven laser shots into them. Greytiders are never killed (the user's ruling): armed only counts once they've hurt somebody or come at the officer. The officer has a laser and a taser; it never says it's going lethal."
	time_limit = 16 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded, /obj/item/gun/energy/laser, /obj/item/gun/energy/e_gun/advtaser)
	layout = list(
		"###############",
		"#B...........C#",
		"#.............#",
		"###############")
	var/obj/item/twohanded/fireaxe/axe
	/// The control: this one's laid into somebody a moment ago
	var/hurt_somebody = FALSE

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal/grief()
	GLOB.security_level = SEC_LEVEL_GREEN //a red alert left up by a scenario before this one makes lethal force fair for anybody
	axe = griefer_holds(/obj/item/twohanded/fireaxe)
	officers = list(bot)
	make_griefer_wanted("Major Vandalism", BOT_CRIME_MAJOR)
	if(hurt_somebody)
		var/mob/living/carbon/human/victim = stand_in(get_step(bot, SOUTH), "Vic Victim") //beside the officer, off the line of fire
		GLOB.bot_recent_aggression["[REF(griefer)]>[REF(victim)]"] = world.time
	brain.begin_arrest(griefer)

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/lethal = bot_transcript_said("Going lethal on")
	if(hurt_somebody)
		if(lethal)
			return BOT_GYM_PASS
		fail_reason = "didn't go lethal on somebody armed with a fire axe who's just hit somebody"
		return BOT_GYM_PENDING
	if(lethal)
		fail_reason = "went lethal on a vandal who hadn't hurt anybody"
		return BOT_GYM_FAIL
	return world.time > start_time + 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/armed/lethal/axe_vandal/hit_somebody
	name = "security: an officer does go lethal on somebody with a fire axe who's just laid into somebody"
	desc = "The control for the vandal: the same fire axe, and they've hit somebody in the last half minute."
	hurt_somebody = TRUE

// ---------------------------------------------------------------------------------------------
// A call for help
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/security_call_cap
	name = "security: a call for help draws two officers, not the whole of Security"
	desc = "Shift batches play1114b and gen1116f: two calls in three took four or more officers off their posts at once (all five or six on a third of them), for a flickering light or a locked door. Four officers hear somebody ask Security to come and look at something: two go, the others carry on. A call that says somebody's being attacked draws three (the next scenario)."
	job = "Security Officer"
	layout = list(
		"###########",
		"#BONM..C..#",
		"###########")
	time_limit = 10 SECONDS
	var/list/mob/living/carbon/human/others = list()
	var/mob/living/carbon/human/visitor
	var/called_at = 0
	/// What the visitor says, and how many officers it takes
	var/the_call = "Security, can somebody come and look at the light in here?"
	var/officers_wanted = 2

/datum/bot_scenario/security_call_cap/issue_goal()
	return

/datum/bot_scenario/security_call_cap/post_spawn()
	brain.register_security()
	for(var/mark in list("O", "N", "M"))
		var/mob/living/carbon/human/H = second_bot(first_marker(mark), "Officer [mark]")
		H.mind.assigned_role = "Security Officer"
		H.bot_brain.register_security()
		others += H
	visitor = stand_in(first_marker("C"), "Cal Caller")
	addtimer(CALLBACK(src, PROC_REF(call_it)), 2 SECONDS)

/datum/bot_scenario/security_call_cap/proc/call_it()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	called_at = world.time
	log_line("visitor: \"[the_call]\"")
	visitor.say(the_call)

/// Officers who took the call: a taken call sets next_security_call_time a minute ahead, in every build.
/datum/bot_scenario/security_call_cap/proc/answering()
	. = 0
	var/list/brains = list(brain)
	for(var/mob/living/carbon/human/H in others)
		brains += H.bot_brain
	for(var/datum/bot_brain/B as anything in brains)
		if(B.next_security_call_time > world.time)
			.++

/datum/bot_scenario/security_call_cap/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!called_at || world.time < called_at + 4 SECONDS)
		return BOT_GYM_PENDING
	var/n = answering()
	if(n == officers_wanted)
		return BOT_GYM_PASS
	fail_reason = "[n] of the four officers took the call, not [officers_wanted]"
	return BOT_GYM_FAIL

/datum/bot_scenario/security_call_cap/danger
	name = "security: a call that says somebody's being attacked draws three officers"
	desc = "The same four officers, and the visitor cries that somebody's attacking them: three go. (A cap of two for everything would leave a fight short.)"
	the_call = "Security! Somebody is attacking me in here!"
	officers_wanted = 3

// ---------------------------------------------------------------------------------------------
// Handcuffs stay on an officer
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/officer_keeps_cuffs
	name = "security: an officer with a pair of cuffs in one hand and a drink in the other doesn't put the cuffs on the floor for a pickup"
	desc = "Shift sec1121a: officers set their handcuffs down 'for a moment' to take something they passed (24 times in a 40-minute shift across five officers), then went to 'find a pair' (34 times) and now and then had nothing to cuff somebody with mid-arrest. With no bag to put them in and both hands full, the cuffs stay in hand and the pickup goes without."
	job = "Security Officer"
	layout = list(
		"#######",
		"#B..t.#",
		"#######")
	time_limit = 8 SECONDS
	var/obj/item/restraints/handcuffs/cuffs

/datum/bot_scenario/officer_keeps_cuffs/issue_goal()
	return

/datum/bot_scenario/officer_keeps_cuffs/post_spawn()
	brain.register_security()
	if(bot.back)
		qdel(bot.back) //nowhere to put anything: the hand's the only place
	bot.equip_to_slot_or_del(new /obj/item/flashlight(bot), ITEM_SLOT_BELT) //a belt with no room for cuffs on it
	bot.equip_to_slot_or_del(new /obj/item/lighter(bot), ITEM_SLOT_LPOCKET)
	bot.equip_to_slot_or_del(new /obj/item/lighter(bot), ITEM_SLOT_RPOCKET)
	cuffs = new /obj/item/restraints/handcuffs(bot)
	bot.put_in_hands(new /obj/item/reagent_containers/food/drinks/soda_cans/cola(bot))
	bot.put_in_hands(cuffs)
	addtimer(CALLBACK(src, PROC_REF(pass_something_by)), 2 SECONDS)

/datum/bot_scenario/officer_keeps_cuffs/proc/pass_something_by()
	if(result == BOT_GYM_PENDING && !QDELETED(bot))
		brain.make_room_for_item(FALSE) //what pickup_item() does for something it passes: both hands full
		log_line("made room for a pickup: cuffs [cuffs.loc]")

/datum/bot_scenario/officer_keeps_cuffs/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(cuffs))
		fail_reason = "the cuffs are gone"
		return BOT_GYM_FAIL
	if(isturf(cuffs.loc))
		fail_reason = "set the cuffs down on the floor for a pickup it passed"
		return BOT_GYM_FAIL
	return world.time > start_time + 5 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Not firing past a colleague going in
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/officer_colleague_going_in
	name = "security: an officer's shot at somebody with a colleague two steps from them isn't a clear one"
	desc = "Shift batches play1114b and gen1116f: officers hit each other with stun shots (and a laser now and then), one or two a shift, at somebody another officer was already going in on, a tile or two off the line. has_clear_shot() asked straight out: a colleague within two tiles of the target is in the way, a crewman there or nobody isn't (a crewman off the line is still crew_in_the_way's own business, and the same man three tiles off is neither)."
	job = "Security Officer"
	layout = list(
		"###########",
		"#B.......C#",
		"#.........#",
		"#.......O.#",
		"#.....N...#",
		"###########")
	time_limit = 6 SECONDS
	var/mob/living/carbon/human/target
	var/mob/living/carbon/human/colleague
	var/mob/living/carbon/human/crew
	var/asked = FALSE

/datum/bot_scenario/officer_colleague_going_in/issue_goal()
	return

/datum/bot_scenario/officer_colleague_going_in/post_spawn()
	brain.register_security()
	target = stand_in(first_marker("C"), "Tim Target")
	colleague = stand_in(first_marker("O"), "Officer Oliver")
	colleague.mind_initialize()
	colleague.mind.assigned_role = "Security Officer"
	crew = stand_in(first_marker("N"), "Cora Crew")
	crew.mind_initialize()
	crew.mind.assigned_role = "Assistant"

/datum/bot_scenario/officer_colleague_going_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!asked)
		asked = TRUE
		if(brain.has_clear_shot(target))
			fail_reason = "a colleague two steps from the target, and the shot's called clear"
			return BOT_GYM_FAIL
		colleague.forceMove(locate(bot.x + 1, bot.y + 2, bot.z)) //the control: the colleague well off now, and the crewman (off the line, three tiles off) still there
		return BOT_GYM_PENDING
	if(!brain.has_clear_shot(target))
		fail_reason = "nobody within two tiles of the target and the shot's still not clear"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// An officer with no ID (the user's ruling, 2026-11-12)
// ---------------------------------------------------------------------------------------------

/// A colleague with a card of its own, awake, and another officer on the books.
/datum/bot_scenario/brigged/proc/colleague_with_a_card(marker)
	var/mob/living/carbon/human/O = second_bot(first_marker(marker), "Officer Oduya")
	O.mind.assigned_role = "Security Officer"
	O.bot_brain.register_security()
	O.bot_brain.gym_scripted = FALSE //its duties run
	var/obj/item/card/id/C = new(O)
	C.registered_name = O.real_name
	C.assignment = "Security Officer"
	C.access = list(ACCESS_SECURITY, ACCESS_BRIG)
	O.equip_to_slot_or_del(C, ITEM_SLOT_ID)
	return O

/datum/bot_scenario/brigged/no_id
	name = "brig: an officer with no ID hands a cuffed prisoner to another officer, who takes them in"
	desc = "Shift batch gen1116f: four officers with no ID took a prisoner to the cell, searched and uncuffed them, found \"no access\" at the timer and gave up, with the prisoner loose again. The user's ruling (2026-11-12): hand the prisoner to another officer at once. This one has no card: it says so, lets go, and the other officer, who has, takes the prisoner into the cell and starts the sentence."
	layout = list(
		"#########",
		"#BC..iO.#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/colleague
	/// The officer asked for somebody else to take them in (seen on the books at a check)
	var/handed_over = FALSE
	/// Whether it starts at the arrest's end (start_brig_escort()), or already has the goal of taking them in
	var/starts_with_escort = TRUE

/datum/bot_scenario/brigged/no_id/post_spawn()
	..()
	brain.register_security()
	for(var/obj/item/card/id/mine in bot.GetAllContents())
		qdel(mine) //the base scenario gave it one
	colleague = colleague_with_a_card("O")

/// As a round does it: the arrest is done and it sets about taking them in.
/datum/bot_scenario/brigged/no_id/issue_goal()
	if(!starts_with_escort)
		return ..()
	goal_attempts++
	brain.start_brig_escort(prisoner)

/// Whether the officer's ask is on the list just now (not in a build without a list: nothing's ever asked)
/datum/bot_scenario/brigged/no_id/proc/asked_for_somebody()
	if("bot_handovers" in GLOB.vars)
		var/list/asked = GLOB.vars["bot_handovers"]
		return islist(asked) && asked[REF(prisoner)]
	return FALSE

/datum/bot_scenario/brigged/no_id/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(asked_for_somebody())
		handed_over = TRUE
	for(var/line in transcript)
		if(findtext(line, "no access to"))
			fail_reason = "took them to the cell and found no access at the timer"
			return BOT_GYM_FAIL
	if(timer.timing && (get_turf(prisoner) in bot_get_cell_interior(timer)))
		if(!starts_with_escort && (get_turf(bot) in bot_get_cell_interior(timer)))
			fail_reason = "the officer with no ID is still standing in the cell"
			return BOT_GYM_FAIL
		if(handed_over || !starts_with_escort) //the colleague may have come on it by itself, as it would: the cell's the thing
			return BOT_GYM_PASS
		fail_reason = "the prisoner got a sentence, but the officer with no ID never asked anybody to take them in"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/brigged/no_id/release_run()
	if("bot_handovers" in GLOB.vars)
		var/list/asked = GLOB.vars["bot_handovers"]
		if(islist(asked))
			asked -= REF(prisoner)
	return ..()

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop
	name = "asks: an officer who's lost its ID asks the HoP for a new one, once its prisoner's seen to"
	desc = "An officer with no card between jobs radios the HoP, who knows the face against the manifest, makes a card out in the Security Officer's name with Security's access, and brings it over. (The ruling of 2026-11-12: a replacement ID from the HoP after.)"
	job = "Head of Personnel"
	time_limit = 90 SECONDS
	layout = list(
		"##########",
		"#B.....I.#",
		"#..C...X.#",
		"##########")
	var/datum/data/record/manifest_entry
	/// When the officer looks at the duty
	var/looks_at = 3 SECONDS

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/setup()
	place("I", new /obj/machinery/computer/card(first_marker("I")))
	place("X", new /obj/item/storage/box/ids(first_marker("X")))

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/post_spawn()
	give_job_id(list(ACCESS_CHANGE_IDS, ACCESS_HEADS, ACCESS_HOP))
	brain.gym_scripted = FALSE //its duties run, as they would at its desk
	visitor = second_bot(first_marker("C"), "Olly Officer")
	visitor.mind.assigned_role = "Security Officer"
	visitor.bot_brain.register_security()
	for(var/obj/item/card/id/mine in visitor.GetAllContents())
		qdel(mine)
	manifest_entry = new
	manifest_entry.fields["name"] = visitor.real_name
	manifest_entry.fields["rank"] = "Security Officer"
	GLOB.data_core.general += manifest_entry
	addtimer(CALLBACK(src, PROC_REF(officer_looks)), looks_at)

/// The officer's own look at the duty, by hand: its AI left scripted, so it can't wander into the HoP's way (one run in eight failed to a
/// card that was picked up before it was made), while the duty itself is what's asked.
/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/proc/officer_looks()
	if(result != BOT_GYM_PENDING || QDELETED(visitor?.bot_brain))
		return
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/new_id_from_hop)
	if(!D)
		log_line("no such duty")
		return
	visitor.bot_brain.gym_scripted = FALSE //call_for() keeps a scripted bot quiet
	D.try_start(visitor.bot_brain)
	visitor.bot_brain.gym_scripted = TRUE

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/card/id/card in visitor.GetAllContents() + range(1, visitor))
		if(card.registered_name != visitor.real_name)
			continue
		if(card.assignment != "Security Officer" || !(ACCESS_SECURITY in card.access))
			fail_reason = "made the card out as [card.assignment], [length(card.access)] accesses"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/on_timeout()
	fail_reason = "no card for the officer"
	return BOT_GYM_FAIL

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/release_run()
	if(manifest_entry)
		GLOB.data_core.general -= manifest_entry
		manifest_entry = null
	..()

// ---------------------------------------------------------------------------------------------
// Kept in the Brig for a doctor who doesn't come
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/no_answer
	name = "brig: nobody answers the call for a doctor, and the officer puts the prisoner in a cell inside a minute, not after two and a half"
	desc = "Bot Shift gen1116e, gen1116f and play1114b: of 59 prisoners kept by the Brig's door for a doctor, one in five had one get to them. The rest stood there with an officer for two and a half minutes (median 100 game seconds, 27 over two minutes) with nobody coming. Now, with the call not taken by anybody and no medic near, the officer says so after forty-five seconds and puts them in a cell, patched up there."
	time_limit = 90 SECONDS

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/no_answer/doctor_near
	name = "brig: a doctor close by, the officer keeps the prisoner by the door for them past the minute"
	desc = "The control: a doctor stands a few steps off (not driven by anybody: nobody has taken the call), so the officer keeps waiting for them instead of cutting the wait short."
	layout = list(
		"#########",
		"#BC.Kio.#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	time_limit = 70 SECONDS
	var/mob/living/carbon/human/doctor

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/no_answer/doctor_near/post_spawn()
	..()
	doctor = doctor_on("o")

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/no_answer/doctor_near/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	keep_pale()
	if(bot_transcript_said("goal /datum/bot_goal/brig_prisoner/brig_care succeeded") || bot_transcript_said("no doctor's coming for"))
		fail_reason = "gave up waiting for a doctor standing a few steps off"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/no_answer/doctor_near/on_timeout()
	return BOT_GYM_PASS //still with the prisoner at the end of it

// ---------------------------------------------------------------------------------------------
// An accident a bot says sorry for
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/accident_sorry/bot_throws
	name = "accident: a crewman who throws a toolbox at a table and hits somebody on the way says sorry, and is forgiven, not arrested"
	desc = "Shift batch play1113e run9: the Captain's toolbox, thrown at a nanosuit, hit a crewman on the way. Nobody said sorry (a bot never did), so when the time ran out it was taken as the attack it looked like, and the Captain was arrested for Assault with a Deadly Weapon. Now the thrower, a bot, says sorry a few seconds after, and the one it hit forgives it."
	say_sorry = FALSE //the thrower's own brain says it

/datum/bot_scenario/chat/accident_sorry/bot_throws/post_spawn()
	..()
	visitor.mind_initialize()
	var/datum/bot_brain/thrower = new(visitor)
	thrower.gym_run = src
	thrower.gym_scripted = TRUE
	thrower.greytider = FALSE

/// With nobody else on to take the prisoner, the officer doesn't wait three minutes for somebody
/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/alone
	name = "asks: an officer with no ID and a cuffed prisoner, with no other officer on, asks the HoP at once and doesn't wait for somebody to take them"
	desc = "The same officer with no card, now with a prisoner in cuffs and no other officer on the station to hand them to: the ask for somebody to take the prisoner in stands for three minutes, and it used to hold the officer off the HoP for all of them. Now with nobody to take them it asks the HoP for its card straight away."
	layout = list(
		"##########",
		"#B.....I.#",
		"#..C.P.X.#",
		"##########")
	looks_at = 7 SECONDS //after its prisoner's been seen to (or not)
	var/mob/living/carbon/human/prisoner

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/alone/post_spawn()
	..()
	prisoner = stand_in(first_marker("P"), "Pat Prisoner")
	prisoner.handcuffed = new /obj/item/restraints/handcuffs(prisoner)
	prisoner.update_handcuffed()
	var/datum/bot_wanted/W = new
	W.crime = "Assault"
	W.severity = BOT_CRIME_MINOR
	GLOB.bot_security_wanted[WEAKREF(prisoner)] = W
	addtimer(CALLBACK(visitor.bot_brain, TYPE_PROC_REF(/datum/bot_brain, start_brig_escort), prisoner), 3 SECONDS)

/datum/bot_scenario/chat/officer_with_no_id_asks_the_hop/alone/release_run()
	GLOB.bot_security_wanted -= WEAKREF(prisoner)
	if("bot_handovers" in GLOB.vars)
		var/list/asked = GLOB.vars["bot_handovers"]
		if(islist(asked))
			asked -= REF(prisoner)
	return ..()

// ---------------------------------------------------------------------------------------------
// "One sec" is a second
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/one_sec_is_a_second
	name = "security: an officer who hears \"Sure, one sec.\" doesn't take it for a call to Security, and still answers a real one"
	desc = "Shift batches gen1116e, gen1116f and play1114b: officers answered \"on my way to sec office with the mop\", \"hang on, one sec\" and the like as calls for help, the word \"sec\" being Security's to them wherever it stood. The HoP's own answer to a request for an ID, \"Sure, one sec.\", sent an officer running to it in the gym. A crewman says it; the officer stays; then the crewman cries \"Sec! Somebody's attacking me!\" and the officer goes."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B.....C#",
		"#########")
	time_limit = 20 SECONDS
	var/said_real_one_at = 0

/datum/bot_scenario/chat/one_sec_is_a_second/post_spawn()
	..()
	brain.register_security()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Sure, one sec."), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Sorry, give me a sec."), 3 SECONDS)

/datum/bot_scenario/chat/one_sec_is_a_second/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!said_real_one_at)
		if(brain.next_security_call_time > world.time)
			fail_reason = "took \"one sec\" for a call to Security"
			return BOT_GYM_FAIL
		if(world.time > start_time + 7 SECONDS)
			said_real_one_at = world.time
			visitor_says("Sec! Somebody is attacking me in here!")
		return BOT_GYM_PENDING
	if(brain.next_security_call_time > world.time)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// With telecomms down the ask gets nowhere on the radio: it goes on the list when the officer tells a colleague who's come up to them
/datum/bot_scenario/brigged/no_id/radio_down
	name = "brig: with telecomms down, an officer with no ID tells the colleague who comes up to it, and only then is the prisoner taken in"
	desc = "The officer's ask for somebody to take the prisoner in is a radio call like any other (commit 246985cc): with nothing carried it's no use to anybody on the other side of the station, and is kept for the next officer it meets close by and told to their face. The colleague is walled off and not told anything for the first seconds, then comes up beside the officer, who tells them; the colleague takes the prisoner in."
	layout = list(
		"#########",
		"#BC..i..#",
		"####d####",
		"###...###",
		"###..l###",
		"#########",
		"#O#######",
		"#########")
	var/told_at = 0

/datum/bot_scenario/brigged/no_id/radio_down/setup()
	..()
	if("radio_down" in arena_area.vars)
		arena_area.vars["radio_down"] = TRUE

/datum/bot_scenario/brigged/no_id/radio_down/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!told_at)
		if(asked_for_somebody())
			fail_reason = "on the list from a radio call that never got out"
			return BOT_GYM_FAIL
		if(world.time > start_time + 5 SECONDS)
			told_at = world.time
			log_line("the colleague comes up to the officer")
			var/turf/T = locate(bot.x + 2, bot.y, bot.z)
			colleague.forceMove(T && !T.density ? T : get_step(bot, SOUTH))
			brain.tell_officer_in_person() //bot_radio.dm: its keep_an_eye_out() does this every few seconds, off for a scripted bot
			if(asked_for_somebody())
				handed_over = TRUE
		return BOT_GYM_PENDING
	return ..()

/// The card goes missing when it's got the prisoner to the cell
/datum/bot_scenario/brigged/no_id/late
	name = "brig: an officer who finds it has no ID in the cell with the prisoner still cuffed leaves the cell, and asks for another officer there"
	desc = "The officer has taken the prisoner into the cell as if it had its card, and finds it hasn't one. Standing in the cell it counts as occupying it (find_free_brig_cell()): a handover from inside left the colleague no free cell. It doesn't search and uncuff them for nothing either: it goes out to the timer, asks there, and the colleague takes the prisoner in."
	starts_with_escort = FALSE //the base scenario's goal to take the prisoner in
	time_limit = 100 SECONDS //the walk out, the ask, the colleague's walk in

/datum/bot_scenario/brigged/no_id/late/make_goal()
	return goal_attempts > 1 ? null : ..()
