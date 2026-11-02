// Toxins: a tank transfer valve bomb, for the research points, the way the lab's regulars make one. What it comes to on this server's atmos
// was measured on the bench (gym/ttv_bench.dm): a mix pulled out of the burn at 6,000 C never gets past radius 9. What does the job is a
// lean mix that burns its oxygen and stops by itself, hot, and still nine parts plasma.
//
//  - Plasma and oxygen through a gas mixer, twenty to one, into an empty canister.
//  - That canister on the heater's port until it lights, then off the port: a shut canister burns on by itself, up to about 3,000 K.
//  - The oxygen canister on the freezer's port, to get as cold as it'll go.
//  - A canister only lets out 1,013 kPa, and the hot tank wants 2,500. So the hot canister goes through the second mixer into a portable
//    pump, which will fill a tank to 2,533. The plasma tank's emptied into the pump first: a tank of cold plasma would take the heat out.
//  - The tanks on a valve with a timer, the valve on the mass driver, and the button: it goes off out past the test range, where the
//    doppler array can see it. Radius 17 or so, by the bench.
//
// A traitor who gets this far fits a health sensor instead and keeps it in the bag: if they go down, everybody round them goes with them.
//
// It takes a mixer with all three ports on, and only the Hippie map has that: the others pipe it straight into the burn chamber.

/// How long into the round before anybody starts on this.
#define BOT_TOXINS_SETTLE_IN (5 MINUTES)
/// What goes in the burn canister, at room temperature. It comes out ten times that.
#define BOT_TOXINS_BURN_KPA 1500
/// Parts plasma to one of oxygen, on the mixer's dials. On the bench it takes 20, but some goes on burning in the pipes. A hair leaner and it
/// barely gets warm: 30 to 1 stops at 895 K.
#define BOT_TOXINS_PLASMA_SHARE 10
/// How hot it has to get to light.
#define BOT_TOXINS_LIGHT_AT 395
/// What the hot tank wants, and what the cold one wants.
#define BOT_TOXINS_HOT_KPA 2450
#define BOT_TOXINS_COLD_KPA 950
/// What the freezer's set to. A full canister at 100 K is still about 1,000 kPa, which it needs to be to fill a tank.
#define BOT_TOXINS_FREEZER_SET 100
/// How long the freezer's given, and how cold will do.
#define BOT_TOXINS_CHILL_LIMIT (5 MINUTES)
#define BOT_TOXINS_COLD_ENOUGH 110
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
	var/obj/machinery/atmospherics/components/trinary/mixer/mix_mixer
	var/obj/machinery/atmospherics/components/trinary/mixer/pump_mixer
	var/obj/machinery/atmospherics/components/unary/portables_connector/plasma_port
	var/obj/machinery/atmospherics/components/unary/portables_connector/oxygen_port
	var/obj/machinery/atmospherics/components/unary/portables_connector/mix_port
	var/obj/machinery/atmospherics/components/unary/portables_connector/hot_port
	var/obj/machinery/atmospherics/components/unary/portables_connector/pump_port
	var/obj/machinery/atmospherics/components/unary/portables_connector/heater_port
	var/obj/machinery/atmospherics/components/unary/portables_connector/freezer_port
	var/obj/machinery/atmospherics/components/unary/thermomachine/heater/heater
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer
	var/obj/machinery/portable_atmospherics/canister/plasma_can
	var/obj/machinery/portable_atmospherics/canister/oxygen_can
	var/obj/machinery/portable_atmospherics/canister/mix_can
	var/obj/machinery/portable_atmospherics/pump/pump
	var/obj/item/tank/hot_tank
	var/obj/item/tank/cold_tank
	var/obj/item/transfer_valve/valve
	var/chill_started = 0
	var/finished = FALSE
	/// Who's on it, as a weakref.
	var/datum/weakref/worker

/// A port on one side of a mixer, if there is one.
/proc/bot_mixer_port(obj/machinery/atmospherics/components/trinary/mixer/M, side)
	var/obj/machinery/atmospherics/components/unary/portables_connector/C = M.nodes[side]
	if(istype(C))
		return C
	var/datum/pipeline/P = M.parents[side]
	if(P)
		for(var/obj/machinery/atmospherics/components/unary/portables_connector/found in P.other_atmosmch)
			return found
	return null

