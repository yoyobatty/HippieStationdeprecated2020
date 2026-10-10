// Internals tank refilling: a Station Engineer/Chief Engineer/Atmospheric Technician
// keeps an eye on its own internals tank and tops it back up from a nearby oxygen
// canister once it's run down - confirmed as a real gap in-game: a bot spends real time
// firefighting/EVA work breathing from a fixed-size tank and, with nothing watching its
// level, just runs it dry mid-task.
//
// "Half empty" is tracked per-tank rather than against a hardcoded pressure - different
// tank types fill to very different pressures at spawn (a standard oxygen tank populates
// to 6 atmospheres, tank_types.dm; the small "emergency oxygen" tank populates to 10
// atmospheres despite holding far fewer actual moles, since its volume is tiny) - a fixed
// threshold would either refill a standard tank way too early or an emergency tank way
// too late. Instead this remembers the highest pressure it's ever seen THIS specific tank
// at (reset the moment the tank itself changes, e.g. after a real refill or a fresh one
// equipped) and treats that as "full" for comparison.
//
// The actual refill mechanic mirrors exactly what a real player does (portable_
// atmospherics.dm/canister.dm): click the canister with the tank to insert it
// (attackby()), open its valve (ui_act() "valve" toggles valve_open, which process_atmos()
// then pumps gas through every tick while it's set), wait for the transfer, then pull the
// tank back out (replace_tank(), which also closes the valve in the same call).

/datum/bot_brain/proc/is_tank_refill_job()
	return is_eva_job()

// Oxygen specifically, NOT the general "air" canister (~79% N2/21% O2) - breathing is
// gated on O2 PARTIAL pressure (check_breath(), life.dm: O2_partialpressure = O2_fraction
// * breath_pressure, compared against safe_oxy_min), not total tank pressure, so a tank
// full of diluted air delivers only ~1/5th the oxygen a pure-O2 tank does at the exact
// same distribute_pressure setting. It's not unsafe by definition - cranking distribute_
// pressure up enough would compensate - but this system doesn't touch that setting at
// all, it only maxes the CANISTER's release pressure to fill fast (below). Sticking to
// pure oxygen sidesteps needing that math entirely: whatever distribute_pressure the tank
// already had (calibrated for near-100% O2 to begin with) stays correct after a refill.
/datum/bot_brain/proc/is_oxygen_canister(obj/machinery/portable_atmospherics/canister/C)
	return istype(C, /obj/machinery/portable_atmospherics/canister/oxygen)

// "if it's a viable thing to do" - a bot has no business pulling its own tank out of
// commission (and briefly breathing nothing at all - internal gets nulled the instant
// the tank's loc leaves the mob, life.dm's get_breath_from_internal(), same gap
// equip_eva_gear's own tank-fetch step already has to work around) while standing
// somewhere that actually needs it. Reuses the exact same hazard signals needs_mag_
// pulse() (gear_up_eva.dm) already checks for a different reason - no gravity or a
// hull-breach-grade low pressure both mean "don't take your tank off right now."
/datum/bot_brain/proc/safe_to_refill_tank()
	var/turf/T = get_turf(owner)
	if(!T)
		return FALSE
	if(!owner.has_gravity())
		return FALSE
	if(!istype(T, /turf/open))
		return FALSE
	var/turf/open/O = T
	var/datum/gas_mixture/environment = O.return_air()
	if(!environment || environment.return_pressure() < HAZARD_LOW_PRESSURE)
		return FALSE
	return TRUE

// Resets the moment the tank object itself changes (a real refill, or swapping to a
// freshly-fetched one) - the remembered "full" pressure only ever means anything for
// the CURRENT physical tank, not whatever was worn before it.
/datum/bot_brain/proc/tank_needs_refill()
	var/obj/item/tank/internals/tank = eva_tank()
	if(!istype(tank))
		return FALSE
	if(tank != last_seen_internals_tank)
		last_seen_internals_tank = tank
		internals_tank_max_pressure_seen = 0
	var/pressure = tank.air_contents.return_pressure()
	if(pressure > internals_tank_max_pressure_seen)
		internals_tank_max_pressure_seen = pressure
		return FALSE //just saw a new high (freshly filled, or the first read) - not low by definition
	if(!internals_tank_max_pressure_seen)
		return FALSE //nothing to compare against yet
	return pressure < (internals_tank_max_pressure_seen * 0.5)

