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
	var/airless = 0
	var/good = 0
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
			if(kpa < 20)
				airless++
			else if(kpa >= 90)
				good++
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
	return list("[docked], shuttle [round(mean)] kPa mean, [airless] of [count] floor tiles under 20 kPa and [good] over 90, [doors_open] of [doors] doors open; bay [round(bay_mean)] kPa; [dock_open] of [dock_total] dock and shuttle airlocks open", "[docked] [band] [airless] [doors_open] [bay_band] [dock_open]")

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
	if("bot_cargo_eva_asked_at" in GLOB.vars)
		GLOB.vars["bot_cargo_eva_asked_at"] = -INFINITY //runs side by side share it: each one's own first ask is the first
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

/// Three of them stood at the HoP's door in the live shift (jobs_s1: the Quartermaster and both technicians, one crate): the one ask is enough.
/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/two_techs
	name = "cargo: a crate in a vacuum and no suit to be had, two technicians, only one of them asks the HoP for EVA access"
	desc = "The same vacuum, and a second cargo technician beside the first, each with a card that opens no EVA door. Both look at the crate in the same second, and one leaves its card at the HoP's door for EVA access: not both, since the one the HoP gives it to is enough for the crate."
	time_limit = 30 SECONDS
	layout = list(
		"###############",
		"#Q.........####",
		"#H.........enk#",
		"#J.B.......#nn#",
		"###############")
	var/mob/living/carbon/human/other_tech

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/two_techs/setup()
	..()
	other_tech = second_bot(first_marker("J"), "Jo Second")
	other_tech.mind.assigned_role = "Cargo Technician"
	var/obj/item/card/id/C = new(other_tech)
	C.registered_name = other_tech.real_name
	C.assignment = "Cargo Technician"
	C.access = list(ACCESS_CARGO)
	other_tech.equip_to_slot_or_del(C, ITEM_SLOT_ID)

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/two_techs/before_unload()
	. = ..()
	if(other_tech?.bot_brain && hascall(other_tech.bot_brain, "try_suit_up_for_crates") && !other_tech.bot_brain.current_goal)
		call(other_tech.bot_brain, "try_suit_up_for_crates")(list(crate))

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/two_techs/proc/asks()
	. = 0
	for(var/line in transcript)
		if(findtext(line, "for EVA access to unload"))
			.++

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/two_techs/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	var/count = asks()
	if(count >= 2)
		fail_reason = "both of them left their cards at the HoP's door"
		return BOT_GYM_FAIL
	return (world.time > start_time + 20 SECONDS && count == 1) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/crate_air/vacuum_no_suit/two_techs/on_timeout()
	fail_reason = "[asks()] of them asked for EVA access, not one"
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

// ---------------------------------------------------------------------------------------------
// A Curator with no books (bot_pursuits.dm pursuit_weights(), goals/quiet_jobs.dm bot_library_has_books())
// ---------------------------------------------------------------------------------------------

/// jobs_s1: the Curator did nothing but sit, smoke and wander the library for 25 minutes (98% of its time), and "library: a book read" failed
/// as it has in every batch: the random bookcases are stocked from the book database, and a round with none has empty shelves.
/datum/bot_scenario/curator_no_books
	name = "curator: with nothing on the library's shelves it's after exploring more than a lawyer is"
	desc = "No bookcase with a book in it anywhere. The Curator's want to go exploring is higher than the same bot's as a Lawyer, with the same nerve: it hasn't a library to look after, so it goes and looks for something else to curate."
	job = "Curator"
	time_limit = 10 SECONDS
	layout = list(
		"#####",
		"#B..#",
		"#####")

/datum/bot_scenario/curator_no_books/make_goal()
	return null

/datum/bot_scenario/curator_no_books/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/as_curator = brain.pursuit_weights()
	brain.standing_in_for = "Lawyer"
	var/list/as_lawyer = brain.pursuit_weights()
	brain.standing_in_for = null
	if(as_curator[BOT_PURSUIT_EXPLORE] <= as_lawyer[BOT_PURSUIT_EXPLORE])
		fail_reason = "explore weight [as_curator[BOT_PURSUIT_EXPLORE]] as a Curator, [as_lawyer[BOT_PURSUIT_EXPLORE]] as a Lawyer"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// A powergaming HoP (goals/powergame.dm try_power_access())
// ---------------------------------------------------------------------------------------------

/// jobs_s1: the Head of Personnel, a powergamer, left its own ID card at the HoP's door "for robotics access", and stood there for it.
/datum/bot_scenario/powergame_access/hop_itself
	name = "powergame: the HoP who wants more access doesn't leave its own card at its own door"
	desc = "The same powergamer card that opens next to nothing, and the bot is the Head of Personnel: there's nobody else to ask, and it can't give itself access from the other side of its own desk. It doesn't put its card on the floor and wait for itself."
	job = "Head of Personnel"
	time_limit = 14 SECONDS

