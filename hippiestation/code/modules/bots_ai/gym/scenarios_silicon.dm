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
	SIGNAL_HANDLER
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

// Layout letter G: where Medbay is, for this.
/datum/bot_scenario/griefed/borg/crit
	name = "cyborg: somebody in crit gets epinephrine first, and is taken to Medbay"
	desc = "Somebody burned into crit and suffocating. A medical cyborg gave them kelotane and nothing else, every two seconds for twenty minutes, stood over them where they fell, until they'd suffocated. It gives the epinephrine that stops that first, and takes them to Medbay."
	borg_module = /obj/item/robot_module/medical
	time_limit = 90 SECONDS
	layout = list(
		"###############",
		"#R..C........G#",
		"#B............#",
		"###############")
	var/had_epinephrine = FALSE

/datum/bot_scenario/griefed/borg/crit/post_spawn()
	. = ..()
	var/datum/bot_silicon/borg/mind = borg.bot_silicon
	mind.vars["gym_medbay_spot"] = first_marker("G") //by name: the build before this has no such var

/datum/bot_scenario/griefed/borg/crit/grief()
	griefer.adjustFireLoss(135)
	griefer.updatehealth()
	griefer.update_stat()

/datum/bot_scenario/griefed/borg/crit/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(griefer.stat == DEAD)
		fail_reason = had_epinephrine ? "the patient died on the way" : "the patient died without any epinephrine"
		return BOT_GYM_FAIL
	if(griefer.reagents.has_reagent(/datum/reagent/medicine/epinephrine))
		had_epinephrine = TRUE
	if(had_epinephrine && get_dist(griefer, first_marker("G")) <= 2 && !griefer.pulledby)
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/medical/saline
	name = "cyborg: somebody short of blood gets saline from a medical cyborg"
	desc = "Cut about and a third of their blood gone. Bicaridine closes the cuts and does nothing for the blood, which went on costing them breath: saline stands in for it at once."

/datum/bot_scenario/griefed/borg/medical/saline/grief()
	..()
	griefer.blood_volume = 350

/datum/bot_scenario/griefed/borg/medical/saline/check()
	. = ..()
	if(. == BOT_GYM_PASS && !griefer.reagents.has_reagent(/datum/reagent/medicine/salglu_solution))
		return BOT_GYM_PENDING

// Layout letter e: an emitter, pointed down the arena (bot_hazards.dm).
/datum/bot_scenario/griefed/borg/out_of_beam
	name = "cyborg: stood where an emitter comes on, it gets out of the line of fire"
	desc = "A cyborg stood on the tile an emitter starts firing across. The cyborgs had no rule about beams at all: a medical one took 597 of them in a shift, seeing to somebody shot in the same spot."
	borg_module = /obj/item/robot_module/janitor
	time_limit = 20 SECONDS
	layout = list(
		"#######",
		"#..e..#",
		"#B.R.C#",
		"#.....#",
		"#######")
	var/obj/machinery/power/emitter/emitter
	var/lit = FALSE

/datum/bot_scenario/griefed/borg/out_of_beam/setup()
	emitter = place("e", new /obj/machinery/power/emitter(first_marker("e")))
	emitter.anchored = TRUE
	emitter.state = 2 //EMITTER_WELDED
	emitter.active_power_usage = 0 //there's no wire under it here
	emitter.setDir(SOUTH)

/datum/bot_scenario/griefed/borg/out_of_beam/grief()
	addtimer(CALLBACK(src, PROC_REF(light_it)), 10)

/datum/bot_scenario/griefed/borg/out_of_beam/proc/light_it()
	if(result != BOT_GYM_PENDING || QDELETED(emitter))
		return
	emitter.active = TRUE
	lit = TRUE
	bot_refresh_hazards()

/datum/bot_scenario/griefed/borg/out_of_beam/check()
	. = ..()
	if(. != BOT_GYM_PENDING || !lit)
		return
	if(borg.x != emitter.x)
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/out_of_beam/release_run()
	if(!QDELETED(emitter))
		emitter.active = FALSE
	bot_refresh_hazards()
	return ..()

// The pool (pool_main.dm): a cyborg can't swim to the edge and drag itself out as a person does. In the user's round (2026-11-10) the
// bot crew's two cyborgs routed through the water and sat in it for 25 minutes, until the user killed them there.
/datum/bot_scenario/griefed/borg/pool
	borg_module = /obj/item/robot_module/janitor
	time_limit = 40 SECONDS
	/// How many times the cyborg stepped into the water from dry floor
	var/went_in = 0
	/// It starts in the water (R is a pool tile too)
	var/starts_in_water = FALSE

/datum/bot_scenario/griefed/borg/pool/setup()
	var/list/water = list()
	water += markers["q"]
	if(starts_in_water)
		water += markers["R"]
	for(var/turf/T in water)
		T.ChangeTurf(/turf/open/pool)
	for(var/turf/T in markers["b"])
		place("b", new /obj/effect/decal/cleanable/blood(T))

/datum/bot_scenario/griefed/borg/pool/post_spawn()
	. = ..()
	RegisterSignal(borg, COMSIG_MOVABLE_MOVED, PROC_REF(borg_moved))

/datum/bot_scenario/griefed/borg/pool/proc/borg_moved(atom/movable/source, atom/old_loc)
	SIGNAL_HANDLER
	if(istype(borg.loc, /turf/open/pool) && !istype(old_loc, /turf/open/pool))
		went_in++
		log_line("cyborg stepped into the water at [COORD(borg)]")
	else if(!istype(borg.loc, /turf/open/pool) && istype(old_loc, /turf/open/pool))
		log_line("cyborg out of the water at [COORD(borg)]")

