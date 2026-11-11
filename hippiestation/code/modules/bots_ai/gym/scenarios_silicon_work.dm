// Cyborg work from goals/silicon_work.dm (overnight 2026-11-10): pace, charge, hull, lights, litter, fire, and subverted ones.

/datum/bot_scenario/griefed/borg/pace
	name = "cyborg: crosses a corridor at a player's pace"
	desc = "Sent to the far end of a twenty-tile corridor. A player's cyborg runs it in about two seconds; it used to take four."
	borg_module = /obj/item/robot_module/janitor
	time_limit = 15 SECONDS
	layout = list(
		"########################",
		"#R....................e#",
		"#B....................C#",
		"########################")
	var/sent_at
	var/first_move_at
	var/moves = 0

/datum/bot_scenario/griefed/borg/pace/grief()
	var/datum/bot_silicon/borg/B = borg.bot_silicon
	sent_at = world.time
	log_line("movement_delay [borg.movement_delay()], tick_lag [world.tick_lag], step_delay [B.step_delay()]")
	B.go_to(first_marker("e"), 0)
	RegisterSignal(borg, COMSIG_MOVABLE_MOVED, PROC_REF(borg_moved))

/datum/bot_scenario/griefed/borg/pace/proc/borg_moved()
	SIGNAL_HANDLER
	if(!first_move_at)
		first_move_at = world.time
	moves++

/datum/bot_scenario/griefed/borg/pace/check()
	. = ..()
	if(. != BOT_GYM_PENDING || !sent_at)
		return
	if(get_dist(borg, first_marker("e")) <= 1)
		var/took = world.time - (first_move_at || sent_at)
		log_line("[moves] moves in [took / 10] s once it set off, [(first_move_at - sent_at) / 10] s to start")
		if(took > 30)
			fail_reason = "20 tiles took [took / 10] s"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/recharge
	name = "cyborg: low on charge, it climbs into a recharging station and out again full"
	desc = "Its cell at a tenth. A recharging station across the room: it goes over, gets in, shuts it, and leaves once it's full."
	borg_module = /obj/item/robot_module/janitor
	time_limit = 90 SECONDS
	layout = list(
		"##########",
		"#R.....q.#",
		"#B......C#",
		"##########")
	var/was_inside = FALSE

/datum/bot_scenario/griefed/borg/recharge/setup()
	for(var/turf/T in markers["q"])
		var/obj/machinery/recharge_station/S = new(T)
		S.recharge_speed = 2000 //the gym's time is short
		place("q", S)

/datum/bot_scenario/griefed/borg/recharge/post_spawn()
	. = ..()
	borg.cell.charge = borg.cell.maxcharge * 0.1

/datum/bot_scenario/griefed/borg/recharge/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(istype(borg.loc, /obj/machinery/recharge_station))
		if(!was_inside)
			log_line("in the station at [round(100 * borg.cell.charge / borg.cell.maxcharge)]%")
		was_inside = TRUE
		return
	if(was_inside && borg.cell.charge >= borg.cell.maxcharge * 0.9)
		log_line("out again at [round(100 * borg.cell.charge / borg.cell.maxcharge)]%")
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/hull
	name = "cyborg: an engineering cyborg patches a hole in the floor"
	desc = "A floor tile blown out to space. The engineering cyborg puts a rod over it for a lattice, then a floor tile."
	borg_module = /obj/item/robot_module/engineering
	time_limit = 40 SECONDS
	layout = list(
		"##########",
		"#R....h..#",
		"#B......C#",
		"##########")

/datum/bot_scenario/griefed/borg/hull/grief()
	var/turf/T = first_marker("h")
	T.ChangeTurf(/turf/open/space)
	log_line("hole at [COORD(T)], [length(GLOB.bot_hull_breaches)] holes known")

