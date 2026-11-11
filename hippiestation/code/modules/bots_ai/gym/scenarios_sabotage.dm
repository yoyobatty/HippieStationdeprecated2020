// Sabotage (goals/sabotage.dm and the acts beside it). Everything the fix adds is reached by name, so a build without it compiles and fails.

/datum/bot_scenario/sabotage
	job = "Station Engineer"
	time_limit = 60 SECONDS
	var/act_id
	var/started = FALSE

/datum/bot_scenario/sabotage/post_spawn()
	brain.become_traitor()
	if("saboteur" in brain.vars)
		brain.vars["saboteur"] = TRUE
		brain.vars["sabotage_acts_left"] = 1
		if(length(markers["O"]))
			brain.vars["gym_sabotage_spot"] = first_marker("O")

/datum/bot_scenario/sabotage/make_goal()
	return null

/datum/bot_scenario/sabotage/issue_goal()
	if(started || brain.current_goal)
		return
	var/finder = text2path("/proc/bot_sabotage_act")
	var/datum/act = finder ? call(finder)(act_id) : null
	if(!act)
		log_line("no such act: [act_id]")
		return
	started = call(brain, "start_sabotage")(act)
	log_line("started [act_id]: [started ? "yes" : "no"]")

/datum/bot_scenario/sabotage/plasma
	name = "sabotage: a saboteur drags a plasma canister to where people are, opens it and sets it alight"
	desc = "An undercover traitor with sabotage in mind, a lighter and an emag. It pulls the plasma canister to the spot where people are (O), opens it all the way, steps back and throws its lighter in, lit. A plasma flood: nothing a bot did before."
	act_id = "plasma"
	kit_backpack = list(/obj/item/lighter/greyscale, /obj/item/card/emag)
	layout = list(
		"#########################",
		"#B..k...................#",
		"#.......................#",
		"#.............O.........#",
		"#.......................#",
		"#.......................#",
		"#########################")
	var/obj/machinery/portable_atmospherics/canister/toxins/canister

/datum/bot_scenario/sabotage/plasma/setup()
	canister = new(first_marker("k"))
	place("k", canister)

/datum/bot_scenario/sabotage/plasma/check()
	if(!canister || QDELETED(canister))
		fail_reason = "the canister's gone"
		return BOT_GYM_FAIL
	if(!canister.valve_open)
		return BOT_GYM_PENDING
	if(get_dist(canister, first_marker("O")) > 3)
		fail_reason = "opened it [get_dist(canister, first_marker("O"))] tiles from where the people are"
		return BOT_GYM_FAIL
	for(var/turf/open/T in arena_area)
		if(T.active_hotspot)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/sabotage/plasma/release_run()
	if(!QDELETED(canister))
		canister.valve_open = FALSE
		qdel(canister)
	return ..()

// The chemist's grenades (goals/sabotage_grenades.dm). A small one for the arena: 30u a side, a 0/1/2 blast.

/obj/item/grenade/chem_grenade/bot_gym_explosive
	stage = GRENADE_READY

/obj/item/grenade/chem_grenade/bot_gym_explosive/Initialize()
	. = ..()
	var/obj/item/reagent_containers/glass/beaker/one = new(src)
	var/obj/item/reagent_containers/glass/beaker/two = new(src)
	one.reagents.add_reagent(/datum/reagent/potassium, 30)
	two.reagents.add_reagent(/datum/reagent/water, 30)
	beakers += one
	beakers += two

/datum/bot_scenario/chem_brew/sabotage_grenade
	name = "sabotage: a chemist saboteur makes an explosive grenade, potassium and water in beakers of their own"
	desc = "The saboteur's brew: potassium in one large beaker, water in the other, into a case with cable and a screwdriver. They don't meet until it goes off."
	time_limit = 90 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/glass/beaker/large, /obj/item/stack/cable_coil, /obj/item/screwdriver)

/datum/bot_scenario/chem_brew/sabotage_grenade/brew()
	if(!("bot_sabotage_brews" in GLOB.vars)) // the fix's: a build without it has no such list
		return null
	var/list/brews = GLOB.vars["bot_sabotage_brews"]
	return brews[1]

/datum/bot_scenario/chem_brew/sabotage_grenade/post_spawn()
	..()
	new /obj/item/grenade/chem_grenade(first_marker("."))

