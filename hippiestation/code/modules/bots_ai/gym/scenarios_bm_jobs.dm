// Bot gym scenarios from the 2026-11-21 bot audit, jobs area.

// ---------------------------------------------------------------------------------------------
// A Bot Shift look at the supply shuttle's air: a note in the timeline each time its docking, its doors or its pressure band changes.
// Batch play1114b (Hippie Station, 4 of 6 shifts): the third arrival was airless and the cargo technician left the crates aboard (the
// silver for Science's lathe never came round: "cargo: a crate asked for at Science's console brought round" 5 of 12).
// ---------------------------------------------------------------------------------------------

/datum/bot_shift_check/supply_air
	name = "cargo: the supply shuttle's air through its trips (a look, not judged)"
	jobs = list("Cargo Technician", "Quartermaster")
	deadline = 600 MINUTES //never late: observation only
	var/last_key

/// list(what to say, a key that changes when something worth a line does)
/datum/bot_shift_check/supply_air/proc/look()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S?.shuttle_areas)
		return list("no supply shuttle", "none")
	var/docked = S.getDockedId() || (S.mode == SHUTTLE_IDLE ? "nowhere" : "flying")
	var/count = 0
	var/total = 0
	var/lowest
	var/doors_open = 0
	var/doors = 0
	for(var/area/A as anything in S.shuttle_areas)
		for(var/turf/open/T in A)
			var/datum/gas_mixture/air = T.return_air()
			if(!air)
				continue
			var/kpa = air.return_pressure()
			total += kpa
			count++
			if(isnull(lowest) || kpa < lowest)
				lowest = kpa
		for(var/obj/machinery/door/D in A)
			doors++
			if(!D.density)
				doors_open++
	var/mean = count ? total / count : 0
	var/band = mean >= 80 ? "good" : (mean >= 20 ? "thin" : "none")
	// The bay it unloads into, and the dock's own airlocks: where the air goes when the shuttle comes in airless
	var/bay_total = 0
	var/bay_count = 0
	var/area/bay = GLOB.areas_by_type[/area/quartermaster/storage]
	if(bay)
		for(var/turf/open/T in bay)
			var/datum/gas_mixture/air = T.return_air()
			if(air)
				bay_total += air.return_pressure()
				bay_count++
	var/dock_open = 0
	var/dock_total = 0
	for(var/obj/machinery/door/airlock/A in GLOB.airlocks)
		if(!findtext(A.name, "Supply Dock") && !findtext(A.name, "Supply Shuttle"))
			continue
		dock_total++
		if(!A.density)
			dock_open++
	var/bay_mean = bay_count ? bay_total / bay_count : 0
	var/bay_band = bay_mean >= 80 ? "good" : (bay_mean >= 20 ? "thin" : "none")
	return list("[docked], shuttle [round(mean)] kPa mean and [round(lowest || 0)] lowest over [count] floor tiles, [doors_open] of [doors] doors open; bay [round(bay_mean)] kPa; [dock_open] of [dock_total] dock and shuttle airlocks open", "[docked] [band] [doors_open] [bay_band] [dock_open]")

/datum/bot_shift_check/supply_air/poll()
	var/list/seen = look()
	if(seen[2] != last_key)
		last_key = seen[2]
		shift.note("supply shuttle: [seen[1]]")
	if(isnull(done_at))
		done_at = shift.elapsed() //observation only

/datum/bot_shift_check/supply_air/done()
	return TRUE

// ---------------------------------------------------------------------------------------------
// Pastimes while the station's in trouble (bot_duties.dm station_in_trouble()). Both go through the bot's own leisure round
// (run_duties), not the duty by hand as the older scenarios do.
// ---------------------------------------------------------------------------------------------

/// The scenarios that say the station's in trouble (bot_duties.dm station_in_trouble()): a gym bot's idea of it is its scenario's say-so.
GLOBAL_LIST_EMPTY(bot_trouble_drill)

/datum/bot_scenario/duty/leisure/smoke/rounds
	name = "pastimes: in a quiet shift a smoker's leisure round lights a cigarette"
	desc = "A pack and a lighter in the bag and nothing wrong anywhere. The bot's free-time round (run_duties) has it light up, as it always did."
	time_limit = 40 SECONDS