/datum/bot_scenario/powergame_access/hop_itself/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/card/id/C in range(1, bot))
		if(isturf(C.loc))
			fail_reason = "left its own card on the floor for the HoP (itself)"
			return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "access") && findtext(line, "for the HoP"))
			fail_reason = "asked the HoP (itself) for access: [line]"
			return BOT_GYM_FAIL
	return world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// A doctor fetching somebody down in air nobody can breathe (goals/treat_patient.dm escort_to_sleeper, goals/refill_internals.dm)
// ---------------------------------------------------------------------------------------------

/// jobs_s2: the Chemist went down in crit in a room full of bad air and lay there five minutes. Three doctors each tried to take it to a sleeper,
/// and each turned it down ("Vic Sorrento is somewhere I can't breathe and I'm not suited up - not doing escort_to_sleeper", 10 times in the
/// last minute and a half) until it died. A player puts a mask on, opens the tank in the survival box and goes in.
/datum/bot_scenario/sleeper_check/toxic_air
	name = "medical rounds: somebody down in air nobody can breathe is fetched out on a mask and tank"
	desc = "A patient in crit behind a door, in a room full of nitrogen at 101 kPa and 20 C, a sleeper in clean air on the doctor's side, and a breath mask and an emergency oxygen tank in the doctor's bag. It puts the mask on and opens the tank before it goes in, brings them out to the sleeper, and shuts the valve and takes the mask off again after. It's never in the nitrogen with its tank shut. jobs_s2: a Chemist died in crit in a room of bad air with three doctors turning the rescue down five minutes running."
	// The clean side is long, and the room past the door two tiles: the nitrogen that comes out when the door's opened mixes into the
	// air on the doctor's side, and a small arena was left without the 16 kPa of oxygen to take the kit off in
	layout = list(
		"####################",
		"#Y.....B........DnP#",
		"####################")
	time_limit = 45 SECONDS
	kit_backpack = list(/obj/item/clothing/mask/breath, /obj/item/tank/internals/emergency_oxygen) //as a crew member's survival box has
	/// The air in the room past the door: 104 mol a tile is about 101 kPa at 20 C
	var/room_air = "n2=104;TEMP=293.15"
	var/setup_problem
	var/loaded_at

/datum/bot_scenario/sleeper_check/toxic_air/setup()
	..()
	if(!room_air)
		return
	for(var/char in list("n", "P"))
		for(var/turf/open/F in markers[char])
			F.air.parse_gas_string(room_air)
			F.update_visuals()
			SSair.add_to_active(F)

/datum/bot_scenario/sleeper_check/toxic_air/post_spawn()
	give_job_id(list(ACCESS_MEDICAL))
	patient = stand_in(first_marker("P"), "Chet Chemist")
	ADD_TRAIT(patient, TRAIT_NOBREATH, "bm_jobs_gym") //it's the doctor's air that's being judged, not how long a patient lasts in it
	patient.adjustBruteLoss(120)
	var/turf/open/there = get_turf(patient)
	if(room_air && brain.turf_air_is_breathable(there))
		setup_problem = "setup: the air by the patient at [bot_coord(there)] can be breathed ([round(there.air.return_pressure(), 0.1)] kPa, [round(there.air.temperature)] K)"
	else if(!room_air && !brain.turf_air_is_breathable(there))
		setup_problem = "setup: the air by the patient at [bot_coord(there)] can't be breathed"

/datum/bot_scenario/sleeper_check/toxic_air/make_goal()
	return new /datum/bot_goal/escort_to_sleeper()

/// What it has on for the air
/datum/bot_scenario/sleeper_check/toxic_air/proc/kitted()
	return bot.internal || istype(bot.wear_mask, /obj/item/clothing/mask/breath)

/datum/bot_scenario/sleeper_check/toxic_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(!loaded_at)
		var/turf/open/here = get_turf(bot)
		if(room_air && istype(here) && !brain.turf_air_is_breathable(here) && !bot.internal)
			fail_reason = "in air it can't breathe at [bot_coord(here)] with its tank shut"
			return BOT_GYM_FAIL
		if(sleeper.occupant != patient)
			if(bot_transcript_said("can't breathe and I'm not suited up"))
				fail_reason = "turned the rescue down: it can't breathe there and isn't suited up"
				return BOT_GYM_FAIL
			return BOT_GYM_PENDING
		loaded_at = world.time
		log_line("[patient] is in [sleeper]")
		if(room_air && !bot_transcript_said("kitted out for the air at"))
			fail_reason = "got them out without kitting up for the air they were in"
			return BOT_GYM_FAIL
		if(!room_air && (bot_transcript_said("kitted out for the air at") || bot_transcript_said("opened the valve")))
			fail_reason = "put its mask on and opened its tank for a patient in air it could breathe"
			return BOT_GYM_FAIL
	// What a bot's own brain does once a second (mind_air_supply(), goals/refill_internals.dm): the kit off again once the work's done and it's
	// back in air it can breathe. A scripted gym bot between goals only minds its valve, so the scenario asks for it, as crate_air does
	brain.mind_air_kit()
	if(kitted())
		if(world.time > loaded_at + 20 SECONDS)
			fail_reason = "still kitted out 20 s after they were in the sleeper: tank [bot.internal ? "open" : "shut"], wearing [bot.wear_mask || "no mask"]"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