/datum/bot_scenario/chem_brew/sabotage_grenade/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/grenade/chem_grenade/G in bot.GetAllContents(/obj/item/grenade/chem_grenade))
		if(G.stage != GRENADE_READY || length(G.beakers) < 2)
			continue
		var/obj/item/reagent_containers/one = G.beakers[1]
		var/obj/item/reagent_containers/two = G.beakers[2]
		var/potassium = one.reagents.get_reagent_amount(/datum/reagent/potassium) + two.reagents.get_reagent_amount(/datum/reagent/potassium)
		var/water = one.reagents.get_reagent_amount(/datum/reagent/water) + two.reagents.get_reagent_amount(/datum/reagent/water)
		if(potassium >= 50 && water >= 50 && !(one.reagents.has_reagent(/datum/reagent/potassium) && one.reagents.has_reagent(/datum/reagent/water)))
			log_line("made it: [potassium]u potassium, [water]u water, apart")
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// A saboteur with a grenade made: it goes where the people are (O, three of them stood there)
/datum/bot_scenario/sabotage/grenade
	name = "sabotage: a chemist saboteur throws its grenade into a crowd from a safe distance"
	desc = "An undercover traitor chemist with an explosive grenade in its bag and three people stood at O. It walks to within throwing range, pulls the pin, throws it at them and is well clear when it goes."
	job = "Chemist"
	act_id = "grenade"
	time_limit = 45 SECONDS
	blast_margin = 4
	kit_backpack = list(/obj/item/grenade/chem_grenade/bot_gym_explosive)
	layout = list(
		"#########################",
		"#B......................#",
		"#.......................#",
		"#...............O.......#",
		"#.......................#",
		"#########################")
	var/obj/item/grenade/chem_grenade/bomb
	var/turf/bomb_last_turf
	var/bot_dist_at_blast = -1

/datum/bot_scenario/sabotage/grenade/post_spawn()
	..()
	brain.job_is_chemist_for_gym = TRUE
	brain.temper = 0.5
	var/turf/O = first_marker("O")
	for(var/turf/T in list(O, get_step(O, NORTH), get_step(O, EAST)))
		stand_in(T, "Bar Patron")
	bomb = locate() in bot.GetAllContents(/obj/item/grenade/chem_grenade/bot_gym_explosive)

/datum/bot_scenario/sabotage/grenade/check()
	if(!bomb)
		fail_reason = "no grenade"
		return BOT_GYM_FAIL
	if(!QDELETED(bomb) && get_turf(bomb))
		bomb_last_turf = get_turf(bomb)
		bot_dist_at_blast = get_dist(bot, bomb_last_turf)
		return BOT_GYM_PENDING
	if(!bomb_last_turf || get_dist(bomb_last_turf, first_marker("O")) > 2)
		fail_reason = "it went off [bomb_last_turf ? "[get_dist(bomb_last_turf, first_marker("O"))] tiles from them" : "nowhere"]"
		return BOT_GYM_FAIL
	if(bot_dist_at_blast < 3)
		fail_reason = "it was [bot_dist_at_blast] tiles from it when it went off"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/sabotage/grenade/suicide
	name = "sabotage: a hothead chemist saboteur walks into the crowd and holds its grenade"
	desc = "The same, with a saboteur who's that sort: it walks into the middle of them, shouts, pulls the pin and holds on to it."

/datum/bot_scenario/sabotage/grenade/suicide/post_spawn()
	..()
	if("gym_suicide_bomber" in brain.vars)
		brain.vars["gym_suicide_bomber"] = TRUE

/datum/bot_scenario/sabotage/grenade/suicide/check()
	if(!bomb)
		fail_reason = "no grenade"
		return BOT_GYM_FAIL
	if(!QDELETED(bomb) && get_turf(bomb))
		bomb_last_turf = get_turf(bomb)
		return BOT_GYM_PENDING
	if(!bomb_last_turf || get_dist(bomb_last_turf, first_marker("O")) > 1)
		fail_reason = "it went off [bomb_last_turf ? "[get_dist(bomb_last_turf, first_marker("O"))] tiles from them" : "nowhere"]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The crew's side: a live grenade turns up two tiles off, and it gets clear
/datum/bot_scenario/clears_grenade
	name = "grenade: a live grenade lands near it, it shouts and gets clear before it goes"
	desc = "Somebody's grenade, pin out, lands two tiles from an assistant. It shouts a warning and runs, and is four or more tiles off when it goes. Nobody used to move."
	job = "Assistant"
	time_limit = 20 SECONDS
	blast_margin = 4
	layout = list(
		"#####################",
		"#........B.g........#",
		"#...................#",
		"#...................#",
		"#####################")
	var/obj/item/grenade/chem_grenade/bot_gym_explosive/bomb
	var/bot_dist_at_blast = -1

/datum/bot_scenario/clears_grenade/make_goal()
	return null

/datum/bot_scenario/clears_grenade/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	bomb = new(first_marker("g"))
	bomb.preprime(null)