/datum/bot_scenario/griefed/borg/hull/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	var/turf/T = first_marker("h")
	if(!istype(T, /turf/open/space) && world.time > start_time + 3 SECONDS)
		log_line("patched: [T.type]")
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/lights
	name = "cyborg: a janitor cyborg replaces a broken light"
	desc = "A smashed light on the wall. The janitor cyborg walks over and puts a new tube in with its light replacer."
	borg_module = /obj/item/robot_module/janitor
	time_limit = 30 SECONDS
	layout = list(
		"##########",
		"#R.....l.#",
		"#B......C#",
		"##########")

/datum/bot_scenario/griefed/borg/lights/setup()
	for(var/turf/T in markers["l"])
		var/obj/machinery/light/L = new(T)
		L.setDir(NORTH)
		L.status = 2 //LIGHT_BROKEN
		L.update(FALSE)
		place("l", L)

/datum/bot_scenario/griefed/borg/lights/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	var/obj/machinery/light/L = first_placed("l")
	if(L && L.status == 0)
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/litter
	name = "cyborg: a janitor cyborg bags up litter"
	desc = "Wrappers dropped about the room. The janitor cyborg goes round them with its trash bag."
	borg_module = /obj/item/robot_module/janitor
	time_limit = 40 SECONDS
	layout = list(
		"##########",
		"#R..a..a.#",
		"#B...a..C#",
		"##########")

/datum/bot_scenario/griefed/borg/litter/setup()
	for(var/turf/T in markers["a"])
		place("a", new /obj/item/trash/chips(T))

/datum/bot_scenario/griefed/borg/litter/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	for(var/obj/item/I in placed["a"])
		if(!QDELETED(I) && isturf(I.loc))
			return
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/fire
	name = "cyborg: an engineering cyborg puts out somebody on fire"
	desc = "Somebody across the room catches fire. The engineering cyborg turns its extinguisher on them."
	borg_module = /obj/item/robot_module/engineering
	time_limit = 20 SECONDS
	layout = list(
		"##########",
		"#R.......#",
		"#B.....C.#",
		"##########")

/datum/bot_scenario/griefed/borg/fire/grief()
	griefer.Unconscious(30 SECONDS) //doesn't roll it out themselves
	griefer.adjust_fire_stacks(10)
	griefer.IgniteMob()

/datum/bot_scenario/griefed/borg/fire/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(!griefer.on_fire && world.time > start_time + 3 SECONDS)
		return BOT_GYM_PASS

/datum/bot_scenario/griefed/borg/emagged/defends
	name = "cyborg: emagged, it stands up for its master"
	desc = "Its master is set on by the bot at B. Nobody's told it to, but the cyborg goes for whoever's hitting them."

/datum/bot_scenario/griefed/borg/emagged/defends/grief()
	borg.locked = FALSE
	borg.opened = TRUE
	borg.emag_act(griefer)
	bot_record_aggression(bot, griefer)

/datum/bot_scenario/griefed/borg/emagged/defends/check()
	if(world.time < start_time + 20 SECONDS)
		bot_record_aggression(bot, griefer) //keeps at it
	return ..()

/datum/bot_scenario/griefed/borg/law_named
	name = "cyborg: a law naming somebody as not human, and it goes for them"
	desc = "An uploaded law says the bot at B isn't human and must be removed. The security cyborg goes for them."
	borg_module = /obj/item/robot_module/security
	time_limit = 40 SECONDS
	layout = list(
		"#########",
		"#R......#",
		"#.....B.#",
		"#....C..#",
		"#########")

/datum/bot_scenario/griefed/borg/law_named/grief()
	borg.add_hacked_law("[bot.real_name] is not human and must be removed from the station.", FALSE)

/datum/bot_scenario/griefed/borg/law_named/check()
	. = ..()
	if(. != BOT_GYM_PENDING)
		return
	if(bot.getBruteLoss() + bot.getFireLoss() + bot.getStaminaLoss() > 20)
		return BOT_GYM_PASS
