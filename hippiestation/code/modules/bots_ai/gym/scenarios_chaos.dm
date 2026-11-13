// Bot Gym scenarios for being griefed, and for griefing: bot_reflexes.dm, bot_fighting.dm, bot_witness.dm, goals/greytide.dm.
//
// A stand-in with nobody driving it (C) plays the griefer. Everything it does to the bot is the real click, the one a
// player's would go through: UnarmedAttack() on an intent, melee_attack_chain() with something in hand. Run them again with
// bot-reflexes=off and all but the ones that pass by the bot doing nothing fail: that's the control.

/area/bot_gym
	/// The jobs this arena counts as staffed by (bot_staff_of(), bot_witness.dm).
	var/list/staff_jobs

/datum/bot_scenario
	/// The arena counts as where this bot works (is_my_department(), bot_witness.dm).
	var/arena_is_home = FALSE

/datum/bot_scenario/griefed
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/griefer
	var/griefer_name = "Griff Griefer"
	/// What the griefer's job says, if anything.
	var/griefer_job

/datum/bot_scenario/griefed/issue_goal()
	return

/datum/bot_scenario/griefed/post_spawn()
	griefer = stand_in(first_marker("C"), griefer_name)
	if(griefer_job)
		griefer.mind_initialize()
		griefer.mind.assigned_role = griefer_job
	griefer.setDir(get_dir(griefer, bot))
	addtimer(CALLBACK(src, PROC_REF(grief)), 2 SECONDS)

/// What the griefer does, once, a couple of seconds in.
/datum/bot_scenario/griefed/proc/grief()
	return

/datum/bot_scenario/griefed/proc/griefer_hand(intent, atom/at)
	if(QDELETED(griefer) || griefer.stat != CONSCIOUS)
		return
	griefer.a_intent = intent
	griefer.UnarmedAttack(at || bot, TRUE)

/datum/bot_scenario/griefed/proc/griefer_swing(obj/item/I, atom/at)
	griefer.a_intent = INTENT_HARM
	I.melee_attack_chain(griefer, at || bot)

/datum/bot_scenario/griefed/proc/griefer_holds(path)
	var/obj/item/I = new path(griefer)
	griefer.put_in_active_hand(I)
	return I

/// Keeps calling proc_name every `every` until it says it's done, or the scenario is.
/datum/bot_scenario/griefed/proc/keep_at_it(proc_name, every)
	if(result != BOT_GYM_PENDING || QDELETED(griefer))
		return
	if(call(src, proc_name)())
		addtimer(CALLBACK(src, PROC_REF(keep_at_it), proc_name, every), every)

/datum/bot_scenario/griefed/proc/bot_transcript_has(text)
	return bot_transcript_said(text)

/datum/bot_scenario/proc/bot_transcript_said(text)
	for(var/line in transcript)
		if(findtext(line, text))
			return TRUE
	return FALSE

/// A bot that ran for it, and got this far from the griefer. In a small arena it may well have arrived already.
/datum/bot_scenario/griefed/proc/got_away(tiles)
	return get_dist(bot, griefer) >= tiles && bot_transcript_has("run_from")

// ---------------------------------------------------------------------------------------------
// Hands on it
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/grabbed
	name = "griefing: grabbed hard, it breaks free"
	desc = "An aggressive grab counts as incapacitated, and a bot's brain used to stop right there: 27 grabs and shoves in one griefed round and not one attempt to get away. It presses Resist until it's free."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	var/gripped = FALSE

/datum/bot_scenario/griefed/grabbed/grief()
	griefer_hand(INTENT_GRAB)
	griefer_hand(INTENT_GRAB)
	gripped = griefer.grab_state >= GRAB_AGGRESSIVE
	log_line("griefer's grip: [griefer.grab_state]")

/datum/bot_scenario/griefed/grabbed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!gripped)
		return BOT_GYM_PENDING
	return griefer.pulling != bot ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer_holds
	name = "griefing: an officer's grip is left alone"
	desc = "The same grab from a security officer. A law-abiding crewmember doesn't wrestle the officer arresting them."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	griefer_name = "Olly Officer"
	griefer_job = "Security Officer"
	time_limit = 12 SECONDS
	var/gripped = FALSE //timers run late with the whole gym going

/datum/bot_scenario/griefed/officer_holds/grief()
	griefer_hand(INTENT_GRAB)
	griefer_hand(INTENT_GRAB)
	gripped = TRUE