/// The pressure a refill stops at: back above the halfway mark that sent the bot here, with a little headroom so it
/// doesn't qualify as low again the moment it's put back on
/datum/bot_brain/proc/tank_refill_target()
	return internals_tank_max_pressure_seen * 0.6

/datum/bot_brain/proc/find_oxygen_canister()
	var/turf/bot_turf = get_turf(owner)
	// A canister only fills a tank up to about its own pressure (release_gas_to() needs a 10 kPa gradient), so one below
	// the target could never finish the job - the bot used to stand at it forever with its tank inside
	var/min_pressure = max(ONE_ATMOSPHERE * 2, tank_refill_target() + 20)
	var/obj/machinery/portable_atmospherics/canister/best
	var/best_dist
	for(var/obj/machinery/portable_atmospherics/canister/C in GLOB.machines)
		if(!is_oxygen_canister(C))
			continue
		if((C.stat & BROKEN) || C.holding)
			continue //already got someone/something else's tank in it
		var/turf/T = get_turf(C)
		if(!T || T.z != owner.z)
			continue
		if(C.air_contents.return_pressure() < min_pressure)
			continue //not worth the trip - it couldn't fill the tank to the target
		// The nearest canister used to be picked every time, reachable or not: one bot gave up on the same one 22 times
		// running. One that just didn't work out is left alone for a while, and one standing somewhere the tank can't
		// come off (fill_tank_from_canister checks safe_to_refill_tank() on arrival) isn't worth the walk at all.
		var/retry_at = LAZYACCESS(failed_refill_canisters, C)
		if(retry_at && world.time < retry_at)
			continue
		if(!turf_air_is_breathable(T))
			continue
		var/dist = get_dist(bot_turf, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/datum/bot_brain/proc/try_refill_internals_round()
	if(try_retrieve_stranded_tank())
		return TRUE
	// Not gated on safe_to_refill_tank() here any more: that asks whether the tank can come off where the bot is
	// standing NOW, so a bot out in space never even set off for a canister - and out in space is exactly where a
	// low tank matters. The step that takes the tank off checks it at the canister, where it counts.
	if(!is_tank_refill_job() || !tank_needs_refill())
		return FALSE
	return assign_goal(new /datum/bot_goal/refill_internals())

/// A refill that got cut short after the tank went in (knocked away from the canister, a fight, somewhere turning unsafe)
/// leaves the tank sitting in it - go back for it, as a player would, rather than leave it and run around tankless
/datum/bot_brain/proc/try_retrieve_stranded_tank()
	var/datum/bot_goal/refill_internals/retrieve = make_stranded_tank_goal()
	return retrieve ? assign_goal(retrieve) : FALSE

/// A goal to go take a stranded tank back out of its canister, or null if there's none to fetch (or it isn't safe to)
/datum/bot_brain/proc/make_stranded_tank_goal()
	var/obj/item/tank/internals/tank = stranded_refill_tank?.resolve()
	var/obj/machinery/portable_atmospherics/canister/C = tank?.loc
	if(!istype(C) || C.holding != tank)
		stranded_refill_tank = null // someone else took it out, or it's gone
		return null
	if(!safe_to_refill_tank())
		return null
	var/datum/bot_goal/refill_internals/retrieve = new
	retrieve.tank = tank
	retrieve.retrieve_only = TRUE
	return retrieve

/// Pulls the tank out of the canister (closing its valve) and puts it back on. TRUE if the bot has it again - its
/// valve only gets opened if the air here calls for it (manage_internals()).
/datum/bot_brain/proc/take_back_refill_tank(obj/machinery/portable_atmospherics/canister/C, obj/item/tank/internals/tank)
	if(C.holding == tank)
		C.replace_tank(owner, TRUE) //pulls the tank back out AND closes the valve
	if(tank.loc != owner)
		owner.put_in_hands(tank)
	if(tank.loc != owner)
		return FALSE
	stranded_refill_tank = null
	manage_internals()
	return TRUE

// Same immediate-rechain idea as continue_fire_response_round() (respond_to_fire.dm) -
// re-checks are cheap and this only ever actually does anything when genuinely low.
/datum/bot_brain/proc/continue_refill_internals_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_refill_internals_round)))

