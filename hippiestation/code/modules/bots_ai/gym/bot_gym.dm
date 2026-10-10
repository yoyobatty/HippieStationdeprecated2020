// Bot Gym - headless scenario runner for the bot AI.
//
// Each /datum/bot_scenario builds a small sealed arena from an ASCII layout in reserved space
// (away from the station), spawns a scripted bot with an exact kit, gives it a goal, and judges
// the outcome. Every scenario runs at once, each in its own arena, so the whole suite takes about
// as long as the slowest scenario.
//
// Run it:   tools/bot_gym/run_bot_gym.sh [name filter] [runs per scenario]
// or boot:  DreamDaemon hippiestation.dmb -params "bot-gym=all&bot-gym-runs=1"
//           add &timewarp=0 to fast-forward it (admin/timewarp.dm) - the script does
// Results:  data/bot_gym/summary.txt, results.json, and a transcript per run in transcripts/.
//
// For bots left to work a whole shift on the real station, see bot_shift.dm.
//
// Scripted bots don't wander, chat or pick up jobs of their own (see gym_scripted in
// bot_brain.dm) - they only pursue the goal the scenario gives them, re-issued if they give up.

#define BOT_GYM_PENDING 0
#define BOT_GYM_PASS 1
#define BOT_GYM_FAIL 2
/// Empty space kept around each arena so view()- and range()-based searches can't reach into a neighbour: with
/// each arena walled, two arenas' floors are never nearer than 2 * margin + 3 tiles, and nothing a bot does looks
/// further than 7. It was 4 until three passes of every scenario stopped fitting on the one reserved map level.
#define BOT_GYM_MARGIN 3

GLOBAL_VAR_INIT(bot_gym_running, FALSE)

/datum/bot_brain
	/// Scenario this bot belongs to; set only for Bot Gym bots.
	var/datum/bot_scenario/gym_run
	/// Scripted bots do nothing on their own while idle - no wandering, rounds or chatter.
	var/gym_scripted = FALSE

/area/bot_gym
	name = "Bot Gym Arena"
	icon_state = "yellow"
	requires_power = FALSE //machinery (airlocks) always powered
	has_gravity = STANDARD_GRAVITY
	dynamic_lighting = DYNAMIC_LIGHTING_DISABLED

/datum/outfit/bot_gym
	name = "Bot Gym"
	uniform = /obj/item/clothing/under/color/grey
	shoes = /obj/item/clothing/shoes/sneakers/black
	back = /obj/item/storage/backpack

/datum/bot_scenario
	var/name = "unnamed"
	var/desc = ""
	/// Rows top to bottom. Legend in build_tile().
	var/list/layout
	/// Item types put in the bot's hands (up to 2) and backpack.
	var/list/kit_hands
	var/list/kit_backpack
	/// Forced urgency for the whole run (-1 = the bot's real perception).
	var/urgency_override = -1
	/// Job title for the bot (mind.assigned_role) - job-specific behaviour keys off it.
	var/job
	var/time_limit = 60 SECONDS
	/// Times the goal is re-issued after the bot gives up, like a real bot trying again.
	var/max_goal_attempts = 3
	/// FALSE for scenarios describing behavior not built yet - reported as XFAIL/XPASS, not failures.
	var/expect_success = TRUE
	/// Telemetry tells (bot_telemetry.dm) that fail a run even if the goal succeeded: reaching the
	/// goal isn't enough, it has to look like a person did it.
	var/list/forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target")

	// --- runtime state ---
	var/run_index = 1
	var/datum/turf_reservation/reservation
	var/area/bot_gym/arena_area
	/// Layout character -> list of turfs with it.
	var/list/markers = list()
	/// Layout character -> list of objects placed for it.
	var/list/placed = list()
	var/mob/living/carbon/human/bot
	var/datum/bot_brain/brain
	var/goal_attempts = 0
	var/result = BOT_GYM_PENDING
	var/fail_reason
	var/start_time
	var/end_time
	var/list/transcript = list()

// ---------------------------------------------------------------------------------------------
// Hooks for scenarios
// ---------------------------------------------------------------------------------------------

/// Extra setup after the arena is built and before the bot spawns (fill lockers, etc).
/datum/bot_scenario/proc/setup()
	return

/// Called right after the bot spawns, before its goal (dress it, give it an ID...).
/datum/bot_scenario/proc/post_spawn()
	return

/// The goal to give the bot. Default: walk to the G marker.
/datum/bot_scenario/proc/make_goal()
	var/datum/bot_goal/gym_reach/G = new
	G.target = first_marker("G")
	return G

