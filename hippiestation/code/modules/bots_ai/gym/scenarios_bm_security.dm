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