/// The same, in air it can breathe: no mask and tank for it
/datum/bot_scenario/sleeper_check/toxic_air/clean
	name = "medical rounds: somebody down in air that can be breathed is fetched without a mask and tank"
	desc = "The same patient and sleeper with ordinary air in the room: the doctor doesn't kit up for it (the control for the nitrogen one)."
	room_air = null

// ---------------------------------------------------------------------------------------------
// A miner boarding the mining shuttle with thin air in its cabin (bot_doors.dm /obj/machinery/door/airlock/external/CanAStarPass())
// ---------------------------------------------------------------------------------------------

/// jobs_s2 (and four other batches on Hippie Station: a mech miner with one trip to Lavaland and nothing after, "ride_mining_shuttle ...
/// no path to the shuttle floor (Mining Shuttle)" 8 times, take_mech_down 17 to 25 tries): the shuttle came home with 27 kPa in its cabin and
/// the dock at 101, and the dock's external airlock turns back anybody not aboard already from air they can't breathe, a miner dressed for
/// Lavaland on its mask and tank as well. The station's own mining dock, so it runs alone and by name, on bot-map=hippiestation:
/// MAP=hippiestation tools/bot_gym/run_bot_gym.sh "the shuttle's cabin has thin air" 1
/datum/bot_scenario/mining_cabin_air
	name = "mining: the shuttle's cabin has thin air in it, and a miner on its mask and tank still boards it"
	desc = "The mining shuttle sat at the station's dock with 28 kPa of air in its cabin (the dock hall's at 101), and a miner with its mask on and an emergency oxygen tank on its belt in the dock, sent to ride it down. It walks aboard through the dock's external airlock: a mask and a tank do for thin air, and nobody else is going to take it down. It's never turned back at the airlock for the cabin's air."
	job = "Shaft Miner"
	time_limit = 60 SECONDS
	max_goal_attempts = 6
	station_wide = TRUE //the station's own mining shuttle and dock
	layout = list(
		"#####",
		"#B..#",
		"#####")
	/// 28 kPa of ordinary air at 20 C on a 2500 litre tile, and what the cabin's given back after
	var/thin_air = "o2=6;n2=22.7;TEMP=293.15"
	var/normal_air = "o2=21.8;n2=82.1;TEMP=293.15"
	var/list/turf/open/thinned
	var/setup_problem
	var/not_applicable
	/// Its mask on and its tank on its belt, as a miner dressed for Lavaland is
	var/dressed = TRUE

/datum/bot_scenario/mining_cabin_air/setup()
	var/obj/docking_port/mobile/M = bot_mining_shuttle()
	if(!M || !SSshuttle.getDock("mining_home") || !GLOB.areas_by_type[/area/quartermaster/miningdock])
		not_applicable = TRUE //a map with no mining dock (the testbench): nothing here to judge, so a filter like "mining" doesn't fail on it
		return
	if(!bot_mining_shuttle_at("mining_home"))
		setup_problem = "setup: the mining shuttle isn't sat idle at the station's dock ([M.mode] at [M.getDockedId()])"
		return
	thinned = list()
	for(var/turf/open/T in M.return_turfs())
		if(!M.shuttle_areas[T.loc] || !T.air)
			continue
		T.air.parse_gas_string(thin_air)
		T.update_visuals()
		SSair.add_to_active(T)
		thinned += T

/datum/bot_scenario/mining_cabin_air/post_spawn()
	give_job_id(list(ACCESS_MAINT_TUNNELS, ACCESS_MINING, ACCESS_MINING_STATION, ACCESS_CARGO, ACCESS_MAILSORTING))
	if(dressed)
		bot.equip_to_slot_or_del(new /obj/item/clothing/mask/gas/explorer(bot), ITEM_SLOT_MASK)
		bot.equip_to_slot_or_del(new /obj/item/tank/internals/emergency_oxygen(bot), ITEM_SLOT_BELT)
	if(setup_problem || not_applicable)
		return
	// Into the station's mining dock, a few tiles from the shuttle's door, beyond the dock hall and its two airlocks
	var/obj/docking_port/stationary/home = SSshuttle.getDock("mining_home")
	var/area/dock_area = GLOB.areas_by_type[/area/quartermaster/miningdock]
	var/turf/open/start
	if(home && dock_area)
		for(var/turf/open/floor/T in dock_area)
			if(T.z != home.z || is_blocked_turf(T, TRUE) || (locate(/obj/machinery/door) in range(1, T)) || (locate(/obj/machinery/conveyor) in T))
				continue
			if(!start || abs(get_dist(T, home) - 7) < abs(get_dist(start, home) - 7))
				start = T
	if(!start)
		setup_problem = "setup: no floor in the mining dock to start on"
		return
	bot.forceMove(start)
	log_line("bot moved to the mining dock at [bot_coord(start)]; the cabin's air is [round(thinned[1].air.return_pressure())] kPa, the dock's [round(start.air.return_pressure())]")
	if(dressed != brain.ready_for_lavaland())
		setup_problem = "setup: the miner [dressed ? "isn't" : "is"] ready for Lavaland"

