// What the Who list says with a bot crew aboard, as a real player and as an admin sees it. Not part of the game:
// HARNESS=who_check.dm tools/keybind_check/run.sh <label>

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
			who_check_run(src)

/proc/who_check_run(client/C)
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	CONFIG_SET(number/bot_crew_target, 20)
	CONFIG_SET(number/bot_crew_traitors, 0)
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 2 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(5)
	sleep(5 SECONDS)
	kc_log("round state [SSticker.current_state], [length(GLOB.bot_crew_members)] bots, [length(GLOB.clients)] real client(s), admin [check_rights_for(C, R_ADMIN) ? "yes" : "no"]")
	kc_log(replacetext(C.who_list(), "\t", "  "))
	var/datum/admins/holder = C.holder
	if(holder)
		C.holder = null
		kc_log("--- the same list with no admin rights")
		kc_log(replacetext(C.who_list(), "\t", "  "))
		C.holder = holder
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
