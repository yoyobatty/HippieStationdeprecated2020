// Toxins: a tank transfer valve bomb, for the research points, the way the user makes one (2026-11-05): the burn chamber, the plasma
// filtered out of it hot, and oxygen off the freezer. Measured first on the station's own chamber (gym/ttv_bench.dm BENCH=chamber_burn),
// which reaches the server's cap, radius 20, on the Hippie, Box and Meta maps alike:
//
//  - The freezer on and the oxygen canister on its port, early: it takes its time.
//  - A plasma tank and an oxygen tank from the dispenser, the plasma tank scrubbed out first in a portable scrubber, so it holds only
//    what comes out of the chamber.
//  - The chamber's scrubber off at its air alarm (as mapped it scrubs CO2 into the output line, which would be the first thing in the
//    tank), and the portable pump on the output port.
//  - Plasma in through the inlet port, then oxygen to half as much again: 2 to 1. The inlet valve's shut before each canister comes off,
//    or what's still in the line behind it goes on in after.
//  - The ignition switch, and stood by while it burns to 3,000 K. Hotter isn't better here: a tank at the same pressure holds a tenth
//    as much plasma at 30,000 K, and the chamber's down to a fifth plasma by then (radius 17 against 20).
//  - The scrubber on plasma only, the output line open, and the pump filling the emptied tank to 2,500 kPa: pure plasma at about
//    3,000 K. A canister only lets out 1,013 kPa, and filled from one the tank never gets past radius 4 on this server.
//  - The oxygen tank from the cold canister. 73 K is as good as it gets: a full canister colder than that is under 1,013 kPa, so the tank
//    takes no more oxygen however cold it is.
//  - The tanks on a valve with a timer, the valve on the mass driver, and the button: it goes off out past the test range, where the
//    doppler array can see it.
//
// A traitor who gets this far fits a health sensor instead and keeps it in the bag: if they go down, everybody round them goes with them.
//
// The old way, before the user's: a lean mix through the Hippie map's three-port mixers, lit on the heater and burned out in its canister,
// radius 11-12 and on that one map only, since the canister burn stays a fifth burned gas.

/// How long into the round before anybody starts on this.
#define BOT_TOXINS_SETTLE_IN (5 MINUTES)
/// The chamber's plasma, by its pressure: a full canister gives about 190 kPa. Oxygen goes in to half as much again.
#define BOT_TOXINS_PLASMA_KPA 150
#define BOT_TOXINS_OXYGEN_SHARE 0.5
/// The chamber's heat when the plasma's pulled, and how long it's given to get there.
#define BOT_TOXINS_PULL_AT 3000
#define BOT_TOXINS_BURN_LIMIT (5 MINUTES)
/// What the hot tank wants, and what the cold one wants.
#define BOT_TOXINS_HOT_KPA 2450
#define BOT_TOXINS_COLD_KPA 950
/// What the freezer's set to: on the bench, oxygen at 73 K did best; colder, the canister's pressure falls and the tank gets no more
#define BOT_TOXINS_FREEZER_SET 75
/// How long the freezer's given, and how cold will do.
#define BOT_TOXINS_CHILL_LIMIT (5 MINUTES)
#define BOT_TOXINS_COLD_ENOUGH 85
/// Timer on the valve, from when it's set down on the driver.
#define BOT_TOXINS_FUSE 20
/// How many times one stage can fail before the lab's left alone for a while.
#define BOT_TOXINS_TRIES 3

GLOBAL_DATUM(bot_toxins, /datum/bot_toxins)

/datum/bot_brain
	/// Bombs this bot has launched.
	var/bombs_launched = 0
	/// The bomb a traitor is carrying about, to be picked back up if it's put down.
	var/obj/item/transfer_valve/armed_bomb

/// The bomb in progress: all of it is out on the lab floor, so whichever scientist comes along picks up where the last one left off.
/datum/bot_toxins
	var/stage = 1
	var/stage_failures = 0
	var/rest_until = 0
	// The burn chamber: what goes in, what comes out, and what works it
	var/obj/machinery/atmospherics/components/unary/outlet_injector/injector
	var/obj/machinery/atmospherics/components/unary/portables_connector/inlet_port
	var/obj/machinery/atmospherics/components/binary/valve/inlet_valve
	var/obj/machinery/atmospherics/components/binary/pump/inlet_pump
	var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber
	var/obj/machinery/atmospherics/components/unary/portables_connector/outlet_port
	var/obj/machinery/atmospherics/components/binary/valve/outlet_valve
	var/obj/machinery/atmospherics/components/binary/pump/outlet_pump
	var/obj/machinery/airalarm/chamber_alarm
	var/obj/machinery/button/ignition/ignition
	var/obj/machinery/button/door/vent_button
	/// The chamber's pressure once the plasma's in, which the oxygen goes on top of
	var/plasma_in_kpa = 0
	var/obj/machinery/atmospherics/components/unary/portables_connector/freezer_port
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer
	var/obj/machinery/portable_atmospherics/canister/plasma_can
	/// The cold one, for the tank, and the one that goes in the chamber
	var/obj/machinery/portable_atmospherics/canister/oxygen_can
	var/obj/machinery/portable_atmospherics/canister/burn_oxygen_can
	var/obj/machinery/portable_atmospherics/pump/pump
	/// What the plasma tank's scrubbed out in
	var/obj/machinery/portable_atmospherics/scrubber/tank_scrubber
	var/obj/item/tank/hot_tank
	var/obj/item/tank/cold_tank
	var/obj/item/transfer_valve/valve
	var/chill_started = 0
	var/finished = FALSE
	/// Everything found and walkable to; FALSE till then
	var/found = FALSE
	/// The last look found it all there, but not all of it somewhere that bot could get to
	var/unreachable = FALSE
	/// Who's on it, as a weakref.
	var/datum/weakref/worker
	/// When forget_deleted() next runs
	var/next_forget_time = 0

/// The line behind one of the chamber's devices, out to its port: list(port, valve, pump), any of them null where it hasn't one
/proc/bot_chamber_line(obj/machinery/atmospherics/components/unary/U)
	var/list/line = list(null, null, null)
	var/list/frontier = list(U)
	var/list/seen = list()
	while(length(frontier))
		var/obj/machinery/atmospherics/components/A = frontier[1]
		frontier.Cut(1, 2)
		if(A in seen)
			continue
		seen += A
		for(var/datum/pipeline/P in A.parents)
			for(var/obj/machinery/atmospherics/components/C in P.other_atmosmch)
				if(istype(C, /obj/machinery/atmospherics/components/unary/portables_connector) && !line[1])
					line[1] = C
				else if(istype(C, /obj/machinery/atmospherics/components/binary/valve) && !line[2])
					line[2] = C
					frontier += C
				else if(istype(C, /obj/machinery/atmospherics/components/binary/pump) && !line[3])
					line[3] = C
					frontier += C
	return line

/proc/bot_lab_thermomachine_port(obj/machinery/atmospherics/components/unary/thermomachine/M)
	var/obj/machinery/atmospherics/components/unary/portables_connector/C = M.nodes[1]
	if(istype(C))
		return C
	var/datum/pipeline/P = M.parents[1]
	if(P)
		for(var/obj/machinery/atmospherics/components/unary/portables_connector/found in P.other_atmosmch)
			return found
	return null

