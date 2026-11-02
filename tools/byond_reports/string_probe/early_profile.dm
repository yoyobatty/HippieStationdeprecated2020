// BYOND's profiler over the first three minutes of a shift, where the bot brain spikes are. Not part of the game:
// AT_END=1 HARNESS=../string_probe/early_profile.dm PARAMS="bot-shift=4&bot-crew=fill:20&bot-quiet=1&timewarp=0" bash tools/byond_reports/ref_stall/hippie_check.sh
// Writes data/early_profile.json. Heavy single calls show as a high total time for few calls.

/proc/ep_run()
	UNTIL(SSticker.initialized)
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	sleep(300)
	world.Profile(PROFILE_START)
	sleep(1800)
	var/data = world.Profile(PROFILE_REFRESH, format = "json")
	world.Profile(PROFILE_STOP)
	fdel("data/early_profile.json")
	text2file(data, "data/early_profile.json")
	text2file("done", "data/ref_stall.txt")
	del(world)

/world/New()
	. = ..()
	spawn(0)
		ep_run()
