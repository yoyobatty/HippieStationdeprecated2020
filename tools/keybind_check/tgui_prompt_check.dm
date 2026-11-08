// Real-client check of the tgui prompts (hippiestation/code/modules/tgui/tgui_prompt.dm, TguiPrompt.js), the input()/alert()
// stand-ins. Not part of the game: HARNESS=tgui_prompt_check.dm SENDER=kb_panel.ps1 tools/keybind_check/run.sh <label>
// Keys are posted to whatever has DreamSeeker's keyboard, so every answer typed here also proves the prompt took the focus.
// Pictures in data/previews/prompt_*.png.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(tp_pass, 0)
GLOBAL_VAR_INIT(tp_fail, 0)
GLOBAL_VAR(tp_result)
GLOBAL_VAR_INIT(tp_done, FALSE)

/proc/kc_log(text)
	text2file("[time2text(world.timeofday, "hh:mm:ss")] [text]", "data/keycheck.txt")

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			tp_run(src)

/proc/tp_check(name, ok, detail = "")
	if(ok)
		GLOB.tp_pass++
	else
		GLOB.tp_fail++
	kc_log("[ok ? "ok   " : "WRONG"] [name][detail ? " ([detail])" : ""]")

/proc/tp_cmd(text, timeout = 20 SECONDS)
	fdel("data/kp_ack")
	fdel("data/kp_cmd")
	text2file(text, "data/kp_cmd")
	var/deadline = world.time + timeout
	while(!fexists("data/kp_ack") && world.time < deadline)
		sleep(1)
	. = fexists("data/kp_ack") ? trim(file2text("data/kp_ack")) : "no answer"
	fdel("data/kp_ack")

