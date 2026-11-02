// Starting the supermatter: the engine on every map but Hippie Station and Ministation, and the reason a crew on one of
// them used to lose its power half an hour in, with nobody able to call the shuttle from a dark bridge.
//
// The order is the Guide to the Supermatter's, and the same on every map, whatever its pipes look like:
//  1. nitrogen on the loop: the canisters standing on a connector get wrenched down, and the pumps beside them opened up.
//     Delta keeps its own in atmospherics with the ports empty, so those get dragged round first.
//  2. the loop running: every pump on it switched on and turned right up, every filter too, and the bypasses shut.
//  3. the chamber's own air, at its air alarm: the scrubbers siphoning over their widest range, and no pressure limit on
//     the vents. Left alone the vents stop at one atmosphere and the scrubbers leave nitrogen where it is, so nothing
//     moves in there: the loop can be running perfectly with the crystal cooking in its own waste heat.
//  4. the collectors ready: a plasma tank from the dispenser in each, and each one switched on
//  5. and only then the emitters. Nothing starts the crystal but the emitters (and fools), so nothing here can get ahead
//     of the cooling: engine_room_ready() won't let them fire until 1 to 4 are done.
// Then everybody stays away from it (bot_hazards.dm). A crystal with its cooling running looks after itself.

/// How far from the crystal its pipes and machinery go. Atmospherics next door stays out of it.
#define BOT_SM_REACH 22
/// Collectors that want to be running before the crystal is lit. Some can be out of reach.
#define BOT_SM_COLLECTORS_NEEDED 4
/// As many as the maps with fewest have, and those hold. A fourth can be out of reach behind the others' beams once they fire.
#define BOT_SM_EMITTERS_NEEDED 3
/// Two canisters are what every other map starts with on its ports, and what the cooling has been seen to hold on.
#define BOT_SM_CANISTERS_WANTED 2
/// How far off a spare canister is still worth dragging over.
#define BOT_SM_HAUL_REACH 45

/// The pumps on the cooling loop, by the names the maps give them. "External Gas to Loop" is the pair right beside the
/// nitrogen ports: with those shut the canisters are wrenched down and none of it gets anywhere. Nothing with "Atmos" in
/// it: those are for feeding the loop from elsewhere. "Freezer Bypass" is the way past freezers nobody has switched on,
/// not one of the bypasses in sm_bypass_to_shut().
GLOBAL_LIST_INIT(bot_sm_loop_pumps, list(
	"Gas to Cooling Loop", "Cooling Loop to Gas", "Gas to Cold Loop", "Cold Loop to Gas", "Gas to Filter", "Gas to Chamber",
	"Gas to Mix", "Mix to Gas", "Input Toggle", "Output Toggle", "Waste to Filter", "Filter to Gas", "Gas to Loop",
	"Hot to Cold Loop", "Filtered Loop to Chamber", "Filter to Freezer", "Freezer Return", "Freezer Bypass", "Cooling to Unfiltered",
	"External Gas to Loop", "Thermo to Gas",
))

/// The crystal this bot could be setting up: the station's engine, on a map with no tesla to start instead.
/datum/bot_brain/proc/station_crystal()
	var/obj/machinery/power/supermatter_crystal/S = GLOB.main_supermatter_engine
	if(QDELETED(S) || S.z != owner.z)
		return null
	// By the accelerator, not the tesla generator: that's used up when the ball forms, and engineers on Hippie Station
	// would then have gone and lit the crystal as well. Anywhere on the level, not find_pa_console(), which only looks
	// as far as this bot can reach: an engineer standing by the crystal took it for a supermatter map and pumped the
	// chamber out, and an unused crystal in a vacuum wears away until it delaminates on its own.
	for(var/obj/machinery/particle_accelerator/control_box/console as anything in bot_instances_of(/obj/machinery/particle_accelerator/control_box))
		if(!QDELETED(console) && console.z == S.z)
			return null
	return S

/datum/bot_brain/proc/sm_part_free(atom/A)
	return !is_failed_engine_part(A) && !taken_by_another(A)

/// Atmospherics next door is /area/engine as well.
/datum/bot_brain/proc/sm_in_engine_room(atom/A)
	var/area/room = get_area(A)
	return istype(room, /area/engine) && !istype(room, /area/engine/atmos)

