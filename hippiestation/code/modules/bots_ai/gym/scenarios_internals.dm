// Internals refills (goals/refill_internals.dm). O marks where the oxygen canister goes.

/datum/bot_scenario/refill_internals
	name = "refill_internals"
	desc = "A Station Engineer's emergency tank is down to 30%. There's a full oxygen canister nearby: fill the tank back up, take it out and put it back on."
	layout = list(
		"#######",
		"#B...O#",
		"#######")
	job = "Station Engineer"
	time_limit = 60 SECONDS
	/// kPa the canister starts at; the full one is far above what the tank holds
	var/canister_pressure = 4000
	/// kPa the tank has to be back up to
	var/fill_target = 950
	var/obj/item/tank/internals/tank
	var/obj/machinery/portable_atmospherics/canister/oxygen/canister
	/// Set once the tank's been seen in the canister, so the starting state (tank on, canister idle) doesn't count as done
	var/was_in_canister = FALSE

/datum/bot_scenario/refill_internals/setup()
	canister = new(first_marker("O"))
	canister.air_contents.moles[/datum/gas/oxygen] = canister_pressure * canister.air_contents.volume / (R_IDEAL_GAS_EQUATION * canister.air_contents.temperature)
	placed["O"] = list(canister)

/datum/bot_scenario/refill_internals/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(bot), ITEM_SLOT_MASK)
	tank = new /obj/item/tank/internals/emergency_oxygen(bot)
	bot.equip_to_slot_or_del(tank, ITEM_SLOT_BELT)
	var/full = tank.air_contents.return_pressure()
	brain.internals_tank_max_pressure_seen = full // it's seen this tank full before
	brain.last_seen_internals_tank = tank
	tank.air_contents.moles[/datum/gas/oxygen] *= 0.3
	bot.internal = tank
	log_line("tank at [round(tank.air_contents.return_pressure())] of [round(full)] kPa")

/datum/bot_scenario/refill_internals/make_goal()
	return new /datum/bot_goal/refill_internals()

/datum/bot_scenario/refill_internals/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(tank.loc == canister)
		was_in_canister = TRUE
	if(was_in_canister && bot.internal == tank && tank.loc == bot && !canister.holding && !canister.valve_open)
		var/pressure = tank.air_contents.return_pressure()
		if(pressure < fill_target)
			fail_reason = "put the tank back on at only [round(pressure)] kPa"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/refill_internals/on_timeout()
	fail_reason = "timed out: tank [tank.loc == canister ? "still in the canister" : "at [tank.loc]"], valve [canister.valve_open ? "open" : "shut"], [round(tank.air_contents.return_pressure())] kPa"
	return BOT_GYM_FAIL

// The canister can get the tank past the halfway mark but not back to full: the bot used to wait at it forever for a
// pressure it could never reach, tank inside, valve open
/datum/bot_scenario/refill_internals/weak_canister
	name = "refill_internals_weak_canister"
	desc = "Same, but the only canister is at 900 kPa - under the tank's full 1013. Fill it as far as the canister goes, then take it back."
	canister_pressure = 900
	fill_target = 700

// A refill that got cut short left the tank in the canister: go back for it
/datum/bot_scenario/refill_internals/stranded
	name = "retrieve_stranded_tank"
	desc = "A refill was cut short and the engineer's tank is still in the canister. Walk back, take it out and put it back on."
	fill_target = 0

/datum/bot_scenario/refill_internals/stranded/post_spawn()
	. = ..()
	bot.internal = null
	bot.temporarilyRemoveItemFromInventory(tank, TRUE)
	tank.forceMove(canister)
	canister.holding = tank
	canister.valve_open = TRUE
	brain.stranded_refill_tank = WEAKREF(tank)

/datum/bot_scenario/refill_internals/stranded/make_goal()
	return brain.make_stranded_tank_goal()