/datum/bot_scenario/mining_cabin_air/make_goal()
	return new /datum/bot_goal/ride_mining_shuttle("mining_away")

/datum/bot_scenario/mining_cabin_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(not_applicable)
		log_line("not applicable: this map has no mining dock")
		return BOT_GYM_PASS
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(bot_aboard_mining_shuttle(bot))
		log_line("aboard the mining shuttle")
		brain.stop_pursuit()
		brain.drop_goals("the scenario's seen it aboard") //not on to send the shuttle away with the next scenario's dock
		return BOT_GYM_PASS
	if(bot_transcript_said("can't breathe and I'm not suited up"))
		fail_reason = "turned the ride down: it can't breathe at the console and isn't suited up"
		return BOT_GYM_FAIL
	if(bot_transcript_said("no path to the shuttle floor"))
		fail_reason = "no path to the shuttle floor: turned back at the dock's airlock for the cabin's air"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/mining_cabin_air/release_run()
	for(var/turf/open/T as anything in thinned)
		if(QDELETED(T) || !T.air)
			continue
		T.air.parse_gas_string(normal_air)
		T.update_visuals()
		SSair.add_to_active(T)
	. = ..()

/// The same cabin and a miner with no mask or tank on it: the airlock still turns it back, as it does anybody who'd walk into air they can't
/// breathe (the control for the one above)
/datum/bot_scenario/mining_cabin_air/undressed
	name = "mining: the shuttle's cabin has thin air in it, and a miner with no mask or tank doesn't board it"
	desc = "The same dock and cabin, and a miner with nothing to breathe from on it: the dock's airlock turns it back, and it isn't aboard 20 seconds on."
	dressed = FALSE

/datum/bot_scenario/mining_cabin_air/undressed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(not_applicable)
		log_line("not applicable: this map has no mining dock")
		return BOT_GYM_PASS
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(bot_aboard_mining_shuttle(bot))
		fail_reason = "boarded a shuttle full of air it can't breathe with no mask and tank on it"
		return BOT_GYM_FAIL
	return world.time > start_time + 20 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// The gravity generator (goals/repair_damage.dm /datum/bot_duty/gravity)
// ---------------------------------------------------------------------------------------------

/// Once the gravity generator went offline nobody ever went near it, and the crew floated for the rest of the round (7 of 24 recent shifts
/// by the humanlike agent's count; the drill is grav-drill=1 in run_bot_shift.sh on bm/humanlike). An engineer's duty now looks at it, and
/// does what a player does: the breaker, or the four steps of its framework and then the breaker. The generator an admin can spawn has
/// no power of its own to lose, so what's judged is the engineer.
/datum/bot_scenario/duty/gravity
	name = "gravity: the generator's breaker is off, and an engineer switches it back on"
	desc = "The station's gravity generator switched off at its breaker (the engineer's duty notices it's off and nothing's bringing it back). It goes over and puts the breaker on, and the generator is charging again. It's the first thing in a shift that goes near it: the crew float till then."
	job = "Station Engineer"
	time_limit = 60 SECONDS
	// The generator takes the 3 by 3 above and either side of the G (its parts), so there's floor below it to stand on, as on the station
	layout = list(
		"###########",
		"#.........#",
		"#.........#",
		"#....G....#",
		"#B........#",
		"###########")
	var/obj/machinery/gravity_generator/main/station/admin/generator

/datum/bot_scenario/duty/gravity/setup()
	duty_type = text2path("/datum/bot_duty/gravity") // by name: a build without the fix has no such duty
	generator = new(first_marker("G"))
	break_it()

/// The generator off at its breaker, with nothing charging it
/datum/bot_scenario/duty/gravity/proc/break_it()
	generator.breaker = FALSE
	generator.charge_count = 0
	generator.set_power()
	generator.set_state(0)

/// Back on its way up: not broken, the breaker on, and on or charging
/datum/bot_scenario/duty/gravity/proc/back_on()
	return generator.breaker && !(generator.stat & BROKEN) && (generator.on || generator.charging_state)

/datum/bot_scenario/duty/gravity/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(generator))
		fail_reason = "the generator's gone"
		return BOT_GYM_FAIL
	return back_on() ? BOT_GYM_PASS : BOT_GYM_PENDING