/datum/bot_goal/refill_internals
	/// The tank being refilled. Kept here because owner.internal is cleared the moment it goes into the canister - the
	/// step used to re-read owner.internal on its next cycle, find nothing, give up and walk off leaving the tank inside
	var/obj/item/tank/internals/tank
	/// Just going back to take a tank out of the canister a cut-short refill left it in (try_retrieve_stranded_tank())
	var/retrieve_only = FALSE
	/// The tank's pressure when it last rose, and when - a transfer that's stopped rising has gone as far as it will
	var/last_pressure = 0
	var/last_progress_time = 0

/datum/bot_goal/refill_internals/resolve_target(datum/bot_brain/bot)
	if(retrieve_only)
		target = tank?.loc
		return
	target = bot.find_oxygen_canister()

/datum/bot_goal/refill_internals/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/refill_internals())

/datum/bot_goal/refill_internals/on_success(datum/bot_brain/bot)
	bot.continue_refill_internals_round()

// No cooldown on giving up, same reasoning as fight_fire's goal - a canister that's genuinely out of reach just gets
// re-evaluated fresh next cycle rather than needing a dedicated blacklist. But a tank still in the canister is remembered,
// and try_refill_internals_round() sends the bot back for it before anything else.
/datum/bot_goal/refill_internals/on_give_up(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/C = tank?.loc
	if(istype(C) && C.holding == tank)
		bot.stranded_refill_tank = WEAKREF(tank)
		bot_log(bot, "had to leave [tank] in [C] - will come back for it")
	else if(target && !retrieve_only)
		LAZYSET(bot.failed_refill_canisters, target, world.time + rand(1200, 1800)) //try a different one next - see find_oxygen_canister()

/datum/bot_strategy/refill_internals/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/fill_tank_from_canister())

/datum/bot_strategy/refill_internals/is_feasible(datum/bot_brain/bot)
	return TRUE