/datum/bot_scenario/griefed/officer_holds/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(gripped && griefer.pulling != bot)
		fail_reason = "broke away from an officer"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer_holds/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/one_shove
	name = "griefing: one shove gets a word, not a fight"
	desc = "Somebody shoves it once. A person says something and carries on."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	time_limit = 10 SECONDS

/datum/bot_scenario/griefed/one_shove/grief()
	griefer.do_attack_animation(bot, ATTACK_EFFECT_DISARM)
	log_combat(griefer, bot, "shoved") //one shove and no more: a real disarm can knock it down, which isn't what this is about

/datum/bot_scenario/griefed/one_shove/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.state == BOT_STATE_COMBAT)
		fail_reason = "started a fight over one shove"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/one_shove/on_timeout()
	if(bot_transcript_has("telling"))
		return BOT_GYM_PASS
	fail_reason = "said nothing about it"
	return BOT_GYM_FAIL

/datum/bot_scenario/griefed/keeps_shoving
	name = "griefing: keeps shoving, it gets shoved back, then a fight"
	desc = "Somebody who won't stop: a word, a shove back, and a fight once it's had enough. Disarms and shoves used to mean nothing to a bot at all."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")

/datum/bot_scenario/griefed/keeps_shoving/post_spawn()
	..()
	brain.temper = 0.9

/datum/bot_scenario/griefed/keeps_shoving/grief()
	keep_at_it("shove", 15)

/datum/bot_scenario/griefed/keeps_shoving/proc/shove()
	griefer_hand(INTENT_DISARM)
	return brain.state != BOT_STATE_COMBAT

/datum/bot_scenario/griefed/keeps_shoving/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (brain.state == BOT_STATE_COMBAT && brain.attacker == griefer) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/disarmed
	name = "griefing: knocked out of its hand, it picks it back up"
	desc = "A disarm sends what it's holding to the floor. It picks it straight back up."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	kit_hands = list(/obj/item/crowbar)
	var/obj/item/crowbar/tool
	var/knocked = FALSE

/datum/bot_scenario/griefed/disarmed/grief()
	tool = locate() in bot.held_items
	keep_at_it("disarm", 10)

/datum/bot_scenario/griefed/disarmed/proc/disarm()
	griefer_hand(INTENT_DISARM)
	if(!(tool in bot.held_items) && isturf(tool.loc))
		knocked = TRUE
		log_line("knocked out of its hand")
		return FALSE
	return TRUE

/datum/bot_scenario/griefed/disarmed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (knocked && brain.is_carried(tool)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/locked_in
	name = "griefing: shut in a welded locker, it breaks out"
	desc = "Stuffed in a locker and welded in. It leans on the door the way a player does until it gives."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	var/obj/structure/closet/locker

/datum/bot_scenario/griefed/locked_in/post_spawn()
	..()
	locker = new(get_turf(bot))
	locker.breakout_time = 6 SECONDS
	bot.forceMove(locker)
	locker.welded = TRUE

/datum/bot_scenario/griefed/locked_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return isturf(bot.loc) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Cuffs on the bot, as if somebody had just got them on it.
/datum/bot_scenario/griefed/proc/cuff_bot(breakout)
	var/obj/item/restraints/handcuffs/cuffs = new(bot)
	cuffs.breakouttime = breakout
	bot.handcuffed = cuffs
	bot.update_handcuffed()

/datum/bot_scenario/griefed/cuffed
	name = "griefing: cuffed by a stranger, it gets them off"
	desc = "Cuffs from somebody with no right to put them on: it starts working them off."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")

/datum/bot_scenario/griefed/cuffed/post_spawn()
	..()
	cuff_bot(6 SECONDS)

/datum/bot_scenario/griefed/cuffed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot.handcuffed ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/griefed/cuffed_by_officer
	name = "griefing: cuffed by an officer, it waits"
	desc = "The same cuffs from an officer. It waits to be taken to the brig."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	griefer_name = "Olly Officer"
	griefer_job = "Security Officer"
	time_limit = 12 SECONDS

/datum/bot_scenario/griefed/cuffed_by_officer/post_spawn()
	..()
	cuff_bot(3 SECONDS)
	brain.cuffed_lawfully = TRUE

/datum/bot_scenario/griefed/cuffed_by_officer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!bot.handcuffed)
		fail_reason = "took an officer's cuffs off"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/cuffed_by_officer/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/robbed
	name = "griefing: robbed, it goes for them"
	desc = "Somebody takes something out of its pocket with the strip menu. It's not having that."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")

/datum/bot_scenario/griefed/robbed/post_spawn()
	..()
	brain.temper = 0.9
	bot.equip_to_slot_or_del(new /obj/item/screwdriver(bot), ITEM_SLOT_LPOCKET)

