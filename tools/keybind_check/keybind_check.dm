// Real-client check of the keybinds. Not part of the game: tools/keybind_check/run.sh builds a copy of the .dme with this added.
// A guest connects, and this drives what needs a real client: the walk key through keyDown()/keyUp(), where the keyboard's focus
// reports itself to be, the real "press any key" window through its own JavaScript, and what BYOND calls each key on a real press.
// Results in data/keycheck.txt. Works on a build without the fixes too, for a before and after.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(keycheck_real_keys)
GLOBAL_LIST_EMPTY(keycheck_real_ups)

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			keycheck_run(src)

// Whoever connects, nothing here may reach their saved preferences. ##guest doesn't always come in as a guest: a run of this got
// the real login, and bound test keys into the real save. run.sh compares the save files as well.
/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

// Every real key that arrives, by the name BYOND gives it.
/client/keyDown(_key as text)
	set instant = TRUE
	set hidden = TRUE
	GLOB.keycheck_real_keys += _key
	return ..()

/client/keyUp(_key as text)
	set instant = TRUE
	set hidden = TRUE
	GLOB.keycheck_real_ups += _key
	return ..()

/proc/kc_walk(client/C, name, list/sequence, start, expected)
	var/mob/M = C.mob
	C.keys_held.Cut()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held += null
	if(M.m_intent != start)
		M.toggle_move_intent()
	if("held_move_intent" in C.vars)
		C.vars["held_move_intent"] = null
	for(var/step in sequence)
		var/what = copytext(step, 2)
		switch(copytext(step, 1, 2))
			if("+")
				C.keyDown(what)
			if("-")
				C.keyUp(what)
			if("!") //the keyboard went somewhere else
				if(hascall(C, "reset_held_keys"))
					call(C, "reset_held_keys")()
	kc_log("[M.m_intent == expected ? "ok   " : "WRONG"] walk: [name]: ends on [M.m_intent]")
	C.keyUp("Alt")

/proc/kc_capture(client/C, key, code, key_code, alt, ctrl, shift, expected)
	var/datum/preferences/P = C.prefs
	var/datum/keybinding/kb = GLOB.keybindings_by_name["toggle_move_intent_alt"]
	var/list/before = deepCopyList(P.key_bindings)
	P.CaptureKeybinding(C.mob, kb, "Unbound")
	sleep(10)
	var/js = "var e={key:[json_encode(key)],code:[json_encode(code)],keyCode:[key_code],altKey:[alt],ctrlKey:[ctrl],shiftKey:[shift],preventDefault:function(){}};if(document.onkeydown){document.onkeydown(e);}document.onkeyup(e);"
	C << output(url_encode(js), "capturekeypress.browser:eval")
	var/saved
	for(var/tries in 1 to 30)
		sleep(1)
		for(var/k in P.key_bindings)
			if((kb.name in P.key_bindings[k]) && !(kb.name in before[k]))
				saved = k
		if(saved)
			break
	kc_log("[saved == expected ? "ok   " : "WRONG"] capture: [key] ([code]) expected [expected], saved \"[saved]\"")
	if(saved)
		P.key_bindings = before
	C << browse(null, "window=capturekeypress")
	C << browse(null, "window=preferences_window")
	sleep(2)