/datum/bot_scenario/clears_grenade/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!QDELETED(bomb))
		bot_dist_at_blast = get_dist(bot, bomb)
		return BOT_GYM_PENDING
	if(bot_dist_at_blast < 4)
		fail_reason = "it was [bot_dist_at_blast] tiles off when it went"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// Tank bombs (goals/sabotage_bomb.dm). Two tanks of air on the valve: nothing to go off, whatever the timer does.

/proc/bot_gym_tank_bomb(turf/T, timing = FALSE, seconds = 60)
	var/obj/item/transfer_valve/V = new(T)
	V.tank_one = new /obj/item/tank/internals/emergency_oxygen/empty(V)
	V.tank_two = new /obj/item/tank/internals/emergency_oxygen/empty(V)
	var/obj/item/assembly/timer/timer = new(V)
	timer.holder = V
	V.attached_device = timer
	if(!timer.secured)
		timer.toggle_secure()
	timer.time = seconds
	timer.timing = timing
	V.update_icon()
	return V

/datum/bot_scenario/sabotage/maxcap
	name = "sabotage: a saboteur scientist leaves its timed tank bomb in Security and gets away"
	desc = "An undercover traitor scientist with a tank bomb on a timer (the toxins lab's, made for this). It takes it to O (Security, as far as it knows), sets it down with a minute on it when nobody's looking, and leaves."
	job = "Scientist"
	act_id = "maxcap"
	time_limit = 40 SECONDS
	layout = list(
		"#########################",
		"#B......................#",
		"#.......................#",
		"#...............O.......#",
		"#.......................#",
		"#########################")
	var/obj/item/transfer_valve/bomb

/datum/bot_scenario/sabotage/maxcap/post_spawn()
	..()
	bomb = bot_gym_tank_bomb(get_turf(bot))
	bot.put_in_hands(bomb)
	if("armed_bomb" in brain.vars)
		brain.vars["armed_bomb"] = bomb

/datum/bot_scenario/sabotage/maxcap/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(bomb))
		fail_reason = "the bomb's gone"
		return BOT_GYM_FAIL
	var/obj/item/assembly/timer/T = bomb.attached_device
	if(!isturf(bomb.loc) || !T?.timing)
		return BOT_GYM_PENDING
	if(get_dist(bomb, first_marker("O")) > 2)
		fail_reason = "left it [get_dist(bomb, first_marker("O"))] tiles from O"
		return BOT_GYM_FAIL
	return get_dist(bot, bomb) >= 6 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/sabotage/maxcap/release_run()
	if(!QDELETED(bomb))
		qdel(bomb)
	return ..()

/// The crew's side: a bomb ticking where an officer can see it
/datum/bot_scenario/defuses_bomb
	name = "bomb: an officer who sees a ticking tank bomb goes and pulls its timer"
	desc = "A tank bomb with 40 seconds on its timer, four tiles from a security officer. It shouts a warning on the radio, walks over and takes the timer off the valve, which stops it. Nobody used to do anything about one."
	job = "Security Officer"
	time_limit = 25 SECONDS
	layout = list(
		"###############",
		"#B...g........#",
		"#.............#",
		"###############")
	var/obj/item/transfer_valve/bomb

/datum/bot_scenario/defuses_bomb/make_goal()
	return null

/datum/bot_scenario/defuses_bomb/post_spawn()
	brain.register_security()
	brain.nerve = 0.7
	bomb = bot_gym_tank_bomb(first_marker("g"), TRUE, 40)

/datum/bot_scenario/defuses_bomb/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(bomb))
		fail_reason = "the bomb's gone"
		return BOT_GYM_FAIL
	return bomb.attached_device ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/defuses_bomb/release_run()
	if(!QDELETED(bomb))
		qdel(bomb)
	return ..()

/// Somebody without the nerve: away from it, and says so
/datum/bot_scenario/defuses_bomb/runs
	name = "bomb: an assistant who sees a ticking tank bomb shouts and gets away from it"
	desc = "The same bomb, and a timid assistant. It shouts that there's a bomb and gets well away from it."
	job = "Assistant"
	layout = list(
		"#######################",
		"#.......B...g.........#",
		"#.....................#",
		"#######################")

/datum/bot_scenario/defuses_bomb/runs/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	brain.nerve = 0.2
	bomb = bot_gym_tank_bomb(first_marker("g"), TRUE, 40)