/datum/bot_scenario/griefed/robbed/grief()
	var/obj/item/I = bot.l_store
	if(I)
		INVOKE_ASYNC(griefer, TYPE_PROC_REF(/mob/living, stripPanelUnequip), I, bot, ITEM_SLOT_LPOCKET)

/datum/bot_scenario/griefed/robbed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("engaging") ? BOT_GYM_PASS : BOT_GYM_PENDING //a fight can be over by the next look at it: down's down

// ---------------------------------------------------------------------------------------------
// Fights
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/axe_murderer
	name = "griefing: bare hands against a fire axe, it runs"
	desc = "Punching somebody with a 9999 force axe is what the griefed round's crew all did, to the death. A bot with its hands empty and no great nerve gets out of there, shouting."
	layout = list(
		"######################",
		"#.CB.................#",
		"######################")
	var/obj/item/twohanded/fireaxe/axe

/datum/bot_scenario/griefed/axe_murderer/post_spawn()
	..()
	brain.nerve = 0.2
	axe = griefer_holds(/obj/item/twohanded/fireaxe)
	axe.wield(griefer)

/datum/bot_scenario/griefed/axe_murderer/grief()
	griefer_swing(axe)

/datum/bot_scenario/griefed/axe_murderer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return got_away(4) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/draws_toolbox
	name = "griefing: in a fight, it gets the extinguisher out of its bag"
	desc = "Attacked with something heavy in its backpack. Nobody in a fight leaves that where it is: it comes out, and gets used."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	kit_backpack = list(/obj/item/extinguisher) //a toolbox won't fit in a backpack

/datum/bot_scenario/griefed/draws_toolbox/post_spawn()
	..()
	brain.nerve = 0.9

/datum/bot_scenario/griefed/draws_toolbox/grief()
	griefer_hand(INTENT_HARM)
	griefer_hand(INTENT_HARM)
	griefer_hand(INTENT_HARM)

/datum/bot_scenario/griefed/draws_toolbox/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_has("hitting [griefer] with") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/takes_their_weapon
	name = "griefing: picks up the weapon at its feet"
	desc = "A fight with a toolbox lying within reach. It's in its hand a second later."
	layout = list(
		"########",
		"#.TBC..#",
		"########")

/datum/bot_scenario/griefed/takes_their_weapon/post_spawn()
	..()
	brain.nerve = 0.9

/datum/bot_scenario/griefed/takes_their_weapon/grief()
	griefer_hand(INTENT_HARM)
	griefer_hand(INTENT_HARM)
	griefer_hand(INTENT_HARM)

/datum/bot_scenario/griefed/takes_their_weapon/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/storage/toolbox) in bot.held_items) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/rogue_officer
	name = "griefing: an officer with an axe isn't arresting anybody"
	desc = "Anybody in a security job used to get a free pass: the crew stood there protesting while a griefer in a uniform killed them. Past a scuffle, it fights back."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	griefer_name = "Olly Officer"
	griefer_job = "Security Officer"
	var/obj/item/twohanded/fireaxe/axe

/datum/bot_scenario/griefed/rogue_officer/post_spawn()
	..()
	brain.nerve = 0.9
	axe = griefer_holds(/obj/item/twohanded/fireaxe)
	axe.wield(griefer)

/datum/bot_scenario/griefed/rogue_officer/grief()
	keep_at_it("swing", 15)

/datum/bot_scenario/griefed/rogue_officer/proc/swing()
	griefer_swing(axe)
	return brain.state != BOT_STATE_COMBAT

/datum/bot_scenario/griefed/rogue_officer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (brain.state == BOT_STATE_COMBAT && brain.attacker == griefer) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Bystanders
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/bystander
	layout = list(
		"#################",
		"#...............#",
		"#..B...VC.......#",
		"#...............#",
		"#################")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/griefed/bystander/post_spawn()
	..()
	victim = stand_in(first_marker("V"), "Vic Victim")

/datum/bot_scenario/griefed/bystander/grief()
	keep_at_it("beat", 15)

/datum/bot_scenario/griefed/bystander/proc/beat()
	griefer_hand(INTENT_HARM, victim)
	return victim.stat == CONSCIOUS

/datum/bot_scenario/griefed/bystander/brave
	name = "griefing: somebody with nerve steps in"
	desc = "Somebody getting beaten in front of it. It calls it in and goes to help. Everybody who wasn't security used to carry on with their work."

/datum/bot_scenario/griefed/bystander/brave/post_spawn()
	..()
	brain.nerve = 0.9