/datum/bot_scenario/duty/leisure/smoke/rounds/issue_goal()
	goal_attempts++
	for(var/datum/bot_duty/D as anything in brain.my_duties(BOT_DUTY_LEISURE))
		brain.duty_next_check[D] = 0 //every one of them due now
	if(brain.run_duties(BOT_DUTY_LEISURE))
		log_line("the leisure round started on [brain.current_goal ? brain.current_goal.type : "something"] (attempt [goal_attempts]/[max_goal_attempts])")

/datum/bot_scenario/duty/leisure/smoke/rounds/trouble
	name = "pastimes: with the station in trouble the same smoker's leisure round leaves the cigarette"
	desc = "The same bag, and the crew are dying: nothing in the free-time round starts for 25 seconds, though every duty in it is due."

/datum/bot_scenario/duty/leisure/smoke/rounds/trouble/setup()
	..()
	GLOB.bot_trouble_drill += src

/datum/bot_scenario/duty/leisure/smoke/rounds/trouble/release_run()
	GLOB.bot_trouble_drill -= src
	..()

/datum/bot_scenario/duty/leisure/smoke/rounds/trouble/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.current_goal || bot.wear_mask)
		fail_reason = "started on [brain.current_goal ? brain.current_goal.type : "a cigarette"] with the station in trouble"
		return BOT_GYM_FAIL
	return world.time > start_time + 25 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Cargo, a crate in a vacuum and no suit to be had (goals/cargo.dm try_suit_up_for_crates())
// ---------------------------------------------------------------------------------------------

/// Batch play1114b, Hippie Station: in 4 shifts of 6 the third supply shuttle arrived airless, EVA's storage was behind doors a cargo
/// technician's card doesn't open ("there's none I can get to"), Engineering was asked five and seven times, and the silver for Science
/// sat aboard to the end of the shift. A player with no way into EVA asks the HoP for it.
/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit
	name = "cargo: a crate in a vacuum and no space suit to be had, it asks the HoP for EVA access"
	desc = "The room past the airlock is a vacuum, there's no suit storage unit its card opens, and the HoP's stood at the near end. The cargo technician, who can't go in without a suit, leaves its card at the HoP's door for EVA access, as an explorer does, instead of just leaving the crate and calling Engineering."
	time_limit = 40 SECONDS
	layout = list(
		"###############",
		"#Q.........####",
		"#H.........enk#",
		"#..B.......#nn#",
		"###############")
	room_air = "TEMP=2.7"
	var/mob/living/carbon/human/hop

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/setup()
	..()
	hop = second_bot(first_marker("H"), "Hollis Head")
	hop.mind.assigned_role = "Head of Personnel"

/// The cargo round's own first move for a crate in a vacuum, asked while it's idle
/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/before_unload()
	if(!hascall(brain, "try_suit_up_for_crates"))
		return FALSE
	if(call(brain, "try_suit_up_for_crates")(list(crate)))
		log_line("cargo: off to see about a suit for the crate")
		return TRUE
	return FALSE

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(bot_transcript_said("for EVA access to unload"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/on_timeout()
	fail_reason = "never asked for EVA access: left the crate in the vacuum"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// Shut in behind a firelock (goals/acquire_tool.dm try_pry_my_way_out())
// ---------------------------------------------------------------------------------------------

/// jobs_s1: the Research Director was shut into the Toxins lab behind a heavy firelock five minutes in, with no crowbar, and walked the one room
/// for the rest of the shift with "no path" to everywhere. The call to be let out only knows airlocks.
/datum/bot_scenario/firelock_pocket
	name = "shut in: behind a firelock that's down with no crowbar, it takes one from the toolbox and pries its way out"
	desc = "A small room with a mechanical toolbox in it and a closed firelock in the one doorway, and the way on beyond. The bot has no crowbar, so no route through the firelock: it looks for one, takes the crowbar out of the toolbox, opens the firelock and walks out. It used to walk the room for ever."
	job = "Research Director"
	time_limit = 60 SECONDS
	layout = list(
		"############",
		"#T.B...F..G#",
		"############")

/datum/bot_scenario/firelock_pocket/post_spawn()
	give_job_id(list(ACCESS_RESEARCH))

/// The look it takes now and then for a way out, then on to where it was going
/datum/bot_scenario/firelock_pocket/issue_goal()
	if(!QDELETED(brain) && hascall(brain, "try_pry_my_way_out"))
		brain.is_shut_in(TRUE)
		if(call(brain, "try_pry_my_way_out")())
			log_line("shut in behind the firelock: off for a crowbar")
			return
	..()