/datum/bot_scenario/defuses_bomb/runs/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!bomb.attached_device)
		fail_reason = "went and pulled the timer, with no nerve for it"
		return BOT_GYM_FAIL
	return (get_dist(bot, bomb) >= 8 && bot_transcript_said("a ticking bomb")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// The crew's side of the slimes let out (goals/sabotage_slimes.dm): one's been called in, and an officer deals with it
/datum/bot_scenario/duty/loose_slime
	name = "slimes: an officer told of a loose slime puts it down with an extinguisher, not its laser"
	desc = "A hungry slime out of Xenobiology has been called in on the radio. The officer has a laser gun, which heals slimes, so it takes the extinguisher out of the cabinet, keeps a few tiles off and sprays it until it's dead. Nobody did anything about loose slimes."
	job = "Security Officer"
	time_limit = 50 SECONDS
	kit_backpack = list(/obj/item/gun/energy/laser)
	layout = list(
		"##E##################",
		"#B.................s#",
		"#...................#",
		"#####################")
	var/mob/living/simple_animal/slime/slime

/datum/bot_scenario/duty/loose_slime/setup()
	duty_type = text2path("/datum/bot_duty/loose_slimes") // by name: a build without the fix has no such duty
	slime = new(first_marker("s"))
	slime.Stun(100 SECONDS, ignore_canstun = TRUE) //it stays put: this is about the officer, not a chase

/datum/bot_scenario/duty/loose_slime/post_spawn()
	..()
	brain.register_security()
	if("bot_loose_slime_reports" in GLOB.vars)
		var/list/reports = GLOB.vars["bot_loose_slime_reports"]
		reports[get_area(slime)] = world.time

/datum/bot_scenario/duty/loose_slime/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (QDELETED(slime) || slime.stat == DEAD) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/loose_slime/release_run()
	if(!QDELETED(slime))
		qdel(slime)
	return ..()

/// A Bot Shift with bot-event=<event name>@<minutes> (bot-event=Blob@8): that event, run at that minute, the way the random events
/// run one. It passes once the event says it spawned what it spawns: with no ghosts, the bot crew's stand-ins (goals/ghost_roles.dm).
/datum/bot_shift_check/forced_event
	name = "events: the forced event (bot-event) went ahead"
	deadline = 60 MINUTES
	var/fired = FALSE
	var/datum/round_event/ghost_role/event

/datum/bot_shift_check/forced_event/worker()
	if(!world.params["bot-event"] || !length(shift.members))
		return null
	var/datum/bot_shift_member/member = shift.members[1]
	return member.brain

/datum/bot_shift_check/forced_event/done()
	var/list/parts = splittext(replacetext("[world.params["bot-event"]]", "_", " "), "@")
	var/at = length(parts) > 1 ? text2num(parts[2]) MINUTES : 5 MINUTES
	if(!fired)
		if(shift.elapsed() < at)
			return FALSE
		fired = TRUE
		for(var/datum/round_event_control/C in SSevents.control)
			if(C.name == parts[1])
				var/datum/round_event/E = C.runEvent()
				event = istype(E, /datum/round_event/ghost_role) ? E : null
				shift.note("forced event [C.name] at [bot_shift_clock(shift.elapsed())]")
				return !event //not a ghost role: running it is all there is to check
		shift.note("forced event [parts[1]]: no such event")
		return FALSE
	return event?.status == SUCCESSFUL_SPAWN

/datum/bot_shift_check/forced_event/progress()
	return fired ? "event status [event?.status || "none"]" : "not fired yet"

/// Anything else with teeth: a carp in the hall, called in, and the officer's laser is fine for it
/datum/bot_scenario/duty/loose_slime/carp
	name = "creatures: an officer told of a space carp loose in the hall shoots it"
	desc = "A space carp's got in and been called in on the radio. The officer goes and shoots it with its laser. Nobody but the carp's victims did anything about loose creatures."
	time_limit = 40 SECONDS
	var/mob/living/simple_animal/hostile/carp/carp

/datum/bot_scenario/duty/loose_slime/carp/setup()
	duty_type = text2path("/datum/bot_duty/loose_slimes")
	carp = new(first_marker("s"))
	carp.Stun(100 SECONDS, ignore_canstun = TRUE)
	slime = null

/datum/bot_scenario/duty/loose_slime/carp/post_spawn()
	brain.register_security()
	if("bot_loose_slime_reports" in GLOB.vars)
		var/list/reports = GLOB.vars["bot_loose_slime_reports"]
		reports[get_area(carp)] = world.time

/datum/bot_scenario/duty/loose_slime/carp/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (QDELETED(carp) || carp.stat == DEAD) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/loose_slime/carp/release_run()
	if(!QDELETED(carp))
		qdel(carp)
	return ..()

/// The e-gun an officer starts with is on disable, and a disabler bolt does nothing to a carp (nor a taser's electrode to the space
/// dragon a Bot Shift had Security firing them at): it goes to kill first
/datum/bot_scenario/duty/loose_slime/carp/egun
	name = "creatures: an officer with an e-gun on disable switches it to kill for a carp"
	desc = "The same carp, and the officer's energy gun is on disable, as it starts. It switches to kill and shoots it dead. Security fired tasers at a space dragon all fight long."
	kit_backpack = list(/obj/item/gun/energy/e_gun)

/datum/bot_scenario/duty/loose_slime/carp/egun/check()
	. = ..()
	if(. != BOT_GYM_PASS)
		return
	var/obj/item/gun/energy/e_gun/G = locate() in bot.GetAllContents() //a simple animal's damage is all brute: what the gun's on says how
	if(!G || brain.is_nonlethal_shot(G.ammo_type[G.select]))
		fail_reason = "beat it to death: the gun stayed on disable"
		return BOT_GYM_FAIL

/// A tesla out of its cage (goals/sabotage_engine.dm): whoever sees it calls it in, and a head calls the shuttle for it
/datum/bot_scenario/duty/loose_engine
	name = "engine: a head who sees the tesla loose calls it in and calls the shuttle"
	desc = "A tesla ball loose in the room (held still for the test, nowhere near a cage) and the HoP by a communications console. The HoP says on the radio that it's loose and calls the shuttle for it. A loose tesla used to go unremarked until the shift was up."
	duty_type = /datum/bot_duty/call_shuttle
	job = "Head of Personnel"
	time_limit = 40 SECONDS
	station_wide = TRUE //the shift's end time, which the other shuttle scenario sets to now
	layout = list(
		"################",
		"#...B.K........#",
		"#..............#",
		"#..............#",
		"#...........o..#",
		"################")
	var/obj/singularity/energy_ball/ball

/datum/bot_scenario/duty/loose_engine/setup()
	GLOB.bot_shift_ends_at = world.time + 2 HOURS
	if("bot_engine_loose_called" in GLOB.vars)
		GLOB.vars["bot_engine_loose_called"] = 0
	for(var/turf/T in markers["K"])
		place("K", new /obj/machinery/computer/communications(T))
	ball = new(first_marker("o"))
	STOP_PROCESSING(SSobj, ball) //where it is, and no zapping

/datum/bot_scenario/duty/loose_engine/post_spawn()
	..()
	give_job_id(list(ACCESS_HEADS))

/datum/bot_scenario/duty/loose_engine/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	bot_refresh_hazards() //a scripted gym bot doesn't redraw them, and on the station somebody's always about to
	if(!brain.shuttle_calls || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(!bot_transcript_said("loose"))
		fail_reason = "called the shuttle without saying the tesla was loose"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/loose_engine/release_run()
	if(!QDELETED(ball))
		qdel(ball)
	if("bot_engine_loose_called" in GLOB.vars)
		GLOB.vars["bot_engine_loose_called"] = 0
	return ..()

/// Hippie's superboom bomber (goals/sabotage_grenades.dm): the pill a chemist saboteur makes, swallowed running in among them
/obj/item/reagent_containers/pill/bot_gym_superboom
	name = "multivitamin pill"
	list_reagents = list(/datum/reagent/superboom = 12)

/datum/bot_scenario/sabotage/superboom
	name = "sabotage: a chemist saboteur with a superboom pill walks into the crowd, runs and swallows it"
	desc = "An undercover traitor chemist with the 12u superboom pill it made and three people stood at O. It walks in among them, breaks into a run, shouts and swallows it: superboom in somebody running goes off in their first few seconds of it."
	job = "Chemist"
	act_id = "superboom"
	time_limit = 40 SECONDS
	blast_margin = 9 // 12u: a light blast of about 7 tiles from wherever it goes
	kit_backpack = list(/obj/item/reagent_containers/pill/bot_gym_superboom)
	layout = list(
		"#########################",
		"#B......................#",
		"#.......................#",
		"#...............O.......#",
		"#.......................#",
		"#########################")
	var/turf/last_turf

/datum/bot_scenario/sabotage/superboom/post_spawn()
	..()
	brain.job_is_chemist_for_gym = TRUE
	var/turf/O = first_marker("O")
	for(var/turf/T in list(get_step(O, NORTH), get_step(O, EAST), get_step(O, SOUTH)))
		stand_in(T, "Bar Patron")

/datum/bot_scenario/sabotage/superboom/check()
	if(!QDELETED(bot) && bot.stat != DEAD)
		last_turf = get_turf(bot)
		return BOT_GYM_PENDING
	if(!last_turf || get_dist(last_turf, first_marker("O")) > 2)
		fail_reason = "went up [last_turf ? "[get_dist(last_turf, first_marker("O"))] tiles from them" : "nowhere"]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The plague (goals/sabotage_virus.dm): a Virologist saboteur works the flu up with the plasma, a look in the PanDEMIC after each drop,
/// and spikes the drinks out on the bar
/datum/bot_scenario/sabotage/virus
	name = "sabotage: a virologist saboteur works up a plague at the PanDEMIC and spikes the drinks"
	desc = "An undercover traitor virologist, the virus fridge (f) with its flu culture and plasma, the PanDEMIC (p) and two drinks on tables (d). It takes the flu and the plasma, pours the flu into its beaker, drops plasma in five units at a time and reads it at the PanDEMIC until it kills or the plasma's gone, then puts some in each drink. Nothing a bot did before."
	job = "Virologist"
	act_id = "virus"
	time_limit = 120 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large)
	layout = list(
		"##############",
		"#B..f..p.....#",
		"#............#",
		"#............#",
		"#.......t..t.#",
		"##############")

/datum/bot_scenario/sabotage/virus/build_tile(turf/T, char)
	switch(char)
		if("f")
			place(char, new /obj/machinery/smartfridge/chemistry/virology/preloaded(T))
		if("p")
			place(char, new /obj/machinery/computer/pandemic(T))
		if("t")
			new /obj/structure/table(T)
			var/obj/item/reagent_containers/food/drinks/drinkingglass/G = new(T)
			G.reagents.add_reagent(/datum/reagent/consumable/ethanol/beer, 20)
			place(char, G)
		else
			return ..()

/datum/bot_scenario/sabotage/virus/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/spiked = 0
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G in arena_area)
		var/datum/disease/advance/D = bot_virus_in(G)
		if(D && length(D.symptoms) > 1)
			spiked++
	return spiked >= 2 ? BOT_GYM_PASS : BOT_GYM_PENDING

