// Whether watch_held_keys() lets go of a key that's still down, with the keyboard's focus in each place it goes in play: the map,
// the chat bar, the say prompt (T) open and closed, the window minimised, the chat pane and a browse() popup. Not part of the game:
// HARNESS=say_focus_check.dm SENDER=say_focus.ps1 tools/keybind_check/run.sh <label>
// S is held through keyDown() for 2.5 seconds each time: 25 tiles running if it was kept, about 10 if the watcher let go.
// Only the chat pane and the popup should let go (2026-11-07: the user stopped dead mid-walk, 43 times in 7 rounds, before).
// The say prompt opens the way the T macro opens it and say_focus.ps1 types "hi" + Enter into it.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file("[time2text(world.timeofday, "hh:mm:ss")].[world.timeofday % 10] [text]", "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			sf_run(src)

/client/reset_held_keys()
	kc_log("RESET: the watcher let go of every held key")
	return ..()

/client/focus_hears_keys(focused)
	. = ..()
	kc_log("watcher: focus \"[focused]\" hears keys: [. ? "yes" : "NO"]")

/mob/say_verb(message as text)
	kc_log("say ran: \"[message]\"")
	return ..()

/proc/sf_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(60, 60)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 59, y0 + 59, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0 + 30, y0 + 30, z)

/// Hold S for 2.5 seconds through keyDown() and say how far it got: 25 tiles running if nothing let go of it, about 10 if the
/// watcher did at its first look.
/proc/sf_hold(client/C, mob/living/H, turf/home, label)
	H.forceMove(home)
	sleep(2)
	var/start_y = H.y
	C.keyDown("S")
	sleep(25)
	var/moved = start_y - H.y
	C.keyUp("S")
	kc_log("[label]: S held 2.5 s, [moved] tiles[moved < 20 ? " -- LET GO EARLY" : ""]; focus \"[winget(C, null, "focus")]\"")
	sleep(5)

/proc/sf_trial(client/C, mob/living/H, turf/home, start)
	winset(C, start, "focus=true")
	sleep(5)
	sf_hold(C, H, home, "focus put on [start], it says \"[winget(C, null, "focus")]\"")

/// The say prompt opens the way the T macro opens it; say_focus.ps1 answers prompt n after wait_ms.
/proc/sf_prompt(client/C, n, wait_ms)
	text2file("[wait_ms]", "data/sf_prompt_[n]")
	winset(C, null, "command=say")

/proc/sf_prompt_answered(n)
	for(var/i in 1 to 100)
		if(fexists("data/sf_answered_[n]"))
			return
		sleep(1)

/proc/sf_run(client/C)
	var/turf/home = sf_floor()
	var/mob/living/carbon/human/H = new(home)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	C.mob = H
	sleep(20)
	kc_log("hotkeys mode: [C.prefs.hotkeys ? "on" : "off"], focus at login \"[winget(C, null, "focus")]\"")
	for(var/i in 1 to 2)
		fdel("data/sf_prompt_[i]")
		fdel("data/sf_answered_[i]")
	text2file("go", "data/keycheck_sendkeys")
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	winset(C, "mainwindow", "is-minimized=true")
	for(var/i in 1 to 4)
		sleep(5)
		kc_log("minimised: focus \"[winget(C, null, "focus")]\", [winget(C, "mainwindow", "is-minimized;is-maximized;pos;size;outer-size;inner-size")]")
	sf_hold(C, H, home, "minimised")
	winset(C, "mainwindow", "is-minimized=false")
	sleep(10)
	kc_log("restored: [winget(C, "mainwindow", "is-minimized;is-maximized;pos;size;outer-size;inner-size")]")
	sf_trial(C, H, home, "mapwindow.map")
	sf_trial(C, H, home, "infowindow.input")
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	sf_prompt(C, 1, 3500)
	sleep(5)
	sf_hold(C, H, home, "say prompt open, focus \"[winget(C, null, "focus")]\"")
	sf_prompt_answered(1)
	sleep(10)
	sf_hold(C, H, home, "say prompt closed, focus \"[winget(C, null, "focus")]\"")
	sf_trial(C, H, home, "outputwindow.browseroutput")
	C << browse("<html><body>popup</body></html>", "window=sf_popup;size=300x200")
	sleep(10)
	sf_trial(C, H, home, "sf_popup.browser")
	C << browse(null, "window=sf_popup")
	for(var/i in 1 to 300)
		if(fexists("data/keycheck_keys_sent"))
			break
		sleep(1)
	text2file("done", "data/keycheck.txt")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