/datum/bot_toxins/New()
	. = ..()
	START_PROCESSING(SSprocessing, src)

/datum/bot_toxins/process()
	if(world.time >= next_forget_time)
		forget_deleted()

/// A bomb that's gone off is still held here, tanks and all, and a blast through the lab leaves the freezer, the pump, the canisters
/// and the ports: each one held was a hard delete. Runs once a minute on its own (above), and from any bot's forget_deleted()
/// (bot_brain.dm): a blast that killed every scientist left nobody to call it.
/datum/bot_toxins/proc/forget_deleted()
	next_forget_time = world.time + 1 MINUTES
	for(var/name in vars)
		var/datum/thing = vars[name]
		if(istype(thing) && QDELETED(thing))
			vars[name] = null

/// Everything a bomb takes, found where it's kept. FALSE if this station hasn't got it.
/datum/bot_toxins/proc/find_lab(datum/bot_brain/bot)
	unreachable = FALSE
	for(var/obj/machinery/M in GLOB.machines)
		if(!istype(get_area(M), /area/science/mixing/chamber))
			continue
		if(istype(M, /obj/machinery/atmospherics/components/unary/outlet_injector))
			injector = M
		else if(istype(M, /obj/machinery/atmospherics/components/unary/vent_scrubber))
			scrubber = M
		else if(istype(M, /obj/machinery/airalarm))
			chamber_alarm = M
	if(!injector || !scrubber || !chamber_alarm)
		log_game("BOT TOXINS: no burn chamber here (injector [injector], scrubber [scrubber], air alarm [chamber_alarm])")
		return FALSE
	var/list/line = bot_chamber_line(injector)
	inlet_port = line[1]
	inlet_valve = line[2]
	inlet_pump = line[3]
	line = bot_chamber_line(scrubber)
	outlet_port = line[1]
	outlet_valve = line[2]
	outlet_pump = line[3]
	if(!inlet_port || !inlet_valve || !outlet_port || !outlet_valve)
		log_game("BOT TOXINS: the chamber's lines don't run to ports (inlet [inlet_port]/[inlet_valve], outlet [outlet_port]/[outlet_valve])")
		return FALSE
	for(var/obj/machinery/button/B as anything in bot_instances_of(/obj/machinery/button))
		if(!istype(get_area(B), /area/science) || !findtext("[B.id]", "toxmix"))
			continue
		if(istype(B, /obj/machinery/button/ignition))
			ignition = B
		else if(istype(B, /obj/machinery/button/door))
			vent_button = B
	if(!ignition)
		log_game("BOT TOXINS: no ignition switch for the chamber")
		return FALSE
	for(var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/F as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/thermomachine/freezer))
		if(istype(get_area(F), /area/science/mixing) && bot_lab_thermomachine_port(F))
			freezer = F
			freezer_port = bot_lab_thermomachine_port(F)
	if(!freezer_port)
		log_game("BOT TOXINS: no freezer with a port in the lab")
		return FALSE
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(!istype(get_area(C), /area/science) || C.connected_port || C.stat & BROKEN)
			continue
		var/pressure = C.air_contents.return_pressure()
		if(!plasma_can && istype(C, /obj/machinery/portable_atmospherics/canister/toxins) && pressure > 2000 && bot.can_walk_lawfully_to(C))
			plasma_can = C
		else if(istype(C, /obj/machinery/portable_atmospherics/canister/oxygen) && pressure > 2000 && bot.can_walk_lawfully_to(C))
			if(!oxygen_can)
				oxygen_can = C
			else if(!burn_oxygen_can)
				burn_oxygen_can = C
	for(var/obj/machinery/portable_atmospherics/P as anything in bot_instances_of(/obj/machinery/portable_atmospherics))
		if(!istype(get_area(P), /area/science/mixing) || P.connected_port || !bot.can_walk_lawfully_to(P))
			continue
		if(!pump && istype(P, /obj/machinery/portable_atmospherics/pump))
			pump = P
		else if(!tank_scrubber && P.type == /obj/machinery/portable_atmospherics/scrubber)
			tank_scrubber = P
	if(plasma_can && oxygen_can && burn_oxygen_can && pump && tank_scrubber)
		return TRUE
	log_game("BOT TOXINS: the lab has no [english_list(list(plasma_can ? null : "plasma canister", oxygen_can ? null : "oxygen canister", burn_oxygen_can ? null : "second oxygen canister", pump ? null : "portable pump", tank_scrubber ? null : "portable scrubber") - null)] [bot.owner.real_name] can get to now")
	unreachable = TRUE //the lab's there: another time, or somebody else
	return FALSE

/// Somebody else taking over: the tanks are where the last one left them, and if that's on them (down, cuffed, gone), this one starts again
/// from fresh tanks, with full canisters for any that were spent and the chamber vented. Picking up after somebody used to fail the cold
/// tank's stage nine times over, with both tanks still on the scientist who'd started.
/datum/bot_toxins/proc/handover(datum/bot_brain/bot)
	var/lost = FALSE
	for(var/obj/item/tank/T in list(hot_tank, cold_tank))
		if(!QDELETED(T) && !isturf(T.loc) && !istype(T.loc, /obj/machinery/portable_atmospherics) && !(T in bot.owner.GetAllContents()))
			lost = TRUE
	if(!lost || stage <= 4) //stage 4 takes the tanks from the dispenser
		return
	bot_log(bot, "TOXINS: the tanks are on whoever had this before, starting again from fresh ones")
	hot_tank = null
	cold_tank = null
	stage = 4
	stage_failures = 0
	plasma_in_kpa = 0
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(!istype(get_area(C), /area/science) || C.connected_port || (C.stat & BROKEN) || C.air_contents.return_pressure() < 2000 || C == oxygen_can)
			continue
		if(istype(C, /obj/machinery/portable_atmospherics/canister/toxins) && plasma_can?.air_contents.return_pressure() < 2000)
			plasma_can = C
		else if(istype(C, /obj/machinery/portable_atmospherics/canister/oxygen) && burn_oxygen_can?.air_contents.return_pressure() < 2000)
			burn_oxygen_can = C

/// Onto a port, or first whatever's stood on it out of the way: Meta's inlet port has an empty canister on it from the start
/datum/bot_toxins/proc/place_on(obj/machinery/portable_atmospherics/P, obj/machinery/atmospherics/components/unary/portables_connector/port)
	for(var/obj/machinery/portable_atmospherics/other in get_turf(port))
		if(other != P)
			return new /datum/bot_goal/toxins/clear_port/blocker(src, other)
	return new /datum/bot_goal/toxins/place(src, P, port)

/// What's in the chamber now, as its air alarm reads it
/datum/bot_toxins/proc/chamber_air()
	var/turf/T = get_turf(injector)
	return T?.return_air()

/datum/bot_toxins/proc/advance(datum/bot_brain/bot)
	bot_log(bot, "TOXINS: stage [stage] done")
	stage++
	stage_failures = 0

/datum/bot_toxins/proc/failed(datum/bot_brain/bot)
	stage_failures++
	bot_log(bot, "TOXINS: stage [stage] failed ([stage_failures]/[BOT_TOXINS_TRIES])")
	if(stage_failures >= BOT_TOXINS_TRIES)
		stage_failures = 0
		rest_until = world.time + 5 MINUTES

