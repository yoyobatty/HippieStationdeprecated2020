// Whether the bot crew starts at its posts, who comes in late and when, and whether a bot still reads as absent. Not part of the game:
// HARNESS=crew_check.dm EXTRA_PARAMS="timewarp=0" tools/power_check/run.sh <label>
// A live round the way a real server runs one, with no gym or shift harness in the way, and nobody connected.

#define CC_MINUTES 45

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_VAR_INIT(cc_posted, 0)
GLOBAL_VAR_INIT(cc_on_landmark, 0)
GLOBAL_VAR_INIT(cc_not_on_landmark, 0)

/proc/uc_log(text)
	text2file(text, "data/update_check.txt")

/world/New()
	. = ..()
	spawn(0)
		crew_check_run()

/proc/cc_on_own_landmark(mob/living/carbon/human/H)
	for(var/obj/effect/landmark/start/post in GLOB.start_landmarks_list)
		if(post.name == H.job && post.loc == get_turf(H))
			return TRUE
	return FALSE

/mob/dead/new_player/join_at_post(rank)
	var/datum/bot_identity/identity = bot_identity
	. = ..()
	var/mob/living/carbon/human/H = identity?.spawned_human
	if(!H)
		uc_log("post: [rank] FAILED")
		return
	GLOB.cc_posted++
	var/on_post = cc_on_own_landmark(H)
	if(on_post)
		GLOB.cc_on_landmark++
	else
		GLOB.cc_not_on_landmark++
	var/area/where = get_area(H)
	uc_log("post +[(world.time - SSticker.round_start_time) / 10]s: [H.real_name] as [H.job] in [where.name] [on_post ? "on their own start point" : "NOT ON THEIR START POINT"], late_joiner [H.mind?.late_joiner ? "YES" : "no"], handle [H.mind?.bot_handle]")

/proc/crew_check_run()
	UNTIL(SSticker.initialized) // it reads data/mode.txt when it starts up
	GLOB.master_mode = "extended" // data/mode.txt is whatever the last real round left there, and most modes won't start with nobody playing
	CONFIG_SET(number/bot_crew_target, 20)
	CONFIG_SET(number/bot_crew_traitors, 2)
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1)
	sleep(5 SECONDS)
	uc_log("round state [SSticker.current_state], 5 seconds in: [length(GLOB.bot_crew_members)] bots, [GLOB.cc_posted] started at a post ([GLOB.cc_on_landmark] on their own start point, [GLOB.cc_not_on_landmark] not), [GLOB.bot_population.latecomers] latecomers due")
	var/list/jobs = list()
	for(var/mob/living/carbon/human/H as anything in GLOB.bot_crew_members)
		jobs[H.job] += 1
	var/list/job_text = list()
	for(var/title in jobs)
		job_text += "[title] [jobs[title]]"
	uc_log("jobs: [jointext(job_text, ", ")]")

	// What gives a bot away
	var/mob/living/carbon/human/seen = GLOB.bot_crew_members[1]
	var/mob/living/carbon/human/looker = new(get_turf(seen))
	var/said = jointext(seen.examine(looker), " ")
	uc_log("examine: catatonic [findtext(said, "catatonic") ? "SHOWN" : "no"], absent-minded [findtext(said, "absent-minded") ? "SHOWN" : "no"]")
	uc_log("considered_afk: [considered_afk(seen.mind) ? "YES" : "no"]")
	uc_log("key_name: [key_name(seen)]")
	uc_log("round-end line: [printplayer(seen.mind)]")
	qdel(looker)

	var/seen_count = length(GLOB.bot_crew_members)
	var/stop_at = SSticker.round_start_time + CC_MINUTES MINUTES
	while(world.time < stop_at && SSticker.IsRoundInProgress())
		sleep(5 SECONDS)
		if(length(GLOB.bot_crew_members) > seen_count)
			for(var/i in seen_count + 1 to length(GLOB.bot_crew_members))
				var/mob/living/carbon/human/H = GLOB.bot_crew_members[i]
				var/area/where = get_area(H)
				uc_log("late [round((world.time - SSticker.round_start_time) / 600, 0.1)] min: [H.real_name] as [H.job], in [where.name], late_joiner [H.mind?.late_joiner ? "yes" : "NO"]")
			seen_count = length(GLOB.bot_crew_members)
	uc_log("at [CC_MINUTES] minutes: [length(GLOB.bot_crew_members)] bots, [GLOB.bot_population.latecomers] latecomers still due, [GLOB.bot_population.joined] joined")
	uc_log("done")
	sleep(5)
	del(world)

#undef CC_MINUTES