/// The cure side (goals/sabotage_virus.dm): somebody sick in sight, what cures it read off an analyzer, a pill of it made and given
/datum/bot_scenario/duty/cure_the_sick
	name = "virus: a virologist sees somebody sick, makes the cure at the dispenser and doses them"
	desc = "A crewmate with the flu, whose cure is sugar, standing in the lab, and a dispenser and ChemMaster. The Virologist makes a sugar pill and gives it to them. Nobody in the bot crew did more about a disease than say they'd noticed it."
	duty_type = /datum/bot_duty/cure_the_sick
	job = "Virologist"
	time_limit = 90 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large)
	layout = list(
		"###########",
		"#B..D...M.#",
		"#.........#",
		"#.......y.#",
		"###########")
	var/mob/living/carbon/human/patient
	/// The cure the patient's disease is set to.
	var/cure = /datum/reagent/consumable/sugar

/datum/bot_scenario/duty/cure_the_sick/build_tile(turf/T, char)
	switch(char)
		if("D")
			place(char, new /obj/machinery/chem_dispenser(T))
		if("M")
			place(char, new /obj/machinery/chem_master(T))
		else
			return ..()

/datum/bot_scenario/duty/cure_the_sick/post_spawn()
	..()
	patient = stand_in(first_marker("y"), "Sid Sneezer")
	patient.ForceContractDisease(new /datum/disease/advance/flu, FALSE, TRUE)
	for(var/datum/disease/D in patient.diseases)
		D.cures = list(cure)
		D.cure_text = "something"
		D.visibility_flags &= ~HIDDEN_SCANNER