/// Called every second. Return BOT_GYM_PASS/FAIL (setting fail_reason) or BOT_GYM_PENDING.
/datum/bot_scenario/proc/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(get_turf(bot) == first_marker("G"))
		var/problem = check_success_conditions()
		if(problem)
			fail_reason = problem
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// Extra conditions a success must also meet ("no windows broken"). Return a reason or null.
/datum/bot_scenario/proc/check_success_conditions()
	return null

/// Called when time runs out. Some scenarios pass by NOT doing something.
/datum/bot_scenario/proc/on_timeout()
	fail_reason = "timed out after [time_limit / 10]s"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// Helpers for scenarios
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/proc/first_marker(char)
	var/list/L = markers[char]
	return length(L) ? L[1] : null

/datum/bot_scenario/proc/first_placed(char)
	var/list/L = placed[char]
	return length(L) ? L[1] : null

/// True if an object placed for this layout character was destroyed or broken open.
/datum/bot_scenario/proc/placed_destroyed(char)
	for(var/obj/O in placed[char])
		if(QDELETED(O) || !O.density)
			return TRUE
	return FALSE

/datum/bot_scenario/proc/log_line(msg)
	transcript += "[(world.time - start_time) / 10]s: [msg]"

// ---------------------------------------------------------------------------------------------
// Arena building
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/proc/build()
	var/height = length(layout)
	var/width = 0
	for(var/row in layout)
		width = max(width, length(row))
	reservation = SSmapping.RequestBlockReservation(width + BOT_GYM_MARGIN * 2, height + BOT_GYM_MARGIN * 2)
	if(!reservation)
		fail_reason = "couldn't reserve [width]x[height] of space"
		return FALSE
	arena_area = new
	var/list/arena_turfs = list()
	var/list/floors = list()
	var/x0 = reservation.bottom_left_coords[1] + BOT_GYM_MARGIN
	var/y0 = reservation.bottom_left_coords[2] + BOT_GYM_MARGIN
	var/z = reservation.bottom_left_coords[3]
	// Pass 1: turfs and area. Rows are top-down, so the first row is the highest y.
	for(var/row_index in 1 to height)
		var/row = layout[row_index]
		for(var/col in 1 to length(row))
			var/char = copytext(row, col, col + 1)
			if(char == " ")
				continue //outside the arena - stays reserved space
			var/turf/T = locate(x0 + col - 1, y0 + height - row_index, z)
			var/area/old_area = T.loc
			old_area.contents -= T
			arena_area.contents += T
			T.change_area(old_area, arena_area)
			if(char == "#")
				T.ChangeTurf(/turf/closed/indestructible/riveted, flags = CHANGETURF_IGNORE_AIR)
			else if(char == "S")
				T.ChangeTurf(/turf/open/space/basic, flags = CHANGETURF_IGNORE_AIR)
			else
				var/floor_type = (char in list("=", "~", "x", "P")) ? /turf/open/floor/plating : /turf/open/floor/plasteel
				T = T.ChangeTurf(floor_type, flags = CHANGETURF_IGNORE_AIR)
				floors += T
			arena_turfs[T] = char
			LAZYADD(markers[char], T)
	// Pass 2: air. Space changed into floor starts near-vacuum, which reads as a panic-level
	// hazard to the bot - give every floor tile normal station air now that the walls are up.
	for(var/turf/open/F in floors)
		F.air.parse_gas_string(arena_turfs[F] == "v" ? "TEMP=2.7" : OPENTURF_DEFAULT_ATMOS) //v = airless floor
		F.update_visuals()
		SSair.add_to_active(F)
	// Pass 3: objects.
	for(var/turf/T in arena_turfs)
		build_tile(T, arena_turfs[T])
	return TRUE