/datum/bot_scenario/griefed/borg/pool/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	for(var/obj/effect/decal/cleanable/C in placed["b"])
		if(!QDELETED(C))
			return
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/pool/fallen_in
	name = "cyborg: knocked into the pool, a cyborg's floaters get it out and it gets on with its job"
	desc = "A janitor cyborg starts in the middle of the pool with blood on the floor beyond it. It works its way to the edge, its floaters lift it out, and it mops the blood up."
	starts_in_water = TRUE
	layout = list(
		"##########",
		"#B.......#",
		"#qqqq..b.#",
		"#qRqq....#",
		"#qqqq...C#",
		"##########")

/datum/bot_scenario/griefed/borg/pool/round_it
	name = "cyborg: a cyborg goes round the pool, not through it"
	desc = "Blood on the far side of a pool, with dry floor round it. The janitor cyborg walks round the water to mop it up, and never goes in."
	layout = list(
		"###########",
		"#.........#",
		"#Rqqqqq.b.#",
		"#Bqqqqq..C#",
		"#.........#",
		"###########")

/datum/bot_scenario/griefed/borg/pool/round_it/check()
	if(went_in)
		fail_reason = "it walked into the pool"
		return BOT_GYM_FAIL
	return ..()

// Medical cyborgs and what's in the way of a needle (goals/silicon.dm injection_zone()). In the user's round (2026-11-10) the
// hypospray "injected" a janitor in a bio suit every two seconds for two minutes, nothing went in, and he suffocated in Medbay.
/datum/bot_scenario/griefed/borg/medical/bio_suit
	name = "cyborg: somebody hurt in a bio suit, hood off, gets the needle in the neck"
	desc = "Bruised and out cold in a bio suit with the hood down. The suit's too thick for a needle, so the cyborg aims for the head and gets the bicaridine in."

/datum/bot_scenario/griefed/borg/medical/bio_suit/grief()
	..()
	griefer.equip_to_slot_or_del(new /obj/item/clothing/suit/bio_suit(griefer), ITEM_SLOT_OCLOTHING)

/datum/bot_scenario/griefed/borg/medical/bio_suit/sealed
	name = "cyborg: somebody hurt and sealed in a bio suit gets a doctor called, not a hypospray poked at them"
	desc = "Bruised and out cold in a bio suit and hood: no needle gets through anywhere. The cyborg tells Medical where they are and why, and stops trying."
	var/called = FALSE

/datum/bot_scenario/griefed/borg/medical/bio_suit/sealed/grief()
	..()
	griefer.equip_to_slot_or_del(new /obj/item/clothing/head/bio_hood(griefer), ITEM_SLOT_HEAD)

/datum/bot_scenario/griefed/borg/medical/bio_suit/sealed/borg_spoke(datum/source, list/speech_args)
	. = ..()
	if(findtext(speech_args[SPEECH_MESSAGE], "needs a doctor"))
		called = TRUE

/datum/bot_scenario/griefed/borg/medical/bio_suit/sealed/check()
	if(griefer.reagents.has_reagent(/datum/reagent/medicine/bicaridine))
		fail_reason = "bicaridine got through a sealed bio suit: the test's wrong"
		return BOT_GYM_FAIL
	if(called)
		return BOT_GYM_PASS
	return ..()

/datum/bot_scenario/griefed/borg/revive
	name = "cyborg: somebody who's just died is shocked back with its paddles"
	desc = "Somebody suffocated a moment ago, intact. A medical cyborg's module has defibrillator paddles: it goes over, activates them and shocks them back, as a player would, then sees to them."
	borg_module = /obj/item/robot_module/medical
	layout = list(
		"##########",
		"#R......C#",
		"#B.......#",
		"##########")

/datum/bot_scenario/griefed/borg/revive/grief()
	griefer.adjustOxyLoss(210)
	griefer.updatehealth()
	if(griefer.stat != DEAD)
		griefer.death()
	log_line("patient [griefer.stat == DEAD ? "dead" : "not dead"], [griefer.health] health")

/datum/bot_scenario/griefed/borg/revive/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(griefer.stat != DEAD && griefer.timeofdeath)
		log_line("patient back, [griefer.health] health")
		return BOT_GYM_PASS

// Layout letter j: a welding fuel tank.
/datum/bot_scenario/griefed/borg/engineer/refuel
	name = "cyborg: an engineering cyborg out of fuel fills its welder at the fuel tank, then mends the window"
	desc = "A cracked window and an empty welder. Clicking with an empty welder does nothing, and one cyborg did it 141 times: it fills the welder at the tank, switched off, and then mends the window."
	layout = list(
		"##########",
		"#R.....k.#",
		"#B..j...C#",
		"##########")

/datum/bot_scenario/griefed/borg/engineer/refuel/setup()
	..()
	for(var/turf/T in markers["j"])
		place("j", new /obj/structure/reagent_dispensers/fueltank(T))

/datum/bot_scenario/griefed/borg/engineer/refuel/post_spawn()
	. = ..()
	var/obj/item/weldingtool/W = locate() in borg.module.modules
	W?.reagents.remove_reagent(/datum/reagent/fuel, W.max_fuel)
	log_line("welder fuel [W?.get_fuel()]")

/datum/bot_scenario/griefed/borg/engineer/refuel/check()
	var/obj/structure/reagent_dispensers/fueltank/tank = first_placed("j")
	if(QDELETED(tank))
		fail_reason = "the fuel tank went up"
		return BOT_GYM_FAIL
	return ..()