/// The next thing that wants doing, as a goal, or null if there's nothing to do but wait.
/datum/bot_toxins/proc/next_goal(datum/bot_brain/bot)
	switch(stage)
		if(1)
			return new /datum/bot_goal/toxins/kit(src) //first: the valves are on a rack the canisters end up stood in front of
		if(2)
			return new /datum/bot_goal/toxins/at_machine(src, freezer, new /datum/bot_step/paced/toxins/start_freezer(src))
		if(3)
			return place_on(oxygen_can, freezer_port)
		if(4)
			return new /datum/bot_goal/toxins/get_tanks(src)
		if(5)
			return new /datum/bot_goal/toxins/at_machine(src, tank_scrubber, new /datum/bot_step/paced/toxins/scrub_tank(src, FALSE))
		if(6)
			return new /datum/bot_goal/toxins/at_machine(src, tank_scrubber, new /datum/bot_step/paced/toxins/scrub_tank(src, TRUE))
		if(7)
			return new /datum/bot_goal/toxins/at_machine(src, chamber_alarm, new /datum/bot_step/paced/toxins/scrubber_off(src))
		if(8)
			var/datum/gas_mixture/air = chamber_air()
			if(!vent_button || !air || air.return_pressure() < 10) //nothing left in it from before
				advance(bot)
				return next_goal(bot)
			return new /datum/bot_goal/toxins/at_machine(src, vent_button, new /datum/bot_step/paced/toxins/vent_chamber(src))
		if(9)
			return place_on(pump, outlet_port)
		if(10)
			return place_on(plasma_can, inlet_port)
		if(11)
			return new /datum/bot_goal/toxins/at_machine(src, inlet_valve, new /datum/bot_step/paced/toxins/fill_chamber(src, FALSE))
		if(12)
			return new /datum/bot_goal/toxins/clear_port(src, plasma_can)
		if(13)
			return place_on(burn_oxygen_can, inlet_port)
		if(14)
			return new /datum/bot_goal/toxins/at_machine(src, inlet_valve, new /datum/bot_step/paced/toxins/fill_chamber(src, TRUE))
		if(15)
			return new /datum/bot_goal/toxins/at_machine(src, ignition, new /datum/bot_step/paced/toxins/ignite(src))
		if(16)
			return new /datum/bot_goal/toxins/at_machine(src, chamber_alarm, new /datum/bot_step/paced/toxins/scrub_plasma(src))
		if(17)
			return new /datum/bot_goal/toxins/at_machine(src, outlet_valve, new /datum/bot_step/paced/toxins/open_outlet(src))
		if(18)
			return new /datum/bot_goal/toxins/at_machine(src, pump, new /datum/bot_step/paced/toxins/fill_hot(src))
		if(19)
			if(oxygen_can.air_contents.temperature > BOT_TOXINS_COLD_ENOUGH && world.time < chill_started + BOT_TOXINS_CHILL_LIMIT)
				return null
			return new /datum/bot_goal/toxins/at_machine(src, oxygen_can, new /datum/bot_step/paced/toxins/fill_cold(src))
		if(20)
			return new /datum/bot_goal/toxins/assemble(src)
		if(21)
			return new /datum/bot_goal/toxins/launch(src)
	return null

/datum/bot_duty/toxins
	name = "the toxins lab"
	jobs = list("Scientist", "Research Director")
	priority = 25
	interval_min = 60
	interval_max = 150

/datum/bot_duty/toxins/try_start(datum/bot_brain/bot)
	if(!bot.gym_run && world.time < SSticker.round_start_time + BOT_TOXINS_SETTLE_IN)
		return FALSE
	if(!GLOB.bot_toxins)
		GLOB.bot_toxins = new
	var/datum/bot_toxins/lab = GLOB.bot_toxins
	if(!lab.found && !lab.finished && world.time >= lab.rest_until)
		if(lab.find_lab(bot))
			lab.found = TRUE
		else if(lab.unreachable) // A scientist shut in somewhere at the time made it "no lab" for the round, on two maps of three
			lab.rest_until = world.time + 2 MINUTES
		else
			lab.finished = TRUE
			log_game("BOT TOXINS: this station has no lab a bot can work")
	if(!lab.found || lab.finished || world.time < lab.rest_until)
		return FALSE
	// One pair of hands: whoever started has the tanks and knows where it's up to. Somebody else only takes over if they can't go on.
	var/datum/weakref/ref = lab.worker
	var/mob/living/carbon/human/worker = ref?.resolve()
	if(worker && worker != bot.owner && worker.stat == CONSCIOUS && !worker.handcuffed)
		return FALSE
	if(worker != bot.owner)
		lab.handover(bot)
	lab.worker = WEAKREF(bot.owner)
	var/datum/bot_goal/toxins/G = lab.next_goal(bot)
	return G ? bot.assign_goal(G) : FALSE

/datum/bot_goal/toxins
	lawful = TRUE
	exclusive = TRUE
	doing = "working in Toxins"
	var/datum/bot_toxins/lab

/datum/bot_goal/toxins/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_goal/toxins/on_success(datum/bot_brain/bot)
	lab.advance(bot)
	var/datum/bot_duty/toxins/duty = bot_duty_of(/datum/bot_duty/toxins)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/toxins/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	lab.failed(bot)

/datum/bot_strategy/toxins/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Base of the steps that work one thing in the lab.
/datum/bot_step/paced/toxins
	max_clicks = 400
	var/datum/bot_toxins/lab
	var/ends_at = 0
	var/limit = 2 MINUTES
	/// Where it stood to start waiting, and when it next moves about a little.
	var/turf/anchor
	var/next_mill = 0

/datum/bot_step/paced/toxins/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_step/paced/toxins/start(datum/bot_brain/bot)
	ends_at = world.time + limit
	anchor = get_turf(bot.owner)
	next_mill = world.time + rand(15 SECONDS, 30 SECONDS)
	return begin(bot)

/datum/bot_step/paced/toxins/proc/begin(datum/bot_brain/bot)
	return TRUE

/// What it's waiting to see, TRUE when that's happened.
/datum/bot_step/paced/toxins/proc/ready(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/paced/toxins/do_click(datum/bot_brain/bot)
	if(ready(bot) || world.time > ends_at)
		return FALSE
	// A wait of minutes (a burn takes up to eight) isn't spent stood on the one tile: a step or two about the lab now and then, and back.
	// Every shift with a scientist in Toxins had it flagged as frozen, three minutes at a time, by the burn chamber.
	if(world.time >= next_mill && anchor && !bot.owner.buckled && !bot.pursuing_kind)
		next_mill = world.time + rand(15 SECONDS, 30 SECONDS)
		var/list/near = list()
		for(var/turf/open/T in get_adjacent_open_turfs(bot.owner))
			if(get_dist(T, anchor) <= 2 && get_area(T) == get_area(anchor) && !is_blocked_turf(T, TRUE) && !bot_turf_is_deadly(T) && !GLOB.bot_hazard_turfs[T])
				near += T
		if(length(near))
			step_to(bot.owner, pick(near))
	wait_for = 5
	return TRUE

/datum/bot_step/paced/toxins/finish(datum/bot_brain/bot)
	. = ready(bot) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	wrap_up(bot)

/datum/bot_step/paced/toxins/proc/wrap_up(datum/bot_brain/bot)
	return

// ---------------------------------------------------------------------------------------------
// Moving the portables
// ---------------------------------------------------------------------------------------------

/// A canister or a pump from wherever it is to a port, and wrenched on.
/datum/bot_goal/toxins/place
	var/obj/machinery/portable_atmospherics/thing
	var/obj/machinery/atmospherics/components/unary/portables_connector/port

/datum/bot_goal/toxins/place/New(datum/bot_toxins/L, obj/machinery/portable_atmospherics/P, obj/machinery/atmospherics/components/unary/portables_connector/C)
	. = ..()
	thing = P
	port = C

/datum/bot_goal/toxins/place/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(thing) && !QDELETED(port))
		target = thing

