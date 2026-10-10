// Bot Shift - a whole shift on the real station, crewed by bots and fast-forwarded.
//
// The Bot Gym (bot_gym.dm) tests one behaviour at a time in a sealed arena. This is the other
// half: it boots the real map, starts the round, late-joins a crew of bots and leaves them to it.
// Nothing is scripted - they do whatever their jobs have them do, for a whole shift. With timewarp
// on (admin/timewarp.dm) a 30 minute shift takes a couple of minutes.
//
// At the end every bot is judged (alive, never frozen, no robotic tells), so is the work each
// department should have got done (engine running, air loop set, trays planted...), and so is
// the code (no bot AI exceptions, no runtimes in bot code).
//
// Run it:   tools/bot_gym/run_bot_shift.sh [minutes] [crew]
// or boot:  DreamDaemon hippiestation.dmb -params "bot-shift=30&timewarp=0"
//           also: bot-crew=Station Engineer*2,Botanist    bot-events=1 (leave random events on)
//                 bot-profile=1 (profile the shift; read it with tools/bot_gym/shift_profile.py)
// Results:  data/bot_shift/summary.txt, results.json and timeline.txt
//
// How fast a shift runs is set by how busy the server is, which is mostly the bots' pathfinding -
// the summary's load and pathfinding lines say how that went. A run where the server couldn't keep
// up says so, because bots then run slow in game time and look stuck when they aren't.
//
// To judge more of a department's work, add a /datum/bot_shift_check below.

#define BOT_SHIFT_DEFAULT_MINUTES 30
#define BOT_SHIFT_DEFAULT_CREW "Chief Engineer,Station Engineer*2,Atmospheric Technician,Botanist,Medical Doctor,Chemist,Security Officer,Assistant*2,Janitor,Cook,Bartender,Scientist,Cargo Technician,Quartermaster"
/// Late-joiners trickle in rather than all appearing on the same tick.
#define BOT_SHIFT_ARRIVAL_GAP (3 SECONDS)
/// Standing still this long with nothing going on gets a warning...
#define BOT_SHIFT_IDLE_WARN (60 SECONDS)
/// ...and this long is a bot that has frozen up.
#define BOT_SHIFT_STUCK (3 MINUTES)
/// One goal taking this long is worth a look.
#define BOT_SHIFT_SLOW_GOAL (10 MINUTES)
/// Giving up on the same kind of goal this often without ever managing it is worth a look.
#define BOT_SHIFT_FUTILE_GOAL 3

GLOBAL_DATUM(bot_shift, /datum/bot_shift)

/datum/bot_brain
	/// This bot's record in the running Bot Shift, if there is one.
	var/datum/bot_shift_member/shift_member

/datum/bot_goal
	/// world.time this goal was handed to a bot, for Bot Shift's goal timing.
	var/shift_started_at

/proc/bot_shift_clock(deciseconds)
	var/seconds = round(deciseconds / 10)
	return "[round(seconds / 60)]:[seconds % 60 < 10 ? "0" : ""][seconds % 60]"

/proc/bot_shift_duration(deciseconds)
	var/seconds = round(deciseconds / 10)
	return seconds >= 60 ? "[round(seconds / 60)]m [seconds % 60]s" : "[seconds]s"

// ---------------------------------------------------------------------------------------------
// The runner
// ---------------------------------------------------------------------------------------------

/// Starts the round, runs a bot-crewed shift of the given length, writes the results, shuts down.
/proc/run_bot_shift(minutes, crew_text)
	// Headless: nobody is connected, and with sleep_offline on the world pauses.
	Master.sleep_offline_after_initializations = FALSE
	world.sleep_offline = FALSE
	if(!(BOT_SHIFT_EVENTS_PARAMETER in world.params))
		CONFIG_SET(flag/allow_random_events, FALSE) //a meteor shower isn't the bots' doing - keep shifts comparable
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	var/datum/bot_shift/shift = new(minutes, crew_text)
	GLOB.bot_shift = shift
	shift.run_shift()
	shift.write_results()
	log_world("BOT SHIFT: done")
	Master.Shutdown()
	qdel(world)

/datum/bot_shift
	/// How long the shift runs, in game time.
	var/length
	var/crew_text
	var/start_time
	var/real_start_ms
	var/real_end_ms
	var/list/datum/bot_shift_member/members = list()
	var/list/datum/bot_shift_check/checks = list()
	var/list/timeline = list()
	/// "file:line" -> list("count", "error", "bot_code") for every runtime during the shift.
	var/list/runtime_sites = list()
	/// Exceptions the bot AI caught itself (BOT AI EXCEPTION in runtime.log).
	var/list/bot_exceptions = list()
	var/bot_exception_count = 0
	/// Server load over the shift, see bot_gym_sample_load() (bot_gym.dm).
	var/list/load = list("seconds" = 0, "sum" = 0, "peak" = 0, "over" = 0)
	/// The BYOND profiler's figures for the shift, as JSON, when booted with bot-profile.
	var/profile
	/// GLOB.astar_tally as the shift began, then what the shift added to it.
	var/list/pathfinding

/datum/bot_shift/New(minutes, crew_text)
	length = clamp(text2num("[minutes]") || BOT_SHIFT_DEFAULT_MINUTES, 1, 600) MINUTES
	src.crew_text = replacetext(crew_text || BOT_SHIFT_DEFAULT_CREW, "_", " ")

/// Game time since the shift began.
/datum/bot_shift/proc/elapsed()
	return world.time - start_time

/datum/bot_shift/proc/note(text)
	timeline += "[bot_shift_clock(elapsed())]  [text]"

/datum/bot_shift/proc/speed()
	var/real = (real_end_ms || timewarp_real_ms()) - real_start_ms
	return real > 0 ? round(elapsed() * 100 / real, 0.1) : 0

/datum/bot_shift/proc/run_shift()
	start_time = world.time
	real_start_ms = timewarp_real_ms()
	log_world("BOT SHIFT: [bot_shift_clock(length)] shift, crew: [crew_text]")
	pathfinding = GLOB.astar_tally.Copy()
	if(BOT_SHIFT_PROFILE_PARAMETER in world.params)
		world.Profile(PROFILE_RESTART)
	muster()
	for(var/path in subtypesof(/datum/bot_shift_check))
		var/datum/bot_shift_check/check = new path(src)
		if(check.name && check.worker())
			checks += check
			check.begin()
	var/next_report = start_time + 1 MINUTES
	var/second = 0
	while(elapsed() < length)
		sleep(1 SECONDS)
		second++
		for(var/datum/bot_shift_member/member as anything in members)
			member.sample()
		bot_gym_sample_load(load)
		if(!(second % 5))
			for(var/datum/bot_shift_check/check as anything in checks)
				check.poll()
		if(world.time >= next_report)
			next_report += 1 MINUTES
			log_world("BOT SHIFT: [bot_shift_clock(elapsed())] of [bot_shift_clock(length)], [speed()]x")
	real_end_ms = timewarp_real_ms()
	for(var/count in pathfinding)
		pathfinding[count] = GLOB.astar_tally[count] - pathfinding[count]
	if(BOT_SHIFT_PROFILE_PARAMETER in world.params)
		profile = world.Profile(PROFILE_REFRESH, format = "json")
		world.Profile(PROFILE_STOP)
	for(var/datum/bot_shift_check/check as anything in checks)
		check.poll()