/proc/bot_lab_thermomachine_port(obj/machinery/atmospherics/components/unary/thermomachine/M)
	var/obj/machinery/atmospherics/components/unary/portables_connector/C = M.nodes[1]
	if(istype(C))
		return C
	var/datum/pipeline/P = M.parents[1]
	if(P)
		for(var/obj/machinery/atmospherics/components/unary/portables_connector/found in P.other_atmosmch)
			return found
	return null

/// Everything a bomb takes, found where it's kept. FALSE if this station hasn't got it.
/datum/bot_toxins/proc/find_lab(datum/bot_brain/bot)
	var/list/mixers = list()
	for(var/obj/machinery/atmospherics/components/trinary/mixer/M as anything in bot_instances_of(/obj/machinery/atmospherics/components/trinary/mixer))
		if(istype(get_area(M), /area/science/mixing) && bot_mixer_port(M, 1) && bot_mixer_port(M, 2) && bot_mixer_port(M, 3))
			mixers += M
	if(length(mixers) < 2)
		return FALSE
	mix_mixer = mixers[1]
	pump_mixer = mixers[2]
	plasma_port = bot_mixer_port(mix_mixer, 1)
	oxygen_port = bot_mixer_port(mix_mixer, 2)
	mix_port = bot_mixer_port(mix_mixer, 3)
	hot_port = bot_mixer_port(pump_mixer, 1)
	pump_port = bot_mixer_port(pump_mixer, 3)
	for(var/obj/machinery/atmospherics/components/unary/thermomachine/M as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/thermomachine))
		if(!istype(get_area(M), /area/science/mixing))
			continue
		if(istype(M, /obj/machinery/atmospherics/components/unary/thermomachine/heater))
			heater = M
			heater_port = bot_lab_thermomachine_port(M)
		else
			freezer = M
			freezer_port = bot_lab_thermomachine_port(M)
	if(!heater_port || !freezer_port)
		return FALSE
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(!istype(get_area(C), /area/science) || C.connected_port || C.stat & BROKEN)
			continue
		var/pressure = C.air_contents.return_pressure()
		if(!plasma_can && istype(C, /obj/machinery/portable_atmospherics/canister/toxins) && pressure > 2000 && bot.can_walk_lawfully_to(C))
			plasma_can = C
		else if(!oxygen_can && istype(C, /obj/machinery/portable_atmospherics/canister/oxygen) && pressure > 2000 && bot.can_walk_lawfully_to(C))
			oxygen_can = C
		else if(!mix_can && C.type == /obj/machinery/portable_atmospherics/canister && pressure < 10 && bot.can_walk_lawfully_to(C))
			mix_can = C
	for(var/obj/machinery/portable_atmospherics/pump/P as anything in bot_instances_of(/obj/machinery/portable_atmospherics/pump))
		if(istype(get_area(P), /area/science/mixing) && !P.connected_port && bot.can_walk_lawfully_to(P))
			pump = P
			break
	return plasma_can && oxygen_can && mix_can && pump

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
			return new /datum/bot_goal/toxins/place(src, plasma_can, plasma_port)
		if(3)
			return new /datum/bot_goal/toxins/place(src, oxygen_can, oxygen_port)
		if(4)
			return new /datum/bot_goal/toxins/place(src, mix_can, mix_port)
		if(5)
			return new /datum/bot_goal/toxins/at_machine(src, mix_mixer, new /datum/bot_step/paced/toxins/run_mix(src))
		if(6)
			return new /datum/bot_goal/toxins/at_machine(src, heater, new /datum/bot_step/paced/toxins/start_heater(src)) //a canister on the port is in the way of it
		if(7)
			return new /datum/bot_goal/toxins/place(src, mix_can, heater_port)
		if(8)
			return new /datum/bot_goal/toxins/light(src)
		if(9)
			return new /datum/bot_goal/toxins/at_machine(src, freezer, new /datum/bot_step/paced/toxins/start_freezer(src))
		if(10)
			return new /datum/bot_goal/toxins/place(src, oxygen_can, freezer_port)
		if(11)
			return new /datum/bot_goal/toxins/place(src, pump, pump_port)
		if(12)
			return new /datum/bot_goal/toxins/place(src, mix_can, hot_port)
		if(13)
			return new /datum/bot_goal/toxins/get_tanks(src)
		if(14)
			return new /datum/bot_goal/toxins/at_machine(src, pump, new /datum/bot_step/paced/toxins/drain_tank(src))
		if(15)
			return new /datum/bot_goal/toxins/at_machine(src, pump_mixer, new /datum/bot_step/paced/toxins/run_hot(src))
		if(16)
			return new /datum/bot_goal/toxins/at_machine(src, pump, new /datum/bot_step/paced/toxins/fill_hot(src))
		if(17)
			if(oxygen_can.air_contents.temperature > BOT_TOXINS_COLD_ENOUGH && world.time < chill_started + BOT_TOXINS_CHILL_LIMIT)
				return null
			return new /datum/bot_goal/toxins/at_machine(src, oxygen_can, new /datum/bot_step/paced/toxins/fill_cold(src))
		if(18)
			return new /datum/bot_goal/toxins/assemble(src)
		if(19)
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
		if(!GLOB.bot_toxins.find_lab(bot))
			GLOB.bot_toxins.finished = TRUE
			log_game("BOT TOXINS: this station has no lab a bot can work")
	var/datum/bot_toxins/lab = GLOB.bot_toxins
	if(lab.finished || world.time < lab.rest_until)
		return FALSE
	// One pair of hands: whoever started has the tanks and knows where it's up to. Somebody else only takes over if they can't go on.
	var/datum/weakref/ref = lab.worker
	var/mob/living/carbon/human/worker = ref?.resolve()
	if(worker && worker != bot.owner && worker.stat == CONSCIOUS && !worker.handcuffed)
		return FALSE
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

