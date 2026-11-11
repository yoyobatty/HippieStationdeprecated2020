// Verbs typed by a real client reach hippie's redefinitions. A verb is added to a client's verbs by its path
// (/datum/admins/proc/access_news_network), and a path names the FIRST definition: a later file's redefinition at the same type
// (hippie's tgui windows) is skipped unless the tg proc hands over by name. This runs each verb the way an admin does, by
// command, and checks the tgui window opened. Not part of the game:
// HARNESS=verb_check.dm MAP=testbench tools/keybind_check/run.sh <label>      verdicts in data/keycheck_<label>.txt

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
			verb_check_run(src)

/// The interfaces of the tgui windows open for this client's mob
/proc/vc_open(client/C)
	. = list()
	for(var/datum/tgui/ui in C?.mob?.open_uis)
		. += ui.interface

/proc/vc_close(client/C)
	for(var/datum/tgui/ui in C?.mob?.open_uis.Copy())
		ui.close()

/// Types `command` into the client as the admin would and checks a tgui `interface` window came up
/proc/vc_try(client/C, label, command, interface)
	vc_close(C)
	sleep(5)
	winset(C, null, "command=[command]")
	for(var/i in 1 to 30)
		sleep(2)
		if(interface in vc_open(C))
			break
	var/list/open = vc_open(C)
	kc_log("[(interface in open) ? "PASS" : "FAIL"] [label]: typed \"[command]\", tgui windows open: [open.len ? jointext(open, ", ") : "none"]")

/proc/verb_check_run(client/C)
	if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	CONFIG_SET(flag/use_exp_tracking, TRUE) //off in config.txt: Player Playtime would only say so
	C.verbs.Add(GLOB.admin_verbs_debug_mapping) //"Debug verbs - Enable": Camera Report is one of them
	sleep(20)
	vc_try(C, "/datum/admins verb, admin newscaster", "Access-Newscaster-Network", "newscaster")
	vc_try(C, "/datum/admins verb, reagent spawner", "Spawn-reagent-container", "admin_beakers")
	vc_try(C, "/client verb, Investigate", "Investigate", "admin_investigate")
	vc_try(C, "/client verb, del() log", "Display-del()-Log", "admin_del_log")
	vc_try(C, "/client verb, Initialize() log", "Display-Initialize()-Log", "admin_report")
	vc_try(C, "/client verb, player playtime", "Player-Playtime", "admin_playtime")
	vc_try(C, "/client verb, Camera Report", "Camera-Report", "admin_report")
	vc_close(C)
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