/// Late-joins the crew, one at a time. An entry is a job title, optionally "*N" for several.
/datum/bot_shift/proc/muster()
	for(var/entry in splittext(crew_text, ","))
		var/list/parts = splittext(entry, "*")
		var/job = trim(parts[1])
		if(!job)
			continue
		// "fill:25" is 25 arrivals in whatever jobs the population manager would give them (bot_population.dm).
		var/fill = findtext(job, "fill:") == 1 ? text2num(copytext(job, 6)) : 0
		for(var/i in 1 to clamp(fill || (length(parts) > 1 ? text2num(parts[2]) : 1), 1, fill ? 60 : 20))
			if(fill)
				job = GLOB.bot_population.pick_job() || "Assistant"
			var/mob/living/carbon/human/body = SSjob.GetJob(job) ? spawn_bot_crew_member(job) : null
			var/datum/bot_shift_member/member = new(src, job, body)
			members += member
			note(body ? "[member.label()] joined the crew" : "nobody could join as [job]")
			sleep(BOT_SHIFT_ARRIVAL_GAP)

/// Called from world/Error() for every runtime while a shift is running. Runs inside the error
/// handler: keep it to plain list work.
/datum/bot_shift/proc/note_runtime(exception/E)
	var/site = "[E.file]:[E.line]"
	var/list/entry = runtime_sites[site]
	if(!entry)
		entry = list("count" = 0, "error" = "[E.name]", "bot_code" = !!findtext("[E.file]", "bots_ai"))
		runtime_sites[site] = entry
		if(entry["bot_code"])
			note("runtime in bot code: [E.name] at [site]")
	entry["count"]++

/// Called where the bot AI catches an exception of its own (bot_log_exception(), bot_brain/process()).
/datum/bot_shift/proc/note_bot_exception(text)
	bot_exception_count++
	if(length(bot_exceptions) < 20)
		bot_exceptions += text
	note(text)

// ---------------------------------------------------------------------------------------------
// One crew member
// ---------------------------------------------------------------------------------------------

/datum/bot_shift_member
	var/datum/bot_shift/shift
	var/job
	var/name
	var/mob/living/carbon/human/body
	var/datum/bot_brain/brain
	var/turf/last_turf
	var/tiles_walked = 0
	var/list/areas_seen = list()
	/// Last time the bot was knocked down or resting on purpose - stillness is counted from here.
	var/quiet_since = 0
	var/longest_still = 0
	var/longest_still_note
	var/still_flagged = FALSE
	var/down_seconds = 0
	var/space_seconds = 0
	/// Unconscious right now - the timeline notes each time that starts, with what the bot had to breathe.
	var/collapsed = FALSE
	var/died_at
	var/death_note
	/// Kind of goal -> list(times succeeded, times given up).
	var/list/goals = list()
	var/longest_goal = 0
	var/longest_goal_kind
	/// Telemetry tells (bot_telemetry.dm), copied when the bot dies or the shift ends.
	var/list/tells
	var/final_health

/datum/bot_shift_member/New(datum/bot_shift/shift, job, mob/living/carbon/human/body)
	src.shift = shift
	src.job = job
	src.body = body
	brain = body?.bot_brain
	name = body ? body.real_name : "(nobody)"
	if(brain)
		brain.shift_member = src
		quiet_since = world.time

/datum/bot_shift_member/proc/label()
	return "[name] ([job])"

/datum/bot_shift_member/proc/where()
	var/turf/T = get_turf(body) || last_turf
	return T ? "in [get_area(T)] ([T.x],[T.y],[T.z])" : "nowhere"

/// What the bot is in the middle of, for explaining why it's standing still.
/datum/bot_shift_member/proc/doing()
	if(brain.current_goal)
		. = "on [bot_telemetry_short(brain.current_goal.type)]"
		if(brain.current_strategy && brain.current_step_index && brain.current_step_index <= length(brain.current_strategy.steps))
			var/datum/bot_step/step = brain.current_strategy.steps[brain.current_step_index]
			. += ", step [bot_telemetry_short(step.type)]"
		if(brain.suspended_goal)
			. += " (a fetch for [bot_telemetry_short(brain.suspended_goal.type)])"
	else
		. = "[brain.state] with no goal"
	. += brain.pursuing_kind ? ", walking to a [brain.pursuing_kind]" : ", not walking anywhere"

/datum/bot_shift_member/proc/damage()
	return "brute [round(body.getBruteLoss())], burn [round(body.getFireLoss())], toxin [round(body.getToxLoss())], suffocation [round(body.getOxyLoss())]"

/// What the bot has to breathe and what it's wearing, for explaining a collapse or a death.
/datum/bot_shift_member/proc/air_supply()
	var/obj/item/tank/breathing = body.internal
	. = breathing ? "breathing from [breathing] at [round(breathing.air_contents.return_pressure())] kPa" : "no internals running"
	var/list/spares = list()
	for(var/obj/item/tank/internals/spare in body.GetAllContents())
		if(spare != breathing)
			spares += "[spare] at [round(spare.air_contents.return_pressure())] kPa"
	if(length(spares))
		. += ", carrying [english_list(spares)]"
	var/list/worn = list()
	for(var/obj/item/clothing/item in list(body.wear_suit, body.head, body.wear_mask))
		worn += "[item]"
	. += length(worn) ? ", wearing [english_list(worn)]" : ", no suit, helmet or mask"
	var/turf/open/here = get_turf(body)
	if(istype(here))
		var/datum/gas_mixture/air = here.return_air()
		. += ", air here at [round(air.return_pressure())] kPa"

