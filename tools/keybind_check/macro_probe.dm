// Probe: when a key has a macro of its own (as T has "say"), does the "Any" macro still fire keyDown() for it? Decides whether a talk
// key can share its key with another action. Not part of the game:
// HARNESS=macro_probe.dm SENDER=macro_probe.ps1 tools/keybind_check/run.sh <label>
// Adds macros K -> "kc-probe" and Ctrl+K -> "kc-probe ctrl", then macro_probe.ps1 posts real K, Ctrl+K and J (no macro, the control).

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(keycheck_real_keys)
GLOBAL_LIST_EMPTY(keycheck_probe_calls)

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			mp_run(src)

/client/keyDown(_key as text)
	set instant = TRUE
	set hidden = TRUE
	GLOB.keycheck_real_keys += _key
	return ..()

/client/verb/kc_probe(which as text|null)
	set name = "kc-probe"
	set hidden = TRUE
	set instant = TRUE
	GLOB.keycheck_probe_calls += (which || "plain")

/proc/mp_run(client/C)
	for(var/i in 1 to 300)
		if(!C)
			return
		if(SSticker.current_state >= GAME_STATE_PREGAME && C.mob)
			break
		sleep(1)
	sleep(20)
	winset(C, "default-probe-k", "parent=default;name=K;command=kc-probe")
	winset(C, "default-probe-ck", "parent=default;name=Ctrl+K;command=\"kc-probe ctrl\"")
	winset(C, "mapwindow.map", "focus=true")
	sleep(10)
	kc_log("info macros: [winget(C, "default-probe-k", "name")] / [winget(C, "default-probe-ck", "name")], focus \"[winget(C, null, "focus")]\"")
	GLOB.keycheck_real_keys.Cut()
	text2file("go", "data/keycheck_sendkeys")
	for(var/i in 1 to 150)
		sleep(1)
		if(fexists("data/keycheck_keys_sent"))
			break
	sleep(20)
	kc_log("info keyDown() got: [GLOB.keycheck_real_keys.Join(" ")]")
	kc_log("info macro commands ran: [GLOB.keycheck_probe_calls.Join(" ")]")
	kc_log("[("K" in GLOB.keycheck_real_keys) ? "yes  " : "no   "] Any still fires keyDown(K) when K has a macro of its own")
	kc_log("[(GLOB.keycheck_probe_calls.Find("plain")) ? "yes  " : "no   "] the K macro ran")
	kc_log("[(GLOB.keycheck_probe_calls.Find("ctrl")) ? "yes  " : "no   "] the Ctrl+K macro ran")
	kc_log("[("J" in GLOB.keycheck_real_keys) ? "ok   " : "WRONG"] control: J (no macro) reached keyDown()")
	kc_log("done")