/// With strict, whatever's left to do. Without, what somebody could go and do about it right now.
/datum/bot_brain/proc/sm_canister_to_connect(obj/machinery/power/supermatter_crystal/S, strict = FALSE)
	for(var/obj/machinery/portable_atmospherics/canister/nitrogen/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister/nitrogen))
		if(QDELETED(C) || C.connected_port || C.z != S.z || get_dist(S, C) > BOT_SM_REACH || !(strict || sm_part_free(C)))
			continue
		if(locate(/obj/machinery/atmospherics/components/unary/portables_connector) in C.loc)
			return C
	return null

/// Nitrogen the loop can draw on.
/datum/bot_brain/proc/sm_nitrogen_on_loop(obj/machinery/power/supermatter_crystal/S)
	for(var/obj/machinery/portable_atmospherics/canister/nitrogen/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister/nitrogen))
		if(!QDELETED(C) && C.connected_port && C.z == S.z && get_dist(S, C) <= BOT_SM_REACH)
			return TRUE
	return FALSE

/// An empty port with a pump beside it onto the loop, which rules out the ones that only collect what the filters take.
/datum/bot_brain/proc/sm_free_port(obj/machinery/power/supermatter_crystal/S)
	for(var/obj/machinery/atmospherics/components/unary/portables_connector/C as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/portables_connector))
		if(C.z != S.z || get_dist(S, C) > BOT_SM_REACH || C.connected_device || !sm_in_engine_room(C))
			continue
		if(locate(/obj/machinery/portable_atmospherics) in C.loc)
			continue
		for(var/obj/machinery/atmospherics/components/binary/pump/P in orange(1, C))
			if(sm_loop_pump(P))
				return C
	return null

/// The nearest spare nitrogen, when the ports are short of it.
/datum/bot_brain/proc/sm_canister_to_haul(obj/machinery/power/supermatter_crystal/S)
	var/on_ports = 0
	var/obj/machinery/portable_atmospherics/canister/nitrogen/best
	for(var/obj/machinery/portable_atmospherics/canister/nitrogen/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister/nitrogen))
		if(QDELETED(C) || C.z != S.z || get_dist(S, C) > BOT_SM_HAUL_REACH)
			continue
		if(C.connected_port || (locate(/obj/machinery/atmospherics/components/unary/portables_connector) in C.loc))
			if(get_dist(S, C) <= BOT_SM_REACH)
				on_ports++
			continue
		if(sm_part_free(C) && (!best || get_dist(owner, C) < get_dist(owner, best)))
			best = C
	return on_ports < BOT_SM_CANISTERS_WANTED && sm_free_port(S) ? best : null

/// A pump nobody named is one that matters: Pubby's between the nitrogen ports and the loop, and the chamber's way out.
/datum/bot_brain/proc/sm_loop_pump(obj/machinery/atmospherics/components/binary/pump/P)
	return (P.name in GLOB.bot_sm_loop_pumps) || (P.name == initial(P.name) && sm_in_engine_room(P))

/datum/bot_brain/proc/sm_pump_to_set(obj/machinery/power/supermatter_crystal/S, strict = FALSE)
	for(var/obj/machinery/atmospherics/components/binary/pump/P as anything in bot_instances_of(/obj/machinery/atmospherics/components/binary/pump))
		if(P.z != S.z || get_dist(S, P) > BOT_SM_REACH || !sm_loop_pump(P) || !(strict || sm_part_free(P)))
			continue
		if(!P.on || P.target_pressure < MAX_OUTPUT_PRESSURE)
			return P
	return null

/// A bypass left open sends the cold gas round the chamber instead of through it. Only Pubby's "Chamber Bypass" starts on.
/datum/bot_brain/proc/sm_bypass_to_shut(obj/machinery/power/supermatter_crystal/S, strict = FALSE)
	for(var/obj/machinery/atmospherics/components/binary/pump/P as anything in bot_instances_of(/obj/machinery/atmospherics/components/binary/pump))
		if(P.on && P.z == S.z && get_dist(S, P) <= BOT_SM_REACH && findtext(P.name, "Bypass") && !sm_loop_pump(P) && (strict || sm_part_free(P)))
			return P
	return null

/datum/bot_brain/proc/sm_filter_to_set(obj/machinery/power/supermatter_crystal/S, strict = FALSE)
	for(var/obj/machinery/atmospherics/components/trinary/filter/F as anything in bot_instances_of(/obj/machinery/atmospherics/components/trinary/filter))
		if(F.z != S.z || get_dist(S, F) > BOT_SM_REACH || !sm_in_engine_room(F) || !(strict || sm_part_free(F)))
			continue
		if(!F.on || F.transfer_rate < MAX_TRANSFER_RATE)
			return F
	return null