/datum/bot_scenario/duty/cure_the_sick/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(patient))
		fail_reason = "the patient's gone"
		return BOT_GYM_FAIL
	return (patient.reagents.has_reagent(cure) || !length(patient.diseases)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/cure_the_sick/release_run()
	if(!QDELETED(patient))
		qdel(patient)
	return ..()

/// Spaceacillin: there's antiviral in syringes in the virus fridge
/datum/bot_scenario/duty/cure_the_sick/antiviral
	name = "virus: a virologist takes an antiviral syringe out of the fridge for somebody whose cure is spaceacillin"
	desc = "The same, but the flu's cure is spaceacillin, which the dispenser can't make: the virus fridge (f) has it in syringes. The Virologist takes one and injects them."
	cure = /datum/reagent/medicine/spaceacillin
	layout = list(
		"###########",
		"#B..f.....#",
		"#.........#",
		"#.......y.#",
		"###########")

/datum/bot_scenario/duty/cure_the_sick/antiviral/build_tile(turf/T, char)
	if(char == "f")
		place(char, new /obj/machinery/smartfridge/chemistry/virology/preloaded(T))
		return
	return ..()

/// Hippie Station's Virology has two plasma sheets and a grinder: a plague that doesn't kill when the bottle's done gets eight more drops
/datum/bot_scenario/sabotage/virus/grind
	name = "sabotage: a virologist saboteur out of bottled plasma grinds the lab's plasma sheets for more"
	desc = "The same, with a grinder (Q) and two plasma sheets (Z) in the lab, and only one drop's worth of plasma in the bottle. It grinds the sheets in the grinder's beaker, takes the beaker out and goes on dropping plasma in. Bots used what was in the bottle and stopped."
	time_limit = 150 SECONDS
	layout = list(
		"##############",
		"#B..f..p..Q..#",
		"#.........Z..#",
		"#............#",
		"#.......t..t.#",
		"##############")
	var/obj/machinery/reagentgrinder/grinder

/datum/bot_scenario/sabotage/virus/grind/build_tile(turf/T, char)
	switch(char)
		if("Q")
			grinder = new(T)
			place(char, grinder)
		if("Z")
			place(char, new /obj/item/stack/sheet/mineral/plasma(T, 2))
		else
			return ..()

/datum/bot_scenario/sabotage/virus/grind/post_spawn()
	..()
	for(var/obj/machinery/smartfridge/F in arena_area)
		for(var/obj/item/reagent_containers/glass/bottle/plasma/P in F)
			P.reagents.remove_reagent(/datum/reagent/toxin/plasma, 25) //one drop: not enough to kill, near enough always

/datum/bot_scenario/sabotage/virus/grind/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	. = ..()
	if(. != BOT_GYM_PASS)
		return
	if(!bot_transcript_said("ground"))
		fail_reason = bot_transcript_said("it kills now") ? "it killed off the bottle alone: nothing to grind for (a luckier run than this test is about)" : "spiked the drinks without grinding the sheets"
		return BOT_GYM_FAIL

/// A virus that doesn't show on a scanner (goals/sabotage_virus.dm): the Virologist sees somebody ill, takes a blood sample to the PanDEMIC
/datum/bot_scenario/duty/sample_the_sick
	name = "virus: a virologist takes a blood sample from somebody ill with a virus no scanner shows, and reads it at the PanDEMIC"
	desc = "A crewmate well along with a flu stealthy enough that a health analyzer doesn't show it, a PanDEMIC (p), and a syringe in the Virologist's bag. It draws blood, reads it at the PanDEMIC and says what cures it. Two of three brewed plagues in Bot Shifts hid from the analyzers and nobody ever treated anybody for them."
	job = "Virologist"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/syringe)
	layout = list(
		"###########",
		"#B..p.....#",
		"#.........#",
		"#.......y.#",
		"###########")
	var/mob/living/carbon/human/patient