// One step start-to-finish (insert, open valve, wait, close valve, retrieve, re-don) -
// PENDING while the transfer is still running, same idiom the tesla engine's tool-use
// steps already use for a multi-tick real interaction rather than splitting an
// inherently continuous action across several separate step types.
/datum/bot_step/fill_tank_from_canister/execute(datum/bot_brain/bot)
	var/datum/bot_goal/refill_internals/goal = bot.current_goal
	var/obj/machinery/portable_atmospherics/canister/C = goal?.target
	if(!istype(goal) || !istype(C) || QDELETED(C))
		return GOAL_STEP_FAIL
	if(!goal.tank)
		goal.tank = bot.eva_tank()
	var/obj/item/tank/internals/tank = goal.tank
	if(!istype(tank) || QDELETED(tank))
		bot_log(bot, "no internals tank to refill anymore")
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL // on_give_up() remembers the tank if it's still inside

	if(goal.retrieve_only || (C.holding == tank && !bot.safe_to_refill_tank()))
		if(!bot.take_back_refill_tank(C, tank))
			bot_log(bot, "[C] wouldn't give [tank] back")
			return GOAL_STEP_FAIL
		bot_log(bot, goal.retrieve_only ? "came back for [tank] and put it back on" : "took [tank] back out of [C] - somewhere unsafe to be without it")
		return goal.retrieve_only ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(!bot.safe_to_refill_tank())
		bot_log(bot, "somewhere unsafe to swap my tank now - abandoning the refill")
		return GOAL_STEP_FAIL

	// Not already sitting in the canister from an earlier PENDING cycle - go insert it.
	if(C.holding != tank)
		if(C.holding)
			bot_log(bot, "[C] already has a tank in it - can't refill from here")
			return GOAL_STEP_FAIL
		bot.owner.internal = null //about to leave the mob's inventory anyway (life.dm nulls this the instant it does) - clear it up front rather than let a stray life tick do it
		bot.owner.update_internals_hud_icon(0)
		if(tank.loc != bot.owner)
			bot.try_pickup_target(tank)
		if(tank.loc != bot.owner)
			bot_log(bot, "couldn't get [tank] into my hands to refill it")
			return GOAL_STEP_FAIL
		bot.use_tool_on(tank, C) //insert it the way a player does: click the canister with the tank in hand
		if(C.holding != tank)
			bot_log(bot, "[C] wouldn't accept [tank]")
			return GOAL_STEP_FAIL
		bot_log(bot, "inserted [tank] into [C] to refill it")
		goal.last_pressure = tank.air_contents.return_pressure()
		goal.last_progress_time = world.time

	// Max release pressure, not whatever it was already set to - confirmed in-game: left
	// at the canister's default (often just above standard atmospheric), the transfer was
	// so slow it never actually finished filling anything. A real player refilling their
	// own tank cranks the canister to max first for exactly this reason.
	if(C.release_pressure < C.can_max_release_pressure)
		C.release_pressure = C.can_max_release_pressure
	if(!C.valve_open)
		C.valve_open = TRUE
		C.update_icon()

	// Fill it up, as a player does: until it's back to full, or the canister stops pushing any more in (it only fills to
	// about its own pressure). Waiting for a fixed target the canister couldn't reach kept the bot there forever.
	var/pressure = tank.air_contents.return_pressure()
	if(pressure < bot.internals_tank_max_pressure_seen)
		if(pressure > goal.last_pressure + 1)
			goal.last_pressure = pressure
			goal.last_progress_time = world.time
		if(world.time < goal.last_progress_time + 5 SECONDS)
			// Nothing re-runs a PENDING step on its own - this never came back, so the bot stood there forever with its
			// tank in the canister. Check again shortly, the way self_treat and the other waiting steps do.
			addtimer(CALLBACK(src, PROC_REF(continue_fill), bot, goal, C, tank), 1 SECONDS)
			return GOAL_STEP_PENDING
		bot_log(bot, "[C] stopped filling [tank] at [round(pressure)] kPa")

	if(!bot.take_back_refill_tank(C, tank))
		bot_log(bot, "[C] wouldn't give [tank] back")
		return GOAL_STEP_FAIL
	bot_log(bot, "refilled [tank] from [C] to [round(pressure)] kPa and put it back on")
	return GOAL_STEP_SUCCESS