/datum/bot_goal/toxins/place/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	var/datum/bot_step/move_to/to_thing = new
	// Lost hold of it in a doorway, it's now stood in the only way to it: it can be got at from the door itself.
	if(!bot.can_walk_lawfully_to(thing))
		for(var/direction in GLOB.cardinals)
			var/turf/T = get_step(thing, direction)
			if(locate(/obj/machinery/door/airlock) in T)
				to_thing.step_target = T
				break
	var/datum/bot_step/move_to/to_port = new
	to_port.step_target = get_turf(port)
	S.steps = list(new /datum/bot_step/ensure_wrench(), to_thing, new /datum/bot_step/free_portable(thing), new /datum/bot_step/grab_portable(thing), to_port, new /datum/bot_step/paced/park_on_port(thing, port), new /datum/bot_step/wrench_canister(thing))
	return list(S)

/datum/bot_step/free_portable
	var/obj/machinery/portable_atmospherics/thing

/datum/bot_step/free_portable/New(obj/machinery/portable_atmospherics/P)
	. = ..()
	thing = P

/datum/bot_step/free_portable/execute(datum/bot_brain/bot)
	if(QDELETED(thing) || !bot.owner.Adjacent(thing))
		return GOAL_STEP_FAIL
	if(thing.connected_port)
		var/obj/item/wrench/W = bot.find_or_transform_tool(/obj/item/wrench)
		if(!W)
			return GOAL_STEP_FAIL
		bot.use_item_on(W, thing)
	return thing.connected_port ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/datum/bot_step/grab_portable
	var/obj/machinery/portable_atmospherics/thing

/datum/bot_step/grab_portable/New(obj/machinery/portable_atmospherics/P)
	. = ..()
	thing = P

/datum/bot_step/grab_portable/execute(datum/bot_brain/bot)
	if(QDELETED(thing) || !bot.owner.Adjacent(thing))
		return GOAL_STEP_FAIL
	bot.human_pause(thing)
	bot.owner.start_pulling(thing)
	return bot.owner.pulling == thing ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// It's got to be sat right on the port: a pull leaves it a tile behind, so the last step is out of the way, or the pulled thing's own.
/datum/bot_step/paced/park_on_port
	max_clicks = 12
	var/obj/machinery/portable_atmospherics/thing
	var/obj/machinery/atmospherics/components/unary/portables_connector/port

/datum/bot_step/paced/park_on_port/New(obj/machinery/portable_atmospherics/P, obj/machinery/atmospherics/components/unary/portables_connector/C)
	. = ..()
	thing = P
	port = C

/datum/bot_step/paced/park_on_port/do_click(datum/bot_brain/bot)
	var/turf/spot = get_turf(port)
	if(thing.loc == spot)
		bot.owner.stop_pulling()
		return FALSE
	if(bot.owner.pulling != thing)
		return FALSE
	if(get_turf(bot.owner) == spot)
		for(var/direction in GLOB.cardinals)
			var/turf/next = get_step(bot.owner, direction)
			if(next != thing.loc && isopenturf(next) && !is_blocked_turf(next, TRUE))
				bot.owner.Move(next, direction)
				wait_for = 4
				return TRUE
		return FALSE
	if(thing.Adjacent(spot))
		bot.owner.Move_Pulled(spot)
		wait_for = 4
		return TRUE
	return FALSE

/datum/bot_step/paced/park_on_port/finish(datum/bot_brain/bot)
	return thing.loc == get_turf(port) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Working the machines
// ---------------------------------------------------------------------------------------------

/// Over to something and one job at it.
/datum/bot_goal/toxins/at_machine
	var/atom/machine
	var/datum/bot_step/job

/datum/bot_goal/toxins/at_machine/New(datum/bot_toxins/L, atom/M, datum/bot_step/J)
	. = ..()
	machine = M
	job = J

/datum/bot_goal/toxins/at_machine/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(machine))
		target = machine

/datum/bot_goal/toxins/at_machine/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	S.steps = list(new /datum/bot_step/move_to(), job)
	// A job with a tank in it has the tank fetched first, if it was set down
	var/datum/bot_step/paced/toxins/scrub_tank/scrub = job
	if(istype(scrub))
		S.steps.Insert(1, new /datum/bot_step/fetch_tank(lab, scrub.cold))
	else if(istype(job, /datum/bot_step/paced/toxins/fill_hot))
		S.steps.Insert(1, new /datum/bot_step/fetch_tank(lab, FALSE))
	else if(istype(job, /datum/bot_step/paced/toxins/fill_cold))
		S.steps.Insert(1, new /datum/bot_step/fetch_tank(lab, TRUE))
	return list(S)

/// The freezer on, as cold as it goes. It takes its time: there's plenty else to be getting on with.
/datum/bot_step/paced/toxins/start_freezer/begin(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/F = lab.freezer
	bot.telemetry_ui_action(F, "cool")
	bot.human_pause(F)
	F.target_temperature = max(F.min_temperature, BOT_TOXINS_FREEZER_SET) //any colder and the canister's pressure drops below the tank's
	F.on = TRUE
	F.update_icon()
	lab.chill_started = world.time
	return TRUE

/// A plasma tank and an oxygen tank from the dispenser.
/datum/bot_goal/toxins/get_tanks/resolve_target(datum/bot_brain/bot)
	for(var/obj/structure/tank_dispenser/D as anything in bot_instances_of(/obj/structure/tank_dispenser))
		if(istype(get_area(D), /area/science) && D.plasmatanks && D.oxygentanks)
			target = D
			return

/datum/bot_goal/toxins/get_tanks/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/toxins/take_tanks(lab))
	return list(S)

/datum/bot_step/paced/toxins/take_tanks/ready(datum/bot_brain/bot)
	return lab.hot_tank && lab.cold_tank

/datum/bot_step/paced/toxins/take_tanks/do_click(datum/bot_brain/bot)
	var/obj/structure/tank_dispenser/D = bot.current_goal?.target
	if(ready(bot) || QDELETED(D) || !bot.owner.Adjacent(D))
		return FALSE
	bot.human_pause(D)
	bot.free_hand_for(null)
	if(!lab.hot_tank)
		var/obj/item/tank/internals/plasma/P = locate() in D
		if(P && bot.owner.put_in_hands(P))
			D.plasmatanks--
			lab.hot_tank = P
	else
		var/obj/item/tank/internals/oxygen/O = locate() in D
		if(O && bot.owner.put_in_hands(O))
			D.oxygentanks--
			lab.cold_tank = O
	D.update_icon()
	bot.put_away(lab.cold_tank || lab.hot_tank)
	wait_for = 8
	clicks++
	return TRUE