/// Whether the chamber's vents and scrubbers are as step 3 wants them, going by what its air alarm shows.
/datum/bot_brain/proc/sm_chamber_air_set(obj/machinery/power/supermatter_crystal/S)
	var/area/chamber = get_area(S)
	for(var/id_tag in chamber.air_scrub_names)
		var/list/scrubber = chamber.air_scrub_info[id_tag]
		if(!scrubber || scrubber["scrubbing"] || !scrubber["widenet"])
			return FALSE
	for(var/id_tag in chamber.air_vent_names)
		var/list/vent = chamber.air_vent_info[id_tag]
		if(!vent || vent["checks"])
			return FALSE
	return TRUE

/datum/bot_brain/proc/sm_alarm_to_set(obj/machinery/power/supermatter_crystal/S)
	if(sm_chamber_air_set(S))
		return null
	var/area/chamber = get_area(S)
	for(var/obj/machinery/airalarm/A as anything in bot_instances_of(/obj/machinery/airalarm))
		if(A.z == S.z && get_area(A) == chamber && sm_part_free(A))
			return A
	return null

/datum/bot_brain/proc/sm_collector_to_load(obj/machinery/power/supermatter_crystal/S)
	for(var/obj/machinery/power/rad_collector/C as anything in bot_instances_of(/obj/machinery/power/rad_collector))
		if(C.z == S.z && C.anchored && !C.loaded_tank && get_dist(S, C) <= BOT_SM_REACH && sm_part_free(C))
			return C
	return null

/datum/bot_brain/proc/sm_collector_to_start(obj/machinery/power/supermatter_crystal/S)
	for(var/obj/machinery/power/rad_collector/C as anything in bot_instances_of(/obj/machinery/power/rad_collector))
		if(C.z == S.z && C.anchored && C.loaded_tank && !C.active && !C.locked && get_dist(S, C) <= BOT_SM_REACH && sm_part_free(C))
			return C
	return null

/datum/bot_brain/proc/sm_tank_dispenser(obj/machinery/power/supermatter_crystal/S)
	for(var/obj/structure/tank_dispenser/D as anything in bot_instances_of(/obj/structure/tank_dispenser))
		if(!QDELETED(D) && D.z == S.z && D.plasmatanks > 0 && get_dist(S, D) <= BOT_SM_REACH + 10)
			return D
	return null

/// The safety interlock: the loop running and enough collectors on. A part nobody could reach still counts against it. A
/// crew that can't finish leaves the crystal dark and the station on its batteries for an hour, and one lit with the
/// cooling half done lasted under ten minutes in the first trial.
/datum/bot_brain/proc/engine_room_ready(obj/machinery/power/supermatter_crystal/S)
	if(!sm_nitrogen_on_loop(S) || !sm_chamber_air_set(S))
		return FALSE
	if(sm_pump_to_set(S, TRUE) || sm_bypass_to_shut(S, TRUE) || sm_filter_to_set(S, TRUE) || sm_canister_to_connect(S, TRUE))
		return FALSE
	var/on = 0
	var/loop_pumps = 0
	for(var/obj/machinery/atmospherics/components/binary/pump/P as anything in bot_instances_of(/obj/machinery/atmospherics/components/binary/pump))
		if(P.z == S.z && get_dist(S, P) <= BOT_SM_REACH && (P.name in GLOB.bot_sm_loop_pumps) && P.on)
			loop_pumps++
	for(var/obj/machinery/power/rad_collector/C as anything in bot_instances_of(/obj/machinery/power/rad_collector))
		if(C.z == S.z && C.active && get_dist(S, C) <= BOT_SM_REACH)
			on++
	return loop_pumps >= 2 && on >= BOT_SM_COLLECTORS_NEEDED

/datum/bot_brain/proc/sm_emitter_to_fire(obj/machinery/power/supermatter_crystal/S)
	if(!engine_room_ready(S))
		return null
	var/firing = 0
	var/obj/machinery/power/emitter/anchored/next
	for(var/obj/machinery/power/emitter/anchored/E as anything in bot_instances_of(/obj/machinery/power/emitter/anchored))
		if(E.z != S.z || get_dist(S, E) > BOT_SM_REACH)
			continue
		if(E.active)
			firing++
		else if(!next && sm_part_free(E))
			next = E
	return firing < BOT_SM_EMITTERS_NEEDED ? next : null