/datum/bot_scenario/griefed/bystander/brave/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.state == BOT_STATE_COMBAT && brain.attacker == griefer)
		if(bot_transcript_has("called in"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/bystander/coward
	name = "griefing: somebody with no nerve gets out of there"
	desc = "The same beating, in front of somebody who wants no part of it."

/datum/bot_scenario/griefed/bystander/coward/post_spawn()
	..()
	brain.nerve = 0.1
	bot.forceMove(get_step(first_marker("V"), WEST))

/datum/bot_scenario/griefed/bystander/coward/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_has("run_from") ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Vandals
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/vandal
	layout = list(
		"###########",
		"#.B...Cw..#",
		"#.....www.#",
		"###########")
	var/obj/item/storage/toolbox/mechanical/box

/datum/bot_scenario/griefed/vandal/post_spawn()
	..()
	box = griefer_holds(/obj/item/storage/toolbox/mechanical)

/datum/bot_scenario/griefed/vandal/grief()
	keep_at_it("smash", CLICK_CD_MELEE)

/datum/bot_scenario/griefed/vandal/proc/smash()
	griefer.dir = EAST
	if(griefer.stat != CONSCIOUS || griefer.handcuffed || griefer.IsParalyzed() || griefer.IsKnockdown())
		return TRUE
	var/obj/structure/window/W = locate() in get_step(griefer, EAST)
	if(!W)
		for(var/obj/structure/window/other in range(1, griefer))
			W = other
			break
	if(!W)
		return FALSE
	griefer_swing(box, W)
	return TRUE

/datum/bot_scenario/griefed/vandal/called_in
	name = "griefing: somebody smashing the place up gets called in"
	desc = "A griefer smashing windows in plain sight. It tells them to stop and gets on the radio: this used to go on all round them without anybody looking up."

/datum/bot_scenario/griefed/vandal/called_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_has("called in") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/vandal/own_department
	name = "griefing: smashing up its own department, it stops them"
	desc = "The same thing where it works, and it has the nerve: it isn't waiting for security."
	arena_is_home = TRUE

/datum/bot_scenario/griefed/vandal/own_department/post_spawn()
	..()
	brain.nerve = 0.9

/datum/bot_scenario/griefed/vandal/own_department/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (brain.state == BOT_STATE_COMBAT && brain.attacker == griefer) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/vandal/officer
	name = "griefing: an officer who sees it makes the arrest"
	desc = "A security officer sees it. It's on the record, and they're in cuffs."
	job = "Security Officer"
	kit_backpack = list(/obj/item/melee/baton/loaded, /obj/item/restraints/handcuffs)
	time_limit = 40 SECONDS

/datum/bot_scenario/griefed/vandal/officer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return griefer.handcuffed ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/trespasser
	name = "griefing: somebody who shouldn't be in here gets asked to leave"
	desc = "A stranger in a staff-only room. It tells them, and calls them in if they stay."
	layout = list(
		"#######",
		"#.B.C.#",
		"#######")
	job = "Medical Doctor"
	griefer_name = "Terry Trespasser"
	griefer_job = "Assistant"
	time_limit = 45 SECONDS

/datum/bot_scenario/griefed/trespasser/post_spawn()
	..()
	arena_area.staff_jobs = list("Medical Doctor")
	brain.gym_scripted = FALSE
	brain.next_watch_time = world.time

/datum/bot_scenario/griefed/trespasser/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_has("called in") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/bomb
	name = "griefing: a bomb goes live in front of it, it runs"
	desc = "Somebody primes something in plain sight. It shouts, and it leaves."
	layout = list(
		"################",
		"#.CB...........#",
		"################")

/datum/bot_scenario/griefed/bomb/grief()
	log_bomber(griefer, "has primed a", griefer, message_admins = FALSE)

/datum/bot_scenario/griefed/bomb/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return got_away(3) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Doing the griefing
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/duty/greytide
	duty_type = /datum/bot_duty/greytide
	job = "Assistant"
	time_limit = 100 SECONDS
	forbidden_tells = list("item_teleport", "equip_without_holding", "remote_pickup")

/datum/bot_scenario/duty/greytide/post_spawn()
	..()
	give_job_id(list())
	brain.greytider = TRUE

/datum/bot_scenario/duty/greytide/smash
	name = "greytide: arms up and smashes the place"
	desc = "An assistant out for trouble, with nothing on it. It goes and gets the toolbox, and starts on the room: the vending machine and the windows, swinging at the speed anybody can."
	layout = list(
		"############",
		"#B.T...www.#",
		"#......www.#",
		"#........V.#",
		"############")

/datum/bot_scenario/duty/greytide/smash/issue_goal()
	if(brain.mischief_weapon())
		goal_attempts++
		brain.assign_goal(new /datum/bot_goal/tide/smash()) //what it's for here: mouthing off on the radio has its own turn at a real round
	else
		..()

/datum/bot_scenario/duty/greytide/smash/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.things_smashed >= 3 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/greytide/not_the_hull
	name = "greytide: leaves a window on to space alone"
	desc = "Windows between it and space. It breaks plenty, but nothing that lets the air out: a griefing player answers for a hole in the hull, a bot just kills the shift."
	layout = list(
		"#########",
		"#BT..t.wS",
		"#########")
	time_limit = 30 SECONDS

/datum/bot_scenario/duty/greytide/not_the_hull/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(placed_destroyed("w"))
		fail_reason = "smashed the window that holds the air in"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/greytide/not_the_hull/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/duty/greytide/harass
	name = "greytide: shoves somebody about"
	desc = "Nothing in the room but somebody else. It goes over and starts on them."
	layout = list(
		"#########",
		"#B.....C#",
		"#########")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/mark

/datum/bot_scenario/duty/greytide/harass/post_spawn()
	..()
	mark = stand_in(first_marker("C"), "Pat Bystander")
	bot.put_in_hands(new /obj/item/storage/toolbox/mechanical(bot))

/datum/bot_scenario/duty/greytide/harass/issue_goal()
	if(!brain.current_goal)
		brain.next_mischief_time = 0
		goal_attempts++
		brain.assign_goal(new /datum/bot_goal/tide/harass(mark))

/datum/bot_scenario/duty/greytide/harass/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/key in mark.logging)
		var/list/entries = mark.logging[key]
		for(var/entry in entries)
			if(findtext(entries[entry], "shoved") || findtext(entries[entry], "disarm") || findtext(entries[entry], "pushed") || findtext(entries[entry], "grabbed"))
				return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Falling out, and putting it right
// ---------------------------------------------------------------------------------------------

/// A second bot in the arena, on its own account.
/datum/bot_scenario/proc/second_bot(turf/T, name)
	var/mob/living/carbon/human/H = stand_in(T, name)
	H.mind_initialize()
	var/datum/bot_brain/other = new(H)
	other.gym_run = src
	other.gym_scripted = TRUE
	other.temper = 0.5
	other.nerve = 0.5
	other.greytider = FALSE
	return H

/datum/bot_scenario/quarrel
	name = "chaos: two people fall out, and it ends in a fight"
	desc = "One of them starts it. Words, a comeback, then the shove, and from there it's the same as any other fight."
	layout = list(
		"#########",
		"#B..C...#",
		"#########")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/other

/datum/bot_scenario/quarrel/issue_goal()
	return

/datum/bot_scenario/quarrel/post_spawn()
	other = second_bot(first_marker("C"), "Pat Bystander")
	other.bot_brain.temper = 0.9
	brain.temper = 0.9
	addtimer(CALLBACK(brain, TYPE_PROC_REF(/datum/bot_brain, pick_a_quarrel), other), 2 SECONDS)

/datum/bot_scenario/quarrel/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return GLOB.bot_chaos.tallies["lost their temper"] || other.bot_brain.state == BOT_STATE_COMBAT ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/riot
	name = "chaos: the tide comes in when the call goes out"
	desc = "Somebody puts it out on the radio, and the other tider drops what it's doing and comes to the same room."
	layout = list(
		"#############",
		"#B.t.......C#",
		"#############")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/other
	var/datum/bot_goal/tide/smash/seen_goal

/datum/bot_scenario/riot/issue_goal()
	return

/datum/bot_scenario/riot/post_spawn()
	other = second_bot(first_marker("C"), "Pat Bystander")
	other.bot_brain.greytider = TRUE
	other.put_in_hands(new /obj/item/storage/toolbox/mechanical(other))
	brain.greytider = TRUE
	bot.put_in_hands(new /obj/item/storage/toolbox/mechanical(bot))
	addtimer(CALLBACK(src, PROC_REF(call_it)), 2 SECONDS)

/datum/bot_scenario/riot/proc/call_it()
	for(var/datum/bot_brain/B in list(brain, other.bot_brain))
		B.assign_goal(new /datum/bot_goal/tide/smash(arena_area))

/datum/bot_scenario/riot/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (brain.things_smashed + other.bot_brain.things_smashed) >= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/repair
	duty_type = /datum/bot_duty/repair_windows
	job = "Station Engineer"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/stack/sheet/glass/fifty, /obj/item/stack/rods/fifty)
	var/turf/window_spot