/// A tank into a portable machine: FALSE, and back for it, if it can't be
/datum/bot_step/paced/toxins/proc/load_tank(datum/bot_brain/bot, obj/machinery/portable_atmospherics/P, obj/item/tank/T)
	if(P.holding == T)
		return TRUE
	bot.use_item_on(T, P)
	if(P.holding == T)
		return TRUE
	bot_log(bot, "TOXINS: can't get [T] (at [T.loc]) into [P]")
	if(isturf(T.loc)) //both hands wanted for something, and it was the one set down
		bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(T))
	return FALSE

/// A tank scrubbed out in the portable scrubber ("so it's completely empty", the user's way), so all it holds after is what goes in:
/// a tank of cold plasma would take the heat out of the hot, and a dispenser's oxygen tank comes full of room-warm oxygen, which left the
/// cold one at 944 kPa and 144 K. The scrubber takes oxygen only when told to, as its own window has it.
/datum/bot_step/paced/toxins/scrub_tank
	var/cold = FALSE

/datum/bot_step/paced/toxins/scrub_tank/New(datum/bot_toxins/L, cold)
	. = ..(L)
	src.cold = cold

/datum/bot_step/paced/toxins/scrub_tank/proc/tank()
	return cold ? lab.cold_tank : lab.hot_tank