/// What the drill does (run_bot_shift.sh grav-drill=1): set_state(FALSE) with the breaker still on and nothing to bring it back
/datum/bot_scenario/duty/gravity/stuck
	name = "gravity: the generator's off with its breaker still on, and an engineer cycles it"
	desc = "The generator off with its breaker on (it's what the shift drill does) and nothing charging it. The engineer switches the breaker off and on again, and it's charging."

/datum/bot_scenario/duty/gravity/stuck/break_it()
	generator.set_state(0)

/// A long walk to the far end of a hall in hand when the generator goes off: dropped for it, not finished first
/datum/bot_scenario/duty/gravity/busy
	name = "gravity: the generator's off in the middle of a long errand, and an engineer drops it for the generator"
	desc = "The breaker off while the engineer is on a walk to the far end of a long hall, forty tiles off. It drops the walk (the station floating is worth that, as a lone engineer's seven minutes on the particle accelerator's parts weren't) and puts the breaker on before it gets there."
	time_limit = 60 SECONDS
	layout = list(
		"##################################################",
		"#................................................#",
		"#................................................#",
		"#....G...........................................#",
		"#B..............................................W#",
		"##################################################")

/datum/bot_scenario/duty/gravity/busy
	var/walk_given = FALSE

/datum/bot_scenario/duty/gravity/busy/post_spawn()
	..()
	var/datum/bot_duty/D = bot_duty_of(duty_type)
	if(D)
		brain.gym_duties = list(D.type) //so that its walk can be dropped for it

/// The walk first; the duty is only asked once the bot is idle again, as the base duty scenario does
/datum/bot_scenario/duty/gravity/busy/issue_goal()
	if(!walk_given)
		walk_given = TRUE
		brain.assign_goal(new /datum/bot_goal/walk_up_to(first_marker("W")))
		log_line("sent on a walk to the far end of the hall")
		return
	..()

/datum/bot_scenario/duty/gravity/busy/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(generator))
		fail_reason = "the generator's gone"
		return BOT_GYM_FAIL
	if(back_on())
		return BOT_GYM_PASS
	if(get_dist(bot, first_marker("W")) <= 2)
		fail_reason = "finished its walk to the far end of the hall with the generator off"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/// Four steps to mend it and then the breaker
/datum/bot_scenario/duty/gravity/broken
	name = "gravity: the generator's broken, and an engineer mends its framework and switches it on"
	desc = "The generator broken down (an explosion or a blob did it). The engineer, with a screwdriver, a welder, twenty plasteel and a wrench in its bag, secures the framework, welds it, adds the plating, wrenches it down, and puts the breaker on."
	kit_backpack = list(/obj/item/screwdriver, /obj/item/weldingtool, /obj/item/wrench, /obj/item/stack/sheet/plasteel/twenty)

/datum/bot_scenario/duty/gravity/broken/break_it()
	generator.set_broken()

/// A generator that's on needs nothing, and so does one with no power in its room (it charges up by itself when that's back)
/datum/bot_scenario/duty/gravity/fine
	name = "gravity: the generator's on, and an engineer leaves it alone"
	desc = "The generator running. The engineer doesn't go over and switch its breaker off, or anything else: after eight seconds the breaker's still on and the generator still on."

/datum/bot_scenario/duty/gravity/fine/break_it()
	return

/datum/bot_scenario/duty/gravity/fine/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!generator.breaker || !generator.on)
		fail_reason = "the generator's breaker or its state was changed: breaker [generator.breaker ? "on" : "off"], [generator.on ? "on" : "off"]"
		return BOT_GYM_FAIL
	if(bot_transcript_said("the gravity's off: started"))
		fail_reason = "set about the gravity generator that was running"
		return BOT_GYM_FAIL
	return world.time > start_time + 8 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/gravity/no_power
	name = "gravity: no power in the generator's room, and an engineer doesn't go for its breaker"
	desc = "The generator down for want of power: that's the power's to be seen to, and it charges by itself when it's back. The engineer doesn't go and switch the breaker on and off."

/datum/bot_scenario/duty/gravity/no_power/break_it()
	generator.set_state(0)
	generator.stat |= NOPOWER

/datum/bot_scenario/duty/gravity/no_power/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("the gravity's off: started"))
		fail_reason = "set about a generator with no power in its room"
		return BOT_GYM_FAIL
	return world.time > start_time + 8 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// What a janitor knows of (goals/janitor.dm knows_of_mess())
// ---------------------------------------------------------------------------------------------