/// The next job on the list, in the guide's order, or null if there's nothing left.
/datum/bot_brain/proc/next_sm_job(obj/machinery/power/supermatter_crystal/S)
	. = sm_canister_to_connect(S) || sm_canister_to_haul(S)
	if(.)
		return
	// Nothing else until there's nitrogen to work with: step 3 pumps the chamber out, and with nothing coming in to replace
	// what's taken the crystal sits in a vacuum, which wears it down lit or not. Delta lost half its integrity like that.
	if(!sm_nitrogen_on_loop(S))
		return null
	. = sm_pump_to_set(S) || sm_bypass_to_shut(S) || sm_filter_to_set(S) || sm_alarm_to_set(S)
	if(.)
		return
	if(sm_collector_to_load(S))
		return find_carried_tool(/obj/item/tank/internals/plasma) ? sm_collector_to_load(S) : sm_tank_dispenser(S)
	return sm_collector_to_start(S) || sm_emitter_to_fire(S)

/datum/bot_duty/supermatter
	name = "starting the supermatter"
	jobs = list("Station Engineer", "Chief Engineer")
	priority = 40
	interval_min = 100
	interval_max = 250

/datum/bot_duty/supermatter/try_start(datum/bot_brain/bot)
	var/obj/machinery/power/supermatter_crystal/S = bot.station_crystal()
	return S && bot.next_sm_job(S) ? bot.assign_goal(new /datum/bot_goal/setup_supermatter()) : FALSE

/datum/bot_brain/proc/continue_supermatter_round()
	var/datum/bot_duty/supermatter/duty = bot_duty_of(/datum/bot_duty/supermatter)
	continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), src))

/datum/bot_goal/setup_supermatter
	lawful = TRUE
	exclusive = TRUE
	doing = "setting up the engine"

/datum/bot_goal/setup_supermatter/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/power/supermatter_crystal/S = bot.station_crystal()
	target = S ? bot.next_sm_job(S) : null

/datum/bot_goal/setup_supermatter/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/setup_supermatter/S = new
	if(istype(target, /obj/machinery/power/emitter))
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/stand_clear_of_emitter(), new /datum/bot_step/sm_work())
	else if(istype(target, /obj/machinery/portable_atmospherics/canister) && !(locate(/obj/machinery/atmospherics/components/unary/portables_connector) in target.loc))
		var/obj/machinery/power/supermatter_crystal/crystal = bot.station_crystal()
		var/obj/machinery/atmospherics/components/unary/portables_connector/port = crystal ? bot.sm_free_port(crystal) : null
		if(!port)
			return list()
		var/datum/bot_step/move_to/to_port = new
		to_port.step_target = get_turf(port)
		var/datum/bot_step/sm_let_go_on_port/let_go = new
		let_go.port_tile = get_turf(port)
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/sm_take_hold(), to_port, new /datum/bot_step/move_to/step_off(), let_go)
	else
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/sm_work())
	return list(S)

/datum/bot_goal/setup_supermatter/on_success(datum/bot_brain/bot)
	bot.continue_supermatter_round()

/datum/bot_goal/setup_supermatter/on_give_up(datum/bot_brain/bot)
	if(bot.owner.pulling == target)
		bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/setup_supermatter/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/sm_take_hold/execute(datum/bot_brain/bot)
	var/atom/movable/A = bot.current_goal?.target
	if(QDELETED(A) || !bot.owner.Adjacent(A))
		return GOAL_STEP_FAIL
	bot.human_pause(A)
	if(QDELETED(A) || !bot.owner.Adjacent(A))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(A)
	bot.telemetry_event("pull", list("target" = "[A]"))
	bot.owner.start_pulling(A)
	return bot.owner.pulling == A ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// What's being dragged lands where the bot just was, so standing on the port leaves it a tile short. One step further on.
/datum/bot_step/move_to/step_off/execute(datum/bot_brain/bot)
	var/turf/here = get_turf(bot.owner)
	var/turf/behind = get_turf(bot.owner.pulling)
	step_target = null
	for(var/direction in GLOB.cardinals)
		var/turf/T = get_step(here, direction)
		if(T != behind && !is_blocked_turf(T, TRUE) && !isspaceturf(T))
			step_target = T
			break
	return step_target ? ..() : GOAL_STEP_FAIL

/datum/bot_step/sm_let_go_on_port
	var/turf/port_tile

/datum/bot_step/sm_let_go_on_port/execute(datum/bot_brain/bot)
	var/atom/movable/A = bot.current_goal?.target
	bot.owner.stop_pulling()
	if(QDELETED(A) || A.loc != port_tile)
		return GOAL_STEP_FAIL
	bot_log(bot, "left [A] on the port")
	return GOAL_STEP_SUCCESS