/datum/bot_step/paced/toxins/scrub_tank/begin(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/scrubber/S = lab.tank_scrubber
	if(!load_tank(bot, S, tank()))
		return FALSE
	bot.telemetry_ui_action(S, "scrub the tank")
	if(cold)
		S.scrubbing |= /datum/gas/oxygen
	S.on = TRUE
	S.update_icon()
	return TRUE

/datum/bot_step/paced/toxins/scrub_tank/ready(datum/bot_brain/bot)
	var/obj/item/tank/T = tank()
	return T.air_contents.return_pressure() < 1

/datum/bot_step/paced/toxins/scrub_tank/wrap_up(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/scrubber/S = lab.tank_scrubber
	S.on = FALSE
	S.scrubbing -= /datum/gas/oxygen
	S.update_icon()
	var/obj/item/tank/T = tank()
	if(S.holding == T)
		bot.make_hand_free()
		S.replace_tank(bot.owner, TRUE)
		bot.put_away(T)

/// The chamber's scrubber off at its air alarm while it's filled and burns: as mapped it scrubs CO2 into the output line, which would be
/// the first thing into the tank. On the bench that filled the tank with CO2 at 1,768 K: no explosion.
/datum/bot_step/paced/toxins/scrubber_off/begin(datum/bot_brain/bot)
	bot.telemetry_ui_action(lab.chamber_alarm, "scrubber off")
	bot.human_pause(lab.chamber_alarm)
	lab.scrubber.on = FALSE
	lab.scrubber.update_icon()
	return TRUE

/// What's left in the chamber from before, out through the blast doors to space, and the doors shut again
/datum/bot_step/paced/toxins/vent_chamber
	limit = 1 MINUTES
	var/opened = FALSE

/datum/bot_step/paced/toxins/vent_chamber/begin(datum/bot_brain/bot)
	bot.use_atom(lab.vent_button)
	opened = TRUE
	return TRUE

/datum/bot_step/paced/toxins/vent_chamber/ready(datum/bot_brain/bot)
	var/datum/gas_mixture/air = lab.chamber_air()
	return !air || air.return_pressure() < 2

/datum/bot_step/paced/toxins/vent_chamber/wrap_up(datum/bot_brain/bot)
	if(opened && !QDELETED(lab.vent_button) && bot.owner.Adjacent(lab.vent_button))
		bot.use_atom(lab.vent_button)

/// The inlet valve open and its pump up to all it'll do, until the chamber's got its plasma, or the oxygen on top, then the valve shut
/// before the canister comes off: what's in the line behind the valve goes on in otherwise.
/datum/bot_step/paced/toxins/fill_chamber
	limit = 3 MINUTES
	var/oxygen = FALSE
	var/target_kpa = 0

/datum/bot_step/paced/toxins/fill_chamber/New(datum/bot_toxins/L, oxygen)
	. = ..(L)
	src.oxygen = oxygen

/datum/bot_step/paced/toxins/fill_chamber/begin(datum/bot_brain/bot)
	var/datum/gas_mixture/air = lab.chamber_air()
	if(!air)
		return FALSE
	if(oxygen)
		lab.plasma_in_kpa = air.return_pressure() //what the plasma came to, the line's last of it included
		target_kpa = lab.plasma_in_kpa * (1 + BOT_TOXINS_OXYGEN_SHARE)
	else
		target_kpa = air.return_pressure() + BOT_TOXINS_PLASMA_KPA
	bot.telemetry_ui_action(lab.inlet_valve, "open the inlet")
	bot.human_pause(lab.inlet_valve)
	if(lab.inlet_pump)
		lab.inlet_pump.target_pressure = MAX_OUTPUT_PRESSURE
		lab.inlet_pump.on = TRUE
		lab.inlet_pump.update_icon()
	if(!lab.inlet_valve.on)
		lab.inlet_valve.toggle()
	return TRUE

/datum/bot_step/paced/toxins/fill_chamber/ready(datum/bot_brain/bot)
	var/datum/gas_mixture/air = lab.chamber_air()
	if(!air)
		return FALSE
	var/obj/machinery/portable_atmospherics/canister/C = oxygen ? lab.burn_oxygen_can : lab.plasma_can
	return air.return_pressure() >= target_kpa || (C && C.air_contents.return_pressure() < 10)

/datum/bot_step/paced/toxins/fill_chamber/wrap_up(datum/bot_brain/bot)
	if(lab.inlet_valve.on)
		lab.inlet_valve.toggle()
	var/datum/gas_mixture/air = lab.chamber_air()
	if(air)
		bot_log(bot, "TOXINS: chamber at [round(air.return_pressure())] kPa after the [oxygen ? "oxygen" : "plasma"], [round(100 * air.moles[/datum/gas/plasma] / max(air.total_moles(), 0.001))]% plasma")

/// A canister off a port and pulled aside, out of the way of the next
/datum/bot_goal/toxins/clear_port
	var/obj/machinery/portable_atmospherics/thing

/datum/bot_goal/toxins/clear_port/New(datum/bot_toxins/L, obj/machinery/portable_atmospherics/P)
	. = ..(L)
	thing = P

/datum/bot_goal/toxins/clear_port/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(thing))
		target = thing

/datum/bot_goal/toxins/clear_port/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	S.steps = list(new /datum/bot_step/ensure_wrench(), new /datum/bot_step/move_to(), new /datum/bot_step/free_portable(thing), new /datum/bot_step/grab_portable(thing), new /datum/bot_step/paced/pull_aside(thing))
	return list(S)

/// Something in the way of a port moved off it: the stage the port's wanted for is still to do
/datum/bot_goal/toxins/clear_port/blocker/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/toxins/duty = bot_duty_of(/datum/bot_duty/toxins)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/// What's being pulled taken a few tiles off the port it was on, a step at a time, and let go: one tile only left Meta's spare canister
/// stood between its inlet and outlet ports, in the way of both
/datum/bot_step/paced/pull_aside
	max_clicks = 8
	var/obj/machinery/portable_atmospherics/thing
	var/turf/from

/datum/bot_step/paced/pull_aside/New(obj/machinery/portable_atmospherics/P)
	. = ..()
	thing = P

/datum/bot_step/paced/pull_aside/start(datum/bot_brain/bot)
	from = get_turf(thing)
	return !QDELETED(thing) && bot.owner.pulling == thing

/datum/bot_step/paced/pull_aside/do_click(datum/bot_brain/bot)
	if(QDELETED(thing) || bot.owner.pulling != thing || get_dist(thing, from) >= 3)
		return FALSE
	var/turf/best
	for(var/turf/open/T in orange(1, bot.owner)) //the diagonals too: by Meta's inlet port every straight step stays a tile from it
		if(T == get_turf(thing) || is_blocked_turf(T, TRUE) || (locate(/obj/machinery/atmospherics/components/unary/portables_connector) in T))
			continue
		if(!best || get_dist(T, from) > get_dist(best, from))
			best = T
	if(!best || get_dist(best, from) <= get_dist(bot.owner, from)) //each step farther off, or it's done
		return FALSE
	bot.owner.Move(best, get_dir(bot.owner, best))
	wait_for = 4
	return TRUE

/datum/bot_step/paced/pull_aside/finish(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	return (!QDELETED(thing) && get_turf(thing) != from) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// A tank back in hand before it's wanted, if it was set down: both hands wanted at once, and it was the one put on the floor
/datum/bot_step/fetch_tank
	var/datum/bot_toxins/lab
	var/cold = FALSE

/datum/bot_step/fetch_tank/New(datum/bot_toxins/L, cold)
	. = ..()
	lab = L
	src.cold = cold

/datum/bot_step/fetch_tank/execute(datum/bot_brain/bot)
	var/obj/item/tank/T = cold ? lab.cold_tank : lab.hot_tank
	if(QDELETED(T))
		return GOAL_STEP_FAIL
	if(isturf(T.loc))
		return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(T)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS //carried, or in the machine it's going to

/// The ignition switch, and stood by while it burns to the pull heat. Pressed again if it hasn't caught: an igniter that's still off, or
/// sparkers that didn't take.
/datum/bot_step/paced/toxins/ignite
	limit = BOT_TOXINS_BURN_LIMIT
	var/pressed_at = 0
	var/presses = 0
	var/next_note = 0

/datum/bot_step/paced/toxins/ignite/begin(datum/bot_brain/bot)
	press(bot)
	return TRUE

/datum/bot_step/paced/toxins/ignite/proc/press(datum/bot_brain/bot)
	if(QDELETED(lab.ignition) || !bot.owner.Adjacent(lab.ignition))
		return
	bot.use_atom(lab.ignition)
	pressed_at = world.time
	presses++
	bot_log(bot, "TOXINS: pressed the ignition switch")

/datum/bot_step/paced/toxins/ignite/do_click(datum/bot_brain/bot)
	. = ..()
	if(!.)
		return
	var/datum/gas_mixture/air = lab.chamber_air()
	if(!air)
		return
	if(air.temperature < 400 && world.time > pressed_at + 40 SECONDS && presses < 3)
		var/lit_igniter = FALSE
		for(var/obj/machinery/igniter/I in GLOB.machines)
			if(I.id == lab.ignition.id && I.on)
				lit_igniter = TRUE
		if(!lit_igniter) //an igniter that's on stays on, and another press turns it off
			press(bot)
	if(world.time >= next_note)
		next_note = world.time + 30 SECONDS
		bot_log(bot, "TOXINS: chamber at [round(air.temperature)] K, [round(air.return_pressure())] kPa")

/datum/bot_step/paced/toxins/ignite/ready(datum/bot_brain/bot)
	var/datum/gas_mixture/air = lab.chamber_air()
	return air && air.temperature >= BOT_TOXINS_PULL_AT

/datum/bot_step/paced/toxins/ignite/wrap_up(datum/bot_brain/bot)
	var/datum/gas_mixture/air = lab.chamber_air()
	if(air)
		bot_log(bot, "TOXINS: [air.temperature >= BOT_TOXINS_PULL_AT ? "pulling" : "never got there"] at [round(air.temperature)] K, [round(air.return_pressure())] kPa, [round(100 * air.moles[/datum/gas/plasma] / max(air.total_moles(), 0.001))]% plasma")

/// The scrubber on plasma only, at the chamber's air alarm: the filter
/datum/bot_step/paced/toxins/scrub_plasma/begin(datum/bot_brain/bot)
	bot.telemetry_ui_action(lab.chamber_alarm, "scrub plasma")
	bot.human_pause(lab.chamber_alarm)
	lab.scrubber.filter_types = list(/datum/gas/plasma)
	lab.scrubber.scrubbing = TRUE
	lab.scrubber.on = TRUE
	lab.scrubber.update_icon()
	return TRUE

/// The output line open: its pump up to all it'll do, and the valve
/datum/bot_step/paced/toxins/open_outlet/begin(datum/bot_brain/bot)
	bot.telemetry_ui_action(lab.outlet_valve, "open the outlet")
	bot.human_pause(lab.outlet_valve)
	if(lab.outlet_pump)
		lab.outlet_pump.target_pressure = MAX_OUTPUT_PRESSURE
		lab.outlet_pump.on = TRUE
		lab.outlet_pump.update_icon()
	if(!lab.outlet_valve.on)
		lab.outlet_valve.toggle()
	return TRUE

/// The emptied tank in the pump on the output port, filled to as much as the pump will give, with the plasma coming off the chamber
/datum/bot_step/paced/toxins/fill_hot
	limit = 4 MINUTES

/datum/bot_step/paced/toxins/fill_hot/begin(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/pump/P = lab.pump
	if(!load_tank(bot, P, lab.hot_tank))
		return FALSE
	bot.telemetry_ui_action(P, "fill the tank")
	bot.human_pause(P)
	P.direction = "in"
	P.pump.target_pressure = ONE_ATMOSPHERE * 25 //all it'll do
	P.on = TRUE
	P.update_icon()
	return TRUE

/datum/bot_step/paced/toxins/fill_hot/ready(datum/bot_brain/bot)
	return lab.hot_tank.air_contents.return_pressure() >= BOT_TOXINS_HOT_KPA

/datum/bot_step/paced/toxins/fill_hot/wrap_up(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/pump/P = lab.pump
	P.on = FALSE
	P.update_icon()
	// The line shut and the scrubber off again, as found
	if(lab.outlet_valve.on)
		lab.outlet_valve.toggle()
	lab.scrubber.on = FALSE
	lab.scrubber.update_icon()
	var/datum/gas_mixture/air = lab.hot_tank.air_contents
	bot_log(bot, "TOXINS: hot tank at [round(air.return_pressure())] kPa, [round(air.temperature)] K, [round(100 * air.moles[/datum/gas/plasma] / max(air.total_moles(), 0.001))]% plasma")
	if(P.holding == lab.hot_tank)
		bot.make_hand_free()
		P.replace_tank(bot.owner, TRUE)
		bot.put_away(lab.hot_tank)

/// The oxygen tank in the cold canister, as much as it'll let out.
/datum/bot_step/paced/toxins/fill_cold/begin(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/C = lab.oxygen_can
	if(C.holding != lab.cold_tank)
		bot.use_item_on(lab.cold_tank, C)
	if(C.holding != lab.cold_tank)
		return FALSE
	C.release_pressure = C.can_max_release_pressure
	C.valve_open = TRUE
	C.update_icon()
	return TRUE

/// Full, or as full as the canister will make it: one chilled on the freezer's port shares its oxygen with the pipe and the freezer,
/// and at 75 K it's down to about 950 kPa, which the tank comes level with
/datum/bot_step/paced/toxins/fill_cold/ready(datum/bot_brain/bot)
	var/tank_kpa = lab.cold_tank.air_contents.return_pressure()
	return tank_kpa >= BOT_TOXINS_COLD_KPA || tank_kpa >= lab.oxygen_can.air_contents.return_pressure() * 0.97

/datum/bot_step/paced/toxins/fill_cold/wrap_up(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/C = lab.oxygen_can
	C.valve_open = FALSE
	C.update_icon()
	lab.freezer.on = FALSE
	lab.freezer.update_icon()
	var/datum/gas_mixture/air = lab.cold_tank.air_contents
	bot_log(bot, "TOXINS: cold tank at [round(air.return_pressure())] kPa, [round(air.temperature)] K; canister [round(C.air_contents.return_pressure())] kPa, [round(C.air_contents.temperature)] K, holding [C.holding], release [C.release_pressure], port [C.connected_port], broken [C.stat & BROKEN], moles [round(C.air_contents.total_moles())]")
	bot.make_hand_free()
	C.replace_tank(bot.owner, TRUE)
	bot.put_away(lab.cold_tank)

// ---------------------------------------------------------------------------------------------
// The bomb
// ---------------------------------------------------------------------------------------------

/// A valve and what sets it off, from the rack or the Toximate.
/datum/bot_goal/toxins/kit/resolve_target(datum/bot_brain/bot)
	target = bot.owner

/datum/bot_goal/toxins/kit/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	S.steps = list(new /datum/bot_step/fetch_bomb_parts(lab))
	return list(S)

/// Everything out of the bag and on the valve.
/datum/bot_goal/toxins/assemble/resolve_target(datum/bot_brain/bot)
	target = bot.owner

/datum/bot_goal/toxins/assemble/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	S.steps = list(new /datum/bot_step/gather_tanks(lab), new /datum/bot_step/fetch_bomb_parts(lab), new /datum/bot_step/paced/assemble_valve(lab))
	return list(S)

/datum/bot_goal/botany_supply/toximate/resolve_target(datum/bot_brain/bot)
	target = bot.find_botany_vendor(/obj/machinery/vending/plasmaresearch, list(item_type))

/// What goes on the valve: a health sensor, for a traitor who's taking it with them. A timer for the range.
/datum/bot_brain/proc/bomb_trigger_type()
	if(saboteur && wants_maxcap) //goals/sabotage_bomb.dm: a timer, for leaving it in Security
		return /obj/item/assembly/timer
	return owner.mind?.has_antag_datum(/datum/antagonist/traitor) ? /obj/item/assembly/health : /obj/item/assembly/timer

/// A tank that ended up on the floor, with the bot's hands full when it came out of the machine.
/datum/bot_step/gather_tanks
	var/datum/bot_toxins/lab

/datum/bot_step/gather_tanks/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_step/gather_tanks/execute(datum/bot_brain/bot)
	for(var/obj/item/tank/T in list(lab.hot_tank, lab.cold_tank))
		if(bot.is_carried(T) || (lab.valve && (T == lab.valve.tank_one || T == lab.valve.tank_two)))
			continue
		// At its feet will do: the valve step takes each tank up from where it lies (ready_in_hand()), one at a time. With a full bag and
		// something in the other hand it had nowhere to put (a wrench, a bio suit), picking one tank up set the other down (make_hand_free()),
		// this step sent it for that one, and the two changed places fifteen times a try, nine tries in a shift: no bomb.
		if(isturf(T.loc) && bot.owner.Adjacent(T))
			continue
		if(isturf(T.loc) && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(T)))
			return GOAL_STEP_PENDING
		bot_log(bot, "TOXINS: lost [T] ([T.loc])")
		return GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS

/datum/bot_step/fetch_bomb_parts
	var/datum/bot_toxins/lab
	var/list/tried = list()

/datum/bot_step/fetch_bomb_parts/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_step/fetch_bomb_parts/execute(datum/bot_brain/bot)
	for(var/needed in list(/obj/item/transfer_valve, bot.bomb_trigger_type()))
		if(bot.find_carried_tool(needed) || (needed in tried))
			continue
		tried += needed
		// Science's own first, where the lab keeps them: the search below goes by the nearest six anywhere, and Box has a dozen timers
		// about the station, the bridge's and Security's and Chemistry's nearer than the lab's to wherever the scientist stood
		var/obj/item/in_lab
		for(var/obj/item/I as anything in bot_instances_of(needed))
			if(isturf(I.loc) && I.z == bot.owner.z && istype(get_area(I), /area/science) && (!in_lab || get_dist(I, bot.owner) < get_dist(in_lab, bot.owner)))
				in_lab = I
		if(in_lab)
			if(bot.can_walk_lawfully_to(in_lab))
				if(bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(in_lab)))
					return GOAL_STEP_PENDING
			else
				// Box's sit on a table in a corner, a table and the wall either side: reached across the diagonal, as anybody would
				for(var/turf/open/T in orange(1, in_lab))
					if(get_dir(in_lab, T) in GLOB.diagonals)
						if(!is_blocked_turf(T, TRUE) && bot.can_walk_lawfully_to(T) && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact/from_spot(in_lab, T)))
							return GOAL_STEP_PENDING
		var/datum/bot_goal/acquire_item_type/fetch = new()
		fetch.item_type = needed
		fetch.lawful = TRUE
		if(bot.suspend_goal_for(fetch))
			return GOAL_STEP_PENDING
		var/datum/bot_goal/botany_supply/toximate/bought = new(needed, "toximate")
		bought.lawful = TRUE
		if(bot.suspend_goal_for(bought))
			return GOAL_STEP_PENDING
	if(bot.find_carried_tool(/obj/item/transfer_valve) && bot.find_carried_tool(bot.bomb_trigger_type()))
		return GOAL_STEP_SUCCESS
	var/list/near = list()
	for(var/obj/item/I as anything in bot_instances_of(bot.bomb_trigger_type()))
		if(isturf(I.loc) && I.z == bot.owner.z && get_dist(I, bot.owner) < 12)
			near += "[I.x],[I.y] [bot.can_walk_lawfully_to(I) ? "reachable" : "not reachable"]"
	bot_log(bot, "TOXINS: no valve or no trigger to be had (valve [!!bot.find_carried_tool(/obj/item/transfer_valve)]; nearby: [english_list(near, "none")])")
	return GOAL_STEP_FAIL

/// One particular loose thing, picked up from a given tile beside it
/datum/bot_goal/take_item/exact/from_spot
	var/turf/spot

/datum/bot_goal/take_item/exact/from_spot/New(obj/item/I, turf/T)
	. = ..(I)
	spot = T

/datum/bot_goal/take_item/exact/from_spot/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/take_item/S = new
	var/datum/bot_step/move_to/there = new
	there.step_target = spot
	S.steps = list(there, new /datum/bot_step/take_in_hand())
	return list(S)

/// The tanks on the valve, then what sets it off. A health sensor on a traitor's bomb is as good as a dead man's switch from here on.
/datum/bot_step/paced/assemble_valve
	max_clicks = 6
	var/datum/bot_toxins/lab

/datum/bot_step/paced/assemble_valve/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_step/paced/assemble_valve/do_click(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = lab.valve || bot.find_carried_tool(/obj/item/transfer_valve)
	if(!V)
		return FALSE
	lab.valve = V
	if(!V.tank_one)
		bot.use_item_on(lab.hot_tank, V)
		return TRUE
	if(!V.tank_two)
		bot.use_item_on(lab.cold_tank, V)
		return TRUE
	if(!V.attached_device)
		bot.fit_trigger(V, bot.find_carried_tool(bot.bomb_trigger_type()))
		return TRUE
	return FALSE

/datum/bot_step/paced/assemble_valve/finish(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = lab.valve
	if(!V?.tank_one || !V.tank_two || !V.attached_device)
		bot_log(bot, "TOXINS: valve [V], tanks [V?.tank_one] and [V?.tank_two], device [V?.attached_device]")
		return GOAL_STEP_FAIL
	if(istype(V.attached_device, /obj/item/assembly/health))
		// That's it, for a traitor. It's too bulky for a bag, so it stays in the hand, and goes off as it falls out of it (assembly/health.dm).
		lab.finished = TRUE
		bot.armed_bomb = V
		bot_log(bot, "TOXINS: armed a dead man's switch")
		bot_tally("dead man's switches")
		log_game("BOT TOXINS: [bot.owner.real_name] is carrying a tank bomb on a health sensor")
	else if(bot.saboteur && bot.wants_maxcap)
		// Not for the range: it's going to Security (goals/sabotage_bomb.dm), and the lab's done for the round.
		lab.finished = TRUE
		bot.armed_bomb = V
		bot_log(bot, "TOXINS: SABOTAGE: a timer on it, and it's staying with me")
		log_game("BOT TOXINS: [bot.owner.real_name] is keeping a tank bomb on a timer for sabotage")
	return GOAL_STEP_SUCCESS

/// A traitor doesn't leave that lying about.
/datum/bot_brain/proc/mind_armed_bomb()
	if(QDELETED(armed_bomb))
		armed_bomb = null
		return
	if(isturf(armed_bomb.loc) && owner.Adjacent(armed_bomb))
		INVOKE_ASYNC(src, PROC_REF(take_in_hand), armed_bomb)

/// What sets it off, on the valve. They come screwed shut: the valve won't take one until it's undone, and it does it up again itself.
/// Undoing a health sensor stops it reading, so that goes back on after.
/datum/bot_brain/proc/fit_trigger(obj/item/transfer_valve/V, obj/item/assembly/trigger)
	if(!trigger)
		return FALSE
	if(trigger.secured)
		trigger.toggle_secure()
	use_item_on(trigger, V)
	var/obj/item/assembly/health/sensor = V.attached_device
	if(istype(sensor) && !sensor.scanning)
		sensor.toggle_scan()
	return V.attached_device == trigger

/// Onto the mass driver, the timer started, and over to the button.
/datum/bot_goal/toxins/launch/resolve_target(datum/bot_brain/bot)
	for(var/obj/machinery/mass_driver/D as anything in bot_instances_of(/obj/machinery/mass_driver))
		if(D.id == "toxinsdriver" && D.z == bot.owner.z)
			target = D
			return

/datum/bot_goal/toxins/launch/get_strategies(datum/bot_brain/bot)
	var/obj/machinery/button/massdriver/B
	for(var/obj/machinery/button/massdriver/candidate as anything in bot_instances_of(/obj/machinery/button/massdriver))
		if(candidate.id == "toxinsdriver" && candidate.z == bot.owner.z)
			B = candidate
	if(!B || lab.finished)
		return list()
	var/datum/bot_strategy/toxins/S = new
	var/datum/bot_step/move_to/on_driver = new
	on_driver.step_target = get_turf(target)
	var/datum/bot_step/move_to/to_button = new
	to_button.step_target = B
	S.steps = list(new /datum/bot_step/fetch_valve(lab), on_driver, new /datum/bot_step/set_down_bomb(lab), to_button, new /datum/bot_step/paced/press_launch(lab, B))
	return list(S)

/// Back for it if it's been set down: a valve with two tanks on it doesn't go in a bag, and it's first to go when both hands are wanted.
/datum/bot_step/fetch_valve
	var/datum/bot_toxins/lab

/datum/bot_step/fetch_valve/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_step/fetch_valve/execute(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = lab.valve
	if(QDELETED(V))
		return GOAL_STEP_FAIL
	if(bot.is_carried(V))
		return GOAL_STEP_SUCCESS
	if(isturf(V.loc) && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(V)))
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/datum/bot_step/set_down_bomb
	var/datum/bot_toxins/lab

/datum/bot_step/set_down_bomb/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_step/set_down_bomb/execute(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = lab.valve
	if(QDELETED(V))
		return GOAL_STEP_FAIL
	if(!bot.ready_in_hand(V))
		bot_log(bot, "TOXINS: valve is at [V.loc], not on me")
		return GOAL_STEP_FAIL
	var/obj/item/assembly/timer/T = V.attached_device
	if(istype(T))
		T.time = BOT_TOXINS_FUSE
		T.timing = TRUE
		T.update_icon()
	bot.owner.dropItemToGround(V)
	// Left there on purpose. It had been set down for a moment while the tanks went on, which put it on the list of things to go
	// back for (bot_items.dm), and nothing took it off: a scientist put the bomb on the driver, set the timer, walked out, went
	// "back for the tank transfer valve", and carried it into the station. It went off in maintenance and killed five.
	LAZYREMOVE(bot.set_down_items, V)
	bot_log(bot, "TOXINS: bomb on the driver, [BOT_TOXINS_FUSE] seconds on the timer")
	bot_say(bot.owner, ";Toxins launching. Clear the range.")
	return GOAL_STEP_SUCCESS

/datum/bot_step/paced/press_launch
	max_clicks = 3
	var/datum/bot_toxins/lab
	var/obj/machinery/button/massdriver/button

/datum/bot_step/paced/press_launch/New(datum/bot_toxins/L, obj/machinery/button/massdriver/B)
	. = ..()
	lab = L
	button = B

/datum/bot_step/paced/press_launch/do_click(datum/bot_brain/bot)
	if(QDELETED(button) || !bot.owner.Adjacent(button) || lab.finished)
		return FALSE
	bot.use_atom(button)
	lab.finished = TRUE
	bot_news("Science just set off a bomb on the test range")
	return FALSE

/datum/bot_step/paced/press_launch/finish(datum/bot_brain/bot)
	if(!lab.finished)
		return GOAL_STEP_FAIL
	bot.bombs_launched++
	bot_tally("bombs launched")
	log_game("BOT TOXINS: [bot.owner.real_name] launched a tank bomb")
	return GOAL_STEP_SUCCESS

#undef BOT_TOXINS_SETTLE_IN
#undef BOT_TOXINS_PLASMA_KPA
#undef BOT_TOXINS_OXYGEN_SHARE
#undef BOT_TOXINS_PULL_AT
#undef BOT_TOXINS_BURN_LIMIT
#undef BOT_TOXINS_HOT_KPA
#undef BOT_TOXINS_COLD_KPA
#undef BOT_TOXINS_FREEZER_SET
#undef BOT_TOXINS_CHILL_LIMIT
#undef BOT_TOXINS_COLD_ENOUGH
#undef BOT_TOXINS_FUSE
#undef BOT_TOXINS_TRIES