/// Once a second.
/datum/bot_shift_member/proc/sample()
	if(!brain) //never joined, or dead and wrapped up
		return
	if(QDELETED(body) || body.stat == DEAD)
		died()
		return
	var/turf/T = get_turf(body)
	if(T && T != last_turf)
		if(last_turf && T.z == last_turf.z)
			tiles_walked += get_dist(T, last_turf)
		last_turf = T
		areas_seen["[get_area(T)]"] = TRUE
	if(isspaceturf(T))
		space_seconds++
	if(body.stat != CONSCIOUS)
		if(!collapsed)
			collapsed = TRUE
			shift.note("[label()] collapsed [where()] - [damage()]; [air_supply()]; was [doing()]")
	else
		collapsed = FALSE
	if(body.stat != CONSCIOUS || body.incapacitated())
		down_seconds++
		quiet_since = world.time
		return
	if((body.buckled && world.time < brain.hangout_until) || brain.holding_duty)
		quiet_since = world.time //sitting down for a while is a choice, not a freeze - so is waiting for the shuttle (bot_duties.dm)
		return
	var/still = world.time - max(brain.telemetry_last_activity, quiet_since)
	if(still > longest_still)
		longest_still = still
		longest_still_note = "[where()], [doing()]"
	if(still < BOT_SHIFT_IDLE_WARN)
		still_flagged = FALSE
	else if(!still_flagged)
		still_flagged = TRUE
		shift.note("[label()] has stood still for [bot_shift_duration(still)] [where()], [doing()]")

/datum/bot_shift_member/proc/died()
	died_at = shift.elapsed()
	if(QDELETED(body))
		death_note = "body destroyed, last seen [where()]"
	else
		death_note = "[where()] - [damage()]; [air_supply()]; was [doing()]"
	shift.note("[label()] died [death_note]")
	wrap_up()

/// Takes what the report needs and lets go of the mob, so a destroyed body isn't kept from being deleted.
/datum/bot_shift_member/proc/wrap_up()
	if(!brain)
		return
	tells = brain.telemetry_flags ? brain.telemetry_flags.Copy() : list()
	if(!QDELETED(body))
		final_health = round(body.health)
	var/datum/bot_goal/open = brain.current_goal
	if(open?.shift_started_at && isnull(died_at))
		note_goal_time(open, world.time - open.shift_started_at)
	brain.shift_member = null
	brain = null
	body = null

/datum/bot_shift_member/proc/note_goal_time(datum/bot_goal/goal, took)
	if(took > longest_goal)
		longest_goal = took
		longest_goal_kind = bot_telemetry_short(goal.type)

/datum/bot_shift_member/proc/goal_ended(datum/bot_goal/goal, success)
	if(!goal)
		return
	var/kind = bot_telemetry_short(goal.type)
	var/list/tally = goals[kind]
	if(!tally)
		goals[kind] = tally = list(0, 0)
	tally[success ? 1 : 2]++
	if(goal.shift_started_at)
		note_goal_time(goal, world.time - goal.shift_started_at)

/// What a watching player would have reported as broken.
/datum/bot_shift_member/proc/problems()
	. = list()
	if(isnull(tells))
		. += "couldn't join the round as [job]"
		return
	if(!isnull(died_at))
		. += "died at [bot_shift_clock(died_at)] [death_note]"
	if(longest_still >= BOT_SHIFT_STUCK)
		. += "froze for [bot_shift_duration(longest_still)] [longest_still_note]"
	// The same tells that fail a Bot Gym run - a list var has no initial(), so ask a scenario for them
	var/static/list/forbidden_tells
	if(!forbidden_tells)
		var/datum/bot_scenario/defaults = new
		forbidden_tells = defaults.forbidden_tells
	var/list/robotic = list()
	for(var/tell in forbidden_tells)
		if(tells[tell])
			robotic += "[tell] x[tells[tell]]"
	if(length(robotic))
		. += "looked robotic: [jointext(robotic, ", ")]"

/// Things worth a look that aren't certainly wrong.
/datum/bot_shift_member/proc/warnings()
	. = list()
	if(isnull(tells))
		return
	if(longest_still >= BOT_SHIFT_IDLE_WARN && longest_still < BOT_SHIFT_STUCK)
		. += "stood still for [bot_shift_duration(longest_still)] [longest_still_note]"
	for(var/kind in goals)
		var/list/tally = goals[kind]
		if(!tally[1] && tally[2] >= BOT_SHIFT_FUTILE_GOAL)
			. += "gave up on [kind] [tally[2]] times and never managed it"
	if(longest_goal >= BOT_SHIFT_SLOW_GOAL)
		. += "spent [bot_shift_duration(longest_goal)] on one [longest_goal_kind]"
	if(down_seconds >= 60)
		. += "was knocked out or restrained for [bot_shift_duration(down_seconds * 10)]"
	if(isnull(died_at) && tiles_walked < 20)
		. += "barely moved ([tiles_walked] tiles all shift)"

/datum/bot_shift_member/proc/goal_text()
	var/list/parts = list()
	for(var/kind in goals)
		var/list/tally = goals[kind]
		parts += "[kind] [tally[1]]/[tally[1] + tally[2]]"
	return length(parts) ? jointext(parts, ", ") : "none"

/datum/bot_shift_member/proc/goal_totals()
	. = list(0, 0)
	for(var/kind in goals)
		var/list/tally = goals[kind]
		.[1] += tally[1]
		.[2] += tally[2]

// Goal bookkeeping. A goal can succeed or be given up inside assign_goal() itself, so the start is
// stamped on the way in rather than after.
/datum/bot_brain/assign_goal(datum/bot_goal/goal)
	if(shift_member && goal)
		goal.shift_started_at = world.time
	return ..()

/datum/bot_brain/goal_succeeded()
	shift_member?.goal_ended(current_goal, TRUE)
	return ..()

/datum/bot_brain/give_up_goal()
	shift_member?.goal_ended(current_goal, FALSE)
	return ..()

// ---------------------------------------------------------------------------------------------
// Department work
// ---------------------------------------------------------------------------------------------

/// A piece of work a department should have got done by some point in the shift.
/datum/bot_shift_check
	var/name
	/// The jobs that do this work. The check only runs when the crew has one of them.
	var/list/jobs
	/// How far into the shift it should be done by.
	var/deadline = 20 MINUTES
	var/datum/bot_shift/shift
	/// Shift time it was first seen done.
	var/done_at

/datum/bot_shift_check/New(datum/bot_shift/shift)
	src.shift = shift

/// The brain of a living crew member whose job this is - the finders this leans on live on the brain.
/datum/bot_shift_check/proc/worker()
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			return member.brain
	return null

/// Called once the crew has joined, to take any "before" measurements.
/datum/bot_shift_check/proc/begin()
	return

/datum/bot_shift_check/proc/done()
	return FALSE

/// Where things stand, for the report.
/datum/bot_shift_check/proc/progress()
	return ""