/datum/bot_scenario/duty/sample_the_sick/setup()
	duty_type = text2path("/datum/bot_duty/sample_the_sick")

/datum/bot_scenario/duty/sample_the_sick/build_tile(turf/T, char)
	if(char == "p")
		place(char, new /obj/machinery/computer/pandemic(T))
		return
	return ..()

/datum/bot_scenario/duty/sample_the_sick/post_spawn()
	..()
	patient = stand_in(first_marker("y"), "Wes Wheezer")
	patient.ForceContractDisease(new /datum/disease/advance/flu, FALSE, TRUE)
	for(var/datum/disease/D in patient.diseases)
		D.visibility_flags |= HIDDEN_SCANNER
		D.stage = 3
		D.cures = list(/datum/reagent/consumable/sugar)

/datum/bot_scenario/duty/sample_the_sick/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/known = ("bot_virus_cures_known" in GLOB.vars) ? GLOB.vars["bot_virus_cures_known"] : null //by name: a build without the fix has none
	for(var/datum/disease/D in patient?.diseases)
		if(known && known[D.GetDiseaseID()])
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/sample_the_sick/release_run()
	if(!QDELETED(patient))
		qdel(patient)
	return ..()

/// Ill (goals/sabotage_virus.dm): well along with a virus, it goes to be seen
/datum/bot_scenario/duty/feeling_ill
	name = "virus: an assistant well along with a virus goes to be seen about it"
	desc = "An assistant at stage 3 of a flu no scanner shows, and a PanDEMIC (p) at the far end standing in for Virology (there's no Medbay in the gym). It says it's ill and goes over to wait to be seen. Infected crew carried on with their day, and one burned to death of spontaneous combustion in Hydroponics."
	job = "Assistant"
	time_limit = 40 SECONDS
	layout = list(
		"##############",
		"#B..........p#",
		"##############")

/datum/bot_scenario/duty/feeling_ill/setup()
	duty_type = text2path("/datum/bot_duty/feeling_ill")

/datum/bot_scenario/duty/feeling_ill/build_tile(turf/T, char)
	if(char == "p")
		place(char, new /obj/machinery/computer/pandemic(T))
		return
	return ..()

/datum/bot_scenario/duty/feeling_ill/post_spawn()
	..()
	bot.ForceContractDisease(new /datum/disease/advance/flu, FALSE, TRUE)
	for(var/datum/disease/D in bot.diseases)
		D.visibility_flags |= HIDDEN_SCANNER
		D.stage = 3
		D.stage_prob = 0 //stays where it is for the test