/datum/bot_scenario/duty/repair/post_spawn()
	..()
	give_job_id(list())

/datum/bot_scenario/duty/repair/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/structure/window/fulltile) in window_spot) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/repair/grille_left
	name = "repairs: glass on the grille that's left"
	desc = "The window's gone and the grille's still there. Glass in hand, clicked on the grille."
	layout = list(
		"#########",
		"#B.....g#",
		"#########")

/datum/bot_scenario/duty/repair/grille_left/post_spawn()
	..()
	window_spot = first_marker("g")
	bot_note_wreckage(new /obj/structure/window/fulltile(window_spot))
	var/obj/structure/window/W = locate() in window_spot
	qdel(W)

/datum/bot_scenario/duty/repair/gone_entirely
	name = "repairs: rods first, then the glass"
	desc = "Nothing left of it at all. A new grille from the rods, stood on the tile, and the glass on that from beside it."
	layout = list(
		"#########",
		"#B......#",
		"#########")

/datum/bot_scenario/duty/repair/gone_entirely/post_spawn()
	..()
	window_spot = locate(first_marker("B").x + 5, first_marker("B").y, first_marker("B").z)
	bot_note_wreckage(new /obj/structure/window/fulltile(window_spot))
	var/obj/structure/window/W = locate() in window_spot
	qdel(W)

