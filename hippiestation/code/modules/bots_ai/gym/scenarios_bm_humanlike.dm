// Bot gym scenarios from the 2026-11-21 bot audit, humanlike area.

/datum/bot_scenario/bmhl

/// Counts how many of the bot's steps went against the way it set out, for the "doesn't dither" scenarios.
/datum/bot_scenario/bmhl/proc/count_steps_back(dir_out)
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(note_step))
	steps_out_dir = dir_out

/datum/bot_scenario/bmhl
	var/steps_out_dir = 0
	var/steps_taken = 0
	var/steps_back = 0

/datum/bot_scenario/bmhl/proc/note_step(atom/movable/mover, atom/oldloc, dir)
	SIGNAL_HANDLER
	steps_taken++
	if(dir == REVERSE_DIR(steps_out_dir))
		steps_back++

/datum/bot_scenario/bmhl/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	return ..()

/datum/bot_scenario/bmhl/corridor_pass
	name = "walking: two of the crew meet head-on in a one-wide corridor and get past each other without dithering"
	desc = "Two crew, each sent to the other's end of a one-wide corridor, meet in the middle. They change places (help intent) and walk on, the way two players do. The audit asks it of a bot that backed off, stepped aside into nothing or stopped for seconds in front of the other."
	layout = list(
		"##########################",
		"#B......................G#",
		"##########################")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/other

/datum/bot_scenario/bmhl/corridor_pass/post_spawn()
	other = second_bot(first_marker("G"), "Pat Passerby")
	count_steps_back(EAST)
	var/datum/bot_goal/gym_reach/G = new
	G.target = first_marker("B")
	other.bot_brain.assign_goal(G)

/datum/bot_scenario/bmhl/corridor_pass/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(get_turf(bot) == first_marker("G") && get_turf(other) == first_marker("B"))
		if(steps_back > 2)
			fail_reason = "backed up [steps_back] times to get past (of [steps_taken] steps)"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Who's hurt and who's dead (bot_knowledge.dm knows_of_casualty())
// ---------------------------------------------------------------------------------------------
// A doctor's rounds scanned every mob on the level, so a body somebody had shut away in maintenance had a doctor on its way inside
// the minute. These run in strict_casualties mode: the arena's nobody's Medbay, and what the doctor knows of is what it's seen, been
// told on the radio, or reads off a crew monitor stood in front of it. The defibrillator and body are as in "doctor drags somebody just
// dead to the defibrillator" (scenarios_medical.dm); the doctor's scripted, so only the goal it's handed is judged.

/datum/bot_scenario/revive/unknown
	name = "casualty: a doctor doesn't go for a body it has no way of knowing about, down the far end of a long hall"
	desc = "Dead and fresh enough for the paddles, twenty-odd tiles down a hall the doctor can't see along, in a uniform with its sensors off, with a crew monitor on the wall beside the doctor. Nobody's said a word. It leaves it. Before 2026-11-21 every doctor's round went for any body on the level."
	strict_casualties = TRUE
	time_limit = 12 SECONDS
	layout = list(
		"##############################",
		"#B......................C...K#",
		"#M...........................#",
		"##############################")

/datum/bot_scenario/revive/unknown/setup()
	..()
	for(var/turf/T in markers["M"])
		place("M", new /obj/machinery/computer/crew(T))

/datum/bot_scenario/revive/unknown/post_spawn()
	..()
	var/obj/item/clothing/under/U = patient.w_uniform
	if(istype(U))
		U.has_sensor = HAS_SENSORS
		U.sensor_mode = SENSOR_OFF

/datum/bot_scenario/revive/unknown/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(patient))
		fail_reason = "the patient's gone"
		return BOT_GYM_FAIL
	if(patient.stat != DEAD || bot.pulling == patient || (locate(/obj/item/twohanded/shockpaddles) in bot.held_items) || bot_transcript_said("bot_strategy/revive"))
		fail_reason = "set off for a body it had no way of knowing about"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/revive/unknown/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/revive/unknown/reported
	name = "casualty: a body somebody's called in on the radio is gone for, from the far end of a long hall"
	desc = "As above, and somebody who came across the body has said so on the radio (GLOB.bot_bodies_reported): the doctor's heard, and goes."
	time_limit = 60 SECONDS

/datum/bot_scenario/revive/unknown/reported/post_spawn()
	..()
	GLOB.bot_bodies_reported[WEAKREF(patient)] = world.time

/datum/bot_scenario/revive/unknown/reported/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(patient))
		fail_reason = "the patient's gone"
		return BOT_GYM_FAIL
	return patient.stat != DEAD ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/revive/unknown/reported/on_timeout()
	fail_reason = "didn't go for a body that had been called in"
	return BOT_GYM_FAIL

/datum/bot_scenario/revive/unknown/monitor
	name = "casualty: a body whose uniform sensors are on tracking, on the crew monitor in the doctor's room, is gone for"
	desc = "As the first, with the dead one's sensors on tracking: the doctor reads it off the monitor beside it and goes."
	time_limit = 60 SECONDS

/datum/bot_scenario/revive/unknown/monitor/post_spawn()
	..()
	var/obj/item/clothing/under/U = patient.w_uniform
	if(istype(U))
		U.sensor_mode = SENSOR_COORDS

/datum/bot_scenario/revive/unknown/monitor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(patient))
		fail_reason = "the patient's gone"
		return BOT_GYM_FAIL
	return patient.stat != DEAD ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/revive/unknown/monitor/on_timeout()
	fail_reason = "didn't go for a body its monitor showed"
	return BOT_GYM_FAIL

/datum/bot_scenario/revive/unknown/in_sight
	name = "casualty: a body in plain sight is gone for"
	desc = "Five tiles down the room, sensors off, nobody's said anything: it can see them, and goes."
	time_limit = 60 SECONDS
	layout = list(
		"##############",
		"#B....C...K..#",
		"##############")

/datum/bot_scenario/revive/unknown/in_sight/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(patient))
		fail_reason = "the patient's gone"
		return BOT_GYM_FAIL
	return patient.stat != DEAD ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/revive/unknown/in_sight/on_timeout()
	fail_reason = "didn't go for a body it could see"
	return BOT_GYM_FAIL

/datum/bot_scenario/patient/unseen
	name = "casualty: a doctor doesn't set off for somebody hurt that it's never seen, twenty-odd tiles down the hall"
	desc = "A crew member with thirty brute, at the far end of a hall the doctor can't see along, their sensors off. The doctor's rounds used to find them anywhere within forty tiles."
	strict_casualties = TRUE
	time_limit = 12 SECONDS
	max_goal_attempts = 1
	layout = list(
		"##############################",
		"#B..........................C.#",
		"##############################")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment)

/datum/bot_scenario/patient/unseen/post_spawn()
	..()
	var/obj/item/clothing/under/U = patient.w_uniform
	if(istype(U))
		U.has_sensor = HAS_SENSORS
		U.sensor_mode = SENSOR_OFF

/datum/bot_scenario/patient/unseen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(patched_up() || get_dist(bot, patient) < 12)
		fail_reason = "set off for somebody it had no way of knowing was hurt"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/patient/unseen/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/patient/unseen/called
	name = "casualty: the same patient, who's called for a medic and the doctor answered, is gone to"
	desc = "As above, and the doctor took the call (called_patient, bot_requests.dm): it knows where they are, and goes and patches them up."
	time_limit = 60 SECONDS

/datum/bot_scenario/patient/unseen/called/post_spawn()
	..()
	brain.called_patient = WEAKREF(patient)
	brain.called_patient_until = world.time + 2 MINUTES

/datum/bot_scenario/patient/unseen/called/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return patched_up() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/patient/unseen/called/on_timeout()
	fail_reason = "didn't go to the patient it was called to"
	return BOT_GYM_FAIL

/datum/bot_scenario/patient/cloning/unknown
	name = "casualty: a doctor at the cloner doesn't go for a body it has no way of knowing about"
	desc = "A clonable body down the far end of a long hall, nobody's said a word and its sensors are off. The doctor at the cloner leaves it: clone_body used to take the nearest body on the level."
	strict_casualties = TRUE
	time_limit = 12 SECONDS
	max_goal_attempts = 1
	layout = list(
		"##############################",
		"#B..........................C#",
		"#.QKZ........................#",
		"##############################")

/datum/bot_scenario/patient/cloning/unknown/post_spawn()
	..()
	var/obj/item/clothing/under/U = patient.w_uniform
	if(istype(U))
		U.has_sensor = HAS_SENSORS
		U.sensor_mode = SENSOR_OFF

/datum/bot_scenario/patient/cloning/unknown/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(get_dist(bot, patient) < 12 || patient.pulledby)
		fail_reason = "set off for a body it had no way of knowing about"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/patient/cloning/unknown/on_timeout()
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Floating in a room with no gravity (bot_hazards.dm float_without_a_hold())
// ---------------------------------------------------------------------------------------------
// Batches play1114b and gen1116f: in the seven of twenty-four shifts where the gravity generator went offline, the crew spent 30,000
// seconds on an errand with a route and not a step to it (floating mid-room, nothing to push off), against a thousand in the other
// seventeen shifts. "stuck heading to the floor, rerouting" five hundred times, and not a step for eighteen minutes.

/datum/bot_scenario/bmhl/zero_g_push_off
	name = "zero-g: floating mid-room with nothing to push off, it throws something the other way and drifts to where it's going"
	desc = "No gravity, ten tiles of open floor between the bot and the goal on the far wall, a sheet of paper in its bag. A step does nothing from where it floats: it throws the paper away from the goal and drifts to the wall by it. It used to try the step for the rest of the shift."
	layout = list(
		"#####################",
		"#...................#",
		"#...................#",
		"#.........B........G#",
		"#...................#",
		"#...................#",
		"#####################")
	time_limit = 40 SECONDS
	kit_backpack = list(/obj/item/paper)

/datum/bot_scenario/bmhl/zero_g_push_off/setup()
	arena_area.has_gravity = FALSE

/datum/bot_scenario/bmhl/zero_g_nothing_to_throw
	name = "zero-g: floating with nothing to push off and nothing to throw, it says so on the radio and doesn't keep at the step"
	desc = "As the above with an empty bag and empty hands. A player has nothing to do but call for help; the bot tried the step and rerouted and gave the walk up, over and over."
	layout = list(
		"#####################",
		"#...................#",
		"#...................#",
		"#.........B........G#",
		"#...................#",
		"#...................#",
		"#####################")
	time_limit = 12 SECONDS
	max_goal_attempts = 1

/datum/bot_scenario/bmhl/zero_g_nothing_to_throw/setup()
	arena_area.has_gravity = FALSE

/datum/bot_scenario/bmhl/zero_g_nothing_to_throw/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/stuck_lines = 0
	for(var/line in transcript)
		if(findtext(line, "stuck heading to"))
			stuck_lines++
	if(stuck_lines > 2)
		fail_reason = "tried the step and rerouted [stuck_lines] times"
		return BOT_GYM_FAIL
	return bot_transcript_said("calling for help") && world.time > start_time + 6 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// A moment to take it in (bot_witness.dm react_to_sight())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/bmhl/witness_takes_a_moment
	name = "reaction: a witness takes a moment to take in a punch before it does anything about it, not the tick it lands"
	desc = "Somebody punches somebody six tiles from the bot. A person turns and shouts a third of a second to a second later; the bot did it in the tick the blow landed, whoever it was and however many were watching."
	layout = list(
		"#################",
		"#B....V.C.......#",
		"#################")
	time_limit = 10 SECONDS
	slow_reactions = TRUE
	var/mob/living/carbon/human/griefer
	var/mob/living/carbon/human/victim
	var/blow_at = 0

/datum/bot_scenario/bmhl/witness_takes_a_moment/issue_goal()
	return

/datum/bot_scenario/bmhl/witness_takes_a_moment/post_spawn()
	griefer = stand_in(first_marker("C"), "Griff Griefer")
	victim = stand_in(first_marker("V"), "Vic Victim")
	griefer.setDir(get_dir(griefer, victim))
	addtimer(CALLBACK(src, PROC_REF(punch)), 2 SECONDS)

/datum/bot_scenario/bmhl/witness_takes_a_moment/proc/punch()
	if(result != BOT_GYM_PENDING || QDELETED(griefer) || QDELETED(victim))
		return
	blow_at = world.time
	griefer.a_intent = INTENT_HARM
	griefer.UnarmedAttack(victim, TRUE)

/datum/bot_scenario/bmhl/witness_takes_a_moment/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!blow_at || brain.next_witness_time <= 0)
		return BOT_GYM_PENDING
	var/gap = (brain.next_witness_time - 4 SECONDS) - blow_at
	if(gap < 3)
		fail_reason = "turned and called it in [gap] ds after the blow: the tick it landed"
		return BOT_GYM_FAIL
	log_line("reacted [gap] ds after the blow")
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Taking its things back in hand (goals/cloning.dm take_things_back)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/patient/cloning/by_hand
	name = "cloned: it takes its things back in hand and puts them on, not straight off the floor on to its body"
	desc = "As the cloning run, and the cloned bot's telemetry is read too: a thing taken off its old body went from the floor straight on to it, which the shift's verdict calls looking robotic (equip_without_holding, 60 times in 24 shifts, nearly all of them here)."

/datum/bot_scenario/patient/cloning/by_hand/check()
	. = ..()
	if(. == BOT_GYM_PASS && patient_brain && LAZYACCESS(patient_brain.telemetry_flags, "equip_without_holding"))
		fail_reason = "put its things on straight off the floor, never holding them (x[patient_brain.telemetry_flags["equip_without_holding"]])"
		return BOT_GYM_FAIL

/datum/bot_scenario/bmhl/witness_types_the_call
	name = "reaction: a witness types out its call to Security, it isn't on the radio the moment it saw the blow"
	desc = "As above, and what the witness does about it is to call it in: a line typed out, which takes a quick typist three or four seconds, on top of the moment it takes to see what's going on. The bot's call was in the tick it decided to make it."
	layout = list(
		"#################",
		"#B....V.C.......#",
		"#################")
	time_limit = 12 SECONDS
	slow_reactions = TRUE
	var/mob/living/carbon/human/griefer
	var/mob/living/carbon/human/victim
	var/blow_at = 0

/datum/bot_scenario/bmhl/witness_types_the_call/issue_goal()
	return

/datum/bot_scenario/bmhl/witness_types_the_call/post_spawn()
	griefer = stand_in(first_marker("C"), "Griff Griefer")
	victim = stand_in(first_marker("V"), "Vic Victim")
	griefer.setDir(get_dir(griefer, victim))
	addtimer(CALLBACK(src, PROC_REF(punch)), 2 SECONDS)

/datum/bot_scenario/bmhl/witness_types_the_call/proc/punch()
	if(result != BOT_GYM_PENDING || QDELETED(griefer) || QDELETED(victim))
		return
	blow_at = world.time
	griefer.a_intent = INTENT_HARM
	griefer.UnarmedAttack(victim, TRUE)

/datum/bot_scenario/bmhl/witness_types_the_call/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!blow_at)
		return BOT_GYM_PENDING
	for(var/line in transcript)
		var/at = findtext(line, "s: called in ")
		if(!at)
			continue
		var/gap = text2num(copytext(line, 1, at)) * 10 - (blow_at - start_time)
		if(gap < 25)
			fail_reason = "called it in [gap / 10] s after the blow"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Who the killer is (goals/massacre.dm killer_it_knows())
// ---------------------------------------------------------------------------------------------
// massacre_killer() read who last hurt every body on the station off the bodies' own records, so the whole crew knew the name of a killer
// nobody had seen: three bodies and the crew sticking together against Max, who they'd never laid eyes on doing anything.

/datum/bot_scenario/duty/group_up/unseen
	name = "panic: three dead and the killer stood by it, but it never saw who did it, so it has nobody to keep away from"
	desc = "As the panic scenario with strict_casualties: the bodies are all last hurt by the man by the bot, and it saw none of it and was told nothing. It doesn't know it's him, and doesn't go off to stick with the others against him. Before 2026-11-21 it went by the bodies' records."
	strict_casualties = TRUE
	time_limit = 12 SECONDS

/datum/bot_scenario/duty/group_up/unseen/post_spawn()
	..()
	// The deaths happened a long time ago, as far as the bot's concerned: a body that's just died of a blow the last tick is a killing it saw
	for(var/mob/living/carbon/human/H in range(12, bot))
		if(H.stat == DEAD)
			H.last_assailant_at = world.time - 10 MINUTES

/datum/bot_scenario/duty/group_up/unseen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(get_dist(bot, crew) <= 4 || bot_transcript_said("with the others") || bot_transcript_said("staying with the others"))
		fail_reason = "went to the others against a killer it didn't know of"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/group_up/unseen/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/duty/group_up/saw_it
	name = "panic: three dead and it saw the killing, so it goes and sticks with the others"
	desc = "As above, and the bot saw him do it (a first-hand fact, bot_memory.dm): it knows who's killing and goes to the others."
	strict_casualties = TRUE

/datum/bot_scenario/duty/group_up/saw_it/post_spawn()
	..()
	var/mob/living/carbon/human/killer
	var/mob/living/carbon/human/body
	for(var/mob/living/carbon/human/H in range(12, bot))
		if(H.real_name == "Max Killer")
			killer = H
		else if(H.stat == DEAD && !body)
			body = H
	if(killer && body)
		brain.learn_fact(BOT_FACT_KILLED, killer, body, "the arena")

/datum/bot_scenario/bmhl/hit_takes_a_moment
	name = "reaction: hit by somebody, it takes a moment to take it in and type its call to Security, not the tick the blow lands"
	desc = "Somebody punches the bot. It fights back and radios it in, but a person takes a moment to see what's happened and then types the call out (a quick typist's three seconds or so). The bot's call was on the radio the tick the blow landed."
	layout = list(
		"#########",
		"#B.C....#",
		"#########")
	time_limit = 12 SECONDS
	slow_reactions = TRUE
	var/mob/living/carbon/human/griefer
	var/blow_at = 0

/datum/bot_scenario/bmhl/hit_takes_a_moment/issue_goal()
	return

/datum/bot_scenario/bmhl/hit_takes_a_moment/post_spawn()
	griefer = stand_in(first_marker("C"), "Griff Griefer")
	griefer.setDir(get_dir(griefer, bot))
	addtimer(CALLBACK(src, PROC_REF(punch)), 2 SECONDS)

/datum/bot_scenario/bmhl/hit_takes_a_moment/proc/punch()
	if(result != BOT_GYM_PENDING || QDELETED(griefer) || QDELETED(bot))
		return
	blow_at = world.time
	griefer.a_intent = INTENT_HARM
	griefer.UnarmedAttack(bot, TRUE)

/datum/bot_scenario/bmhl/hit_takes_a_moment/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!blow_at || brain.next_assault_report_time <= 0)
		return BOT_GYM_PENDING
	var/gap = (brain.next_assault_report_time - 600) - blow_at //bot_call_security() sets it a minute on from when the call is made
	if(gap < 25)
		fail_reason = "called Security [gap / 10] s after the blow"
		return BOT_GYM_FAIL
	log_line("called Security [gap / 10] s after the blow")
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// A flat cell (goals/mech_pilot.dm bot_step_towards())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/mech_drive/flat
	name = "mech: with a flat cell it climbs out and walks on, rather than pressing the pedal"
	desc = "A Ripley with nothing in its cell, and the far end of the room beyond it. The bot climbs in, and the Ripley won't step: it gets out and goes on foot. It sat in a flat Ripley pressing the pedal for 13 minutes (gen1116f run9, 'wouldn't step: no charge' every five seconds)."
	layout = list(
		"############",
		"#B.k.......G#",
		"############")
	time_limit = 40 SECONDS

/datum/bot_scenario/mech_drive/flat/setup()
	..()
	var/obj/mecha/M = first_placed("k")
	if(M?.cell)
		M.cell.charge = 0

/datum/bot_scenario/mech_drive/flat/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(get_turf(bot) == first_marker("G") && !istype(bot.loc, /obj/mecha))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// A walk that's stopped
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/bmhl/stalled_stroll
	name = "walking: a stroll that's stopped on one tile is let go after a while, not stood at for minutes"
	desc = "In wander with no goal, the bot has a route for a friend's walk and no step due to take it. The goal-walk watchdog (watch_for_freeze()) only looked at errands, so a stalled stroll stood there for good (a bot stood on one tile for 222 s with a route twelve tiles long, play1114b run7). It drops it inside a minute."
	layout = list(
		"##############",
		"#B..........G#",
		"##############")
	time_limit = 70 SECONDS
	max_goal_attempts = 0

/datum/bot_scenario/bmhl/stalled_stroll/issue_goal()
	return

/datum/bot_scenario/bmhl/stalled_stroll/post_spawn()
	brain.gym_scripted = FALSE
	brain.next_wander_time = world.time + 10 MINUTES //it has the one walk, then nothing else to do
	addtimer(CALLBACK(src, PROC_REF(stall)), 1 SECONDS)

/datum/bot_scenario/bmhl/stalled_stroll/proc/stall()
	if(QDELETED(bot))
		return
	brain.pursue(first_marker("G"), "follow")
	brain.cancel_step() //no step is due: the walk's stopped where it stands

/datum/bot_scenario/bmhl/stalled_stroll/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("dropping it"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/bmhl/stalled_stroll/on_timeout()
	fail_reason = "stood at a stalled stroll for the whole minute"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// Shut in with a kill to make
// ---------------------------------------------------------------------------------------------

/// The strike on its own: a killer already at its mark when it is shut away is in this step (the one a cell's prisoner stood in)
/datum/bot_goal/traitor_kill/robust/strike_only

/datum/bot_goal/traitor_kill/robust/strike_only/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/paced/strike/robust())
	return list(S)

/datum/bot_scenario/bmhl/proc/transcript_count(text)
	. = 0
	for(var/line in transcript)
		if(findtext(line, text))
			.++

/datum/bot_scenario/bmhl/shut_in_hunt
	name = "hunt: a killer shut in with no way to its mark waits, looks again, and lets the kill go"
	desc = "Apex, mid-hunt in a room with no door and no tool to cut a wall with, the mark in the next room. It went for a tool 300 times in a shift, every half second for three minutes, until the watchdog ended the step (Perry Nakata in the Brig, play1114b run10). It looks a few times, a few seconds apart, and gives the kill up inside half a minute."
	layout = list(
		"################",
		"#B...#.........#",
		"#....H....V....#",
		"################")
	time_limit = 45 SECONDS
	var/mob/living/carbon/human/mark

/datum/bot_scenario/bmhl/shut_in_hunt/setup()
	for(var/turf/T as anything in markers["H"])
		T.ChangeTurf(/turf/closed/wall)

/datum/bot_scenario/bmhl/shut_in_hunt/post_spawn()
	brain.skill = 1
	mark = stand_in(first_marker("V"), "Mark Target")

/datum/bot_scenario/bmhl/shut_in_hunt/make_goal()
	return new /datum/bot_goal/traitor_kill/robust/strike_only(null, mark)

/datum/bot_scenario/bmhl/shut_in_hunt/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/asks = transcript_count("the only way to")
	if(asks > 3)
		fail_reason = "went for a cutting tool [asks] times with none to be had"
		return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/traitor_kill"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/bmhl/shut_in_hunt/on_timeout()
	fail_reason = "still after a mark it could not get to, [transcript_count("no path to")] tries on"
	return BOT_GYM_FAIL
