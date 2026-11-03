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