/// Legend:
///  # wall   . floor   v airless floor   S space   B bot start   G goal
///  W grille + window   w window   g grille   D airlock   X welded airlock
///  F closed firelock   f welded firelock   T toolbox   E extinguisher cabinet
///  L locker   V vending machine   t table   c crowbar   r wirecutters
///  P plating   = plating + cable (yellow layer)   ~ plating + cable (red layer)
///  x plating + a chewed-off bit of cable (a gap)   m a mouse that stays put
/datum/bot_scenario/proc/build_tile(turf/T, char)
	switch(char)
		if("W")
			place(char, new /obj/structure/grille(T))
			place(char, new /obj/structure/window/fulltile(T))
		if("w")
			place(char, new /obj/structure/window/fulltile(T))
		if("g")
			place(char, new /obj/structure/grille(T))
		if("D")
			place(char, new /obj/machinery/door/airlock(T))
		if("X")
			var/obj/machinery/door/airlock/A = new(T)
			A.welded = TRUE
			A.update_icon()
			place(char, A)
		if("F", "f")
			var/obj/machinery/door/firedoor/F = new(T)
			INVOKE_ASYNC(F, TYPE_PROC_REF(/obj/machinery/door, close))
			if(char == "f")
				F.welded = TRUE
			place(char, F)
		if("T")
			place(char, new /obj/item/storage/toolbox/mechanical(T))
		if("E")
			place(char, new /obj/structure/extinguisher_cabinet(T))
		if("L")
			place(char, new /obj/structure/closet(T))
		if("V")
			place(char, new /obj/machinery/vending/cola(T))
		if("t")
			place(char, new /obj/structure/table(T))
		if("c")
			place(char, new /obj/item/crowbar(T))
		if("r")
			place(char, new /obj/item/wirecutters(T))
		if("=")
			place(char, new /obj/structure/cable(T))
		if("~")
			place(char, new /obj/structure/cable/layer1(T))
		if("x")
			place(char, new /obj/item/stack/cable_coil(T, 1))
		if("m")
			var/mob/living/simple_animal/mouse/M = new(T)
			M.stop_automated_movement = TRUE
			M.wander = FALSE
			M.chew_probability = 0
			place(char, M)

/datum/bot_scenario/proc/place(char, obj/O)
	LAZYADD(placed[char], O)
	return O

// ---------------------------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/proc/spawn_bot()
	var/turf/start = first_marker("B")
	if(!start)
		fail_reason = "layout has no B (bot start)"
		return FALSE
	bot = new(start)
	bot.real_name = "Gym [name] #[run_index]"
	bot.name = bot.real_name
	bot.equipOutfit(/datum/outfit/bot_gym)
	bot.mind_initialize()
	if(job)
		bot.mind.assigned_role = job
	for(var/path in kit_hands)
		bot.put_in_hands(new path(bot))
	for(var/path in kit_backpack)
		bot.equip_to_slot_or_del(new path(bot), ITEM_SLOT_BACKPACK)
	brain = new(bot)
	brain.gym_run = src
	brain.gym_scripted = TRUE
	brain.urgency_override = urgency_override
	// An even temperament every run (bot_personality.dm rolls one), so runs compare - post_spawn() can set its own.
	brain.diligence = 1
	brain.sociability = 0.5
	brain.nerve = 0.5
	post_spawn()
	return TRUE

/// Builds the arena. The runner does these one at a time before anything starts - see run_bot_gym().
/datum/bot_scenario/proc/prepare()
	start_time = world.time
	log_line("building arena")
	if(!build())
		result = BOT_GYM_FAIL
		return
	log_line("arena built at [bot_coord(first_marker("B"))]")

/datum/bot_scenario/proc/start()
	if(result != BOT_GYM_PENDING)
		return //no arena
	start_time = world.time
	setup()
	sleep(2 SECONDS) //let doors finish closing and air settle before the clock starts
	start_time = world.time
	if(!spawn_bot())
		result = BOT_GYM_FAIL
		return
	log_line("bot spawned: [english_list(bot.held_items)] in hands, urgency [bot_urgency_name(brain.get_urgency())]")
	issue_goal()

/datum/bot_scenario/proc/issue_goal()
	goal_attempts++
	var/datum/bot_goal/G = make_goal()
	if(!G)
		log_line("nothing left to issue as a goal (attempt [goal_attempts]/[max_goal_attempts])") //e.g. the stranded tank is already back on the bot
		return
	log_line("issuing goal [G.type] (attempt [goal_attempts]/[max_goal_attempts])")
	if(!brain.assign_goal(G))
		log_line("assign_goal refused")

/// One tick of judging; also re-issues the goal if the bot gave up.
/datum/bot_scenario/proc/tick()
	if(result != BOT_GYM_PENDING)
		return
	result = check()
	if(result == BOT_GYM_PENDING && world.time > start_time + time_limit)
		result = on_timeout()
	if(result == BOT_GYM_PASS)
		var/tells = robotic_tells()
		if(tells)
			result = BOT_GYM_FAIL
			fail_reason = "succeeded but looked robotic: [tells]"
	if(result != BOT_GYM_PENDING)
		end_time = world.time
		release_run()
		return
	if(brain && brain.state == BOT_STATE_WANDER && !brain.current_goal && goal_attempts < max_goal_attempts)
		issue_goal()

