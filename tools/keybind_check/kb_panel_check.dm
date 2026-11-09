// Real-client check of the keybind panel (hippiestation/code/modules/keybindings/keybind_panel.dm, KeybindPanel.js). Not part of the
// game: HARNESS=kb_panel_check.dm SENDER=kb_panel.ps1 tools/keybind_check/run.sh <label>
// Key names, the capture, clashes, an old save getting the new actions, then with a real client: T and Y open their prompts through
// the macros made for them, say moved to G leaves T doing nothing, and the panel itself clicked and typed into through its own
// page (key events dispatched on the window, as a real key press reaches it). Pictures in data/previews/kbpanel_*.png.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(kp_said)
GLOBAL_VAR(kp_dom)
GLOBAL_VAR_INIT(kp_pass, 0)
GLOBAL_VAR_INIT(kp_fail, 0)

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
			kp_run(src)

/mob/say_verb(message as text)
	GLOB.kp_said += message
	kc_log("info say ran: \"[message]\"")
	return ..()

// The chat bar runs Say with call(), which skips the verb override above: what reaches say() is recorded too
/mob/say(message, bubble_type, list/spans = list(), sanitize = TRUE, datum/language/language = null, ignore_spam = FALSE, forced = null)
	GLOB.kp_said += "[message]"
	return ..()

/mob/living/say(message, bubble_type, list/spans = list(), sanitize = TRUE, datum/language/language = null, ignore_spam = FALSE, forced = null)
	GLOB.kp_said += "[message]"
	return ..()

/client/Topic(href, list/href_list, hsrc)
	if(href_list["kp_dom"])
		GLOB.kp_dom = href_list["kp_dom"]
		return
	return ..()

/proc/kp_check(name, ok, detail = "")
	if(ok)
		GLOB.kp_pass++
	else
		GLOB.kp_fail++
	kc_log("[ok ? "ok   " : "WRONG"] [name][detail ? " ([detail])" : ""]")

/// Typing and Enter into the chat bar if the chat page has the keyboard (a talk key gave it), through the page's DOM: posted keys
/// don't reach WebView2. With the keyboard elsewhere nothing is typed.
/proc/kp_bar_type(client/C, text)
	GLOB.kp_dom = null
	var/js = "var report=function(x){Byond.topic({kp_dom:String(x)});};var a=document.activeElement;var state=document.hasFocus()+'|'+(a?a.tagName:'none')+'|'+(a&&a.value!==undefined?a.value:'');if(document.hasFocus()&&a&&a.tagName=='INPUT'){var set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;set.call(a,a.value+[json_encode(text)]);a.dispatchEvent(new Event('input',{bubbles:true}));setTimeout(function(){a.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));report(state+' -> typed');},50);}else{report(state+' -> not typed');}"
	C << output(url_encode(js), "browseroutput:eval")
	for(var/i in 1 to 15)
		if(!isnull(GLOB.kp_dom))
			break
		sleep(1)
	sleep(5)
	return "chat page [GLOB.kp_dom]"

/// kb_panel.ps1 does one thing (a key, typing into what has the keyboard, a picture) and answers
/proc/kp_cmd(text, timeout = 20 SECONDS)
	fdel("data/kp_ack")
	fdel("data/kp_cmd")
	text2file(text, "data/kp_cmd")
	var/deadline = world.time + timeout
	while(!fexists("data/kp_ack") && world.time < deadline)
		sleep(1)
	. = fexists("data/kp_ack") ? trim(file2text("data/kp_ack")) : "no answer"
	fdel("data/kp_ack")