/datum/bot_shift_check/proc/poll()
	if(isnull(done_at) && done())
		done_at = shift.elapsed()
		shift.note("[name]: done")

/// PASS, LATE (done, but after the deadline), FAIL, or SKIP (the shift ended before the deadline).
/datum/bot_shift_check/proc/outcome()
	if(!isnull(done_at))
		return done_at <= deadline ? "PASS" : "LATE"
	return shift.length >= deadline ? "FAIL" : "SKIP"

/datum/bot_shift_check/proc/report()
	var/limit = "limit [bot_shift_clock(deadline)]"
	if(!isnull(done_at))
		return "done at [bot_shift_clock(done_at)] ([limit])"
	var/state = progress()
	if(shift.length < deadline)
		return "not done; not judged, the shift is shorter than its [bot_shift_clock(deadline)] limit[state ? " - [state]" : ""]"
	return "not done ([limit])[state ? " - [state]" : ""]"

/datum/bot_shift_check/proc/station_pa_console()
	for(var/obj/machinery/particle_accelerator/control_box/console in GLOB.machines)
		if(is_station_level(console.z))
			return console
	return null

/datum/bot_shift_check/proc/tesla_ball()
	for(var/obj/singularity/energy_ball/ball in GLOB.singularities)
		return ball
	return null

// --- Engineering ---

/datum/bot_shift_check/engineer_kit
	name = "engineering: insulated gloves on"
	jobs = list("Station Engineer", "Chief Engineer")
	deadline = 5 MINUTES

/datum/bot_shift_check/engineer_kit/proc/unkitted()
	. = list()
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(!member.brain || !(member.job in jobs))
			continue
		var/list/wanted = member.brain.engineer_gear_wanted()
		for(var/item_type in wanted)
			if(!member.brain.is_wearing(item_type, wanted[item_type]))
				var/obj/item/missing = item_type
				. += "[member.name] has no [initial(missing.name)]"

/datum/bot_shift_check/engineer_kit/done()
	return !length(unkitted())

/datum/bot_shift_check/engineer_kit/progress()
	return jointext(unkitted(), "; ")

/datum/bot_shift_check/pa_assembled
	name = "engineering: particle accelerator assembled"
	jobs = list("Station Engineer", "Chief Engineer")
	deadline = 15 MINUTES

/// list(parts assembled, parts in all), the console included.
/datum/bot_shift_check/pa_assembled/proc/tally()
	var/obj/machinery/particle_accelerator/control_box/console = station_pa_console()
	if(!console)
		return list(0, 0)
	. = list(console.construction_state >= 3, 1) //3 is PA_CONSTRUCTION_COMPLETE, #undef'd in its own file
	for(var/obj/structure/particle_accelerator/part in range(4, console))
		.[2]++
		if(part.construction_state >= 3)
			.[1]++

/datum/bot_shift_check/pa_assembled/done()
	var/list/parts = tally()
	return parts[2] && parts[1] == parts[2]

/datum/bot_shift_check/pa_assembled/progress()
	var/list/parts = tally()
	return parts[2] ? "[parts[1]] of [parts[2]] parts assembled" : "no particle accelerator on the station"

/datum/bot_shift_check/tesla_running
	name = "engineering: tesla engine running"
	jobs = list("Station Engineer", "Chief Engineer")
	deadline = 25 MINUTES

/datum/bot_shift_check/tesla_running/done()
	var/obj/machinery/particle_accelerator/control_box/console = station_pa_console()
	return console?.active && tesla_ball()

/datum/bot_shift_check/tesla_running/progress()
	var/obj/machinery/particle_accelerator/control_box/console = station_pa_console()
	if(!console)
		return "no particle accelerator on the station"
	if(console.active)
		return "particle accelerator is on, no tesla ball yet"
	var/datum/bot_brain/engineer = worker()
	if(!engineer)
		return "particle accelerator is off and no engineer is left"
	var/list/waiting = list()
	if(engineer.find_incomplete_pa_target())
		waiting += "particle accelerator assembly"
	if(engineer.find_singularity_generator_to_remove())
		waiting += "the stray singularity generator"
	if(engineer.find_incomplete_tesla_emitter())
		waiting += "emitters"
	if(engineer.find_unanchored_tesla_coil())
		waiting += "tesla coils"
	if(engineer.find_unanchored_grounding_rod())
		waiting += "grounding rods"
	if(engineer.find_incomplete_field_generator())
		waiting += "field generators"
	return "particle accelerator is off; still to do: [length(waiting) ? jointext(waiting, ", ") : "only switching it on"]"

/// Not a deadline but a state the shift must end in: whatever the engineers started is still in its cage.
/datum/bot_shift_check/tesla_contained
	name = "engineering: tesla still contained"
	jobs = list("Station Engineer", "Chief Engineer")
	deadline = 0
	/// Where the tesla generator stood, which is where the ball belongs.
	var/turf/cage_centre
	var/escaped_at
	var/next_status = 0

/datum/bot_shift_check/tesla_contained/begin()
	for(var/obj/machinery/the_singularitygen/tesla/generator in GLOB.machines)
		if(is_station_level(generator.z))
			cage_centre = get_turf(generator)
			return

/// What the containment is running on, in one line: a field generator holds only what the emitters shoot into it,
/// and the emitters fire only while there's power on their grid - which, before the engine is running, there may not be.
/datum/bot_shift_check/tesla_contained/proc/engine_status()
	var/ring = 0
	var/online = 0
	var/generators = 0
	for(var/obj/machinery/field/generator/F in GLOB.machines)
		if(!F.anchored || F.z != cage_centre.z || get_dist(F, cage_centre) > 12)
			continue
		generators++
		ring += F.power
		if(F.active == 2) //FG_ONLINE
			online++
	var/emitters = 0
	var/firing = 0
	var/datum/powernet/grid
	for(var/obj/machinery/power/emitter/E in GLOB.machines)
		if(E.z != cage_centre.z || get_dist(E, cage_centre) > 12)
			continue
		emitters++
		if(E.active && E.powered)
			firing++
		grid = grid || E.powernet
	var/obj/machinery/particle_accelerator/control_box/console = station_pa_console()
	// The SMES units feeding that grid: how full, and what they're set to let out.
	var/units = 0
	var/stored = 0
	var/room = 0
	var/letting_out = 0
	for(var/obj/machinery/power/smes/S in grid?.nodes)
		units++
		stored += S.charge
		room += S.capacity
		if(S.output_attempt)
			letting_out += S.output_level
	return "field generators [online]/[generators] online holding [round(ring)] of [generators * 250]; emitters [firing]/[emitters] firing; [grid ? "[round(grid.avail)] W on their grid against a load of [round(grid.load)] W" : "no grid under them"]; [units] SMES [room ? round(stored * 100 / room) : 0]% full set to [round(letting_out)] W out; accelerator [console?.active ? "on" : "off"], [tesla_ball() ? "ball formed" : "no ball yet"]"