/// The forbidden tells this run showed, as text, or null.
/datum/bot_scenario/proc/robotic_tells()
	if(!brain)
		return null
	var/list/found = list()
	for(var/tell in forbidden_tells)
		if(LAZYACCESS(brain.telemetry_flags, tell))
			found += "[tell] x[brain.telemetry_flags[tell]]"
	return length(found) ? jointext(found, ", ") : null

/// Scenario datums live until every run has finished (the report is written at the end), but a judged run
/// only needs its text and brain. Letting go of its other atoms (arena objects, a scenario's own mouse or
/// assailant) lets anything the bot destroyed be garbage collected - held here, every one was hard-deleted.
/// The bot stays: start() may still be using it, and gym bots are never deleted.
/datum/bot_scenario/proc/release_run()
	for(var/varname in vars)
		if(varname != "bot" && isatom(vars[varname]))
			vars[varname] = null
	markers = list()
	placed = list()

/// Robotic tells recorded by telemetry (bot_telemetry.dm) during the run, e.g. " [tool_not_in_hand=2]".
/datum/bot_scenario/proc/believability_text()
	if(!brain || !length(brain.telemetry_flags))
		return ""
	var/list/parts = list()
	for(var/flag in brain.telemetry_flags)
		parts += "[flag]=[brain.telemetry_flags[flag]]"
	return "   \[[jointext(parts, " ")]\]"

/datum/bot_scenario/proc/outcome_text()
	switch(result)
		if(BOT_GYM_PASS)
			return expect_success ? "PASS" : "XPASS"
		if(BOT_GYM_FAIL)
			return expect_success ? "FAIL" : "XFAIL"
	return "PENDING"

// ---------------------------------------------------------------------------------------------
// The runner
// ---------------------------------------------------------------------------------------------

/// Runs every scenario (optionally filtered by name substring), writes results, then shuts down.
/proc/run_bot_gym(filter, runs = 1)
	GLOB.bot_gym_running = TRUE
	// Headless: nobody is connected, and with sleep_offline on the world pauses - every sleeping
	// proc (this runner, the bots, their timers) would wait forever.
	Master.sleep_offline_after_initializations = FALSE
	world.sleep_offline = FALSE
	runs = clamp(text2num("[runs]") || 1, 1, 50)
	// Bot brains (SSprocessing) and machines (SSmachines: trays, vendors) only fire once a round is
	// under way - RUNLEVELS_DEFAULT leaves out the lobby. Waiting out the lobby countdown froze
	// every bot's own ticking and every machine for the first ~110s of the run.
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	log_world("BOT GYM: round state [SSticker.current_state], starting scenarios")
	var/list/datum/bot_scenario/active = list()
	for(var/path in subtypesof(/datum/bot_scenario))
		var/datum/bot_scenario/probe = new path
		if(!probe.layout || (filter && filter != "all" && !findtext(probe.name, filter)))
			continue
		for(var/i in 1 to runs)
			var/datum/bot_scenario/S = (i == 1) ? probe : new path
			S.run_index = i
			active += S
	log_world("BOT GYM: running [length(active)] scenario run(s)")
	// Arenas are built one after another, and only then does everything start at once. Asking for all the map space
	// in the same tick had a hundred reservation searches (turf_reservation/Reserve(), a slow first-fit scan that
	// yields on a busy tick) competing: stoplag() doubles its wait each time it wakes to a busy tick, so the
	// unlucky ones backed off for minutes and whole scenarios never got an arena before the deadline - on a server
	// that was by then sitting idle. Roughly one three-pass run in six lost anything from 1 to 28 scenarios.
	var/build_started = world.time
	for(var/datum/bot_scenario/S in active)
		S.prepare()
	log_world("BOT GYM: [length(active)] arena\s built in [(world.time - build_started) / 10]s")
	// A few per tick rather than all in the same one: a hundred bots asking for their first route in the same instant
	// queue for the pathfinder's slots (get_path_to()), and the ones at the back stood for four seconds before
	// taking a step - which the human-pace scenarios rightly fail.
	var/started = 0
	for(var/datum/bot_scenario/S in active)
		INVOKE_ASYNC(S, TYPE_PROC_REF(/datum/bot_scenario, start))
		if(!(++started % 4))
			sleep(world.tick_lag)
	var/deadline = world.time + 10 MINUTES
	var/list/load = list("seconds" = 0, "sum" = 0, "peak" = 0, "over" = 0)
	while(world.time < deadline)
		sleep(1 SECONDS)
		bot_gym_sample_load(load)
		var/pending = 0
		for(var/datum/bot_scenario/S in active)
			if(S.brain) //judge only once the bot exists (arena build + settle take a few seconds)
				S.tick()
			if(S.result == BOT_GYM_PENDING)
				pending++
		if(!pending)
			break
	write_bot_gym_results(active, load)
	log_world("BOT GYM: done")
	Master.Shutdown()
	qdel(world)

