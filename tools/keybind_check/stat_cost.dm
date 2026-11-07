// What the stat panel costs the server for one real client: the profiler over 20 s in the lobby and 20 s as a crewmember in a
// round, every proc with "stat" in its name (the old Stat() procs, or the stat panel subsystem and its helpers). Not part of the game:
//   HARNESS=stat_cost.dm tools/keybind_check/run.sh statcost
// Results in data/keycheck_statcost.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			stat_cost_run(src)

/proc/sc_profile(label, seconds)
	world.Profile(PROFILE_CLEAR)
	world.Profile(PROFILE_START)
	var/started = REALTIMEOFDAY
	sleep(seconds SECONDS)
	world.Profile(PROFILE_STOP)
	var/real = (REALTIMEOFDAY - started) / 10
	var/list/rows = json_decode(world.Profile(PROFILE_REFRESH, null, "json"))
	var/total_self = 0
	var/total_calls = 0
	var/list/lines = list()
	for(var/list/row in rows)
		var/name = row["name"]
		if(!findtext(name, "stat") && !findtext(name, "Stat"))
			continue
		if(findtext(name, "/proc/stat_entry") || findtext(name, "status_") || findtext(name, "statue") || findtext(name, "station") || findtext(name, "static"))
			continue
		var/self = row["self"]
		var/calls = row["calls"]
		if(!self && !calls)
			continue
		lines += "  [name]: self [round(self * 1000, 0.01)] ms, total [round(row["total"] * 1000, 0.01)] ms, [calls] calls"
		if(findtext(name, "/Stat") || findtext(name, "statpanel") || findtext(name, "stat_panel"))
			total_self += self
			total_calls += calls
	kc_log("[label]: [round(real, 0.1)] s real; stat panel procs self [round(total_self * 1000, 0.01)] ms in [total_calls] calls = [round(total_self * 1000 / real, 0.001)] ms a second for this client")
	for(var/line in lines)
		kc_log(line)

/proc/stat_cost_run(client/C)
	sleep(50)
	sc_profile("lobby", 20)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/mob/living/carbon/human/H = new(get_turf(pick(SSjob.latejoin_trackers)))
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(5 SECONDS)
	sc_profile("crewmember", 20)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