/// A wall across the corridor, then gone: the bot puts it back as it was (goals/repair_damage.dm). The duty is named by text so the
/// run without it still builds.
/datum/bot_scenario/duty/wall
	job = "Station Engineer"
	time_limit = 60 SECONDS
	layout = list(
		"#########",
		"#B......#",
		"#########")
	kit_backpack = list(/obj/item/stack/sheet/metal/fifty)
	var/turf/wall_spot
	/// What stood there
	var/wall_was = /turf/closed/wall
	/// What's left of it on the tile, if anything
	var/left_behind
	/// What it should put up, if not what was there
	var/expect_type
	/// A plain wall stands there to begin with, to be reinforced: not a wrong answer yet
	var/reinforcing = FALSE

/datum/bot_scenario/duty/wall/New()
	duty_type = text2path("/datum/bot_duty/rebuild_walls")
	..()

/datum/bot_scenario/duty/wall/post_spawn()
	..()
	give_job_id(list())
	wall_spot = wall_spot_turf()
	knock_down()

/// What a blast does: the wall's gone, the floor under it left
/datum/bot_scenario/duty/wall/proc/knock_down()
	wall_spot.PlaceOnTop(wall_was)
	wall_spot = wall_spot.ScrapeAway()
	if(left_behind)
		new left_behind(wall_spot)

/// Where the wall stood: across the corridor, five along from the bot
/datum/bot_scenario/duty/wall/proc/wall_spot_turf()
	return locate(first_marker("B").x + 5, first_marker("B").y, first_marker("B").z)

/datum/bot_scenario/duty/wall/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/wanted = expect_type || wall_was
	if(istype(wall_spot, /turf/closed/wall))
		if(wall_spot.type == wanted)
			return BOT_GYM_PASS
		if(wall_spot.type != /turf/closed/wall || wanted != /turf/closed/wall/r_wall || !reinforcing)
			fail_reason = "built [wall_spot.type], not [wanted]"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/wall/gone
	name = "repairs: a wall blown out, girder and all"
	desc = "A wall across the corridor blown out to the floor. A girder from metal stood on the tile, then metal on the girder from beside it."

/datum/bot_scenario/duty/wall/reinforced_girder
	name = "repairs: a reinforced wall from its girder"
	desc = "A reinforced wall taken down to its girder. Plasteel on the girder from beside it: a reinforced wall, not a plain one."
	wall_was = /turf/closed/wall/r_wall
	left_behind = /obj/structure/girder/reinforced
	kit_backpack = list(/obj/item/stack/sheet/plasteel/twenty)

/datum/bot_scenario/duty/wall/reinforced_gone
	name = "repairs: a reinforced wall from nothing"
	desc = "A reinforced wall blown out to the floor. A girder from metal, then two plasteel: reinforced, as it was."
	wall_was = /turf/closed/wall/r_wall
	kit_backpack = list(/obj/item/stack/sheet/metal/fifty, /obj/item/stack/sheet/plasteel/twenty)

/area/bot_gym/locked_room
	name = "Locked Room"