/// world.cpu is the share of a tick the server needed. Over 100 it can't keep up, and everything -
/// bots included - runs slow in game time, whether the run is fast-forwarded (admin/timewarp.dm) or not.
/proc/bot_gym_sample_load(list/load)
	load["seconds"]++
	load["sum"] += world.cpu
	load["peak"] = max(load["peak"], world.cpu)
	if(world.cpu > 100)
		load["over"]++

/proc/bot_gym_load_text(list/load)
	. = "Server load averaged [round(load["sum"] / max(load["seconds"], 1))]% of a tick, peak [round(load["peak"])]%, [load["over"]] of [load["seconds"]] seconds over 100%."
	if(load["over"] > load["seconds"] * 0.1)
		. += " The server couldn't keep up, so bots ran slow in game time - timeouts and idle tells in this run may not be their doing."

/proc/write_bot_gym_results(list/datum/bot_scenario/active, list/load)
	var/dir = "data/bot_gym/"
	fdel(dir)
	var/list/json = list()
	var/list/counts = list("PASS" = 0, "FAIL" = 0, "XFAIL" = 0, "XPASS" = 0, "PENDING" = 0)
	var/list/lines = list()
	// A colon in a file name is an NTFS stream, not a file: "locker: take the gloves..." wrote its transcript into a stream of an empty file called "locker".
	var/static/regex/not_for_filenames = regex(@'[\\/:*?"<>|]', "g")
	for(var/datum/bot_scenario/S in active)
		var/outcome = S.outcome_text()
		counts[outcome]++
		var/seconds = S.end_time ? round((S.end_time - S.start_time) / 10, 0.1) : null
		var/label = "[S.name][S.run_index > 1 ? " #[S.run_index]" : ""]"
		lines += "[pad_bot_gym(outcome, 7)][pad_bot_gym(label, 54)][seconds != null ? "[seconds]s" : ""][S.fail_reason ? "   [S.fail_reason]" : ""][S.believability_text()]"
		json += list(list("name" = S.name, "run" = S.run_index, "outcome" = outcome, "seconds" = seconds, "reason" = S.fail_reason, "desc" = S.desc))
		text2file(jointext(S.transcript, "\n"), "[dir]transcripts/[not_for_filenames.Replace(replacetext(S.name, " ", "_"), "")]_[S.run_index].log")
	var/header = "BOT GYM  [counts["PASS"]] passed, [counts["FAIL"]] failed, [counts["XFAIL"]] expected failures, [counts["XPASS"]] unexpected passes[counts["PENDING"] ? ", [counts["PENDING"]] unfinished" : ""]"
	if(load)
		header += "\n[bot_gym_load_text(load)]"
	// When the reserved map level fills up, the rest of the arenas go on a new one made on the spot - which the
	// spatial grid and the air never finish setting up, and bots on it fail for reasons that aren't theirs.
	var/list/levels = list()
	for(var/datum/bot_scenario/S in active)
		if(S.reservation)
			levels["[S.reservation.bottom_left_coords[3]]"]++
	if(length(levels) > 1)
		var/main_level
		for(var/level in levels)
			if(!main_level || levels[level] > levels[main_level])
				main_level = level
		header += "\nWARNING: [length(active) - levels[main_level]] of [length(active)] arenas didn't fit on the reserved map level and were built on an extra one, where results can't be trusted. Run fewer passes at once."
	var/summary = "[header]\n\n[jointext(lines, "\n")]\nFAILED: [counts["FAIL"] + counts["PENDING"]]\n"
	text2file(summary, "[dir]summary.txt")
	text2file(json_encode(json), "[dir]results.json")
	log_world(summary)

/proc/pad_bot_gym(text, width)
	. = "[text]"
	while(length(.) < width)
		. += " "

// ---------------------------------------------------------------------------------------------
// The default goal: walk to a turf
// ---------------------------------------------------------------------------------------------

/// target preset by the scenario.
/datum/bot_goal/gym_reach

/datum/bot_goal/gym_reach/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/gym_walk())

/datum/bot_strategy/gym_walk/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to())

/datum/bot_strategy/gym_walk/is_feasible(datum/bot_brain/bot)
	return TRUE