/datum/bot_shift_check/tesla_contained/poll()
	if(!cage_centre)
		return
	// Every half minute for the first ten: the run-up to the ball forming is where containment is won or lost.
	if(shift.elapsed() >= next_status && shift.elapsed() <= 10 MINUTES)
		next_status = shift.elapsed() + 30 SECONDS
		shift.note("engine: [engine_status()]")
	if(escaped_at)
		return
	var/obj/singularity/energy_ball/ball = tesla_ball()
	if(ball && (ball.z != cage_centre.z || get_dist(ball, cage_centre) > 10))
		escaped_at = shift.elapsed()
		shift.note("[name]: the tesla ball is loose [get_area(ball)] ([ball.x],[ball.y],[ball.z])")
		shift.note("engine: [engine_status()]")

/datum/bot_shift_check/tesla_contained/outcome()
	if(escaped_at)
		return "FAIL"
	return tesla_ball() ? "PASS" : "SKIP"

/datum/bot_shift_check/tesla_contained/report()
	if(escaped_at)
		return "the tesla ball got loose at [bot_shift_clock(escaped_at)]"
	return tesla_ball() ? "the ball stayed in its cage" : "not judged, no tesla ball was made"

/datum/bot_shift_check/solars_tracking
	name = "engineering: solar arrays tracking the sun"
	jobs = list("Station Engineer", "Chief Engineer")
	deadline = 20 MINUTES

/// Consoles on auto, and consoles that could be: only the ones with an array on their wiring count (on Hippie
/// Station none has - see bot_solar_console_is_wired(), goals/solars.dm).
/datum/bot_shift_check/solars_tracking/proc/tally()
	. = list(0, 0)
	for(var/obj/machinery/power/solar_control/C in GLOB.machines)
		if(!is_station_level(C.z) || !bot_solar_console_is_wired(C))
			continue
		.[2]++
		if(C.track == SOLAR_TRACK_AUTO)
			.[1]++

/datum/bot_shift_check/solars_tracking/done()
	var/list/arrays = tally()
	return arrays[1] >= min(2, arrays[2]) //nothing wired to anything: nothing to do, and that's done

/datum/bot_shift_check/solars_tracking/progress()
	var/list/arrays = tally()
	return arrays[2] ? "[arrays[1]] of [arrays[2]] wired consoles on auto" : "no console on this map has an array on its wiring"

/datum/bot_shift_check/solars_tracking/report()
	. = ..()
	var/list/arrays = tally()
	. += arrays[2] ? " - [arrays[1]] of [arrays[2]] by the end" : " - no console on this map has an array on its wiring: nothing for them to set"

// --- Atmospherics ---

/datum/bot_shift_check/air_loop
	name = "atmospherics: air loop set"
	jobs = list("Atmospheric Technician")
	deadline = 10 MINUTES

/// The pumps in the Atmospherics room that aren't how setup_atmospherics.dm wants them.
/datum/bot_shift_check/air_loop/proc/wrong_pumps()
	. = list()
	var/datum/bot_brain/tech = worker()
	if(!tech)
		return
	for(var/obj/machinery/atmospherics/components/binary/pump/pump in GLOB.machines)
		if(is_station_level(pump.z) && istype(get_area(pump), /area/engine/atmos) && tech.atmos_pump_needs_action(pump))
			. += pump.name

/datum/bot_shift_check/air_loop/done()
	return worker() && !length(wrong_pumps())

/datum/bot_shift_check/air_loop/progress()
	return worker() ? "still wrong: [english_list(wrong_pumps())]" : "no atmospheric technician is left"

// --- Botany ---

/datum/bot_shift_check/bay_planted
	name = "botany: hydroponics bay planted"
	jobs = list("Botanist")
	deadline = 10 MINUTES

/// list(trays with a living plant, trays in all) for the hydroponics bay.
/datum/bot_shift_check/bay_planted/proc/tally()
	. = list(0, 0)
	var/datum/bot_brain/botanist = worker()
	if(!botanist)
		return
	for(var/obj/machinery/hydroponics/tray in GLOB.machines)
		if(!botanist.is_workplace_tray(tray))
			continue
		.[2]++
		if(tray.myseed && !tray.dead)
			.[1]++

/datum/bot_shift_check/bay_planted/done()
	var/list/trays = tally()
	return trays[2] && trays[1] >= trays[2] * 0.8

/datum/bot_shift_check/bay_planted/progress()
	var/list/trays = tally()
	return "[trays[1]] of [trays[2]] trays growing something"

/datum/bot_shift_check/produce_stocked
	name = "botany: harvest stocked in the fridge"
	jobs = list("Botanist")
	deadline = 25 MINUTES
	var/stocked_at_start = 0

/datum/bot_shift_check/produce_stocked/proc/stocked()
	. = 0
	for(var/obj/machinery/smartfridge/fridge in GLOB.machines)
		if(fridge.type != /obj/machinery/smartfridge || !is_station_level(fridge.z))
			continue
		for(var/obj/item/reagent_containers/food/snacks/grown/produce in fridge)
			.++

/datum/bot_shift_check/produce_stocked/begin()
	stocked_at_start = stocked()

/datum/bot_shift_check/produce_stocked/done()
	return stocked() > stocked_at_start

/datum/bot_shift_check/produce_stocked/progress()
	return "nothing new in the produce fridges"

// --- Medical ---

/// A drill rather than something that happens by itself: with nobody hurt, medical has nothing to
/// do all shift. One crew member picks up an injury a few minutes in and has to end up patched -
/// by a doctor coming over, or by seeing to it themselves.
/datum/bot_shift_check/casualty
	name = "medical: hurt crew member patched up (drill)"
	jobs = list("Medical Doctor", "Chief Medical Officer")
	deadline = 15 MINUTES
	var/hurt_at = 5 MINUTES
	var/datum/bot_shift_member/patient
	var/patient_lost

/datum/bot_shift_check/casualty/proc/pick_patient()
	var/list/candidates = list()
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(!member.brain || member.body.stat != CONSCIOUS || (member.job in jobs))
			continue
		if(member.job == "Assistant")
			return member
		candidates += member
	return length(candidates) ? pick(candidates) : null