/// The janitor picked every stain within sixty tiles of itself, seen or not, through bot_instances_of(). Now it picks what it can see, has seen
/// or was asked to come to (bot_knowledge.dm did the same for items and casualties).
/datum/bot_scenario/janitor_knows
	name = "janitor: it picks the stain in sight, and doesn't know of one forty tiles off until it's by it"
	desc = "Two blood stains in a long hall, one five tiles from the janitor and one forty. It picks the near one; with that mopped up it knows of nothing else (the far one's never been in sight); stood by the far one it picks that."
	job = "Janitor"
	time_limit = 20 SECONDS
	layout = list(
		"##############################################",
		"#B....n..................................f...#",
		"##############################################")
	var/obj/effect/decal/cleanable/blood/near
	var/obj/effect/decal/cleanable/blood/far
	var/stage = 0

/datum/bot_scenario/janitor_knows/setup()
	if("strict_mess" in vars)
		vars["strict_mess"] = TRUE //by name: a build without the fix has no such var
	near = new /obj/effect/decal/cleanable/blood/splatter(first_marker("n"))
	far = new /obj/effect/decal/cleanable/blood/splatter(first_marker("f"))

/datum/bot_scenario/janitor_knows/make_goal()
	return null

/datum/bot_scenario/janitor_knows/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(far))
		fail_reason = "the far stain's gone"
		return BOT_GYM_FAIL
	var/found = brain.pick_mess()
	switch(stage)
		if(0)
			if(found != near)
				fail_reason = "picked [found || "nothing"] with a stain in sight, not it"
				return BOT_GYM_FAIL
			stage = 1
			qdel(near)
			log_line("the stain in sight is mopped up")
		if(1)
			if(found)
				fail_reason = "knew of the stain forty tiles off that it had never seen: picked it"
				return BOT_GYM_FAIL
			stage = 2
			bot.forceMove(get_step(first_marker("f"), WEST))
			log_line("it's by the far stain")
		if(2)
			if(found != far)
				fail_reason = "stood by the far stain it didn't pick it (picked [found || "nothing"])"
				return BOT_GYM_FAIL
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// A miner's tank (goals/refill_internals.dm take_back_refill_tank(), goals/mining.dm dress_for_lavaland)
// ---------------------------------------------------------------------------------------------

/// bm_early run3 (Hippie Station): a miner back from a ruin on Lavaland with a refilled tank in its hand lost it when the shuttle set off
/// (the launch knocks everybody aboard over and their hands empty), and from then on "dress_for_lavaland" failed on the spot every fifteen
/// seconds for thirty minutes: "0 ore delivered of 0 dug". The refill now puts the tank back on the body, and a miner with no tank fetches
/// one.
/datum/bot_scenario/refill_internals/on_the_body
	name = "refill_internals: the refilled tank goes back on the belt or in a pocket, not left in a hand"
	desc = "The same refill, and once it's out of the canister it isn't left in a hand: a hand gets emptied for the next thing or knocked empty at a shuttle's launch, and a miner's tank was lost that way."
	var/in_hand_since

/datum/bot_scenario/refill_internals/on_the_body/check()
	var/result = ..()
	if(result == BOT_GYM_FAIL)
		return result
	// Back from the canister and in a hand: given a moment to be put on, and then it was left there
	if(was_in_canister && !QDELETED(tank) && tank.loc == bot && !canister.holding && bot.is_holding(tank))
		in_hand_since ||= world.time
		if(world.time > in_hand_since + 3 SECONDS)
			fail_reason = "left the refilled tank in a hand"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	return result

/datum/bot_scenario/miner_lost_tank
	name = "mining: a miner with no tank on it fetches an emergency tank from the rack and dresses for Lavaland"
	desc = "A miner with its mask on and no tank anywhere on it, and an emergency oxygen tank on a rack eight tiles off. It fetches the tank and puts it on its belt: ready for Lavaland, not set down on the floor to wait for the next shuttle."
	job = "Shaft Miner"
	time_limit = 40 SECONDS
	layout = list(
		"#############",
		"#B.......T..#",
		"#############")

/datum/bot_scenario/miner_lost_tank/setup()
	new /obj/item/tank/internals/emergency_oxygen(first_marker("T"))
	var/obj/item/tank/internals/emergency_oxygen/spare = locate() in first_marker("T")
	if(spare)
		bot_note_mapped(spare) //laid out for the scenario: common knowledge, as what the map put on a rack is

/datum/bot_scenario/miner_lost_tank/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/gas/explorer(bot), ITEM_SLOT_MASK)

/datum/bot_scenario/miner_lost_tank/make_goal()
	return new /datum/bot_goal/dress_for_lavaland()

/datum/bot_scenario/miner_lost_tank/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.ready_for_lavaland())
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// A tank down to 30% and no canister anywhere: the fresh one fetched from the rack goes on in its place (the goal that fetches it is
/// what's judged; what sends a bot after one is a minute's look at its gauge, which a scripted gym bot doesn't make).
/datum/bot_scenario/spare_tank_swap
	name = "mining: a miner's tank is down to 30% and there's no canister, so it fetches one from the rack and puts it on"
	desc = "A miner on its mask and a tank that's nearly gone, no oxygen canister about, and an emergency tank on a rack eight tiles off. It fetches the full tank and puts it on its belt in place of the old one, which goes in its bag, and the tank it breathes from is the full one."
	job = "Shaft Miner"
	time_limit = 40 SECONDS
	layout = list(
		"#############",
		"#B.......T..#",
		"#############")
	var/obj/item/tank/internals/old_tank
	var/obj/item/tank/internals/rack_tank

