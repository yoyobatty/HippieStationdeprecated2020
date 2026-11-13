// Defenders (the plan's apex/defenders.dm, M6). The user's ruling, 2026-11-13: both halves, full depth - stopping an apex traitor, and
// surviving one. This file is the stopping half, for Security and the crew:
//
//  - The armory for any killer at large (security_tactics.dm opened it only for a nanosuit): somebody with the crew's bodies to their name
//    (goals/massacre.dm) gets the same as a suit. An apex Head of Security or Warden doesn't wait the minute first.
//  - Reading a strike before it goes off (the kill planner's openers, apex/kill_planner.dm): a tank bomb carried where nobody has any
//    business with one, a plasma canister dragged into where people are. Seen, it's called in and put on the record, and Security goes
//    for them; a bomb sends the crew out of the room.
// The surviving half is in apex/survivors.dm.

/// Where people gather: what a strike is aimed at (goals/sabotage.dm sabotage_crowd_spot() picks from the same rooms)
GLOBAL_LIST_INIT(bot_crowd_rooms, list(/area/crew_quarters/bar, /area/crew_quarters/cafeteria, /area/hallway/primary, /area/crew_quarters/fitness, /area/hallway/secondary/exit/departure_lounge))
/// Where a tank bomb is nobody's business either: what a saboteur's maxcap is left in (goals/sabotage_bomb.dm bomb_spot())
GLOBAL_LIST_INIT(bot_no_bomb_rooms, list(/area/bridge, /area/security))
/// Somebody seen dragging plasma into a crowd: REF -> until when it's not called in again
GLOBAL_LIST_EMPTY(bot_canister_drag_called)

/area/bot_gym
	/// A Bot Gym arena standing in for one of the station's crowd rooms (above)
	var/crowd_room = FALSE

/proc/bot_is_crowd_room(area/A)
	var/area/bot_gym/arena = A
	if(istype(arena))
		return arena.crowd_room
	return is_type_in_list(A, GLOB.bot_crowd_rooms)

// ---------------------------------------------------------------------------------------------
// The armory
// ---------------------------------------------------------------------------------------------

/// Somebody the armory's for: a suit at large (goals/security_tactics.dm), or failing that a killer at large on a shift gone bad
/// (goals/massacre.dm). From when it was first known, in GLOB.bot_suit_seen_at, as for a suit.
/datum/bot_brain/proc/armory_threat()
	. = suit_at_large()
	if(.)
		return
	var/mob/living/carbon/human/K = massacre_killer()
	if(!K || K == owner || K.stat == DEAD || K.handcuffed)
		return null
	if(!GLOB.bot_suit_seen_at[REF(K)])
		GLOB.bot_suit_seen_at[REF(K)] = world.time
	return K

// ---------------------------------------------------------------------------------------------
// A strike in the making
// ---------------------------------------------------------------------------------------------

/// A tank bomb in somebody's hands where nobody has any business with one: where people gather, on the Bridge, in Security. A scientist
/// carrying the lab's bomb to the test range isn't one.
/proc/bot_bomb_out_of_place(mob/living/carbon/human/H)
	var/obj/item/transfer_valve/V = bot_held_bomb(H)
	if(!V)
		return null
	var/area/A = get_area(H)
	return (bot_is_crowd_room(A) || is_type_in_list(A, GLOB.bot_no_bomb_rooms)) ? V : null

/// What a bot that's seen somebody with a bomb out of place does about the record: on it, for Security. The crew's warning and getting
/// clear are look_out_for_bombers()'s (bot_fighting.dm).
/// An officer writes it up itself; anybody else's word gets there with its radio call (bot_radio.dm), or in person.
/datum/bot_brain/proc/report_bomb_carrier(mob/living/carbon/human/H)
	if(bot_get_wanted_entry(H) || !length(GLOB.bot_security_brains) || gone_loud())
		return
	var/details = "Carrying a tank bomb in [get_area_name(H, TRUE)] (seen by [owner.real_name])."
	if(is_security_job())
		file_crime(H, "Possession of explosives", details, BOT_CRIME_MAJOR)
	else
		var/datum/callback/report = CALLBACK(src, PROC_REF(report_to_security), WEAKREF(H), "Possession of explosives", details, BOT_CRIME_MAJOR, null)
		bot_radio_then(owner, world.time - 5 SECONDS, report, CALLBACK(src, PROC_REF(keep_to_tell), report, "[H.name]'s carrying a tank bomb in [get_area_name(H, TRUE)].", WEAKREF(H)))
	bot_tally("bombs called in")