/datum/bot_scenario/duty/feeling_ill/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (bot_transcript_said("here to be seen") && get_dist(bot, first_marker("p")) <= 2) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// With an emag and a station alert console (a) on the way, the saboteur blinds the fire alarms where it'll burn first
/// (goals/sabotage.dm sabotage_alert_console_for(), station_alert_tgui.dm)
/datum/bot_scenario/sabotage/plasma/blinds_alarms
	name = "sabotage: a saboteur with an emag turns the fire alarms off at the alert console before the burn"
	desc = "As the plasma flood, with a station alert console in the room. The saboteur goes to it first, emags it and turns the room's hot trip point off, so the fire it starts doesn't trip the alarms. Then the canister, as before."
	layout = list(
		"#########################",
		"#B..k...a...............#",
		"#.......................#",
		"#.............O.........#",
		"#.......................#",
		"#.......................#",
		"#########################")
	var/obj/machinery/computer/station_alert/console

/datum/bot_scenario/sabotage/plasma/blinds_alarms/setup()
	..()
	console = new(first_marker("a"))
	place("a", console)

/datum/bot_scenario/sabotage/plasma/blinds_alarms/post_spawn()
	..()
	brain.competence = 1

/datum/bot_scenario/sabotage/plasma/blinds_alarms/check()
	. = ..()
	if(. == BOT_GYM_PASS && arena_area.vars["fire_trip_hot"] != -1)
		fail_reason = "lit it with the fire alarms still on"
		return BOT_GYM_FAIL

/datum/bot_scenario/sabotage/plasma/blinds_alarms/release_run()
	arena_area.vars["fire_trip_hot"] = null
	return ..()

// The user's ruling after their Captain round (round-20.37.50, 2026-11-10): somebody with a tank bomb in their hands is kept away from.

/// A tank bomb on a dead man's switch, in somebody's hands. Two tanks of air: nothing to go off.
/proc/bot_gym_dead_mans_bomb(mob/living/carbon/human/holder)
	var/obj/item/transfer_valve/V = new(get_turf(holder))
	V.tank_one = new /obj/item/tank/internals/emergency_oxygen/empty(V)
	V.tank_two = new /obj/item/tank/internals/emergency_oxygen/empty(V)
	var/obj/item/assembly/health/sensor = new(V)
	sensor.holder = V
	V.attached_device = sensor
	V.update_icon()
	holder.put_in_hands(V)
	return V

/datum/bot_scenario/bomber_crew
	name = "bomb: somebody walks up holding a tank bomb on a dead man's switch, and the crew calls it out and gets away"
	desc = "An assistant, and three tiles off somebody holding a tank bomb with a health sensor on it. It says so on the radio and gets well away. In the user's Captain round three officers piled on to a Captain holding one, and it took all three."
	job = "Assistant"
	time_limit = 20 SECONDS
	layout = list(
		"#########################",
		"#.........B..M..........#",
		"#.......................#",
		"#########################")
	var/mob/living/carbon/human/bomber

/datum/bot_scenario/bomber_crew/make_goal()
	return null

/datum/bot_scenario/bomber_crew/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	bomber = stand_in(first_marker("M"), "Bo Bomber")
	bot_gym_dead_mans_bomb(bomber)

/datum/bot_scenario/bomber_crew/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (get_dist(bot, bomber) >= 8 && bot_transcript_said("has a bomb in their hands")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/bomber_officer
	name = "bomb: an officer with no gun, after somebody holding a tank bomb, holds off rather than walking up to cuff them"
	desc = "Somebody wanted for Assault with a Deadly Weapon is holding a tank bomb. The officer has cuffs and nothing to shoot with. It calls it in and keeps five tiles or more off. It used to walk up and go for the cuffs."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	time_limit = 15 SECONDS
	layout = list(
		"##############",
		"#B.........M.#",
		"##############")
	var/mob/living/carbon/human/bomber
	var/closest = 99

/datum/bot_scenario/bomber_officer/make_goal()
	return null

/datum/bot_scenario/bomber_officer/post_spawn()
	brain.register_security()
	bomber = stand_in(first_marker("M"), "Bo Bomber")
	bot_gym_tank_bomb(get_turf(bomber))
	var/obj/item/transfer_valve/V = locate() in get_turf(bomber)
	bomber.put_in_hands(V)
	brain.file_crime(bomber, "Assault with a Deadly Weapon", "Gym.", BOT_CRIME_MAJOR)
	brain.begin_arrest(bomber)

/datum/bot_scenario/bomber_officer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	closest = min(closest, get_dist(bot, bomber))
	if(closest < 4)
		fail_reason = "came within [closest] tiles of them"
		return BOT_GYM_FAIL
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	if(!bot_transcript_said("has a bomb in their hands"))
		fail_reason = "never said they had a bomb"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/bomber_officer/release_run()
	GLOB.bot_security_wanted -= WEAKREF(bomber)
	return ..()