/datum/bot_shift_check/casualty/poll()
	if(!patient && !patient_lost && shift.elapsed() >= hurt_at)
		patient = pick_patient()
		if(!patient)
			patient_lost = "nobody was around to be the patient"
			return
		patient.body.apply_damage(30, BRUTE, BODY_ZONE_CHEST)
		patient.body.apply_damage(20, BURN, BODY_ZONE_L_ARM)
		shift.note("[name]: [patient.label()] takes 30 brute and 20 burn [patient.where()]")
	if(patient && !patient.brain && isnull(done_at) && !patient_lost)
		patient_lost = "[patient.name] died before being treated"
	..()

/datum/bot_shift_check/casualty/done()
	var/mob/living/carbon/human/body = patient?.body
	return body && body.getBruteLoss() <= 10 && body.getFireLoss() <= 10

/datum/bot_shift_check/casualty/outcome()
	if(isnull(done_at) && patient_lost)
		return patient ? "FAIL" : "SKIP"
	return ..()

/datum/bot_shift_check/casualty/progress()
	if(patient_lost)
		return patient_lost
	var/mob/living/carbon/human/body = patient?.body
	return body ? "[patient.name] still has [round(body.getBruteLoss())] brute and [round(body.getFireLoss())] burn" : "nobody has been hurt yet"

// --- Service ---

/datum/bot_shift_check/floors_mopped
	name = "janitor: floors mopped"
	jobs = list("Janitor")
	deadline = 12 MINUTES

/datum/bot_shift_check/floors_mopped/proc/tally()
	. = list(0, 0)
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			.[1] += member.brain.tiles_mopped
			.[2] += member.brain.lights_replaced

/datum/bot_shift_check/floors_mopped/done()
	var/list/work = tally()
	return work[1] >= 15

/datum/bot_shift_check/floors_mopped/progress()
	var/list/work = tally()
	return "[work[1]] tile\s mopped, [work[2]] light\s replaced"

/datum/bot_shift_check/floors_mopped/report()
	. = ..()
	if(!isnull(done_at))
		var/list/work = tally()
		. += " - [work[1]] tile\s mopped and [work[2]] light\s replaced by the end"

/datum/bot_shift_check/kitchen_serving
	name = "kitchen: food out on the counter"
	jobs = list("Cook")
	deadline = 12 MINUTES

/datum/bot_shift_check/kitchen_serving/proc/served()
	. = 0
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			. += member.brain.dishes_served

/datum/bot_shift_check/kitchen_serving/done()
	return served() >= 3

/datum/bot_shift_check/kitchen_serving/progress()
	return "[served()] dishes put out"

/datum/bot_shift_check/kitchen_serving/report()
	. = ..()
	if(!isnull(done_at))
		var/eaten = 0
		for(var/datum/bot_shift_member/member as anything in shift.members)
			if(member.brain)
				eaten += member.brain.meals_eaten
		. += " - [served()] dishes put out by the end, and the crew ate [eaten] meal\s between them"

/datum/bot_shift_check/bar_serving
	name = "bar: drinks out on the bar"
	jobs = list("Bartender")
	deadline = 12 MINUTES

/datum/bot_shift_check/bar_serving/proc/served()
	. = 0
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			. += member.brain.drinks_served

/datum/bot_shift_check/bar_serving/done()
	return served() >= 2

/datum/bot_shift_check/bar_serving/progress()
	return "[served()] drink\s poured"

/datum/bot_shift_check/bar_serving/report()
	. = ..()
	if(!isnull(done_at))
		var/drunk = 0
		for(var/datum/bot_shift_member/member as anything in shift.members)
			if(member.brain)
				drunk += member.brain.drinks_drunk
		. += " - [served()] poured by the end, and the crew had [drunk] drink\s between them (machines included)"

/// A drill: a customer nobody is driving turns up at the bar a few minutes in and asks for a drink by name. The
/// bartender has to mix that one and say it's ready.
/datum/bot_shift_check/drink_order
	name = "bar: a customer's order mixed (drill)"
	jobs = list("Bartender")
	deadline = 12 MINUTES
	var/asks_at = 4 MINUTES
	var/mob/living/carbon/human/customer
	var/asked = FALSE

/datum/bot_shift_check/drink_order/proc/served()
	. = 0
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			. += member.brain.orders_filled

/datum/bot_shift_check/drink_order/poll()
	if(!asked && shift.elapsed() >= asks_at)
		var/datum/bot_brain/barkeep = worker()
		var/obj/structure/table/counter = barkeep?.find_bar_counter()
		// Once the bartender is at the bar to hear it: nobody orders from an empty bar.
		if(counter && get_dist(barkeep.owner, counter) <= 5)
			asked = TRUE
			// Stood on the customers' side of the bar, facing it.
			var/turf/spot
			for(var/turf/open/T in orange(2, counter))
				if(!T.density && !is_blocked_turf(T, TRUE) && (barkeep.owner in view(6, T)))
					spot = T
					break
			spot = spot || get_step(counter, SOUTH)
			customer = new(spot)
			customer.real_name = "Dana Customer"
			customer.name = customer.real_name
			customer.equipOutfit(/datum/outfit/job/assistant)
			customer.face_atom(counter)
			customer.say("Bartender, can I get a martini please?")
			shift.note("[name]: Dana Customer asks for a martini at [get_area_name(spot, TRUE)]")
	..()

/datum/bot_shift_check/drink_order/done()
	return served() >= 1

/datum/bot_shift_check/drink_order/progress()
	return asked ? "asked for a martini; [served()] order\s filled" : "nobody has asked yet"

// --- Supply ---

/// A drill: somebody asks cargo over the radio for a crate of glass. It has to get ordered.
/datum/bot_shift_check/supply_request
	name = "cargo: a crate somebody asked for ordered (drill)"
	jobs = list("Cargo Technician", "Quartermaster")
	deadline = 14 MINUTES
	var/asks_at = 5 MINUTES
	var/mob/living/carbon/human/asker
	var/asked = FALSE

/datum/bot_shift_check/supply_request/proc/ordered()
	. = 0
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			. += member.brain.requests_ordered

/datum/bot_shift_check/supply_request/poll()
	if(!asked && shift.elapsed() >= asks_at)
		var/datum/bot_brain/clerk = worker()
		if(clerk && !QDELETED(clerk.owner))
			asked = TRUE
			// Somebody out in the hallway with a headset on.
			var/turf/spot = get_turf(clerk.owner)
			for(var/turf/open/T in orange(3, clerk.owner))
				if(!T.density && !is_blocked_turf(T, TRUE))
					spot = T
					break
			asker = new(spot)
			asker.real_name = "Glenn Asker"
			asker.name = asker.real_name
			asker.equipOutfit(/datum/outfit/job/assistant)
			asker.say(";Cargo, can we get some glass please?")
			shift.note("[name]: Glenn Asker asks cargo for glass over the radio")
	..()