/proc/keycheck_run(client/C)
	kc_log("client [C.key] BYOND [C.byond_version].[C.byond_build], hotkey mode [C.prefs.hotkeys], Alt is bound to [english_list(C.prefs.key_bindings["Alt"])]")

	// ---- the walk key
	kc_walk(C, "held and let go", list("+Alt", "-Alt"), MOVE_INTENT_RUN, MOVE_INTENT_RUN)
	kc_walk(C, "while held", list("+Alt"), MOVE_INTENT_RUN, MOVE_INTENT_WALK)
	kc_walk(C, "Ctrl held first, as AltGr does", list("+Ctrl", "+Alt", "-Alt", "-Ctrl"), MOVE_INTENT_RUN, MOVE_INTENT_RUN)
	kc_walk(C, "Shift held first", list("+Shift", "+Alt", "-Alt", "-Shift"), MOVE_INTENT_RUN, MOVE_INTENT_RUN)
	kc_walk(C, "a release with no press", list("-Alt"), MOVE_INTENT_RUN, MOVE_INTENT_RUN)
	kc_walk(C, "Alt-Tab: the keyboard goes away, the release never comes", list("+Alt", "!"), MOVE_INTENT_RUN, MOVE_INTENT_RUN)
	kc_walk(C, "pressed twice, first release lost", list("+Alt", "+Alt", "-Alt"), MOVE_INTENT_RUN, MOVE_INTENT_RUN)
	kc_walk(C, "already walking, held to run and let go", list("+Alt", "-Alt"), MOVE_INTENT_WALK, MOVE_INTENT_WALK)

	// ---- modifiers that stay stuck
	C.keys_held.Cut()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held += null
	C.keyDown("Alt")
	if(hascall(C, "check_modifiers_against"))
		call(C, "check_modifiers_against")(list("left" = "1"))
	kc_log("[C.keys_held["Alt"] ? "WRONG" : "ok   "] click with no Alt in it clears a stuck Alt")
	C.keyUp("Alt")

	// ---- where the keyboard says it is
	kc_log("info focus at login: \"[winget(C, null, "focus")]\"")
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	kc_log("info focus on the map: \"[winget(C, null, "focus")]\"")
	winset(C, "input", "focus=true")
	sleep(5)
	kc_log("info focus on the chat bar: \"[winget(C, null, "focus")]\"")
	C << browse("<html><body><input id='i'><script>document.getElementById('i').focus();</script></body></html>", "window=kc_popup;size=300x200")
	sleep(10)
	winset(C, "kc_popup.browser", "focus=true")
	sleep(5)
	kc_log("info focus in a browser popup: \"[winget(C, null, "focus")]\"")
	C << browse(null, "window=kc_popup")
	sleep(5)
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)

	// ---- the keyboard in the chat pane: a key pressed there hands it back to the game, key and all
	GLOB.keycheck_real_keys.Cut()
	winset(C, "browseroutput", "focus=true")
	sleep(5)
	kc_log("info focus in the chat pane: \"[winget(C, null, "focus")]\"")
	var/chat_key = "var e=$.Event('keydown');e.which=87;e.key='w';e.target=document.body;$('body').trigger(e);"
	C << output(url_encode(chat_key), "browseroutput:eval")
	sleep(10)
	kc_log("[("W" in GLOB.keycheck_real_keys) ? "ok   " : "WRONG"] a key pressed in the chat pane reaches the game: [jointext(GLOB.keycheck_real_keys, " ")]")
	kc_log("[findtext(winget(C, null, "focus"), ".map") ? "ok   " : "WRONG"] and the keyboard goes back to the map: \"[winget(C, null, "focus")]\"")
	C.keyUp("W")

	// ---- a tgui window: on Chromium it used to keep every key to itself
	var/datum/language_menu/menu = new(C.mob.get_language_holder())
	menu.ui_interact(C.mob, "main", null, FALSE, null, GLOB.always_state)
	sleep(20)
	var/datum/tgui/ui = SStgui.get_open_ui(C.mob, menu, "main")
	if(ui)
		winset(C, "[ui.window_id].browser", "focus=true")
		sleep(5)
		kc_log("info focus in a tgui window: \"[winget(C, null, "focus")]\"")
		GLOB.keycheck_real_keys.Cut()
		GLOB.keycheck_real_ups.Cut()
		if(C.mob.m_intent != MOVE_INTENT_RUN)
			C.mob.toggle_move_intent()
		var/press = "function kcKey(type,code){var e=new Event(type,{bubbles:true});e.keyCode=code;Object.defineProperty(e,'which',{get:function(){return code;}});document.body.dispatchEvent(e);}"
		C << output(url_encode("[press]kcKey('keydown',87);"), "[ui.window_id].browser:eval")
		sleep(10)
		kc_log("[("W" in GLOB.keycheck_real_keys) ? "ok   " : "WRONG"] a key pressed in a tgui window reaches the game: [jointext(GLOB.keycheck_real_keys, " ")]")
		C << output(url_encode("[press]kcKey('keydown',18);"), "[ui.window_id].browser:eval")
		sleep(10)
		kc_log("[C.mob.m_intent == MOVE_INTENT_WALK ? "ok   " : "WRONG"] Alt held in a tgui window walks: [C.mob.m_intent]")
		C << output(url_encode("document.getElementById('Layout__content').blur();window.dispatchEvent(new Event('beforeunload'));"), "[ui.window_id].browser:eval")
		sleep(10)
		kc_log("[("W" in GLOB.keycheck_real_ups) ? "ok   " : "WRONG"] a tgui window closing with W held lets go of it: released [jointext(GLOB.keycheck_real_ups, " ")]")
		kc_log("[C.mob.m_intent == MOVE_INTENT_RUN ? "ok   " : "WRONG"] and with Alt held, back to running: [C.mob.m_intent]")
		ui.close()
		C.keyUp("W")
		C.keyUp("Alt")
	else
		kc_log("info no tgui window could be opened here, skipped")
	qdel(menu)
	sleep(5)

	// ---- a real Alt-Tab, real key events and all
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	if(C.mob.m_intent != MOVE_INTENT_RUN)
		C.mob.toggle_move_intent()
	C.keys_held.Cut()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held += null
	GLOB.keycheck_real_keys.Cut()
	GLOB.keycheck_real_ups.Cut()
	text2file("go", "data/keycheck_alttab")
	for(var/tries in 1 to 100)
		sleep(1)
		if(fexists("data/keycheck_alttab_done"))
			break
	sleep(5)
	var/alt_tabbed = findtext(file2text("data/keycheck_alttab_done"), "switched away: True")
	kc_log("info real Alt-Tab: [file2text("data/keycheck_alttab_done")]")
	kc_log("info real Alt-Tab: the game saw pressed [jointext(GLOB.keycheck_real_keys, " ")], released [jointext(GLOB.keycheck_real_ups, " ")]")
	if(alt_tabbed)
		kc_log("[C.keys_held["Alt"] ? "WRONG" : "ok   "] real Alt-Tab: Alt is not left down, intent [C.mob.m_intent]")
		kc_log("[C.mob.m_intent == MOVE_INTENT_RUN ? "ok   " : "WRONG"] real Alt-Tab: still running afterwards")
	text2file("go", "data/keycheck_alttab_back")
	sleep(10)
	C.keyUp("Alt")

	// ---- the keyboard elsewhere, with a key the game only believes is held
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	if(C.mob.m_intent != MOVE_INTENT_RUN)
		C.mob.toggle_move_intent()
	C.keys_held.Cut()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held += null
	C.keyDown("Alt")
	text2file("go", "data/keycheck_focus_away")
	for(var/tries in 1 to 100)
		sleep(1)
		if(fexists("data/keycheck_focus_gone"))
			break
	sleep(5)
	kc_log("info another program has the keyboard: focus \"[winget(C, null, "focus")]\", mainwindow.focus \"[winget(C, "mainwindow", "focus")]\", map.focus \"[winget(C, "mapwindow.map", "focus")]\"")
	sleep(25)
	if(findtext(file2text("data/keycheck_focus_gone"), "had it"))
		kc_log("[C.mob.m_intent == MOVE_INTENT_RUN ? "ok   " : "WRONG"] another program took the keyboard with Alt held: intent [C.mob.m_intent] after 3 seconds")
		kc_log("[C.keys_held["Alt"] ? "WRONG" : "ok   "] and Alt is no longer down")
	else
		kc_log("info the game never had the foreground, so nothing to lose: skipped")
	C.keyUp("Alt")
	text2file("go", "data/keycheck_focus_back")
	sleep(10)

	// ---- the real thing: a key held as the whole window goes away
	if(C.mob.m_intent != MOVE_INTENT_RUN)
		C.mob.toggle_move_intent()
	C.keys_held.Cut()
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held += null
	C.keyDown("Alt")
	kc_log("info Alt held, intent [C.mob.m_intent]; minimising the game window")
	winset(C, "mainwindow", "is-minimized=true")
	sleep(5)
	kc_log("info focus with the window minimised: \"[winget(C, null, "focus")]\"")
	sleep(25)
	kc_log("[C.mob.m_intent == MOVE_INTENT_RUN ? "ok   " : "WRONG"] window lost the keyboard with Alt held: intent [C.mob.m_intent] after 3 seconds")
	kc_log("[C.keys_held["Alt"] ? "WRONG" : "ok   "] and Alt is no longer down")
	C.keyUp("Alt")
	winset(C, "mainwindow", "is-minimized=false")
	sleep(10)

	// ---- the capture window
	var/list/cases = list(
		list(" ", "Space", 32, 0, 0, 0, "Space"),
		list("ArrowUp", "ArrowUp", 38, 0, 0, 0, "North"),
		list("ArrowRight", "ArrowRight", 39, 0, 0, 0, "East"),
		list("ArrowDown", "ArrowDown", 40, 0, 0, 0, "South"),
		list("ArrowLeft", "ArrowLeft", 37, 0, 0, 0, "West"),
		list("Delete", "Delete", 46, 0, 0, 0, "Delete"),
		list("Insert", "Insert", 45, 0, 0, 0, "Insert"),
		list("Home", "Home", 36, 0, 0, 0, "Northwest"),
		list("End", "End", 35, 0, 0, 0, "Southwest"),
		list("PageUp", "PageUp", 33, 0, 0, 0, "Northeast"),
		list("PageDown", "PageDown", 34, 0, 0, 0, "Southeast"),
		list("Enter", "Enter", 13, 0, 0, 0, "Return"),
		list("Backspace", "Backspace", 8, 0, 0, 0, "Back"),
		list("Tab", "Tab", 9, 0, 0, 0, "Tab"),
		list("F1", "F1", 112, 0, 0, 0, "F1"),
		list("a", "KeyA", 65, 0, 0, 0, "A"),
		list("A", "KeyA", 65, 0, 0, 1, "ShiftA"),
		list("z", "KeyZ", 90, 0, 1, 0, "CtrlZ"),
		list("5", "Digit5", 53, 0, 0, 0, "5"),
		list("!", "Digit1", 49, 0, 0, 1, "Shift1"),
		list("?", "Slash", 191, 0, 0, 1, "Shift/"),
		list("/", "Slash", 191, 0, 0, 0, "/"),
		list(";", "Semicolon", 186, 0, 0, 0, ";"),
		list("=", "Equal", 187, 0, 0, 0, "="),
		list("+", "NumpadAdd", 107, 0, 0, 0, "Add"),
		list("-", "NumpadSubtract", 109, 0, 0, 0, "Subtract"),
		list("*", "NumpadMultiply", 106, 0, 0, 0, "Multiply"),
		list("/", "NumpadDivide", 111, 0, 0, 0, "Divide"),
		list(".", "NumpadDecimal", 110, 0, 0, 0, "Decimal"),
		list("0", "Numpad0", 96, 0, 0, 0, "Numpad0"),
		list("5", "Numpad5", 101, 0, 0, 0, "Numpad5"),
		list("\[", "BracketLeft", 219, 0, 0, 0, "\["),
		list("Alt", "AltLeft", 18, 0, 0, 0, "Alt"),
		list("Control", "ControlLeft", 17, 0, 0, 0, "Ctrl"),
	)
	for(var/list/K in cases)
		kc_capture(C, K[1], K[2], K[3], K[4], K[5], K[6], K[7])

	// ---- what BYOND calls real keys
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	GLOB.keycheck_real_keys.Cut()
	text2file("go", "data/keycheck_sendkeys")
	for(var/tries in 1 to 200)
		sleep(1)
		if(fexists("data/keycheck_keys_sent"))
			break
	sleep(10)
	kc_log("real keys: [jointext(GLOB.keycheck_real_keys, " ")]")
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