/// A plasma canister somebody's dragging into where people are
/proc/bot_canister_dragger(mob/living/carbon/human/H)
	var/obj/machinery/portable_atmospherics/canister/C = H.pulling
	if(!istype(C) || C.valve_open)
		return null
	var/list/moles = C.air_contents?.moles
	if(!moles || moles[/datum/gas/plasma] < 500)
		return null
	return bot_is_crowd_room(get_area(H)) ? C : null

/// Whether anybody at all is dragging one into a crowd: a look round the canisters, before anybody looks round the room.
/proc/bot_any_canister_dragger()
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(!QDELETED(C) && ishuman(C.pulledby) && bot_canister_dragger(C.pulledby))
			return TRUE
	return FALSE

/// From keep_an_eye_out() (bot_witness.dm): somebody hauling plasma into the Bar is somebody about to set the Bar on fire. Called in once
/// a minute between everybody, on the record for Security, and an officer who sees it goes to stop them. TRUE if it's acted.
/datum/bot_brain/proc/look_out_for_canister_drags()
	if(!bot_any_canister_dragger())
		return FALSE
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H == owner || H.stat != CONSCIOUS || H.handcuffed || !bot_canister_dragger(H) || on_my_side(H))
			continue
		if(!notices_threat()) //foundation/threat_read.dm: a low-skill bot may not think anything of it
			return FALSE
		if(GLOB.bot_canister_drag_called[REF(H)] <= world.time)
			GLOB.bot_canister_drag_called[REF(H)] = world.time + 1 MINUTES
			bot_log(src, "DEFENCE: [H] is dragging plasma into [get_area_name(H, TRUE)]")
			bot_tally("plasma drags called in")
			if(is_security_job())
				if(!bot_get_wanted_entry(H))
					file_crime(H, "Attempted sabotage", "Dragging a plasma canister into [get_area_name(H, TRUE)].", BOT_CRIME_MINOR)
			else
				call_it_in(H, "Attempted sabotage", "is dragging a plasma canister", BOT_CRIME_MINOR)
		if(is_security_job() && state != BOT_STATE_ARREST && begin_arrest(H))
			return TRUE
		return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Booking a killer nobody saw
// ---------------------------------------------------------------------------------------------

/// Three of the crew dead with the same name on them (goals/massacre.dm counts it, from the radio and what a scan of the bodies turns up)
/// and nobody saw it done: only killings somebody saw ever made the records, so Security went on with its rounds while the bodies piled
/// up. A robust officer puts it together and books them for it, and the hunt's on (goals/security_patrol.dm; with the director's clues
/// for an apex one, foundation/hunt.dm).
/datum/bot_duty/book_the_killer
	name = "booking a killer from the bodies"
	jobs = list("Security Officer", "Warden", "Head of Security", "Detective")
	tier = BOT_DUTY_URGENT
	priority = 33
	interval_min = 50
	interval_max = 100

/datum/bot_duty/book_the_killer/try_start(datum/bot_brain/bot)
	if(!bot.skill_at_least(BOT_SKILL_MID) || bot.owner.handcuffed || bot.state == BOT_STATE_COMBAT)
		return FALSE
	var/mob/living/carbon/human/K = bot.massacre_killer()
	if(!K || K == bot.owner || bot_is_officer(K))
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(K)
	if(W && W.severity >= BOT_CRIME_MURDER)
		return FALSE
	var/list/counts = bot_body_counts(bot.gym_run ? get_area(bot.owner) : null)
	var/bodies = counts[K.real_name] || 0
	bot.file_crime(K, "Murder", "[bodies] of the crew dead by their hand.", BOT_CRIME_MURDER)
	bot_log(bot, "DEFENCE: [bodies] bodies with [K.real_name]'s name on them - booking them for Murder")
	bot_tally("killers booked from the bodies")
	bot_say(bot.owner, ":s [K.real_name]'s done for [bodies] of the crew. Murder. Find them.")
	return FALSE