/datum/bot_shift_check/supply_request/done()
	return ordered() >= 1

/datum/bot_shift_check/supply_request/progress()
	return asked ? "asked for glass; [ordered()] request\s ordered" : "nobody has asked yet"


/datum/bot_shift_check/cargo_delivery
	name = "cargo: an order brought in and unloaded"
	jobs = list("Cargo Technician", "Quartermaster")
	deadline = 12 MINUTES

/datum/bot_shift_check/cargo_delivery/proc/tally()
	. = list(0, 0)
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			.[1] += member.brain.orders_placed
			.[2] += member.brain.crates_unloaded

/datum/bot_shift_check/cargo_delivery/done()
	var/list/work = tally()
	return work[2] >= 1

/datum/bot_shift_check/cargo_delivery/progress()
	var/list/work = tally()
	return "[work[1]] order\s placed, [work[2]] crate\s unloaded; the shuttle is [SSshuttle.supply?.getDockedId() || "in transit"]"

/datum/bot_shift_check/cargo_delivery/report()
	. = ..()
	if(!isnull(done_at))
		var/list/work = tally()
		. += " - [work[1]] order\s and [work[2]] crate\s by the end"

// --- Science ---

/datum/bot_shift_check/research_done
	name = "science: research unlocked"
	jobs = list("Scientist", "Research Director")
	deadline = 10 MINUTES

/datum/bot_shift_check/research_done/proc/unlocked()
	. = 0
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			. += member.brain.nodes_researched

/datum/bot_shift_check/research_done/done()
	return unlocked() >= 3

/datum/bot_shift_check/research_done/progress()
	return "[unlocked()] node\s researched"

/datum/bot_shift_check/research_done/report()
	. = ..()
	if(!isnull(done_at))
		. += " - [unlocked()] node\s by the end"

/datum/bot_shift_check/medibot_built
	name = "robotics: a medibot built"
	jobs = list("Roboticist")
	deadline = 14 MINUTES

/datum/bot_shift_check/medibot_built/proc/built()
	. = 0
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			. += member.brain.bots_built

/datum/bot_shift_check/medibot_built/done()
	return built() >= 1

/datum/bot_shift_check/medibot_built/progress()
	return "[built()] built"

/datum/bot_shift_check/medibot_built/report()
	. = ..()
	if(!isnull(done_at))
		. += " - [built()] by the end"

// --- Command and civilians ---

/datum/bot_shift_check/captain_duties
	name = "captain: disk secured, crew addressed"
	jobs = list("Captain")
	deadline = 10 MINUTES

/datum/bot_shift_check/captain_duties/proc/has_disk()
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs) && !QDELETED(member.brain.owner) && member.brain.find_carried_tool(/obj/item/disk/nuclear))
			return TRUE
	return FALSE

/datum/bot_shift_check/captain_duties/done()
	return GLOB.bot_captain_greeted && has_disk()

/datum/bot_shift_check/captain_duties/progress()
	return "the disk is [has_disk() ? "on the captain" : "not on the captain"]; [GLOB.bot_captain_greeted ? "the crew has been addressed" : "no announcement yet"]"

// Not the Quartermaster, whose shift is the cargo round: the desk comes last, and often not at all.
/datum/bot_shift_check/desks_manned
	name = "offices: somebody at their desk"
	jobs = list("Head of Personnel", "Captain", "Warden", "Detective", "Lawyer", "Curator", "Chaplain", "Research Director", "Chief Medical Officer", "Head of Security")
	deadline = 10 MINUTES

/datum/bot_shift_check/desks_manned/proc/tally()
	. = list(0, 0)
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			.[2]++
			if(member.brain.desk_sittings)
				.[1]++

/datum/bot_shift_check/desks_manned/done()
	var/list/sat = tally()
	return sat[1] >= max(1, round(sat[2] / 2))

/datum/bot_shift_check/desks_manned/progress()
	var/list/sat = tally()
	return "[sat[1]] of [sat[2]] have sat down at theirs"

/datum/bot_shift_check/desks_manned/report()
	. = ..()
	if(!isnull(done_at))
		var/list/sat = tally()
		. += " - [sat[1]] of [sat[2]] by the end"

/datum/bot_shift_check/a_show
	name = "clown and mime: a show put on"
	jobs = list("Clown", "Mime")
	deadline = 14 MINUTES

/datum/bot_shift_check/a_show/proc/shows()
	. = 0
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain && (member.job in jobs))
			. += member.brain.shows_put_on

/datum/bot_shift_check/a_show/done()
	return shows() >= 1

/datum/bot_shift_check/a_show/progress()
	return "[shows()] so far"

/datum/bot_shift_check/a_show/report()
	. = ..()
	if(!isnull(done_at))
		. += " - [shows()] by the end"

// --- Everyone ---

/// A drill, on request (bot-evac=1): the emergency shuttle is called eight minutes before the end of the shift, three
/// minutes out, and everyone still alive should be on it when it leaves (goals/evacuate.dm).
/datum/bot_shift_check/evacuation
	name = "everyone: aboard the shuttle when it leaves (drill)"
	deadline = 0
	var/called_at
	var/launched_at
	var/list/left_behind = list()
	var/aboard = 0
	var/seated = 0

/datum/bot_shift_check/evacuation/worker()
	if(!(BOT_SHIFT_EVAC_PARAMETER in world.params) || shift.length < 10 MINUTES)
		return null
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(member.brain)
			return member.brain
	return null

/datum/bot_shift_check/evacuation/poll()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E || launched_at)
		return
	if(!called_at)
		if(shift.elapsed() < shift.length - 8 MINUTES)
			return
		called_at = shift.elapsed()
		E.request(null, set_coefficient = 1)
		E.setTimer(3 MINUTES)
		shift.note("[name]: the shuttle is called, three minutes out")
		return
	// Counted in the last seconds before it goes, while everyone aboard is still on the station's z-level to be found.
	if(E.mode != SHUTTLE_IGNITING && E.mode != SHUTTLE_ESCAPE)
		return
	launched_at = shift.elapsed()
	for(var/datum/bot_shift_member/member as anything in shift.members)
		if(!member.brain || member.body.stat == DEAD)
			continue
		if(bot_aboard_shuttle(member.body))
			aboard++
			if(member.body.buckled)
				seated++
		else
			left_behind += "[member.label()] [member.where()], [member.doing()]"
	shift.note("[name]: [aboard] aboard ([seated] sitting down), [length(left_behind)] left behind")
	for(var/who in left_behind)
		shift.note("  left behind: [who]")