/proc/tp_shot(name, title)
	fdel("data/keycheck_shot_title")
	if(title)
		text2file(title, "data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

GLOBAL_LIST_EMPTY(tp_prompts)

/datum/tgui_prompt/New()
	. = ..()
	GLOB.tp_prompts += src

/datum/tgui_prompt/Destroy(force, ...)
	GLOB.tp_prompts -= src
	GLOB.tp_last_title = title
	GLOB.tp_last_result = result
	return ..()

GLOBAL_VAR(tp_last_title)
GLOBAL_VAR(tp_last_result)
GLOBAL_VAR_INIT(tp_ignore_ran, FALSE)

/// `in world` only walks atoms, so prompts are kept track of here
/proc/tp_open_prompt()
	for(var/datum/tgui_prompt/P in GLOB.tp_prompts)
		if(!P.done)
			return P

/// Starts a prompt in the background (it sleeps), waits for its window
/proc/tp_start(datum/callback/CB)
	// one stuck prompt mustn't be driven by the steps after it
	for(var/datum/tgui_prompt/old in GLOB.tp_prompts)
		if(!old.done)
			kc_log("info closing a prompt left open: \"[old.title]\"")
			old.finish(null)
	sleep(2)
	GLOB.tp_result = "UNSET"
	GLOB.tp_done = FALSE
	spawn(0)
		GLOB.tp_result = CB.Invoke()
		GLOB.tp_done = TRUE
	sleep(12)

/proc/tp_wait(limit = 10 SECONDS)
	var/deadline = world.time + limit
	while(!GLOB.tp_done && world.time < deadline)
		sleep(1)
	return GLOB.tp_done

/proc/tp_desc(x)
	if(isnull(x))
		return "null"
	if(isatom(x))
		var/atom/A = x
		return "[A.type] \"[A.name]\""
	return "\"[x]\""

/obj/item/tp_probe
	var/usable = TRUE

/obj/item/tp_probe/ui_status(mob/user, datum/ui_state/state)
	return usable ? UI_INTERACTIVE : UI_CLOSE

/proc/tp_run(client/C)
	for(var/i in 1 to 300)
		if(!C)
			return
		if(SSticker.current_state >= GAME_STATE_PREGAME && C.mob)
			break
		sleep(1)
	sleep(30)
	var/mob/M = C.mob
	var/start_ms = world.timeofday
	text2file("go", "data/keycheck_sendkeys") // starts kb_panel.ps1 (keys) and shot.ps1 (pictures)
	for(var/i in 1 to 6) // the sender compiles its C# first: wait until it answers (F24 does nothing anywhere)
		if(findtext(tp_cmd("key 87", 5 SECONDS), "pressed"))
			break

	// 1. alert: Right then Enter picks the second button
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_alert, M, "Vent the plasma into space?", "Atmospherics", list("Yes", "No", "Later")))
	tp_shot("popup_prompt_alert", "370x120")
	var/ack = tp_cmd("key 27")
	kc_log("info the keyboard when the alert opened: [ack]")
	tp_check("the key sender answers", findtext(ack, "pressed"), ack)
	tp_cmd("key 0D")
	tp_wait()
	tp_check("alert: Right, Enter -> No", GLOB.tp_result == "No", tp_desc(GLOB.tp_result))
	sleep(5)
	ack = tp_cmd("key 87")
	kc_log("info after the alert closed the keyboard is in: [ack]")

	// 1b. an alert has no Cancel natively: Escape does nothing, there's no close button, Enter gives the first button
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_alert, M, "Are you sure?", "Sure", list("Yes", "No")))
	var/datum/tgui_prompt/AP = tp_open_prompt()
	var/datum/tgui/AUI = AP && SStgui.get_open_ui(M, AP, AP.prompt_key)
	tp_check("alert window has no close button", AUI && AUI.no_close)
	ack = tp_cmd("key 1B")
	sleep(5)
	tp_check("alert: Escape doesn't answer", !GLOB.tp_done, "[tp_desc(GLOB.tp_result)]; [ack]")
	ack = tp_cmd("key 0D")
	tp_wait()
	tp_check("alert: then Enter -> Yes", GLOB.tp_result == "Yes", "[tp_desc(GLOB.tp_result)]; [ack]")

	// 2. a big list, searched
	var/list/big = list()
	for(var/i in 1 to 3000)
		big += "Item [i]"
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_list, M, "Pick one", "Big list", big, "Item 10"))
	tp_shot("popup_prompt_list", "340x420")
	ack = tp_cmd("type Item 2999")
	tp_wait()
	tp_check("list of 3000: type to search, Enter", GLOB.tp_result == "Item 2999", "[tp_desc(GLOB.tp_result)]; [ack]")

	// 3. a list of atoms gives the atom back; Down moves off the default
	var/obj/item/wrench/W = new
	var/obj/item/crowbar/CR = new
	var/obj/item/wrench/W2 = new
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_list, M, "Which tool?", "Tools", list(W, CR, W2)))
	tp_cmd("key 28")
	tp_cmd("key 28")
	tp_cmd("key 0D")
	tp_wait()
	tp_check("list of atoms: Down Down Enter -> the second wrench itself", GLOB.tp_result == W2, tp_desc(GLOB.tp_result))

	// 4. associative list gives the key
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_list, M, "Mode?", "Assoc", list("Stun" = 1, "Kill" = 2), "Kill"))
	tp_cmd("key 0D")
	tp_wait()
	tp_check("associative list: default Kill, Enter -> \"Kill\"", GLOB.tp_result == "Kill", tp_desc(GLOB.tp_result))

	// 5. Escape on a list cancels
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_list, M, "Pick", "Escape me", list("a", "b")))
	tp_cmd("key 1B")
	tp_wait()
	tp_check("list: Escape -> null", GLOB.tp_done && isnull(GLOB.tp_result), tp_desc(GLOB.tp_result))

	// 6. text, the default is selected so typing replaces it
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_text, M, "Name your pet", "Rename", "Runtime"))
	tp_shot("popup_prompt_text", "360x160")
	ack = tp_cmd("type Ian the Second")
	tp_wait()
	tp_check("text: typed over the default", GLOB.tp_result == "Ian the Second", "[tp_desc(GLOB.tp_result)]; [ack]")

	// 7. max length cuts it short
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_text, M, "Tag", "Short", "", 4))
	tp_cmd("type abcdefgh")
	tp_wait()
	tp_check("text: max length 4", GLOB.tp_result == "abcd", tp_desc(GLOB.tp_result))

	// 8. a message box takes Enter as a newline (the sender then presses Escape: null)
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_text, M, "Write the note", "Paper", "Dear Captain,", 0, TRUE))
	tp_shot("popup_prompt_message", "440x300")
	ack = tp_cmd("type hello")
	tp_wait()
	tp_check("message: Enter adds a line, doesn't send", findtext(ack, "still open") && isnull(GLOB.tp_result), "[tp_desc(GLOB.tp_result)]; [ack]")

	// 9. number, clamped to max
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_number, M, "Release pressure (kPa)", "Valve", 5, 100, 0))
	tp_shot("popup_prompt_number", "360x160")
	tp_cmd("type 250")
	tp_wait()
	tp_check("number: 250 with max 100 -> 100", GLOB.tp_result == 100, tp_desc(GLOB.tp_result))

	// 10. number: letters can't be sent, Escape then gives null
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_number, M, "Amount", "Bad number", null))
	ack = tp_cmd("type abc")
	tp_wait()
	tp_check("number: \"abc\" isn't sent", findtext(ack, "still open") && isnull(GLOB.tp_result), "[tp_desc(GLOB.tp_result)]; [ack]")

	// 11. timeout
	var/t0 = world.time
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_alert, M, "Quick!", "Timed", list("Ok"), 3 SECONDS))
	tp_wait()
	tp_check("timeout 3 s -> null", GLOB.tp_done && isnull(GLOB.tp_result) && world.time - t0 < 6 SECONDS, "[tp_desc(GLOB.tp_result)] after [(world.time - t0) / 10] s")
	tp_check("timed-out window is gone", !tp_open_prompt())

	// 12. source can no longer be used -> closes
	var/obj/item/tp_probe/probe = new
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_text, M, "Set frequency", "Radio", "1459", 0, FALSE, 0, TRUE, probe))
	probe.usable = FALSE
	tp_wait(3 SECONDS)
	tp_check("source out of reach -> null", GLOB.tp_done && isnull(GLOB.tp_result), tp_desc(GLOB.tp_result))
	var/obj/item/tp_probe/probe2 = new
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_alert, M, "Cut the wire?", "Wires", list("Yes", "No"), 0, probe2))
	qdel(probe2)
	tp_wait(3 SECONDS)
	tp_check("source deleted -> null", GLOB.tp_done && isnull(GLOB.tp_result), tp_desc(GLOB.tp_result))

	// 13. window closed from outside -> null
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_alert, M, "Close me", "Closer", list("A", "B")))
	var/datum/tgui_prompt/P = tp_open_prompt()
	tp_check("the harness can see the open prompt", P)
	if(!P)
		kc_log("info giving up: no prompt to drive")
		text2file("x", "data/keycheck_shots_done")
		kc_log("done")
		shutdown()
		return
	SStgui.close_uis(P)
	tp_wait(3 SECONDS)
	tp_check("window closed -> null", GLOB.tp_done && isnull(GLOB.tp_result), tp_desc(GLOB.tp_result))

	// 14. clicked through ui_act, as the page does
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_alert, M, "Click", "Clicker", list("A", "B", "C")))
	P = tp_open_prompt()
	P.ui_act("submit", list("index" = "3"), SStgui.get_open_ui(M, P, P.prompt_key), GLOB.always_state)
	tp_wait(3 SECONDS)
	tp_check("button 3 clicked -> C", GLOB.tp_result == "C", tp_desc(GLOB.tp_result))
	tp_start(CALLBACK(GLOBAL_PROC, /proc/tgui_input_list, M, "Click", "Bad index", list("x")))
	P = tp_open_prompt()
	P.ui_act("submit", list("index" = "7"), SStgui.get_open_ui(M, P, P.prompt_key), GLOB.always_state)
	sleep(3)
	tp_check("an index past the end is ignored", !GLOB.tp_done)
	P.ui_act("cancel", list(), SStgui.get_open_ui(M, P, P.prompt_key), GLOB.always_state)
	tp_wait(3 SECONDS)
	tp_check("cancel -> null", GLOB.tp_done && isnull(GLOB.tp_result))

	// 15. no client: the native answers at once
	var/mob/living/carbon/human/dummy/D = new
	var/t1 = world.time
	tp_check("no client: alert -> first button", tgui_alert(D, "x", "x", list("Yes", "No")) == "Yes")
	tp_check("no client: list -> default", tgui_input_list(D, "x", "x", list("a", "b"), "b") == "b")
	tp_check("no client: list, no default -> null", isnull(tgui_input_list(D, "x", "x", list("a", "b"))))
	tp_check("no client: text -> default", tgui_input_text(D, "x", "x", "def") == "def")
	tp_check("no client: number -> default", tgui_input_number(D, "x", "x", 7) == 7)
	tp_check("no client: no waiting", world.time == t1)
	tp_check("a client as the target works", isnull(tgui_input_list(C, "x", "x", list())))
	qdel(D)

	// 16. a converted call in the game: the OOC Ignore verb's pick list, answered with Enter (yourself: refused)
	GLOB.tp_last_title = null
	GLOB.tp_last_result = null
	GLOB.tp_ignore_ran = FALSE
	spawn(0)
		usr = C.mob // a verb run from code has no usr; a click gives it the player
		C.select_ignore()
		GLOB.tp_ignore_ran = TRUE
	sleep(12)
	P = tp_open_prompt()
	tp_check("Ignore verb opens a tgui list", P && P.title == "Ignore" && length(P.choices) >= 1, P ? "[P.title], [length(P.choices)] rows" : "no prompt")
	tp_shot("popup_prompt_ignore_verb", "340x420")
	tp_cmd("key 0D")
	for(var/i in 1 to 30)
		if(GLOB.tp_ignore_ran)
			break
		sleep(1)
	tp_check("Ignore verb got its answer and finished", GLOB.tp_ignore_ran && GLOB.tp_last_title == "Ignore" && !isnull(GLOB.tp_last_result), "result [tp_desc(GLOB.tp_last_result)]")

	tp_check("no prompt left open", !tp_open_prompt())
	kc_log("info [GLOB.tp_pass] passed, [GLOB.tp_fail] wrong, [(world.timeofday - start_ms) / 10] s")
	text2file("x", "data/keycheck_shots_done")
	sleep(10)
	kc_log("done")
	shutdown()