/// The wall's in a room behind a door its ID doesn't open. Bombed Hippie shifts: the Teleporter Room's wall and hull hole were never seen to,
/// "no path" every time (wallsboom, 2026-11-13). It asks the AI on the radio, and with nothing opening presses the door's request. An arena
/// is off the station's levels, where telecomms doesn't reach, so it's the request the AI answers here. A bot AI made for the run:
/// station-wide, never with the rest, as an AI answers every arena.
/datum/bot_scenario/duty/wall/behind_door
	name = "repairs: a wall in a room its ID doesn't open, the AI asked to open up"
	desc = "The wall's in a room behind a Captain's-access door. It goes to the door, asks the AI to open up, and goes in when it opens."
	station_wide = TRUE
	layout = list(
		"#########",
		"#B......#",
		"####D####",
		"#qqqqqqq#",
		"#########")
	var/mob/living/silicon/ai/ai
	var/make_ai = TRUE

/// q the room's floor
/datum/bot_scenario/duty/wall/behind_door/setup()
	var/area/bot_gym/locked_room/room = new
	for(var/turf/T as anything in markers["q"])
		var/area/old_area = T.loc
		old_area.contents -= T
		room.contents += T
		T.change_area(old_area, room)
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)
	A.req_access_txt = "[ACCESS_CAPTAIN]"

/datum/bot_scenario/duty/wall/behind_door/wall_spot_turf()
	var/list/room = markers["q"]
	return room[4]

/datum/bot_scenario/duty/wall/behind_door/post_spawn()
	..()
	if(!make_ai)
		return
	ai = bot_make_silicon("AI") //goals/silicon.dm: as a round makes one, at the station's AI landmark
	if(!ai)
		log_line("no AI could be made")
		return
	var/datum/bot_silicon/ai/brain_ai = new(ai)
	brain_ai.strictness = 0.2 //easygoing: a door request carries no reason, and the radio that would give one doesn't reach an arena

/datum/bot_scenario/duty/wall/behind_door/release_run()
	if(!QDELETED(ai))
		qdel(ai)
	return ..()

/// No AI to ask: it calls for somebody with access, and somebody whose ID opens the door comes and lets it in (the user's ruling,
/// 2026-11-13: "call a head to let in", for the rooms the AI keeps to command too).
/datum/bot_scenario/duty/wall/behind_door/no_ai
	name = "repairs: a wall in a room its ID doesn't open, no AI: somebody with access lets it in"
	desc = "The same locked room with no AI aboard. It asks on the radio for somebody with access to let it in; the crewman with the Captain's access comes over and opens the door."
	station_wide = FALSE
	make_ai = FALSE
	layout = list(
		"#########",
		"#B....C.#",
		"####D####",
		"#qqqqqqq#",
		"#########")
	var/mob/living/carbon/human/opener

/datum/bot_scenario/duty/wall/behind_door/no_ai/post_spawn()
	..()
	brain.gym_scripted = FALSE //a scripted bot makes no calls (call_for())
	opener = second_bot(first_marker("C"), "Doug Doorman")
	var/obj/item/card/id/C = new(opener)
	C.access = list(ACCESS_CAPTAIN)
	opener.equip_to_slot_or_del(C, ITEM_SLOT_ID)

/// No plasteel to be had for a reinforced wall: a plain one to seal it, for now (the user's ruling, 2026-11-13). MetaStation's engineers
/// left a reinforced wall open for want of it: "no way into where the plasteel is".
/datum/bot_scenario/duty/wall/no_plasteel
	name = "repairs: a reinforced wall with no plasteel to be had, a plain one for now"
	desc = "A reinforced wall blown out, metal in the bag and no plasteel anywhere. A plain wall goes up to seal it."
	wall_was = /turf/closed/wall/r_wall
	expect_type = /turf/closed/wall

/// The plain wall put up for want of plasteel, reinforced now there's plasteel: the plating sliced off with a welder, down to the girder,
/// then the plasteel on it. The list it's on is named by text so the run without it still builds.
/datum/bot_scenario/duty/wall/reinforce_later
	name = "repairs: a wall put back plain is reinforced once there's plasteel"
	desc = "A plain wall standing where a reinforced one was, plasteel and a welder in the bag. The welder takes it down to its girder, and two plasteel sheets make it reinforced."
	wall_was = /turf/closed/wall/r_wall
	kit_backpack = list(/obj/item/stack/sheet/plasteel/twenty, /obj/item/weldingtool)

/datum/bot_scenario/duty/wall/reinforce_later/knock_down()
	reinforcing = TRUE
	wall_spot.PlaceOnTop(/turf/closed/wall)
	var/list/to_reinforce = GLOB.vars["bot_walls_to_reinforce"]
	if(islist(to_reinforce))
		to_reinforce |= wall_spot