/datum/bot_scenario/spare_tank_swap/setup()
	rack_tank = new /obj/item/tank/internals/emergency_oxygen(first_marker("T"))
	bot_note_mapped(rack_tank)

/datum/bot_scenario/spare_tank_swap/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/gas/explorer(bot), ITEM_SLOT_MASK)
	old_tank = new /obj/item/tank/internals/emergency_oxygen(bot)
	bot.equip_to_slot_or_del(old_tank, ITEM_SLOT_BELT)
	old_tank.air_contents.moles[/datum/gas/oxygen] *= 0.3

/datum/bot_scenario/spare_tank_swap/make_goal()
	return new /datum/bot_goal/acquire_item_type/breathing_tank()

/datum/bot_scenario/spare_tank_swap/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(rack_tank) || QDELETED(old_tank))
		fail_reason = "a tank's gone"
		return BOT_GYM_FAIL
	// The fresh one on the body (a slot, not a hand) and the old one not: in its bag or on the floor
	if(rack_tank.loc == bot && !bot.is_holding(rack_tank))
		if(old_tank.loc == bot)
			fail_reason = "the old tank's still on it"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// A goliath's tentacles (goals/mining.dm dodge_tentacles())
// ---------------------------------------------------------------------------------------------

/// Miners and explorers died to goliaths in the first five minutes on Lavaland in 5 of 18 shifts (bm_early run1, 5, 6; play1114b run1, 9): the
/// goliath digs its tentacles under somebody (four tiles, showing for a second), and whoever stands on one is stunned for ten seconds and
/// hurt while it walks up and beats them. Nobody stepped off it.
/datum/bot_scenario/mining/tentacles
	name = "miner: a goliath digs its tentacles under it, and it steps off them before they strike"
	desc = "A goliath seven tiles off with its AI off, and its tentacles dug under the miner (the tile it's on and three beside it, as the goliath's own attack does). The miner steps off before they grab: after four seconds it isn't stunned and has taken no damage."
	time_limit = 8 SECONDS
	kit_hands = list(/obj/item/pickaxe)
	kit_backpack = list(/obj/item/t_scanner/adv_mining_scanner/lesser, /obj/item/gun/energy/kinetic_accelerator)
	layout = list(
		"###############",
		"#.............#",
		"#.............#",
		"#.....B.....y.#",
		"#.............#",
		"#.............#",
		"###############")
	var/mob/living/simple_animal/hostile/asteroid/goliath/goliath
	var/dug_at

/datum/bot_scenario/mining/tentacles/setup()
	..()
	goliath = new(first_marker("y"))
	goliath.toggle_ai(AI_OFF)

/datum/bot_scenario/mining/tentacles/make_goal()
	return null

/datum/bot_scenario/mining/tentacles/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!dug_at)
		dug_at = world.time
		new /obj/effect/temp_visual/goliath_tentacle/original(get_turf(bot), goliath)
		log_line("the goliath digs its tentacles under the miner")
		return BOT_GYM_PENDING
	if(world.time < dug_at + 4 SECONDS)
		return BOT_GYM_PENDING
	if(bot.IsStun() || bot.getBruteLoss() > 0)
		fail_reason = "held by the tentacles: [bot.IsStun() ? "stunned" : "not stunned"], [round(bot.getBruteLoss())] brute"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Fighting a goliath (bot_fighting.dm fight_fauna())
// ---------------------------------------------------------------------------------------------

/// A goliath with its AI off, three tiles from the miner, which is made to know it's being attacked by it (as the goliath's first blow does).
/datum/bot_scenario/mining/goliath_fighting
	time_limit = 8 SECONDS
	layout = list(
		"#####################",
		"#...................#",
		"#...................#",
		"#.......B..y........#",
		"#...................#",
		"#...................#",
		"#####################")
	var/mob/living/simple_animal/hostile/asteroid/goliath/goliath
	var/started_at

/datum/bot_scenario/mining/goliath_fighting/setup()
	..()
	goliath = new(first_marker("y"))
	goliath.toggle_ai(AI_OFF)

/datum/bot_scenario/mining/goliath_fighting/make_goal()
	return null

/// Once, at the start: it has been hit
/datum/bot_scenario/mining/goliath_fighting/proc/start_fight()
	started_at = world.time
	brain.on_attacked(goliath, "attacked", null)
	log_line("the goliath's first blow: [get_dist(bot, goliath)] tiles off")