/proc/kp_shot(name)
	fdel("data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// Runs js in a tgui window; whatever it hands report() comes back
/proc/kp_js(client/C, datum/tgui/ui, js, wait = 15)
	GLOB.kp_dom = null
	var/helpers = {"
var report=function(x){window.__sendToByond__('byond://?kp_dom='+encodeURIComponent(x));};
var row=function(name){var rows=document.querySelectorAll('tr');for(var i=0;i<rows.length;i++){var c=rows\[i].querySelector('td');if(c&&c.textContent.trim()===name){return rows\[i];}}return null;};
var btn=function(r,text){var b=r.querySelectorAll('.Button');for(var i=0;i<b.length;i++){if(b\[i].textContent.trim()===text){return b\[i];}}return null;};
var plus=function(r){var b=r.querySelectorAll('.Button');for(var i=0;i<b.length;i++){if(b\[i].querySelector('.fa-plus')){return b\[i];}}return null;};
var press=function(type,key,code,mods){mods=mods||{};window.dispatchEvent(new KeyboardEvent(type,{key:key,code:code,altKey:!!mods.alt,ctrlKey:!!mods.ctrl,shiftKey:!!mods.shift,bubbles:true,cancelable:true}));};
"}
	C << output(url_encode(helpers + "try{" + js + "}catch(e){report('error: '+e.message);}"), "[ui.window_id].browser:eval")
	for(var/i in 1 to wait)
		if(!isnull(GLOB.kp_dom))
			break
		sleep(1)
	return GLOB.kp_dom

/proc/kp_on(datum/preferences/P, kb_name, key)
	return (kb_name in P.key_bindings[key]) ? TRUE : FALSE

/proc/kp_run(client/C)
	for(var/i in 1 to 300)
		if(!C)
			return
		if(SSticker.current_state >= GAME_STATE_PREGAME && C.mob && C.prefs && C.chatOutput?.loaded)
			break
		sleep(1)
	sleep(40) // the chat page has its verbs: a talk key opens the bar on one
	var/datum/preferences/P = C.prefs
	kc_log("info hotkeys [P.hotkeys], [length(P.key_bindings)] keys bound")

	// Names
	var/list/labels = list("CtrlShiftE" = "Ctrl+Shift+E", "North" = "Up", "Numpad8" = "Num 8", "AltShift" = "Alt+Shift", "Add" = "Num +", "Alt" = "Alt", "AltCtrlW" = "Ctrl+Alt+W", "Northwest" = "Home", "Unbound" = "None")
	for(var/k in labels)
		kp_check("label [k] -> [labels[k]]", keybind_label(k) == labels[k], keybind_label(k))
	kp_check("macro name CtrlShiftE", keybind_macro_name("CtrlShiftE") == "Ctrl+Shift+E", keybind_macro_name("CtrlShiftE"))
	var/list/caps = list(
		list(list("key" = "!", "code" = "Digit1", "shift" = "1"), "Shift1"),
		list(list("key" = "g", "code" = "KeyG"), "G"),
		list(list("key" = "Alt", "code" = "AltLeft", "ctrl" = "1"), "AltCtrl"),
		list(list("key" = "ArrowUp", "code" = "ArrowUp", "ctrl" = "1"), "CtrlNorth"),
		list(list("key" = "+", "code" = "NumpadAdd"), "Add"),
		list(list("key" = "\"", "code" = "Quote", "shift" = "1"), "Shift'"),
		)
	for(var/list/c in caps)
		var/got = keybind_from_capture(c[1])
		kp_check("capture [json_encode(c[1])] -> [c[2]]", got == c[2], "[got]")

	// Defaults: what a new player starts with, and what clashes there
	kp_check("say on T, me on M, ooc on O, radio on Y by default", kp_on(P, "say", "T") && kp_on(P, "me", "M") && kp_on(P, "ooc", "O") && kp_on(P, "radio", "Y"))
	var/list/default_clashes = list()
	for(var/key in P.key_bindings)
		var/list/names = P.key_bindings[key]
		for(var/a in names)
			var/list/clash = P.keybind_clashes(GLOB.keybindings_by_name[a], key)
			if(length(clash))
				default_clashes |= "[keybind_label(key)]: [a] + [clash.Join(", ")]"
	kp_check("no clashes in the defaults", !length(default_clashes), default_clashes.Join("; "))
	kp_check("facing on Ctrl+arrows only, Ctrl+S just Scream", kp_on(P, "face_south", "CtrlSouth") && !kp_on(P, "face_south", "CtrlS") && kp_on(P, "scream", "CtrlS") && !P.key_bindings["CtrlW"] && !P.key_bindings["CtrlA"] && !P.key_bindings["CtrlD"])

	// An old save: none of the new actions, T holding throw mode as well, U holding drop item
	var/list/saved_binds = deepCopyList(P.key_bindings)
	var/list/old = deepCopyList(GLOB.hotkey_keybinding_list_by_key)
	for(var/key in old.Copy())
		old[key] -= GLOB.keybinds_added_2026_11
		if(!length(old[key]))
			old -= key
	old["T"] = list("toggle_throw_mode")
	old["U"] = list("drop_item")
	P.key_bindings = old
	P.known_keybinds = null
	var/added = P.add_new_keybind_defaults()
	kp_check("old save: something was added", added)
	kp_check("old save: say still on T, alongside throw mode", kp_on(P, "say", "T") && kp_on(P, "toggle_throw_mode", "T"))
	kp_check("old save: rest left off U, drop item is there", !kp_on(P, "rest", "U") && kp_on(P, "drop_item", "U"))
	kp_check("old save: radio on Y, pray on P", kp_on(P, "radio", "Y") && kp_on(P, "pray", "P"))
	kp_check("old save: every action known now", length(P.known_keybinds) == length(GLOB.keybindings_by_name), "[length(P.known_keybinds)] of [length(GLOB.keybindings_by_name)]")
	kp_check("old save: nothing more the second time", !P.add_new_keybind_defaults())
	// A version 28 save: Ctrl+W/A/S/D still face, Ctrl+S screams too
	var/list/v28 = deepCopyList(saved_binds)
	v28["CtrlS"] = list("face_south", "scream")
	v28["CtrlW"] = list("face_north")
	v28["CtrlA"] = list("face_west")
	v28["CtrlD"] = list("face_east")
	P.key_bindings = v28
	P.update_preferences(28, null)
	kp_check("version 28 save: Ctrl+S only screams, Ctrl+W/A/D gone, Ctrl+Down still faces south", (P.key_bindings["CtrlS"] ~= list("scream")) && !P.key_bindings["CtrlW"] && !P.key_bindings["CtrlA"] && !P.key_bindings["CtrlD"] && kp_on(P, "face_south", "CtrlSouth"), json_encode(P.key_bindings["CtrlS"]))
	P.key_bindings = saved_binds
	C.update_movement_keys()

	// Clashes through keybind_act(), as the page sends them
	P.keybind_act("kb_capture", list("id" = "rest", "old" = "U", "key" = "r", "code" = "KeyR"), C.mob)
	kp_check("rest onto R (throw mode's) asks", islist(P.keybind_pending) && kp_on(P, "rest", "U") && !kp_on(P, "rest", "R"))
	P.keybind_act("kb_resolve", list("choice" = "cancel"), C.mob)
	kp_check("cancel leaves both alone", !P.keybind_pending && kp_on(P, "rest", "U") && !kp_on(P, "rest", "R") && kp_on(P, "toggle_throw_mode", "R"))
	P.keybind_act("kb_capture", list("id" = "rest", "old" = "U", "key" = "r", "code" = "KeyR"), C.mob)
	P.keybind_act("kb_resolve", list("choice" = "move"), C.mob)
	kp_check("move here: rest on R, throw mode off it, U free", kp_on(P, "rest", "R") && !kp_on(P, "toggle_throw_mode", "R") && !kp_on(P, "rest", "U"))
	P.keybind_act("kb_reset", list("id" = "rest"), C.mob)
	P.keybind_act("kb_reset", list("id" = "toggle_throw_mode"), C.mob)
	kp_check("reset puts both back", kp_on(P, "rest", "U") && kp_on(P, "toggle_throw_mode", "R") && !kp_on(P, "rest", "R"))
	P.keybind_act("kb_capture", list("id" = "module_one", "old" = "1", "key" = "e", "code" = "KeyE"), C.mob)
	kp_check("a cyborg's module onto E (quick equip's) doesn't ask: nothing fires both", !P.keybind_pending && kp_on(P, "module_one", "E") && kp_on(P, "quick_equip", "E"))
	P.keybind_act("kb_capture", list("id" = "module_two", "old" = "2", "key" = "q", "code" = "KeyQ"), C.mob)
	kp_check("but onto Q it asks: the cyborg's Unequip module is there", islist(P.keybind_pending))
	P.keybind_act("kb_resolve", list("choice" = "cancel"), C.mob)
	P.keybind_act("kb_reset", list("id" = "module_one"), C.mob)
	P.keybind_act("kb_capture", list("id" = "whisper", "key" = "\"", "code" = "Quote", "shift" = "1"), C.mob)
	kp_check("whisper gets Shift+'", kp_on(P, "whisper", "Shift'"))
	P.keybind_act("kb_capture", list("id" = "whisper", "old" = "Shift'", "clear" = "1", "key" = "Escape", "code" = "Escape"), C.mob)
	kp_check("Escape clears it", !kp_on(P, "whisper", "Shift'"))
	P.keybind_act("kb_capture", list("id" = "whisper", "key" = "x;y", "code" = ""), C.mob)
	kp_check("a made-up key name is refused", !length(P.keybind_keys_of("whisper")))
	P.keybind_act("kb_capture", list("id" = "whisper", "key" = "F11", "code" = "F11", "ctrl" = "1"), C.mob)
	kp_check("a named key with a modifier is fine: Ctrl+F11", kp_on(P, "whisper", "CtrlF11"))
	P.keybind_act("kb_capture", list("id" = "whisper", "old" = "CtrlF11", "clear" = "1"), C.mob)

	// The macros, then real keys
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(10, 10)
	var/turf/home = locate(R.bottom_left_coords[1] + 5, R.bottom_left_coords[2] + 5, R.bottom_left_coords[3])
	for(var/turf/T in block(locate(R.bottom_left_coords[1], R.bottom_left_coords[2], R.bottom_left_coords[3]), locate(R.bottom_left_coords[1] + 9, R.bottom_left_coords[2] + 9, R.bottom_left_coords[3])))
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	var/mob/living/carbon/human/H = new(home)
	H.status_flags |= GODMODE
	C.mob = H
	sleep(20)
	kc_log("info talk macros: [kp_macro_names(C)]")
	kp_check("macros for T, M, O, Y and P", kp_has_macros(C, list("T", "M", "O", "Y", "P")), kp_macro_names(C))
	kp_check("the fixed T/M/O macros are gone from SSinput", !SSinput.macro_set["T"] && !SSinput.macro_set["M"] && !SSinput.macro_set["O"])
	text2file("go", "data/keycheck_sendkeys") //starts kb_panel.ps1
	winset(C, "mapwindow.map", "focus=true")
	sleep(10)
	kc_log("info [kp_cmd("key 54")]") //T
	kc_log("info [kp_bar_type(C, "hi")]")
	sleep(10)
	kp_check("T opened say: \"hi\" said", ("hi" in GLOB.kp_said))
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	kc_log("info [kp_cmd("key 59")]") //Y
	kc_log("info [kp_bar_type(C, "yo")]")
	sleep(10)
	kp_check("Y opened the radio prompt: \";yo\" said", (";yo" in GLOB.kp_said))
	P.keybind_act("kb_capture", list("id" = "say", "old" = "T", "key" = "g", "code" = "KeyG"), C.mob)
	sleep(5)
	kp_check("say moved to G", kp_on(P, "say", "G") && !kp_on(P, "say", "T"), kp_macro_names(C))
	kp_check("macro moved with it", kp_has_macros(C, list("G")) && !kp_has_macros(C, list("T")), kp_macro_names(C))
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	kc_log("info [kp_cmd("key 54")]") //T
	kc_log("info [kp_bar_type(C, "zz")]")
	sleep(10)
	kp_check("T does nothing now: \"zz\" never said", !("zz" in GLOB.kp_said))
	winset(C, "mapwindow.map", "focus=true")
	sleep(5)
	kc_log("info [kp_cmd("key 47")]") //G
	kc_log("info [kp_bar_type(C, "gg")]")
	sleep(10)
	kp_check("G opens say: \"gg\" said", ("gg" in GLOB.kp_said))
	P.keybind_act("kb_reset", list("id" = "say"), C.mob)

	// The panel in its own window
	C.keybindings_menu()
	sleep(40)
	var/datum/tgui/ui = SStgui.get_open_ui(C.mob, C.keybind_menu, "main")
	kp_check("the Keybindings window opened", !!ui)
	if(ui)
		var/got = kp_js(C, ui, "report(document.querySelectorAll('tr').length + ' rows; ' + (row('Radio (;)') ? 'radio row' : 'no radio row') + '; ' + (row('Face South') && row('Face South').querySelector('.Button--color--bad') ? 'face south red' : 'face south plain'));")
		kc_log("info window: [got]")
		kp_check("rows drawn, Radio among them, Face South not red", findtext(got, "radio row") && !findtext(got, "no radio") && findtext(got, "face south plain"), got)
		kp_shot("popup_kbpanel_window")
		// + on Whisper, then K
		got = kp_js(C, ui, "var r=row('Whisper');plus(r).click();setTimeout(function(){report(btn(row('Whisper'),'Press a key')?'waiting':'not waiting');},300);")
		kp_check("+ on Whisper waits for a key", got == "waiting", got)
		kp_shot("popup_kbpanel_capturing")
		kp_js(C, ui, "press('keydown','k','KeyK');press('keyup','k','KeyK');setTimeout(function(){report('sent');},300);")
		sleep(5)
		kp_check("K pressed in the window binds Whisper to K", kp_on(P, "whisper", "K"))
		// Rest's U, then R: the question, in the row
		kp_js(C, ui, "btn(row('Rest'),'U').click();setTimeout(function(){press('keydown','r','KeyR');setTimeout(function(){report('sent');},200);},200);")
		sleep(10)
		got = kp_js(C, ui, "row('Rest').scrollIntoView({block:'center'});report(document.body.textContent.indexOf('R is Toggle throw mode')>=0?'asked':'not asked: '+document.body.textContent.slice(0,200));")
		kp_check("R on Rest asks in the window", got == "asked", got)
		kp_shot("popup_kbpanel_clash")
		kp_js(C, ui, "btn(document.body,'Keep both').click();setTimeout(function(){report('sent');},300);")
		sleep(5)
		kp_check("Keep both: Rest and throw mode on R", kp_on(P, "rest", "R") && kp_on(P, "toggle_throw_mode", "R") && !kp_on(P, "rest", "U"))
		got = kp_js(C, ui, "setTimeout(function(){var b=btn(row('Rest'),'R');report(b&&b.className.indexOf('Button--color--bad')>=0?'red':'not red');},300);")
		kp_check("Rest's R shows red", got == "red", got)
		// Escape on it, then the reset arrow
		kp_js(C, ui, "btn(row('Rest'),'R').click();setTimeout(function(){press('keydown','Escape','Escape');setTimeout(function(){report('sent');},200);},200);")
		sleep(5)
		kp_check("Escape cleared Rest's R", !kp_on(P, "rest", "R") && kp_on(P, "toggle_throw_mode", "R"))
		kp_js(C, ui, "setTimeout(function(){row('Rest').querySelector('.fa-undo').parentNode.click();setTimeout(function(){report('sent');},200);},300);")
		sleep(5)
		kp_check("the reset arrow put Rest back on U", kp_on(P, "rest", "U"))
		// A combination: Ctrl held, then E, on Whisper's K
		kp_js(C, ui, "setTimeout(function(){btn(row('Whisper'),'K').click();setTimeout(function(){press('keydown','Control','ControlLeft',{ctrl:1});press('keydown','e','KeyE',{ctrl:1,shift:1});setTimeout(function(){report('sent');},200);},200);},300);")
		sleep(5)
		kp_check("Ctrl+Shift+E pressed: Whisper on CtrlShiftE", kp_on(P, "whisper", "CtrlShiftE") && !kp_on(P, "whisper", "K"))
		got = kp_js(C, ui, "setTimeout(function(){report(btn(row('Whisper'),'Ctrl+Shift+E')?'shown':'not shown');},300);")
		kp_check("it shows as Ctrl+Shift+E", got == "shown", got)
		// A modifier on its own counts when let go (Shift: Alt is the walk key, and would ask)
		kp_js(C, ui, "btn(row('Whisper'),'Ctrl+Shift+E').click();setTimeout(function(){press('keydown','Shift','ShiftLeft',{shift:1});press('keyup','Shift','ShiftLeft');setTimeout(function(){report('sent');},200);},200);")
		sleep(5)
		kp_check("Shift alone, let go: Whisper on Shift", kp_on(P, "whisper", "Shift") && !kp_on(P, "whisper", "CtrlShiftE"))
		// Search, mode
		got = kp_js(C, ui, "var i=document.querySelector('.Input__input');i.value='pocket';i.dispatchEvent(new Event('input',{bubbles:true}));setTimeout(function(){report(document.querySelectorAll('tr.candystripe').length+'');},300);")
		kp_check("search \"pocket\": the two pocket rows", got == "2", got)
		kp_shot("popup_kbpanel_search")
		kp_js(C, ui, "var i=document.querySelector('.Input__input');i.value='';i.dispatchEvent(new Event('input',{bubbles:true}));btn(document.body,'Classic').click();setTimeout(function(){report('sent');},300);")
		sleep(5)
		kp_check("Classic picked", !P.hotkeys)
		kp_js(C, ui, "btn(document.body,'Hotkey').click();setTimeout(function(){report('sent');},300);")
		sleep(5)
		kp_check("Hotkey picked again", P.hotkeys)
		// The capture mustn't leak to the game: nothing reached keyDown() while it ran
		SStgui.close_uis(C.keybind_menu)

	// The same panel in Character Setup
	P.current_tab = 3
	P.ShowChoices(C.mob)
	sleep(40)
	var/datum/tgui/prefs_ui = SStgui.get_open_ui(C.mob, P, "main")
	kp_check("Character Setup opened", !!prefs_ui)
	if(prefs_ui)
		var/got = kp_js(C, prefs_ui, "report(row('Radio (;)')?'radio row':'no radio row');")
		kp_check("its Keybindings tab has the panel", got == "radio row", got)
		kp_shot("popup_kbpanel_setup")
		kp_js(C, prefs_ui, "plus(row('Whisper')) ? plus(row('Whisper')).click() : 0;setTimeout(function(){press('keydown','j','KeyJ');setTimeout(function(){report('sent');},200);},200);")
		sleep(5)
		kp_check("binding from Character Setup: Whisper gets J", kp_on(P, "whisper", "J"))
		SStgui.close_uis(P)
	kc_log("[GLOB.kp_fail ? "WRONG" : "ok   "] [GLOB.kp_pass] passed, [GLOB.kp_fail] wrong")
	text2file("done", "data/keycheck_shots_done")
	sleep(10)
	text2file("done", "data/keycheck.txt") //run.sh waits for a line that starts with it

/proc/kp_macro_names(client/C)
	var/list/names = list()
	for(var/id in C.talk_macro_ids)
		names += "[winget(C, id, "name")]=[winget(C, id, "command")]"
	return names.Join(" ")

/proc/kp_has_macros(client/C, list/keys)
	var/list/names = list()
	for(var/id in C.talk_macro_ids)
		names += uppertext(winget(C, id, "name"))
	for(var/k in keys)
		if(!(uppertext(k) in names))
			return FALSE
	return TRUE