/datum/bot_step/fill_tank_from_canister/proc/continue_fill(datum/bot_brain/bot, datum/bot_goal/refill_internals/goal, obj/machinery/portable_atmospherics/canister/C, obj/item/tank/internals/tank)
	if(QDELETED(bot))
		return
	if(bot.state != BOT_STATE_GOAL || bot.current_goal != goal || bot.current_strategy?.steps?[bot.current_step_index] != src)
		// The goal was dropped some other way (a fight, a patrol taking over) with the tank still filling - remember it
		if(!QDELETED(C) && C.holding == tank)
			bot.stranded_refill_tank = WEAKREF(tank)
		return
	var/result = execute(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

// ============================================================
// Minding the air supply
// ============================================================
// A bot used to open its tank's valve when it suited up and never close it again. The tank the suit
// storage units hand out is a small one - about nine and a half minutes - so every suited bot collapsed
// at around 9:40 and was dead by 15:00, indoors as readily as out: helmet on, breathing from an empty
// tank in a room full of air (Bot Shift, 2026-10-04 - every engineer and atmospheric technician, every
// 30 minute run). A player keeps the valve shut inside, opens it at the airlock, watches the gauge
// while out, and turns back for a refill while there's still enough left to get home on.

/// Below this share of what the tank has held, with nowhere to refill: stop everything and get to air.
#define BOT_TANK_RUNNING_OUT 0.25
/// A valve that was just opened stays open at least this long, so walking along a row of windows doesn't flick it on and off.
#define BOT_INTERNALS_MIN_OPEN (5 SECONDS)
/// How far to look for air when the tank is running out.
#define BOT_AIR_SEARCH_RANGE 30

/datum/bot_brain
	var/next_air_check_time = 0
	/// When the bot will next break off what it's doing over a low tank - a trip that didn't work out isn't retried at once.
	var/next_air_trip_time = 0
	var/internals_opened_at = 0
	/// Canister -> world.time before it's worth trying again, see find_oxygen_canister().
	var/list/failed_refill_canisters
	/// In good air with the tank nearly empty: no routes across space until it's refilled. Only out where the tank
	/// is all there is does a nearly empty one still get used - the way home runs through it.
	var/low_air_stay_in = FALSE

/// The tank this bot breathes from when it has to: the one whose valve is open, or else the fullest it's
/// carrying on its body, where the valve can be reached - not one buried in a bag.
/datum/bot_brain/proc/eva_tank()
	if(istype(owner.internal, /obj/item/tank/internals))
		return owner.internal
	var/obj/item/tank/internals/best
	for(var/obj/item/tank/internals/tank in owner)
		if(!best || tank.air_contents.return_pressure() > best.air_contents.return_pressure())
			best = tank
	return best

/// Could this bot breathe the air on T without coming to harm? Oxygen, plasma, CO2 and temperature against
/// its own lungs' limits, the ones check_breath() (lungs.dm) goes by.
/datum/bot_brain/proc/turf_air_is_breathable(turf/open/T)
	if(!istype(T))
		return FALSE
	var/datum/gas_mixture/air = T.return_air()
	var/total = air?.total_moles()
	if(!total)
		return FALSE
	var/obj/item/organ/lungs/lungs = owner.getorganslot(ORGAN_SLOT_LUNGS)
	if(!lungs)
		return FALSE
	var/per_mole = air.return_pressure() / total //partial pressure of a gas = its moles times this
	if(air.moles[/datum/gas/oxygen] * per_mole < lungs.safe_oxygen_min)
		return FALSE
	if(lungs.safe_toxins_max && air.moles[/datum/gas/plasma] * per_mole > lungs.safe_toxins_max)
		return FALSE
	if(lungs.safe_co2_max && air.moles[/datum/gas/carbon_dioxide] * per_mole > lungs.safe_co2_max)
		return FALSE
	return air.temperature > lungs.cold_level_1_threshold && air.temperature < lungs.heat_level_1_threshold

/datum/bot_brain/proc/air_is_breathable()
	return turf_air_is_breathable(get_turf(owner))

/// Opens the tank's valve where the bot can't breathe - or is a step from somewhere it can't
/// (needs_mag_pulse(), gear_up_eva.dm: no gravity, a breach, a fire, space next door) - and closes it again
/// where it can. On the tank's own switch (toggle_internals(), what the HUD button calls), so it needs a
/// mask the same as a player does.
/datum/bot_brain/proc/manage_internals()
	if(!is_eva_job())
		return
	var/need_tank = !air_is_breathable() || needs_mag_pulse()
	var/obj/item/tank/tank = owner.internal
	if(tank)
		if(need_tank || world.time < internals_opened_at + BOT_INTERNALS_MIN_OPEN)
			return
		tank.toggle_internals(owner)
		if(!owner.internal)
			bot_log(src, "the air's fine here - closed the valve on [tank] ([round(tank.air_contents.return_pressure())] kPa left)")
			telemetry_event("internals", list("tank" = "[tank]", "on" = FALSE, "kpa" = round(tank.air_contents.return_pressure())))
		return
	if(!need_tank)
		return
	tank = eva_tank()
	if(!tank)
		return
	tank.toggle_internals(owner)
	if(owner.internal == tank)
		internals_opened_at = world.time
		bot_log(src, "opened the valve on [tank] and started breathing from it ([round(tank.air_contents.return_pressure())] kPa)")
		telemetry_event("internals", list("tank" = "[tank]", "on" = TRUE, "kpa" = round(tank.air_contents.return_pressure())))

/// Down to a quarter of what this tank has held: enough to get indoors on, not to set out with.
/datum/bot_brain/proc/tank_running_out()
	var/obj/item/tank/internals/tank = eva_tank()
	if(!tank || tank != last_seen_internals_tank || !internals_tank_max_pressure_seen)
		return FALSE
	return tank.air_contents.return_pressure() < internals_tank_max_pressure_seen * BOT_TANK_RUNNING_OUT

/// Once a second, whatever else the bot is doing (process(), bot_brain.dm): the valve, and the gauge.
/// Breathing from a tank that's under half gone, it breaks off for a refill - pausing the goal in hand
/// the way a fetch for a tool does, to come back to. Under a quarter with nowhere to refill, nothing
/// else matters: it drops everything and makes for the nearest air.
/datum/bot_brain/proc/mind_air_supply()
	if(!is_eva_job())
		return
	manage_internals()
	if(gym_scripted)
		return //a Bot Gym bot minds its valve, but only runs the errands its scenario gives it
	var/low = tank_needs_refill() //also keeps track of what this tank holds when full
	low_air_stay_in = !owner.internal && tank_running_out()
	if(!owner.internal || !low)
		return //breathing the room's air, or plenty left
	if(world.time < next_air_trip_time || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST)
		return
	if(istype(current_goal, /datum/bot_goal/refill_internals) || istype(current_goal, /datum/bot_goal/seek_air))
		return //already on its way
	if(telemetry_action || world.time < mid_click_until)
		return //mid-click on something - a second from now will do
	next_air_trip_time = world.time + 10 SECONDS
	var/obj/item/tank/tank = owner.internal
	var/left = round(tank.air_contents.return_pressure())
	if(suspend_goal_for(new /datum/bot_goal/refill_internals()))
		bot_log(src, "[tank] is down to [left] kPa out here - going to refill it")
		return
	if(!tank_running_out())
		return
	bot_log(src, "[tank] is down to [left] kPa and there's nowhere to refill it - dropping everything to get to air")
	stop_pursuit()
	state_before_combat = null
	current_goal = null
	current_strategy = null
	current_step_index = 0
	suspended_goal = null
	suspended_strategy = null
	suspended_step_index = 0
	state = BOT_STATE_WANDER
	if(!assign_goal(new /datum/bot_goal/refill_internals()))
		assign_goal(new /datum/bot_goal/seek_air())

/// The nearest floor with air on it that the bot could stand on.
/datum/bot_brain/proc/find_breathable_turf()
	var/turf/here = get_turf(owner)
	var/turf/best
	var/best_dist
	for(var/turf/open/floor/T in RANGE_TURFS(BOT_AIR_SEARCH_RANGE, here))
		var/dist = get_dist(here, T)
		if(best && dist >= best_dist)
			continue
		if(!turf_air_is_breathable(T) || is_blocked_turf(T, TRUE))
			continue
		best = T
		best_dist = dist
	return best

/// Nowhere to refill and the tank nearly gone: get to air, where manage_internals() shuts the valve and
/// can_path_through_space() (gear_up_eva.dm) won't plan a way back out on what's left.
/datum/bot_goal/seek_air

/datum/bot_goal/seek_air/resolve_target(datum/bot_brain/bot)
	target = bot.find_breathable_turf()

/datum/bot_goal/seek_air/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/seek_air())

/datum/bot_strategy/seek_air/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to())

/datum/bot_strategy/seek_air/is_feasible(datum/bot_brain/bot)
	return TRUE

#undef BOT_TANK_RUNNING_OUT
#undef BOT_INTERNALS_MIN_OPEN
#undef BOT_AIR_SEARCH_RANGE
