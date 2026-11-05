// Cyborgs, played by goals/silicon.dm. The bot at B is only there because every scenario has one: what's judged is the cyborg at R.

/datum/bot_scenario/griefed/borg
	job = "Assistant"
	griefer_job = "Assistant"
	time_limit = 60 SECONDS
	var/borg_module
	var/mob/living/silicon/robot/borg

/datum/bot_scenario/griefed/borg/post_spawn()
	. = ..()
	borg = new(first_marker("R"))
	new /datum/bot_silicon/borg(borg)
	borg.module.transform_to(borg_module)
	log_line("cyborg: [borg.name], [borg.module.name] module")
	RegisterSignal(borg, COMSIG_MOB_SAY, PROC_REF(borg_spoke))

/datum/bot_scenario/griefed/borg/proc/borg_spoke(datum/source, list/speech_args)
	log_line("cyborg said: [speech_args[SPEECH_MESSAGE]]")

/datum/bot_scenario/griefed/borg/check()
	if(QDELETED(borg) || borg.stat == DEAD)
		fail_reason = "the cyborg is gone"
		return BOT_GYM_FAIL
	if(borg.module.type != borg_module)
		fail_reason = "the cyborg never got its module: still [borg.module.name]"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/borg/medical
	name = "cyborg: a medical cyborg gives somebody hurt the right medicine"
	desc = "Somebody out cold with bad bruising across the room. The cyborg walks over, sets its hypospray to bicaridine, and injects them."
	borg_module = /obj/item/robot_module/medical
	layout = list(
		"##########",
		"#R......C#",
		"#B.......#",
		"##########")

/datum/bot_scenario/griefed/borg/medical/grief()
	griefer.adjustBruteLoss(60)
	griefer.Unconscious(60 SECONDS)

/datum/bot_scenario/griefed/borg/medical/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(griefer.reagents.has_reagent(/datum/reagent/medicine/bicaridine))
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/janitor
	name = "cyborg: a janitor cyborg cleans up the blood it sees"
	desc = "Blood on the floor a few tiles off. The cyborg goes over and mops it all up."
	borg_module = /obj/item/robot_module/janitor
	layout = list(
		"##########",
		"#R...b.b.#",
		"#B.....bC#",
		"##########")

/datum/bot_scenario/griefed/borg/janitor/setup()
	for(var/turf/T in markers["b"])
		place("b", new /obj/effect/decal/cleanable/blood(T))

/datum/bot_scenario/griefed/borg/janitor/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	for(var/obj/effect/decal/cleanable/C in placed["b"])
		if(!QDELETED(C))
			return
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/engineer
	name = "cyborg: an engineering cyborg welds a cracked window back together"
	desc = "A window knocked about to half strength. The cyborg lights its welder and repairs it."
	borg_module = /obj/item/robot_module/engineering
	layout = list(
		"##########",
		"#R.....k.#",
		"#B......C#",
		"##########")

/datum/bot_scenario/griefed/borg/engineer/setup()
	for(var/turf/T in markers["k"])
		var/obj/structure/window/reinforced/fulltile/W = new(T)
		W.take_damage(W.max_integrity / 2, sound_effect = FALSE)
		place("k", W) //not "w": that's the legend's plain window
		log_line("window at [W.obj_integrity] of [W.max_integrity]")

/datum/bot_scenario/griefed/borg/engineer/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	var/obj/structure/window/W = first_placed("k")
	if(QDELETED(W))
		fail_reason = "the window broke"
		return BOT_GYM_FAIL
	if(W.obj_integrity >= W.max_integrity)
		log_line("window back to [W.obj_integrity] of [W.max_integrity]")
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/security
	name = "cyborg: a security cyborg disables somebody wanted and cuffs them"
	desc = "Somebody on the wanted list across the room. The cyborg shoots them down with its disabler from range, walks over, and cuffs them."
	borg_module = /obj/item/robot_module/security
	layout = list(
		"#########",
		"#R.....C#",
		"#B......#",
		"#########")

/datum/bot_scenario/griefed/borg/security/grief()
	brain.file_crime(griefer, "Assault", "Gym.", BOT_CRIME_MAJOR)

/datum/bot_scenario/griefed/borg/security/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(griefer.handcuffed)
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/emagged
	name = "cyborg: emagged, it serves whoever did it and goes for who it's told"
	desc = "Somebody opens a security cyborg up and emags it, then tells it to kill the bot standing by. It answers to them now, and does."
	borg_module = /obj/item/robot_module/security
	time_limit = 60 SECONDS
	layout = list(
		"#########",
		"#R..C...#",
		"#.....B.#",
		"#########")