/datum/bot_shift_check/evacuation/outcome()
	if(!launched_at)
		return called_at ? "FAIL" : "SKIP"
	return length(left_behind) ? "FAIL" : "PASS"

/datum/bot_shift_check/evacuation/report()
	if(!called_at)
		return "not judged, the shuttle was never called"
	if(!launched_at)
		return "called at [bot_shift_clock(called_at)] but it hadn't left by the end of the shift"
	if(length(left_behind))
		return "[aboard] aboard, [length(left_behind)] left behind: [jointext(left_behind, "; ")]"
	return "all [aboard] aboard at [bot_shift_clock(launched_at)], [seated] of them sitting down"

// ---------------------------------------------------------------------------------------------
// The report
// ---------------------------------------------------------------------------------------------

/datum/bot_shift/proc/write_results()
	var/dir = "data/bot_shift/"
	fdel(dir)
	var/failures = 0
	var/warnings = 0
	var/list/lines = list()
	var/list/json_checks = list()
	var/list/json_crew = list()

	lines += "DEPARTMENT WORK"
	for(var/datum/bot_shift_check/check as anything in checks)
		var/outcome = check.outcome()
		if(outcome == "FAIL")
			failures++
		else if(outcome == "LATE")
			warnings++
		lines += "[pad_bot_gym(outcome, 7)][pad_bot_gym(check.name, 50)][check.report()]"
		json_checks += list(list("name" = check.name, "outcome" = outcome, "done_at" = isnull(check.done_at) ? null : check.done_at / 10, "deadline" = check.deadline / 10, "detail" = check.report()))
	if(!length(checks))
		lines += "       (nothing to judge for this crew)"

	lines += ""
	lines += "CREW"
	for(var/datum/bot_shift_member/member as anything in members)
		member.wrap_up()
		var/list/problems = member.problems()
		var/list/worries = member.warnings()
		var/outcome = length(problems) ? "FAIL" : (length(worries) ? "WARN" : "PASS")
		if(length(problems))
			failures++
		else if(length(worries))
			warnings++
		var/list/totals = member.goal_totals()
		var/stats = isnull(member.tells) ? "" : "walked [member.tiles_walked] tiles through [length(member.areas_seen)] areas; goals [totals[1]] done, [totals[2]] given up; longest pause [bot_shift_duration(member.longest_still)][member.space_seconds ? "; [bot_shift_duration(member.space_seconds * 10)] out in space" : ""]"
		lines += "[pad_bot_gym(outcome, 7)][pad_bot_gym(member.label(), 50)][stats]"
		for(var/problem in problems)
			lines += "         ! [problem]"
		for(var/worry in worries)
			lines += "         ? [worry]"
		if(!isnull(member.tells))
			lines += "         goals (done/tried): [member.goal_text()]"
		json_crew += list(list("name" = member.name, "job" = member.job, "outcome" = outcome, "problems" = problems, "warnings" = worries,
			"died_at" = isnull(member.died_at) ? null : member.died_at / 10, "health" = member.final_health, "tiles_walked" = member.tiles_walked,
			"areas" = length(member.areas_seen), "longest_still" = member.longest_still / 10, "longest_still_note" = member.longest_still_note,
			"down_seconds" = member.down_seconds, "space_seconds" = member.space_seconds, "goals" = member.goals, "tells" = member.tells))

	lines += ""
	lines += "ERRORS"
	var/bot_runtimes = 0
	var/other_runtimes = 0
	var/list/other_sites = list()
	var/list/json_runtimes = list()
	for(var/site in runtime_sites)
		var/list/entry = runtime_sites[site]
		json_runtimes += list(list("site" = site, "error" = entry["error"], "count" = entry["count"], "bot_code" = entry["bot_code"]))
		if(entry["bot_code"])
			bot_runtimes += entry["count"]
			failures++
			lines += "[pad_bot_gym("FAIL", 7)]runtime in bot code x[entry["count"]]: [entry["error"]] at [site]"
		else
			other_runtimes += entry["count"]
			other_sites += "[site] x[entry["count"]]"
	if(bot_exception_count)
		failures++
		lines += "[pad_bot_gym("FAIL", 7)][bot_exception_count] bot AI exception\s caught:"
		for(var/text in bot_exceptions)
			lines += "         ! [text]"
	if(!bot_runtimes && !bot_exception_count)
		lines += "[pad_bot_gym("PASS", 7)]no runtimes in bot code, no bot AI exceptions"
	if(other_runtimes)
		lines += "[pad_bot_gym("INFO", 7)][other_runtimes] runtime\s elsewhere in the game: [jointext(other_sites, ", ")]"

	var/real_seconds = (real_end_ms - real_start_ms) / 1000
	var/header = "BOT SHIFT  [bot_shift_clock(length)] shift, [length(members)] bots - [failures] failure\s, [warnings] warning\s\n"
	header += "Took [bot_shift_duration(real_seconds * 10)] of real time ([speed()]x). [bot_gym_load_text(load)]\n"
	// What sets the server load, and so how fast a shift can run: a search that finds nothing opens every turf it can reach.
	header += "Pathfinding: [pathfinding["searches"]] searches opened [pathfinding["turfs"]] turfs; [pathfinding["failed"]] found no route and opened [pathfinding["failed_turfs"]] of them.\n"
	header += "Round logs: [GLOB.log_directory]\n"
	var/summary = "[header]\n[jointext(lines, "\n")]\nFAILED: [failures]\n"
	text2file(summary, "[dir]summary.txt")
	text2file(jointext(timeline, "\n"), "[dir]timeline.txt")
	if(profile)
		text2file(profile, "[dir]profile.json")
	text2file(json_encode(list("minutes" = length / 600, "crew" = crew_text, "failures" = failures, "warnings" = warnings,
		"real_seconds" = real_seconds, "speed" = speed(), "load_avg" = round(load["sum"] / max(load["seconds"], 1)), "load_max" = round(load["peak"]), "overloaded_seconds" = load["over"],
		"pathfinding" = pathfinding, "log_directory" = GLOB.log_directory, "checks" = json_checks, "members" = json_crew, "runtimes" = json_runtimes,
		"bot_exceptions" = bot_exceptions)), "[dir]results.json")
	log_world(summary)

#undef BOT_SHIFT_DEFAULT_MINUTES
#undef BOT_SHIFT_DEFAULT_CREW
#undef BOT_SHIFT_ARRIVAL_GAP
#undef BOT_SHIFT_IDLE_WARN
#undef BOT_SHIFT_STUCK
#undef BOT_SHIFT_SLOW_GOAL
#undef BOT_SHIFT_FUTILE_GOAL