/datum/bot_scenario/alert
	name = "chaos: a head of staff puts the station on alert"
	desc = "Two people wanted for major crimes and still at large. The HoP goes to the comms console and raises the alert."
	layout = list(
		"#########",
		"#B.....c#",
		"#########")
	job = "Head of Personnel"
	time_limit = 30 SECONDS
	var/datum/bot_wanted/one
	var/datum/bot_wanted/two
	var/list/culprits

/datum/bot_scenario/alert/issue_goal()
	return

/datum/bot_scenario/alert/build_tile(turf/T, char)
	if(char == "c")
		place(char, new /obj/machinery/computer/communications(T))
		return
	..()

/datum/bot_scenario/alert/post_spawn()
	culprits = list()
	for(var/i in 1 to 2)
		var/mob/living/carbon/human/H = stand_in(first_marker("B"), "Culprit [i]")
		H.forceMove(first_marker("."))
		culprits += H
		var/datum/bot_wanted/W = new
		W.severity = BOT_CRIME_MAJOR
		W.crime = "Sabotage"
		GLOB.bot_security_wanted[WEAKREF(H)] = W
	addtimer(CALLBACK(src, PROC_REF(raise)), 2 SECONDS)

/// Over and over: the alert level is the whole world's, and with passes side by side somebody else's run may have it up.
/datum/bot_scenario/alert/proc/raise()
	if(result != BOT_GYM_PENDING)
		return
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/raise_alert)
	if(!brain.current_goal)
		D.try_start(brain)
	addtimer(CALLBACK(src, PROC_REF(raise)), 2 SECONDS)

/datum/bot_scenario/alert/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(GLOB.security_level >= SEC_LEVEL_BLUE && bot_transcript_said("put the station on blue alert"))
		set_security_level(SEC_LEVEL_GREEN)
		for(var/mob/living/carbon/human/H as anything in culprits)
			GLOB.bot_security_wanted -= WEAKREF(H)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/prank
	name = "chaos: the clown leaves a banana skin by a door"
	desc = "The banana out of the clown's bag, eaten, and the skin put down next to a door for somebody to tread on."
	duty_type = /datum/bot_duty/prank
	job = "Clown"
	time_limit = 40 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/food/snacks/grown/banana)
	layout = list(
		"#########",
		"#B.....D#",
		"#########")
	forbidden_tells = list("item_teleport", "equip_without_holding", "remote_pickup")

/datum/bot_scenario/duty/prank/post_spawn()
	..()
	give_job_id(list())

/datum/bot_scenario/duty/prank/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/grown/bananapeel/peel in range(8, bot))
		if(isturf(peel.loc))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// wrench_grounding_rod, on the rod in this arena rather than whichever one is nearest a tesla.
/datum/bot_goal/wrench_grounding_rod/gym
	braves_bad_air = TRUE //engineers are suited up out there, and this one isn't what the scenario is about
	var/obj/machinery/power/grounding_rod/rod

/datum/bot_goal/wrench_grounding_rod/gym/resolve_target(datum/bot_brain/bot)
	target = rod

/datum/bot_goal/wrench_grounding_rod/gym/on_success(datum/bot_brain/bot)
	return

/datum/bot_scenario/rod_off_the_floor
	name = "repairs: a rod shoved on to the lattice gets dragged back and wrenched"
	desc = "A grounding rod pushed off the plating on to bare lattice. A wrench won't secure anything there, so every attempt used to fail and the tesla was started with it loose. It takes hold of it, walks it back on to the floor and wrenches it down."
	layout = list(
		"#######",
		"#..B..#",
		"#.....#",
		"###S###",
		"#######")
	job = "Station Engineer"
	kit_backpack = list(/obj/item/wrench)
	time_limit = 30 SECONDS
	var/obj/machinery/power/grounding_rod/rod

/datum/bot_scenario/rod_off_the_floor/setup()
	var/turf/T = first_marker("S")
	new /obj/structure/lattice(T)
	rod = new(T)
	rod.anchored = FALSE

/datum/bot_scenario/rod_off_the_floor/make_goal()
	var/datum/bot_goal/wrench_grounding_rod/gym/G = new
	G.rod = rod
	return G

/datum/bot_scenario/rod_off_the_floor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(rod))
		fail_reason = "the rod's gone"
		return BOT_GYM_FAIL
	return rod.anchored ? BOT_GYM_PASS : BOT_GYM_PENDING