/// Whatever the job at this machine is.
/datum/bot_step/sm_work/execute(datum/bot_brain/bot)
	var/atom/A = bot.current_goal?.target
	if(QDELETED(A) || !bot.owner.Adjacent(A))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(A)
	bot.human_pause(A)
	if(QDELETED(A) || !bot.owner.Adjacent(A))
		return GOAL_STEP_FAIL
	if(istype(A, /obj/machinery/portable_atmospherics/canister))
		var/obj/machinery/portable_atmospherics/canister/C = A
		var/obj/item/wrench/W = bot.find_or_transform_tool(/obj/item/wrench)
		if(!W)
			return bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(/obj/item/wrench)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		bot.use_item_on(W, C)
		return C.connected_port ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(istype(A, /obj/machinery/atmospherics/components/binary/pump))
		var/obj/machinery/atmospherics/components/binary/pump/P = A
		if(!bot.sm_loop_pump(P))
			bot.telemetry_ui_action(P, "off")
			P.on = FALSE
			P.update_icon()
			bot_log(bot, "shut [P]")
			return GOAL_STEP_SUCCESS
		bot.telemetry_ui_action(P, "on and maxed")
		P.on = TRUE
		P.target_pressure = MAX_OUTPUT_PRESSURE
		P.update_icon()
		bot_log(bot, "maxed out [P]")
		return GOAL_STEP_SUCCESS
	if(istype(A, /obj/machinery/atmospherics/components/trinary/filter))
		var/obj/machinery/atmospherics/components/trinary/filter/F = A
		bot.telemetry_ui_action(F, "on and maxed")
		F.on = TRUE
		F.transfer_rate = MAX_TRANSFER_RATE
		F.update_icon()
		bot_log(bot, "turned up [F]")
		return GOAL_STEP_SUCCESS
	if(istype(A, /obj/machinery/airalarm))
		var/obj/machinery/airalarm/alarm = A
		var/area/chamber = get_area(alarm)
		bot.telemetry_ui_action(alarm, "siphon the chamber, vent limits off")
		for(var/id_tag in chamber.air_scrub_names)
			alarm.send_signal(id_tag, list("scrubbing" = 0), bot.owner)
			alarm.send_signal(id_tag, list("widenet" = 1), bot.owner)
		for(var/id_tag in chamber.air_vent_names)
			alarm.send_signal(id_tag, list("checks" = 0), bot.owner)
		bot_log(bot, "set the scrubbers in [chamber] to siphon and took the limit off its vents")
		return GOAL_STEP_SUCCESS
	if(istype(A, /obj/structure/tank_dispenser))
		var/obj/structure/tank_dispenser/D = A
		var/obj/item/tank/internals/plasma/tank = locate() in D
		if(!tank)
			return GOAL_STEP_FAIL
		bot.make_hand_free()
		bot.telemetry_ui_action(D, "take a plasma tank")
		if(!bot.owner.put_in_hands(tank))
			return GOAL_STEP_FAIL
		D.plasmatanks--
		D.update_icon()
		return GOAL_STEP_SUCCESS
	if(istype(A, /obj/machinery/power/rad_collector))
		var/obj/machinery/power/rad_collector/C = A
		if(!C.loaded_tank)
			var/obj/item/tank/internals/plasma/tank = bot.find_carried_tool(/obj/item/tank/internals/plasma)
			if(!tank)
				return GOAL_STEP_FAIL
			bot.use_tool_on(tank, C)
			return C.loaded_tank ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
		bot.use_atom(C)
		bot_log(bot, "switched on [C]")
		return C.active ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(istype(A, /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/E = A
		var/obj/machinery/power/supermatter_crystal/S = bot.station_crystal()
		if(!S || !bot.engine_room_ready(S))
			return GOAL_STEP_FAIL //something has been switched off since this was picked: not with the cooling down
		if(!E.powernet && !E.connect_to_network())
			bot_log(bot, "[E] has no cable to run on")
			return GOAL_STEP_FAIL
		bot.telemetry_ui_action(E, "switch on")
		E.locked = FALSE
		E.active = TRUE
		E.shot_number = 0
		E.fire_delay = E.maximum_fire_delay
		E.update_icon()
		bot_log(bot, "fired up [E]")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

#undef BOT_SM_REACH
#undef BOT_SM_COLLECTORS_NEEDED
#undef BOT_SM_EMITTERS_NEEDED
#undef BOT_SM_CANISTERS_WANTED
#undef BOT_SM_HAUL_REACH