/datum/bot_step/paced/toxins/New(datum/bot_toxins/L)
	. = ..()
	lab = L

/datum/bot_step/paced/toxins/start(datum/bot_brain/bot)
	ends_at = world.time + limit
	return begin(bot)

/datum/bot_step/paced/toxins/proc/begin(datum/bot_brain/bot)
	return TRUE

/// What it's waiting to see, TRUE when that's happened.
/datum/bot_step/paced/toxins/proc/ready(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/paced/toxins/do_click(datum/bot_brain/bot)
	if(ready(bot) || world.time > ends_at)
		return FALSE
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
	return list(S)

/// Twenty parts plasma to one of oxygen, into the empty canister.
/datum/bot_step/paced/toxins/run_mix/begin(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/trinary/mixer/M = lab.mix_mixer
	bot.telemetry_ui_action(M, "set the mix")
	bot.human_pause(M)
	M.node1_concentration = BOT_TOXINS_PLASMA_SHARE / (BOT_TOXINS_PLASMA_SHARE + 1)
	M.node2_concentration = 1 / (BOT_TOXINS_PLASMA_SHARE + 1)
	M.target_pressure = BOT_TOXINS_BURN_KPA
	M.on = TRUE
	M.update_icon()
	return TRUE

/datum/bot_step/paced/toxins/run_mix/ready(datum/bot_brain/bot)
	return lab.mix_can.air_contents.return_pressure() >= BOT_TOXINS_BURN_KPA * 0.95

/datum/bot_step/paced/toxins/run_mix/wrap_up(datum/bot_brain/bot)
	lab.mix_mixer.on = FALSE
	lab.mix_mixer.update_icon()

/// The heater up to what it'll do, until the mix lights, and straight off the port: the heater would hold it at 573.
/datum/bot_goal/toxins/light/resolve_target(datum/bot_brain/bot)
	target = lab.mix_can

/datum/bot_goal/toxins/light/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	S.steps = list(new /datum/bot_step/ensure_wrench(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/toxins/heat_mix(lab), new /datum/bot_step/free_portable(lab.mix_can), new /datum/bot_step/paced/toxins/burn_out(lab))
	return list(S)

/datum/bot_step/paced/toxins/start_heater/begin(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/unary/thermomachine/heater/H = lab.heater
	bot.telemetry_ui_action(H, "heat")
	bot.human_pause(H)
	H.target_temperature = H.max_temperature
	H.on = TRUE
	H.update_icon()
	return TRUE

/datum/bot_step/paced/toxins/heat_mix
	limit = 4 MINUTES

/datum/bot_step/paced/toxins/heat_mix/ready(datum/bot_brain/bot)
	return lab.mix_can.air_contents.temperature >= BOT_TOXINS_LIGHT_AT

/datum/bot_step/paced/toxins/heat_mix/wrap_up(datum/bot_brain/bot)
	lab.heater.on = FALSE
	lab.heater.update_icon()

/// Stood by it while it burns: it's done when the oxygen is.
/datum/bot_step/paced/toxins/burn_out
	limit = 8 MINUTES //it isn't a quick burn: the fuel's nearly all plasma, and there's only so much oxygen to find

/datum/bot_step/paced/toxins/burn_out/ready(datum/bot_brain/bot)
	return lab.mix_can.air_contents.moles[/datum/gas/oxygen] < 1

/datum/bot_step/paced/toxins/burn_out/wrap_up(datum/bot_brain/bot)
	var/datum/gas_mixture/air = lab.mix_can.air_contents
	bot_log(bot, "TOXINS: burned out at [round(air.temperature)] K, [round(air.return_pressure())] kPa, plasma [round(air.moles[/datum/gas/plasma])] mol, oxygen [round(air.moles[/datum/gas/oxygen], 0.1)] mol")

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

/// The plasma tank in the pump, and what's in it into the pump's own air: a tank of cold plasma would take the heat out of the hot gas.
/datum/bot_step/paced/toxins/drain_tank/begin(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/pump/P = lab.pump
	if(P.holding != lab.hot_tank)
		bot.use_item_on(lab.hot_tank, P)
	if(P.holding != lab.hot_tank)
		bot_log(bot, "TOXINS: can't get [lab.hot_tank] (at [lab.hot_tank.loc]) into [P]")
		if(isturf(lab.hot_tank.loc)) //both hands wanted for something, and it was the one set down
			bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(lab.hot_tank))
		return FALSE
	bot.telemetry_ui_action(P, "drain the tank")
	P.direction = "out"
	P.pump.target_pressure = ONE_ATMOSPHERE * 25 //all it'll do
	P.on = TRUE
	P.update_icon()
	return TRUE

/datum/bot_step/paced/toxins/drain_tank/ready(datum/bot_brain/bot)
	return lab.hot_tank.air_contents.return_pressure() < 5

/datum/bot_step/paced/toxins/drain_tank/wrap_up(datum/bot_brain/bot)
	lab.pump.on = FALSE
	lab.pump.update_icon()

/// The second mixer wide open from the hot canister: it's only there for the pressure.
/datum/bot_step/paced/toxins/run_hot/begin(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/trinary/mixer/M = lab.pump_mixer
	bot.telemetry_ui_action(M, "open")
	bot.human_pause(M)
	M.node1_concentration = 1
	M.node2_concentration = 0
	M.target_pressure = 3000
	M.on = TRUE
	M.update_icon()
	return TRUE

/datum/bot_step/paced/toxins/run_hot/ready(datum/bot_brain/bot)
	return lab.pump.air_contents.return_pressure() >= BOT_TOXINS_HOT_KPA

/datum/bot_step/paced/toxins/run_hot/wrap_up(datum/bot_brain/bot)
	lab.pump_mixer.on = FALSE
	lab.pump_mixer.update_icon()

/// The pump the other way, to as much as it'll give.
/datum/bot_step/paced/toxins/fill_hot/begin(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/pump/P = lab.pump
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
	var/datum/gas_mixture/air = lab.hot_tank.air_contents
	bot_log(bot, "TOXINS: hot tank at [round(air.return_pressure())] kPa, [round(air.temperature)] K")
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

/datum/bot_step/paced/toxins/fill_cold/ready(datum/bot_brain/bot)
	return lab.cold_tank.air_contents.return_pressure() >= BOT_TOXINS_COLD_KPA

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
	bot_log(bot, "TOXINS: no valve or no trigger to be had")
	return GOAL_STEP_FAIL

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
#undef BOT_TOXINS_BURN_KPA
#undef BOT_TOXINS_PLASMA_SHARE
#undef BOT_TOXINS_LIGHT_AT
#undef BOT_TOXINS_HOT_KPA
#undef BOT_TOXINS_COLD_KPA
#undef BOT_TOXINS_FREEZER_SET
#undef BOT_TOXINS_CHILL_LIMIT
#undef BOT_TOXINS_COLD_ENOUGH
#undef BOT_TOXINS_FUSE
#undef BOT_TOXINS_TRIES