/datum/bot_scenario/mining/goliath_fighting/no_gun
	name = "miner: a goliath on it and no accelerator, it doesn't hit it with what's in its hand but makes for the outpost"
	desc = "A goliath three tiles off and a miner with a pickaxe and no kinetic accelerator, which has just been hit by it. It doesn't go at the goliath (not a scratch on it after six seconds), and it's six tiles or more from it by then."
	kit_hands = list(/obj/item/pickaxe)
	kit_backpack = list(/obj/item/t_scanner/adv_mining_scanner/lesser)

/datum/bot_scenario/mining/goliath_fighting/no_gun/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!started_at)
		start_fight()
		return BOT_GYM_PENDING
	if(goliath.health < goliath.maxHealth)
		fail_reason = "hit the goliath with what it had in its hand"
		return BOT_GYM_FAIL
	if(world.time < started_at + 6 SECONDS)
		return BOT_GYM_PENDING
	if(get_dist(bot, goliath) < 6)
		fail_reason = "still [get_dist(bot, goliath)] tiles from the goliath six seconds on"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/mining/goliath_fighting/kiting
	name = "miner: its accelerator recharging with a goliath three tiles off, it moves away rather than stand there"
	desc = "A goliath three tiles off, the miner's accelerator empty and recharging. It keeps moving away from it for the second and a half the recharge takes: two seconds on it is five tiles or more from it."
	kit_hands = list(/obj/item/gun/energy/kinetic_accelerator)
	kit_backpack = list(/obj/item/pickaxe)

/datum/bot_scenario/mining/goliath_fighting/kiting/post_spawn()
	..()
	for(var/obj/item/gun/energy/kinetic_accelerator/KA in bot.GetAllContents())
		KA.overheat = TRUE //recharging, and not done for the length of the scenario
		KA.empty()

/datum/bot_scenario/mining/goliath_fighting/kiting/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!started_at)
		start_fight()
		return BOT_GYM_PENDING
	if(world.time < started_at + 2 SECONDS)
		return BOT_GYM_PENDING
	if(get_dist(bot, goliath) < 5)
		fail_reason = "two seconds into the recharge it was still [get_dist(bot, goliath)] tiles from the goliath"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/mining/goliath_fighting/ready_shot
	name = "miner: a goliath five tiles off and the accelerator ready, it steps in to the bolt's range and hits it"
	desc = "A goliath five tiles off that has just hit the miner, and a loaded kinetic accelerator. The bolt goes three tiles, and the miner used to fire from where it stood and hit nothing: it steps in to three and the goliath is hurt inside six seconds."
	kit_hands = list(/obj/item/gun/energy/kinetic_accelerator)
	kit_backpack = list(/obj/item/pickaxe)
	layout = list(
		"#####################",
		"#...................#",
		"#...................#",
		"#.......B....y......#",
		"#...................#",
		"#...................#",
		"#####################")

/datum/bot_scenario/mining/goliath_fighting/ready_shot/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!started_at)
		start_fight()
		return BOT_GYM_PENDING
	if(goliath.health < goliath.maxHealth)
		return BOT_GYM_PASS
	if(world.time > started_at + 6 SECONDS)
		fail_reason = "the goliath's not been scratched six seconds on, [get_dist(bot, goliath)] tiles off"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/// bm_early run1: a miner hurt to 74 health set off for a first-aid kit across Lavaland by a route that went by a goliath at three tiles, was
/// grabbed and beaten to death on the way. Routes keep three tiles clear of a conscious goliath now (bot_hazards.dm).
/datum/bot_scenario/mining/goliath_route
	name = "miner: the straight way past a goliath is three tiles from it, so it goes round"
	desc = "A hall with a goliath in the middle of it, its AI off, and the miner sent to the far end. The direct route goes right by the goliath; there's room to go round at four tiles. It never comes nearer than three."
	time_limit = 40 SECONDS
	layout = list(
		"###########################",
		"#.........................#",
		"#.........................#",
		"#.........................#",
		"#.........................#",
		"#B.........y............T.#",
		"#.........................#",
		"#.........................#",
		"#.........................#",
		"#.........................#",
		"###########################")
	var/mob/living/simple_animal/hostile/asteroid/goliath/goliath
	var/closest = 99

/datum/bot_scenario/mining/goliath_route/setup()
	..()
	goliath = new(first_marker("y"))
	goliath.toggle_ai(AI_OFF)
	bot_refresh_hazards() //the hazard map is redrawn every few seconds; the route's planned before the next

/datum/bot_scenario/mining/goliath_route/make_goal()
	var/datum/bot_goal/walk_up_to/G = new(first_marker("T"))
	return G

/datum/bot_scenario/mining/goliath_route/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	closest = min(closest, get_dist(bot, goliath))
	if(closest < 3)
		fail_reason = "went by the goliath at [closest] tiles"
		return BOT_GYM_FAIL
	return get_dist(bot, first_marker("T")) <= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING
