// Bot gym scenarios from the 2026-11-21 bot audit, humanlike area.

// ---------------------------------------------------------------------------------------------
// Staged events that don't ride SStimer
// ---------------------------------------------------------------------------------------------
// A scenario's staged events (a shuttle leaving, a visitor speaking, a poll of what the bot is doing) were addtimer()s of 1-15 ds. In a
// fast-forwarded gym SStimer runs late against the bot's own steps (SSbot_steps), by 0.05 s to 1 s or more with the machine's load, so
// an event meant to come "after it has set off" came before or after it depending on how loaded the machine was: the dock-door scenario
// failed on it, and "an emitter switched on across the way" had it lit when the bot was 4 tiles along or 2. Events go by the bot's steps
// (gym_on_step) where they are about the walk, and by sleep() (gym_after) where they are about time.

/// What to run when the bot has taken `steps` steps.
/datum/gym_step_trigger
	var/steps_left
	var/datum/callback/what

/datum/gym_step_trigger/New(atom/movable/mover, steps, datum/callback/cb)
	. = ..()
	steps_left = steps
	what = cb
	RegisterSignal(mover, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))

/datum/gym_step_trigger/proc/stepped(atom/movable/mover, atom/oldloc, dir)
	SIGNAL_HANDLER
	if(--steps_left > 0)
		return
	UnregisterSignal(mover, COMSIG_MOVABLE_MOVED)
	INVOKE_ASYNC(what, TYPE_PROC_REF(/datum/callback, Invoke))

/// Runs what when the bot has taken its nth step, however long that takes.
/datum/bot_scenario/proc/gym_on_step(steps, datum/callback/what)
	new /datum/gym_step_trigger(bot, steps, what)

/// Runs what in `ds` deciseconds, on the tick (sleep), not when SStimer gets round to it. A scenario that's over doesn't run it.
/datum/bot_scenario/proc/gym_after(ds, datum/callback/what)
	set waitfor = FALSE
	sleep(ds)
	if(result != BOT_GYM_PENDING)
		return
	what.Invoke()

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

// ---------------------------------------------------------------------------------------------
// Hands take a beat (bot_human.dm hand_beat())
// ---------------------------------------------------------------------------------------------
// Telemetry (play1114b, 12 shifts) had a drop and a pickup in the same tick about a thousand times a shift, and the thing drawn from a
// belt or a bag clicked on its target in the tick it was drawn in (42% of 7,400 draws came less than 0.2 s before the click).

/datum/bot_scenario/jaws_from_backpack/with_a_beat
	name = "hands: the jaws drawn from the backpack are clicked on the door a moment after, not in the same instant"
	desc = "The jaws start in the backpack. A player draws them (a click on the bag) and then clicks the door (another): two inputs, not one. Telemetry had 42% of draws less than 0.2 s before the click they were for."
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_click")

/datum/bot_scenario/locker_take_only_gloves/hands_and_bag_full
	name = "hands: hands and bag full at a locker, the gloves are taken a moment after one thing is set down"
	desc = "Sent for gloves with an ear of corn and a flashlight in the hands and the bag, pockets and belt full: one thing goes down on the floor to free a hand. The gloves are taken after it, not in the same instant (a drop and a pickup in the same tick came about a thousand times a shift in the 12-shift batch play1114b)."
	kit_hands = list(/obj/item/reagent_containers/food/snacks/grown/corn, /obj/item/flashlight)
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_swap")

/datum/bot_scenario/locker_take_only_gloves/hands_and_bag_full/post_spawn()
	..()
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!bot.get_item_by_slot(slot))
			bot.equip_to_slot_or_del(new /obj/item/flashlight(bot), slot)
	if(!bot.get_item_by_slot(ITEM_SLOT_BELT))
		bot.equip_to_slot_or_del(new /obj/item/storage/belt/fannypack(bot), ITEM_SLOT_BELT)
	var/obj/item/storage/belt/fannypack/F = bot.get_item_by_slot(ITEM_SLOT_BELT)
	if(istype(F))
		for(var/i in 1 to 3)
			new /obj/item/flashlight(F)

/datum/bot_scenario/one_arm_picks_up/with_a_beat
	name = "hands: an arm gone and a wrench in the other hand, the bin is picked up a moment after the wrench goes away"
	desc = "The wrench has to go away before the matter bin can be taken in the one hand there is: two inputs, a beat apart, not one tick (a drop and a pickup in the same tick came about a thousand times a shift in play1114b)."
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_swap")

// ---------------------------------------------------------------------------------------------
// Job flows that let go of one thing and take another, and a webbing in the hand
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/kitchen_duty/fridge_full_hands/with_a_beat
	name = "hands: at the smartfridge with its hands full, a cook empties a hand and presses the button a moment after"
	desc = "Both hands and the bag full. A hand is emptied for each potato the fridge lets go of, and the button is pressed a beat after, not in the same tick (hand_beat())."
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_swap")

/datum/bot_scenario/griefed/surgeon/full_bag/with_a_beat
	name = "hands: a doctor with its bag full draws each surgery tool a moment after putting the last one away, and clicks a moment after that"
	desc = "Each operating step took the next tool out of the bag as the last went in, and clicked the patient in the same tick: a stow, a draw and a click as one input. A beat between each."
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_swap", "instant_click")

/datum/bot_scenario/clear_bag/with_a_beat
	name = "hands: emptying a bag, each thing is drawn a moment after the last is let go of"
	desc = "The bag is emptied onto a table and into a bin one thing at a time: the next is drawn a beat after the last went down, not 0.1 s after (1-3 ds)."
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_swap")

/datum/bot_scenario/mining_points/pda_on_belt
	name = "miner: with its PDA on its belt, the webbing from the voucher goes on and the PDA into the bag"
	desc = "The PDA is on the belt (a bot puts it there), so the webbing from the voucher had no place and stayed in the miner's hand for the shift. Every shuttle ride knocks down whoever is not buckled in, and a knocked-down hand drops what it holds: the webbing was down on the floor and picked up again five times a shift (play1114b run10). The PDA goes in the bag and the webbing on."

/datum/bot_scenario/mining_points/pda_on_belt/post_spawn()
	..()
	if(bot.belt)
		qdel(bot.belt)
	bot.equip_to_slot_or_del(new /obj/item/pda(bot), ITEM_SLOT_BELT)
	brain.next_id_consolidation_check_time = world.time + 10 MINUTES //it moves the PDA to the ID slot given the chance (consolidate_id_into_pda(), bot_items.dm)

/datum/bot_scenario/mining_points/pda_on_belt/check()
	. = ..()
	if(. == BOT_GYM_PASS && !istype(bot.belt, /obj/item/storage/belt/mining/vendor))
		fail_reason = "left the webbing in its hand with the PDA on its belt"
		return BOT_GYM_FAIL

/// What was on the belt in play1114b run10 (Bailey Rourke, equipped at 207 s): the miner's proto-kinetic accelerator, not a PDA.
/datum/bot_scenario/mining_points/pda_on_belt/accelerator
	name = "miner: with its proto-kinetic accelerator on its belt, the webbing from the voucher goes on and the accelerator into the bag"
	desc = "Bailey Rourke in play1114b run10 had the accelerator on its belt (equipped at 207 s) and carried the voucher's webbing in its hand for the shift, dropping it on every shuttle ride."

/datum/bot_scenario/mining_points/pda_on_belt/accelerator/post_spawn()
	..()
	qdel(bot.belt)
	bot.equip_to_slot_or_del(new /obj/item/gun/energy/kinetic_accelerator(bot), ITEM_SLOT_BELT)

// ---------------------------------------------------------------------------------------------
// Machine steps that put a disk in and take it out in the same tick, a purchase right after a hand is emptied, the toolbelt case
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/nanite_disk_hands_full/with_a_beat
	name = "hands: both hands full at the nanite machines, the disk goes in, the program downloads and the disk comes out a moment apart"
	desc = "A hand is emptied for the blank disk, and the disk is put in the hub, downloaded to and ejected, then put in the cloud and ejected, each a click of its own: they were all in one tick (instant_swap x3)."
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_swap")

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_kit/with_a_beat
	name = "hands: both hands and the bag full, a traitor puts something down and buys what it needs a moment after"
	desc = "A hand is emptied for what the uplink gives, and the purchase is the next click, not the same tick."
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "instant_swap")

/// A toolbelt on the belt: nobody swaps it for the webbing. The webbing is put down and the capsule out of it goes in the bag.
/datum/bot_scenario/mining_points/pda_on_belt/toolbelt
	name = "miner: with a toolbelt on its belt, the capsule comes out of the voucher's webbing and the webbing is left"
	desc = "The webbing had no place and stayed in the miner's hand for the shift, dropped on every shuttle ride. A toolbelt stays on the belt; the capsule, the only thing in the webbing a miner wants, goes in the bag and the webbing is put down."

/datum/bot_scenario/mining_points/pda_on_belt/toolbelt/post_spawn()
	..()
	qdel(bot.belt)
	bot.equip_to_slot_or_del(new /obj/item/storage/belt/utility(bot), ITEM_SLOT_BELT)

/datum/bot_scenario/mining_points/pda_on_belt/toolbelt/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(card))
		fail_reason = "its card's gone"
		return BOT_GYM_FAIL
	if(card.mining_points != 100 || machine.points) //1,500 less the scanner (800) and the kit (600)
		return BOT_GYM_PENDING
	if(brain.find_carried_tool(/obj/item/storage/belt/mining/vendor))
		fail_reason = "still carrying the webbing it has no place for"
		return BOT_GYM_FAIL
	if(!brain.find_carried_tool(/obj/item/survivalcapsule))
		fail_reason = "left the capsule in the webbing"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// A bomb with both hands full when the trigger is taken (goals/toxins.dm fetch_bomb_parts)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/tank_juggle/valve_and_trigger
	name = "toxins: a plasma tank and the valve in its hands, the trigger on the table and a full bag, and it still builds the bomb"
	desc = "bm_final run4, Charlie Vasquez: the plasma tank in one hand, the valve picked up in the other; taking the trigger put the valve down for a hand, and fetch_bomb_parts failed the valve for not being carried, having tried it already, three times and \"isn't working\". The valve is bulky and the bag is full: the part it set down is still its own, and it builds the bomb with the valve on the floor."
	time_limit = 60 SECONDS
	kit_hands = list(/obj/item/transfer_valve, /obj/item/tank/internals/plasma)
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)
	layout = list(
		"##########",
		"#Bnt.....#",
		"##########")

/datum/bot_scenario/fixes1112/tank_juggle/valve_and_trigger/setup()
	lab = new
	lab.stage = 20
	lab.rest_until = world.time + 10 MINUTES //the duty its success chains to (try_start()) finds nothing more to do
	GLOB.bot_toxins = lab
	lab.cold_tank = place("n", new /obj/item/tank/internals/oxygen/empty(first_marker("n")))
	// The trigger on a table in Science, where fetch_bomb_parts looks for the lab's own first and goes for it with take_in_hand()
	var/turf/there = first_marker("t")
	new /obj/item/assembly/timer(there)
	var/area/science/lab_area = new
	lab_area.name = "Gym Science [run_index]"
	lab_area.contents += there

/datum/bot_scenario/fixes1112/tank_juggle/valve_and_trigger/post_spawn()
	// Pockets and belt full too: nothing in a hand has anywhere to go
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!bot.get_item_by_slot(slot))
			bot.equip_to_slot_or_del(new /obj/item/flashlight(bot), slot)
	if(!bot.get_item_by_slot(ITEM_SLOT_BELT))
		bot.equip_to_slot_or_del(new /obj/item/storage/belt/fannypack(bot), ITEM_SLOT_BELT)
	var/obj/item/storage/belt/fannypack/F = bot.get_item_by_slot(ITEM_SLOT_BELT)
	if(istype(F))
		for(var/i in 1 to 3)
			new /obj/item/flashlight(F)
	lab.hot_tank = locate(/obj/item/tank/internals/plasma) in bot.held_items
	if(!lab.hot_tank || !(locate(/obj/item/transfer_valve) in bot.held_items))
		log_line("SETUP: hands hold [english_list(bot.held_items, "nothing")], not the plasma tank and the valve")

// ---------------------------------------------------------------------------------------------
// Hands between jobs (tidy_hands(), bot_human.dm)
// ---------------------------------------------------------------------------------------------
// The Turing judge (tools/bot_gym/turing.py, 2026-11-28) found the hands the biggest tell: between jobs a bot had something in a hand 68-73%
// of the time against the player's 42-44%, and nothing ever put a tool away once its job was done (held_report.py). tidy_hands() is reached
// by name here (gym_tidies_hands), so the build from before it compiles too.

/datum/bot_scenario/bmhl/tidy
	layout = list(
		"#######",
		"#..B..#",
		"#######")
	time_limit = 20 SECONDS
	max_goal_attempts = 0
	/// When each kit item left its hands (COMSIG_ITEM_DROPPED), by item.
	var/list/left_hands_at = list()

/datum/bot_scenario/bmhl/tidy/issue_goal()
	return

/datum/bot_scenario/bmhl/tidy/post_spawn()
	if("gym_tidies_hands" in brain.vars)
		brain.vars["gym_tidies_hands"] = TRUE
	for(var/obj/item/I in bot.held_items)
		RegisterSignal(I, COMSIG_ITEM_DROPPED, PROC_REF(note_left_hands))

/datum/bot_scenario/bmhl/tidy/proc/note_left_hands(obj/item/source)
	SIGNAL_HANDLER
	if(!left_hands_at[source])
		left_hands_at[source] = world.time

/// Whether I is on the bot (worn, on the belt, in the bag or a pocket) and not in a hand.
/datum/bot_scenario/bmhl/tidy/proc/put_away_on_bot(obj/item/I)
	if(QDELETED(I) || (I in bot.held_items))
		return FALSE
	var/atom/holder = I.loc
	while(holder && holder != bot && !isturf(holder))
		holder = holder.loc
	return holder == bot

/datum/bot_scenario/bmhl/tidy/tools
	name = "hands: between jobs it puts the screwdriver and wrench in its hands away, a beat apart, not on the floor"
	desc = "No job, a screwdriver in one hand and a wrench in the other, a bag with room. Both go on the belt, in a pocket or the bag within a few seconds, one input at a time (at least 0.2 s apart), and neither on the floor. Nothing put tools away between jobs: shift batch night1122b_after had screwdrivers and wrenches in bots' hands for 8% of their time between jobs."
	kit_hands = list(/obj/item/screwdriver, /obj/item/wrench)

/datum/bot_scenario/bmhl/tidy/tools/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/screwdriver/S = locate() in bot.GetAllContents()
	var/obj/item/wrench/W = locate() in bot.GetAllContents()
	for(var/obj/item/I in placed_items())
		if(isturf(I.loc))
			fail_reason = "set [I] down on the floor"
			return BOT_GYM_FAIL
	if(!put_away_on_bot(S) || !put_away_on_bot(W))
		return BOT_GYM_PENDING
	// When each went: the bot's own "put X away" lines (a move from a hand to a slot or a bag sends no COMSIG_ITEM_DROPPED)
	var/s_at = transcript_time("put [S] away")
	var/w_at = transcript_time("put [W] away")
	var/gap = abs(s_at - w_at)
	log_line("put away: [S] to [S.loc], [W] to [W.loc], [gap] s apart")
	if(isnull(s_at) || isnull(w_at))
		fail_reason = "put away without saying when"
		return BOT_GYM_FAIL
	if(gap < 0.2)
		fail_reason = "put both away in the same instant ([gap] s apart)"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The time (s into the run) of the first transcript line with `text`, or null.
/datum/bot_scenario/bmhl/tidy/proc/transcript_time(text)
	for(var/line in transcript)
		if(findtext(line, text))
			return text2num(copytext(line, 1, findtext(line, "s:")))
	return null

/datum/bot_scenario/bmhl/tidy/proc/placed_items()
	. = list()
	for(var/obj/item/I in left_hands_at)
		. += I
	for(var/obj/item/I in bot.GetAllContents())
		if(istype(I, /obj/item/screwdriver) || istype(I, /obj/item/wrench))
			. |= I

/datum/bot_scenario/bmhl/tidy/tools/on_timeout()
	fail_reason = "still holding [english_list(bot.held_items, "nothing")] after [time_limit / 10] s between jobs"
	return BOT_GYM_FAIL

/datum/bot_scenario/bmhl/tidy/firesuit
	name = "hands: a firesuit it has no room for and isn't wearing is left where it stands, and a stroll doesn't take it back"
	desc = "No job, an emergency firesuit in hand (bulky: no bag takes it) and none worn. It's left on the floor rather than carried about or put on, and the stroll's look round (find_item_goal()) doesn't go back for it. Shift batch night1122b_after had bots carrying emergency firesuits for 3.4% of their time between jobs, and radiation suits for 1.5%."
	kit_hands = list(/obj/item/clothing/suit/fire)
	var/obj/item/clothing/suit/fire/suit

/datum/bot_scenario/bmhl/tidy/firesuit/post_spawn()
	..()
	suit = locate() in bot.held_items

/datum/bot_scenario/bmhl/tidy/firesuit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(suit))
		fail_reason = "the firesuit's gone"
		return BOT_GYM_FAIL
	if(suit in bot.held_items)
		return BOT_GYM_PENDING
	if(!isturf(suit.loc))
		fail_reason = "the firesuit went to [suit.loc], not the floor ([bot.wear_suit == suit ? "it put it on" : "somewhere on it"])"
		return BOT_GYM_FAIL
	var/atom/A = brain.find_item_goal()
	log_line("left [suit] on the floor; a look round for something to pick up: [A || "nothing"]")
	if(A == suit)
		fail_reason = "its next stroll would go straight back for the firesuit"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/bmhl/tidy/firesuit/on_timeout()
	fail_reason = "still carrying the firesuit after [time_limit / 10] s between jobs"
	return BOT_GYM_FAIL

/datum/bot_scenario/bmhl/tidy/toolbox_kept
	name = "hands: a toolbox too big for its bag stays in its hand between jobs (control)"
	desc = "No job and a mechanical toolbox in hand (bulky: no bag takes it). People carry toolboxes about, so it's kept, not left on the floor. Passes before tidy_hands() too: it guards against putting down what's worth keeping."
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	time_limit = 12 SECONDS

/datum/bot_scenario/bmhl/tidy/toolbox_kept/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!(locate(/obj/item/storage/toolbox) in bot.held_items))
		fail_reason = "let go of the toolbox"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/bmhl/tidy/toolbox_kept/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/bmhl/tidy/on_its_own
	name = "hands: an ordinary bot between jobs puts the crowbar in its hand away by itself"
	desc = "Not a scripted gym bot: its own wander tick (handle_wander()) runs, with no stroll due. The crowbar in its hand goes on the belt, in a pocket or the bag, not the floor."
	kit_hands = list(/obj/item/crowbar)

/datum/bot_scenario/bmhl/tidy/on_its_own/post_spawn()
	for(var/obj/item/I in bot.held_items)
		RegisterSignal(I, COMSIG_ITEM_DROPPED, PROC_REF(note_left_hands))
	brain.gym_scripted = FALSE
	brain.next_wander_time = world.time + 10 MINUTES //nowhere to stroll to: only what happens between strolls

/datum/bot_scenario/bmhl/tidy/on_its_own/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/crowbar/C = locate() in bot.GetAllContents()
	if(!C)
		C = locate() in get_turf(bot)
		if(C)
			fail_reason = "set the crowbar down on the floor"
			return BOT_GYM_FAIL
		fail_reason = "the crowbar's gone"
		return BOT_GYM_FAIL
	if(put_away_on_bot(C))
		log_line("put [C] away to [C.loc]")
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/bmhl/tidy/on_its_own/on_timeout()
	fail_reason = "still holding the crowbar after [time_limit / 10] s between jobs"
	return BOT_GYM_FAIL

/datum/bot_scenario/bmhl/tidy/lamp
	name = "hands: a lit desk lamp it took up is left behind between jobs in a lit room"
	desc = "No job, a desk lamp in hand (on, as they come; bulky, and force 10 so it counted as a weapon worth keeping), and the room lit. It's left on the floor, not carried about. Batch hands1128_after: kept for being lit, lamps were carried for 4.2% of bots' time between jobs."
	kit_hands = list(/obj/item/flashlight/lamp)

/datum/bot_scenario/bmhl/tidy/lamp/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/flashlight/lamp/L = locate() in bot.held_items
	if(L)
		return BOT_GYM_PENDING
	L = locate() in get_turf(bot)
	if(!L)
		fail_reason = "the lamp went somewhere other than the floor"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/bmhl/tidy/lamp/on_timeout()
	fail_reason = "still carrying the lamp after [time_limit / 10] s between jobs"
	return BOT_GYM_FAIL

/datum/bot_scenario/bmhl/seated_set_down
	name = "seated: sat at a desk with something it set down two tiles off, it doesn't start a walk back to it from the chair"
	desc = "An ordinary bot (not scripted) buckled to a chair for a long sit, a wrench it set down for a moment two tiles away. go_back_for_set_down() started a walk to it that a buckled bot can't take: a Head of Personnel sat at its desk 'stuck' in one for 638 s (stuck_walks.py, hands1128_after run1). It stays sat with no walk, and goes for it once it's up."
	layout = list(
		"#######",
		"#B.w..#",
		"#######")
	time_limit = 10 SECONDS
	max_goal_attempts = 0
	var/obj/item/wrench/wrench

/datum/bot_scenario/bmhl/seated_set_down/issue_goal()
	return

/datum/bot_scenario/bmhl/seated_set_down/post_spawn()
	var/obj/structure/chair/C = new(get_turf(bot))
	C.buckle_mob(bot, TRUE)
	wrench = new(first_marker("w"))
	LAZYADD(brain.set_down_items, wrench)
	brain.gym_scripted = FALSE
	brain.next_wander_time = world.time + 10 MINUTES
	brain.hangout_until = world.time + 10 MINUTES //a long sit at the desk

/datum/bot_scenario/bmhl/seated_set_down/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.pursuing_kind == "follow" && brain.pursue_target == wrench)
		fail_reason = "set off from the chair back for the wrench ([bot.buckled ? "still buckled" : "got up"])"
		return BOT_GYM_FAIL
	if(!bot.buckled)
		fail_reason = "got up from a long sit"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/bmhl/seated_set_down/on_timeout()
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Walking like a person (walk_pause(), corner_overshoot(), bot_human.dm)
// ---------------------------------------------------------------------------------------------
// The Turing judge (tools/bot_gym/turing.py slice --calm --where "move_frac > 0.6", 2026-11-28): on the move, the player's walks broke
// off for a moment more often (6 brief stops a minute against 4; moving stretches 5.75 s against 9 s) and doubled back more (20% of
// seconds against 9%). What only the fix adds is reached by name (gym_walks_like_people, steps_to_pause, overshoot_chance).

/datum/bot_scenario/bmhl/walk
	time_limit = 40 SECONDS
	/// When each step was taken, and every tile stood on.
	var/list/moved_at = list()
	var/list/stood_on = list()

/datum/bot_scenario/bmhl/walk/post_spawn()
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(note_move))
	if("gym_walks_like_people" in brain.vars)
		brain.vars["gym_walks_like_people"] = TRUE

/// An everyday errand to G: a gym walk (gym_reach) is one that never rests and braves bad air, which a walk at its ease isn't
/datum/bot_goal/gym_reach/everyday
	never_rests = FALSE
	braves_bad_air = FALSE

/datum/bot_scenario/bmhl/walk/make_goal()
	var/datum/bot_goal/gym_reach/everyday/G = new
	G.target = first_marker("G")
	return G

/datum/bot_scenario/bmhl/walk/proc/note_move(datum/source)
	SIGNAL_HANDLER
	moved_at += world.time
	stood_on |= get_turf(bot)

/// The longest it stood between two steps, in deciseconds, once it's under way (the first few steps of a walk come slower: a bot
/// setting off takes a moment, 0.9-1.4 s in a gym run, whether it stops on the way or not).
/datum/bot_scenario/bmhl/walk/proc/longest_stand()
	. = 0
	for(var/i in 5 to length(moved_at))
		. = max(., moved_at[i] - moved_at[i - 1])

/datum/bot_scenario/bmhl/walk/pauses
	name = "walking: on a long everyday walk it stops for a moment on the way, a second or two, not tile after tile to the end"
	desc = "A 37-tile corridor, an everyday errand to the end, a stop due eight steps in. It stops once for 1-2 s and gets there."
	layout = list(
		"#######################################",
		"#B....................................G#",
		"#######################################")

/datum/bot_scenario/bmhl/walk/pauses/post_spawn()
	..()
	if("steps_to_pause" in brain.vars)
		brain.vars["steps_to_pause"] = 8

/datum/bot_scenario/bmhl/walk/pauses/check_success_conditions()
	var/stood = longest_stand()
	log_line("longest stand between two steps: [stood / 10] s, [length(moved_at)] steps")
	if(stood < 9)
		return "walked the whole way without a stop (the longest between two steps was [stood / 10] s)"
	if(stood > 25)
		return "stood [stood / 10] s on the way: a moment, not a freeze"
	return null

/datum/bot_scenario/bmhl/walk/hurried
	name = "walking: in a hurry (the air's not right) it doesn't stop on the way (control)"
	desc = "The same corridor and the same stop due, but the bot's worried (urgency concerned): no stop. Passes before walk_pause() too: it guards against stopping when there's a reason not to."
	urgency_override = 1 //BOT_URGENCY_CONCERNED
	layout = list(
		"#######################################",
		"#B....................................G#",
		"#######################################")

/datum/bot_scenario/bmhl/walk/hurried/post_spawn()
	..()
	if("steps_to_pause" in brain.vars)
		brain.vars["steps_to_pause"] = 8

/datum/bot_scenario/bmhl/walk/hurried/check_success_conditions()
	var/stood = longest_stand()
	log_line("longest stand between two steps: [stood / 10] s")
	if(stood >= 9)
		return "stopped for [stood / 10] s on the way while worried"
	return null

/datum/bot_scenario/bmhl/walk/corner
	name = "walking: after a straight run it now and then takes a turn a step late, past the corner and back, and still gets there"
	desc = "Five tiles east, then the way turns south; the corridor goes on a tile past the turn (o). With a late turn certain (overshoot_chance 100), it steps on to o, back to the corner and down to the end."
	layout = list(
		"#########",
		"#B....+o#",
		"######.##",
		"######.##",
		"######G##",
		"#########")

/datum/bot_scenario/bmhl/walk/corner/post_spawn()
	..()
	if("overshoot_chance" in brain.vars)
		brain.vars["overshoot_chance"] = 100
	if("steps_to_pause" in brain.vars)
		brain.vars["steps_to_pause"] = 999

/datum/bot_scenario/bmhl/walk/corner/check_success_conditions()
	log_line("stood on: [english_list(stood_on)]")
	if(!(first_marker("o") in stood_on))
		return "turned at the corner without a step past it"
	return null