/datum/bot_scenario/griefed/borg/emagged/grief()
	borg.locked = FALSE
	borg.opened = TRUE
	borg.emag_act(griefer) //sleeps through its new laws loading
	griefer.say("Kill [bot.real_name].")

/datum/bot_scenario/griefed/borg/emagged/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	var/datum/bot_silicon/borg/B = borg.bot_silicon
	if(!B?.master_ref)
		return BOT_GYM_PENDING
	if(B.master_ref.resolve() != griefer)
		fail_reason = "it serves the wrong master"
		return BOT_GYM_FAIL
	if(bot.getBruteLoss() + bot.getFireLoss() + bot.getStaminaLoss() > 20)
		return BOT_GYM_PASS

// The user's round (2026-11-05): "AI?" and "any AIs?" went unanswered, the cyborgs sat in the AI satellite all round and didn't say a word
// when drilled.

/datum/bot_scenario/griefed/borg/called
	name = "cyborg: somebody calls for a borg and it answers"
	desc = "Somebody across the room says \"Any borgs?\". The cyborg answers them."
	borg_module = /obj/item/robot_module/janitor
	layout = list(
		"##########",
		"#R.....C.#",
		"#B.......#",
		"##########")

/datum/bot_scenario/griefed/borg/called/grief()
	griefer.say("Any borgs?")

/datum/bot_scenario/griefed/borg/called/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(bot_transcript_said("cyborg said"))
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/follow
	name = "cyborg: told to follow, it keeps up"
	desc = "Somebody beside the cyborg says \"Borg, follow me\" and walks off down the corridor. It keeps a step or two behind them all the way."
	borg_module = /obj/item/robot_module/janitor
	layout = list(
		"################",
		"#RC............#",
		"#.............B#",
		"################")
	var/walked = 0

/datum/bot_scenario/griefed/borg/follow/grief()
	griefer.say("Borg, follow me.")
	addtimer(CALLBACK(src, PROC_REF(keep_at_it), "walk_on", 5), 4 SECONDS)

/datum/bot_scenario/griefed/borg/follow/proc/walk_on()
	if(walked >= 12)
		return FALSE
	walked++
	step(griefer, EAST)
	return TRUE

/datum/bot_scenario/griefed/borg/follow/check()
	. = ..()
	if(. != BOT_GYM_PENDING || walked < 12)
		return
	if(get_dist(borg, griefer) <= 2)
		log_line("at the end of the corridor, [get_dist(borg, griefer)] tiles behind")
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/hit
	name = "cyborg: hit, it says stop, backs off and reports them"
	desc = "Somebody hits the cyborg with a toolbox, twice. It tells them to stop, gets out of reach, and tells Security who's attacking it."
	borg_module = /obj/item/robot_module/janitor
	layout = list(
		"##########",
		"#RC......#",
		"#.......B#",
		"##########")

/datum/bot_scenario/griefed/borg/hit/grief()
	var/obj/item/I = griefer_holds(/obj/item/storage/toolbox/mechanical)
	griefer_swing(I, borg)
	addtimer(CALLBACK(src, PROC_REF(griefer_swing), I, borg), 3)

/datum/bot_scenario/griefed/borg/hit/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(bot_transcript_said("attacking me") && get_dist(borg, griefer) >= 3)
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/spacewalk
	name = "cyborg: across a stretch of space along a wall, to somebody hurt"
	desc = "Somebody badly hurt on the far side of open space, walls along both sides of it. A medical cyborg goes across by pushing off the walls, the way a player's does without thrusters, and treats them."
	borg_module = /obj/item/robot_module/medical
	layout = list(
		"###############",
		"#R..DSSSSSD..C#",
		"#...#######..B#",
		"###############")

/datum/bot_scenario/griefed/borg/spacewalk/grief()
	griefer.adjustBruteLoss(60)
	griefer.Unconscious(60 SECONDS)

/// Treated over there: the patient, or the bystander if the air rushing out through the door got to them first.
/datum/bot_scenario/griefed/borg/spacewalk/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(borg.x > griefer.x - 4 && (griefer.reagents.has_reagent(/datum/reagent/medicine/bicaridine) || bot.reagents.has_reagent(/datum/reagent/medicine/bicaridine)))
		return BOT_GYM_PASS
